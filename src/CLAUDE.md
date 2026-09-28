# src — root TypeScript tooling

The Node 20+ / TypeScript (ESM, run with `tsx`, no build) tools that read `.contribute/data/`,
write the generated addon data, validate the monorepo, link addons for development and package
releases. Runtime addons never import from here and never read contributor JSON; this code may
read `.contribute/` and write only inside `*/db/generated/` (and the curated JSON on `fix` /
`import`). Scripts are in `package.json`.

**What the tools do in detail — sources, validation rules, recipe rules, generation, import — is
in `docs/data-pipeline.md`; read the matching section before changing a module.** The formats
contributors write are in `docs/contributing.md`.

## Entry points (one per `npm run …`)

- `cli.ts` — `generate` (default; `--check` = staleness only), `check` (`--fix` = `npm run fix`),
  `import [file]`. The pipeline order is in `docs/data-pipeline.md`.
- `check-addons.ts` — discovers the addons; checks that every TOC load entry exists (a
  `[TextLocale]` entry for every one of `CLIENT_LOCALES`), that `Spyglass_*` addons declare
  `## Dependencies: Spyglass`, that there are no dependency cycles, and that no
  `.lua`/`.xml`/`.toc` under `Spyglass/` contains a companion's name except the intentional
  `Spyglass_Locale` load in `src/core/ace.lua` (plain substring, comments included).
- `check-lua.ts` — `luac -p` on every `.lua` in every addon (requires Lua 5.1's `luac`).
- `check-xml.ts` — validates every addon `.xml` against
  `../_data/BlizzardInterfaceCode/Interface/AddOns/Blizzard_SharedXML/UI.xsd` with python + lxml;
  exits 0 with a notice when that folder is absent.
- `link-addons.ts` — `npm run dev:link -- <AddOns dir>` (or `WOW_ADDONS_DIR`): a junction/symlink
  per addon; refuses to replace a path that isn't already our link.
- `package-addons.ts` — deterministic zip (fixed timestamps, hand-rolled writer, no dependency)
  of every addon into `dist/Spyglass-<version>.zip`; version from the TOCs (`mixed` if they
  differ).
- `package-local.ts` — `npm run package:local [-- <release.sh options>]`: downloads the BigWigs
  packager's `release.sh` (`v2`, the release workflows' version; cached in `.cache/packager/`)
  and runs it with `-d` (never uploads) in Git for Windows' bash, output in `.release/`. When that
  bash has no `zip` it passes `-z` and zips the packaged folders itself.

## Modules

- `config.ts` — repo paths, `FALLBACK_LOCALE`, `CLIENT_LOCALES` (every `[TextLocale]` value),
  `LOCALE_FILES` (the locale addon's per-language files) and `loadConfig()` for
  `.contribute/data/config.json`.
- `addons.ts` — `addonDirectories()`: every direct child of the root with a same-named `.toc` (no
  hard-coded list); `addonVersion`, `walkFiles`.
- `wago.ts` — `fetchTable(table, build, locale)`: a wago.tools DB2 CSV, cached in `.cache/<build>/`.
- `reference.ts` — `Reference`, everything read from the game tables and the scans: instances,
  encounters (`ENCOUNTER_DIFFICULTIES`), recipes, factions, scanned items, per-locale name
  tables; `refreshItemNames`, `relinkRecipes`, `nameOf()`.
- `recipes.ts` — the profession recipe database: `buildRecipes` (pure, tested), `shipsRecipe`
  (the shipping rule the generator and the checker share), `linkRecipeItems`, `loadRecipes`.
- `items.ts` — `ScannedItem` (field meanings = `Data.ITEM` in the core) and the
  `.contribute/data/items/` store.
- `curated.ts` — the instance files (`CuratedInstance/Encounter/Loot/Quest`), `loadCurated`,
  `validate`, `serialize`, and the shared `Checker` with `checkItemRow`.
- `lists.ts` — the item lists (`CuratedList/Row`, `ROWS_KEY`, `ROW_FIELDS`, `STANDINGS`),
  `rowsOf`, `validateLists`, `validateSections`, `serializeList`.
- `savedvars.ts` — a parser for the Lua subset the client writes to SavedVariables; not a Lua
  interpreter.
- `discovered.ts` — `Discovered` (what the scraper recorded) and `loadDiscovered(path)` for a
  `/sg export` `.json` or a SavedVariables `.lua`.
- `import.ts` — `importDiscovered`: merges items into the scans and observed drops into the
  instance files.
- `generate.ts` — `build()` (the three trees in memory) and `write()`. `itemRow()` **must match
  `Data.ITEM`** and `recipeRow()` **`Data.RECIPE`** in `Spyglass/src/data/data.lua`.
- `lua.ts` — Lua serialization and the provenance `header()`, which deliberately still says
  `.contribute/tools (npm run gen)`; changing it rewrites every generated file, so do it only on
  purpose.
- `json.ts` — `writeJson(path, json)`: JSON formatted with the repo's Prettier config.
- `zip.ts` — `createZip` (stored, fixed timestamps), `directoryEntries`, `fileNamePart` (a TOC
  version as a file name), shared by the two packaging scripts.

## Tests (`tests/`)

- `tests/tooling/*.test.ts` — node:test, `npm run test:tooling` (`tsx --test`), on pure functions.
  Add one next to a new parsing, validation or serialization rule.
- There is no Lua test suite; Lua is checked by `npm run check:lua` (syntax) and in-game.

## Conventions

- ESM with `.js` extensions in relative imports (`import … from "./config.js"`); `tsx` runs the
  `.ts` directly; `npm run typecheck` is `tsc --noEmit` (strict). Dependencies: `csv-parse`, and
  `prettier` for writing JSON.
- Report through the `Checker` (`report` = error or, with `fixable`, something `--fix` corrects;
  `warn` = printed but never fails) rather than throwing, so one run lists every problem.
- Serializers write stable key order and a trailing newline so `fix`/`import` produce minimal
  diffs; keep that property when adding fields (`serialize`, `serializeList`, `saveScannedItems`).
- Every JSON file under `.contribute/data/` is written through `writeJson`: the serializer's
  `JSON.stringify(value, null, 2)` run through the repo's Prettier config, so a tool-written file
  is exactly what `npm run format` and format-on-save make of it. Never `writeFileSync` a data
  file directly.
- Generated files are compared ignoring CRLF; write them with `\n`.
- One-off data pulls belong in a scratchpad script, not in a new command here (see
  `.contribute/CLAUDE.md`).
