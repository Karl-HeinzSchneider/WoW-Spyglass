---@type string, ForeverLoot
local _, app = ...

-- TEMPORARY placeholder data so the main window has something to show.
-- Replace with the real module/collection system once the data layer exists.
-- A node is either a folder ({ name, icon, children }) or an item ({ name, icon, quality }).

---@class ForeverLoot.Node
---@field name string
---@field icon string|number
---@field quality? Enum.ItemQuality  # leaf items only
---@field children? ForeverLoot.Node[]  # folders only

local ICON = {
    raid = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    dungeon = "Interface\\Icons\\Achievement_Dungeon_Deadmines",
    boss = "Interface\\Icons\\Ability_Creature_Cursed_02",
}

---@param name string
---@param quality Enum.ItemQuality
---@param icon string
---@return ForeverLoot.Node
local function item(name, quality, icon)
    return { name = name, quality = quality, icon = icon }
end

---@param name string
---@param icon string
---@param children ForeverLoot.Node[]
---@return ForeverLoot.Node
local function folder(name, icon, children)
    return { name = name, icon = icon, children = children }
end

-- Generates enough items to overflow a page so paging is visible.
---@param prefix string
---@param count integer
---@return ForeverLoot.Node[]
local function items(prefix, count)
    local qualities = { 2, 3, 3, 4, 4, 4, 5 }
    local icons = {
        "Interface\\Icons\\INV_Sword_39",
        "Interface\\Icons\\INV_Chest_Plate16",
        "Interface\\Icons\\INV_Helmet_25",
        "Interface\\Icons\\INV_Boots_Plate_08",
        "Interface\\Icons\\INV_Misc_Cape_18",
        "Interface\\Icons\\INV_Jewelry_Ring_36",
        "Interface\\Icons\\INV_Staff_13",
    }
    local list = {}
    for i = 1, count do
        local q = qualities[(i - 1) % #qualities + 1]
        local icon = icons[(i - 1) % #icons + 1]
        list[i] = item(("%s Item %d"):format(prefix, i), q, icon)
    end
    return list
end

app.ui = app.ui or {}

app.ui.mockTree = folder("ForeverLoot", "Interface\\Icons\\INV_Misc_Bag_10", {
    folder("Raids", ICON.raid, {
        folder("Molten Core", ICON.raid, {
            folder("Lucifron", ICON.boss, items("Lucifron", 9)),
            folder("Magmadar", ICON.boss, items("Magmadar", 12)),
            folder("Ragnaros", ICON.boss, items("Ragnaros", 21)),
        }),
        folder("Blackwing Lair", ICON.raid, {
            folder("Razorgore", ICON.boss, items("Razorgore", 8)),
            folder("Nefarian", ICON.boss, items("Nefarian", 18)),
        }),
        folder("Onyxia's Lair", ICON.raid, {
            folder("Onyxia", ICON.boss, items("Onyxia", 14)),
        }),
    }),
    folder("Dungeons", ICON.dungeon, {
        folder("The Deadmines", ICON.dungeon, {
            folder("Edwin VanCleef", ICON.boss, items("VanCleef", 6)),
            folder("Mr. Smite", ICON.boss, items("Smite", 4)),
        }),
        folder("Scarlet Monastery", ICON.dungeon, {
            folder("Herod", ICON.boss, items("Herod", 5)),
            folder("High Inquisitor Whitemane", ICON.boss, items("Whitemane", 7)),
        }),
    }),
})
