---@type string, Spyglass
local _, app = ...

local log = app.logger
local Lists = app.lists

app.ui = app.ui or {}

-- The dialog behind the Lists module's buttons: a new list, editing one (name, marker, whether
-- tooltips name it), export (the string to copy), import (a text to paste) and delete. Opened
-- through Spyglass.Lists:Open*Dialog, so the module needs nothing but the public API.

local PADDING, GAP = 12, 10
local MARKER_COUNT, MARKER_SIZE, MARKER_GAP = 8, 22, 4
local UNSELECTED_ALPHA = 0.3
local ACCEPT_HEIGHT = 22
local ERROR_COLOR = RED_FONT_COLOR or CreateColor(1, 0.13, 0.13)

---@alias Spyglass.ListDialogMode "create"|"edit"|"export"|"import"|"delete"

---@class Spyglass.ListDialog : Frame
---@field Title FontString
---@field CloseButton Button
---@field Message FontString
---@field NameBox EditBox
---@field Markers Frame
---@field TooltipCheck CheckButton|{ Label: FontString }
---@field TextFrame Frame|{ Text: ScrollingEditBoxMixin }
---@field Accept Button
---@field markerButtons Button[]
---@field mode? Spyglass.ListDialogMode
---@field listID? string  # the list edited, exported, imported into or deleted
---@field marker? integer  # the picked marker (create / edit)
---@field message? string
---@field isError? boolean
SpyglassListDialogMixin = {}
app.ui.ListDialogMixin = SpyglassListDialogMixin

function SpyglassListDialogMixin:OnLoad()
    app.ui.listDialog = self
    self.markerButtons = {}
    for marker = 1, MARKER_COUNT do
        local button = CreateFrame("Button", nil, self.Markers)
        button:SetSize(MARKER_SIZE, MARKER_SIZE)
        button:SetPoint("LEFT", (marker - 1) * (MARKER_SIZE + MARKER_GAP), 0)
        button:SetNormalTexture(Lists:GetMarkerFile(marker))
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        button:SetScript("OnClick", function()
            self:SelectMarker(marker)
        end)
        self.markerButtons[marker] = button
    end
    self.TooltipCheck.Label:SetText("Show in item tooltips")
    self.NameBox:SetScript("OnEnterPressed", function()
        self:OnAccept()
    end)
    self.Accept:SetScript("OnClick", function()
        self:OnAccept()
    end)
end

-- SpyglassPopupTemplate's scripts; the dialog needs no events.
function SpyglassListDialogMixin:OnShow() end

function SpyglassListDialogMixin:OnEvent() end

function SpyglassListDialogMixin:OnHide()
    self.NameBox:ClearFocus()
    self.TextFrame.Text:ClearFocus()
    self.mode, self.listID = nil, nil
end

---@param marker integer
function SpyglassListDialogMixin:SelectMarker(marker)
    self.marker = marker
    for i, button in ipairs(self.markerButtons) do
        button:SetAlpha(i == marker and 1 or UNSELECTED_ALPHA)
    end
end

-- Stacks the parts the mode shows below the title (the message first) and sizes the frame to
-- them plus the button.
function SpyglassListDialogMixin:Layout()
    local mode = self.mode
    local editing = mode == "create" or mode == "edit"
    local texting = mode == "export" or mode == "import"
    local y = PADDING + self.Title:GetStringHeight() + GAP

    ---@param region Region
    ---@param shown boolean
    ---@param height number
    ---@param x? number
    local function place(region, shown, height, x)
        region:SetShown(shown)
        if shown then
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", self, "TOPLEFT", PADDING + (x or 0), -y)
            y = y + height + GAP
        end
    end

    local color = self.isError and ERROR_COLOR or HIGHLIGHT_FONT_COLOR
    self.Message:SetText(self.message or "")
    self.Message:SetTextColor(color.r, color.g, color.b)
    place(self.Message, self.message ~= nil, self.Message:GetStringHeight())
    -- The input box's frame art reaches a few pixels left of the box.
    place(self.NameBox, editing, self.NameBox:GetHeight(), 6)
    place(self.Markers, editing, self.Markers:GetHeight())
    place(self.TooltipCheck, editing, self.TooltipCheck:GetHeight())
    place(self.TextFrame, texting, self.TextFrame:GetHeight())
    self:SetHeight(y + ACCEPT_HEIGHT + PADDING)
end

---@param message? string
---@param isError? boolean
function SpyglassListDialogMixin:SetMessage(message, isError)
    self.message, self.isError = message, isError
    self:Layout()
end

-- Opens the dialog in a mode, for a list (all but "create"; optional for "import", which makes a
-- new list without one).
---@param mode Spyglass.ListDialogMode
---@param listID? string
function SpyglassListDialogMixin:Open(mode, listID)
    local list = listID and Lists:Get(listID)
    if mode ~= "create" and mode ~= "import" and not list then
        return
    end
    app.ui.HidePopups()
    self.mode, self.listID = mode, listID
    local name = list and list.name or ""
    local title, message, accept
    if mode == "create" then
        title, accept = "New list", "Create"
        self.NameBox:SetText("")
        self:SelectMarker((#Lists:GetAll() - 1) % MARKER_COUNT + 1)
        self.TooltipCheck:SetChecked(true)
    elseif mode == "edit" then
        title, accept = "Edit list", "Save"
        ---@cast list Spyglass.ItemList
        self.NameBox:SetText(name)
        self:SelectMarker(list.marker or 1)
        self.TooltipCheck:SetChecked(list.tooltip)
    elseif mode == "export" then
        title, accept = "Export: " .. name, "Done"
        message = "Copy the text below (Ctrl+C) to share the list. Import list reads it back."
    elseif mode == "import" then
        title, accept = list and ("Import into: " .. name) or "Import list", "Import"
        message = "Paste an exported list (Ctrl+V), or any text with item links or item ids. "
            .. (list and "The items are added to this list." or "They make a new list.")
    else
        title, accept = "Delete list", "Delete"
        message = ("Delete %s and its %d items? This can't be undone."):format(
            name,
            Lists:GetCount(listID --[[@as string]])
        )
    end
    self.Title:SetText(title)
    self.Accept:SetText(accept)
    self.message, self.isError = message, nil
    self:Layout()
    self:Show()

    local textBox = self.TextFrame.Text
    if mode == "export" then
        textBox:SetText(Lists:Export(listID --[[@as string]]) or "")
        textBox:SetFocus()
        textBox:GetEditBox():HighlightText()
    elseif mode == "import" then
        textBox:ClearText()
        textBox:SetFocus()
    elseif mode == "create" then
        self.NameBox:SetFocus()
    end
end

function SpyglassListDialogMixin:OnAccept()
    local mode, id = self.mode, self.listID
    if mode == "create" then
        Lists:Create(self.NameBox:GetText(), self.marker, self.TooltipCheck:GetChecked())
    elseif mode == "edit" and id then
        Lists:Rename(id, self.NameBox:GetText())
        Lists:SetMarker(id, self.marker --[[@as integer]])
        Lists:SetShowInTooltip(id, self.TooltipCheck:GetChecked())
    elseif mode == "import" then
        local newID, result = Lists:Import(self.TextFrame.Text:GetInputText(), id)
        if not newID then
            self:SetMessage(tostring(result), true)
            return
        end
        local list = Lists:Get(newID) --[[@as Spyglass.ItemList]]
        log:chat("%d new items in %s.", result, list.name)
    elseif mode == "delete" and id then
        Lists:Delete(id)
    end
    self:Hide()
end

---------------------------------------------------------------------------------------------------
-- The dialogs on the public API (Spyglass.Lists)
---------------------------------------------------------------------------------------------------

function Lists:OpenCreateDialog()
    app.ui.listDialog:Open("create")
end

---@param id string
function Lists:OpenEditDialog(id)
    app.ui.listDialog:Open("edit", id)
end

---@param id string
function Lists:OpenExportDialog(id)
    app.ui.listDialog:Open("export", id)
end

---@param intoID? string  # nil = the items make a new list
function Lists:OpenImportDialog(intoID)
    app.ui.listDialog:Open("import", intoID)
end

---@param id string
function Lists:OpenDeleteDialog(id)
    app.ui.listDialog:Open("delete", id)
end
