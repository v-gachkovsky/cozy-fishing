local _, ns = ...
local L = ns.L

-- The catch of the session: the total on top, the Fishing skill under it, then one cell per kind of item (in
-- the order first caught) with how many of it. A right click on a cell dims that item (junk) and puts it at
-- the end; another one brings it back (ns.db.hidden). Every item caught is always shown.
-- No background unless one is set, so it sits over the world like the icon.
local Grid = {}
ns.Grid = Grid

local CELL, GAP, TITLE, SKILL_LINE = 32, 3, 18, 15
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
    if not c.sample then
        GameTooltip:AddLine(c.dim and L["Right-click: bring it back"] or L["Right-click: dim it and put it at the end (junk)"],
            0.6, 0.6, 0.6)
    end
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
    c:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" or self.sample then return end
        ns.SetHidden(self.id, not ns.db.hidden[self.id])
        if GameTooltip:IsOwned(self) then Cell_OnEnter(self) end
    end)
    cells[i] = c
    return c
end

function Grid:Create()
    frame = CreateFrame("Frame", "CozyFishingGrid", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(CELL, TITLE)
    frame.anchor = "TOPLEFT"
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", -4, 4)
    frame.bg:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.bg:SetColorTexture(0, 0, 0, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", 0, -1)

    -- The skill line, with a tooltip that says what the numbers are.
    local skill = CreateFrame("Frame", nil, frame)
    skill:SetPoint("TOPLEFT", 0, -TITLE)
    skill:SetSize(CELL, SKILL_LINE - 2)
    skill:EnableMouse(true)
    skill.text = skill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    skill.text:SetPoint("LEFT")
    skill:SetScript("OnEnter", function(self)
        local sk = ns.skill
        if not sk then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.FishingName(), 1, 1, 1)
        GameTooltip:AddLine(L["Skill: %d of %d"]:format(sk.rank, sk.max), 0.9, 0.8, 0.5)
        if sk.bonus > 0 then
            GameTooltip:AddLine(L["+%d from the fishing pole and the lure"]:format(sk.bonus), 0.4, 0.8, 1)
        end
        local gain = ns.SkillGain()
        if gain > 0 then GameTooltip:AddLine(L["+%d this session"]:format(gain), 0.25, 1, 0.25) end
        GameTooltip:Show()
    end)
    skill:SetScript("OnLeave", GameTooltip_Hide)
    skill:RegisterForDrag("LeftButton")
    skill:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
    skill:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
    frame.skill = skill

    ns.MakeMovable(frame, Cfg)
    ns.MakeGrip(frame, {
        get = function() return Cfg().scale end,
        set = function(v) Cfg().scale = math.floor(v * 20 + 0.5) / 20 end,
        min = 0.5, max = 3,
        apply = function() Grid:Refresh() end,
    })
end

-- Skill points gained this session.
function ns.SkillGain()
    local s, sk = ns.session, ns.skill
    if not (s and sk and s.skillStart) then return 0 end
    return math.max(0, sk.rank - s.skillStart)
end

function ns.SetHidden(id, hidden)
    ns.db.hidden[id] = hidden or nil
    ns.Grid:Refresh()
    ns.HistoryWindow:Refresh()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.HiddenCount()
    local n = 0
    for _ in pairs(ns.db.hidden) do n = n + 1 end
    return n
end

-- The cells to show and the total caught: every item, the dimmed ones (junk) at the end.
local function Entries()
    local s = ns.session
    if s and #s.order > 0 then
        local list, dimmed = {}, {}
        for _, id in ipairs(s.order) do
            local e = s.items[id]
            local dim = ns.db.hidden[id] and true or false
            table.insert(dim and dimmed or list, { id = id, count = e.count, icon = e.icon, dim = dim })
        end
        for _, e in ipairs(dimmed) do list[#list + 1] = e end
        return list, s.total
    end
    if not s and ns.placing then
        local total = 0
        for _, e in ipairs(SAMPLE) do total = total + e.count end
        return SAMPLE, total, true
    end
    return {}, s and s.total or 0
end

local function SkillText()
    local sk = ns.skill
    if not sk then return nil end
    local text = ("%s %d/%d"):format(ns.FishingName(), sk.rank, sk.max)
    if sk.bonus > 0 then text = text .. (" |cff66ccff+%d|r"):format(sk.bonus) end
    local gain = ns.SkillGain()
    if gain > 0 then text = text .. ("  |cff40ff40%s|r"):format(L["+%d this session"]:format(gain)) end
    return text
end

-- The item IDs shown now (for the tests).
function Grid.Shown()
    local ids = {}
    for _, c in ipairs(cells) do
        if c:IsShown() then ids[#ids + 1] = c.id end
    end
    return ids
end

function Grid:Refresh()
    if not frame then return end
    local cfg = Cfg()
    local show = cfg.enabled and (ns.session ~= nil or ns.placing) or false
    frame:SetShown(show)
    if not show then return end

    local list, total, sample = Entries()
    -- Set on every refresh: without font families the font file follows the language.
    ns.SetOutlineFont(frame.title, 13)
    frame.title:SetTextColor(1, 0.82, 0)
    frame.title:SetText(L["Caught: %d"]:format(total))

    local skillText = cfg.skill and SkillText()
    local header = TITLE
    if skillText then
        ns.SetOutlineFont(frame.skill.text, 11)
        frame.skill.text:SetText(skillText)
        frame.skill:SetWidth(math.max(CELL, frame.skill.text:GetStringWidth() + 2))
        frame.skill:Show()
        header = TITLE + SKILL_LINE
    else
        frame.skill:Hide()
    end

    local cols = math.max(1, cfg.columns)
    local n = #list
    for i, e in ipairs(list) do
        local c = GetCell(i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", col * (CELL + GAP), -(header + row * (CELL + GAP)))
        c.id, c.n, c.sample, c.dim = e.id, e.count, sample, e.dim
        c.icon:SetTexture(e.icon or ns.ItemIcon(e.id))
        c.icon:SetDesaturated(e.dim or false)
        c:SetAlpha(e.dim and 0.45 or 1)
        c.count:SetText(e.count)
        c:Show()
    end
    for i = n + 1, #cells do cells[i]:Hide() end

    local usedCols = math.min(cols, n)
    local rows = math.ceil(n / cols)
    local width = math.max(frame.title:GetStringWidth() + 2, usedCols * (CELL + GAP) - GAP)
    if skillText then width = math.max(width, frame.skill:GetWidth()) end
    local height = header + (rows > 0 and rows * (CELL + GAP) - GAP or 0)
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
