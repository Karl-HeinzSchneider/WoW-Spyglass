# ForeverLoot public API

ForeverLoot exposes a global table `ForeverLoot` that other addons can use to add content to the
ForeverLoot window. ForeverLoot's own content (the folders under `modules/`) is registered through
exactly the same calls, so anything the built-in modules can do, yours can too.

Load order: list `ForeverLoot` under `## Dependencies:` (or `## OptionalDeps:` and check
`ForeverLoot ~= nil`) in your TOC so the global exists when your files run.

```lua
-- MyAddon/MyAddon.toc
## Dependencies: ForeverLoot

-- MyAddon/MyAddon.lua
local FL = ForeverLoot

FL:RegisterModule({
    id = "myaddon-worldbosses",          -- unique; prefix with your addon name
    name = "World Bosses",               -- shown in the window
    icon = "Interface\\Icons\\Achievement_Boss_Azuregos",
    order = 30,                          -- lower sorts first (built-ins use 10, 20, ...)
    description = "Outdoor raid bosses", -- optional
    children = {
        FL.Folder("Azuregos", "Interface\\Icons\\Achievement_Boss_Azuregos", {
            FL.Item(17070), -- Fang of the Mystics
            FL.Item(18202), -- Eskhandar's Left Claw
        }),
    },
})
```

## Adding to an existing module

You don't have to create a module to contribute content. `ForeverLoot:AddToModule(id, node)`
appends a folder (or any node) to a registered module, e.g. a new dungeon inside the built-in
`"dungeons"` module:

```lua
local dungeon = ForeverLoot.Folder("Gnomeregan", "Interface\\Icons\\...", { ...bosses... }, { minLevel = 24 })
ForeverLoot:AddToModule("dungeons", dungeon)
```

Built-in module ids: `"items"`, `"raids"`, `"dungeons"`. The built-in raids/dungeons sort by
`minLevel`, then name. If your instance is in the game's data, prefer adding its drops to the
item database (`ForeverLoot.Data:AddBossLoot`) — it then shows up in the built-in modules and
in the item browser's filters automatically.

## `ForeverLoot:RegisterModule(def) -> boolean`

Registers (or, if `def.id` already exists, replaces) a module. Returns `false` and logs an error
if the definition is invalid; it never throws.

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Unique key. Prefix with your addon name to avoid collisions. |
| `name` | string | yes | Display name. |
| `icon` | string \| number | yes | Texture path or fileID. |
| `order` | number | no | Sort position among modules; lower first. Default `100`. Ties sort by name. |
| `description` | string | no | Free text for tooltips. |
| `children` | Node[] | one of | The module's top-level entries. |
| `getChildren` | fun(def) -> Node[] | one of | Lazy alternative; called once, the first time the tree is built. Errors are caught and logged. |
| `sortChildren` | boolean \| fun(a, b) | no | `true` sorts children by node `order` (default 100), then `name`; a function is used as the comparator and receives the full nodes (metadata included). Applies to `AddToModule` entries too. |
| `query` | boolean | no | The module's own list is the item database, filtered by the view's search box and filter menu (see [Item database](#item-database)). `children` may be `{}`. |
| `columns`, `groupBy` | | no | Layout of the module's own list, as on folder nodes. |
| `expansionID`, `seasonID`, `tags`, `meta` | various | no | Metadata; see below. |

## Nodes

A node is a plain table; the fields set decide what it displays as:

```lua
{ name = "Boss", icon = "...", children = { ... } }         -- folder (navigable)
{ name = "Live", icon = "...", getChildren = function(node, view) return { ... } end }
                                                            -- dynamic folder: entries computed every time it is opened
{ name = "All", icon = "...", query = true }                -- query folder: the item DB, filtered per view (search box + filter menu)
{ itemID = 17070 }                                          -- item: name/icon/quality/ilvl from the game, item tooltip, shift-click links
{ itemID = 17070, chance = 0.18 }                           -- item with a drop chance (0..1), shown as "18%"
{ spellID = 22888 }                                         -- spell: name/icon from the game, spell tooltip
{ name = "Title", icon = "...", description = "Second line", -- custom entry
  quality = 4, category = "Misc", tooltip = { "line", ... },
  onClick = function(node, button) end }
```

Items and spells resolve lazily. An item the client hasn't cached yet is drawn from the item
database (name, quality, item level) when it is in there, otherwise as "Item #id"; either way
it redraws when the game's data arrives. `ForeverLoot.IsFolder(node)` tells whether a node
opens (static, dynamic or query folder).

Folders may also set `columns = 1 | 2` to control how their children are laid out: one
full-width column (the default) or two columns per page. This is decided by the collection,
not by a user setting, so choose it per list (e.g. `columns = 2` for a boss's loot table).

### Metadata

Modules and nodes accept optional metadata that ForeverLoot stores but does not interpret;
it is there for your sort functions, filters and other addons:

| Field | Type | Notes |
|---|---|---|
| `order` | number | Sort key used by `sortChildren = true`. Use fractions for ties, e.g. `60.1`, `60.2`. |
| `expansionID` | integer | e.g. `LE_EXPANSION_CLASSIC` |
| `seasonID` | integer | |
| `instanceID` | integer | journal / map instance id |
| `minLevel`, `maxLevel` | integer | |
| `tags` | string[] | |
| `meta` | table | anything else |

`Folder(name, icon, children, opts)` copies every key of `opts` onto the node, so layout
options and metadata go in the same table; `Custom(def)` copies every field of `def`.

```lua
local dungeon = ForeverLoot.Folder("Gnomeregan", icon, bosses, {
    order = 29, minLevel = 24, maxLevel = 34, expansionID = 0, instanceID = 90, tags = { "tech" },
})
ForeverLoot:RegisterModule({
    id = "myaddon-season", name = "Season 3", icon = icon, seasonID = 3, children = {},
    sortChildren = function(a, b) return (a.minLevel or 0) < (b.minLevel or 0) end,
})
```

### Headers and groups

Inside a folder's `children`:

- `{ header = "Weapons" }` renders as a big section header (spellbook-style title with a
  divider). The current folder's own name is always shown as the first header of its list.
- `{ group = "Tier 2", items = { ... } }` renders as a row-sized group label followed by
  `items`. Without `items` it just marks where a group starts in the surrounding list.

### Automatic grouping

Set `groupBy` on a folder to cluster its plain entries under group labels automatically.
Explicit headers/groups in the same list are kept as written; only the entries between them
are grouped.

- `groupBy = "auto"` uses `ForeverLoot.DefaultGroupKey`: items by equipment slot (weapons
  together) in canonical slot order, spells under "Spells", folders under "Collections",
  custom entries by their `category`.
- `groupBy = function(node) return key, label end` for your own logic (return `nil` to leave
  an entry ungrouped under "Other"). Groups with unknown keys keep first-seen order.

Inside each group, entries are sorted by `ForeverLoot.DefaultEntryRank`: armor by type
(plate > mail > leather > cloth > shields > misc), weapons by weapon type; everything else keeps
its written order.

`ForeverLoot.GroupEntries(entries, keyFn?, rankFn?)` exposes the same bucketing and sorting for
your own use; pass `rankFn` to change the in-group order.

Constructors (optional sugar):

- `ForeverLoot.Folder(name, icon, children, opts?)` — `opts = { columns = 2, description = "...", groupBy = "auto" }`
- `ForeverLoot.Header(text)` — section header inside a list
- `ForeverLoot.Group(text, items?)` — group label, optionally with its entries
- `ForeverLoot.Item(itemID)`
- `ForeverLoot.Spell(spellID)`
- `ForeverLoot.Custom({ name, icon, description, quality, category, tooltip, onClick })`
- `ForeverLoot.InstanceFolders(type)` — folders for every DB instance of `type` (`"dungeon"` / `"raid"`)
- `ForeverLoot.InstanceFolder(instanceID)` / `ForeverLoot.BossFolder(bossID)` / `ForeverLoot.BossLootEntries(bossID)` —
  DB-backed folders: instance → bosses → drops with `chance`
- `ForeverLoot.Log(fmt, ...)` — prefixed chat message
- `ForeverLoot.PlaceholderItem(name, quality, icon)` — hard-coded display data, for prototyping
- `ForeverLoot.PlaceholderItems(prefix, count)` — generates `count` placeholder items

## Other calls

- `ForeverLoot:AddToModule(id, node) -> boolean` — append an entry to a registered module
- `ForeverLoot:UnregisterModule(id) -> boolean`
- `ForeverLoot:GetModule(id) -> def?`
- `ForeverLoot:GetModules() -> def[]` — sorted by `order`, then `name`
- `ForeverLoot:GetRootNode() -> Node` — the virtual root the window browses (one child per module,
  each carrying `moduleID`). Cached until the module set changes.
- `ForeverLoot.API_VERSION` — currently `1`.

## Item database

`ForeverLoot.Data` holds every item in the client and where it drops. ForeverLoot ships its
data as generated files (`db/generated/`, built by `.contribute/tools` from wago.tools exports
and the curated JSON in `.contribute/`); other addons may add to it with the same calls.
Instance ids are `Map` ids, boss ids are `DungeonEncounter` ids. Tables are integer-keyed:

```lua
local Data = ForeverLoot.Data
Data.items[5188]     -- { quality, itemLevel, reqLevel, classID, subclassID, equipLoc, bind }; indices in Data.ITEM
Data.instances[36]   -- { type = "dungeon", bosses = { 2741, ... }, minLevel = 15, maxLevel = 21, expansionID = 0, icon = "..." }
Data.bosses[2747]    -- { instanceID = 36, order = 6000 }
Data.bossLoot[2747]  -- { { 5188, 0.9 }, { 5191 }, ... }   -- { itemID, chance 0..1 or nil }
Data.names.enUS      -- { items = { [5188] = "Filled Vessel" }, bosses = {...}, instances = {...} }
```

Adding data (any call may be repeated; every one invalidates the caches and fires `OnDataChanged`):

- `Data:AddItems({ [itemID] = { quality, ilvl, reqLevel, classID, subclassID, equipLoc, bind }, ... })`
- `Data:AddInstance(id, def)`, `Data:AddBoss(id, def)` (appends to its instance's `bosses` if missing),
  `Data:AddBossLoot(bossID, { { itemID, chance }, ... })`
- `Data:AddNames(locale, "items" | "bosses" | "instances", { [id] = name })` — enUS is the fallback

Reading:

- `Data:GetItem(id) -> row?`, `Data:GetItemField(id, Data.ITEM.ILVL)`, `Data:GetItemIDs()` (sorted, cached),
  `Data:GetItemCount()`, `for id, row in Data:EachItem() do`
- `Data:GetItemName(id) -> name, known` — client locale, then enUS, then `C_Item.GetItemInfo`, then `"Item #id"`
- `Data:GetItemSources(id) -> { { kind = "boss", id = bossID, chance = 0.18 }, ... }` — inverted index, built lazily
- `Data:GetInstance(id)`, `Data:GetInstanceIDs()` (by level, then name), `Data:GetBoss(id)`, `Data:GetBossLoot(bossID)`,
  `Data:GetInstanceName(id)`, `Data:GetBossName(id)`
- `Data:GetVersion()` — bumps on every change; cache against it

### Filters

`ForeverLoot.Filters` is the registry behind the filter menu on query folders. Register your
own to make it appear there:

```lua
ForeverLoot.Filters:Register({
    id = "myaddon-usable",          -- prefix with your addon name
    name = "Usable by me",
    order = 90,                     -- menu position, lower first (built-ins use 10..80)
    kind = "multi",                 -- "multi" = checkboxes (values OR-ed) | "single" = radios (one value or nil)
    options = { { value = 1, label = "Yes" } },  -- or a function returning that list (re-evaluated when the data changes)
    match = function(itemID, row, value) return ... end,   -- row = Data.items[itemID]
    index = function(itemID, row) return key end,          -- optional: option value(s) of the item -> precomputed buckets
})
```

Built-in ids: `quality`, `slot`, `armorType`, `weaponType`, `itemLevel`, `reqLevel`, `instance`, `boss`.
Other calls: `Filters:Get(id)`, `Filters:GetAll()`, `Filters:GetOptions(id)`, `Filters:GetBucket(id, value)`,
`Filters:Unregister(id)`. Registering fires `OnFiltersChanged`.

### Queries

A query is plain data — no functions — so it can be saved or shared:

```lua
local ids = ForeverLoot.Query.Run({
    search = "defias",                                       -- case-insensitive substring; all digits also matches the id
    filters = { quality = { 3, 4 }, slot = { "INVTYPE_CHEST" }, itemLevel = "21-30" },
    sort = "name",                                           -- "name" | "ilvl" | "quality" | "id"
})
```

Different filters are AND-ed, the values of one filter OR-ed. `Query.New()`, `Query.Copy(q)`
and `Query.IsEmpty(q)` are helpers. Each view (tab) keeps its own query per query folder.

## Events

Backed by CallbackHandler-1.0:

```lua
ForeverLoot.RegisterCallback(myTable, "OnModuleRegistered", function(event, id, replaced) end)
ForeverLoot.RegisterCallback(myTable, "OnModuleUnregistered", function(event, id) end)
ForeverLoot.RegisterCallback(myTable, "OnModulesChanged", function(event) end)
ForeverLoot.RegisterCallback(myTable, "OnDataChanged", function(event) end)     -- item DB changed
ForeverLoot.RegisterCallback(myTable, "OnFiltersChanged", function(event) end)  -- filter registry changed
ForeverLoot.UnregisterCallback(myTable, "OnModulesChanged")
```

`OnModulesChanged` fires after either of the first two. The main window listens to it and
refreshes any view that is sitting at the root; `OnDataChanged`/`OnFiltersChanged` redraw the
open views.
