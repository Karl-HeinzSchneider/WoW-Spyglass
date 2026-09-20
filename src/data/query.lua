---@type string, ForeverLoot
local _, app = ...

local Data = app.data
local Filters = app.filters
local ITEM = Data.ITEM

-- Queries over the item DB, public as `ForeverLoot.Query`. A query is a plain table with no
-- functions in it, so it can be stored in the profile (presets) or sent around:
--
--   { search = "defias", filters = { quality = { 3, 4 }, slot = { "INVTYPE_CHEST" }, itemLevel = "20-29" }, sort = "name" }
--
-- Values of one filter are OR-ed, different filters AND-ed, then the name search applies.

---@alias ForeverLoot.QuerySort "name"|"ilvl"|"quality"|"id"

---@class ForeverLoot.Query
---@field search? string  # case-insensitive substring of the item name; all digits = item id too
---@field filters? table<string, any>  # filterID -> value: array for "multi", scalar for "single"
---@field sort? ForeverLoot.QuerySort  # default "name"

---@class ForeverLoot.QueryAPI
local Query = {}
app.query = Query
app.api.Query = Query

---@return ForeverLoot.Query
function Query.New()
    return { search = "", filters = {}, sort = "name" }
end

-- Deep copy (values are plain data).
---@param q ForeverLoot.Query
---@return ForeverLoot.Query
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
---@param q ForeverLoot.Query
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
---@param q ForeverLoot.Query
---@return { def: ForeverLoot.FilterDef, values: (string|number)[] }[]
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

-- Union of an indexed filter's buckets for its selected values, or nil if it has no index.
---@param entry { def: ForeverLoot.FilterDef, values: (string|number)[] }
---@return integer[]?
local function candidateSet(entry)
    if not entry.def.index then
        return nil
    end
    if #entry.values == 1 then
        return Filters:GetBucket(entry.def.id, entry.values[1])
    end
    local seen, union = {}, {}
    for _, value in ipairs(entry.values) do
        for _, itemID in ipairs(Filters:GetBucket(entry.def.id, value) or {}) do
            if not seen[itemID] then
                seen[itemID] = true
                union[#union + 1] = itemID
            end
        end
    end
    table.sort(union)
    return union
end

---@param entry { def: ForeverLoot.FilterDef, values: (string|number)[] }
---@param itemID integer
---@param row ForeverLoot.ItemRow
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

local comparators = {}

function comparators.name(a, b)
    local na, nb = Data:GetSearchName(a), Data:GetSearchName(b)
    if na ~= nb then
        return na < nb
    end
    return a < b
end

function comparators.ilvl(a, b)
    local la, lb = Data:GetItemField(a, ITEM.ILVL) or 0, Data:GetItemField(b, ITEM.ILVL) or 0
    if la ~= lb then
        return la > lb
    end
    return comparators.name(a, b)
end

function comparators.quality(a, b)
    local qa, qb = Data:GetItemField(a, ITEM.QUALITY) or 0, Data:GetItemField(b, ITEM.QUALITY) or 0
    if qa ~= qb then
        return qa > qb
    end
    return comparators.name(a, b)
end

function comparators.id(a, b)
    return a < b
end

-- Runs the query: smallest indexed bucket (or all items) -> AND every filter -> name search
-- -> sort. Returns a new array of item ids.
---@param q ForeverLoot.Query
---@return integer[]
function Query.Run(q)
    local active = activeFilters(q)

    -- Start from the narrowest indexed filter; the others are checked per item.
    local candidates, sourceIndex = nil, nil
    for i, entry in ipairs(active) do
        local set = candidateSet(entry)
        if set and (not candidates or #set < #candidates) then
            candidates, sourceIndex = set, i
        end
    end
    candidates = candidates or Data:GetItemIDs()

    local search = (q.search or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local searchID = search ~= "" and tonumber(search:match("^%d+$")) or nil

    local results = {}
    for _, itemID in ipairs(candidates) do
        local row = Data:GetItem(itemID)
        local ok = row ~= nil
        for i, entry in ipairs(active) do
            if not ok then
                break
            end
            if i ~= sourceIndex then
                ok = matchesAny(entry, itemID, row)
            end
        end
        if ok and search ~= "" then
            ok = itemID == searchID or Data:GetSearchName(itemID):find(search, 1, true) ~= nil
        end
        if ok then
            results[#results + 1] = itemID
        end
    end

    table.sort(results, comparators[q.sort or "name"] or comparators.name)
    return results
end
