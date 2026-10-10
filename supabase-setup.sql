-- Runner Tips: database setup.
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run. Running it twice is safe.
-- On a fresh project, run supabase-update-1.sql right after this one.

create table if not exists settings (
  id int primary key default 1 check (id = 1),
  hub_code text not null,
  admin_key text not null
);
insert into settings (id, hub_code, admin_key)
values (1, 'change-this-hub-code', 'change-this-moderator-key')
on conflict (id) do nothing;

create table if not exists tips (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  category text not null check (category in ('crates','van','weather','stairs','cust','returns','body','new')),
  title text not null check (char_length(title) between 3 and 80),
  body text not null check (char_length(body) between 5 and 500),
  author text check (author is null or char_length(author) <= 30),
  photo text check (photo is null or char_length(photo) < 400000),
  hidden boolean not null default false
);

create table if not exists votes (
  tip_id uuid not null references tips(id) on delete cascade,
  voter uuid not null,
  created_at timestamptz not null default now(),
  primary key (tip_id, voter)
);

create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  tip_id uuid not null references tips(id) on delete cascade,
  created_at timestamptz not null default now(),
  author text check (author is null or char_length(author) <= 30),
  body text not null check (char_length(body) between 1 and 300),
  hidden boolean not null default false
);

create table if not exists reports (
  tip_id uuid not null references tips(id) on delete cascade,
  voter uuid not null,
  reason text not null check (char_length(reason) <= 40),
  created_at timestamptz not null default now(),
  primary key (tip_id, voter)
);

-- Nobody touches the tables directly. Everything goes through the functions below,
-- which check the hub code (and the moderator key for moderation).
alter table settings enable row level security;
alter table tips enable row level security;
alter table votes enable row level security;
alter table comments enable row level security;
alter table reports enable row level security;
revoke all on settings, tips, votes, comments, reports from anon, authenticated;

create or replace function _check_code(p_code text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from settings where hub_code = lower(trim(p_code))) then
    raise exception 'bad_code';
  end if;
end $$;

create or replace function _is_admin(p_admin text) returns boolean
language sql security definer set search_path = public as $$
  select coalesce(p_admin is not null and exists (select 1 from settings where admin_key = p_admin), false);
$$;

create or replace function get_tips(p_code text, p_voter uuid, p_admin text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  adm boolean := _is_admin(p_admin);
  result json;
begin
  perform _check_code(p_code);
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json) into result from (
    select t.id, t.created_at, t.category, t.title, t.body, t.author, t.hidden,
           (t.photo is not null) as has_photo,
           (select count(*) from votes v where v.tip_id = t.id) as votes,
           exists (select 1 from votes v where v.tip_id = t.id and v.voter = p_voter) as voted,
           exists (select 1 from reports r where r.tip_id = t.id and r.voter = p_voter) as reported,
           case when adm then (select count(*) from reports r where r.tip_id = t.id) else 0 end as reports,
           case when adm then (select string_agg(distinct r.reason, ', ') from reports r where r.tip_id = t.id) end as report_reasons,
           (select coalesce(json_agg(json_build_object('id', c.id, 'created_at', c.created_at, 'author', c.author, 'body', c.body, 'hidden', c.hidden) order by c.created_at), '[]'::json)
              from comments c where c.tip_id = t.id and (adm or not c.hidden)) as comments
    from tips t
    where adm or not t.hidden
  ) x;
  return json_build_object('tips', result, 'admin', adm);
end $$;

create or replace function get_photo(p_code text, p_tip uuid) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  return (select photo from tips where id = p_tip);
end $$;

create or replace function add_tip(p_code text, p_category text, p_title text, p_body text, p_author text, p_photo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  perform _check_code(p_code);
  if p_photo is not null and p_photo not like 'data:image/jpeg;base64,%' then raise exception 'bad_photo'; end if;
  insert into tips (category, title, body, author, photo)
  values (p_category, trim(p_title), trim(p_body), nullif(trim(p_author), ''), p_photo)
  returning id into new_id;
  return new_id;
end $$;

create or replace function toggle_vote(p_code text, p_tip uuid, p_voter uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  if exists (select 1 from votes where tip_id = p_tip and voter = p_voter) then
    delete from votes where tip_id = p_tip and voter = p_voter;
    return false;
  end if;
  insert into votes (tip_id, voter) values (p_tip, p_voter);
  return true;
end $$;

create or replace function add_comment(p_code text, p_tip uuid, p_author text, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  insert into comments (tip_id, author, body) values (p_tip, nullif(trim(p_author), ''), trim(p_body));
end $$;

create or replace function report_tip(p_code text, p_tip uuid, p_voter uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  insert into reports (tip_id, voter, reason) values (p_tip, p_voter, p_reason)
  on conflict (tip_id, voter) do update set reason = excluded.reason;
end $$;

create or replace function admin_set_hidden(p_admin text, p_kind text, p_id uuid, p_hidden boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin(p_admin) then raise exception 'not_admin'; end if;
  if p_kind = 'tip' then update tips set hidden = p_hidden where id = p_id;
  elsif p_kind = 'comment' then update comments set hidden = p_hidden where id = p_id;
  end if;
end $$;

create or replace function admin_clear_reports(p_admin text, p_tip uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin(p_admin) then raise exception 'not_admin'; end if;
  delete from reports where tip_id = p_tip;
end $$;

revoke execute on function _check_code(text), _is_admin(text) from public, anon, authenticated;
grant execute on function get_tips(text, uuid, text), get_photo(text, uuid), add_tip(text, text, text, text, text, text),
  toggle_vote(text, uuid, uuid), add_comment(text, uuid, text, text), report_tip(text, uuid, uuid, text),
  admin_set_hidden(text, text, uuid, boolean), admin_clear_reports(text, uuid) to anon, authenticated;

-- Starting tips (only added if the table is still empty).
insert into tips (category, title, body, author)
select * from (values
  ('crates', 'IJspakkenkrat en deksels laag in het frame',
   'Zet de extra krat voor de ijspakken en de deksels laag in het frame zodra je de kans hebt. Dan hoef je niet elke keer omhoog te reiken om ze terug te zetten.', 'Marco'),
  ('weather', 'Gratis koud drinken op warme dagen',
   'Leg je waterfles op een warme dag bij de ijspakken in een koude krat. Een halfuur later heb je een koud drankje onder het werk.', 'Marco')
) as v(category, title, body, author)
where not exists (select 1 from tips);
