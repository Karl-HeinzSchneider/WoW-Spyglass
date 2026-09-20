-- Dungeon: Scarlet Monastery. PLACEHOLDER loot until real item IDs exist.
local FL = ForeverLoot
local Folder, placeholderItems = FL.Folder, FL.PlaceholderItems

local ICON = "Interface\\Icons\\Achievement_Dungeon_Deadmines"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local LOOT = { columns = 2 }

local dungeon = Folder("Scarlet Monastery", ICON, {
    Folder("Herod", ICON_BOSS, placeholderItems("Herod", 5), LOOT),
    Folder("High Inquisitor Whitemane", ICON_BOSS, placeholderItems("Whitemane", 7), LOOT),
}, {
    order = 34, -- level, used as sort key within the module
    minLevel = 26,
    maxLevel = 45,
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    instanceID = 189,
})

FL:AddToModule("dungeons", dungeon)
