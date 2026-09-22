-- Built-in module: PvP. One tile per reward source (a battleground's vendors, the honor
-- ranks), each listing its rewards grouped by the rank or standing they need. The sources
-- are curated lists in .contribute/data/pvp/*.json; this module holds no data of its own.
local FL = ForeverLoot

FL:RegisterModule({
    id = "pvp",
    name = "PvP",
    icon = "Interface\\Icons\\INV_BannerPVP_02",
    order = 50,
    description = "Honor and battleground rewards.",
    display = "tiles",
    getChildren = function()
        return FL.ListFolders("pvp")
    end,
})
