-- Built-in module: Crafting. One tile per profession, each listing the items its recipes make,
-- grouped by the skill tier they need. The professions and their recipes are curated lists in
-- .contribute/data/crafting/*.json (one file per profession); this module holds no data of its own.
local FL = ForeverLoot

FL:RegisterModule({
    id = "crafting",
    name = "Crafting",
    icon = "Interface\\Icons\\Trade_Engineering",
    order = 30,
    description = "Items made by professions.",
    display = "tiles",
    getChildren = function()
        return FL.ListFolders("crafting")
    end,
})
