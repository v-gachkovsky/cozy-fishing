local _, ns = ...
local L = ns.L

------------------------------------------------------------------------
-- Moving: modifier + left-drag
------------------------------------------------------------------------
ns.MOVE_MODES = {
    { value = "alt",   text = "Alt + left-drag" },
    { value = "ctrl",  text = "Ctrl + left-drag" },
    { value = "shift", text = "Shift + left-drag" },
    { value = "meta",  text = "Cmd + left-drag", mac = true },
}

local modifierDown = {
    alt   = function() return IsAltKeyDown() end,
    ctrl  = function() return IsControlKeyDown() end,
    shift = function() return IsShiftKeyDown() end,
    meta  = function() return IsMetaKeyDown and IsMetaKeyDown() end,
}

function ns.GetMoveModes()
    local list = {}
    for _, m in ipairs(ns.MOVE_MODES) do
        if not m.mac or (IsMacClient and IsMacClient()) then list[#list + 1] = m end
    end
    return list
end

function ns.MoveModeText()
    for _, m in ipairs(ns.MOVE_MODES) do
        if m.value == ns.db.moveWith then return L[m.text] end
    end
    return L["Alt + left-drag"]
end

-- Positions are kept in UIParent units, so a frame's own scale doesn't move it around.
local function Ratio(frame) return frame:GetEffectiveScale() / UIParent:GetEffectiveScale() end

local function Round(v) return math.floor(v * 10 + 0.5) / 10 end

-- frame.anchor = "TOPLEFT" keeps the top left corner (the grid grows down and right with its content);
-- other frames keep their center.
function ns.SavePoint(frame, cfg)
    local k = Ratio(frame)
    local ux, uy = UIParent:GetCenter()
    if frame.anchor == "TOPLEFT" then
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left then return end
        cfg.point = { "TOPLEFT", "CENTER", Round(left * k - ux), Round(top * k - uy) }
    else
        local cx, cy = frame:GetCenter()
        if not cx then return end
        cfg.point = { "CENTER", "CENTER", Round(cx * k - ux), Round(cy * k - uy) }
    end
end

function ns.ApplyPoint(frame, point)
    if frame.moving or frame.sizing or not point then return end
    if frame:IsProtected() and InCombatLockdown() then return end
    local k = Ratio(frame)
    frame:ClearAllPoints()
    frame:SetPoint(point[1], UIParent, point[2], point[3] / k, point[4] / k)
end

ns.movables = {}

-- getCfg() returns the settings table holding `point` and `locked`.
function ns.MakeMovable(frame, getCfg)
    frame.getCfg = getCfg
    table.insert(ns.movables, frame)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if getCfg().locked then return end
        if self:IsProtected() and InCombatLockdown() then return end
        local down = modifierDown[ns.db.moveWith]
        if down and not down() then return end
        self.moving = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self:StopMovingOrSizing()
        self.moving = nil
        if self.SetUserPlaced then self:SetUserPlaced(false) end
        local cfg = getCfg()
        ns.SavePoint(self, cfg)
        ns.ApplyPoint(self, cfg.point)
    end)
end

------------------------------------------------------------------------
-- Resizing: a grip in the bottom right corner, shown on hover while the frame is unlocked.
-- o.get() / o.set(v) read and write the size value (pixels for the icon, scale for the grid),
-- o.min / o.max bound it, o.apply() redraws the frame. The top left corner stays in place.
------------------------------------------------------------------------
function ns.MakeGrip(frame, o)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", 2, -2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:Hide()

    local startX, startY, startW, startV, left, top

    local function Pin()
        local es = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / es, top / es)
    end

    local function Stop()
        if not frame.sizing then return end
        grip:SetScript("OnUpdate", nil)
        frame.sizing = nil
        local cfg = frame.getCfg()
        ns.SavePoint(frame, cfg)
        ns.ApplyPoint(frame, cfg.point)
        if ns.RefreshOptions then ns.RefreshOptions() end
    end

    local function Step()
        if not IsMouseButtonDown("LeftButton") then return Stop() end
        local x, y = GetCursorPosition()
        local d = ((x - startX) + (startY - y)) / 2
        local v = startV * math.max(0.05, (startW + d) / startW)
        o.set(math.max(o.min, math.min(o.max, v)))
        o.apply()
        Pin()
    end

    grip:SetScript("OnMouseDown", function()
        if frame:IsProtected() and InCombatLockdown() then return end
        local es = frame:GetEffectiveScale()
        left, top = frame:GetLeft() * es, frame:GetTop() * es
        startW = math.max(1, frame:GetWidth() * es)
        startX, startY = GetCursorPosition()
        startV = o.get()
        frame.sizing = true
        Pin()
        grip:SetScript("OnUpdate", Step)
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Drag to resize"])
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", GameTooltip_Hide)
    frame.grip = grip
    return grip
end

-- Whether the cursor is over the frame, also with its mouse turned off. Newer clients dropped the global
-- MouseIsOver(); frames have :IsMouseOver() instead.
function ns.IsMouseOver(f)
    if f.IsMouseOver then return f:IsMouseOver() and true or false end
    if MouseIsOver then return MouseIsOver(f) and true or false end
    return false
end

-- Grips show while the mouse is over an unlocked frame.
local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.1 then return end
    elapsed = 0
    if InCombatLockdown() then return end
    for _, f in ipairs(ns.movables) do
        local grip = f.grip
        if grip then
            local want = f:IsVisible() and not f.getCfg().locked and (f.sizing or ns.IsMouseOver(f)) or false
            if want ~= grip:IsShown() then grip:SetShown(want) end
        end
    end
end)

-- An outlined font for texts on screen. A font set with SetFont covers one file's letters only, and the game's
-- Latin font has no Cyrillic, so the text gets a font family that takes the other alphabets from the game's own
-- fonts. Clients without font families switch to the Cyrillic file of Friz Quadrata for any language but English.
local ALPHABETS = {
    { alphabet = "russian",            file = "Fonts\\FRIZQT___CYR.TTF" },
    { alphabet = "korean",             file = "Fonts\\2002.TTF" },
    { alphabet = "simplifiedchinese",  file = "Fonts\\ARKai_T.ttf" },
    { alphabet = "traditionalchinese", file = "Fonts\\blei00d.TTF" },
}
local families = {}

local function Family(size)
    if families[size] ~= nil then return families[size] end
    local members = { { alphabet = "roman", file = STANDARD_TEXT_FONT, height = size, flags = "OUTLINE" } }
    for _, a in ipairs(ALPHABETS) do
        members[#members + 1] = { alphabet = a.alphabet, file = a.file, height = size, flags = "OUTLINE" }
    end
    local ok, f = pcall(CreateFontFamily, "CozyFishingFont" .. size, members)
    families[size] = ok and f or false
    return families[size]
end

function ns.SetOutlineFont(fs, size)
    local family = CreateFontFamily and Family(size)
    if family then
        fs:SetFontObject(family)
        return
    end
    local file = (ns.db and ns.db.locale ~= "enUS") and "Fonts\\FRIZQT___CYR.TTF" or STANDARD_TEXT_FONT
    if fs:SetFont(file, size, "OUTLINE") == false then fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE") end
end
