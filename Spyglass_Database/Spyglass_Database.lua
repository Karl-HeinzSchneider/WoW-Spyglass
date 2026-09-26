-- The Items module: the whole item database (Spyglass.Data, filled by the generated files
-- loaded before this one) as one flat, filterable list; the view shows a search box and a filter
-- dropdown on `query` modules. Uses only the public Spyglass API.
local SG = Spyglass

SG:RegisterModule({
    id = "items",
    name = "Items",
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    order = 1000, -- last: after the content modules and any third-party ones (default 100)
    spacerBefore = true,
    description = "Every known item, searchable and filterable.",
    query = true,
    columns = 2,
    children = {},
})

-- PLAYER_LOGIN is still behind the loading screen and every addon (the locale names too) has
-- loaded: build the query's sort order now instead of on the first click on Items.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    self:UnregisterEvent(event)
    SG.Query.Run(SG.Query.New())
end)
