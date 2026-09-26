---@class SpyglassScraper
---@field name string
---@field api Spyglass.API
---@field coreAPIVersion integer
---@field log SpyglassScraper.Logger
---@field addon SpyglassScraper.Addon
---@field dbDefaults SpyglassScraper.DBDefaults
---@field db SpyglassScraper.DB
---@field discovery SpyglassScraper.Discovery
---@field json SpyglassScraper.JSON
---@field exportFrame SpyglassScraper.ExportFrame
---@field portraitFrame SpyglassScraper.PortraitFrame
---@field ExportFrameMixin SpyglassScraper.ExportFrame
local addonName, addon = ...

addon.name = addonName
addon.api = Spyglass
addon.coreAPIVersion = Spyglass.API_VERSION

-- Keep scraper output under the core's prefix and log-level setting without reaching into its
-- private logger. User-facing command output is unfiltered; diagnostic levels use LogAt.
---@class SpyglassScraper.Logger
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
