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
