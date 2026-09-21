---@type string, ForeverLoot
local _, app = ...

local log = app.logger
local Data = app.data
local ITEM = Data.ITEM

-- XML `mixin=` attributes need globals; these are the only globals the addon defines besides the
-- window frame itself. They are also reachable via app.ui.* for code that has the namespace.
app.ui = app.ui or {}

----------------------------------------------------------------------------------------------------
-- List row: one template for folders, items, spells and custom entries
----------------------------------------------------------------------------------------------------

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Delay between the last keystroke in the search box and running the query.
local SEARCH_DEBOUNCE = 0.25

-- One node per DB item, shared by every query result so lists don't re-allocate 20k tables.
---@type table<integer, ForeverLoot.Node>
local itemNodes = {}

---@param itemID integer
---@return ForeverLoot.Node
local function nodeForItem(itemID)
    local node = itemNodes[itemID]
    if not node then
        node = { itemID = itemID }
        itemNodes[itemID] = node
    end
    return node
end

---@param chance number  # 0..1
---@return string
local function formatChance(chance)
    if chance >= 0.1 then
        return ("%d%%"):format(chance * 100 + 0.5)
    end
    return ("%.1f%%"):format(chance * 100)
end

-- Instance folders show their level range behind the name, "Deadmines (15-21)", colored like
-- mob levels: the low end in the orange of a hard mob, the high end in the green of an easy one.
local LEVEL_LOW = QuestDifficultyColors and QuestDifficultyColors.verydifficult or { r = 1, g = 0.5, b = 0.25 }
local LEVEL_HIGH = QuestDifficultyColors and QuestDifficultyColors.standard or { r = 0.25, g = 0.75, b = 0.25 }

local function colorHex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

-- "15-21" with the colors above; nil when the node has no level range.
---@param node ForeverLoot.Node
---@return string?
local function levelRangeText(node)
    local lo, hi = node.minLevel, node.maxLevel
    if not lo and not hi then
        return nil
    end
    local low = lo and (colorHex(LEVEL_LOW) .. lo .. "|r") or nil
    local high = hi and (colorHex(LEVEL_HIGH) .. hi .. "|r") or nil
    if low and high then
        return low .. "-" .. high
    end
    return low or high
end

---@param node ForeverLoot.Node
---@return string
local function levelRangeName(node)
    local name = node.name or "?"
    local range = levelRangeText(node)
    if not range then
        return name
    end
    return ("%s (%s)"):format(name, range)
end

-- Red for the slot / armor type of gear the character can't equip: the engine's color when
-- it defines one, otherwise the tooltip's red.
local INVALID_COLOR = INVALID_EQUIPMENT_COLOR or RED_FONT_COLOR or CreateColor(1, 0.13, 0.13)

-- The game colors the "Shoulder ... Plate" line of an item tooltip red when the character's
-- class can't use that slot / armor or weapon type. Reading that line back is exact for this
-- client (proficiencies here need not match Classic's) and needs no table of classes, but
-- filling a tooltip per row is too slow for long lists. The answer only depends on the item's
-- kind (class, subclass, slot) and the character's proficiencies, so it is scanned once per
-- kind and cached until a skill changes (new armor class at 40, a weapon skill trained).
---@type GameTooltip?
local scanTooltip

---@type table<string, boolean> kind -> slotInvalid
local slotInvalidByKind = {}
---@type table<string, boolean> kind -> typeInvalid
local typeInvalidByKind = {}

local function isRed(fontString)
    local r, g, b = fontString:GetTextColor()
    return r > 0.9 and g < 0.3 and b < 0.3
end

-- Scans one (cached) item's tooltip for the slot line.
---@param itemID integer
---@param slotText string  # the localized slot name that identifies the line
---@return boolean slotInvalid, boolean typeInvalid
local function scanEquipErrors(itemID, slotText)
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "ForeverLootScanTooltip", UIParent, "GameTooltipTemplate") --[[@as GameTooltip]]
    end
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetItemByID(itemID)
    local slotInvalid, typeInvalid = false, false
    for i = 2, scanTooltip:NumLines() do
        local left = _G["ForeverLootScanTooltipTextLeft" .. i]
        if left and left:GetText() == slotText then
            local right = _G["ForeverLootScanTooltipTextRight" .. i]
            slotInvalid, typeInvalid = isRed(left), right ~= nil and isRed(right)
            break
        end
    end
    scanTooltip:Hide()
    return slotInvalid, typeInvalid
end

-- Whether the character can equip items of this kind; `itemID` is a cached item of that kind,
-- used for the first (and only) scan.
---@param itemID integer
---@param classID integer
---@param subclassID integer
---@param equipSlot string
---@param slotText string
---@return boolean slotInvalid, boolean typeInvalid
local function equipErrors(itemID, classID, subclassID, equipSlot, slotText)
    local kind = classID .. ":" .. subclassID .. ":" .. equipSlot
    local slotInvalid = slotInvalidByKind[kind]
    if slotInvalid == nil then
        slotInvalid, typeInvalidByKind[kind] = scanEquipErrors(itemID, slotText)
        slotInvalidByKind[kind] = slotInvalid
    end
    return slotInvalid, typeInvalidByKind[kind]
end

-- Proficiencies changed: forget the answers and redraw what is open.
local skillWatcher = CreateFrame("Frame")
skillWatcher:RegisterEvent("SKILL_LINES_CHANGED")
skillWatcher:SetScript("OnEvent", function()
    wipe(slotInvalidByKind)
    wipe(typeInvalidByKind)
    local window = app.ui.mainWindow
    if window and window:IsShown() then
        window:RefreshViews()
    end
end)

-- What the bottom line says for an item: gear shows its slot and armor/weapon type
-- ("Shoulder" ... "Plate"); the armor class "Miscellaneous" (rings, necks, trinkets) says
-- nothing useful and is left blank. Anything else shows its item class and, when it adds
-- something, subclass ("Consumable" ... "Potion").
---@param classID integer
---@param subclassID integer
---@param equipSlot string  # "INVTYPE_*", "" when not equippable
---@return string slot, string type
local function itemKindTexts(classID, subclassID, equipSlot)
    local subclass = C_Item.GetItemSubClassInfo(classID, subclassID) or ""
    if equipSlot ~= "" then
        local slot = _G[equipSlot] or equipSlot
        local isMiscArmor = classID == Enum.ItemClass.Armor and subclassID == Enum.ItemArmorSubclass.Generic
        return slot, isMiscArmor and "" or subclass
    end
    local class = C_Item.GetItemClassInfo(classID) or ""
    return class, subclass ~= class and subclass or ""
end

---@class ForeverLoot.ListRow : Button
---@field Backplate Texture
---@field Icon Texture
---@field Name FontString
---@field Chance FontString
---@field Sub FontString
---@field Type FontString
---@field Arrow Texture
---@field node ForeverLoot.Node
---@field view ForeverLoot.View
---@field link? string  # item/spell link for chat linking
ForeverLootListRowMixin = {}
app.ui.ListRowMixin = ForeverLootListRowMixin

-- What a row shows; the bottom line and the chance are optional.
---@class ForeverLoot.RowDisplay
---@field name string
---@field icon? string|number
---@field quality? Enum.ItemQuality
---@field sub? string  # bottom left: slot, item class or description
---@field type? string  # bottom right: armor / weapon type
---@field subInvalid? boolean  # draw `sub` red (can't equip)
---@field typeInvalid? boolean  # draw `type` red
---@field chance? number  # 0..1, top right

---@param d ForeverLoot.RowDisplay
function ForeverLootListRowMixin:SetDisplay(d)
    self.Icon:SetTexture(d.icon or FALLBACK_ICON)
    self.Name:SetText(d.name)
    -- Items in their quality color, everything else white; both read on the dark pane.
    local color = d.quality and ITEM_QUALITY_COLORS[d.quality] or HIGHLIGHT_FONT_COLOR
    self.Name:SetTextColor(color.r, color.g, color.b)

    local hasSub = (d.sub ~= nil and d.sub ~= "") or (d.type ~= nil and d.type ~= "")
    self.Sub:SetText(d.sub or "")
    self.Sub:SetShown(hasSub)
    self.Type:SetText(d.type or "")
    self.Type:SetShown(hasSub)
    local subColor = d.subInvalid and INVALID_COLOR or HIGHLIGHT_FONT_COLOR
    self.Sub:SetTextColor(subColor.r, subColor.g, subColor.b)
    local typeColor = d.typeInvalid and INVALID_COLOR or HIGHLIGHT_FONT_COLOR
    self.Type:SetTextColor(typeColor.r, typeColor.g, typeColor.b)

    self.Chance:SetText(d.chance and formatChance(d.chance) or "")
    self.Chance:SetShown(d.chance ~= nil)

    -- With a bottom line the name sits in the upper half, otherwise it is vertically centered.
    self.Name:ClearAllPoints()
    if hasSub then
        self.Name:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 8, -2)
    else
        self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
    end
    self.Name:SetPoint("RIGHT", self.Chance, "LEFT", -4, 0)
end

---@param view ForeverLoot.View
---@param node ForeverLoot.Node
function ForeverLootListRowMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil
    self.Arrow:SetShown(app.api.IsFolder(node))

    if node.itemID then
        self:InitItem(view, node)
    elseif node.spellID then
        local info = C_Spell.GetSpellInfo(node.spellID)
        if info then
            self.link = C_Spell.GetSpellLink(node.spellID)
            self:SetDisplay({ name = info.name, icon = info.iconID, sub = node.description })
        else
            self:SetDisplay({ name = "Spell #" .. node.spellID })
        end
    else
        self:SetDisplay({
            name = levelRangeName(node),
            icon = node.icon,
            sub = node.description,
            quality = node.quality,
        })
    end
end

-- Items: the shipped DB answers immediately (name, quality, class, slot); the client's item
-- cache, when it has the item, wins because it is exact, provides the link and lets the
-- tooltip say whether the character can equip it. Uncached items are requested so that
-- arrives; GET_ITEM_INFO_RECEIVED re-renders the page. Server-side items are unknown to
-- GetItemInfoInstant until fetched, so their icon comes from the row.
---@param view ForeverLoot.View
---@param node ForeverLoot.Node
function ForeverLootListRowMixin:InitItem(view, node)
    local itemID = node.itemID --[[@as integer]]
    local name, link, quality, _, _, _, _, _, equipSlot, icon, _, classID, subclassID = C_Item.GetItemInfo(itemID)
    local cached = name ~= nil
    if cached then
        self.link = link
    else
        view:RequestItem(itemID)
        local row = Data:GetItem(itemID)
        if row then
            name = Data:GetItemName(itemID)
            quality, classID, subclassID, equipSlot = row[ITEM.QUALITY], row[ITEM.CLASS], row[ITEM.SUBCLASS], row[ITEM.SLOT]
        end
        icon = select(5, C_Item.GetItemInfoInstant(itemID)) or (row and row[ITEM.ICON])
    end

    if not name then
        self:SetDisplay({ name = "Item #" .. itemID, icon = icon, sub = RETRIEVING_ITEM_INFO or "Loading...", chance = node.chance })
        return
    end

    local slot, kind = itemKindTexts(classID, subclassID, equipSlot or "")
    local slotInvalid, typeInvalid = false, false
    if cached and equipSlot ~= "" then
        slotInvalid, typeInvalid = equipErrors(itemID, classID, subclassID, equipSlot, slot)
    end
    self:SetDisplay({
        name = name,
        icon = icon,
        quality = quality,
        sub = slot,
        type = kind,
        subInvalid = slotInvalid,
        typeInvalid = typeInvalid,
        chance = node.chance,
    })
end

---@param button string
function ForeverLootListRowMixin:OnClick(button)
    local node = self.node
    if button == "RightButton" then
        self.view:Back()
    elseif app.api.IsFolder(node) then
        self.view:Push(node)
    elseif node.onClick then
        node.onClick(node, button)
    elseif self.link then
        -- Shift-click links to chat, ctrl-click previews in the dressing room, etc.
        HandleModifiedItemClick(self.link)
    elseif node.itemID then
        -- DB item the client hasn't cached yet: ask for it, the next click will have the link.
        self.view:RequestItem(node.itemID)
        log:chat(RETRIEVING_ITEM_INFO or "Retrieving item information...")
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
    elseif app.api.IsFolder(node) then
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
-- Tile: a picture card for entries of a `display = "tiles"` folder
----------------------------------------------------------------------------------------------------

-- Clicking and hovering work exactly like a row, so those handlers are shared.
---@class ForeverLoot.Tile : Button
---@field Frame Texture
---@field Background Texture
---@field TopShade Texture
---@field BottomShade Texture
---@field Icon Texture
---@field Name FontString
---@field Info FontString
---@field InfoRight FontString
---@field node ForeverLoot.Node
---@field view ForeverLoot.View
---@field link? string
ForeverLootTileMixin = {
    OnClick = ForeverLootListRowMixin.OnClick,
    OnEnter = ForeverLootListRowMixin.OnEnter,
    OnLeave = ForeverLootListRowMixin.OnLeave,
}
app.ui.TileMixin = ForeverLootTileMixin

---@param view ForeverLoot.View
---@param node ForeverLoot.Node
function ForeverLootTileMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil

    self.Name:SetText(node.name or "?")
    local color = node.quality and ITEM_QUALITY_COLORS[node.quality] or HIGHLIGHT_FONT_COLOR
    self.Name:SetTextColor(color.r, color.g, color.b)
    self.Info:SetText(node.info or levelRangeText(node) or "")
    self.InfoRight:SetText(node.infoRight or "")

    local background = node.background
    self.Background:SetShown(background ~= nil)
    self.TopShade:SetShown(background ~= nil)
    self.BottomShade:SetShown(background ~= nil)
    self.Icon:SetShown(background == nil)
    if background then
        self.Background:SetTexture(background)
        local c = node.backgroundCoords
        if c then
            self.Background:SetTexCoord(c[1], c[2], c[3], c[4])
        else
            self.Background:SetTexCoord(0, 1, 0, 1)
        end
    else
        self.Icon:SetTexture(node.icon or FALLBACK_ICON)
    end
end

----------------------------------------------------------------------------------------------------
-- Group label (row-sized, lighter than a page header)
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.GroupLabel : Frame
---@field Text FontString
---@field Line Texture
ForeverLootGroupLabelMixin = {}
app.ui.GroupLabelMixin = ForeverLootGroupLabelMixin

---@param text string
function ForeverLootGroupLabelMixin:Init(text)
    self.Text:SetText(text)
end

----------------------------------------------------------------------------------------------------
-- Page header (section title on the character frame's category plate)
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.PageHeader : Frame
---@field Backplate Texture
---@field Text FontString
ForeverLootPageHeaderMixin = {}
app.ui.PageHeaderMixin = ForeverLootPageHeaderMixin

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
-- Search box (query toolbar)
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.SearchBox : EditBox
---@field Instructions FontString
---@field clearButton Button
---@field debounce? FunctionContainer  # C_Timer handle
ForeverLootSearchBoxMixin = {}
app.ui.SearchBoxMixin = ForeverLootSearchBoxMixin

-- Runs after SearchBoxTemplate_OnTextChanged (prepend). Typing is debounced; programmatic
-- SetText (userInput = false) never triggers a query.
---@param userInput boolean
function ForeverLootSearchBoxMixin:OnTextChanged(userInput)
    if not userInput then
        return
    end
    if self.debounce then
        self.debounce:Cancel()
    end
    self.debounce = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
        self.debounce = nil
        local view = self:GetParent() --[[@as ForeverLoot.View]]
        view:SetSearch(self:GetText())
    end)
end

----------------------------------------------------------------------------------------------------
-- View: breadcrumb bar + one page of rows
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.FilterDropdown : Frame, WowStyle1FilterDropdownMixin

---@class ForeverLoot.PagingControls : Frame, PagingControlsMixin

---@class ForeverLoot.View : Frame
---@field BackButton Button
---@field Breadcrumbs ForeverLoot.LayoutFrame
---@field HeaderDivider Texture
---@field Content ForeverLoot.Page
---@field PagingControls ForeverLoot.PagingControls
---@field SearchBox ForeverLoot.SearchBox
---@field FilterDropdown ForeverLoot.FilterDropdown
---@field ResultCount FontString
---@field queries table<ForeverLoot.Node, ForeverLoot.Query>  # filter state per query node, for this tab
---@field resultCount integer  # size of the last query result
---@field crumbPool ForeverLoot.FramePool
---@field separatorPool ForeverLoot.FramePool
---@field rowHeight number
---@field tileHeight number
---@field headerHeight number
---@field headerGap number
---@field columnGap number
---@field pages ForeverLoot.PlacedElement[][]  # layout result for the current node
---@field path ForeverLoot.Node[]
---@field onNavigate? fun(view: ForeverLoot.View)
---@field pendingItems table<integer, boolean>  # itemIDs whose info hasn't arrived yet
ForeverLootViewMixin = {}
app.ui.ViewMixin = ForeverLootViewMixin

-- The list area: pooled rows/tiles/headers/group labels are placed from its top-left corner.
---@class ForeverLoot.Page : Frame
---@field rowPool ForeverLoot.FramePool
---@field tilePool ForeverLoot.FramePool
---@field headerPool ForeverLoot.FramePool
---@field groupPool ForeverLoot.FramePool

-- What a page displays. `kind` picks the template; new element kinds plug in here
-- (BuildElements, LayoutPages, RenderPage).
---@class ForeverLoot.Element
---@field kind "header"|"group"|"row"|"tile"
---@field text? string  # header, group
---@field node? ForeverLoot.Node  # row, tile

---@class ForeverLoot.PlacedElement
---@field element ForeverLoot.Element
---@field x number
---@field y number
---@field width number
---@field height number

function ForeverLootViewMixin:OnLoad()
    self.path = {}

    local page = self.Content
    page.rowPool = CreateFramePool("Button", page, "ForeverLootListRowTemplate") --[[@as ForeverLoot.FramePool]]
    page.tilePool = CreateFramePool("Button", page, "ForeverLootTileTemplate") --[[@as ForeverLoot.FramePool]]
    page.headerPool = CreateFramePool("Frame", page, "ForeverLootPageHeaderTemplate") --[[@as ForeverLoot.FramePool]]
    page.groupPool = CreateFramePool("Frame", page, "ForeverLootGroupLabelTemplate") --[[@as ForeverLoot.FramePool]]
    self.pages = {}
    self.pendingItems = {}
    self.queries = {}
    self.resultCount = 0
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")

    -- The template's clear button sets the text programmatically (userInput = false), so the
    -- debounce never sees it; clear the query directly.
    self.SearchBox.clearButton:HookScript("OnClick", function()
        self:SetSearch("")
    end)
    self.FilterDropdown:SetupMenu(function(_, rootDescription)
        self:BuildFilterMenu(rootDescription)
    end)

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
            self:Render()
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

-- The icon of the deepest node on the path that has one (the root has none), for the tab.
---@return string|number|nil
function ForeverLootViewMixin:GetIcon()
    for i = #self.path, 1, -1 do
        local icon = self.path[i].icon
        if icon then
            return icon
        end
    end
    return nil
end

-- Called after any path change: reset paging, redraw, and let the owner update the tab label.
function ForeverLootViewMixin:Navigate()
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
    if self.onNavigate then
        self.onNavigate(self)
    end
end

-- PagingControls calls this on its parent when the page changes. The layout is unchanged,
-- so only the visible pages are redrawn.
function ForeverLootViewMixin:OnPageChanged()
    self:Render()
end

----------------------------------------------------------------------------------------------------
-- Children: static, dynamic and query folders
----------------------------------------------------------------------------------------------------

-- The entries to list for a folder node. Query folders run the view's query over the item DB.
---@param node ForeverLoot.Node
---@return ForeverLoot.Node[]
function ForeverLootViewMixin:GetChildren(node)
    if node.query then
        return self:GetQueryChildren(node)
    end
    if node.getChildren then
        local ok, result = pcall(node.getChildren, node, self)
        if ok and type(result) == "table" then
            return result
        end
        log:error("%s: getChildren failed: %s", tostring(node.name), tostring(result))
        return {}
    end
    return node.children or {}
end

-- The query state of a query folder, created on first use and kept while this tab lives.
---@param node ForeverLoot.Node
---@return ForeverLoot.Query
function ForeverLootViewMixin:GetQuery(node)
    local q = self.queries[node]
    if not q then
        q = app.query.New()
        self.queries[node] = q
    end
    return q
end

---@param node ForeverLoot.Node
---@return ForeverLoot.Node[]
function ForeverLootViewMixin:GetQueryChildren(node)
    local ids = app.query.Run(self:GetQuery(node))
    self.resultCount = #ids
    local children = {}
    for i, itemID in ipairs(ids) do
        children[i] = nodeForItem(itemID)
    end
    return children
end

-- The current node's query, or nil when it isn't a query folder.
---@return ForeverLoot.Query?, ForeverLoot.Node?
function ForeverLootViewMixin:GetCurrentQuery()
    local node = self:GetCurrentNode()
    if node and node.query then
        return self:GetQuery(node), node
    end
    return nil, node
end

-- Search/filter changed: back to page 1 and re-run.
function ForeverLootViewMixin:OnQueryChanged()
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
end

---@param text string
function ForeverLootViewMixin:SetSearch(text)
    local q = self:GetCurrentQuery()
    if q and q.search ~= text then
        q.search = text
        self:OnQueryChanged()
    end
end

---@param q ForeverLoot.Query
---@param filterID string
---@param value string|number
---@return boolean
local function hasFilterValue(q, filterID, value)
    local values = q.filters[filterID]
    if type(values) ~= "table" then
        return values == value
    end
    for _, v in ipairs(values) do
        if v == value then
            return true
        end
    end
    return false
end

-- "multi" filters: add/remove one value.
---@param q ForeverLoot.Query
---@param filterID string
---@param value string|number
function ForeverLootViewMixin:ToggleFilterValue(q, filterID, value)
    local values = q.filters[filterID]
    if type(values) ~= "table" then
        values = {}
        q.filters[filterID] = values
    end
    for i, v in ipairs(values) do
        if v == value then
            table.remove(values, i)
            self:OnQueryChanged()
            return
        end
    end
    values[#values + 1] = value
    self:OnQueryChanged()
end

-- "single" filters: set one value (nil = any).
---@param q ForeverLoot.Query
---@param filterID string
---@param value string|number|nil
function ForeverLootViewMixin:SetFilterValue(q, filterID, value)
    if q.filters[filterID] ~= value then
        q.filters[filterID] = value
        self:OnQueryChanged()
    end
end

---@param q ForeverLoot.Query
---@param sort ForeverLoot.QuerySort
function ForeverLootViewMixin:SetSort(q, sort)
    if q.sort ~= sort then
        q.sort = sort
        self:OnQueryChanged()
    end
end

-- Clears filters and sort but keeps the search text (that's what the search box's X is for).
---@param q ForeverLoot.Query
function ForeverLootViewMixin:ResetFilters(q)
    wipe(q.filters)
    q.sort = "name"
    self:OnQueryChanged()
end

local SORT_OPTIONS = {
    { value = "name", label = NAME or "Name" },
    { value = "ilvl", label = ITEM_LEVEL_ABBR or "Item Level" },
    { value = "quality", label = QUALITY or "Quality" },
    { value = "id", label = "ID" },
}
local SCROLL_AFTER = 20 -- options; longer submenus scroll

-- Generator for FilterDropdown (Blizzard_Menu): one submenu per registered filter, sort, reset.
-- Handlers return MenuResponse.Refresh so the menu stays open and re-checks its boxes.
---@param root RootMenuDescriptionProxy
function ForeverLootViewMixin:BuildFilterMenu(root)
    local q = self:GetCurrentQuery()
    if not q then
        root:CreateTitle("No item list")
        return
    end

    for _, def in ipairs(app.filters:GetAll()) do
        local submenu = root:CreateButton(def.name)
        local options = app.filters:GetOptions(def.id)
        if def.kind == "multi" then
            for _, option in ipairs(options) do
                submenu:CreateCheckbox(option.label, function()
                    return hasFilterValue(q, def.id, option.value)
                end, function()
                    self:ToggleFilterValue(q, def.id, option.value)
                    return MenuResponse.Refresh
                end)
            end
        else
            submenu:CreateRadio(ALL or "Any", function()
                return q.filters[def.id] == nil
            end, function()
                self:SetFilterValue(q, def.id, nil)
                return MenuResponse.Refresh
            end)
            for _, option in ipairs(options) do
                submenu:CreateRadio(option.label, function()
                    return q.filters[def.id] == option.value
                end, function()
                    self:SetFilterValue(q, def.id, option.value)
                    return MenuResponse.Refresh
                end)
            end
        end
        if #options > SCROLL_AFTER then
            submenu:SetScrollMode(20 * SCROLL_AFTER)
        end
    end

    root:CreateDivider()
    local sortMenu = root:CreateButton("Sort by")
    for _, option in ipairs(SORT_OPTIONS) do
        sortMenu:CreateRadio(option.label, function()
            return (q.sort or "name") == option.value
        end, function()
            self:SetSort(q, option.value)
            return MenuResponse.Refresh
        end)
    end

    root:CreateDivider()
    root:CreateButton(RESET or "Reset", function()
        self:ResetFilters(q)
        return MenuResponse.Refresh
    end)
end

-- Shows the search box / filter button on query folders and syncs them with the query.
function ForeverLootViewMixin:UpdateToolbar()
    local q = self:GetCurrentQuery()
    local shown = q ~= nil
    self.SearchBox:SetShown(shown)
    self.FilterDropdown:SetShown(shown)
    self.ResultCount:SetShown(shown)
    if not q then
        return
    end
    -- Sync the box to the query unless the user is typing (the debounce hasn't fired yet).
    if not self.SearchBox:HasFocus() and self.SearchBox:GetText() ~= q.search then
        self.SearchBox:SetText(q.search or "") -- userInput = false: no query re-run
    end
    self.ResultCount:SetText(("%d items"):format(self.resultCount))
end

-- Whether a folder draws its entries as picture tiles instead of rows.
---@param node ForeverLoot.Node?
---@return boolean
local function usesTiles(node)
    return node ~= nil and node.display == "tiles"
end

-- Columns for the current list. Defined by the collection itself (`node.columns`): rows
-- default to one full-width column (max 2), tiles to three (max 4).
---@param node ForeverLoot.Node?
---@return integer
function ForeverLootViewMixin:GetColumns(node)
    local columns = node and node.columns
    if usesTiles(node) then
        return math.max(1, math.min(4, columns or 3))
    end
    columns = columns or 1
    return math.max(1, math.min(2, columns))
end

-- Full redraw: rebuild the element list and page layout for the current node, then render.
-- Called on navigation, query changes, page-size changes and profile refreshes; page flips
-- and item-info arrivals only need Render().
function ForeverLootViewMixin:Refresh()
    local node = self:GetCurrentNode()
    self.pages = self:LayoutPages(self:BuildElements(node), self:GetColumns(node))

    local maxPages = math.max(1, #self.pages)
    -- SetMaxPages may clamp the current page, which calls OnPageChanged -> Render.
    self.PagingControls:SetMaxPages(maxPages)
    self.PagingControls:SetShown(maxPages > 1)

    self:Render()
end

-- Draws the current page plus the chrome around it.
function ForeverLootViewMixin:Render()
    self:RenderPage(self.Content, self.pages[self.PagingControls:GetCurrentPage()])

    self:RefreshBreadcrumbs()
    self:UpdateToolbar()
    self.BackButton:SetEnabled(#self.path > 1)
end

-- Turns the current node into the flat list of things to draw: a title header, then its
-- children. `header` nodes become section headers, `group` nodes become group labels (followed
-- by their `items`), everything else a row (or a tile in a `display = "tiles"` folder). If the
-- folder has `groupBy`, runs of plain entries are bucketed into auto groups; explicit
-- headers/groups are kept as written.
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
    local entryKind = usesTiles(node) and "tile" or "row"
    local pending = {}

    local function addRows(entries)
        for _, entry in ipairs(entries) do
            elements[#elements + 1] = { kind = entryKind, node = entry }
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

    for _, child in ipairs(self:GetChildren(node)) do
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

-- Flows elements top-to-bottom into as many pages as needed. Headers span the full width and
-- start a new line; rows and tiles fill `columns` columns left to right (tiles are taller and
-- get a little air between lines). A header never ends a page.
---@param elements ForeverLoot.Element[]
---@param columns integer
---@return ForeverLoot.PlacedElement[][]
function ForeverLootViewMixin:LayoutPages(elements, columns)
    local pages = {}
    local page, y, column = {}, 0, 0
    local pageWidth, pageHeight = self.Content:GetSize()
    local columnWidth = (pageWidth - self.columnGap * (columns - 1)) / columns
    local lineHeight = self.rowHeight -- of the line being filled

    local function newPage()
        if #page > 0 then
            pages[#pages + 1] = page
        end
        page, y, column = {}, 0, 0
    end

    local function newLine()
        if column > 0 then
            y = y + lineHeight
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
            local height = element.kind == "tile" and self.tileHeight or self.rowHeight
            local gap = element.kind == "tile" and self.columnGap or 0
            if column == 0 then
                if y + height > pageHeight then
                    newPage()
                end
                lineHeight = height + gap
            end
            place(element, column * (columnWidth + self.columnGap), columnWidth, height)
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
    page.tilePool:ReleaseAll()
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
        elseif element.kind == "tile" then
            frame = page.tilePool:Acquire() --[[@as ForeverLoot.Tile]]
            frame:Init(self, element.node)
        else
            frame = page.rowPool:Acquire() --[[@as ForeverLoot.ListRow]]
            frame:Init(self, element.node)
        end
        frame:SetSize(item.width, item.height)
        frame:SetPoint("TOPLEFT", page, "TOPLEFT", item.x, -item.y)
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
