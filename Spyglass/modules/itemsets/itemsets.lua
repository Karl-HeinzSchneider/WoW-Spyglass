local SG = Spyglass
local Data = SG.Data
local icon = "Interface\\Icons\\INV_Chest_Plate04"

-- Class, dungeon set, upgrade set, then the Forever quest reward bundles (wrist item first).
-- Upgrade variants share a set ID, so their pieces are listed separately.
local setsByClass = {
    {
        "DRUID",
        { 185, 16706, "Wildheart Raiment" },
        { 1667, "Feralheart Raiment" },
        { 226775, 226772, 226773, 226774, 226776, 226777, 226778, 226779 },
        { 226782, 226780, 226781, 226783, 226784, 226785, 226786, 226787 },
        { 226788, 226789, 226790, 226791, 226792, 226793, 226794, 226795 },
        { 226796, 226797, 226798, 226799, 226801, 226802, 226803, 226804 },
    },
    {
        "HUNTER",
        { 186, 16674, "Beaststalker Armor" },
        { 1669, "Beastmaster Armor" },
        { 226885, 226881, 226882, 226883, 226884, 226886, 226887, 226888 },
    },
    {
        "MAGE",
        { 181, 16688, "Magister's Regalia" },
        { 1671, "Sorcerer's Regalia" },
        { 226929, 226930, 226931, 226932, 226933, 226934, 226935, 226936 },
    },
    {
        "PALADIN",
        { 188, 16726, "Lightforge Armor" },
        { 1673, "Soulforge Armor" },
        { 226970, 226969, 226971, 226972, 226973, 226974, 226975, 226976 },
        { 226977, 226978, 226979, 226980, 226981, 226982, 226983, 226984 },
        { 226985, 226986, 226987, 226988, 226989, 226990, 226991, 226992 },
    },
    {
        "PRIEST",
        { 182, 16690, "Devout Raiment" },
        { 1675, "Vestments of the Virtuous" },
        { 226949, 226945, 226946, 226947, 226948, 226950, 226951, 226952 },
        { 226953, 226954, 226955, 226956, 226957, 226958, 226959, 226960 },
    },
    {
        "ROGUE",
        { 184, 16721, "Shadowcraft Armor" },
        { 1676, "Darkmantle Armor" },
        { 226830, 226825, 226826, 226827, 226828, 226829, 226831, 226832 },
    },
    {
        "SHAMAN",
        { 187, 16666, "The Elements" },
        { 1679, "The Five Thunders" },
        { 227001, 227002, 227003, 227004, 227005, 227006, 227007, 227008 },
        { 227009, 227010, 227011, 227012, 227013, 227014, 227015, 227016 },
        { 227017, 227018, 227019, 227020, 227021, 227022, 227023, 227024 },
    },
    {
        "WARLOCK",
        { 183, 16700, "Dreadmist Raiment" },
        { 1681, "Deathmist Raiment" },
        { 226907, 226905, 226906, 226908, 226909, 226910, 226911, 226912 },
    },
    {
        "WARRIOR",
        { 189, 16730, "Battlegear of Valor" },
        { 1778, "Battlegear of Heroism" },
        { 226863, 226857, 226858, 226859, 226860, 226861, 226862, 226864 },
        { 226865, 226866, 226867, 226868, 226869, 226870, 226871, 226872 },
    },
}

local function setRow(setID, fallbackName, itemID, class, description, items)
    local name = Data:GetSetName(setID)
    if name == ("Set #%d"):format(setID) then
        name = fallbackName
    end
    return SG.Custom({
        name = name,
        icon = "Interface\\Icons\\ClassIcon_" .. class,
        description = description,
        quality = items and Enum.ItemQuality.Epic or Enum.ItemQuality.Rare,
        column = items and 2 or 1,
        setItemID = itemID,
        setItems = items,
        meta = { section = class },
    })
end

SG:RegisterModule({
    id = "itemsets",
    name = "Item Sets",
    icon = icon,
    order = 25,
    description = "Dungeon armor sets and their upgrades.",
    getChildren = function()
        local rows = {}
        for _, sets in ipairs(setsByClass) do
            local token, base, upgrade = sets[1], sets[2], sets[3]
            local class = token:sub(1, 1) .. token:sub(2):lower()
            local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or class
            rows[#rows + 1] = setRow(base[1], base[3], base[2], class, className .. " · Tier 0")
            for index = 4, #sets do
                local items = sets[index]
                local description = className .. " · Tier 0.5"
                if #sets > 4 then
                    local wristName, known = Data:GetItemName(items[1])
                    description = "Tier 0.5 · " .. (known and wristName or ("Variant %d"):format(index - 3))
                end
                rows[#rows + 1] = setRow(upgrade[1], upgrade[2], items[1], class, description, items)
            end
        end
        local dungeonSets = SG.Folder("Tier 0/0.5", icon, rows, {
            columns = 2,
            meta = { listID = "tier-0" },
        })
        dungeonSets.panel = { { classDropdown = "Class" } }
        return { dungeonSets }
    end,
})
