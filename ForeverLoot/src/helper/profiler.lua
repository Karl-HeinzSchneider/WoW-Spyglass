---@type string, ForeverLoot
local appName, app = ...

-- Flip to true to profile. Wrapping everything adds overhead to every call, so keep it off unless measuring.
local ENABLED = false

-- Optional hook into the NumyFunctionProfiler addon (loads before us). Does nothing when it is
-- not installed. Loaded last so every `app.*` module already exists; each sub-table of `app`
-- becomes one profiler module, wrapped one layer deep (e.g. app.data.GetItem, app.ui.mainWindow.Refresh).
if not ENABLED or not NumyFunctionProfiler then
    return
end

for name, module in pairs(app) do
    if type(module) == "table" and name ~= "db" then
        NumyFunctionProfiler:WrapModules(appName, name, module, 2)
    end
end
