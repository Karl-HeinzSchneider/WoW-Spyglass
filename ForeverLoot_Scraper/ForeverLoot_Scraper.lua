---@class ForeverLootScraper
---@field name string
---@field api ForeverLoot.API
---@field coreAPIVersion integer
local addonName, addon = ...

-- Scanning remains in the core until the step-10 extraction. The future scraper may publish
-- data through ForeverLoot.Data, but it must never reach into the core addon's private table.
addon.name = addonName
addon.api = ForeverLoot
addon.coreAPIVersion = ForeverLoot.API_VERSION
