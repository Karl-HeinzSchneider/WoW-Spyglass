# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ForeverLoot is a World of Warcraft addon (Classic client, `## Interface: 16001`) written in Lua
on top of Ace3. It is early: the core skeleton (logger, AceAddon object, AceDB) exists; loot
tracking itself does not yet.

## Tooling

WoW addons are plain Lua files loaded directly by the game client; there is no build step for
the code itself. To try changes, run `npm run dev:link -- "<WoW>/Interface/AddOns"` to link every
addon directory into the client, then run `/reload` in-game.

The one generated part is the database. The root TypeScript tooling lives in `src/` and uses
`package.json` (`npm install` once,
Node 20+) builds `ForeverLoot/db/generated/` from three inputs: the **item scans** in
`.contribute/data/items/items_<n>.json` (recorded in-game by `/fl scan`, one file per 10 000 ids,
machine-written by `npm run import`), the **curated drops** in `.contribute/data/dungeons|raids/*.json`,
the **curated item lists** in `.contribute/data/crafting|pvp|collections|reputation/*.json` (one
file per profession / reward source / collection / faction; nothing in them comes from a game
table), and wago.tools' `Map` + `DungeonEncounter` tables (instances, bosses, their names) for
the build pinned in `.contribute/data/config.json`. Commands: `npm run fix` (validate ids, fill names, add missing bosses),
`npm run gen` (write `ForeverLoot/db/generated/`), `npm run generate:check` (staleness, for CI),
`npm run import` (merge what the addon recorded in-game — SavedVariables `ForeverLoot.lua` /
`/fl export` JSON files dropped into the gitignored `.contribute/inbox/`, or one file given as
`-- <path>` — into the scans and the curated files). Never edit
`ForeverLoot/db/generated/` by hand. Contributor docs in `.contribute/README.md`.

WoW Forever's items are server-side: the wago.tools item tables are incomplete and wrong for
this client and ids from Classic/wowhead don't match, so **the in-game scan is the only item
source**. Only scanned items exist in the DB; a curated loot row may reference an unscanned id
(warning, not error). Item rows carry everything `GetItemInfo`/`GetItemStats` return (see
`Data.ITEM`).

Static checks used so far (no test runner in the repo): `luac -p` on every Lua file, lxml
validation of every XML file against Blizzard's `UI.xsd`, the LuaLS CLI (`lua-language-server
--check`) and stock-Lua harnesses that load the real libraries with a WoW API stub.

## Layout

- `ForeverLoot/ForeverLoot.toc` — the addon manifest. The game reads it to learn the addon's metadata
  (`## Interface`, `## Title`, `## SavedVariables`, …) and the ordered list of files to load.
  **Every new Lua/XML file must be listed here, in dependency order, or it will not load.**
  Libraries under `lib/` load before `src/`; `locales/` load before code that uses strings.
- `ForeverLoot/embeds.xml` — loads every vendored library in dependency order (LibStub → CallbackHandler →
  Ace* → LibDataBroker/LibDBIcon). Listed first in the TOC.
- `ForeverLoot/src/core/logger.lua` — `app.logger`. Leveled, colored chat logging; `log("x")` is `log:info("x")`.
- `ForeverLoot/src/core/db.lua` — `app.dbDefaults`, the AceDB-3.0 defaults. `profile` = user settings,
  `char` = per-character data (loot history), `global` = account-wide (`global.discovered`: items
  and boss drops recorded in-game, the shape `npm run import` reads). Change the schema here.
- `ForeverLoot/src/core/discovery.lua` — `app.discovery`, AceAddon module. `/fl scan <from> [to]` /
  `resume` / `<from> <to> force` / `stop` requests ids via `RequestLoadItemDataByID` and records
  every existing item in full (`GetItemInfo` + `GetItemStats`, stat keys shortened) into
  `global.discovered.items`, 1000 new per run, progress in `global.scan`. Also records items the
  DB lacks from `LOOT_OPENED`/`START_LOOT_ROLL` and boss drops (attributed to the last successful
  `ENCOUNTER_END`, checked against the looted creature when `GetLootSourceInfo` exists). Everything
  is merged into `Data` at once and on login; a record identical to the shipped row is pruned then.
  Listed in the TOC after the generated data because it takes `app.data` at load time.
- `ForeverLoot/src/core/json.lua` — `app.json.encode`, the minimal JSON encoder behind `/fl export`.
- `ForeverLoot/src/core/registry.lua` — `app.api`, also the **public global `ForeverLoot`** (contract in
  `docs/API.md`). `RegisterModule(def)` validates and stores module definitions; `GetRootNode()`
  builds the virtual tree the window browses (one node per module, sorted by `order`). Events via
  CallbackHandler-1.0 (`OnModuleRegistered/Unregistered/OnModulesChanged`). Defines the
  `ForeverLoot.Node` and `ForeverLoot.ModuleDef` types. Changing the API means updating `docs/API.md`.
- `ForeverLoot/src/data/` — the item database, public as `ForeverLoot.Data/Filters/Query` (also `app.data`,
  `app.filters`, `app.query`). `data.lua`: normalized integer-keyed tables (`items` rows are
  positional arrays indexed by `Data.ITEM`, `instances`, `bosses`, `bossLoot`, `names[locale]`)
  plus the string-keyed curated lists (`lists[kind][id]` = `{ name, icon, order, factionID, … }`,
  `listLoot[kind][id]` = `{ { itemID, standing = "Honored", … }, … }`; kind = `crafting` / `pvp` /
  `collections` / `reputation`, id = the JSON file's slug), `Add*` calls that invalidate caches
  and fire `OnDataChanged`, lazy `GetItemSources` inverted index over boss loot and lists. `filters.lua`: registry of named predicates with options (`multi`/`single`), optional
  precomputed buckets, the built-in filters. `query.lua`: `Query.Run(q)` over a plain, serializable
  query table (`search`, `filters`, `sort`). Nothing in here touches frames.
  `nodes.lua`: DB-backed node constructors on the public API (`InstanceFolders(type)`,
  `InstanceFolder(id)`, `BossFolder(id)`, `BossLootEntries(id)`; `ListFolders(kind)`,
  `ListFolder(kind, id)`, `ListEntries(kind, id)` — list rows become item nodes with the row's
  fields in `meta`, grouped by the row's `group`, else the kind's default: standing for
  reputation, honor rank/standing for pvp, skill tier for crafting) that modules build their
  trees from.
- `ForeverLoot/db/generated/` — **generated** (see Tooling); the TOC lists only `db\generated\generated.xml`.
  Every client item (`items/items_NNN.lua`), all instances with encounters plus curated
  levels/icons (`instances.lua`), curated drops (`loot/<name>.lua`), curated item lists
  (`<kind>/<slug>.lua`, one `Data:AddList` + `Data:AddListLoot` each), names per locale
  (`locales/<locale>/`, non-enUS files return early unless `GetLocale()` matches). Excluded from
  LuaLS and StyLua. Boss ids are `DungeonEncounter` ids, instance ids are `Map` ids.
- `.contribute/data/` — everything people edit and send as pull requests: `dungeons/*.json` and
  `raids/*.json` (one instance each: map id, level range, icon, tile picture, boss portraits, drops with chance; names are
  informational and rewritten by `npm run fix`; a row with only a `name` gets its id filled in
  when unambiguous), `crafting|pvp|collections|reputation/*.json` (the item lists: `name` is the
  displayed name, the file name the id, rows under `recipes` / `rewards` / `items` / `rewards`
  with per-kind fields — schema and validation in `src/lists.ts`, table in the README),
  `items/items_<n>.json` (the scanned item dump: `ScannedItem` in
  `src/items.ts`, names per locale; written by `npm run import`, not by hand). The generator's
  `node_modules/` and `.cache/` are gitignored; `src/savedvars.ts` parses
  SavedVariables Lua, `src/discovered.ts` + `src/import.ts` merge recorded data;
  `src/curated.ts` exports the `Checker` whose `checkItemRow` every validator shares). Item ids from
  Classic/wowhead do **not** apply — WoW Forever has its own itemization, so items and drops must
  be recorded in this client.
- `ForeverLoot/modules/<name>/` — one folder per built-in content module (`items`, `raids`, `dungeons`,
  `crafting`, `pvp`, `collections`, `reputation`), each with a `<name>.xml` loader listed in
  `ForeverLoot/modules/modules.xml`. `items` is a `query = true` module (the item DB with the view's search
  box and filter dropdown); `raids`/`dungeons` build their trees at runtime from the DB via
  `getChildren = function() return FL.InstanceFolders("raid") end`, the other four via
  `FL.ListFolders(kind)`; none holds data of its own. Modules use only the public API a third-party addon would use,
  so never give them private hooks.
- `ForeverLoot/src/core/ace.lua` — `app.addon`, the AceAddon-3.0 object (mixins: AceConsole, AceEvent).
  `OnInitialize` creates `app.db` from `ForeverLootDB`, wires profile-change callbacks to
  `OnProfileRefresh`, and registers `/fl` + `/foreverloot`. Register game events in `OnEnable`.
- `ForeverLoot/src/types.lua` — LuaLS annotations only (not in the TOC). Declares the `ForeverLoot` namespace
  class and `ForeverLoot.DB`. Ace3 types (`AceAddon`, `AceDBObject-3.0`, `AceDB.Schema`, …) come
  from the `ketho.wow-api` VS Code extension, not from `lib/` (which is excluded from LuaLS) —
  inherit from them rather than redeclaring the API.
- `ForeverLoot/src/types_blizzard.lua` — annotations only, not in the TOC. Blizzard UI mixins the UI inherits
  from (`SidePanelTabButtonMixin`, `PortraitFrameMixin`, `PagingControlsMixin`, …), limited to the
  methods we use, because the full ones are only in Ketho's opt-in FrameXML annotations. Extend
  a stub (verified against `BlizzardInterfaceCode`) when using a new method.
- `ForeverLoot/src/ui/` — the main window, Blizzard-style **XML layout + Lua mixin** so the exported Blizzard
  code (see below) maps 1:1. XML `mixin=`/`name=` attributes need globals, so mixins and the window
  frame are globals prefixed `ForeverLoot…` (also on `app.ui.*`). Together with the public
  `ForeverLoot` API table these are the only sanctioned globals. Lua mixin files must be listed in the TOC *before* the XML that
  references them, and `templates.xml` before `mainwindow.xml`.
  - `mainwindow.lua/.xml` — `ForeverLootMainWindow`, modeled on the Camelot `CharacterFrame`
    (`Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml`): `PortraitFrameBaseTemplate`, a dark
    two-column interior (`LeftPane` = the views, `RightPane` = meta data, both using the
    `UI-Character-Info-*-BG` atlases stretched to 900x620, split by `common-framedivider`) and
    icon tabs down the right edge (`ForeverLootSideTabTemplate` = `LargeSideTabButtonTemplate`,
    a *Frame*, so clicks come through `SetCustomOnMouseUpHandler`). Browser-style tabs: one per
    open *view* (icon = deepest node with one, tooltip = title), plus a `+` tab; right-click
    closes; `RebuildTabs()` relays the strip from a pool. Draggable; position saved to
    `profile.window`. `/fl` and the minimap button toggle it.
  - `view.lua` + `templates.xml` — a view fills the left column: header row (back button +
    breadcrumbs left, search box + filter dropdown right) over a divider, then one `Content` page
    of rows with Blizzard `PagingControls` bottom-right. A row is icon, name in quality color,
    drop chance top-right, slot bottom-left and armor/weapon type bottom-right (`itemKindTexts`),
    both red when the character can't equip the item — read from the item tooltip's slot line via
    the hidden `ForeverLootScanTooltip` (`scanEquipErrors`), which is exact for this client's
    proficiencies. A folder with `display = "tiles"` (raids, dungeons) draws its entries as
    `ForeverLootTileTemplate` cards instead: `background`/`backgroundCoords` picture, name on
    top, `info` (level range by default) and `infoRight` in the bottom corners, three per line.
    `display = "cards"` (an instance's boss list) draws `ForeverLootCardTemplate`: the same
    bevelled list-button atlas with the entry's `portrait` (a bust on transparency) standing on
    the left, name and info texts beside it (boss level/type, drops of interest, a quest "!"
    for `quests`), two per line. Pictures, level/type and quests are curated data
    (`.contribute` JSON → `instances.lua` → `InstanceFolder`/`BossFolder`).
    Section headers use the `UI-Character-Info-Title` plate. Navigation
    is a `path` stack over `ForeverLoot.Node` trees (`Push`/`PopTo`/`Back` → `Refresh`).
    `Refresh()` rebuilds elements + page layout (navigation, query/size changes); `Render()` only
    redraws the current page (page flips, item info arriving).
    Children come from `view:GetChildren(node)`: static `children`, dynamic `getChildren`, or a
    `query` folder whose entries are `Query.Run` over the DB with the view's own per-node query
    state (`view.queries`); query folders show the `SearchBox` (debounced) and `FilterDropdown`
    (Blizzard_Menu `WowStyle1FilterDropdownTemplate`, menu generated from the filter registry).
  - The window's root comes from `app.api:GetRootNode()`; it listens to `OnModulesChanged`.
  - `exportframe.lua/.xml` — `ForeverLootExportFrame` (`BasicFrameTemplateWithInset` +
    `InputScrollFrameTemplate`), the `/fl export` text box; `app.ui.exportFrame:ShowText(text)`.
- `ForeverLoot/ForeverLoot.lua` — root entry file, loaded last.
- `ForeverLoot/lib/` — vendored Ace3, LibStub, CallbackHandler, LibDBIcon. Excluded from LuaLS and StyLua.
- `ForeverLoot/locales/` — localization string tables.
- `ForeverLoot/assets/` — textures, icons, sounds referenced from code. Prefer the client's own atlases
  (they scale with the frame); the client does not load `.png` files.

## XML files

Every XML file starts with `<Ui xmlns="http://www.blizzard.com/wow/ui/">` and **no**
`xsi:schemaLocation` — the client ignores that hint and a wrong path makes the VS Code XML
extension report errors. Schema validation instead comes from `xml.fileAssociations` in
`.vscode/settings.json`, which maps `**/*.xml` to `../_data/BlizzardInterfaceCode/.../Blizzard_SharedXML/UI.xsd`
(so it only works when the optional `../_data/BlizzardInterfaceCode/` folder exists). To validate from
the command line: `python -c "from lxml import etree; ..."` against that XSD, as in this session.

## Files with backslashes

Lua strings for texture paths need `\\`. When writing such files from a shell, heredocs and
inline Python strip the doubled backslash; use the Write/Edit tools (or a script file with raw
strings) instead.

## Optional: Blizzard's own UI source and art for reference

A developer may place Blizzard's exported interface files in `../_data/` (a sibling of the
repo folder, i.e. `E:\Projects\_data\` here — outside the repo, so nothing needs gitignoring
or excluding from LuaLS/StyLua), typically as symlinks to the folders the game client writes
next to the WoW install:

- `../_data/BlizzardInterfaceCode/` — from `/run ExportInterfaceFiles("code")`. Lua/XML for all of
  Blizzard's FrameXML/AddOns.
- `../_data/BlizzardInterfaceArt/` — from `/run ExportInterfaceFiles("art")`. Every texture as `.blp`
  under `BlizzardInterfaceArt/Interface/...` (e.g. `Interface/Icons/INV_Misc_Bag_10.blp`).

If they exist, Claude should **read them, never edit them**:

- Code: look up exact API signatures/return values, event payloads, frame templates and global
  strings. Prefer it over guessing from memory, since the Classic client's API differs from retail.
- Art: verify that a texture path used in code exists (paths are case-insensitive in-game, so
  match case-insensitively), and browse for suitable icons/textures by name. `.blp` files can't
  be viewed directly; the file list is what matters. Atlas names (`atlas="..."`) are *not* in
  this export — they're looked up from XML usages in `BlizzardInterfaceCode` instead.

Never list anything from these folders in the TOC or copy files out of them into `src/`.

## Textures and Blizzard frames: reuse art, remake code

- **Don't create new textures unless there is no other way.** Strongly prefer the textures and
  atlases already in the game files (browse `../_data/BlizzardInterfaceArt/` and atlas usages in
  `BlizzardInterfaceCode`). Client art scales with the frame and needs no shipping; the client
  also doesn't load `.png`. If something really must be drawn, ask first.
- **Don't hard-reference a frame from retail or Classic WoW.** Don't inherit its templates,
  call its mixins, anchor to its frames or name it as the thing being copied in comments or
  docs. Look at it to learn how it is built, then remake the look with our own template and
  mixin; naming it as "an example" or "a similar idea" in a comment is fine. The frame's *art*
  (atlases, textures) may be reused freely, as above.
- Code that exists in the Forever/"Camelot" codebase itself (`Blizzard_*/Camelot/`, and shared
  templates it loads such as `Blizzard_SharedXML`) is fair to lean on more directly: its
  templates and mixins are what this client ships, so inheriting from e.g.
  `PortraitFrameBaseTemplate`, `LargeSideTabButtonTemplate` or `PagingControlsTemplate` is fine.
  Verify the file is loaded by this client (Camelot/Mainline TOC) before depending on it.

## WoW addon constraints to keep in mind

- The runtime is Lua 5.1 with Blizzard's restricted API. No `require`, `io`, `os`, or
  `loadstring` of external files; all code must be listed in the TOC.
- Addons share a single global namespace. Keep the addon's state in the private table passed
  to each file rather than globals. Every file starts with:

  ```lua
  ---@type string, ForeverLoot
  local appName, app = ...
  ```

  (Use `local _, app = ...` when the name is unused, or LuaLS flags it.) The `---@type` line is
  what gives the Lua language server completion on `app.*`; without it `...` is untyped. `ForeverLoot/src/types.lua` declares the `ForeverLoot` class — when a file adds a member
  to `app`, add a matching `---@field` there. That file is annotations only and is not in the TOC.
- Persistent state lives only in tables declared via `## SavedVariables` in the TOC; they are
  populated after `ADDON_LOADED` fires, not at file-load time.
