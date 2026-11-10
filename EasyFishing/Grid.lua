local _, ns = ...
local L = ns.L

-- The catch of the session: the total on top, then one cell per kind of item (in the order first caught)
-- with how many of it. No background unless one is set, so it sits over the world like the icon.
local Grid = {}
ns.Grid = Grid

local CELL, GAP, HEADER = 32, 3, 18
-- Shown while placing the frames without a session, to see the size.
local SAMPLE = {
    { id = 6291, count = 7 }, -- Raw Brilliant Smallfish
    { id = 6303, count = 4 }, -- Raw Slitherskin Mackerel
    { id = 6358, count = 2 }, -- Oily Blackmouth
    { id = 6359, count = 1 }, -- Firefin Snapper
}

local frame
local cells = {}

local function Cfg() return ns.db.grid end

local function Cell_OnEnter(c)
    GameTooltip:SetOwner(c, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(c.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Caught this session: %d"]:format(c.n), 0.9, 0.8, 0.5)
    if not Cfg().locked then GameTooltip:AddLine(L["%s to move, the corner to resize"]:format(ns.MoveModeText()), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function GetCell(i)
    local c = cells[i]
    if c then return c end
    c = CreateFrame("Frame", nil, frame)
    c:SetSize(CELL, CELL)
    c:EnableMouse(true)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetAllPoints()
    c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    c.count = c:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    c.count:SetPoint("BOTTOMRIGHT", -1, 2)
    -- Dragging a cell moves the whole grid.
    c:RegisterForDrag("LeftButton")
    c:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
    c:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
    c:SetScript("OnEnter", Cell_OnEnter)
    c:SetScript("OnLeave", GameTooltip_Hide)
    cells[i] = c
    return c
end

function Grid:Create()
    frame = CreateFrame("Frame", "EasyFishingGrid", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(CELL, HEADER)
    frame.anchor = "TOPLEFT"
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", -4, 4)
    frame.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.bg:SetColorTexture(0, 0, 0, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 0, -1)

    ns.MakeMovable(frame, Cfg)
    ns.MakeGrip(frame, {
        get = function() return Cfg().scale end,
        set = function(v) Cfg().scale = math.floor(v * 20 + 0.5) / 20 end,
        min = 0.5, max = 3,
        apply = function() Grid:Refresh() end,
    })
end

local function Entries()
    local s = ns.session
    if s and #s.order > 0 then
        local list = {}
        for _, id in ipairs(s.order) do
            local e = s.items[id]
            list[#list + 1] = { id = id, count = e.count, icon = e.icon }
        end
        return list, s.total
    end
    if not s and ns.placing then
        local total = 0
        for _, e in ipairs(SAMPLE) do total = total + e.count end
        return SAMPLE, total
    end
    return {}, s and s.total or 0
end

function Grid:Refresh()
    if not frame then return end
    local cfg = Cfg()
    local show = cfg.enabled and (ns.session ~= nil or ns.placing) or false
    frame:SetShown(show)
    if not show then return end

    local list, total = Entries()
    -- Set on every refresh: without font families the font file follows the language.
    ns.SetOutlineFont(frame.title, 13)
    frame.title:SetTextColor(1, 0.82, 0)
    frame.title:SetText(L["Caught: %d"]:format(total))

    local cols = math.max(1, cfg.columns)
    local n = #list
    for i, e in ipairs(list) do
        local c = GetCell(i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", col * (CELL + GAP), -(HEADER + row * (CELL + GAP)))
        c.id, c.n = e.id, e.count
        c.icon:SetTexture(e.icon or ns.ItemIcon(e.id))
        c.count:SetText(e.count)
        c:Show()
    end
    for i = n + 1, #cells do cells[i]:Hide() end

    local usedCols = math.min(cols, n)
    local rows = math.ceil(n / cols)
    local width = math.max(frame.title:GetStringWidth() + 2, usedCols * (CELL + GAP) - GAP)
    local height = HEADER + (rows > 0 and rows * (CELL + GAP) - GAP or 0)
    frame:SetSize(width, height)
    frame:SetScale(cfg.scale)

    -- A faint background while placing, so the edges show.
    local bg = cfg.bgAlpha / 100
    if ns.placing then bg = math.max(bg, 0.3) end
    frame.bg:SetAlpha(bg)
    frame.bg:SetShown(bg > 0)

    -- Locked: the empty parts let clicks through to the world; cells keep their tooltips.
    frame:EnableMouse(not cfg.locked)
    ns.ApplyPoint(frame, cfg.point)
end
