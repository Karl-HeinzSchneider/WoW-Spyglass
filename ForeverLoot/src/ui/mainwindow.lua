---@type string, ForeverLoot
local appName, app = ...

local log = app.logger
app.ui = app.ui or {}

-- The addon's icon, the TOC's `## IconTexture` (a fileID): the window portrait, and the tab of a
-- view with no icon anywhere on its path (the root node carries the same one, see GetRootNode).
local PORTRAIT_ICON = 8197077
-- The "+" tab: a plus in a ring, drawn at atlas proportions instead of filling the tab.
local NEW_TAB_ATLAS = "communities-icon-addgroupplus"
local NEW_TAB_ICON_SIZE = 36
-- Vertical gap between side tabs, as in CharacterFrameMixin:UpdateTabLayout.
local TAB_SPACING = -2

----------------------------------------------------------------------------------------------------
-- Side tab: one per open view, plus the "+" tab
----------------------------------------------------------------------------------------------------

-- LargeSideTabButtonTemplate is a Frame, not a Button: clicks arrive through the mixin's
-- custom mouse-up handler, which is what tells left from right clicks.
---@class ForeverLoot.SideTab : Frame, SidePanelTabButtonMixin
---@field Icon Texture
---@field tooltipText? string
---@field flView? ForeverLoot.View  # nil on the "+" tab
ForeverLootSideTabMixin = {}
app.ui.SideTabMixin = ForeverLootSideTabMixin

function ForeverLootSideTabMixin:OnLoad()
    SidePanelTabButtonMixin.OnLoad(self)
    self:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if upInside then
            local window = self:GetParent():GetParent() --[[@as ForeverLoot.MainWindow]]
            window:OnTabClicked(self, button)
        end
    end)
end

-- Shows a view: its icon fills the tab interior (fillToInterior), tooltip is the view title.
---@param view ForeverLoot.View
function ForeverLootSideTabMixin:SetView(view)
    self.flView = view
    self.Icon:SetTexture(view:GetIcon() or PORTRAIT_ICON)
    -- Restores the interior tex coords/size; the pooled frame may have been the "+" tab.
    self:SetFillToInterior(true)
    self.tooltipText = view:GetTitle()
end

function ForeverLootSideTabMixin:SetNewTab()
    self.flView = nil
    -- SetFillToInterior(true) would clobber the atlas tex coords, so this tab opts out of it.
    self:SetFillToInterior(false)
    self.Icon:SetAtlas(NEW_TAB_ATLAS)
    self.Icon:SetSize(NEW_TAB_ICON_SIZE, NEW_TAB_ICON_SIZE)
    self.tooltipText = "Open a new tab"
end

-- SidePanelTabButtonMixin:OnEnter calls this; view tabs add the close hint under the title.
function ForeverLootSideTabMixin:GetTooltipTextSetupFunction()
    if not self.flView then
        return nil
    end
    return function(tooltip)
        tooltip:SetText(self.tooltipText)
        tooltip:AddLine("Right-click to close", 1, 1, 1)
        return true
    end
end

----------------------------------------------------------------------------------------------------
-- Main window
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.RightPane : Frame
---@field Title FontString
---@field Divider Frame

---@class ForeverLoot.MainWindow : Frame, PortraitFrameMixin
---@field CloseButton Button
---@field LeftPane Frame
---@field RightPane ForeverLoot.RightPane
---@field Tabs Frame
---@field views ForeverLoot.View[]
---@field viewPool ForeverLoot.FramePool
---@field tabPool ForeverLoot.FramePool
---@field tabs ForeverLoot.SideTab[]  # in display order; the last one is the "+" tab
---@field viewToTab table<ForeverLoot.View, ForeverLoot.SideTab>
---@field selectedView? ForeverLoot.View
ForeverLootMainWindowMixin = {}
app.ui.MainWindowMixin = ForeverLootMainWindowMixin

function ForeverLootMainWindowMixin:OnLoad()
    self:SetTitle(appName)
    self:SetPortraitToAsset(PORTRAIT_ICON)

    -- ESC closes the window.
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")

    self.views = {}
    self.tabs = {}
    self.viewToTab = {}
    self.viewPool = CreateFramePool("Frame", self.LeftPane, "ForeverLootViewTemplate") --[[@as ForeverLoot.FramePool]]
    self.tabPool = CreateFramePool("Frame", self.Tabs, "ForeverLootSideTabTemplate") --[[@as ForeverLoot.FramePool]]

    self:OpenView()
    app.ui.mainWindow = self

    app.api.RegisterCallback(self, "OnModulesChanged", "OnModulesChanged")
    app.api.RegisterCallback(self, "OnDataChanged", "OnDataChanged")
    app.api.RegisterCallback(self, "OnFiltersChanged", "OnDataChanged")
end

-- Item DB or filter set changed (a late-loading addon added data): redraw what's visible.
function ForeverLootMainWindowMixin:OnDataChanged()
    if self:IsShown() then
        self:RefreshViews()
    end
end

-- A module was registered/unregistered: swap in the new root. Views sitting at the root are
-- refreshed; views deeper in a tree keep browsing the nodes they already hold.
function ForeverLootMainWindowMixin:OnModulesChanged()
    local root = app.api:GetRootNode()
    for _, view in ipairs(self.views) do
        if #view.path <= 1 then
            view:SetRoot(root)
        else
            view.path[1] = root
        end
    end
end

function ForeverLootMainWindowMixin:OnShow()
    self:RestorePosition()
end

----------------------------------------------------------------------------------------------------
-- Position (drag to move, persisted per profile)
----------------------------------------------------------------------------------------------------

function ForeverLootMainWindowMixin:OnDragStart()
    self:StartMoving()
end

function ForeverLootMainWindowMixin:OnDragStop()
    self:StopMovingOrSizing()
    self:SavePosition()
end

function ForeverLootMainWindowMixin:SavePosition()
    if not app.db then
        return
    end
    local point, _, _, x, y = self:GetPoint(1)
    local window = app.db.profile.window
    window.point, window.x, window.y = point, x, y
end

function ForeverLootMainWindowMixin:RestorePosition()
    if not app.db then
        return
    end
    local window = app.db.profile.window
    self:ClearAllPoints()
    self:SetPoint(window.point, UIParent, window.point, window.x, window.y)
end

----------------------------------------------------------------------------------------------------
-- Views and tabs
----------------------------------------------------------------------------------------------------

---@return ForeverLoot.View
function ForeverLootMainWindowMixin:OpenView()
    local view = self.viewPool:Acquire() --[[@as ForeverLoot.View]]
    view:SetAllPoints(self.LeftPane)
    view.onNavigate = function(v)
        self:UpdateTab(v)
    end
    view:SetRoot(app.api:GetRootNode())
    self.views[#self.views + 1] = view

    self:RebuildTabs()
    self:SelectView(view)
    return view
end

---@param view ForeverLoot.View
function ForeverLootMainWindowMixin:CloseView(view)
    if #self.views <= 1 then
        log:debug("Refusing to close the last view")
        return
    end
    local index = tIndexOf(self.views, view)
    if not index then
        return
    end

    local wasSelected = self.selectedView == view
    tremove(self.views, index)
    self.viewPool:Release(view)
    if wasSelected then
        self.selectedView = nil
    end

    self:RebuildTabs()
    if wasSelected then
        self:SelectView(self.views[math.min(index, #self.views)])
    end
end

-- Lays the tab strip out from scratch: one tab per view in order, then the "+" tab, stacked
-- top to bottom like CharacterFrameMixin:UpdateTabLayout.
function ForeverLootMainWindowMixin:RebuildTabs()
    self.tabPool:ReleaseAll()
    wipe(self.tabs)
    wipe(self.viewToTab)

    local function add(setup)
        local tab = self.tabPool:Acquire() --[[@as ForeverLoot.SideTab]]
        setup(tab)
        local previous = self.tabs[#self.tabs]
        if previous then
            tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, TAB_SPACING)
        else
            tab:SetPoint("TOPLEFT", self.Tabs, "TOPLEFT", 0, 0)
        end
        tab:Show()
        self.tabs[#self.tabs + 1] = tab
        return tab
    end

    for _, view in ipairs(self.views) do
        self.viewToTab[view] = add(function(tab)
            tab:SetView(view)
            tab:SetChecked(view == self.selectedView)
        end)
    end
    add(function(tab)
        tab:SetNewTab()
        tab:SetChecked(false)
    end)
end

-- Shows one view and marks its tab; the others are hidden.
---@param view ForeverLoot.View
function ForeverLootMainWindowMixin:SelectView(view)
    self.selectedView = view
    for _, v in ipairs(self.views) do
        v:SetShown(v == view)
        local tab = self.viewToTab[v]
        if tab then
            tab:SetChecked(v == view)
        end
    end
end

-- Left-click selects (or opens, on the "+" tab), right-click closes.
---@param tab ForeverLoot.SideTab
---@param button string
function ForeverLootMainWindowMixin:OnTabClicked(tab, button)
    local view = tab.flView
    if not view then
        if button == "LeftButton" then
            self:OpenView()
        end
    elseif button == "RightButton" then
        self:CloseView(view)
    elseif button == "LeftButton" then
        self:SelectView(view)
    end
end

-- The view navigated: its tab shows the icon and title of where it is now.
---@param view ForeverLoot.View
function ForeverLootMainWindowMixin:UpdateTab(view)
    local tab = self.viewToTab[view]
    if tab then
        tab:SetView(view)
    end
end

----------------------------------------------------------------------------------------------------
-- Public helpers
----------------------------------------------------------------------------------------------------

function ForeverLootMainWindowMixin:Toggle()
    self:SetShown(not self:IsShown())
end

-- Redraw every open view (layout settings changed, profile switched, ...).
function ForeverLootMainWindowMixin:RefreshViews()
    for _, view in ipairs(self.views) do
        view:Refresh()
    end
end
