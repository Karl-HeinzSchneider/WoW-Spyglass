---@type string, SpyglassScraper
local _, app = ...

-- `/sg export`: the recorded data as JSON in a text box to copy from (Ctrl+A is done for you,
-- Ctrl+C is yours). The text goes into a file for `npm run import` or into an issue.

local HINT =
    "Ctrl+C copies the selection. Save it as a .json file in .contribute/inbox/ and run `npm run import`, or attach it to an issue. Only records new since the last export are shown; /sg export all shows everything."

---@class SpyglassScraper.ExportFrame : Frame
---@field TitleText FontString
---@field Hint FontString
---@field Scroll ScrollFrame|{ EditBox: EditBox }
SpyglassScraperExportFrameMixin = {}
app.ExportFrameMixin = SpyglassScraperExportFrameMixin

function SpyglassScraperExportFrameMixin:OnLoad()
    self.TitleText:SetText("Spyglass - Export")
    self.Hint:SetText(HINT)
    -- ESC closes the window; the edit box drops focus first (InputScrollFrame_OnEscapePressed).
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")
    app.exportFrame = self
end

function SpyglassScraperExportFrameMixin:OnDragStart()
    self:StartMoving()
end

function SpyglassScraperExportFrameMixin:OnDragStop()
    self:StopMovingOrSizing()
end

-- Shows the window with `text` selected, ready to copy.
---@param text string
---@param title? string
---@param hint? string
function SpyglassScraperExportFrameMixin:ShowText(text, title, hint)
    local editBox = self.Scroll.EditBox
    self.TitleText:SetText(title or "Spyglass - Export")
    self.Hint:SetText(hint or HINT)
    editBox:SetText(text)
    self:Show()
    editBox:SetFocus()
    editBox:HighlightText()
    editBox:SetCursorPosition(0)
end
