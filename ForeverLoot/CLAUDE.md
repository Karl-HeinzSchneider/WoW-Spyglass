# ForeverLoot (core addon)

The distributable core: the public `ForeverLoot` API (`docs/API.md`), the item database API with
filters and queries (but **no item rows**: those, and the `items` module, ship in
`ForeverLoot_Database`), the built-in content modules, the browser window and user settings
(`ForeverLootDB`). It must work on its own; the companions are optional and **no `.lua`, `.xml`
or `.toc` file in this directory may name them** — `npm run check:addons` fails on the bare
string, comments included.

## Load order (`ForeverLoot.toc`)

The TOC is the manifest and the source of truth for the load order; **every new Lua/XML file must
be listed**. The order follows these rules:

1. `embeds.xml` first: every vendored library in dependency order (LibStub → CallbackHandler →
   Ace\* → LibDataBroker → LibDBIcon).
2. `src\core\`, then `src\data\` (the database API), then `db\generated\generated.xml` (the data)
   and `modules\modules.xml` (the modules, which need both).
3. `src\ui\`: each Lua mixin before the XML that names it, `templates.xml` and `infopane.xml`
   before `mainwindow.xml`, the recipe popup after the window it is parented to.
   The set popup comes after the recipe popup, whose template and mixin it builds on.
   `src\helper\profiler.lua` sits between the mixins it wraps and the XML that creates frames
   from them.
4. `ForeverLoot.lua` last; it only logs.

## Files

### `src/core/`

- `logger.lua` — `app.logger`: leveled, colored chat logging; `log("x")` is `log:info("x")`.
  Companions log through the public `ForeverLoot.Log` / `LogAt` wrappers in `registry.lua`.
- `db.lua` — `app.dbDefaults` for AceDB: `profile` = user settings (`logLevel`, `minimap`,
  `window` anchor; `minimapPos` = 245° so an undragged button doesn't sit on LibDBIcon's shared
  225° default), `char.tabs` = the window's open tabs (see `docs/ui.md`), `char.loot` = a
  placeholder for the planned loot history (nothing reads or writes it yet), `global.dbVersion`. Scraper state deliberately lives in the scraper.
- `registry.lua` — `app.api`, which **is the public global `ForeverLoot`**: `API_VERSION`, the
  module registry and `GetRootNode()`, the node constructors, grouping, the slash-command
  extension registry and the CallbackHandler events. Its private parts: `app.commands` (the
  dispatcher; `show`, `loglevel` and `reset` are reserved) and `app.unknownItemKinds` (items the
  grouping couldn't classify — no `GetItemInfoInstant` result, no DB row, not in the client's
  cache — which the view fetches and regroups). **Everything public here is in `docs/API.md`;
  change both together.**
- `ace.lua` — `app.addon`, the AceAddon object (AceConsole, AceEvent). `OnInitialize` opens
  `app.db`, wires the profile callbacks to `OnProfileRefresh` (log level, views, modules'
  `OnProfileRefresh`) and registers `/fl` + `/foreverloot`; `OnSlashCommand` handles the reserved
  commands and hands the rest to `app.commands:Run`. `OnEnable` preloads the tile pictures.
  Register game events in `OnEnable`.
- `minimapbutton.lua` — `app.minimapButton`, a LibDataBroker launcher + LibDBIcon that toggles
  the window and honors `profile.minimap`.

### `src/data/` — the item database (public as `ForeverLoot.Data/Filters/Query`)

Nothing in here touches frames. The tables, calls and built-in filters are documented in
`docs/API.md` ("Item database").

- `data.lua` — `app.data`: the normalized tables, the `Add*` calls (each invalidates caches, fires
  `OnDataChanged` and bumps `GetVersion()`), the getters, name resolution and `GetItemSources`
  (a lazy inverted index). Item and recipe rows are positional: `Data.ITEM` must match
  `itemRow()` and `Data.RECIPE` must match `recipeRow()` in `src/generate.ts`.
- `filters.lua` — `app.filters`: the filter registry and the built-in filters.
- `query.lua` — `app.query`: `Query.Run(q)` over a plain query table. `search` matches
  `Data:GetSearchName`, the client-locale name plus the English one after a newline.
- `classfilter.lua` — `app.classFilter`: which classes can use which armor and weapon
  subclasses (the `USERS` table; edit it to tune the view's class filter), `CanUse(class,
itemID)`. Private, not part of the public API.
- `nodes.lua` — the DB-backed node constructors modules build their trees from
  (`InstanceFolder(s)`, `BossFolder`, `TrashFolder`, `QuestFolder`, `ListFolder(s)`, …). Crafting
  lists merge the generated recipes with the curated rows (`craftingEntries`) and split into
  category folders (`categoryFolders`), optionally under subheaders (`sectionedFolders`); see
  `ListFolder` in `docs/API.md`.

### `db/generated/` — **generated, never hand-edited**

Written by `npm run gen` from `.contribute/data/`; the TOC lists only `db\generated\generated.xml`,
which loads the rest. No item rows and no English item names (those are in the database
companion). `instances.lua` (its `-- Name` comments are where to look up instance ids),
`loot/<slug>.lua`, `<kind>/<slug>.lua` (the curated lists), `recipes/<profession>.lua` (its
`-- Name` comments list recipe spell ids and category ids) and `locales/enUS/*.lua` (the
standalone English names of instances, bosses and crafting). Excluded from LuaLS, StyLua and
Prettier. What each file is made from: `docs/data-pipeline.md`.

### `modules/<name>/` — built-in content modules

One folder per module, a `<name>.lua` + `<name>.xml` loader each, listed in `modules/modules.xml`.
They hold no data and use **only the public API a third-party addon would** (`local FL =
ForeverLoot`, no private table); never give them private hooks.

- Root order by `order`: dungeons 10, raids 20, crafting 30, reputation 40, pvp 50,
  collections 60. The database companion's `items` module follows at 1000, after a spacer.
- `raids` and `dungeons` are `display = "tiles"` modules listing explicit `FL.InstanceFolder(id)`
  lines, commented out until the instance has curated loot (a split dungeon's parts by their own
  ids, e.g. `18901`). The other four return `FL.ListFolders(kind)`; `crafting` also sets
  `showIcon` on each tile, and `collections` appends the item set tiles (one per source).

### `src/ui/` — the browser window

XML layouts with Lua mixins; the mixins and the window frame are globals prefixed
`ForeverLoot…` (also on `app.ui.*`). How it is built: **`docs/ui.md`** — read it before changing
the window.

- `mainwindow.lua/.xml` — `ForeverLootMainWindow` (`app.ui.mainWindow`): the frame, its two panes
  and the browser-style view tabs.
- `infopane.lua/.xml` — `ForeverLootInfoPaneMixin`, the right pane (`RightPane.Info`): the
  selected tab's info `panel`, drawn with the character frame's side-pane look. Its checkbox
  filter ids live in `view.lua` and must match `PANEL_FILTERS` in `src/lists.ts`.
- `view.lua` + `templates.xml` — a view: header row, paged content, the navigation stack, rows,
  tiles, cards and headers, search box and filter dropdown, the footer's class filter buttons.
- `recipepopup.lua/.xml` — `app.ui.recipePopup`, toggled by a click on a recipe row;
  `ForeverLootPopupTemplate` / `ForeverLootPopupMixin`, the shell both popups share
  (`app.ui.HidePopups()`); `ForeverLootItemSlotTemplate` is the icon slot every slot uses.
- `setpopup.lua/.xml` — `app.ui.setPopup`, toggled by a click on an item of a set: every item of
  the set.
- `modelpreview.lua/.xml` — `app.ui.modelPreview`: the character (or the mount) wearing the item
  while ctrl is held.
- `tooltip.lua` — `app.tooltip`: appends an item's sources to every item tooltip.

### Annotations (not in the TOC)

- `src/types.lua` — the private-table class `ForeverLoot` (`app.*` fields), `ForeverLoot.DB`,
  `ForeverLoot.UI` and `ForeverLoot.FramePool`. When a file adds a member to `app`, add a
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
  pictures of bosses this server added, shot with the scraper's `/fl portrait` and converted by
  `tools/portrait/portrait.py` (128x64 with alpha, like the client's own boss art); a curated
  encounter points at one with `"portrait": "Interface\\AddOns\\ForeverLoot\\assets\\bosses\\<slug>.blp"`.

## Conventions

- Prototype-style Ace modules: define methods on a local `module` table and pass it to
  `addon:NewModule("Name", module, …)`; state lives on the object Ace returns (see
  `minimapbutton.lua`).
- A change to the API surface, the data layout (`Data.ITEM` / `Data.RECIPE` ↔ `src/generate.ts`)
  or module behavior visible to addons updates `docs/API.md` in the same change.
