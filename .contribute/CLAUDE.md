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
    crafting/<slug>.json    one file per profession: its skill line, plus hand-curated additions to the generated recipes
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
`DungeonEncounter.ID`. A few maps (Blackfathom Deeps, Gnomeregan, Sunken Temple) also carry the
same bosses for other difficulties (Season of Discovery raids, a second 5-player set); only the
normal 5-player set is used, the other ids are unknown to the tooling. Profession recipes come from wago.tools too (`SkillLine`,
`SkillLineAbility`, `SpellReagents`, `SpellEffect`, `SpellTotems`, `TradeSkillCategory`,
`TotemCategory`): recipe ids are spell ids, profession ids are `SkillLine.ID`. Factions are
checked against `Faction`. wago.tools' `ItemSparse` is incomplete for this server but agrees
with the scans on the items it has, so the tooling reads one thing from it: the skill a
scanned recipe item requires. Drops and item lists are hand-curated tables; they meet the
scans only through item ids.

| Output | Source under `data/` |
|---|---|
| `ForeverLoot/db/generated/items/items_NNN.lua` | `items/*.json`, `itemsPerFile` rows per file |
| `…/instances.lua` | wago.tools `Map` + `DungeonEncounter` (only maps with encounters), levels/icons/portraits from `dungeons/` and `raids/` |
| `…/loot/<slug>.lua` | the `loot` rows of `dungeons/` and `raids/` files that have any |
| `…/<kind>/<slug>.lua` (crafting, pvp, collections, reputation) | the item lists, one file each, rows or not |
| `…/recipes/<profession>.lua` | wago.tools recipe tables, one file per profession, only recipes whose product (enchants: every reagent) is in the scans |
| `…/locales/<locale>/crafting.lua` | profession, trade skill category and tool names from wago.tools, for the configured locales |
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
"20 Humanoid"), a picture (`portrait` or `displayID`, see below), and the ids of `quests` it is
involved in (quest "!" on the card).
Names are informational and rewritten by `fix`; a row with only a `name` gets its `item` id
filled in when exactly one scanned item has that name. An unscanned item is allowed (warning):
the boss page shows it once the client fetches it, it just isn't searchable until scanned.

**Split dungeons.** Some maps are several dungeons to players: Scarlet Monastery (map 189) is
Graveyard, Library, Armory and Cathedral; Blackrock Spire (229) is Lower and Upper; Dire Maul
(429) is East, West and North. Such a map has one file per part, all with the same `map`, each
with its own `id` (by convention map × 100 + n: `18901`…`18904`) and its own `name` (no game
table has one, so `fix` leaves it alone). The addon knows the part by that `id`: its tile, boss
cards, trash and quests, and its `FL.InstanceFolder(id)` line in the module. Each of the map's
encounters goes in exactly one of the files: one listed in two is an error, one in none a
warning (`fix` can't know which part it belongs to, so it doesn't add it).

Besides the bosses, an instance file has two lists of its own, `trash` and `quests`. The browser
shows each of them as one more card next to the boss cards, in that order.

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
  ],
  "trash": [
    { "item": 1935, "name": "Buzzer Blade", "chance": 0.01 }
  ],
  "quests": [
    { "id": 166, "name": "Underground Assault", "side": "Alliance",
      "items": [
        { "item": 6220, "name": "Silver-Thread Cape" },
        { "name": "Gold-Flecked Gloves" }
      ] }
  ]
}
```

### A boss's picture: `portrait` or `displayID`

`portrait` is a texture path or fileID, normally the Encounter Journal's hand-made boss art
(`Interface\EncounterJournal\UI-EJ-BOSS-<Name>`). Bosses this server added have none — this
client ships no Encounter Journal data at all — so they instead carry `displayID`, the
**CreatureDisplayID** of the model, which the client renders into a portrait by itself
(`SetPortraitTextureFromCreatureDisplayID`, the same call and the same 2:1 shape the game's own
boss buttons use). `portrait` wins when both are set; with neither, the card shows a generic
boss icon.

A display id is not in any client table for these NPCs, so it is collected in game. With the
boss (or any copy of it) as your target:

```text
/run local m=CreateFrame("PlayerModel") m:SetUnit("target") print(m:GetDisplayInfo(), UnitGUID("target"))
```

The number is the `displayID`; the GUID's sixth field is the NPC id, which goes in the optional
`npc` field — it is not shipped, it only records where the display id came from so it can be
re-checked later. Both must be positive integers; `npm run check` verifies that much, not that
the model is the right one.

```json
{ "id": 3493, "name": "Faldrim Anvilmar", "displayID": 142826, "npc": 261306, "loot": [] }
```

### `trash`: what the enemies between the bosses drop

`trash` is a list of the same rows a boss's `loot` has (`item`, `name`, optional `chance` 0–1),
for everything that drops off the instance's non-boss enemies. Every instance has the category,
so `npm run fix` adds an empty `"trash": []` to a file without one; leaving it empty is fine —
the browser then shows the card and asks for contributions, exactly as it does for a boss with
no recorded loot. Unlike a boss's loot, trash is keyed by the *map*, so a trash row is not
attached to any encounter (an item found there still matches the browser's *Instance* filter,
just not its *Boss* filter).

### `quests`: the instance's quests and what they reward

`quests` is a list of quest objects, in the order they should be shown:

| Field | Type | Meaning |
|---|---|---|
| `id` | integer | The quest id, and the only field checked against anything: positive, and listed once per file. **Required.** |
| `name` | string | The quest's title. Curated, because this client ships no quest table — `npm run fix` never rewrites it, and a quest without one is a warning. |
| `side` | string | `"Alliance"`, `"Horde"` or `"Both"`; omitting it means the same as `"Both"`. Anything else is an error. |
| `items` | array | The items the quest rewards: the same `item` / `name` rows as loot, without a `chance`. May be empty. |

The quest ids are what the game knows the quests by, so they are the same ids a boss's `quests`
field lists (the "!" on its card) — a boss that hands in or is the objective of a quest names the
id there, the quest itself and its rewards are described once here. Item rows behave as they do
everywhere else: a row with only a `name` gets its `item` filled in when exactly one scanned item
carries that name, and the same item may appear in several quests.

In the browser the instance's *Quests* card opens a page with one subheader per quest — its title
and id, plus the faction when `side` restricts it — and that quest's reward items underneath.

`npm run fix` validates ids (map exists and is in the right folder, encounters belong to the
map, no duplicates, chance in range, quest ids positive and unique, `side` a known value), fills
names, adds every encounter the game knows that the file doesn't list yet (empty `loot`; not on a
split map, see above) and a
`trash` list to files without one, and rewrites the file in stable key order. Schema:
`CuratedInstance` / `CuratedQuest` in `src/curated.ts`. A raid only appears in the Raids module
once its `FL.InstanceFolder(mapID)` line in `ForeverLoot/modules/raids/raids.lua` is uncommented.

## Item lists (`crafting/`, `pvp/`, `collections/`, `reputation/`)

One module each in the browser; each shows tiles, one per file, and each tile lists that file's
items. Nothing here comes from a game table: **the file name is the list's id** (lowercase
letters, digits, underscores), `name` is what the tile shows, and the rows are yours. The rows
key differs per kind:

| Folder | Rows key | Row fields besides `item`/`name`/`group` | Default grouping |
|---|---|---|---|
| `crafting/` | `recipes` | `spell` (recipe spell id), `skill` (skill needed to learn it), `source` (free text: "Trainer", "Vendor: …") | one sub-folder per trade skill category ("Plate Helmets"), optionally under subheaders (`sections`); a `group` label is a folder of its own |
| `pvp/` | `rewards` | `rank` (honor rank 1–14), `standing`, `side` (`Alliance`/`Horde`) | rank, else standing |
| `collections/` | `items` | `source` (free text), `side` | none (by item type) |
| `reputation/` | `rewards` **object keyed by standing** | `side` | standing |

Every row may carry a `group` label of your own, which replaces the default grouping for that
row. Every file may carry `icon`, `background` + `backgroundCoords` (as for instances), `info`
(small text on the tile) and `order` (tile position; by name otherwise). Reputation files must
state the game's `faction` id — the addon uses it at runtime for the localized name, description
and the character's standing; crafting files may state the profession's `skillLine` id. Valid
standings: `Hated`, `Hostile`, `Unfriendly`, `Neutral`, `Friendly`, `Honored`, `Revered`,
`Exalted`; empty groups may be omitted. A reputation's `faction` must be a faction with a
reputation bar; `fix` rewrites `name` to the game's. Unknown fields, wrong rows keys and
out-of-range values are errors.

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

### Crafting: generated recipes plus curated rows

A crafting file names its profession's `skillLine` (`164` Blacksmithing, `165` Leatherworking,
`171` Alchemy, `182` Herbalism, `185` Cooking, `186` Mining, `197` Tailoring, `202` Engineering,
`333` Enchanting, `356` Fishing, `393` Skinning, `129` First Aid; `npm run check` lists them when
an id is wrong). The addon then shows **every recipe of that profession from the generated
recipe database** (`ForeverLoot/db/generated/recipes/<profession>.lua`: what it makes and how
many, reagents, tools, the skill at which it turns yellow/green/grey, the trade skill category)
and lays the file's `recipes` rows over it at runtime — so the rows are for what the game's
tables can't say:

- `skill`: the skill needed to learn the recipe from a trainer. Recipes taught by an item
  ("Plans: …") get that from the scanned recipe item automatically (its `RequiredSkillRank` in
  wago.tools' `ItemSparse`, matched by name), and the item shows as "Taught by" in the tooltip;
  trainer requirements are server-side, so without a row the orange number shown is the
  client's minimum (1).
- `source`: "Trainer", "Vendor: Name (Zone)", "Drop: Boss", …
- `group`: a label of your own instead of the game's category.
- rows for recipes the client's tables don't know (server-side ones): a plain item row, allowed
  with a warning on `spell`.

A row names its recipe by `spell` (the recipe's spell id, as in `-- Copper Chain Belt` comments of
the generated file) or just by the item: `npm run fix` fills in the other when exactly one recipe
of the profession makes that item. A recipe that makes no item (an enchant) is named by `spell`
alone — the only rows allowed without an item. A `spell` of another profession or making a
different item is an error. `npm run check` warns when a profession with recipes has no file here.

```json
{
  "name": "Blacksmithing",
  "icon": "Interface\\Icons\\Trade_BlackSmithing",
  "order": 20,
  "skillLine": 164,
  "recipes": [
    { "item": 2851, "name": "Copper Chain Belt", "spell": 2661, "skill": 1, "source": "Trainer" }
  ]
}
```

### Crafting: subheaders over the category folders (`sections`)

A profession with many trade skill categories (Blacksmithing has 34) becomes one long list of
folders. An optional `sections` array groups them under subheaders in the browser: each section
has a `name` (the subheader) and the `categories` under it, by category id — the `-- Name`
comments in `ForeverLoot/db/generated/recipes/<profession>.lua` are the place to look them up —
or by the category's enUS name, which `npm run fix` rewrites to the id. The folders appear in
the order the section lists them, sections in the order of the array, and every category no
section claims keeps its place under a final "Other". Categories of another profession, an
unknown id or name, and a category in two sections are errors.

```json
{
  "name": "Blacksmithing",
  "skillLine": 164,
  "sections": [
    { "name": "Plate Armor", "categories": [2469, 2470, 2471, 2472, 2473, 2474, 2475, 2476] },
    { "name": "Mail Armor", "categories": ["Mail Helmets", "Mail Pauldrons"] }
  ],
  "recipes": []
}
```

A `group` label used by the file's rows can be named in a section too (its folder is matched by
that label), so curated groups sit under a subheader like any category. Sections are a display
choice, not data: a module may pass its own to `ForeverLoot.ListFolders` and override the
file's (see `docs/API.md`).

Which recipes ship is decided by the scans, not by hand: the client's tables also hold recipes
of other seasons whose items this server never had, so a recipe is generated only when the item
it makes has been scanned (an enchant: when every reagent has). Scan a missing crafted item and
its recipe appears on the next `npm run gen`.

## Checklist for any data change

1. Edit or add JSON under `data/` (or `npm run import`).
2. `npm run fix` — must end without `ERROR` lines; warnings are fine.
3. `npm run gen` — writes both generated trees.
4. Commit the JSON **and** both generated trees (`npm run generate:check` is what CI runs).
