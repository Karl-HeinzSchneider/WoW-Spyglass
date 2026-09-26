---@type string, Spyglass
local _, app = ...

-- AceDB-3.0 defaults. Missing keys in the SavedVariables fall back to these values,
-- and values equal to the default are not written to disk.

-- User settings, switchable per character via AceDBOptions.
---@class Spyglass.DB.Profile
local profile = {
    logLevel = "INFO",
    minimap = {
        hide = false,
        -- Degrees around the minimap (0 = east, counter-clockwise), written by LibDBIcon on drag.
        -- LibDBIcon puts every button at 225 when it has none, so buttons nobody has dragged yet
        -- all stack on one spot; start a bit further round instead.
        minimapPos = 245,
    },
    -- Main window anchor relative to UIParent; written on drag stop.
    window = {
        point = "CENTER",
        x = 0,
        y = 0,
    },
}

-- Data tied to one character; loot history lives here.
---@class Spyglass.DB.Char
local char = {
    loot = {},
    -- The window's open tabs, written whenever one opens, closes, is selected or navigates.
    -- `paths[i]` = the names of the folders tab i has open below the root (empty = the root);
    -- `selected` = the index of the selected tab; `classFilters[i]` = tab i's footer class filter,
    -- `{ on = true, class = "MAGE", mode = "fade" }` (class nil = the character's class).
    tabs = {
        paths = {},
        selected = 1,
        classFilters = {},
    },
}

-- Account-wide data shared by every character.
---@class Spyglass.DB.Global
---@field lists? Spyglass.ListStore
---@field favorites? table<integer, true>  # before lists; moved into lists.byID.favorites
local global = {
    dbVersion = 2,
    -- `lists` = the user's item lists (lists.lua), created there on first use; it takes over
    -- `favorites` (itemID -> true) of the version before lists.
}

---@class Spyglass.DBDefaults : AceDB.Schema
app.dbDefaults = {
    profile = profile,
    char = char,
    global = global,
}
