---@type string, Spyglass
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
---@class Spyglass.ModelPreview : Frame
---@field ModelScene ModelScene|ModelSceneMixin
---@field owner? Frame  # the frame whose tooltip the preview belongs to
---@field itemID? integer
---@field playerReady? boolean  # the actor has the character's current model and gear
---@field yaw? number  # the actor's facing as the scene places it
SpyglassModelPreviewMixin = {}
app.ui.ModelPreviewMixin = SpyglassModelPreviewMixin

function SpyglassModelPreviewMixin:OnLoad()
    app.ui.modelPreview = self
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    self:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
end

---@param event string
function SpyglassModelPreviewMixin:OnEvent(event)
    if event == "MODIFIER_STATE_CHANGED" then
        self:Update()
    else
        -- New gear or shape: the actor is built again for the next preview.
        self.playerReady = false
    end
end

-- The tooltip went away without the row noticing (hidden under the cursor, taken by another frame).
function SpyglassModelPreviewMixin:OnUpdate()
    if not (self.owner and GameTooltip:IsShown() and GameTooltip:IsOwned(self.owner)) then
        self:Clear()
    end
end

-- Follows the tooltip `owner` just opened for an item; call after GameTooltip:Show().
---@param owner Frame
---@param itemID integer
function SpyglassModelPreviewMixin:SetItem(owner, itemID)
    self.owner, self.itemID = owner, itemID
    self:RegisterEvent("MODIFIER_STATE_CHANGED")
    self:Update()
end

function SpyglassModelPreviewMixin:Clear()
    self.owner, self.itemID = nil, nil
    self:UnregisterEvent("MODIFIER_STATE_CHANGED")
    self:Hide()
end

-- The mount an item teaches, from the item or, when the client doesn't know the item as a mount,
-- from its use spell (needs the item cached).
---@param itemID integer
---@return integer?
local function mountFromItem(itemID)
    if not C_MountJournal then
        return nil
    end
    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if not mountID then
        local spellID = select(2, C_Item.GetItemSpell(itemID))
        mountID = spellID and C_MountJournal.GetMountFromSpell(spellID)
    end
    return mountID
end

-- Shown while ctrl is down and the item is a mount or can be worn visibly (not rings, trinkets,
-- bags, ...). Items the client hasn't cached yet have no link to try on; the view has already
-- asked for them.
function SpyglassModelPreviewMixin:Update()
    local itemID = self.itemID
    if not (itemID and IsControlKeyDown() and GameTooltip:IsOwned(self.owner)) then
        self:Hide()
        return
    end
    local mountID = mountFromItem(itemID)
    if mountID then
        self:Place()
        self:Show()
        if not self:ShowMount(mountID) then
            self:Hide()
        end
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
function SpyglassModelPreviewMixin:TryOn(link)
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

-- The mount on its own in the mount's model scene (the scene the mount journal frames it with);
-- false when the client has no model for it.
---@param mountID integer
---@return boolean
function SpyglassModelPreviewMixin:ShowMount(mountID)
    local creatureDisplayID, _, _, isSelfMount, _, modelSceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
    if not (creatureDisplayID and modelSceneID) then
        return false
    end
    local scene = self.ModelScene
    scene:TransitionToModelSceneID(
        modelSceneID,
        CAMERA_TRANSITION_TYPE_IMMEDIATE,
        CAMERA_MODIFICATION_TYPE_DISCARD,
        true
    )
    -- The dressing room's actor is gone; the next item preview sets it up again.
    self.playerReady = false
    local actor = scene:GetActorByTag("unwrapped")
    if not actor then
        return false
    end
    actor:SetModelByCreatureDisplayID(creatureDisplayID)
    if isSelfMount then
        actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.None)
        actor:SetAnimation(618) -- MountSelfIdle
    else
        actor:SetAnimationBlendOperation(Enum.ModelBlendOperation.Anim)
        actor:SetAnimation(0)
    end
    return true
end

-- As wide as the tooltip, below it; above it when the screen ends first.
function SpyglassModelPreviewMixin:Place()
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
