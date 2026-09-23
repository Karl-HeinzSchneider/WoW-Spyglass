---@type string, ForeverLootLocale
local _, app = ...

-- Item names the client told us in its language, for the items the generated locale files don't
-- name (see itemnames.lua). Kept per language, so switching the game's language keeps what the
-- other one learned.
---@class ForeverLootLocale.LearnedNames
---@field build? string  # client build the `missing` marks belong to
---@field items table<integer, string>  # itemID -> name in this language
---@field missing table<integer, boolean>  # ids the server didn't know; not asked again this build

---@class ForeverLootLocale.DB : AceDBObject-3.0
---@field global ForeverLootLocale.DB.Global

---@class ForeverLootLocale.DB.Global
local global = {
    dbVersion = 1,
    ---@type table<string, ForeverLootLocale.LearnedNames>
    locales = {
        ["*"] = { items = {}, missing = {} },
    },
}

---@class ForeverLootLocale.DBDefaults : AceDB.Schema
app.dbDefaults = {
    global = global,
}
