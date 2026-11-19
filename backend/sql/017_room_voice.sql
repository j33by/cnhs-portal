-- Run after 016. Safe to run more than once.
-- Room voice messages: one short voice message (max 30 s) per person per section, posted by students OR teachers of that section.
-- Everyone in the room can play it (students of the section, its adviser and its subject teachers). It disappears after 12 hours.
-- The author can delete it any time; the section's adviser can also delete any (moderation).

-- sections whose Room I may open: my own section (student), sections I advise, sections where I teach a subject
create or replace function room_view_sections() returns setof uuid language sql stable security definer set search_path = public as $$
  select my_room_section_ids()
  union select section_id from section_subjects where teacher_id = auth.uid()
$$;

create table if not exists room_voice (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references sections(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  audio_url text not null,
  duration_ms int not null check (duration_ms between 300 and 31000),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '12 hours',
  unique (section_id, user_id)
);
create index if not exists room_voice_exp_idx on room_voice (expires_at);
alter table room_voice enable row level security;
drop policy if exists rv_read on room_voice;
create policy rv_read on room_voice for select using (expires_at > now() and section_id in (select room_view_sections()));

insert into storage.buckets (id, name, public) values ('room-voice', 'room-voice', true) on conflict (id) do update set public = true;

-- Room roster now also works for teachers: room_roster('<section id>'). Students always get their own section.
drop function if exists room_roster();
create or replace function room_roster(p_section uuid default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sid uuid;
begin
  select section_id into sid from students where id = auth.uid();
  if sid is null then
    sid := p_section;
    if sid is null or sid not in (select room_view_sections()) then sid := null; end if;
  end if;
  if sid is null then return jsonb_build_object('section', null, 'classmates', '[]'::jsonb, 'adviser', null, 'subject_teachers', '[]'::jsonb); end if;
  return jsonb_build_object(
    'section', (select jsonb_build_object('id', s.id, 'grade_level', s.grade_level, 'name', s.name) from sections s where s.id = sid),
    'classmates', coalesce((select jsonb_agg(jsonb_build_object('id', st.id, 'first_name', st.first_name, 'last_name', st.last_name, 'photo_url', p.photo_url)
                                             order by st.last_name, st.first_name)
                            from students st left join profiles p on p.id = st.id where st.section_id = sid and st.status = 'enrolled'), '[]'::jsonb),
    'adviser', (select jsonb_build_object('id', t.id, 'first_name', t.first_name, 'last_name', t.last_name, 'photo_url', p.photo_url)
                from sections s join teachers t on t.id = s.adviser_id left join profiles p on p.id = t.id where s.id = sid),
    'subject_teachers', coalesce((select jsonb_agg(x order by x->>'last_name') from (
        select jsonb_build_object('id', t.id, 'first_name', t.first_name, 'last_name', t.last_name, 'photo_url', p.photo_url,
                                  'subjects', jsonb_agg(sb.name order by sb.name)) x
        from section_subjects ss join teachers t on t.id = ss.teacher_id join subjects sb on sb.id = ss.subject_id left join profiles p on p.id = t.id
        where ss.section_id = sid and t.id is distinct from (select adviser_id from sections where id = sid)
        group by t.id, t.first_name, t.last_name, p.photo_url) q), '[]'::jsonb));
end $$;
grant execute on function room_roster(uuid) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_voice') then
    alter publication supabase_realtime add table public.room_voice;
  end if;
end $$;
notify pgrst, 'reload schema';
