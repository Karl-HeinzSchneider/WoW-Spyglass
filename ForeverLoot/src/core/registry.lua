---@type string, ForeverLoot
local appName, app = ...

local log = app.logger

-- Public API. Exposed as the global `ForeverLoot` so other addons can register modules;
-- the addon's own modules (modules/*) go through exactly the same calls.
--
--   ForeverLoot:RegisterModule({ id = "raids", name = "Raids", icon = ..., children = {...} })
--   ForeverLoot.RegisterCallback(owner, "OnModuleRegistered", function(_, id) ... end)
--
-- See docs/API.md for the full contract.

-- A browsable tree node. What it displays as depends on which fields are set:
--   folder  : `children` (navigable)
--   item    : `itemID` (name/icon/quality resolved from the game)
--   spell   : `spellID`
--   custom  : `name` (+ `icon`, `description`, `onClick`, `tooltip`), also used by placeholders
--   header  : `header` (big section title)      group : `group` (row-sized label, + `items`)
--   subheader: `subheader` (small section title between the two, + `items`)
--   spacer  : `spacer` (one empty row of space)
--   dynamic : `getChildren` (folder whose entries are computed when opened)
--   query   : `query` (folder listing the item DB, filtered by the view's search/filter state)
---@class ForeverLoot.Node
---@field name? string
---@field icon? string|number
---@field description? string  # second text line on custom entries; tooltip line otherwise
---@field children? ForeverLoot.Node[]  # folders only
---@field getChildren? fun(node: ForeverLoot.Node, view: ForeverLoot.View): ForeverLoot.Node[]  # dynamic folders; called on every open
---@field query? boolean  # folder showing ForeverLoot.Data items through the view's ForeverLoot.Query
---@field itemID? integer
---@field chance? number  # items: drop chance 0..1, shown as a percentage
---@field spellID? integer
---@field quality? Enum.ItemQuality  # custom/placeholder entries: colors the name
---@field category? string  # custom/placeholder entries: bucket used by auto grouping
---@field tooltip? string[]|fun(node: ForeverLoot.Node): string[]  # extra tooltip lines (after the item/spell tooltip on those); a function is called when the tooltip shows
---@field onClick? fun(node: ForeverLoot.Node, button: string)  # custom entries
---@field moduleID? string  # set on the root's module nodes
---@field columns? integer  # folders: columns for this list; default 1 for rows, 3 for tiles
---@field display? "rows"|"tiles"|"cards"  # folders: how the entries are drawn; default "rows"
---@field groupBy? "auto"|fun(node: ForeverLoot.Node): string?, string?  # folders: auto-group ungrouped entries; see api.DefaultGroupKey
--- Tile / card fields, read when the parent folder has `display = "tiles"` or `"cards"`:
---@field background? string|number  # tiles: wide picture filling the tile (texture path, fileID or atlas name)
---@field backgroundCoords? number[]  # tiles: { left, right, top, bottom } part of `background` to show (of an atlas: of its region); all of it by default
---@field showIcon? boolean  # tiles: also show `icon` on a tile with a `background` (at its left edge)
---@field portrait? string|number  # cards: picture of the entry (e.g. a boss) on the left of the card; `icon` when unset
---@field portraitDisplayID? integer  # cards: CreatureDisplayID the client renders the picture from, for entries without a `portrait`
---@field info? string  # small text bottom-left; the level range when unset and `minLevel`/`maxLevel` are
---@field infoRight? string  # small text bottom-right; on rows: the top-right corner (where a `chance` would go)
---@field quests? integer[]  # cards: quest ids the entry is involved in; shows a "!" and lists their titles in the tooltip
---@field order? number  # sort key when the owning module sorts its children
---@field header? string  # section header marker; see ForeverLoot.Header
---@field subheader? string  # small section header marker; `items` optionally holds the entries under it; see ForeverLoot.Subheader
---@field spacer? boolean  # spacer marker: one empty row of space; see ForeverLoot.Spacer
--- Optional metadata, free for modules and custom sort functions to use:
---@field expansionID? integer  # e.g. LE_EXPANSION_CLASSIC
---@field seasonID? integer
---@field instanceID? integer  # journal/map instance id
---@field minLevel? integer
---@field maxLevel? integer
---@field tags? string[]
---@field meta? table<string, any>  # anything else
---@field group? string  # group label marker; `items` optionally holds the grouped entries
---@field items? ForeverLoot.Node[]

-- What api.ListFolder / api.ListFolders may be told about a list, so a module can regroup a
-- list without touching the curated data: `sections` replaces the list's own subheaders (see
-- ForeverLoot.ListSection), either directly, keyed by list id, or as a function of it;
-- `false` drops the ones the data brings.
---@class ForeverLoot.ListFolderOptions
---@field sections? ForeverLoot.ListSection[]|false|table<string, ForeverLoot.ListSection[]|false>|fun(id: string, list: ForeverLoot.List): ForeverLoot.ListSection[]|false|nil

---@class ForeverLoot.ModuleDef
---@field id string  # unique key, e.g. "raids"; other addons should prefix theirs ("myaddon-raids")
---@field name string  # display name
---@field icon string|number  # texture path or fileID
---@field order? number  # sort position in the root list; lower first, default 100
---@field spacerBefore? boolean  # an empty row above this module in the root list (unless it comes first)
---@field description? string  # shown in tooltips
---@field children? ForeverLoot.Node[]  # the module's top-level entries (may be empty and filled via AddToModule)
---@field getChildren? fun(def: ForeverLoot.ModuleDef): ForeverLoot.Node[]  # lazy alternative to `children`, called once
---@field query? boolean  # the module node lists the item DB (see ForeverLoot.Node.query); `children` may be empty
---@field columns? integer  # layout of the module's own list, as on folder nodes
---@field display? "rows"|"tiles"|"cards"
---@field groupBy? "auto"|fun(node: ForeverLoot.Node): string?, string?
---@field sortChildren? boolean|fun(a: ForeverLoot.Node, b: ForeverLoot.Node): boolean  # true = by node `order`, then name; a function gets the full nodes incl. metadata
--- Optional metadata, same meaning as on nodes:
---@field expansionID? integer
---@field seasonID? integer
---@field tags? string[]
---@field meta? table<string, any>

---@class ForeverLoot.API
---@field Data ForeverLoot.Data  # item database (ForeverLoot/src/data/data.lua)
---@field Filters ForeverLoot.Filters  # filter registry (ForeverLoot/src/data/filters.lua)
---@field Query ForeverLoot.QueryAPI  # query runner (ForeverLoot/src/data/query.lua)
---@field API_VERSION integer
---@field Log fun(fmt: string, ...: any)
---@field LogAt fun(level: string, fmt: string, ...: any): boolean
---@field RegisterCommand fun(self: ForeverLoot.API, name: string, handler: fun(a?: string, b?: string, c?: string), usage: string): boolean
---@field UnregisterCommand fun(self: ForeverLoot.API, name: string, handler?: function): boolean
---@field RegisterCallback fun(target: table, event: string, method: string|function, ...)
---@field UnregisterCallback fun(target: table, event: string)
---@field UnregisterAllCallbacks fun(target: table)
---@field callbacks CallbackHandlerRegistry
local api = {}
api.API_VERSION = 1

---@class ForeverLoot.CommandDef
---@field handler fun(a?: string, b?: string, c?: string)
---@field usage string

---@type table<string, ForeverLoot.CommandDef>
local commands = {}
local reservedCommands = { show = true, loglevel = true, reset = true }

-- True for anything the window can open: static, dynamic and query folders.
---@param node ForeverLoot.Node
---@return boolean
function api.IsFolder(node)
    return node.children ~= nil or node.getChildren ~= nil or node.query == true
end

-- Chat output with the ForeverLoot prefix, for module authors.
---@param fmt string
---@param ... any
function api.Log(fmt, ...)
    log:chat(fmt, ...)
end

-- Leveled output for companion/third-party addons; uses the core user's current log threshold.
---@param level string  # ERROR, WARN, INFO, VERBOSE, DEBUG or SILLY
---@param fmt string
---@param ... any
---@return boolean validLevel
function api.LogAt(level, fmt, ...)
    local value = type(level) == "string" and log.level[level:upper()] or nil
    if not value then
        log:error("LogAt: unknown level %q", tostring(level))
        return false
    end
    log:print(value, fmt, ...)
    return true
end

-- Adds a subcommand to the core `/fl` command without exposing the core AceAddon object.
---@param name string
---@param handler fun(a?: string, b?: string, c?: string)
---@param usage string
---@return boolean ok
function api:RegisterCommand(name, handler, usage)
    name = type(name) == "string" and name:lower() or ""
    if not name:match("^[a-z][a-z0-9_-]*$") or type(handler) ~= "function" or type(usage) ~= "string" then
        log:error("RegisterCommand: expected (command name, function, usage string)")
        return false
    end
    if reservedCommands[name] or commands[name] then
        log:error("RegisterCommand: command %q is already registered or reserved", name)
        return false
    end
    commands[name] = { handler = handler, usage = usage }
    return true
end

---@param name string
---@param handler? function  # when supplied, only unregisters the same handler
---@return boolean removed
function api:UnregisterCommand(name, handler)
    name = type(name) == "string" and name:lower() or ""
    local def = commands[name]
    if not def or (handler and def.handler ~= handler) then
        return false
    end
    commands[name] = nil
    return true
end

-- Private dispatcher used by the core AceAddon. Errors stay contained in the registering addon.
---@class ForeverLoot.CommandRegistry
local commandRegistry = {}
app.commands = commandRegistry

---@param name string
---@param ... string?
---@return boolean found
function commandRegistry:Run(name, ...)
    local def = commands[name]
    if not def then
        return false
    end
    local ok, err = pcall(def.handler, ...)
    if not ok then
        log:error("Command %q failed: %s", name, tostring(err))
    end
    return true
end

---@return string[]
function commandRegistry:GetUsages()
    local usages = {}
    for _, def in pairs(commands) do
        usages[#usages + 1] = def.usage
    end
    table.sort(usages)
    return usages
end

app.api = api
-- Installs api.RegisterCallback/UnregisterCallback/UnregisterAllCallbacks; we fire via the registry.
api.callbacks = LibStub("CallbackHandler-1.0"):New(api)

-- The public global. `appName` is "ForeverLoot"; spelled out so tooling can see the definition.
ForeverLoot = api

----------------------------------------------------------------------------------------------------
-- Node constructors (optional sugar for module authors)
----------------------------------------------------------------------------------------------------

-- Anything in here is copied onto the folder node: layout options and metadata alike.
---@class ForeverLoot.FolderOptions
---@field columns? integer  # columns per page: 1 (default) or 2 for rows and cards, up to 4 (default 3) for tiles
---@field display? "rows"|"tiles"|"cards"  # draw the entries as rows (default), picture tiles or portrait cards
---@field description? string
---@field background? string|number  # when this folder is itself listed as a tile
---@field backgroundCoords? number[]
---@field portrait? string|number  # when this folder is itself listed as a card
---@field info? string
---@field infoRight? string
---@field quests? integer[]
---@field groupBy? "auto"|fun(node: ForeverLoot.Node): string?, string?  # cluster entries under group labels
---@field order? number
---@field expansionID? integer
---@field seasonID? integer
---@field instanceID? integer
---@field minLevel? integer
---@field maxLevel? integer
---@field tags? string[]
---@field meta? table<string, any>

---@param name string
---@param icon string|number
---@param children ForeverLoot.Node[]
---@param opts? ForeverLoot.FolderOptions
---@return ForeverLoot.Node
function api.Folder(name, icon, children, opts)
    local node = { name = name, icon = icon, children = children }
    for key, value in pairs(opts or {}) do
        if key ~= "name" and key ~= "icon" and key ~= "children" then
            node[key] = value
        end
    end
    return node
end

-- A group label inside a list: row-sized text, lighter than a Header. With `items`, those
-- entries follow the label; without, it just marks where a group starts.
---@param text string
---@param items? ForeverLoot.Node[]
---@return ForeverLoot.Node
function api.Group(text, items)
    return { group = text, items = items }
end

-- A spell, resolved from the game's spell data.
---@param spellID integer
---@return ForeverLoot.Node
function api.Spell(spellID)
    return { spellID = spellID }
end

-- Anything else: an icon, a title, an optional description line, tooltip lines and a click
-- handler. Every field is copied, so metadata (expansionID, tags, meta, ...) comes along.
---@param def { name: string, icon?: string|number, description?: string, quality?: Enum.ItemQuality, category?: string, tooltip?: string[], onClick?: fun(node: ForeverLoot.Node, button: string), [string]: any }
---@return ForeverLoot.Node
function api.Custom(def)
    local node = {}
    for key, value in pairs(def) do
        node[key] = value
    end
    return node
end

-- A section header inside a folder's children, e.g. to split a loot table into "Weapons" / "Armor".
---@param text string
---@return ForeverLoot.Node
function api.Header(text)
    return { header = text }
end

-- A small section title one step under a Header, for lists long enough to need a level between
-- the headers and the group labels ("Rare Drops" under "Mounts", with its own groups inside).
-- With `items`, those entries follow it; without, it just marks where the section starts.
---@param text string
---@param items? ForeverLoot.Node[]
---@return ForeverLoot.Node
function api.Subheader(text, items)
    return { subheader = text, items = items }
end

-- One empty row of space inside a folder's children, e.g. to set an entry apart from the rest.
---@return ForeverLoot.Node
function api.Spacer()
    return { spacer = true }
end

-- A real item, resolved from the game's item database when displayed (not implemented yet).
---@param itemID integer
---@return ForeverLoot.Node
function api.Item(itemID)
    return { itemID = itemID }
end

-- A stand-in item with hard-coded display data; for prototyping before real item IDs exist.
---@param name string
---@param quality Enum.ItemQuality
---@param icon string|number
---@return ForeverLoot.Node
function api.PlaceholderItem(name, quality, icon)
    return { name = name, quality = quality, icon = icon }
end

-- Generates `count` placeholder items named "<prefix> Item N". Prototyping only.
-- They rotate through a few `category` values so auto grouping has something to group by.
---@param prefix string
---@param count integer
---@return ForeverLoot.Node[]
function api.PlaceholderItems(prefix, count)
    local qualities = { 2, 3, 3, 4, 4, 4, 5 }
    local categories = { "Weapons", "Armor", "Armor", "Trinkets", "Armor", "Weapons", "Armor" }
    local icons = {
        "Interface\\Icons\\INV_Sword_39",
        "Interface\\Icons\\INV_Chest_Plate16",
        "Interface\\Icons\\INV_Helmet_25",
        "Interface\\Icons\\INV_Boots_Plate_08",
        "Interface\\Icons\\INV_Misc_Cape_18",
        "Interface\\Icons\\INV_Jewelry_Ring_36",
        "Interface\\Icons\\INV_Staff_13",
    }
    local list = {}
    for i = 1, count do
        local quality = qualities[(i - 1) % #qualities + 1]
        local icon = icons[(i - 1) % #icons + 1]
        list[i] = api.PlaceholderItem(("%s Item %d"):format(prefix, i), quality, icon)
        list[i].category = categories[(i - 1) % #categories + 1]
    end
    return list
end

----------------------------------------------------------------------------------------------------
-- Grouping
----------------------------------------------------------------------------------------------------

-- The four groups the default grouping sorts items into, in display order: quest items and
-- everything else that isn't gear first, then armor, weapons and jewelry. Other keys
-- (spells, collections, custom categories) follow in order of appearance.
local GROUP_ORDER = { "QUEST", "ARMOR", "WEAPON", "ACCESSORY" }
local GROUP_LABELS = {
    QUEST = (AUCTION_CATEGORY_QUEST_ITEMS or "Quest Items") .. " & " .. (MISCELLANEOUS or "Misc"),
    ARMOR = AUCTION_CATEGORY_ARMOR or "Armor",
    WEAPON = AUCTION_CATEGORY_WEAPONS or "Weapons",
    ACCESSORY = "Rings, Amulets & Trinkets",
}
local groupRank = {}
for i, key in ipairs(GROUP_ORDER) do
    groupRank[key] = i
end

-- Slots that count as weapons besides weapon-class items, and the jewelry slots.
local WEAPON_SLOTS = {
    INVTYPE_SHIELD = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
    INVTYPE_RELIC = true,
    INVTYPE_AMMO = true,
}
local ACCESSORY_SLOTS = {
    INVTYPE_NECK = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
}

-- Order of slots inside a group (second sort key, after the armor / weapon type).
local SLOT_ORDER = {
    "INVTYPE_HEAD",
    "INVTYPE_SHOULDER",
    "INVTYPE_CLOAK",
    "INVTYPE_CHEST",
    "INVTYPE_ROBE",
    "INVTYPE_WRIST",
    "INVTYPE_HAND",
    "INVTYPE_WAIST",
    "INVTYPE_LEGS",
    "INVTYPE_FEET",
    "INVTYPE_BODY",
    "INVTYPE_TABARD",
    "INVTYPE_NECK",
    "INVTYPE_FINGER",
    "INVTYPE_TRINKET",
    "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPON",
    "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND",
    "INVTYPE_SHIELD",
    "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN",
    "INVTYPE_RELIC",
    "INVTYPE_AMMO",
}
local slotRank = {}
for i, slot in ipairs(SLOT_ORDER) do
    slotRank[slot] = i
end

local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4

-- Armor subclass -> first sort key inside a group: cloth, leather, mail, plate, then the rest.
local ARMOR_RANK = {
    [1] = 1, -- Cloth
    [2] = 2, -- Leather
    [3] = 3, -- Mail
    [4] = 4, -- Plate
    [0] = 5, -- Miscellaneous (rings, trinkets, off-hands, ...)
    [6] = 6, -- Shields
}

-- Items whose kind itemKind couldn't tell (server-side items the client hasn't fetched, with no
-- DB row). The view clears it before grouping a list and fetches what it collects, then groups
-- again once they have arrived.
---@type table<integer, true>
app.unknownItemKinds = {}

-- Class id, subclass id and equip location of an item, from the client when it has the item,
-- else from the DB row (server-side items the client hasn't fetched yet), else from the
-- client's item cache.
---@param itemID integer
---@return integer? classID, integer? subclassID, string? equipLoc
local function itemKind(itemID)
    -- GetItemInfoInstant needs no server round-trip, so grouping is stable on first draw.
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID then
        return classID, subclassID, equipLoc
    end
    local row = app.data and app.data:GetItem(itemID)
    if row then
        local ITEM = app.data.ITEM
        return row[ITEM.CLASS], row[ITEM.SUBCLASS], row[ITEM.SLOT]
    end
    _, _, _, _, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(itemID)
    if classID then
        return classID, subclassID, equipLoc
    end
    app.unknownItemKinds[itemID] = true
    return nil, nil, nil
end

-- Default grouping: items into four groups (quest items & misc, armor, weapons, jewelry; see
-- GROUP_ORDER), spells under "Spells", custom/placeholder entries by their `category`, folders
-- under "Collections". Returns a sort key and the label to display; nil = leave ungrouped.
---@param node ForeverLoot.Node
---@return string? key, string? label
function api.DefaultGroupKey(node)
    if node.itemID then
        local classID, _, equipLoc = itemKind(node.itemID)
        local key
        if classID == ITEM_CLASS_WEAPON or WEAPON_SLOTS[equipLoc] then
            key = "WEAPON"
        elseif ACCESSORY_SLOTS[equipLoc] then
            key = "ACCESSORY"
        elseif classID == ITEM_CLASS_ARMOR and equipLoc and equipLoc ~= "" then
            key = "ARMOR"
        else
            key = "QUEST"
        end
        return key, GROUP_LABELS[key]
    elseif node.spellID then
        return "SPELLS", SPELLS or "Spells"
    elseif api.IsFolder(node) then
        return "COLLECTIONS", "Collections"
    elseif node.category then
        return node.category, node.category
    end
    return "OTHER", OTHER or "Other"
end

-- Default order of entries inside a group: first by type (armor: cloth, leather, mail, plate;
-- weapons: by weapon type, shields and off-hands after them), then by slot (head, shoulder,
-- chest, ... / main hand, off hand, ...); everything else keeps its original order.
---@param node ForeverLoot.Node
---@return number rank  # lower first
function api.DefaultEntryRank(node)
    if node.itemID then
        local classID, subclassID, equipLoc = itemKind(node.itemID)
        local typeRank
        if classID == ITEM_CLASS_WEAPON then
            typeRank = 10 + (subclassID or 0)
        else
            typeRank = ARMOR_RANK[subclassID] or 50
        end
        return typeRank * 100 + (slotRank[equipLoc] or 99)
    end
    return 10000
end

---@class ForeverLoot.EntryGroup
---@field key string
---@field label string
---@field entries ForeverLoot.Node[]

-- Buckets `entries` by the key function (default: api.DefaultGroupKey). The default groups keep
-- their canonical order (GROUP_ORDER), other keys follow in the order in which they were first
-- seen. Inside a group,
-- entries are ordered by the rank function (default: api.DefaultEntryRank), ties keep their
-- original order.
---@param entries ForeverLoot.Node[]
---@param keyFn? fun(node: ForeverLoot.Node): string?, string?
---@param rankFn? fun(node: ForeverLoot.Node): number
---@return ForeverLoot.EntryGroup[]
function api.GroupEntries(entries, keyFn, rankFn)
    keyFn = keyFn or api.DefaultGroupKey
    rankFn = rankFn or api.DefaultEntryRank
    local groups, byKey = {}, {}
    local rankOf, indexOf = {}, {}
    for index, entry in ipairs(entries) do
        local key, label = keyFn(entry)
        key = key or "OTHER"
        local group = byKey[key]
        if not group then
            group = { key = key, label = label or key, entries = {}, seen = #groups }
            byKey[key] = group
            groups[#groups + 1] = group
        end
        group.entries[#group.entries + 1] = entry
        rankOf[entry], indexOf[entry] = rankFn(entry), index
    end
    table.sort(groups, function(a, b)
        local ra, rb = groupRank[a.key] or (1000 + a.seen), groupRank[b.key] or (1000 + b.seen)
        return ra < rb
    end)
    for _, group in ipairs(groups) do
        table.sort(group.entries, function(a, b)
            if rankOf[a] ~= rankOf[b] then
                return rankOf[a] < rankOf[b]
            end
            return indexOf[a] < indexOf[b]
        end)
    end
    return groups
end

----------------------------------------------------------------------------------------------------
-- Module registry
----------------------------------------------------------------------------------------------------

---@type table<string, ForeverLoot.ModuleDef>
local modules = {}
---@type ForeverLoot.Node?
local cachedRoot = nil

local DEFAULT_ORDER = 100

---@param def ForeverLoot.ModuleDef
---@return ForeverLoot.Node[]
local function resolveChildren(def)
    if def.children == nil and def.getChildren then
        local ok, result = pcall(def.getChildren, def)
        if ok and type(result) == "table" then
            def.children = result
        else
            log:error("Module %s: getChildren failed: %s", def.id, tostring(result))
            def.children = {}
        end
    end
    if def.children == nil then
        def.children = {}
    end
    return def.children
end

---@param def any
---@return boolean ok, string? err
local function validate(def)
    if type(def) ~= "table" then
        return false, "module definition must be a table"
    end
    if type(def.id) ~= "string" or def.id == "" then
        return false, "field `id` must be a non-empty string"
    end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "field `name` must be a non-empty string"
    end
    if type(def.icon) ~= "string" and type(def.icon) ~= "number" then
        return false, "field `icon` must be a texture path or fileID"
    end
    if def.order ~= nil and type(def.order) ~= "number" then
        return false, "field `order` must be a number"
    end
    if def.spacerBefore ~= nil and type(def.spacerBefore) ~= "boolean" then
        return false, "field `spacerBefore` must be a boolean"
    end
    if def.children ~= nil and type(def.children) ~= "table" then
        return false, "field `children` must be a table"
    end
    if def.getChildren ~= nil and type(def.getChildren) ~= "function" then
        return false, "field `getChildren` must be a function"
    end
    if def.children == nil and def.getChildren == nil then
        return false, "one of `children` or `getChildren` is required"
    end
    if def.sortChildren ~= nil and type(def.sortChildren) ~= "boolean" and type(def.sortChildren) ~= "function" then
        return false, "field `sortChildren` must be a boolean or a comparator function"
    end
    if def.query ~= nil and type(def.query) ~= "boolean" then
        return false, "field `query` must be a boolean"
    end
    if def.display ~= nil and def.display ~= "rows" and def.display ~= "tiles" and def.display ~= "cards" then
        return false, 'field `display` must be "rows", "tiles" or "cards"'
    end
    return true
end

-- Registers a module. Re-registering an existing id replaces it (handy for /reload-free dev).
---@param def ForeverLoot.ModuleDef
---@return boolean ok
function api:RegisterModule(def)
    local ok, err = validate(def)
    if not ok then
        log:error("RegisterModule: %s", err)
        return false
    end

    local replaced = modules[def.id] ~= nil
    modules[def.id] = def
    cachedRoot = nil

    log:debug("Module %s: %s", replaced and "replaced" or "registered", def.id)
    self.callbacks:Fire("OnModuleRegistered", def.id, replaced)
    self.callbacks:Fire("OnModulesChanged")
    return true
end

-- Appends an entry to an already registered module, e.g. one dungeon per file, or a third-party
-- addon adding an instance to the built-in "dungeons" module. The module's `sortChildren`
-- decides the final order; otherwise entries appear in the order they were added.
---@param id string
---@param node ForeverLoot.Node
---@return boolean ok
function api:AddToModule(id, node)
    local def = modules[id]
    if not def then
        log:error("AddToModule: no module with id %q (register it first)", tostring(id))
        return false
    end
    if type(node) ~= "table" then
        log:error("AddToModule(%s): node must be a table", id)
        return false
    end
    local children = resolveChildren(def)
    children[#children + 1] = node
    cachedRoot = nil
    self.callbacks:Fire("OnModulesChanged")
    return true
end

---@param id string
---@return boolean removed
function api:UnregisterModule(id)
    if not modules[id] then
        return false
    end
    modules[id] = nil
    cachedRoot = nil
    self.callbacks:Fire("OnModuleUnregistered", id)
    self.callbacks:Fire("OnModulesChanged")
    return true
end

---@param id string
---@return ForeverLoot.ModuleDef?
function api:GetModule(id)
    return modules[id]
end

-- Module definitions sorted by `order`, then name.
---@return ForeverLoot.ModuleDef[]
function api:GetModules()
    local list = {}
    for _, def in pairs(modules) do
        list[#list + 1] = def
    end
    table.sort(list, function(a, b)
        local oa, ob = a.order or DEFAULT_ORDER, b.order or DEFAULT_ORDER
        if oa ~= ob then
            return oa < ob
        end
        return a.name < b.name
    end)
    return list
end

---@param a ForeverLoot.Node
---@param b ForeverLoot.Node
---@return boolean
local function byOrderThenName(a, b)
    local oa, ob = a.order or DEFAULT_ORDER, b.order or DEFAULT_ORDER
    if oa ~= ob then
        return oa < ob
    end
    return (a.name or "") < (b.name or "")
end

---@param def ForeverLoot.ModuleDef
---@return ForeverLoot.Node[]
local function sortedChildren(def)
    local children = def.children or {}
    if not def.sortChildren then
        return children
    end
    local copy = {}
    for i, child in ipairs(children) do
        copy[i] = child
    end
    -- Narrow on a local: LuaLS doesn't refine `def.sortChildren` (boolean|function) via type().
    local comparator = def.sortChildren
    if type(comparator) ~= "function" then
        comparator = byOrderThenName
    end
    table.sort(copy, comparator)
    return copy
end

-- The virtual root node the main window browses: one child per registered module, with a
-- spacer above every module that asks for one. Rebuilt lazily whenever the module set changes.
---@return ForeverLoot.Node
function api:GetRootNode()
    if cachedRoot then
        return cachedRoot
    end
    local children = {}
    for i, def in ipairs(self:GetModules()) do
        if def.spacerBefore and i > 1 then
            children[#children + 1] = api.Spacer()
        end
        children[#children + 1] = {
            name = def.name,
            icon = def.icon,
            description = def.description,
            children = (resolveChildren(def) and sortedChildren(def)),
            query = def.query,
            columns = def.columns,
            display = def.display,
            groupBy = def.groupBy,
            moduleID = def.id,
        }
    end
    cachedRoot = { name = appName, icon = "Interface\\Icons\\INV_Misc_Bag_10", children = children }
    return cachedRoot
end
