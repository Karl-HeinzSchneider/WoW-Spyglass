---@type string, SpyglassScraper
local appName, app = ...

local SG = app.api
local log = app.log

---@class SpyglassScraper.Addon : AceAddon, AceEvent-3.0
---@field db SpyglassScraper.DB
---@field scanHandler function
---@field exportHandler function
---@field portraitHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceEvent-3.0")
app.addon = addon

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("SpyglassScraperDB", app.dbDefaults, true) --[[@as SpyglassScraper.DB]]
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
    SG:RegisterCommand("scan", self.scanHandler, "/sg scan <from> [to] | resume | stop | limit <n|off>")
    SG:RegisterCommand("export", self.exportHandler, "/sg export [all]")
    SG:RegisterCommand("portrait", self.portraitHandler, "/sg portrait [displayID]")
    log:debug("Enabled")
end

function addon:OnDisable()
    SG:UnregisterCommand("scan", self.scanHandler)
    SG:UnregisterCommand("export", self.exportHandler)
    SG:UnregisterCommand("portrait", self.portraitHandler)
    log:debug("Disabled")
end
