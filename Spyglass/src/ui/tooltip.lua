---@type string, Spyglass
local _, app = ...

local addon = app.addon
local Data = app.data

-- Adds where an item comes from to every item tooltip: one block per instance, the instance's
-- name over the bosses, trash and quests that give the item, a loot sack before drops and the
-- quest giver's "!" before quests; then one line per profession whose recipes make the item.
-- First, one line per list of the user's that has the item (app.lists, those shown in tooltips).
--
--   [star] Favorite
--   [skull] Warrior BiS
--   Deadmines
--      [sack] Rhahk'Zor
--      [!] Quest: The Defias Brotherhood
--   [anvil] Crafted by Blacksmithing

local INDENT = "   "
local QUEST_LABEL = "Quest: "
local CRAFTED_LABEL = "Crafted by "
local RECIPE_BOSS_LIMIT = 4
local ICON_SIZE = 14
local UNCOLLECTED_LOOK = TRANSMOGRIFY_TOOLTIP_APPEARANCE_UNKNOWN or "You haven't collected this appearance"

-- Inline markup of an atlas, ICON_SIZE high and as wide as its aspect ratio asks.
---@param atlas string
---@return string
local function atlasIcon(atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    local width = ICON_SIZE
    if info and info.height > 0 then
        width = math.floor(ICON_SIZE * info.width / info.height + 0.5)
    end
    return CreateAtlasMarkup(atlas, width, ICON_SIZE)
end

local LOOT_ICON = atlasIcon("ParagonReputation_Bag")
local QUEST_ICON = CreateSimpleTextureMarkup("Interface\\GossipFrame\\AvailableQuestIcon", ICON_SIZE, ICON_SIZE)
-- The lines naming the user's lists that have the item and are shown in tooltips, each with
-- the list's marker (the star for Favorites, which reads "Favorite").
---@param itemID integer
---@return string[]
local function listLines(itemID)
    local Lists, out = app.lists, {}
    for _, id in ipairs(Lists:GetListsOf(itemID)) do
        local list = Lists:Get(id) --[[@as Spyglass.ItemList]]
        if list.tooltip then
            local name = id == Lists.FAVORITES and "Favorite" or list.name
            out[#out + 1] = Lists:GetMarkerMarkup(id, ICON_SIZE) .. " " .. name
        end
    end
    return out
end

-- Order of the kinds under one instance.
local BOSS, TRASH, QUEST = 1, 2, 3

---@class Spyglass.Tooltip : AceModule
local module = {}
app.tooltip = addon:NewModule("Tooltip", module) --[[@as Spyglass.Tooltip]]

---@class Spyglass.TooltipLine
---@field instanceID integer
---@field kind integer  # BOSS, TRASH or QUEST
---@field order number  # the boss's encounter order; 0 otherwise
---@field text string

-- The instance loot line of one source; nil for sources that are no instance's loot (lists,
-- recipes) or whose boss is unknown.
---@param source Spyglass.ItemSource
---@return Spyglass.TooltipLine?
local function sourceLine(source)
    if source.kind == "boss" then
        local boss = Data:GetBoss(source.id --[[@as integer]])
        if boss then
            return {
                instanceID = boss.instanceID,
                kind = BOSS,
                order = boss.order or 0,
                text = Data:GetBossName(source.id --[[@as integer]]),
            }
        end
    elseif source.kind == "trash" then
        return {
            instanceID = source.id --[[@as integer]],
            kind = TRASH,
            order = 0,
            text = "Trash",
        }
    elseif source.kind == "quest" and source.instanceID then
        return {
            instanceID = source.instanceID,
            kind = QUEST,
            order = 0,
            text = QUEST_LABEL .. Data:GetQuestName(source.id --[[@as integer]]),
        }
    end
end

---@param a Spyglass.TooltipLine
---@param b Spyglass.TooltipLine
---@return boolean
local function lineBefore(a, b)
    if a.instanceID ~= b.instanceID then
        local na, nb = Data:GetInstanceName(a.instanceID), Data:GetInstanceName(b.instanceID)
        if na ~= nb then
            return na < nb
        end
        return a.instanceID < b.instanceID
    end
    if a.kind ~= b.kind then
        return a.kind < b.kind
    end
    if a.order ~= b.order then
        return a.order < b.order
    end
    return a.text < b.text
end

-- The profession's crafting list, for its icon; nil when none is curated.
---@param skillLineID integer
---@return Spyglass.List?
local function professionList(skillLineID)
    for _, id in ipairs(Data:GetListIDs("crafting")) do
        local list = Data:GetList("crafting", id)
        if list and list.skillLineID == skillLineID then
            return list
        end
    end
end

-- "Crafted by <profession>" once per profession with a recipe that makes the item, by name.
---@param sources Spyglass.ItemSource[]
---@return string[]
local function craftedLines(sources)
    local seen, professions = {}, {}
    for _, source in ipairs(sources) do
        local skillLineID = source.kind == "recipe" and source.skillLineID
        if skillLineID and not seen[skillLineID] then
            seen[skillLineID] = true
            local list = professionList(skillLineID)
            local name = Data:GetName("skillLines", skillLineID) or (list and list.name)
            professions[#professions + 1] = {
                name = name or ("Skill #%d"):format(skillLineID),
                icon = list and list.icon,
            }
        end
    end
    table.sort(professions, function(a, b)
        return a.name < b.name
    end)
    local out = {}
    for i, profession in ipairs(professions) do
        -- Trimmed like an action button icon, so the icon's own border doesn't show.
        local icon = profession.icon
                and CreateTextureMarkup(profession.icon, 64, 64, ICON_SIZE, ICON_SIZE, 0.07, 0.93, 0.07, 0.93) .. " "
            or ""
        out[i] = icon .. CRAFTED_LABEL .. profession.name
    end
    return out
end

local BATTLEGROUND_MARK_LABELS = {
    [19322] = "Warsong Gulch",
    [20558] = "Warsong Gulch",
    [20559] = "Arathi Basin",
    [20560] = "Alterac Valley",
    [274895] = "Darkspear Island",
}
local HONOR_CURRENCY_ID = 1792

---@param cost Spyglass.ItemCost
---@return string
local function formatCost(cost)
    if cost.copper then
        return C_CurrencyInfo.GetCoinTextureString(cost.copper, ICON_SIZE)
    end
    local iconID, name = cost.icon, cost.name
    if cost.currency then
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(cost.currency)
        if info then
            iconID = info.iconFileID
            if info.name and info.name ~= "" then
                name = info.name
            end
        end
        if cost.currency == HONOR_CURRENCY_ID then
            name = HONOR or "Honor"
        end
    elseif cost.item then
        local itemName, known = Data:GetItemName(cost.item)
        name = BATTLEGROUND_MARK_LABELS[cost.item] or (known and itemName or nil)
    end
    local icon = iconID and (" " .. CreateSimpleTextureMarkup(iconID, ICON_SIZE, ICON_SIZE)) or ""
    return ("%d%s%s"):format(cost.amount, icon, name and (" " .. name) or "")
end

-- Each list row is a separate offer. Its cost components are all paid together.
---@param sources Spyglass.ItemSource[]
---@return string[]
local function costLines(sources)
    local out = {}
    for _, source in ipairs(sources) do
        if source.costs then
            local parts = {}
            for i, cost in ipairs(source.costs) do
                parts[i] = formatCost(cost)
            end
            if #parts > 0 then
                if source.upgradeFrom then
                    out[#out + 1] = "Upgrade: " .. table.concat(parts, "\n" .. INDENT .. "+ ")
                else
                    out[#out + 1] = "Cost: " .. table.concat(parts, " + ")
                end
            end
        end
    end
    table.sort(out)
    return out
end

local PVP_RANK_POINTS_FACTION_ID = 2800

---@param sources Spyglass.ItemSource[]
---@return integer?
local function requiredPvPRank(sources)
    local required
    for _, source in ipairs(sources) do
        if source.kind == "pvp" and type(source.rank) == "number" and source.rank > 0 then
            required = math.min(required or source.rank, source.rank)
        end
    end
    return required
end

---@param data? TooltipData
---@param rankText string
---@return boolean
local function hasPvPRankLine(data, rankText)
    local types = Enum and Enum.TooltipDataUsageRequirementType
    local rankType = types and types.PvPRank
    local rankLabel = "(" .. rankText .. ")"
    for _, line in ipairs(data and data.lines or {}) do
        if (rankType ~= nil and line.requirementType == rankType)
            or (line.leftText and line.leftText:find(rankLabel, 1, true))
        then
            return true
        end
    end
    return false
end

---@param tooltip GameTooltip
---@param rank integer
---@param data? TooltipData
local function addPvPRankLine(tooltip, rank, data)
    local rankText = (PVP_RANK_NUMBER or "Rank %d"):format(rank)
    if hasPvPRankLine(data, rankText) then
        return
    end

    local ranks = Enum and Enum.PvPRanks
    local title
    if ranks and ranks.Rank_1 and GetText then
        local key = "PVP_RANK_" .. (ranks.Rank_1 + rank - 1) .. "_"
        local gender = UnitSex("player")
        local allianceKey, hordeKey = key .. "1", key .. "0"
        local alliance, horde = GetText(allianceKey, gender), GetText(hordeKey, gender)
        if alliance and alliance ~= "" and alliance ~= allianceKey and horde and horde ~= "" and horde ~= hordeKey then
            title = alliance .. " / " .. horde
        end
    end
    local requirement = title and ("Requires %s (%s)"):format(title, rankText) or ("Requires PvP %s"):format(rankText)
    local progression = C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo(PVP_RANK_POINTS_FACTION_ID)
    local unmet = progression and progression.renownLevel and progression.renownLevel < rank
    local color = unmet and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR
    local r, g, b = color:GetRGB()
    tooltip:AddLine(requirement, r, g, b, true)
end

---@param tooltip GameTooltip
---@param itemID integer
local function addUncollectedLookLine(tooltip, itemID)
    if tooltip ~= GameTooltip or not app.ui.mainWindow then
        return
    end
    local owner = tooltip:GetOwner()
    while owner and owner ~= app.ui.mainWindow do
        owner = owner:GetParent()
    end
    if not owner or app.ui.GetCollectedLook(itemID) ~= false then
        return
    end

    -- Inspect the rendered lines so this also sees native text added by tooltip handlers.
    for i = 1, tooltip:NumLines() do
        local line = tooltip:GetLeftLine(i)
        if line and line:GetText() == UNCOLLECTED_LOOK then
            return
        end
    end
    local r, g, b = LIGHTBLUE_FONT_COLOR:GetRGB()
    tooltip:AddLine(UNCOLLECTED_LOOK, r, g, b, true)
end

---@param tooltip GameTooltip
---@param itemID integer?
---@param tooltipData? TooltipData
function module:AddSources(tooltip, itemID, tooltipData)
    if not itemID then
        return
    end
    addUncollectedLookLine(tooltip, itemID)
    local sources = Data:GetItemSources(itemID)
    local rank = requiredPvPRank(sources)
    if rank then
        addPvPRankLine(tooltip, rank, tooltipData)
    end
    local lines = {}
    local isRecipe = #sources > 0 and app.itemKind(itemID) == Enum.ItemClass.Recipe
    local seenBosses, bossCount = {}, 0
    local dropInstanceID, multipleInstances
    for _, source in ipairs(sources) do
        local line = sourceLine(source)
        lines[#lines + 1] = line
        if isRecipe and line and line.kind ~= QUEST then
            dropInstanceID = dropInstanceID or line.instanceID
            multipleInstances = multipleInstances or line.instanceID ~= dropInstanceID
            if line.kind == BOSS and not seenBosses[source.id] then
                seenBosses[source.id] = true
                bossCount = bossCount + 1
            end
        end
    end
    local summarizeBosses = bossCount > RECIPE_BOSS_LIMIT
    local crafted = craftedLines(sources)
    local lists = listLines(itemID)
    local costs = costLines(sources)
    if #lines == 0 and #crafted == 0 and #lists == 0 and #costs == 0 then
        return
    end
    table.sort(lines, lineBefore)

    tooltip:AddLine(" ")
    for _, text in ipairs(lists) do
        tooltip:AddLine(text, NORMAL_FONT_COLOR:GetRGB())
    end
    if multipleInstances then
        tooltip:AddLine(LOOT_ICON .. " Drops in multiple instances", HIGHLIGHT_FONT_COLOR:GetRGB())
    end
    local instanceID
    local addedBossSummary = false
    for _, line in ipairs(lines) do
        if not multipleInstances or line.kind == QUEST then
            if line.instanceID ~= instanceID then
                instanceID = line.instanceID
                tooltip:AddLine(Data:GetInstanceName(instanceID), NORMAL_FONT_COLOR:GetRGB())
            end
            if line.kind == BOSS and summarizeBosses then
                if not addedBossSummary then
                    tooltip:AddLine(INDENT .. LOOT_ICON .. " Drops from multiple bosses", HIGHLIGHT_FONT_COLOR:GetRGB())
                    addedBossSummary = true
                end
            else
                local icon = line.kind == QUEST and QUEST_ICON or LOOT_ICON
                tooltip:AddLine(INDENT .. icon .. " " .. line.text, HIGHLIGHT_FONT_COLOR:GetRGB())
            end
        end
    end
    for _, text in ipairs(crafted) do
        tooltip:AddLine(text, NORMAL_FONT_COLOR:GetRGB())
    end
    for _, cost in ipairs(costs) do
        for line in cost:gmatch("[^\n]+") do
            tooltip:AddLine(line, NORMAL_FONT_COLOR:GetRGB())
        end
    end
end

-- Hooks the item tooltips once. Tooltips built by the tooltip data handler report every item
-- they show through TooltipDataProcessor; older ones fire OnTooltipSetItem instead.
function module:OnInitialize()
    if TooltipDataProcessor and Enum.TooltipDataType and GameTooltip.ProcessInfo then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip.AddLine and data then
                self:AddSources(tooltip, data.id, data)
            end
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tooltip:HookScript("OnTooltipSetItem", function(t)
                local _, link = t:GetItem()
                self:AddSources(t, link and tonumber(link:match("item:(%d+)")), t.GetTooltipData and t:GetTooltipData())
            end)
        end
    end
end
