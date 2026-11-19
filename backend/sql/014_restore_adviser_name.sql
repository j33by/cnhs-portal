-- Run once if jamesbryllefahardo@gmail.com was renamed to "Jeremae T. Pulmano" by an earlier copy of 013_mock_data.sql.
-- It restores the name from the Google sign-in (Auth > Users > that user > Google identity). He stays adviser of Grade 12 ABM.
-- No Google name found? Skip this and use the manual update at the bottom.
do $$
declare uid uuid; nm text; f text; l text;
begin
  select id into uid from auth.users where lower(email) = 'jamesbryllefahardo@gmail.com';
  if uid is null then raise exception 'No user with that email'; end if;
  select coalesce(identity_data->>'full_name', identity_data->>'name') into nm from auth.identities where user_id = uid and provider = 'google' limit 1;
  if nm is null or btrim(nm) = '' then raise exception 'No Google name saved for this user. Use the manual update below.'; end if;
  nm := btrim(nm);
  l := case when position(' ' in nm) > 0 then regexp_replace(nm, '^.*\s', '') else nm end;       -- last word = last name
  f := case when position(' ' in nm) > 0 then regexp_replace(nm, '\s+\S+$', '') else nm end;     -- the rest = first name(s)
  update profiles set full_name = nm where id = uid;
  update teachers set first_name = f, last_name = l where id = uid;
  raise notice 'Restored name: % (first: %, last: %)', nm, f, l;
end $$;

-- MANUAL (edit the two names, then run only these lines):
-- update teachers set first_name = 'YOUR FIRST NAME', last_name = 'YOUR LAST NAME' where id = (select id from auth.users where lower(email) = 'jamesbryllefahardo@gmail.com');
-- update profiles set full_name = 'YOUR FIRST NAME YOUR LAST NAME' where id = (select id from auth.users where lower(email) = 'jamesbryllefahardo@gmail.com');
