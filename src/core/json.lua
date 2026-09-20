---@type string, ForeverLoot
local _, app = ...

-- Minimal JSON encoder for `/fl export`; there is nothing to decode in-game.
-- Every table becomes an object whose keys are written as strings in sorted order (numbers
-- numerically), so the output is stable. There are no arrays: a table keyed by item ids that
-- happen to run 1..n must not turn into a list with the ids lost, so nothing is guessed.

---@class ForeverLoot.JSON
local json = {}
app.json = json

local ESCAPES = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

---@param s string
---@return string
local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
end

---@param a string|number
---@param b string|number
---@return boolean
local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
        return ta == "number" -- numeric keys first
    end
    return a < b
end

local encode

---@param t table
---@param indent string
---@return string
local function encodeTable(t, indent)
    local inner = indent .. "  "
    local parts = {}
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    if #keys == 0 then
        return "{}"
    end
    table.sort(keys, keyLess)
    for i, k in ipairs(keys) do
        parts[i] = inner .. encodeString(tostring(k)) .. ": " .. encode(t[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

---@param value any
---@param indent string
---@return string
function encode(value, indent)
    local kind = type(value)
    if kind == "table" then
        return encodeTable(value, indent)
    elseif kind == "string" then
        return encodeString(value)
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        elseif value == math.floor(value) then
            return ("%d"):format(value)
        end
        return ("%.14g"):format(value)
    elseif kind == "boolean" then
        return tostring(value)
    end
    return "null"
end

-- Pretty-printed JSON text for a plain data table (no functions, no cycles).
---@param value any
---@return string
function json.encode(value)
    return encode(value, "")
end
