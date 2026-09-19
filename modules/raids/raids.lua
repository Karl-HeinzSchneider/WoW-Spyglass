-- Built-in module: Raids. Registers through the same public API third-party addons use.
-- Data is PLACEHOLDER until real loot tables exist; use ForeverLoot.Item(itemID) for real items.
local FL = ForeverLoot
local Folder, placeholderItems = FL.Folder, FL.PlaceholderItems

local ICON_RAID = "Interface\\Icons\\Achievement_Boss_Ragnaros"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"

FL:RegisterModule({
    id = "raids",
    name = "Raids",
    icon = ICON_RAID,
    order = 10,
    description = "Loot tables for raid instances.",
    children = {
        Folder("Molten Core", ICON_RAID, {
            Folder("Lucifron", ICON_BOSS, placeholderItems("Lucifron", 9)),
            Folder("Magmadar", ICON_BOSS, placeholderItems("Magmadar", 12)),
            Folder("Ragnaros", ICON_BOSS, placeholderItems("Ragnaros", 21)),
        }),
        Folder("Blackwing Lair", ICON_RAID, {
            Folder("Razorgore", ICON_BOSS, placeholderItems("Razorgore", 8)),
            Folder("Nefarian", ICON_BOSS, placeholderItems("Nefarian", 18)),
        }),
        Folder("Onyxia's Lair", ICON_RAID, {
            Folder("Onyxia", ICON_BOSS, placeholderItems("Onyxia", 14)),
        }),
    },
})
