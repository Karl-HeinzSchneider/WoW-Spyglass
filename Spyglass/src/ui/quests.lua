---@type string, Spyglass
local _, app = ...

----------------------------------------------------------------------------------------------------
-- Quests: what the info pane's quest lines and the lists' quest banners share — the character's
-- progress, the chat link, the tooltip and the click
----------------------------------------------------------------------------------------------------

---@class Spyglass.QuestInfo
local Quests = {}
app.questInfo = Quests

-- The gossip window's quest marks and the ready check's tick, by progress.
local ICON_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_INCOMPLETE = "Interface\\GossipFrame\\IncompleteQuestIcon"
local ICON_READY = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"

-- The character's progress on a quest, as text, color and icon: turned in, objectives complete,
-- in the quest log, or not taken yet.
---@param questID integer
---@return string text, ColorMixin color, string icon
function Quests.Status(questID)
    local questLog = C_QuestLog
    if questLog.IsQuestFlaggedCompleted(questID) then
        return "Done", GREEN_FONT_COLOR, ICON_DONE
    end
    if questLog.IsOnQuest(questID) then
        if questLog.ReadyForTurnIn(questID) or questLog.IsComplete(questID) then
            return "Ready", YELLOW_FONT_COLOR, ICON_READY
        end
        return "Active", HIGHLIGHT_FONT_COLOR, ICON_INCOMPLETE
    end
    if not Quests.IsForCharacter(questID) then
        return "Unavailable", GRAY_FONT_COLOR, ICON_AVAILABLE
    end
    local quest = app.data:GetQuest(questID)
    if quest and quest.requiredLevel and UnitLevel("player") < quest.requiredLevel then
        return ("Level %d"):format(quest.requiredLevel), GRAY_FONT_COLOR, ICON_AVAILABLE
    end
    local hasRequirements = quest and (#(quest.requires or {}) > 0 or #(quest.requiresAny or {}) > 0)
    if hasRequirements then
        for _, required in ipairs(quest.requires or {}) do
            if not questLog.IsQuestFlaggedCompleted(required) then
                return "Locked", GRAY_FONT_COLOR, ICON_AVAILABLE
            end
        end
        local alternatives = quest.requiresAny or {}
        if #alternatives > 0 then
            local complete = false
            for _, required in ipairs(alternatives) do
                complete = complete or questLog.IsQuestFlaggedCompleted(required)
            end
            if not complete then
                return "Locked", GRAY_FONT_COLOR, ICON_AVAILABLE
            end
        end
        return "Eligible", HIGHLIGHT_FONT_COLOR, ICON_AVAILABLE
    end
    return "Not started", GRAY_FONT_COLOR, ICON_AVAILABLE
end

-- Quests asked from the server once, so a quest it never answers for can't redraw in a loop.
---@type table<integer, true>
local requestedQuests = {}

-- The quest's chat link; nil until the client has the quest's data, which is then asked for
-- (QUEST_DATA_LOAD_RESULT tells the frames showing it to redraw).
---@param questID integer
---@return string?
function Quests.Link(questID)
    local link = GetQuestLink(questID)
    if not link and not requestedQuests[questID] and C_QuestLog.RequestLoadQuestByID then
        requestedQuests[questID] = true
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    return link
end

-- Can the character take the quest: not one of the other faction, not another class's.
---@param questID integer
---@return boolean
function Quests.IsForCharacter(questID)
    local quest = app.data:GetQuest(questID)
    local side, class = quest and quest.side, quest and quest.class
    if (side == "Alliance" or side == "Horde") and side ~= UnitFactionGroup("player") then
        return false
    end
    return not class or class == select(2, UnitClass("player"))
end

-- The experience a quest rewards, "9,750".
---@param xp integer
---@return string
function Quests.FormatXP(xp)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp)
end

-- Opens a curated { uiMapID, x, y } point and sets it as the user's waypoint where supported.
---@param point number[]
function Quests.ShowOnMap(point)
    local mapID, x, y = unpack(point)
    if type(mapID) ~= "number" then
        return
    end
    x, y = tonumber(x) or 50, tonumber(y) or 50
    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint({ uiMapID = mapID, position = CreateVector2D(x / 100, y / 100) } --[[@as UiMapPoint]])
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
    if OpenWorldMap then
        OpenWorldMap(mapID)
    end
end

-- The most useful map point for the character's current progress: turn-in when ready/done,
-- otherwise the quest giver. Falls back to whichever contact has a point.
---@param questID integer
---@return number[]?
function Quests.MapPoint(questID)
    local quest = app.data:GetQuest(questID)
    if not quest then
        return nil
    end
    local done = C_QuestLog.IsQuestFlaggedCompleted(questID)
        or (C_QuestLog.IsOnQuest(questID) and (C_QuestLog.ReadyForTurnIn(questID) or C_QuestLog.IsComplete(questID)))
    local preferred = done and quest.finish or quest.start
    local fallback = done and quest.start or quest.finish
    return preferred and preferred.map or fallback and fallback.map
end

-- A reward's tooltip line: the item's icon and name, in its quality color. The client's cache when
-- it has the item, else the database row; an uncached item is requested for the next hover.
---@param itemID integer
---@return string text, ColorMixin color
local function rewardLine(itemID)
    local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if not name then
        C_Item.RequestLoadItemDataByID(itemID)
        local row = app.data:GetItem(itemID)
        name = app.data:GetItemName(itemID)
        quality = row and row[app.data.ITEM.QUALITY]
        icon = select(5, C_Item.GetItemInfoInstant(itemID)) or (row and row[app.data.ITEM.ICON])
    end
    local markup = CreateSimpleTextureMarkup(icon or "Interface\\Icons\\INV_Misc_QuestionMark", 16, 16)
    return markup .. " " .. name, quality and ITEM_QUALITY_COLORS[quality] or HIGHLIGHT_FONT_COLOR
end

-- Adds one prerequisite row using client titles when available and curated fallbacks otherwise.
---@param label string
---@param questIDs integer[]
local function addRequirements(label, questIDs)
    if #questIDs == 0 then
        return
    end
    local names = {}
    for _, questID in ipairs(questIDs) do
        local name = app.data:GetQuestName(questID)
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then
            name = GREEN_FONT_COLOR:WrapTextInColorCode(name)
        end
        names[#names + 1] = name
    end
    GameTooltip:AddDoubleLine(
        label,
        table.concat(names, ", "),
        NORMAL_FONT_COLOR:GetRGB(),
        HIGHLIGHT_FONT_COLOR:GetRGB()
    )
end

-- A quest's tooltip on `owner`: the game's own quest tooltip from its link, else, while the
-- client doesn't have the quest (quests are server-side), the curated title, id, level and
-- objective. The curated rewards and experience follow either way.
---@param owner Frame
---@param questID integer
function Quests.ShowTooltip(owner, questID)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local quest = app.data:GetQuest(questID)
    local link = Quests.Link(questID)
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(app.data:GetQuestName(questID), NORMAL_FONT_COLOR:GetRGB())
        GameTooltip:AddLine(("Quest #%d"):format(questID), HIGHLIGHT_FONT_COLOR:GetRGB())
        if quest and quest.requiredLevel then
            GameTooltip:AddLine(("Required level %d"):format(quest.requiredLevel), HIGHLIGHT_FONT_COLOR:GetRGB())
        end
        if quest and quest.objective then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(
                quest.objective,
                HIGHLIGHT_FONT_COLOR.r,
                HIGHLIGHT_FONT_COLOR.g,
                HIGHLIGHT_FONT_COLOR.b,
                true
            )
        end
    end
    if quest and (#quest.items > 0 or quest.xp) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(QUEST_REWARDS or "Rewards", NORMAL_FONT_COLOR:GetRGB())
        for _, row in ipairs(quest.items) do
            local text, color = rewardLine(row[1])
            GameTooltip:AddLine(text, color.r, color.g, color.b)
        end
        if quest.xp then
            local xp = ("%s %s"):format(EXPERIENCE_COLON or "Experience:", Quests.FormatXP(quest.xp))
            GameTooltip:AddLine(xp, HIGHLIGHT_FONT_COLOR:GetRGB())
        end
    end
    if quest and (#(quest.requires or {}) > 0 or #(quest.requiresAny or {}) > 0) then
        GameTooltip:AddLine(" ")
        addRequirements("Requires", quest.requires or {})
        addRequirements("Requires one of", quest.requiresAny or {})
    end
    if quest and #(quest.breadcrumbs or {}) > 0 then
        GameTooltip:AddLine(" ")
        addRequirements("Optional lead-in", quest.breadcrumbs)
    end
    if quest and (quest.start or quest.finish) then
        GameTooltip:AddLine(" ")
        if quest.start and quest.start.name then
            GameTooltip:AddDoubleLine(
                "Starts",
                quest.start.name,
                NORMAL_FONT_COLOR:GetRGB(),
                HIGHLIGHT_FONT_COLOR:GetRGB()
            )
        end
        if quest.finish and quest.finish.name then
            GameTooltip:AddDoubleLine(
                "Ends",
                quest.finish.name,
                NORMAL_FONT_COLOR:GetRGB(),
                HIGHLIGHT_FONT_COLOR:GetRGB()
            )
        end
        if Quests.MapPoint(questID) then
            GameTooltip:AddLine("Alt-click to show on map", GREEN_FONT_COLOR:GetRGB())
        end
    end
    GameTooltip:Show()
end

-- A modified click links the quest in chat, like a quest link there.
---@param questID integer
function Quests.HandleModifiedClick(questID)
    if IsAltKeyDown and IsAltKeyDown() then
        local point = Quests.MapPoint(questID)
        if point then
            Quests.ShowOnMap(point)
            return
        end
    end
    local link = Quests.Link(questID)
    if link then
        HandleModifiedItemClick(link)
    end
end
