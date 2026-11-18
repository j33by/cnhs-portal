-- Run after 009. Safe to run more than once.
-- Offline queue support (teacher attendance + scores):
-- 1) every queued change carries a client-made operation id; the server remembers it so a retry can never apply (or notify) twice
create table if not exists sync_ops (
  op_id uuid primary key, user_id uuid not null, kind text not null,
  status text not null default 'processing',          -- processing | done
  result jsonb, created_at timestamptz not null default now()
);
create index if not exists sync_ops_created_idx on sync_ops (created_at);
alter table sync_ops enable row level security;       -- no policy: only the server touches it

-- 2) scores get a version stamp, so an offline edit based on an old value is detected instead of silently overwriting
alter table record_scores add column if not exists updated_at timestamptz not null default now();
