---@type string, ForeverLootScraper
local _, app = ...

-- `/fl export`: the recorded data as JSON in a text box to copy from (Ctrl+A is done for you,
-- Ctrl+C is yours). The text goes into a file for `npm run import` or into an issue.

local HINT = "Ctrl+C copies the selection. Save it as a .json file in .contribute/inbox/ and run `npm run import`, or attach it to an issue. Only records new since the last export are shown; /fl export all shows everything."

---@class ForeverLootScraper.ExportFrame : Frame
---@field TitleText FontString
---@field Hint FontString
---@field Scroll ScrollFrame|{ EditBox: EditBox }
ForeverLootScraperExportFrameMixin = {}
app.ExportFrameMixin = ForeverLootScraperExportFrameMixin

function ForeverLootScraperExportFrameMixin:OnLoad()
    self.TitleText:SetText("ForeverLoot - Export")
    self.Hint:SetText(HINT)
    -- ESC closes the window; the edit box drops focus first (InputScrollFrame_OnEscapePressed).
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")
    app.exportFrame = self
end

function ForeverLootScraperExportFrameMixin:OnDragStart()
    self:StartMoving()
end

function ForeverLootScraperExportFrameMixin:OnDragStop()
    self:StopMovingOrSizing()
end

-- Shows the window with `text` selected, ready to copy.
---@param text string
function ForeverLootScraperExportFrameMixin:ShowText(text)
    local editBox = self.Scroll.EditBox
    editBox:SetText(text)
    self:Show()
    editBox:SetFocus()
    editBox:HighlightText()
    editBox:SetCursorPosition(0)
end
