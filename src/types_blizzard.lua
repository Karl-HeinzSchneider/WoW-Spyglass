-- Type annotations only; not listed in the TOC and never runs in-game.
--
-- Blizzard UI mixins that src/ui inherits from, limited to the methods we actually use. The full
-- definitions live in the ketho.wow-api FrameXML annotations, which are opt-in
-- (`wowAPI.luals.frameXML`) and heavy; these minimal declarations keep diagnostics clean without
-- them. LuaLS merges same-named classes, so nothing breaks when they are enabled.
-- Signatures verified against BlizzardInterfaceCode (Blizzard_SharedXML, Blizzard_PagedContent).
-- Extend a class here when using a new method of it.

---@class BaseLayoutMixin
---@field MarkDirty fun(self: BaseLayoutMixin)
---@field Layout fun(self: BaseLayoutMixin)

---@class LayoutMixin : BaseLayoutMixin

---@class TitledPanelMixin
---@field SetTitle fun(self: TitledPanelMixin, title: string)
---@field SetTitleFormatted fun(self: TitledPanelMixin, fmt: string, ...: any)
---@field GetTitleText fun(self: TitledPanelMixin): FontString

---@class PortraitFrameMixin : TitledPanelMixin
---@field SetPortraitToAsset fun(self: PortraitFrameMixin, texture: string|number)
---@field SetPortraitToUnit fun(self: PortraitFrameMixin, unit: string)
---@field SetPortraitShown fun(self: PortraitFrameMixin, shown: boolean)
---@field GetPortrait fun(self: PortraitFrameMixin): Texture

---@class MaximizeMinimizeButtonFrameMixin
---@field SetOnMaximizedCallback fun(self: MaximizeMinimizeButtonFrameMixin, callback: fun(self: MaximizeMinimizeButtonFrameMixin))
---@field SetOnMinimizedCallback fun(self: MaximizeMinimizeButtonFrameMixin, callback: fun(self: MaximizeMinimizeButtonFrameMixin))
---@field SetMinimizedCVar fun(self: MaximizeMinimizeButtonFrameMixin, cvar: string)
---@field Maximize fun(self: MaximizeMinimizeButtonFrameMixin)
---@field Minimize fun(self: MaximizeMinimizeButtonFrameMixin)

---@class TabSystemButtonMixin
---@field tabText? string
---@field SetTooltipText fun(self: TabSystemButtonMixin, text: string)
---@field UpdateTabWidth fun(self: TabSystemButtonMixin)
---@field SetTabSelected fun(self: TabSystemButtonMixin, selected: boolean)
---@field GetTabID fun(self: TabSystemButtonMixin): integer

---@class TabSystemMixin
---@field AddTab fun(self: TabSystemMixin, tabText: string?, tabIcon?: string|number): integer
---@field RemoveAllTabs fun(self: TabSystemMixin)
---@field SetTab fun(self: TabSystemMixin, tabID: integer, isUserAction?: boolean)
---@field SetTabVisuallySelected fun(self: TabSystemMixin, tabID: integer)
---@field SetTabShown fun(self: TabSystemMixin, tabID: integer, shown: boolean)
---@field SetTabEnabled fun(self: TabSystemMixin, tabID: integer, enabled: boolean, errorReason?: string)
---@field GetTabButton fun(self: TabSystemMixin, tabID: integer): Button

---@class TabSystemOwnerMixin
---@field OnLoad fun(self: TabSystemOwnerMixin)
---@field SetTabSystem fun(self: TabSystemOwnerMixin, tabSystem: TabSystemMixin)
---@field AddNamedTab fun(self: TabSystemOwnerMixin, tabName: string, ...: Frame): integer
---@field AddIconTab fun(self: TabSystemOwnerMixin, tabIcon: string|number, ...: Frame): integer
---@field SetTab fun(self: TabSystemOwnerMixin, tabID: integer, isUserAction?: boolean)
---@field GetTab fun(self: TabSystemOwnerMixin): integer?
---@field GetTabButton fun(self: TabSystemOwnerMixin, tabID: integer): Button
---@field RemoveAllTabs fun(self: TabSystemOwnerMixin)

---@class PagingControlsMixin
---@field GetMaxPages fun(self: PagingControlsMixin): integer
---@field SetMaxPages fun(self: PagingControlsMixin, maxPages: integer)
---@field GetCurrentPage fun(self: PagingControlsMixin): integer
---@field SetCurrentPage fun(self: PagingControlsMixin, page: integer): boolean
---@field NextPage fun(self: PagingControlsMixin)
---@field PreviousPage fun(self: PagingControlsMixin)
---@field OnMouseWheel fun(self: PagingControlsMixin, delta: number)
