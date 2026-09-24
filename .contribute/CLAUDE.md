# .contribute — the data the database is built from

Everything under `data/` is input; the three generated trees (`ForeverLoot/db/generated/`,
`ForeverLoot_Database/db/generated/`, `ForeverLoot_Locale/db/generated/`) are produced from it by
`npm run gen` and **never edited by hand**. `inbox/` is the gitignored drop folder for
`npm run import`.

**Before editing a data file, read the matching section of `docs/contributing.md`**: it has the
format of every file here (instance files with split dungeons, `displayName`, boss pictures,
`trash` and `quests`; the four kinds of item lists; crafting rows and `sections`) and what
`npm run fix` checks and rewrites. Where the data comes from and how it is turned into Lua is in
`docs/data-pipeline.md`; the tooling that reads this folder is `src/`.

```text
.contribute/
  inbox/                    SavedVariables / export files for `npm run import` (gitignored)
  data/
    config.json             pinned client build and generation settings
    items/items_<n>.json    the in-game scans, one file per 10 000 ids (machine-written)
    dungeons/, raids/       one file per instance: levels, art, bosses, drops, trash, quests
    crafting/               one file per profession: its skill line, plus additions to the generated recipes
    pvp/, collections/, reputation/   one file per item list
```

## Rules

- Every data change ends with `npm run fix` (no `ERROR` lines; warnings are fine), then
  `npm run gen`; the JSON and all three regenerated trees are committed together
  (`npm run generate:check`, part of `npm run check`, fails when they are stale).
- `items/*.json` is machine-written by `npm run import`; change it through a scan, not by hand.
- Only ids matter: every `name` in an item row is informational and rewritten by `fix`. A boss's
  `name`, a split dungeon's `name`, `displayName` and quest titles are the exceptions `fix` leaves
  alone.
- A new instance only shows in the browser once its `FL.InstanceFolder(<id>)` line in
  `ForeverLoot/modules/dungeons/dungeons.lua` or `raids/raids.lua` is uncommented.
- Texture paths in JSON need `\\`; write these files with the Write/Edit tools, not shell
  heredocs.
- When asked to pull data in from somewhere (a website's drop tables, a spreadsheet), do it with
  a throwaway script in the session scratchpad that writes the JSON here, then `npm run fix` and
  `npm run gen`. Don't add tools or commands to the repo for a one-off.
