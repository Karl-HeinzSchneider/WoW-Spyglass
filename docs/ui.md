# The browser window

How the core addon's window (`ForeverLoot/src/ui/`) is built. What modules and nodes can ask the
window to draw is the public contract in [API.md](API.md); this document is about the
implementation behind it.

Every frame is a Blizzard-style XML layout with a Lua mixin. XML `mixin=` / `name=` attributes
need globals, so the mixins and the window frame are globals prefixed `ForeverLoot…` (also
exposed on `app.ui.*`); together with the public API table they are the only sanctioned
globals. The TOC lists each Lua mixin before the XML that names it.

## Main window (`mainwindow.lua` / `.xml`)

`ForeverLootMainWindow` inherits `PortraitFrameBaseTemplate`, sized 900x640, with a dark
two-column interior: `LeftPane` holds the views, `RightPane` the metadata. Both are
`UI-Character-Info-*-BG` atlases stretched to fit, split by `common-framedivider`. Icon tabs run
down the right edge (`ForeverLootSideTabTemplate`, from `LargeSideTabButtonTemplate`, which is a
_Frame_, so clicks arrive through `SetCustomOnMouseUpHandler`).

The tabs work like a browser's: one per open _view_ (icon = the deepest node that has one,
tooltip = its title) plus a `+` tab; right-click closes one, and `RebuildTabs()` lays the strip
out again from a pool. The window is draggable and its position is saved to `profile.window`.
The root node comes from `app.api:GetRootNode()`; the window listens to `OnModulesChanged`,
`OnDataChanged` and `OnFiltersChanged`.

## Views (`view.lua` + `templates.xml`)

A view fills the left column: a header row (breadcrumbs on the left, starting right of the
window portrait; search box and filter dropdown on the right) over a divider, then one `Content`
page of rows with Blizzard's `PagingControls` at the bottom right.

- **Navigation** is a `path` stack over `ForeverLoot.Node` trees (`Push` / `PopTo` / `Back`, then
  `Refresh`). `Push` remembers the page the node was on in `view.pathPages`, and going back
  (`PopTo`, breadcrumbs, right-click) returns to that page.
- **`Refresh()`** rebuilds the elements and the page layout (navigation, query or size changes)
  and keeps the current page; **`Render()`** only redraws it (page flips, item info arriving).
- **Children** come from `view:GetChildren(node)`: static `children`, dynamic `getChildren`, or a
  `query` folder whose entries are `Query.Run` over the database with per-node query state
  (`view.queries`). Query folders show the debounced `SearchBox` and the `FilterDropdown`
  (Blizzard_Menu `WowStyle1FilterDropdownTemplate`, its menu generated from the filter registry).
- **Regrouping.** Items the grouping couldn't place (`app.unknownItemKinds`, filled by
  `registry.lua` and cleared before each build: no database row and not fetched yet) are all
  requested after the build and marked in `view.regroupItems`. When one arrives the deferred
  redraw is a `Refresh` instead of a `Render`, once per item, so the list regroups on the page it
  was showing.

### Rows

A row is the icon, the name in quality color, the drop chance top right (else the node's
`infoRight`, e.g. a recipe's skill thresholds), the slot bottom left and the armor or weapon type
bottom right (`itemKindTexts`). Both turn red when the character can't equip the item; that is
read from the tooltip's slot line through the hidden `ForeverLootScanTooltip`
(`scanEquipErrors`), which is exact for this client's proficiencies. Item and spell tooltips are
followed by the node's `tooltip` lines (a list, or a function of the node).

### Tiles and cards

- **`display = "tiles"`** (raids, dungeons, crafting) draws `ForeverLootTileTemplate` cards, three
  per line: the `background` / `backgroundCoords` picture (a texture, or an atlas resolved through
  `C_Texture.GetAtlasInfo` with the coords cut from its region), the name on top, `info` (the
  level range by default) and `infoRight` in the bottom corners. `addon:OnEnable` (still behind
  the loading screen) preloads the pictures of the root's tile folders onto textures of their
  own, set once on an alpha-0 frame, so the files are loaded before the first visit and never
  drop out.
- **`display = "cards"`** (an instance's boss list) draws `ForeverLootCardTemplate`, two per line:
  the same bevelled list-button atlas with the entry's `portrait` standing on the left (a
  `portraitDisplayID` instead draws the creature's model through
  `SetPortraitTextureFromCreatureDisplayID` into the same region), and the name and info beside
  it (boss level and type, drops of interest, a quest "!" for `quests`).

### Headers, subheaders, groups, spacers

Section headers use the `UI-Character-Info-Title` plate. Subheaders are a step smaller: centered
text with `UI-Character-Info-ScrollLine-Long` running out to both sides. Groups are row-sized
labels. A `spacer` element is one row of empty space that takes part in the page layout but has
no frame; it is dropped at the top of a page.

## Recipe popup (`recipepopup.lua` / `.xml`)

`ForeverLootRecipePopup` (`app.ui.recipePopup`) is a tooltip-bordered child of the main window.
A click on a recipe row (a node whose `meta.spell` is in `Data.recipes`) toggles it below that
row: a title, then icons only — the product and the recipe item that teaches it, then the recipe
itself (the profession's tile icon; spell tooltip and link) and one slot per reagent with its
count.

`ForeverLootItemSlotTemplate` / `ForeverLootItemSlotMixin` is the 32px icon with count and quality
border that every slot uses (`SetItem` / `SetSpell`, tooltip on hover, `HandleModifiedItemClick`
on click). The background is the main window's pane atlas (`UI-Character-Info-General-BG`) under
the tooltip border, with the template's own translucent backdrop switched off. The popup redraws
on `GET_ITEM_INFO_RECEIVED`; the view hides it on `Refresh` and on page changes, because its
anchor row is reused.

## Model preview (`modelpreview.lua` / `.xml`)

`ForeverLootModelPreview` (`app.ui.modelPreview`): while ctrl is held over an item row or item
slot, it shows the character wearing that item under `GameTooltip` (above it when the screen ends
first), as wide as the tooltip, in the recipe popup's look (tooltip border over
`UI-Character-Info-General-BG`).

- Rows call `SetItem(owner, itemID)` after showing the tooltip and `Clear()` on leave.
  `MODIFIER_STATE_CHANGED` shows and hides it, and `OnUpdate` drops it once the tooltip belongs
  to someone else.
- It is a `NonInteractableModelSceneMixinTemplate` (Blizzard_SharedXML) set up from the dressing
  room's model scene id (596) with `SetupPlayerForModelScene`, then `actor:Dress()` +
  `TryOn(link)` per item, turned 25° further than the scene's yaw (towards the main hand), or
  around (+ π) for a cloak. Only items `C_Item.IsDressableItemByID` accepts and the client has
  cached are shown. The actor is rebuilt after `PLAYER_EQUIPMENT_CHANGED` / `UNIT_MODEL_CHANGED`.
- A mount item (`C_MountJournal.GetMountFromItem`, else from the item's use spell) shows the
  mount instead: the scene switches to the mount's `uiModelSceneID` and its `unwrapped` actor gets
  the mount's creature display, without a rider.

## Item tooltips (`tooltip.lua`)

`app.tooltip`, an Ace module, appends an item's sources (`Data:GetItemSources` kinds `boss`,
`trash`, `quest`, `recipe`) to every item tooltip. After a blank line comes the instance name in
gold over its bosses, "Trash" and `Quest: <title>` lines, indented and sorted by encounter order.
Drops start with the `ParagonReputation_Bag` atlas (a loot sack, used by the Camelot reputation
frame), quests with `Interface\GossipFrame\AvailableQuestIcon`. Then one gold
`Crafted by <profession>` line per profession with a recipe for the item, with the icon of that
profession's crafting list.

It hooks once in `OnInitialize`: through `TooltipDataProcessor.AddTooltipPostCall` when
`GameTooltip` is built on the tooltip data handler, else `OnTooltipSetItem` on `GameTooltip` and
`ItemRefTooltip`.

## Timing (`src/helper/profiler.lua`)

A development aid, off by default: set `ENABLED = true` and it wraps `Query.Run` and the main
window's and views' high-level methods, printing each call's duration to the chat. Frames copy
mixin functions when they are created, so the TOC loads it after the mixins it wraps and before
the XML that creates the frames.
