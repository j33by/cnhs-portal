-- Run after 011. Safe to run more than once.
-- A student who picks subjects when enrolling is placed in the section that covers most of them.
-- Picks that belong to ANOTHER section are kept here, so that subject teacher sees the student in their class list
-- (attendance, scores, grades) and the student sees that class in their schedule.
create table if not exists student_subjects (
  student_id uuid not null references students(id) on delete cascade,
  section_id uuid not null references sections(id) on delete cascade,
  subject_id uuid not null references subjects(id),
  created_at timestamptz not null default now(),
  primary key (student_id, section_id, subject_id)
);
create index if not exists student_subjects_class_idx on student_subjects (section_id, subject_id);
alter table student_subjects enable row level security;
drop policy if exists sts_read on student_subjects;
create policy sts_read on student_subjects for select using (student_id = auth.uid() or my_role() = 'teacher' or student_id in (select my_kids()));
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'student_subjects') then
    alter publication supabase_realtime add table public.student_subjects;
  end if;
end $$;
