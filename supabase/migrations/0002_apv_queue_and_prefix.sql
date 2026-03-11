-- APV 0002 — queue fields + evidence prefix (folder-prefix ingest)
-- Deterministic SQL: additive, idempotent guards where feasible.

begin;

-- apv.runs additions (if table exists from 0001)
alter table if exists apv.runs
  add column if not exists status text not null default 'queued',
  add column if not exists evidence_prefix text,
  add column if not exists worker_host text,
  add column if not exists started_at timestamptz,
  add column if not exists finished_at timestamptz;

-- Helpful index for worker polling
create index if not exists apv_runs_status_created_at_idx
  on apv.runs (status, created_at desc);

commit;
