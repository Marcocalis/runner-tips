-- Runner Tips: update 1.
-- Categories that follow a trip (pitstraat, onderweg, bij de klant...), English text for tips,
-- rewritten and new tips, removes test tips.
-- Paste into Supabase > SQL Editor > New query and press Run. Running it twice is safe.

alter table tips add column if not exists title_en text;
alter table tips add column if not exists body_en text;

alter table tips drop constraint if exists tips_category_check;
alter table tips add constraint tips_category_check
  check (category in ('pit','route','cust','device','body','weather','new','general',
                      'crates','returns','van','stairs'));

create or replace function get_tips(p_code text, p_voter uuid, p_admin text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
  adm boolean := _is_admin(p_admin);
  result json;
begin
  perform _check_code(p_code);
  select coalesce(json_agg(row_to_json(x) order by x.created_at desc), '[]'::json) into result from (
    select t.id, t.created_at, t.category, t.title, t.body, t.title_en, t.body_en, t.author, t.hidden,
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

-- Remove test tips.
delete from tips where title like '[TEST]%';

-- Rewrite the two original tips (keeps their likes and comments).
update tips set category = 'route',
  title = 'Zet je krat voor koelelementen zo snel mogelijk lager in je frame',
  body = 'Bovenop je frame is prima om mee te beginnen, maar zodra er lager een plek vrijkomt, wissel je hem daarheen. Dan gooi je de koelelementen er makkelijk in, zonder bij elke stop omhoog te reiken. Scheelt je schouders en tijd.',
  title_en = 'Move your cooling-pack crate lower in your frame as soon as you can',
  body_en = 'On top of your frame is fine to start with, but as soon as a spot lower down frees up, move it there. Then you can drop the cooling packs in easily, without reaching up at every stop. Saves your shoulders and time.'
where title = 'IJspakkenkrat en deksels laag in het frame';

update tips set category = 'weather',
  title = 'Koud drinken op warme dagen',
  body = 'Leg je flesje drinken op een warme dag tussen je ice packs of het droogijs en dek het af. Binnen no time heb je een lekker koud drankje.',
  title_en = 'Cold drinks on hot days',
  body_en = 'On a hot day, put your drink bottle between your ice packs or the dry ice and cover it. In no time you have a nice cold drink.'
where title = 'Gratis koud drinken op warme dagen';

-- New tips.
insert into tips (category, title, body, title_en, body_en, author)
select v.* from (values
  ('route', 'Sorteer tijdens je trip, niet in de pitstraat',
   'Leg wat je bij een klant terugkrijgt meteen op een vaste plek in je EPV, voordat je doorrijdt naar de volgende stop. In de pitstraat hoef je dan alleen nog uit te laden. Je staat er korter, en collega''s die achter je wachten zijn sneller aan de beurt.',
   'Sort during your trip, not in the pit lane',
   'Put whatever a customer hands back straight into a fixed spot in your EPV, before you drive on to the next stop. In the pit lane you then only have to unload. You''re there for less time, and colleagues waiting behind you get their turn sooner.',
   'Marco'),
  ('route', 'Eén open zak voor alle plastic zakjes',
   'Zet in je verzamelkrat een plastic zak met de hengsels over de rand van de krat, zodat hij open blijft staan. Alle zakjes die je van klanten terugkrijgt, prop je daarin. Geen losse zakjes meer door je hele EPV.',
   'One open bag for all plastic bags',
   'In your collection crate, put a plastic bag with the handles hooked over the rim of the crate so it stays open. Stuff every bag you get back from customers into it. No more loose bags all over your EPV.',
   'Marco'),
  ('route', 'Markeer je verzamelkrat',
   'Trek een stukje plastic (bijvoorbeeld van een tasje) door het handvat van je verzamelkrat, zodat het naar buiten steekt. Doe je de EPV open, dan zie je meteen in welke krat de zakjes moeten.',
   'Mark your collection crate',
   'Pull a strip of plastic (from a bag, for example) through the handle of your collection crate so it sticks out. When you open the EPV, you instantly see which crate the bags go in.',
   'Marco'),
  ('device', 'Accu wisselen? Kies eerst "battery swap"',
   'Staat je device na een trip nog maar op 30 tot 40% en ga je nog een trip doen? Wissel dan eerst de accu, er liggen reserve-accu''s op de hub. Houd de aan/uit-knop even ingedrukt: naast uitzetten krijg je de optie "battery swap". Kies die voordat je de accu eruit haalt. Dan onthoudt het device je login en hoef je na het wisselen niet opnieuw in te loggen.',
   'Swapping the battery? Choose "battery swap" first',
   'Is your device at only 30 to 40% after a trip and you''re doing another one? Swap the battery first; there are spare batteries at the hub. Hold the power button for a moment: next to turning it off, you get the option "battery swap". Choose it before you take the battery out. The device then remembers your login, so you don''t have to log in again after swapping.',
   'Marco'),
  ('body', 'Til met je benen, niet met je rug',
   'Buig door je knieën, houd de krat dicht tegen je lijf en draai met je voeten in plaats van met je bovenlichaam. Je tilt elke shift heel wat kratten, dus je rug gaat het verschil merken.',
   'Lift with your legs, not your back',
   'Bend your knees, keep the crate close to your body and turn with your feet instead of twisting your upper body. You lift a lot of crates every shift, so your back will notice the difference.',
   null),
  ('cust', 'Zware bestelling en hoog wonen? Loop twee keer',
   'Als je aankomt, laat je device zien hoeveel kilo een bestelling is. Is het zwaar en moet je de trap op? Neem dan minder per keer mee en loop twee keer. Een extra rondje kost een minuut, een overbelaste rug veel langer.',
   'Heavy order and a high floor? Make two trips',
   'When you arrive, your device shows how many kilos an order is. Heavy, and you have to take the stairs? Carry less at a time and make two trips. An extra trip costs a minute; an overloaded back costs a lot longer.',
   null),
  ('new', 'Neem de tijd als beginner',
   'Zorg eerst dat je alles goed onder de knie hebt. Als nieuwe runner krijg je makkelijkere trips met meer tijd, dus gebruik die tijd ook. Werk rustig en zonder stress. Je hoeft het niet precies zo te doen als een ervaren collega, het gaat erom dat je je eigen ritme vindt. De snelheid komt vanzelf.',
   'Take your time as a beginner',
   'First make sure you have everything down. As a new runner you get easier trips with more time, so use that time. Work calmly and without stress. You don''t have to do it exactly like an experienced colleague; what matters is finding your own rhythm. Speed comes by itself.',
   null)
) as v(category, title, body, title_en, body_en, author)
where not exists (select 1 from tips t where t.title = v.title);
