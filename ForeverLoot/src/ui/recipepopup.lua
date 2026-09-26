---@type string, ForeverLoot
local _, app = ...

local Data = app.data
local ITEM = Data.ITEM
local RECIPE = Data.RECIPE

app.ui = app.ui or {}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SLOT_SIZE = 32
local SLOT_GAP = 6
local PADDING = 12

-- What the client knows about an item right now: the cache when it has the item (exact, with
-- the link), else the database row. Uncached items are requested; GET_ITEM_INFO_RECEIVED redraws.
---@param itemID integer
---@return string name, integer? quality, string|number? icon, string? link
local function itemDisplay(itemID)
    local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    if name then
        return name, quality, icon, link
    end
    C_Item.RequestLoadItemDataByID(itemID)
    local row = Data:GetItem(itemID)
    icon = select(5, C_Item.GetItemInfoInstant(itemID)) or (row and row[ITEM.ICON])
    return Data:GetItemName(itemID), row and row[ITEM.QUALITY], icon, nil
end

----------------------------------------------------------------------------------------------------
-- Item slot: icon in the shared icon frame (ring tinted by quality), count; tooltip and chat linking
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.ItemSlot : Button
---@field Icon Texture
---@field IconMask MaskTexture
---@field IconRing Texture
---@field Count FontString
---@field Favorite Texture
---@field ListMarker Texture
---@field itemID? integer
---@field spellID? integer  # a spell instead of an item (an enchant recipe's product)
---@field link? string
ForeverLootItemSlotMixin = {}
app.ui.ItemSlotMixin = ForeverLootItemSlotMixin

---@param itemID integer
---@param count? integer  # shown bottom-right when above 1
---@return string name, integer? quality
function ForeverLootItemSlotMixin:SetItem(itemID, count)
    local name, quality, icon, link = itemDisplay(itemID)
    self.itemID, self.spellID = itemID, nil
    self.link = link
    self.Icon:SetTexture(icon or FALLBACK_ICON)
    app.ui.SetIconQuality(self.IconRing, quality)
    self.Count:SetText(count and count > 1 and tostring(count) or "")
    self.Count:SetShown(count ~= nil and count > 1)
    app.ui.SetItemBadges(self, itemID)
    return name, quality
end

-- A spell in the slot instead of an item: its icon (or the one given), no count or border.
---@param spellID integer
---@param icon? string|number
function ForeverLootItemSlotMixin:SetSpell(spellID, icon)
    local info = C_Spell.GetSpellInfo(spellID)
    self.itemID, self.spellID = nil, spellID
    self.link = C_Spell.GetSpellLink(spellID)
    self.Icon:SetTexture(icon or (info and info.iconID) or FALLBACK_ICON)
    app.ui.SetIconQuality(self.IconRing, nil)
    self.Count:Hide()
    app.ui.SetItemBadges(self, nil)
end

function ForeverLootItemSlotMixin:OnEnter()
    if self.itemID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(self.itemID)
    elseif self.spellID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.spellID)
    else
        return
    end
    GameTooltip:Show()
    if self.itemID then
        app.ui.modelPreview:SetItem(self, self.itemID)
    end
end

function ForeverLootItemSlotMixin:OnLeave()
    app.ui.modelPreview:Clear()
    GameTooltip:Hide()
end

-- Shift-click links the item to chat (ctrl-click previews it), alt-click adds it to the active
-- list or removes it (the open popup redraws on OnListsChanged); a plain click on an item the
-- client hasn't cached asks for it.
---@param button string
function ForeverLootItemSlotMixin:OnClick(button)
    if self.itemID and button == "LeftButton" and IsAltKeyDown() then
        app.lists:Toggle(app.lists:GetActive(), self.itemID)
        if GameTooltip:IsOwned(self) then
            self:OnEnter()
        end
    elseif self.link then
        HandleModifiedItemClick(self.link)
    elseif self.itemID then
        C_Item.RequestLoadItemDataByID(self.itemID)
    end
end

----------------------------------------------------------------------------------------------------
-- A popup opened from a list row (ForeverLootPopupTemplate): one open at a time, below its row
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.Popup : Frame
---@field Title FontString
---@field CloseButton Button
---@field node? ForeverLoot.Node  # the node it shows
---@field anchor? Frame  # the row it was opened from
---@field Refresh fun(self: ForeverLoot.Popup)  # draws `node`; hides the popup when there is nothing to show
ForeverLootPopupMixin = {}

local popups = {} ---@type ForeverLoot.Popup[]

-- Hides every popup; the view calls it when the rows they are anchored to are about to change.
function app.ui.HidePopups()
    for _, popup in ipairs(popups) do
        popup:Hide()
    end
end

function ForeverLootPopupMixin:OnLoad()
    popups[#popups + 1] = self
    -- Redraw the badges when an item of the popup (or of the list under it) or a list changed.
    app.api.RegisterCallback(self, "OnListsChanged", function()
        if self:IsShown() and self.node then
            self:Refresh()
        end
    end)
end

function ForeverLootPopupMixin:OnShow()
    self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function ForeverLootPopupMixin:OnHide()
    self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    self.node, self.anchor = nil, nil
end

-- Item names and icons arrive asynchronously; redraw with whatever is known now.
function ForeverLootPopupMixin:OnEvent(event)
    if event == "GET_ITEM_INFO_RECEIVED" and self.node then
        self:Refresh()
    end
end

-- Opens the popup for a node below the row it was clicked on, closing any other popup;
-- clicking the same row again closes it.
---@param node ForeverLoot.Node
---@param anchor Frame
function ForeverLootPopupMixin:Toggle(node, anchor)
    if self:IsShown() and self.node == node then
        self:Hide()
        return
    end
    app.ui.HidePopups()
    self.node, self.anchor = node, anchor
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    self:Refresh()
    self:Show()
end

----------------------------------------------------------------------------------------------------
-- The recipe popup
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.RecipePopup : ForeverLoot.Popup
---@field Product ForeverLoot.ItemSlot
---@field Source ForeverLoot.ItemSlot
---@field Recipe ForeverLoot.ItemSlot
---@field reagentPool ForeverLoot.FramePool
ForeverLootRecipePopupMixin = CreateFromMixins(ForeverLootPopupMixin)
app.ui.RecipePopupMixin = ForeverLootRecipePopupMixin

function ForeverLootRecipePopupMixin:OnLoad()
    ForeverLootPopupMixin.OnLoad(self)
    app.ui.recipePopup = self
    self.reagentPool = CreateFramePool("Button", self, "ForeverLootItemSlotTemplate") --[[@as ForeverLoot.FramePool]]
end

---@param node ForeverLoot.Node
---@return integer? spellID, ForeverLoot.RecipeRow? recipe
local function recipeOf(node)
    local spellID = node.meta and node.meta.spell
    if type(spellID) ~= "number" then
        return nil, nil
    end
    return spellID, Data:GetRecipe(spellID)
end

-- The icon of the profession a recipe belongs to: the crafting list's, as the tile shows it.
---@param skillLineID integer
---@return string|number?
local function professionIcon(skillLineID)
    for _, id in ipairs(Data:GetListIDs("crafting")) do
        local list = Data:GetList("crafting", id)
        if list and list.skillLineID == skillLineID and list.icon then
            return list.icon
        end
    end
    return nil
end

function ForeverLootRecipePopupMixin:Refresh()
    local node = self.node
    if not node then
        self:Hide()
        return
    end
    local spellID, recipe = recipeOf(node)
    if not spellID or not recipe then
        self:Hide()
        return
    end

    -- Title: the recipe's name (the spell's, which is also the product's for item recipes).
    local info = C_Spell.GetSpellInfo(spellID)
    self.Title:SetText(info and info.name or Data:GetItemName(recipe[RECIPE.ITEM]))

    -- First line: the product (the recipe spell itself for enchants) and the item that teaches it.
    local productID = recipe[RECIPE.ITEM]
    if productID ~= 0 then
        local count = recipe[RECIPE.COUNT]
        self.Product:SetItem(productID, type(count) == "number" and count or nil)
    else
        self.Product:SetSpell(spellID)
    end
    local taughtBy = recipe[RECIPE.TAUGHT_BY]
    if taughtBy then
        self.Source:SetItem(taughtBy)
    end
    self.Source:SetShown(taughtBy ~= nil)
    local firstLine = taughtBy and (2 * SLOT_SIZE + 2 * SLOT_GAP) or SLOT_SIZE

    -- Second line: the recipe (the profession's icon; tooltip and link are the spell's), then
    -- one slot per reagent with its count.
    self.Recipe:SetSpell(spellID, professionIcon(recipe[RECIPE.SKILL_LINE]))
    local lineWidth = SLOT_SIZE
    self.reagentPool:ReleaseAll()
    local previous = self.Recipe --[[@as Frame]]
    local gap = 2 * SLOT_GAP
    local reagents = recipe[RECIPE.REAGENTS] or {}
    for i = 1, #reagents, 2 do
        local slot = self.reagentPool:Acquire() --[[@as ForeverLoot.ItemSlot]]
        slot:SetItem(reagents[i], reagents[i + 1])
        slot:SetPoint("LEFT", previous, "RIGHT", gap, 0)
        slot:Show()
        lineWidth = lineWidth + gap + SLOT_SIZE
        previous, gap = slot, SLOT_GAP
    end

    local titleWidth = self.Title:GetStringWidth() + 24 -- room for the close button
    self:SetWidth(math.max(titleWidth, firstLine, lineWidth) + 2 * PADDING)
end
