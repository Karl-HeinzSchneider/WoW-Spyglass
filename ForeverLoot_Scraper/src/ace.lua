---@type string, ForeverLootScraper
local appName, app = ...

local FL = app.api
local log = app.log

---@class ForeverLootScraper.Addon : AceAddon, AceEvent-3.0
---@field db ForeverLootScraper.DB
---@field scanHandler function
---@field exportHandler function
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceEvent-3.0")
app.addon = addon

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, child in pairs(value) do
        result[copy(key)] = copy(child)
    end
    return result
end

local function mergeMissing(target, source)
    if type(source) ~= "table" then
        return
    end
    for key, value in pairs(source) do
        if target[key] == nil then
            target[key] = copy(value)
        end
    end
end

-- Moves pre-split discovery state once, then removes it from the core SavedVariables table. New
-- scraper data is written only to ForeverLootScraperDB.
local function migrateCoreState(db)
    if db.global.migratedFromCore then
        return
    end
    local legacy = type(ForeverLootDB) == "table" and ForeverLootDB.global or nil
    local migrated = false
    if type(legacy) == "table" then
        local oldDiscovered = legacy.discovered
        if type(oldDiscovered) == "table" then
            local target = db.global.discovered
            if target.build == nil then
                target.build = oldDiscovered.build
            end
            if target.locale == nil then
                target.locale = oldDiscovered.locale
            end
            mergeMissing(target.items, oldDiscovered.items)
            for bossID, oldLoot in pairs(oldDiscovered.loot or {}) do
                local current = target.loot[bossID]
                if current == nil then
                    target.loot[bossID] = copy(oldLoot)
                else
                    current.kills = math.max(current.kills or 0, oldLoot.kills or 0)
                    current.items = current.items or {}
                    for itemID, count in pairs(oldLoot.items or {}) do
                        current.items[itemID] = math.max(current.items[itemID] or 0, count)
                    end
                end
            end
            migrated = true
        end
        if type(legacy.scan) == "table" then
            mergeMissing(db.global.scan, legacy.scan)
            migrated = true
        end
        legacy.discovered = nil
        legacy.scan = nil
        legacy.dbVersion = nil
    end
    db.global.migratedFromCore = true
    if migrated then
        log:chat("Migrated scanner data to ForeverLootScraperDB")
    end
end

function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("ForeverLootScraperDB", app.dbDefaults, true) --[[@as ForeverLootScraper.DB]]
    self.db = db
    app.db = db
    migrateCoreState(db)

    self.scanHandler = function(a, b, c)
        app.discovery:ScanCommand(a, b, c)
    end
    self.exportHandler = function(a)
        app.discovery:ExportCommand(a)
    end
end

function addon:OnEnable()
    FL:RegisterCommand(
        "scan",
        self.scanHandler,
        "/fl scan <from> [to] | resume | stop | limit <n|off>"
    )
    FL:RegisterCommand("export", self.exportHandler, "/fl export [all]")
    log:debug("Enabled")
end

function addon:OnDisable()
    FL:UnregisterCommand("scan", self.scanHandler)
    FL:UnregisterCommand("export", self.exportHandler)
    log:debug("Disabled")
end
