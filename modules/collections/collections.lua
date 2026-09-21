-- Built-in module: Collections. One tile per collection (mounts, companions, ...), each
-- listing the items that belong to it and where they come from. The collections are curated
-- lists in .contribute/collections/*.json; this module holds no data of its own.
local FL = ForeverLoot

FL:RegisterModule({
    id = "collections",
    name = "Collections",
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    order = 50,
    description = "Mounts, companions and other collectibles.",
    display = "tiles",
    getChildren = function()
        return FL.ListFolders("collections")
    end,
})
