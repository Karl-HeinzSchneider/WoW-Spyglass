---@type string, SpyglassScraper
local appName, app = ...

local SG = app.api
local log = app.log

---@class SpyglassScraper.Addon : AceAddon, AceEvent-3.0
---@field db SpyglassScraper.DB
---@field scanHandler function
---@field exportHandler function
---@field portraitHandler function
---@field levelsHandler function
---@field trainerHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceEvent-3.0")
app.addon = addon

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("SpyglassScraperDB", app.dbDefaults, true) --[[@as SpyglassScraper.DB]]
    self.db = db
    app.db = db

    local optionsName = "Spyglass Scraper"
    LibStub("AceConfig-3.0"):RegisterOptionsTable(optionsName, {
        type = "group",
        name = optionsName,
        args = {
            collectLoot = {
                type = "toggle",
                order = 10,
                width = "full",
                name = "Automatically collect mob drops",
                desc = "Record new items from loot and group rolls, and track boss kills and drops.",
                get = function()
                    return db.global.collectLoot
                end,
                set = function(_, enabled)
                    app.discovery:SetLootCollection(enabled)
                end,
            },
            deleteCache = {
                type = "execute",
                order = 20,
                width = "full",
                name = "Delete scraper cache",
                desc = "Delete collected items, boss loot and trainer snapshots, then reload the UI.",
                confirm = true,
                confirmText = "Delete all collected items, boss loot and trainer snapshots and reload the UI?",
                func = function()
                    app.discovery:DeleteCache()
                end,
            },
        },
    })
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(optionsName)

    self.scanHandler = function(a, b, c)
        app.discovery:ScanCommand(a, b, c)
    end
    self.exportHandler = function(a)
        app.discovery:ExportCommand(a)
    end
    self.portraitHandler = function(a)
        app.portraitFrame:Command(a)
    end
    self.levelsHandler = function()
        app.discovery:LevelsCommand()
    end
    self.trainerHandler = function()
        app.discovery:TrainerCommand()
    end
end

function addon:OnEnable()
    SG:RegisterCommand(
        "scan",
        self.scanHandler,
        "/sg scan <from> [to] | missing | resume | stop | limit <n|off> | batch <n|reset>"
    )
    SG:RegisterCommand("export", self.exportHandler, "/sg export [all]")
    SG:RegisterCommand("portrait", self.portraitHandler, "/sg portrait [displayID]")
    SG:RegisterCommand("levels", self.levelsHandler, "/sg levels")
    SG:RegisterCommand("trainer", self.trainerHandler, "/sg trainer")
    log:debug("Enabled")
end

function addon:OnDisable()
    SG:UnregisterCommand("scan", self.scanHandler)
    SG:UnregisterCommand("export", self.exportHandler)
    SG:UnregisterCommand("portrait", self.portraitHandler)
    SG:UnregisterCommand("levels", self.levelsHandler)
    SG:UnregisterCommand("trainer", self.trainerHandler)
    log:debug("Disabled")
end
