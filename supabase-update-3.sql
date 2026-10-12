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

-- Count contributors correctly, including people who post anonymously.
-- New tips remember which device posted them; older anonymous tips each count as one contributor.
alter table tips add column if not exists voter uuid;

drop function if exists add_tip(text, text, text, text, text, text);
create or replace function add_tip(p_code text, p_category text, p_title text, p_body text, p_author text, p_photo text, p_voter uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  perform _check_code(p_code);
  if p_photo is not null and p_photo not like 'data:image/jpeg;base64,%' then raise exception 'bad_photo'; end if;
  insert into tips (category, title, body, author, photo, voter)
  values (p_category, trim(p_title), trim(p_body), nullif(trim(p_author), ''), p_photo, p_voter)
  returning id into new_id;
  return new_id;
end $$;
grant execute on function add_tip(text, text, text, text, text, text, uuid) to anon, authenticated;

create or replace function get_tips(p_code text, p_voter uuid, p_admin text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  adm boolean := _is_admin(p_admin);
  result json;
begin
  perform _check_code(p_code);
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json) into result from (
    select t.id, t.created_at, t.category, t.title, t.body, t.title_en, t.body_en, t.author, t.hidden, t.pin,
           (t.photo is not null) as has_photo,
           (select count(*) from votes v where v.tip_id = t.id) as votes,
           exists (select 1 from votes v where v.tip_id = t.id and v.voter = p_voter) as voted,
           exists (select 1 from reports r where r.tip_id = t.id and r.voter = p_voter) as reported,
           case when adm then (select count(*) from reports r where r.tip_id = t.id) else 0 end as reports,
           case when adm then (select string_agg(distinct r.reason, ', ') from reports r where r.tip_id = t.id) end as report_reasons,
           (select coalesce(json_agg(json_build_object('id', c.id, 'created_at', c.created_at, 'author', c.author, 'body', c.body,
                     'hidden', c.hidden, 'mine', (c.voter is not null and c.voter = p_voter)) order by c.created_at), '[]'::json)
              from comments c where c.tip_id = t.id and (adm or not c.hidden)) as comments
    from tips t
    where adm or not t.hidden
  ) x;
  return json_build_object('tips', result, 'admin', adm,
    'contributors', (select count(distinct coalesce(voter::text, lower(trim(author)), id::text)) from tips where not hidden));
end $$;
