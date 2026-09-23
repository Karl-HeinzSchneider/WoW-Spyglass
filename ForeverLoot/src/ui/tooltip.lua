---@type string, ForeverLoot
local _, app = ...

local addon = app.addon
local Data = app.data

-- Adds where an item comes from to every item tooltip: one block per instance, the instance's
-- name over the bosses, trash and quests that give the item, a loot sack before drops and the
-- quest giver's "!" before quests.
--
--   Deadmines
--      [sack] Rhahk'Zor
--      [!] Quest: The Defias Brotherhood

local INDENT = "   "
local QUEST_LABEL = "Quest: "
local ICON_SIZE = 14

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

-- Order of the kinds under one instance.
local BOSS, TRASH, QUEST = 1, 2, 3

---@class ForeverLoot.Tooltip : AceModule
local module = {}
app.tooltip = addon:NewModule("Tooltip", module) --[[@as ForeverLoot.Tooltip]]

---@class ForeverLoot.TooltipLine
---@field instanceID integer
---@field kind integer  # BOSS, TRASH or QUEST
---@field order number  # the boss's encounter order; 0 otherwise
---@field text string

-- The instance loot line of one source; nil for sources that are no instance's loot (lists,
-- recipes) or whose boss is unknown.
---@param source ForeverLoot.ItemSource
---@return ForeverLoot.TooltipLine?
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

---@param a ForeverLoot.TooltipLine
---@param b ForeverLoot.TooltipLine
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

---@param tooltip GameTooltip
---@param itemID integer?
function module:AddSources(tooltip, itemID)
    if not itemID then
        return
    end
    local lines = {}
    for _, source in ipairs(Data:GetItemSources(itemID)) do
        lines[#lines + 1] = sourceLine(source)
    end
    if #lines == 0 then
        return
    end
    table.sort(lines, lineBefore)

    tooltip:AddLine(" ")
    local instanceID
    for _, line in ipairs(lines) do
        if line.instanceID ~= instanceID then
            instanceID = line.instanceID
            tooltip:AddLine(Data:GetInstanceName(instanceID), NORMAL_FONT_COLOR:GetRGB())
        end
        local icon = line.kind == QUEST and QUEST_ICON or LOOT_ICON
        tooltip:AddLine(INDENT .. icon .. " " .. line.text, HIGHLIGHT_FONT_COLOR:GetRGB())
    end
end

-- Hooks the item tooltips once. Tooltips built by the tooltip data handler report every item
-- they show through TooltipDataProcessor; older ones fire OnTooltipSetItem instead.
function module:OnInitialize()
    if TooltipDataProcessor and Enum.TooltipDataType and GameTooltip.ProcessInfo then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if tooltip.AddLine and data then
                self:AddSources(tooltip, data.id)
            end
        end)
    else
        for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
            tooltip:HookScript("OnTooltipSetItem", function(t)
                local _, link = t:GetItem()
                self:AddSources(t, link and tonumber(link:match("item:(%d+)")))
            end)
        end
    end
end
