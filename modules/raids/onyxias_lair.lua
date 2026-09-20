-- Raid: Onyxia's Lair. Uses real item/spell IDs plus a custom entry, as a showcase of entry kinds.
local FL = ForeverLoot
local Folder, Group, Item, Spell, Custom = FL.Folder, FL.Group, FL.Item, FL.Spell, FL.Custom

local ICON = "Interface\\Icons\\Achievement_Boss_Ragnaros"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local LOOT = { columns = 2 }

local raid = Folder("Onyxia's Lair", ICON, {
    Folder("Onyxia", ICON_BOSS, {
        Group("Real items"),
        Item(18422), -- Head of Onyxia (Horde)
        Item(18423), -- Head of Onyxia (Alliance)
        Item(17068), -- Deathbringer
        Item(18705), -- Mature Black Dragon Sinew
        Group("Spells"),
        Spell(22888), -- Rallying Cry of the Dragonslayer
        Group("Other"),
        Custom({
            name = "Onyxia's Lair attunement",
            icon = "Interface\\Icons\\INV_Misc_Key_13",
            description = "Drakefire Amulet quest chain",
            tooltip = { "Starts at Warlord Goretooth / Haleh.", "Required to enter the lair." },
            onClick = function(node)
                FL.Log("Clicked %s", node.name)
            end,
        }),
    }, LOOT),
}, {
    order = 60.1, -- level, with a fraction for progression order among same-level raids
    minLevel = 60,
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    instanceID = 249,
})

FL:AddToModule("raids", raid)
