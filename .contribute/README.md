# Contributing data

Everything in this folder is what the database is built from; everything under `db/generated/`
is produced from it and must not be edited by hand.

```text
.contribute/
  inbox/                 drop SavedVariables / export files here for `npm run import` (not committed)
  items/items_<n>.json   the item database: in-game scans, one file per 10 000 ids (machine-written)
  dungeons/<name>.json   one file per dungeon: level range, icon, tile picture, drops per boss (hand-curated)
  raids/<name>.json      same for raids
  tools/                 the generator (TypeScript, npm)
```

WoW Forever's items are server-side. No data export describes them — the wago.tools tables
are incomplete and wrong for this client, and item ids from other sources don't match — so the
item database comes from the game itself: the addon asks the server about item ids and records
everything the client then knows about each item. Drop locations are a separate, hand-curated
table; the two only meet through item ids.

## Items: scanning

```text
/fl scan 1              scan upward from id 1; stops after 1000 new items
/fl scan resume         continue where the last scan stopped (survives /reload)
/fl scan 270000 280000  scan a range
/fl scan 270000 280000 force   re-record every id in the range, known or not
/fl scan stop           /fl scan   (status)
/fl scan limit off      no per-scan item limit (for the SavedVariables route); `limit 1000` restores it
```

The scanner requests ~50 ids per second, skips ids the shipped database already has, and stops
after 1000 newly recorded items so that `/fl export` stays small — when you import the
SavedVariables file instead, `/fl scan limit off` lets a scan run on; an open-ended scan also gives up
after 20 000 ids in a row that don't exist. Every item that exists is recorded with all of
`C_Item.GetItemInfo` and `C_Item.GetItemStats` (name in your client's language, quality, item
level, required level, class/subclass, slot, bind, icon, sell price, stack size, set, expansion,
stats) and is usable in the addon right away.

To get the records into the repository, copy your SavedVariables file
(`World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverLoot.lua`, written
on logout and `/reload`) into `inbox/` and run:

```sh
cd .contribute/tools
npm install          # once
npm run import       # every .lua / .json in inbox/; or: npm run import -- <path to one file>
npm run gen
```

Without a checkout of the repository, `/fl export` in-game shows the same data as JSON: copy it
into a file and attach it to an issue, or send it to someone who drops it into `inbox/`. Each
export only holds the records new since the previous one (records stay in the SavedVariables
until the shipped database has them, so a full dump would grow with every scan); `/fl export all`
repeats everything. Either way, commit `items/` together with the regenerated
`db/generated/` files. After `/reload` the addon drops records the shipped database now states
exactly, so `/fl scan resume` keeps going with a clean slate; records that differ from the
shipped row (a `force` re-scan, a changed item) stay until they have been imported too.

`import` merges each record into `items/items_<range>.json`: the newest observation replaces
the old one, names are kept per locale (scan on a deDE client and the German names join the
English ones). Names are only ever what a client of that language reported.

## Drops

The addon also records loot: every item it sees dropping while the database lacks it, and for
every boss (`ENCOUNTER_END`) how often you killed it and which items were seen dropping — from
your own loot windows and your group's rolls. `npm run import` turns that into loot rows in the
boss's instance file (creating the file when needed) and prints what it saw as `seen/kills`. It
never changes rows that already exist and only writes a `chance` for new rows after 10 or more
kills (kills where you neither looted nor rolled still count, so the ratios err on the low
side). Have a look at the diff before committing.

### By hand

1. Find the instance file in `dungeons/` or `raids/`, or create one — all you need is the map id
   (see the `-- Name` comments in `db/generated/instances.lua`). Encounter and item ids are the
   game's own (`DungeonEncounter.ID`, item id); the item id is in the item link (`item:5188:...`).
2. Add rows to the boss's `loot` array. `chance` is 0–1 and optional. Names are informational
   and filled in for you; a row with only a `name` gets its `item` id filled in when exactly one
   scanned item carries that name. An item nobody has scanned yet is allowed (the boss page
   still shows it once the client fetches it), it just isn't searchable until scanned.

```json
{
  "map": 36,
  "minLevel": 15,
  "maxLevel": 21,
  "icon": "Interface\\Icons\\INV_Misc_Key_13",
  "background": "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-Deadmines",
  "backgroundCoords": [0, 0.68, 0.05, 0.69],
  "encounters": [
    { "id": 2747, "name": "Edwin VanCleef", "loot": [
      { "item": 5188, "name": "Filled Vessel", "chance": 0.9 },
      { "name": "Cruel Barb" }
    ] }
  ]
}
```

3. Run the tools (Node 20+):

```sh
cd .contribute/tools
npm install          # once
npm run fix          # validate ids, fill names, add missing bosses
npm run gen          # write db/generated/
```

4. Commit the JSON **and** the regenerated `db/generated/` files, then open a pull request.

`npm run check` only validates; `npm run gen -- --check` fails when `db/generated/` is stale
(used in CI). Instances and encounters come from [wago.tools](https://wago.tools) (`Map`,
`DungeonEncounter`) for the build pinned in `tools/config.json`, cached in `tools/.cache/`
(delete it to re-download). Bump `build` there when the client updates; `locales` lists the
instance/boss name tables to ship (item names ship for every locale that was scanned).

## What is generated from what

| Output (`db/generated/`) | Source |
|---|---|
| `items/items_NNN.lua` | `items/*.json`: the scanned items, `itemsPerFile` rows per file |
| `instances.lua` | wago.tools `Map` + `DungeonEncounter` (only maps with encounters), levels/icons from the JSON |
| `loot/<name>.lua` | the `dungeons/` and `raids/` files' `loot` rows |
| `locales/<locale>/items.lua` | the scanned names of that locale |
| `locales/<locale>/instances.lua`, `bosses.lua` | wago.tools name columns per configured locale |
| `generated.xml` | loader listed in the TOC |
