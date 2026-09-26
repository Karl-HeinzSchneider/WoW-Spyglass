---@type string, SpyglassLocale
local appName, app = ...

local SG = app.api
local log = app.log

---@class SpyglassLocale.Addon : AceAddon
---@field db SpyglassLocale.DB
---@field localeHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName)
app.addon = addon

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("SpyglassLocaleDB", app.dbDefaults, true) --[[@as SpyglassLocale.DB]]
    self.db = db
    app.db = db

    self.localeHandler = function(a)
        app.itemNames:Command(a)
    end
end

function addon:OnEnable()
    SG:RegisterCommand("locale", self.localeHandler, "/sg locale [rescan]")
    log:debug("Enabled")
end

function addon:OnDisable()
    SG:UnregisterCommand("locale", self.localeHandler)
    log:debug("Disabled")
end
