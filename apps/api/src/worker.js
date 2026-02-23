import os from "os";
import path from "path";
import fs from "fs";
import { spawn } from "child_process";
import { createClient } from "@supabase/supabase-js";

function die(m){ throw new Error(m); }
function sleep(ms){ return new Promise(r => setTimeout(r, ms)); }

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!SUPABASE_URL) die("MISSING_ENV: SUPABASE_URL");
if(!SUPABASE_SERVICE_ROLE_KEY) die("MISSING_ENV: SUPABASE_SERVICE_ROLE_KEY");

const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

const WORKER_HOST = process.env.APV_WORKER_HOST || os.hostname();
const POWERSHELL = process.env.APV_POWERSHELL_EXE || "powershell.exe";

const defaultRepoRoot = path.resolve(process.cwd(), "..", "..");
const APV_REPO_ROOT = process.env.APV_REPO_ROOT || defaultRepoRoot;

const verifier = path.join(APV_REPO_ROOT, "scripts", "apv_verify_v1.ps1");

function ensureDir(p){
  if(!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

async function claimNextRun(){
  const { data, error } = await supa
    .from("apv.runs")
    .select("id,created_by,project_id,evidence_object_path,output_object_prefix,status")
    .eq("status", "queued")
    .order("created_at", { ascending: true })
    .limit(1);

  if(error) throw new Error(error.message);
  if(!data || data.length === 0) return null;

  const run = data[0];
  const { data: upd, error: updErr } = await supa
    .from("apv.runs")
    .update({ status: "running", claimed_at: new Date().toISOString(), worker_host: WORKER_HOST })
    .eq("id", run.id)
    .eq("status", "queued")
    .select("id,status,created_by,project_id,evidence_object_path,output_object_prefix")
    .maybeSingle();

  if(updErr) throw new Error(updErr.message);
  if(!upd) return null;
  return upd;
}

function runVerifier(packetDir, outDir){
  return new Promise((resolve,reject) => {
    ensureDir(outDir);

    const args = [
      "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
      "-File", verifier,
      "-PacketDir", packetDir,
      "-OutDir", outDir
    ];

    const p = spawn(POWERSHELL, args, { windowsHide: true });
    let stdout = "";
    let stderr = "";
    p.stdout.on("data", d => { stdout += d.toString("utf8"); });
    p.stderr.on("data", d => { stderr += d.toString("utf8"); });

    p.on("close", (code) => resolve({ code, stdout, stderr }));
    p.on("error", (e) => reject(e));
  });
}

async function processRun(run){
  // Tier-1 scaffold v1: execution not wired yet (we add folder-prefix download next).
  // Fail deterministically so UI can show pipeline status.
  await supa.from("apv.runs")
    .update({
      status: "failed",
      finished_at: new Date().toISOString(),
      verdict: "INVALID",
      reason_tokens: ["TIER1_SCAFFOLD_NO_EVIDENCE_INGEST_YET"],
      verifier_version: "apv_verify_v1"
    })
    .eq("id", run.id);
}

async function loop(){
  console.log("APV_WORKER_START");
  console.log("APV_WORKER_REPO_ROOT=" + APV_REPO_ROOT);
  console.log("APV_WORKER_HOST=" + WORKER_HOST);

  if(!fs.existsSync(verifier)){
    throw new Error("MISSING_VERIFIER: " + verifier);
  }

  while(true){
    try{
      const run = await claimNextRun();
      if(!run){
        await sleep(1500);
        continue;
      }
      console.log("CLAIMED_RUN=" + run.id);
      await processRun(run);
    } catch(e){
      console.error("WORKER_LOOP_ERR: " + (e && e.message ? e.message : String(e)));
      await sleep(2000);
    }
  }
}

loop().catch(e => {
  console.error("APV_WORKER_FATAL: " + (e && e.message ? e.message : String(e)));
  process.exit(1);
});
