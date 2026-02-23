# =====================================================================
# APV — MONOREPO SCAFFOLD GENERATOR v1 (FIXED: StrictMode-safe)
# - Writes apps/web (Next.js) + apps/api (Node worker) + supabase migration + docs
# - Avoids interactive fragments; this is the SINGLE SOURCE OF TRUTH runner.
# - Uses single-quoted here-strings for TSX/JS/JSON to prevent $ expansion.
# - UTF-8 no BOM + LF
# - PS 5.1, StrictMode Latest
# =====================================================================

param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ return }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  Ensure-Dir $dir
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ Die ("MISSING_FILE: " + $Path) }
  $tokens=$null; $errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if($errors -and $errors.Count -gt 0){
    $m = ($errors | ForEach-Object { $_.ToString() }) -join "`n"
    Die ("PARSE_FAIL: " + $Path + "`n" + $m)
  }
}

# --- Resolve RepoRoot ---
if(-not (Test-Path -LiteralPath $RepoRoot -PathType Container)){ Die ("Missing RepoRoot: " + $RepoRoot) }
$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location -LiteralPath $RepoRootAbs

Write-Output "APV_MONOREPO_SCAFFOLD_V1_START"
Write-Output ("REPO_ROOT=" + $RepoRootAbs)

# -------------------------------
# Ensure dirs
# -------------------------------
$dirs = @(
  "apps\web",
  "apps\api\src",
  "apps\web\src\app\projects\[id]",
  "apps\web\src\lib",
  "supabase\migrations",
  "docs"
)
foreach($d in $dirs){ Ensure-Dir (Join-Path $RepoRootAbs $d) }

# -------------------------------
# docs/PRODUCT_SPEC_v1.md
# -------------------------------
$ProductSpec = @'
# APV Product Surface v1 (Monorepo)

## What APV is (product layer)
APV is a model-agnostic evidence verification application.

- Inputs: Packet Constitution v1 / HashCanon v1 Option-A directory packets
- Outputs: deterministic verification_result.json + append-only receipts
- Guarantees: verifier is the authority; UI/API never invents truth

APV UI/API is a Tier-1 surface on top of the Tier-0 verifier nucleus.

## Tier boundaries
- Tier-0 nucleus (already shipped in repo root):
  - scripts/apv_verify_v1.ps1
  - scripts/_selftest_apv_v1.ps1
  - scripts/_RUN_apv_tier0_evidence_v1.ps1

- Tier-1 product surface (this scaffold):
  - apps/web  : Next.js UI (Supabase auth + storage + DB)
  - apps/api  : Node API/worker that runs the verifier and writes results back
  - supabase/ : migrations for app tables + RLS

## Model-agnostic contract
APV never couples to PIE or any one model provider.
Any model/tool is supported if it can produce a PCv1 Option-A packet.

## Minimal data model
- projects: owned by auth user
- runs: owned by auth user; references project

## Execution model (target)
1) UI uploads packet evidence to Supabase Storage
2) UI creates run row (status=queued)
3) Worker claims queued run
4) Worker downloads packet dir, runs verifier, uploads outputs
5) UI shows verdict + receipts

## Next steps
- Implement folder-prefix packet ingestion (download prefix -> local dir -> verify)
- Add run timeline + receipt viewer UI
- Add Figma Make pass later for visual polish
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "docs\PRODUCT_SPEC_v1.md") $ProductSpec

# -------------------------------
# supabase/migrations/0001_apv_app_core.sql
# -------------------------------
$Mig = @'
begin;

create extension if not exists pgcrypto;
create schema if not exists apv;

create table if not exists apv.projects (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid(),
  title text not null,
  is_active boolean not null default true
);

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace
                 where n.nspname='apv' and t.typname='run_status') then
    create type apv.run_status as enum ('queued','running','succeeded','failed');
  end if;
end $$;

create table if not exists apv.runs (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid not null default auth.uid(),

  project_id uuid not null references apv.projects(id) on delete cascade,
  status apv.run_status not null default 'queued',

  evidence_object_path text not null,
  output_object_prefix text not null,

  verdict text null,
  reason_tokens text[] not null default '{}'::text[],
  verifier_version text null,

  claimed_at timestamptz null,
  finished_at timestamptz null,
  worker_host text null
);

create index if not exists apv_runs_project_created_at on apv.runs(project_id, created_at desc);

alter table apv.projects enable row level security;
alter table apv.runs enable row level security;

drop policy if exists apv_projects_owner_select on apv.projects;
create policy apv_projects_owner_select
on apv.projects for select
to authenticated
using (created_by = auth.uid());

drop policy if exists apv_projects_owner_insert on apv.projects;
create policy apv_projects_owner_insert
on apv.projects for insert
to authenticated
with check (created_by = auth.uid());

drop policy if exists apv_projects_owner_update on apv.projects;
create policy apv_projects_owner_update
on apv.projects for update
to authenticated
using (created_by = auth.uid())
with check (created_by = auth.uid());

drop policy if exists apv_projects_owner_delete on apv.projects;
create policy apv_projects_owner_delete
on apv.projects for delete
to authenticated
using (created_by = auth.uid());

drop policy if exists apv_runs_owner_select on apv.runs;
create policy apv_runs_owner_select
on apv.runs for select
to authenticated
using (created_by = auth.uid());

drop policy if exists apv_runs_owner_insert on apv.runs;
create policy apv_runs_owner_insert
on apv.runs for insert
to authenticated
with check (
  created_by = auth.uid()
  and exists(select 1 from apv.projects p where p.id = project_id and p.created_by = auth.uid())
);

drop policy if exists apv_runs_owner_update on apv.runs;
create policy apv_runs_owner_update
on apv.runs for update
to authenticated
using (created_by = auth.uid())
with check (created_by = auth.uid());

drop policy if exists apv_runs_owner_delete on apv.runs;
create policy apv_runs_owner_delete
on apv.runs for delete
to authenticated
using (created_by = auth.uid());

-- Storage bucket (private)
insert into storage.buckets (id, name, public)
values ('apv', 'apv', false)
on conflict (id) do nothing;

drop policy if exists "apv bucket owner read" on storage.objects;
create policy "apv bucket owner read"
on storage.objects for select
to authenticated
using (
  bucket_id = 'apv'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "apv bucket owner write" on storage.objects;
create policy "apv bucket owner write"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'apv'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "apv bucket owner update" on storage.objects;
create policy "apv bucket owner update"
on storage.objects for update
to authenticated
using (
  bucket_id = 'apv'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
)
with check (
  bucket_id = 'apv'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "apv bucket owner delete" on storage.objects;
create policy "apv bucket owner delete"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'apv'
  and (storage.foldername(name))[1] = 'users'
  and (storage.foldername(name))[2] = auth.uid()::text
);

commit;
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "supabase\migrations\0001_apv_app_core.sql") $Mig

# -------------------------------
# apps/api
# -------------------------------
$ApiPkg = @'
{
  "name": "apv-api",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "node src/server.js",
    "worker": "node src/worker.js"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.4",
    "express": "^4.19.2"
  }
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\api\package.json") $ApiPkg

$ApiReadme = @'
# APV API/Worker

## Env vars (server-only)
- SUPABASE_URL
- SUPABASE_SERVICE_ROLE_KEY

Optional:
- APV_REPO_ROOT (defaults to repo root)
- APV_WORKER_HOST (defaults to hostname)
- APV_POWERSHELL_EXE (defaults to powershell.exe)

## Run
npm install
npm run dev
npm run worker
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\api\README.md") $ApiReadme

$ApiServer = @'
import express from "express";
import { createClient } from "@supabase/supabase-js";

function die(m){ throw new Error(m); }

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if(!SUPABASE_URL) die("MISSING_ENV: SUPABASE_URL");
if(!SUPABASE_SERVICE_ROLE_KEY) die("MISSING_ENV: SUPABASE_SERVICE_ROLE_KEY");

const supa = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false }
});

const app = express();
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req,res) => res.json({ ok: true }));

app.post("/runs/:id/enqueue", async (req,res) => {
  const id = req.params.id;
  const { data, error } = await supa
    .from("apv.runs")
    .update({ status: "queued" })
    .eq("id", id)
    .select("id,status")
    .maybeSingle();

  if(error) return res.status(500).json({ ok:false, error: error.message });
  if(!data) return res.status(404).json({ ok:false, error: "NOT_FOUND" });
  return res.json({ ok:true, run: data });
});

const port = process.env.PORT ? parseInt(process.env.PORT,10) : 8787;
app.listen(port, () => {
  console.log(`APV_API_OK listening on :${port}`);
});
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\api\src\server.js") $ApiServer

$ApiWorker = @'
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
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\api\src\worker.js") $ApiWorker

# -------------------------------
# apps/web (Next.js)
# -------------------------------
$WebPkg = @'
{
  "name": "apv-web",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev -p 3000",
    "build": "next build",
    "start": "next start -p 3000"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.45.4",
    "next": "14.2.5",
    "react": "18.3.1",
    "react-dom": "18.3.1"
  }
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\package.json") $WebPkg

$WebNextConfig = @'
/** @type {import("next").NextConfig} */
const nextConfig = {
  reactStrictMode: true
};
module.exports = nextConfig;
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\next.config.js") $WebNextConfig

$WebTsConfig = @'
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom","dom.iterable","es2022"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true
  },
  "include": ["next-env.d.ts","**/*.ts","**/*.tsx"],
  "exclude": ["node_modules"]
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\tsconfig.json") $WebTsConfig

$WebNextEnv = @'
/// <reference types="next" />
/// <reference types="next/image-types/global" />
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\next-env.d.ts") $WebNextEnv

$WebLibSupabase = @'
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(url, anon, {
  auth: { persistSession: true }
});
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\src\lib\supabase.ts") $WebLibSupabase

$WebLayout = @'
export const metadata = {
  title: "APV",
  description: "AI Provenance Verifier — UI"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "ui-sans-serif, system-ui", margin: 0, padding: 0 }}>
        <div style={{ padding: 16, borderBottom: "1px solid #333" }}>
          <b>APV</b> <span style={{ opacity: 0.7 }}>Tier-1 UI scaffold</span>
        </div>
        <div style={{ padding: 16 }}>
          {children}
        </div>
      </body>
    </html>
  );
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\src\app\layout.tsx") $WebLayout

$WebHome = @'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "../lib/supabase";

export default function HomePage(){
  const [email,setEmail] = useState("");
  const [pw,setPw] = useState("");
  const [msg,setMsg] = useState<string | null>(null);
  const [user,setUser] = useState<any>(null);

  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => setUser(data.user ?? null));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setUser(s?.user ?? null));
    return () => { sub.subscription.unsubscribe(); };
  }, []);

  async function signIn(){
    setMsg(null);
    const { error } = await supabase.auth.signInWithPassword({ email, password: pw });
    if(error) setMsg(error.message);
  }

  async function signUp(){
    setMsg(null);
    const { error } = await supabase.auth.signUp({ email, password: pw });
    if(error) setMsg(error.message);
    else setMsg("Sign-up OK. If email confirmations are enabled, check inbox.");
  }

  async function signOut(){
    await supabase.auth.signOut();
  }

  return (
    <div style={{ maxWidth: 640 }}>
      {!user ? (
        <>
          <h2>Login</h2>
          <div style={{ display: "grid", gap: 8 }}>
            <input placeholder="email" value={email} onChange={e=>setEmail(e.target.value)} />
            <input placeholder="password" type="password" value={pw} onChange={e=>setPw(e.target.value)} />
            <div style={{ display: "flex", gap: 8 }}>
              <button onClick={signIn}>Sign In</button>
              <button onClick={signUp}>Sign Up</button>
            </div>
            {msg ? <div style={{ color: "tomato" }}>{msg}</div> : null}
          </div>
          <p style={{ opacity: 0.7, marginTop: 16 }}>
            Next: build Projects/Runs screens + upload.
          </p>
        </>
      ) : (
        <>
          <h2>Signed in</h2>
          <div style={{ opacity: 0.8 }}>uid: {user.id}</div>
          <div style={{ marginTop: 12 }}>
            <a href="/projects">Go to Projects</a>
          </div>
          <div style={{ marginTop: 12 }}>
            <button onClick={signOut}>Sign Out</button>
          </div>
        </>
      )}
    </div>
  );
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\src\app\page.tsx") $WebHome

$WebProjects = @'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../lib/supabase";

type Project = { id: string; title: string; created_at: string };

export default function ProjectsPage(){
  const [projects,setProjects] = useState<Project[]>([]);
  const [title,setTitle] = useState("");
  const [msg,setMsg] = useState<string | null>(null);

  async function refresh(){
    setMsg(null);
    const { data, error } = await supabase
      .from("apv.projects")
      .select("id,title,created_at")
      .order("created_at", { ascending: false });

    if(error){ setMsg(error.message); return; }
    setProjects((data ?? []) as any);
  }

  useEffect(() => { refresh(); }, []);

  async function create(){
    setMsg(null);
    if(!title.trim()){ setMsg("Title required"); return; }
    const { error } = await supabase.from("apv.projects").insert({ title });
    if(error){ setMsg(error.message); return; }
    setTitle("");
    await refresh();
  }

  return (
    <div style={{ maxWidth: 720 }}>
      <h2>Projects</h2>
      <div style={{ display: "flex", gap: 8, marginBottom: 12 }}>
        <input placeholder="New project title" value={title} onChange={e=>setTitle(e.target.value)} style={{ flex: 1 }} />
        <button onClick={create}>Create</button>
      </div>
      {msg ? <div style={{ color: "tomato" }}>{msg}</div> : null}
      <ul>
        {projects.map(p => (
          <li key={p.id}>
            <a href={`/projects/${p.id}`}>{p.title}</a>{" "}
            <span style={{ opacity: 0.7 }}>({new Date(p.created_at).toLocaleString()})</span>
          </li>
        ))}
      </ul>
      <p style={{ opacity: 0.7 }}>
        Runs/upload UI comes next (Tier-1 step 2).
      </p>
    </div>
  );
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\src\app\projects\page.tsx") $WebProjects

$WebProjectDetail = @'
"use client";

import { useEffect, useState } from "react";
import { supabase } from "../../../lib/supabase";

type Run = { id: string; created_at: string; status: string; verdict: string | null };

export default function ProjectDetail({ params }: { params: { id: string } }){
  const projectId = params.id;
  const [runs,setRuns] = useState<Run[]>([]);
  const [msg,setMsg] = useState<string | null>(null);

  async function refresh(){
    setMsg(null);
    const { data, error } = await supabase
      .from("apv.runs")
      .select("id,created_at,status,verdict")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false });

    if(error){ setMsg(error.message); return; }
    setRuns((data ?? []) as any);
  }

  useEffect(() => { refresh(); }, []);

  return (
    <div style={{ maxWidth: 720 }}>
      <h2>Project</h2>
      <div style={{ opacity: 0.7 }}>id: {projectId}</div>
      {msg ? <div style={{ color: "tomato", marginTop: 12 }}>{msg}</div> : null}

      <h3 style={{ marginTop: 16 }}>Runs</h3>
      <ul>
        {runs.map(r => (
          <li key={r.id}>
            <b>{r.status}</b> {r.verdict ? <span>({r.verdict})</span> : null}{" "}
            <span style={{ opacity: 0.7 }}>{new Date(r.created_at).toLocaleString()}</span>
          </li>
        ))}
      </ul>

      <p style={{ opacity: 0.7 }}>
        Upload + enqueue + worker execution is next.
      </p>
    </div>
  );
}
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\src\app\projects\[id]\page.tsx") $WebProjectDetail

$WebReadme = @'
# APV Web

## Env vars (client)
Create apps/web/.env.local:

NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...

## Run
npm install
npm run dev
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "apps\web\README.md") $WebReadme

# -------------------------------
# scripts/_RUN_apv_local_stack_v1.ps1 (placeholder)
# -------------------------------
$LocalRunner = @'
param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
Write-Output "APV_LOCAL_STACK_V1_START"
Write-Output ("REPO_ROOT=" + $RepoRootAbs)
Write-Output "TODO: wire Supabase local + run upload + worker verify."
Write-Output "APV_LOCAL_STACK_V1_OK"
'@
Write-Utf8NoBomLf (Join-Path $RepoRootAbs "scripts\_RUN_apv_local_stack_v1.ps1") $LocalRunner
Parse-GateFile (Join-Path $RepoRootAbs "scripts\_RUN_apv_local_stack_v1.ps1")

Write-Output "APV_MONOREPO_SCAFFOLD_V1_OK"