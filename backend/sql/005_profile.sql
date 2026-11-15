-- Run after 004. Parents can keep a contact number on their profile.
alter table profiles add column if not exists contact_no text;
