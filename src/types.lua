-- Type annotations only; this file is not listed in the TOC and never runs in-game.
-- It exists so the Lua language server can type the `...` vararg every file receives.
-- Every file should start with:
--   ---@type string, ForeverLoot
--   local appName, app = ...
-- When a file adds something to `app`, add a matching ---@field here.

---@class ForeverLoot
---@field logger ForeverLoot.Logger
---@field addon ForeverLoot.Addon
---@field dbDefaults ForeverLoot.DBDefaults
---@field db ForeverLoot.DB
---@field minimapButton ForeverLoot.MinimapButton

-- The AceDB object, with profile/char/global narrowed to the shape of app.dbDefaults.
-- Ace3 API types (AceAddon, AceDBObject-3.0, ...) come from the ketho.wow-api extension.
---@class ForeverLoot.DB : AceDBObject-3.0
---@field profile ForeverLoot.DB.Profile
---@field char ForeverLoot.DB.Char
---@field global ForeverLoot.DB.Global
