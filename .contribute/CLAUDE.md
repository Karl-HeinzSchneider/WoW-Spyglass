# .contribute — the data the database is built from

Everything under `data/` is input; `ForeverLoot/db/generated/` and
`ForeverLoot_Locale/db/generated/` are produced from it by `npm run gen` and **never edited by
hand**. The tooling that reads this folder is described in `src/CLAUDE.md`; the addon that
records the scans is `ForeverLoot_Scraper/`.

```text
.contribute/
  inbox/                    drop SavedVariables / export files here for `npm run import` (gitignored; only .gitkeep is tracked)
  data/
    config.json             pinned client build and generation settings
    items/items_<n>.json    the item database: in-game scans, one file per 10 000 ids (machine-written)
    dungeons/<slug>.json    one file per dungeon: levels, art, bosses and drops (hand-curated)
    raids/<slug>.json       same for raids
    crafting/<slug>.json    one file per profession and the items its recipes make
    pvp/<slug>.json         one file per reward source and its rewards
    collections/<slug>.json one file per collection and its items
    reputation/<slug>.json  one file per faction and its rewards
```

`config.json`: `build` (wago.tools build, bump when the client updates; the download is cached
in the root `.cache/<build>/`, delete it to refresh), `locales` (instance/boss name tables to
ship; enUS is always first; item names ship for every locale that was scanned), `excludeMaps`
(maps with encounters to leave out, e.g. test maps), `itemsPerFile` (rows per generated
`items_NNN.lua`).

When Claude is asked to pull data in from somewhere (a website's drop tables, a spreadsheet),
do it with a throwaway script in the session scratchpad that writes the JSON here, then
`npm run fix` and `npm run gen`. Don't add tools or commands to the repo for a one-off. Texture
paths in JSON need `\\`; write these files with the Write/Edit tools, not shell heredocs.

## Where things come from

WoW Forever's items are server-side. No data export describes them — wago.tools' item tables are
incomplete and wrong for this client, and item ids from Classic/wowhead don't match — so **the
item database comes from the game itself**: the scraper asks the server about item ids and
records everything the client then knows. Instances and encounters come from wago.tools
(`Map`, `DungeonEncounter`) for the pinned build: instance ids are `Map.ID`, boss ids are
`DungeonEncounter.ID`. Drops and item lists are hand-curated tables; they meet the scans only
through item ids.

| Output | Source under `data/` |
|---|---|
| `ForeverLoot/db/generated/items/items_NNN.lua` | `items/*.json`, `itemsPerFile` rows per file |
| `…/instances.lua` | wago.tools `Map` + `DungeonEncounter` (only maps with encounters), levels/icons/portraits from `dungeons/` and `raids/` |
| `…/loot/<slug>.lua` | the `loot` rows of `dungeons/` and `raids/` files that have any |
| `…/<kind>/<slug>.lua` (crafting, pvp, collections, reputation) | the item lists, one file each, rows or not |
| `…/locales/enUS/*.lua` | English fallback names (items from scans, instances/bosses from wago) |
| `ForeverLoot_Locale/db/generated/locales/<locale>/items.lua` | scanned names of every non-English locale |
| `ForeverLoot_Locale/db/generated/locales/<locale>/instances.lua`, `bosses.lua` | wago.tools names for every configured non-English locale |
| each `generated.xml` | the loader listed in that addon's TOC |

## Items: scanning (`ForeverLoot_Scraper`)

```text
/fl scan 1                     scan upward from id 1; stops after 1000 new items
/fl scan resume                continue where the last scan stopped (survives /reload)
/fl scan 270000 280000         scan a range
/fl scan 270000 280000 force   re-record every id in the range, known or not
/fl scan stop    /fl scan      stop; status
/fl scan limit off             no per-scan item limit (for the SavedVariables route); `limit 1000` restores it
```

~50 ids per second; ids the shipped database already has are skipped; an open-ended scan gives
up after 20 000 consecutive missing ids. Every existing item is recorded with all of
`C_Item.GetItemInfo` + `C_Item.GetItemStats` (name in the client's language, quality, item
level, required level, class/subclass, slot, bind, icon, sell price, stack size, set, expansion,
stats) and is browsable in the addon right away.

Getting records into the repository, either route:

1. **SavedVariables** — copy
   `World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/ForeverLoot_Scraper.lua`
   (written on logout and `/reload`) into `inbox/`, or pass its path:
   `npm run import -- <path>`.
2. **`/fl export`** — shows the same data as JSON to copy into a `.json` file for `inbox/` or an
   issue. Each export holds only records new since the previous one (`/fl export all` repeats
   everything).

Then `npm run import` (every `.lua`/`.json` in `inbox/`, name order) and `npm run gen`; commit
`data/items/` together with both regenerated addon trees. `import` merges each record into
`items/items_<range>.json`: the newest observation replaces the old, names are kept per locale
(a deDE scan adds German names next to the English ones; a name is only ever what a client of
that language reported). After `/reload` the scraper drops records the shipped database now
states exactly; records that differ (a `force` re-scan, a changed item) stay until imported.

## Drops (`dungeons/`, `raids/`)

The scraper also records loot: every item seen dropping that the DB lacks, and per boss
(`ENCOUNTER_END`) how often you killed it and which items were seen dropping (own loot windows
and the group's rolls). `npm run import` turns that into loot rows in the boss's instance file
(creating the file when needed) and prints what it saw as `seen/kills`. It never changes existing
rows and only writes a `chance` for new rows after 10+ kills (kills with no loot/roll still
count, so ratios err low). Review the diff before committing.

By hand: find or create the instance file — all it needs is the map id (the `-- Name` comments
in `ForeverLoot/db/generated/instances.lua` list them). Add rows to a boss's `loot`. `chance` is
0–1 and optional. A boss may carry `level` and `creatureType` as the game shows them (card says
"20 Humanoid"), a `portrait`, and the ids of `quests` it is involved in (quest "!" on the card).
Names are informational and rewritten by `fix`; a row with only a `name` gets its `item` id
filled in when exactly one scanned item has that name. An unscanned item is allowed (warning):
the boss page shows it once the client fetches it, it just isn't searchable until scanned.

```json
{
  "map": 36,
  "minLevel": 15,
  "maxLevel": 21,
  "icon": "Interface\\Icons\\INV_Misc_Key_13",
  "background": "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-Deadmines",
  "backgroundCoords": [0.0156, 0.6641, 0.0703, 0.6797],
  "encounters": [
    { "id": 2747, "name": "Edwin VanCleef",
      "portrait": "Interface\\EncounterJournal\\UI-EJ-BOSS-EdwinVancleef",
      "level": 20, "creatureType": "Humanoid", "quests": [166],
      "loot": [
        { "item": 5188, "name": "Filled Vessel", "chance": 0.9 },
        { "name": "Cruel Barb" }
      ] }
  ]
}
```

`npm run fix` validates ids (map exists and is in the right folder, encounters belong to the
map, no duplicates, chance in range), fills names, adds every encounter the game knows that the
file doesn't list yet (empty `loot`), and rewrites the file in stable key order. Schema:
`CuratedInstance` in `src/curated.ts`. A raid only appears in the Raids module once its
`FL.InstanceFolder(mapID)` line in `ForeverLoot/modules/raids/raids.lua` is uncommented.

## Item lists (`crafting/`, `pvp/`, `collections/`, `reputation/`)

One module each in the browser; each shows tiles, one per file, and each tile lists that file's
items. Nothing here comes from a game table: **the file name is the list's id** (lowercase
letters, digits, underscores), `name` is what the tile shows, and the rows are yours. The rows
key differs per kind:

| Folder | Rows key | Row fields besides `item`/`name`/`group` | Default grouping |
|---|---|---|---|
| `crafting/` | `recipes` | `spell` (recipe spell id), `skill` (required skill), `source` (free text: "Trainer", "Vendor: …") | skill tier (Apprentice, Journeyman, Expert, Artisan, Master) |
| `pvp/` | `rewards` | `rank` (honor rank 1–14), `standing`, `side` (`Alliance`/`Horde`) | rank, else standing |
| `collections/` | `items` | `source` (free text), `side` | none (by item type) |
| `reputation/` | `rewards` **object keyed by standing** | `side` | standing |

Every row may carry a `group` label of your own, which replaces the default grouping for that
row. Every file may carry `icon`, `background` + `backgroundCoords` (as for instances), `info`
(small text on the tile) and `order` (tile position; by name otherwise). Reputation files must
state the game's `faction` id — the addon uses it at runtime for the localized name, description
and the character's standing; crafting files may state the profession's `skillLine` id. Valid
standings: `Hated`, `Hostile`, `Unfriendly`, `Neutral`, `Friendly`, `Honored`, `Revered`,
`Exalted`; empty groups may be omitted. Unknown fields, wrong rows keys and out-of-range values
are errors.

```json
{
  "name": "Argent Dawn",
  "icon": "Interface\\Icons\\Achievement_Reputation_01",
  "faction": 529,
  "rewards": {
    "Friendly": [ { "item": 13209, "name": "Seal of the Dawn" } ],
    "Honored": [ { "name": "Argent Dawn Tabard", "side": "Alliance" } ]
  }
}
```

Item rows work as for drops (id, or a name that resolves to exactly one scanned item; unscanned
allowed with a warning). A file with no rows still gets its tile — the page then asks for
contributions. Schema and validation: `src/lists.ts`.

## Checklist for any data change

1. Edit or add JSON under `data/` (or `npm run import`).
2. `npm run fix` — must end without `ERROR` lines; warnings are fine.
3. `npm run gen` — writes both generated trees.
4. Commit the JSON **and** both generated trees (`npm run generate:check` is what CI runs).
