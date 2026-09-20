# Contributing loot data

Everything in this folder is meant to be edited by people; everything under `db/generated/` is
produced from it and must not be edited by hand.

```text
.contribute/
  dungeons/<name>.json   one file per dungeon: level range, icon, drops per boss
  raids/<name>.json      same for raids
  tools/                 the generator (TypeScript, npm)
```

## Adding or changing drops

1. Find the instance file in `dungeons/` or `raids/`, or create one — all you need is the map id
   (see the `-- Name` comments in `db/generated/instances.lua`). Encounter and item ids are the
   game's own (`DungeonEncounter.ID`, item id); the item id is in the item link (`item:5188:...`).
2. Add rows to the boss's `loot` array. `chance` is 0–1 and optional. Names are informational
   and filled in for you.

```json
{
  "map": 36,
  "minLevel": 15,
  "maxLevel": 21,
  "icon": "Interface\\Icons\\INV_Misc_Key_13",
  "encounters": [
    { "id": 2747, "name": "Edwin VanCleef", "loot": [
      { "item": 5188, "name": "Filled Vessel", "chance": 0.9 }
    ] }
  ]
}
```

3. Run the tools (Node 20+):

```sh
cd .contribute/tools
npm install          # once
npm run fix          # validate ids, fill names, add missing bosses
npm run gen          # write db/generated/
```

4. Commit the JSON **and** the regenerated `db/generated/` files, then open a pull request.

`npm run check` only validates; `npm run gen -- --check` fails when `db/generated/` is stale
(used in CI). Game tables come from [wago.tools](https://wago.tools) for the build pinned in
`tools/config.json` and are cached in `tools/.cache/` (delete it to re-download). Bump
`build` there when the client updates; `locales` lists the name tables to ship.

## What is generated from what

| Output (`db/generated/`) | Source |
|---|---|
| `items/items_NNN.lua` | wago.tools `ItemSparse` + `Item`: every item in the client |
| `instances.lua` | wago.tools `Map` + `DungeonEncounter` (only maps with encounters), levels/icons from the JSON |
| `loot/<name>.lua` | the JSON files' `loot` rows |
| `locales/<locale>/*.lua` | wago.tools name columns per locale |
| `generated.xml` | loader listed in the TOC |
