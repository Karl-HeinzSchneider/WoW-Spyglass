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
-- List row: one template for folders, items, spells and custom entries
----------------------------------------------------------------------------------------------------

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

---@class ForeverLoot.ListRow : Button
---@field Icon Texture
---@field Name FontString
---@field Sub FontString
---@field Arrow Texture
---@field node ForeverLoot.Node
---@field view ForeverLoot.View
---@field link? string  # item/spell link for chat linking
ForeverLootListRowMixin = {}
app.ui.ListRowMixin = ForeverLootListRowMixin

---@param name string
---@param icon string|number|nil
---@param sub string?
---@param quality Enum.ItemQuality?
function ForeverLootListRowMixin:SetDisplay(name, icon, sub, quality)
    self.Icon:SetTexture(icon or FALLBACK_ICON)
    self.Name:SetText(name)
    self.Sub:SetText(sub or "")
    self.Sub:SetShown(sub ~= nil and sub ~= "")

    -- With a second line the name sits in the upper half, otherwise it is vertically centered.
    self.Name:ClearAllPoints()
    if sub and sub ~= "" then
        self.Name:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 8, -2)
    else
        self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
    end
    self.Name:SetPoint("RIGHT", self.Arrow, "LEFT", -4, 0)

    local color = quality and ITEM_QUALITY_COLORS[quality]
    if color then
        self.Name:SetTextColor(color.r, color.g, color.b)
    else
        self.Name:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
end

---@param view ForeverLoot.View
---@param node ForeverLoot.Node
function ForeverLootListRowMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil
    self.Arrow:SetShown(node.children ~= nil)

    if node.itemID then
        local name, link, quality, itemLevel, _, _, _, _, _, icon = C_Item.GetItemInfo(node.itemID)
        if name then
            self.link = link
            self:SetDisplay(name, icon, itemLevel and (ITEM_LEVEL or "Item Level %d"):format(itemLevel) or nil, quality)
        else
            -- Not cached yet: show a stand-in and redraw when GET_ITEM_INFO_RECEIVED arrives.
            local _, _, _, _, instantIcon = C_Item.GetItemInfoInstant(node.itemID)
            self:SetDisplay("Item #" .. node.itemID, instantIcon, RETRIEVING_ITEM_INFO or "Loading...", nil)
            view:RequestItem(node.itemID)
        end
    elseif node.spellID then
        local info = C_Spell.GetSpellInfo(node.spellID)
        if info then
            self.link = C_Spell.GetSpellLink(node.spellID)
            self:SetDisplay(info.name, info.iconID, node.description, nil)
        else
            self:SetDisplay("Spell #" .. node.spellID, nil, nil, nil)
        end
    else
        self:SetDisplay(node.name or "?", node.icon, node.description, node.quality)
    end
end

---@param button string
function ForeverLootListRowMixin:OnClick(button)
    local node = self.node
    if button == "RightButton" then
        self.view:Back()
    elseif node.children then
        self.view:Push(node)
    elseif node.onClick then
        node.onClick(node, button)
    elseif self.link then
        -- Shift-click links to chat, ctrl-click previews in the dressing room, etc.
        HandleModifiedItemClick(self.link)
    else
        log:debug("Clicked %s", node.name or tostring(node.itemID or node.spellID))
    end
end

function ForeverLootListRowMixin:OnEnter()
    local node = self.node
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if node.itemID then
        GameTooltip:SetItemByID(node.itemID)
    elseif node.spellID then
        GameTooltip:SetSpellByID(node.spellID)
    elseif node.children then
        GameTooltip:AddLine(node.name or "")
        if node.description then
            GameTooltip:AddLine(node.description, 1, 1, 1, true)
        end
    else
        GameTooltip:AddLine(node.name or "")
        if node.description then
            GameTooltip:AddLine(node.description, 1, 1, 1, true)
        end
        for _, line in ipairs(node.tooltip or {}) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
end

function ForeverLootListRowMixin:OnLeave()
    GameTooltip:Hide()
end

----------------------------------------------------------------------------------------------------
-- Group label (row-sized, lighter than a page header)
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.GroupLabel : Frame
---@field Text FontString
---@field Line Texture
ForeverLootGroupLabelMixin = {}
app.ui.GroupLabelMixin = ForeverLootGroupLabelMixin

function ForeverLootGroupLabelMixin:OnLoad()
    local color = SPELLBOOK_FONT_COLOR or CreateColor(0.25, 0.16, 0.06)
    self.Text:SetTextColor(color:GetRGB())
end

---@param text string
function ForeverLootGroupLabelMixin:Init(text)
    self.Text:SetText(text)
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
---@field pendingItems table<integer, boolean>  # itemIDs whose info hasn't arrived yet
ForeverLootViewMixin = {}
app.ui.ViewMixin = ForeverLootViewMixin

---@class ForeverLoot.Page : Frame
---@field Background Texture
---@field rowPool ForeverLoot.FramePool
---@field headerPool ForeverLoot.FramePool
---@field groupPool ForeverLoot.FramePool
---@field insetLeft number
---@field insetRight number
---@field insetTop number
---@field insetBottom number

-- What a page displays. `kind` picks the template; new element kinds plug in here
-- (BuildElements, LayoutPages, RenderPage).
---@class ForeverLoot.Element
---@field kind "header"|"group"|"row"
---@field text? string  # header, group
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
        page.groupPool = CreateFramePool("Frame", page, "ForeverLootGroupLabelTemplate") --[[@as ForeverLoot.FramePool]]
    end
    self.pages = {}
    self.pendingItems = {}
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")

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

-- Item data arrives asynchronously; redraw once something we're showing has loaded.
---@param event string
---@param itemID integer
function ForeverLootViewMixin:OnEvent(event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" and self.pendingItems[itemID] then
        self.pendingItems[itemID] = nil
        if self:IsShown() then
            self:Refresh()
        end
    end
end

---@param itemID integer
function ForeverLootViewMixin:RequestItem(itemID)
    if not self.pendingItems[itemID] then
        self.pendingItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
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
-- children. `header` nodes become section headers, `group` nodes become group labels (followed
-- by their `items`), everything else a row. If the folder has `groupBy`, runs of plain entries
-- are bucketed into auto groups; explicit headers/groups are kept as written.
---@param node ForeverLoot.Node?
---@return ForeverLoot.Element[]
function ForeverLootViewMixin:BuildElements(node)
    local elements = {}
    if not node then
        return elements
    end
    elements[#elements + 1] = { kind = "header", text = node.name }

    local groupBy = node.groupBy
    local keyFn = type(groupBy) == "function" and groupBy or nil
    local pending = {}

    local function addRows(entries)
        for _, entry in ipairs(entries) do
            elements[#elements + 1] = { kind = "row", node = entry }
        end
    end

    -- Emit the plain entries collected so far, auto-grouped if the folder asks for it.
    local function flush()
        if #pending == 0 then
            return
        end
        if groupBy then
            for _, group in ipairs(app.api.GroupEntries(pending, keyFn)) do
                elements[#elements + 1] = { kind = "group", text = group.label }
                addRows(group.entries)
            end
        else
            addRows(pending)
        end
        pending = {}
    end

    for _, child in ipairs(node.children or {}) do
        if child.header then
            flush()
            elements[#elements + 1] = { kind = "header", text = child.header }
        elseif child.group then
            flush()
            elements[#elements + 1] = { kind = "group", text = child.group }
            addRows(child.items or {})
        else
            pending[#pending + 1] = child
        end
    end
    flush()
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
        elseif element.kind == "group" then
            -- Row-sized, full width, on its own line, and never orphaned at a page bottom.
            newLine()
            if y > 0 and y + self.rowHeight * 2 > pageHeight then
                newPage()
            end
            place(element, 0, pageWidth, self.rowHeight)
            y = y + self.rowHeight
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
    page.groupPool:ReleaseAll()
    for _, item in ipairs(placed or {}) do
        local element = item.element
        local frame
        if element.kind == "header" then
            frame = page.headerPool:Acquire() --[[@as ForeverLoot.PageHeader]]
            frame:Init(element.text or "")
        elseif element.kind == "group" then
            frame = page.groupPool:Acquire() --[[@as ForeverLoot.GroupLabel]]
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
