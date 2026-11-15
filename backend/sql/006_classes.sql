-- Run after 005. Safe to run more than once.
-- Biometric IDs are for students only.
alter table teachers drop column if exists biometric_id;
-- IDs on the terminal that belong to teachers/staff can be ignored so they stop showing as "not linked".
alter table device_people add column if not exists ignored boolean not null default false;
create index if not exists schedules_teacher_idx on schedules (teacher_id, day_of_week);
create index if not exists section_subjects_teacher_idx on section_subjects (teacher_id);
