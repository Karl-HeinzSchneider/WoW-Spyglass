---@type string, Spyglass
local _, app = ...

local log = app.logger

-- The item database: normalized, integer-keyed tables plus lazily built indexes.
-- Public as `Spyglass.Data`; the generated files under db/ fill it through the Add* calls,
-- and other addons may do the same. The core's own files add no item rows (`items`) or English
-- item names: those come from an addon that adds the item database. Contract in docs/API.md.
--
--   Data.items[itemID]      = { quality, itemLevel, reqLevel, classID, subclassID, equipLoc, bindType,
--                               icon, stats, sellPrice, stackCount, setID, expansionID, craftingReagent }
--   Data.instances[id]      = { type = "dungeon", bosses = { bossID, ... }, minLevel = 15, ... }
--   Data.bosses[bossID]     = { instanceID = 36, order = 6000 }   -- bossID = DungeonEncounter id
--   Data.bossLoot[bossID]   = { { itemID, chance }, ... }
--   Data.trashLoot[instID]  = { { itemID, chance }, ... }   -- what the instance's non-boss enemies drop
--   Data.quests[questID]    = { id = 26, name = "...", side = "Alliance", requiredLevel = 14, xp = 4688, objective = "...",
--                               instanceID = 36, items = { { itemID }, ... } }
--   Data.instanceQuests[id] = { questID, ... }              -- the instance's quests, in curated order
--   Data.lists[kind][id]    = { name = "Argent Dawn", icon = ..., factionID = 529 }  -- curated item lists;
--                             kind = "crafting" | "pvp" | "collections" | "reputation", id = the file's slug
--   Data.listLoot[kind][id] = { { itemID, standing = "Honored", ... }, ... }    -- the list's rows
--   Data.recipes[spellID]   = { skillLineID, itemID, count, minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy }
--                             -- profession recipes from the client's spell tables (positions in Data.RECIPE)
--   Data.categories[id]     = { skillLineID = 164, order = 30 }   -- the trade skill window's headers ("Plate Helmets")
--   Data.names[locale]      = { items = {}, bosses = {}, instances = {}, skillLines = {}, categories = {}, tools = {} }
--
-- Item and recipe rows are positional arrays (see Data.ITEM, Data.RECIPE) to keep tens of
-- thousands of rows cheap.

-- Field indices into an item row.
---@class Spyglass.ItemFields
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

-- Field indices into a recipe row (keyed by the recipe's spell id).
---@class Spyglass.RecipeFields
local RECIPE = {
    SKILL_LINE = 1, -- the profession's SkillLine id (164 = Blacksmithing)
    ITEM = 2, -- created item id; 0 when the recipe makes no item (enchants)
    COUNT = 3, -- items made per craft; { min, max } when it varies
    -- Skill needed to learn the recipe: from the recipe item that teaches it (TAUGHT_BY) when
    -- one is known, else what the client's ability tables require, which is 1 for nearly every
    -- Classic recipe (trainer requirements are server-side: the curated `skill` row field).
    MIN_SKILL = 4,
    YELLOW = 5, -- skill at which the recipe turns yellow (orange below, from when it is known)
    GREEN = 6,
    GREY = 7,
    CATEGORY = 8, -- Data.categories id, 0 = none
    REAGENTS = 9, -- { itemID, count, itemID, count, ... }; nil = none
    TOOLS = 10, -- { toolID, ... } ids into Data.names[locale].tools (Blacksmith Hammer, Anvil, ...); nil = none
    AUTO = 11, -- true when the recipe is learned automatically at MIN_SKILL
    TAUGHT_BY = 12, -- item id of the recipe item ("Plans: ...") that teaches it; nil = none known
}

---@alias Spyglass.ItemStats table<string, number>
---@alias Spyglass.ItemRow { [1]: integer, [2]: integer, [3]: integer, [4]: integer, [5]: integer, [6]: string, [7]: integer, [8]: integer, [9]: Spyglass.ItemStats?, [10]: integer, [11]: integer, [12]: integer, [13]: integer, [14]: boolean }

---@class Spyglass.Instance
---@field type "raid"|"dungeon"|string
---@field displayName? string  # shorter name the browser shows for the instance (tile, breadcrumbs), in every language
---@field bosses integer[]  # bossIDs in encounter order
---@field minLevel? integer
---@field maxLevel? integer
---@field requiredLevel? integer  # the level a character needs to enter
---@field zone? integer  # uiMapID of the zone the entrance is in
---@field expansionID? integer
---@field icon? string|number
---@field background? string|number  # wide picture for the instance's tile in the browser
---@field backgroundCoords? number[]  # { left, right, top, bottom } of `background` to show
---@field entrance? number[]  # { uiMapID, x, y } of the entrance, x and y in 0..100

---@class Spyglass.Boss
---@field npcID? integer  # optional; not in the generated data
---@field instanceID integer
---@field order? integer  # position inside the instance
---@field portrait? string|number  # picture of the boss for its card in the browser
---@field displayID? integer  # CreatureDisplayID of the boss's model; the client draws a portrait from it when there is no `portrait`
---@field level? integer
---@field creatureType? string  # "Beast", "Undead", ... as the game shows it
---@field quests? integer[]  # quest ids the boss is involved in

---@alias Spyglass.LootRow { [1]: integer, [2]: number? }  # itemID, drop chance 0..1 (nil = unknown)

-- A quest of an instance and what it rewards. This client ships no quest table, so the title is
-- curated data: `C_QuestLog` only knows quests the character has seen.
---@class Spyglass.QuestEndpoint
---@field npc? string
---@field npcID? integer
---@field item? integer
---@field location? number[]  # [uiMapID, x, y], x/y in 0..100

---@class Spyglass.QuestPrerequisite
---@field id integer
---@field name? string

---@class Spyglass.Quest
---@field id integer  # quest id
---@field name? string  # quest title, as curated
---@field side? "Alliance"|"Horde"|"Both"  # faction the quest is available to; nil = both
---@field class? string  # class token ("WARLOCK") of a class quest; nil = any class
---@field requiredLevel? integer  # the level a character needs to accept it
---@field xp? integer  # the experience it rewards
---@field objective? string  # what it asks for, in one sentence (English)
---@field description? string  # optional curated description
---@field requires? Spyglass.QuestPrerequisite[]  # direct prerequisite quests
---@field start? Spyglass.QuestEndpoint
---@field turnIn? Spyglass.QuestEndpoint
---@field instanceID? integer  # the (last) instance it was registered for, set by Data:AddQuests
---@field items Spyglass.LootRow[]  # the items it rewards

---@alias Spyglass.RecipeRow { [1]: integer, [2]: integer, [3]: integer|integer[], [4]: integer, [5]: integer, [6]: integer, [7]: integer, [8]: integer, [9]: integer[]?, [10]: integer[]?, [11]: boolean?, [12]: integer? }

---@class Spyglass.Category
---@field skillLineID integer
---@field order number  # position among the profession's categories

-- The kinds of curated item lists; one built-in module each. Other addons may add their own.
---@alias Spyglass.ListKind "crafting"|"pvp"|"collections"|"reputation"|string

-- A curated item list: a profession, a battleground or rank set, a collection, a faction.
---@class Spyglass.List
---@field name string  # display name
---@field icon? string|number
---@field background? string|number  # wide picture for the list's tile in the browser (texture or atlas name)
---@field backgroundCoords? number[]  # { left, right, top, bottom } of `background` to show
---@field info? string  # small text on the tile
---@field order? number  # position among the kind's lists; by name when equal
---@field factionID? integer  # reputation lists
---@field skillLineID? integer  # crafting lists
---@field sections? Spyglass.ListSection[]  # crafting lists: the categories grouped under subheaders
---@field panel? Spyglass.PanelWidget[]  # the right pane while the list is open; replaces the kind's default

-- One subheader of a crafting list and the trade skill categories under it, by category id,
-- by the category's displayed name or by a curated `group` label.
---@class Spyglass.ListSection
---@field name string
---@field categories (integer|string)[]

-- A row of a list: the item id, then the kind's fields by name (`standing`, `rank`, `skill`,
-- `spell`, `source`, `side`, ...) and an optional `group` label overriding the default grouping.
-- A crafting row for a recipe that makes no item (an enchant) has no item, only its `spell`.
---@alias Spyglass.ListLootRow { [1]: integer?, [string]: any }

-- Where an item comes from: a boss or an instance's trash (`chance`), a quest (`instanceID`,
-- `side`), a row of a list (`kind`, `id` and that row's named fields, e.g. `standing`) or a
-- recipe that makes it (`skillLineID`).
---@class Spyglass.ItemSource
---@field kind "boss"|"trash"|"quest"|"recipe"|Spyglass.ListKind
---@field id integer|string  # bossID for "boss", the instance id for "trash", the quest id for "quest", the recipe's spell id for "recipe", the list id otherwise
---@field chance? number
---@field skillLineID? integer
---@field [string] any

---@alias Spyglass.NameKind "items"|"bosses"|"instances"|"skillLines"|"categories"|"tools"

---@class Spyglass.NameTables
---@field items table<integer, string>
---@field bosses table<integer, string>
---@field instances table<integer, string>
---@field skillLines table<integer, string>  # professions
---@field categories table<integer, string>  # trade skill categories
---@field tools table<integer, string>  # tools recipes need

---@class Spyglass.Data
---@field ITEM Spyglass.ItemFields
---@field RECIPE Spyglass.RecipeFields
---@field items table<integer, Spyglass.ItemRow>
---@field instances table<integer, Spyglass.Instance>
---@field bosses table<integer, Spyglass.Boss>
---@field bossLoot table<integer, Spyglass.LootRow[]>
---@field trashLoot table<integer, Spyglass.LootRow[]>  # keyed by instance id
---@field quests table<integer, Spyglass.Quest>  # keyed by quest id
---@field instanceQuests table<integer, integer[]>  # instance id -> quest ids in curated order
---@field lists table<Spyglass.ListKind, table<string, Spyglass.List>>
---@field listLoot table<Spyglass.ListKind, table<string, Spyglass.ListLootRow[]>>
---@field recipes table<integer, Spyglass.RecipeRow>
---@field categories table<integer, Spyglass.Category>
---@field names table<string, Spyglass.NameTables>
local Data = {
    ITEM = ITEM,
    RECIPE = RECIPE,
    items = {},
    instances = {},
    bosses = {},
    bossLoot = {},
    trashLoot = {},
    quests = {},
    instanceQuests = {},
    lists = {},
    listLoot = {},
    recipes = {},
    categories = {},
    names = {},
}
app.data = Data
app.api.Data = Data

local FALLBACK_LOCALE = "enUS"

local NAME_KINDS = { items = true, bosses = true, instances = true, skillLines = true, categories = true, tools = true }

-- Bumped on every change; consumers cache against it (see Query).
local version = 0
-- Lazy caches, dropped whenever the data changes.
local itemIDs ---@type integer[]?
local instanceIDs ---@type integer[]?
local listIDs ---@type table<Spyglass.ListKind, string[]>?
local recipeIDs ---@type table<integer, integer[]>?
local sources ---@type table<integer, Spyglass.ItemSource[]>?
local searchNames ---@type table<integer, string>?
local setItems ---@type table<integer, integer[]>?
local setIDs ---@type integer[]?
local NO_SOURCES = {}

local function invalidate()
    version = version + 1
    itemIDs, instanceIDs, listIDs, recipeIDs, sources, searchNames = nil, nil, nil, nil, nil, nil
    setItems, setIDs = nil, nil
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
---@param rows table<integer, Spyglass.ItemRow>
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
---@param def Spyglass.Instance
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
---@param def Spyglass.Boss
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
---@param rows Spyglass.LootRow[]
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

-- Appends loot rows `{ { itemID, chance }, ... }` to an instance's trash — what its non-boss
-- enemies drop. Keyed by the instance, because trash belongs to no encounter.
---@param instanceID integer
---@param rows Spyglass.LootRow[]
function Data:AddTrashLoot(instanceID, rows)
    if type(instanceID) ~= "number" or type(rows) ~= "table" then
        log:error("Data.AddTrashLoot: expected (number, table), got (%s, %s)", type(instanceID), type(rows))
        return
    end
    local loot = self.trashLoot[instanceID]
    if not loot then
        loot = {}
        self.trashLoot[instanceID] = loot
    end
    for _, row in ipairs(rows) do
        loot[#loot + 1] = row
    end
    invalidate()
end

-- Appends quests to an instance: `{ { id = 26, name = "...", side = "Alliance", items = { { itemID }, ... } }, ... }`.
-- Each quest is stored by its id with `instanceID` filled in, and listed under the instance in
-- the order it was added; adding a quest id again replaces its definition. A quest that spans
-- several instances (a class quest through two dungeons) is listed under each that adds it.
---@param instanceID integer
---@param quests Spyglass.Quest[]
function Data:AddQuests(instanceID, quests)
    if type(instanceID) ~= "number" or type(quests) ~= "table" then
        log:error("Data.AddQuests: expected (number, table), got (%s, %s)", type(instanceID), type(quests))
        return
    end
    local ids = self.instanceQuests[instanceID]
    if not ids then
        ids = {}
        self.instanceQuests[instanceID] = ids
    end
    for _, quest in ipairs(quests) do
        if type(quest) ~= "table" or type(quest.id) ~= "number" then
            log:error("Data.AddQuests: quest without an id in instance %d", instanceID)
        else
            quest.instanceID = instanceID
            quest.items = quest.items or {}
            local listed = false
            for _, id in ipairs(ids) do
                listed = listed or id == quest.id
            end
            if not listed then
                ids[#ids + 1] = quest.id
            end
            self.quests[quest.id] = quest
        end
    end
    invalidate()
end

-- Adds or replaces a curated item list; `kind` names the module it belongs to, `id` is unique
-- within the kind (the file's slug for shipped lists; other addons should prefix theirs).
---@param kind Spyglass.ListKind
---@param id string
---@param def Spyglass.List
function Data:AddList(kind, id, def)
    if type(kind) ~= "string" or type(id) ~= "string" or type(def) ~= "table" or type(def.name) ~= "string" then
        log:error(
            "Data.AddList: expected (string, string, table with name), got (%s, %s, %s)",
            type(kind),
            type(id),
            type(def)
        )
        return
    end
    local lists = self.lists[kind]
    if not lists then
        lists = {}
        self.lists[kind] = lists
    end
    lists[id] = def
    invalidate()
end

-- Appends rows `{ { itemID, field = value, ... }, ... }` to a list; may be called more than once
-- and before the list itself is added.
---@param kind Spyglass.ListKind
---@param id string
---@param rows Spyglass.ListLootRow[]
function Data:AddListLoot(kind, id, rows)
    if type(kind) ~= "string" or type(id) ~= "string" or type(rows) ~= "table" then
        log:error(
            "Data.AddListLoot: expected (string, string, table), got (%s, %s, %s)",
            type(kind),
            type(id),
            type(rows)
        )
        return
    end
    local byID = self.listLoot[kind]
    if not byID then
        byID = {}
        self.listLoot[kind] = byID
    end
    local loot = byID[id]
    if not loot then
        loot = {}
        byID[id] = loot
    end
    for _, row in ipairs(rows) do
        loot[#loot + 1] = row
    end
    invalidate()
end

-- Adds or replaces recipe rows keyed by spell id: `{ [spellID] = { skillLineID, itemID, count,
-- minSkill, yellow, green, grey, categoryID, reagents, tools, auto, taughtBy } }` (positions in Data.RECIPE).
---@param rows table<integer, Spyglass.RecipeRow>
function Data:AddRecipes(rows)
    local recipes = self.recipes
    for id, row in pairs(rows) do
        if type(id) == "number" and type(row) == "table" then
            recipes[id] = row
        else
            log:error("Data.AddRecipes: bad row for key %s", tostring(id))
        end
    end
    invalidate()
end

-- Adds or replaces trade skill categories: `{ [id] = { skillLineID = 164, order = 30 } }`; their
-- names come through AddNames("categories").
---@param rows table<integer, Spyglass.Category>
function Data:AddCategories(rows)
    local categories = self.categories
    for id, def in pairs(rows) do
        if type(id) == "number" and type(def) == "table" then
            categories[id] = def
        else
            log:error("Data.AddCategories: bad row for key %s", tostring(id))
        end
    end
    invalidate()
end

-- Merges display names for one locale: kind is "items", "bosses", "instances", "skillLines"
-- (professions), "categories" (trade skill categories) or "tools" (what recipes need).
---@param locale string  # e.g. "enUS", "deDE"
---@param kind Spyglass.NameKind
---@param tbl table<integer, string>
function Data:AddNames(locale, kind, tbl)
    if not NAME_KINDS[kind] then
        log:error("Data.AddNames: unknown kind %q", tostring(kind))
        return
    end
    local names = self.names[locale]
    if not names then
        names = { items = {}, bosses = {}, instances = {}, skillLines = {}, categories = {}, tools = {} }
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

---@param kind Spyglass.NameKind
---@param id integer
---@return string?
local function localizedName(kind, id)
    local names = Data.names[GetLocale()]
    local name = names and names[kind] and names[kind][id]
    if name == nil then
        names = Data.names[FALLBACK_LOCALE]
        name = names and names[kind] and names[kind][id]
    end
    return name
end

-- Client locale, then enUS; nil when neither knows the id. For professions, trade skill
-- categories and tools (items, bosses and instances have their own getters with fallbacks).
---@param kind Spyglass.NameKind
---@param id integer
---@return string?
function Data:GetName(kind, id)
    return localizedName(kind, id)
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

-- Lowercased item name for substring search; built lazily for the whole DB. The name in the
-- client's language, then the English one after a newline when it differs, so either finds the
-- item and no search matches across the two.
---@param itemID integer
---@return string
function Data:GetSearchName(itemID)
    if not searchNames then
        searchNames = {}
    end
    local name = searchNames[itemID]
    if not name then
        name = localizedName("items", itemID) or ""
        local english = Data.names[FALLBACK_LOCALE]
        english = english and english.items[itemID]
        if english and english ~= name then
            name = name .. "\n" .. english
        end
        name = name:lower()
        searchNames[itemID] = name
    end
    return name
end

----------------------------------------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------------------------------------

---@param itemID integer
---@return Spyglass.ItemRow?
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
---@return Spyglass.ItemStats?
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
---@return fun(): integer?, Spyglass.ItemRow?
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
---@return Spyglass.Instance?
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
---@return Spyglass.Boss?
function Data:GetBoss(bossID)
    return self.bosses[bossID]
end

---@param bossID integer
---@return Spyglass.LootRow[]
function Data:GetBossLoot(bossID)
    return self.bossLoot[bossID] or NO_SOURCES
end

-- What the instance's non-boss enemies drop.
---@param instanceID integer
---@return Spyglass.LootRow[]
function Data:GetTrashLoot(instanceID)
    return self.trashLoot[instanceID] or NO_SOURCES
end

---@param questID integer
---@return Spyglass.Quest?
function Data:GetQuest(questID)
    return self.quests[questID]
end

-- A quest's title: the client's when it knows the quest, else the curated one, else "#id".
---@param questID integer
---@return string
function Data:GetQuestName(questID)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if type(title) == "string" and title ~= "" then
        return title
    end
    local quest = self.quests[questID]
    if quest and type(quest.name) == "string" and quest.name ~= "" then
        return quest.name
    end
    return "#" .. questID
end

-- The instance's quests, in the order they were added.
---@param instanceID integer
---@return Spyglass.Quest[]
function Data:GetInstanceQuests(instanceID)
    local quests = {}
    for _, questID in ipairs(self.instanceQuests[instanceID] or NO_SOURCES) do
        quests[#quests + 1] = self.quests[questID]
    end
    return quests
end

---@param kind Spyglass.ListKind
---@param id string
---@return Spyglass.List?
function Data:GetList(kind, id)
    local lists = self.lists[kind]
    return lists and lists[id]
end

-- Ids of one kind's lists sorted by `order` (unset last), then name.
---@param kind Spyglass.ListKind
---@return string[]
function Data:GetListIDs(kind)
    listIDs = listIDs or {}
    local ids = listIDs[kind]
    if not ids then
        ids = {}
        local lists = self.lists[kind] or {}
        for id in pairs(lists) do
            ids[#ids + 1] = id
        end
        table.sort(ids, function(a, b)
            local oa, ob = lists[a].order or math.huge, lists[b].order or math.huge
            if oa ~= ob then
                return oa < ob
            end
            return lists[a].name < lists[b].name
        end)
        listIDs[kind] = ids
    end
    return ids
end

---@param kind Spyglass.ListKind
---@param id string
---@return Spyglass.ListLootRow[]
function Data:GetListLoot(kind, id)
    local byID = self.listLoot[kind]
    return byID and byID[id] or NO_SOURCES
end

---@param spellID integer
---@return Spyglass.RecipeRow?
function Data:GetRecipe(spellID)
    return self.recipes[spellID]
end

---@param categoryID integer
---@return Spyglass.Category?
function Data:GetCategory(categoryID)
    return self.categories[categoryID]
end

-- Spell ids of one profession's recipes in the trade skill window's order: by category, then
-- by the skill to learn them and the skill they turn yellow at; cached until the data changes.
---@param skillLineID integer
---@return integer[]
function Data:GetRecipeIDs(skillLineID)
    recipeIDs = recipeIDs or {}
    local ids = recipeIDs[skillLineID]
    if not ids then
        ids = {}
        local recipes, categories = self.recipes, self.categories
        for id, row in pairs(recipes) do
            if row[RECIPE.SKILL_LINE] == skillLineID then
                ids[#ids + 1] = id
            end
        end
        ---@param row Spyglass.RecipeRow
        ---@return number
        local function categoryOrder(row)
            local category = categories[row[RECIPE.CATEGORY]]
            return category and category.order or math.huge
        end
        table.sort(ids, function(a, b)
            local ra, rb = recipes[a], recipes[b]
            local oa, ob = categoryOrder(ra), categoryOrder(rb)
            if oa ~= ob then
                return oa < ob
            end
            if ra[RECIPE.MIN_SKILL] ~= rb[RECIPE.MIN_SKILL] then
                return ra[RECIPE.MIN_SKILL] < rb[RECIPE.MIN_SKILL]
            end
            if ra[RECIPE.YELLOW] ~= rb[RECIPE.YELLOW] then
                return ra[RECIPE.YELLOW] < rb[RECIPE.YELLOW]
            end
            return a < b
        end)
        recipeIDs[skillLineID] = ids
    end
    return ids
end

-- Inverted index item -> sources, built on first use from every loot table, list and recipe.
---@param itemID integer
---@return Spyglass.ItemSource[]
function Data:GetItemSources(itemID)
    if not sources then
        sources = {}
        ---@param id integer
        ---@param source Spyglass.ItemSource
        local function add(id, source)
            local list = sources[id]
            if not list then
                list = {}
                sources[id] = list
            end
            list[#list + 1] = source
        end
        for bossID, loot in pairs(self.bossLoot) do
            for _, row in ipairs(loot) do
                add(row[1], { kind = "boss", id = bossID, chance = row[2] })
            end
        end
        for instanceID, loot in pairs(self.trashLoot) do
            for _, row in ipairs(loot) do
                add(row[1], { kind = "trash", id = instanceID, chance = row[2] })
            end
        end
        -- Per instance, so a quest listed under two instances is a source in both.
        for instanceID, questIDs in pairs(self.instanceQuests) do
            for _, questID in ipairs(questIDs) do
                local quest = self.quests[questID]
                for _, row in ipairs(quest and quest.items or NO_SOURCES) do
                    add(row[1], { kind = "quest", id = questID, instanceID = instanceID, side = quest.side })
                end
            end
        end
        for kind, byID in pairs(self.listLoot) do
            for id, loot in pairs(byID) do
                for _, row in ipairs(loot) do
                    if row[1] then
                        local source = { kind = kind, id = id }
                        for field, value in pairs(row) do
                            if type(field) == "string" then
                                source[field] = value
                            end
                        end
                        add(row[1], source)
                    end
                end
            end
        end
        for spellID, row in pairs(self.recipes) do
            if row[RECIPE.ITEM] ~= 0 then
                add(row[RECIPE.ITEM], { kind = "recipe", id = spellID, skillLineID = row[RECIPE.SKILL_LINE] })
            end
        end
    end
    return sources[itemID] or NO_SOURCES
end

-- Item sets, from the rows' SET field: set id -> its item ids (ascending), built on first use.
---@return table<integer, integer[]>
local function itemSets()
    if not setItems then
        setItems = {}
        for id, row in Data:EachItem() do
            local setID = row[ITEM.SET]
            if type(setID) == "number" and setID ~= 0 then
                local items = setItems[setID]
                if not items then
                    items = {}
                    setItems[setID] = items
                end
                items[#items + 1] = id
            end
        end
    end
    return setItems
end

-- The items of a set that are in the database, ascending by id; empty when none are.
---@param setID integer
---@return integer[]
function Data:GetSetItems(setID)
    return itemSets()[setID] or NO_SOURCES
end

-- Every set id some item in the database belongs to, ascending; cached until the data changes.
---@return integer[]
function Data:GetSetIDs()
    if not setIDs then
        setIDs = {}
        for id in pairs(itemSets()) do
            setIDs[#setIDs + 1] = id
        end
        table.sort(setIDs)
    end
    return setIDs
end

-- A set's name in the client's language ("Rotmender's Raiment"), else "Set #id".
---@param setID integer
---@return string
function Data:GetSetName(setID)
    local name = C_Item and C_Item.GetItemSetInfo and C_Item.GetItemSetInfo(setID)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return ("Set #%d"):format(setID)
end
