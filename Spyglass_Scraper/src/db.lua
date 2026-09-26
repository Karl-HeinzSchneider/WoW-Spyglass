---@type string, SpyglassScraper
local _, app = ...

-- One item recorded in-game (scanned, or seen dropping while the shipped database lacked it).
---@class SpyglassScraper.DiscoveredItem
---@field id integer
---@field name string
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
---@field setID integer
---@field expansionID integer
---@field craftingReagent boolean
---@field stats? Spyglass.ItemStats
---@field exported? boolean

---@class SpyglassScraper.DiscoveredLoot
---@field id integer
---@field kills integer
---@field items table<integer, integer>

---@class SpyglassScraper.Discovered
---@field build? string
---@field locale? string
---@field items table<integer, SpyglassScraper.DiscoveredItem>
---@field loot table<integer, SpyglassScraper.DiscoveredLoot>

---@class SpyglassScraper.ScanProgress
---@field next? integer
---@field to? integer
---@field limit? integer

---@class SpyglassScraper.DB.Global
local global = {
    dbVersion = 1,
    ---@type SpyglassScraper.Discovered
    discovered = {
        items = {},
        loot = {},
    },
    ---@type SpyglassScraper.ScanProgress
    scan = {},
}

---@class SpyglassScraper.DBDefaults : AceDB.Schema
app.dbDefaults = {
    global = global,
}
