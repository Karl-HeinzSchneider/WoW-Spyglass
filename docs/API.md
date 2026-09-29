# Spyglass public API

Spyglass exposes a global table `Spyglass` that other addons can use to add content to the
Spyglass window. Spyglass's own content (the folders under `Spyglass/modules/`) is registered through
exactly the same calls, so anything the built-in modules can do, yours can too.

Load order: list `Spyglass` under `## Dependencies:` (or `## OptionalDeps:` and check
`Spyglass ~= nil`) in your TOC so the global exists when your files run.

The official `Spyglass_Database`, `Spyglass_Locale` and `Spyglass_Scraper` companion
addons follow this same contract. They depend on the core and use only this public global; the
core never reaches into a companion. `Spyglass_Locale` is load-on-demand, and the core asks the
client to load it on non-English clients; all integration after loading still goes through this
public API. See [architecture.md](architecture.md) for ownership boundaries.

```lua
-- MyAddon/MyAddon.toc
## Dependencies: Spyglass

-- MyAddon/MyAddon.lua
local SG = Spyglass

SG:RegisterModule({
    id = "myaddon-worldbosses",          -- unique; prefix with your addon name
    name = "World Bosses",               -- shown in the window
    icon = "Interface\\Icons\\Achievement_Boss_Azuregos",
    order = 30,                          -- lower sorts first (built-ins use 10, 20, ...)
    description = "Outdoor raid bosses", -- optional
    children = {
        SG.Folder("Azuregos", "Interface\\Icons\\Achievement_Boss_Azuregos", {
            SG.Item(17070), -- Fang of the Mystics
            SG.Item(18202), -- Eskhandar's Left Claw
        }),
    },
})
```

## Adding to an existing module

You don't have to create a module to contribute content. `Spyglass:AddToModule(id, node)`
appends a folder (or any node) to a registered module, e.g. a new dungeon inside the built-in
`"dungeons"` module:

```lua
local dungeon = Spyglass.Folder("Gnomeregan", "Interface\\Icons\\...", { ...bosses... }, { minLevel = 24 })
Spyglass:AddToModule("dungeons", dungeon)
```

Built-in module ids: `"raids"`, `"dungeons"`, `"crafting"`, `"pvp"`, `"collections"`,
`"reputation"`, `"lists"` (the user's [item lists](#lists-and-favorites)); `Spyglass_Database` adds
`"items"` (the item browser). `"collections"` lists its curated lists, then the database's item sets as one tile per source — Dungeon, Raid, PvP,
Crafted, Reputation and Other Sets — each set going to the source most of its items have
(`Data:GetItemSources`), grouped by armor type inside. The set tiles are always there and
find their sets when opened (a module's entries are built while the core loads, before an
addon has added the item rows). The built-in
dungeons sort by level range (`minLevel`, then `maxLevel`; none last), then name; the raids keep
the order they are listed in. If your instance is in the game's data, prefer adding its drops to the item database (`Spyglass.Data:AddBossLoot`)
— it then shows up in the built-in modules and in the item browser's filters automatically. The
same goes for the other four: a list added with `Spyglass.Data:AddList` /
`AddListLoot` under one of those kinds becomes a tile in that module.

## `Spyglass:RegisterModule(def) -> boolean`

Registers (or, if `def.id` already exists, replaces) a module. Returns `false` and logs an error
if the definition is invalid; it never throws.

| Field                                     | Type                      | Required | Notes                                                                                                                                                                                         |
| ----------------------------------------- | ------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`                                      | string                    | yes      | Unique key. Prefix with your addon name to avoid collisions.                                                                                                                                  |
| `name`                                    | string                    | yes      | Display name.                                                                                                                                                                                 |
| `icon`                                    | string \| number          | yes      | Texture path or fileID.                                                                                                                                                                       |
| `order`                                   | number                    | no       | Sort position among modules; lower first. Default `100`. Ties sort by name. The built-in content modules use 10–70, the item browser `1000` so it stays last.                                 |
| `spacerBefore`                            | boolean                   | no       | Leaves one empty row above the module in the root list (not when it comes first). The `items` module (`Spyglass_Database`) uses it to sit apart from the content modules.                     |
| `description`                             | string                    | no       | Free text for tooltips.                                                                                                                                                                       |
| `children`                                | Node[]                    | one of   | The module's top-level entries.                                                                                                                                                               |
| `getChildren`                             | fun(def) -> Node[]        | one of   | Lazy alternative; called once, the first time the tree is built. Errors are caught and logged.                                                                                                |
| `getEntries`                              | fun(node, view) -> Node[] | no       | The module's own list, built each time it is drawn, as a dynamic folder's `getChildren`; takes the place of `children` (which may be `{}`). The `lists` module uses it.                       |
| `sortChildren`                            | boolean \| fun(a, b)      | no       | `true` sorts children by node `order` (default 100), then `name`; a function is used as the comparator and receives the full nodes (metadata included). Applies to `AddToModule` entries too. |
| `query`                                   | boolean                   | no       | The module's own list is the item database, filtered by the view's search box and filter menu (see [Item database](#item-database)). `children` may be `{}`.                                  |
| `columns`, `display`, `groupBy`           |                           | no       | Layout of the module's own list, as on folder nodes (see [Tiles](#tiles) and [Cards](#cards)).                                                                                                |
| `panel`                                   | table \| function         | no       | The window's right pane inside the module, as on folder nodes (see [Info panel](#info-panel)).                                                                                                |
| `expansionID`, `seasonID`, `tags`, `meta` | various                   | no       | Metadata; see below.                                                                                                                                                                          |

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
database (name, quality, item level) when it is in there (the core ships no item rows;
`Spyglass_Database` adds them), otherwise as "Item #id"; either way it is requested and
redraws when the game's data arrives. `Spyglass.IsFolder(node)` tells whether a node
opens (static, dynamic or query folder).
Set `hidden = true` on a node to keep it available for navigation without drawing it in its
parent's list.

Any entry may carry `tooltip`: a list of extra lines, or a function `(node) -> lines` called
each time the tooltip is shown (so names the client fetched in the meantime are used). On items
and spells the lines follow the game's own tooltip. A row shows `infoRight` in its top-right
corner when it has no `chance` (the built-in recipe rows put the skill thresholds there).

A folder may carry a `panel`: what the window's right column shows while it (or a folder below
it) is open. See [Info panel](#info-panel).

Folders may also set `columns = 1 | 2` to control how their children are laid out: one
full-width column (the default) or two columns per page. This is decided by the collection,
not by a user setting, so choose it per list (e.g. `columns = 2` for a boss's loot table).

### Tiles

A folder with `display = "tiles"` draws its entries as picture cards instead of rows — three
per line by default (`columns` = 1..4), about twice as tall as a row. Each entry may carry:

| Field              | Type             | Notes                                                                                                                                                     |
| ------------------ | ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `background`       | string \| number | Wide picture filling the card: a texture (path or fileID) or an atlas name. Without it the card is dark and shows the entry's `icon`.                     |
| `backgroundCoords` | number[4]        | `{ left, right, top, bottom }` in 0..1: the part of `background` to show — of an atlas, the part of the atlas's own region. All of it by default.         |
| `showIcon`         | boolean          | With a `background`, also show the entry's `icon`, at the picture's left edge. The built-in Crafting tiles do, so a profession is recognized at a glance. |
| `info`             | string           | Small text in the bottom-left corner. Defaults to the level range (`minLevel`-`maxLevel`) when the entry has one.                                         |
| `infoRight`        | string           | Small text in the bottom-right corner.                                                                                                                    |

The entry's `name` is the card's title (in `quality` color when set); clicking, tooltips and
right-click-to-go-back work as for rows. Headers and groups inside the folder are drawn as
usual. The built-in Raids/Dungeons modules are tile folders; `InstanceFolder` nodes carry the
instance's picture from the database, and are named by the instance's `displayName` (a shorter
curated name, e.g. "SM: Graveyard") when it has one, else by `Data:GetInstanceName`.

### Cards

A folder with `display = "cards"` draws its entries as portrait cards: a bevelled card with a
picture standing on its left, the name and the two info texts beside it, two cards per line
(`columns` = 1..2). Entries use `info` / `infoRight` as for tiles plus:

| Field               | Type             | Notes                                                                                                                                                       |
| ------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `portrait`          | string \| number | Picture on the left of the card (path or fileID), best a bust on transparency at 2:1. Without it the entry's `icon` is shown there.                         |
| `portraitDisplayID` | integer          | CreatureDisplayID the client renders the picture from, for entries without a `portrait` (the game's own boss buttons draw creature portraits the same way). |
| `quests`            | integer[]        | Quest ids the entry is involved in: the card shows a quest "!" and the tooltip lists the quests' titles.                                                    |

`InstanceFolder` nodes are card folders. The first card, "All Bosses", lists every item any of
the instance's bosses drops (each item once), so the whole loot table reads at a glance. The
trash card follows, then each `BossFolder(bossID)` carries what the database
knows about the boss — portrait (a texture, or the model's display id for bosses without art), `info` as "<level> <creature type>" (e.g. "60 Beast"), `quests`,
and `infoRight` reserved for its _drops of interest_ (hidden until the planned favorites
system decides what counts). The right pane lists quests and has a button beneath them to open
`QuestFolder(instanceID)`; the quest folder is not a card in the instance list.

```lua
Spyglass:RegisterModule({
    id = "myaddon-favorites", name = "Favorites", icon = icon, display = "tiles",
    children = {
        Spyglass.Folder("Deadmines", icon, entries, {
            background = "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-Deadmines",
            backgroundCoords = { 0.0156, 0.6641, 0.0703, 0.6797 }, -- the picture is in the top-left of a 256x128 texture
            minLevel = 15, maxLevel = 21, infoRight = "Westfall",
        }),
    },
})
```

### Metadata

Modules and nodes accept optional metadata that Spyglass stores but does not interpret;
it is there for your sort functions, filters and other addons:

| Field                  | Type     | Notes                                                                                |
| ---------------------- | -------- | ------------------------------------------------------------------------------------ |
| `order`                | number   | Sort key used by `sortChildren = true`. Use fractions for ties, e.g. `60.1`, `60.2`. |
| `expansionID`          | integer  | e.g. `LE_EXPANSION_CLASSIC`                                                          |
| `seasonID`             | integer  |                                                                                      |
| `instanceID`           | integer  | journal / map instance id                                                            |
| `minLevel`, `maxLevel` | integer  |                                                                                      |
| `tags`                 | string[] |                                                                                      |
| `meta`                 | table    | anything else                                                                        |

`Folder(name, icon, children, opts)` copies every key of `opts` onto the node, so layout
options and metadata go in the same table; `Custom(def)` copies every field of `def`.

```lua
local dungeon = Spyglass.Folder("Gnomeregan", icon, bosses, {
    order = 29, minLevel = 24, maxLevel = 34, expansionID = 0, instanceID = 90, tags = { "tech" },
})
Spyglass:RegisterModule({
    id = "myaddon-season", name = "Season 3", icon = icon, seasonID = 3, children = {},
    sortChildren = function(a, b) return (a.minLevel or 0) < (b.minLevel or 0) end,
})
```

### Headers and groups

Inside a folder's `children`, from the biggest to the smallest:

- `{ header = "Weapons" }` renders as a big section header (spellbook-style title with a
  divider).
- `{ subheader = "Rare Drops", items = { ... } }` renders as a small centered section title with
  a line to either side, followed by `items` — one level under a header, for lists with enough
  sections that the group labels alone no longer structure them. Without `items` it just marks
  where the section starts. Set `onClick = function(node, button) end` to make the title clickable.
- `{ quest = questID, items = { ... }, info = "Level 14" }` renders as a full-width quest banner
  followed by `items` (what the quest rewards): the quest's title (`Data:GetQuestName`), `info`
  beside it, the curated `objective` under it, its `xp` on the right ("No rewards recorded" when
  the database has neither `xp` nor items), and the character's progress ("Done", "Ready",
  "Active", "Not started", with the gossip window's quest mark to match). Hover shows the same
  quest tooltip as the info panel's quest lines, shift-click links the quest in chat. If the node
  has `children`, clicking its banner opens them. Set `indent` to inset a nested quest banner
  from the left. `prerequisiteIDs` adds a completed/total prequest count before the objective.
  Unlike a subheader it stays when the filters remove all of its `items`.
- `{ group = "Tier 2", items = { ... } }` renders as a row-sized group label followed by
  `items`. Without `items` it just marks where a group starts in the surrounding list.
- `{ spacer = true }` is one empty row of space (as high as a list row, nothing drawn), e.g. to
  set an entry apart from the rest. Dropped when it would fall at the top of a page.

### Automatic grouping

Set `groupBy` on a folder to cluster its plain entries under group labels automatically.
Explicit headers, subheaders and groups in the same list are kept as written; only the entries
between them are grouped.

- `groupBy = "auto"` uses `Spyglass.DefaultGroupKey`: items into four groups in this order —
  _Quest Items & Misc_ (quest items and anything that isn't gear: recipes, consumables, keys, …),
  _Armor_ (head to feet, cloaks, shirts, tabards), _Weapons_ (weapons, shields, off-hands, ranged,
  relics) and _Rings, Amulets & Trinkets_ — then spells under "Spells", folders under
  "Collections", custom entries by their `category`.
- `groupBy = function(node) return key, label end` for your own logic (return `nil` to leave
  an entry ungrouped under "Other"). Groups with unknown keys keep first-seen order.

Inside each group, entries are sorted by `Spyglass.DefaultEntryRank`: first by type (armor:
cloth, leather, mail, plate; weapons: by weapon type, shields and off-hands after them), then by
slot (head, shoulder, chest, … / neck, finger, trinket / main hand, off hand, …); everything
else keeps its written order.

Both read an item's class and slot from the client, else from its item database row. An item
with neither (a server-side item the client hasn't fetched, without the database addon) is
grouped as _Quest Items & Misc_ at first; the window then fetches every such item of the list
and groups the list again once each has arrived, on the page it was showing.

`Spyglass.GroupEntries(entries, keyFn?, rankFn?)` exposes the same bucketing and sorting for
your own use; pass `rankFn` to change the in-group order.

Constructors (optional sugar):

- `Spyglass.Folder(name, icon, children, opts?)` — `opts = { columns = 2, display = "tiles", description = "...", groupBy = "auto" }`
- `Spyglass.Header(text)` — section header inside a list
- `Spyglass.Subheader(text, items?)` — small section title under a header, optionally with its entries
- `Spyglass.QuestEntry(questID, items?, info?)` — quest banner, optionally with its rewards
- `Spyglass.Group(text, items?)` — group label, optionally with its entries
- `Spyglass.Spacer()` — one empty row
- `Spyglass.Item(itemID)`
- `Spyglass.Spell(spellID)`
- `Spyglass.Custom({ name, icon, description, quality, category, tooltip, onClick })`
- `Spyglass.InstanceFolders(type)` — folders for every DB instance of `type` (`"dungeon"` / `"raid"`)
- `Spyglass.InstanceFolder(instanceID)` / `Spyglass.BossFolder(bossID)` / `Spyglass.BossLootEntries(bossID)` —
  DB-backed folders: instance → bosses → drops with `chance`
- `Spyglass.TrashFolder(instanceID)` / `Spyglass.TrashLootEntries(instanceID)` — the instance's
  trash card and its drops: what the enemies between the bosses drop (`Data:GetTrashLoot`), auto-grouped
  like a boss's loot and with the drop count as `info`
- `Spyglass.QuestFolder(instanceID)` / `Spyglass.InstanceQuestEntries(instanceID)` — the instance's
  quest folder and its contents: one clickable `QuestEntry` per quest, sorted by `requiredLevel`,
  then title. The folder's right pane shows the dungeon name and filters the list to the
  character's faction by default;
  Alliance and Horde include shared quests, and Both shows all quests. Each banner shows
  Alliance and/or Horde emblems immediately before XP, plus level
  and class in `info`, with no reward rows below it. Clicking opens a quest page with its title,
  objective, optional description, giver and turn-in details (including item icons and tooltips
  for item starts), map buttons where locations are known, and reward items. When present, a clickable
  subheader expands the ordered prerequisites
  as indented, numbered quest banners. Each prerequisite opens its own detail page, whose back button returns
  to the main quest; prerequisite pages do not open further prerequisites. The card carries the
  quest ids in `quests`, so it shows the same
  "!" and title list a boss with quests does.
- `Spyglass.ListFolders(kind, opts?)` — folders for every curated list of `kind` (`"crafting"`, `"pvp"`,
  `"collections"`, `"reputation"`), by `order` then name; the built-in modules of those names are exactly this
- `Spyglass.ListFolder(kind, id, opts?)` / `Spyglass.ListEntries(kind, id)` — one list as a two-column
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
  profession page is a list of categories rather than hundreds of rows. Professions with many
  categories can put those folders under subheaders — see _Category sections_ below. Crafting folders show the
  character's rank ("145 / 150") as `info` and the localized profession name.
  A plain click on any row whose `meta.spell` is a recipe in `Data.recipes` opens the recipe popup
  (product and teaching item, recipe link and reagents); modified clicks still link the row's item.
  Likewise, a plain click on any item row whose item belongs to a set (`Data:GetSetItems`) opens
  the set popup: the set's name and every item of the set.
- `Spyglass.Log(fmt, ...)` — prefixed chat message
- `Spyglass.LogAt(level, fmt, ...)` — threshold-aware diagnostic output using the core logger
- `Spyglass.PlaceholderItem(name, quality, icon)` — hard-coded display data, for prototyping
- `Spyglass.PlaceholderItems(prefix, count)` — generates `count` placeholder items

### Category sections (crafting)

A profession with many trade skill categories (Blacksmithing has 34) lists a lot of folders.
`sections` groups them under `Subheader` titles: each section has a `name` and the `categories`
below it, named by category id, by the category's displayed name, or by a curated `group` label.
The folders come in the order the section lists them, sections in array order, and categories no
section claims follow under "Other". Nothing else changes — the folders and their contents are
the same nodes.

Sections normally come from the profession's curated file (`.contribute/data/crafting/*.json`),
so every player sees them. A module can pass its own instead, which is the quick way to try a
grouping out:

```lua
Spyglass.ListFolders("crafting", {
    sections = {
        -- per list id (the JSON file's name); `false` drops the ones the data brings
        blacksmithing = {
            { name = "Plate Armor", categories = { 2469, 2470, 2471, 2472, 2473, 2474, 2475, 2476 } },
            { name = "Weapons", categories = { "Two-Handed Axes", "One-Handed Axes", "Daggers" } },
        },
        enchanting = false,
    },
})

-- or as a function of the list, and for a single profession
Spyglass.ListFolders("crafting", { sections = function(id, list) return mySections[list.skillLineID] end })
Spyglass.ListFolder("crafting", "tailoring", { sections = { { name = "Bags", categories = { "Bags", "Specialty Bags" } } } })
```

`opts` is passed through unchanged to every list, so the same call works for the other kinds;
only crafting lists read `sections` today.

### Info panel

The window's right column shows the _info panel_ of the selected tab: the `panel` of the
deepest node on the tab's path that has one, under that node's name. Nodes further down inherit
it (a profession's panel stays while one of its category folders is open). Without one on the
path, the pane shows the current node's name and `description`.

`panel` is a list of widgets drawn top to bottom, or a function `(node, view) -> widgets` called
each time the pane is drawn. Each widget has exactly one type key; the other fields are its
options:

An `{ item = itemID }` widget shows the item's icon and name. Hover shows its game tooltip;
modified click links it in chat.

| Widget                        | Options                                         | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------------------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `{ header = text }`           |                                                 | Section plate.                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `{ text = text }`             |                                                 | Wrapped text.                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `{ description = true }`      |                                                 | The panel node's `description`.                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `{ row = label }`             | `value`                                         | Label left, value right.                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `{ bar = kind }`              | `faction`, `skillLine`; `value`, `max`, `label` | `"reputation"`: the character's standing with `faction` (default `meta.factionID` of the panel node); `"skill"`: the rank in `skillLine` (default `meta.skillLineID`); `"value"`: `value` of `max`, `label` on the bar.                                                                                                                                                                                                                                                           |
| `{ checkbox = label }`        | `filter`                                        | While checked, hides the list's entries `filter` rejects: a built-in id (`"side"`: rows whose `meta.side` is the other faction; `"standing"`: rows whose `meta.standing` is above the character's standing with the panel node's faction) or a function `(entry, node) -> boolean`.                                                                                                                                                                                               |
| `{ dropdown = label }`        | `field`                                         | Offers every value of `meta[field]` among the current list's entries; picking one shows only entries with that value.                                                                                                                                                                                                                                                                                                                                                             |
| `{ factionDropdown = label }` |                                                 | Quest-list selector for Alliance, Horde, or Both; defaults to the character's faction.                                                                                                                                                                                                                                                                                                                                                                                            |
| `{ grouping = label }`        | `options`                                       | A dropdown of `options`, each `{ label = text, groupBy = ... }`; the picked one's `groupBy` (as on folder nodes, `false` = no groups) replaces the list's own. The first option is picked until another is.                                                                                                                                                                                                                                                                       |
| `{ button = label }`          | `onClick`, `open` or `map`                      | `onClick(node, view)`; `open`: a path from the root (`"crafting/cooking"`, see below); `map`: `{ uiMapID, x, y }` opens the world map there with a waypoint (x, y in 0..100).                                                                                                                                                                                                                                                                                                     |
| `{ quests = ids }`            |                                                 | One line per quest id: the title (`Data:GetQuestName`) and the character's progress, "Done", "Ready" (objectives complete), "Active" or "Not started". Quests the database marks for the other faction or another class are left out. Hover shows the quest tooltip (the game's when the client has the quest, else the curated title, `requiredLevel` and `objective`), followed by the quest's reward items with their icons and its `xp`; shift-click links the quest in chat. |
| `{ spacer = true }`           |                                                 | Empty space; a number is its height.                                                                                                                                                                                                                                                                                                                                                                                                                                              |

Checkbox and dropdown filters and the grouping apply to the entries of whatever list the tab
shows below the panel's node (folders remain visible except quest banners under the faction
selector) and are kept per tab and panel node until
the tab is closed. An `open` path is `/`-separated: each segment picks a folder among the entries of the
one before it, starting at the root, by module id, list id (`meta.listID`), crafting category id
or curated group label (category folders), `instanceID`, or name. The tab navigates there as if
clicked through.

```lua
Spyglass:RegisterModule({
    id = "myaddon-worldbosses", name = "World Bosses", icon = icon, children = bosses,
    panel = function(node, view)
        return {
            { header = "This week" },
            { row = "Killed", value = ("%d / %d"):format(killed(), #bosses) },
            { bar = "value", value = killed(), max = #bosses },
            { button = "Reset", onClick = function() resetKills() end },
        }
    end,
})
```

`ListFolder` gives every list its file's `panel` (see [contributing.md](contributing.md#the-info-panel-panel)),
else a default: reputation lists `{ bar = "reputation" }, { description = true }`, professions
`{ bar = "skill" }, { row = "Recipes", value = count }`. `InstanceFolder` gives an instance a
panel of its zone (`zone`, a uiMapID, by the client's name for it), level range, required level
(`requiredLevel`) and boss count, a "Show entrance" `map` button when the instance has an
`entrance` (`Data:AddInstance`, `{ uiMapID, x, y }`), and a `quests` line list of its quests.

## Other calls

- `Spyglass:AddToModule(id, node) -> boolean` — append an entry to a registered module
- `Spyglass:UnregisterModule(id) -> boolean`
- `Spyglass:GetModule(id) -> def?`
- `Spyglass:GetModules() -> def[]` — sorted by `order`, then `name`
- `Spyglass:GetRootNode() -> Node` — the virtual root the window browses (one child per module,
  each carrying `moduleID`). Cached until the module set changes.
- `Spyglass.API_VERSION` — currently `1`.

### Slash-command extensions

Companion and third-party addons can add a subcommand to the core `/sg` dispatcher without
accessing its private AceAddon object:

```lua
local function handleScan(from, to, mode)
    -- ...
end

Spyglass:RegisterCommand("scan", handleScan, "/sg scan <from> [to]")
Spyglass:UnregisterCommand("scan", handleScan)
```

Names are lowercase command words. `show`, `loglevel`, and `reset` are reserved by the core;
duplicate registration fails. A handler receives up to three parsed arguments and its errors are
caught and logged. The usage string is appended to `/sg` help while registered.

## Lists and favorites

`Spyglass.Lists` holds the user's item lists (a BiS list, a farm list, …), account-wide in
`SpyglassDB.global.lists`. The built-in list `Lists.FAVORITES` (`"favorites"`) comes first,
shows a star and can't be renamed, re-marked or deleted. Every other list has a _marker_, one of
the eight raid target icons (1 = star … 8 = skull). In the window, alt-click adds an item to the
_active_ list or removes it. The window's footer shows the active list in a dropdown that
switches it (as does a list's "Make active" button). Favorites is the active list until another
is made active, and again after the active list is deleted. An item on a list shows the list's marker on its icon
(the star top-left for Favorites, one other list's marker top-right: the active list's, else
the first that has the item). Every item tooltip gets one line per list that has the item and
`tooltip` set.

The `lists` module shows one tile per list, then "New list" and "Import list". A list opens as
its items. Its info panel says whether alt-click adds to it, and counts the items per kind of
content. It groups them with a `grouping` dropdown: by _Source_ (the instance, profession or list
an item comes from; the default), _Content_ (Dungeons, Raids, Crafted, PvP, Reputation,
Collections, No known source) or _Item type_ (`"auto"`). An item with several sources is filed
under the one of the earliest kind of content in that order. The panel's buttons make the list
active, and edit, export, import into or delete it.

- `Lists:GetAll() -> string[]` — every list id, Favorites first, then in the order made
- `Lists:Get(id) -> { name, marker?, tooltip, items = { [itemID] = true } }?` — read it, change it only through the calls below
- `Lists:Create(name, marker?, tooltip?) -> id?` — a free marker when none is given; `tooltip` defaults to true
- `Lists:Delete(id)`, `Lists:Rename(id, name)`, `Lists:SetMarker(id, marker)`,
  `Lists:SetShowInTooltip(id, show)` — each `-> boolean`, false when nothing changed
- `Lists:GetActive() -> id`, `Lists:SetActive(id) -> boolean`
- `Lists:Contains(id, itemID) -> boolean`, `Lists:SetItem(id, itemID, on) -> boolean` (changed),
  `Lists:Toggle(id, itemID) -> boolean` (on the list now)
- `Lists:GetItems(id) -> integer[]` (ascending), `Lists:GetCount(id) -> integer`,
  `Lists:GetListsOf(itemID) -> string[]` (in list order)
- `Lists:GetMarkerFile(marker) -> path`, `Lists:SetMarkerTexture(texture, id)`,
  `Lists:GetMarkerMarkup(id, size) -> string` — a list's marker (Favorites: the star)
- `Lists:Export(id) -> string?` — `FL1:<name>:<marker>:<id>,<id>,…`, with `%`, `:` and line
  breaks in the name as `%25`, `%3A`, `%0A`/`%0D`; Favorites exports marker 0
- `Lists:Import(text, intoID?) -> id?, countOrError` — reads an export string, else every
  `item:<id>` in the text (pasted links), else every number. It adds the items to `intoID`, or
  to a new list named and marked by the export (else "Imported list"). It returns the list and
  how many items were new to it, or nil and a message. Ids the database doesn't know are kept.
- `Lists:OpenCreateDialog()`, `OpenEditDialog(id)`, `OpenExportDialog(id)`,
  `OpenImportDialog(intoID?)`, `OpenDeleteDialog(id)` — the window's list dialog (name, marker
  and tooltip switch; the export string to copy; a box to paste into; the delete confirmation)

`Spyglass.Favorites` is the favorites API of before the lists, over the Favorites list:
`IsFavorite(itemID)`, `SetFavorite(itemID, favorite)`, `Toggle(itemID)`, `GetAll()`.

The SavedVariables load after the addons' files, so there are no lists before `ADDON_LOADED`
(`OnInitialize` in an AceAddon), and changes made before that are ignored. On first use the
favorites of the single-list version (`global.favorites`) move into the Favorites list. Every
change fires `OnListsChanged` (see [Events](#events)): with the item id for an item added or
removed, without one for a list made, deleted, renamed, re-marked, switched in tooltips, made
active or imported into. A change to Favorites' items also fires `OnFavoritesChanged`.

## Item database

`Spyglass.Data` holds every scanned item and where it drops. Spyglass ships its data as
generated files, built by the root TypeScript tools from in-game item scans, the curated drop
JSON in `.contribute/` and wago.tools' instance/encounter tables and localized item names: the
core's `Spyglass/db/generated/` has the instances, loot, lists, recipes and their English
names but **no item rows**; every scanned item row and its English name is in
`Spyglass_Database/db/generated/`, the non-English names in
`Spyglass_Locale/db/generated/`. Without the database addon `Data.items` is empty (unless
another addon adds rows) and the core's lists take what they show from the client. Other addons
may add to it with the same calls. The scraper companion adds whatever it scans or sees dropping
in-game (`SpyglassScraperDB.global.discovered`, see `Spyglass_Scraper/src/discovery.lua`),
so `Data.items` can grow at runtime while the scraper is enabled. On a non-English client the
locale companion looks up the names of the items the generated files don't name and registers
them with `AddNames` (`SpyglassLocaleDB`, see `Spyglass_Locale/src/itemnames.lua`).
Instance ids are `Map` ids, except for a map players see as several dungeons (Scarlet Monastery's
wings, Upper/Lower Blackrock Spire, Dire Maul's parts): each part has its own id, by convention
map × 100 + n (`18901` = Scarlet Monastery: Graveyard). Boss ids are `DungeonEncounter` ids.
Tables are integer-keyed:

```lua
local Data = Spyglass.Data
Data.items[5188]     -- { quality, itemLevel, reqLevel, classID, subclassID, equipLoc, bind, icon (fileDataID),
                     --   stats, sellPrice, stackCount, setID, expansionID, craftingReagent }; indices in Data.ITEM
                     -- stats = { INTELLECT = 4, SPELL_POWER = 18 } (GetItemStats keys without ITEM_MOD_/_SHORT) or nil
Data.instances[36]   -- { type = "dungeon", bosses = { 2741, ... }, minLevel = 15, maxLevel = 21, expansionID = 0, icon = "..." }
Data.bosses[2747]    -- { instanceID = 36, order = 6000 }
Data.bossLoot[2747]  -- { { 5188, 0.9 }, { 5191 }, ... }   -- { itemID, chance 0..1 or nil }
Data.trashLoot[36]   -- { { 1935, 0.01 }, ... }   -- same rows, keyed by the instance: what its non-boss enemies drop
Data.quests[166]     -- { id = 166, name = "The Defias Brotherhood", side = "Alliance", instanceID = 36, items = { { 2041 }, ... } }
                     -- a class quest also has class = "WARLOCK" (the client's class token);
                     -- optional requiredLevel, xp, objective, description, requires, start, turnIn
Data.instanceQuests[36] -- { 166, ... }   -- the instance's quest ids, in curated order
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
- `Data:AddTrashLoot(instanceID, { { itemID, chance }, ... })` — the same rows for what an instance's
  non-boss enemies drop; keyed by the instance, because trash belongs to no encounter
- `Data:AddQuests(instanceID, { { id = 166, name = "...", side = "Alliance", items = { { itemID }, ... } }, ... })` —
  the instance's quests. `side` is `"Alliance"`, `"Horde"` or `"Both"` (nil = both); `class` is a class
  token (`"WARLOCK"`) for a class quest (nil = any class). Optional `requiredLevel`, `xp`,
  `objective` and `description` feed the tooltip. `requires` is an array of direct prerequisites
  as `{ id, name? }`; the tooltip shows each one's completion state. `start` and `turnIn` are optional
  `{ npc?, npcID?, item?, location?, description? }` tables, where `location` is
  `{ uiMapID, x, y }` in map percentages and `description` is optional info text beside that
  endpoint. Each quest is stored by its id and listed under the instance in the order it was added.
  A quest registered under several instances appears in each; its `instanceID` field is
  the last registration, so use `Data:GetInstanceQuests(instanceID)` for membership. Quest titles
  are curated data: this client ships no quest table, and `C_QuestLog` only knows quests the
  character has seen.
- `Data:AddQuestDefinitions({ quest, ... })` — stores quests by id without listing them under an
  instance. The generator uses this for quests defined only as prerequisites. Definitions use the
  same fields as `AddQuests`.
- `Data:AddList(kind, id, def)`, `Data:AddListLoot(kind, id, { { itemID, standing = "Honored" }, ... })`
- `Data:AddRecipes({ [spellID] = { skillLineID, itemID, count, minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy }, ... })`,
  `Data:AddCategories({ [id] = { skillLineID = 164, order = 30 }, ... })`
- `Data:AddNames(locale, kind, { [id] = name })` with `kind` one of `"items"`, `"bosses"`, `"instances"`,
  `"skillLines"`, `"categories"`, `"tools"` — enUS is the fallback; the official locale addon registers
  every generated non-English name and every item name it learns in-game through this call

Reading:

- `Data:GetItem(id) -> row?`, `Data:GetItemField(id, Data.ITEM.ILVL)`, `Data:GetItemIDs()` (sorted, cached),
  `Data:GetItemCount()`, `for id, row in Data:EachItem() do`
- `Data:GetItemName(id) -> name, known` — client locale, then enUS, then `C_Item.GetItemInfo`, then `"Item #id"`
- `Data:GetItemStats(id) -> { INTELLECT = 4, ... }?`, `Data.StatLabel("INTELLECT") -> "Intellect"` (the game's `ITEM_MOD_*_SHORT`)
- `Data:GetItemSources(id) -> { { kind = "boss", id = bossID, chance = 0.18 }, { kind = "trash", id = instanceID, chance = 0.01 }, { kind = "quest", id = questID, instanceID = 36, side = "Alliance" }, { kind = "reputation", id = "argent_dawn", standing = "Honored" }, { kind = "recipe", id = spellID, skillLineID = 164 }, ... }`
  — inverted index over boss loot, instance trash, quest rewards, every list (a list source carries its row's fields) and the recipes that make the item, built lazily
- `Data:GetInstance(id)`, `Data:GetInstanceIDs()` (by level, then name), `Data:GetBoss(id)`, `Data:GetBossLoot(bossID)`,
  `Data:GetInstanceName(id)`, `Data:GetBossName(id)`
- `Data:GetTrashLoot(instanceID)`, `Data:GetInstanceQuests(instanceID) -> quest[]` (in curated order),
  `Data:GetQuest(questID)`, `Data:GetQuestName(questID)` — the client's title when it knows the quest,
  then the curated one, then `"#id"`
- `Data:GetList(kind, id)`, `Data:GetListIDs(kind)` (by `order`, then name), `Data:GetListLoot(kind, id)`
- `Data:GetSetItems(setID) -> itemID[]` (the set's items in the database, ascending), `Data:GetSetIDs()`
  (every set id an item belongs to, ascending; cached), `Data:GetSetName(setID)` — the client's
  `C_Item.GetItemSetInfo`, else `"Set #id"`. Built from the rows' `setID` (`Data.ITEM.SET`)
- `Data:GetRecipe(spellID) -> row?`, `Data:GetRecipeIDs(skillLineID)` (spell ids in the trade skill window's order:
  category, then the yellow threshold; cached), `Data:GetCategory(id)`
- `Data:GetName(kind, id) -> string?` — client locale, then enUS, for `"skillLines"`, `"categories"` and `"tools"`
- `Data:GetVersion()` — bumps on every change; cache against it

### Filters

`Spyglass.Filters` is the registry behind the filter menu on query folders. Register your
own to make it appear there:

```lua
Spyglass.Filters:Register({
    id = "myaddon-usable",          -- prefix with your addon name
    name = "Usable by me",
    order = 100,                    -- menu position, lower first (built-ins use 5..90)
    kind = "multi",                 -- "multi" = checkboxes (values OR-ed) | "single" = radios (one value or nil)
    options = { { value = 1, label = "Yes" } },  -- or a function returning that list (re-evaluated when the data changes)
    match = function(itemID, row, value) return ... end,   -- row = Data.items[itemID]
    index = function(itemID, row) return key end,          -- optional: option value(s) of the item -> precomputed buckets
})
```

Built-in ids: `type` (the item class, value = its `Enum.ItemClass` id; mounts and companion
pets are split out of Miscellaneous as `"15:5"` and `"15:2"`), `quality`, `slot`, `armorType`, `weaponType`, `itemLevel`, `reqLevel`, `instance`
(anything the instance drops or rewards: a boss's loot, its trash and its quests), `boss`,
`profession` (items made by a profession's recipes; one option per crafting list with a `skillLineID`).
Other calls: `Filters:Get(id)`, `Filters:GetAll()`, `Filters:GetOptions(id)`, `Filters:GetBucket(id, value)`,
`Filters:Unregister(id)`. Registering fires `OnFiltersChanged`.

### Queries

A query is plain data — no functions — so it can be saved or shared:

```lua
local ids = Spyglass.Query.Run({
    search = "defias",                                       -- case-insensitive substring of the name in the client's language or in English; all digits also matches the id
    filters = { quality = { 3, 4 }, slot = { "INVTYPE_CHEST" }, itemLevel = "21-30" },
    sort = "name",                                           -- "name" | "ilvl" | "quality" | "id"
})
```

Different filters are AND-ed, the values of one filter OR-ed. `Query.New()`, `Query.Copy(q)`
and `Query.IsEmpty(q)` are helpers. Each view (tab) keeps its own query per query folder.

## Events

Backed by CallbackHandler-1.0:

```lua
Spyglass.RegisterCallback(myTable, "OnModuleRegistered", function(event, id, replaced) end)
Spyglass.RegisterCallback(myTable, "OnModuleUnregistered", function(event, id) end)
Spyglass.RegisterCallback(myTable, "OnModulesChanged", function(event) end)
Spyglass.RegisterCallback(myTable, "OnDataChanged", function(event) end)     -- item DB changed
Spyglass.RegisterCallback(myTable, "OnFiltersChanged", function(event) end)  -- filter registry changed
Spyglass.RegisterCallback(myTable, "OnListsChanged", function(event, listID, itemID) end)       -- itemID nil: the list itself changed
Spyglass.RegisterCallback(myTable, "OnFavoritesChanged", function(event, itemID, isFavorite) end)
Spyglass.UnregisterCallback(myTable, "OnModulesChanged")
```

`OnModulesChanged` fires after either of the first two. The main window listens to it and
refreshes any view that is sitting at the root; `OnDataChanged`/`OnFiltersChanged` redraw the
open views, `OnListsChanged` the shown page (an item's badges) or the open views (a list itself
changed).
