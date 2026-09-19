---@type string, ForeverLoot
local appName, app = ...

local log = app.logger

-- Public API. Exposed as the global `ForeverLoot` so other addons can register modules;
-- the addon's own modules (modules/*) go through exactly the same calls.
--
--   ForeverLoot:RegisterModule({ id = "raids", name = "Raids", icon = ..., children = {...} })
--   ForeverLoot.RegisterCallback(owner, "OnModuleRegistered", function(_, id) ... end)
--
-- See docs/API.md for the full contract.

-- A browsable tree node. Folders have `children`; items have `itemID` (real) or
-- name/icon/quality (placeholder).
---@class ForeverLoot.Node
---@field name? string  # required for folders and placeholder items
---@field icon? string|number
---@field description? string
---@field children? ForeverLoot.Node[]  # folders only
---@field itemID? integer  # real items (display resolution not implemented yet)
---@field quality? Enum.ItemQuality  # placeholder items
---@field moduleID? string  # set on the root's module nodes

---@class ForeverLoot.ModuleDef
---@field id string  # unique key, e.g. "raids"; other addons should prefix theirs ("myaddon-raids")
---@field name string  # display name
---@field icon string|number  # texture path or fileID
---@field order? number  # sort position in the root list; lower first, default 100
---@field description? string  # shown in tooltips
---@field children? ForeverLoot.Node[]  # the module's top-level entries
---@field getChildren? fun(def: ForeverLoot.ModuleDef): ForeverLoot.Node[]  # lazy alternative to `children`, called once

---@class ForeverLoot.API
---@field RegisterCallback fun(target: table, event: string, method: string|function, ...)
---@field UnregisterCallback fun(target: table, event: string)
---@field UnregisterAllCallbacks fun(target: table)
---@field callbacks CallbackHandlerRegistry
local api = {}
api.API_VERSION = 1

app.api = api
-- Installs api.RegisterCallback/UnregisterCallback/UnregisterAllCallbacks; we fire via the registry.
api.callbacks = LibStub("CallbackHandler-1.0"):New(api)

-- The public global. `appName` is "ForeverLoot"; spelled out so tooling can see the definition.
ForeverLoot = api

----------------------------------------------------------------------------------------------------
-- Node constructors (optional sugar for module authors)
----------------------------------------------------------------------------------------------------

---@param name string
---@param icon string|number
---@param children ForeverLoot.Node[]
---@return ForeverLoot.Node
function api.Folder(name, icon, children)
    return { name = name, icon = icon, children = children }
end

-- A real item, resolved from the game's item database when displayed (not implemented yet).
---@param itemID integer
---@return ForeverLoot.Node
function api.Item(itemID)
    return { itemID = itemID }
end

-- A stand-in item with hard-coded display data; for prototyping before real item IDs exist.
---@param name string
---@param quality Enum.ItemQuality
---@param icon string|number
---@return ForeverLoot.Node
function api.PlaceholderItem(name, quality, icon)
    return { name = name, quality = quality, icon = icon }
end

-- Generates `count` placeholder items named "<prefix> Item N". Prototyping only.
---@param prefix string
---@param count integer
---@return ForeverLoot.Node[]
function api.PlaceholderItems(prefix, count)
    local qualities = { 2, 3, 3, 4, 4, 4, 5 }
    local icons = {
        "Interface\\Icons\\INV_Sword_39",
        "Interface\\Icons\\INV_Chest_Plate16",
        "Interface\\Icons\\INV_Helmet_25",
        "Interface\\Icons\\INV_Boots_Plate_08",
        "Interface\\Icons\\INV_Misc_Cape_18",
        "Interface\\Icons\\INV_Jewelry_Ring_36",
        "Interface\\Icons\\INV_Staff_13",
    }
    local list = {}
    for i = 1, count do
        local quality = qualities[(i - 1) % #qualities + 1]
        local icon = icons[(i - 1) % #icons + 1]
        list[i] = api.PlaceholderItem(("%s Item %d"):format(prefix, i), quality, icon)
    end
    return list
end

----------------------------------------------------------------------------------------------------
-- Module registry
----------------------------------------------------------------------------------------------------

---@type table<string, ForeverLoot.ModuleDef>
local modules = {}
---@type ForeverLoot.Node?
local cachedRoot = nil

local DEFAULT_ORDER = 100

---@param def any
---@return boolean ok, string? err
local function validate(def)
    if type(def) ~= "table" then
        return false, "module definition must be a table"
    end
    if type(def.id) ~= "string" or def.id == "" then
        return false, "field `id` must be a non-empty string"
    end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "field `name` must be a non-empty string"
    end
    if type(def.icon) ~= "string" and type(def.icon) ~= "number" then
        return false, "field `icon` must be a texture path or fileID"
    end
    if def.order ~= nil and type(def.order) ~= "number" then
        return false, "field `order` must be a number"
    end
    if def.children ~= nil and type(def.children) ~= "table" then
        return false, "field `children` must be a table"
    end
    if def.getChildren ~= nil and type(def.getChildren) ~= "function" then
        return false, "field `getChildren` must be a function"
    end
    if def.children == nil and def.getChildren == nil then
        return false, "one of `children` or `getChildren` is required"
    end
    return true
end

-- Registers a module. Re-registering an existing id replaces it (handy for /reload-free dev).
---@param def ForeverLoot.ModuleDef
---@return boolean ok
function api:RegisterModule(def)
    local ok, err = validate(def)
    if not ok then
        log:error("RegisterModule: %s", err)
        return false
    end

    local replaced = modules[def.id] ~= nil
    modules[def.id] = def
    cachedRoot = nil

    log:debug("Module %s: %s", replaced and "replaced" or "registered", def.id)
    self.callbacks:Fire("OnModuleRegistered", def.id, replaced)
    self.callbacks:Fire("OnModulesChanged")
    return true
end

---@param id string
---@return boolean removed
function api:UnregisterModule(id)
    if not modules[id] then
        return false
    end
    modules[id] = nil
    cachedRoot = nil
    self.callbacks:Fire("OnModuleUnregistered", id)
    self.callbacks:Fire("OnModulesChanged")
    return true
end

---@param id string
---@return ForeverLoot.ModuleDef?
function api:GetModule(id)
    return modules[id]
end

-- Module definitions sorted by `order`, then name.
---@return ForeverLoot.ModuleDef[]
function api:GetModules()
    local list = {}
    for _, def in pairs(modules) do
        list[#list + 1] = def
    end
    table.sort(list, function(a, b)
        local oa, ob = a.order or DEFAULT_ORDER, b.order or DEFAULT_ORDER
        if oa ~= ob then
            return oa < ob
        end
        return a.name < b.name
    end)
    return list
end

---@param def ForeverLoot.ModuleDef
---@return ForeverLoot.Node[]
local function resolveChildren(def)
    if def.children == nil and def.getChildren then
        local ok, result = pcall(def.getChildren, def)
        if ok and type(result) == "table" then
            def.children = result
        else
            log:error("Module %s: getChildren failed: %s", def.id, tostring(result))
            def.children = {}
        end
    end
    return def.children or {}
end

-- The virtual root node the main window browses: one child per registered module.
-- Rebuilt lazily whenever the module set changes.
---@return ForeverLoot.Node
function api:GetRootNode()
    if cachedRoot then
        return cachedRoot
    end
    local children = {}
    for i, def in ipairs(self:GetModules()) do
        children[i] = {
            name = def.name,
            icon = def.icon,
            description = def.description,
            children = resolveChildren(def),
            moduleID = def.id,
        }
    end
    cachedRoot = { name = appName, icon = "Interface\\Icons\\INV_Misc_Bag_10", children = children }
    return cachedRoot
end
