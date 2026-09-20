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
local dungeon = ForeverLoot.Folder("Gnomeregan", "Interface\\Icons\\...", { ...bosses... })
dungeon.order = 29 -- level; built-in modules sort their children by `order`, then name
ForeverLoot:AddToModule("dungeons", dungeon)
```

Built-in module ids: `"raids"`, `"dungeons"`. ForeverLoot's own content uses exactly this call —
one file per instance under `modules/<module>/`.

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
| `expansionID`, `seasonID`, `tags`, `meta` | various | no | Metadata; see below. |

## Nodes

A node is a plain table; the fields set decide what it displays as:

```lua
{ name = "Boss", icon = "...", children = { ... } }         -- folder (navigable)
{ itemID = 17070 }                                          -- item: name/icon/quality/ilvl from the game, item tooltip, shift-click links
{ spellID = 22888 }                                         -- spell: name/icon from the game, spell tooltip
{ name = "Title", icon = "...", description = "Second line", -- custom entry
  quality = 4, category = "Misc", tooltip = { "line", ... },
  onClick = function(node, button) end }
```

Items and spells resolve lazily; an item whose data isn't cached yet shows "Item #id" and
redraws when the data arrives.

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

## Events

Backed by CallbackHandler-1.0:

```lua
ForeverLoot.RegisterCallback(myTable, "OnModuleRegistered", function(event, id, replaced) end)
ForeverLoot.RegisterCallback(myTable, "OnModuleUnregistered", function(event, id) end)
ForeverLoot.RegisterCallback(myTable, "OnModulesChanged", function(event) end)
ForeverLoot.UnregisterCallback(myTable, "OnModulesChanged")
```

`OnModulesChanged` fires after either of the other two. The main window listens to it and
refreshes any view that is sitting at the root.
