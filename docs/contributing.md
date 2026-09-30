# Contributing

Spyglass's database is built from what players record in the game, plus hand-curated drop
tables and item lists. This guide covers setting up the repository, getting in-game recordings
into it, and the format of every file under `.contribute/data/`. How those files become the
addons' generated data is in [data-pipeline.md](data-pipeline.md); the API other addons use is
in [API.md](API.md), the rules between the addons in [architecture.md](architecture.md).

## Setup

- Node 20+, then `npm install` once in the repository root.
- A Lua 5.1 `luac` on PATH, for `npm run check:lua`.
- Optional: Python 3 with `lxml` and Blizzard's exported interface code in
  `../_data/BlizzardInterfaceCode/` (from `/run ExportInterfaceFiles("code")`), for
  `npm run check:xml`; the check is skipped without them. Python 3 with Pillow for boss
  pictures ([tools/portrait/README.md](../tools/portrait/README.md)).
- Link the addons into your client once:
  `npm run dev:link -- "<World of Warcraft>/_classic_beta_/Interface/AddOns"` (or set
  `WOW_ADDONS_DIR`). After that, edit and `/reload`; `/sg` opens the window.

Before sending a change: `npm run format`, then `npm run check` (typecheck, tooling tests, addon
boundaries, data, generated staleness, Lua syntax, XML schema).

## Every data change, in four steps

1. Edit or add JSON under `.contribute/data/`, or `npm run import` a recording.
2. `npm run fix` — must end without `ERROR` lines; warnings are fine. It checks every id against
   the game data and the scans (the map exists and its file is in the right folder, `dungeons/`
   or `raids/`; the encounters belong to the map; no duplicates; values in range), rewrites
   names, fills in ids, adds missing encounters and writes every file in stable key order.
3. `npm run gen` — writes the three generated trees (`Spyglass/db/generated/`,
   `Spyglass_Database/db/generated/`, `Spyglass_Locale/db/generated/`).
4. Commit the JSON **and** the regenerated trees together; `npm run generate:check` (part of
   `npm run check`) fails when they are stale.

Never edit a generated tree by hand. Texture paths in JSON need doubled backslashes
(`"Interface\\Icons\\INV_Misc_Key_13"`). The schemas, with a comment per field, are
`src/curated.ts` (instance files) and `src/lists.ts` (item lists).

## What is in `.contribute/`

```text
.contribute/
  inbox/                    drop SavedVariables / export files here for `npm run import` (gitignored)
  data/
    config.json             pinned client build and generation settings
    items/items_<n>.json    the item database: in-game scans, one file per 10 000 ids (machine-written)
    dungeons/<slug>.json    one file per dungeon: levels, art, bosses, drops, trash, quest IDs
    quests/dungeons/<slug>.json one file per dungeon: quest definitions and prerequisites
    raids/<slug>.json       the same for raids
    crafting/<slug>.json    one file per profession: its skill line, plus additions to the generated recipes
    pvp/<slug>.json         one file per reward source and its rewards
    collections/<slug>.json one file per collection and its items
    reputation/<slug>.json  one file per faction and its rewards
```

`config.json`:

| Field          | Meaning                                                                                                                                                           |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `build`        | The wago.tools build the game tables are read from. Bump it when the client updates; downloads are cached in the root `.cache/<build>/` (delete it to refresh).   |
| `locales`      | The languages to ship instance, boss, profession and item names for from wago.tools; `enUS` first. Item names also ship for every language items were scanned in. |
| `excludeMaps`  | Maps with encounters to leave out, e.g. test maps.                                                                                                                |
| `itemsPerFile` | Rows per generated `items_NNN.lua`.                                                                                                                               |

## Items: scanning in game

WoW Forever's items are server-side, and no data export describes them, so the item database is
recorded in the game by the `Spyglass_Scraper` addon:

```text
/sg scan 1                     scan upward from id 1; stops after 1000 new items
/sg scan resume                continue where the last scan stopped (survives /reload)
/sg scan 270000 280000         scan a range
/sg scan 270000 280000 force   re-record every id in the range, known or not
/sg scan stop    /sg scan      stop; status
/sg scan limit off             no per-scan item limit (for the SavedVariables route); `limit 1000` restores it
```

A scan asks for about 100 ids per second and skips ids the shipped database already has; an
open-ended scan gives up after 20 000 consecutive missing ids. Every existing item is recorded
with everything `C_Item.GetItemInfo` and `C_Item.GetItemStats` return (name in the client's
language, quality, item level, required level, class/subclass, slot, bind, icon, sell price,
stack size, set, expansion, stats) and is browsable in the addon right away.

Getting the records into the repository, either way:

1. **SavedVariables** — copy
   `World of Warcraft/_classic_beta_/WTF/Account/<ACCOUNT>/SavedVariables/Spyglass_Scraper.lua`
   (written on logout and `/reload`) into `.contribute/inbox/`, or pass its path:
   `npm run import -- <path>`.
2. **`/sg export`** — shows the same data as JSON, to copy into a `.json` file for the inbox or an
   issue. Each export holds only the records new since the previous one (`/sg export all`
   repeats everything).

Then `npm run import` (every `.lua`/`.json` in the inbox, in name order) and `npm run gen`, and
commit `data/items/` with the regenerated trees. `import` merges each record into
`items/items_<range>.json`: the newest observation replaces the old one, and names are kept per
language (a deDE scan adds German names next to the English ones; a name is only ever what a
client of that language reported). After a `/reload` the scraper drops the records the shipped
database now states exactly; records that differ (a `force` re-scan, a changed item) stay until
they are imported.

## Drops: dungeon and raid files

### Recorded in game

The scraper also records loot: every item seen dropping that the database lacks, and per boss
(`ENCOUNTER_END`) how often you killed it and which items were seen dropping (your own loot
windows and the group's rolls). `npm run import -- --loot` turns that into loot rows in the boss's instance
file, creating the file when needed, and prints what it saw as `seen/kills`. It never changes
existing rows, and only writes a `chance` for a new row after 10 or more kills. Kills without any
loot or roll still count, so the ratios err low. Review the diff before committing.

### By hand

Find or create the instance file; all it needs is the map id (the `-- Name` comments in
`Spyglass/db/generated/instances.lua` list them). Then add rows to a boss's `loot`.

```json
{
  "map": 36,
  "minLevel": 15,
  "maxLevel": 21,
  "icon": "Interface\\Icons\\INV_Misc_Key_13",
  "background": "Interface\\GLUES\\LOADINGSCREENS\\LoadScreenDeadmines",
  "backgroundCoords": [0, 1, 0.305, 0.695],
  "encounters": [
    {
      "id": 2747,
      "name": "Edwin VanCleef",
      "portrait": "Interface\\EncounterJournal\\UI-EJ-BOSS-EdwinVancleef",
      "level": 20,
      "creatureType": "Humanoid",
      "quests": [166],
      "loot": [{ "item": 5188, "name": "Filled Vessel", "chance": 0.9 }, { "name": "Cruel Barb" }]
    }
  ],
  "trash": [{ "item": 1935, "name": "Buzzer Blade", "chance": 0.01 }],
  "quests": [166]
}
```

The instance:

| Field                            | Meaning                                                                                                                 |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| `map`                            | The game's map id. Required.                                                                                            |
| `id`, `name`                     | Only on a split dungeon, see below.                                                                                     |
| `displayName`                    | A shorter name for the browser, see below.                                                                              |
| `minLevel`, `maxLevel`           | The level range shown on the tile and in the info panel.                                                                |
| `requiredLevel`                  | The level a character needs to enter; shown in the info panel.                                                          |
| `zone`                           | uiMapID of the zone the entrance is in; the info panel shows the game's name for it, in the player's language.          |
| `entrance`                       | `[uiMapID, x, y]` of the entrance (x, y in 0–100, as the map shows them): the info panel's "Show entrance" button.      |
| `icon`                           | Texture path.                                                                                                           |
| `background`, `backgroundCoords` | The tile's picture: a texture path or fileID, and `[left, right, top, bottom]` in 0–1 of it (all of it when omitted).   |
| `encounters`                     | The bosses. `fix` adds every encounter the game knows for the map that the file doesn't list yet, with an empty `loot`. |
| `trash`, `quests`                | Trash loot and quest IDs; quest definitions live under `.contribute/data/quests/dungeons/`.                             |

Dungeon level ranges can be scanned in-game with `/sg levels`. Copy the JSON into
`.contribute/inbox/dungeon-levels.json` and run `npm run import`, then `npm run gen`. The import
writes one `.contribute/data/dungeon-levels.json` snapshot and updates `minLevel`/`maxLevel` in
the matched dungeon files; there is nothing to set manually in those files. `npm run check` compares
those ranges against the snapshot once it exists. Unscanned dungeons keep their curated levels.
`requiredLevel` is separate and is
not changed by this scan. The importer matches normal dungeons by map ID and split wings by their
activity names; an ambiguous or missing match is reported for review.

The scan records its client build; it can differ from the pinned reference-table build. Split wings
need activity names that match the curated English names.

A boss (`encounters[]`):

| Field                   | Meaning                                                                                                                                                                                                                                                           |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                    | The encounter id. Required.                                                                                                                                                                                                                                       |
| `name`                  | Filled in by `fix` when missing, otherwise left alone. When it differs from the game table's, it is the name shown in every language: the server renamed the boss and the client's table still has the old name (Hall of Thanes' "Magmatus" is "Infurnus" there). |
| `level`, `creatureType` | As the game shows them; the card says "20 Humanoid".                                                                                                                                                                                                              |
| `rare`                  | Set to `true` for a boss that does not spawn on every visit; the card says "19 rare" after its level.                                                                                                                                                             |
| `portrait`, `displayID` | The boss's picture, see below.                                                                                                                                                                                                                                    |
| `npc`                   | Where the `displayID` came from; not shipped.                                                                                                                                                                                                                     |
| `quests`                | Ids of the quests the boss is involved in (the "!" on its card). Definitions live under `.contribute/data/quests/dungeons/`.                                                                                                                                      |
| `loot`                  | Item rows with an optional `chance` (0–1).                                                                                                                                                                                                                        |

**Item rows**, everywhere in `.contribute/data/`: `item` is the item id, `name` is informational
and rewritten by `fix`. A row with only a `name` gets its `item` filled in when exactly one
scanned item has that name. An unscanned item id is allowed with a warning: the browser shows it
once the client has fetched it, but it isn't searchable until it is scanned.

### Split dungeons

Some maps are several dungeons to players: Scarlet Monastery (map 189) is Graveyard, Library,
Armory and Cathedral; Blackrock Spire (229) is Lower and Upper; Dire Maul (429) is East, West and
North. Such a map has one file per part, all with the same `map`, each with its own `id` (by
convention map × 100 + n: `18901`…`18904`) and its own `name` (no game table has one, so `fix`
leaves it alone). The addon knows the part by that `id`: its tile, boss cards, trash and quests.
Each of the map's encounters goes in exactly one of the files: one listed in two files is an
error, one in none a warning (`fix` can't know which part it belongs to, so it doesn't add it).

### A shorter name: `displayName`

Any instance file may set `displayName` (e.g. `"SM: Graveyard"`), which the browser shows instead
of the full name on the instance's tile, breadcrumbs and page title, in every language. Item
tooltips and the _Instance_ filter keep the full name. `fix` leaves it alone; an empty one is an
error.

### The info panel of an instance

While an instance is open, the window's right column shows the zone its entrance is in, its
level range, the level needed to enter and its boss count, a
"Show entrance" button when the file has an `entrance` (it opens the map with a waypoint there;
the game tables of this client carry no dungeon entrances, so they are curated), and the
instance's `quests` with the character's progress on each: done, ready to turn in, active or not
started. Quests of the other faction and other classes' quests are left out. Each quest shows the game's quest
tooltip on hover and can be shift-clicked into chat. Quests are server-side, so the client often
doesn't have a quest yet; its tooltip then shows the curated title, `requiredLevel` and
`objective` instead. Either way the tooltip ends with the quest's rewards: the `items` with their
icons and the `xp`.

### A boss's picture: `portrait` or `displayID`

`portrait` is a texture path or fileID, normally the Encounter Journal's boss art
(`Interface\EncounterJournal\UI-EJ-BOSS-<Name>`). Bosses this server added have none — this
client ships no Encounter Journal data at all — so they carry either a picture made with the
portrait tool ([tools/portrait/README.md](../tools/portrait/README.md), which writes
`"portrait": "Interface\\AddOns\\Spyglass\\assets\\bosses\\<slug>.blp"`) or `displayID`, the
**CreatureDisplayID** of the model, which the client renders into a portrait by itself (the same
call and the same 2:1 shape the game's own boss buttons use). `portrait` wins when both are set;
with neither, the card shows a generic boss icon.

A display id is not in any client table for these NPCs, so it is collected in game. With the boss
(or any copy of it) as your target:

```text
/run local m=CreateFrame("PlayerModel") m:SetUnit("target") print(m:GetDisplayInfo(), UnitGUID("target"))
```

The number is the `displayID`. The GUID's sixth field is the NPC id, which goes in the optional
`npc` field: it is not shipped, it only records where the display id came from so it can be
checked again later. Both must be positive integers; `npm run check` verifies that much, not that
the model is the right one.

```json
{ "id": 3493, "name": "Faldrim Anvilmar", "displayID": 142826, "npc": 261306, "loot": [] }
```

### `trash`: what the enemies between the bosses drop

`trash` holds the same rows as a boss's `loot`, for everything that drops off the instance's
non-boss enemies. Every instance has the category, so `fix` adds an empty `"trash": []` to a file
without one; leaving it empty is fine — the browser then shows the card and asks for
contributions, as it does for a boss with no recorded loot. Trash is keyed by the instance, not
by an encounter: an item found there matches the browser's _Instance_ filter, not its _Boss_
filter.

### Dungeon quests

Each dungeon has a `.contribute/data/quests/dungeons/<dungeon>.json` file. Its `quests` array
holds the quest definitions associated with that dungeon; it may be empty. The dungeon file's
`quests` field lists the IDs to show in its info panel, in that order. A prerequisite or follow-up
quest can have a definition in the quest file without being listed on the dungeon page. A quest
spanning several dungeons is defined in just one quest file and its ID is listed in each dungeon file.

For example, a quest file can contain these illustrative definitions:

```json
{
  "npcs": {
    "Quest Giver": { "location": [1436, 43, 72], "description": "Upstairs." }
  },
  "quests": [
    {
      "id": 1,
      "name": "Earlier quest",
      "objective": "Complete the earlier task.",
      "items": []
    },
    {
      "id": 2,
      "name": "Dungeon quest",
      "side": "Alliance",
      "requires": [1],
      "followUps": [3],
      "start": { "npc": "Quest Giver" },
      "turnIn": { "npc": "Quest Giver", "description": "Inside the inn." },
      "items": []
    },
    {
      "id": 3,
      "name": "Follow-up quest",
      "requires": [2],
      "items": []
    }
  ]
}
```

The optional top-level `npcs` map shares a location and description by NPC name within this file.
Both `start` and `turnIn` use those details when their `npc` matches; fields written on an individual
endpoint override the shared values. A turn-in at the same NPC therefore gets the same map button
without repeating its coordinates. Keep quest-specific directions on the endpoint.

The definition fields are:

| Field             | Type    | Meaning                                                                                                                                                                                                      |
| ----------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `id`              | integer | The quest id: positive and defined only once across all quest files. A quest without one is a warning and isn't shipped until it has one.                                                                    |
| `name`            | string  | The quest's title. Curated, because this client ships no quest table: `fix` never rewrites it, and a quest without one is a warning.                                                                         |
| `side`            | string  | `"Alliance"`, `"Horde"` or `"Both"`; omitting it means `"Both"`. Anything else is an error.                                                                                                                  |
| `class`           | string  | A class quest's class: `"Warrior"`, `"Paladin"`, `"Hunter"`, `"Rogue"`, `"Priest"`, `"Shaman"`, `"Mage"`, `"Warlock"` or `"Druid"`; omitted means any class.                                                 |
| `requiredLevel`   | integer | The level a character needs to accept the quest; shown beside its title and in its tooltip.                                                                                                                  |
| `xp`              | integer | The experience the quest rewards; shown on its banner and in its tooltip.                                                                                                                                    |
| `objective`       | string  | What the quest asks for, in one English sentence; shown on its page and in its tooltip.                                                                                                                      |
| `description`     | string  | Optional curated description, shown on its page and in its tooltip before the client has the quest.                                                                                                          |
| `requires`        | array   | IDs of direct prerequisite quests, in the order they should appear. Each needs its own definition in a quest file, even if it is not shown on a dungeon page.                                                |
| `followUps`       | array   | IDs of later quests, in the order they should appear after this quest. Each needs its own definition, even if it is not shown on a dungeon page.                                                             |
| `start`, `turnIn` | object  | Optional giver and turn-in: `npc` name, `npcID`, starting `item` ID, `location` as `[uiMapID, x, y]` (x/y in 0–100), and `description` for extra info shown beside that endpoint. Use only the fields known. |
| `items`           | array   | The items the quest rewards: item rows without a `chance`. May be empty.                                                                                                                                     |

The quest ids are also the ones a boss's `quests` field lists: a boss that hands out or is the
objective of a quest names the id there. The same item may appear in several quests. `npm run
check:data` reports duplicate quest definitions, unresolved dungeon quest IDs, prerequisites and
follow-ups. `npm run fix` rewrites reward item names but leaves quest and NPC names alone.

In the browser, the instance's _Quests_ card lists one clickable banner per quest, sorted by
`requiredLevel`, then title. Each quest page shows the objective, known start and turn-in sources,
map buttons for known locations, and rewards. Prerequisites are collapsed below the rewards;
expanding them shows the complete chain, earliest quest first. A prerequisite opens its own page,
and Back returns to the main quest without another nested prerequisite list. Quest definitions
used only as prerequisites are shipped without adding them to a dungeon's quest list. Follow-ups
appear in their own collapsible section below prerequisites, with the same indented quest pages
and rewards; Back returns to the main quest. Follow-up definitions can also stay off the dungeon
list. A quest that runs through several instances (the warlock quest "The Orb of Soran'ruk" needs Blackfathom
Deeps and Shadowfang Keep) is referenced by each dungeon but defined once under
`quests/dungeons/`.

### Showing an instance in the browser

The Dungeons and Raids modules list their instances explicitly, one
`SG.InstanceFolder(<id>)` line each in `Spyglass/modules/dungeons/dungeons.lua` and
`Spyglass/modules/raids/raids.lua`, commented out until the instance has curated loot.
Uncomment (or add) the line when you add the first drops; a split dungeon's parts are listed by
their own `id`.

## Item lists: `crafting/`, `pvp/`, `collections/`, `reputation/`

One module each in the browser; each shows one tile per file, and each tile lists that file's
items. Nothing here comes from a game table: **the file name is the list's id** (lowercase
letters, digits, underscores), `name` is what the tile shows, and the rows are yours. The key the
rows live under differs per kind:

| Folder         | Rows key                               | Row fields besides `item`/`name`/`group`                                                                    | Default grouping                                                                                                                            |
| -------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `crafting/`    | `recipes`                              | `spell` (recipe spell id), `skill` (skill needed to learn it), `source` (free text: "Trainer", "Vendor: …") | one sub-folder per trade skill category ("Plate Helmets"), optionally under subheaders (`sections`); a `group` label is a folder of its own |
| `pvp/`         | `rewards`                              | `rank` (honor rank 1–14), `standing`, `side` (`Alliance`/`Horde`)                                           | rank, else standing                                                                                                                         |
| `collections/` | `items`                                | `source` (free text), `side`                                                                                | none (by item type)                                                                                                                         |
| `reputation/`  | `rewards` **object keyed by standing** | `side`                                                                                                      | standing                                                                                                                                    |

Every row may carry a `group` label of your own, which replaces the default grouping for that
row. Every file may carry `icon`, `background` + `backgroundCoords` (as for instances;
`background` may also be an atlas name, the coords then cut its region — the crafting files use
the client's `Profession-overview-Card-<Profession>` art this way), `info` (small text on the
tile) and `order` (tile position; by name otherwise).

Reputation files must state the game's `faction` id, a faction with a reputation bar; the addon
uses it at runtime for the localized name, description and the character's standing, and `fix`
rewrites `name` to the game's. Valid standings: `Hated`, `Hostile`, `Unfriendly`, `Neutral`,
`Friendly`, `Honored`, `Revered`, `Exalted`; empty groups may be omitted.

```json
{
  "name": "Argent Dawn",
  "icon": "Interface\\Icons\\Achievement_Reputation_01",
  "faction": 529,
  "rewards": {
    "Friendly": [{ "item": 13209, "name": "Seal of the Dawn" }],
    "Honored": [{ "name": "Argent Dawn Tabard", "side": "Alliance" }]
  }
}
```

Unknown fields, a wrong rows key and out-of-range values are errors. A file with no rows still
gets its tile; the page then asks for contributions.

### Crafting: generated recipes plus curated rows

A crafting file names its profession's `skillLine`: `171` Alchemy, `164` Blacksmithing, `3012`
Comprehension, `185` Cooking, `333` Enchanting, `202` Engineering, `129` First Aid, `356` Fishing,
`182` Herbalism, `165` Leatherworking, `186` Mining, `40` Poisons, `393` Skinning, `197`
Tailoring (`npm run check` lists the valid ones when an id is wrong, and warns about a profession
with recipes but no file). The addon then shows **every recipe of that profession from the
generated recipe database** (`Spyglass/db/generated/recipes/<profession>.lua`: what it makes
and how many, reagents, tools, the skill at which it turns yellow/green/grey, the trade skill
category) and lays the file's `recipes` rows over it at runtime. So the rows are for what the
game's tables can't say:

- `skill`: the skill needed to learn the recipe from a trainer. Recipes taught by an item
  ("Plans: …") get it from the scanned recipe item automatically, and the item shows as "Taught
  by" in the tooltip. Trainer requirements are server-side, so without a row the orange number
  shown is the client's minimum (1).
- `source`: "Trainer", "Vendor: Name (Zone)", "Drop: Boss", …
- `group`: a label of your own instead of the game's category.
- Rows for recipes the client's tables don't know (server-side ones): a plain item row, allowed
  with a warning on `spell`.

A row names its recipe by `spell` (the recipe's spell id, as in the `-- Copper Chain Belt`
comments of the generated file) or just by the item: `fix` fills in the other when exactly one
recipe of the profession makes that item. A recipe that makes no item (an enchant) is named by
`spell` alone — the only rows allowed without an item. A `spell` of another profession, or one
making a different item, is an error.

```json
{
  "name": "Blacksmithing",
  "icon": "Interface\\Icons\\Trade_BlackSmithing",
  "order": 20,
  "skillLine": 164,
  "recipes": [{ "item": 2851, "name": "Copper Chain Belt", "spell": 2661, "skill": 1, "source": "Trainer" }]
}
```

Which recipes ship is decided by the scans, not by hand: the client's tables also hold recipes of
other seasons whose items this server never had, so a recipe is generated only when the item it
makes has been scanned (an enchant: when every reagent has). Scan a missing crafted item and its
recipe appears on the next `npm run gen`.

### Crafting: subheaders over the category folders (`sections`)

A profession with many trade skill categories (Blacksmithing has 34) becomes one long list of
folders. An optional `sections` array groups them under subheaders: each section has a `name`
(the subheader) and the `categories` under it, by category id (the `-- Name` comments in
`Spyglass/db/generated/recipes/<profession>.lua` list them) or by the category's English name,
which `fix` rewrites to the id. The folders appear in the order the section lists them, sections
in array order, and every category no section claims follows under a final "Other". A category
of another profession, an unknown id or name, and a category in two sections are errors.

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
that label). Sections are a display choice, not data: a module may pass its own to
`Spyglass.ListFolders` and override the file's (see [API.md](API.md#category-sections-crafting)).

### The info panel: `panel`

The window's right column shows the _info panel_ of the list that is open (also while one of
its category folders is): its name as the title, then the widgets of the file's `panel`, top to
bottom. Without a `panel` a reputation shows the character's standing bar and the faction's
description, a profession the skill bar and its recipe count, the other kinds just the name. A
file's `panel` replaces that default, so repeat the bar if you want to keep it.

Each widget is an object with exactly one of these keys, plus that widget's options:

| Widget        | Options             | Shows                                                                                                                                                                                                    |
| ------------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `header`      |                     | a section plate with the text                                                                                                                                                                            |
| `text`        |                     | wrapped text                                                                                                                                                                                             |
| `description` |                     | `true`: the list's own description (a faction's, from the game, in the player's language)                                                                                                                |
| `row`         | `value`             | a label on the left, `value` on the right                                                                                                                                                                |
| `bar`         |                     | `"reputation"`: the character's standing with the file's `faction`; `"skill"`: the character's rank in the file's `skillLine`                                                                            |
| `checkbox`    | `filter`            | a checkbox that hides entries while checked. Filters: `"side"` (rows of the other faction), `"standing"` (reputation: rewards above the character's standing)                                            |
| `dropdown`    | `field`             | a dropdown with every value the list's rows have in `field` (`standing`, `source`, `group`, ...); picking one shows only those rows                                                                      |
| `button`      | `open` **or** `map` | `open`: goes to another collection, `"<module>/<list id>"`, optionally deeper (a crafting category by id: `"crafting/blacksmithing/2469"`). `map`: `[uiMapID, x, y]` opens the map there with a waypoint |
| `spacer`      |                     | `true`: a little empty space                                                                                                                                                                             |

Checkboxes and dropdowns act on the list in that tab only and are forgotten when the tab is
closed. `npm run check` reports unknown widgets and options, a bar without the file's id, a
filter or field the kind doesn't have, and an `open` naming a module or list that doesn't exist.

```json
{
  "name": "Cenarion Circle",
  "faction": 609,
  "panel": [
    { "bar": "reputation" },
    { "description": true },
    { "header": "Rewards" },
    { "checkbox": "Only reached standings", "filter": "standing" },
    { "dropdown": "Standing", "field": "standing" },
    { "button": "Show Cenarion Hold", "map": [1451, 51.2, 38.3] },
    { "button": "Open Timbermaw Hold", "open": "reputation/timbermaw_hold" }
  ],
  "rewards": {}
}
```

## Code changes

The addons are plain Lua/XML loaded by the game; there is no build step. The rules between the
addons are in [architecture.md](architecture.md), and a change to the public `Spyglass` API
updates [API.md](API.md) in the same commit. Internals: [ui.md](ui.md) (the browser window),
[scraper.md](scraper.md) (scanning and loot recording), [localization.md](localization.md)
(names in every language), [data-pipeline.md](data-pipeline.md) (the generator).
