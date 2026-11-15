-- CNHS Portal v2 - Supabase (Postgres). Run once in the Supabase SQL editor.
create extension if not exists pgcrypto;

create type user_role as enum ('teacher','student','parent');
create type att_status as enum ('P','A','L','E');

create table profiles (               -- one row per Google (Supabase auth) account
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null,
  email text, full_name text not null, photo_url text,
  fcm_token text, onboarded boolean not null default false,
  created_at timestamptz default now()
);

create table school_years (
  id serial primary key, label text unique not null,   -- '2026-2027'
  is_current boolean not null default false
);

create table id_counters (scope text primary key, last_seq int not null default 0, mult int not null, offset_b int not null);

create table teachers (
  id uuid primary key references profiles(id) on delete cascade,
  teacher_no text unique not null,                      -- T-12345
  first_name text not null, last_name text not null, birthdate date, address text, contact_no text,
  subjects text[] not null check (cardinality(subjects) between 1 and 5),
  grade_levels int[] not null check (cardinality(grade_levels) between 1 and 5),
  biometric_id int unique,                              -- ID on the fingerprint device
  created_at timestamptz default now()
);

create table sections (
  id uuid primary key default gen_random_uuid(),
  school_year_id int references school_years(id),
  grade_level int not null, name text not null,
  adviser_id uuid references teachers(id),              -- the advisory teacher
  homeroom text, biometric_dept_no int,                 -- Dept. 1-16 on the device
  grading_term int not null default 1,
  unique (school_year_id, grade_level, name)
);

create table students (
  id uuid primary key references profiles(id) on delete cascade,
  student_no text unique not null,                      -- 202627-48213
  first_name text not null, middle_name text, last_name text not null,
  age int, sex char(1), birthdate date, address text, lrn text,
  grade_level int not null, section_id uuid references sections(id),
  guardian_name text, guardian_contact text,
  biometric_id int unique, status text not null default 'enrolled',
  created_at timestamptz default now()
);

create table subjects (id uuid primary key default gen_random_uuid(), code text unique not null, name text not null);

create table section_subjects (                         -- teacher assigned to a subject in a section
  section_id uuid references sections(id) on delete cascade,
  subject_id uuid references subjects(id), teacher_id uuid references teachers(id),
  primary key (section_id, subject_id)
);

create table schedules (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references sections(id) on delete cascade,
  subject_id uuid references subjects(id), teacher_id uuid references teachers(id),
  day_of_week int not null check (day_of_week between 0 and 6),   -- 0 = Sun
  start_time time not null, end_time time not null, room text,
  shift_no int                                                    -- device shift 1-10
);

create table attendance (                                          -- every raw biometric punch
  id bigserial primary key,
  biometric_id int not null, student_id uuid references students(id), teacher_id uuid references teachers(id),
  punched_at timestamptz not null, device_id int default 1, source text default 'usb',
  unique (biometric_id, punched_at)
);
create table daily_attendance (                                    -- derived per student per day
  student_id uuid references students(id) on delete cascade, att_date date,
  section_id uuid references sections(id), status att_status not null,
  time_in time, time_out time, punches int default 0, remarks text,
  primary key (student_id, att_date)
);

create table grades (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references students(id) on delete cascade, subject_id uuid references subjects(id),
  section_id uuid references sections(id), school_year_id int references school_years(id),
  term int not null check (term between 1 and 4), grade numeric(5,2) not null,
  released boolean not null default false, entered_by uuid references teachers(id),
  updated_at timestamptz default now(), unique (student_id, subject_id, school_year_id, term)
);

create table announcements (
  id uuid primary key default gen_random_uuid(), author_id uuid references teachers(id),
  title text not null, body text not null, section_ids uuid[] default '{}', created_at timestamptz default now()
);

create table parent_links (                                        -- bind requests
  id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references profiles(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references teachers(id), created_at timestamptz default now(), reviewed_at timestamptz,
  unique (parent_id, student_id)
);

create table notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(id) on delete cascade,
  title text not null, body text not null, kind text, data jsonb, read boolean default false, created_at timestamptz default now()
);

create table usb_sync_state (                                      -- does the USB need rewriting?
  id int primary key default 1, dirty boolean default true, version bigint default 0, last_ingest timestamptz
);
insert into usb_sync_state values (1) on conflict do nothing;
insert into school_years(label,is_current) values ('2026-2027',true) on conflict do nothing;

-- Any change that must be written back to the USB marks it dirty (the Windows app then rewrites the .xls)
create or replace function bump_usb() returns trigger language plpgsql as $$
begin update usb_sync_state set dirty=true, version=version+1 where id=1; return null; end $$;
create trigger t_students_usb after insert or update or delete on students for each statement execute function bump_usb();
create trigger t_teachers_usb after insert or update or delete on teachers for each statement execute function bump_usb();
create trigger t_sched_usb after insert or update or delete on schedules for each statement execute function bump_usb();
create trigger t_sections_usb after insert or update or delete on sections for each statement execute function bump_usb();

-- Row Level Security: apps READ directly from Supabase (realtime); every WRITE goes through the Node API (service role).
alter table profiles enable row level security;   alter table teachers enable row level security;
alter table students enable row level security;   alter table sections enable row level security;
alter table attendance enable row level security; alter table daily_attendance enable row level security;
alter table grades enable row level security;     alter table schedules enable row level security;
alter table parent_links enable row level security; alter table notifications enable row level security;
alter table announcements enable row level security; alter table subjects enable row level security;
alter table section_subjects enable row level security;

create or replace function my_role() returns user_role language sql stable security definer as $$ select role from profiles where id=auth.uid() $$;
create or replace function my_kids() returns setof uuid language sql stable security definer as $$
  select student_id from parent_links where parent_id=auth.uid() and status='approved' $$;

create policy prof_self  on profiles   for select using (id=auth.uid() or my_role()='teacher');
create policy teach_read on teachers   for select using (auth.uid() is not null);
create policy stud_read  on students   for select using (id=auth.uid() or my_role()='teacher' or id in (select my_kids()));
create policy sect_read  on sections   for select using (auth.uid() is not null);
create policy subj_read  on subjects   for select using (auth.uid() is not null);
create policy ss_read    on section_subjects for select using (auth.uid() is not null);
create policy sched_read on schedules  for select using (auth.uid() is not null);
create policy ann_read   on announcements for select using (auth.uid() is not null);
create policy att_read   on daily_attendance for select using (student_id=auth.uid() or my_role()='teacher' or student_id in (select my_kids()));
create policy punch_read on attendance for select using (student_id=auth.uid() or my_role()='teacher' or student_id in (select my_kids()));
create policy grade_read on grades     for select using (my_role()='teacher' or (released and (student_id=auth.uid() or student_id in (select my_kids()))));
create policy link_read  on parent_links for select using (parent_id=auth.uid() or my_role()='teacher');
create policy notif_read on notifications for select using (user_id=auth.uid());

-- Realtime
alter publication supabase_realtime add table daily_attendance, attendance, grades, schedules, students, sections, parent_links, notifications, announcements;

-- Storage buckets for profile pictures and other pictures
insert into storage.buckets (id,name,public) values ('avatars','avatars',true),('pictures','pictures',true) on conflict do nothing;
create policy "own upload" on storage.objects for insert to authenticated
  with check (bucket_id in ('avatars','pictures') and (storage.foldername(name))[1]=auth.uid()::text);
create policy "own update" on storage.objects for update to authenticated
  using (bucket_id in ('avatars','pictures') and (storage.foldername(name))[1]=auth.uid()::text);
