# ForeverLoot_Scraper (contributor companion)

Optional addon that **collects the data the repository is built from**: it scans item ids
(`/fl scan`), observes what drops from which boss, exports the records (`/fl export`) for
`npm run import`, and is the studio the boss pictures are shot in (`/fl portrait`). Its own
AceAddon object, database (`ForeverLootScraperDB`), frames and modules are private; it depends on
`ForeverLoot` and uses only the public API (`app.api = ForeverLoot`). It also depends on
`ForeverLoot_Database` (`## Dependencies: ForeverLoot, ForeverLoot_Database`), because it tells
new items from known ones by the scanned item rows (`Data:GetItem`), which only that addon ships.
Disabling it leaves the core fully functional.

How scanning, loot attribution, the export and the portrait studio work: **`docs/scraper.md`** —
read it before changing this addon. The contributor workflow it feeds is in
`docs/contributing.md`.

## Files (`ForeverLoot_Scraper.toc`, in load order)

- `ForeverLoot_Scraper.lua` — bootstrap. Declares the private-table class `ForeverLootScraper`
  (its `---@field`s are here, not in `types.lua`), stores `app.api`, `app.coreAPIVersion`, and
  `app.log`, a tiny logger whose `chat` / `info` / `debug` forward to `ForeverLoot.Log` /
  `ForeverLoot.LogAt`, so output shares the core's prefix and level setting.
- `src/db.lua` — `app.dbDefaults` for AceDB: `global.dbVersion`,
  `global.discovered = { build?, locale?, items = { [id] = DiscoveredItem }, loot = { [encounterID] = { id, kills, items = { [itemID] = count } } } }`,
  `global.scan = { next?, to?, limit? }` (progress that survives `/reload`). The Lua classes
  `DiscoveredItem/DiscoveredLoot/Discovered/ScanProgress` are the shape `src/discovered.ts` reads.
- `src/json.lua` — `app.json.encode`, a minimal encoder for `/fl export` (objects only, no arrays).
- `src/ace.lua` — `app.addon`, the AceAddon object (AceEvent). `OnInitialize` opens
  `ForeverLootScraperDB`; `OnEnable` registers `scan`, `export` and `portrait` through
  `ForeverLoot:RegisterCommand`, `OnDisable` unregisters them. The handlers are stored on the
  object so unregistering matches.
- `src/discovery.lua` — `app.discovery`, the Ace module doing the scanning, loot observation and
  export.
- `src/ui/exportframe.lua/.xml` — `ForeverLootScraperExportFrameMixin` / `app.exportFrame`: the
  window that shows the export JSON.
- `src/ui/portraitframe.lua/.xml` — `ForeverLootScraperPortraitFrameMixin` / `app.portraitFrame`:
  the `/fl portrait [displayID]` studio. It freezes the model with `FreezeAnimation(0, 0, 0)` and
  never pauses the frame: a paused model stays translucent part-way through its fade-in, which
  silently ruins the picture's alpha.
- `src/types.lua` — annotations only, not in the TOC: `ForeverLootScraper.DB`.

## Conventions

- Everything user-facing goes through `log:chat`; diagnostics through `log:info`/`log:debug`.
- Never touch `ForeverLootDB`; never require a core private. There is no migration code and no
  legacy SavedVariables layout to support: nobody used the addon before the scraper split.
- Globals: only `ForeverLootScraperDB` and the XML-required `ForeverLootScraper…` mixins/frames.
- When the recorded shape changes, change `src/db.lua`'s classes, `src/discovered.ts`'s
  `normalize`, and the `ScannedItem` fields in `src/items.ts` together.
