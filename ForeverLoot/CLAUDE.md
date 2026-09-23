# ForeverLoot (core addon)

The distributable core: the public `ForeverLoot` API, the item database with filters and
queries, the built-in content modules, the browser window, user settings and loot history
(`ForeverLootDB`). It must work on its own; the companions (`ForeverLoot_Locale`,
`ForeverLoot_Scraper`) are optional and **nothing in this directory may mention them** —
`npm run check:addons` fails on the bare string, comments included. Repo-wide rules
(constraints, XML, textures, Blizzard reference folders) are in the root `CLAUDE.md`; the
public contract is `docs/API.md`.

## Load order (`ForeverLoot.toc`)

The TOC is the addon manifest: metadata (`## Interface: 16001`, `## SavedVariables: ForeverLootDB`)
and the ordered file list. **Every new Lua/XML file must be listed, in dependency order.**
Current order and why:

1. `embeds.xml` — every vendored library in dependency order (LibStub → CallbackHandler → Ace*
   → LibDataBroker → LibDBIcon).
2. `src\core\logger.lua`, `db.lua`, `registry.lua`, `ace.lua`, `minimapbutton.lua`.
3. `src\data\data.lua`, `filters.lua`, `query.lua`, `nodes.lua` — the DB API, then
   `db\generated\generated.xml` (the generated data) and `modules\modules.xml` (the built-in
   modules, which need both).
4. `src\ui\view.lua`, `templates.xml`, `mainwindow.lua`, `mainwindow.xml`, `recipepopup.lua`,
   `recipepopup.xml` — Lua mixins before the XML that names them; `templates.xml` before
   `mainwindow.xml`; the popup after the window it is parented to.
5. `ForeverLoot.lua` — root entry, loaded last; only logs.

## Files

### `src/core/`

- `logger.lua` — `app.logger`. Leveled, colored chat logging; `log("x")` is `log:info("x")`.
  The public `ForeverLoot.Log` / `LogAt` (in `registry.lua`) wrap it so companions log under
  the core prefix and level without reaching in.
- `db.lua` — `app.dbDefaults`, the AceDB-3.0 defaults. `profile` = user settings (`logLevel`,
  `minimap.hide`, `window` anchor), `char` = per-character data (`loot` history), `global` =
  account-wide (`dbVersion`). Scraper collection state is deliberately *not* here.
- `registry.lua` — `app.api`, which **is the public global `ForeverLoot`**. `API_VERSION`,
  `RegisterModule(def)` (validates and stores module definitions), `AddToModule`,
  `GetRootNode()` (the virtual tree the window browses, one node per module sorted by `order`,
  a spacer above modules with `spacerBefore`, cached until the module set changes), node
  constructors (`Folder/Item/Spell/Custom/Header/Group/Spacer`), grouping (`DefaultGroupKey`,
  `DefaultEntryRank`, `GroupEntries`), the slash-command
  extension registry (`RegisterCommand/UnregisterCommand`; `app.commands` is the private
  dispatcher, `show`/`loglevel`/`reset` are reserved), and CallbackHandler-1.0 events
  (`OnModuleRegistered/Unregistered`, `OnModulesChanged`, `OnDataChanged`, `OnFiltersChanged`).
  Defines the `ForeverLoot.Node` and `ForeverLoot.ModuleDef` types. **Changing anything here
  means updating `docs/API.md`.**
- `ace.lua` — `app.addon`, the AceAddon-3.0 object (mixins AceConsole, AceEvent).
  `OnInitialize` creates `app.db` from `ForeverLootDB`, wires profile-change callbacks to
  `OnProfileRefresh` (re-applies log level, refreshes views, calls modules' `OnProfileRefresh`)
  and registers `/fl` + `/foreverloot`. `OnSlashCommand` handles the reserved commands and
  hands everything else to `app.commands:Run`. Register game events in `OnEnable`.
- `minimapbutton.lua` — `app.minimapButton`, an Ace module wrapping a LibDataBroker launcher +
  LibDBIcon; toggles the window, honors `profile.minimap.hide`.

### `src/data/` — the item database (public as `ForeverLoot.Data/Filters/Query`)

Nothing in here touches frames.

- `data.lua` — `app.data`. Normalized integer-keyed tables: `items` rows are positional arrays
  indexed by `Data.ITEM` (layout must match `itemRow()` in `src/generate.ts`), `instances`,
  `bosses`, `bossLoot`, `trashLoot` (loot rows keyed by instance: what its non-boss enemies
  drop), `quests` (curated quest definitions keyed by quest id) with `instanceQuests` listing
  each instance's in curated order, `recipes` (positional rows indexed by `Data.RECIPE`, keyed by spell id,
  layout must match `recipeRow()`), `categories` (trade skill categories: `skillLineID`,
  `order`), `names[locale]` (`items`, `bosses`, `instances`, `skillLines`, `categories`,
  `tools`); plus the string-keyed curated lists (`lists[kind][id]` = `{ name, icon, order,
  factionID, skillLineID, … }`, `listLoot[kind][id]` = `{ { itemID, standing = "Honored", … }, … }`;
  kind = `crafting`/`pvp`/`collections`/`reputation`, id = the JSON file's slug). `Add*` calls
  invalidate caches and fire `OnDataChanged`; `GetVersion()` bumps on every change.
  `GetItemName` resolves client locale → enUS → `C_Item.GetItemInfo` → `"Item #id"`;
  `GetName(kind, id)` does client locale → enUS for the other kinds; `GetQuestName` does
  `C_QuestLog` → the curated title → `"#id"`, because this client ships no quest table.
  `GetRecipeIDs(skillLineID)`
  is a profession's recipes in trade-skill-window order. `GetItemSources` is a lazy inverted
  index over boss loot, instance trash, quest rewards, every list and the recipes that make an
  item (kinds `"boss"`, `"trash"`, `"quest"`, `"recipe"` and the list kinds).
- `filters.lua` — `app.filters`: registry of named predicates with options (`multi`/`single`),
  optional precomputed buckets, and the built-ins (`quality`, `slot`, `armorType`, `weaponType`,
  `itemLevel`, `reqLevel`, `instance`, `boss`, `profession` = made by a profession's recipes).
- `query.lua` — `app.query`: `Query.Run(q)` over a plain, serializable query table (`search`,
  `filters`, `sort`). Filters AND, values within a filter OR.
- `nodes.lua` — DB-backed node constructors on the public API that modules build their trees
  from: `InstanceFolders(type)`, `InstanceFolder(id)` (a `cards` folder of bosses, then the
  instance's own two cards), `BossFolder(id)`,
  `BossLootEntries(id)`, `TrashFolder(id)`/`TrashLootEntries(id)` (the drops of everything
  between the bosses) and `QuestFolder(id)`/`InstanceQuestEntries(id)` (one subheader per quest —
  title, id and the faction when its `side` restricts it — over the items it rewards);
  `ListFolders(kind)`, `ListFolder(kind, id)`, `ListEntries(kind, id)` — list
  rows become item nodes with the row's fields in `meta`, grouped by the row's `group`, else the
  kind's default (standing for reputation, honor rank/standing for pvp, trade skill category then
  skill tier for crafting), else item type. Crafting lists with a `skillLineID` are built from
  `Data.recipes` (`craftingEntries`: one node per recipe — the item it makes, or the spell for
  enchants — with the colored skill thresholds as `infoRight` and reagents/tools/source as a
  `tooltip` function) and the curated rows are laid over them by `spell` or by item; the
  profession folder holds one sub-folder per trade skill category (`categoryFolders`: curated
  `group` labels get their own, the rest "Other"; first recipe's icon, "N recipes" as the
  description), grouped under subheaders when the list has `sections` (`sectionedFolders`: from
  the crafting JSON, or from what the caller passes as `ListFolder(kind, id, opts)` /
  `ListFolders(kind, opts)`; categories no section names follow under "Other"), and takes the
  localized profession name from `Data:GetName("skillLines", …)`
  and the character's rank from `C_SkillInfo.GetSkillLineInfoByID` as `info`.

### `db/generated/` — **generated, never hand-edited**

Written by `npm run gen` from `.contribute/data/`; the TOC lists only `db\generated\generated.xml`,
which loads the rest. `items/items_NNN.lua` (every scanned item, `itemsPerFile` rows each),
`instances.lua` (all instances with encounters plus curated levels/icons/portraits; the `-- Name`
comments are the place to look up map ids), `loot/<slug>.lua` (curated drops), `<kind>/<slug>.lua`
(one `Data:AddList` + `Data:AddListLoot` per curated list), `recipes/<profession>.lua` (the
profession's trade skill categories and every recipe the scans confirm, from wago.tools; the
`-- Name` comments are the place to look up recipe spell ids), `locales/enUS/*.lua` (the
standalone fallback names, including `crafting.lua` = profession/category/tool names). Excluded
from LuaLS and StyLua. The provenance header in these files intentionally still says
`.contribute/tools` (see `src/CLAUDE.md`).

### `modules/<name>/` — built-in content modules

One folder per module (`items`, `raids`, `dungeons`, `crafting`, `pvp`, `collections`,
`reputation`), each a `<name>.lua` + `<name>.xml` loader listed in `modules/modules.xml`. They
hold no data and use **only the public API a third-party addon would** — never give them private
hooks. Root order: dungeons, raids, crafting, reputation, pvp, collections (`order` 10–60), then
a spacer and `items` (`order = 1000`, `spacerBefore = true`). `items` is a `query = true` module (the whole DB with search box and filter dropdown).
`raids`/`dungeons` are `display = "tiles"` modules whose `getChildren` returns explicit
`FL.InstanceFolder(mapID)` lines (commented out until an instance has curated loot; a split
dungeon's parts are listed by their own ids, e.g. `18901`). The other
four return `FL.ListFolders(kind)`; for `crafting` that means one tile per profession file, each
listing the generated recipes merged with the file's rows (see `nodes.lua`).

### `src/ui/` — the main window (Blizzard-style XML layout + Lua mixin)

XML `mixin=`/`name=` attributes need globals, so mixins and the window frame are globals prefixed
`ForeverLoot…` (also exposed on `app.ui.*`). Together with the public API table these are the
only sanctioned globals.

- `mainwindow.lua/.xml` — `ForeverLootMainWindow`: `PortraitFrameBaseTemplate`, a dark two-column
  interior (`LeftPane` = the views, `RightPane` = meta data, both `UI-Character-Info-*-BG` atlases
  stretched to 900x640, split by `common-framedivider`) and icon tabs down the right edge
  (`ForeverLootSideTabTemplate` = `LargeSideTabButtonTemplate`, a *Frame*, so clicks come through
  `SetCustomOnMouseUpHandler`). Browser-style tabs: one per open *view* (icon = deepest node with
  one, tooltip = title) plus a `+` tab; right-click closes; `RebuildTabs()` relays the strip from
  a pool. Draggable; position saved to `profile.window`. Root node from `app.api:GetRootNode()`;
  listens to `OnModulesChanged`, `OnDataChanged`, `OnFiltersChanged`.
- `view.lua` + `templates.xml` — a view fills the left column: header row (back button +
  breadcrumbs left, search box + filter dropdown right) over a divider, one `Content` page of rows
  with Blizzard `PagingControls` bottom-right. Navigation is a `path` stack over `ForeverLoot.Node`
  trees (`Push`/`PopTo`/`Back` → `Refresh`). `Refresh()` rebuilds elements + page layout
  (navigation, query/size changes); `Render()` only redraws the current page (page flips, item
  info arriving). Children come from `view:GetChildren(node)`: static `children`, dynamic
  `getChildren`, or a `query` folder whose entries are `Query.Run` over the DB with per-node
  query state (`view.queries`); query folders show the debounced `SearchBox` and the
  `FilterDropdown` (Blizzard_Menu `WowStyle1FilterDropdownTemplate`, menu generated from the
  filter registry).
  - A **row** is icon, name in quality color, drop chance (else the node's `infoRight`, e.g. a
    recipe's skill thresholds) top-right, slot bottom-left and armor/weapon type bottom-right
    (`itemKindTexts`), both red when the character can't equip the item — read from the
    tooltip's slot line via the hidden `ForeverLootScanTooltip` (`scanEquipErrors`), which is
    exact for this client's proficiencies. Item and spell tooltips are followed by the node's
    `tooltip` lines (a list or a function of the node).
  - `display = "tiles"` (raids, dungeons) draws `ForeverLootTileTemplate` cards:
    `background`/`backgroundCoords` picture, name on top, `info` (level range by default) and
    `infoRight` in the bottom corners, three per line.
  - `display = "cards"` (an instance's boss list) draws `ForeverLootCardTemplate`: the same
    bevelled list-button atlas with the entry's `portrait` standing on the left (a
    `portraitDisplayID` instead draws the creature's model through
    `SetPortraitTextureFromCreatureDisplayID` into the same region), name and info
    beside it (boss level/type, drops of interest, a quest "!" for `quests`), two per line.
  - Section headers use the `UI-Character-Info-Title` plate; subheaders (`subheader` nodes) are
    a smaller step below them — centered text with `UI-Character-Info-ScrollLine-Long` running
    out to both sides; groups are row-sized labels;
    a `spacer` element is one row of empty space that takes part in the page layout but has no
    frame (dropped at a page top).
- `recipepopup.lua/.xml` — `ForeverLootRecipePopup` (`app.ui.recipePopup`), a tooltip-bordered
  child of the main window that a click on a recipe row (a node whose `meta.spell` is in
  `Data.recipes`) toggles below that row: title, then icons only — the product and the recipe
  item that teaches it, then the recipe itself (the profession's tile icon; spell tooltip and
  link) and one slot per reagent with its count. `ForeverLootItemSlotTemplate`/
  `ForeverLootItemSlotMixin` is the 32px icon with count and quality border (`SetItem` /
  `SetSpell`, tooltip on hover, `HandleModifiedItemClick` on click) that every slot uses; the
  background is the main window's pane atlas (`UI-Character-Info-General-BG`) under the
  tooltip border, the template's own translucent backdrop switched off. Redraws on `GET_ITEM_INFO_RECEIVED`; the
  view hides it on `Refresh` and page changes because its anchor row is reused.

### Annotations (not in the TOC)

- `src/types.lua` — declares the `ForeverLoot` private-table class (`app.*` fields),
  `ForeverLoot.DB`, `ForeverLoot.UI` and `ForeverLoot.FramePool`. When a file adds a member to
  `app`, add a matching `---@field` here.
- `src/types_blizzard.lua` — Blizzard UI mixins the UI inherits from (`SidePanelTabButtonMixin`,
  `PortraitFrameMixin`, `PagingControlsMixin`, …) and Classic-only API namespaces the
  annotations lack (`C_SkillInfo`), limited to the methods we use, because the full ones are
  only in Ketho's opt-in FrameXML annotations. Extend a stub (verified against
  `BlizzardInterfaceCode`) when using a new method.

### Other

- `lib/` — vendored Ace3, LibStub, CallbackHandler, LibDBIcon (+ LibDataBroker). Excluded from
  LuaLS and StyLua; update by replacing the folder, don't patch.
- `assets/` — the few textures the game files cannot provide; prefer the client's own atlases
  and textures (see the root `CLAUDE.md`). `assets/bosses/<slug>.blp` holds boss pictures for
  bosses this server added, shot with the scraper's `/fl portrait` studio and cut to 128x64
  with an alpha channel like the client's own boss art; a curated encounter points at one with
  `"portrait": "Interface\\AddOns\\ForeverLoot\\assets\\bosses\\<slug>.blp"`.

## Conventions

- Prototype-style Ace modules: define methods on a local `module` table and pass it to
  `addon:NewModule("Name", module, …)`; state lives on the object Ace returns (see
  `minimapbutton.lua`).
- Comments and docs may say a Blizzard frame served as "an example"; never inherit, call or
  anchor to retail/Classic frames. Camelot-shipped templates are fine.
- After changing the API surface, data layout (`Data.ITEM` ↔ `src/generate.ts`), or module
  behavior visible to addons, update `docs/API.md` in the same change.
