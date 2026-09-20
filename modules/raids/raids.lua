-- Built-in module: Raids. Only metadata lives here; each raid instance is its own file in this
-- folder and adds itself with ForeverLoot:AddToModule("raids", ...). Third-party addons can do
-- the same to add raids to this module.
local FL = ForeverLoot

FL:RegisterModule({
    id = "raids",
    name = "Raids",
    icon = "Interface\\Icons\\Achievement_Boss_Ragnaros",
    order = 10,
    description = "Loot tables for raid instances.",
    children = {},
    sortChildren = true, -- by each instance's `order`, then name; independent of file load order
})
