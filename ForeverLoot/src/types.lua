-- Type annotations only; this file is not listed in the TOC and never runs in-game.
-- It exists so the Lua language server can type the `...` vararg every file receives.
-- Every file should start with:
--   ---@type string, ForeverLoot
--   local appName, app = ...
-- When a file adds something to `app`, add a matching ---@field here.

---@class ForeverLoot
---@field logger ForeverLoot.Logger
---@field addon ForeverLoot.Addon
---@field dbDefaults ForeverLoot.DBDefaults
---@field db ForeverLoot.DB
---@field minimapButton ForeverLoot.MinimapButton
---@field api ForeverLoot.API  # also the global `ForeverLoot`
---@field data ForeverLoot.Data  # item database; also `ForeverLoot.Data`
---@field filters ForeverLoot.Filters  # filter registry; also `ForeverLoot.Filters`
---@field query ForeverLoot.QueryAPI  # query runner; also `ForeverLoot.Query`
---@field commands ForeverLoot.CommandRegistry  # private dispatcher; registration is public API
---@field ui ForeverLoot.UI

-- UI namespace. Mixins are globals (XML requires it) but also exposed here.
---@class ForeverLoot.UI
---@field mainWindow ForeverLoot.MainWindow  # set in ForeverLootMainWindowMixin:OnLoad
---@field recipePopup ForeverLoot.RecipePopup  # set in ForeverLootRecipePopupMixin:OnLoad
---@field MainWindowMixin ForeverLoot.MainWindow
---@field RecipePopupMixin ForeverLoot.RecipePopup
---@field ItemSlotMixin ForeverLoot.ItemSlot
---@field SideTabMixin ForeverLoot.SideTab
---@field ViewMixin ForeverLoot.View
---@field ListRowMixin ForeverLoot.ListRow
---@field TileMixin ForeverLoot.Tile
---@field CardMixin ForeverLoot.Card
---@field PageHeaderMixin ForeverLoot.PageHeader
---@field GroupLabelMixin ForeverLoot.GroupLabel
---@field BreadcrumbButtonMixin ForeverLoot.BreadcrumbButton
---@field SearchBoxMixin ForeverLoot.SearchBox

-- Return type of CreateFramePool. The FrameXML annotations keep the pool mixins private,
-- so the methods we use are declared here.
---@class ForeverLoot.FramePool
---@field Acquire fun(self: ForeverLoot.FramePool): Frame
---@field Release fun(self: ForeverLoot.FramePool, frame: Frame)
---@field ReleaseAll fun(self: ForeverLoot.FramePool)
---@field EnumerateActive fun(self: ForeverLoot.FramePool): fun(): Frame

-- A HorizontalLayoutFrame / VerticalLayoutFrame instance.
---@class ForeverLoot.LayoutFrame : Frame, LayoutMixin

-- Any child placed in a layout frame needs a layoutIndex.
---@class ForeverLoot.LayoutChild : Frame
---@field layoutIndex integer

-- The AceDB object, with profile/char/global narrowed to the shape of app.dbDefaults.
-- Ace3 API types (AceAddon, AceDBObject-3.0, ...) come from the ketho.wow-api extension.
---@class ForeverLoot.DB : AceDBObject-3.0
---@field profile ForeverLoot.DB.Profile
---@field char ForeverLoot.DB.Char
---@field global ForeverLoot.DB.Global
