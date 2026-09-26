---@type string, Spyglass
local _, app = ...

local Data = app.data
local Filters = app.filters
local ITEM = Data.ITEM

-- Queries over the item DB, public as `Spyglass.Query`. A query is a plain table with no
-- functions in it, so it can be stored in the profile (presets) or sent around:
--
--   { search = "defias", filters = { quality = { 3, 4 }, slot = { "INVTYPE_CHEST" }, itemLevel = "20-29" }, sort = "name" }
--
-- Values of one filter are OR-ed, different filters AND-ed, then the name search applies.

---@alias Spyglass.QuerySort "name"|"ilvl"|"quality"|"id"

---@class Spyglass.Query
---@field search? string  # case-insensitive substring of the item name; all digits = item id too
---@field filters? table<string, any>  # filterID -> value: array for "multi", scalar for "single"
---@field sort? Spyglass.QuerySort  # default "name"

---@class Spyglass.QueryAPI
local Query = {}
app.query = Query
app.api.Query = Query

---@return Spyglass.Query
function Query.New()
    return { search = "", filters = {}, sort = "name" }
end

-- Deep copy (values are plain data).
---@param q Spyglass.Query
---@return Spyglass.Query
function Query.Copy(q)
    local filters = {}
    for id, value in pairs(q.filters or {}) do
        if type(value) == "table" then
            local list = {}
            for i, v in ipairs(value) do
                list[i] = v
            end
            filters[id] = list
        else
            filters[id] = value
        end
    end
    return { search = q.search or "", filters = filters, sort = q.sort or "name" }
end

-- True when a filter value selects nothing: nil, or an empty array.
---@param value any
---@return boolean
local function isEmptyValue(value)
    return value == nil or (type(value) == "table" and #value == 0)
end

-- True when the query would return every item.
---@param q Spyglass.Query
---@return boolean
function Query.IsEmpty(q)
    if q.search and q.search:match("%S") then
        return false
    end
    for _, value in pairs(q.filters or {}) do
        if not isEmptyValue(value) then
            return false
        end
    end
    return true
end

-- Filters that are set and still registered, as { def, values[] } pairs.
---@param q Spyglass.Query
---@return { def: Spyglass.FilterDef, values: (string|number)[] }[]
local function activeFilters(q)
    local active = {}
    for id, value in pairs(q.filters or {}) do
        local def = Filters:Get(id)
        if def and not isEmptyValue(value) then
            local values = value
            if type(values) ~= "table" then
                values = { values }
            end
            active[#active + 1] = { def = def, values = values }
        end
    end
    return active
end

-- Sort orders, built once per data version: `orders[sort]` = every item id in that order,
-- `ranks[sort][itemID]` = its position. Sorting 25k names on every query is what made the
-- Items list stall; with these, an unfiltered query walks the order and a filtered one sorts
-- its (smaller) result by rank, which compares two integers instead of two names.
---@type table<Spyglass.QuerySort, integer[]>
local orders = {}
---@type table<Spyglass.QuerySort, table<integer, integer>>
local ranks = {}
local ordersVersion = -1

---@return integer[]
local function copyItemIDs()
    local ids = {}
    for i, id in ipairs(Data:GetItemIDs()) do
        ids[i] = id
    end
    return ids
end

---@param ids integer[]
---@return table<integer, integer>
local function rankOf(ids)
    local rank = {}
    for i, id in ipairs(ids) do
        rank[id] = i
    end
    return rank
end

-- Item ids by a numeric row field, highest first, ties by name rank.
---@param field integer
---@return integer[]
local function sortedByField(field)
    local nameRank, items = ranks.name, Data.items
    local key = {}
    for id, row in pairs(items) do
        key[id] = row[field] or 0
    end
    local ids = copyItemIDs()
    table.sort(ids, function(a, b)
        local ka, kb = key[a], key[b]
        if ka ~= kb then
            return ka > kb
        end
        return nameRank[a] < nameRank[b]
    end)
    return ids
end

---@param sort Spyglass.QuerySort
---@return integer[] order, table<integer, integer> rank
local function sortOrder(sort)
    local v = Data:GetVersion()
    if ordersVersion ~= v then
        orders, ranks, ordersVersion = {}, {}, v
    end
    if not orders.name then
        local ids, names = copyItemIDs(), {}
        for _, id in ipairs(ids) do
            names[id] = Data:GetSearchName(id)
        end
        table.sort(ids, function(a, b)
            local na, nb = names[a], names[b]
            if na ~= nb then
                return na < nb
            end
            return a < b
        end)
        orders.name, ranks.name = ids, rankOf(ids)
    end
    if not orders[sort] then
        local ids
        if sort == "id" then
            ids = Data:GetItemIDs()
        else
            ids = sortedByField(sort == "ilvl" and ITEM.ILVL or ITEM.QUALITY)
        end
        orders[sort], ranks[sort] = ids, rankOf(ids)
    end
    return orders[sort], ranks[sort]
end

-- The items an indexed filter selects: the union of its buckets for the chosen values, as a
-- list and as a set. Cached per data version so re-running the same query (page size
-- changes, profile refreshes) doesn't rebuild it.
-- Keyed by the def table, so a re-registered filter gets fresh buckets.
---@type table<Spyglass.FilterDef, table<string, { list: integer[], set: table<integer, true> }>>
local unionCache = {}
local unionVersion = -1

---@param entry { def: Spyglass.FilterDef, values: (string|number)[] }
---@return { list: integer[], set: table<integer, true> }?
local function candidateSet(entry)
    local def = entry.def
    if not def.index then
        return nil
    end
    local v = Data:GetVersion()
    if unionVersion ~= v then
        unionCache, unionVersion = {}, v
    end
    local byValues = unionCache[def]
    if not byValues then
        byValues = {}
        unionCache[def] = byValues
    end
    local key = table.concat(entry.values, "|")
    local union = byValues[key]
    if not union then
        local list, set = {}, {}
        for _, value in ipairs(entry.values) do
            for _, itemID in ipairs(Filters:GetBucket(def.id, value) or {}) do
                if not set[itemID] then
                    set[itemID] = true
                    list[#list + 1] = itemID
                end
            end
        end
        union = { list = list, set = set }
        byValues[key] = union
    end
    return union
end

---@param entry { def: Spyglass.FilterDef, values: (string|number)[] }
---@param itemID integer
---@param row Spyglass.ItemRow
---@return boolean
local function matchesAny(entry, itemID, row)
    local match = entry.def.match
    for _, value in ipairs(entry.values) do
        if match(itemID, row, value) then
            return true
        end
    end
    return false
end

-- Below this share of the DB, a candidate list is walked and its matches sorted by rank;
-- above it, the full sort order is walked instead and the candidates only checked (no sort).
local WALK_ORDER_SHARE = 0.25

local SORTS = { name = true, ilvl = true, quality = true, id = true }

-- Runs the query: indexed filters through their buckets, the rest per item, then the name
-- search; the result comes out in `sort` order. Returns a new array of item ids.
---@param q Spyglass.Query
---@return integer[]
function Query.Run(q)
    local sort = SORTS[q.sort or "name"] and q.sort or "name"
    local order, rank = sortOrder(sort)

    -- Indexed filters become membership sets; the narrowest is the candidate list.
    local sets, checks = {}, {}
    local candidates, candidateSetOf = nil, nil
    for _, entry in ipairs(activeFilters(q)) do
        local union = candidateSet(entry)
        if union then
            sets[#sets + 1] = union.set
            if not candidates or #union.list < #candidates then
                candidates, candidateSetOf = union.list, union.set
            end
        else
            checks[#checks + 1] = entry
        end
    end

    local search = (q.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local searchID = search ~= "" and tonumber(search:match("^%d+$")) or nil
    local items = Data.items

    -- Walking the sort order needs no sort afterwards; a small candidate list is cheaper to
    -- walk and sort than 25k membership checks.
    local walkOrder = not candidates or #candidates > #order * WALK_ORDER_SHARE
    local source = walkOrder and order or candidates --[[@as integer[] ]]

    local results = {}
    for i = 1, #source do
        local itemID = source[i]
        local row = items[itemID]
        local ok = row ~= nil
        for j = 1, #sets do
            if not ok then
                break
            end
            local set = sets[j]
            if (walkOrder or set ~= candidateSetOf) and not set[itemID] then
                ok = false
            end
        end
        for j = 1, #checks do
            if not ok then
                break
            end
            ok = matchesAny(checks[j], itemID, row)
        end
        if ok and search ~= "" then
            ok = itemID == searchID or Data:GetSearchName(itemID):find(search, 1, true) ~= nil
        end
        if ok then
            results[#results + 1] = itemID
        end
    end

    if not walkOrder then
        table.sort(results, function(a, b)
            return rank[a] < rank[b]
        end)
    end
    return results
end
