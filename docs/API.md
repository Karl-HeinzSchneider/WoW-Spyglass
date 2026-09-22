# ForeverLoot public API

ForeverLoot exposes a global table `ForeverLoot` that other addons can use to add content to the
ForeverLoot window. ForeverLoot's own content (the folders under `ForeverLoot/modules/`) is registered through
exactly the same calls, so anything the built-in modules can do, yours can too.

Load order: list `ForeverLoot` under `## Dependencies:` (or `## OptionalDeps:` and check
`ForeverLoot ~= nil`) in your TOC so the global exists when your files run.

The official `ForeverLoot_Locale` and `ForeverLoot_Scraper` companion addons follow this same
contract. They depend on the core and use only this public global; the core never depends on or
reaches into either companion. See [architecture.md](architecture.md) for ownership boundaries.

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

Built-in module ids: `"items"`, `"raids"`, `"dungeons"`, `"crafting"`, `"pvp"`, `"collections"`,
`"reputation"`. The built-in raids/dungeons sort by `minLevel`, then name. If your instance is
in the game's data, prefer adding its drops to the item database (`ForeverLoot.Data:AddBossLoot`)
— it then shows up in the built-in modules and in the item browser's filters automatically. The
same goes for the other four: a list added with `ForeverLoot.Data:AddList` /
`AddListLoot` under one of those kinds becomes a tile in that module.

## `ForeverLoot:RegisterModule(def) -> boolean`

Registers (or, if `def.id` already exists, replaces) a module. Returns `false` and logs an error
if the definition is invalid; it never throws.

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | yes | Unique key. Prefix with your addon name to avoid collisions. |
| `name` | string | yes | Display name. |
| `icon` | string \| number | yes | Texture path or fileID. |
| `order` | number | no | Sort position among modules; lower first. Default `100`. Ties sort by name. The built-in content modules use 10–60, the item browser `1000` so it stays last. |
| `spacerBefore` | boolean | no | Leaves one empty row above the module in the root list (not when it comes first). The built-in `items` module uses it to sit apart from the content modules. |
| `description` | string | no | Free text for tooltips. |
| `children` | Node[] | one of | The module's top-level entries. |
| `getChildren` | fun(def) -> Node[] | one of | Lazy alternative; called once, the first time the tree is built. Errors are caught and logged. |
| `sortChildren` | boolean \| fun(a, b) | no | `true` sorts children by node `order` (default 100), then `name`; a function is used as the comparator and receives the full nodes (metadata included). Applies to `AddToModule` entries too. |
| `query` | boolean | no | The module's own list is the item database, filtered by the view's search box and filter menu (see [Item database](#item-database)). `children` may be `{}`. |
| `columns`, `display`, `groupBy` | | no | Layout of the module's own list, as on folder nodes (see [Tiles](#tiles) and [Cards](#cards)). |
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
{ itemID = 2851, infoRight = "|cffffff00 70|r", tooltip = fn } -- item with its own top-right text and extra tooltip lines
{ spellID = 22888 }                                         -- spell: name/icon from the game, spell tooltip
{ name = "Title", icon = "...", description = "Second line", -- custom entry
  quality = 4, category = "Misc", tooltip = { "line", ... },
  onClick = function(node, button) end }
```

Items and spells resolve lazily. An item the client hasn't cached yet is drawn from the item
database (name, quality, item level) when it is in there, otherwise as "Item #id"; either way
it redraws when the game's data arrives. `ForeverLoot.IsFolder(node)` tells whether a node
opens (static, dynamic or query folder).

Any entry may carry `tooltip`: a list of extra lines, or a function `(node) -> lines` called
each time the tooltip is shown (so names the client fetched in the meantime are used). On items
and spells the lines follow the game's own tooltip. A row shows `infoRight` in its top-right
corner when it has no `chance` (the built-in recipe rows put the skill thresholds there).

Folders may also set `columns = 1 | 2` to control how their children are laid out: one
full-width column (the default) or two columns per page. This is decided by the collection,
not by a user setting, so choose it per list (e.g. `columns = 2` for a boss's loot table).

### Tiles

A folder with `display = "tiles"` draws its entries as picture cards instead of rows — three
per line by default (`columns` = 1..4), about twice as tall as a row. Each entry may carry:

| Field | Type | Notes |
|---|---|---|
| `background` | string \| number | Wide texture (path or fileID) filling the card. Without it the card is dark and shows the entry's `icon`. |
| `backgroundCoords` | number[4] | `{ left, right, top, bottom }` in 0..1: the part of `background` to show. Whole texture by default. |
| `info` | string | Small text in the bottom-left corner. Defaults to the level range (`minLevel`-`maxLevel`) when the entry has one. |
| `infoRight` | string | Small text in the bottom-right corner. |

The entry's `name` is the card's title (in `quality` color when set); clicking, tooltips and
right-click-to-go-back work as for rows. Headers and groups inside the folder are drawn as
usual. The built-in Raids/Dungeons modules are tile folders; `InstanceFolder` nodes carry the
instance's picture from the database.

### Cards

A folder with `display = "cards"` draws its entries as portrait cards: a bevelled card with a
picture standing on its left, the name and the two info texts beside it, two cards per line
(`columns` = 1..2). Entries use `info` / `infoRight` as for tiles plus:

| Field | Type | Notes |
|---|---|---|
| `portrait` | string \| number | Picture on the left of the card (path or fileID), best a bust on transparency at 2:1. Without it the entry's `icon` is shown there. |
| `quests` | integer[] | Quest ids the entry is involved in: the card shows a quest "!" and the tooltip lists the quests' titles. |

`InstanceFolder` nodes are card folders: each `BossFolder(bossID)` carries what the database
knows about the boss — portrait, `info` as "<level> <creature type>" (e.g. "60 Beast"), `quests`,
and `infoRight` reserved for its *drops of interest* (hidden until the planned favorites
system decides what counts).

```lua
ForeverLoot:RegisterModule({
    id = "myaddon-favorites", name = "Favorites", icon = icon, display = "tiles",
    children = {
        ForeverLoot.Folder("Deadmines", icon, entries, {
            background = "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-Deadmines",
            backgroundCoords = { 0.0156, 0.6641, 0.0703, 0.6797 }, -- the picture is in the top-left of a 256x128 texture
            minLevel = 15, maxLevel = 21, infoRight = "Westfall",
        }),
    },
})
```

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
- `{ spacer = true }` is one empty row of space (as high as a list row, nothing drawn), e.g. to
  set an entry apart from the rest. Dropped when it would fall at the top of a page.

### Automatic grouping

Set `groupBy` on a folder to cluster its plain entries under group labels automatically.
Explicit headers/groups in the same list are kept as written; only the entries between them
are grouped.

- `groupBy = "auto"` uses `ForeverLoot.DefaultGroupKey`: items into four groups in this order —
  *Quest Items & Misc* (quest items and anything that isn't gear: recipes, consumables, keys, …),
  *Armor* (head to feet, cloaks, shirts, tabards), *Weapons* (weapons, shields, off-hands, ranged,
  relics) and *Rings, Amulets & Trinkets* — then spells under "Spells", folders under
  "Collections", custom entries by their `category`.
- `groupBy = function(node) return key, label end` for your own logic (return `nil` to leave
  an entry ungrouped under "Other"). Groups with unknown keys keep first-seen order.

Inside each group, entries are sorted by `ForeverLoot.DefaultEntryRank`: first by type (armor:
cloth, leather, mail, plate; weapons: by weapon type, shields and off-hands after them), then by
slot (head, shoulder, chest, … / neck, finger, trinket / main hand, off hand, …); everything
else keeps its written order.

`ForeverLoot.GroupEntries(entries, keyFn?, rankFn?)` exposes the same bucketing and sorting for
your own use; pass `rankFn` to change the in-group order.

Constructors (optional sugar):

- `ForeverLoot.Folder(name, icon, children, opts?)` — `opts = { columns = 2, display = "tiles", description = "...", groupBy = "auto" }`
- `ForeverLoot.Header(text)` — section header inside a list
- `ForeverLoot.Group(text, items?)` — group label, optionally with its entries
- `ForeverLoot.Spacer()` — one empty row
- `ForeverLoot.Item(itemID)`
- `ForeverLoot.Spell(spellID)`
- `ForeverLoot.Custom({ name, icon, description, quality, category, tooltip, onClick })`
- `ForeverLoot.InstanceFolders(type)` — folders for every DB instance of `type` (`"dungeon"` / `"raid"`)
- `ForeverLoot.InstanceFolder(instanceID)` / `ForeverLoot.BossFolder(bossID)` / `ForeverLoot.BossLootEntries(bossID)` —
  DB-backed folders: instance → bosses → drops with `chance`
- `ForeverLoot.ListFolders(kind)` — folders for every curated list of `kind` (`"crafting"`, `"pvp"`,
  `"collections"`, `"reputation"`), by `order` then name; the built-in modules of those names are exactly this
- `ForeverLoot.ListFolder(kind, id)` / `ForeverLoot.ListEntries(kind, id)` — one list as a two-column
  folder; its item nodes carry the row's fields in `meta` (`standing`, `rank`, `skill`, `spell`, `source`,
  `side`, `group`) and are grouped by the row's `group`, else the kind's default (standing / honor rank /
  trade skill category, then skill tier), else the item's type. A crafting list with a `skillLineID`
  starts from the recipe database: every recipe of that profession becomes an entry (the item it
  makes, or the spell for enchants) with `meta.spell` and `meta.category`, the skill thresholds as
  `infoRight` and reagents/tools in the tooltip; the list's own rows then add their fields to the
  recipe they name (by `spell`, or by the item exactly one recipe makes) or become plain entries.
  `ListFolder` then splits a profession into one sub-folder per trade skill category ("Weapon
  Stones", "Plate Helmets", ...; a curated `group` label makes a folder of its own, rows with
  neither go under "Other"), each with its first recipe's icon and a recipe count, so the
  profession page is a list of categories rather than hundreds of rows. Crafting folders show the
  character's rank ("145 / 150") as `info` and the localized profession name.
  A plain click on any row whose `meta.spell` is a recipe in `Data.recipes` opens the recipe popup
  (product and teaching item, recipe link and reagents); modified clicks still link the row's item.
- `ForeverLoot.Log(fmt, ...)` — prefixed chat message
- `ForeverLoot.LogAt(level, fmt, ...)` — threshold-aware diagnostic output using the core logger
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

### Slash-command extensions

Companion and third-party addons can add a subcommand to the core `/fl` dispatcher without
accessing its private AceAddon object:

```lua
local function handleScan(from, to, mode)
    -- ...
end

ForeverLoot:RegisterCommand("scan", handleScan, "/fl scan <from> [to]")
ForeverLoot:UnregisterCommand("scan", handleScan)
```

Names are lowercase command words. `show`, `loglevel`, and `reset` are reserved by the core;
duplicate registration fails. A handler receives up to three parsed arguments and its errors are
caught and logged. The usage string is appended to `/fl` help while registered.

## Item database

`ForeverLoot.Data` holds every scanned item and where it drops. ForeverLoot ships its data as
generated files (`ForeverLoot/db/generated/` plus non-English names in
`ForeverLoot_Locale/db/generated/`, built by the root TypeScript tools from in-game item scans, the
curated drop JSON in `.contribute/` and wago.tools' instance/encounter tables); other addons may
add to it with the same calls. The scraper companion adds whatever it scans or sees dropping
in-game (`ForeverLootScraperDB.global.discovered`, see `ForeverLoot_Scraper/src/discovery.lua`),
so `Data.items` can grow at runtime while the scraper is enabled.
Instance ids are `Map` ids, boss ids are `DungeonEncounter` ids. Tables are integer-keyed:

```lua
local Data = ForeverLoot.Data
Data.items[5188]     -- { quality, itemLevel, reqLevel, classID, subclassID, equipLoc, bind, icon (fileDataID),
                     --   stats, sellPrice, stackCount, setID, expansionID, craftingReagent }; indices in Data.ITEM
                     -- stats = { INTELLECT = 4, SPELL_POWER = 18 } (GetItemStats keys without ITEM_MOD_/_SHORT) or nil
Data.instances[36]   -- { type = "dungeon", bosses = { 2741, ... }, minLevel = 15, maxLevel = 21, expansionID = 0, icon = "..." }
Data.bosses[2747]    -- { instanceID = 36, order = 6000 }
Data.bossLoot[2747]  -- { { 5188, 0.9 }, { 5191 }, ... }   -- { itemID, chance 0..1 or nil }
Data.lists.reputation.argent_dawn      -- { name = "Argent Dawn", icon = "...", order = 1, factionID = 529 }
Data.listLoot.reputation.argent_dawn   -- { { 13209, standing = "Friendly" }, ... }   -- { itemID, field = value, ... }
Data.recipes[2661]   -- { skillLineID, itemID, count, minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy };
                     -- indices in Data.RECIPE: Copper Chain Belt = { 164, 2851, 1, 1, 70, 90, 110, 2466, { 2840, 6 } }
Data.categories[2466] -- { skillLineID = 164, order = 160 }   -- trade skill category ("Mail Belts"), for group order
Data.names.enUS      -- { items = { [5188] = "Filled Vessel" }, bosses = {...}, instances = {...},
                     --   skillLines = { [164] = "Blacksmithing" }, categories = { [2466] = "Mail Belts" }, tools = { [162] = "Blacksmith Hammer" } }
```

Curated item lists (`Data.lists[kind][id]`) back the Crafting, PvP, Collections and Reputation
modules: `kind` is one of `"crafting"`, `"pvp"`, `"collections"`, `"reputation"` (other addons may
add kinds of their own and browse them with `ListFolders`), `id` is a string unique within the kind
(the shipped ones are the `.contribute/data/<kind>/<id>.json` file names; prefix yours). A list is
`{ name, icon?, background?, backgroundCoords?, info?, order?, factionID?, skillLineID? }`; reputation
folders use `factionID` to resolve the localized name, description, current reaction and progress
from `C_Reputation` at runtime, falling back to the generated fields. Its rows
are `{ itemID, field = value, ... }` with the kind's fields by name (`standing`, `rank`, `skill`,
`spell`, `source`, `side`) and an optional `group` label; a crafting row for a recipe that makes
no item (an enchant) has no `itemID`, only its `spell`, and shows as a spell entry.

Recipes (`Data.recipes`) are keyed by their spell id and come from the client's own spell tables
(wago.tools `SkillLineAbility`, `SpellReagents`, `SpellEffect`, `SpellTotems`), limited to
recipes whose products the scans confirm. A row is positional (`Data.RECIPE`): the profession's
`skillLineID`, the created `itemID` (0 for enchants), `count` (a number, or `{ min, max }`),
`minSkill` (the skill needed to learn it: the requirement of the recipe item that teaches it when
one is known, else the client's ability minimum, which is 1 for nearly every Classic recipe —
trainer requirements are server-side and belong in the curated `skill` row field), the skill at
which it turns `yellow`, `green` and `grey` (orange below yellow), the `categoryID` into
`Data.categories`, `reagents` as flat `{ itemID, count, ... }` pairs, `tools` as ids into
`Data.names[locale].tools`, `auto` (learned automatically at `minSkill`) and `taughtBy` (the
scanned recipe item — "Plans: …" — that teaches it, nil when none is known).

Adding data (any call may be repeated; every one invalidates the caches and fires `OnDataChanged`):

- `Data:AddItems({ [itemID] = { quality, ilvl, reqLevel, classID, subclassID, equipLoc, bind, icon, stats, ... }, ... })`
- `Data:AddInstance(id, def)`, `Data:AddBoss(id, def)` (appends to its instance's `bosses` if missing),
  `Data:AddBossLoot(bossID, { { itemID, chance }, ... })`
- `Data:AddList(kind, id, def)`, `Data:AddListLoot(kind, id, { { itemID, standing = "Honored" }, ... })`
- `Data:AddRecipes({ [spellID] = { skillLineID, itemID, count, minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy }, ... })`,
  `Data:AddCategories({ [id] = { skillLineID = 164, order = 30 }, ... })`
- `Data:AddNames(locale, kind, { [id] = name })` with `kind` one of `"items"`, `"bosses"`, `"instances"`,
  `"skillLines"`, `"categories"`, `"tools"` — enUS is the fallback; the official locale addon registers
  every generated non-English name through this call

Reading:

- `Data:GetItem(id) -> row?`, `Data:GetItemField(id, Data.ITEM.ILVL)`, `Data:GetItemIDs()` (sorted, cached),
  `Data:GetItemCount()`, `for id, row in Data:EachItem() do`
- `Data:GetItemName(id) -> name, known` — client locale, then enUS, then `C_Item.GetItemInfo`, then `"Item #id"`
- `Data:GetItemStats(id) -> { INTELLECT = 4, ... }?`, `Data.StatLabel("INTELLECT") -> "Intellect"` (the game's `ITEM_MOD_*_SHORT`)
- `Data:GetItemSources(id) -> { { kind = "boss", id = bossID, chance = 0.18 }, { kind = "reputation", id = "argent_dawn", standing = "Honored" }, { kind = "recipe", id = spellID, skillLineID = 164 }, ... }`
  — inverted index over boss loot, every list (a list source carries its row's fields) and the recipes that make the item, built lazily
- `Data:GetInstance(id)`, `Data:GetInstanceIDs()` (by level, then name), `Data:GetBoss(id)`, `Data:GetBossLoot(bossID)`,
  `Data:GetInstanceName(id)`, `Data:GetBossName(id)`
- `Data:GetList(kind, id)`, `Data:GetListIDs(kind)` (by `order`, then name), `Data:GetListLoot(kind, id)`
- `Data:GetRecipe(spellID) -> row?`, `Data:GetRecipeIDs(skillLineID)` (spell ids in the trade skill window's order:
  category, then the yellow threshold; cached), `Data:GetCategory(id)`
- `Data:GetName(kind, id) -> string?` — client locale, then enUS, for `"skillLines"`, `"categories"` and `"tools"`
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

Built-in ids: `quality`, `slot`, `armorType`, `weaponType`, `itemLevel`, `reqLevel`, `instance`, `boss`,
`profession` (items made by a profession's recipes; one option per crafting list with a `skillLineID`).
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
