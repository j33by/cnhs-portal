-- Run after 001 and 002. Adds: class records, subject attendance + absence policy, homeroom manual attendance,
-- device-ID registry (people already on the terminal), and closes a few security gaps.

-- Homeroom attendance can be biometric OR marked by the adviser
alter table daily_attendance add column if not exists source text not null default 'biometric';
alter table daily_attendance add column if not exists marked_by uuid;
alter table daily_attendance add column if not exists updated_at timestamptz default now();

-- People that already exist on the fingerprint terminal (read from Employee_Form.xls / logs).
-- Their device IDs are never reused for new students; a teacher links each one to a student or teacher.
create table device_people (
  biometric_id int primary key, name text, dept_no int, last_seen timestamptz default now()
);

create table class_policy (
  section_id uuid references sections(id) on delete cascade, subject_id uuid references subjects(id),
  school_year_id int references school_years(id),
  free_absences int not null default 10 check (free_absences between 1 and 100),
  apply_to_record boolean not null default false, updated_by uuid,
  primary key (section_id, subject_id, school_year_id)
);
create table class_attendance (
  student_id uuid references students(id) on delete cascade, section_id uuid references sections(id),
  subject_id uuid references subjects(id), school_year_id int references school_years(id),
  att_date date not null, status att_status not null, remarks text, marked_by uuid, updated_at timestamptz default now(),
  primary key (student_id, subject_id, att_date)
);
create index on class_attendance (section_id, subject_id, att_date);

create table record_columns (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references sections(id) on delete cascade, subject_id uuid not null references subjects(id),
  school_year_id int references school_years(id), term int not null check (term between 1 and 4),
  title text not null, col_date date not null,
  max_score numeric(7,2) not null check (max_score > 0 and max_score <= 1000),
  weight numeric(5,2) not null default 1 check (weight > 0 and weight <= 10),
  created_by uuid, is_deleted boolean not null default false, created_at timestamptz default now()
);
create index on record_columns (section_id, subject_id, school_year_id, term);
create table record_scores (
  column_id uuid references record_columns(id) on delete cascade, student_id uuid references students(id) on delete cascade,
  score numeric(7,2) not null check (score >= 0), primary key (column_id, student_id)
);

-- Names only (no birthdate/address/contact) for students & parents to see who teaches them
create view teacher_names as select id, first_name, last_name, subjects from teachers;
grant select on teacher_names to authenticated;
drop policy teach_read on teachers;
create policy teach_read on teachers for select using (id = auth.uid() or my_role() = 'teacher');

-- Tables created earlier without RLS were readable through the public API; lock them
alter table id_counters enable row level security;                       -- no policy = nobody but the server
alter table school_years enable row level security;
create policy sy_read on school_years for select using (auth.uid() is not null);
alter table usb_sync_state enable row level security;
create policy usb_read on usb_sync_state for select using (my_role() = 'teacher');
alter table device_people enable row level security;
create policy dev_read on device_people for select using (my_role() = 'teacher');
alter table class_policy enable row level security;
create policy cp_read on class_policy for select using (my_role() = 'teacher');
alter table class_attendance enable row level security;
create policy ca_read on class_attendance for select using (my_role() = 'teacher' or student_id = auth.uid() or student_id in (select my_kids()));
alter table record_columns enable row level security;
create policy rc_read on record_columns for select using (my_role() = 'teacher');
alter table record_scores enable row level security;
create policy rs_read on record_scores for select using (my_role() = 'teacher');

alter publication supabase_realtime add table usb_sync_state, device_people, class_policy, class_attendance, record_columns, record_scores;
