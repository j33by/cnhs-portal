-- Run after 010. Safe to run more than once.
-- Feed: teachers post announcements (text + images) to sections / grade levels / subjects / homeroom; students and parents read, react and comment.
-- Post images use the existing public "pictures" bucket (folder = the teacher's user id).

-- Sections the signed-in person belongs to (student: own section; parent: their kids' sections; teacher: sections they teach or advise)
create or replace function my_section_ids() returns setof uuid language sql stable security definer set search_path = public as $$
  select section_id from students where id = auth.uid() and section_id is not null
  union select section_id from students where id in (select my_kids()) and section_id is not null
  union select section_id from section_subjects where teacher_id = auth.uid()
  union select id from sections where adviser_id = auth.uid()
$$;

create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles(id) on delete cascade,
  author_name text not null, author_photo text,
  body text not null default '', category text not null default 'announcement',
  images text[] not null default '{}',
  allow_reactions boolean not null default true, allow_comments boolean not null default true,
  pinned boolean not null default false,
  audience text,                                              -- label shown on the card, e.g. "Grade 7 · Rizal · Math"
  reactions jsonb not null default '{}', reaction_count int not null default 0, comment_count int not null default 0,
  created_at timestamptz not null default now(), edited_at timestamptz
);
create index if not exists posts_created_idx on posts (created_at desc);
create table if not exists post_targets (
  post_id uuid not null references posts(id) on delete cascade,
  section_id uuid not null references sections(id) on delete cascade,
  kind text not null,                                         -- section | grade | subject | homeroom
  primary key (post_id, section_id)
);
create index if not exists post_targets_section_idx on post_targets (section_id);
create table if not exists post_reactions (
  post_id uuid not null references posts(id) on delete cascade, user_id uuid not null references profiles(id) on delete cascade,
  kind text not null, created_at timestamptz not null default now(), primary key (post_id, user_id)
);
create table if not exists post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade, user_id uuid not null references profiles(id) on delete cascade,
  author_name text not null, author_photo text, author_role text,
  body text not null, created_at timestamptz not null default now()
);
create index if not exists post_comments_post_idx on post_comments (post_id, created_at);

alter table posts enable row level security;
alter table post_targets enable row level security;
alter table post_reactions enable row level security;
alter table post_comments enable row level security;
drop policy if exists posts_read on posts;
create policy posts_read on posts for select using (author_id = auth.uid() or id in (select post_id from post_targets where section_id in (select my_section_ids())));
drop policy if exists pt_read on post_targets;
create policy pt_read on post_targets for select using (section_id in (select my_section_ids()));
drop policy if exists pr_read on post_reactions;
create policy pr_read on post_reactions for select using (user_id = auth.uid());
drop policy if exists pc_read on post_comments;
create policy pc_read on post_comments for select using (post_id in (select id from posts));
-- all writes go through the API (service role)

do $$
declare t text;
begin
  foreach t in array array['posts', 'post_reactions', 'post_comments'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
