---@type string, SpyglassScraper
local _, app = ...

-- `/sg portrait`: a studio for shooting boss pictures. Bosses this server added have no
-- Encounter Journal art, and the portrait the client renders from a creature display id is a
-- plain head shot, so the pictures are made by hand instead: this window shows the boss's model
-- twice side by side, posed and frozen the same way, once on black and once on white, each
-- ringed by a magenta marker the screenshot is cropped on.
--
-- Both backgrounds are on screen at once because one shot cannot tell a dark pixel from a
-- transparent one, while the pair gives the exact transparency back
-- (alpha = 1 - (white - black)). The settings line under them is part of the screenshot on
-- purpose: it says how the picture was framed, so it can be reshot the same way, and how large
-- the capture areas really are in screen pixels.

local SG = app.api
local log = app.log

-- What each capture area aims for in real screen pixels: 4x the 128x64 the client's own boss
-- art uses, so the model is shot larger than it will be shown and downscaled afterwards. The
-- size it really ends up with goes in the settings line; any 2:1 area big enough will do.
local CAPTURE_WIDTH, CAPTURE_HEIGHT = 512, 256
-- Thickness of the magenta crop marker around each area, also in screen pixels.
local MARKER = 2
-- Space between the two areas, and from the window's edge.
local GAP, MARGIN = 12, 14
-- Room above the capture areas (title, hint, subject) and below them (controls, settings line).
local HEADER, FOOTER = 90, 150

-- Where a boss's model starts, matched against one of the game's own boss pictures: a wide
-- bust turned 30 degrees to the viewer's left, sitting a little low in the frame. Every picture
-- is shot from these, which is what makes the set look like one set.
local DEFAULTS = { zoom = 0.25, facing = math.rad(30), x = 0, y = -0.05 }
local ZOOM_STEP, FACING_STEP, MOVE_STEP = 0.05, math.pi / 36, 0.05

---@class SpyglassScraper.Capture : Frame
---@field Background Texture
---@field Marker Texture
---@field Model PlayerModel

---@class SpyglassScraper.PortraitFrame : Frame
---@field TitleText FontString
---@field Hint FontString
---@field Black SpyglassScraper.Capture
---@field White SpyglassScraper.Capture
---@field Settings FontString
---@field Subject FontString
---@field IDBox EditBox
---@field Buttons table<string, Button>
---@field displayID? integer
---@field subject? string  # what the current model is, for the settings line
---@field index integer  # position in the boss list for < Boss / Boss >
---@field zoom number
---@field facing number
---@field x number
---@field y number
SpyglassScraperPortraitFrameMixin = {}
app.PortraitFrameMixin = SpyglassScraperPortraitFrameMixin

local mixin = SpyglassScraperPortraitFrameMixin

-- Every boss the core's database knows a display id for, in browsing order, so < Boss / Boss >
-- walks exactly the bosses whose picture is still to be made.
---@return { bossID: integer, displayID: integer, name: string, instance: string }[]
local function bossList()
    local Data = SG.Data
    local list = {}
    for _, instanceID in ipairs(Data:GetInstanceIDs()) do
        local instance = Data:GetInstance(instanceID)
        for _, bossID in ipairs(instance and instance.bosses or {}) do
            local boss = Data:GetBoss(bossID)
            if boss and type(boss.displayID) == "number" and boss.displayID > 0 then
                list[#list + 1] = {
                    bossID = bossID,
                    displayID = boss.displayID,
                    name = Data:GetBossName(bossID),
                    instance = Data:GetInstanceName(instanceID),
                }
            end
        end
    end
    return list
end

-- The control bar, built in code because it is a dozen identical buttons: label, width and
-- what the click does. They flow left to right under the capture areas and wrap.
local CONTROLS = {
    {
        "< Boss",
        70,
        function(self)
            self:Step(-1)
        end,
    },
    {
        "Boss >",
        70,
        function(self)
            self:Step(1)
        end,
    },
    {
        "Zoom -",
        60,
        function(self)
            self:Nudge("zoom", -ZOOM_STEP)
        end,
    },
    {
        "Zoom +",
        60,
        function(self)
            self:Nudge("zoom", ZOOM_STEP)
        end,
    },
    {
        "Turn <",
        60,
        function(self)
            self:Nudge("facing", -FACING_STEP)
        end,
    },
    {
        "Turn >",
        60,
        function(self)
            self:Nudge("facing", FACING_STEP)
        end,
    },
    {
        "Left",
        50,
        function(self)
            self:Nudge("x", -MOVE_STEP)
        end,
    },
    {
        "Right",
        50,
        function(self)
            self:Nudge("x", MOVE_STEP)
        end,
    },
    {
        "Down",
        50,
        function(self)
            self:Nudge("y", -MOVE_STEP)
        end,
    },
    {
        "Up",
        50,
        function(self)
            self:Nudge("y", MOVE_STEP)
        end,
    },
    {
        "Reset",
        60,
        function(self)
            self:Reset()
        end,
    },
}

-- Lays the buttons out in rows under the left capture area and adds the settings line below.
function mixin:BuildControls()
    self.Buttons = {}
    local x, y = 104, -34 -- to the right of the id box, then wrapping into its own rows
    for _, control in ipairs(CONTROLS) do
        local label, width, onClick = control[1], control[2], control[3]
        if x + width > CAPTURE_WIDTH then
            x, y = 6, y - 26
        end
        local button = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetPoint("TOPLEFT", self.Black, "BOTTOMLEFT", x, y)
        button:SetScript("OnClick", function()
            onClick(self)
        end)
        self.Buttons[label] = button
        x = x + width + 4
    end

    self.Settings = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.Settings:SetPoint("TOPLEFT", self.Black, "BOTTOMLEFT", 6, y - 30)
    self.Settings:SetJustifyH("LEFT")
end

function mixin:OnLoad()
    self.TitleText:SetText("Spyglass - Portrait")
    self.Hint:SetText(
        "One screenshot (Print Screen) catches both magenta frames, and the black/white pair "
            .. "carries the transparency. The settings line below is part of the shot."
    )
    self.index = 0
    self.Black.Background:SetColorTexture(0, 0, 0, 1)
    self.White.Background:SetColorTexture(1, 1, 1, 1)
    self:BuildControls()
    self.zoom, self.facing = DEFAULTS.zoom, DEFAULTS.facing
    self.x, self.y = DEFAULTS.x, DEFAULTS.y
    tinsert(UISpecialFrames, self:GetName())
    self:RegisterForDrag("LeftButton")
    -- The capture areas are measured in screen pixels, so they are re-laid out whenever the
    -- relation between screen and interface coordinates changes.
    self:RegisterEvent("UI_SCALE_CHANGED")
    self:RegisterEvent("DISPLAY_SIZE_CHANGED")
    self:SetScript("OnEvent", function()
        self:UpdateCaptureSize()
    end)
    app.portraitFrame = self

    self.IDBox:SetScript("OnEnterPressed", function(box)
        local id = tonumber(box:GetText())
        box:ClearFocus()
        if id then
            self:SetDisplayID(id, ("display %d"):format(id))
        end
    end)
end

function mixin:OnDragStart()
    self:StartMoving()
end

function mixin:OnDragStop()
    self:StopMovingOrSizing()
end

function mixin:OnShow()
    self:UpdateCaptureSize()
end

-- Sizes both capture areas so each is CAPTURE_WIDTH x CAPTURE_HEIGHT *screen* pixels whatever
-- the UI scale is, and grows the window around them. The size that comes out is reported in the
-- settings line rather than relied on: the crop only needs a 2:1 area, not an exact one.
function mixin:UpdateCaptureSize()
    local scale = self:GetEffectiveScale()
    if not scale or scale <= 0 then
        return
    end
    local width, height = CAPTURE_WIDTH / scale, CAPTURE_HEIGHT / scale
    local marker = MARKER / scale
    for _, capture in ipairs({ self.Black, self.White }) do
        capture:SetSize(width, height)
        capture.Marker:ClearAllPoints()
        capture.Marker:SetPoint("TOPLEFT", -marker, marker)
        capture.Marker:SetPoint("BOTTOMRIGHT", marker, -marker)
    end
    self:SetSize(2 * width + GAP + 2 * MARGIN, HEADER + height + FOOTER)
    self.Black:ClearAllPoints()
    self.Black:SetPoint("TOPLEFT", MARGIN, -HEADER)
    self:UpdateSettings()
end

-- Back to the framing every picture starts from; keeping it identical is what makes the set
-- look uniform.
function mixin:Reset()
    self.zoom, self.facing = DEFAULTS.zoom, DEFAULTS.facing
    self.x, self.y = DEFAULTS.x, DEFAULTS.y
    self:ApplyFraming()
end

---@param displayID integer
---@param subject? string  # "Edwin VanCleef (Deadmines)" for the settings line
function mixin:SetDisplayID(displayID, subject)
    self.displayID = displayID
    self.subject = subject
    self.IDBox:SetText(tostring(displayID))
    self:LoadModels()
    self:Show()
end

-- Steps through the bosses that carry a display id; `step` is +1 or -1.
---@param step integer
function mixin:Step(step)
    local list = bossList()
    if #list == 0 then
        log:chat("No boss in the database carries a displayID yet; type one in the box instead.")
        return
    end
    self.index = (self.index + step - 1) % #list + 1
    local boss = list[self.index]
    self:SetDisplayID(boss.displayID, ("%s (%s), boss %d"):format(boss.name, boss.instance, boss.bossID))
end

---@param field "zoom"|"facing"|"x"|"y"
---@param delta number
function mixin:Nudge(field, delta)
    if field == "zoom" then
        self.zoom = math.max(0, math.min(1, self.zoom + delta))
    else
        self[field] = self[field] + delta
    end
    self:ApplyFraming()
end

-- Loads a model into both capture areas, frozen in its stand pose so the two sides line up
-- pixel for pixel -- which is what recovering the transparency depends on. Only called when the
-- display id actually changes: re-setting a model that is already loaded brings it back unlit
-- (it renders black until the frame is shown again), and the framing needs no reload anyway.
function mixin:LoadModels()
    for _, capture in ipairs({ self.Black, self.White }) do
        local model = capture and capture.Model
        if model and capture.loadedDisplayID ~= self.displayID then
            capture.loadedDisplayID = self.displayID
            model:ClearModel()
            if self.displayID then
                model:SetDisplayInfo(self.displayID)
                -- A model fades in when it is set, so the clock has to keep running (pausing
                -- the frame freezes it part-way through and the whole model stays translucent);
                -- FreezeAnimation is what holds the pose still.
                model:SetPaused(false)
                model:SetModelAlpha(1)
                model:FreezeAnimation(0, 0, 0)
                -- Re-showing the frame is what makes a newly set model light itself properly.
                model:Hide()
                model:Show()
            end
        end
    end
    self:ApplyFraming()
end

-- Zoom, turn and offset: applied to the loaded models without touching the model itself.
function mixin:ApplyFraming()
    for _, capture in ipairs({ self.Black, self.White }) do
        local model = capture and capture.Model
        if model and capture.loadedDisplayID then
            model:SetPortraitZoom(self.zoom)
            model:SetRotation(self.facing)
            model:SetPosition(0, self.x, self.y)
        end
    end
    self:UpdateSettings()
end

function mixin:UpdateSettings()
    self.Subject:SetText(self.subject or (self.displayID and ("display %d"):format(self.displayID)) or "no model")
    local scale = self:GetEffectiveScale() or 1
    self.Settings:SetText(
        ("display %s | zoom %.2f | facing %d deg | offset %.2f / %.2f | capture %dx%d px"):format(
            self.displayID and tostring(self.displayID) or "-",
            self.zoom,
            math.floor(math.deg(self.facing) + 0.5),
            self.x,
            self.y,
            math.floor(self.Black:GetWidth() * scale + 0.5),
            math.floor(self.Black:GetHeight() * scale + 0.5)
        )
    )
end

-- `/sg portrait [displayID]`
---@param arg? string
function mixin:Command(arg)
    local id = tonumber(arg)
    if id then
        self:SetDisplayID(id, ("display %d"):format(id))
        return
    end
    if self.displayID then
        self:Show()
    else
        self.index = 0
        self:Step(1)
        self:Show()
    end
end
