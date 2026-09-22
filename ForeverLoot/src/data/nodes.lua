---@type string, ForeverLoot
local _, app = ...

local api = app.api
local Data = app.data
local RECIPE = Data.RECIPE

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

---@param rank number
---@param fallback? string
---@return string?
local function standingLabel(rank, fallback)
    local label = _G["FACTION_STANDING_LABEL" .. rank]
    return type(label) == "string" and label or fallback
end

---@param standing string?
---@return string? key, string? label, number rank
local function standingGroup(standing)
    local rank = standing and STANDING_RANK[standing]
    if not rank then
        return nil, nil, math.huge
    end
    return "STANDING" .. rank, standingLabel(rank, standing), rank
end

-- Faction names/descriptions belong to the client: they are localized there, while reaction
-- and progress belong to the current character. Curated list fields remain the fallback for
-- clients that do not know a faction yet.
---@param list ForeverLoot.List
---@return table?
local function factionData(list)
    if type(list.factionID) ~= "number" or not C_Reputation or not C_Reputation.GetFactionDataByID then
        return nil
    end
    return C_Reputation.GetFactionDataByID(list.factionID)
end

----------------------------------------------------------------------------------------------------
-- Crafting: the recipe database merged with the curated profession list
----------------------------------------------------------------------------------------------------

-- The trade skill window's difficulty colors (orange, yellow, green, grey), as escape codes.
local DIFFICULTY_COLORS = { "|cffff8040", "|cffffff00", "|cff40bf40", "|cff808080" }

---@param index integer  # 1 = orange .. 4 = grey
---@param value any
---@return string
local function colored(index, value)
    return DIFFICULTY_COLORS[index] .. tostring(value) .. "|r"
end

-- "1 70 90 110": the skill at which the recipe is orange (learnable: the curated `skill`, else
-- what the client's tables require), then turns yellow, green and grey.
---@param recipe ForeverLoot.RecipeRow
---@param skill number?  # curated requirement
---@return string
local function thresholdText(recipe, skill)
    local orange = type(skill) == "number" and skill or recipe[RECIPE.MIN_SKILL]
    return table.concat({
        colored(1, orange),
        colored(2, recipe[RECIPE.YELLOW]),
        colored(3, recipe[RECIPE.GREEN]),
        colored(4, recipe[RECIPE.GREY]),
    }, " ")
end

-- Extra tooltip lines of a recipe node: what it makes (when more than one), reagents, tools,
-- the skill thresholds, the recipe item that teaches it and the curated source. Built when the
-- tooltip shows, so item names the client fetched in the meantime are used.
---@param node ForeverLoot.Node
---@return string[]
local function recipeTooltip(node)
    local meta = node.meta
    if not meta then
        return {}
    end
    local recipe = Data:GetRecipe(meta.spell)
    if not recipe then
        return {}
    end
    local lines = {}
    local count = recipe[RECIPE.COUNT]
    if type(count) == "table" then
        lines[#lines + 1] = ("Makes %d-%d"):format(count[1], count[2])
    elseif type(count) == "number" and count > 1 then
        lines[#lines + 1] = ("Makes %d"):format(count)
    end
    local reagents = recipe[RECIPE.REAGENTS]
    if reagents then
        local parts = {}
        for i = 1, #reagents, 2 do
            local itemID, needed = reagents[i], reagents[i + 1]
            local name = Data:GetItemName(itemID)
            parts[#parts + 1] = needed > 1 and ("%s (%d)"):format(name, needed) or name
        end
        lines[#lines + 1] = (SPELL_REAGENTS or "Reagents:") .. " " .. table.concat(parts, ", ")
    end
    local tools = recipe[RECIPE.TOOLS]
    if tools then
        local parts = {}
        for i, toolID in ipairs(tools) do
            parts[i] = Data:GetName("tools", toolID) or ("Tool #" .. toolID)
        end
        lines[#lines + 1] = (REQUIRES_LABEL or "Requires:") .. " " .. table.concat(parts, ", ")
    end
    lines[#lines + 1] = (SKILL or "Skill") .. ": " .. thresholdText(recipe, meta.skill)
    if recipe[RECIPE.AUTO] then
        lines[#lines + 1] = ("Learned automatically at skill %d"):format(recipe[RECIPE.MIN_SKILL])
    end
    local taughtBy = recipe[RECIPE.TAUGHT_BY]
    if taughtBy then
        lines[#lines + 1] = "Taught by: " .. Data:GetItemName(taughtBy)
    end
    if type(meta.source) == "string" and meta.source ~= "" then
        lines[#lines + 1] = (SOURCE or "Source") .. ": " .. meta.source
    end
    return lines
end

-- One recipe as a node: the item it makes (an item node, so the row shows its slot and type)
-- or the recipe spell itself for enchants; `meta.spell` names the recipe either way, the row's
-- top-right corner shows the skill thresholds and the tooltip lists reagents and tools.
---@param spellID integer
---@param recipe ForeverLoot.RecipeRow
---@return ForeverLoot.Node
local function recipeNode(spellID, recipe)
    local itemID = recipe[RECIPE.ITEM]
    return {
        itemID = itemID ~= 0 and itemID or nil,
        spellID = spellID,
        meta = { spell = spellID, category = recipe[RECIPE.CATEGORY] },
        infoRight = thresholdText(recipe),
        tooltip = recipeTooltip,
    }
end

-- The curated fields of a row copied onto a recipe node; the curated `skill` restates the
-- orange threshold.
---@param node ForeverLoot.Node
---@param row ForeverLoot.ListLootRow
local function applyCuratedRow(node, row)
    local meta = node.meta --[[@as table]]
    for field, value in pairs(row) do
        if type(field) == "string" then
            meta[field] = value
        end
    end
    local recipe = Data:GetRecipe(meta.spell)
    if recipe then
        node.infoRight = thresholdText(recipe, meta.skill)
    end
end

-- A list row as a plain node: the item, or the spell when the row has no item.
---@param row ForeverLoot.ListLootRow
---@return ForeverLoot.Node?
local function rowNode(row)
    local meta = {}
    for field, value in pairs(row) do
        if type(field) == "string" then
            meta[field] = value
        end
    end
    if row[1] then
        return { itemID = row[1], meta = meta }
    elseif type(meta.spell) == "number" then
        return { spellID = meta.spell, meta = meta }
    end
    return nil
end

-- Every recipe of the list's profession, then the curated rows: a row naming a recipe (by
-- `spell`, or by the item a single recipe makes) adds its fields to that recipe's node, any
-- other row becomes a plain node — recipes the client's tables don't know.
---@param list ForeverLoot.List
---@param rows ForeverLoot.ListLootRow[]
---@return ForeverLoot.Node[]
local function craftingEntries(list, rows)
    local entries, bySpell, byItem = {}, {}, {}
    if type(list.skillLineID) == "number" then
        for _, spellID in ipairs(Data:GetRecipeIDs(list.skillLineID)) do
            local recipe = Data:GetRecipe(spellID) --[[@as ForeverLoot.RecipeRow]]
            local node = recipeNode(spellID, recipe)
            entries[#entries + 1] = node
            bySpell[spellID] = node
            local itemID = recipe[RECIPE.ITEM]
            if itemID ~= 0 then
                byItem[itemID] = byItem[itemID] == nil and node or false -- false: made by several recipes
            end
        end
    end
    for _, row in ipairs(rows) do
        local node = (type(row.spell) == "number" and bySpell[row.spell]) or (row[1] and byItem[row[1]]) or nil
        if node then
            applyCuratedRow(node, row)
        else
            entries[#entries + 1] = rowNode(row)
        end
    end
    return entries
end

-- The character's rank in a profession, from the client; nil when it doesn't have it.
---@param list ForeverLoot.List
---@return table?
local function skillLineData(list)
    if type(list.skillLineID) ~= "number" or not C_SkillInfo or not C_SkillInfo.GetSkillLineInfoByID then
        return nil
    end
    return C_SkillInfo.GetSkillLineInfoByID(list.skillLineID)
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

-- Recipes by the trade skill window's category ("Plate Helmets"), in its order.
---@param categoryID any  # the row's `category` field
---@return string? key, string? label, number rank
local function categoryGroup(categoryID)
    if type(categoryID) ~= "number" then
        return nil, nil, math.huge
    end
    local category = Data:GetCategory(categoryID)
    if not category then
        return nil, nil, math.huge
    end
    local label = Data:GetName("categories", categoryID) or ("Category #" .. categoryID)
    return "CATEGORY" .. categoryID, label, category.order
end

-- The default grouping of a list's rows per kind: reputation by standing, pvp by honor rank
-- (else standing), crafting by trade skill category (else skill tier). Returns key, label and
-- a sort rank; nothing when the row has no such field (the row then falls back to the item's
-- own group, see api.DefaultGroupKey) or the kind has no default (collections).
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
        local key, label, rank = categoryGroup(row.category)
        if key then
            return key, label, rank
        end
        return skillGroup(row.skill)
    end
    return nil, nil, math.huge
end

-- The rows of one list as item nodes. Each node carries its row's named fields in `meta`
-- (`standing`, `rank`, `skill`, `spell`, `source`, `side`, `group`, ...) and is sorted so that
-- the default groups come out in their natural order (Friendly before Honored, "Weapon Stones"
-- before "Plate Helmets"). Crafting lists with a `skillLineID` start from the recipe database
-- and lay the curated rows over it (see craftingEntries). Lists without rows get a single
-- explanatory entry.
---@param kind ForeverLoot.ListKind
---@param id string
---@return ForeverLoot.Node[]
function api.ListEntries(kind, id)
    local entries, rankOf, indexOf = {}, {}, {}
    local rows = Data:GetListLoot(kind, id)
    local list = Data:GetList(kind, id)
    if kind == "crafting" and list then
        entries = craftingEntries(list, rows)
    else
        for _, row in ipairs(rows) do
            entries[#entries + 1] = rowNode(row)
        end
    end
    for index, node in ipairs(entries) do
        local _, _, rank = rowGroup(kind, node.meta or {})
        rankOf[node], indexOf[node] = rank, index
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

-- The icon an entry shows: the item's from the database (the client may not have fetched it
-- yet), else the spell's.
---@param node ForeverLoot.Node
---@return string|number?
local function entryIcon(node)
    if node.itemID then
        local row = Data:GetItem(node.itemID)
        return select(5, C_Item.GetItemInfoInstant(node.itemID)) or (row and row[Data.ITEM.ICON]) or nil
    elseif node.spellID then
        local info = C_Spell.GetSpellInfo(node.spellID)
        return info and info.iconID or nil
    end
    return node.icon
end

-- Which folder a recipe row belongs in: its curated `group` label, else its trade skill
-- category, else "Other".
---@param node ForeverLoot.Node
---@return string key, string label
local function craftingFolderKey(node)
    local meta = node.meta or {}
    if type(meta.group) == "string" and meta.group ~= "" then
        return "CUSTOM:" .. meta.group, meta.group
    end
    local key, label = categoryGroup(meta.category)
    if key then
        return key, label or key
    end
    return "OTHER", OTHER or "Other"
end

-- A profession's recipes as one folder per trade skill category ("Weapon Stones", "Plate
-- Helmets", ...), in the trade skill window's order, so a profession's hundreds of recipes
-- don't make one long list. Rows with a curated `group` label get a folder of their own where
-- their first recipe sorts; rows with neither end up under "Other" at the end. Each folder
-- shows its first recipe's icon and its recipe count.
---@param kind ForeverLoot.ListKind
---@param id string
---@param entries ForeverLoot.Node[]  # from api.ListEntries, already in category order
---@return ForeverLoot.Node[]
local function categoryFolders(kind, id, entries)
    local groups = api.GroupEntries(entries, craftingFolderKey, function()
        return 0 -- keep ListEntries' order (category, then skill)
    end)
    local folders = {}
    for _, group in ipairs(groups) do
        local first = group.entries[1]
        folders[#folders + 1] = api.Folder(group.label, entryIcon(first) or ICON_LIST, group.entries, {
            columns = 2,
            description = ("%d recipes"):format(#group.entries),
            meta = { listKind = kind, listID = id, groupKey = group.key },
        })
    end
    return folders
end

-- A list folder: its rows in two grouped columns, carrying the list's picture and info for
-- lists that draw their entries as tiles. A profession (a crafting list with recipes) instead
-- holds one folder per category, see categoryFolders.
---@param kind ForeverLoot.ListKind
---@param id string
---@return ForeverLoot.Node?
function api.ListFolder(kind, id)
    local list = Data:GetList(kind, id)
    if not list then
        return nil
    end
    local faction = kind == "reputation" and factionData(list) or nil
    local name = faction and type(faction.name) == "string" and faction.name ~= "" and faction.name or list.name
    local description = faction and type(faction.description) == "string" and faction.description ~= "" and faction.description or nil
    local standing = faction and type(faction.reaction) == "number" and standingLabel(faction.reaction) or nil
    -- Professions: the localized name from the database, the character's rank from the client.
    local skill = kind == "crafting" and skillLineData(list) or nil
    if kind == "crafting" and type(list.skillLineID) == "number" then
        name = Data:GetName("skillLines", list.skillLineID) or name
    end
    local rank = nil
    if skill and type(skill.rank) == "number" and skill.rank > 0 then
        rank = ("%d / %d"):format(skill.rank, skill.maxRank or 0)
    end
    local entries = api.ListEntries(kind, id)
    local groupBy = listGroupKey(kind) ---@type ("auto"|fun(node: ForeverLoot.Node): string?, string?)?
    if kind == "crafting" and entries[1] and (entries[1].itemID or entries[1].spellID) then
        entries, groupBy = categoryFolders(kind, id, entries), nil
    end
    return api.Folder(name, list.icon or ICON_LIST, entries, {
        columns = 2,
        groupBy = groupBy,
        order = list.order,
        info = list.info or standing or rank,
        description = description,
        background = list.background,
        backgroundCoords = list.backgroundCoords,
        meta = {
            listKind = kind,
            listID = id,
            factionID = list.factionID,
            skillLineID = list.skillLineID,
            reaction = faction and faction.reaction,
            currentStanding = faction and faction.currentStanding,
            currentReactionThreshold = faction and faction.currentReactionThreshold,
            nextReactionThreshold = faction and faction.nextReactionThreshold,
            skillRank = skill and skill.rank,
            skillMaxRank = skill and skill.maxRank,
        },
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
