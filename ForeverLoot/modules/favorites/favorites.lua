-- Built-in module: Favorites. The items the user marked with alt-click (FL.Favorites), in one
-- list that the info panel groups by where each item comes from (an instance, a profession or a
-- list), by the kind of content (dungeons, raids, crafting, ...) or by item type, with a count per
-- kind of content as an overview. This module holds no data of its own.
local FL = ForeverLoot
local Data = FL.Data

local ICON = "Interface\\Icons\\Ability_Druid_Starfall"
local HINT = "Alt-click any item in the window to mark it as a favorite, and again to remove it. "
    .. "A favorite has a star on its icon and in its tooltip, and is listed here."

-- The kinds of content an item can come from, in list order; "other" = no known source.
local CONTENT = {
    { key = "dungeon", label = "Dungeons" },
    { key = "raid", label = "Raids" },
    { key = "crafted", label = "Crafted" },
    { key = "pvp", label = "PvP" },
    { key = "reputation", label = "Reputation" },
    { key = "collections", label = "Collections" },
    { key = "other", label = "No known source" },
}
local CONTENT_RANK, CONTENT_LABEL = {}, {}
for i, content in ipairs(CONTENT) do
    CONTENT_RANK[content.key] = i
    CONTENT_LABEL[content.key] = content.label
end

---@class ForeverLoot.FavoriteSource
---@field content string  # a CONTENT key
---@field key string  # the instance, profession or list
---@field label string

local NO_SOURCE = { content = "other", key = "other", label = CONTENT_LABEL.other }

-- What one source counts for: instance loot and quests by the instance (and its type), recipes
-- and crafting lists by the profession, the other lists by themselves.
---@param source ForeverLoot.ItemSource
---@return ForeverLoot.FavoriteSource?
local function describe(source)
    local kind, instanceID = source.kind, nil
    if kind == "boss" then
        local boss = Data:GetBoss(source.id --[[@as integer]])
        instanceID = boss and boss.instanceID
    elseif kind == "trash" then
        instanceID = source.id --[[@as integer]]
    elseif kind == "quest" then
        instanceID = source.instanceID
    elseif kind == "recipe" or kind == "crafting" then
        local list = kind == "crafting" and Data:GetList("crafting", source.id --[[@as string]])
        local skillLineID = source.skillLineID or (list and list.skillLineID)
        if skillLineID then
            local name = Data:GetName("skillLines", skillLineID) or (list and list.name)
            return { content = "crafted", key = "skill:" .. skillLineID, label = name or ("Skill #" .. skillLineID) }
        end
        return list and { content = "crafted", key = "crafting:" .. source.id, label = list.name } or nil
    elseif CONTENT_RANK[kind] then
        local list = Data:GetList(kind, source.id --[[@as string]])
        return list and { content = kind, key = kind .. ":" .. source.id, label = list.name } or nil
    end
    local instance = instanceID and Data:GetInstance(instanceID)
    if not instance then
        return nil
    end
    local content = (instance.type == "dungeon" or instance.type == "raid") and instance.type or "other"
    return { content = content, key = "instance:" .. instanceID, label = Data:GetInstanceName(instanceID) }
end

-- The source an item is filed under: the one of the earliest kind of content (a dungeon drop
-- before a recipe for it), the first of those. Cached until the data changes.
local primaryCache, cachedVersion = {}, nil

---@param itemID integer
---@return ForeverLoot.FavoriteSource
local function primarySource(itemID)
    if cachedVersion ~= Data:GetVersion() then
        primaryCache, cachedVersion = {}, Data:GetVersion()
    end
    local primary = primaryCache[itemID]
    if not primary then
        for _, source in ipairs(Data:GetItemSources(itemID)) do
            local described = describe(source)
            if described and (not primary or CONTENT_RANK[described.content] < CONTENT_RANK[primary.content]) then
                primary = described
            end
        end
        primary = primary or NO_SOURCE
        primaryCache[itemID] = primary
    end
    return primary
end

---@param node ForeverLoot.Node
---@return string?, string?
local function bySource(node)
    if node.itemID then
        local source = primarySource(node.itemID)
        return source.key, source.label
    end
end

---@param node ForeverLoot.Node
---@return string?, string?
local function byContent(node)
    if node.itemID then
        local content = primarySource(node.itemID).content
        return "content:" .. content, CONTENT_LABEL[content]
    end
end

-- The favorites in the order the groups should come in: by kind of content, then by source
-- name. Groups keep the order their first entry has, so this orders both groupings.
---@return ForeverLoot.Node[]
local function entries()
    local ids = FL.Favorites:GetAll()
    table.sort(ids, function(a, b)
        local sa, sb = primarySource(a), primarySource(b)
        if sa.content ~= sb.content then
            return CONTENT_RANK[sa.content] < CONTENT_RANK[sb.content]
        end
        if sa.label ~= sb.label then
            return sa.label < sb.label
        end
        return a < b
    end)
    local list = {}
    for i, itemID in ipairs(ids) do
        list[i] = FL.Item(itemID)
    end
    if #list == 0 then
        -- An explicit group, so no grouping files the hint under "Other".
        return {
            FL.Group("No favorites yet", {
                FL.Custom({ name = "Alt-click an item to add it", icon = ICON, description = HINT }),
            }),
        }
    end
    return list
end

-- The info panel: how to use it, the grouping, and how many favorites each kind of content has.
---@return ForeverLoot.PanelWidget[]
local function panel()
    local ids = FL.Favorites:GetAll()
    local widgets = {
        { text = HINT },
        { spacer = true },
        { row = "Favorites", value = #ids },
        {
            grouping = "Group by",
            options = {
                { label = "Source", groupBy = bySource },
                { label = "Content", groupBy = byContent },
                { label = "Item type", groupBy = "auto" },
            },
        },
    }
    if #ids > 0 then
        local counts = {}
        for _, itemID in ipairs(ids) do
            local content = primarySource(itemID).content
            counts[content] = (counts[content] or 0) + 1
        end
        widgets[#widgets + 1] = { header = "Overview" }
        for _, content in ipairs(CONTENT) do
            if counts[content.key] then
                widgets[#widgets + 1] = { row = content.label, value = counts[content.key] }
            end
        end
    end
    return widgets
end

FL:RegisterModule({
    id = "favorites",
    name = "Favorites",
    icon = ICON,
    order = 70,
    description = "The items you marked with alt-click.",
    columns = 2,
    groupBy = bySource,
    children = {},
    getEntries = entries,
    panel = panel,
})
