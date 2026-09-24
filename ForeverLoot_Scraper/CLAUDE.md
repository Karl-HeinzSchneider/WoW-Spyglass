# ForeverLoot_Scraper (contributor companion)

Optional addon that **collects the data the repository is built from**: it scans item ids
(`/fl scan`), observes what drops from which boss, and exports the records (`/fl export`) for
`npm run import`. Its own AceAddon object, database (`ForeverLootScraperDB`), frames and modules
are private; it depends on `ForeverLoot` and uses only the public API (`app.api = ForeverLoot`).
It also depends on `ForeverLoot_Database` (`## Dependencies: ForeverLoot, ForeverLoot_Database`),
because it tells new items from known ones by the scanned item rows (`Data:GetItem`), which only
that addon ships; without them every item would count as new. Disabling it leaves the core fully
functional. Rules for all addons are in the root `CLAUDE.md`;
the data workflow it feeds is in `.contribute/CLAUDE.md`.

## Files (`ForeverLoot_Scraper.toc`, in load order)

- `ForeverLoot_Scraper.lua` — bootstrap. Declares the private-table class `ForeverLootScraper`
  (its `---@field`s are here, not in a `types.lua`), stores `app.api`, `app.coreAPIVersion`, and
  `app.log`, a tiny logger whose `chat` / `info` / `debug` forward to `ForeverLoot.Log` /
  `ForeverLoot.LogAt` so output shares the core's prefix and level setting.
- `src/db.lua` — `app.dbDefaults` for AceDB: `global.dbVersion`,
  `global.discovered = { build?, locale?, items = { [id] = DiscoveredItem }, loot = { [encounterID] = { id, kills, items = { [itemID] = count } } } }`,
  `global.scan = { next?, to?, limit? }` (progress that survives `/reload`). The Lua classes
  `DiscoveredItem/DiscoveredLoot/Discovered/ScanProgress` are the shape `src/discovered.ts` reads.
- `src/ace.lua` — `app.addon`, the AceAddon object (AceEvent). `OnInitialize` opens
  `ForeverLootScraperDB`. `OnEnable` registers `scan` and
  `export` through `ForeverLoot:RegisterCommand`, `OnDisable` unregisters them; the handlers are
  stored on the object so unregistering matches.
- `src/discovery.lua` — `app.discovery`, the Ace module doing all the work (see below).
- `src/json.lua` — `app.json.encode`: a minimal encoder for `/fl export`. Every table becomes
  an object with sorted string keys (numbers numerically); there are no arrays, so tables keyed
  by item ids that happen to run 1..n never lose their ids.
- `src/ui/portraitframe.lua/.xml` — `ForeverLootScraperPortraitFrameMixin` / `app.portraitFrame`:
  `/fl portrait [displayID]`, the studio the boss pictures are shot in. Bosses this server added
  have no Encounter Journal art, so their picture is made from the model: the window draws it
  **twice side by side, on black and on white**, so one screenshot carries both and the pair
  gives the transparency back (alpha = 1 - (white - black)), which a single background cannot.
  Each area is resized (on show, and on `UI_SCALE_CHANGED`/`DISPLAY_SIZE_CHANGED`) to aim for
  512x256 _screen_ pixels -- 4x the client's own 128x64 boss art -- and the window grows around
  them; the size it really got is printed in the settings line, because the crop only needs a
  2:1 area, not an exact one. A magenta marker rings each area _outside_ the pixels being
  cropped. The model is frozen with `FreezeAnimation(0, 0, 0)` while its clock keeps running:
  pausing the frame stops a model part-way through its fade-in and it stays translucent, which
  silently ruins the alpha. `< Boss` / `Boss >` walk every boss the core knows a `displayID` for
  (public API only: `Data:GetInstanceIDs/GetInstance/GetBoss/GetBossName`), the id box jumps to
  any display id, and zoom / turn / offset nudge the framing from one shared default (`Reset`
  returns to it) so the set stays uniform. The settings line is meant to be in the screenshot,
  so a picture can be reshot with the same framing.
- `src/ui/exportframe.lua/.xml` — `ForeverLootScraperExportFrameMixin` / `app.exportFrame`: a
  draggable window with a scrollable edit box that shows the JSON, selects it (Ctrl+C is the
  user's), and explains where to put it.
- `src/types.lua` — annotations only, not in the TOC: `ForeverLootScraper.DB`.

## What `discovery.lua` does

Two ways in, both written to `discovered` and merged into `ForeverLoot.Data` right away
(`MergeIntoData`, tracked in `module.merged`), so a scanned item is browsable immediately:

- **Scan** (`/fl scan <from> [to]`, `resume`, `stop`, `limit <n|off>`, `<from> <to> force`).
  `StartScan`/`ScanTick`: `SCAN_BATCH` = 25 ids per `SCAN_INTERVAL` = 0.25 s (~50/s) via
  `C_Item.RequestLoadItemDataByID`; `ITEM_DATA_LOAD_RESULT` records each existing item with
  everything `C_Item.GetItemInfo` + `C_Item.GetItemStats` return (`RecordItem`; stats keys
  shortened `ITEM_MOD_X_SHORT → X`). Ids the shipped DB already has are skipped unless `force`.
  `MergeIntoData` runs in `OnEnable` (PLAYER_LOGIN, when every data file has loaded): a record
  identical to the shipped row is dropped, the rest are added to `Data`, so after an import and
  `/reload` `resume` starts clean. A scan stops after `SCAN_LIMIT` = 1000 new items (default; `limit off`
  = 0 for the SavedVariables route) or `SCAN_MAX_GAP` = 20 000 consecutive missing ids;
  `SCAN_SETTLE` = 3 s waits for the last results. Progress persists in `global.scan`.
- **Loot** — `NoteItem` records any item seen dropping that the DB lacks. `ENCOUNTER_END`
  (success) opens a `KILL_WINDOW` = 300 s attribution window (`lastKill`, with the encounter's
  creature ids when the client provides them); `LOOT_OPENED` (matched against
  `GetLootSourceInfo` when creatures are known, so trash/chests after the kill don't count) and
  `START_LOOT_ROLL` count each item once per kill into `loot[encounterID].items`. Kills are
  counted even when nothing was looted/rolled, so ratios err low — the import tool only
  suggests a `chance` from them.
- **Export** (`/fl export [all]`) — `ExportTable` marks item records `exported` and the next
  export holds only new ones (`all` repeats everything; loot is always included). The JSON shape
  (`{ version, build, locale, items, loot }`) is the same `discovered` table, and
  `src/discovered.ts` reads either the SavedVariables file or this JSON.

## Conventions

- Everything user-facing goes through `log:chat`; diagnostics through `log:info`/`log:debug`.
- Never touch `ForeverLootDB`; never require a core private. There is no migration code and no
  legacy SavedVariables layout to support: nobody used the addon before the scraper split.
- Globals: only `ForeverLootScraperDB` and the XML-required `ForeverLootScraper…` mixin/frame.
- When the recorded shape changes, change `src/db.lua`'s classes, `src/discovered.ts`'s
  `normalize`, and the `DiscoveredItem` ↔ `ScannedItem` mapping in `src/items.ts` together.
