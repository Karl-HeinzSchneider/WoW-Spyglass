-- Built-in module: Dungeons. Each instance is listed explicitly below (one `InstanceFolder` per
-- line) so only dungeons with curated loot show up; uncomment a line once its drops are in
-- .contribute/dungeons/*.json. Bosses and levels come from the item database (db/generated).
-- The list order is the display order.
local FL = ForeverLoot

FL:RegisterModule({
    id = "dungeons",
    name = "Dungeons",
    icon = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
    order = 20,
    description = "Loot tables for 5-man dungeons.",
    getChildren = function()
        return {
            FL.InstanceFolder(389), -- Ragefire Chasm
            FL.InstanceFolder(43), -- Wailing Caverns
            FL.InstanceFolder(36), -- Deadmines
            FL.InstanceFolder(33), -- Shadowfang Keep
            FL.InstanceFolder(48), -- Blackfathom Deeps
            FL.InstanceFolder(34), -- Stormwind Stockade
            FL.InstanceFolder(90), -- Gnomeregan
            FL.InstanceFolder(47), -- Razorfen Kraul
            FL.InstanceFolder(189), -- Scarlet Monastery
            FL.InstanceFolder(129), -- Razorfen Downs
            FL.InstanceFolder(70), -- Uldaman
            FL.InstanceFolder(209), -- Zul'Farrak
            FL.InstanceFolder(349), -- Maraudon
            FL.InstanceFolder(109), -- Sunken Temple
            FL.InstanceFolder(230), -- Blackrock Depths
            FL.InstanceFolder(229), -- Blackrock Spire
            FL.InstanceFolder(429), -- Dire Maul
            FL.InstanceFolder(329), -- Stratholme
            FL.InstanceFolder(289), -- Scholomance
            FL.InstanceFolder(2720), -- The Searing Basin
            FL.InstanceFolder(2784), -- Demon Fall Canyon
            FL.InstanceFolder(2875), -- Karazhan Crypts
            -- FL.InstanceFolder(2921), -- Naxxramas (5-man)
            FL.InstanceFolder(2959), -- City of Dalaran
            FL.InstanceFolder(2998), -- Excavation Site: Wetlands
            FL.InstanceFolder(2999), -- Ruins of Lordaeron
            FL.InstanceFolder(3002), -- Half-Pint Tavern
            FL.InstanceFolder(3065), -- The Hall of Thanes
        }
    end,
})
