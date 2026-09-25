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

-- LargeSideTabButtonTemplate (the icon tabs down the side of the character frame).
---@class SidePanelTabButtonMixin
---@field Icon Texture
---@field SelectedTexture Texture
---@field tooltipText? string
---@field OnLoad fun(self: SidePanelTabButtonMixin)
---@field SetCustomOnMouseUpHandler fun(self: SidePanelTabButtonMixin, handler: fun(tab: SidePanelTabButtonMixin, button: string, upInside: boolean))
---@field SetFillToInterior fun(self: SidePanelTabButtonMixin, fillToInterior: boolean, extent?: number)
---@field SetChecked fun(self: SidePanelTabButtonMixin, checked: boolean)
---@field GetTooltipTextSetupFunction fun(self: SidePanelTabButtonMixin): (fun(tooltip: GameTooltip): boolean)?
---@field SetTabGlowAnimationPlaying fun(self: SidePanelTabButtonMixin, playing: boolean)
SidePanelTabButtonMixin = {} --[[@as SidePanelTabButtonMixin]]

-- C_SkillInfo (Blizzard_APIDocumentationGenerated/SkillInfoDocumentation.lua): the character's
-- skill lines, used for the profession rank on crafting tiles.
---@class SkillLineAttributes
---@field skillID number
---@field name string
---@field isHeader boolean
---@field rank number
---@field maxRank number
---@field parentSkillLineID number
---@field skillLineCategoryID number

---@class C_SkillInfo
---@field GetSkillLineInfoByID fun(skillLineID: number): SkillLineAttributes?
C_SkillInfo = {} --[[@as C_SkillInfo]]

-- ColoredProgressBarTemplate (Blizzard_SharedXML/Camelot/ProgressBars/ColoredProgressBar.lua):
-- the character frame's skill and reputation bar.
---@class ColoredProgressBarMixin : Frame
---@field Fill Texture
---@field Text FontString
---@field ColorType { Red: integer, Green: integer, Blue: integer, White: integer }
---@field SetText fun(self: ColoredProgressBarMixin, text: string)
---@field SetFillPercent fun(self: ColoredProgressBarMixin, percent: number)
---@field SetFillTextureByColorType fun(self: ColoredProgressBarMixin, colorType: integer)
ColoredProgressBarMixin = {} --[[@as ColoredProgressBarMixin]]

-- NonInteractableModelSceneMixinTemplate (Blizzard_SharedXML/ModelSceneMixin.lua).
---@class ModelSceneMixin
---@field TransitionToModelSceneID fun(self: ModelSceneMixin, modelSceneID: number, cameraTransitionType: number, cameraModificationType: number, forceEvenIfSame?: boolean)
---@field GetPlayerActor fun(self: ModelSceneMixin, overrideActorName?: string): ModelSceneFrameActor?
---@field GetActorByTag fun(self: ModelSceneMixin, tag: string): ModelSceneFrameActor?

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
---@field SetIsDefaultCallback fun(self: WowStyle1FilterDropdownMixin, callback: fun(): boolean)
---@field SetDefaultCallback fun(self: WowStyle1FilterDropdownMixin, callback: fun())
---@field ValidateResetState fun(self: WowStyle1FilterDropdownMixin)

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
