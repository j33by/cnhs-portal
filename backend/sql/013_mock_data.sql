-- Run after 012. Safe to run more than once (it updates what it created, never duplicates).
-- MOCK DATA for testing, built from the Grade 12 ABM class program (adviser: Pulmano, Jeremae T.):
--   * 5 real-named teachers from the timetable + 2 extra mock teachers for a second section (Grade 11 ABM)
--   * subjects, section_subjects (who teaches what in which section) and the full weekly schedule
--   * the ADVISER of Grade 12 ABM is signed in with  jamesbryllefahardo@gmail.com
--
-- How the adviser login works: the teacher rows need a Supabase auth user. If jamesbryllefahardo@gmail.com already exists in
-- Auth > Users (he signed in once with Google) that user is reused and made the adviser. If not, a confirmed user with that email is
-- created here; when he later taps "Continue with Google" with the same email, Supabase links Google to this user automatically,
-- so he lands straight in the teacher app as adviser of Grade 12 ABM (no sign-up form).
-- Every other mock teacher uses a @mock.cnhs.test address and cannot sign in (they only exist so the timetable has names).
--
-- Students are NOT seeded: a new student signs up, chooses Grade 12 > ABM, and receives all six subjects of that section.
-- Re-running this file resets the timetable of the two mock sections only.

create or replace function pg_temp.seed_user(p_id uuid, p_email text, p_name text) returns uuid language plpgsql as $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(p_email) limit 1;
  if uid is not null then return uid; end if;
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, '', now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('full_name', p_name, 'email_verified', true), now(), now(), '', '', '', '');
  if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'identities' and column_name = 'provider_id') then
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), p_id, p_id::text, jsonb_build_object('sub', p_id::text, 'email', p_email, 'email_verified', true), 'email', now(), now(), now());
  end if;
  return p_id;
end $$;

do $$
declare
  y int; t record; r record; uid uuid; sid uuid; subid uuid; dept int;
  adviser_email constant text := 'jamesbryllefahardo@gmail.com';
  uids jsonb := '{}';
begin
  select id into y from school_years where is_current = true limit 1;
  if y is null then raise exception 'No current school year. Run 001_schema.sql first.'; end if;

  -- ---------- 1. teachers ----------
  -- key, fixed id, email, first, last, teacher_no, grade levels, subjects [{code,name}]
  for t in select * from jsonb_to_recordset('[
    {"k":"pulmano","id":"cafe0000-0000-4000-8000-000000000001","email":"jamesbryllefahardo@gmail.com","first":"Jeremae T.","last":"Pulmano","no":"T-90001","g":[11,12],
     "s":[{"code":"HGP_12","name":"Homeroom Guidance Program 12"}]},
    {"k":"mejorada","id":"cafe0000-0000-4000-8000-000000000002","email":"daisy.mejorada@mock.cnhs.test","first":"Daisy G.","last":"Mejorada","no":"T-90002","g":[12],
     "s":[{"code":"RESEARCH1_12","name":"Research 1"}]},
    {"k":"sanchez","id":"cafe0000-0000-4000-8000-000000000003","email":"ishajane.sanchez@mock.cnhs.test","first":"Ishajane B.","last":"Sanchez","no":"T-90003","g":[12],
     "s":[{"code":"FIL_IDENTITY12","name":"Fil Identity 12"}]},
    {"k":"ruloma","id":"cafe0000-0000-4000-8000-000000000004","email":"rosana.ruloma@mock.cnhs.test","first":"Rosana P.","last":"Ruloma","no":"T-90004","g":[12],
     "s":[{"code":"PRECALCULUS_12","name":"Pre-Calculus 12"}]},
    {"k":"labrador","id":"cafe0000-0000-4000-8000-000000000005","email":"alicia.labrador@mock.cnhs.test","first":"Alicia C.","last":"Labrador","no":"T-90005","g":[12],
     "s":[{"code":"INTRO_PHILO_12","name":"Intro to Philosophy 12"}]},
    {"k":"santos","id":"cafe0000-0000-4000-8000-000000000006","email":"maria.santos@mock.cnhs.test","first":"Maria L.","last":"Santos","no":"T-90006","g":[11],
     "s":[{"code":"ORAL_COM_11","name":"Oral Communication 11"},{"code":"GEN_MATH_11","name":"General Mathematics 11"}]},
    {"k":"reyes","id":"cafe0000-0000-4000-8000-000000000007","email":"jose.reyes@mock.cnhs.test","first":"Jose A.","last":"Reyes","no":"T-90007","g":[11],
     "s":[{"code":"FABM1_11","name":"Fundamentals of ABM 1"},{"code":"LIT21_11","name":"21st Century Literature 11"}]}
  ]'::jsonb) as x(k text, id uuid, email text, first text, last text, no text, g int[], s jsonb)
  loop
    uid := pg_temp.seed_user(t.id, t.email, t.first || ' ' || t.last);
    uids := uids || jsonb_build_object(t.k, uid);
    insert into profiles (id, role, email, full_name, onboarded) values (uid, 'teacher', t.email, t.first || ' ' || t.last, true)
      on conflict (id) do update set role = 'teacher', full_name = excluded.full_name, onboarded = true;
    insert into teachers (id, teacher_no, first_name, last_name, grade_levels) values (uid, t.no, t.first, t.last, t.g)
      on conflict (id) do update set first_name = excluded.first_name, last_name = excluded.last_name, grade_levels = excluded.grade_levels;
    insert into teacher_subjects (teacher_id, code, name)
      select uid, s->>'code', s->>'name' from jsonb_array_elements(t.s) s
      on conflict (teacher_id, code) do update set name = excluded.name;
    insert into subjects (code, name) select s->>'code', s->>'name' from jsonb_array_elements(t.s) s on conflict (code) do update set name = excluded.name;
  end loop;
  insert into subjects (code, name) values ('SHS_ARAL', 'SHS ARAL') on conflict (code) do update set name = excluded.name;   -- no teacher on the timetable

  -- ---------- 2. sections ----------
  for r in select * from jsonb_to_recordset('[
    {"g":12,"name":"ABM","adviser":"pulmano","homeroom":"G12 ABM"},
    {"g":11,"name":"ABM","adviser":"reyes","homeroom":"G11 ABM"}
  ]'::jsonb) as x(g int, name text, adviser text, homeroom text)
  loop
    select id into sid from sections where school_year_id = y and grade_level = r.g and name = r.name;
    if sid is null then
      select min(d) into dept from generate_series(1, 16) d where d not in (select biometric_dept_no from sections where biometric_dept_no is not null);
      insert into sections (school_year_id, grade_level, name, adviser_id, homeroom, biometric_dept_no)
        values (y, r.g, r.name, (uids->>r.adviser)::uuid, r.homeroom, dept);
    else
      update sections set adviser_id = coalesce(adviser_id, (uids->>r.adviser)::uuid), homeroom = coalesce(homeroom, r.homeroom) where id = sid;
    end if;
  end loop;

  -- ---------- 3. who teaches what + weekly schedule ----------
  -- grade, section, subject code, teacher key (null = nobody assigned), day (1=Mon..5=Fri), start, end
  -- Grade 12 ABM is copied from the printed class program; consecutive hours of the same class are one block.
  create temp table _slots (g int, sec text, code text, teacher text, day int, st time, en time) on commit drop;
  insert into _slots values
    -- Research 1 (Mejorada)
    (12,'ABM','RESEARCH1_12','mejorada',1,'07:50','09:50'), (12,'ABM','RESEARCH1_12','mejorada',2,'07:50','09:50'),
    (12,'ABM','RESEARCH1_12','mejorada',4,'07:50','09:50'), (12,'ABM','RESEARCH1_12','mejorada',5,'10:00','12:00'),
    -- Fil Identity 12 (Sanchez)
    (12,'ABM','FIL_IDENTITY12','sanchez',3,'07:50','09:50'), (12,'ABM','FIL_IDENTITY12','sanchez',2,'10:00','12:00'),
    (12,'ABM','FIL_IDENTITY12','sanchez',5,'13:00','15:00'), (12,'ABM','FIL_IDENTITY12','sanchez',1,'15:00','16:00'),
    (12,'ABM','FIL_IDENTITY12','sanchez',4,'15:00','16:00'),
    -- Pre-Calculus 12 (Ruloma)
    (12,'ABM','PRECALCULUS_12','ruloma',5,'08:50','09:50'), (12,'ABM','PRECALCULUS_12','ruloma',1,'10:00','12:00'),
    (12,'ABM','PRECALCULUS_12','ruloma',3,'13:00','15:00'), (12,'ABM','PRECALCULUS_12','ruloma',4,'13:00','15:00'),
    (12,'ABM','PRECALCULUS_12','ruloma',2,'15:00','16:00'),
    -- Intro to Philosophy 12 (Labrador)
    (12,'ABM','INTRO_PHILO_12','labrador',3,'10:00','12:00'), (12,'ABM','INTRO_PHILO_12','labrador',4,'10:00','12:00'),
    (12,'ABM','INTRO_PHILO_12','labrador',1,'13:00','15:00'), (12,'ABM','INTRO_PHILO_12','labrador',2,'13:00','15:00'),
    -- Homeroom Guidance (adviser Pulmano), Friday first period
    (12,'ABM','HGP_12','pulmano',5,'07:50','08:50'),
    -- SHS ARAL, Mon + Tue 4-5 PM (no teacher on the printed program)
    (12,'ABM','SHS_ARAL',null,1,'16:00','17:00'), (12,'ABM','SHS_ARAL',null,2,'16:00','17:00'),
    -- Grade 11 ABM: invented sample section so the grade picker has more than one choice
    (11,'ABM','ORAL_COM_11','santos',1,'07:30','09:00'), (11,'ABM','ORAL_COM_11','santos',3,'07:30','09:00'),
    (11,'ABM','GEN_MATH_11','santos',2,'07:30','09:00'), (11,'ABM','GEN_MATH_11','santos',4,'07:30','09:00'),
    (11,'ABM','FABM1_11','reyes',1,'09:15','10:45'), (11,'ABM','FABM1_11','reyes',3,'09:15','10:45'),
    (11,'ABM','LIT21_11','reyes',2,'09:15','10:45'), (11,'ABM','LIT21_11','reyes',4,'09:15','10:45');

  -- no teacher (or section) may be double-booked in the seed itself
  if exists (select 1 from _slots a join _slots b on a.teacher = b.teacher and a.day = b.day and (a.g, a.sec, a.code, a.st) <> (b.g, b.sec, b.code, b.st) and a.st < b.en and b.st < a.en)
    or exists (select 1 from _slots a join _slots b on a.g = b.g and a.sec = b.sec and a.day = b.day and (a.code, a.st) <> (b.code, b.st) and a.st < b.en and b.st < a.en)
  then raise exception 'Mock timetable has an overlap'; end if;

  for r in select distinct g, sec as name from _slots loop
    select id into sid from sections where school_year_id = y and grade_level = r.g and name = r.name;
    insert into section_subjects (section_id, subject_id, teacher_id)
      select distinct sid, s.id, (uids->>x.teacher)::uuid from _slots x join subjects s on s.code = x.code where x.g = r.g and x.sec = r.name
      on conflict (section_id, subject_id) do update set teacher_id = excluded.teacher_id;
    delete from schedules where section_id = sid;
    insert into schedules (section_id, subject_id, teacher_id, day_of_week, start_time, end_time)
      select sid, s.id, (uids->>x.teacher)::uuid, x.day, x.st, x.en from _slots x join subjects s on s.code = x.code where x.g = r.g and x.sec = r.name;
  end loop;
end $$;
