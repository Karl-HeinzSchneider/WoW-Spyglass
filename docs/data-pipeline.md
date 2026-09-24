# Data pipeline

How the root TypeScript tools (`src/`) turn `.contribute/data/` and the game's tables into the
three generated trees the addons load. The file formats contributors edit are described in
[contributing.md](contributing.md); this document is about where the data comes from and what
the tools do with it.

## Where the data comes from

| Data                   | Source                                                                                                                                                                                                                                                      |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Items                  | **Only the in-game scans** (`.contribute/data/items/`). WoW Forever's items are server-side: wago.tools' item tables are incomplete and wrong for this client, and item ids from Classic or wowhead don't match. Only scanned items exist in the database.  |
| Instances, encounters  | wago.tools `Map` + `DungeonEncounter` for the build pinned in `config.json`. Instance ids are `Map.ID` (a split dungeon's parts: the file's own `id`), boss ids are `DungeonEncounter.ID`.                                                                  |
| Profession recipes     | wago.tools `SkillLine`, `SkillLineAbility`, `SpellReagents`, `SpellEffect`, `SpellTotems`, `TradeSkillCategory`, `TotemCategory`, `SpellName`. Recipe ids are spell ids, profession ids `SkillLine.ID`. Shipped only when the scans confirm what they make. |
| Factions               | wago.tools `Faction`, the rows with a reputation bar; reputation files are checked against it.                                                                                                                                                              |
| Non-English item names | wago.tools `ItemSparse`, for a scanned item whose English name there is the scanned one; a name scanned on a client of that language wins.                                                                                                                  |
| Drops, item lists      | Hand-curated JSON; it meets the scans only through item ids. A curated row may reference an unscanned id (a warning, not an error).                                                                                                                         |

`ItemSparse` agrees with the scans on the items it has but lacks thousands of this server's
items, so it is read for exactly two things: the skill a scanned recipe item requires, and the
non-English names above. It is never an item source.

Several maps (Blackfathom Deeps, Gnomeregan, Sunken Temple) carry the same bosses more than once,
for other difficulties (Season of Discovery raids, a second 5-player set). The client has one
version of each dungeon, the normal 5-player one: per map, only the encounters of the first
difficulty in `ENCOUNTER_DIFFICULTIES` (`src/reference.ts`: 0, 1, 201) the map has are kept, and
the other ids are unknown to the tooling.

wago.tools tables are downloaded as CSV and cached in `.cache/<build>/` (`src/wago.ts`).

## What each generated file comes from

| Output                                                                                         | Source                                                                                                                                 |
| ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `ForeverLoot_Database/db/generated/items/items_NNN.lua`                                        | the scans, `itemsPerFile` rows per file                                                                                                |
| `ForeverLoot_Database/db/generated/locales/enUS/items.lua`                                     | the scanned items' English names                                                                                                       |
| `ForeverLoot/db/generated/instances.lua`                                                       | `Map` + `DungeonEncounter` (only maps with encounters), levels/icons/portraits from `dungeons/` and `raids/`                           |
| `ForeverLoot/db/generated/loot/<slug>.lua`                                                     | the boss loot, trash and quests of every instance file that has any                                                                    |
| `ForeverLoot/db/generated/<kind>/<slug>.lua` (crafting, pvp, collections, reputation)          | the item lists, one file each, rows or not                                                                                             |
| `ForeverLoot/db/generated/recipes/<profession>.lua`                                            | the recipe tables, one file per profession, only recipes whose product (enchants: every reagent) is scanned                            |
| `ForeverLoot/db/generated/locales/enUS/*.lua`                                                  | the English fallback names: `instances`, `bosses`, `crafting` (profession, trade skill category and tool names)                        |
| `ForeverLoot_Locale/db/generated/locales/<locale>/items.lua`                                   | the scanned items' names in every configured or scanned non-English locale: `ItemSparse`, overridden by names scanned in that language |
| `ForeverLoot_Locale/db/generated/locales/<locale>/instances.lua`, `bosses.lua`, `crafting.lua` | the wago.tools names for every configured non-English locale                                                                           |
| `ForeverLoot/db/generated/generated.xml`, `ForeverLoot_Database/db/generated/generated.xml`    | each addon's loader, listed in its TOC; the locale addon has none (its TOC lists `locales\[TextLocale]\*.lua` instead)                 |

## The run (`src/cli.ts`)

`loadConfig()` → `loadReference()` (the game tables and the scans) → `loadCurated()` +
`loadLists()` → for `import`: `loadDiscovered` + `importDiscovered` per file, then
`saveScannedItems` → `Checker` + `validate` + `validateLists` → for `fix` and `import`: rewrite
the JSON → `build` + `write`. Errors stop generation; fixable problems and warnings don't.
`import` always fixes, since it writes the curated files anyway.

## Validation

Every validator reports through the shared `Checker` (`src/curated.ts`) instead of throwing, so
one run lists every problem: `report` is an error or, with `fixable`, something `--fix` corrects;
`warn` is printed and never fails. `checkItemRow`, used for every item row, resolves a name-only
row to an id when exactly one scanned item has that name, rejects duplicates, rewrites names from
the scans and warns on unscanned ids.

- **Instance files** (`validate`): ids against the game tables, the file's folder against the
  map's `InstanceType`, duplicates, the chance range; missing encounters are added on fix (not on
  a split map). Each file gets a `trash` list on fix. Quest ids must be positive and unique (a
  missing one is a warning and the quest isn't shipped), `side` one of `QUEST_SIDES`, `class` one
  of `QUEST_CLASSES`, shipped as the client's class token (`classToken`). On a split map (several
  files with one `map`, each with its own `id`) every encounter must be in exactly one file:
  twice is an error, none a warning.
- **Item lists** (`validateLists`, `src/lists.ts`): the rows key and row fields per kind
  (`ROWS_KEY`, `ROW_FIELDS`, per-field specs); reputation's standing-keyed object is flattened by
  `rowsOf`. A reputation `faction` must be in the `Faction` table, and fix rewrites `name` from
  it. A crafting `skillLine` must be a profession with recipes; `checkRecipeSpell` checks a row's
  `spell` against the recipe database (profession and created item; unknown spells warn) and on
  fix fills `item` from `spell`, `fillRecipeSpell` fills `spell` from `item` when exactly one
  recipe of the profession makes it. `validateSections` checks `sections`: every category belongs
  to the file's profession and to one section only; a category given by name is fixed to its id.
  A profession with recipes but no file is a warning.

## Recipes (`src/recipes.ts`)

`buildRecipes` (pure, tested) turns the tables into `Recipe`s keyed by spell id: a profession
ability whose spell creates an item (effect 24 or 157) or enchants one (53 or 54, with reagents).

- Thresholds: yellow = `TrivialSkillLineRankLow`, grey = `TrivialSkillLineRankHigh`, green =
  their midpoint (the client's own formula). `count` comes from `EffectBasePointsF` ± `Variance`.
- `[DNT]` skill lines and professions without recipes are dropped; class-restricted rows are not
  (rogue poisons are SkillLine 40 "Poisons", a secondary profession). Tier skill lines (2938
  "Blacksmithing" under 164) fold into their root profession.
- `shipsRecipe` is the rule the generator and the checker share: the created item must be
  scanned (an enchant: every reagent), because the tables also hold other seasons' recipes.
- `linkRecipeItems` matches scanned recipe items (item class 9, "Plans: X") to the recipe named
  X: `ItemSparse.RequiredSkill` picks the profession, `RequiredSkillRank` becomes the recipe's
  `learnSkill`, and the item becomes its `taughtBy`. `relinkRecipes` (`src/reference.ts`) reruns
  it after an import.

## Generation (`src/generate.ts`)

`build()` produces all three trees in memory; `write()` diffs them against disk (ignoring CRLF),
removes stale files and returns the number of changes. `npm run generate:check` only reports.

- `itemRow()` must match `Data.ITEM` and `recipeRow()` `Data.RECIPE` in
  `ForeverLoot/src/data/data.lua`; both rows are positional. A recipe's `minSkill` is
  `learnSkillOf()`: the recipe item's requirement when one is known.
- `instances.lua` has one instance per map, or per file with its own `id` on a split map, with the
  encounters that file lists; the English name of such a part is its file's `name`.
- `loot/<slug>.lua` is written for every instance file `hasLoot` is true for: a boss's drops via
  `AddBossLoot`, the trash via `AddTrashLoot`, the quests via `AddQuests`.
- A crafting list without an `icon` gets its skill line's `SpellIconFileID`; a crafting row
  without an item (an enchant) is emitted as `{ spell = id, ... }`.
- `recipes/<profession>.lua` holds `AddCategories` + `AddRecipes`, rows in category order.
- Names: enUS goes to the core (enUS item names to the database addon), every other locale to the
  locale addon. A boss an instance file names differently from the game table gets the file's
  name in enUS and no entry in the other locales, so they fall back to it. Every `LOCALE_FILES`
  entry is written for every `CLIENT_LOCALES` language (`src/config.ts`), as a comment-only
  placeholder where there are no names, because the locale addon's TOC loads
  `locales\[TextLocale]\<file>.lua` and a missing file is a `LUA_WARNING` at login.
- The provenance header (`header()` in `src/lua.ts`) and the `generated.xml` comment still say
  `.contribute/tools (npm run gen)`: the tools moved to `src/` in the monorepo refactor, and
  keeping the old label avoided rewriting every generated file. Changing it is a mass diff of the
  generated trees; do it only on purpose.

## Import (`src/import.ts`, `src/discovered.ts`)

`loadDiscovered(path)` reads what the scraper recorded, from a `/fl export` `.json` or the
`ForeverLoot_Scraper.lua` SavedVariables file (`ForeverLootScraperDB.global.discovered`, the only
layout; `src/savedvars.ts` parses the Lua subset the client writes, it is not a Lua interpreter).
Records carry their own `id`, which wins over the container key.

`importDiscovered` merges items into the scans (the newest observation wins, names are kept per
locale) and observed drops into the instance files: it creates a file when needed (slug from the
instance name) and, on a split map, uses the file that lists the encounter, else skips it. New
rows get a `chance` only after `MIN_KILLS_FOR_CHANCE` = 10 kills; existing rows are never
changed, only reported.

## The item store (`src/items.ts`)

`.contribute/data/items/items_<start>.json` holds `ID_RANGE` = 10 000 ids per file, keyed by id,
sorted, in a fixed field order; empty ranges are removed. Field meanings are those of `Data.ITEM`
in the core, plus `names` per locale. The files are machine-written.

Every JSON file under `.contribute/data/` is written through `writeJson` (`src/json.ts`):
`JSON.stringify(value, null, 2)` formatted with the repository's Prettier config, so a
tool-written file is exactly what `npm run format` makes of it, and an unchanged file is not
rewritten.
