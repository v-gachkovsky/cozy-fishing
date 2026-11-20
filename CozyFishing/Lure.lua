local _, ns = ...
local L = ns.L

-- The lure reminder: while a fishing pole without a lure is in hand and a lure is in the bags, a small button
-- by the hook puts the best of them on (a secure macro: use the lure, then the main hand). The pole's lure is
-- read from the game's weapon enchant; a lure wearing off has no event of its own, so a ticker checks it.
local Lure = {}
ns.Lure = Lure

local MAINHAND = INVSLOT_MAINHAND or 16
-- Best first. skill: the Fishing skill the lure needs.
Lure.LURES = {
    { id = 6533, bonus = 100, skill = 100 }, -- Aquadynamic Fish Attractor
    { id = 34861, bonus = 100, skill = 100 }, -- Sharpened Fish Hook (later clients)
    { id = 6532, bonus = 75, skill = 100 }, -- Bright Baubles
    { id = 7307, bonus = 75, skill = 100 }, -- Flesh Eating Worm
    { id = 6811, bonus = 50, skill = 50 }, -- Aquadynamic Fish Lens
    { id = 6530, bonus = 50, skill = 50 }, -- Nightcrawlers
    { id = 6529, bonus = 25, skill = 1 }, -- Shiny Bauble
}

local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)

local btn
local current -- the lure the button puts on now

local function Cfg() return ns.db.icon end

-- Whether the pole has a lure on, and for how many more seconds.
function Lure.OnPole()
    if not GetWeaponEnchantInfo then return false end
    local has, ms = GetWeaponEnchantInfo()
    if ns.IsSecret(has) then return false end
    return has and true or false, (type(ms) == "number" and not ns.IsSecret(ms)) and ms / 1000 or nil
end

-- The best lure in the bags that the character's skill allows, or nil.
function Lure.Best()
    if not GetItemCount then return nil end
    local rank = ns.skill and ns.skill.rank
    for _, lure in ipairs(Lure.LURES) do
        if (not rank or rank >= lure.skill) and (GetItemCount(lure.id) or 0) > 0 then return lure end
    end
end

local function Wanted()
    if not (Cfg().enabled and Cfg().lure and ns.session) then return nil end
    if Lure.OnPole() then return nil end
    return Lure.Best()
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if current then
        GameTooltip:SetItemByID(current.id)
        GameTooltip:AddLine(" ")
    end
    GameTooltip:AddLine(L["No lure on the fishing pole."], 1, 0.82, 0)
    GameTooltip:AddLine(L["Click: put this lure on"], 0.9, 0.8, 0.5)
    GameTooltip:Show()
end

function Lure:Create()
    local parent = _G.CozyFishingIcon
    btn = CreateFrame("Button", "CozyFishingLure", parent, "SecureActionButtonTemplate")
    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    btn:SetAttribute("type1", "macro")
    btn:Hide()

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(1, 0.82, 0, 0.9)
    border:SetDrawLayer("BACKGROUND")
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- A slow pulse, so it's noticed without being in the way.
    local pulse = btn:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.9)
    btn.pulse = pulse

    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    -- The lure wearing off has no event: a look every second while the session lasts.
    local ticker = CreateFrame("Frame")
    local t = 0
    ticker:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 1 then return end
        t = 0
        if ns.session then Lure:Refresh() end
    end)
end

-- A secure button can't change in combat; the end of combat calls this again.
function Lure:Refresh()
    if not btn or InCombatLockdown() then return end
    local lure = Wanted()
    if lure ~= current then
        current = lure
        if lure then
            btn:SetAttribute("macrotext1", ("/use item:%d\n/use %d"):format(lure.id, MAINHAND))
            btn.icon:SetTexture(ns.ItemIcon(lure.id))
        end
    end
    local size = math.max(14, math.floor(Cfg().size * 0.42 + 0.5))
    btn:SetSize(size, size)
    btn:ClearAllPoints()
    -- On the right side, out of the way of the cast timer over the hook.
    btn:SetPoint("LEFT", btn:GetParent(), "RIGHT", 2, 0)
    if lure then
        btn:Show()
        if not btn.pulse:IsPlaying() then btn.pulse:Play() end
    else
        btn.pulse:Stop()
        btn:Hide()
    end
end

-- Shown now (for the tests and the icon's tooltip).
function Lure:Current() return btn and btn:IsShown() and current or nil end
