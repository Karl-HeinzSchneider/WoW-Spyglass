---@type string, ForeverLoot
local appName, app = ...

local log = app.logger

---@class ForeverLoot.Addon : AceAddon, AceConsole-3.0, AceEvent-3.0
---@field db ForeverLoot.DB
local addon = {}
LibStub("AceAddon-3.0"):NewAddon(addon, appName, "AceConsole-3.0", "AceEvent-3.0")
app.addon = addon

-- Called once, after ADDON_LOADED for this addon: SavedVariables are available now.
function addon:OnInitialize()
    local db = LibStub("AceDB-3.0"):New("ForeverLootDB", app.dbDefaults, true) --[[@as ForeverLoot.DB]]
    self.db = db
    app.db = db

    db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

    self:RegisterChatCommand("fl", "OnSlashCommand")
    self:RegisterChatCommand("foreverloot", "OnSlashCommand")

    self:OnProfileRefresh()
    log:debug("Initialized (profile: %s)", db:GetCurrentProfile())
end

-- Called after OnInitialize and whenever the addon is re-enabled. Register events here.
function addon:OnEnable()
    log:debug("Enabled")
end

-- Ace unregisters events/timers/hooks automatically on disable.
function addon:OnDisable()
    log:debug("Disabled")
end

-- Re-apply everything that depends on profile settings. Modules opt in by defining OnProfileRefresh.
function addon:OnProfileRefresh()
    log:setLevel(self.db.profile.logLevel)
    if app.ui and app.ui.mainWindow then
        app.ui.mainWindow:RefreshViews()
    end
    for _, module in self:IterateModules() do
        if module.OnProfileRefresh then
            module:OnProfileRefresh()
        end
    end
end

---@param input string
function addon:OnSlashCommand(input)
    local cmd, a, b, c = self:GetArgs(input, 4)
    cmd = cmd and cmd:lower() or ""

    if cmd == "" or cmd == "show" then
        app.ui.mainWindow:Toggle()
    elseif cmd == "loglevel" then
        if a and log:setLevel(a) then
            self.db.profile.logLevel = log:getLevelName()
            log:chat("Log level set to %s", self.db.profile.logLevel)
        else
            log:chat("Log level is %s", log:getLevelName())
        end
    elseif cmd == "reset" then
        self.db:ResetProfile()
        log:chat("Profile reset")
    elseif cmd == "export" then
        app.ui.exportFrame:ShowText(app.json.encode(app.discovery:ExportTable()))
    elseif cmd == "scan" then
        app.discovery:ScanCommand(a, b, c)
    else
        log:chat("Commands: /fl, /fl export, /fl scan <from> [to], /fl scan resume, /fl loglevel <level>, /fl reset")
    end
end
