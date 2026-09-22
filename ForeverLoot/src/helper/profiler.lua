---@type string, ForeverLoot
local _, app = ...

-- Flip to true to time the high-level calls below; each prints its duration to the chat.
local ENABLED = true

if not ENABLED then
    return
end

local log = app.logger

---@param label string
---@param minMs number
---@param start number
---@param ... any  # the wrapped function's results
---@return ...
local function finish(label, minMs, start, ...)
    local ms = debugprofilestop() - start
    if ms >= minMs then
        log:chat("%s: %.2f ms", label, ms)
    end
    return ...
end

-- Returns `fn` wrapped so that every call taking at least `minMs` reports how long it took.
---@generic F: function
---@param label string
---@param fn F
---@param minMs? number  # default 0: report every call
---@return F
local function wrap(label, fn, minMs)
    minMs = minMs or 0
    return function(...)
        return finish(label, minMs, debugprofilestop(), fn(...))
    end
end

-- Replaces the named functions of `tbl` with timed versions. Frames copy mixin functions when
-- they are created, so this file is loaded after the mixins and before the XML that creates
-- the frames (see the TOC).
---@param name string  # label prefix
---@param tbl table
---@param minMs number  # only calls at least this long are reported
---@param ... string  # function names
local function wrapAll(name, tbl, minMs, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        tbl[key] = wrap(name .. ":" .. key, tbl[key], minMs)
    end
end

wrapAll("Query", app.query, 0, "Run")
wrapAll("View", app.ui.ViewMixin, 0, "Navigate", "Refresh", "Render", "OnPageChanged")
-- GET_ITEM_INFO_RECEIVED fires for every item the client fetches, for every view; nearly all
-- of those calls return at once.
wrapAll("View", app.ui.ViewMixin, 0.5, "OnEvent")
wrapAll("MainWindow", app.ui.MainWindowMixin, 0, "OpenView", "Toggle", "RefreshViews")
