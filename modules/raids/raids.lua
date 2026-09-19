-- Built-in module: Raids. Registers through the same public API third-party addons use.
-- Data is PLACEHOLDER until real loot tables exist; use ForeverLoot.Item(itemID) for real items.
local FL = ForeverLoot
local Folder, Header, placeholderItems = FL.Folder, FL.Header, FL.PlaceholderItems

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
            Folder("Magmadar", ICON_BOSS, placeholderItems("Magmadar", 12), LOOT),
            Folder("Ragnaros", ICON_BOSS, sectionedLoot("Ragnaros"), LOOT),
        }),
        Folder("Blackwing Lair", ICON_RAID, {
            Folder("Razorgore", ICON_BOSS, placeholderItems("Razorgore", 8), LOOT),
            Folder("Nefarian", ICON_BOSS, placeholderItems("Nefarian", 18), LOOT),
        }),
        Folder("Onyxia's Lair", ICON_RAID, {
            Folder("Onyxia", ICON_BOSS, placeholderItems("Onyxia", 14), LOOT),
        }),
    },
})
