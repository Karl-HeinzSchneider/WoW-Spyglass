-- Built-in module: Raids. Each instance is listed explicitly below (one `InstanceFolder` per
-- line) so only raids with curated loot show up; uncomment a line once its drops are in
-- .contribute/data/raids/*.json. Bosses and levels come from the item database (ForeverLoot/db/generated).
-- The list order is the display order.
local FL = ForeverLoot

FL:RegisterModule({
    id = "raids",
    name = "Raids",
    icon = "Interface\\Icons\\Achievement_Dungeon_ClassicRaider",
    order = 10,
    description = "Loot tables for raid instances.",
    display = "tiles",
    getChildren = function()
        return {
            FL.InstanceFolder(249), -- Onyxia's Lair
            -- FL.InstanceFolder(409), -- Molten Core
            -- FL.InstanceFolder(469), -- Blackwing Lair
            -- FL.InstanceFolder(309), -- Zul'Gurub
            -- FL.InstanceFolder(509), -- Ruins of Ahn'Qiraj
            -- FL.InstanceFolder(531), -- Ahn'Qiraj Temple
            -- FL.InstanceFolder(533), -- Naxxramas
            -- FL.InstanceFolder(2789), -- The Tainted Scar
            -- FL.InstanceFolder(2791), -- Storm Cliffs
            -- FL.InstanceFolder(2804), -- The Crystal Vale
            -- FL.InstanceFolder(2832), -- Nightmare Grove
            -- FL.InstanceFolder(2856), -- Scarlet Enclave
        }
    end,
})
