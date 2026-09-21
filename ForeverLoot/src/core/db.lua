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

-- One item recorded in-game (scanned, or seen dropping while the shipped database lacked it):
-- everything C_Item.GetItemInfo and C_Item.GetItemStats return. The same shape lands in
-- .contribute/data/items/*.json through `npm run import`; see discovery.lua.
---@class ForeverLoot.DiscoveredItem
---@field id integer  # the item id, repeated from the key so a record stands on its own
---@field name string  # in `Discovered.locale`
---@field quality integer
---@field itemLevel integer
---@field reqLevel integer
---@field classID integer
---@field subclassID integer
---@field slot string
---@field bind integer
---@field icon integer
---@field sellPrice integer
---@field stackCount integer
---@field setID integer  # 0 = none
---@field expansionID integer
---@field craftingReagent boolean
---@field stats? ForeverLoot.ItemStats
---@field exported? boolean  # part of an earlier /fl export; left out of the next one

-- What was seen dropping from one boss (DungeonEncounter id).
---@class ForeverLoot.DiscoveredLoot
---@field id integer  # the encounter id, repeated from the key
---@field kills integer  # successful ENCOUNTER_ENDs
---@field items table<integer, integer>  # itemID -> kills in which it dropped

---@class ForeverLoot.Discovered
---@field build? string  # client build the data was recorded on, informational
---@field locale? string  # GetLocale() of the recording client: the language of item names
---@field items table<integer, ForeverLoot.DiscoveredItem>
---@field loot table<integer, ForeverLoot.DiscoveredLoot>

-- Where `/fl scan` left off, so `/fl scan resume` continues after a /reload.
---@class ForeverLoot.ScanProgress
---@field next? integer  # first id not yet requested
---@field to? integer  # upper bound of that scan, nil = open-ended
---@field limit? integer  # new items per scan before it stops; 0 = no limit; nil = the default

-- Account-wide data shared by every character.
---@class ForeverLoot.DB.Global
local global = {
    dbVersion = 1,
    -- Everything recorded in-game that the shipped database may lack. Read by
    -- the root `npm run import` command and by `/fl export`.
    ---@type ForeverLoot.Discovered
    discovered = {
        items = {},
        loot = {},
    },
    ---@type ForeverLoot.ScanProgress
    scan = {},
}

---@class ForeverLoot.DBDefaults : AceDB.Schema
app.dbDefaults = {
    profile = profile,
    char = char,
    global = global,
}
