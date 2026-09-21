---@class ForeverLootLocale
---@field name string
---@field api ForeverLoot.API
---@field coreAPIVersion integer
local addonName, addon = ...

-- Companion addons communicate with the core exclusively through its public API. Locale data
-- remains in the core until the step-9 extraction; this bootstrap establishes the load boundary.
addon.name = addonName
addon.api = ForeverLoot
addon.coreAPIVersion = ForeverLoot.API_VERSION
