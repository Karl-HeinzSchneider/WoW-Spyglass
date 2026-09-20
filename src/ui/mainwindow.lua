---@type string, ForeverLoot
local appName, app = ...

local log = app.logger
app.ui = app.ui or {}

local PORTRAIT_ICON = "Interface\\Icons\\INV_Misc_Bag_10"
local NEW_TAB_LABEL = "+"

---@class ForeverLoot.TabSystem : Frame, TabSystemMixin, LayoutMixin

-- A pooled TabSystemButtonTemplate button with our close-on-right-click extras.
---@class ForeverLoot.TabButton : Button, TabSystemButtonMixin
---@field flView? ForeverLoot.View
---@field flCloseHooked? boolean

---@class ForeverLoot.MaxMinButton : Frame, MaximizeMinimizeButtonFrameMixin
---@field MaximizeButton Button
---@field MinimizeButton Button

---@class ForeverLoot.MainWindow : Frame, PortraitFrameMixin, TabSystemOwnerMixin
---@field TabSystem ForeverLoot.TabSystem
---@field ViewContainer Frame
---@field MaximizeMinimizeButton ForeverLoot.MaxMinButton
---@field minimizedWidth number
---@field maximizedWidth number
---@field bookMinimizedWidth number
---@field bookMaximizedWidth number
---@field isMinimized boolean
---@field views ForeverLoot.View[]
---@field viewPool ForeverLoot.FramePool
---@field viewToTabID table<ForeverLoot.View, integer>
---@field newTabID integer
---@field internalTabTracker table  # TabSystemTrackerMixin instance created by TabSystemOwnerMixin.OnLoad
ForeverLootMainWindowMixin = {}
app.ui.MainWindowMixin = ForeverLootMainWindowMixin

function ForeverLootMainWindowMixin:OnLoad()
    -- Both inherited templates route <OnLoad method="OnLoad"/> here, so chain them by hand.
    if PortraitFrameTemplateMixin and PortraitFrameTemplateMixin.OnLoad then
        PortraitFrameTemplateMixin.OnLoad(self)
    end
    TabSystemOwnerMixin.OnLoad(self)

    self:SetTabSystem(self.TabSystem)
    self:SetTitle(appName)
    self:SetPortraitToAsset(PORTRAIT_ICON)

    -- ESC closes the window.
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")

    self.MaximizeMinimizeButton:SetOnMinimizedCallback(function()
        self:SetMinimized(true)
    end)
    self.MaximizeMinimizeButton:SetOnMaximizedCallback(function()
        self:SetMinimized(false)
    end)

    self.views = {}
    self.viewToTabID = {}
    self.viewPool = CreateFramePool("Frame", self.ViewContainer, "ForeverLootViewTemplate") --[[@as ForeverLoot.FramePool]]

    self:SetMinimized(true)
    self:OpenView()
    app.ui.mainWindow = self

    app.api.RegisterCallback(self, "OnModulesChanged", "OnModulesChanged")
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
    if app.db then
        self:SetMinimized(app.db.profile.window.minimized)
    end
end

----------------------------------------------------------------------------------------------------
-- Minimized (one page) / maximized (two-page spread), like the spellbook
----------------------------------------------------------------------------------------------------

---@param minimized boolean
function ForeverLootMainWindowMixin:SetMinimized(minimized)
    self.isMinimized = minimized
    self:SetWidth(minimized and self.minimizedWidth or self.maximizedWidth)
    self.ViewContainer:SetWidth(minimized and self.bookMinimizedWidth or self.bookMaximizedWidth)

    for _, view in ipairs(self.views) do
        view:SetMinimized(minimized)
    end

    -- Keep the button's icon in sync without re-firing its callbacks.
    self.MaximizeMinimizeButton.MaximizeButton:SetShown(minimized)
    self.MaximizeMinimizeButton.MinimizeButton:SetShown(not minimized)

    if app.db then
        app.db.profile.window.minimized = minimized
    end
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
    view:SetAllPoints(self.ViewContainer)
    view:SetMinimized(self.isMinimized)
    view.onNavigate = function(v)
        self:UpdateTabTitle(v)
    end
    view:SetRoot(app.api:GetRootNode())
    self.views[#self.views + 1] = view

    self:RebuildTabs()
    self:SetTab(self.viewToTabID[view])
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

    local wasSelected = self:GetTab() == self.viewToTabID[view]
    tremove(self.views, index)
    self.viewPool:Release(view)

    self:RebuildTabs()
    if wasSelected then
        local neighbor = self.views[math.min(index, #self.views)]
        self:SetTab(self.viewToTabID[neighbor])
    else
        local current = self:GetTab()
        if current then
            self.TabSystem:SetTabVisuallySelected(current)
        end
    end
end

-- TabSystem can only append or clear tabs, so any open/close rebuilds the whole strip.
-- The owner's RemoveAllTabs only clears the strip; reset its tracker too or it keeps every
-- element ever added.
function ForeverLootMainWindowMixin:RebuildTabs()
    self:RemoveAllTabs()
    self.internalTabTracker:Init()
    wipe(self.viewToTabID)

    for _, view in ipairs(self.views) do
        local tabID = self:AddNamedTab(view:GetTitle(), view)
        self.viewToTabID[view] = tabID
        self:DecorateTabButton(self.TabSystem:GetTabButton(tabID) --[[@as ForeverLoot.TabButton]], view)
    end
    self.newTabID = self:AddNamedTab(NEW_TAB_LABEL)
    local newTab = self.TabSystem:GetTabButton(self.newTabID) --[[@as ForeverLoot.TabButton]]
    newTab.flView = nil -- pooled button may have been a view tab before
    newTab:SetTooltipText("Open a new tab")
end

-- Right-click on a tab closes its view. Tab buttons come from a pool, so hook each one only once.
---@param button ForeverLoot.TabButton
---@param view ForeverLoot.View
function ForeverLootMainWindowMixin:DecorateTabButton(button, view)
    button.flView = view
    button:SetTooltipText("Right-click to close")
    if not button.flCloseHooked then
        button.flCloseHooked = true
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:HookScript("OnClick", function(btn, mouseButton)
            if mouseButton == "RightButton" and btn.flView then
                self:CloseView(btn.flView)
            end
        end)
    end
end

---@param view ForeverLoot.View
function ForeverLootMainWindowMixin:UpdateTabTitle(view)
    local tabID = self.viewToTabID[view]
    if not tabID then
        return
    end
    local button = self.TabSystem:GetTabButton(tabID) --[[@as ForeverLoot.TabButton]]
    button.tabText = view:GetTitle()
    button:SetText(button.tabText)
    button:UpdateTabWidth()
    self.TabSystem:MarkDirty()
end

-- Tab selected callback (wired by SetTabSystem). Returning true suppresses the visual selection.
---@param tabID integer
---@param isUserAction? boolean
function ForeverLootMainWindowMixin:SetTab(tabID, isUserAction)
    if tabID == self.newTabID then
        self:OpenView()
        return true
    end
    TabSystemOwnerMixin.SetTab(self, tabID, isUserAction)
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
