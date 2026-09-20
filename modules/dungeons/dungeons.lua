-- Built-in module: Dungeons. Everything comes from the item database (db/generated): one
-- folder per instance of type "dungeon", a folder per boss, the recorded drops inside.
-- Levels, icons and loot are curated in .contribute/dungeons/*.json.
local FL = ForeverLoot

FL:RegisterModule({
    id = "dungeons",
    name = "Dungeons",
    icon = "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster",
    order = 20,
    description = "Loot tables for 5-man dungeons.",
    getChildren = function()
        return FL.InstanceFolders("dungeon")
    end,
    -- By level (instances without a curated level range go last), then name.
    sortChildren = function(a, b)
        local la, lb = a.minLevel or 999, b.minLevel or 999
        if la ~= lb then
            return la < lb
        end
        return (a.name or "") < (b.name or "")
    end,
})
