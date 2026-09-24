---@type string, ForeverLoot
local _, app = ...

-- AceDB-3.0 defaults. Missing keys in the SavedVariables fall back to these values,
-- and values equal to the default are not written to disk.

-- User settings, switchable per character via AceDBOptions.
---@class ForeverLoot.DB.Profile
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
---@class ForeverLoot.DB.Char
local char = {
    loot = {},
}

-- Account-wide data shared by every character.
---@class ForeverLoot.DB.Global
local global = {
    dbVersion = 2,
}

---@class ForeverLoot.DBDefaults : AceDB.Schema
app.dbDefaults = {
    profile = profile,
    char = char,
    global = global,
}
