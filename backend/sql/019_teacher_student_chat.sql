-- Run after 018. Safe to run more than once.
-- Teachers and students can message each other privately: a teacher with the students of any section he advises or teaches,
-- and a student with the adviser / subject teachers of his own section. Nobody else can read these chats.
-- (The student group chat stays students-only and the teachers' group chat stays teachers-only.)

create or replace function my_chat_thread_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  -- students
  select t.id from chat_threads t join students me on me.id = auth.uid() and me.section_id is not null
  where (t.kind = 'group' and t.section_id = me.section_id)
     or (t.kind = 'private' and auth.uid() in (t.user_a, t.user_b) and (
           exists (select 1 from students o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end and o.section_id = me.section_id)
        or me.section_id in (select teacher_section_ids(case when t.user_a = auth.uid() then t.user_b else t.user_a end))))        -- a teacher of my section
  union
  -- teachers
  select t.id from chat_threads t
  where exists (select 1 from teachers me where me.id = auth.uid())
    and ((t.kind = 'staff' and t.section_id in (select teacher_section_ids(auth.uid())))
      or (t.kind = 'private' and auth.uid() in (t.user_a, t.user_b) and (
            (exists (select 1 from teachers o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end)
               and teachers_share_section(auth.uid(), case when t.user_a = auth.uid() then t.user_b else t.user_a end))
         or exists (select 1 from students o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end
               and o.section_id in (select teacher_section_ids(auth.uid()))))))
$$;

-- Teacher directory: colleagues + students of my sections + my sections
create or replace function staff_directory() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from teachers where id = auth.uid()) then return jsonb_build_object('people', '[]'::jsonb, 'students', '[]'::jsonb, 'sections', '[]'::jsonb); end if;
  return jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'first_name', t.first_name, 'last_name', t.last_name, 'photo_url', p.photo_url) order by t.last_name, t.first_name)
                        from teachers t left join profiles p on p.id = t.id
                        where t.id <> auth.uid() and teachers_share_section(auth.uid(), t.id)), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', st.id, 'first_name', st.first_name, 'last_name', st.last_name, 'photo_url', p.photo_url, 'section_id', st.section_id)
                                           order by st.last_name, st.first_name)
                          from students st left join profiles p on p.id = st.id
                          where st.status = 'enrolled' and st.section_id in (select teacher_section_ids(auth.uid()))), '[]'::jsonb),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'grade_level', s.grade_level, 'name', s.name, 'adviser', s.adviser_id = auth.uid(),
                                  'members', (select count(distinct x) from (select s.adviser_id x union all select teacher_id from section_subjects where section_id = s.id) q where x is not null))
                                  order by s.grade_level, s.name)
                          from sections s where s.id in (select teacher_section_ids(auth.uid()))), '[]'::jsonb));
end $$;
grant execute on function staff_directory() to authenticated;
notify pgrst, 'reload schema';
