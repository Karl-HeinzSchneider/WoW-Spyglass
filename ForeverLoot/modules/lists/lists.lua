-- Built-in module: Lists. One tile per list of the user's (FL.Lists: Favorites first, then the
-- lists they made), then "New list" and "Import list". A list opens as its items, which the info
-- panel groups by where each item comes from (an instance, a profession or a list), by the kind
-- of content (dungeons, raids, crafting, ...) or by item type, with a count per kind of content
-- as an overview; its buttons make it the active list (the one alt-click adds to), edit, export,
-- import into or delete it. This module holds no data of its own.
local FL = ForeverLoot
local Data = FL.Data
local Lists = FL.Lists

local ICON = "Interface\\Icons\\Ability_Druid_Starfall"
local NEW_ICON = "Interface\\GuildBankFrame\\UI-GuildBankFrame-NewTab"
local IMPORT_ICON = "Interface\\Icons\\INV_Letter_15"
local HINT = "Lists of items you pick: a BiS list, a farm list, a shopping list, ... Alt-click an "
    .. "item anywhere in the window to add it to the active list, and again to remove it. An "
    .. "item on a list shows the list's marker on its icon and in its tooltip (Favorites: a star)."

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

---@param id string
---@return boolean
local function isActive(id)
    return Lists:GetActive() == id
end

-- A list's items in the order the groups should come in: by kind of content, then by source
-- name. Groups keep the order their first entry has, so this orders both groupings.
---@param id string
---@return ForeverLoot.Node[]
local function entries(id)
    if not Lists:Get(id) then
        return { FL.Custom({ name = "This list was deleted", icon = ICON }) }
    end
    local ids = Lists:GetItems(id)
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
        local how = isActive(id) and "Alt-click an item to add it"
            or "Make this list active, then alt-click items to add them"
        return { FL.Group("Nothing here yet", { FL.Custom({ name = how, icon = ICON }) }) }
    end
    return list
end

-- A list's info panel: whether alt-click adds to it, its item count and grouping (these first,
-- so the grouping keeps its place and its picked option), how many items each kind of content
-- has, and the buttons that manage it.
---@param id string
---@return ForeverLoot.PanelWidget[]
local function listPanel(id)
    if not Lists:Get(id) then
        return { { text = "This list was deleted." } }
    end
    local active = Lists:Get(Lists:GetActive()) --[[@as ForeverLoot.ItemList]]
    local ids = Lists:GetItems(id)
    local widgets = {
        {
            text = isActive(id)
                    and "This is the active list: alt-click an item anywhere in the window to add it here, and again to remove it."
                or ("Alt-click adds items to the active list, %s. Make this list active to add them here instead."):format(
                    active.name
                ),
        },
        { spacer = true },
        { row = "Items", value = #ids },
        {
            grouping = "Group by",
            options = {
                { label = "Source", groupBy = bySource },
                { label = "Content", groupBy = byContent },
                { label = "Item type", groupBy = "auto" },
            },
        },
    }
    if not isActive(id) then
        widgets[#widgets + 1] = {
            button = "Make active",
            onClick = function()
                Lists:SetActive(id)
            end,
        }
    end
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
    widgets[#widgets + 1] = { header = "Manage" }
    local canChange = id ~= Lists.FAVORITES
    if canChange then
        widgets[#widgets + 1] = {
            button = "Edit",
            onClick = function()
                Lists:OpenEditDialog(id)
            end,
        }
    end
    widgets[#widgets + 1] = {
        button = "Export",
        onClick = function()
            Lists:OpenExportDialog(id)
        end,
    }
    widgets[#widgets + 1] = {
        button = "Import into this list",
        onClick = function()
            Lists:OpenImportDialog(id)
        end,
    }
    if canChange then
        widgets[#widgets + 1] = {
            button = "Delete",
            onClick = function()
                Lists:OpenDeleteDialog(id)
            end,
        }
    end
    return widgets
end

-- One tile per list, kept per id so a tab's open list (and its panel settings) stays the same
-- node while the list is renamed or its items change; the fields are brought up to date each
-- time the tiles are built.
---@type table<string, ForeverLoot.Node>
local tiles = {}

---@param id string
---@return ForeverLoot.Node
local function listTile(id)
    local tile = tiles[id]
    if not tile then
        tile = {
            columns = 2,
            groupBy = bySource,
            meta = { listID = id },
            getChildren = function()
                return entries(id)
            end,
            panel = function()
                return listPanel(id)
            end,
        }
        tiles[id] = tile
    end
    local list = Lists:Get(id) --[[@as ForeverLoot.ItemList]]
    local count = Lists:GetCount(id)
    tile.name = list.name
    tile.icon = list.marker and Lists:GetMarkerFile(list.marker) or ICON
    tile.info = count == 1 and "1 item" or ("%d items"):format(count)
    tile.infoRight = isActive(id) and "Active" or nil
    tile.description = isActive(id) and "The active list: alt-click adds items here." or nil
    return tile
end

---@return ForeverLoot.Node[]
local function rootEntries()
    local nodes = {}
    for _, id in ipairs(Lists:GetAll()) do
        nodes[#nodes + 1] = listTile(id)
    end
    nodes[#nodes + 1] = FL.Custom({
        name = "New list",
        icon = NEW_ICON,
        description = "Make a new list of items.",
        onClick = function()
            Lists:OpenCreateDialog()
        end,
    })
    nodes[#nodes + 1] = FL.Custom({
        name = "Import list",
        icon = IMPORT_ICON,
        description = "Paste a list someone exported, or any text with item links or ids.",
        onClick = function()
            Lists:OpenImportDialog()
        end,
    })
    return nodes
end

-- The panel over the tiles: what lists are for, which one is active, and the same two actions
-- as the last two tiles.
---@return ForeverLoot.PanelWidget[]
local function rootPanel()
    local active = Lists:Get(Lists:GetActive()) --[[@as ForeverLoot.ItemList]]
    return {
        { text = HINT },
        { spacer = true },
        { row = "Active list", value = active.name },
        { row = "Lists", value = #Lists:GetAll() },
        {
            button = "New list",
            onClick = function()
                Lists:OpenCreateDialog()
            end,
        },
        {
            button = "Import list",
            onClick = function()
                Lists:OpenImportDialog()
            end,
        },
    }
end

FL:RegisterModule({
    id = "lists",
    name = "Lists",
    icon = ICON,
    order = 70,
    description = "Favorites and your own item lists.",
    display = "tiles",
    children = {},
    getEntries = rootEntries,
    panel = rootPanel,
})
