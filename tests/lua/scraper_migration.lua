-- Executes the real scraper initialization against minimal Ace stubs. This protects the one-time
-- SavedVariables migration without requiring a WoW client.

local messages = {}
ForeverLoot = {
    API_VERSION = 1,
    Log = function(message)
        messages[#messages + 1] = message
    end,
    LogAt = function()
        return true
    end,
}

ForeverLootDB = {
    global = {
        dbVersion = 1,
        discovered = {
            build = "legacy-build",
            locale = "deDE",
            items = {
                [101] = { id = 101, name = "Legacy item" },
            },
            loot = {
                [7] = { id = 7, kills = 4, items = { [101] = 2, [102] = 3 } },
            },
        },
        scan = { next = 1234, to = 2000, limit = 0 },
    },
}

local scraperDB = {
    global = {
        dbVersion = 1,
        migratedFromCore = false,
        discovered = {
            items = { [202] = { id = 202, name = "Current item" } },
            loot = { [7] = { id = 7, kills = 5, items = { [101] = 1, [103] = 1 } } },
        },
        scan = {},
    },
}

local aceAddon = {}
function aceAddon:NewAddon(target)
    target.NewModule = function()
        error("modules are not needed by this migration test")
    end
end

local aceDB = {}
function aceDB:New(name)
    assert(name == "ForeverLootScraperDB")
    return scraperDB
end

function LibStub(name)
    if name == "AceAddon-3.0" then
        return aceAddon
    elseif name == "AceDB-3.0" then
        return aceDB
    end
    error("unexpected library " .. tostring(name))
end

local app = {}
assert(loadfile("ForeverLoot_Scraper/ForeverLoot_Scraper.lua"))("ForeverLoot_Scraper", app)
assert(loadfile("ForeverLoot_Scraper/src/db.lua"))("ForeverLoot_Scraper", app)
assert(loadfile("ForeverLoot_Scraper/src/ace.lua"))("ForeverLoot_Scraper", app)

app.addon:OnInitialize()

local global = scraperDB.global
assert(global.migratedFromCore == true, "migration marker was not written")
assert(global.discovered.build == "legacy-build" and global.discovered.locale == "deDE", "metadata was not migrated")
assert(global.discovered.items[101].name == "Legacy item", "legacy item was not migrated")
assert(global.discovered.items[202].name == "Current item", "existing scraper item was lost")
assert(global.discovered.loot[7].kills == 5, "larger existing kill count was not retained")
assert(global.discovered.loot[7].items[101] == 2, "larger legacy item count was not retained")
assert(global.discovered.loot[7].items[102] == 3, "legacy loot item was not migrated")
assert(global.discovered.loot[7].items[103] == 1, "existing scraper loot item was lost")
assert(global.scan.next == 1234 and global.scan.to == 2000 and global.scan.limit == 0, "scan progress was not migrated")
assert(ForeverLootDB.global.discovered == nil, "legacy discovered state was not removed")
assert(ForeverLootDB.global.scan == nil, "legacy scan state was not removed")
assert(ForeverLootDB.global.dbVersion == nil, "legacy schema version was not removed")
assert(#messages == 1, "migration was not reported exactly once")

-- The marker makes subsequent initialization idempotent, even if stale legacy values reappear.
ForeverLootDB.global.discovered = { items = { [303] = { id = 303, name = "Must not migrate" } }, loot = {} }
app.addon:OnInitialize()
assert(global.discovered.items[303] == nil, "migration ran more than once")

print("Scraper migration OK")
