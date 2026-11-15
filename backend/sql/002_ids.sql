-- Unique, non-sequential 5-digit numbers: (mult * n + offset) mod 100000 is a bijection when mult is coprime with 100000.
-- The counter row is locked (FOR UPDATE) so two sign-ups at the same instant can never get the same number.
create or replace function next_id_seq(p_scope text) returns int language plpgsql security definer set search_path = public as $$
declare r id_counters; m int;
begin
  if not exists (select 1 from id_counters where scope = p_scope) then
    loop m := 10001 + floor(random() * 89998)::int; exit when m % 2 = 1 and m % 5 <> 0; end loop;
    insert into id_counters(scope, last_seq, mult, offset_b) values (p_scope, 0, m, floor(random() * 100000)::int) on conflict do nothing;
  end if;
  select * into r from id_counters where scope = p_scope for update;
  if r.last_seq >= 100000 then raise exception 'ID range full'; end if;
  update id_counters set last_seq = last_seq + 1 where scope = p_scope returning * into r;
  return ((r.mult::bigint * r.last_seq + r.offset_b) % 100000)::int;
end $$;
revoke execute on function next_id_seq(text) from public, anon, authenticated;   -- only the Node API (service role) may call it
