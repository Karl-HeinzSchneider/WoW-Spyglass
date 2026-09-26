---@type string, ForeverLoot
local _, app = ...

local Data = app.data
local ITEM = Data.ITEM

local SLOT_SIZE = 32
local SLOT_GAP = 6
local PADDING = 12
local TITLE_GAP = 8
local PER_LINE = 8

-- The set of an item node, when the database has the set's items; nil otherwise.
---@param node ForeverLoot.Node
---@return integer?
local function setOf(node)
    local setID = node and node.itemID and Data:GetItemField(node.itemID, ITEM.SET)
    if type(setID) == "number" and setID ~= 0 and #Data:GetSetItems(setID) > 0 then
        return setID
    end
    return nil
end

-- The set's items in the order a loot list shows them: armor type, then slot.
---@param setID integer
---@return integer[]
local function sortedItems(setID)
    local items, rank = {}, {}
    for _, itemID in ipairs(Data:GetSetItems(setID)) do
        items[#items + 1] = itemID
        rank[itemID] = app.api.DefaultEntryRank({ itemID = itemID })
    end
    table.sort(items, function(a, b)
        if rank[a] ~= rank[b] then
            return rank[a] < rank[b]
        end
        return a < b
    end)
    return items
end

----------------------------------------------------------------------------------------------------
-- The item set popup: the set's name, then every item of the set, PER_LINE slots per line
----------------------------------------------------------------------------------------------------

---@class ForeverLoot.SetPopup : ForeverLoot.Popup
---@field slotPool ForeverLoot.FramePool
ForeverLootSetPopupMixin = CreateFromMixins(ForeverLootPopupMixin)
app.ui.SetPopupMixin = ForeverLootSetPopupMixin

function ForeverLootSetPopupMixin:OnLoad()
    ForeverLootPopupMixin.OnLoad(self)
    app.ui.setPopup = self
    self.slotPool = CreateFramePool("Button", self, "ForeverLootItemSlotTemplate") --[[@as ForeverLoot.FramePool]]
end

-- Whether a click on this node opens the popup: an item of a set the database knows.
---@param node ForeverLoot.Node
---@return boolean
function ForeverLootSetPopupMixin:HasSet(node)
    return setOf(node) ~= nil
end

function ForeverLootSetPopupMixin:Refresh()
    local setID = setOf(self.node)
    if not setID then
        self:Hide()
        return
    end
    self.Title:SetText(Data:GetSetName(setID))

    self.slotPool:ReleaseAll()
    local items = sortedItems(setID)
    for i, itemID in ipairs(items) do
        local slot = self.slotPool:Acquire() --[[@as ForeverLoot.ItemSlot]]
        slot:SetItem(itemID)
        local column, line = (i - 1) % PER_LINE, math.floor((i - 1) / PER_LINE)
        slot:SetPoint(
            "TOPLEFT",
            self.Title,
            "BOTTOMLEFT",
            column * (SLOT_SIZE + SLOT_GAP),
            -TITLE_GAP - line * (SLOT_SIZE + SLOT_GAP)
        )
        slot:Show()
    end

    local columns, lines = math.min(#items, PER_LINE), math.ceil(#items / PER_LINE)
    local gridWidth = columns * SLOT_SIZE + (columns - 1) * SLOT_GAP
    local gridHeight = lines * SLOT_SIZE + (lines - 1) * SLOT_GAP
    local titleWidth = self.Title:GetStringWidth() + 24 -- room for the close button
    self:SetWidth(math.max(titleWidth, gridWidth) + 2 * PADDING)
    self:SetHeight(PADDING + self.Title:GetStringHeight() + TITLE_GAP + gridHeight + PADDING)
end
