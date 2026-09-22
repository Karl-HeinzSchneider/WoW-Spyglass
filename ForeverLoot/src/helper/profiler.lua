---@type string, ForeverLoot
local _, app = ...

-- Flip to true to time the high-level calls below; each prints its duration to the chat.
local ENABLED = true

if not ENABLED then
    return
end

local log = app.logger

---@param label string
---@param start number
---@param ... any  # the wrapped function's results
---@return ...
local function finish(label, start, ...)
    log:chat("%s: %.2f ms", label, debugprofilestop() - start)
    return ...
end

-- Returns `fn` wrapped so that every call reports how long it took.
---@generic F: function
---@param label string
---@param fn F
---@return F
local function wrap(label, fn)
    return function(...)
        return finish(label, debugprofilestop(), fn(...))
    end
end

-- Replaces the named functions of `tbl` with timed versions. Frames copy mixin functions when
-- they are created, so this file is loaded after the mixins and before the XML that creates
-- the frames (see the TOC).
---@param name string  # label prefix
---@param tbl table
---@param ... string  # function names
local function wrapAll(name, tbl, ...)
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        tbl[key] = wrap(name .. ":" .. key, tbl[key])
    end
end

wrapAll("Query", app.query, "Run")
wrapAll("View", app.ui.ViewMixin, "Navigate", "Refresh", "Render", "OnPageChanged", "OnEvent")
wrapAll("MainWindow", app.ui.MainWindowMixin, "OpenView", "Toggle", "RefreshViews")
