-- PvP's battleground and honor gear tiles, built from the curated reward lists.
local SG = Spyglass

SG:RegisterModule({
    id = "pvp",
    name = "PvP",
    icon = "Interface\\Icons\\INV_BannerPVP_02",
    order = 50,
    description = "Honor and battleground rewards.",
    display = "tiles",
    panel = { { factionDropdown = "Faction", field = "side" } },
    getChildren = function()
        local entries = { SG.Header("Battlegrounds") }
        local honorGear
        for _, folder in ipairs(SG.ListFolders("pvp")) do
            if folder.meta and folder.meta.listID == "honor_gear" then
                honorGear = folder
            else
                entries[#entries + 1] = folder
            end
        end
        if honorGear then
            entries[#entries + 1] = SG.Header("Honor Gear")
            for _, folder in ipairs(honorGear.children or {}) do
                folder.panel = honorGear.panel
                entries[#entries + 1] = folder
            end
        end
        return entries
    end,
})
