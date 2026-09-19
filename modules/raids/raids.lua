-- Built-in module: Raids. Registers through the same public API third-party addons use.
-- Data is PLACEHOLDER until real loot tables exist; use ForeverLoot.Item(itemID) for real items.
local FL = ForeverLoot
local Folder, Header, Group, Item, Spell, Custom, placeholderItems =
    FL.Folder, FL.Header, FL.Group, FL.Item, FL.Spell, FL.Custom, FL.PlaceholderItems

-- Loot table split into sections, to exercise page headers inside a list.
local function sectionedLoot(prefix)
    local list = { Header("Weapons") }
    for _, item in ipairs(placeholderItems(prefix .. " Weapon", 5)) do
        list[#list + 1] = item
    end
    list[#list + 1] = Header("Armor")
    for _, item in ipairs(placeholderItems(prefix .. " Armor", 9)) do
        list[#list + 1] = item
    end
    list[#list + 1] = Header("Trinkets")
    for _, item in ipairs(placeholderItems(prefix .. " Trinket", 3)) do
        list[#list + 1] = item
    end
    return list
end

local ICON_RAID = "Interface\\Icons\\Achievement_Boss_Ragnaros"
local LOOT = { columns = 2 } -- boss loot tables are shown in two columns
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"

FL:RegisterModule({
    id = "raids",
    name = "Raids",
    icon = ICON_RAID,
    order = 10,
    description = "Loot tables for raid instances.",
    children = {
        Folder("Molten Core", ICON_RAID, {
            Folder("Lucifron", ICON_BOSS, placeholderItems("Lucifron", 9), LOOT),
            -- Auto-grouped: placeholder entries bucket by `category`, real items by equipment slot.
            Folder("Magmadar", ICON_BOSS, placeholderItems("Magmadar", 12), { columns = 2, groupBy = "auto" }),
            Folder("Ragnaros", ICON_BOSS, sectionedLoot("Ragnaros"), LOOT),
        }),
        Folder("Blackwing Lair", ICON_RAID, {
            Folder("Razorgore", ICON_BOSS, placeholderItems("Razorgore", 8), LOOT),
            -- Explicit groups: label + the entries that belong to it.
            Folder("Nefarian", ICON_BOSS, {
                Group("Tier 2 Tokens", placeholderItems("Nefarian Token", 4)),
                Group("Weapons", placeholderItems("Nefarian Weapon", 3)),
                Group("Misc", placeholderItems("Nefarian Misc", 5)),
            }, LOOT),
        }),
        Folder("Onyxia's Lair", ICON_RAID, {
            -- Real items and spells resolve from game data; Custom shows any icon/title/description.
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
        }),
    },
})
