-- Unique, non-sequential 5-digit numbers (bijection mult*n+offset mod 100000). Row lock => no duplicates.
create or replace function next_id_seq(p_scope text) returns int language plpgsql security definer as $$
declare r id_counters; v int;
begin
  insert into id_counters(scope,last_seq,mult,offset_b)
  values (p_scope,0,(select m from (select (10001 + floor(random()*89998))::int as m) x where m%2=1 and m%5<>0 union all select 12347 limit 1),(random()*99999)::int)
  on conflict do nothing;
  select * into r from id_counters where scope=p_scope for update;
  if r.last_seq >= 100000 then raise exception 'ID range full'; end if;
  update id_counters set last_seq=last_seq+1 where scope=p_scope returning * into r;
  v := (r.mult::bigint * r.last_seq + r.offset_b) % 100000;
  return v;
end $$;
