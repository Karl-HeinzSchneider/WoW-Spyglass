---@type string, ForeverLoot
local appName, app = ...

app.ui = app.ui or {}

-- `/fl export`: the recorded data as JSON in a text box to copy from (Ctrl+A is done for you,
-- Ctrl+C is yours). The text goes into a file for `npm run import` or into an issue.

local HINT = "Ctrl+C copies the selection. Save it as a .json file and run `npm run import -- <file>` in .contribute/tools, or attach it to an issue."

---@class ForeverLoot.ExportFrame : Frame
---@field TitleText FontString
---@field Hint FontString
---@field Scroll ScrollFrame|{ EditBox: EditBox }
ForeverLootExportFrameMixin = {}
app.ui.ExportFrameMixin = ForeverLootExportFrameMixin

function ForeverLootExportFrameMixin:OnLoad()
    self.TitleText:SetText(appName .. " - Export")
    self.Hint:SetText(HINT)
    -- ESC closes the window; the edit box drops focus first (InputScrollFrame_OnEscapePressed).
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")
    app.ui.exportFrame = self
end

function ForeverLootExportFrameMixin:OnDragStart()
    self:StartMoving()
end

function ForeverLootExportFrameMixin:OnDragStop()
    self:StopMovingOrSizing()
end

-- Shows the window with `text` selected, ready to copy.
---@param text string
function ForeverLootExportFrameMixin:ShowText(text)
    local editBox = self.Scroll.EditBox
    editBox:SetText(text)
    self:Show()
    editBox:SetFocus()
    editBox:HighlightText()
    editBox:SetCursorPosition(0)
end
