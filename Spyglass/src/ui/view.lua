---@type string, Spyglass
local appName, app = ...

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

-- Tints an icon's `IconRing` (SpyglassIconRingTemplate, the slot frame around it) in the item's
-- quality color; without a quality (folders, spells, custom entries) it keeps its own texture color. Shared by
-- every widget that shows an icon.
---@param ring Texture
---@param quality? Enum.ItemQuality
local function setIconQuality(ring, quality)
    local color = quality and ITEM_QUALITY_COLORS[quality] or HIGHLIGHT_FONT_COLOR
    ring:SetVertexColor(color.r, color.g, color.b)
end
app.ui.SetIconQuality = setIconQuality

-- The list badges on an item's icon (`Favorite` and `ListMarker` of the row and slot templates):
-- the star when Favorites has the item; the marker of the active list when it has the item,
-- else of the first other list that has it. Nothing for no item.
---@param frame { Favorite: Texture, ListMarker: Texture }
---@param itemID? integer
local function setItemBadges(frame, itemID)
    local Lists = app.lists
    local favorite, marked = false, nil
    if itemID then
        local active = Lists:GetActive()
        for _, id in ipairs(Lists:GetListsOf(itemID)) do
            if id == Lists.FAVORITES then
                favorite = true
            elseif id == active or not marked then
                marked = id
            end
        end
    end
    frame.Favorite:SetShown(favorite)
    frame.ListMarker:SetShown(marked ~= nil)
    if marked then
        Lists:SetMarkerTexture(frame.ListMarker, marked)
    end
end
app.ui.SetItemBadges = setItemBadges

-- Delay between the last keystroke in the search box and running the query.
local SEARCH_DEBOUNCE = 0.25

-- One node per DB item, shared by every query result so lists don't re-allocate 20k tables.
---@type table<integer, Spyglass.Node>
local itemNodes = {}

---@param itemID integer
---@return Spyglass.Node
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
    return ("|cff%02x%02x%02x"):format(
        math.floor(c.r * 255 + 0.5),
        math.floor(c.g * 255 + 0.5),
        math.floor(c.b * 255 + 0.5)
    )
end

-- "15-21" with the colors above; nil when the node has no level range.
---@param node Spyglass.Node
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

---@param node Spyglass.Node
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
        scanTooltip = CreateFrame("GameTooltip", "SpyglassScanTooltip", UIParent, "GameTooltipTemplate") --[[@as GameTooltip]]
    end
    scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTooltip:SetItemByID(itemID)
    local slotInvalid, typeInvalid = false, false
    for i = 2, scanTooltip:NumLines() do
        local left = _G["SpyglassScanTooltipTextLeft" .. i]
        if left and left:GetText() == slotText then
            local right = _G["SpyglassScanTooltipTextRight" .. i]
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

-- Quest titles come from the client when it knows the quest, else from the curated data, else
-- the id (see Data:GetQuestName).
local QUEST_LABEL = "Quest: "
---@param questID integer
---@return string
local function questTitle(questID)
    return Data:GetQuestName(questID)
end

---@class Spyglass.ListRow : Button
---@field Backplate Texture
---@field Icon Texture
---@field IconMask MaskTexture
---@field IconRing Texture
---@field Name FontString
---@field Chance FontString
---@field Sub FontString
---@field Type FontString
---@field Arrow Texture
---@field Favorite Texture  # the star on a favorite item's icon
---@field ListMarker Texture  # the marker of a list with the item (setItemBadges)
---@field node Spyglass.Node
---@field view Spyglass.View
---@field link? string  # item/spell link for chat linking
SpyglassListRowMixin = {}
app.ui.ListRowMixin = SpyglassListRowMixin

-- What a row shows; the bottom line and the top-right text are optional.
---@class Spyglass.RowDisplay
---@field name string
---@field icon? string|number
---@field quality? Enum.ItemQuality
---@field sub? string  # bottom left: slot, item class or description
---@field type? string  # bottom right: armor / weapon type
---@field subInvalid? boolean  # draw `sub` red (can't equip)
---@field typeInvalid? boolean  # draw `type` red
---@field chance? number  # 0..1, top right, as a percentage
---@field right? string  # top right, as given (a node's `infoRight`); `chance` wins when both are set

---@param d Spyglass.RowDisplay
function SpyglassListRowMixin:SetDisplay(d)
    self.Icon:SetTexture(d.icon or FALLBACK_ICON)
    setIconQuality(self.IconRing, d.quality)
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

    local right = d.chance and formatChance(d.chance) or d.right
    self.Chance:SetText(right or "")
    self.Chance:SetShown(right ~= nil)

    -- With a bottom line the name sits in the upper half, otherwise it is vertically centered.
    self.Name:ClearAllPoints()
    if hasSub then
        self.Name:SetPoint("TOPLEFT", self.Icon, "TOPRIGHT", 8, -2)
    else
        self.Name:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
    end
    self.Name:SetPoint("RIGHT", self.Chance, "LEFT", -4, 0)
end

---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassListRowMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil
    self.Arrow:SetShown(app.api.IsFolder(node))
    setItemBadges(self, node.itemID)

    if node.itemID then
        self:InitItem(view, node)
    elseif node.spellID then
        local info = C_Spell.GetSpellInfo(node.spellID)
        if info then
            self.link = C_Spell.GetSpellLink(node.spellID)
            self:SetDisplay({ name = info.name, icon = info.iconID, sub = node.description, right = node.infoRight })
        else
            self:SetDisplay({ name = "Spell #" .. node.spellID, right = node.infoRight })
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

-- Items: the client's item cache, when it has the item, is exact, provides the link and lets the
-- tooltip say whether the character can equip it. Uncached items are requested so that
-- arrives; GET_ITEM_INFO_RECEIVED re-renders the page. Until then a DB row, when an addon has
-- added the item's (the core ships none), answers immediately (name, quality, class, slot);
-- without one the row shows "Item #id" and loading. Server-side items are unknown to
-- GetItemInfoInstant until fetched, so their icon comes from the row.
---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassListRowMixin:InitItem(view, node)
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
            quality, classID, subclassID, equipSlot =
                row[ITEM.QUALITY], row[ITEM.CLASS], row[ITEM.SUBCLASS], row[ITEM.SLOT]
        end
        icon = select(5, C_Item.GetItemInfoInstant(itemID)) or (row and row[ITEM.ICON])
    end

    if not name then
        self:SetDisplay({
            name = "Item #" .. itemID,
            icon = icon,
            sub = RETRIEVING_ITEM_INFO or "Loading...",
            chance = node.chance,
            right = node.infoRight,
        })
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
        right = node.infoRight,
    })
end

---@param button string
function SpyglassListRowMixin:OnClick(button)
    local node = self.node
    if button == "RightButton" then
        self.view:Back()
    elseif app.api.IsFolder(node) then
        self.view:Push(node)
    elseif node.itemID and IsAltKeyDown() then
        -- Alt-click adds the item to the active list or removes it; the window redraws the badges
        -- on OnListsChanged, the tooltip is built again here.
        app.lists:Toggle(app.lists:GetActive(), node.itemID)
        if GameTooltip:IsOwned(self) then
            self:OnEnter()
        end
    elseif node.onClick then
        node.onClick(node, button)
    elseif self.link and HandleModifiedItemClick(self.link) then
        -- Shift-click linked to chat, ctrl-click previewed in the dressing room, etc.
        return
    elseif node.meta and type(node.meta.spell) == "number" and Data:GetRecipe(node.meta.spell) then
        -- A recipe: the popup with what it makes, what teaches it and what it needs.
        app.ui.recipePopup:Toggle(node, self)
    elseif app.ui.setPopup:HasSet(node) then
        -- An item of a set: the popup with every item of the set.
        app.ui.setPopup:Toggle(node, self)
    elseif self.link then
        return
    elseif node.itemID then
        -- DB item the client hasn't cached yet: ask for it, the next click will have the link.
        self.view:RequestItem(node.itemID)
        log:chat(RETRIEVING_ITEM_INFO or "Retrieving item information...")
    else
        log:debug("Clicked %s", node.name or tostring(node.itemID or node.spellID))
    end
end

-- A node's extra tooltip lines: a list, or a function building one when the tooltip shows.
---@param node Spyglass.Node
---@return string[]
local function extraTooltipLines(node)
    local lines = node.tooltip
    if type(lines) == "function" then
        lines = lines(node)
    end
    return type(lines) == "table" and lines or {}
end

function SpyglassListRowMixin:OnEnter()
    local node = self.node
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if node.itemID or node.spellID then
        if node.itemID then
            GameTooltip:SetItemByID(node.itemID)
        else
            GameTooltip:SetSpellByID(node.spellID)
        end
        local lines = extraTooltipLines(node)
        if #lines > 0 then
            GameTooltip:AddLine(" ")
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
    elseif app.api.IsFolder(node) then
        GameTooltip:AddLine(node.name or "")
        if node.description then
            GameTooltip:AddLine(node.description, 1, 1, 1, true)
        end
        for _, questID in ipairs(node.quests or {}) do
            GameTooltip:AddLine(QUEST_LABEL .. questTitle(questID), 1, 0.82, 0)
        end
    else
        GameTooltip:AddLine(node.name or "")
        if node.description then
            GameTooltip:AddLine(node.description, 1, 1, 1, true)
        end
        for _, line in ipairs(extraTooltipLines(node)) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
    end
    GameTooltip:Show()
    if node.itemID then
        -- Holding ctrl shows the character wearing the item under the tooltip.
        app.ui.modelPreview:SetItem(self, node.itemID)
    end
end

function SpyglassListRowMixin:OnLeave()
    app.ui.modelPreview:Clear()
    GameTooltip:Hide()
end

----------------------------------------------------------------------------------------------------
-- Tile: a picture card for entries of a `display = "tiles"` folder
----------------------------------------------------------------------------------------------------

-- How much brighter than painted a tile's picture is drawn: the picture is added onto itself
-- with this alpha (0 = as painted, 0.5 = strongly lifted). The shade bands behind the texts are
-- the two gradient alphas in SpyglassTileTemplate.
local TILE_PICTURE_BOOST = 0

local WHOLE_TEXTURE = { 0, 1, 0, 1 }

-- The file and texture coordinates of a tile's picture. `background` is a texture (path or
-- fileID) or an atlas name; `coords` pick the part to show, for an atlas within its own region.
---@param background string|number
---@param coords? number[]
---@return (string|number)? file, number left, number right, number top, number bottom
local function tilePicture(background, coords)
    local c = coords or WHOLE_TEXTURE
    local atlas = type(background) == "string" and C_Texture.GetAtlasInfo(background)
    if not atlas then
        return background, c[1], c[2], c[3], c[4]
    end
    local l, r, t, b = atlas.leftTexCoord, atlas.rightTexCoord, atlas.topTexCoord, atlas.bottomTexCoord
    local w, h = r - l, b - t
    return atlas.file or atlas.filename, l + w * c[1], l + w * c[2], t + h * c[3], t + h * c[4]
end

-- The dark box behind a bottom text: the text's width plus its 6px inset from the picture edge
-- on both sides, and only when there is a picture under it and a text to read.
local INFO_BOX_PADDING = 6

---@param box Texture
---@param text FontString
---@param hasPicture boolean
local function fitInfoBox(box, text, hasPicture)
    local show = hasPicture and (text:GetText() or "") ~= ""
    box:SetShown(show)
    if show then
        box:SetWidth(text:GetStringWidth() + 2 * INFO_BOX_PADDING)
    end
end

-- Clicking and hovering work exactly like a row, so those handlers are shared.
---@class Spyglass.Tile : Button
---@field Card Texture
---@field Background Texture
---@field Boost Texture
---@field TopShade Texture
---@field BottomShade Texture
---@field InfoBox Texture
---@field InfoRightBox Texture
---@field Icon Texture
---@field IconMask MaskTexture
---@field IconRing Texture
---@field Name FontString
---@field Info FontString
---@field InfoRight FontString
---@field node Spyglass.Node
---@field view Spyglass.View
---@field link? string
SpyglassTileMixin = {
    OnClick = SpyglassListRowMixin.OnClick,
    OnEnter = SpyglassListRowMixin.OnEnter,
    OnLeave = SpyglassListRowMixin.OnLeave,
}
app.ui.TileMixin = SpyglassTileMixin

---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassTileMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil

    self.Name:SetText(node.name or "?")
    local color = node.quality and ITEM_QUALITY_COLORS[node.quality] or NORMAL_FONT_COLOR
    self.Name:SetTextColor(color.r, color.g, color.b)
    self.Info:SetText(node.info or levelRangeText(node) or "")
    self.InfoRight:SetText(node.infoRight or "")

    local background = node.background
    self.Background:SetShown(background ~= nil)
    self.Boost:SetShown(background ~= nil and TILE_PICTURE_BOOST > 0)
    self.TopShade:SetShown(background ~= nil)
    self.BottomShade:SetShown(background ~= nil)
    fitInfoBox(self.InfoBox, self.Info, background ~= nil)
    fitInfoBox(self.InfoRightBox, self.InfoRight, background ~= nil)
    -- The icon stands in for a missing picture (centered) or, with `showIcon`, sits at the
    -- picture's left edge, between the name and the bottom texts.
    local showIcon = background == nil or node.showIcon == true
    self.Icon:SetShown(showIcon)
    self.IconRing:SetShown(showIcon)
    setIconQuality(self.IconRing, node.quality)
    if background then
        local file, left, right, top, bottom = tilePicture(background, node.backgroundCoords)
        for _, texture in ipairs({ self.Background, self.Boost }) do
            texture:SetTexture(file)
            texture:SetTexCoord(left, right, top, bottom)
        end
        self.Boost:SetAlpha(TILE_PICTURE_BOOST)
    end
    if showIcon then
        self.Icon:SetTexture(node.icon or FALLBACK_ICON)
        self.Icon:ClearAllPoints()
        if background then
            self.Icon:SetPoint("LEFT", 14, -3)
        else
            self.Icon:SetPoint("CENTER", 0, -2)
        end
    end
end

-- The client loads a texture file in the background when a texture first asks for it and drops
-- it again once no texture uses it, so a tile drawn before its picture has loaded shows it a few
-- frames late; and as the tile pool hands frames from one folder to the next, every visit can
-- load it anew. The stock profession overview avoids this by never changing a card's picture.
-- The same here: every tile picture gets a texture of its own that is set once and kept, on a
-- frame that is shown at alpha 0 (the world map keeps its loading tiles that way), so the files
-- load early and stay loaded.
local pictureHolder ---@type Frame?
local heldPictures = {} ---@type table<string|number, Texture>

---@param background string|number
local function holdPicture(background)
    local file = tilePicture(background)
    if file == nil or heldPictures[file] then
        return
    end
    if not pictureHolder then
        pictureHolder = CreateFrame("Frame", nil, UIParent)
        pictureHolder:SetSize(1, 1)
        pictureHolder:SetPoint("TOPLEFT")
        pictureHolder:SetAlpha(0)
    end
    local texture = pictureHolder:CreateTexture()
    texture:SetAllPoints()
    texture:SetTexture(file)
    heldPictures[file] = texture
end
----------------------------------------------------------------------------------------------------

-- The card's picture region: the template's 2:1 size for art files, a square for a portrait
-- the client renders from a creature display id (those come out square and would stretch).
local PORTRAIT_WIDTH, PORTRAIT_HEIGHT, PORTRAIT_SQUARE = 112, 56, 58

---@class Spyglass.Card : Button
---@field Card Texture
---@field Portrait Texture
---@field Icon Texture
---@field IconMask MaskTexture
---@field IconRing Texture
---@field Arrow Texture
---@field QuestIcon Texture
---@field Name FontString
---@field Info FontString
---@field InfoRight FontString
---@field node Spyglass.Node
---@field view Spyglass.View
---@field link? string
SpyglassCardMixin = {
    OnClick = SpyglassListRowMixin.OnClick,
    OnEnter = SpyglassListRowMixin.OnEnter,
    OnLeave = SpyglassListRowMixin.OnLeave,
}
app.ui.CardMixin = SpyglassCardMixin

---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassCardMixin:Init(view, node)
    self.view = view
    self.node = node
    self.link = nil

    self.Name:SetText(node.name or "?")
    local color = node.quality and ITEM_QUALITY_COLORS[node.quality] or HIGHLIGHT_FONT_COLOR
    self.Name:SetTextColor(color.r, color.g, color.b)
    self.Info:SetText(node.info or levelRangeText(node) or "")
    -- A boss's saved-drop count can change while its folder node remains open.
    if node.meta and node.meta.bossID then
        node.infoRight = app.bossInterestText(node.meta.bossID)
    end
    self.InfoRight:SetText(node.infoRight or "")
    self.Arrow:SetShown(app.api.IsFolder(node))
    self.QuestIcon:SetShown(node.quests ~= nil and #node.quests > 0)

    -- A picture beats a generated portrait beats the entry's icon. Art files are 2:1 busts
    -- (the client's own boss art is 128x64), while a portrait the client renders from a
    -- creature display id is square, so the region takes the shape of what fills it.
    local portrait, displayID = node.portrait, node.portraitDisplayID
    local hasPortrait = portrait ~= nil or displayID ~= nil
    self.Portrait:SetShown(hasPortrait)
    self.Icon:SetShown(not hasPortrait)
    self.IconRing:SetShown(not hasPortrait)
    setIconQuality(self.IconRing, node.quality)
    self.Portrait:ClearAllPoints()
    if portrait then
        self.Portrait:SetSize(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
        self.Portrait:SetPoint("BOTTOMLEFT", 2, 5)
        self.Portrait:SetTexture(portrait)
    elseif displayID then
        self.Portrait:SetSize(PORTRAIT_SQUARE, PORTRAIT_SQUARE)
        self.Portrait:SetPoint("LEFT", (PORTRAIT_WIDTH - PORTRAIT_SQUARE) / 2, 0)
        SetPortraitTextureFromCreatureDisplayID(self.Portrait, displayID)
    else
        self.Icon:SetTexture(node.icon or FALLBACK_ICON)
    end
end

----------------------------------------------------------------------------------------------------
-- Group label (row-sized, lighter than a page header)
----------------------------------------------------------------------------------------------------

---@class Spyglass.GroupLabel : Frame
---@field Text FontString
---@field Line Texture
SpyglassGroupLabelMixin = {}
app.ui.GroupLabelMixin = SpyglassGroupLabelMixin

---@param text string
function SpyglassGroupLabelMixin:Init(text)
    self.Text:SetText(text)
end

----------------------------------------------------------------------------------------------------
-- Subheader (small section title: one step under a page header, above the group labels)
----------------------------------------------------------------------------------------------------

---@class Spyglass.Subheader : Frame
---@field Text FontString
---@field LineLeft Texture
---@field LineRight Texture
---@field node? Spyglass.Node
SpyglassSubheaderMixin = {}
app.ui.SubheaderMixin = SpyglassSubheaderMixin

-- How much of the flanking lines has to stay visible on each side; a title that would leave
-- less than this is truncated instead (the text is centered, so both sides shrink together).
local SUBHEADER_LINE_MIN = 20

---@param text string
---@param node? Spyglass.Node
function SpyglassSubheaderMixin:Init(text, node)
    self.node = node
    self:EnableMouse(node ~= nil and node.onClick ~= nil)
    self.Text:SetFontObject(node and node.onClick and GameFontNormalMed2 or GameFontNormal)
    self.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    self.Text:SetText(text)
    self:UpdateText()
end

function SpyglassSubheaderMixin:OnEnter()
    if self.node and self.node.onClick then
        self.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    end
end

function SpyglassSubheaderMixin:OnLeave()
    self.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
end

---@param button string
function SpyglassSubheaderMixin:OnMouseUp(button)
    if self.node and self.node.onClick then
        self.node.onClick(self.node, button)
    end
end

function SpyglassSubheaderMixin:OnSizeChanged()
    self:UpdateText()
end

function SpyglassSubheaderMixin:UpdateText()
    -- Width 0 = size to the text; the lines are anchored to its edges and follow along.
    self.Text:SetWidth(0)
    local maximum = self:GetWidth() - 2 * SUBHEADER_LINE_MIN
    if maximum > 0 and self.Text:GetStringWidth() > maximum then
        self.Text:SetWidth(maximum)
    end
end

----------------------------------------------------------------------------------------------------
-- Quest banner (a quest spanning the list's width, its rewards below it)
----------------------------------------------------------------------------------------------------

---@class Spyglass.QuestBanner : Button
---@field Backplate Texture
---@field TreeLine Texture
---@field Icon Texture
---@field Line Texture
---@field Title FontString
---@field Info FontString
---@field Objective FontString
---@field XP FontString
---@field Status FontString
---@field AllianceLogo Texture
---@field HordeLogo Texture
---@field showAllianceLogo boolean
---@field showHordeLogo boolean
---@field node Spyglass.Node
---@field view Spyglass.View
SpyglassQuestBannerMixin = {}
app.ui.QuestBannerMixin = SpyglassQuestBannerMixin

local NO_REWARDS = "No rewards"

---@param view Spyglass.View
---@param node Spyglass.Node
function SpyglassQuestBannerMixin:Init(view, node)
    self.view = view
    self.node = node
    self.TreeLine:SetShown((node.indent or 0) > 0)
    local Quests = app.questInfo
    local questID = node.quest --[[@as integer]]
    local quest = Data:GetQuest(questID)
    Quests.Link(questID) -- loads the quest ahead of hover and click; its title may follow

    self.Title:SetText(Data:GetQuestName(questID))
    self.Info:SetText(node.info or "")
    local objective = quest and quest.objective or ""
    if node.prerequisiteIDs then
        local done = 0
        for _, id in ipairs(node.prerequisiteIDs) do
            if C_QuestLog.IsQuestFlaggedCompleted(id) then
                done = done + 1
            end
        end
        local progress = ("Prequests %d/%d"):format(done, #node.prerequisiteIDs)
        objective = objective ~= "" and (progress .. " \194\183 " .. objective) or progress
    end
    self.Objective:SetText(objective)
    local side = quest and quest.side
    self.showAllianceLogo = side ~= "Horde"
    self.showHordeLogo = side ~= "Alliance"
    self.AllianceLogo:SetShown(self.showAllianceLogo)
    self.HordeLogo:SetShown(self.showHordeLogo)
    self.AllianceLogo:ClearAllPoints()
    if self.showHordeLogo then
        self.AllianceLogo:SetPoint("RIGHT", self.HordeLogo, "LEFT", -2, 0)
    else
        self.AllianceLogo:SetPoint("RIGHT", self.XP, "LEFT", -3, -4)
    end
    local status, color, icon = Quests.Status(questID)
    self.Status:SetText(status)
    self.Status:SetTextColor(color:GetRGB())
    self.Icon:SetTexture(icon)
    if quest and quest.xp then
        local xp = quest.xp >= 100000 and ("%dk"):format(math.floor(quest.xp / 1000)) or Quests.FormatXP(quest.xp)
        self.XP:SetText(("%s %s"):format(xp, NORMAL_FONT_COLOR:WrapTextInColorCode("XP")))
        self.XP:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    elseif not quest or #quest.items == 0 then
        self.XP:SetText(NO_REWARDS)
        self.XP:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    else
        self.XP:SetText("")
    end
    self:UpdateTitle()
end

function SpyglassQuestBannerMixin:OnSizeChanged()
    self:UpdateTitle()
end

-- Width 0 = size to the text, so the info follows the title; a title that would run into the
-- faction emblems and experience on the right is truncated instead.
function SpyglassQuestBannerMixin:UpdateTitle()
    self.Title:SetWidth(0)
    local left = select(4, self.Title:GetPoint(1)) or 0
    local info = self.Info:GetText()
    local infoWidth = info and info ~= "" and self.Info:GetStringWidth() + 10 or 0
    local logosWidth = (self.showAllianceLogo and 32 or 0) + (self.showHordeLogo and 32 or 0)
    local maximum = self:GetWidth() - left - infoWidth - self.XP:GetWidth() - logosWidth - 24
    if maximum > 0 and self.Title:GetStringWidth() > maximum then
        self.Title:SetWidth(maximum)
    end
end

---@param button string
function SpyglassQuestBannerMixin:OnClick(button)
    if button == "RightButton" then
        self.view:Back()
    elseif IsShiftKeyDown() then
        app.questInfo.HandleModifiedClick(self.node.quest --[[@as integer]])
    elseif app.api.IsFolder(self.node) then
        self.view:Push(self.node)
    else
        app.questInfo.HandleModifiedClick(self.node.quest --[[@as integer]])
    end
end

function SpyglassQuestBannerMixin:OnEnter()
    app.questInfo.ShowTooltip(self, self.node.quest --[[@as integer]])
end

function SpyglassQuestBannerMixin:OnLeave()
    GameTooltip:Hide()
end

----------------------------------------------------------------------------------------------------
-- Page header (section title on the character frame's category plate)
----------------------------------------------------------------------------------------------------

---@class Spyglass.PageHeader : Frame
---@field Backplate Texture
---@field Text FontString
SpyglassPageHeaderMixin = {}
app.ui.PageHeaderMixin = SpyglassPageHeaderMixin

-- The plate behind the text: text width plus this much on each side, but never wider than
-- the header itself.
local HEADER_PLATE_PADDING = 40

---@param text string
function SpyglassPageHeaderMixin:Init(text)
    self.Text:SetText(text)
    self:UpdatePlate()
end

function SpyglassPageHeaderMixin:OnSizeChanged()
    self:UpdatePlate()
end

function SpyglassPageHeaderMixin:UpdatePlate()
    local width = self.Text:GetStringWidth() + 2 * HEADER_PLATE_PADDING
    self.Backplate:SetWidth(math.min(width, self:GetWidth()))
end

----------------------------------------------------------------------------------------------------
-- Breadcrumb button
----------------------------------------------------------------------------------------------------

---@class Spyglass.BreadcrumbButton : Button
---@field Text FontString
---@field layoutIndex integer
---@field view Spyglass.View
---@field index integer
SpyglassBreadcrumbButtonMixin = {}
app.ui.BreadcrumbButtonMixin = SpyglassBreadcrumbButtonMixin

---@param view Spyglass.View
---@param index integer  # position in view.path
---@param text string
---@param isCurrent boolean
function SpyglassBreadcrumbButtonMixin:Init(view, index, text, isCurrent)
    self.view = view
    self.index = index
    self:SetText(text)
    self:SetWidth(self.Text:GetStringWidth() + 8)
    self:SetEnabled(not isCurrent)
end

function SpyglassBreadcrumbButtonMixin:OnClick()
    self.view:PopTo(self.index)
end

----------------------------------------------------------------------------------------------------
-- Search box (query toolbar)
----------------------------------------------------------------------------------------------------

---@class Spyglass.SearchBox : EditBox
---@field Instructions FontString
---@field clearButton Button
---@field debounce? FunctionContainer  # C_Timer handle
SpyglassSearchBoxMixin = {}
app.ui.SearchBoxMixin = SpyglassSearchBoxMixin

-- Runs after SearchBoxTemplate_OnTextChanged (prepend). Typing is debounced; programmatic
-- SetText (userInput = false) never triggers a query.
---@param userInput boolean
function SpyglassSearchBoxMixin:OnTextChanged(userInput)
    if not userInput then
        return
    end
    if self.debounce then
        self.debounce:Cancel()
    end
    self.debounce = C_Timer.NewTimer(SEARCH_DEBOUNCE, function()
        self.debounce = nil
        local view = self:GetParent() --[[@as Spyglass.View]]
        view:SetSearch(self:GetText())
    end)
end

----------------------------------------------------------------------------------------------------
-- Class filter button (footer): the class's icon in an item slot frame
----------------------------------------------------------------------------------------------------

-- The frame around the button's icon while the filter is on; off, it is the plain frame and the
-- icon is grey.
local CLASS_FILTER_ON_COLOR = NORMAL_FONT_COLOR

---@class Spyglass.ClassFilterButton : Button
---@field Icon Texture
---@field IconMask MaskTexture
---@field IconRing Texture
SpyglassClassFilterButtonMixin = {}
app.ui.ClassFilterButtonMixin = SpyglassClassFilterButtonMixin

---@return Spyglass.View
function SpyglassClassFilterButtonMixin:GetView()
    return self:GetParent() --[[@as Spyglass.View]]
end

-- Shows the view's class and whether the filter is on.
function SpyglassClassFilterButtonMixin:Update()
    local view = self:GetView()
    self.Icon:SetTexture(app.classFilter:GetIcon(view:GetFilterClass()))
    self.Icon:SetDesaturated(not view.classFilterOn)
    local color = view.classFilterOn and CLASS_FILTER_ON_COLOR or HIGHLIGHT_FONT_COLOR
    self.IconRing:SetVertexColor(color.r, color.g, color.b)
end

-- Left-click turns the filter on and off, right-click opens the class and mode menu.
---@param button string
function SpyglassClassFilterButtonMixin:OnClick(button)
    local view = self:GetView()
    if button == "RightButton" then
        MenuUtil.CreateContextMenu(self, function(_, root)
            view:BuildClassFilterMenu(root)
        end)
    else
        view:SetClassFilter(not view.classFilterOn)
    end
    if GameTooltip:IsOwned(self) then
        self:OnEnter()
    end
end

function SpyglassClassFilterButtonMixin:OnEnter()
    local view = self:GetView()
    local name = app.classFilter:GetName(view:GetFilterClass())
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Class filter: " .. name)
    if not view.classFilterOn then
        GameTooltip:AddLine("Off", 1, 1, 1)
    elseif view.classFilterMode == "fade" then
        GameTooltip:AddLine(("Fades armor and weapons a %s can't use"):format(name), 1, 1, 1, true)
    else
        GameTooltip:AddLine(("Hides armor and weapons a %s can't use"):format(name), 1, 1, 1, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click to turn on or off", 0.5, 0.5, 0.5)
    GameTooltip:AddLine("Right-click to pick the class", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function SpyglassClassFilterButtonMixin:OnLeave()
    GameTooltip:Hide()
end

-- The button next to it: whether the items the class can't use are faded out or hidden. A click
-- switches; like the class button it is grey while the filter is off.
local CLASS_FILTER_MODE_ICONS = {
    fade = "Interface\\Icons\\Spell_Nature_Invisibilty",
    hide = "Interface\\Icons\\Ability_Vanish",
}

---@class Spyglass.ClassFilterModeButton : Spyglass.ClassFilterButton
SpyglassClassFilterModeButtonMixin = {
    GetView = SpyglassClassFilterButtonMixin.GetView,
    OnLeave = SpyglassClassFilterButtonMixin.OnLeave,
}
app.ui.ClassFilterModeButtonMixin = SpyglassClassFilterModeButtonMixin

function SpyglassClassFilterModeButtonMixin:Update()
    local view = self:GetView()
    self.Icon:SetTexture(CLASS_FILTER_MODE_ICONS[view.classFilterMode])
    self.Icon:SetDesaturated(not view.classFilterOn)
    local color = view.classFilterOn and CLASS_FILTER_ON_COLOR or HIGHLIGHT_FONT_COLOR
    self.IconRing:SetVertexColor(color.r, color.g, color.b)
end

function SpyglassClassFilterModeButtonMixin:OnClick()
    local view = self:GetView()
    view:SetClassFilter(nil, nil, view.classFilterMode == "fade" and "hide" or "fade")
    if GameTooltip:IsOwned(self) then
        self:OnEnter()
    end
end

function SpyglassClassFilterModeButtonMixin:OnEnter()
    local view = self:GetView()
    local fade = view.classFilterMode == "fade"
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(fade and "Fade out" or "Hide")
    GameTooltip:AddLine(
        ("Armor and weapons a %s can't use are %s"):format(
            app.classFilter:GetName(view:GetFilterClass()),
            fade and "faded out" or "hidden"
        ),
        1,
        1,
        1,
        true
    )
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(fade and "Click to hide them instead" or "Click to fade them out instead", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

----------------------------------------------------------------------------------------------------
-- Options page: "Spyglass > Options", opened by the window's gear button
----------------------------------------------------------------------------------------------------

-- A page of its own, not a module: it lists nothing, and the AceConfig options of options.lua are
-- drawn in its list area instead. Only one view is shown at a time, so one AceGUI container
-- serves every tab; the view on the options page borrows it (showOptionsIn).
local OPTIONS_NODE = { name = "Options", icon = "Interface\\Buttons\\UI-OptionsButton" }
---@type AceGUIContainer?, Frame?
local optionsGroup, optionsFrame
-- The container holds the current options; cleared whenever it hides.
local optionsFed = false

local function feedOptions()
    LibStub("AceConfigDialog-3.0"):Open(appName, optionsGroup)
    optionsFed = true
end

-- Puts the options into `page` (a view's list area). They are fed anew after being hidden, so what
-- changed meanwhile (in the Settings panel, say) is drawn.
---@param page Frame
local function showOptionsIn(page)
    if not optionsGroup then
        -- The container the Settings panel uses too: AceConfigDialog puts a scroll frame in it.
        local group = LibStub("AceGUI-3.0"):Create("BlizOptionsGroup") --[[@as table]]
        -- The page header already says "Options": keep AceConfigDialog from adding its title.
        local setTitle = group.SetTitle
        group.SetTitle = function(widget)
            setTitle(widget, nil)
        end
        group:SetTitle()
        group:SetCallback("OnHide", function()
            optionsFed = false
        end)
        optionsGroup, optionsFrame = group, group.frame
        -- A setting changed elsewhere (profile switch, /sg loglevel): redraw the shown options.
        LibStub("AceConfigRegistry-3.0").RegisterCallback(OPTIONS_NODE, "ConfigTableChange", function(_, changed)
            if changed == appName and optionsFrame:IsVisible() then
                feedOptions()
            end
        end)
    end
    if optionsFrame:GetParent() ~= page then
        optionsFrame:SetParent(page)
        optionsFrame:ClearAllPoints()
        optionsFrame:SetAllPoints(page)
    end
    optionsFrame:Show()
    if not optionsFed then
        feedOptions()
    end
end

---@param page Frame
local function hideOptionsIn(page)
    if optionsFrame and optionsFrame:GetParent() == page then
        optionsFrame:Hide()
    end
end

----------------------------------------------------------------------------------------------------
-- View: breadcrumb bar + one page of rows
----------------------------------------------------------------------------------------------------

---@class Spyglass.FilterDropdown : Frame, WowStyle1FilterDropdownMixin

---@class Spyglass.PagingControls : Frame, PagingControlsMixin

---@class Spyglass.View : Frame
---@field Breadcrumbs Spyglass.LayoutFrame
---@field HeaderDivider Texture
---@field FooterDivider Texture
---@field Title Spyglass.PageHeader
---@field Content Spyglass.Page
---@field PagingControls Spyglass.PagingControls
---@field SearchBox Spyglass.SearchBox
---@field FilterDropdown Spyglass.FilterDropdown
---@field ResultCount FontString
---@field ClassFilter Spyglass.ClassFilterButton
---@field ClassFilterMode Spyglass.ClassFilterModeButton
---@field ActiveList WowStyle1FilterDropdownMixin|Frame  # the footer's active list dropdown
---@field classFilterOn boolean  # the footer's class filter is on, for this tab
---@field classFilterMode "hide"|"fade"  # what it does to the items the class can't use
---@field filterClass? string  # the class it filters for; nil = the character's own
---@field queries table<Spyglass.Node, Spyglass.Query>  # filter state per query node, for this tab
---@field resultCount integer  # size of the last query result
---@field panelState table<Spyglass.Node, table<integer, any>>  # per panel node: the value of each checkbox/dropdown/grouping widget (by index), for this tab
---@field crumbPool Spyglass.FramePool
---@field separatorPool Spyglass.FramePool
---@field rowHeight number
---@field tileHeight number
---@field cardHeight number
---@field headerHeight number
---@field headerGap number
---@field subheaderHeight number
---@field subheaderGap number
---@field questHeight number
---@field questGap number
---@field columnGap number
---@field pages Spyglass.PageRange[]  # layout result for the current node (into `layout`)
---@field path Spyglass.Node[]
---@field pathPages integer[]  # pathPages[i] = the page path[i] was on when a deeper node was opened
---@field onNavigate? fun(view: Spyglass.View)
---@field pendingItems table<integer, boolean>  # itemIDs whose info hasn't arrived yet
---@field regroupItems table<integer, boolean>  # items grouped without their kind: true = waiting to regroup, false = done
---@field renderQueued? boolean  # a deferred Render is scheduled (item info arrived)
---@field refreshQueued? boolean  # the deferred redraw is a Refresh (an item to regroup arrived)
---@field showsQuests? boolean  # the current list has quest banners, which redraw on quest events
SpyglassViewMixin = {}
app.ui.ViewMixin = SpyglassViewMixin

-- The list area: pooled rows/tiles/headers/group labels are placed from its top-left corner.
---@class Spyglass.Page : Frame
---@field rowPool Spyglass.FramePool
---@field tilePool Spyglass.FramePool
---@field cardPool Spyglass.FramePool
---@field headerPool Spyglass.FramePool
---@field subheaderPool Spyglass.FramePool
---@field questPool Spyglass.FramePool
---@field groupPool Spyglass.FramePool

-- What a page displays. `kind` picks the template; new element kinds plug in here
-- (BuildElements, LayoutPages, RenderPage). A `spacer` is one row of empty space: it takes
-- part in the layout but draws nothing.
---@class Spyglass.Element
---@field kind "header"|"subheader"|"quest"|"group"|"spacer"|"row"|"tile"|"card"
---@field text? string  # header, subheader, group
---@field node? Spyglass.Node  # quest, row, tile, card
---@field source? Spyglass.Node  # clickable subheader

-- Where every element of the current layout goes, as parallel arrays indexed by placement
-- order; a page is a range of them. Shared by all views: only the shown view lays out and
-- draws (a hidden one refreshes when shown, see Refresh), so one buffer serves every tab
-- instead of a table per placed row per tab -- a 25k-item list is ~2 MB here, not ~7 MB each.
---@class Spyglass.Layout
---@field element Spyglass.Element[]
---@field x number[]
---@field y number[]
---@field width number[]
---@field height number[]
local layout = { element = {}, x = {}, y = {}, width = {}, height = {} }

---@class Spyglass.PageRange
---@field first integer  # index into `layout`
---@field last integer

-- One element per (kind, node), shared across refreshes: a 25k-item query would otherwise
-- allocate 25k of them every time the list is rebuilt.
---@type table<string, table<Spyglass.Node, Spyglass.Element>>
local entryElements = { row = {}, tile = {}, card = {} }

---@param kind "row"|"tile"|"card"
---@param node Spyglass.Node
---@return Spyglass.Element
local function entryElement(kind, node)
    local byNode = entryElements[kind]
    local element = byNode[node]
    if not element then
        element = { kind = kind, node = node }
        byNode[node] = element
    end
    return element
end

function SpyglassViewMixin:OnLoad()
    self.path = {}
    self.pathPages = {}

    local page = self.Content
    page.rowPool = CreateFramePool("Button", page, "SpyglassListRowTemplate") --[[@as Spyglass.FramePool]]
    page.tilePool = CreateFramePool("Button", page, "SpyglassTileTemplate") --[[@as Spyglass.FramePool]]
    page.cardPool = CreateFramePool("Button", page, "SpyglassCardTemplate") --[[@as Spyglass.FramePool]]
    page.headerPool = CreateFramePool("Frame", page, "SpyglassPageHeaderTemplate") --[[@as Spyglass.FramePool]]
    page.subheaderPool = CreateFramePool("Frame", page, "SpyglassSubheaderTemplate") --[[@as Spyglass.FramePool]]
    page.questPool = CreateFramePool("Button", page, "SpyglassQuestBannerTemplate") --[[@as Spyglass.FramePool]]
    page.groupPool = CreateFramePool("Frame", page, "SpyglassGroupLabelTemplate") --[[@as Spyglass.FramePool]]
    self.pages = {}
    self.pendingItems = {}
    self.regroupItems = {}
    self.queries = {}
    self.panelState = {}
    self.classFilterOn = false
    self.classFilterMode = "fade"
    self.resultCount = 0
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    -- Quest banners show the character's progress and the client's quest title.
    self:RegisterEvent("QUEST_LOG_UPDATE")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("QUEST_DATA_LOAD_RESULT")

    -- The template's clear button sets the text programmatically (userInput = false), so the
    -- debounce never sees it; clear the query directly.
    self.SearchBox.clearButton:HookScript("OnClick", function()
        self:SetSearch("")
    end)
    self.FilterDropdown:SetupMenu(function(_, rootDescription)
        self:BuildFilterMenu(rootDescription)
    end)
    -- The template's red X over the button's corner: shown while filters or sort differ from
    -- the defaults or the class filter is on, a click resets them.
    self.FilterDropdown:SetIsDefaultCallback(function()
        local q = self:GetCurrentQuery()
        return not q or (self:IsDefaultQuery(q) and not self.classFilterOn)
    end)
    self.FilterDropdown:SetDefaultCallback(function()
        local q = self:GetCurrentQuery()
        if q then
            self:ResetFilters(q)
        end
    end)

    -- The footer's active list: every list with its marker, the active one picked. The text
    -- follows changes made elsewhere (Render).
    local Lists = app.lists
    self.ActiveList:SetupMenu(function(_, rootDescription)
        for _, id in ipairs(Lists:GetAll()) do
            local list = Lists:Get(id) --[[@as Spyglass.ItemList]]
            rootDescription:CreateRadio(Lists:GetMarkerMarkup(id, 14) .. " " .. list.name, function()
                return Lists:GetActive() == id
            end, function()
                Lists:SetActive(id)
            end)
        end
    end)
    self.ActiveList:HookScript("OnEnter", function(dropdown)
        GameTooltip:SetOwner(dropdown, "ANCHOR_TOP")
        GameTooltip:AddLine("Active list")
        GameTooltip:AddLine("Alt-click an item to add it to this list, or to remove it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    self.ActiveList:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.crumbPool = CreateFramePool("Button", self.Breadcrumbs, "SpyglassBreadcrumbButtonTemplate") --[[@as Spyglass.FramePool]]
    self.separatorPool = CreateFramePool("Frame", self.Breadcrumbs, "SpyglassBreadcrumbSeparatorTemplate") --[[@as Spyglass.FramePool]]
end

function SpyglassViewMixin:OnShow()
    self:Refresh()
end

-- Wheel up = previous page, wheel down = next page (PagingControls handles the clamping).
---@param delta number
function SpyglassViewMixin:OnMouseWheel(delta)
    self.PagingControls:OnMouseWheel(delta)
end

-- Right-click on empty page space goes one level back, like closing a folder.
---@param button string
function SpyglassViewMixin:OnMouseUp(button)
    if button == "RightButton" then
        self:Back()
    end
end

-- Item data arrives asynchronously; redraw once something we're showing has loaded. Several
-- can arrive in one frame, so the redraw is deferred to the next frame and done once. An item
-- the list was grouped without (see Refresh) is regrouped: a Refresh instead of a Render, once
-- per item, so an item the server never answers for can't loop.
---@param event string
---@param itemID integer
function SpyglassViewMixin:OnEvent(event, itemID)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if not self.pendingItems[itemID] then
            return
        end
        self.pendingItems[itemID] = nil
        if self.regroupItems[itemID] then
            self.regroupItems[itemID] = false
            self.refreshQueued = true
        end
    elseif not self.showsQuests then
        -- A quest event: only quest banners show anything of it.
        return
    end
    -- Never directly: drawing a quest banner asks the server for the quest, whose
    -- QUEST_DATA_LOAD_RESULT can fire inside that call.
    if self:IsShown() and not self.renderQueued then
        self.renderQueued = true
        C_Timer.After(0, function()
            local refresh = self.refreshQueued
            self.renderQueued, self.refreshQueued = nil, nil
            if self:IsShown() then
                if refresh then
                    self:Refresh()
                else
                    self:Render()
                end
            end
        end)
    end
end

---@param itemID integer
function SpyglassViewMixin:RequestItem(itemID)
    if not self.pendingItems[itemID] then
        self.pendingItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

---@param root Spyglass.Node
function SpyglassViewMixin:SetRoot(root)
    self.path = { root }
    self.pathPages = {}
    self:Navigate()
end

-- Opens `node` below the current one; the current node's page is kept for the way back.
---@param node Spyglass.Node
function SpyglassViewMixin:Push(node)
    self.pathPages[#self.path] = self.PagingControls:GetCurrentPage()
    self.path[#self.path + 1] = node
    self:Navigate()
end

-- Goes back to path[index], on the page it was left on.
---@param index integer
function SpyglassViewMixin:PopTo(index)
    for i = #self.path, index + 1, -1 do
        self.path[i] = nil
    end
    local page = self.pathPages[index]
    for i = #self.pathPages, index, -1 do
        self.pathPages[i] = nil
    end
    self:Navigate(page)
end

function SpyglassViewMixin:Back()
    if #self.path > 1 then
        self:PopTo(#self.path - 1)
    end
end

---@return Spyglass.Node?
function SpyglassViewMixin:GetCurrentNode()
    return self.path[#self.path]
end

-- Opens the options page right below the root, or goes back to the root when it is open.
function SpyglassViewMixin:ToggleOptions()
    if self:IsShowingOptions() then
        self:PopTo(1)
    else
        self.path = { self.path[1], OPTIONS_NODE }
        self.pathPages = {}
        self:Navigate()
    end
end

---@return boolean
function SpyglassViewMixin:IsShowingOptions()
    return self:GetCurrentNode() == OPTIONS_NODE
end

---@return string
function SpyglassViewMixin:GetTitle()
    local node = self:GetCurrentNode()
    return node and node.name or "New Tab"
end

-- The folders open below the root, "Crafting > Alchemy > Camping", for the tab's tooltip; nil at
-- the root.
---@return string?
function SpyglassViewMixin:GetPathText()
    local names = {}
    for i = 2, #self.path do
        names[#names + 1] = self.path[i].name or "?"
    end
    return #names > 0 and table.concat(names, " > ") or nil
end

-- The icon of the deepest node on the path that has one (the root carries the addon's), for the tab.
---@return string|number|nil
function SpyglassViewMixin:GetIcon()
    for i = #self.path, 1, -1 do
        local icon = self.path[i].icon
        if icon then
            return icon
        end
    end
    return nil
end

-- Called after any path change: reset paging (or go to `page`, when coming back to a node),
-- redraw, and let the owner update the tab label.
---@param page? integer
function SpyglassViewMixin:Navigate(page)
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
    -- After Refresh: SetCurrentPage clamps to the page count, which only now is this node's.
    if page and page > 1 then
        self.PagingControls:SetCurrentPage(page)
    end
    if self.onNavigate then
        self.onNavigate(self)
    end
end

-- PagingControls calls this on its parent when the page changes. The layout is unchanged,
-- so only the visible pages are redrawn.
function SpyglassViewMixin:OnPageChanged()
    if app.ui.HidePopups then
        app.ui.HidePopups()
    end
    self:Render()
end

----------------------------------------------------------------------------------------------------
-- Children: static, dynamic and query folders
----------------------------------------------------------------------------------------------------

-- The entries to list for a folder node. Query folders run the view's query over the item DB.
---@param node Spyglass.Node
---@return Spyglass.Node[]
function SpyglassViewMixin:GetChildren(node)
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

-- Loads the pictures of the tiles in the root's tile folders (Dungeons, Raids, Crafting, …)
-- ahead of the first visit and keeps them loaded (see holdPicture).
function SpyglassViewMixin:PreloadTilePictures()
    for _, module in ipairs(self:GetChildren(self.path[1])) do
        if module.display == "tiles" then
            for _, child in ipairs(self:GetChildren(module)) do
                if child.background then
                    holdPicture(child.background)
                end
            end
        end
    end
end

-- The query state of a query folder, created on first use and kept while this tab lives.
---@param node Spyglass.Node
---@return Spyglass.Query
function SpyglassViewMixin:GetQuery(node)
    local q = self.queries[node]
    if not q then
        q = app.query.New()
        self.queries[node] = q
    end
    return q
end

---@param node Spyglass.Node
---@return Spyglass.Node[]
function SpyglassViewMixin:GetQueryChildren(node)
    local ids = app.query.Run(self:GetQuery(node))
    self.resultCount = #ids
    local children = {}
    for i, itemID in ipairs(ids) do
        children[i] = nodeForItem(itemID)
    end
    return children
end

-- The current node's query, or nil when it isn't a query folder.
---@return Spyglass.Query?, Spyglass.Node?
function SpyglassViewMixin:GetCurrentQuery()
    local node = self:GetCurrentNode()
    if node and node.query then
        return self:GetQuery(node), node
    end
    return nil, node
end

-- Search/filter changed: back to page 1 and re-run.
function SpyglassViewMixin:OnQueryChanged()
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
end

----------------------------------------------------------------------------------------------------
-- Info panel: the right pane's widgets for the current path, and what they do to the list
----------------------------------------------------------------------------------------------------

-- Standings as the curated rows spell them, in the game's order.
local STANDING_RANK = {
    Hated = 1,
    Hostile = 2,
    Unfriendly = 3,
    Neutral = 4,
    Friendly = 5,
    Honored = 6,
    Revered = 7,
    Exalted = 8,
}

-- The built-in checkbox filters, by the id a panel widget's `filter` names: does `entry` stay
-- in the list? `node` is the node the panel belongs to.
---@type table<string, fun(entry: Spyglass.Node, node: Spyglass.Node): boolean>
local PANEL_FILTERS = {
    -- Only my faction: rows restricted to the other faction are hidden.
    side = function(entry)
        local side = entry.meta and entry.meta.side
        return side == nil or side == UnitFactionGroup("player")
    end,
    -- Reached standings only: rewards above the character's standing with the list's faction
    -- are hidden (a faction the character hasn't met counts as Neutral).
    standing = function(entry, node)
        local rank = entry.meta and STANDING_RANK[entry.meta.standing]
        if not rank then
            return true
        end
        local factionID = node.meta and node.meta.factionID
        local data = factionID and C_Reputation and C_Reputation.GetFactionDataByID(factionID)
        return rank <= (data and data.reaction or STANDING_RANK.Neutral)
    end,
}

-- The deepest node on the path that has a `panel`, and its widgets (a function panel is called
-- each time). Nil when no node on the path has one.
---@return Spyglass.Node?, Spyglass.PanelWidget[]?
function SpyglassViewMixin:GetPanel()
    for i = #self.path, 1, -1 do
        local node = self.path[i]
        local panel = node.panel
        if type(panel) == "function" then
            local ok, result = pcall(panel, node, self)
            if not ok then
                log:error("%s: panel failed: %s", tostring(node.name), tostring(result))
            end
            panel = ok and result or nil
        end
        if type(panel) == "table" then
            return node, panel
        end
    end
    return nil, nil
end

-- The value a panel's checkbox (true/nil), dropdown (the picked value, nil = all) or grouping
-- (the picked option's index, nil = the first) has in this tab.
---@param node Spyglass.Node  # the panel's node
---@param index integer  # the widget's index in the panel
---@return any
function SpyglassViewMixin:GetPanelValue(node, index)
    local state = self.panelState[node]
    return state and state[index]
end

-- A checkbox, dropdown or grouping changed: the list is filtered and grouped again, from page 1.
---@param node Spyglass.Node
---@param index integer
---@param value any
function SpyglassViewMixin:SetPanelValue(node, index, value)
    local state = self.panelState[node]
    if not state then
        state = {}
        self.panelState[node] = state
    end
    state[index] = value
    self.PagingControls:SetCurrentPage(1)
    self:Refresh()
end

-- The grouping the current panel's `grouping` dropdown has picked in this tab (its first option
-- until another is picked). `found` is false when the panel has none, and the list keeps its own.
---@return boolean found, ("auto"|fun(node: Spyglass.Node): string?, string?|false)? groupBy
function SpyglassViewMixin:GetPanelGrouping()
    local node, widgets = self:GetPanel()
    if not node or not widgets then
        return false, nil
    end
    for index, widget in ipairs(widgets) do
        local options = widget.grouping and widget.options
        if options and #options > 0 then
            local option = options[self:GetPanelValue(node, index) or 1] or options[1]
            return true, option.groupBy
        end
    end
    return false, nil
end

-- The test the current panel's checkboxes and dropdowns put on the list's entries, or nil when
-- none is set. BuildElements keeps ordinary folders but can hide quest banners by faction.
---@return (fun(entry: Spyglass.Node): boolean)?
function SpyglassViewMixin:GetEntryFilter()
    local node, widgets = self:GetPanel()
    local state = node and self.panelState[node]
    if not node or not widgets then
        return nil
    end
    local tests = {}
    for index, widget in ipairs(widgets) do
        local value = state and state[index]
        if widget.checkbox and value then
            local filter = widget.filter
            local test = type(filter) == "function" and filter or PANEL_FILTERS[filter]
            if test then
                tests[#tests + 1] = function(entry)
                    return test(entry, node)
                end
            end
        elseif widget.dropdown and value ~= nil then
            local field = widget.field
            tests[#tests + 1] = function(entry)
                return entry.meta ~= nil and entry.meta[field] == value
            end
        elseif widget.factionDropdown then
            local side = value or UnitFactionGroup("player")
            if side ~= "Both" then
                tests[#tests + 1] = function(entry)
                    local quest = entry.quest and app.data:GetQuest(entry.quest)
                    return not quest or not quest.side or quest.side == "Both" or quest.side == side
                end
            end
        end
    end
    if #tests == 0 then
        return nil
    end
    return function(entry)
        for _, test in ipairs(tests) do
            if not test(entry) then
                return false
            end
        end
        return true
    end
end

----------------------------------------------------------------------------------------------------
-- Class filter: the footer button's state, per tab; which items a class can use is classfilter.lua
----------------------------------------------------------------------------------------------------

-- How visible a faded item stays (its row, tile or card, with its icon grey).
local FADED_ALPHA = 0.3

---@return string
function SpyglassViewMixin:GetFilterClass()
    return self.filterClass or app.classFilter:GetPlayerClass()
end

-- Changes the class filter; the arguments left nil keep their value. The list is filtered again
-- on the page it was showing (Refresh clamps it when hiding items leaves fewer pages).
---@param on boolean?
---@param class string?
---@param mode ("hide"|"fade")?
function SpyglassViewMixin:SetClassFilter(on, class, mode)
    if on ~= nil then
        self.classFilterOn = on
    end
    self.filterClass = class or self.filterClass
    self.classFilterMode = mode or self.classFilterMode
    self.ClassFilter:Update()
    self.ClassFilterMode:Update()
    self:Refresh()
    -- Kept with the tabs across sessions.
    app.ui.mainWindow:SaveTabs()
end

-- A class in a menu: its icon and name.
---@param class string
---@return string
local function classMenuLabel(class)
    return ("|T%s:16:16|t %s"):format(app.classFilter:GetIcon(class), app.classFilter:GetName(class))
end

-- The class button's right-click menu: the classes; picking one turns the filter on.
---@param root RootMenuDescriptionProxy
function SpyglassViewMixin:BuildClassFilterMenu(root)
    root:CreateTitle("Class")
    for _, class in ipairs(app.classFilter:GetClasses()) do
        root:CreateRadio(classMenuLabel(class), function()
            return class == self:GetFilterClass()
        end, function()
            self:SetClassFilter(true, class)
        end)
    end
end

-- The class filter's test for BuildElements: nil unless it is on and hiding.
---@return (fun(entry: Spyglass.Node): boolean)?
function SpyglassViewMixin:GetClassFilterTest()
    if not self.classFilterOn or self.classFilterMode ~= "hide" then
        return nil
    end
    local class, classFilter = self:GetFilterClass(), app.classFilter
    return function(entry)
        return not entry.itemID or classFilter:CanUse(class, entry.itemID)
    end
end

-- Is `node` an item the class filter fades out?
---@param node Spyglass.Node?
---@return boolean
function SpyglassViewMixin:IsFaded(node)
    return self.classFilterOn
        and self.classFilterMode == "fade"
        and node ~= nil
        and node.itemID ~= nil
        and not app.classFilter:CanUse(self:GetFilterClass(), node.itemID)
end

-- The values `field` has in the current list's `meta` (entries under subheaders and groups
-- included), in list order, with what a dropdown shows for them: standings by their localized
-- label, anything else as it is.
---@param field string
---@return { value: any, label: string }[]
function SpyglassViewMixin:GetFieldValues(field)
    local values, seen = {}, {}
    local function add(entry)
        local value = entry.meta and entry.meta[field]
        if value ~= nil and not seen[value] then
            seen[value] = true
            local rank = field == "standing" and STANDING_RANK[value]
            local label = rank and _G["FACTION_STANDING_LABEL" .. rank] or tostring(value)
            values[#values + 1] = { value = value, label = label }
        end
    end
    local node = self:GetCurrentNode()
    for _, child in ipairs(node and self:GetChildren(node) or {}) do
        for _, entry in ipairs(child.items or { child }) do
            add(entry)
        end
    end
    return values
end

-- Does `node` answer to one segment of an `open` path: a module id, a list id, a crafting
-- category folder by category id or curated group label, an instance id, or its name.
---@param node Spyglass.Node
---@param segment string
---@return boolean
local function matchesSegment(node, segment)
    if node.moduleID == segment or node.name == segment then
        return true
    end
    if node.instanceID and tostring(node.instanceID) == segment then
        return true
    end
    local meta = node.meta
    if not meta then
        return false
    end
    if meta.groupKey then
        return meta.groupKey == "CATEGORY" .. segment or meta.groupKey == "CUSTOM:" .. segment
    end
    return meta.listID == segment
end

-- Opens a collection by path (a panel button's `open`, e.g. "crafting/cooking"): from the root,
-- each segment picks a folder among the entries of the one before it, subheaders' and groups'
-- included. The tab navigates there as if clicked through; false when a segment matches nothing.
---@param path string
---@return boolean
function SpyglassViewMixin:OpenPath(path)
    local nodes = { self.path[1] }
    for segment in path:gmatch("[^/]+") do
        local parent, found = nodes[#nodes], nil
        for _, child in ipairs(self:GetChildren(parent)) do
            for _, entry in ipairs(child.items or { child }) do
                if app.api.IsFolder(entry) and matchesSegment(entry, segment) then
                    found = entry
                    break
                end
            end
            if found then
                break
            end
        end
        if not found then
            log:warn("Cannot open %q: nothing called %q in %s", path, segment, tostring(parent.name))
            return false
        end
        nodes[#nodes + 1] = found
    end
    self.path = nodes
    self.pathPages = {}
    self:Navigate()
    return true
end

-- Where the tab is, for the SavedVariables: the name of every folder below the root.
---@return string[]
function SpyglassViewMixin:GetSavedPath()
    local names = {}
    for i = 2, #self.path do
        names[#names + 1] = self.path[i].name
    end
    return names
end

-- Opens a path GetSavedPath saved in an earlier session: each name picks a folder among the
-- entries of the one before it, subheaders' and groups' included. A name that matches nothing
-- (the module is gone, the client's language changed) ends the path there.
---@param names string[]
function SpyglassViewMixin:RestorePath(names)
    local nodes = { self.path[1] }
    for _, name in ipairs(names) do
        local found
        for _, child in ipairs(self:GetChildren(nodes[#nodes])) do
            for _, entry in ipairs(child.items or { child }) do
                if app.api.IsFolder(entry) and entry.name == name then
                    found = entry
                    break
                end
            end
            if found then
                break
            end
        end
        if not found then
            break
        end
        nodes[#nodes + 1] = found
    end
    self.path = nodes
    self.pathPages = {}
    self:Navigate()
end

---@param text string
function SpyglassViewMixin:SetSearch(text)
    local q = self:GetCurrentQuery()
    if q and q.search ~= text then
        q.search = text
        self:OnQueryChanged()
    end
end

---@param q Spyglass.Query
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
---@param q Spyglass.Query
---@param filterID string
---@param value string|number
function SpyglassViewMixin:ToggleFilterValue(q, filterID, value)
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
---@param q Spyglass.Query
---@param filterID string
---@param value string|number|nil
function SpyglassViewMixin:SetFilterValue(q, filterID, value)
    if q.filters[filterID] ~= value then
        q.filters[filterID] = value
        self:OnQueryChanged()
    end
end

---@param q Spyglass.Query
---@param sort Spyglass.QuerySort
function SpyglassViewMixin:SetSort(q, sort)
    if q.sort ~= sort then
        q.sort = sort
        self:OnQueryChanged()
    end
end

-- Clears filters and sort and turns the class filter off, but keeps the search text (that's what
-- the search box's X is for).
---@param q Spyglass.Query
function SpyglassViewMixin:ResetFilters(q)
    wipe(q.filters)
    q.sort = "name"
    -- Off, keeping class and mode; the redraw updates the footer buttons.
    self.classFilterOn = false
    self:OnQueryChanged()
    app.ui.mainWindow:SaveTabs()
end

-- Filters and sort as ResetFilters leaves them (the search text doesn't count). A multi filter
-- whose last value was unticked is left as an empty table.
---@param q Spyglass.Query
---@return boolean
function SpyglassViewMixin:IsDefaultQuery(q)
    if (q.sort or "name") ~= "name" then
        return false
    end
    for _, values in pairs(q.filters) do
        if type(values) ~= "table" or #values > 0 then
            return false
        end
    end
    return true
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
function SpyglassViewMixin:BuildFilterMenu(root)
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

    -- The footer's class filter, the same state as its two buttons: "Off" or a class (which
    -- turns it on), then fade out or hide.
    local classMenu = root:CreateButton("Class")
    classMenu:CreateRadio(OFF or "Off", function()
        return not self.classFilterOn
    end, function()
        self:SetClassFilter(false)
        return MenuResponse.Refresh
    end)
    for _, class in ipairs(app.classFilter:GetClasses()) do
        classMenu:CreateRadio(classMenuLabel(class), function()
            return self.classFilterOn and class == self:GetFilterClass()
        end, function()
            self:SetClassFilter(true, class)
            return MenuResponse.Refresh
        end)
    end
    classMenu:CreateDivider()
    classMenu:CreateRadio("Fade out", function()
        return self.classFilterMode == "fade"
    end, function()
        self:SetClassFilter(nil, nil, "fade")
        return MenuResponse.Refresh
    end)
    classMenu:CreateRadio("Hide", function()
        return self.classFilterMode == "hide"
    end, function()
        self:SetClassFilter(nil, nil, "hide")
        return MenuResponse.Refresh
    end)

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
function SpyglassViewMixin:UpdateToolbar()
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
    self.FilterDropdown:ValidateResetState()
end

-- The element kind a folder's entries are drawn as: "row" (default), "tile" or "card".
---@param node Spyglass.Node?
---@return "row"|"tile"|"card"
local function entryKindOf(node)
    local display = node and node.display
    if display == "tiles" then
        return "tile"
    elseif display == "cards" then
        return "card"
    end
    return "row"
end

-- Columns per line for each entry kind: { default, max }. Set by the collection itself
-- (`node.columns`), clamped to what the kind can fit.
local COLUMNS = {
    row = { 1, 2 },
    tile = { 3, 4 },
    card = { 2, 2 },
}

-- Columns for the current list.
---@param node Spyglass.Node?
---@return integer
function SpyglassViewMixin:GetColumns(node)
    local range = COLUMNS[entryKindOf(node)]
    local columns = node and node.columns or range[1]
    return math.max(1, math.min(range[2], columns))
end

-- Full redraw: rebuild the element list and page layout for the current node, then render.
-- Called on navigation, query changes, page-size changes, profile refreshes and when an item
-- the grouping had to guess arrives; page flips and other item-info arrivals only need Render().
function SpyglassViewMixin:Refresh()
    -- A hidden view (another tab is selected) shares `layout` with the shown one and would
    -- overwrite it; it lays itself out in OnShow instead.
    if not self:IsShown() then
        return
    end
    -- The rows are about to change; a popup anchored to one of them would be stale.
    if app.ui.HidePopups then
        app.ui.HidePopups()
    end
    local node = self:GetCurrentNode()
    wipe(app.unknownItemKinds)
    self.pages = self:LayoutPages(self:BuildElements(node), self:GetColumns(node))
    -- Items the grouping had to guess (no DB row, not fetched yet): fetch them all, not only the
    -- ones on this page, and regroup once each has arrived (OnEvent).
    for itemID in pairs(app.unknownItemKinds) do
        if self.regroupItems[itemID] == nil then
            self.regroupItems[itemID] = true
            self:RequestItem(itemID)
        end
    end

    local maxPages = math.max(1, #self.pages)
    -- SetMaxPages may clamp the current page, which calls OnPageChanged -> Render.
    self.PagingControls:SetMaxPages(maxPages)
    self.PagingControls:SetShown(maxPages > 1)

    self:Render()
end

-- Draws the current page plus the chrome around it.
function SpyglassViewMixin:Render()
    local node = self:GetCurrentNode()
    -- self.Title:Init(node and node.name or "")
    self:RenderPage(self.Content, self.pages[self.PagingControls:GetCurrentPage()])
    local isOptions = node == OPTIONS_NODE
    if isOptions then
        showOptionsIn(self.Content)
    else
        hideOptionsIn(self.Content)
    end

    self:RefreshBreadcrumbs()
    self:UpdateToolbar()
    -- The footer's class filter and active list act on items; the options page has none.
    self.ClassFilter:SetShown(not isOptions)
    self.ClassFilterMode:SetShown(not isOptions)
    self.ActiveList:SetShown(not isOptions)
    self.ClassFilter:Update()
    self.ClassFilterMode:Update()
    -- The active list may have changed, or been renamed, since the menu was last built.
    self.ActiveList:GenerateMenu()
end

-- Turns the current node into the flat list of things to draw: its children. `header` nodes become section headers,
-- `subheader` nodes the smaller section titles under them, `quest` nodes quest banners (followed
-- by their `items`), `group` nodes group labels (followed by their `items`), `spacer` nodes an
-- empty row, everything else a row (or a tile in a `display = "tiles"` folder). If the folder
-- has `groupBy`, runs of plain entries are bucketed
-- into auto groups (or as the info panel's `grouping` dropdown picked); explicit
-- headers/subheaders/groups/spacers are kept as written.
---@param node Spyglass.Node?
---@return Spyglass.Element[]
function SpyglassViewMixin:BuildElements(node)
    local elements = {}
    self.showsQuests = false
    if not node then
        return elements
    end

    local groupBy = node.groupBy
    local picked, pickedGroupBy = self:GetPanelGrouping()
    if picked then
        groupBy = pickedGroupBy or nil
    end
    local keyFn = type(groupBy) == "function" and groupBy or nil
    local entryKind = entryKindOf(node)
    local pending = {}
    -- The info panel's checkboxes/dropdowns and the class filter; folders always stay.
    local filter = self:GetEntryFilter()
    local classTest = self:GetClassFilterTest()
    if filter and classTest then
        local panelTest = filter
        filter = function(entry)
            return panelTest(entry) and classTest(entry)
        end
    else
        filter = filter or classTest
    end
    local function keep(entry)
        return not entry.hidden and (not filter or app.api.IsFolder(entry) or filter(entry))
    end

    local function addRows(entries)
        for _, entry in ipairs(entries) do
            if keep(entry) then
                elements[#elements + 1] = entryElement(entryKind, entry)
            end
        end
    end

    -- A subheader's or group's own entries after filtering; a label whose entries were all
    -- filtered out is dropped with them.
    ---@param items Spyglass.Node[]?
    ---@return boolean
    local function hasKept(items)
        if not items or #items == 0 then
            return true
        end
        for _, entry in ipairs(items) do
            if keep(entry) then
                return true
            end
        end
        return false
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
        if child.hidden then
            flush()
        elseif child.header then
            flush()
            elements[#elements + 1] = { kind = "header", text = child.header }
        elseif child.subheader then
            flush()
            if hasKept(child.items) then
                elements[#elements + 1] = { kind = "subheader", text = child.subheader, source = child }
                addRows(child.items or {})
            end
        elseif child.quest then
            -- The faction filter may hide a quest; reward filters only affect its item rows.
            if not filter or filter(child) then
                flush()
                elements[#elements + 1] = { kind = "quest", node = child }
                addRows(child.items or {})
                self.showsQuests = true
            end
        elseif child.group then
            flush()
            if hasKept(child.items) then
                elements[#elements + 1] = { kind = "group", text = child.group }
                addRows(child.items or {})
            end
        elseif child.spacer then
            flush()
            elements[#elements + 1] = { kind = "spacer" }
        elseif groupBy then
            if keep(child) then
                pending[#pending + 1] = child
            end
        elseif keep(child) then
            -- No grouping: straight in, without collecting 25k entries first.
            elements[#elements + 1] = entryElement(entryKind, child)
        end
    end
    flush()
    if #elements == 0 and node.meta and node.meta.quests then
        elements[1] = { kind = "subheader", text = "No quests for this faction" }
    end
    -- The query counted its result before the filters above removed entries from it: the count
    -- next to the search box is what is listed.
    if filter and node.query then
        local count = 0
        for _, element in ipairs(elements) do
            if element.kind == entryKind then
                count = count + 1
            end
        end
        self.resultCount = count
    end
    return elements
end

-- Flows elements top-to-bottom into as many pages as needed. Headers and subheaders span the
-- full width and start a new line; rows, tiles and cards fill `columns` columns left to right
-- (tiles and cards are taller and get a little air between lines). A header never ends a page
-- (nor does a subheader: both take the row that follows them along to the next one). A spacer
-- is a row-high blank line that is dropped at the top of a page and never causes a page break
-- by itself.
---@param elements Spyglass.Element[]
---@param columns integer
---@return Spyglass.PageRange[]
function SpyglassViewMixin:LayoutPages(elements, columns)
    local pages = {}
    local first, count, y, column = 1, 0, 0, 0 -- first: layout index of the page being filled
    local elementAt, xAt, yAt, widthAt, heightAt = layout.element, layout.x, layout.y, layout.width, layout.height
    local pageWidth, pageHeight = self.Content:GetSize()
    local columnWidth = (pageWidth - self.columnGap * (columns - 1)) / columns
    local lineHeight = self.rowHeight -- of the line being filled

    local function newPage()
        if count >= first then
            pages[#pages + 1] = { first = first, last = count }
        end
        first, y, column = count + 1, 0, 0
    end

    local function newLine()
        if column > 0 then
            y = y + lineHeight
            column = 0
        end
    end

    local function place(element, x, width, height)
        count = count + 1
        elementAt[count], xAt[count], yAt[count], widthAt[count], heightAt[count] = element, x, y, width, height
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
        elseif element.kind == "subheader" then
            -- Like a header, only smaller; also never left alone at a page bottom.
            newLine()
            local height = self.subheaderHeight + (element.source and element.source.onClick and 16 or 0)
            local needed = height + self.subheaderGap + self.rowHeight
            if y > 0 and y + needed > pageHeight then
                newPage()
            end
            place(element, 0, pageWidth, height)
            y = y + height + self.subheaderGap
        elseif element.kind == "quest" then
            -- Full width; kept with its first reward row when it has rewards.
            newLine()
            local items = element.node.items
            local needed = self.questHeight + self.questGap + (items and #items > 0 and self.rowHeight or 0)
            if y > 0 and y + needed > pageHeight then
                newPage()
            end
            local indent = math.max(0, math.min(element.node.indent or 0, pageWidth / 3))
            place(element, indent, pageWidth - indent, self.questHeight)
            y = y + self.questHeight + self.questGap
        elseif element.kind == "group" then
            -- Row-sized, full width, on its own line, and never orphaned at a page bottom.
            newLine()
            if y > 0 and y + self.rowHeight * 2 > pageHeight then
                newPage()
            end
            place(element, 0, pageWidth, self.rowHeight)
            y = y + self.rowHeight
        elseif element.kind == "spacer" then
            -- Only space: nothing is placed, so nothing is drawn. Skipped at a page top and
            -- swallowed when it would not fit, so a page never ends (or starts) with air.
            newLine()
            if y > 0 and y + self.rowHeight <= pageHeight then
                y = y + self.rowHeight
            end
        else
            local height, gap = self.rowHeight, 0
            if element.kind == "tile" then
                height, gap = self.tileHeight, self.columnGap
            elseif element.kind == "card" then
                height, gap = self.cardHeight, self.columnGap
            end
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

---@param page Spyglass.Page
---@param range Spyglass.PageRange?
function SpyglassViewMixin:RenderPage(page, range)
    page.rowPool:ReleaseAll()
    page.tilePool:ReleaseAll()
    page.cardPool:ReleaseAll()
    page.headerPool:ReleaseAll()
    page.subheaderPool:ReleaseAll()
    page.questPool:ReleaseAll()
    page.groupPool:ReleaseAll()
    for i = range and range.first or 1, range and range.last or 0 do
        local element = layout.element[i]
        local frame
        if element.kind == "header" then
            frame = page.headerPool:Acquire() --[[@as Spyglass.PageHeader]]
            frame:Init(element.text or "")
        elseif element.kind == "subheader" then
            frame = page.subheaderPool:Acquire() --[[@as Spyglass.Subheader]]
            frame:Init(element.text or "", element.source)
        elseif element.kind == "quest" then
            frame = page.questPool:Acquire() --[[@as Spyglass.QuestBanner]]
            frame:Init(self, element.node)
        elseif element.kind == "group" then
            frame = page.groupPool:Acquire() --[[@as Spyglass.GroupLabel]]
            frame:Init(element.text or "")
        elseif element.kind == "tile" then
            frame = page.tilePool:Acquire() --[[@as Spyglass.Tile]]
            frame:Init(self, element.node)
        elseif element.kind == "card" then
            frame = page.cardPool:Acquire() --[[@as Spyglass.Card]]
            frame:Init(self, element.node)
        else
            frame = page.rowPool:Acquire() --[[@as Spyglass.ListRow]]
            frame:Init(self, element.node)
        end
        if element.node then
            -- Pooled frames come back from other lists: reset what fading changed.
            local faded = self:IsFaded(element.node)
            frame:SetAlpha(faded and FADED_ALPHA or 1)
            frame.Icon:SetDesaturated(faded)
        end
        frame:SetSize(layout.width[i], layout.height[i])
        frame:SetPoint("TOPLEFT", page, "TOPLEFT", layout.x[i], -layout.y[i])
        frame:Show()
    end
end

function SpyglassViewMixin:RefreshBreadcrumbs()
    self.crumbPool:ReleaseAll()
    self.separatorPool:ReleaseAll()

    local layoutIndex = 1
    for i, node in ipairs(self.path) do
        if i > 1 then
            local sep = self.separatorPool:Acquire() --[[@as Spyglass.LayoutChild]]
            sep.layoutIndex = layoutIndex
            layoutIndex = layoutIndex + 1
            sep:Show()
        end
        local crumb = self.crumbPool:Acquire() --[[@as Spyglass.BreadcrumbButton]]
        crumb.layoutIndex = layoutIndex
        layoutIndex = layoutIndex + 1
        crumb:Init(self, i, node.name, i == #self.path)
        crumb:Show()
    end
    self.Breadcrumbs:MarkDirty()
end
