---@type string, SpyglassLocale
local _, app = ...

local log = app.log
local addon = app.addon
local Data = app.api.Data

-- Names the items the generated locale files don't. Those come from wago.tools' tables, which
-- lack the items this server added or changed; the client knows them in its own language once it
-- has fetched them. So after login this asks for every item in Spyglass.Data that has no name
-- in the client's language, a few per tick and never in combat, and keeps what it learns in
-- SpyglassLocaleDB.global.locales[locale]. The next session registers those names on load, so
-- each item is looked up once. English clients get every name from the core; nothing runs there.

-- Seconds after login before the lookups start, so they don't compete with loading in.
local START_DELAY = 15
-- Item requests per tick and the tick length: 10 per second, a fifth of what /sg scan asks.
local BATCH, INTERVAL = 5, 0.5
-- Seconds between handing learned names to Spyglass.Data: each AddNames invalidates the core's
-- search and sort caches and redraws an open window.
local FLUSH_INTERVAL = 30
-- Seconds to wait for the answers to the last requests before reporting.
local SETTLE = 5

---@class SpyglassLocale.Lookup
---@field queue integer[]  # item ids to ask for, in id order
---@field next integer  # index into queue of the next request
---@field pending table<integer, boolean>  # requested, no answer yet
---@field learned integer  # names learned by this lookup
---@field done boolean  # no more requests; waiting for the last answers
---@field ticker any

-- Prototype: Ace attaches it to the real module object via __index.
---@class SpyglassLocale.ItemNames : AceModule, AceEvent-3.0
---@field locale string  # GetLocale()
---@field saved? SpyglassLocale.LearnedNames  # this language's saved names; nil on English clients
---@field unflushed table<integer, string>  # learned, not handed to Spyglass.Data yet
---@field flushedAt number  # GetTime() of the last hand-over
---@field lookup? SpyglassLocale.Lookup
local module = {}
app.itemNames = addon:NewModule("ItemNames", module, "AceEvent-3.0") --[[@as SpyglassLocale.ItemNames]]

-- The item names Spyglass.Data has in `locale`, from any source; nil when it has none.
---@param locale string
---@return table<integer, string>?
local function knownNames(locale)
    local names = Data.names[locale]
    return names and names.items
end

---@param tbl table
---@return integer
local function count(tbl)
    local n = 0
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

-- ADDON_LOADED, after addon:OnInitialize: the generated files of the core and of this addon have
-- run, so the saved names can be compared with the shipped ones.
function module:OnInitialize()
    self.locale = GetLocale()
    self.unflushed = {}
    self.flushedAt = 0
    if self.locale == "enUS" then
        return
    end
    local saved = app.db.global.locales[self.locale]
    self.saved = saved
    local version, build = GetBuildInfo()
    build = version .. "." .. build
    if saved.build ~= build then
        saved.build, saved.missing = build, {}
    end
    -- A name a newer release ships is the shipped file's now; the rest go to Data.
    local known = knownNames(self.locale)
    local names, n = {}, 0
    for itemID, name in pairs(saved.items) do
        if known and known[itemID] then
            saved.items[itemID] = nil
        else
            names[itemID] = name
            n = n + 1
        end
    end
    if n > 0 then
        Data:AddNames(self.locale, "items", names)
    end
    log:debug("%d saved item name(s) registered (%s)", n, self.locale)
end

-- PLAYER_LOGIN
function module:OnEnable()
    if not self.saved then
        log:info(
            "Spyglass Locale isn't needed on an English client: Spyglass has every English name. You can disable it in the AddOns list."
        )
        return
    end
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    C_Timer.After(START_DELAY, function()
        if self:IsEnabled() and not self.lookup then
            self:Start()
        end
    end)
end

function module:OnDisable()
    self:Stop()
end

-- Queues every item Data has without a name in this language, minus the ids the server didn't
-- know this build; with `redo` the names learned earlier are asked for again. False when there is
-- nothing to ask for.
---@param redo? boolean
---@return boolean
function module:Start(redo)
    local saved = self.saved
    if not saved then
        return false
    end
    local known = knownNames(self.locale) or {}
    local queue = {}
    for _, itemID in ipairs(Data:GetItemIDs()) do
        if not saved.missing[itemID] and (not known[itemID] or (redo and saved.items[itemID])) then
            queue[#queue + 1] = itemID
        end
    end
    if #queue == 0 then
        log:debug("Every item has a name (%s)", self.locale)
        return false
    end
    ---@type SpyglassLocale.Lookup
    local lookup = { queue = queue, next = 1, pending = {}, learned = 0, done = false }
    self.lookup = lookup
    self.flushedAt = GetTime()
    lookup.ticker = C_Timer.NewTicker(INTERVAL, function()
        self:Tick()
    end)
    log:info("Looking up %d item name(s) in the background (%s)", #queue, self.locale)
    return true
end

function module:Tick()
    local lookup = self.lookup
    if not lookup or lookup.done then
        return
    end
    if GetTime() - self.flushedAt >= FLUSH_INTERVAL then
        self:Flush()
    end
    if InCombatLockdown() then
        return
    end
    local queue = lookup.queue
    local last = math.min(lookup.next + BATCH - 1, #queue)
    for i = lookup.next, last do
        local itemID = queue[i]
        if C_Item.IsItemDataCachedByID(itemID) then
            self:Learn(itemID)
        else
            lookup.pending[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    lookup.next = last + 1
    if lookup.next > #queue then
        self:Finish()
    end
end

-- Keeps the client's name for an item whose data it has.
---@param itemID integer
function module:Learn(itemID)
    local name = C_Item.GetItemInfo(itemID)
    if not name then
        return
    end
    self.saved.items[itemID] = name
    self.unflushed[itemID] = name
    if self.lookup then
        self.lookup.learned = self.lookup.learned + 1
    end
end

---@param itemID integer
---@param success boolean
function module:ITEM_DATA_LOAD_RESULT(_, itemID, success)
    local lookup = self.lookup
    if not (lookup and lookup.pending[itemID]) then
        return
    end
    lookup.pending[itemID] = nil
    if success then
        self:Learn(itemID)
    else
        self.saved.missing[itemID] = true
    end
end

-- Hands the names learned since the last call to Spyglass.Data.
function module:Flush()
    self.flushedAt = GetTime()
    if next(self.unflushed) == nil then
        return
    end
    Data:AddNames(self.locale, "items", self.unflushed)
    self.unflushed = {}
end

-- Stops requesting, waits for the answers still in flight, then reports. Ids that never got an
-- answer are neither named nor marked missing, so the next session asks again.
function module:Finish()
    local lookup = self.lookup
    if not lookup or lookup.done then
        return
    end
    lookup.done = true
    lookup.ticker:Cancel()
    C_Timer.After(SETTLE, function()
        if self.lookup ~= lookup then
            return
        end
        self.lookup = nil
        self:Flush()
        if lookup.learned > 0 then
            log:info("%d item name(s) learned (%s)", lookup.learned, self.locale)
        end
    end)
end

function module:Stop()
    local lookup = self.lookup
    if lookup then
        lookup.ticker:Cancel()
        self.lookup = nil
    end
    self:Flush()
end

-- `/sg locale` (status), `/sg locale rescan` (ask for every learned and missing item again).
---@param a? string
function module:Command(a)
    local saved = self.saved
    if not saved then
        log:chat("English client: every item name comes with Spyglass, there is nothing to look up.")
        return
    end
    if a == "rescan" then
        if self.lookup then
            log:chat("Item names are being looked up already; /sg locale shows how far.")
            return
        end
        saved.missing = {}
        if not self:Start(true) then
            log:chat("Every item has a name (%s), there is nothing to look up.", self.locale)
        end
    elseif a then
        log:chat("Usage: /sg locale, /sg locale rescan")
    elseif self.lookup then
        local lookup = self.lookup
        log:chat(
            "Looking up item names (%s): %d of %d asked, %d learned so far.",
            self.locale,
            lookup.next - 1,
            #lookup.queue,
            lookup.learned
        )
    else
        log:chat(
            "%s: %d item name(s) learned in-game, %d item(s) the server doesn't know. /sg locale rescan asks for them all again.",
            self.locale,
            count(saved.items),
            count(saved.missing)
        )
    end
end
