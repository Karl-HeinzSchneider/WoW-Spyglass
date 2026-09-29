# The browser window

How the core addon's window (`Spyglass/src/ui/`) is built. What modules and nodes can ask the
window to draw is the public contract in [API.md](API.md); this document is about the
implementation behind it.

Every frame is a Blizzard-style XML layout with a Lua mixin. XML `mixin=` / `name=` attributes
need globals, so the mixins and the window frame are globals prefixed `Spyglass…` (also
exposed on `app.ui.*`); together with the public API table they are the only sanctioned
globals. The TOC lists each Lua mixin before the XML that names it.

## Main window (`mainwindow.lua` / `.xml`)

`SpyglassMainWindow` inherits `PortraitFrameBaseTemplate`, sized 900x650, with a dark
two-column interior: `LeftPane` holds the views, `RightPane` the info pane (below). Both are
`UI-Character-Info-*-BG` atlases stretched to fit, split by `common-framedivider`. Icon tabs run
down the right edge (`SpyglassSideTabTemplate`, from `LargeSideTabButtonTemplate`, which is a
_Frame_, so clicks arrive through `SetCustomOnMouseUpHandler`). The title is the addon name and
the TOC's `## Version` in `ff8080ff`; a client linked to the git repo, whose TOC still has the
packager's `@project-version@` token, shows "dev (git)" instead.

The gear left of the close button (`OptionsButton`, `Interface\Buttons\UI-OptionsButton`, above
the border at frame level 510 like the close button) opens the options page in the selected tab,
"Spyglass > Options" (`view:ToggleOptions()`; clicked again, or via the breadcrumb or a
right-click, it goes back to the root). It stays lit while that tab is on the page. The page is
a private node of `view.lua`, not a module: it lists nothing, the footer's class filter and
active list are hidden, and its list area holds the same AceConfig table the game's Settings
panel shows (`src/core/options.lua`), drawn into one AceGUI `BlizOptionsGroup` (the container
the Settings panel uses, so AceConfigDialog gives it a scroll frame; its own title is suppressed)
that the view on the page borrows. It is fed again after being hidden, and while shown on
`ConfigTableChange` (a profile switch, `/sg loglevel`), so a new option needs no window code. The
page isn't restored with the tabs of the last session (it is not a child of the root).

The tabs work like a browser's: one per open _view_ (icon = the deepest node that has one,
tooltip = its title, then the path of folders below the root in gold, "Crafting > Alchemy >
Camping", when there is more than one) plus a `+` tab; right-click closes one, and `RebuildTabs()` lays the strip
out again from a pool. The window's edge fits ten tabs, so at most nine views are open
(`MAX_VIEWS`): with nine the `+` tab is left out until one is closed. The open tabs survive the session: `SaveTabs()` writes them to
`char.tabs` (per tab the names of the folders open below the root and the footer's class
filter, plus the selected tab) whenever one opens, closes, is selected or navigates and whenever
a class filter changes, and `RestoreTabs()` reopens them from `OnEnable`, when every module is
registered, following each path by name as far as it still matches. Search text, filters, panel
settings and the page are not kept. The window is
draggable and its position is saved to `profile.window`.
The root node comes from `app.api:GetRootNode()`; the window listens to `OnModulesChanged`,
`OnDataChanged`, `OnFiltersChanged` and `OnListsChanged` (see [Item lists](#item-lists)).

## Views (`view.lua` + `templates.xml`)

A view fills the left column: a header row (breadcrumbs on the left, starting right of the
window portrait; search box and filter dropdown on the right) over a divider, then one `Content`
page of rows, then under a second divider (`FooterDivider`) a footer row as high as the header
row (44px) with the two class filter buttons on the left, then the active list dropdown
(`ActiveList`, see [Item lists](#item-lists)), and Blizzard's `PagingControls` on the right.

- **Navigation** is a `path` stack over `Spyglass.Node` trees (`Push` / `PopTo` / `Back`, then
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
- **Class filter.** Two footer buttons (`SpyglassFooterButtonTemplate`: an icon in an item
  slot's frame; gold frame = on, grey icon = off). `ClassFilter` shows the class icon:
  left-click toggles the filter, right-click opens a menu to pick the class (which also turns it
  on). `ClassFilterMode` next to it switches with a click whether the armor and weapons that
  class can't use are _faded_ (the default; `IsFaded`: `RenderPage` draws the row, tile or card
  at `FADED_ALPHA` with a grey icon) or _hidden_ (`GetClassFilterTest`, joined with the info
  panel's filters in `BuildElements`). On query folders the `FilterDropdown` menu has the same
  state as a "Class" submenu (Off / a class / fade out or hide); its red X shows while the
  class filter is on, and its reset (`ResetFilters`) turns it off. The state is per tab (`classFilterOn`, `classFilterMode`,
  `filterClass`, nil = the character's class) and saved with the tabs (`char.tabs.classFilters`). Which class can use what is the
  table in `src/data/classfilter.lua` (`app.classFilter:CanUse(class, itemID)`): per armor and
  weapon subclass the classes that can use it, turned around at load into a per-class set of
  blocked subclasses, so a lookup is the item's kind (`app.itemKind`) plus two table reads.
  Subclasses not in the table, and every item that is neither armor nor a weapon, are usable
  by all; an item whose kind isn't known yet counts as usable.

### Rows

A row is the icon, the name in quality color, the drop chance top right (else the node's
`infoRight`, e.g. a recipe's skill thresholds), the slot bottom left and the armor or weapon type
bottom right (`itemKindTexts`). Both turn red when the character can't equip the item; that is
read from the tooltip's slot line through the hidden `SpyglassScanTooltip`
(`scanEquipErrors`), which is exact for this client's proficiencies. Item and spell tooltips are
followed by the node's `tooltip` lines (a list, or a function of the node).

### Item lists

Alt-click on an item row (or an item slot in a popup) toggles the item in the active list of
`app.lists` (`Spyglass.Lists`, see [API.md](API.md#lists-and-favorites)) and rebuilds the
tooltip under the cursor. The footer's `ActiveList` (`WowStyle1DropdownTemplate`) shows the
active list with its marker and offers every list as a radio; picking one calls `SetActive`.
`Render` regenerates its menu, so it follows a list made active, renamed or deleted elsewhere. `app.ui.SetItemBadges` (view.lua) draws an item's list badges on the
row and slot templates. `Favorite` is the transmog frame's favorite star
(`transmog-icon-favorite`, 19x19 in `Interface\Transmogrify\UITransmogrify2x`) over the icon's
top-left corner, for Favorites. `ListMarker` is over the top-right corner: the marker of the
active list when it has the item, else of the first other list that has it. The star is drawn
at 15px next to the 14px markers (`Lists:GetMarkerMarkup` scales it the same in tooltips), so
both look the same size.

On `OnListsChanged` with an item id, the main window only `Render`s the shown view, so rows
keep their places, and refreshes the info pane, whose list panel counts the items. An item
removed from the list being shown keeps its row (without the badge) until the list is opened
again, and the next row never slides under the cursor. Without an item id (a list made,
renamed, deleted or made active), the shown views `Refresh`, since the Lists tiles show all of
that. The popups `Refresh` for their slots either way.

`SpyglassListDialog` (`listdialog.lua` / `.xml`, `app.ui.listDialog`) is behind
`Lists:Open*Dialog`: one `SpyglassPopupTemplate` frame centered on the main window whose mode
(create, edit, export, import, delete) picks the parts `Layout()` stacks under the title. The
parts are a message, a name box (`InputBoxTemplate`), the eight raid target markers as buttons
(the picked one opaque), a "Show in item tooltips" checkbox (the info pane's checkbox template),
a text box (`ScrollingEditBoxTemplate` on a dark backdrop; the export string is selected for
Ctrl+C) and the accept button. A failed import shows its message in red and keeps the dialog
open.

### Tiles and cards

- **`display = "tiles"`** (raids, dungeons, crafting) draws `SpyglassTileTemplate` cards, three
  per line: the `background` / `backgroundCoords` picture (a texture, or an atlas resolved through
  `C_Texture.GetAtlasInfo` with the coords cut from its region), the name on top, `info` (the
  level range by default) and `infoRight` in the bottom corners. `addon:OnEnable` (still behind
  the loading screen) preloads the pictures of the root's tile folders onto textures of their
  own, set once on an alpha-0 frame, so the files are loaded before the first visit and never
  drop out.
- **`display = "cards"`** (an instance's boss list) draws `SpyglassCardTemplate`, two per line:
  the same bevelled list-button atlas with the entry's `portrait` standing on the left (a
  `portraitDisplayID` instead draws the creature's model through
  `SetPortraitTextureFromCreatureDisplayID` into the same region), and the name and info beside
  it (boss level and type, drops of interest, a quest "!" for `quests`).
  An instance lists All Bosses, then trash loot, then its bosses. A button under the right
  pane's quest list opens the quest folder.

### Headers, subheaders, quest banners, groups, spacers

Section headers use the `UI-Character-Info-Title` plate. Subheaders are a step smaller: centered
text with `UI-Character-Info-ScrollLine-Long` running out to both sides. Clickable subheaders
use larger text and a 40-pixel-high hit area. Groups are row-sized labels. A `spacer` element
is one row of empty space that takes part in the page layout but has
no frame; it is dropped at the top of a page.

A quest node (`{ quest = id }`) is drawn as `SpyglassQuestBannerTemplate`
(`SpyglassQuestBannerMixin`), full width and `questHeight` high, over a darker row backplate with
the group label's scroll line along its bottom. On the left is the progress icon
(`Interface\GossipFrame\AvailableQuestIcon`, `IncompleteQuestIcon`, `ActiveQuestIcon`,
`Interface\RaidFrame\ReadyCheck-Ready` once done), then the title in `GameFontNormalMed2` with the
node's `info` right after it (the title is sized to its text and truncated before it reaches the
right column) and the objective under both; on the right the experience over the progress text.
Progress, hover, shift-click and the quest data request come from `app.questInfo` (`quests.lua`),
shared with the info pane's quest lines. A banner with `children` opens those children on click.
The dungeon's quest page shows the dungeon name and a right-pane dropdown for Alliance, Horde,
or Both (all quests). It defaults to the character's faction; shared quests appear under either
faction. It shows one
banner per visible quest, with Alliance and/or Horde emblems
directly left of a compact, fixed-width XP display. Values below 100,000 keep their full number;
larger values use `k` (for example, `100k`). Its reward rows appear on the opened quest page.
If a quest has prequests, its banner shows completed/total prequests before the objective (for
example, `Prequests 1/2`). That page shows the quest title and
objective, start and turn-in sources, optional description, and map buttons for known endpoint
locations in the right pane. When prequests exist, a clickable subheader below the rewards
expands them in order. Their banners are indented with a left rail and numbered steps. Each prerequisite
opens a detail page with its own rewards and a button back to the main quest; it does not show
another prerequisite list.
The layout keeps a banner together with its first reward row when it has any. While the list has
banners (`view.showsQuests`), the view redraws the page on
`QUEST_LOG_UPDATE`, `QUEST_TURNED_IN` and `QUEST_DATA_LOAD_RESULT`, deferred to the next frame
like the item-info redraw.

### Info panel filters

A view keeps the state of the info panel's checkboxes, dropdowns and grouping in
`view.panelState`, per panel node and widget index. `GetPanel()` finds the deepest node on the
path with a `panel` (calling a function panel), `GetEntryFilter()` turns the set checkboxes and
dropdowns into one test, and `BuildElements` drops the entries it rejects (quest banners can be
filtered; other folders stay), along
with a subheader or group label whose entries are all gone. `GetPanelGrouping()` returns the
picked `grouping` option's `groupBy` (the option's index is the stored value, the first until
one is picked), which `BuildElements` uses instead of the node's. `SetPanelValue` stores a value and refreshes from
page 1. The checkbox filter ids (`PANEL_FILTERS`: `side`, `standing`) must match the ones
`src/lists.ts` accepts. `OpenPath(path)` resolves a button's `open` path from the root and
replaces the tab's path with the nodes it passed.

## Info pane (`infopane.lua` / `.xml`)

`SpyglassInfoPaneMixin` is `RightPane.Info`, inset like the character frame's side panes. It
remakes the look of that frame's reputation and skill detail panes (`CharacterFrameSidePaneTemplate`
registers itself with the character frame, so it can't be inherited): the title in
`GameFontNormalMed3`, the `UI-Character-Info-ScrollLine` divider, then the widgets in a
`VerticalLayoutFrame` of fixed width. Each widget kind has a pooled template:

- `header`: the `UI-Character-Info-Title` plate; `text`/`description`: wrapped white text;
  `row`: gold label, white value; `spacer`: empty space.
- `bar`: `ColoredProgressBarTemplate` (Blizzard_SharedXML, Camelot). Reputation as the
  reputation pane draws it (white fill tinted with `FACTION_BAR_COLORS`, standing and progress
  text), skill in the blue fill with "rank / max".
- `checkbox`: `checkbox-minimal` / `checkmark-minimal`, the label beside it inside the hit rect;
  `dropdown`: `WowStyle1DropdownTemplate` with an "All" radio and one per value; `grouping`:
  the same dropdown with one radio per option. The quest list's `factionDropdown` uses that
  dropdown for Alliance, Horde, and Both.
- `button`: `SharedGoldRedButtonSmallTemplate`. A `map` button sets a user waypoint from a plain
  `{ uiMapID, position }` table (`UiMapPoint` isn't loaded in this client) and calls
  `OpenWorldMap`.
- `quests`: one `SpyglassInfoQuestTemplate` line per quest the character can take (side and
  class from `Data:GetQuest`), the title wrapped on the left, the progress on the right from
  `C_QuestLog` (`IsQuestFlaggedCompleted`, `IsOnQuest`, `ReadyForTurnIn` / `IsComplete`), from
  `app.questInfo` (`quests.lua`), which the list's quest banners use too. Each line is a button
  that behaves like a quest link in chat: hover shows the game's quest tooltip (`GameTooltip:SetHyperlink` with `GetQuestLink`), a modified click goes through
  `HandleModifiedItemClick`. A quest the client hasn't loaded has no link yet; it is asked for
  once (`C_QuestLog.RequestLoadQuestByID`) and `QUEST_DATA_LOAD_RESULT` redraws the pane, until
  then the tooltip shows the curated title, id, `requiredLevel`, `objective` and optional
  `description` from `Data:GetQuest`. Curated start and turn-in details and prerequisite quests
  follow either tooltip, with each prerequisite's completion state. Either tooltip ends with
  the curated rewards: each of the quest's `items` as
  its icon and name in its quality color (the item cache, else the database row; an uncached item
  is requested for the next hover), then the `xp`.

Text that may run over one line (`text`, `description`, quest titles) sits in a FontString with
a fixed width: the rows are measured before the layout frame places them, so a width taken from
anchors would measure as a single line.

The main window hands the pane the selected view (`SetView` in `SelectView`) and refreshes it
when that view navigates and on `OnDataChanged`; the pane itself redraws on `OnShow`,
`UPDATE_FACTION`, `SKILL_LINES_CHANGED`, `QUEST_LOG_UPDATE`, `QUEST_TURNED_IN` and
`QUEST_DATA_LOAD_RESULT`. Event redraws wait for the next frame and happen once however many
events came: asking for a quest while the lines are drawn can fire `QUEST_DATA_LOAD_RESULT`
inside that call, and a redraw inside a redraw would release lines still being filled. A
checkbox or dropdown only calls the view's
`SetPanelValue`; its own state already shows the change.

## Recipe and set popups (`recipepopup.lua` / `.xml`, `setpopup.lua` / `.xml`)

Both popups are `SpyglassPopupTemplate` frames: a tooltip-bordered child of the main window
with a title and a close button. `SpyglassPopupMixin` (which both mixins build on) toggles one
below the row it was clicked from and closes the other; `app.ui.HidePopups()` closes both.

`SpyglassRecipePopup` (`app.ui.recipePopup`): a click on a recipe row (a node whose
`meta.spell` is in `Data.recipes`) toggles it: a title, then icons only — the product and the
recipe item that teaches it, then the recipe itself (the profession's tile icon; spell tooltip
and link) and one slot per reagent with its count.

`SpyglassSetPopup` (`app.ui.setPopup`): a plain click on any other item row whose item is in a
set the database knows (`HasSet`) toggles it: the set's name (`Data:GetSetName`), then one slot
per item of the set (`Data:GetSetItems`), in loot-list order (armor type, then slot), eight per
line. The item tooltip on a slot shows the game's set bonuses.

The set's name is hoverable (`TitleButton`, sized to the title): the tooltip is the set part of
the clicked item's tooltip data (`C_TooltipInfo.GetItemByID`), copied line by line with the
game's colors — from the header matching `ITEM_SET_NAME` with the set's name, over the items
that follow it, to the last line matching `ITEM_SET_BONUS_GRAY` or `ITEM_SET_BONUS` — so owned
pieces and active bonuses show as the game shows them. Until the client has that data it lists
the set's name and items, and redraws when the item arrives. The client has no chat link for a
set, so shift-click on the name links the clicked item instead, whose tooltip shows the set.

`SpyglassItemSlotTemplate` / `SpyglassItemSlotMixin` is the 32px icon with count and quality
border that every slot uses (`SetItem` / `SetSpell`, tooltip on hover, `HandleModifiedItemClick`
on click, alt-click toggles the item in the active list). The background is the main window's pane atlas (`UI-Character-Info-General-BG`) under
the tooltip border, with the template's own translucent backdrop switched off. A popup redraws
on `GET_ITEM_INFO_RECEIVED`; the view hides them on `Refresh` and on page changes, because their
anchor row is reused.

## Model preview (`modelpreview.lua` / `.xml`)

`SpyglassModelPreview` (`app.ui.modelPreview`): while ctrl is held over an item row or item
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
`trash`, `quest`, `recipe`) to every item tooltip. After a blank line comes one gold line per
user list that has the item and is shown in tooltips, with the list's marker: `[star] Favorite`,
`[skull] Warrior BiS`. Then the instance name in
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
