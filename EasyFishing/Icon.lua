local _, ns = ...
local L = ns.L

-- The fishing hook. A secure button: a left click casts Fishing (a macro, so it can clear the target first).
-- A click on a UI frame never reaches the game's key bindings, so while the line is out the icon stops taking
-- the mouse: clicks on it land in the game world, and while the cursor is over the icon the world's mouse
-- buttons are bound for us: the right one (BUTTON2) to Interact with Target, which reels in the soft-targeted
-- bobber, the left one (BUTTON1) to a click on the icon, which casts again. Out of that, only plain clicks
-- act: a click with the "move" modifier only moves the icon.
local Icon = {}
ns.Icon = Icon

local btn, hookOwner
local hookBound = false
local pending = false
local driver

local function Cfg() return ns.db.icon end

-- Debug lines go to chat and to EasyFishingDB.debugLog (the last 500), to read from the saved file after a reload.
local LOG_SIZE = 500
local function Trace(fmt, ...)
    if not ns.db.debug then return end
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    ns.Print("|cff999999[debug]|r " .. text)
    local log = ns.db.debugLog or {}
    ns.db.debugLog = log
    log[#log + 1] = date("%H:%M:%S ") .. text
    while #log > LOG_SIZE do table.remove(log, 1) end
end
ns.Trace = Trace

local function Safe(v)
    if ns.IsSecret(v) then return "<secret>" end
    return tostring(v)
end

-- What the game has as the soft interact target now (the bobber, when soft targeting found it).
function ns.SoftInteractText()
    local ok, guid = pcall(UnitGUID, "softinteract")
    local ok2, name = pcall(UnitName, "softinteract")
    return ("%s (%s)"):format(ok2 and Safe(name) or "?", ok and Safe(guid) or "?")
end

local function SetHookBinding(on)
    if on == hookBound or InCombatLockdown() then return end
    if on then
        SetOverrideBinding(hookOwner, true, "BUTTON2", "INTERACTTARGET")
        SetOverrideBindingClick(hookOwner, true, "BUTTON1", "EasyFishingIcon", "LeftButton")
        Trace("hook armed: right click = %s, soft target: %s", Safe(GetBindingAction("BUTTON2", true)), ns.SoftInteractText())
    else
        ClearOverrideBindings(hookOwner)
        Trace("hook disarmed")
    end
    hookBound = on
end

-- The game's gear cursor (the one over things you can use) while the mouse is over the icon.
local GEAR_CURSOR = "INTERACT_CURSOR"
local gearShown = false

local function SetGearCursor(on)
    if on then
        SetCursor(GEAR_CURSOR)
    elseif gearShown then
        ResetCursor()
    end
    gearShown = on
end

local function HookTick(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.05 then return end
    self.t = 0
    local over = btn:IsVisible() and ns.IsMouseOver(btn) or false
    SetHookBinding(over)
    -- On clients where the icon takes no mouse at all while the line is out, the game sets the world's cursor over it.
    SetGearCursor(over)
    if ns.db.debug then
        local soft = ns.SoftInteractText()
        if soft ~= self.lastSoft then
            self.lastSoft = soft
            Trace("soft target changed: %s", soft)
        end
    end
end

-- While the line is out, clicks on the icon must reach the world (and the bindings), so the icon stops taking
-- clicks. It keeps taking mouse motion where the client allows that: the cursor then stays over the UI, where our
-- gear cursor holds, instead of the world's, which the game sets anew every frame.
local function ApplyMouse()
    if btn.SetMouseClickEnabled and btn.SetMouseMotionEnabled then
        btn:EnableMouse(true)
        btn:SetMouseMotionEnabled(true)
        btn:SetMouseClickEnabled(not ns.reeling)
    else
        btn:EnableMouse(not ns.reeling)
    end
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.FishingName(), 1, 1, 1)
    GameTooltip:AddLine(L["Left-click: cast"], 0.9, 0.8, 0.5)
    GameTooltip:AddLine(L["Right-click: hook the fish (while the line is out)"], 0.9, 0.8, 0.5)
    if not ns.FishingKnown() then
        GameTooltip:AddLine(L["You haven't learned Fishing yet."], 1, 0.3, 0.3)
    end
    if not Cfg().locked then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["%s to move, the corner to resize"]:format(ns.MoveModeText()), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- The bobber cursor has the mouse pointer's arrow in its top left corner. The hook is drawn from two pieces of
-- the texture that leave out only that corner: everything right of CUT_X, and the strip below CUT_Y left of it.
local CUT_X, CUT_Y = 0.25, 0.3

local function HookPieces(parent, layer, texture, whole)
    local a = parent:CreateTexture(nil, layer)
    a:SetTexture(texture)
    local p = { a }
    if not whole then
        a:SetTexCoord(CUT_X, 1, 0, 1)
        local b = parent:CreateTexture(nil, layer)
        b:SetTexture(texture)
        b:SetTexCoord(0, CUT_X, CUT_Y, 1)
        p[2] = b
    end
    function p.Layout(w, h)
        a:ClearAllPoints()
        if not p[2] then
            a:SetAllPoints(parent)
            return
        end
        a:SetPoint("TOPLEFT", parent, "TOPLEFT", w * CUT_X, 0)
        a:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
        local b = p[2]
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -h * CUT_Y)
        b:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", w * CUT_X, 0)
    end
    function p.Each(method, ...)
        for _, t in ipairs(p) do t[method](t, ...) end
    end
    return p
end

function Icon:Create()
    btn = CreateFrame("Button", "EasyFishingIcon", UIParent, "SecureActionButtonTemplate")
    btn:SetFrameStrata("MEDIUM")
    btn:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    btn:SetAttribute("type1", "macro")
    btn:Hide()

    -- Everything drawn sits on `art`, a plain frame over the button.
    local art = CreateFrame("Frame", nil, btn)
    art:SetAllPoints(btn)
    btn.art = art

    local probe = art:CreateTexture()
    local texture, whole = ns.HOOK_TEXTURE, false
    if probe:SetTexture(texture) == false then texture, whole = ns.FISHING_ICON, true end
    probe:Hide()

    btn.hook = HookPieces(art, "ARTWORK", texture, whole)
    btn.hover = HookPieces(art, "OVERLAY", texture, whole)
    btn.hover.Each("SetBlendMode", "ADD")
    btn.hover.Each("SetAlpha", 0.5)
    btn.hover.Each("Hide")

    -- A gold pulse while the line is out: a right click now hooks.
    local glow = CreateFrame("Frame", nil, art)
    glow:SetAllPoints(art)
    glow:SetAlpha(0)
    btn.glow = HookPieces(glow, "OVERLAY", texture, whole)
    btn.glow.Each("SetBlendMode", "ADD")
    btn.glow.Each("SetVertexColor", 1, 0.8, 0.2)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(0.8)
    a:SetDuration(0.6)
    pulse:SetScript("OnStop", function() glow:SetAlpha(0) end)
    btn.pulse = pulse

    local function Layout()
        local w, h = btn:GetSize()
        btn.hook.Layout(w, h)
        btn.hover.Layout(w, h)
        btn.glow.Layout(w, h)
    end
    btn:HookScript("OnSizeChanged", Layout)
    Layout()

    btn:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.hook.Each("SetVertexColor", 0.65, 0.65, 0.65) end
    end)
    btn:HookScript("OnMouseUp", function(self) self.hook.Each("SetVertexColor", 1, 1, 1) end)
    btn:SetScript("OnEnter", function(self)
        self.hover.Each("Show")
        SetGearCursor(true)
        Tooltip(self)
    end)
    btn:SetScript("OnLeave", function(self)
        self.hover.Each("Hide")
        SetGearCursor(false)
        GameTooltip:Hide()
    end)

    ns.MakeMovable(btn, Cfg)
    ns.MakeGrip(btn, {
        get = function() return Cfg().size end,
        set = function(v) Cfg().size = math.floor(v + 0.5) end,
        min = 16, max = 160,
        apply = function() Icon:Refresh() end,
    })

    hookOwner = CreateFrame("Frame")
    hookOwner:Hide()
    hookOwner:SetScript("OnUpdate", HookTick)
end

-- Shows with a fishing pole in hand. A state driver, so it also follows a weapon swap in combat.
local function VisibilityRule()
    local cfg = Cfg()
    if not cfg.enabled then return "hide" end
    if ns.placing then return "show" end
    return ("[equipped:%s] show; hide"):format(ns.PoleTypeName())
end

function Icon:Refresh()
    if not btn then return end
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local cfg = Cfg()
    btn:SetSize(cfg.size, cfg.size)
    ns.ApplyPoint(btn, cfg.point)
    local macro = "/cast " .. ns.FishingName()
    if cfg.clearTarget then macro = "/cleartarget [nocombat]\n" .. macro end
    btn:SetAttribute("macrotext1", macro)
    btn.hook.Each("SetDesaturated", not ns.FishingKnown())
    ApplyMouse()
    local rule = VisibilityRule()
    if rule ~= driver then
        RegisterStateDriver(btn, "visibility", rule)
        driver = rule
    end
end

function Icon:SetReeling(on)
    ns.reeling = on or nil
    if ns.db.debug then
        local function cv(name) local ok, v = pcall(GetCVar, name) return ok and tostring(v) or "?" end
        Trace("line %s, soft target: %s, SoftTargetInteract=%s Arc=%s Range=%s", on and "out" or "in",
            ns.SoftInteractText(), cv("SoftTargetInteract"), cv("SoftTargetInteractArc"), cv("SoftTargetInteractRange"))
    end
    if hookOwner then hookOwner.lastSoft = nil end
    if not btn then return end
    -- The icon's mouse changes when the line goes out or comes in, so its hover look may not get an OnLeave.
    btn.hover.Each("Hide")
    if on then
        btn.pulse:Play()
        hookOwner:Show()
    else
        btn.pulse:Stop()
        hookOwner:Hide()
        SetHookBinding(false)
    end
    if not InCombatLockdown() then ApplyMouse() end
    SetGearCursor(btn:IsVisible() and ns.IsMouseOver(btn) or false)
end

-- Right before combat lockdown: the last moment the binding can be taken back.
function Icon:EnterCombat()
    if hookOwner then hookOwner:Hide() end
    if ns.reeling then SetGearCursor(false) end
    if hookBound then
        ClearOverrideBindings(hookOwner)
        hookBound = false
    end
end

function Icon:LeaveCombat()
    if not btn then return end
    if pending then self:Refresh() end
    ApplyMouse()
    if ns.reeling then hookOwner:Show() end
end
