# src — root TypeScript tooling

The Node 20+ / TypeScript (ESM, run with `tsx`, no build) tools that read `.contribute/data/`,
write the generated addon data, validate the monorepo, link addons for development and package
releases. Runtime addons never import from here and never read contributor JSON; this code may
read `.contribute/` and write only inside `*/db/generated/`. Scripts are in `package.json`;
the data they consume is described in `.contribute/CLAUDE.md`.

## Entry points (one per `npm run …`)

- `cli.ts` — `generate` (default; `--check` = staleness only), `check` (`--fix` = `npm run fix`),
  `import [file]`. Pipeline: `loadConfig()` → `loadReference()` → `loadCurated()` + `loadLists()`
  → (`import`: `loadDiscovered` + `importDiscovered` per file, then `saveScannedItems`) →
  `Checker` + `validate` + `validateLists` → (fix: rewrite the JSON) → `build` + `write`.
  `import` always fixes (it writes the curated files anyway). Errors stop generation; fixable
  problems and warnings don't.
- `check-addons.ts` — discovers addons, checks that every TOC load entry exists, that
  `ForeverLoot_*` addons declare `## Dependencies: ForeverLoot`, that there are no dependency
  cycles, and that **no `.lua`/`.xml`/`.toc` under `ForeverLoot/` contains a companion's name**
  (plain substring, comments included).
- `check-lua.ts` — `luac -p` on every `.lua` in every addon (requires Lua 5.1's `luac`).
- `check-xml.ts` — validates every addon `.xml` against `../_data/BlizzardInterfaceCode/Interface/AddOns/Blizzard_SharedXML/UI.xsd`
  with python + lxml; exits 0 with a notice when that folder is absent.
- `link-addons.ts` — `npm run dev:link -- <AddOns dir>` (or `WOW_ADDONS_DIR`): a junction/symlink
  per addon; refuses to replace a path that isn't already our link.
- `package-addons.ts` — deterministic zip (fixed timestamps, hand-rolled writer, no dependency)
  of every addon into `dist/ForeverLoot-<version>.zip`; version from the TOCs (`mixed` if they
  differ).

## Modules

- `config.ts` — repo paths (`ROOT`, `DATA_DIR`, `OUTPUT_DIR`, `LOCALE_OUTPUT_DIR`, `INBOX_DIR`,
  `CURATED_DIRS`, `LIST_KINDS`/`LIST_DIRS`, `SCANNED_ITEMS_DIR`), `FALLBACK_LOCALE = "enUS"`,
  and `loadConfig()` for `.contribute/data/config.json` (`build`, `locales`, `excludeMaps`,
  `itemsPerFile`).
- `addons.ts` — `addonDirectories()`: every direct child of the root with a same-named `.toc`
  (no hard-coded list), `addonVersion`, `walkFiles`.
- `wago.ts` — `fetchTable(table, build, locale)`: wago.tools DB2 CSV, cached in `.cache/<build>/`.
- `reference.ts` — `Reference`: instances (`Map` rows with `InstanceType` 1/2 = dungeon/raid that
  have at least one encounter, minus `excludeMaps`), encounters (`DungeonEncounter`, ordered by
  `OrderIndex`; one difficulty per map, the normal 5-player set, see `ENCOUNTER_DIFFICULTIES`), the recipe tables from `recipes.ts` (`skillLines`, `recipes`, `categories`,
  `itemSkills`), `factions` (`Faction` rows with a reputation bar), the scanned items,
  `wagoItemNames` (`ItemSparse.Display_lang` per configured locale), per-locale name tables
  (items, encounters, instances, skillLines, categories, tools), `nameOf()` for comments and
  messages. `refreshItemNames` builds the item tables: `ItemSparse`'s name in each non-English
  locale for a scanned item whose enUS name there is the scanned one, then the names the scans
  carry, which win.
- `recipes.ts` — the profession recipe database from wago.tools: `buildRecipes(source, localeNames)`
  (pure, tested) turns `SkillLine`, `SkillLineAbility`, `SpellReagents`, `SpellEffect`,
  `SpellTotems`, `TradeSkillCategory`, `TotemCategory` and `SpellName` into `Recipe`s keyed by
  spell id — a profession ability whose spell creates an item (effect 24/157) or enchants one
  (53/54, needs reagents); yellow = `TrivialSkillLineRankLow`, grey = `TrivialSkillLineRankHigh`,
  green = their midpoint (the client's formula), `count` from `EffectBasePointsF` ± `Variance`;
  `[DNT]` skill lines and professions without recipes are dropped, class-restricted rows are not
  (rogue poisons are SkillLine 40 "Poisons", a secondary profession); tier skill lines (2938 "Blacksmithing" under 164) fold into their root. `shipsRecipe`
  is the rule the generator and the checker apply: the created item must be scanned (enchants:
  every reagent), because the tables also hold other seasons' recipes. `linkRecipeItems` matches
  scanned recipe items (class 9, "Plans: X") to the recipe named X — `ItemSparse.RequiredSkill`
  picks the profession and `RequiredSkillRank` becomes `learnSkill`, the item `taughtBy`;
  `relinkRecipes(ref)` in reference.ts reruns it after an import. `loadRecipes(config)` fetches
  and builds.
- `items.ts` — `ScannedItem` (field meanings = `Data.ITEM` in the core) and the
  `.contribute/data/items/items_<start>.json` store: one file per `ID_RANGE` = 10 000 ids, keyed
  by id, sorted, fixed field order, empty ranges removed. Machine-written.
- `curated.ts` — `CuratedInstance/Encounter/Loot/Quest` (the dungeon/raid JSON), `loadCurated`,
  `validate` (ids against the reference, folder vs `InstanceType`, duplicates, chance range,
  missing encounters added on fix; the instance's own `trash` list — added empty on fix, since
  every instance has one — and its `quests`, whose ids must be positive and unique (a missing
  id is a warning, and `generate.ts` leaves that quest out until it has one) and whose
  `side` must be one of `QUEST_SIDES` and `class` (a class quest) one of `QUEST_CLASSES`,
  shipped as the client's class token via `classToken`; a quest title can only be warned about, no game table
  has one; a split map — several files with one `map`, each with its own `id` — must list each
  encounter in exactly one of its files: twice is an error, none a warning, never added on fix),
  `instanceIDOf` (the file's `id`, else its map), `serialize` (stable key order), and the shared `Checker`
  whose `checkItemRow` every validator uses: resolves name-only rows to an id when unambiguous,
  rejects duplicates, rewrites names from the scans, warns on unscanned ids.
- `lists.ts` — `CuratedList/Row` (the crafting/pvp/collections/reputation JSON), `ROWS_KEY`,
  `ROW_FIELDS`, `STANDINGS`, per-field specs, `rowsOf` (flattens reputation's standing-keyed
  object into rows with `standing`), `validateLists`, `serializeList`. Crafting files: `skillLine`
  must be a profession with recipes; `checkRecipeSpell` checks a row's `spell` against the recipe
  database (profession and created item; unknown spells warn) and on fix fills `item` from
  `spell`, `fillRecipeSpell` fills `spell` from `item` when one recipe of the profession makes it;
  rows for recipes that make no item (enchants) carry only `spell` and skip the item check;
  `validateSections` checks the optional `sections` (subheaders over the profession's category
  folders): every category must belong to the file's profession and to one section only, a
  category given by name is fixed to its id; a warning names each profession with recipes but
  no file. Reputation files: `faction` must be in
  `ref.factions`, `fix` rewrites `name` from it.
- `savedvars.ts` — a parser for the Lua subset the client writes to SavedVariables (tables,
  `["key"]`/`[123]`/positional entries, quoted strings with escapes, numbers, booleans, nil);
  `parseSavedVariables`, `luaGet`. Not a Lua interpreter.
- `discovered.ts` — `Discovered` (what the scraper recorded: `locale`, `build`, items, per-boss
  kills and seen items) and `loadDiscovered(path)`: a `.json` from `/fl export` or a `.lua`
  SavedVariables file, reading `ForeverLootScraperDB.global.discovered` (the only layout; there
  is no legacy one). Records carry their own `id`, which wins over the container key.
- `import.ts` — `importDiscovered`: merges items into the scans (newest observation wins, names
  kept per locale) and observed drops into the instance files (creating them, slug from the
  instance name; on a split map, the file that lists the encounter, else skipped); new rows get a `chance` only after `MIN_KILLS_FOR_CHANCE` = 10 kills; existing
  rows are never changed, only reported.
- `generate.ts` — `build()` produces both trees in memory (`items/items_NNN.lua` chunks of
  `itemsPerFile`, `instances.lua` (one instance per map, or per file with its own `id` on a split
  map, with the encounters that file lists; the English name of such a part is its file's),
  `loot/<slug>.lua` for every file `hasLoot` is true for (a
  boss's drops via `AddBossLoot`, the instance's trash via `AddTrashLoot`, its quests via
  `AddQuests`), `<kind>/<slug>.lua`,
  `recipes/<profession>.lua` for every profession with shipped recipes (`AddCategories` +
  `AddRecipes`, rows in category order), `locales/<locale>/*` (`items`, `instances`, `bosses` —
  a boss an instance file names differently from the game table gets the file's name in enUS and
  no entry in other locales, so they fall back to it —,
  `crafting` = skill line/category/tool names) routed to the core for enUS and to the locale
  addon otherwise, each `generated.xml`); `write()` diffs against disk (CRLF-insensitive),
  removes stale files, returns the change count. `itemRow()` **must match `Data.ITEM`** and
  `recipeRow()` **`Data.RECIPE` in `ForeverLoot/src/data/data.lua`** (`minSkill` is emitted as
  `learnSkillOf()`: the recipe item's requirement when known). A crafting list without an
  `icon` gets its skill line's `SpellIconFileID`; a crafting row without an item (an enchant)
  is emitted as `{ spell = id, ... }`.
- `lua.ts` — Lua serialization (`luaString`, `luaValue`, `luaFields`) and the provenance
  `header()`. The header and `generated.xml` comment deliberately still say
  `.contribute/tools (npm run gen)`: the tools moved to `src/` in the monorepo refactor and
  keeping the old label avoided rewriting every generated file. Changing it is a mass diff of
  the generated trees; do it only on purpose.

## Tests (`tests/`)

- `tests/tooling/*.test.ts` — node:test, `npm run test:tooling` (`tsx --test`). Cover pure
  functions (`loadDiscovered` from SavedVariables, reputation list flattening and
  serialization, `buildRecipes`/`shipsRecipe` on hand-written table rows, the instance files'
  `trash`/`quests` validation and round-trip). Add one next to a new parsing/serialization rule.
- There is no Lua test suite; Lua is checked by `npm run check:lua` (syntax) and in-game.

## Conventions

- ESM with `.js` extensions in relative imports (`import … from "./config.js"`), `tsx` runs the
  `.ts` directly; `npm run typecheck` is `tsc --noEmit` (strict). Only dependency: `csv-parse`.
- Report through the `Checker` (`report` = error or, with `fixable`, something `--fix` corrects;
  `warn` = printed but never fails) rather than throwing, so one run lists every problem.
- Serializers write stable key order and a trailing newline so `fix`/`import` produce minimal
  diffs; keep that property when adding fields (`serialize`, `serializeList`, `saveScannedItems`).
- Generated files are compared ignoring CRLF; write them with `\n`.
- One-off data pulls (scraping a site into `.contribute/data/`) belong in a scratchpad script,
  not in a new command here.
