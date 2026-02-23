/*
  APV Worker (Tier-1 scaffold): folder-prefix ingest
  - Polls apv.runs where status='queued'
  - Downloads all objects under evidence_prefix from Supabase Storage
  - Writes to C:\ProgramData\APV\work\<run_id>\...
  - Appends NDJSON receipts at C:\ProgramData\APV\receipts\apv_worker.ndjson
*/

const os = require("os");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { createClient } = require("@supabase/supabase-js");

function mustEnv(name){
  const v = process.env[name];
  if(!v || !String(v).trim()){
    throw new Error("MISSING_ENV_" + name);
  }
  return v;
}

function ensureDir(p){
  if(!fs.existsSync(p)){
    fs.mkdirSync(p, { recursive: true });
  }
}

function sha256(buf){
  const h = crypto.createHash("sha256");
  h.update(buf);
  return h.digest("hex");
}

function nowIso(){
  return new Date().toISOString();
}

function writeReceipt(obj){
  const root = "C:\\ProgramData\\APV\\receipts";
  ensureDir(root);
  const fp = path.join(root, "apv_worker.ndjson");
  const line = JSON.stringify(obj) + "\n";
  fs.appendFileSync(fp, line, { encoding: "utf8" });
}

async function listAllObjects(storage, bucket, prefix){
  // pagination: Supabase Storage list uses limit/offset
  const out = [];
  let offset = 0;
  const limit = 1000;

  while(true){
    const { data, error } = await storage.from(bucket).list(prefix, { limit, offset });
    if(error) throw new Error("STORAGE_LIST_FAIL: " + error.message);
    const rows = data || [];
    // rows contains objects directly under prefix; if you need deep recursion, we encode hierarchy using prefixes.
    // For Tier-1: we require uploads to be flat under a run prefix OR include subfolders encoded in the object name.
    for(const r of rows){
      if(r && r.name){
        out.push({ name: r.name });
      }
    }
    if(rows.length < limit) break;
    offset += limit;
  }
  return out;
}

async function downloadObject(storage, bucket, objectPath){
  const { data, error } = await storage.from(bucket).download(objectPath);
  if(error) throw new Error("STORAGE_DOWNLOAD_FAIL: " + objectPath + " :: " + error.message);
  const ab = await data.arrayBuffer();
  return Buffer.from(ab);
}

async function main(){
  const SUPABASE_URL = mustEnv("SUPABASE_URL");
  const SERVICE_KEY  = mustEnv("SUPABASE_SERVICE_ROLE_KEY");
  const BUCKET       = process.env.APV_BUCKET || "apv-evidence";

  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const host = os.hostname();
  writeReceipt({ ts: nowIso(), event: "WORKER_START", host });

  while(true){
    // 1) claim one queued run
    const { data: runRows, error: runErr } = await supabase
      .from("apv.runs")
      .select("id, project_id, owner_id, status, evidence_prefix, created_at")
      .eq("status", "queued")
      .order("created_at", { ascending: true })
      .limit(1);

    if(runErr){
      writeReceipt({ ts: nowIso(), event: "POLL_FAIL", error: runErr.message });
      await new Promise(r => setTimeout(r, 2000));
      continue;
    }

    if(!runRows || runRows.length === 0){
      await new Promise(r => setTimeout(r, 1500));
      continue;
    }

    const run = runRows[0];
    const runId = run.id;
    const prefix = run.evidence_prefix || "";
    if(!prefix){
      // Mark failed deterministically if no prefix
      await supabase.from("apv.runs").update({
        status: "failed",
        worker_host: host,
        started_at: nowIso(),
        finished_at: nowIso(),
        verdict: "MISSING_EVIDENCE_PREFIX"
      }).eq("id", runId);

      writeReceipt({ ts: nowIso(), event: "RUN_FAIL", run_id: runId, token: "MISSING_EVIDENCE_PREFIX" });
      continue;
    }

    // attempt to transition to running
    await supabase.from("apv.runs").update({
      status: "running",
      worker_host: host,
      started_at: nowIso()
    }).eq("id", runId);

    writeReceipt({ ts: nowIso(), event: "RUN_CLAIMED", run_id: runId, prefix });

    try{
      const workRoot = path.join("C:\\ProgramData\\APV\\work", String(runId));
      ensureDir(workRoot);

      // list objects under prefix
      const storage = supabase.storage;
      const objs = await listAllObjects(storage, BUCKET, prefix);

      // download each object
      const downloaded = [];
      for(const o of objs){
        const relName = o.name; // name relative to prefix
        const objectPath = prefix.endsWith("/") ? (prefix + relName) : (prefix + "/" + relName);

        const buf = await downloadObject(storage, BUCKET, objectPath);
        const h = sha256(buf);

        const outPath = path.join(workRoot, relName);
        ensureDir(path.dirname(outPath));
        fs.writeFileSync(outPath, buf);

        downloaded.push({ object: objectPath, rel: relName, sha256: h, bytes: buf.length });
      }

      // deterministic manifest of what we fetched
      downloaded.sort((a,b) => a.object.localeCompare(b.object));
      const manifestPath = path.join(workRoot, "ingest_manifest.json");
      fs.writeFileSync(manifestPath, JSON.stringify({ run_id: runId, prefix, files: downloaded }, null, 2) + "\n", { encoding: "utf8" });

      writeReceipt({ ts: nowIso(), event: "INGEST_OK", run_id: runId, file_count: downloaded.length });

      // Placeholder verifier hook: mark "ingested" (verifier wiring comes next)
      await supabase.from("apv.runs").update({
        status: "ingested",
        finished_at: nowIso(),
        verdict: "INGEST_OK"
      }).eq("id", runId);

      writeReceipt({ ts: nowIso(), event: "RUN_DONE", run_id: runId, status: "ingested", verdict: "INGEST_OK" });
    } catch (e){
      const msg = (e && e.message) ? e.message : String(e);
      await supabase.from("apv.runs").update({
        status: "failed",
        finished_at: nowIso(),
        verdict: msg.slice(0, 200)
      }).eq("id", runId);

      writeReceipt({ ts: nowIso(), event: "RUN_FAIL", run_id: runId, token: "INGEST_FAIL", error: msg });
    }
  }
}

main().catch(err => {
  const msg = (err && err.message) ? err.message : String(err);
  try{ writeReceipt({ ts: nowIso(), event: "FATAL", error: msg }); } catch(_){}
  process.stderr.write(msg + "\n");
  process.exit(1);
});
