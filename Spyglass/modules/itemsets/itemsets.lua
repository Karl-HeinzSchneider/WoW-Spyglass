local SG = Spyglass
local Data = SG.Data
local icon = "Interface\\Icons\\INV_Chest_Plate04"

SG:RegisterModule({
    id = "itemsets",
    name = "Item Sets",
    icon = icon,
    order = 25,
    description = "Tier sets and other gear sets.",
    children = {},
    getEntries = function()
        local sets = {}
        for _, setID in ipairs(Data:GetSetIDs()) do
            local items = {}
            for _, itemID in ipairs(Data:GetSetItems(setID)) do
                items[#items + 1] = SG.Item(itemID)
            end
            sets[#sets + 1] = SG.Folder(Data:GetSetName(setID), icon, items)
        end
        table.sort(sets, function(a, b)
            return a.name < b.name
        end)
        return sets
    end,
})
