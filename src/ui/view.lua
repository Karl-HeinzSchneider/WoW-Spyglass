---@type string, ForeverLoot
local _, app = ...

local log = app.logger

-- XML `mixin=` attributes need globals; these are the only globals the addon defines besides the
-- window frame itself. They are also reachable via app.ui.* for code that has the namespace.
app.ui = app.ui or {}

-- Camelot ships the "-C60" spellbook art; fall back to the mainline atlases if it's missing.
local function pageAtlas(side)
    local camelot = "spellbook-Page-" .. side .. "-C60"
    if C_Texture.GetAtlasInfo(camelot) then
        return camelot
    end
    return "spellbook-background-evergreen-" .. side:lower()
end

----------------------------------------------------------------------------------------------------
-- List row
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.ListRow : Button
---@field Icon Texture
---@field Name FontString
---@field Arrow Texture
---@field node ForeverLoot.Node
---@field view ForeverLoot.View
ForeverLootListRowMixin = {}
app.ui.ListRowMixin = ForeverLootListRowMixin

---@param view ForeverLoot.View
---@param node ForeverLoot.Node
function ForeverLootListRowMixin:Init(view, node)
    self.view = view
    self.node = node

    -- Real items (itemID) aren't resolved yet; show a stand-in so the tree is still browsable.
    self.Icon:SetTexture(node.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.Name:SetText(node.name or (node.itemID and ("Item #" .. node.itemID)) or "?")

    local isFolder = node.children ~= nil
    self.Arrow:SetShown(isFolder)

    local color = not isFolder and node.quality and ITEM_QUALITY_COLORS[node.quality]
    if color then
        self.Name:SetTextColor(color.r, color.g, color.b)
    else
        self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
end

function ForeverLootListRowMixin:OnClick()
    if self.node.children then
        self.view:Push(self.node)
    else
        -- No item logic yet; just prove the click arrives.
        log:chat("Clicked %s", self.node.name or tostring(self.node.itemID))
    end
end

----------------------------------------------------------------------------------------------------
-- Breadcrumb button
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.BreadcrumbButton : Button
---@field Text FontString
---@field layoutIndex integer
---@field view ForeverLoot.View
---@field index integer
ForeverLootBreadcrumbButtonMixin = {}
app.ui.BreadcrumbButtonMixin = ForeverLootBreadcrumbButtonMixin

---@param view ForeverLoot.View
---@param index integer  # position in view.path
---@param text string
---@param isCurrent boolean
function ForeverLootBreadcrumbButtonMixin:Init(view, index, text, isCurrent)
    self.view = view
    self.index = index
    self:SetText(text)
    self:SetWidth(self.Text:GetStringWidth() + 8)
    self:SetEnabled(not isCurrent)
end

function ForeverLootBreadcrumbButtonMixin:OnClick()
    self.view:PopTo(self.index)
end

----------------------------------------------------------------------------------------------------
-- View: breadcrumb + two pages of rows
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.PagingControls : Frame, PagingControlsMixin

---@class ForeverLoot.View : Frame
---@field BackButton Button
---@field Breadcrumbs ForeverLoot.LayoutFrame
---@field LeftPage ForeverLoot.Page
---@field RightPage ForeverLoot.Page
---@field PagingControls ForeverLoot.PagingControls
---@field crumbPool ForeverLoot.FramePool
---@field separatorPool ForeverLoot.FramePool
---@field rowHeight number
---@field pageInsetTop number
---@field pageInsetBottom number
---@field pageInsetLeft number
---@field pageInsetRight number
---@field path ForeverLoot.Node[]
---@field onNavigate? fun(view: ForeverLoot.View)
---@field isMinimized boolean  # one page (true) or the two-page spread (false)
ForeverLootViewMixin = {}
app.ui.ViewMixin = ForeverLootViewMixin

---@class ForeverLoot.Page : Frame
---@field Background Texture
---@field rowPool ForeverLoot.FramePool

function ForeverLootViewMixin:OnLoad()
    self.path = {}
    self.isMinimized = true

    self.RightPage.Background:SetAtlas(pageAtlas("Right"))
    self:ApplyPageLayout()
    self.LeftPage.rowPool = CreateFramePool("Button", self.LeftPage, "ForeverLootListRowTemplate") --[[@as ForeverLoot.FramePool]]
    self.RightPage.rowPool = CreateFramePool("Button", self.RightPage, "ForeverLootListRowTemplate") --[[@as ForeverLoot.FramePool]]

    self.crumbPool = CreateFramePool("Button", self.Breadcrumbs, "ForeverLootBreadcrumbButtonTemplate") --[[@as ForeverLoot.FramePool]]
    self.separatorPool = CreateFramePool("Frame", self.Breadcrumbs, "ForeverLootBreadcrumbSeparatorTemplate") --[[@as ForeverLoot.FramePool]]

    self.BackButton:SetScript("OnClick", function()
        self:Back()
    end)
end

function ForeverLootViewMixin:OnShow()
    self:Refresh()
end

-- Minimized shows only LeftPage stretched across the view (with the "halved" book art, which
-- is the right-page atlas, exactly as the spellbook's BookBGHalved does). Maximized shows both.
---@param minimized boolean
function ForeverLootViewMixin:SetMinimized(minimized)
    if self.isMinimized == minimized then
        return
    end
    self.isMinimized = minimized
    self:ApplyPageLayout()
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
end

function ForeverLootViewMixin:ApplyPageLayout()
    local left = self.LeftPage
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    if self.isMinimized then
        left:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
        left.Background:SetAtlas(pageAtlas("Right"))
        self.RightPage:Hide()
    else
        left:SetPoint("BOTTOMRIGHT", self, "BOTTOM", 0, 0)
        left.Background:SetAtlas(pageAtlas("Left"))
        self.RightPage:Show()
    end
end

---@return integer
function ForeverLootViewMixin:GetPagesShown()
    return self.isMinimized and 1 or 2
end

---@param root ForeverLoot.Node
function ForeverLootViewMixin:SetRoot(root)
    self.path = { root }
    self:Navigate()
end

---@param node ForeverLoot.Node
function ForeverLootViewMixin:Push(node)
    self.path[#self.path + 1] = node
    self:Navigate()
end

---@param index integer
function ForeverLootViewMixin:PopTo(index)
    for i = #self.path, index + 1, -1 do
        self.path[i] = nil
    end
    self:Navigate()
end

function ForeverLootViewMixin:Back()
    if #self.path > 1 then
        self:PopTo(#self.path - 1)
    end
end

---@return ForeverLoot.Node?
function ForeverLootViewMixin:GetCurrentNode()
    return self.path[#self.path]
end

---@return string
function ForeverLootViewMixin:GetTitle()
    local node = self:GetCurrentNode()
    return node and node.name or "New Tab"
end

-- Called after any path change: reset paging, redraw, and let the owner update the tab label.
function ForeverLootViewMixin:Navigate()
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
    if self.onNavigate then
        self.onNavigate(self)
    end
end

-- PagingControls calls this on its parent when the page changes.
function ForeverLootViewMixin:OnPageChanged()
    self:Refresh()
end

---@return integer
function ForeverLootViewMixin:GetRowsPerPage()
    local usable = self.LeftPage:GetHeight() - self.pageInsetTop - self.pageInsetBottom
    return math.max(1, math.floor(usable / self.rowHeight))
end

function ForeverLootViewMixin:Refresh()
    local node = self:GetCurrentNode()
    local entries = node and node.children or {}

    local rowsPerPage = self:GetRowsPerPage()
    local rowsPerSpread = rowsPerPage * self:GetPagesShown()
    local maxPages = math.max(1, math.ceil(#entries / rowsPerSpread))
    self.PagingControls:SetMaxPages(maxPages)
    local first = (self.PagingControls:GetCurrentPage() - 1) * rowsPerSpread + 1

    self:FillPage(self.LeftPage, entries, first, rowsPerPage)
    self:FillPage(self.RightPage, entries, first + rowsPerPage, self.isMinimized and 0 or rowsPerPage)
    self.PagingControls:SetShown(maxPages > 1)

    self:RefreshBreadcrumbs()
    self.BackButton:SetEnabled(#self.path > 1)
end

---@param page ForeverLoot.Page
---@param entries ForeverLoot.Node[]
---@param first integer
---@param count integer
function ForeverLootViewMixin:FillPage(page, entries, first, count)
    page.rowPool:ReleaseAll()
    local width = page:GetWidth() - self.pageInsetLeft - self.pageInsetRight
    for i = 0, count - 1 do
        local entry = entries[first + i]
        if not entry then
            break
        end
        local row = page.rowPool:Acquire() --[[@as ForeverLoot.ListRow]]
        row:SetSize(width, self.rowHeight)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", self.pageInsetLeft, -(self.pageInsetTop + i * self.rowHeight))
        row:Init(self, entry)
        row:Show()
    end
end

function ForeverLootViewMixin:RefreshBreadcrumbs()
    self.crumbPool:ReleaseAll()
    self.separatorPool:ReleaseAll()

    local layoutIndex = 1
    for i, node in ipairs(self.path) do
        if i > 1 then
            local sep = self.separatorPool:Acquire() --[[@as ForeverLoot.LayoutChild]]
            sep.layoutIndex = layoutIndex
            layoutIndex = layoutIndex + 1
            sep:Show()
        end
        local crumb = self.crumbPool:Acquire() --[[@as ForeverLoot.BreadcrumbButton]]
        crumb.layoutIndex = layoutIndex
        layoutIndex = layoutIndex + 1
        crumb:Init(self, i, node.name, i == #self.path)
        crumb:Show()
    end
    self.Breadcrumbs:MarkDirty()
end
