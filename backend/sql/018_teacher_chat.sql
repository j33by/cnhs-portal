-- Run after 017. Safe to run more than once.
-- Teachers get Room + Messages too:
--   * Room: any section a teacher advises or teaches a subject in (already allowed by 017).
--   * Messages > Group: one "staff" chat per section, readable ONLY by that section's adviser and subject teachers (students never see it).
--   * Messages > Private: teacher to teacher, between teachers who share at least one section.
-- Student chats are unchanged (students only). Teachers still cannot read any student chat.

-- sections a given teacher advises or teaches in
create or replace function teacher_section_ids(p_uid uuid) returns setof uuid language sql stable security definer set search_path = public as $$
  select id from sections where adviser_id = p_uid
  union select section_id from section_subjects where teacher_id = p_uid
$$;
revoke all on function teacher_section_ids(uuid) from public, anon, authenticated;

create or replace function teachers_share_section(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from teacher_section_ids(a) x join teacher_section_ids(b) y on x = y)
$$;
revoke all on function teachers_share_section(uuid, uuid) from public, anon, authenticated;

-- allow the new kind
do $$
declare c record;
begin
  for c in select conname from pg_constraint where conrelid = 'chat_threads'::regclass and contype = 'c' loop
    execute format('alter table chat_threads drop constraint %I', c.conname);
  end loop;
  alter table chat_threads add constraint chat_threads_kind_check check (kind in ('group', 'private', 'staff'));
  alter table chat_threads add constraint chat_threads_shape_check check (
        (kind = 'group'   and section_id is not null and user_a is null and user_b is null)
     or (kind = 'staff'   and section_id is not null and user_a is null and user_b is null)
     or (kind = 'private' and user_a is not null and user_b is not null and user_a < user_b));
end $$;
create unique index if not exists chat_staff_one on chat_threads (section_id) where kind = 'staff';

-- threads I may open (students as before + teachers)
create or replace function my_chat_thread_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select t.id from chat_threads t join students me on me.id = auth.uid() and me.section_id is not null
  where (t.kind = 'group' and t.section_id = me.section_id)
     or (t.kind = 'private' and auth.uid() in (t.user_a, t.user_b)
         and exists (select 1 from students o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end and o.section_id = me.section_id))
  union
  select t.id from chat_threads t
  where exists (select 1 from teachers me where me.id = auth.uid())
    and ((t.kind = 'staff' and t.section_id in (select teacher_section_ids(auth.uid())))
      or (t.kind = 'private' and auth.uid() in (t.user_a, t.user_b)
          and exists (select 1 from teachers o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end)
          and teachers_share_section(auth.uid(), case when t.user_a = auth.uid() then t.user_b else t.user_a end)))
$$;

-- Teacher directory for Messages: colleagues who share a section with me + my sections (each is a staff group chat)
create or replace function staff_directory() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from teachers where id = auth.uid()) then return jsonb_build_object('people', '[]'::jsonb, 'sections', '[]'::jsonb); end if;
  return jsonb_build_object(
    'people', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'first_name', t.first_name, 'last_name', t.last_name, 'photo_url', p.photo_url) order by t.last_name, t.first_name)
                        from teachers t left join profiles p on p.id = t.id
                        where t.id <> auth.uid() and teachers_share_section(auth.uid(), t.id)), '[]'::jsonb),
    'sections', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'grade_level', s.grade_level, 'name', s.name, 'adviser', s.adviser_id = auth.uid(),
                                  'members', (select count(distinct x) from (select s.adviser_id x union all select teacher_id from section_subjects where section_id = s.id) q where x is not null))
                                  order by s.grade_level, s.name)
                          from sections s where s.id in (select teacher_section_ids(auth.uid()))), '[]'::jsonb));
end $$;
grant execute on function staff_directory() to authenticated;
notify pgrst, 'reload schema';
