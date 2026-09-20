-- Raid: Molten Core. PLACEHOLDER loot until real item IDs exist.
local FL = ForeverLoot
local Folder, Header, placeholderItems = FL.Folder, FL.Header, FL.PlaceholderItems

local ICON = "Interface\\Icons\\Achievement_Boss_Ragnaros"
local ICON_BOSS = "Interface\\Icons\\Ability_Creature_Cursed_02"
local LOOT = { columns = 2 }

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

local raid = Folder("Molten Core", ICON, {
    Folder("Lucifron", ICON_BOSS, placeholderItems("Lucifron", 9), LOOT),
    -- Auto-grouped: placeholder entries bucket by `category`, real items by equipment slot.
    Folder("Magmadar", ICON_BOSS, placeholderItems("Magmadar", 12), { columns = 2, groupBy = "auto" }),
    Folder("Ragnaros", ICON_BOSS, sectionedLoot("Ragnaros"), LOOT),
}, {
    order = 60.2, -- level, with a fraction for progression order among same-level raids
    minLevel = 60,
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    instanceID = 409,
})

FL:AddToModule("raids", raid)
