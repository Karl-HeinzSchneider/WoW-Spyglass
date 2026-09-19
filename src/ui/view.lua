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

---@param button string
function ForeverLootListRowMixin:OnClick(button)
    if button == "RightButton" then
        self.view:Back()
    elseif self.node.children then
        self.view:Push(self.node)
    else
        -- No item logic yet; just prove the click arrives.
        log:chat("Clicked %s", self.node.name or tostring(self.node.itemID))
    end
end

----------------------------------------------------------------------------------------------------
-- Page header (section title with backplate and divider, like the spellbook)
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.PageHeader : Frame
---@field Backplate Texture
---@field Text FontString
---@field Border Texture
ForeverLootPageHeaderMixin = {}
app.ui.PageHeaderMixin = ForeverLootPageHeaderMixin

function ForeverLootPageHeaderMixin:OnLoad()
    -- SPELLBOOK_FONT_COLOR is engine-defined; fall back to the same dark brown if it's missing.
    local color = SPELLBOOK_FONT_COLOR or CreateColor(0.25, 0.16, 0.06)
    self.Text:SetTextColor(color:GetRGB())
end

---@param text string
function ForeverLootPageHeaderMixin:Init(text)
    self.Text:SetText(text)
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
---@field headerHeight number
---@field headerGap number
---@field columnGap number
---@field pages ForeverLoot.PlacedElement[][]  # layout result for the current node
---@field path ForeverLoot.Node[]
---@field onNavigate? fun(view: ForeverLoot.View)
---@field isMinimized boolean  # one page (true) or the two-page spread (false)
ForeverLootViewMixin = {}
app.ui.ViewMixin = ForeverLootViewMixin

---@class ForeverLoot.Page : Frame
---@field Background Texture
---@field rowPool ForeverLoot.FramePool
---@field headerPool ForeverLoot.FramePool
---@field insetLeft number
---@field insetRight number
---@field insetTop number
---@field insetBottom number

-- What a page displays. `kind` picks the template; new element kinds plug in here.
---@class ForeverLoot.Element
---@field kind "header"|"row"
---@field text? string  # header
---@field node? ForeverLoot.Node  # row

---@class ForeverLoot.PlacedElement
---@field element ForeverLoot.Element
---@field x number
---@field y number
---@field width number
---@field height number

function ForeverLootViewMixin:OnLoad()
    self.path = {}
    self.isMinimized = true

    self.RightPage.Background:SetAtlas(pageAtlas("Right"))
    self:ApplyPageLayout()
    for _, page in ipairs({ self.LeftPage, self.RightPage }) do
        page.rowPool = CreateFramePool("Button", page, "ForeverLootListRowTemplate") --[[@as ForeverLoot.FramePool]]
        page.headerPool = CreateFramePool("Frame", page, "ForeverLootPageHeaderTemplate") --[[@as ForeverLoot.FramePool]]
    end
    self.pages = {}

    self.crumbPool = CreateFramePool("Button", self.Breadcrumbs, "ForeverLootBreadcrumbButtonTemplate") --[[@as ForeverLoot.FramePool]]
    self.separatorPool = CreateFramePool("Frame", self.Breadcrumbs, "ForeverLootBreadcrumbSeparatorTemplate") --[[@as ForeverLoot.FramePool]]

    self.BackButton:SetScript("OnClick", function()
        self:Back()
    end)
end

function ForeverLootViewMixin:OnShow()
    self:Refresh()
end

-- Wheel up = previous page, wheel down = next page (PagingControls handles the clamping).
---@param delta number
function ForeverLootViewMixin:OnMouseWheel(delta)
    self.PagingControls:OnMouseWheel(delta)
end

-- Right-click on empty page space goes one level back, like closing a folder.
---@param button string
function ForeverLootViewMixin:OnMouseUp(button)
    if button == "RightButton" then
        self:Back()
    end
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

-- Columns per page for the current list. Defined by the collection itself (`node.columns`);
-- one full-width column when unset.
---@param node ForeverLoot.Node?
---@return integer
function ForeverLootViewMixin:GetColumns(node)
    local columns = node and node.columns or 1
    return math.max(1, math.min(2, columns))
end

function ForeverLootViewMixin:Refresh()
    local node = self:GetCurrentNode()
    self.pages = self:LayoutPages(self:BuildElements(node), self:GetColumns(node))

    local pagesShown = self:GetPagesShown()
    local maxPages = math.max(1, math.ceil(#self.pages / pagesShown))
    self.PagingControls:SetMaxPages(maxPages)
    local first = (self.PagingControls:GetCurrentPage() - 1) * pagesShown + 1

    self:RenderPage(self.LeftPage, self.pages[first])
    self:RenderPage(self.RightPage, not self.isMinimized and self.pages[first + 1] or nil)
    self.PagingControls:SetShown(maxPages > 1)

    self:RefreshBreadcrumbs()
    self.BackButton:SetEnabled(#self.path > 1)
end

-- Turns the current node into the flat list of things to draw: a title header, then its
-- children, where `header` nodes become section headers and everything else a row.
---@param node ForeverLoot.Node?
---@return ForeverLoot.Element[]
function ForeverLootViewMixin:BuildElements(node)
    local elements = {}
    if not node then
        return elements
    end
    elements[#elements + 1] = { kind = "header", text = node.name }
    for _, child in ipairs(node.children or {}) do
        if child.header then
            elements[#elements + 1] = { kind = "header", text = child.header }
        else
            elements[#elements + 1] = { kind = "row", node = child }
        end
    end
    return elements
end

-- The page frame that will display page number `index` (1-based) in the current mode.
---@param index integer
---@return ForeverLoot.Page
function ForeverLootViewMixin:GetPageSlot(index)
    if self.isMinimized or index % 2 == 1 then
        return self.LeftPage
    end
    return self.RightPage
end

-- Usable content size of a page frame, inside its insets.
---@param page ForeverLoot.Page
---@return number width, number height
local function contentSize(page)
    return page:GetWidth() - page.insetLeft - page.insetRight, page:GetHeight() - page.insetTop - page.insetBottom
end

-- Flows elements top-to-bottom into as many pages as needed. Headers span the full width and
-- start a new line; rows fill `columns` columns left to right. A header never ends a page.
-- Left and right pages may have different insets, so each page is measured individually.
---@param elements ForeverLoot.Element[]
---@param columns integer
---@return ForeverLoot.PlacedElement[][]
function ForeverLootViewMixin:LayoutPages(elements, columns)
    local pages = {}
    local page, y, column = {}, 0, 0
    local pageWidth, pageHeight, columnWidth

    local function measure()
        pageWidth, pageHeight = contentSize(self:GetPageSlot(#pages + 1))
        columnWidth = (pageWidth - self.columnGap * (columns - 1)) / columns
    end

    local function newPage()
        if #page > 0 then
            pages[#pages + 1] = page
        end
        page, y, column = {}, 0, 0
        measure()
    end
    measure()

    local function newLine()
        if column > 0 then
            y = y + self.rowHeight
            column = 0
        end
    end

    local function place(element, x, width, height)
        page[#page + 1] = { element = element, x = x, y = y, width = width, height = height }
    end

    for _, element in ipairs(elements) do
        if element.kind == "header" then
            newLine()
            local needed = self.headerHeight + self.headerGap + self.rowHeight
            if y > 0 and y + needed > pageHeight then
                newPage()
            end
            place(element, 0, pageWidth, self.headerHeight)
            y = y + self.headerHeight + self.headerGap
        else
            if column == 0 and y + self.rowHeight > pageHeight then
                newPage()
            end
            place(element, column * (columnWidth + self.columnGap), columnWidth, self.rowHeight)
            column = column + 1
            if column >= columns then
                newLine()
            end
        end
    end
    newLine()
    newPage()
    return pages
end

---@param page ForeverLoot.Page
---@param placed ForeverLoot.PlacedElement[]?
function ForeverLootViewMixin:RenderPage(page, placed)
    page.rowPool:ReleaseAll()
    page.headerPool:ReleaseAll()
    for _, item in ipairs(placed or {}) do
        local element = item.element
        local frame
        if element.kind == "header" then
            frame = page.headerPool:Acquire() --[[@as ForeverLoot.PageHeader]]
            frame:Init(element.text or "")
        else
            frame = page.rowPool:Acquire() --[[@as ForeverLoot.ListRow]]
            frame:Init(self, element.node)
        end
        frame:SetSize(item.width, item.height)
        frame:SetPoint("TOPLEFT", page, "TOPLEFT", page.insetLeft + item.x, -(page.insetTop + item.y))
        frame:Show()
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
