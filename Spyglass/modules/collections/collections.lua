-- Built-in module: Collections. Its Mounts tile comes from the curated collection data.
local SG = Spyglass

SG:RegisterModule({
    id = "collections",
    name = "Collections",
    icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
    order = 60,
    description = "Mounts.",
    display = "tiles",
    getChildren = function()
        return SG.ListFolders("collections")
    end,
})
