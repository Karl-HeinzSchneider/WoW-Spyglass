-- Dungeon: The Deadmines. PLACEHOLDER loot until real item IDs exist.
local FL = ForeverLoot
local Folder, placeholderItems = FL.Folder, FL.PlaceholderItems

local ICON = "Interface\\Icons\\Achievement_Dungeon_Deadmines"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local LOOT = { columns = 2 }

local dungeon = Folder("The Deadmines", ICON, {
    Folder("Mr. Smite", ICON_BOSS, placeholderItems("Smite", 4), LOOT),
    Folder("Edwin VanCleef", ICON_BOSS, placeholderItems("VanCleef", 6), LOOT),
}, {
    order = 17, -- level, used as sort key within the module
    minLevel = 15,
    maxLevel = 21,
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    instanceID = 36,
})

FL:AddToModule("dungeons", dungeon)
