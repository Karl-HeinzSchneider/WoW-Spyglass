---@class ForeverLootLocale
---@field name string
---@field api ForeverLoot.API
---@field coreAPIVersion integer
local addonName, addon = ...

-- Companion addons communicate with the core exclusively through its public API. Generated
-- locale files loaded after this bootstrap register their names through ForeverLoot.Data.
addon.name = addonName
addon.api = ForeverLoot
addon.coreAPIVersion = ForeverLoot.API_VERSION
