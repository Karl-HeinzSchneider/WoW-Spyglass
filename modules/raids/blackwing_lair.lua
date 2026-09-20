-- Raid: Blackwing Lair. PLACEHOLDER loot until real item IDs exist.
local FL = ForeverLoot
local Folder, Group, placeholderItems = FL.Folder, FL.Group, FL.PlaceholderItems

local ICON = "Interface\\Icons\\Achievement_Boss_Ragnaros"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local LOOT = { columns = 2 }

local raid = Folder("Blackwing Lair", ICON, {
    Folder("Razorgore", ICON_BOSS, placeholderItems("Razorgore", 8), LOOT),
    -- Explicit groups: label + the entries that belong to it.
    Folder("Nefarian", ICON_BOSS, {
        Group("Tier 2 Tokens", placeholderItems("Nefarian Token", 4)),
        Group("Weapons", placeholderItems("Nefarian Weapon", 3)),
        Group("Misc", placeholderItems("Nefarian Misc", 5)),
    }, LOOT),
}, {
    order = 60.3, -- level, with a fraction for progression order among same-level raids
    minLevel = 60,
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    instanceID = 469,
})

FL:AddToModule("raids", raid)
