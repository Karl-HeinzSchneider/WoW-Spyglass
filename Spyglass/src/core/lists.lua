---@type string, Spyglass
local _, app = ...

local log = app.logger

-- The user's item lists (BiS lists, farm lists, ...), account-wide in SpyglassDB.global.lists.
-- The built-in list "favorites" comes first and can't be renamed or deleted; it shows a star, the
-- others one of the eight raid target icons (`marker`). Alt-click in the window adds to the
-- *active* list (Favorites until another is made active). Public as Spyglass.Lists; every
-- change fires OnListsChanged(listID, itemID) — itemID nil when the list itself changed
-- (created, deleted, renamed, new marker, tooltip switch, made active). Spyglass.Favorites is
-- the old favorites API over the "favorites" list and still fires OnFavoritesChanged.
--
--   global.lists = {
--       active = "favorites", nextID = 2, order = { "favorites", "l1" },
--       byID = { favorites = { name = "Favorites", tooltip = true, items = { [itemID] = true } },
--                l1 = { name = "Warrior BiS", marker = 8, tooltip = true, items = {...} } },
--   }

local FAVORITES = "favorites"
local MARKER_COUNT = 8
local MARKER_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
-- The favorites star: the transmog frame's (19x19, UITransmogrify2x), drawn a little larger than
-- a marker, 15 for 14, so it looks as big as one.
local FAVORITE_ATLAS = "transmog-icon-favorite"
local FAVORITE_SCALE = 15 / 14
local EXPORT_PREFIX = "FL1"

---@class Spyglass.ItemList
---@field name string
---@field marker? integer  # 1..8, a raid target icon; nil on Favorites (the star)
---@field tooltip boolean  # item tooltips name the list
---@field items table<integer, true>

---@class Spyglass.ListStore
---@field active string
---@field nextID integer
---@field order string[]
---@field byID table<string, Spyglass.ItemList>

---@class Spyglass.Lists
---@field FAVORITES string  # the id of the built-in Favorites list
---@field OpenCreateDialog fun(self: Spyglass.Lists)  # the dialogs are added by src/ui/listdialog.lua
---@field OpenEditDialog fun(self: Spyglass.Lists, id: string)
---@field OpenExportDialog fun(self: Spyglass.Lists, id: string)
---@field OpenImportDialog fun(self: Spyglass.Lists, intoID?: string)
---@field OpenDeleteDialog fun(self: Spyglass.Lists, id: string)
local Lists = { FAVORITES = FAVORITES }
app.lists = Lists
app.api.Lists = Lists

-- The store, created on first use once the SavedVariables are loaded; the favorites of the
-- single-list version (global.favorites) move into the Favorites list then.
---@return Spyglass.ListStore?
local function store()
    local db = app.db
    if not db then
        return nil
    end
    local global = db.global
    local lists = global.lists
    if not lists then
        local favorites = { name = "Favorites", tooltip = true, items = {} }
        for itemID in pairs(global.favorites or {}) do
            favorites.items[itemID] = true
        end
        global.favorites = nil
        lists = { active = FAVORITES, nextID = 1, order = { FAVORITES }, byID = { [FAVORITES] = favorites } }
        global.lists = lists
    end
    return lists
end

---@param listID string
---@param itemID? integer
local function changed(listID, itemID)
    app.api.callbacks:Fire("OnListsChanged", listID, itemID)
    if listID == FAVORITES and itemID then
        app.api.callbacks:Fire("OnFavoritesChanged", itemID, Lists:Contains(FAVORITES, itemID))
    end
end

---@param marker any
---@return integer?
local function validMarker(marker)
    marker = tonumber(marker)
    if marker and marker >= 1 and marker <= MARKER_COUNT then
        return math.floor(marker)
    end
    return nil
end

-- The first marker no list uses yet, else the least used one.
---@return integer
local function freeMarker()
    local lists, used = store(), {}
    for _, list in pairs(lists and lists.byID or {}) do
        if list.marker then
            used[list.marker] = (used[list.marker] or 0) + 1
        end
    end
    local best = 1
    for marker = 1, MARKER_COUNT do
        if (used[marker] or 0) < (used[best] or 0) then
            best = marker
        end
    end
    return best
end

---------------------------------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------------------------------

-- Every list id, Favorites first, then in the order they were made.
---@return string[]
function Lists:GetAll()
    local lists, ids = store(), {}
    for i, id in ipairs(lists and lists.order or {}) do
        ids[i] = id
    end
    return ids
end

-- The list's data; read it, change it only through the calls below.
---@param id string
---@return Spyglass.ItemList?
function Lists:Get(id)
    local lists = store()
    return lists and lists.byID[id]
end

---@param name string
---@param marker? integer  # 1..8; a free one when nil
---@param tooltip? boolean  # default true
---@return string? id
function Lists:Create(name, marker, tooltip)
    local lists = store()
    if not lists then
        return nil
    end
    local id = "l" .. lists.nextID
    lists.nextID = lists.nextID + 1
    name = strtrim(tostring(name or ""))
    lists.byID[id] = {
        name = name ~= "" and name or ("List " .. #lists.order),
        marker = validMarker(marker) or freeMarker(),
        tooltip = tooltip ~= false,
        items = {},
    }
    table.insert(lists.order, id)
    changed(id)
    return id
end

-- Deletes a list and its items; Favorites can't be deleted. The active list falls back to
-- Favorites.
---@param id string
---@return boolean
function Lists:Delete(id)
    local lists = store()
    if not lists or id == FAVORITES or not lists.byID[id] then
        return false
    end
    lists.byID[id] = nil
    tDeleteItem(lists.order, id)
    if lists.active == id then
        lists.active = FAVORITES
    end
    changed(id)
    return true
end

---@param id string
---@param name string
---@return boolean
function Lists:Rename(id, name)
    local list = self:Get(id)
    name = strtrim(tostring(name or ""))
    if not list or id == FAVORITES or name == "" or list.name == name then
        return false
    end
    list.name = name
    changed(id)
    return true
end

---@param id string
---@param marker integer  # 1..8
---@return boolean
function Lists:SetMarker(id, marker)
    local list = self:Get(id)
    marker = validMarker(marker) --[[@as integer]]
    if not list or id == FAVORITES or not marker or list.marker == marker then
        return false
    end
    list.marker = marker
    changed(id)
    return true
end

-- Whether item tooltips name this list.
---@param id string
---@param show boolean
---@return boolean
function Lists:SetShowInTooltip(id, show)
    local list = self:Get(id)
    if not list or list.tooltip == (show == true) then
        return false
    end
    list.tooltip = show == true
    changed(id)
    return true
end

-- The list alt-click adds to.
---@return string
function Lists:GetActive()
    local lists = store()
    local active = lists and lists.active
    return active and lists.byID[active] and active or FAVORITES
end

---@param id string
---@return boolean
function Lists:SetActive(id)
    local lists = store()
    if not lists or not lists.byID[id] or lists.active == id then
        return false
    end
    lists.active = id
    changed(id)
    return true
end

---------------------------------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------------------------------

---@param id string
---@param itemID integer
---@return boolean
function Lists:Contains(id, itemID)
    local list = self:Get(id)
    return list ~= nil and list.items[itemID] == true
end

-- Adds or removes an item; false when nothing changed.
---@param id string
---@param itemID integer
---@param on boolean
---@return boolean changed
function Lists:SetItem(id, itemID, on)
    local list = self:Get(id)
    if not list or type(itemID) ~= "number" or (list.items[itemID] == true) == (on == true) then
        return false
    end
    list.items[itemID] = on and true or nil
    changed(id, itemID)
    return true
end

-- Flips an item; returns whether the list has it now.
---@param id string
---@param itemID integer
---@return boolean
function Lists:Toggle(id, itemID)
    self:SetItem(id, itemID, not self:Contains(id, itemID))
    return self:Contains(id, itemID)
end

-- The list's item ids, ascending.
---@param id string
---@return integer[]
function Lists:GetItems(id)
    local list, ids = self:Get(id), {}
    for itemID in pairs(list and list.items or {}) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids)
    return ids
end

---@param id string
---@return integer
function Lists:GetCount(id)
    local list, count = self:Get(id), 0
    for _ in pairs(list and list.items or {}) do
        count = count + 1
    end
    return count
end

-- The ids of the lists that have the item, in list order.
---@param itemID integer
---@return string[]
function Lists:GetListsOf(itemID)
    local lists, ids = store(), {}
    if lists then
        for _, id in ipairs(lists.order) do
            if lists.byID[id].items[itemID] then
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

---------------------------------------------------------------------------------------------------
-- Markers
---------------------------------------------------------------------------------------------------

-- The texture of a marker (1..8), for icons and tiles.
---@param marker integer
---@return string
function Lists:GetMarkerFile(marker)
    return MARKER_PATH:format(marker)
end

-- Puts the list's marker (Favorites: the star) on a texture.
---@param texture Texture
---@param id string
function Lists:SetMarkerTexture(texture, id)
    local list = self:Get(id)
    if list and list.marker then
        texture:SetTexture(self:GetMarkerFile(list.marker))
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetAtlas(FAVORITE_ATLAS)
    end
end

-- The list's marker (Favorites: the star) as inline text markup, `size` high.
---@param id string
---@param size integer
---@return string
function Lists:GetMarkerMarkup(id, size)
    local list = self:Get(id)
    if list and list.marker then
        return CreateSimpleTextureMarkup(self:GetMarkerFile(list.marker), size, size)
    end
    local starSize = math.floor(size * FAVORITE_SCALE + 0.5)
    return CreateAtlasMarkup(FAVORITE_ATLAS, starSize, starSize)
end

---------------------------------------------------------------------------------------------------
-- Import / export: "FL1:<name>:<marker>:<id>,<id>,..." (":" and "%" in the name as %3A / %25)
---------------------------------------------------------------------------------------------------

---@param id string
---@return string?
function Lists:Export(id)
    local list = self:Get(id)
    if not list then
        return nil
    end
    local name = list.name:gsub("[%%:\r\n]", function(c)
        return ("%%%02X"):format(c:byte())
    end)
    return ("%s:%s:%d:%s"):format(EXPORT_PREFIX, name, list.marker or 0, table.concat(self:GetItems(id), ","))
end

-- The item ids (and, from an export, the name and marker) in a pasted text: an export string,
-- else every item link's id, else every number.
---@param text string
---@return integer[] ids, string? name, integer? marker
local function parse(text)
    local ids, seen = {}, {}
    local function add(value)
        local itemID = tonumber(value)
        if itemID and itemID > 0 and not seen[itemID] then
            seen[itemID] = true
            ids[#ids + 1] = itemID
        end
    end
    local name, marker, rest = text:match(EXPORT_PREFIX .. ":([^:]*):(%d+):([%d,%s]*)")
    if rest then
        for value in rest:gmatch("%d+") do
            add(value)
        end
        name = name:gsub("%%(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        return ids, name, validMarker(marker)
    end
    local pattern = text:find("item:%d+") and "item:(%d+)" or "%d+"
    for value in text:gmatch(pattern) do
        add(value)
    end
    return ids
end

-- Adds the items of a pasted text to list `intoID`, or to a new list named by the export (else
-- "Imported list"). Returns the list's id and how many items were new to it, or nil and why.
---@param text string
---@param intoID? string
---@return string? id, integer|string countOrError
function Lists:Import(text, intoID)
    if not store() then
        return nil, "Not loaded yet."
    end
    local ids, name, marker = parse(tostring(text or ""))
    if #ids == 0 then
        return nil, "No item ids found."
    end
    local id = intoID
    if id then
        if not self:Get(id) then
            return nil, "That list doesn't exist."
        end
    else
        id = self:Create(name ~= nil and name ~= "" and name or "Imported list", marker) --[[@as string]]
    end
    local items, added = self:Get(id).items, 0
    for _, itemID in ipairs(ids) do
        if not items[itemID] then
            items[itemID] = true
            added = added + 1
        end
    end
    changed(id)
    log:debug("Imported %d of %d items into %s", added, #ids, id)
    return id, added
end

---------------------------------------------------------------------------------------------------
-- Spyglass.Favorites: the favorites API of before the lists, over the Favorites list
---------------------------------------------------------------------------------------------------

---@class Spyglass.Favorites
local Favorites = {}
app.api.Favorites = Favorites

---@param itemID integer
---@return boolean
function Favorites:IsFavorite(itemID)
    return Lists:Contains(FAVORITES, itemID)
end

---@param itemID integer
---@param favorite boolean
---@return boolean changed
function Favorites:SetFavorite(itemID, favorite)
    return Lists:SetItem(FAVORITES, itemID, favorite)
end

---@param itemID integer
---@return boolean
function Favorites:Toggle(itemID)
    return Lists:Toggle(FAVORITES, itemID)
end

---@return integer[]
function Favorites:GetAll()
    return Lists:GetItems(FAVORITES)
end
