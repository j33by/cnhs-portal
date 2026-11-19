-- READ-ONLY check (safe to run any time). Lists every table, column, view and function the app needs that is missing in your
-- Supabase project and which file creates it. One row "OK" = everything is in place.
-- It also asks Supabase to reload its API schema, which fixes  "Could not find the table 'public.xxx' in the schema cache".
with need(kind, name, fix) as (values
  ('table','profiles','001'),('table','school_years','001'),('table','id_counters','001'),('table','teachers','001'),('table','sections','001'),
  ('table','students','001'),('table','subjects','001'),('table','section_subjects','001'),('table','schedules','001'),('table','attendance','001'),
  ('table','daily_attendance','001'),('table','grades','001'),('table','announcements','001'),('table','parent_links','001'),('table','notifications','001'),
  ('table','usb_sync_state','001'),
  ('table','device_people','003'),('table','class_policy','003'),('table','class_attendance','003'),('table','record_columns','003'),('table','record_scores','003'),
  ('table','teacher_subjects','004'),('table','class_reminders_sent','008'),('table','class_cancellations','009'),('table','sync_closures','009'),
  ('table','sync_ops','010'),('table','posts','011'),('table','post_targets','011'),('table','post_reactions','011'),('table','post_comments','011'),
  ('table','student_subjects','012'),('table','chat_threads','016'),('table','chat_messages','016'),('table','chat_reads','016'),('table','room_voice','017'),
  ('view','teacher_names','004'),('view','kid_photos','009'),
  ('function','next_id_seq','002'),('function','my_role','001'),('function','my_kids','001'),('function','my_section_ids','011'),('function','room_roster','016'),('function','room_view_sections','017'),('function','staff_directory','018'),('function','teacher_section_ids','018'),
  ('column','posts.kinds','016'),('column','posts.section_post_of','016'),('column','profiles.contact_no','005'),('column','teachers.alert_minutes','008'),
  ('column','parent_links.student_name','007'),('column','parent_links.student_no','007'),('column','parent_links.parent_name','007'),('column','parent_links.parent_email','007'),
  ('column','daily_attendance.source','003'),('column','daily_attendance.marked_by','003'),('column','class_attendance.source','009'),('column','record_scores.updated_at','010'),
  ('enum','att_status.N','009'),
  ('realtime','student_subjects','012'),('realtime','chat_messages','016'),('realtime','room_voice','017'),('realtime','daily_attendance','001'),('realtime','attendance','001'),('realtime','schedules','001'),('realtime','students','001'),
  ('realtime','sections','001'),('realtime','section_subjects','007'),('realtime','notifications','001'),('realtime','class_attendance','003'),('realtime','posts','011'),
  ('realtime','class_cancellations','009'),('realtime','usb_sync_state','003'),('realtime','device_people','003')
), missing as (
  select kind, name, fix from need n where not case kind
    when 'table'    then exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = n.name and table_type = 'BASE TABLE')
    when 'view'     then exists (select 1 from information_schema.views  where table_schema = 'public' and table_name = n.name)
    when 'function' then exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and p.proname = n.name)
    when 'column'   then exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = split_part(n.name, '.', 1) and column_name = split_part(n.name, '.', 2))
    when 'enum'     then exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = split_part(n.name, '.', 1) and e.enumlabel = split_part(n.name, '.', 2))
    when 'realtime' then exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = n.name)
  end)
select 'MISSING ' || kind || ': ' || name as problem, 'run ' || fix || '_*.sql' as fix from missing
union all
select 'OK - nothing missing', '' where not exists (select 1 from missing)
order by 1;

notify pgrst, 'reload schema';
