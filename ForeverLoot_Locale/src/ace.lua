---@type string, ForeverLootLocale
local appName, app = ...

local FL = app.api
local log = app.log

---@class ForeverLootLocale.Addon : AceAddon
---@field db ForeverLootLocale.DB
---@field localeHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName)
app.addon = addon

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("ForeverLootLocaleDB", app.dbDefaults, true) --[[@as ForeverLootLocale.DB]]
    self.db = db
    app.db = db

    self.localeHandler = function(a)
        app.itemNames:Command(a)
    end
end

function addon:OnEnable()
    FL:RegisterCommand("locale", self.localeHandler, "/fl locale [rescan]")
    log:debug("Enabled")
end

function addon:OnDisable()
    FL:UnregisterCommand("locale", self.localeHandler)
    log:debug("Disabled")
end
