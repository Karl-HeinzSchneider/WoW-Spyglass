---@type string, SpyglassLocale
local _, app = ...

-- Item names the client told us in its language, for the items the generated locale files don't
-- name (see itemnames.lua). Kept per language, so switching the game's language keeps what the
-- other one learned.
---@class SpyglassLocale.LearnedNames
---@field build? string  # client build the `missing` marks belong to
---@field items table<integer, string>  # itemID -> name in this language
---@field missing table<integer, boolean>  # ids the server didn't know; not asked again this build

---@class SpyglassLocale.DB : AceDBObject-3.0
---@field global SpyglassLocale.DB.Global

---@class SpyglassLocale.DB.Global
local global = {
    dbVersion = 1,
    ---@type table<string, SpyglassLocale.LearnedNames>
    locales = {
        ["*"] = { items = {}, missing = {} },
    },
}

---@class SpyglassLocale.DBDefaults : AceDB.Schema
app.dbDefaults = {
    global = global,
}
