---@class SpyglassLocale
---@field name string
---@field api Spyglass.API
---@field coreAPIVersion integer
---@field log SpyglassLocale.Logger
---@field addon SpyglassLocale.Addon
---@field dbDefaults SpyglassLocale.DBDefaults
---@field db SpyglassLocale.DB
---@field itemNames SpyglassLocale.ItemNames
local addonName, addon = ...

-- Companion addons communicate with the core exclusively through its public API. Generated
-- locale files loaded after this bootstrap register their names through Spyglass.Data.
addon.name = addonName
addon.api = Spyglass
addon.coreAPIVersion = Spyglass.API_VERSION

-- Output under the core's prefix and log-level setting, without reaching into its private
-- logger. User-facing command output is unfiltered; diagnostic levels use LogAt.
---@class SpyglassLocale.Logger
local log = {}
addon.log = log

function log:chat(fmt, ...)
    Spyglass.Log(fmt, ...)
end

function log:info(fmt, ...)
    Spyglass.LogAt("INFO", fmt, ...)
end

function log:debug(fmt, ...)
    Spyglass.LogAt("DEBUG", fmt, ...)
end
