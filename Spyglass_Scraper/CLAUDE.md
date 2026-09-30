# Spyglass_Scraper (contributor companion)

Optional addon that **collects the data the repository is built from**: it scans item ids
(`/sg scan`), observes what drops from which boss, exports the records (`/sg export`) for
`npm run import`, and is the studio the boss pictures are shot in (`/sg portrait`). Its own
AceAddon object, database (`SpyglassScraperDB`), frames and modules are private; it depends on
`Spyglass` and uses only the public API (`app.api = Spyglass`). It also depends on
`Spyglass_Database` (`## Dependencies: Spyglass, Spyglass_Database`), because it tells
new items from known ones by the scanned item rows (`Data:GetItem`), which only that addon ships.
Disabling it leaves the core fully functional.

How scanning, loot attribution, the export and the portrait studio work: **`docs/scraper.md`** —
read it before changing this addon. The contributor workflow it feeds is in
`docs/contributing.md`.

## Files (`Spyglass_Scraper.toc`, in load order)

- `Spyglass_Scraper.lua` — bootstrap. Declares the private-table class `SpyglassScraper`
  (its `---@field`s are here, not in `types.lua`), stores `app.api`, `app.coreAPIVersion`, and
  `app.log`, a tiny logger whose `chat` / `info` / `debug` forward to `Spyglass.Log` /
  `Spyglass.LogAt`, so output shares the core's prefix and level setting.
- `src/db.lua` — `app.dbDefaults` for AceDB: `global.dbVersion`,
  `global.discovered = { build?, locale?, items = { [id] = DiscoveredItem }, loot = { [encounterID] = { id, kills, items = { [itemID] = count } } } }`,
  `global.discovered.trainers = { [npcID] = trainer snapshot }`, `global.scan = { next?, to?, limit? }`
  (progress that survives `/reload`). The Lua classes
  `DiscoveredItem/DiscoveredLoot/DiscoveredTrainer/Discovered/ScanProgress` are the shape
  `src/discovered.ts` reads.
- `src/json.lua` — `app.json.encode`, a minimal encoder for `/sg export` (objects only, no arrays).
- `src/ace.lua` — `app.addon`, the AceAddon object (AceEvent). `OnInitialize` opens
  `SpyglassScraperDB`; `OnEnable` registers `scan`, `export`, `levels`, `trainer` and `portrait` through
  `Spyglass:RegisterCommand`, `OnDisable` unregisters them. The handlers are stored on the
  object so unregistering matches.
- `src/discovery.lua` — `app.discovery`, the Ace module doing the scanning, loot observation and
  export, including group finder and trainer snapshots.
- `src/ui/exportframe.lua/.xml` — `SpyglassScraperExportFrameMixin` / `app.exportFrame`: the
  window that shows the export JSON.
- `src/ui/portraitframe.lua/.xml` — `SpyglassScraperPortraitFrameMixin` / `app.portraitFrame`:
  the `/sg portrait [displayID]` studio. It freezes the model with `FreezeAnimation(0, 0, 0)` and
  never pauses the frame: a paused model stays translucent part-way through its fade-in, which
  silently ruins the picture's alpha.
- `src/types.lua` — annotations only, not in the TOC: `SpyglassScraper.DB`.

## Conventions

- Everything user-facing goes through `log:chat`; diagnostics through `log:info`/`log:debug`.
- Never touch `SpyglassDB`; never require a core private. There is no migration code and no
  legacy SavedVariables layout to support: nobody used the addon before the scraper split.
- Globals: only `SpyglassScraperDB` and the XML-required `SpyglassScraper…` mixins/frames.
- When the recorded shape changes, change `src/db.lua`'s classes, `src/discovered.ts`'s
  `normalize`, and the `ScannedItem` fields in `src/items.ts` together.
