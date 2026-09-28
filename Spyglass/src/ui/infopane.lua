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

local Quests = app.questInfo

---@param line Button|{ questID: integer }
local function showQuestTooltip(line)
    Quests.ShowTooltip(line, line.questID)
end

---@param line Button|{ questID: integer }
local function linkQuest(line)
    Quests.HandleModifiedClick(line.questID)
end

-- One line per quest the character can do: quests of the other faction and class quests of
-- other classes are left out.
---@param questIDs integer[]
function SpyglassInfoPaneMixin:AddQuests(questIDs)
    for _, questID in ipairs(questIDs) do
        if Quests.IsForCharacter(questID) then
            local frame = self:Acquire("quest") --[[@as Button|{ Title: FontString, Status: FontString, questID: integer }]]
            frame.questID = questID
            Quests.Link(questID) -- loads the quest ahead of hover and click
            frame:SetScript("OnEnter", showQuestTooltip)
            frame:SetScript("OnLeave", GameTooltip_Hide)
            frame:SetScript("OnClick", linkQuest)
            frame.Title:SetText(app.data:GetQuestName(questID))
            local text, color = Quests.Status(questID)
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
            app.questInfo.ShowOnMap({ mapID, tonumber(x) or 50, tonumber(y) or 50 })
        end
    end
end
