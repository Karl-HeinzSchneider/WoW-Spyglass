---@class ForeverLootScraper
---@field name string
---@field api ForeverLoot.API
---@field coreAPIVersion integer
---@field log ForeverLootScraper.Logger
---@field addon ForeverLootScraper.Addon
---@field dbDefaults ForeverLootScraper.DBDefaults
---@field db ForeverLootScraper.DB
---@field discovery ForeverLootScraper.Discovery
---@field json ForeverLootScraper.JSON
---@field exportFrame ForeverLootScraper.ExportFrame
---@field ExportFrameMixin ForeverLootScraper.ExportFrame
local addonName, addon = ...

addon.name = addonName
addon.api = ForeverLoot
addon.coreAPIVersion = ForeverLoot.API_VERSION

-- Keep scraper output under the core's prefix and log-level setting without reaching into its
-- private logger. User-facing command output is unfiltered; diagnostic levels use LogAt.
---@class ForeverLootScraper.Logger
local log = {}
addon.log = log

function log:chat(fmt, ...)
    ForeverLoot.Log(fmt, ...)
end

function log:info(fmt, ...)
    ForeverLoot.LogAt("INFO", fmt, ...)
end

function log:debug(fmt, ...)
    ForeverLoot.LogAt("DEBUG", fmt, ...)
end
