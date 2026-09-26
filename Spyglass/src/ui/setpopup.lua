---@type string, Spyglass
local _, app = ...

local Data = app.data
local ITEM = Data.ITEM

local SLOT_SIZE = 32
local SLOT_GAP = 6
local PADDING = 12
local TITLE_GAP = 8
local PER_LINE = 8

-- The set of an item node, when the database has the set's items; nil otherwise.
---@param node Spyglass.Node
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

local MAGIC = "[%^%$%(%)%.%[%]%*%+%-%?%%]"

-- A Lua pattern for the start of a line the game writes with a format string (ITEM_SET_NAME,
-- "%s (%d/%d)"): its %s become `s`, its %d become numbers, the rest must match literally.
---@param fmt string
---@param s string  # a pattern
---@return string
local function formatPattern(fmt, s)
    local out, pos = {}, 1
    for start, kind, stop in fmt:gmatch("()%%[%d%$]*([sd])()") do
        out[#out + 1] = (fmt:sub(pos, start - 1):gsub(MAGIC, "%%%0"))
        out[#out + 1] = kind == "s" and s or "%d+"
        pos = stop
    end
    out[#out + 1] = (fmt:sub(pos):gsub(MAGIC, "%%%0"))
    return "^" .. table.concat(out)
end

---@param text string
---@return boolean
local function isSetBonus(text)
    return text:find(formatPattern(ITEM_SET_BONUS_GRAY, ".+")) ~= nil
        or text:find(formatPattern(ITEM_SET_BONUS, ".+")) ~= nil
end

-- The set part of an item's tooltip as the game draws it: from the set's header ("Rotmender's
-- Raiment (0/5)") over its items (grey when not owned) to its last bonus ("(2) Set: ...", grey
-- while inactive). nil when the client has no tooltip data for the item (yet) or no set part.
---@param itemID integer
---@param setName string
---@return { text: string, r: number, g: number, b: number }[]?
local function setTooltipLines(itemID, setName)
    local data = C_TooltipInfo and C_TooltipInfo.GetItemByID(itemID)
    local lines = data and data.lines
    if not lines then
        return nil
    end
    local header = formatPattern(ITEM_SET_NAME, (setName:gsub(MAGIC, "%%%0")))
    local first, last, bonuses
    for i, line in ipairs(lines) do
        local text = line.leftText or ""
        if not first then
            if text:find(header) then
                first, last = i, i
            end
        elseif isSetBonus(text) then
            last, bonuses = i, true
        elseif not bonuses and last == i - 1 and text:match("%S") then
            last = i -- the set's items follow the header without a gap
        end
    end
    if not first then
        return nil
    end
    local out = {}
    for i = first, last do
        local line = lines[i]
        local color = line.leftColor or NORMAL_FONT_COLOR
        out[#out + 1] = { text = line.leftText or "", r = color.r, g = color.g, b = color.b }
    end
    return out
end

----------------------------------------------------------------------------------------------------
-- The item set popup: the set's name, then every item of the set, PER_LINE slots per line
----------------------------------------------------------------------------------------------------

---@class Spyglass.SetPopup : Spyglass.Popup
---@field TitleButton Button  # over the title: hover shows the set's tooltip, shift-click links
---@field slotPool Spyglass.FramePool
---@field setID? integer  # the set it shows
SpyglassSetPopupMixin = CreateFromMixins(SpyglassPopupMixin)
app.ui.SetPopupMixin = SpyglassSetPopupMixin

function SpyglassSetPopupMixin:OnLoad()
    SpyglassPopupMixin.OnLoad(self)
    app.ui.setPopup = self
    self.slotPool = CreateFramePool("Button", self, "SpyglassItemSlotTemplate") --[[@as Spyglass.FramePool]]
    self.TitleButton:SetScript("OnEnter", function()
        self:ShowSetTooltip()
    end)
    self.TitleButton:SetScript("OnLeave", function()
        self.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        GameTooltip:Hide()
    end)
    self.TitleButton:SetScript("OnClick", function()
        self:LinkSet()
    end)
end

function SpyglassSetPopupMixin:OnHide()
    SpyglassPopupMixin.OnHide(self)
    if GameTooltip:GetOwner() == self.TitleButton then
        GameTooltip:Hide()
    end
    self.Title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
end

-- The set part of the tooltip of the item the popup was opened from; until the client has that
-- item's tooltip data, the set's name and the names of its items.
function SpyglassSetPopupMixin:ShowSetTooltip()
    local itemID, setID = self.node and self.node.itemID, self.setID
    if not itemID or not setID then
        return
    end
    self.Title:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:SetOwner(self.TitleButton, "ANCHOR_RIGHT")
    local lines = setTooltipLines(itemID, Data:GetSetName(setID))
    if lines then
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line.text:match("%S") and line.text or " ", line.r, line.g, line.b, true)
        end
    else
        C_Item.RequestLoadItemDataByID(itemID)
        GameTooltip:AddLine(Data:GetSetName(setID))
        for _, id in ipairs(sortedItems(setID)) do
            GameTooltip:AddLine("  " .. Data:GetItemName(id), GRAY_FONT_COLOR:GetRGB())
        end
    end
    GameTooltip:Show()
end

-- There is no chat link for an item set: shift-click links the item the popup was opened from,
-- whose tooltip shows the whole set (ctrl-click tries it on, as on any item).
function SpyglassSetPopupMixin:LinkSet()
    local itemID = self.node and self.node.itemID
    if not itemID then
        return
    end
    local _, link = C_Item.GetItemInfo(itemID)
    if link then
        HandleModifiedItemClick(link)
    else
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

-- Whether a click on this node opens the popup: an item of a set the database knows.
---@param node Spyglass.Node
---@return boolean
function SpyglassSetPopupMixin:HasSet(node)
    return setOf(node) ~= nil
end

function SpyglassSetPopupMixin:Refresh()
    local setID = setOf(self.node)
    if not setID then
        self:Hide()
        return
    end
    self.setID = setID
    self.Title:SetText(Data:GetSetName(setID))
    self.TitleButton:SetSize(self.Title:GetStringWidth(), self.Title:GetStringHeight())

    self.slotPool:ReleaseAll()
    local items = sortedItems(setID)
    for i, itemID in ipairs(items) do
        local slot = self.slotPool:Acquire() --[[@as Spyglass.ItemSlot]]
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

    -- Item data arrived while the set's tooltip is up: draw it again, now from the game's lines.
    if GameTooltip:GetOwner() == self.TitleButton then
        self:ShowSetTooltip()
    end
end
