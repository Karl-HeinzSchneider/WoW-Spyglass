-- Built-in module: Dungeons. Only metadata lives here; each dungeon is its own file in this
-- folder and adds itself with ForeverLoot:AddToModule("dungeons", ...). Third-party addons can
-- do the same to add dungeons to this module.
local FL = ForeverLoot

FL:RegisterModule({
    id = "dungeons",
    name = "Dungeons",
    icon = "Interface\\Icons\\Achievement_Dungeon_Deadmines",
    order = 20,
    description = "Loot tables for 5-man dungeons.",
    children = {},
    expansionID = 0, -- LE_EXPANSION_CLASSIC
    -- Custom sort: by minimum level, then name. (`true` would sort by `order`, then name.)
    sortChildren = function(a, b)
        local la, lb = a.minLevel or 0, b.minLevel or 0
        if la ~= lb then
            return la < lb
        end
        return (a.name or "") < (b.name or "")
    end,
})
