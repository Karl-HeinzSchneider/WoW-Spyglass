---@type string, ForeverLootScraper
local appName, app = ...

local FL = app.api
local log = app.log

---@class ForeverLootScraper.Addon : AceAddon, AceEvent-3.0
---@field db ForeverLootScraper.DB
---@field scanHandler function
---@field exportHandler function
---@field portraitHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceEvent-3.0")
app.addon = addon

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("ForeverLootScraperDB", app.dbDefaults, true) --[[@as ForeverLootScraper.DB]]
    self.db = db
    app.db = db

    self.scanHandler = function(a, b, c)
        app.discovery:ScanCommand(a, b, c)
    end
    self.exportHandler = function(a)
        app.discovery:ExportCommand(a)
    end
    self.portraitHandler = function(a)
        app.portraitFrame:Command(a)
    end
end

function addon:OnEnable()
    FL:RegisterCommand("scan", self.scanHandler, "/fl scan <from> [to] | resume | stop | limit <n|off>")
    FL:RegisterCommand("export", self.exportHandler, "/fl export [all]")
    FL:RegisterCommand("portrait", self.portraitHandler, "/fl portrait [displayID]")
    log:debug("Enabled")
end

function addon:OnDisable()
    FL:UnregisterCommand("scan", self.scanHandler)
    FL:UnregisterCommand("export", self.exportHandler)
    FL:UnregisterCommand("portrait", self.portraitHandler)
    log:debug("Disabled")
end
