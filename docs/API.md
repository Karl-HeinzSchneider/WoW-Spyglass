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

## Nodes

A node is a plain table. Folders have `children`; leaves are items.

```lua
{ name = "Boss", icon = "Interface\\Icons\\...", children = { ... } }  -- folder
{ itemID = 17070 }                                                    -- item (real)
{ name = "Some Sword", quality = 4, icon = "Interface\\Icons\\..." }  -- item (placeholder)
```

Folders may also set `columns = 1 | 2` to control how their children are laid out: one
full-width column (the default) or two columns per page. This is decided by the collection,
not by a user setting, so choose it per list (e.g. `columns = 2` for a boss's loot table).

Constructors (optional sugar):

- `ForeverLoot.Folder(name, icon, children, opts?)` — `opts = { columns = 2, description = "..." }`
- `ForeverLoot.Item(itemID)`
- `ForeverLoot.PlaceholderItem(name, quality, icon)` — hard-coded display data, for prototyping
- `ForeverLoot.PlaceholderItems(prefix, count)` — generates `count` placeholder items

Item display from `itemID` is not implemented yet; such nodes currently show `Item #<id>`.

## Other calls

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
