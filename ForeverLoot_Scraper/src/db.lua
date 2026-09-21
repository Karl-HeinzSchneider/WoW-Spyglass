---@type string, ForeverLootScraper
local _, app = ...

-- One item recorded in-game (scanned, or seen dropping while the shipped database lacked it).
---@class ForeverLootScraper.DiscoveredItem
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
---@field stats? ForeverLoot.ItemStats
---@field exported? boolean

---@class ForeverLootScraper.DiscoveredLoot
---@field id integer
---@field kills integer
---@field items table<integer, integer>

---@class ForeverLootScraper.Discovered
---@field build? string
---@field locale? string
---@field items table<integer, ForeverLootScraper.DiscoveredItem>
---@field loot table<integer, ForeverLootScraper.DiscoveredLoot>

---@class ForeverLootScraper.ScanProgress
---@field next? integer
---@field to? integer
---@field limit? integer

---@class ForeverLootScraper.DB.Global
local global = {
    dbVersion = 1,
    ---@type ForeverLootScraper.Discovered
    discovered = {
        items = {},
        loot = {},
    },
    ---@type ForeverLootScraper.ScanProgress
    scan = {},
}

---@class ForeverLootScraper.DBDefaults : AceDB.Schema
app.dbDefaults = {
    global = global,
}
