# The scraper

How `Spyglass_Scraper` records the data the repository is built from. The contributor's side
(the commands and getting the records into the repository) is in
[contributing.md](contributing.md); what the tools do with the records is in
[data-pipeline.md](data-pipeline.md).

Everything lives in `src/discovery.lua` (`app.discovery`), apart from the two windows at the end.
Scans and loot observations are both written to `SpyglassScraperDB.global.discovered` and
merged into `Spyglass.Data` right away (`MergeIntoData`, tracked in `module.merged`), so a
scanned item is browsable immediately.

## Scanning (`/sg scan`)

`/sg scan <from> [to]`, `resume`, `stop`, `limit <n|off>`, `<from> <to> force`.

- `StartScan` / `ScanTick` request `SCAN_BATCH` = 25 ids per `SCAN_INTERVAL` = 0.25 s (about 100 per
  second) through `C_Item.RequestLoadItemDataByID`. `ITEM_DATA_LOAD_RESULT` records each existing
  item with everything `C_Item.GetItemInfo` + `C_Item.GetItemStats` return (`RecordItem`; stat
  keys are shortened, `ITEM_MOD_X_SHORT` → `X`).
- Ids the shipped database already has are skipped unless `force`. The scraper depends on
  `Spyglass_Database` for exactly this: it tells new items from known ones by the scanned item
  rows (`Data:GetItem`), without which every item would count as new.
- A scan stops after `SCAN_LIMIT` = 1000 new items (the default; `limit off` = 0 for the
  SavedVariables route) or `SCAN_MAX_GAP` = 20 000 consecutive missing ids. `SCAN_SETTLE` = 3 s
  waits for the last results. Progress persists in `global.scan`, so `resume` survives `/reload`.
- `MergeIntoData` runs in `OnEnable` (`PLAYER_LOGIN`, when every data file has loaded): a record
  identical to the shipped row is dropped, the rest are added to `Data`. So after an import and a
  `/reload`, `resume` starts clean.

## Dungeon levels (`/sg levels`)

`/sg levels` queries activity IDs in batches so it can include dungeons omitted from the
current character's available-activity list. The copy window opens when scanning finishes. It
exports activity ID, name, map ID, difficulty ID, and `minLevelSuggestion`/`maxLevelSuggestion` through the same copy window
as `/sg export`. Copy the JSON to `.contribute/inbox/` and run `npm run import`; the importer
matches dungeon activities and writes `.contribute/data/dungeon-levels.json`.

## Loot observation

- `NoteItem` records any item seen dropping that the database lacks.
- A successful `ENCOUNTER_END` opens a `KILL_WINDOW` = 300 s attribution window (`lastKill`, with
  the encounter's creature ids when the client provides them).
- `LOOT_OPENED` (matched against `GetLootSourceInfo` when the creatures are known, so trash and
  chests looted after the kill don't count) and `START_LOOT_ROLL` count each item once per kill
  into `loot[encounterID].items`.
- Kills are counted even when nothing was looted or rolled, so the ratios err low; the import
  tool only suggests a `chance` from them.

## Export (`/sg export`)

`ExportTable` marks item records `exported`, and the next export holds only new ones (`all`
repeats everything; loot is always included). The JSON (`{ version, build, locale, items, loot }`)
is the same `discovered` table the SavedVariables file holds, and `src/discovered.ts` reads
either. `src/json.lua` is a minimal encoder for it: every table becomes an object with sorted
string keys (numbers sorted numerically) — there are no arrays, so tables keyed by item ids that
happen to run 1..n never lose their ids.

`src/ui/exportframe.lua` / `.xml` (`SpyglassScraperExportFrameMixin`, `app.exportFrame`) is a
draggable window with a scrollable edit box that shows the JSON, selects it (Ctrl+C is the
user's) and explains where to put it.

## The portrait studio (`/sg portrait`)

`src/ui/portraitframe.lua` / `.xml` (`SpyglassScraperPortraitFrameMixin`, `app.portraitFrame`),
`/sg portrait [displayID]`, is where the boss pictures are shot; `tools/portrait/portrait.py`
turns the screenshot into the `.blp` ([tools/portrait/README.md](../tools/portrait/README.md)).
Bosses this server added have no Encounter Journal art, so their picture is made from the model:

- The window draws the model **twice side by side, on black and on white**, so one screenshot
  carries both and the pair gives the transparency back (alpha = 1 - (white - black)), which a
  single background cannot.
- Each area is resized (on show, and on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`) to aim for
  512x256 _screen_ pixels — 4x the client's own 128x64 boss art — and the window grows around
  them. The size it really got is printed in the settings line, because the crop only needs a
  2:1 area, not an exact one. A magenta marker rings each area _outside_ the pixels being
  cropped.
- The model is frozen with `FreezeAnimation(0, 0, 0)` while its clock keeps running. Pausing the
  frame instead stops a model part-way through its fade-in and it stays translucent, which
  silently ruins the alpha.
- `< Boss` / `Boss >` walk every boss the core knows a `displayID` for (public API only:
  `Data:GetInstanceIDs` / `GetInstance` / `GetBoss` / `GetBossName`); the id box jumps to any
  display id. Zoom, turn and offset nudge the framing from one shared default (`Reset` returns to
  it) so the set stays uniform. The settings line is meant to be in the screenshot, so a picture
  can be shot again with the same framing.
