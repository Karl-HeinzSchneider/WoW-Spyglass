-- Built-in module: Crafting. One tile per profession, each listing its recipes grouped as the
-- trade skill window does, with the skill thresholds (orange/yellow/green/grey) and, in the
-- tooltip, reagents and tools. The professions are curated lists in
-- .contribute/data/crafting/*.json (one file per profession, naming its skill line); the
-- recipes come from the generated recipe database (ForeverLoot.Data.recipes) merged with the
-- list's own rows. This module holds no data of its own.
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
