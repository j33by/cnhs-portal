-- Run after 007. Safe to run more than once.
-- How many minutes before a class the teacher gets a phone notification (0 = off).
alter table teachers add column if not exists alert_minutes int not null default 10;
alter table teachers drop constraint if exists teachers_alert_minutes_check;
alter table teachers add constraint teachers_alert_minutes_check check (alert_minutes in (0, 5, 10, 15, 20, 30, 45, 60));
-- Remembers which reminder was already sent today, so a class is never announced twice.
create table if not exists class_reminders_sent (
  schedule_id uuid not null references schedules(id) on delete cascade,
  rdate date not null, sent_at timestamptz default now(),
  primary key (schedule_id, rdate)
);
alter table class_reminders_sent enable row level security;      -- no policy: only the server touches it
