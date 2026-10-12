-- Runner Tips: update 3.
-- Anonymous visitor counter, only visible in moderator mode.
-- Counts per day per device (the random id the site already keeps on each phone). No IP addresses, no names.
-- ASCII only on purpose. Running it twice is safe.

create table if not exists visits (
  day date not null,
  voter uuid not null,
  views int not null default 1,
  primary key (day, voter)
);
alter table visits enable row level security;
revoke all on visits from anon, authenticated;

create or replace function log_visit(p_code text, p_voter uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  insert into visits (day, voter) values ((now() at time zone 'Europe/Amsterdam')::date, p_voter)
  on conflict (day, voter) do update set views = visits.views + 1;
end $$;

create or replace function get_stats(p_admin text) returns json
language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Amsterdam')::date;
begin
  if not _is_admin(p_admin) then raise exception 'not_admin'; end if;
  return json_build_object(
    'visitors_total', (select count(distinct voter) from visits),
    'visitors_today', (select count(*) from visits where day = today),
    'visitors_week',  (select count(distinct voter) from visits where day > today - 7),
    'views_total',    (select coalesce(sum(views), 0) from visits),
    'days', (select coalesce(json_agg(json_build_object('day', d.day, 'visitors', d.visitors, 'views', d.views) order by d.day), '[]'::json)
             from (select day, count(*) as visitors, sum(views) as views from visits where day > today - 14 group by day) d)
  );
end $$;

grant execute on function log_visit(text, uuid), get_stats(text) to anon, authenticated;
