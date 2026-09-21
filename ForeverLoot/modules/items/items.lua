-- Built-in module: Items. The whole item database (ForeverLoot.Data) as one flat, filterable
-- list: the view shows a search box and a filter dropdown on `query` modules. Nothing is
-- hard-coded here; the data comes from the generated files under db/.
local FL = ForeverLoot

FL:RegisterModule({
    id = "items",
    name = "Items",
    icon = "Interface\\Icons\\INV_Misc_Bag_10",
    order = 5,
    description = "Every known item, searchable and filterable.",
    query = true,
    columns = 2,
    children = {},
})
