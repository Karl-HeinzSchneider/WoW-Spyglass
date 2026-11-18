-- Built-in module: Collections. Its tiles come from the curated collection data.
local SG = Spyglass

SG:RegisterModule({
    id = "collections",
    name = "Collections",
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    order = 60,
    description = "Mounts, toys, and vendor rewards.",
    display = "tiles",
    getChildren = function()
        return SG.ListFolders("collections")
    end,
})
