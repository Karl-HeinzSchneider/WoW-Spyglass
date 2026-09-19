-- Built-in module: Dungeons. Registers through the same public API third-party addons use.
-- Data is PLACEHOLDER until real loot tables exist; use ForeverLoot.Item(itemID) for real items.
local FL = ForeverLoot
local Folder, placeholderItems = FL.Folder, FL.PlaceholderItems

local ICON_DUNGEON = "Interface\\Icons\\Achievement_Dungeon_Deadmines"
local LOOT = { columns = 2 } -- boss loot tables are shown in two columns
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"

FL:RegisterModule({
    id = "dungeons",
    name = "Dungeons",
    icon = ICON_DUNGEON,
    order = 20,
    description = "Loot tables for 5-man dungeons.",
    children = {
        Folder("The Deadmines", ICON_DUNGEON, {
            Folder("Edwin VanCleef", ICON_BOSS, placeholderItems("VanCleef", 6), LOOT),
            Folder("Mr. Smite", ICON_BOSS, placeholderItems("Smite", 4), LOOT),
        }),
        Folder("Scarlet Monastery", ICON_DUNGEON, {
            Folder("Herod", ICON_BOSS, placeholderItems("Herod", 5), LOOT),
            Folder("High Inquisitor Whitemane", ICON_BOSS, placeholderItems("Whitemane", 7), LOOT),
        }),
    },
})
