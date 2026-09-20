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

-- Blizzard_Menu (11.0-style menus): DropdownButton intrinsic + the description proxies the
-- generator receives. Only the element kinds we build are listed.
---@class WowStyle1FilterDropdownMixin
---@field SetupMenu fun(self: WowStyle1FilterDropdownMixin, generator: fun(dropdown: WowStyle1FilterDropdownMixin, rootDescription: RootMenuDescriptionProxy))
---@field GenerateMenu fun(self: WowStyle1FilterDropdownMixin)
---@field SetDefaultText fun(self: WowStyle1FilterDropdownMixin, text: string)

-- Element handlers get the element's `data`; returning a MenuResponse value is optional.
---@alias MenuHandler fun(data: any): integer?
---@alias MenuIsSelected fun(data: any): boolean

---@class MenuElementDescriptionProxy
---@field CreateButton fun(self: MenuElementDescriptionProxy, text: string, callback?: MenuHandler, data?: any): MenuElementDescriptionProxy
---@field CreateCheckbox fun(self: MenuElementDescriptionProxy, text: string, isSelected: MenuIsSelected, setSelected: MenuHandler, data?: any): MenuElementDescriptionProxy
---@field CreateRadio fun(self: MenuElementDescriptionProxy, text: string, isSelected: MenuIsSelected, setSelected: MenuHandler, data?: any): MenuElementDescriptionProxy
---@field CreateTitle fun(self: MenuElementDescriptionProxy, text: string, color?: ColorMixin): MenuElementDescriptionProxy
---@field CreateDivider fun(self: MenuElementDescriptionProxy): MenuElementDescriptionProxy
---@field SetScrollMode fun(self: MenuElementDescriptionProxy, maxScrollExtent: number)
---@field SetEnabled fun(self: MenuElementDescriptionProxy, enabled: boolean|fun(): boolean)

---@class RootMenuDescriptionProxy : MenuElementDescriptionProxy

-- Return values for menu element handlers (MenuConstants.lua).
---@class MenuResponse
---@field Open integer  # stay open, unchanged
---@field Refresh integer  # re-initialize every frame in the menu
---@field Close integer  # close this (sub)menu
---@field CloseAll integer
---@type MenuResponse
MenuResponse = {}
