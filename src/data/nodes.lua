---@type string, ForeverLoot
local _, app = ...

local api = app.api
local Data = app.data

-- Node constructors backed by the item database, so modules (built-in or third-party) can
-- present instances without touching the raw tables: instance -> bosses -> drops.

local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"

-- The drops of one boss as item nodes carrying their drop chance. Bosses without recorded
-- loot get a single explanatory entry instead of an empty page.
---@param bossID integer
---@return ForeverLoot.Node[]
function api.BossLootEntries(bossID)
    local entries = {}
    for _, row in ipairs(Data:GetBossLoot(bossID)) do
        entries[#entries + 1] = { itemID = row[1], chance = row[2] }
    end
    if #entries == 0 then
        entries[1] = api.Custom({
            name = "No drops recorded yet",
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            description = "Help out: add this boss's loot in the repository's .contribute folder.",
        })
    end
    return entries
end

-- A boss folder: its loot in two auto-grouped columns.
---@param bossID integer
---@return ForeverLoot.Node
function api.BossFolder(bossID)
    return api.Folder(Data:GetBossName(bossID), ICON_BOSS, api.BossLootEntries(bossID), {
        columns = 2,
        groupBy = "auto",
        meta = { bossID = bossID },
    })
end

-- An instance folder with one boss folder per encounter, carrying the instance's metadata
-- (`instanceID`, `minLevel`, `maxLevel`, `expansionID`) for sorting and filtering.
---@param instanceID integer
---@return ForeverLoot.Node?
function api.InstanceFolder(instanceID)
    local instance = Data:GetInstance(instanceID)
    if not instance then
        return nil
    end
    local bosses = {}
    for i, bossID in ipairs(instance.bosses) do
        bosses[i] = api.BossFolder(bossID)
    end
    return api.Folder(Data:GetInstanceName(instanceID), instance.icon or ICON_BOSS, bosses, {
        instanceID = instanceID,
        minLevel = instance.minLevel,
        maxLevel = instance.maxLevel,
        expansionID = instance.expansionID,
        order = instance.minLevel,
    })
end

-- Instance folders of one type ("dungeon" / "raid"), in DB order (level, then name).
---@param instanceType string
---@return ForeverLoot.Node[]
function api.InstanceFolders(instanceType)
    local folders = {}
    for _, instanceID in ipairs(Data:GetInstanceIDs()) do
        local instance = Data:GetInstance(instanceID)
        if instance and instance.type == instanceType then
            folders[#folders + 1] = api.InstanceFolder(instanceID)
        end
    end
    return folders
end
