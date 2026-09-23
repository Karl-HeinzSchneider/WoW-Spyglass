---@class ForeverLootLocale
---@field name string
---@field api ForeverLoot.API
---@field coreAPIVersion integer
---@field log ForeverLootLocale.Logger
---@field addon ForeverLootLocale.Addon
---@field dbDefaults ForeverLootLocale.DBDefaults
---@field db ForeverLootLocale.DB
---@field itemNames ForeverLootLocale.ItemNames
local addonName, addon = ...

-- Companion addons communicate with the core exclusively through its public API. Generated
-- locale files loaded after this bootstrap register their names through ForeverLoot.Data.
addon.name = addonName
addon.api = ForeverLoot
addon.coreAPIVersion = ForeverLoot.API_VERSION

-- Output under the core's prefix and log-level setting, without reaching into its private
-- logger. User-facing command output is unfiltered; diagnostic levels use LogAt.
---@class ForeverLootLocale.Logger
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
