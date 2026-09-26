-- Built-in module: Raids. Each instance is listed explicitly below (one `InstanceFolder` per
-- line) so only raids with curated loot show up; uncomment a line once its drops are in
-- .contribute/data/raids/*.json. Bosses and levels come from the item database (Spyglass/db/generated).
-- The list order is the display order.
local SG = Spyglass

SG:RegisterModule({
    id = "raids",
    name = "Raids",
    icon = "Interface\\Icons\\Achievement_Dungeon_ClassicRaider",
    order = 20,
    description = "Loot tables for raid instances.",
    display = "tiles",
    getChildren = function()
        return {
            SG.InstanceFolder(249), -- Onyxia's Lair
            -- SG.InstanceFolder(409), -- Molten Core
            -- SG.InstanceFolder(469), -- Blackwing Lair
            -- SG.InstanceFolder(309), -- Zul'Gurub
            -- SG.InstanceFolder(509), -- Ruins of Ahn'Qiraj
            -- SG.InstanceFolder(531), -- Ahn'Qiraj Temple
            -- SG.InstanceFolder(533), -- Naxxramas
            -- SG.InstanceFolder(2789), -- The Tainted Scar
            -- SG.InstanceFolder(2791), -- Storm Cliffs
            -- SG.InstanceFolder(2804), -- The Crystal Vale
            -- SG.InstanceFolder(2832), -- Nightmare Grove
            -- SG.InstanceFolder(2856), -- Scarlet Enclave
        }
    end,
})
