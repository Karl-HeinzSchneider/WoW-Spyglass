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
---@field tooltip? string[]  # custom entries: extra tooltip lines
---@field onClick? fun(node: ForeverLoot.Node, button: string)  # custom entries
---@field moduleID? string  # set on the root's module nodes
---@field columns? integer  # folders: columns for this list; default 1 for rows, 3 for tiles
---@field display? "rows"|"tiles"  # folders: how the entries are drawn; default "rows"
---@field groupBy? "auto"|fun(node: ForeverLoot.Node): string?, string?  # folders: auto-group ungrouped entries; see api.DefaultGroupKey
--- Tile fields, read when the parent folder has `display = "tiles"`:
---@field background? string|number  # wide picture filling the tile (texture path or fileID)
---@field backgroundCoords? number[]  # { left, right, top, bottom } part of `background` to show; whole texture by default
---@field info? string  # small text bottom-left; the level range when unset and `minLevel`/`maxLevel` are
---@field infoRight? string  # small text bottom-right
---@field order? number  # sort key when the owning module sorts its children
---@field header? string  # section header marker; see ForeverLoot.Header
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

---@class ForeverLoot.ModuleDef
---@field id string  # unique key, e.g. "raids"; other addons should prefix theirs ("myaddon-raids")
---@field name string  # display name
---@field icon string|number  # texture path or fileID
---@field order? number  # sort position in the root list; lower first, default 100
---@field description? string  # shown in tooltips
---@field children? ForeverLoot.Node[]  # the module's top-level entries (may be empty and filled via AddToModule)
---@field getChildren? fun(def: ForeverLoot.ModuleDef): ForeverLoot.Node[]  # lazy alternative to `children`, called once
---@field query? boolean  # the module node lists the item DB (see ForeverLoot.Node.query); `children` may be empty
---@field columns? integer  # layout of the module's own list, as on folder nodes
---@field display? "rows"|"tiles"
---@field groupBy? "auto"|fun(node: ForeverLoot.Node): string?, string?
---@field sortChildren? boolean|fun(a: ForeverLoot.Node, b: ForeverLoot.Node): boolean  # true = by node `order`, then name; a function gets the full nodes incl. metadata
--- Optional metadata, same meaning as on nodes:
---@field expansionID? integer
---@field seasonID? integer
---@field tags? string[]
---@field meta? table<string, any>

---@class ForeverLoot.API
---@field Data ForeverLoot.Data  # item database (src/data/data.lua)
---@field Filters ForeverLoot.Filters  # filter registry (src/data/filters.lua)
---@field Query ForeverLoot.QueryAPI  # query runner (src/data/query.lua)
---@field RegisterCallback fun(target: table, event: string, method: string|function, ...)
---@field UnregisterCallback fun(target: table, event: string)
---@field UnregisterAllCallbacks fun(target: table)
---@field callbacks CallbackHandlerRegistry
local api = {}
api.API_VERSION = 1

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
---@field columns? integer  # columns per page: 1 (default) or 2 for rows, up to 4 (default 3) for tiles
---@field display? "rows"|"tiles"  # draw the entries as rows (default) or as picture tiles
---@field description? string
---@field background? string|number  # when this folder is itself listed as a tile
---@field backgroundCoords? number[]
---@field info? string
---@field infoRight? string
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

-- Canonical order for equipment-slot groups; everything else follows in order of appearance.
local SLOT_ORDER = {
    "INVTYPE_HEAD",
    "INVTYPE_NECK",
    "INVTYPE_SHOULDER",
    "INVTYPE_CLOAK",
    "INVTYPE_CHEST",
    "INVTYPE_ROBE",
    "INVTYPE_WRIST",
    "INVTYPE_HAND",
    "INVTYPE_WAIST",
    "INVTYPE_LEGS",
    "INVTYPE_FEET",
    "INVTYPE_FINGER",
    "INVTYPE_TRINKET",
    "WEAPON",
    "INVTYPE_SHIELD",
    "INVTYPE_HOLDABLE",
    "INVTYPE_RANGED",
    "INVTYPE_RANGEDRIGHT",
    "INVTYPE_THROWN",
    "INVTYPE_RELIC",
    "INVTYPE_BODY",
    "INVTYPE_TABARD",
    "INVTYPE_BAG",
}
local slotRank = {}
for i, slot in ipairs(SLOT_ORDER) do
    slotRank[slot] = i
end

local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4

-- Armor subclass -> rank inside a slot group: heavier armor first, then everything else.
local ARMOR_RANK = {
    [4] = 1, -- Plate
    [3] = 2, -- Mail
    [2] = 3, -- Leather
    [1] = 4, -- Cloth
    [6] = 5, -- Shields
    [0] = 6, -- Miscellaneous (rings, trinkets, cloaks, ...)
}

-- Default grouping: items by equipment slot (weapons together), spells under "Spells",
-- custom/placeholder entries by their `category`, folders under "Collections".
-- Returns a sort key and the label to display; nil = leave ungrouped.
---@param node ForeverLoot.Node
---@return string? key, string? label
function api.DefaultGroupKey(node)
    if node.itemID then
        -- GetItemInfoInstant needs no server round-trip, so grouping is stable on first draw.
        local _, itemType, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(node.itemID)
        if not classID then
            -- Server-side item the client hasn't fetched yet: the DB row knows class and slot.
            local row = app.data and app.data:GetItem(node.itemID)
            if row then
                local ITEM = app.data.ITEM
                classID, equipLoc = row[ITEM.CLASS], row[ITEM.SLOT]
                itemType = C_Item.GetItemClassInfo(classID)
            end
        end
        if classID == ITEM_CLASS_WEAPON then
            return "WEAPON", itemType
        elseif equipLoc and equipLoc ~= "" then
            return equipLoc, _G[equipLoc] or equipLoc
        end
        return itemType or "OTHER", itemType or OTHER
    elseif node.spellID then
        return "SPELLS", SPELLS or "Spells"
    elseif api.IsFolder(node) then
        return "COLLECTIONS", "Collections"
    elseif node.category then
        return node.category, node.category
    end
    return "OTHER", OTHER or "Other"
end

-- Default order of entries inside a group: armor by type (plate > mail > leather > cloth),
-- weapons by weapon type, everything else keeps its original order.
---@param node ForeverLoot.Node
---@return number rank  # lower first
function api.DefaultEntryRank(node)
    if node.itemID then
        local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(node.itemID)
        if not classID then
            local row = app.data and app.data:GetItem(node.itemID)
            if row then
                classID, subclassID = row[app.data.ITEM.CLASS], row[app.data.ITEM.SUBCLASS]
            end
        end
        if classID == ITEM_CLASS_ARMOR then
            return ARMOR_RANK[subclassID] or 10
        elseif classID == ITEM_CLASS_WEAPON then
            return 20 + (subclassID or 0)
        end
        return 50
    end
    return 100
end

---@class ForeverLoot.EntryGroup
---@field key string
---@field label string
---@field entries ForeverLoot.Node[]

-- Buckets `entries` by the key function (default: api.DefaultGroupKey). Groups keep a canonical
-- equipment-slot order first, then the order in which they were first seen. Inside a group,
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
        local ra, rb = slotRank[a.key] or (1000 + a.seen), slotRank[b.key] or (1000 + b.seen)
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
    if def.display ~= nil and def.display ~= "rows" and def.display ~= "tiles" then
        return false, "field `display` must be \"rows\" or \"tiles\""
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

-- The virtual root node the main window browses: one child per registered module.
-- Rebuilt lazily whenever the module set changes.
---@return ForeverLoot.Node
function api:GetRootNode()
    if cachedRoot then
        return cachedRoot
    end
    local children = {}
    for i, def in ipairs(self:GetModules()) do
        children[i] = {
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
