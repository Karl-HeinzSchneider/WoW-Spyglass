# Spyglass (core addon)

The distributable core: the public `Spyglass` API (`docs/API.md`), the item database API with
filters and queries (but **no item rows**: those, and the `items` module, ship in
`Spyglass_Database`), the built-in content modules, the browser window and user settings
(`SpyglassDB`). It must work on its own; the companions are optional. The sole permitted
companion reference is `Spyglass_Locale` in `src/core/ace.lua`, where non-English clients ask
the game to load that load-on-demand addon. `npm run check:addons` rejects every other companion
reference in the core.

## Load order (`Spyglass.toc`)

The TOC is the manifest and the source of truth for the load order; **every new Lua/XML file must
be listed**. The order follows these rules:

1. `embeds.xml` first: every vendored library in dependency order (LibStub → CallbackHandler →
   Ace\* → LibDataBroker → LibDBIcon).
2. `src\core\`, then `src\data\` (the database API), then `db\generated\generated.xml` (the data)
   and `modules\modules.xml` (the modules, which need both).
3. `src\ui\`: each Lua mixin before the XML that names it, `templates.xml` and `infopane.xml`
   before `mainwindow.xml`, the recipe popup after the window it is parented to.
   The set popup comes after the recipe popup, whose template and mixin it builds on; the list
   dialog after both (it uses the popup template and the info pane's checkbox template).
   `src\helper\profiler.lua` sits between the mixins it wraps and the XML that creates frames
   from them.
4. `Spyglass.lua` last; it only logs.

## Files

### `src/core/`

- `logger.lua` — `app.logger`: leveled, colored chat logging; `log("x")` is `log:info("x")`.
  Companions log through the public `Spyglass.Log` / `LogAt` wrappers in `registry.lua`.
- `db.lua` — `app.dbDefaults` for AceDB: `profile` = user settings (`logLevel`, `minimap`,
  `window` anchor; `minimapPos` = 245° so an undragged button doesn't sit on LibDBIcon's shared
  225° default), `char.tabs` = the window's open tabs (see `docs/ui.md`), `char.loot` = a
  placeholder for the planned loot history (nothing reads or writes it yet), `global.dbVersion`,
  `global.lists` (account-wide; made by `lists.lua`, not a default). Scraper state deliberately
  lives in the scraper.
- `registry.lua` — `app.api`, which **is the public global `Spyglass`**: `API_VERSION`, the
  module registry and `GetRootNode()`, the node constructors, grouping, the slash-command
  extension registry and the CallbackHandler events. Its private parts: `app.commands` (the
  dispatcher; `show`, `loglevel` and `reset` are reserved) and `app.unknownItemKinds` (items the
  grouping couldn't classify — no `GetItemInfoInstant` result, no DB row, not in the client's
  cache — which the view fetches and regroups). **Everything public here is in `docs/API.md`;
  change both together.**
- `lists.lua` — `app.lists`, public as `Spyglass.Lists`: the user's item lists in
  `global.lists` (Favorites first; the active list alt-click adds to; markers; export/import),
  plus `Spyglass.Favorites` over the Favorites list. Each change fires `OnListsChanged`
  (`docs/API.md`, "Lists and favorites"). The `Open*Dialog` calls are added by `src/ui/listdialog.lua`.
- `ace.lua` — `app.addon`, the AceAddon object (AceConsole, AceEvent). `OnInitialize` opens
  `app.db`, wires the profile callbacks to `OnProfileRefresh` (log level, views, modules'
  `OnProfileRefresh`), registers `/sg` + `/spyglass`, and loads the load-on-demand locale addon
  outside `enUS` and `enGB`; `OnSlashCommand` handles the reserved commands and hands the rest to
  `app.commands:Run`. `OnEnable` preloads the tile pictures. Register game events in `OnEnable`.
- `minimapbutton.lua` — `app.minimapButton`, a LibDataBroker launcher + LibDBIcon that toggles
  the window and honors `profile.minimap`.
- `options.lua` — `app.options`: the user options as **one** AceConfig table, registered in the
  game's Settings panel (`AddToBlizOptions`) and shown by the window's gear button (`docs/ui.md`).
  A new option goes only here. `Refresh()` redraws them after a setting changed elsewhere.

### `src/data/` — the item database (public as `Spyglass.Data/Filters/Query`)

Nothing in here touches frames. The tables, calls and built-in filters are documented in
`docs/API.md` ("Item database").

- `data.lua` — `app.data`: the normalized tables, the `Add*` calls (each invalidates caches, fires
  `OnDataChanged` and bumps `GetVersion()`), the getters, name resolution and `GetItemSources`
  (a lazy inverted index). Quest definitions are global and reusable; instances hold only
  associations, and `GetQuestChain` expands prerequisites and optional lead-ins. Item and recipe rows are positional: `Data.ITEM` must match
  `itemRow()` and `Data.RECIPE` must match `recipeRow()` in `src/generate.ts`.
- `filters.lua` — `app.filters`: the filter registry and the built-in filters.
- `query.lua` — `app.query`: `Query.Run(q)` over a plain query table. `search` matches
  `Data:GetSearchName`, the client-locale name plus the English one after a newline.
- `classfilter.lua` — `app.classFilter`: which classes can use which armor and weapon
  subclasses (the `USERS` table; edit it to tune the view's class filter), `CanUse(class,
itemID)`. Private, not part of the public API.
- `nodes.lua` — the DB-backed node constructors modules build their trees from
  (`InstanceFolder(s)`, `BossFolder`, `TrashFolder`, `QuestFolder`, `QuestChainEntries`, `ListFolder(s)`, …). Crafting
  lists merge the generated recipes with the curated rows (`craftingEntries`) and split into
  category folders (`categoryFolders`), optionally under subheaders (`sectionedFolders`); see
  `ListFolder` in `docs/API.md`.

### `db/generated/` — **generated, never hand-edited**

Written by `npm run gen` from `.contribute/data/`; the TOC lists only `db\generated\generated.xml`,
which loads the rest. No item rows and no English item names (those are in the database
companion). `instances.lua` (its `-- Name` comments are where to look up instance ids),
`quests/<slug>.lua`, `loot/<slug>.lua`, `<kind>/<slug>.lua` (the curated lists), `recipes/<profession>.lua` (its
`-- Name` comments list recipe spell ids and category ids) and `locales/enUS/*.lua` (the
standalone English names of instances, bosses and crafting). Excluded from LuaLS, StyLua and
Prettier. What each file is made from: `docs/data-pipeline.md`.

### `modules/<name>/` — built-in content modules

One folder per module, a `<name>.lua` + `<name>.xml` loader each, listed in `modules/modules.xml`.
They hold no data and use **only the public API a third-party addon would** (`local SG =
Spyglass`, no private table); never give them private hooks.

- Root order by `order`: dungeons 10, raids 20, crafting 30, reputation 40, pvp 50,
  collections 60, lists 70. The database companion's `items` module follows at 1000, after a
  spacer.
- `raids` and `dungeons` are `display = "tiles"` modules listing explicit `SG.InstanceFolder(id)`
  lines, commented out until the instance has curated loot (a split dungeon's parts by their own
  ids, e.g. `18901`). Crafting, reputation, pvp and collections return `SG.ListFolders(kind)`;
  `crafting` also sets `showIcon` on each tile, and `collections` appends the item set tiles (one
  per source).
- `lists` is a `display = "tiles"` module built through `getEntries` (rebuilt on every open):
  one tile per `SG.Lists` list (kept per list id, so an open tab's node survives a rename), then
  "New list" and "Import list". A list's panel has the `grouping` dropdown (source, kind of
  content, item type; kept in front of the widgets that come and go, so the picked option keeps
  its index) and the buttons that call `SG.Lists` and its dialogs.

### `src/ui/` — the browser window

XML layouts with Lua mixins; the mixins and the window frame are globals prefixed
`Spyglass…` (also on `app.ui.*`). How it is built: **`docs/ui.md`** — read it before changing
the window.

- `mainwindow.lua/.xml` — `SpyglassMainWindow` (`app.ui.mainWindow`): the frame, its two panes
  and the browser-style view tabs.
- `quests.lua` — `app.questInfo`: a quest's progress (text, color, icon), chat link, tooltip and
  modified click, prerequisite/lead-in details, plus curated contact map points shared by the info pane's
  map buttons and the view's quest banners. Loaded
  before `view.lua`.
- `infopane.lua/.xml` — `SpyglassInfoPaneMixin`, the right pane (`RightPane.Info`): the
  selected tab's info `panel`, drawn with the character frame's side-pane look. Its checkbox
  filter ids live in `view.lua` and must match `PANEL_FILTERS` in `src/lists.ts`.
- `view.lua` + `templates.xml` — a view: header row, paged content, the navigation stack, rows,
  tiles, cards, quest banners (including the numbered chain rail) and headers, search box and
  filter dropdown, the footer's class filter buttons.
- `recipepopup.lua/.xml` — `app.ui.recipePopup`, toggled by a click on a recipe row;
  `SpyglassPopupTemplate` / `SpyglassPopupMixin`, the shell both popups share
  (`app.ui.HidePopups()`); `SpyglassItemSlotTemplate` is the icon slot every slot uses.
- `setpopup.lua/.xml` — `app.ui.setPopup`, toggled by a click on an item of a set: every item of
  the set.
- `modelpreview.lua/.xml` — `app.ui.modelPreview`: the character (or the mount) wearing the item
  while ctrl is held.
- `listdialog.lua/.xml` — `app.ui.listDialog`: the new/edit/export/import/delete dialog of the
  item lists; it adds the `Open*Dialog` calls to `Spyglass.Lists`.
- `tooltip.lua` — `app.tooltip`: appends the user lists that have the item and its sources to
  every item tooltip.

### Annotations (not in the TOC)

- `src/types.lua` — the private-table class `Spyglass` (`app.*` fields), `Spyglass.DB`,
  `Spyglass.UI` and `Spyglass.FramePool`. When a file adds a member to `app`, add a
  matching `---@field` here.
- `src/types_blizzard.lua` — the Blizzard UI mixins the UI inherits from
  (`SidePanelTabButtonMixin`, `PortraitFrameMixin`, `PagingControlsMixin`, …) and Classic-only API
  namespaces the annotations lack (`C_SkillInfo`), limited to the methods we use, because the
  full ones are only in Ketho's opt-in FrameXML annotations. Extend a stub (verified against
  `BlizzardInterfaceCode`) when using a new method.

### Other

- `src/helper/profiler.lua` — development timing of the query and window methods; does nothing
  unless `ENABLED = true`.
- `lib/` — vendored Ace3, LibStub, CallbackHandler, LibDBIcon (+ LibDataBroker). Excluded from
  LuaLS and StyLua; update by replacing the folder, don't patch.
- `assets/` — the few textures the game files cannot provide. `assets/bosses/<slug>.blp` are
  pictures of bosses this server added, shot with the scraper's `/sg portrait` and converted by
  `tools/portrait/portrait.py` (128x64 with alpha, like the client's own boss art); a curated
  encounter points at one with `"portrait": "Interface\\AddOns\\Spyglass\\assets\\bosses\\<slug>.blp"`.

## Conventions

- Prototype-style Ace modules: define methods on a local `module` table and pass it to
  `addon:NewModule("Name", module, …)`; state lives on the object Ace returns (see
  `minimapbutton.lua`).
- A change to the API surface, the data layout (`Data.ITEM` / `Data.RECIPE` ↔ `src/generate.ts`)
  or module behavior visible to addons updates `docs/API.md` in the same change.
