local _, ns = ...
local L = ns.L

-- A round button on the minimap edge: left-click opens the settings, right-click shows the frames for placing.
-- Drag it around the edge.
local Minimap_ = {}
ns.Minimap = Minimap_

-- The round logo in Media\logo.tga, a little off the texture's center.
local LOGO_COORDS = { 0.059, 0.926, 0.057, 0.924 }

local button

local function Cfg() return ns.db.minimap end

local function UpdatePosition()
    local angle = math.rad(Cfg().angle)
    local r = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    Cfg().angle = math.floor(math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360 + 0.5)
    UpdatePosition()
end

function Minimap_:Create()
    local b = CreateFrame("Button", "CozyFishingMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ns.LOGO)
    icon:SetTexCoord(unpack(LOGO_COORDS))

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            ns.SetPlacing(not ns.placing)
            ns.Print(ns.placing and L["frames shown for placing."] or L["frames shown only with a fishing pole again."])
        else
            ns.OpenOptions()
        end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Cozy Fishing", 0.31, 0.76, 0.97)
        GameTooltip:AddLine(L["Left-click: settings"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: show or hide the frames for placing"], 1, 1, 1)
        local s = ns.session
        if s then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Caught: %d"]:format(s.total), 1, 0.82, 0)
        end
        GameTooltip:AddLine(L["Drag to move around the minimap"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    button = b
end

function Minimap_:Refresh()
    if not button then return end
    UpdatePosition()
    button:SetShown(not Cfg().hide)
end
