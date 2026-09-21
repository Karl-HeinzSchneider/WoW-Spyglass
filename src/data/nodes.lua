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

-- Drops worth a look on a boss card ("3 of interest"). Not decided yet what counts — a
-- favorites system (the player's marked items), maybe an automatic rule on top — so until
-- then nothing does and the text stays hidden.
---@param bossID integer
---@return integer
local function dropsOfInterest(bossID)
    return 0
end

-- "60 Beast": what the curated data knows about the boss; nil when it knows nothing.
---@param boss ForeverLoot.Boss?
---@return string?
local function bossInfo(boss)
    if not boss or (not boss.level and not boss.creatureType) then
        return nil
    end
    if boss.level and boss.creatureType then
        return ("%d %s"):format(boss.level, boss.creatureType)
    end
    return boss.creatureType or tostring(boss.level)
end

-- A boss folder: its loot in two auto-grouped columns. For lists that draw their entries as
-- cards it carries the boss's portrait, level/type, drops of interest and quests.
---@param bossID integer
---@return ForeverLoot.Node
function api.BossFolder(bossID)
    local boss = Data:GetBoss(bossID)
    local interesting = dropsOfInterest(bossID)
    return api.Folder(Data:GetBossName(bossID), ICON_BOSS, api.BossLootEntries(bossID), {
        columns = 2,
        groupBy = "auto",
        portrait = boss and boss.portrait,
        info = bossInfo(boss),
        infoRight = interesting > 0 and ("%d of interest"):format(interesting) or nil,
        quests = boss and boss.quests,
        meta = { bossID = bossID },
    })
end

-- An instance folder with one boss folder per encounter, carrying the instance's metadata
-- (`instanceID`, `minLevel`, `maxLevel`, `expansionID`) for sorting and filtering and its
-- picture for lists that draw their entries as tiles.
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
        display = "cards",
        instanceID = instanceID,
        minLevel = instance.minLevel,
        maxLevel = instance.maxLevel,
        expansionID = instance.expansionID,
        order = instance.minLevel,
        background = instance.background,
        backgroundCoords = instance.backgroundCoords,
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
