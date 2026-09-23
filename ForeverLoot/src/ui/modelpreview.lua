---@type string, ForeverLoot
local _, app = ...

app.ui = app.ui or {}

-- The dressing room's model scene in the client's data: one player actor per race and gender
-- and a camera that frames the whole character.
local MODEL_SCENE_ID = 596

-- Turned a little further than the scene places it, towards the main hand, so weapons and
-- shoulders show more from the side.
local TURN = math.rad(25)

-- The character wearing an item, shown under the item's tooltip while ctrl is held. A row sets
-- the item when its tooltip opens (SetItem) and clears it when the tooltip closes (Clear);
-- pressing or releasing ctrl in between shows or hides the model.
---@class ForeverLoot.ModelPreview : Frame
---@field ModelScene ModelScene|ModelSceneMixin
---@field owner? Frame  # the frame whose tooltip the preview belongs to
---@field itemID? integer
---@field playerReady? boolean  # the actor has the character's current model and gear
---@field yaw? number  # the actor's facing as the scene places it
ForeverLootModelPreviewMixin = {}
app.ui.ModelPreviewMixin = ForeverLootModelPreviewMixin

function ForeverLootModelPreviewMixin:OnLoad()
    app.ui.modelPreview = self
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
end

---@param event string
function ForeverLootModelPreviewMixin:OnEvent(event)
    if event == "MODIFIER_STATE_CHANGED" then
        self:Update()
    else
        -- New gear or shape: the actor is built again for the next preview.
        self.playerReady = false
    end
end

-- The tooltip went away without the row noticing (hidden under the cursor, taken by another frame).
function ForeverLootModelPreviewMixin:OnUpdate()
    if not (self.owner and GameTooltip:IsShown() and GameTooltip:IsOwned(self.owner)) then
        self:Clear()
    end
end

-- Follows the tooltip `owner` just opened for an item; call after GameTooltip:Show().
---@param owner Frame
---@param itemID integer
function ForeverLootModelPreviewMixin:SetItem(owner, itemID)
    self.owner, self.itemID = owner, itemID
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    self:Update()
end

function ForeverLootModelPreviewMixin:Clear()
    self.owner, self.itemID = nil, nil
    self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    self:Hide()
end

-- Shown while ctrl is down and the item can be worn visibly (not rings, trinkets, bags, ...).
-- Items the client hasn't cached yet have no link to try on; the view has already asked for them.
function ForeverLootModelPreviewMixin:Update()
    local itemID = self.itemID
    if not (itemID and IsControlKeyDown() and GameTooltip:IsOwned(self.owner)) then
        self:Hide()
        return
    end
    local link = select(2, C_Item.GetItemInfo(itemID))
    if not link or not C_Item.IsDressableItemByID(itemID) then
        self:Hide()
        return
    end
    -- Shown before the actor is set up, as the dressing room does.
    self:Place()
    self:Show()
    if not self:TryOn(link) then
        self:Hide()
    end
end

-- Dresses the character in its own gear plus the item; false when the actor can't wear it.
---@param link string
---@return boolean
function ForeverLootModelPreviewMixin:TryOn(link)
    local scene = self.ModelScene
    if not self.playerReady then
        scene:TransitionToModelSceneID(
            MODEL_SCENE_ID,
            CAMERA_TRANSITION_TYPE_IMMEDIATE,
            CAMERA_MODIFICATION_TYPE_DISCARD,
            true
        )
        local _, inAlternateForm = C_PlayerInfo.GetAlternateFormInfo()
        -- Weapons drawn and visible, so a previewed weapon is in hand.
        SetupPlayerForModelScene(scene, nil, nil, false, true, false, not inAlternateForm)
        local actor = scene:GetPlayerActor()
        self.yaw = actor and actor:GetYaw()
        self.playerReady = true
    end
    local actor = scene:GetPlayerActor()
    if not actor then
        return false
    end
    actor:Dress()
    -- A cloak is seen from behind; everything else from the front, a little from the side.
    local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
    actor:SetYaw((self.yaw or 0) + (equipLoc == "INVTYPE_CLOAK" and math.pi or TURN))
    return actor:TryOn(link) == Enum.ItemTryOnReason.Success
end

-- As wide as the tooltip, below it; above it when the screen ends first.
function ForeverLootModelPreviewMixin:Place()
    local tooltip = GameTooltip
    local room = (tooltip:GetBottom() or 0) * tooltip:GetEffectiveScale()
    self:ClearAllPoints()
    if room >= self:GetHeight() * self:GetEffectiveScale() then
        self:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT")
        self:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT")
    else
        self:SetPoint("BOTTOMLEFT", tooltip, "TOPLEFT")
        self:SetPoint("BOTTOMRIGHT", tooltip, "TOPRIGHT")
    end
end
