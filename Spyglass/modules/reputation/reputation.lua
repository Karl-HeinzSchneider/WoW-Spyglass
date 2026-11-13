-- Built-in module: Reputation. Faction tiles grouped by their parent faction.
local SG = Spyglass

local function appendCategory(entries, name, folders)
    if #folders == 0 then
        return
    end
    table.sort(folders, function(a, b)
        local aName, bName = a.name:lower(), b.name:lower()
        if aName == bName then
            return a.meta.listID < b.meta.listID
        end
        return aName < bName
    end)
    entries[#entries + 1] = SG.Header(name)
    for _, folder in ipairs(folders) do
        entries[#entries + 1] = folder
    end
end

SG:RegisterModule({
    id = "reputation",
    name = "Reputation",
    icon = "Interface\\Icons\\Achievement_Reputation_01",
    order = 40,
    description = "Faction rewards by standing.",
    display = "tiles",
    getChildren = function()
        local categories, names, other = {}, {}, {}
        for _, folder in ipairs(SG.ListFolders("reputation")) do
            local list = SG.Data:GetList("reputation", folder.meta.listID)
            local name = list.factionCategory
            if name then
                if not categories[name] then
                    categories[name] = {}
                    names[#names + 1] = name
                end
                local category = categories[name]
                category[#category + 1] = folder
            else
                other[#other + 1] = folder
            end
        end

        table.sort(names)
        local entries = {}
        for _, name in ipairs(names) do
            appendCategory(entries, name, categories[name])
        end
        appendCategory(entries, "Other", other)
        return entries
    end,
})
