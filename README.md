# Runner Tips

A tips board for runners: share tips (with photos), like them, comment, report. Dutch by default, with an English toggle.

- `site/` is the website that gets published (Netlify).
- `supabase-setup.sql` sets up the database (paste it into Supabase > SQL Editor and press Run).
- `demo/` is the first mock-up, kept for reference.

## How a trip works (as Marco explained it, for writing tips)

1. **Pit lane, start:** scan and load your frames into the EPV, take two empty crates for the cooling packs (one per side), log in on the device.
2. **On the road:** the device navigates you to the stop. On arrival it shows the kilos and which side of the EPV.
3. **At the customer:** tap deliver, the device shows which crates to scan and take, you bring the bags to the door. The customer may hand back parcels, plastic bags or deposit items; sort them at the EPV, then press next.
4. **Back in the pit lane:** after "return to hub", unload and sort everything (lids, ice packs/cooling packs, glass, dry ice, deposit), take out the empty frames, done or start the next trip.

Terms: chilled totes (with lid, cooling packs on top), ambient totes (open red crates), frames 3 or 4 high, "koelelementen" = ice packs, dry ice is separate (frozen products).

## How it works

- No accounts. Everything goes through database functions (`supabase-setup.sql` and the update files) that check a hub code; the tables themselves are locked.
- The hub code is built into `site/config.js` (one hub: Dordrecht), so colleagues just open the link.
- A separate moderator key turns on moderator mode (`/?admin=<key>`): hide tips and comments, see reports. It lives in the database and in a local `SECRETS.md`, never in this repo.
- Likes, comments and reports are tied to a random id stored on each phone.
- `/?mock` runs the site on sample data in memory, for testing without touching the database.

## Setting up your own copy

1. Create a Supabase project. In SQL Editor, run `supabase-setup.sql`, then `supabase-update-1.sql` and `supabase-update-2.sql`.
2. Set your own codes: `update settings set hub_code = 'yourcode', admin_key = 'a-long-secret';`
3. Put your project URL, publishable key and hub code in `site/config.js`.
4. Publish the `site/` folder on any static host (this one uses Netlify).

## Links

- Live site: https://runner-tips-hub.netlify.app (Hub Dordrecht)

## Publishing an update

`npx netlify-cli@17.38.1 deploy --prod --dir site --site <site id from SECRETS.md>`

## Taking it offline

Netlify: Site configuration > Delete site. Supabase: Project settings > Delete project.
