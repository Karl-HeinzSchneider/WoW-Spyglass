local SG = Spyglass
local ICON = "Interface\\Icons\\INV_Misc_Rune_07"
local VARIANTS = { { "best", "Best in Slot" }, { "low-effort", "Low Effort" } }

local classes = {
    { "DRUID", "Balance", "Feral Combat", "Restoration" },
    { "HUNTER", "Beast Mastery", "Marksmanship", "Survival" },
    { "MAGE", "Arcane", "Fire", "Frost" },
    { "PALADIN", "Holy", "Protection", "Retribution" },
    { "PRIEST", "Discipline", "Holy", "Shadow" },
    { "ROGUE", "Assassination", "Combat", "Subtlety" },
    { "SHAMAN", "Elemental", "Enhancement", "Restoration" },
    { "WARLOCK", "Affliction", "Demonology", "Destruction" },
    { "WARRIOR", "Arms", "Fury", "Protection" },
}

-- Each row pairs the left and right equipment columns.
local slots = {
    { "head", "Head", "hands", "Hands" },
    { "neck", "Neck", "waist", "Waist" },
    { "shoulders", "Shoulders", "legs", "Legs" },
    { "back", "Back", "feet", "Feet" },
    { "chest", "Chest", "ring1", "Ring 1" },
    { "wrists", "Wrists", "ring2", "Ring 2" },
    { "mainHand", "Main Hand", "trinket1", "Trinket 1" },
    { "offHand", "Off Hand", "trinket2", "Trinket 2" },
    { "ranged", "Ranged / Relic" },
}

-- Keyed by class token, specialization name, variant, then slot. Each variant is a full
-- loadout, so changing the Best in Slot list cannot silently change Low Effort.
local loadouts = {
    DRUID = {
        Restoration = {
            best = {
                head = 252561,
                neck = 18723,
                shoulders = 14139,
                back = 18510,
                chest = 12462,
                wrists = 13208,
                hands = 226784,
                waist = 14553,
                legs = 16694,
                feet = 226781,
                ring1 = 272407,
                ring2 = 16058,
                trinket1 = 272439,
                trinket2 = 18470,
                mainHand = 13360,
                offHand = 19312,
                ranged = 272429,
            },
            ["low-effort"] = {
                head = 260212,
                neck = 18723,
                shoulders = 14139,
                back = 272413,
                chest = 13346,
                wrists = 13208,
                hands = 12554,
                waist = 19047,
                legs = 16694,
                feet = 18507,
                ring1 = 272407,
                ring2 = 16058,
                trinket1 = 272439,
                trinket2 = 18470,
                mainHand = 13360,
                offHand = 15805,
                ranged = 272429,
            },
        },
    },
}

---@param gear table<string, integer>
---@return Spyglass.Node[]
local function gearRows(gear)
    local entries = {}
    for row, pair in ipairs(slots) do
        for i = 1, #pair, 2 do
            local itemID = gear[pair[i]]
            if itemID then
                entries[#entries + 1] = {
                    itemID = itemID,
                    gearSlot = pair[i + 1],
                    gearRow = row,
                    column = (i + 1) / 2,
                }
            end
        end
    end
    return entries
end

local children = {}
for _, class in ipairs(classes) do
    local token = class[1]
    local classID = token:lower()
    local className = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]
        or (token:sub(1, 1) .. classID:sub(2))
    -- Texture paths use the class token even on translated clients.
    local icon = "Interface\\Icons\\ClassIcon_" .. token:sub(1, 1) .. classID:sub(2)
    local specs = {}
    for i = 2, #class do
        local specName = class[i]
        local specID = specName:lower():gsub(" ", "-")
        local specGear = loadouts[token] and loadouts[token][specName]
        local variants = {}
        for _, variant in ipairs(VARIANTS) do
            local variantID, label = variant[1], variant[2]
            local gear = specGear and specGear[variantID]
            if gear then
                variants[#variants + 1] =
                    SG.Folder(label, icon, gearRows(gear), { display = "gear", meta = { listID = variantID } })
            end
        end
        if #variants == 0 then
            variants[1] = SG.Header("Gear recommendations pending")
        elseif #variants == 2 then
            for index, variant in ipairs(variants) do
                local other = variants[3 - index]
                variant.panel = {
                    { button = other.name, open = ("bis/%s/%s/%s"):format(classID, specID, other.meta.listID) },
                }
            end
        end
        specs[#specs + 1] = SG.Folder(specName, icon, variants, { meta = { listID = specID } })
    end
    children[#children + 1] = SG.Folder(className, icon, specs, { meta = { listID = classID } })
end

SG:RegisterModule({
    id = "bis",
    name = "Best in Slot",
    icon = ICON,
    order = 26,
    description = "Curated gear recommendations by class and specialization.",
    columns = 2,
    children = children,
})
