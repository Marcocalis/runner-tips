-- Runner Tips: update 2.
-- Fixed top 3, all starting tips by Marco, people can delete their own comments.
-- ASCII only on purpose, so copying can't mangle it. Running it twice is safe.

alter table tips add column if not exists pin int;
alter table comments add column if not exists voter uuid;

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
  return json_build_object('tips', result, 'admin', adm);
end $$;

drop function if exists add_comment(text, uuid, text, text);
create or replace function add_comment(p_code text, p_tip uuid, p_author text, p_body text, p_voter uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  insert into comments (tip_id, author, body, voter) values (p_tip, nullif(trim(p_author), ''), trim(p_body), p_voter);
end $$;

create or replace function delete_comment(p_code text, p_comment uuid, p_voter uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _check_code(p_code);
  delete from comments where id = p_comment and voter = p_voter;
end $$;

grant execute on function add_comment(text, uuid, text, text, uuid), delete_comment(text, uuid, uuid) to anon, authenticated;

-- Fixed top 3.
update tips set pin = null;
update tips set pin = 1 where title like 'Zet je krat voor koelelementen%';
update tips set pin = 2 where title = 'Koud drinken op warme dagen';
update tips set pin = 3 where title like 'Accu wisselen?%';

-- All starting tips are Marco's.
update tips set author = 'Marco'
where author is null and (title like 'Til met je benen%' or title like 'Zware bestelling%' or title = 'Neem de tijd als beginner');
