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
    item = { "Button", "SpyglassInfoItemTemplate" },
    bar = { "Frame", "SpyglassInfoBarTemplate" },
    checkbox = { "CheckButton", "SpyglassInfoCheckboxTemplate" },
    dropdown = { "Frame", "SpyglassInfoDropdownTemplate" },
    queryDropdown = { "Frame", "SpyglassInfoQueryDropdownTemplate" },
    querySearch = { "Frame", "SpyglassInfoSearchTemplate" },
    queryRange = { "Frame", "SpyglassInfoRangeTemplate" },
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
    self:QueueRefresh()
end

function SpyglassInfoPaneMixin:QueueRefresh()
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
    local focused, focusRangeID, focusView, focusNode, focusText, cursor
    if self.querySearchBox and self.querySearchBox:HasFocus() then
        focused = "Search"
        focusView, focusNode = self.querySearchBox.view, self.querySearchBox.queryNode
        focusText, cursor = self.querySearchBox:GetText(), self.querySearchBox:GetCursorPosition()
    elseif self.queryRanges then
        for id, range in pairs(self.queryRanges) do
            for _, kind in ipairs({ "Min", "Max" }) do
                local input = range[kind]
                if input:HasFocus() then
                    focused, focusRangeID = kind, id
                    focusView, focusNode = self.view, self.view:GetCurrentNode()
                    focusText, cursor = input:GetText(), input:GetCursorPosition()
                    break
                end
            end
            if focused then
                break
            end
        end
    end
    if self.querySearchBox and self.querySearchBox.debounce then
        self.querySearchBox.debounce:Cancel()
        self.querySearchBox.debounce = nil
    end
    self.querySearchBox = nil
    self.queryRanges = {}
    self.queryDropdowns = {}
    self.queryNode = nil
    for _, pool in pairs(self.pools) do
        pool:ReleaseAll()
    end
    self.layoutIndex = 0

    local view = self.view
    local node, widgets = nil, nil
    if view then
        node, widgets = view:GetPanel()
        if not node then
            node = view:GetCurrentNode()
            widgets = node and node.query and {} or { { description = true } }
        end
    end
    self.Title:SetText(node and node.name or "")
    if node and view then
        local current = view:GetCurrentNode()
        if current and current.query then
            self:AddQueryControls(view, current)
        end
        for index, widget in ipairs(widgets or {}) do
            local ok, err = pcall(self.AddWidget, self, view, node, index, widget)
            if not ok then
                log:error("%s: panel widget %d failed: %s", tostring(node.name), index, tostring(err))
            end
        end
    end
    self.Content:Layout()
    if focused and self.view == focusView and self.view:GetCurrentNode() == focusNode then
        local range = focusRangeID and self.queryRanges[focusRangeID]
        local input = focused == "Search" and self.querySearchBox or range and range[focused]
        if input then
            input:SetText(focusText)
            input:SetFocus()
            input:SetCursorPosition(cursor)
            if focused == "Search" then
                local q = input.view:GetCurrentQuery()
                if q and q.search ~= focusText then
                    input:OnTextChanged(true)
                end
            end
        end
    end
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
    elseif widget.item then
        local itemID = widget.item
        local frame = self:Acquire("item") --[[@as Button|{ Icon: Texture, Name: FontString }]]
        local row = app.data:GetItem(itemID)
        local icon = select(5, C_Item.GetItemInfoInstant(itemID)) or (row and row[app.data.ITEM.ICON])
        frame.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        frame.Name:SetText(app.data:GetItemName(itemID))
        frame:SetScript("OnEnter", function(button)
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemID)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", GameTooltip_Hide)
        frame:SetScript("OnClick", function()
            local link = select(2, C_Item.GetItemInfo(itemID))
            if link then
                HandleModifiedItemClick(link)
            end
        end)
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
    elseif widget.factionDropdown then
        local frame = self:Acquire("dropdown") --[[@as Frame|{ Label: FontString, Dropdown: WowStyle1FilterDropdownMixin }]]
        frame.Label:SetText(widget.factionDropdown)
        frame.Dropdown:SetupMenu(function(_, root)
            for _, side in ipairs({ "Alliance", "Horde", "Both" }) do
                root:CreateRadio(side, function()
                    return (view:GetPanelValue(node, index) or UnitFactionGroup("player")) == side
                end, function()
                    view:SetPanelValue(node, index, side)
                end)
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

-- Query controls belong to the current query folder, while its optional info widgets still
-- belong to the deepest panel node. All state lives on the view's per-folder query.
---@param value any
---@return boolean
local function filterIsActive(value)
    return value ~= nil and (type(value) ~= "table" or #value > 0)
end

---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassInfoPaneMixin:AddQueryControls(view, node)
    local q = view:GetQuery(node)
    self.queryNode = node
    local search = self:Acquire("querySearch") --[[@as Frame|{ Box: Spyglass.SearchBox, Count: FontString }]]
    local box = search.Box
    self.querySearchBox = box
    self.queryCount = search.Count
    box.view, box.queryNode = view, node
    box:SetText(q.search or "")
    search.Count:SetText(("%d items"):format(view.resultCount))
    if not box.queryClearHooked then
        box.queryClearHooked = true
        box.clearButton:HookScript("OnClick", function()
            if box.view and box.view:GetCurrentNode() == box.queryNode then
                box.view:SetSearch("")
            end
        end)
    end

    local header = self:Acquire("header") --[[@as Frame|{ Text: FontString }]]
    header.Text:SetText("Filters")

    for _, def in ipairs(app.filters:GetAll()) do
        if def.id == "itemLevel" or def.id == "reqLevel" then
            self:AddLevelRange(view, q, def)
        elseif def.id ~= "boss" then
            self:AddQueryFilter(view, q, def)
        end
    end

    local sort = self:Acquire("queryDropdown") --[[@as Frame|{ Label: FontString, Dropdown: WowStyle1DropdownMixin }]]
    self.queryDropdowns[#self.queryDropdowns + 1] = sort.Dropdown
    sort.Label:SetText("Sort by")
    sort.Dropdown:SetDefaultText(NAME or "Name")
    sort.Dropdown:SetSelectionText(function()
        local labels =
            { name = NAME or "Name", ilvl = ITEM_LEVEL_ABBR or "Item Level", quality = QUALITY or "Quality", id = "ID" }
        return labels[q.sort or "name"]
    end)
    sort.Dropdown:SetupMenu(function(_, root)
        for _, option in ipairs({
            { "name", NAME or "Name" },
            { "ilvl", ITEM_LEVEL_ABBR or "Item Level" },
            { "quality", QUALITY or "Quality" },
            { "id", "ID" },
        }) do
            root:CreateRadio(option[2], function()
                return (q.sort or "name") == option[1]
            end, function()
                view:SetSort(q, option[1])
            end)
        end
    end)
    sort.Dropdown.queryIsDefault = function()
        return (q.sort or "name") == "name"
    end
    sort.Dropdown.ResetButton:SetShown(not sort.Dropdown.queryIsDefault())
    sort.Dropdown.ResetButton:SetScript("OnClick", function()
        view:SetSort(q, "name")
    end)

    local reset = self:Acquire("button") --[[@as Button]]
    reset:SetText("Reset filters")
    reset:SetScript("OnClick", function()
        view:ResetFilters(q)
    end)
end

---@param view Spyglass.View
---@param q Spyglass.Query
---@param def Spyglass.FilterDef
function SpyglassInfoPaneMixin:AddQueryFilter(view, q, def)
    local frame = self:Acquire("queryDropdown") --[[@as Frame|{ Label: FontString, Dropdown: WowStyle1DropdownMixin }]]
    self.queryDropdowns[#self.queryDropdowns + 1] = frame.Dropdown
    frame.Label:SetText(def.name)
    frame.Dropdown:SetDefaultText(ALL or "Any")
    frame.Dropdown:SetSelectionText(function()
        local value = q.filters[def.id]
        if value == nil or (type(value) == "table" and #value == 0) then
            return nil
        end
        if type(value) == "table" and #value > 1 then
            return ("%d selected"):format(#value)
        end
        local selected = type(value) == "table" and value[1] or value
        for _, option in ipairs(app.filters:GetOptions(def.id)) do
            if option.value == selected then
                return option.label
            end
        end
        return tostring(selected)
    end)
    frame.Dropdown:SetupMenu(function(_, root)
        if def.kind == "multi" then
            for _, option in ipairs(app.filters:GetOptions(def.id)) do
                root:CreateCheckbox(option.label, function()
                    return view:HasFilterValue(q, def.id, option.value)
                end, function()
                    view:ToggleFilterValue(q, def.id, option.value)
                    return MenuResponse.Refresh
                end)
            end
        else
            root:CreateRadio(ALL or "Any", function()
                return q.filters[def.id] == nil
            end, function()
                view:SetFilterValue(q, def.id, nil)
                return MenuResponse.Refresh
            end)
            for _, option in ipairs(app.filters:GetOptions(def.id)) do
                root:CreateRadio(option.label, function()
                    return q.filters[def.id] == option.value
                end, function()
                    view:SetFilterValue(q, def.id, option.value)
                    return MenuResponse.Refresh
                end)
            end
        end
        if #app.filters:GetOptions(def.id) > 20 then
            root:SetScrollMode(400)
        end
    end)
    frame.Dropdown.queryIsDefault = function()
        return not filterIsActive(q.filters[def.id])
    end
    frame.Dropdown.ResetButton:SetShown(not frame.Dropdown.queryIsDefault())
    frame.Dropdown.ResetButton:SetScript("OnClick", function()
        view:SetFilterValue(q, def.id, nil)
    end)
end

---@param value any
---@return string?, string?
local function rangeBounds(value)
    local min, max
    if type(value) == "string" then
        min, max = value:match("^(%d+)%-(%d+)$")
        if not min then
            min = value:match("^(%d+)%+$")
        end
    end
    if min == "0" and max then
        min = nil
    end
    return min, max
end

-- Keep query controls in place while a dropdown is open or an edit box has focus.
function SpyglassInfoPaneMixin:SyncQueryControls()
    local view = self.view
    local q, node
    if view then
        q, node = view:GetCurrentQuery()
    end
    if not q or node ~= self.queryNode then
        self:QueueRefresh()
        return
    end
    if self.queryCount then
        self.queryCount:SetText(("%d items"):format(view.resultCount))
    end
    local box = self.querySearchBox
    if box and not box:HasFocus() and box:GetText() ~= q.search then
        box:SetText(q.search or "")
    end
    for _, dropdown in ipairs(self.queryDropdowns or {}) do
        dropdown:Update()
        dropdown.ResetButton:SetShown(not dropdown.queryIsDefault())
    end
    for id, range in pairs(self.queryRanges or {}) do
        range.ResetButton:SetShown(filterIsActive(q.filters[id]))
        if not range.Min:HasFocus() and not range.Max:HasFocus() then
            local min, max = rangeBounds(q.filters[id])
            range.Min:SetText(min or "")
            range.Max:SetText(max or "")
        end
    end
end

---@param view Spyglass.View
---@param q Spyglass.Query
---@param def Spyglass.FilterDef
function SpyglassInfoPaneMixin:AddLevelRange(view, q, def)
    local frame = self:Acquire("queryRange") --[[@as Frame|{ Min: EditBox, Max: EditBox }]]
    self.queryRanges[def.id] = frame
    frame.Label:SetText(def.name)
    local min, max = rangeBounds(q.filters[def.id])
    frame.Min:SetText(min or "")
    frame.Max:SetText(max or "")
    frame.Min:SetNumeric(true)
    frame.Max:SetNumeric(true)
    frame.ResetButton:SetShown(filterIsActive(q.filters[def.id]))
    frame.ResetButton:SetScript("OnClick", function()
        frame.Min:ClearFocus()
        frame.Max:ClearFocus()
        view:SetFilterValue(q, def.id, nil)
    end)
    local function apply()
        if view:GetCurrentQuery() ~= q then
            return
        end
        local low, high = frame.Min:GetText(), frame.Max:GetText()
        local nextValue
        if low ~= "" and high ~= "" then
            nextValue = ("%d-%d"):format(tonumber(low), tonumber(high))
        elseif low ~= "" then
            nextValue = ("%d+"):format(tonumber(low))
        elseif high ~= "" then
            nextValue = ("0-%d"):format(tonumber(high))
        end
        view:SetFilterValue(q, def.id, nextValue)
    end
    for _, input in ipairs({ frame.Min, frame.Max }) do
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            frame.Min:SetText(min or "")
            frame.Max:SetText(max or "")
            self:ClearFocus()
        end)
        input:SetScript("OnEditFocusLost", apply)
    end
end

-- The full loading screen texture, separate from the cropped picture used on dungeon tiles.
---@class Spyglass.LoadingArtPreview : Frame
---@field Art Texture
---@field Title FontString
SpyglassLoadingArtPreviewMixin = {}

---@param node Spyglass.Node
function SpyglassLoadingArtPreviewMixin:ShowArt(node)
    if not node.background then
        return
    end
    self.Title:SetText(node.name or "Loading screen art")
    self.Art:SetTexture(node.background)
    self.Art:SetTexCoord(0, 1, 0, 1)

    local aspect = 16 / 9
    local maxWidth = math.min(1200, UIParent:GetWidth() - 32)
    local maxHeight = math.min(900, UIParent:GetHeight() - 32)
    local width = math.min(maxWidth - 32, (maxHeight - 72) * aspect)
    local height = width / aspect
    self.Art:SetSize(width, height)
    self:SetSize(width + 32, height + 72)
    self:Show()
end
