-- Run after 008. Safe to run more than once.
-- 1) "No class" status for subject attendance (set by the teacher's No-class alert, never counted as an absence)
alter type att_status add value if not exists 'N';
alter table class_attendance add column if not exists source text default 'manual';

-- 2) No-class notices (one row per class + date). Students and parents read them to show "No class" on the schedule.
create table if not exists class_cancellations (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references sections(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  cancel_date date not null,
  reason text, message text,
  label text,                                   -- "Grade 7 · Rizal"
  subject_name text,
  students int default 0,
  applied boolean not null default false,       -- true once every student has a "No class" mark for that date
  created_by uuid references teachers(id), created_at timestamptz default now(),
  unique (section_id, subject_id, cancel_date)
);
create index if not exists cc_date_idx on class_cancellations (cancel_date);
create index if not exists cc_owner_idx on class_cancellations (created_by, created_at desc);
alter table class_cancellations enable row level security;
drop policy if exists cc_read on class_cancellations;
create policy cc_read on class_cancellations for select using (auth.uid() is not null);

-- 3) Auto-absent: after a USB sync, students with no fingerprint punch are marked absent 30 minutes later.
create table if not exists sync_closures (
  att_date date primary key, synced_at timestamptz not null, closed_at timestamptz, absent_marked int default 0
);
alter table sync_closures enable row level security;             -- no policy: only the server touches it

-- 4) A parent may see the profile photo (and nothing else) of an approved child.
create or replace view kid_photos as
  select p.id, p.photo_url from profiles p where p.id in (select my_kids());
grant select on kid_photos to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'class_cancellations') then
    alter publication supabase_realtime add table public.class_cancellations;
  end if;
end $$;
