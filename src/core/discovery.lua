---@type string, ForeverLoot
local _, app = ...

local log = app.logger
local addon = app.addon
local Data = app.data
local ITEM = Data.ITEM

-- Learns from the game what the shipped database doesn't have yet. WoW Forever's items are
-- server-side, so no data export describes them; the client does, once it has fetched an item.
-- Two ways in, both recorded in `global.discovered` (see src/core/db.lua) and merged into
-- ForeverLoot.Data right away:
--
--   /fl scan   asks the server about id ranges and records every item that exists — the way
--              the shipped item database is built (.contribute/items/*.json via `npm run import`)
--   loot       any item dropping in front of us that the DB lacks, plus per boss how often it
--              was killed and which items were seen dropping (curated into the loot files)
--
-- A record holds everything C_Item.GetItemInfo and C_Item.GetItemStats return, in the client's
-- locale (`discovered.locale`).
--
-- Attribution: a loot window or group roll shortly after a successful ENCOUNTER_END belongs to
-- that encounter. When the client tells us the looted unit (GetLootSourceInfo) and the encounter
-- told us its creatures, the two must match, so trash or a chest looted after the kill isn't
-- counted. Kills where nobody in range rolled and we didn't loot still count as kills, which
-- makes observed ratios underestimate the real chance; the import tool only suggests one.

-- A loot window or roll this long after a successful encounter end counts as that boss's loot.
local KILL_WINDOW = 300
-- /fl scan: item requests per tick and the tick length (~50 ids per second).
local SCAN_BATCH, SCAN_INTERVAL = 25, 0.5
-- Newly recorded items after which a scan stops, so exports stay handy.
local SCAN_LIMIT = 500
-- Consecutive ids that don't exist before an open-ended scan assumes it ran past the last item.
local SCAN_MAX_GAP = 20000
-- Seconds to wait for the results of the last requests before a scan reports.
local SCAN_SETTLE = 3

local LOOT_SLOT_ITEM = LOOT_SLOT_ITEM or 1

---@class ForeverLoot.LastKill
---@field id integer  # encounterID
---@field time number  # GetTime() at ENCOUNTER_END
---@field seen table<integer, boolean>  # itemIDs already counted for this kill
---@field creatures table<integer, boolean>  # creatureIDs of the encounter's units, may be empty
---@field hasCreatures boolean

---@class ForeverLoot.Scan
---@field from integer
---@field to? integer  # nil = open-ended
---@field next integer  # first id not requested yet
---@field found integer  # items recorded by this scan
---@field force boolean  # re-record ids the DB has; no SCAN_LIMIT
---@field gap integer  # consecutive ids that didn't exist
---@field pending table<integer, boolean>  # requested, no result yet
---@field done boolean  # no more requests; waiting for the last results
---@field ticker any

-- Prototype: Ace attaches it to the real module object via __index (see minimapbutton.lua).
---@class ForeverLoot.Discovery : AceModule, AceEvent-3.0
---@field lastKill? ForeverLoot.LastKill
---@field scan? ForeverLoot.Scan
---@field pendingItems table<integer, boolean>  # item loads waiting for the client
---@field merged table<integer, boolean>  # rows in Data that came from us, not from the shipped files
local module = {}
app.discovery = addon:NewModule("Discovery", module, "AceEvent-3.0") --[[@as ForeverLoot.Discovery]]

---@return ForeverLoot.Discovered
local function discovered()
    return app.db.global.discovered
end

-- C_Item.GetItemStats keys, shortened: ITEM_MOD_INTELLECT_SHORT -> INTELLECT. nil when none.
---@param link string?
---@return ForeverLoot.ItemStats?
local function readStats(link)
    local raw = link and C_Item.GetItemStats and C_Item.GetItemStats(link)
    if type(raw) ~= "table" then
        return nil
    end
    local stats, any = {}, false
    for key, value in pairs(raw) do
        if type(key) == "string" and type(value) == "number" and value ~= 0 then
            local short = key:gsub("^ITEM_MOD_", "")
            short = short:gsub("_SHORT$", "")
            stats[short] = math.floor(value * 100 + 0.5) / 100
            any = true
        end
    end
    return any and stats or nil
end

---@param item ForeverLoot.DiscoveredItem
---@return ForeverLoot.ItemRow
local function toRow(item)
    return {
        item.quality or 1,
        item.itemLevel or 1,
        item.reqLevel or 0,
        item.classID or 0,
        item.subclassID or 0,
        item.slot or "",
        item.bind or 0,
        item.icon or 0,
        item.stats,
        item.sellPrice or 0,
        item.stackCount or 1,
        item.setID or 0,
        item.expansionID or 0,
        item.craftingReagent or false,
    }
end

---@param a table?
---@param b table?
---@return boolean
local function statsEqual(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

-- True when the shipped row already says exactly what the record says.
---@param row ForeverLoot.ItemRow
---@param record ForeverLoot.ItemRow
---@return boolean
local function rowEquals(row, record)
    for i = 1, ITEM.REAGENT do
        if i == ITEM.STATS then
            if not statsEqual(row[i], record[i]) then
                return false
            end
        elseif row[i] ~= record[i] then
            return false
        end
    end
    return true
end

---@param bossID integer
---@param itemID integer
---@return boolean
local function listed(bossID, itemID)
    for _, row in ipairs(Data:GetBossLoot(bossID)) do
        if row[1] == itemID then
            return true
        end
    end
    return false
end

-- Runs after addon:OnInitialize, so app.db is available.
function module:OnInitialize()
    self.pendingItems = {}
    self.merged = {}
    local version, build = GetBuildInfo()
    discovered().build = version .. "." .. build
end

-- PLAYER_LOGIN: every data file has run, so the shipped DB is complete and can be compared.
function module:OnEnable()
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    self:MergeIntoData()
end

function module:OnDisable()
    self:StopScan(true)
end

---@param encounterID integer
---@return ForeverLoot.DiscoveredLoot
function module:LootEntry(encounterID)
    local loot = discovered().loot
    local entry = loot[encounterID]
    if not entry then
        entry = { kills = 0, items = {} }
        loot[encounterID] = entry
    end
    return entry
end

-- Pushes everything recorded so far into the DB. A record the shipped database states exactly
-- (it has been imported and generated since) is dropped; a differing one wins over the shipped
-- row, since it is the newer observation.
function module:MergeIntoData()
    local d = discovered()
    local rows, names, count = {}, {}, 0
    for itemID, item in pairs(d.items) do
        local row = Data:GetItem(itemID)
        if row and not self.merged[itemID] and rowEquals(row, toRow(item)) then
            d.items[itemID] = nil
        else
            rows[itemID] = toRow(item)
            names[itemID] = item.name
            self.merged[itemID] = true
            count = count + 1
        end
    end
    if count > 0 then
        Data:AddItems(rows)
        Data:AddNames(d.locale or GetLocale(), "items", names)
    end
    local drops = 0
    for bossID, entry in pairs(d.loot) do
        local missing = {}
        for itemID in pairs(entry.items) do
            if not listed(bossID, itemID) then
                missing[#missing + 1] = { itemID }
            end
        end
        if #missing > 0 then
            Data:AddBossLoot(bossID, missing)
            drops = drops + #missing
        end
    end
    log:debug("Discovered data merged: %d item(s), %d drop(s)", count, drops)
end

---@return integer
function module:RecordCount()
    local count = 0
    for _ in pairs(discovered().items) do
        count = count + 1
    end
    return count
end

----------------------------------------------------------------------------------------------------
-- Recording
----------------------------------------------------------------------------------------------------

-- Records an item once the client has its data; without `force` only when the DB lacks it.
-- Returns true when something was recorded.
---@param itemID integer
---@param force? boolean
---@return boolean
function module:RecordItem(itemID, force)
    if not force and Data:GetItem(itemID) then
        return false
    end
    local name, link, quality, itemLevel, reqLevel, _, _, stackCount, slot, icon, sellPrice, classID, subclassID, bind, expansionID, setID, craftingReagent =
        C_Item.GetItemInfo(itemID)
    if not name then
        return false
    end
    ---@type ForeverLoot.DiscoveredItem
    local item = {
        name = name,
        quality = quality,
        itemLevel = itemLevel,
        reqLevel = reqLevel,
        classID = classID,
        subclassID = subclassID,
        slot = slot or "",
        bind = bind or 0,
        icon = icon,
        sellPrice = sellPrice or 0,
        stackCount = stackCount or 1,
        setID = setID or 0,
        expansionID = expansionID or 0,
        craftingReagent = craftingReagent and true or false,
        stats = readStats(link),
    }
    local d = discovered()
    d.items[itemID] = item
    d.locale = GetLocale()
    self.merged[itemID] = true
    Data:AddItems({ [itemID] = toRow(item) })
    Data:AddNames(d.locale, "items", { [itemID] = name })
    log:debug("Item recorded: %s (%d)", name, itemID)
    return true
end

-- Records the item if the DB doesn't know it, waiting for the client's item data if needed.
---@param itemID integer
function module:NoteItem(itemID)
    if Data:GetItem(itemID) or self.pendingItems[itemID] then
        return
    end
    self.pendingItems[itemID] = true
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
        self.pendingItems[itemID] = nil
        if self:RecordItem(itemID) then
            log:info("New item recorded: %s (%d)", Data:GetItemName(itemID), itemID)
        end
    end)
end

-- Counts the item for the last killed boss when the loot plausibly came from it.
---@param itemID integer
---@param guid? string  # of the looted unit, when the client tells us
function module:Attribute(itemID, guid)
    local kill = self.lastKill
    if not kill or GetTime() - kill.time > KILL_WINDOW or kill.seen[itemID] then
        return
    end
    if guid and kill.hasCreatures then
        local unitType, _, _, _, _, creatureID = strsplit("-", guid)
        if (unitType == "Creature" or unitType == "Vehicle") and not kill.creatures[tonumber(creatureID) or 0] then
            return -- some other corpse looted after the kill
        end
    end
    kill.seen[itemID] = true
    local entry = self:LootEntry(kill.id)
    entry.items[itemID] = (entry.items[itemID] or 0) + 1
    if not listed(kill.id, itemID) then
        Data:AddBossLoot(kill.id, { { itemID } })
    end
    log:debug("Drop recorded: item %d from encounter %d (%d/%d)", itemID, kill.id, entry.items[itemID], entry.kills)
end

---@param encounterID integer
---@param encounterName string
---@param success integer  # 1 = kill
---@param units? { creatureID: integer }[]
function module:ENCOUNTER_END(_, encounterID, encounterName, _, _, success, units)
    if success ~= 1 then
        self.lastKill = nil
        return
    end
    local entry = self:LootEntry(encounterID)
    entry.kills = entry.kills + 1
    local creatures, hasCreatures = {}, false
    if type(units) == "table" then
        for _, unit in ipairs(units) do
            if type(unit) == "table" and unit.creatureID then
                creatures[unit.creatureID] = true
                hasCreatures = true
            end
        end
    end
    self.lastKill = { id = encounterID, time = GetTime(), seen = {}, creatures = creatures, hasCreatures = hasCreatures }
    log:debug("Encounter %d (%s) killed, %d kill(s) recorded", encounterID, encounterName, entry.kills)
end

function module:LOOT_OPENED()
    for slot = 1, GetNumLootItems() do
        if GetLootSlotType(slot) == LOOT_SLOT_ITEM then
            local link = GetLootSlotLink(slot)
            local itemID = link and C_Item.GetItemInfoInstant(link)
            if itemID then
                self:NoteItem(itemID)
                -- Not used by Classic's own LootFrame, so it may not exist on this client.
                local guid = GetLootSourceInfo and GetLootSourceInfo(slot) or nil
                self:Attribute(itemID, guid)
            end
        end
    end
end

---@param rollID integer
function module:START_LOOT_ROLL(_, rollID)
    local link = GetLootRollItemLink(rollID)
    local itemID = link and C_Item.GetItemInfoInstant(link)
    if itemID then
        self:NoteItem(itemID)
        self:Attribute(itemID, nil)
    end
end

function module:PLAYER_ENTERING_WORLD()
    self.lastKill = nil
end

---@param itemID integer
---@param success boolean
function module:ITEM_DATA_LOAD_RESULT(_, itemID, success)
    local scan = self.scan
    if not (scan and scan.pending[itemID]) then
        return
    end
    scan.pending[itemID] = nil
    if success then
        scan.gap = 0
        if self:RecordItem(itemID, scan.force) then
            scan.found = scan.found + 1
            if not scan.force and scan.found >= SCAN_LIMIT and not scan.done then
                self:FinishScan(("%d new items recorded"):format(scan.found))
            end
        end
    else
        scan.gap = scan.gap + 1
        if not scan.to and scan.gap >= SCAN_MAX_GAP and not scan.done then
            self:FinishScan(("%d ids in a row don't exist, probably past the last item"):format(scan.gap))
        end
    end
end

----------------------------------------------------------------------------------------------------
-- /fl scan: ask the server about every id in a range and record what exists
----------------------------------------------------------------------------------------------------

---@param from integer
---@param to? integer
---@param force? boolean
function module:StartScan(from, to, force)
    if self.scan then
        log:chat("A scan is already running (%d..%s, at %d); /fl scan stop first", self.scan.from, tostring(self.scan.to or "open"), self.scan.next)
        return
    end
    ---@type ForeverLoot.Scan
    local scan = { from = from, to = to, next = from, found = 0, force = force or false, gap = 0, pending = {}, done = false }
    self.scan = scan
    scan.ticker = C_Timer.NewTicker(SCAN_INTERVAL, function()
        self:ScanTick()
    end)
    if force then
        log:chat("Re-scanning item ids %d..%d, recording every item again.", from, to)
    else
        log:chat(
            "Scanning item ids from %d%s at %d per second; stops after %d new items. The server may throttle item queries, so keep ranges modest; /fl scan stop aborts.",
            from,
            to and (" to " .. to) or "",
            SCAN_BATCH / SCAN_INTERVAL,
            SCAN_LIMIT
        )
    end
end

function module:ScanTick()
    local scan = self.scan
    if not scan or scan.done then
        return
    end
    local last = scan.next + SCAN_BATCH - 1
    if scan.to then
        last = math.min(last, scan.to)
    end
    for id = scan.next, last do
        if scan.force or not Data:GetItem(id) then
            scan.pending[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    scan.next = last + 1
    if not scan.force then
        -- A force re-scan is a side trip; the resume point belongs to the main scan.
        local progress = app.db.global.scan
        progress.next, progress.to = scan.next, scan.to
    end
    if scan.to and scan.next > scan.to then
        self:FinishScan("end of the range")
    elseif (scan.next - scan.from) % 1000 == 0 then
        log:chat("Scan at %d, %d item(s) recorded so far", last, scan.found)
    end
end

-- Stops requesting, waits for the results still in flight, then reports and clears the scan.
---@param reason string
function module:FinishScan(reason)
    local scan = self.scan
    if not scan or scan.done then
        return
    end
    scan.done = true
    scan.ticker:Cancel()
    C_Timer.After(SCAN_SETTLE, function()
        if self.scan ~= scan then
            return
        end
        self.scan = nil
        local resume = scan.to and scan.next > scan.to and "" or (", /fl scan resume continues at %d"):format(scan.next)
        log:chat("Scan stopped at %d (%s): %d item(s) recorded. Export with /fl export or import the SavedVariables file%s.", scan.next - 1, reason, scan.found, resume)
    end)
end

---@param silent? boolean
function module:StopScan(silent)
    if not self.scan then
        if not silent then
            log:chat("No scan running")
        end
        return
    end
    if silent then
        self.scan.ticker:Cancel()
        self.scan = nil
    else
        self:FinishScan("stopped")
    end
end

-- `/fl scan <from> [to]`, `/fl scan <from> <to> force`, `/fl scan resume`, `/fl scan stop`, `/fl scan` (status).
---@param a? string
---@param b? string
---@param c? string
function module:ScanCommand(a, b, c)
    local from, to = tonumber(a), tonumber(b)
    local progress = app.db.global.scan
    if a == "stop" then
        self:StopScan()
    elseif a == "resume" then
        if progress.next then
            self:StartScan(progress.next, progress.to)
        else
            log:chat("Nothing to resume; /fl scan <from> [to] starts a scan")
        end
    elseif from then
        from = math.floor(from)
        to = to and math.floor(to) or nil
        if from < 1 or (to and to < from) then
            log:chat("Usage: /fl scan <from> [to] with 1 <= from <= to")
        elseif c == "force" and not to then
            log:chat("force needs a range: /fl scan <from> <to> force")
        else
            self:StartScan(from, to, c == "force")
        end
    elseif not a then
        local scan = self.scan
        if scan then
            log:chat("Scan %d..%s at %d, %d item(s) recorded so far", scan.from, tostring(scan.to or "open"), scan.next - 1, scan.found)
        elseif progress.next then
            log:chat("No scan running; /fl scan resume continues at %d. %d item record(s) waiting for export.", progress.next, self:RecordCount())
        else
            log:chat("No scan running; /fl scan <from> [to] starts one. %d item record(s) waiting for export.", self:RecordCount())
        end
    else
        log:chat("Usage: /fl scan <from> [to], /fl scan <from> <to> force, /fl scan resume, /fl scan stop")
    end
end

----------------------------------------------------------------------------------------------------
-- Export
----------------------------------------------------------------------------------------------------

-- The recorded data as one plain table, the shape .contribute/tools' `import` reads.
---@return table
function module:ExportTable()
    local d = discovered()
    return { version = 1, build = d.build, locale = d.locale or GetLocale(), items = d.items, loot = d.loot }
end
