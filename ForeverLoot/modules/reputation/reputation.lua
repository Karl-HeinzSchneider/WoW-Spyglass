-- Built-in module: Reputation. One tile per faction, each listing its rewards grouped by the
-- standing they need. The factions are curated lists in .contribute/data/reputation/*.json; this
-- module holds no data of its own.
local FL = ForeverLoot

FL:RegisterModule({
    id = "reputation",
    name = "Reputation",
    icon = "Interface\\Icons\\Achievement_Reputation_01",
    order = 60,
    description = "Faction rewards by standing.",
    display = "tiles",
    getChildren = function()
        return FL.ListFolders("reputation")
    end,
})
