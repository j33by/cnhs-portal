-- Run after 006. Safe to run more than once.

-- 1) Parent requests carry the names, so a parent can see a PENDING request without being allowed to read the student yet
--    (students are only readable once a teacher approves the link) and teachers need no extra lookups.
alter table parent_links add column if not exists student_name text;
alter table parent_links add column if not exists student_no text;
alter table parent_links add column if not exists parent_name text;
alter table parent_links add column if not exists parent_email text;
update parent_links l set student_name = s.first_name || ' ' || s.last_name, student_no = s.student_no
  from students s where s.id = l.student_id and l.student_name is null;
update parent_links l set parent_name = p.full_name, parent_email = p.email
  from profiles p where p.id = l.parent_id and l.parent_name is null;

-- 2) Realtime: every table the apps stream must be in the publication, otherwise lists only load once and never update.
do $$
declare t text;
begin
  foreach t in array array['students','sections','schedules','section_subjects','subjects','teacher_subjects','daily_attendance','attendance',
                           'grades','class_attendance','class_policy','record_columns','record_scores','parent_links','notifications',
                           'announcements','device_people','usb_sync_state'] loop
    if to_regclass('public.' || t) is not null
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
