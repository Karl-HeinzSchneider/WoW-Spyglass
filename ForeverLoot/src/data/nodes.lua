---@type string, ForeverLoot
local _, app = ...

local api = app.api
local Data = app.data

-- Node constructors backed by the item database, so modules (built-in or third-party) can
-- present it without touching the raw tables: instance -> bosses -> drops, and the curated
-- item lists (crafting, pvp, collections, reputation): list -> rows.

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

----------------------------------------------------------------------------------------------------
-- Curated item lists (Data.lists): crafting, pvp, collections, reputation
----------------------------------------------------------------------------------------------------

local ICON_LIST = "Interface\\Icons\\INV_Misc_Note_01"

-- Standing names as the curated files spell them, in the game's order; the labels come from
-- the client (FACTION_STANDING_LABEL1..8) so they are localized.
local STANDING_RANK = {
    Hated = 1,
    Hostile = 2,
    Unfriendly = 3,
    Neutral = 4,
    Friendly = 5,
    Honored = 6,
    Revered = 7,
    Exalted = 8,
}

---@param standing string?
---@return string? key, string? label, number rank
local function standingGroup(standing)
    local rank = standing and STANDING_RANK[standing]
    if not rank then
        return nil, nil, math.huge
    end
    local label = _G["FACTION_STANDING_LABEL" .. rank]
    return "STANDING" .. rank, type(label) == "string" and label or standing, rank
end

-- Profession tiers by the skill a recipe needs.
local SKILL_TIERS = {
    { 300, "Master" },
    { 225, "Artisan" },
    { 150, "Expert" },
    { 75, "Journeyman" },
    { 1, "Apprentice" },
}

---@param skill number?
---@return string? key, string? label, number rank
local function skillGroup(skill)
    if type(skill) ~= "number" then
        return nil, nil, math.huge
    end
    for i, tier in ipairs(SKILL_TIERS) do
        if skill >= tier[1] then
            return "SKILL" .. tier[1], ("%s (%d+)"):format(tier[2], tier[1]), #SKILL_TIERS - i
        end
    end
    return nil, nil, math.huge
end

---@param rank number?
---@return string? key, string? label, number rank
local function pvpRankGroup(rank)
    if type(rank) ~= "number" then
        return nil, nil, math.huge
    end
    return "RANK" .. rank, ("%s %d"):format(RANK or "Rank", rank), rank
end

-- The default grouping of a list's rows per kind: reputation by standing, pvp by honor rank
-- (else standing), crafting by skill tier. Returns key, label and a sort rank; nothing when
-- the row has no such field (the row then falls back to the item's own group, see
-- api.DefaultGroupKey) or the kind has no default (collections).
---@param kind ForeverLoot.ListKind
---@param row table<string, any>
---@return string? key, string? label, number rank
local function rowGroup(kind, row)
    if kind == "reputation" then
        return standingGroup(row.standing)
    elseif kind == "pvp" then
        local key, label, rank = pvpRankGroup(row.rank)
        if key then
            return key, label, rank
        end
        return standingGroup(row.standing)
    elseif kind == "crafting" then
        return skillGroup(row.skill)
    end
    return nil, nil, math.huge
end

-- The rows of one list as item nodes. Each node carries its row's named fields in `meta`
-- (`standing`, `rank`, `skill`, `spell`, `source`, `side`, `group`, ...) and is sorted so that
-- the default groups come out in their natural order (Friendly before Honored, Apprentice
-- before Artisan). Lists without rows get a single explanatory entry.
---@param kind ForeverLoot.ListKind
---@param id string
---@return ForeverLoot.Node[]
function api.ListEntries(kind, id)
    local entries, rankOf, indexOf = {}, {}, {}
    for index, row in ipairs(Data:GetListLoot(kind, id)) do
        local meta = {}
        for field, value in pairs(row) do
            if type(field) == "string" then
                meta[field] = value
            end
        end
        local node = { itemID = row[1], meta = meta }
        local _, _, rank = rowGroup(kind, meta)
        rankOf[node], indexOf[node] = rank, index
        entries[#entries + 1] = node
    end
    -- By group rank, ties in file order (table.sort isn't stable).
    table.sort(entries, function(a, b)
        if rankOf[a] ~= rankOf[b] then
            return rankOf[a] < rankOf[b]
        end
        return indexOf[a] < indexOf[b]
    end)
    if #entries == 0 then
        entries[1] = api.Custom({
            name = "Nothing recorded yet",
            icon = "Interface\\Icons\\INV_Misc_QuestionMark",
            description = ("Help out: add this list's items in the repository's .contribute/%s folder."):format(kind),
        })
    end
    return entries
end

-- Group key for a list folder: the row's own `group` label first, then the kind's default
-- (standing / rank / skill tier), then the item's kind like any other loot list.
---@param kind ForeverLoot.ListKind
---@return fun(node: ForeverLoot.Node): string?, string?
local function listGroupKey(kind)
    return function(node)
        local meta = node.meta
        if meta then
            if type(meta.group) == "string" and meta.group ~= "" then
                return "CUSTOM:" .. meta.group, meta.group
            end
            local key, label = rowGroup(kind, meta)
            if key then
                return key, label
            end
        end
        return api.DefaultGroupKey(node)
    end
end

-- A list folder: its rows in two grouped columns, carrying the list's picture and info for
-- lists that draw their entries as tiles.
---@param kind ForeverLoot.ListKind
---@param id string
---@return ForeverLoot.Node?
function api.ListFolder(kind, id)
    local list = Data:GetList(kind, id)
    if not list then
        return nil
    end
    return api.Folder(list.name, list.icon or ICON_LIST, api.ListEntries(kind, id), {
        columns = 2,
        groupBy = listGroupKey(kind),
        order = list.order,
        info = list.info,
        background = list.background,
        backgroundCoords = list.backgroundCoords,
        meta = { listKind = kind, listID = id, factionID = list.factionID, skillLineID = list.skillLineID },
    })
end

-- Folders for every list of one kind ("crafting", "pvp", "collections", "reputation"), in DB
-- order (`order`, then name).
---@param kind ForeverLoot.ListKind
---@return ForeverLoot.Node[]
function api.ListFolders(kind)
    local folders = {}
    for _, id in ipairs(Data:GetListIDs(kind)) do
        folders[#folders + 1] = api.ListFolder(kind, id)
    end
    return folders
end
