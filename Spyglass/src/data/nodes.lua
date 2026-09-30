---@type string, Spyglass
local _, app = ...

local api = app.api
local Data = app.data
local RECIPE = Data.RECIPE

-- Node constructors backed by the item database, so modules (built-in or third-party) can
-- present it without touching the raw tables: instance -> bosses -> drops, and the curated
-- item lists (crafting, pvp, collections, reputation): list -> rows.

local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local ICON_TRASH = "Interface\\Icons\\INV_Misc_Bag_10"
local ICON_QUEST = "Interface\\Icons\\Achievement_Quests_Completed_01"
local ICON_MISSING = "Interface\\Icons\\INV_Misc_QuestionMark"

-- The drops of one boss as item nodes carrying their drop chance. Bosses without recorded
-- loot get a single explanatory entry instead of an empty page.
---@param bossID integer
---@return Spyglass.Node[]
function api.BossLootEntries(bossID)
    local entries = {}
    for _, row in ipairs(Data:GetBossLoot(bossID)) do
        entries[#entries + 1] = { itemID = row[1], chance = row[2] }
    end
    if #entries == 0 then
        entries[1] = api.Custom({
            name = "No drops recorded yet",
            icon = ICON_MISSING,
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
---@param boss Spyglass.Boss?
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
---@return Spyglass.Node
function api.BossFolder(bossID)
    local boss = Data:GetBoss(bossID)
    local interesting = dropsOfInterest(bossID)
    return api.Folder(Data:GetBossName(bossID), ICON_BOSS, api.BossLootEntries(bossID), {
        columns = 2,
        groupBy = "auto",
        portrait = boss and boss.portrait,
        portraitDisplayID = boss and boss.displayID,
        info = bossInfo(boss),
        infoRight = interesting > 0 and ("%d of interest"):format(interesting) or nil,
        quests = boss and boss.quests,
        meta = { bossID = bossID },
    })
end

-- "1 drop" / "3 drops": how much an instance's own card has to show, nil when it has nothing.
---@param count integer
---@param singular string
---@param plural string
---@return string?
local function countText(count, singular, plural)
    if count == 0 then
        return nil
    end
    return count == 1 and ("1 " .. singular) or ("%d %s"):format(count, plural)
end

-- What the instance's non-boss enemies drop, as item nodes carrying their drop chance.
---@param instanceID integer
---@return Spyglass.Node[]
function api.TrashLootEntries(instanceID)
    local entries = {}
    for _, row in ipairs(Data:GetTrashLoot(instanceID)) do
        entries[#entries + 1] = { itemID = row[1], chance = row[2] }
    end
    if #entries == 0 then
        entries[1] = api.Custom({
            name = "No trash drops recorded yet",
            icon = ICON_MISSING,
            description = "Help out: add the instance's `trash` list in the repository's .contribute folder.",
        })
    end
    return entries
end

-- The trash folder every instance has, next to its bosses: one category for everything that
-- drops off the enemies between them.
---@param instanceID integer
---@return Spyglass.Node
function api.TrashFolder(instanceID)
    local count = #Data:GetTrashLoot(instanceID)
    return api.Folder("Trash", ICON_TRASH, api.TrashLootEntries(instanceID), {
        columns = 2,
        groupBy = "auto",
        info = countText(count, "drop", "drops"),
        description = "What the enemies between the bosses drop.",
        meta = { instanceID = instanceID, trash = true },
    })
end

-- Level and class beside the quest title; the banner draws faction emblems separately.
---@param quest Spyglass.Quest
---@return string?
local function questInfo(quest)
    local parts = {}
    if quest.requiredLevel then
        parts[#parts + 1] = ("%s %d"):format(LEVEL or "Level", quest.requiredLevel)
    end
    local class = quest.class
    if class then
        local label = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color and color.WrapTextInColorCode then
            label = color:WrapTextInColorCode(label)
        end
        parts[#parts + 1] = label
    end
    return #parts > 0 and table.concat(parts, " \194\183 ") or nil
end

-- Quests by required level (unknown last), then title, then id.
---@param a Spyglass.Quest
---@param b Spyglass.Quest
---@return boolean
local function questOrder(a, b)
    local levelA, levelB = a.requiredLevel or math.huge, b.requiredLevel or math.huge
    if levelA ~= levelB then
        return levelA < levelB
    end
    local nameA, nameB = Data:GetQuestName(a.id), Data:GetQuestName(b.id)
    if nameA ~= nameB then
        return nameA < nameB
    end
    return a.id < b.id
end

-- The right pane of a quest page: objective and the curated giver/turn-in details.
---@param panel Spyglass.PanelWidget[]
---@param title string
---@param mapButton string
---@param point Spyglass.QuestEndpoint?
local function addQuestEndpoint(panel, title, mapButton, point)
    panel[#panel + 1] = { header = title }
    if not point then
        panel[#panel + 1] = { text = "Not recorded yet." }
        return
    end
    if point.npc or point.npcID then
        local npc = point.npc or ("#" .. point.npcID)
        if point.npc and point.npcID then
            npc = npc .. " (#" .. point.npcID .. ")"
        end
        panel[#panel + 1] = { text = "NPC: " .. npc }
    end
    if point.item then
        panel[#panel + 1] = { item = point.item }
    end
    if point.location then
        local mapID, x, y = unpack(point.location)
        local map = C_Map and C_Map.GetMapInfo(mapID)
        panel[#panel + 1] = {
            text = ("%s (%.1f, %.1f)"):format(map and map.name or ("Map #" .. mapID), x, y),
        }
    end
    if point.description then
        panel[#panel + 1] = { text = point.description }
    end
    if point.location then
        panel[#panel + 1] = { button = mapButton, map = point.location }
    end
end

---@param quest Spyglass.Quest
---@param mainQuest? Spyglass.Quest
---@return Spyglass.PanelWidget[]
local function questPanel(quest, mainQuest)
    local panel = {}
    if mainQuest then
        panel[#panel + 1] = {
            button = "Back to main quest",
            onClick = function(_, view)
                view:Back()
            end,
        }
    end
    panel[#panel + 1] = { header = "Objective" }
    panel[#panel + 1] = { text = quest.objective or "No objective recorded yet." }
    addQuestEndpoint(panel, "Starts", "Show start on map", quest.start)
    addQuestEndpoint(panel, "Ends", "Show turn-in on map", quest.turnIn)
    if quest.description then
        panel[#panel + 1] = { header = "Description" }
        panel[#panel + 1] = { description = true }
    end
    return panel
end

-- Prerequisites before the quests that require them, keeping the order written in the catalog.
---@param quest Spyglass.Quest
---@return Spyglass.Quest[]
local function questPrerequisites(quest)
    local ordered, seen = {}, { [quest.id] = true }
    local function visit(current)
        for _, required in ipairs(current.requires or {}) do
            local id = type(required) == "table" and required.id or required
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                local prerequisite = Data:GetQuest(id)
                if prerequisite then
                    visit(prerequisite)
                    ordered[#ordered + 1] = prerequisite
                end
            end
        end
    end
    visit(quest)
    return ordered
end

-- A quest in the dungeon list, or a linked quest from its main page. Linked pages show their own
-- details and rewards without opening another prerequisite or follow-up list.
---@param quest Spyglass.Quest
---@param mainQuest? Spyglass.Quest
---@return Spyglass.Node
local function questPage(quest, mainQuest)
    local info = questInfo(quest)
    local items = {}
    for _, row in ipairs(quest.items) do
        items[#items + 1] = { itemID = row[1], chance = row[2] }
    end
    local entry = api.QuestEntry(quest.id, nil, info)
    entry.name = Data:GetQuestName(quest.id)
    entry.description = quest.description or quest.objective or "No description recorded yet."
    entry.columns = 2
    entry.panel = questPanel(quest, mainQuest)
    local details = api.QuestEntry(quest.id, items, info)
    if mainQuest then
        entry.children = { details }
        return entry
    end

    local prerequisites = questPrerequisites(quest)
    local followUps = {}
    for _, id in ipairs(quest.followUps or {}) do
        local followUp = Data:GetQuest(id)
        if followUp then
            followUps[#followUps + 1] = followUp
        end
    end
    if #prerequisites == 0 and #followUps == 0 then
        entry.children = { details }
        return entry
    end
    local prerequisitePages = {}
    if #prerequisites > 0 then
        entry.prerequisiteIDs = {}
    end
    for i, prerequisite in ipairs(prerequisites) do
        entry.prerequisiteIDs[i] = prerequisite.id
        local page = questPage(prerequisite, quest)
        page.indent = 28
        page.info = ("Step %d/%d%s"):format(i, #prerequisites, page.info and (" \194\183 " .. page.info) or "")
        prerequisitePages[#prerequisitePages + 1] = page
    end
    local followUpPages = {}
    for i, followUp in ipairs(followUps) do
        local page = questPage(followUp, quest)
        page.indent = 28
        page.info = ("Step %d/%d%s"):format(i, #followUps, page.info and (" \194\183 " .. page.info) or "")
        followUpPages[#followUpPages + 1] = page
    end
    entry.getChildren = function(node, view)
        local children = { details }
        local function addSection(label, pages, stateIndex)
            if #pages == 0 then
                return
            end
            local expanded = view:GetPanelValue(node, stateIndex) == true
            local toggle = api.Subheader(("%s (%d) - %s"):format(label, #pages, expanded and "Hide" or "Show"))
            toggle.onClick = function(_, button)
                if button == "RightButton" then
                    view:Back()
                else
                    view:SetPanelValue(node, stateIndex, not expanded)
                end
            end
            children[#children + 1] = toggle
            if expanded then
                for _, page in ipairs(pages) do
                    children[#children + 1] = page
                end
            end
        end
        addSection("Prerequisites", prerequisitePages, 0)
        addSection("Follow-ups", followUpPages, -1)
        return children
    end
    return entry
end

-- The dungeon's quest page: one clickable banner per quest, sorted by level. The reward items
-- appear only after opening a quest; its objective and endpoints are in that page's info pane.
---@param instanceID integer
---@return Spyglass.Node[]
function api.InstanceQuestEntries(instanceID)
    local quests = Data:GetInstanceQuests(instanceID)
    table.sort(quests, questOrder)
    local entries = {}
    for _, quest in ipairs(quests) do
        entries[#entries + 1] = questPage(quest)
    end
    if #entries == 0 then
        entries[1] = api.Custom({
            name = "No quests recorded yet",
            icon = ICON_MISSING,
            description = "Help out: add the instance's `quests` list in the repository's .contribute folder.",
        })
    end
    return entries
end

-- The quest folder every instance has, next to its bosses and its trash. Its card carries the
-- quest ids, so it shows the same "!" a boss with quests does and lists their titles.
---@param instanceID integer
---@return Spyglass.Node
function api.QuestFolder(instanceID)
    local quests = Data:GetInstanceQuests(instanceID)
    local instance = Data:GetInstance(instanceID)
    local dungeonName = instance and instance.displayName or Data:GetInstanceName(instanceID)
    local panel = {
        { row = "Dungeon", value = dungeonName },
        { description = true },
        { factionDropdown = "Faction" },
    }
    if instance and type(instance.entrance) == "table" then
        panel[#panel + 1] = { spacer = true }
        panel[#panel + 1] = { button = "Show entrance", map = instance.entrance }
    end
    local ids = {}
    for i, quest in ipairs(quests) do
        ids[i] = quest.id
    end
    return api.Folder(QUESTS_LABEL or "Quests", ICON_QUEST, api.InstanceQuestEntries(instanceID), {
        columns = 2,
        info = countText(#quests, "quest", "quests"),
        quests = #ids > 0 and ids or nil,
        description = "The quests that take place here and what they reward.",
        meta = { instanceID = instanceID, quests = true },
        panel = panel,
    })
end

-- Every item the instance's bosses drop on one card, in front of the boss cards, so the whole
-- loot table can be read at a glance. An item more than one boss drops is listed once, with the
-- first boss's chance.
---@param instanceID integer
---@param instance Spyglass.Instance
---@return Spyglass.Node
local function allBossesFolder(instanceID, instance)
    local entries, seen = {}, {}
    for _, bossID in ipairs(instance.bosses) do
        for _, row in ipairs(Data:GetBossLoot(bossID)) do
            if not seen[row[1]] then
                seen[row[1]] = true
                entries[#entries + 1] = { itemID = row[1], chance = row[2] }
            end
        end
    end
    local count = #entries
    if count == 0 then
        entries[1] = api.Custom({
            name = "No drops recorded yet",
            icon = ICON_MISSING,
            description = "Help out: add the bosses' loot in the repository's .contribute folder.",
        })
    end
    return api.Folder("All Bosses", ICON_BOSS, entries, {
        columns = 2,
        groupBy = "auto",
        info = countText(count, "drop", "drops"),
        description = "Everything the bosses here drop, on one page.",
        meta = { instanceID = instanceID, allBosses = true },
    })
end

-- The right pane of an instance: the zone its entrance is in (the client's name for the map, so
-- it is localized), its level range, the level needed to enter and its boss count, a button to
-- its entrance when the curated data has one, and its quests with the character's progress.
---@param instanceID integer
---@param instance Spyglass.Instance
---@param questFolder Spyglass.Node
---@return Spyglass.PanelWidget[]
local function instancePanel(instanceID, instance, questFolder)
    local panel = {}
    local zone = instance.zone and C_Map.GetMapInfo(instance.zone)
    if zone and zone.name and zone.name ~= "" then
        panel[#panel + 1] = { row = ZONE or "Zone", value = zone.name }
    end
    local minLevel, maxLevel = instance.minLevel, instance.maxLevel
    if minLevel then
        local range = maxLevel and maxLevel ~= minLevel and ("%d - %d"):format(minLevel, maxLevel)
            or maxLevel and tostring(minLevel)
            or ("%d+"):format(minLevel)
        panel[#panel + 1] = { row = LEVEL or "Level", value = range }
    end
    if instance.requiredLevel then
        panel[#panel + 1] = { row = "Required level", value = instance.requiredLevel }
    end
    panel[#panel + 1] = { row = "Bosses", value = #instance.bosses }
    if type(instance.entrance) == "table" then
        panel[#panel + 1] = { spacer = true }
        panel[#panel + 1] = { button = "Show entrance", map = instance.entrance }
    end
    local ids = {}
    for i, quest in ipairs(Data:GetInstanceQuests(instanceID)) do
        ids[i] = quest.id
    end
    panel[#panel + 1] = { header = QUESTS_LABEL or "Quests" }
    if #ids > 0 then
        panel[#panel + 1] = { quests = ids }
    end
    panel[#panel + 1] = {
        button = "View quests",
        onClick = function(_, view)
            view:Push(questFolder)
        end,
    }
    return panel
end

-- An instance folder with "All Bosses" and trash cards before its boss cards. Quests open from
-- the right pane. The folder carries the instance's metadata (`instanceID`, `minLevel`,
-- `maxLevel`, `expansionID`) for sorting and filtering and its picture for lists that draw
-- their entries as tiles. Named by the instance's curated `displayName` when it has one.
---@param instanceID integer
---@return Spyglass.Node?
function api.InstanceFolder(instanceID)
    local instance = Data:GetInstance(instanceID)
    if not instance then
        return nil
    end
    local entries = { allBossesFolder(instanceID, instance), api.TrashFolder(instanceID) }
    for _, bossID in ipairs(instance.bosses) do
        entries[#entries + 1] = api.BossFolder(bossID)
    end
    local questFolder = api.QuestFolder(instanceID)
    questFolder.hidden = true
    entries[#entries + 1] = questFolder
    local name = instance.displayName or Data:GetInstanceName(instanceID)
    return api.Folder(name, instance.icon or ICON_BOSS, entries, {
        display = "cards",
        instanceID = instanceID,
        minLevel = instance.minLevel,
        maxLevel = instance.maxLevel,
        expansionID = instance.expansionID,
        order = instance.minLevel,
        background = instance.background,
        backgroundCoords = instance.backgroundCoords,
        panel = instancePanel(instanceID, instance, questFolder),
    })
end

-- Instance folders of one type ("dungeon" / "raid"), in DB order (level, then name).
---@param instanceType string
---@return Spyglass.Node[]
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
---@param list Spyglass.List
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
---@param recipe Spyglass.RecipeRow
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
---@param node Spyglass.Node
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
---@param recipe Spyglass.RecipeRow
---@return Spyglass.Node
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
---@param node Spyglass.Node
---@param row Spyglass.ListLootRow
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
---@param row Spyglass.ListLootRow
---@return Spyglass.Node?
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
---@param list Spyglass.List
---@param rows Spyglass.ListLootRow[]
---@return Spyglass.Node[]
local function craftingEntries(list, rows)
    local entries, bySpell, byItem = {}, {}, {}
    if type(list.skillLineID) == "number" then
        for _, spellID in ipairs(Data:GetRecipeIDs(list.skillLineID)) do
            local recipe = Data:GetRecipe(spellID) --[[@as Spyglass.RecipeRow]]
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
---@param list Spyglass.List
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
---@param kind Spyglass.ListKind
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
---@param kind Spyglass.ListKind
---@param id string
---@return Spyglass.Node[]
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
            icon = ICON_MISSING,
            description = ("Help out: add this list's items in the repository's .contribute/%s folder."):format(kind),
        })
    end
    return entries
end

-- Group key for a list folder: the row's own `group` label first, then the kind's default
-- (standing / rank / skill tier), then the item's kind like any other loot list.
---@param kind Spyglass.ListKind
---@return fun(node: Spyglass.Node): string?, string?
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
---@param node Spyglass.Node
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
---@param node Spyglass.Node
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
---@param kind Spyglass.ListKind
---@param id string
---@param entries Spyglass.Node[]  # from api.ListEntries, already in category order
---@return Spyglass.Node[]
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

-- Puts the category folders of a profession under subheaders: each section names the
-- categories that belong under its title, by category id, by the category's displayed name or
-- by a curated `group` label, and the folders follow in the order the section lists them.
-- Categories no section claims keep their order and follow under "Other". Sections come from
-- the list's `sections` (the crafting JSON) or from the caller (see api.ListFolder); when none
-- of them matches anything, the plain folder list is left as it is.
---@param folders Spyglass.Node[]  # from categoryFolders, in the trade skill window's order
---@param sections Spyglass.ListSection[]
---@return Spyglass.Node[]
local function sectionedFolders(folders, sections)
    local byKey, byLabel = {}, {}
    for _, folder in ipairs(folders) do
        byKey[(folder.meta or {}).groupKey or folder.name] = folder
        if byLabel[folder.name] == nil then
            byLabel[folder.name] = folder
        end
    end

    local out, taken = {}, {}
    for _, section in ipairs(sections) do
        local entries = {}
        for _, entry in ipairs(type(section) == "table" and section.categories or {}) do
            local folder
            if type(entry) == "number" then
                folder = byKey["CATEGORY" .. entry]
            elseif type(entry) == "string" then
                folder = byLabel[entry] or byKey["CUSTOM:" .. entry]
            end
            if folder and not taken[folder] then
                taken[folder] = true
                entries[#entries + 1] = folder
            end
        end
        if #entries > 0 then
            out[#out + 1] = api.Subheader(section.name or "", entries)
        end
    end
    if #out == 0 then
        return folders
    end

    local rest = {}
    for _, folder in ipairs(folders) do
        if not taken[folder] then
            rest[#rest + 1] = folder
        end
    end
    if #rest > 0 then
        out[#out + 1] = api.Subheader(OTHER or "Other", rest)
    end
    return out
end

-- The sections a list's category folders are grouped by: what the caller passed for this list
-- (`false` switches the list's own off), else the list's `sections` from the curated file.
---@param list Spyglass.List
---@param id string
---@param opts Spyglass.ListFolderOptions?
---@return Spyglass.ListSection[]?
local function sectionsOf(list, id, opts)
    local given = opts and opts.sections
    if type(given) == "function" then
        given = given(id, list)
    elseif type(given) == "table" and given[id] ~= nil then
        given = given[id]
    end
    if given == false then
        return nil
    end
    if type(given) == "table" and given[1] ~= nil then
        return given --[[@as Spyglass.ListSection[] ]]
    end
    return type(list.sections) == "table" and list.sections or nil
end

-- The right pane of a list whose file brings no `panel`: a reputation shows the character's
-- standing and the faction's description, a profession the character's skill and its recipe
-- count. The other kinds get none (the pane then shows the list's name).
---@param kind Spyglass.ListKind
---@param list Spyglass.List
---@param count integer  # entries of the list
---@return Spyglass.PanelWidget[]?
local function defaultPanel(kind, list, count)
    if kind == "reputation" then
        return { { bar = "reputation" }, { description = true } }
    elseif kind == "crafting" and type(list.skillLineID) == "number" then
        return { { bar = "skill" }, { row = "Recipes", value = count } }
    end
    return nil
end

-- A list folder: its rows in two grouped columns, carrying the list's picture and info for
-- lists that draw their entries as tiles. A profession (a crafting list with recipes) instead
-- holds one folder per category, see categoryFolders, optionally under subheaders (`sections`).
---@param kind Spyglass.ListKind
---@param id string
---@param opts? Spyglass.ListFolderOptions
---@return Spyglass.Node?
function api.ListFolder(kind, id, opts)
    local list = Data:GetList(kind, id)
    if not list then
        return nil
    end
    local faction = kind == "reputation" and factionData(list) or nil
    local name = faction and type(faction.name) == "string" and faction.name ~= "" and faction.name or list.name
    local description = faction
            and type(faction.description) == "string"
            and faction.description ~= ""
            and faction.description
        or nil
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
    local panel = list.panel or defaultPanel(kind, list, #entries)
    local groupBy = listGroupKey(kind) ---@type ("auto"|fun(node: Spyglass.Node): string?, string?)?
    if kind == "crafting" and entries[1] and (entries[1].itemID or entries[1].spellID) then
        entries, groupBy = categoryFolders(kind, id, entries), nil
        local sections = sectionsOf(list, id, opts)
        if sections then
            entries = sectionedFolders(entries, sections)
        end
    end
    return api.Folder(name, list.icon or ICON_LIST, entries, {
        columns = 2,
        groupBy = groupBy,
        order = list.order,
        info = list.info or standing or rank,
        description = description,
        background = list.background,
        backgroundCoords = list.backgroundCoords,
        panel = panel,
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
-- order (`order`, then name). `opts` is passed on to every list (see api.ListFolder); its
-- `sections` may be keyed by list id or a function, so one call can regroup several lists.
---@param kind Spyglass.ListKind
---@param opts? Spyglass.ListFolderOptions
---@return Spyglass.Node[]
function api.ListFolders(kind, opts)
    local folders = {}
    for _, id in ipairs(Data:GetListIDs(kind)) do
        folders[#folders + 1] = api.ListFolder(kind, id, opts)
    end
    return folders
end
