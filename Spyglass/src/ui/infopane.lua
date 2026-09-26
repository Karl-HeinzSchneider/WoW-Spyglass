---@type string, Spyglass
local _, app = ...

local log = app.logger
app.ui = app.ui or {}

----------------------------------------------------------------------------------------------------
-- Info pane: the right column of the window, the panel of the selected tab's path
----------------------------------------------------------------------------------------------------

-- The widget kinds (a widget's type key) and the pooled template each is drawn with.
local WIDGETS = {
    header = { "Frame", "SpyglassInfoHeaderTemplate" },
    text = { "Frame", "SpyglassInfoTextTemplate" },
    row = { "Frame", "SpyglassInfoRowTemplate" },
    bar = { "Frame", "SpyglassInfoBarTemplate" },
    checkbox = { "CheckButton", "SpyglassInfoCheckboxTemplate" },
    dropdown = { "Frame", "SpyglassInfoDropdownTemplate" },
    button = { "Button", "SpyglassInfoButtonTemplate" },
    quest = { "Button", "SpyglassInfoQuestTemplate" },
    spacer = { "Frame", "SpyglassInfoSpacerTemplate" },
}
local SPACER_HEIGHT = 8
local NOT_LEARNED = "Not learned"

---@class Spyglass.InfoPane : Frame
---@field Title FontString
---@field Divider Texture
---@field Content Spyglass.LayoutFrame
---@field pools table<string, Spyglass.FramePool>
---@field layoutIndex integer
---@field view? Spyglass.View
---@field refreshQueued? boolean  # an event redraw is scheduled for the next frame
SpyglassInfoPaneMixin = {}
app.ui.InfoPaneMixin = SpyglassInfoPaneMixin

function SpyglassInfoPaneMixin:OnLoad()
    self.pools = {}
    for kind, template in pairs(WIDGETS) do
        self.pools[kind] = CreateFramePool(template[1], self.Content, template[2]) --[[@as Spyglass.FramePool]]
    end
    self.layoutIndex = 0
    -- The bars show the character's standing and skill, the quest lines its quest progress.
    self:RegisterEvent("UPDATE_FACTION")
    self:RegisterEvent("SKILL_LINES_CHANGED")
    self:RegisterEvent("QUEST_LOG_UPDATE")
    self:RegisterEvent("QUEST_TURNED_IN")
    -- A quest the client hadn't loaded arrived: its title and link are known now.
    self:RegisterEvent("QUEST_DATA_LOAD_RESULT")
end

function SpyglassInfoPaneMixin:OnShow()
    self:Refresh()
end

-- Redraws on the next frame, once for any number of events. Never directly: drawing the quest
-- lines asks the server for quests, whose QUEST_DATA_LOAD_RESULT can fire inside that call, and
-- a Refresh inside a Refresh releases the lines the outer one is still filling.
function SpyglassInfoPaneMixin:OnEvent()
    if self:IsVisible() and not self.refreshQueued then
        self.refreshQueued = true
        C_Timer.After(0, function()
            self.refreshQueued = nil
            if self:IsVisible() then
                self:Refresh()
            end
        end)
    end
end

-- Shows the panel of `view` (the selected tab) from now on.
---@param view Spyglass.View
function SpyglassInfoPaneMixin:SetView(view)
    self.view = view
    self:Refresh()
end

-- Draws the panel of the deepest node on the view's path that has one; without any, the
-- current node's name and description.
function SpyglassInfoPaneMixin:Refresh()
    for _, pool in pairs(self.pools) do
        pool:ReleaseAll()
    end
    self.layoutIndex = 0

    local view = self.view
    local node, widgets = nil, nil
    if view then
        node, widgets = view:GetPanel()
        if not node then
            node, widgets = view:GetCurrentNode(), { { description = true } }
        end
    end
    self.Title:SetText(node and node.name or "")
    if node and view then
        for index, widget in ipairs(widgets or {}) do
            local ok, err = pcall(self.AddWidget, self, view, node, index, widget)
            if not ok then
                log:error("%s: panel widget %d failed: %s", tostring(node.name), index, tostring(err))
            end
        end
    end
    self.Content:Layout()
end

---@param kind string
---@return Frame
function SpyglassInfoPaneMixin:Acquire(kind)
    local frame = self.pools[kind]:Acquire() --[[@as Spyglass.LayoutChild]]
    self.layoutIndex = self.layoutIndex + 1
    frame.layoutIndex = self.layoutIndex
    frame:Show()
    return frame
end

---@param text string
function SpyglassInfoPaneMixin:AddText(text)
    local frame = self:Acquire("text") --[[@as Frame|{ Text: FontString }]]
    frame.Text:SetText(text)
    frame:SetHeight(math.max(1, frame.Text:GetStringHeight()))
end

-- One widget below the others, by its type key (see Spyglass.PanelWidget). `node` is the
-- node the panel belongs to, `index` the widget's place in it (the key of its state in the view).
---@param view Spyglass.View
---@param node Spyglass.Node
---@param index integer
---@param widget Spyglass.PanelWidget
function SpyglassInfoPaneMixin:AddWidget(view, node, index, widget)
    if widget.header then
        local frame = self:Acquire("header") --[[@as Frame|{ Text: FontString }]]
        frame.Text:SetText(widget.header)
    elseif widget.text then
        self:AddText(widget.text)
    elseif widget.description then
        if type(node.description) == "string" and node.description ~= "" then
            self:AddText(node.description)
        end
    elseif widget.row then
        local frame = self:Acquire("row") --[[@as Frame|{ Label: FontString, Value: FontString }]]
        frame.Label:SetText(widget.row)
        frame.Value:SetText(widget.value ~= nil and tostring(widget.value) or "")
    elseif widget.bar then
        self:SetBar(self:Acquire("bar") --[[@as ColoredProgressBarMixin]], node, widget)
    elseif widget.checkbox then
        local frame = self:Acquire("checkbox") --[[@as CheckButton|{ Label: FontString }]]
        frame.Label:SetText(widget.checkbox)
        frame:SetChecked(view:GetPanelValue(node, index) == true)
        frame:SetScript("OnClick", function(button)
            view:SetPanelValue(node, index, button:GetChecked() or nil)
        end)
    elseif widget.dropdown then
        local frame = self:Acquire("dropdown") --[[@as Frame|{ Label: FontString, Dropdown: WowStyle1FilterDropdownMixin }]]
        frame.Label:SetText(widget.dropdown)
        frame.Dropdown:SetupMenu(function(_, root)
            local function radio(label, value)
                root:CreateRadio(label, function()
                    return view:GetPanelValue(node, index) == value
                end, function()
                    view:SetPanelValue(node, index, value)
                end)
            end
            radio(ALL or "All", nil)
            for _, option in ipairs(view:GetFieldValues(widget.field)) do
                radio(option.label, option.value)
            end
        end)
    elseif widget.grouping then
        -- The same dropdown, one radio per option; the first is picked until another is.
        local frame = self:Acquire("dropdown") --[[@as Frame|{ Label: FontString, Dropdown: WowStyle1FilterDropdownMixin }]]
        frame.Label:SetText(widget.grouping)
        frame.Dropdown:SetupMenu(function(_, root)
            for i, option in ipairs(widget.options or {}) do
                root:CreateRadio(option.label, function()
                    return (view:GetPanelValue(node, index) or 1) == i
                end, function()
                    view:SetPanelValue(node, index, i)
                end)
            end
        end)
    elseif widget.button then
        local frame = self:Acquire("button") --[[@as Button]]
        frame:SetText(widget.button)
        frame:SetScript("OnClick", function()
            self:RunButton(view, node, widget)
        end)
    elseif widget.quests then
        self:AddQuests(widget.quests)
    elseif widget.spacer then
        local frame = self:Acquire("spacer")
        frame:SetHeight(type(widget.spacer) == "number" and widget.spacer --[[@as number]] or SPACER_HEIGHT)
    end
end

----------------------------------------------------------------------------------------------------
-- Quests
----------------------------------------------------------------------------------------------------

-- The character's progress on a quest, as text and color: turned in, objectives complete,
-- in the quest log, or not taken yet.
---@param questID integer
---@return string, ColorMixin
local function questStatus(questID)
    local questLog = C_QuestLog
    if questLog.IsQuestFlaggedCompleted(questID) then
        return "Done", GREEN_FONT_COLOR
    end
    if questLog.IsOnQuest(questID) then
        if questLog.ReadyForTurnIn(questID) or questLog.IsComplete(questID) then
            return "Ready", YELLOW_FONT_COLOR
        end
        return "Active", HIGHLIGHT_FONT_COLOR
    end
    return "Not started", GRAY_FONT_COLOR
end

-- Quests asked from the server once, so a quest it never answers for can't redraw in a loop.
---@type table<integer, true>
local requestedQuests = {}

-- The quest's chat link; nil until the client has the quest's data, which is then asked for
-- (QUEST_DATA_LOAD_RESULT redraws the pane).
---@param questID integer
---@return string?
local function questLink(questID)
    local link = GetQuestLink(questID)
    if not link and not requestedQuests[questID] and C_QuestLog.RequestLoadQuestByID then
        requestedQuests[questID] = true
        C_QuestLog.RequestLoadQuestByID(questID)
    end
    return link
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

-- A quest line's tooltip: the game's own quest tooltip from its link, else, while the client
-- doesn't have the quest (quests are server-side), the curated title, id, level and objective.
-- The curated rewards and experience follow either way.
---@param line Button|{ questID: integer }
local function showQuestTooltip(line)
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    local quest = app.data:GetQuest(line.questID)
    local link = questLink(line.questID)
    if link then
        GameTooltip:SetHyperlink(link)
    else
        GameTooltip:SetText(app.data:GetQuestName(line.questID), NORMAL_FONT_COLOR:GetRGB())
        GameTooltip:AddLine(("Quest #%d"):format(line.questID), HIGHLIGHT_FONT_COLOR:GetRGB())
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
            local xp = ("%s %s"):format(EXPERIENCE_COLON or "Experience:", BreakUpLargeNumbers(quest.xp))
            GameTooltip:AddLine(xp, HIGHLIGHT_FONT_COLOR:GetRGB())
        end
    end
    GameTooltip:Show()
end

-- A modified click links the quest in chat, like a quest link there.
---@param line Button|{ questID: integer }
local function linkQuest(line)
    local link = questLink(line.questID)
    if link then
        HandleModifiedItemClick(link)
    end
end

-- One line per quest the character can do: quests of the other faction and class quests of
-- other classes are left out.
---@param questIDs integer[]
function SpyglassInfoPaneMixin:AddQuests(questIDs)
    local playerSide = UnitFactionGroup("player")
    local _, playerClass = UnitClass("player")
    for _, questID in ipairs(questIDs) do
        local quest = app.data:GetQuest(questID)
        local side, class = quest and quest.side, quest and quest.class
        local forSide = side ~= "Alliance" and side ~= "Horde" or side == playerSide
        if forSide and (not class or class == playerClass) then
            local frame = self:Acquire("quest") --[[@as Button|{ Title: FontString, Status: FontString, questID: integer }]]
            frame.questID = questID
            questLink(questID) -- loads the quest ahead of hover and click
            frame:SetScript("OnEnter", showQuestTooltip)
            frame:SetScript("OnLeave", GameTooltip_Hide)
            frame:SetScript("OnClick", linkQuest)
            frame.Title:SetText(app.data:GetQuestName(questID))
            local text, color = questStatus(questID)
            frame.Status:SetText(text)
            frame.Status:SetTextColor(color:GetRGB())
            frame:SetHeight(math.max(14, frame.Title:GetStringHeight()))
        end
    end
end

----------------------------------------------------------------------------------------------------
-- Bars
----------------------------------------------------------------------------------------------------

-- The character's standing with a faction, as the reputation pane draws it: the fill within the
-- current standing in the standing's color, the standing and the progress as text. An empty
-- bar when the character hasn't met the faction.
---@param bar ColoredProgressBarMixin
---@param factionID integer?
local function setReputationBar(bar, factionID)
    bar:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.White)
    local data = factionID and C_Reputation and C_Reputation.GetFactionDataByID(factionID)
    if not data or type(data.reaction) ~= "number" then
        bar:SetFillPercent(0)
        bar:SetText(UNKNOWN or "Unknown")
        return
    end
    local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[data.reaction]
    if color then
        bar.Fill:SetVertexColor(color.r, color.g, color.b)
    end
    local standing = _G["FACTION_STANDING_LABEL" .. data.reaction] or ""
    local low, high, current = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
    if data.reaction >= (MAX_REPUTATION_REACTION or 8) or not (low and high and current) or high <= low then
        bar:SetFillPercent(1)
        bar:SetText(standing)
    else
        bar:SetFillPercent((current - low) / (high - low))
        bar:SetText(
            ("%s  %s / %s"):format(standing, BreakUpLargeNumbers(current - low), BreakUpLargeNumbers(high - low))
        )
    end
end

-- The character's rank in a profession, as the skills pane draws it.
---@param bar ColoredProgressBarMixin
---@param skillLineID integer?
local function setSkillBar(bar, skillLineID)
    bar:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.Blue)
    bar.Fill:SetVertexColor(1, 1, 1)
    local info = skillLineID and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID(skillLineID)
    if not info or not info.rank or info.rank <= 0 then
        bar:SetFillPercent(0)
        bar:SetText(NOT_LEARNED)
        return
    end
    local max = info.maxRank or 0
    bar:SetFillPercent(max > 0 and info.rank / max or 0)
    bar:SetText(("%d / %d"):format(info.rank, max))
end

-- The fill color is set before the percentage: SetFillTextureByColorType resets the fill's size.
---@param bar ColoredProgressBarMixin
---@param node Spyglass.Node
---@param widget Spyglass.PanelWidget
function SpyglassInfoPaneMixin:SetBar(bar, node, widget)
    local meta = node.meta or {}
    if widget.bar == "reputation" then
        setReputationBar(bar, widget.faction or meta.factionID)
    elseif widget.bar == "skill" then
        setSkillBar(bar, widget.skillLine or meta.skillLineID)
    else
        local value, max = tonumber(widget.value) or 0, tonumber(widget.max) or 0
        bar:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.Blue)
        bar.Fill:SetVertexColor(1, 1, 1)
        bar:SetFillPercent(max > 0 and value / max or 0)
        bar:SetText(widget.label or ("%s / %s"):format(value, max))
    end
end

----------------------------------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------------------------------

-- Opens the world map at `mapID` with a waypoint at x, y (0..100, as the map shows them) where
-- the map takes one.
---@param mapID integer
---@param x number
---@param y number
local function showOnMap(mapID, x, y)
    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
        -- The table UiMapPoint.CreateFromCoordinates builds; that helper isn't loaded in every client.
        C_Map.SetUserWaypoint({ uiMapID = mapID, position = CreateVector2D(x / 100, y / 100) } --[[@as UiMapPoint]])
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end
    if OpenWorldMap then
        OpenWorldMap(mapID)
    end
end

-- A button's action: its own `onClick`, else open a collection, else show a point on the map.
---@param view Spyglass.View
---@param node Spyglass.Node
---@param widget Spyglass.PanelWidget
function SpyglassInfoPaneMixin:RunButton(view, node, widget)
    if type(widget.onClick) == "function" then
        local ok, err = pcall(widget.onClick, node, view)
        if not ok then
            log:error("%s: panel button failed: %s", tostring(node.name), tostring(err))
        end
    elseif type(widget.open) == "string" then
        view:OpenPath(widget.open)
    elseif type(widget.map) == "table" then
        local mapID, x, y = unpack(widget.map)
        if type(mapID) == "number" then
            showOnMap(mapID, tonumber(x) or 50, tonumber(y) or 50)
        end
    end
end
