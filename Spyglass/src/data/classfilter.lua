---@type string, Spyglass
local _, app = ...

-- Which classes can use which armor and weapons: the view's class filter button (footer) hides
-- or fades the items a class can't use. Only armor and weapons are ever filtered; everything
-- else (consumables, recipes, reagents, quest items, ...) is usable by every class.

local ARMOR = Enum.ItemClass.Armor
local WEAPON = Enum.ItemClass.Weapon
local A = Enum.ItemArmorSubclass
local W = Enum.ItemWeaponSubclass

-- The classes of this client, in the order the menu lists them.
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- Who can use each restricted subclass, by class file name. A subclass that is not listed here
-- is usable by every class: cloth, miscellaneous armor (rings, necks, trinkets, off-hand
-- items), cosmetic items, miscellaneous weapons and fishing poles.
---@type table<integer, table<integer, string[]>>
local USERS = {
    [ARMOR] = {
        [A.Leather] = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "SHAMAN", "DRUID" },
        [A.Mail] = { "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" },
        [A.Plate] = { "WARRIOR", "PALADIN" },
        [A.Shield] = { "WARRIOR", "PALADIN", "SHAMAN" },
        [A.Libram] = { "PALADIN" },
        [A.Idol] = { "DRUID" },
        [A.Totem] = { "SHAMAN" },
        [A.Sigil] = {},
        [A.Relic] = {},
    },
    [WEAPON] = {
        [W.Axe1H] = { "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" },
        [W.Axe2H] = { "WARRIOR", "PALADIN", "HUNTER", "SHAMAN" },
        [W.Bows] = { "WARRIOR", "HUNTER", "ROGUE" },
        [W.Guns] = { "WARRIOR", "HUNTER", "ROGUE" },
        [W.Crossbow] = { "WARRIOR", "HUNTER", "ROGUE" },
        [W.Thrown] = { "WARRIOR", "HUNTER", "ROGUE" },
        [W.Mace1H] = { "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "SHAMAN", "DRUID" },
        [W.Mace2H] = { "WARRIOR", "PALADIN", "SHAMAN", "DRUID" },
        [W.Sword1H] = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "MAGE", "WARLOCK" },
        [W.Sword2H] = { "WARRIOR", "PALADIN", "HUNTER" },
        [W.Polearm] = { "WARRIOR", "PALADIN", "HUNTER" },
        [W.Staff] = { "WARRIOR", "HUNTER", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" },
        [W.Unarmed] = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID" },
        [W.Dagger] = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" },
        [W.Wand] = { "PRIEST", "MAGE", "WARLOCK" },
        [W.Warglaive] = {},
        [W.Bearclaw] = {},
        [W.Catclaw] = {},
        [W.Obsolete3] = {},
    },
}

-- USERS turned around once at load, so a lookup is two table reads:
-- blocked[class][itemClassID][subclassID] = true for what the class can't use.
---@type table<string, table<integer, table<integer, true>>>
local blocked = {}
for _, class in ipairs(CLASSES) do
    local byItemClass = {}
    for itemClassID, subclasses in pairs(USERS) do
        local set = {}
        for subclassID, users in pairs(subclasses) do
            if not tContains(users, class) then
                set[subclassID] = true
            end
        end
        byItemClass[itemClassID] = set
    end
    blocked[class] = byItemClass
end

---@class Spyglass.ClassFilter
local ClassFilter = {}
app.classFilter = ClassFilter

-- The classes the filter knows, in menu order (class file names, "WARLOCK").
---@return string[]
function ClassFilter:GetClasses()
    return CLASSES
end

-- The class's localized name, "Warlock".
---@param class string
---@return string
function ClassFilter:GetName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return names and names[class] or (class:sub(1, 1) .. class:sub(2):lower())
end

-- The class's square icon (Interface\Icons\ClassIcon_Warlock).
---@param class string
---@return string
function ClassFilter:GetIcon(class)
    return "Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()
end

-- The class of the logged-in character, when the filter knows it; else the first one.
---@return string
function ClassFilter:GetPlayerClass()
    local _, class = UnitClass("player")
    return blocked[class] and class or CLASSES[1]
end

-- Can `class` use the item? Items whose kind isn't known yet (server-side items the client
-- hasn't fetched, without a DB row) count as usable until it is.
---@param class string
---@param itemID integer
---@return boolean
function ClassFilter:CanUse(class, itemID)
    local byItemClass = blocked[class]
    if not byItemClass then
        return true
    end
    local itemClassID, subclassID = app.itemKind(itemID)
    local set = itemClassID and byItemClass[itemClassID]
    return not (set and set[subclassID])
end
