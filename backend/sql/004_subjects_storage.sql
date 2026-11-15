-- Run after 003. Safe to run more than once.

-- 1) Photo upload "violates row-level security policy (403)": uploads need INSERT, and replacing a file needs SELECT + UPDATE.
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true), ('pictures', 'pictures', true)
  on conflict (id) do update set public = true;
drop policy if exists "own upload" on storage.objects;
drop policy if exists "own update" on storage.objects;
drop policy if exists cnhs_read on storage.objects;
drop policy if exists cnhs_insert on storage.objects;
drop policy if exists cnhs_update on storage.objects;
drop policy if exists cnhs_delete on storage.objects;
create policy cnhs_read   on storage.objects for select to authenticated using (bucket_id in ('avatars', 'pictures'));
create policy cnhs_insert on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars', 'pictures') and (storage.foldername(name))[1] = auth.uid()::text);
create policy cnhs_update on storage.objects for update to authenticated
  using (bucket_id in ('avatars', 'pictures') and (storage.foldername(name))[1] = auth.uid()::text);
create policy cnhs_delete on storage.objects for delete to authenticated
  using (bucket_id in ('avatars', 'pictures') and (storage.foldername(name))[1] = auth.uid()::text);

-- 2) Teacher subjects are typed by the teacher (name + code), max 5 (enforced by the API).
create table if not exists teacher_subjects (
  teacher_id uuid not null references teachers(id) on delete cascade,
  code text not null, name text not null, created_at timestamptz default now(),
  primary key (teacher_id, code)
);
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'teachers' and column_name = 'subjects') then
    insert into teacher_subjects (teacher_id, code, name)
      select t.id, upper(regexp_replace(trim(s), '\s+', '_', 'g')), trim(s) from teachers t, unnest(t.subjects) s
      on conflict do nothing;                                   -- keep anything entered before this change
    drop view if exists teacher_names;
    alter table teachers drop column subjects;
  end if;
end $$;
create or replace view teacher_names as
  select t.id, t.first_name, t.last_name,
         coalesce((select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name) order by s.code) from teacher_subjects s where s.teacher_id = t.id), '[]'::jsonb) as subjects
  from teachers t;
grant select on teacher_names to authenticated;
alter table teacher_subjects enable row level security;
drop policy if exists ts_read on teacher_subjects;
create policy ts_read on teacher_subjects for select using (teacher_id = auth.uid() or my_role() = 'teacher');
