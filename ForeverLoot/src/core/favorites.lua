---@type string, ForeverLoot
local _, app = ...

-- The items the user marked as favorites (alt-click in the window), account-wide in
-- ForeverLootDB.global.favorites as itemID -> true. Public as ForeverLoot.Favorites; every change
-- fires OnFavoritesChanged(itemID, isFavorite). Until the SavedVariables are loaded there are
-- none and nothing can be changed.

---@class ForeverLoot.Favorites
local Favorites = {}
app.favorites = Favorites
app.api.Favorites = Favorites

---@return table<integer, true>?
local function store()
    return app.db and app.db.global.favorites
end

---@param itemID integer
---@return boolean
function Favorites:IsFavorite(itemID)
    local favorites = store()
    return favorites ~= nil and favorites[itemID] == true
end

-- Marks or unmarks an item; false when nothing changed.
---@param itemID integer
---@param favorite boolean
---@return boolean changed
function Favorites:SetFavorite(itemID, favorite)
    local favorites = store()
    if not favorites or type(itemID) ~= "number" or self:IsFavorite(itemID) == (favorite == true) then
        return false
    end
    favorites[itemID] = favorite and true or nil
    app.api.callbacks:Fire("OnFavoritesChanged", itemID, favorite == true)
    return true
end

-- Flips an item's mark; returns whether it is a favorite now.
---@param itemID integer
---@return boolean
function Favorites:Toggle(itemID)
    local favorite = not self:IsFavorite(itemID)
    self:SetFavorite(itemID, favorite)
    return self:IsFavorite(itemID)
end

-- Every favorite item id, ascending.
---@return integer[]
function Favorites:GetAll()
    local ids = {}
    for itemID in pairs(store() or {}) do
        ids[#ids + 1] = itemID
    end
    table.sort(ids)
    return ids
end
