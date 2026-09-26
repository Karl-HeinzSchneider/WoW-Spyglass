-- Built-in module: Collections. One tile per collection (mounts, companions, ...), each
-- listing the items that belong to it and where they come from. The collections are curated
-- lists in .contribute/data/collections/*.json; this module holds no data of its own. After them
-- come the item sets of the database, one tile per source (dungeon, raid, PvP, crafted, ...).
local FL = ForeverLoot
local Data = FL.Data
local ITEM = Data.ITEM

local ARMOR = 4 -- Enum.ItemClass.Armor

-- The set tiles, in this order. A set goes to the source most of its items come from; ties go
-- to the earlier one, and sets none of whose items has a known source to "other".
local SET_SOURCES = {
    { key = "dungeon", name = "Dungeon Sets", icon = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster" },
    { key = "raid", name = "Raid Sets", icon = "Interface\\Icons\\Achievement_Dungeon_ClassicRaider" },
    { key = "pvp", name = "PvP Sets", icon = "Interface\\Icons\\INV_BannerPVP_02" },
    { key = "crafted", name = "Crafted Sets", icon = "Interface\\Icons\\Trade_Engineering" },
    { key = "reputation", name = "Reputation Sets", icon = "Interface\\Icons\\Achievement_Reputation_01" },
    {
        key = "other",
        name = "Other Sets",
        icon = "Interface\\Icons\\INV_Chest_Chain_05",
        description = "Sets none of whose items a dungeon, raid, list or recipe names yet.",
    },
}

-- The set tile an item source counts for: instance loot and quests by the instance's type,
-- recipes and crafting lists as crafted, PvP and reputation lists as themselves.
---@param source ForeverLoot.ItemSource
---@return string?
local function sourceKey(source)
    local instanceID
    if source.kind == "boss" then
        local boss = Data:GetBoss(source.id --[[@as integer]])
        instanceID = boss and boss.instanceID
    elseif source.kind == "trash" then
        instanceID = source.id
    elseif source.kind == "quest" then
        instanceID = source.instanceID
    elseif source.kind == "recipe" or source.kind == "crafting" then
        return "crafted"
    elseif source.kind == "pvp" or source.kind == "reputation" then
        return source.kind
    end
    local instance = instanceID and Data:GetInstance(instanceID)
    if instance and (instance.type == "dungeon" or instance.type == "raid") then
        return instance.type
    end
    return nil
end

-- Which tile a set belongs to: the source the most of its items have (each item counted once
-- per source).
---@param items integer[]
---@return string
local function setSource(items)
    local counts = {}
    for _, itemID in ipairs(items) do
        local seen = {}
        for _, source in ipairs(Data:GetItemSources(itemID)) do
            local key = sourceKey(source)
            if key and not seen[key] then
                seen[key] = true
                counts[key] = (counts[key] or 0) + 1
            end
        end
    end
    local best, bestCount = "other", 0
    for _, def in ipairs(SET_SOURCES) do
        if (counts[def.key] or 0) > bestCount then
            best, bestCount = def.key, counts[def.key]
        end
    end
    return best
end

---@param itemID integer
---@return string|number?
local function itemIcon(itemID)
    return select(5, C_Item.GetItemInfoInstant(itemID)) or Data:GetItemField(itemID, ITEM.ICON)
end

-- One set as a folder of its items, named by the set, with its chest piece's icon (else the
-- first item's) and its best item quality. `meta` carries what the tiles sort and group by.
---@param setID integer
---@param items integer[]
---@return ForeverLoot.Node
local function setFolder(setID, items)
    local entries, icon, quality, armorType, level = {}, nil, nil, nil, 0
    for _, itemID in ipairs(items) do
        entries[#entries + 1] = FL.Item(itemID)
        local row = Data:GetItem(itemID)
        if row then
            local slot = row[ITEM.SLOT]
            if slot == "INVTYPE_CHEST" or slot == "INVTYPE_ROBE" then
                icon = icon or itemIcon(itemID)
            end
            quality = math.max(quality or 0, row[ITEM.QUALITY] or 0)
            level = math.max(level, row[ITEM.REQ_LEVEL] or 0)
            if not armorType and row[ITEM.CLASS] == ARMOR and row[ITEM.SUBCLASS] >= 1 and row[ITEM.SUBCLASS] <= 4 then
                armorType = row[ITEM.SUBCLASS]
            end
        end
    end
    return FL.Folder(
        Data:GetSetName(setID),
        icon or itemIcon(items[1]) or "Interface\\Icons\\INV_Chest_Chain_05",
        entries,
        {
            columns = 2,
            groupBy = "auto",
            quality = quality,
            description = ("%d items"):format(#items),
            meta = { setID = setID, armorType = armorType, level = level },
        }
    )
end

-- Inside a tile: the sets by armor type (cloth, leather, mail, plate, then the rest), then by
-- the level they need, then by name.
---@param a ForeverLoot.Node
---@param b ForeverLoot.Node
---@return boolean
local function setOrder(a, b)
    local ta, tb = a.meta.armorType or 99, b.meta.armorType or 99
    if ta ~= tb then
        return ta < tb
    end
    if a.meta.level ~= b.meta.level then
        return a.meta.level < b.meta.level
    end
    return a.name < b.name
end

---@param node ForeverLoot.Node
---@return string key, string label
local function armorGroup(node)
    local armorType = node.meta and node.meta.armorType
    if armorType then
        return "ARMOR" .. armorType, C_Item.GetItemSubClassInfo(ARMOR, armorType) or ("Armor " .. armorType)
    end
    return "OTHER", OTHER or "Other"
end

-- The set folders of every source, rebuilt when the data has changed since the last time.
local bySource, builtVersion = {}, nil

---@return table<string, ForeverLoot.Node[]>
local function setsBySource()
    if builtVersion ~= Data:GetVersion() then
        bySource, builtVersion = {}, Data:GetVersion()
        for _, setID in ipairs(Data:GetSetIDs()) do
            local items = Data:GetSetItems(setID)
            local key = setSource(items)
            bySource[key] = bySource[key] or {}
            table.insert(bySource[key], setFolder(setID, items))
        end
        for _, sets in pairs(bySource) do
            table.sort(sets, setOrder)
        end
    end
    return bySource
end

-- One tile per source. The module's entries are built while the core loads, before an addon
-- has added the item rows, so each tile finds its sets only when it is opened.
---@return ForeverLoot.Node[]
local function setTiles()
    local tiles = {}
    for _, def in ipairs(SET_SOURCES) do
        tiles[#tiles + 1] = {
            name = def.name,
            icon = def.icon,
            description = def.description,
            columns = 2,
            groupBy = armorGroup,
            getChildren = function()
                return setsBySource()[def.key]
                    or {
                        FL.Custom({
                            name = "No sets known yet",
                            icon = def.icon,
                            description = "None of the database's item sets comes from here so far.",
                        }),
                    }
            end,
        }
    end
    return tiles
end

FL:RegisterModule({
    id = "collections",
    name = "Collections",
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    order = 60,
    description = "Mounts, companions, item sets and other collectibles.",
    display = "tiles",
    getChildren = function()
        local children = FL.ListFolders("collections")
        for _, tile in ipairs(setTiles()) do
            children[#children + 1] = tile
        end
        return children
    end,
})
