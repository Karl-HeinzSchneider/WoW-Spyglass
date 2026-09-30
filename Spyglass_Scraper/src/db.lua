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

---@class SpyglassScraper.TrainerService
---@field name string
---@field type string
---@field subText? string
---@field category? string
---@field icon? number|string
---@field requiredLevel? number
---@field skillName? string
---@field skillRank? number
---@field abilityRequirements? table<integer, string>
---@field cost? number
---@field isProfession? boolean
---@field skillLineName? string
---@field description? string
---@field itemLink? string
---@field source string  # "trainer"

---@class SpyglassScraper.DiscoveredTrainer
---@field id integer
---@field name string
---@field locale string
---@field build string
---@field zone? string
---@field faction? string
---@field trainerType? number
---@field playerLevel? number
---@field playerClass? string
---@field services table<integer, SpyglassScraper.TrainerService>

---@class SpyglassScraper.Discovered
---@field build? string
---@field locale? string
---@field items table<integer, SpyglassScraper.DiscoveredItem>
---@field loot table<integer, SpyglassScraper.DiscoveredLoot>
---@field trainers table<integer, SpyglassScraper.DiscoveredTrainer>

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
        trainers = {},
    },
    ---@type SpyglassScraper.ScanProgress
    scan = {},
}

---@class SpyglassScraper.DBDefaults : AceDB.Schema
app.dbDefaults = {
    global = global,
}
