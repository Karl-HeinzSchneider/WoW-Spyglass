---@type string, Spyglass
local _, app = ...

local log = app.logger
local Data = app.data
local ITEM = Data.ITEM

-- Filter registry, public as `Spyglass.Filters`. A filter is a named predicate over item rows
-- with a fixed set of selectable options; the query (query.lua) combines them. Third-party
-- addons register their own the same way (e.g. "usable by my class"). Contract in docs/API.md.
--
-- Semantics: values of one filter are OR-ed, different filters AND-ed. `kind` decides the menu
-- widget and the value shape in a query:
--   "multi"  -> checkboxes, query value = array of option values
--   "single" -> radios,     query value = one option value (nil = any)

---@class Spyglass.FilterOption
---@field value string|number
---@field label string

---@class Spyglass.FilterDef
---@field id string  # unique key, e.g. "quality"; other addons should prefix theirs
---@field name string  # menu label
---@field order? number  # menu position, lower first (default 100)
---@field kind "multi"|"single"
---@field options Spyglass.FilterOption[]|fun(): Spyglass.FilterOption[]  # a function is re-evaluated when the data changes
---@field match fun(itemID: integer, row: Spyglass.ItemRow, value: string|number): boolean
---@field index? fun(itemID: integer, row: Spyglass.ItemRow): string|number|(string|number)[]|nil  # option value(s) the item belongs to; enables precomputed buckets

---@class Spyglass.Filters
local Filters = {}
app.filters = Filters
app.api.Filters = Filters

local DEFAULT_ORDER = 100

---@type table<string, Spyglass.FilterDef>
local defs = {}
---@type Spyglass.FilterDef[]?
local sorted = nil
-- filterID -> option value -> sorted itemID[], built lazily per filter
---@type table<string, table<string|number, integer[]>>
local buckets = {}
local bucketsVersion = -1
-- filterID -> options resolved from a function, cached per data version
---@type table<string, Spyglass.FilterOption[]>
local optionCache = {}
local optionsVersion = -1

local function checkVersion()
    local v = Data:GetVersion()
    if bucketsVersion ~= v then
        buckets, bucketsVersion = {}, v
    end
    if optionsVersion ~= v then
        optionCache, optionsVersion = {}, v
    end
end

---@param def any
---@return boolean ok, string? err
local function validate(def)
    if type(def) ~= "table" then
        return false, "filter definition must be a table"
    end
    if type(def.id) ~= "string" or def.id == "" then
        return false, "field `id` must be a non-empty string"
    end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "field `name` must be a non-empty string"
    end
    if def.kind ~= "multi" and def.kind ~= "single" then
        return false, 'field `kind` must be "multi" or "single"'
    end
    if type(def.options) ~= "table" and type(def.options) ~= "function" then
        return false, "field `options` must be a table or a function"
    end
    if type(def.match) ~= "function" then
        return false, "field `match` must be a function"
    end
    if def.index ~= nil and type(def.index) ~= "function" then
        return false, "field `index` must be a function"
    end
    return true
end

-- Registers a filter; re-registering an id replaces it.
---@param def Spyglass.FilterDef
---@return boolean ok
function Filters:Register(def)
    local ok, err = validate(def)
    if not ok then
        log:error("Filters.Register: %s", err)
        return false
    end
    defs[def.id] = def
    sorted = nil
    buckets[def.id] = nil
    optionCache[def.id] = nil
    app.api.callbacks:Fire("OnFiltersChanged")
    return true
end

---@param id string
---@return boolean removed
function Filters:Unregister(id)
    if not defs[id] then
        return false
    end
    defs[id] = nil
    sorted = nil
    app.api.callbacks:Fire("OnFiltersChanged")
    return true
end

---@param id string
---@return Spyglass.FilterDef?
function Filters:Get(id)
    return defs[id]
end

-- All filters sorted by `order`, then name.
---@return Spyglass.FilterDef[]
function Filters:GetAll()
    if not sorted then
        sorted = {}
        for _, def in pairs(defs) do
            sorted[#sorted + 1] = def
        end
        table.sort(sorted, function(a, b)
            local oa, ob = a.order or DEFAULT_ORDER, b.order or DEFAULT_ORDER
            if oa ~= ob then
                return oa < ob
            end
            return a.name < b.name
        end)
    end
    return sorted
end

-- The selectable options of a filter (function options are cached per data version).
---@param id string
---@return Spyglass.FilterOption[]
function Filters:GetOptions(id)
    local def = defs[id]
    if not def then
        return {}
    end
    -- Narrow on a local: LuaLS doesn't refine `def.options` (table|function) via type().
    local source = def.options
    if type(source) ~= "function" then
        return source
    end
    checkVersion()
    local options = optionCache[id]
    if not options then
        local ok, result = pcall(source)
        options = ok and result or {}
        if not ok then
            log:error("Filter %s: options() failed: %s", id, tostring(result))
        end
        optionCache[id] = options
    end
    return options
end

-- Sorted item ids the filter's `index` assigned to `value`, or nil when the filter is not
-- indexed. Buckets for a filter are built in one pass over the DB the first time.
---@param id string
---@param value string|number
---@return integer[]?
function Filters:GetBucket(id, value)
    local def = defs[id]
    if not def or not def.index then
        return nil
    end
    checkVersion()
    local byValue = buckets[id]
    if not byValue then
        byValue = {}
        buckets[id] = byValue
        local function add(key, itemID)
            local list = byValue[key]
            if not list then
                list = {}
                byValue[key] = list
            end
            list[#list + 1] = itemID
        end
        for itemID, row in Data:EachItem() do
            local keys = def.index(itemID, row)
            if type(keys) == "table" then
                for _, key in ipairs(keys) do
                    add(key, itemID)
                end
            elseif keys ~= nil then
                add(keys, itemID)
            end
        end
    end
    return byValue[value] or {}
end

----------------------------------------------------------------------------------------------------
-- Built-in filters
----------------------------------------------------------------------------------------------------

local ITEM_CLASS_WEAPON = 2
local ITEM_CLASS_ARMOR = 4

-- English fallbacks for when the client can't name a class/subclass.
local ARMOR_NAMES = { [0] = "Miscellaneous", "Cloth", "Leather", "Mail", "Plate", "Cosmetic", "Shields" }
local WEAPON_NAMES = {
    [0] = "One-Handed Axes",
    "Two-Handed Axes",
    "Bows",
    "Guns",
    "One-Handed Maces",
    "Two-Handed Maces",
    "Polearms",
    "One-Handed Swords",
    "Two-Handed Swords",
    "Warglaives",
    "Staves",
    "Bear Claws",
    "CatClaws",
    "Fist Weapons",
    "Miscellaneous",
    "Daggers",
    "Thrown",
    "Spears",
    "Crossbows",
    "Wands",
    "Fishing Poles",
}

---@param classID integer
---@param subclassID integer
---@return string
local function subclassName(classID, subclassID)
    local name = C_Item and C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(classID, subclassID)
    if name and name ~= "" then
        return name
    end
    local fallback = classID == ITEM_CLASS_ARMOR and ARMOR_NAMES or WEAPON_NAMES
    return fallback[subclassID] or tostring(subclassID)
end

-- Options for one class's subclasses, only those present in the DB, sorted by subclass id.
---@param classID integer
---@return fun(): Spyglass.FilterOption[]
local function subclassOptions(classID)
    return function()
        local seen, options = {}, {}
        for _, row in Data:EachItem() do
            local sub = row[ITEM.SUBCLASS]
            if row[ITEM.CLASS] == classID and not seen[sub] then
                seen[sub] = true
                options[#options + 1] = { value = sub, label = subclassName(classID, sub) }
            end
        end
        table.sort(options, function(a, b)
            return a.value < b.value
        end)
        return options
    end
end

-- Equipment slots in the order the grouping code uses, weapons expanded into their equipLocs.
local SLOT_VALUES = {
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
    "INVTYPE_WEAPON",
    "INVTYPE_2HWEAPON",
    "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND",
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

-- Level brackets for the item-level / required-level filters: value "40-59" = min-max.
---@param step integer
---@param max integer
---@return Spyglass.FilterOption[]
local function levelBrackets(step, max)
    local options = {}
    for lo = 1, max, step do
        local hi = lo + step - 1
        local value = ("%d-%d"):format(lo, hi)
        options[#options + 1] = { value = value, label = value }
    end
    options[#options + 1] = { value = ("%d+"):format(max + 1), label = ("%d+"):format(max + 1) }
    return options
end

-- Parses a bracket value ("40-59" or "60+") into a bounds check.
---@param level integer?
---@param value string|number
---@return boolean
local function inBracket(level, value)
    if not level then
        return false
    end
    local lo, hi = tostring(value):match("^(%d+)%-(%d+)$")
    if lo then
        return level >= tonumber(lo) and level <= tonumber(hi)
    end
    lo = tostring(value):match("^(%d+)%+$")
    return lo ~= nil and level >= tonumber(lo)
end

---@param level integer?
---@param step integer
---@param max integer
---@return string?
local function bracketOf(level, step, max)
    if not level or level < 1 then
        return nil
    end
    if level > max then
        return ("%d+"):format(max + 1)
    end
    local lo = level - ((level - 1) % step)
    return ("%d-%d"):format(lo, lo + step - 1)
end

-- Instance/boss ids an item drops in, or the professions that make it, for the indexed
-- source filters.
---@param itemID integer
---@param field "instanceID"|"bossID"|"skillLineID"
---@return integer[]
local function sourceKeys(itemID, field)
    local keys, seen = {}, {}
    for _, source in ipairs(Data:GetItemSources(itemID)) do
        local key
        if field == "skillLineID" then
            key = source.kind == "recipe" and source.skillLineID or nil
        elseif source.kind == "boss" then
            local bossID = source.id --[[@as integer]]
            key = bossID
            if field == "instanceID" then
                local boss = Data:GetBoss(bossID)
                key = boss and boss.instanceID
            end
        elseif field == "instanceID" and source.kind == "trash" then
            -- Trash belongs to the instance, not to an encounter, so it has no boss key.
            key = source.id --[[@as integer]]
        elseif field == "instanceID" and source.kind == "quest" then
            key = source.instanceID
        end
        if key and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    return keys
end

-- The item's class (Enum.ItemClass). Mounts and companion pets are Miscellaneous subclasses but
-- get options of their own; "Miscellaneous" is the rest of that class.
local ITEM_CLASS_MISC = 15
local MISC_SPLIT = { [5] = "15:5", [2] = "15:2" } -- subclass -> option value (Mount, Companion Pets)
local TYPE_VALUES = { 4, 2, 0, 1, 11, 6, 5, 7, 9, 12, 13, "15:5", "15:2", 15 } -- menu order
local CLASS_NAMES = {
    [0] = "Consumable",
    [1] = "Container",
    [2] = "Weapon",
    [4] = "Armor",
    [5] = "Reagent",
    [6] = "Projectile",
    [7] = "Trade Goods",
    [9] = "Recipe",
    [11] = "Quiver",
    [12] = "Quest",
    [13] = "Key",
    [15] = "Miscellaneous",
    ["15:5"] = "Mount",
    ["15:2"] = "Companion Pets",
}

---@param row Spyglass.ItemRow
---@return string|number
local function typeOf(row)
    local classID = row[ITEM.CLASS]
    return classID == ITEM_CLASS_MISC and MISC_SPLIT[row[ITEM.SUBCLASS]] or classID
end

---@param value string|number
---@return string
local function typeName(value)
    local name
    if type(value) == "number" then
        name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(value)
    elseif C_Item and C_Item.GetItemSubClassInfo then
        name = C_Item.GetItemSubClassInfo(ITEM_CLASS_MISC, tonumber(value:match(":(%d+)$")))
    end
    if name and name ~= "" then
        return name
    end
    return CLASS_NAMES[value] or tostring(value)
end

Filters:Register({
    id = "type",
    name = "Type",
    order = 5,
    kind = "multi",
    options = function()
        local present = {}
        for _, row in Data:EachItem() do
            present[typeOf(row)] = true
        end
        local options = {}
        for _, value in ipairs(TYPE_VALUES) do
            if present[value] then
                options[#options + 1] = { value = value, label = typeName(value) }
            end
        end
        return options
    end,
    match = function(_, row, value)
        return typeOf(row) == value
    end,
    index = function(_, row)
        return typeOf(row)
    end,
})

Filters:Register({
    id = "quality",
    name = QUALITY or "Quality",
    order = 10,
    kind = "multi",
    options = function()
        local options = {}
        for quality = 0, 6 do
            local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            local label = _G["ITEM_QUALITY" .. quality .. "_DESC"] or ("Quality %d"):format(quality)
            if color and color.hex then
                label = color.hex .. label .. "|r"
            end
            options[#options + 1] = { value = quality, label = label }
        end
        return options
    end,
    match = function(_, row, value)
        return row[ITEM.QUALITY] == value
    end,
    index = function(_, row)
        return row[ITEM.QUALITY]
    end,
})

Filters:Register({
    id = "slot",
    name = "Slot",
    order = 20,
    kind = "multi",
    options = function()
        local present = {}
        for _, row in Data:EachItem() do
            present[row[ITEM.SLOT]] = true
        end
        local options = {}
        for _, slot in ipairs(SLOT_VALUES) do
            if present[slot] then
                options[#options + 1] = { value = slot, label = _G[slot] or slot }
            end
        end
        return options
    end,
    match = function(_, row, value)
        return row[ITEM.SLOT] == value
    end,
    index = function(_, row)
        local slot = row[ITEM.SLOT]
        return slot ~= "" and slot or nil
    end,
})

Filters:Register({
    id = "armorType",
    name = "Armor Type",
    order = 30,
    kind = "multi",
    options = subclassOptions(ITEM_CLASS_ARMOR),
    match = function(_, row, value)
        return row[ITEM.CLASS] == ITEM_CLASS_ARMOR and row[ITEM.SUBCLASS] == value
    end,
    index = function(_, row)
        return row[ITEM.CLASS] == ITEM_CLASS_ARMOR and row[ITEM.SUBCLASS] or nil
    end,
})

Filters:Register({
    id = "weaponType",
    name = "Weapon Type",
    order = 40,
    kind = "multi",
    options = subclassOptions(ITEM_CLASS_WEAPON),
    match = function(_, row, value)
        return row[ITEM.CLASS] == ITEM_CLASS_WEAPON and row[ITEM.SUBCLASS] == value
    end,
    index = function(_, row)
        return row[ITEM.CLASS] == ITEM_CLASS_WEAPON and row[ITEM.SUBCLASS] or nil
    end,
})

local ILVL_STEP, ILVL_MAX = 10, 99
Filters:Register({
    id = "itemLevel",
    name = "Item Level",
    order = 50,
    kind = "single",
    options = levelBrackets(ILVL_STEP, ILVL_MAX),
    match = function(_, row, value)
        return inBracket(row[ITEM.ILVL], value)
    end,
    index = function(_, row)
        return bracketOf(row[ITEM.ILVL], ILVL_STEP, ILVL_MAX)
    end,
})

local REQ_STEP, REQ_MAX = 10, 59
Filters:Register({
    id = "reqLevel",
    name = "Required Level",
    order = 60,
    kind = "single",
    options = levelBrackets(REQ_STEP, REQ_MAX),
    match = function(_, row, value)
        return inBracket(row[ITEM.REQ_LEVEL], value)
    end,
    index = function(_, row)
        return bracketOf(row[ITEM.REQ_LEVEL], REQ_STEP, REQ_MAX)
    end,
})

Filters:Register({
    id = "instance",
    name = "Instance",
    order = 70,
    kind = "multi",
    options = function()
        local options = {}
        for _, id in ipairs(Data:GetInstanceIDs()) do
            options[#options + 1] = { value = id, label = Data:GetInstanceName(id) }
        end
        return options
    end,
    match = function(itemID, _, value)
        for _, key in ipairs(sourceKeys(itemID, "instanceID")) do
            if key == value then
                return true
            end
        end
        return false
    end,
    index = function(itemID)
        return sourceKeys(itemID, "instanceID")
    end,
})

Filters:Register({
    id = "boss",
    name = "Boss",
    order = 80,
    kind = "multi",
    options = function()
        local options = {}
        for _, instanceID in ipairs(Data:GetInstanceIDs()) do
            local instance = Data:GetInstance(instanceID)
            for _, bossID in ipairs(instance and instance.bosses or {}) do
                options[#options + 1] = {
                    value = bossID,
                    label = ("%s: %s"):format(Data:GetInstanceName(instanceID), Data:GetBossName(bossID)),
                }
            end
        end
        return options
    end,
    match = function(itemID, _, value)
        for _, key in ipairs(sourceKeys(itemID, "bossID")) do
            if key == value then
                return true
            end
        end
        return false
    end,
    index = function(itemID)
        return sourceKeys(itemID, "bossID")
    end,
})

-- Professions whose recipes make the item; the options are the professions that have lists.
Filters:Register({
    id = "profession",
    name = TRADE_SKILLS or "Profession",
    order = 90,
    kind = "multi",
    options = function()
        local options = {}
        for _, id in ipairs(Data:GetListIDs("crafting")) do
            local list = Data:GetList("crafting", id)
            if list and type(list.skillLineID) == "number" then
                local label = Data:GetName("skillLines", list.skillLineID) or list.name
                options[#options + 1] = { value = list.skillLineID, label = label }
            end
        end
        return options
    end,
    match = function(itemID, _, value)
        for _, key in ipairs(sourceKeys(itemID, "skillLineID")) do
            if key == value then
                return true
            end
        end
        return false
    end,
    index = function(itemID)
        return sourceKeys(itemID, "skillLineID")
    end,
})
