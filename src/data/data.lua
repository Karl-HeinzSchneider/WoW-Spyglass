---@type string, ForeverLoot
local _, app = ...

local log = app.logger

-- The item database: normalized, integer-keyed tables plus lazily built indexes.
-- Public as `ForeverLoot.Data`; the generated files under db/ fill it through the Add* calls,
-- and third-party addons may do the same. Contract in docs/API.md.
--
--   Data.items[itemID]      = { quality, itemLevel, reqLevel, classID, subclassID, equipLoc, bindType,
--                               icon, stats, sellPrice, stackCount, setID, expansionID, craftingReagent }
--   Data.instances[id]      = { type = "dungeon", bosses = { bossID, ... }, minLevel = 15, ... }
--   Data.bosses[bossID]     = { instanceID = 36, order = 6000 }   -- bossID = DungeonEncounter id
--   Data.bossLoot[bossID]   = { { itemID, chance }, ... }
--   Data.names[locale]      = { items = {}, bosses = {}, instances = {} }
--
-- Item rows are positional arrays (see Data.ITEM) to keep tens of thousands of rows cheap.

-- Field indices into an item row.
---@class ForeverLoot.ItemFields
local ITEM = {
    QUALITY = 1, -- Enum.ItemQuality
    ILVL = 2,
    REQ_LEVEL = 3,
    CLASS = 4, -- Enum.ItemClass (2 = weapon, 4 = armor)
    SUBCLASS = 5,
    SLOT = 6, -- equip location string, e.g. "INVTYPE_HEAD"; "" for non-equippable
    BIND = 7, -- Enum.ItemBind (0 none, 1 on pickup, 2 on equip, 3 on use, 4 quest)
    ICON = 8, -- fileDataID; the client can't look it up for items it hasn't fetched yet
    -- { INTELLECT = 4, SPELL_POWER = 18, ... }: C_Item.GetItemStats keys without the ITEM_MOD_
    -- prefix and _SHORT suffix (see Data.StatLabel), values rounded to 2 decimals; nil = none.
    STATS = 9,
    SELL_PRICE = 10, -- copper
    STACK = 11,
    SET = 12, -- item set id, 0 = none
    EXPANSION = 13,
    REAGENT = 14, -- boolean, crafting reagent
}

---@alias ForeverLoot.ItemStats table<string, number>
---@alias ForeverLoot.ItemRow { [1]: integer, [2]: integer, [3]: integer, [4]: integer, [5]: integer, [6]: string, [7]: integer, [8]: integer, [9]: ForeverLoot.ItemStats?, [10]: integer, [11]: integer, [12]: integer, [13]: integer, [14]: boolean }

---@class ForeverLoot.Instance
---@field type "raid"|"dungeon"|string
---@field bosses integer[]  # bossIDs in encounter order
---@field minLevel? integer
---@field maxLevel? integer
---@field expansionID? integer
---@field icon? string|number

---@class ForeverLoot.Boss
---@field npcID? integer  # optional; not in the generated data
---@field instanceID integer
---@field order? integer  # position inside the instance

---@alias ForeverLoot.LootRow { [1]: integer, [2]: number? }  # itemID, drop chance 0..1 (nil = unknown)

---@class ForeverLoot.ItemSource
---@field kind "boss"|string  # more kinds (vendor, quest, craft) later
---@field id integer  # bossID for kind "boss"
---@field chance? number

---@class ForeverLoot.NameTables
---@field items table<integer, string>
---@field bosses table<integer, string>
---@field instances table<integer, string>

---@class ForeverLoot.Data
---@field ITEM ForeverLoot.ItemFields
---@field items table<integer, ForeverLoot.ItemRow>
---@field instances table<integer, ForeverLoot.Instance>
---@field bosses table<integer, ForeverLoot.Boss>
---@field bossLoot table<integer, ForeverLoot.LootRow[]>
---@field names table<string, ForeverLoot.NameTables>
local Data = {
    ITEM = ITEM,
    items = {},
    instances = {},
    bosses = {},
    bossLoot = {},
    names = {},
}
app.data = Data
app.api.Data = Data

local FALLBACK_LOCALE = "enUS"

-- Bumped on every change; consumers cache against it (see Query).
local version = 0
-- Lazy caches, dropped whenever the data changes.
local itemIDs ---@type integer[]?
local instanceIDs ---@type integer[]?
local sources ---@type table<integer, ForeverLoot.ItemSource[]>?
local searchNames ---@type table<integer, string>?
local NO_SOURCES = {}

local function invalidate()
    version = version + 1
    itemIDs, instanceIDs, sources, searchNames = nil, nil, nil, nil
    app.api.callbacks:Fire("OnDataChanged")
end

---@return integer
function Data:GetVersion()
    return version
end

----------------------------------------------------------------------------------------------------
-- Adding data
----------------------------------------------------------------------------------------------------

-- Adds or replaces item rows: `{ [itemID] = { quality, ilvl, reqLevel, classID, subclassID, slot, bind, icon, stats, ... } }`
-- (positions in Data.ITEM).
---@param rows table<integer, ForeverLoot.ItemRow>
function Data:AddItems(rows)
    local items = self.items
    for id, row in pairs(rows) do
        if type(id) == "number" and type(row) == "table" then
            items[id] = row
        else
            log:error("Data.AddItems: bad row for key %s", tostring(id))
        end
    end
    invalidate()
end

---@param id integer
---@param def ForeverLoot.Instance
function Data:AddInstance(id, def)
    if type(id) ~= "number" or type(def) ~= "table" then
        log:error("Data.AddInstance: expected (number, table), got (%s, %s)", type(id), type(def))
        return
    end
    def.bosses = def.bosses or {}
    self.instances[id] = def
    invalidate()
end

-- Registers a boss. If its instance exists and doesn't list it yet, it is appended, so files
-- may either spell out `instance.bosses` or rely on registration order.
---@param id integer
---@param def ForeverLoot.Boss
function Data:AddBoss(id, def)
    if type(id) ~= "number" or type(def) ~= "table" then
        log:error("Data.AddBoss: expected (number, table), got (%s, %s)", type(id), type(def))
        return
    end
    self.bosses[id] = def
    local instance = def.instanceID and self.instances[def.instanceID]
    if instance then
        local listed = false
        for _, bossID in ipairs(instance.bosses) do
            listed = listed or bossID == id
        end
        if not listed then
            instance.bosses[#instance.bosses + 1] = id
        end
    end
    invalidate()
end

-- Appends loot rows `{ { itemID, chance }, ... }` to a boss; may be called more than once.
---@param bossID integer
---@param rows ForeverLoot.LootRow[]
function Data:AddBossLoot(bossID, rows)
    if type(bossID) ~= "number" or type(rows) ~= "table" then
        log:error("Data.AddBossLoot: expected (number, table), got (%s, %s)", type(bossID), type(rows))
        return
    end
    local loot = self.bossLoot[bossID]
    if not loot then
        loot = {}
        self.bossLoot[bossID] = loot
    end
    for _, row in ipairs(rows) do
        loot[#loot + 1] = row
    end
    invalidate()
end

-- Merges display names for one locale: kind is "items", "bosses" or "instances".
---@param locale string  # e.g. "enUS", "deDE"
---@param kind "items"|"bosses"|"instances"
---@param tbl table<integer, string>
function Data:AddNames(locale, kind, tbl)
    if kind ~= "items" and kind ~= "bosses" and kind ~= "instances" then
        log:error("Data.AddNames: unknown kind %q", tostring(kind))
        return
    end
    local names = self.names[locale]
    if not names then
        names = { items = {}, bosses = {}, instances = {} }
        self.names[locale] = names
    end
    local target = names[kind]
    for id, name in pairs(tbl) do
        target[id] = name
    end
    invalidate()
end

----------------------------------------------------------------------------------------------------
-- Names
----------------------------------------------------------------------------------------------------

---@param kind "items"|"bosses"|"instances"
---@param id integer
---@return string?
local function localizedName(kind, id)
    local names = Data.names[GetLocale()]
    local name = names and names[kind][id]
    if name == nil then
        names = Data.names[FALLBACK_LOCALE]
        name = names and names[kind][id]
    end
    return name
end

-- Client locale, then enUS, then the game's item cache, then "Item #id".
---@param itemID integer
---@return string name, boolean known  # known = false for the numeric fallback
function Data:GetItemName(itemID)
    local name = localizedName("items", itemID)
    if not name and C_Item and C_Item.GetItemInfo then
        name = C_Item.GetItemInfo(itemID)
    end
    if name then
        return name, true
    end
    return ("Item #%d"):format(itemID), false
end

---@param bossID integer
---@return string
function Data:GetBossName(bossID)
    return localizedName("bosses", bossID) or ("Boss #%d"):format(bossID)
end

---@param instanceID integer
---@return string
function Data:GetInstanceName(instanceID)
    return localizedName("instances", instanceID) or ("Instance #%d"):format(instanceID)
end

-- Lowercased item name for substring search; built lazily for the whole DB.
---@param itemID integer
---@return string
function Data:GetSearchName(itemID)
    if not searchNames then
        searchNames = {}
    end
    local name = searchNames[itemID]
    if not name then
        name = (localizedName("items", itemID) or ""):lower()
        searchNames[itemID] = name
    end
    return name
end

----------------------------------------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------------------------------------

---@param itemID integer
---@return ForeverLoot.ItemRow?
function Data:GetItem(itemID)
    return self.items[itemID]
end

---@param itemID integer
---@param field integer  # one of Data.ITEM
---@return any
function Data:GetItemField(itemID, field)
    local row = self.items[itemID]
    return row and row[field]
end

-- The item's stats, e.g. `{ INTELLECT = 4, SPELL_POWER = 18 }`; nil when it has none.
---@param itemID integer
---@return ForeverLoot.ItemStats?
function Data:GetItemStats(itemID)
    local row = self.items[itemID]
    return row and row[ITEM.STATS]
end

-- Display name of a stat key, from the game's ITEM_MOD_*_SHORT strings ("Intellect").
---@param key string  # e.g. "INTELLECT"
---@return string
function Data.StatLabel(key)
    local label = _G["ITEM_MOD_" .. key .. "_SHORT"]
    return type(label) == "string" and label or key
end

-- All item ids, ascending; cached until the data changes.
---@return integer[]
function Data:GetItemIDs()
    if not itemIDs then
        itemIDs = {}
        for id in pairs(self.items) do
            itemIDs[#itemIDs + 1] = id
        end
        table.sort(itemIDs)
    end
    return itemIDs
end

---@return integer
function Data:GetItemCount()
    return #self:GetItemIDs()
end

-- `for itemID, row in Data:EachItem() do`, ascending by id.
---@return fun(): integer?, ForeverLoot.ItemRow?
function Data:EachItem()
    local ids, items, i = self:GetItemIDs(), self.items, 0
    return function()
        i = i + 1
        local id = ids[i]
        if id then
            return id, items[id]
        end
    end
end

---@param instanceID integer
---@return ForeverLoot.Instance?
function Data:GetInstance(instanceID)
    return self.instances[instanceID]
end

-- Instance ids sorted by minLevel (unknown last), then name.
---@return integer[]
function Data:GetInstanceIDs()
    if not instanceIDs then
        instanceIDs = {}
        for id in pairs(self.instances) do
            instanceIDs[#instanceIDs + 1] = id
        end
        table.sort(instanceIDs, function(a, b)
            local la, lb = self.instances[a].minLevel or math.huge, self.instances[b].minLevel or math.huge
            if la ~= lb then
                return la < lb
            end
            return self:GetInstanceName(a) < self:GetInstanceName(b)
        end)
    end
    return instanceIDs
end

---@param bossID integer
---@return ForeverLoot.Boss?
function Data:GetBoss(bossID)
    return self.bosses[bossID]
end

---@param bossID integer
---@return ForeverLoot.LootRow[]
function Data:GetBossLoot(bossID)
    return self.bossLoot[bossID] or NO_SOURCES
end

-- Inverted index item -> sources, built on first use from every loot table.
---@param itemID integer
---@return ForeverLoot.ItemSource[]
function Data:GetItemSources(itemID)
    if not sources then
        sources = {}
        for bossID, loot in pairs(self.bossLoot) do
            for _, row in ipairs(loot) do
                local list = sources[row[1]]
                if not list then
                    list = {}
                    sources[row[1]] = list
                end
                list[#list + 1] = { kind = "boss", id = bossID, chance = row[2] }
            end
        end
    end
    return sources[itemID] or NO_SOURCES
end
