-- Built-in module: Dungeons. Each instance is listed explicitly below (one `InstanceFolder` per
-- line) so only dungeons with curated loot show up; uncomment a line once its drops are in
-- .contribute/data/dungeons/*.json. Bosses and levels come from the item database (Spyglass/db/generated).
local SG = Spyglass

SG:RegisterModule({
    id = "dungeons",
    name = "Dungeons",
    icon = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
    order = 10,
    description = "Loot tables for 5-man dungeons.",
    display = "tiles",
    getChildren = function()
        return {
            SG.InstanceFolder(389), -- Ragefire Chasm
            SG.InstanceFolder(43), -- Wailing Caverns
            SG.InstanceFolder(36), -- Deadmines
            SG.InstanceFolder(33), -- Shadowfang Keep
            SG.InstanceFolder(48), -- Blackfathom Deeps
            SG.InstanceFolder(34), -- Stormwind Stockade
            SG.InstanceFolder(90), -- Gnomeregan
            SG.InstanceFolder(47), -- Razorfen Kraul
            SG.InstanceFolder(18901), -- Scarlet Monastery: Graveyard
            SG.InstanceFolder(18902), -- Scarlet Monastery: Library
            SG.InstanceFolder(18903), -- Scarlet Monastery: Armory
            SG.InstanceFolder(18904), -- Scarlet Monastery: Cathedral
            SG.InstanceFolder(129), -- Razorfen Downs
            SG.InstanceFolder(70), -- Uldaman
            SG.InstanceFolder(209), -- Zul'Farrak
            SG.InstanceFolder(349), -- Maraudon
            SG.InstanceFolder(109), -- Sunken Temple
            SG.InstanceFolder(230), -- Blackrock Depths
            SG.InstanceFolder(22901), -- Blackrock Spire: Lower
            SG.InstanceFolder(22902), -- Blackrock Spire: Upper
            SG.InstanceFolder(42901), -- Dire Maul: East
            SG.InstanceFolder(42902), -- Dire Maul: West
            SG.InstanceFolder(42903), -- Dire Maul: North
            SG.InstanceFolder(329), -- Stratholme
            SG.InstanceFolder(289), -- Scholomance
            SG.InstanceFolder(2720), -- The Searing Basin
            SG.InstanceFolder(2784), -- Demon Fall Canyon
            SG.InstanceFolder(2875), -- Karazhan Crypts
            -- SG.InstanceFolder(2921), -- Naxxramas (5-man)
            SG.InstanceFolder(2959), -- City of Dalaran
            SG.InstanceFolder(2998), -- Excavation Site: Wetlands
            SG.InstanceFolder(2999), -- Ruins of Lordaeron
            SG.InstanceFolder(3002), -- Half-Pint Tavern
            SG.InstanceFolder(3065), -- The Hall of Thanes
        }
    end,
    -- By level range (instances without a curated one go last), then name.
    sortChildren = function(a, b)
        local la, lb = a.minLevel or 999, b.minLevel or 999
        if la ~= lb then
            return la < lb
        end
        local ha, hb = a.maxLevel or 999, b.maxLevel or 999
        if ha ~= hb then
            return ha < hb
        end
        return (a.name or "") < (b.name or "")
    end,
})
