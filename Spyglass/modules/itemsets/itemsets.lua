local SG = Spyglass
local Data = SG.Data
local icon = "Interface\\Icons\\INV_Chest_Plate04"

-- The original dungeon sets and their quest upgrades, verified against the Forever item scan.
-- Each set is { set ID, representative item ID, English fallback name }.
local pairsByClass = {
    { "DRUID", { 185, 16706, "Wildheart Raiment" }, { 513, 22113, "Feralheart Raiment" } },
    { "HUNTER", { 186, 16674, "Beaststalker Armor" }, { 515, 22060, "Beastmaster Armor" } },
    { "MAGE", { 181, 16688, "Magister's Regalia" }, { 517, 22069, "Sorcerer's Regalia" } },
    { "PALADIN", { 188, 16726, "Lightforge Armor" }, { 516, 22089, "Soulforge Armor" } },
    { "PRIEST", { 182, 16690, "Devout Raiment" }, { 514, 22083, "Vestments of the Virtuous" } },
    { "ROGUE", { 184, 16721, "Shadowcraft Armor" }, { 512, 22009, "Darkmantle Armor" } },
    { "SHAMAN", { 187, 16666, "The Elements" }, { 519, 22102, "The Five Thunders" } },
    { "WARLOCK", { 183, 16700, "Dreadmist Raiment" }, { 518, 22075, "Deathmist Raiment" } },
    { "WARRIOR", { 189, 16730, "Battlegear of Valor" }, { 511, 21997, "Battlegear of Heroism" } },
}

local function setRow(setID, itemID, fallbackName, classIcon, description, quality)
    local name = Data:GetSetName(setID)
    if name == ("Set #%d"):format(setID) then
        name = fallbackName
    end
    return SG.Custom({
        name = name,
        icon = classIcon,
        description = description,
        quality = quality,
        setItemID = itemID,
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
        for _, pair in ipairs(pairsByClass) do
            local class, base, upgrade = pair[1], pair[2], pair[3]
            local classSuffix = class:sub(1, 1) .. class:sub(2):lower()
            local classIcon = "Interface\\Icons\\ClassIcon_" .. classSuffix
            local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or classSuffix
            rows[#rows + 1] = setRow(base[1], base[2], base[3], classIcon, className .. " · Tier 0", Enum.ItemQuality.Rare)
            rows[#rows + 1] =
                setRow(upgrade[1], upgrade[2], upgrade[3], classIcon, className .. " · Tier 0.5", Enum.ItemQuality.Epic)
        end
        local dungeonSets = SG.Folder("Tier 0/0.5", icon, rows, {
            columns = 2,
            meta = { listID = "tier-0" },
        })
        return { dungeonSets }
    end,
})
