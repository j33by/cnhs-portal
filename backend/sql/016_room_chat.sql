-- Run after 015 (needs 011_feed.sql). Safe to run more than once.
-- Student "Room", "Messages" (private + group chat of a section) and the Section feed.
--
-- WHO CAN SEE WHAT
--   * Chat: ONLY students of that section. Teachers, parents and students of other sections cannot read a single message.
--     A private chat is readable only by its two students, and only while both are still in the same section.
--   * Section posts (written by students in the feed): only the students of that section and the section's adviser.
--     Subject teachers, parents and other sections do not see them.
-- All writes (send, react, delete, upload) go through the API with the service key, like the rest of the app.

-- ---------- sections I belong to for the Room (a student's own section, an adviser's advised sections) ----------
create or replace function my_room_section_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select section_id from students where id = auth.uid() and section_id is not null
  union select id from sections where adviser_id = auth.uid()
$$;

-- ---------- chat ----------
create table if not exists chat_threads (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('group', 'private')),
  section_id uuid references sections(id) on delete cascade,            -- group chat: the section
  user_a uuid references profiles(id) on delete cascade,                -- private chat: the two students, user_a < user_b
  user_b uuid references profiles(id) on delete cascade,
  last_message_at timestamptz not null default now(), last_sender_id uuid, last_preview text not null default '',
  created_at timestamptz not null default now(),
  check ((kind = 'group' and section_id is not null and user_a is null and user_b is null)
      or (kind = 'private' and user_a is not null and user_b is not null and user_a < user_b))
);
create unique index if not exists chat_group_one on chat_threads (section_id) where kind = 'group';
create unique index if not exists chat_private_one on chat_threads (user_a, user_b) where kind = 'private';

create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references chat_threads(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade, sender_name text not null, sender_photo text,
  body text not null default '',
  attachments jsonb not null default '[]',                              -- [{url, name, size, type}]
  reply_to uuid references chat_messages(id) on delete set null, reply_name text, reply_snippet text,
  reactions jsonb not null default '{}',                                -- {"👍": [userId, ...]}  one reaction per person
  deleted boolean not null default false,                               -- "unsent": text and files are removed, the bubble stays as a note
  created_at timestamptz not null default now()
);
create index if not exists chat_messages_thread_idx on chat_messages (thread_id, created_at desc);

create table if not exists chat_reads (
  thread_id uuid not null references chat_threads(id) on delete cascade, user_id uuid not null references profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(), primary key (thread_id, user_id)
);

-- threads I may open: the group chat of my section + private chats where I am one of the two AND the other is still in my section
create or replace function my_chat_thread_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select t.id from chat_threads t join students me on me.id = auth.uid() and me.section_id is not null
  where (t.kind = 'group' and t.section_id = me.section_id)
     or (t.kind = 'private' and auth.uid() in (t.user_a, t.user_b)
         and exists (select 1 from students o where o.id = case when t.user_a = auth.uid() then t.user_b else t.user_a end and o.section_id = me.section_id))
$$;

alter table chat_threads enable row level security;
alter table chat_messages enable row level security;
alter table chat_reads enable row level security;
drop policy if exists ct_read on chat_threads;
create policy ct_read on chat_threads for select using (id in (select my_chat_thread_ids()));
drop policy if exists cm_read on chat_messages;
create policy cm_read on chat_messages for select using (thread_id in (select my_chat_thread_ids()));
drop policy if exists cr_read on chat_reads;
create policy cr_read on chat_reads for select using (user_id = auth.uid());

-- keep the thread list (last message + preview) up to date
create or replace function chat_touch() returns trigger language plpgsql security definer set search_path = public as $$
declare prev text;
begin
  if tg_op = 'INSERT' then
    prev := case when btrim(new.body) <> '' then left(regexp_replace(btrim(new.body), '\s+', ' ', 'g'), 90)
                 when jsonb_array_length(new.attachments) = 1 and (new.attachments->0->>'type') like 'image/%' then 'Photo'
                 when jsonb_array_length(new.attachments) = 1 then 'File: ' || left(coalesce(new.attachments->0->>'name', 'file'), 60)
                 else jsonb_array_length(new.attachments) || ' files' end;
    update chat_threads set last_message_at = new.created_at, last_sender_id = new.sender_id, last_preview = prev where id = new.thread_id;
  elsif new.deleted and not old.deleted then
    update chat_threads set last_preview = 'Message deleted' where id = new.thread_id and last_message_at = new.created_at;
  end if;
  return null;
end $$;
drop trigger if exists chat_touch_ins on chat_messages;
create trigger chat_touch_ins after insert on chat_messages for each row execute function chat_touch();
drop trigger if exists chat_touch_upd on chat_messages;
create trigger chat_touch_upd after update of deleted on chat_messages for each row execute function chat_touch();

-- one reaction per person; same emoji again (or null) removes it. Row-locked, so two taps at once cannot lose a reaction.
create or replace function chat_set_reaction(p_msg uuid, p_user uuid, p_emoji text) returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb; k text; arr jsonb; had boolean := false;
begin
  select reactions into r from chat_messages where id = p_msg and not deleted for update;
  if r is null then return null; end if;
  for k in select jsonb_object_keys(r) loop
    if r->k ? p_user::text then had := had or k = p_emoji; end if;
    arr := coalesce((select jsonb_agg(v) from jsonb_array_elements(r->k) v where (v #>> '{}') <> p_user::text), '[]'::jsonb);
    if jsonb_array_length(arr) = 0 then r := r - k; else r := jsonb_set(r, array[k], arr); end if;
  end loop;
  if p_emoji is not null and not had then r := jsonb_set(r, array[p_emoji], coalesce(r->p_emoji, '[]'::jsonb) || to_jsonb(p_user::text), true); end if;
  update chat_messages set reactions = r where id = p_msg;
  return r;
end $$;
revoke all on function chat_set_reaction(uuid, uuid, text) from public, anon, authenticated;     -- only the API (service key) may call it

-- ---------- Room: classmates (names only) + adviser + subject teachers of MY section ----------
create or replace function room_roster() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare sid uuid;
begin
  select section_id into sid from students where id = auth.uid();
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
        where ss.section_id = sid and t.id is distinct from (select adviser_id from sections where id = sid)      -- the adviser has his own card
        group by t.id, t.first_name, t.last_name, p.photo_url) q), '[]'::jsonb));
end $$;
grant execute on function room_roster() to authenticated;

-- ---------- files sent in chat (public bucket, unguessable file paths; uploaded only through the API) ----------
insert into storage.buckets (id, name, public) values ('chat-files', 'chat-files', true) on conflict (id) do update set public = true;

-- ---------- feed: filters + posts written by students for their own section ----------
alter table posts add column if not exists kinds jsonb not null default '{}';                       -- {sectionId: 'subject'|'homeroom'|'section'|'grade'} for the filters
alter table posts add column if not exists section_post_of uuid references sections(id) on delete cascade;   -- student post: the section that may see it
create index if not exists posts_section_post_idx on posts (section_post_of) where section_post_of is not null;
update posts p set kinds = coalesce((select jsonb_object_agg(t.section_id::text, t.kind) from post_targets t where t.post_id = p.id), '{}'::jsonb)
  where p.kinds = '{}'::jsonb and p.section_post_of is null;

drop policy if exists posts_read on posts;
create policy posts_read on posts for select using (
  author_id = auth.uid()
  or (section_post_of is null and id in (select post_id from post_targets where section_id in (select my_section_ids())))
  or (section_post_of is not null and section_post_of in (select my_room_section_ids()))              -- ONLY the section's students + its adviser
);

do $$
declare t text;
begin
  foreach t in array array['chat_threads', 'chat_messages', 'chat_reads'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
