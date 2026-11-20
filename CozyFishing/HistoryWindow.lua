local _, ns = ...
local L = ns.L

-- The history window (/cf history): what was caught in each zone over all sessions, the past sessions, the
-- fishing trips; and a trip's report (shown when a trip ends, or from its line). Item icons have the item's
-- tooltip; a right click dims an item in the catch (junk), or brings it back.
local HistoryWindow = {}
ns.HistoryWindow = HistoryWindow

local WIDTH, HEIGHT = 480, 500
local INNER = WIDTH - 64 -- the width of the scrolled content
local ICON, ICON_GAP = 26, 3
local PER_ROW = math.floor((INNER + ICON_GAP) / (ICON + ICON_GAP))
local SESSION_ICONS = PER_ROW * 2 -- a session shows at most two rows of items

local frame, content, tabs, summary
local tab = "zones"
local shownTrip -- the trip on the "trip" page
local texts, icons, buttons = {}, {}, {}
local usedTexts, usedIcons, usedButtons = 0, 0, 0

------------------------------------------------------------------------
-- Pieces (reused on every refresh)
------------------------------------------------------------------------
local function Text(template, x, y, width)
    usedTexts = usedTexts + 1
    local fs = texts[usedTexts]
    if not fs then
        fs = content:CreateFontString(nil, "ARTWORK")
        texts[usedTexts] = fs
    end
    fs:SetFontObject(template)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetWidth(width or 0)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(1, 1, 1)
    fs:Show()
    return fs
end

local function SmallButton(x, y, label, onClick)
    usedButtons = usedButtons + 1
    local b = buttons[usedButtons]
    if not b then
        b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        b:SetSize(90, 20)
        buttons[usedButtons] = b
    end
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    b:Show()
    return b
end

local function Icon_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(self.note, 0.9, 0.8, 0.5)
    GameTooltip:AddLine(ns.db.hidden[self.id] and L["Right-click: bring it back"]
        or L["Right-click: dim it and put it at the end (junk)"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Icon_OnMouseUp(self, button)
    if button ~= "RightButton" then return end
    ns.SetHidden(self.id, not ns.db.hidden[self.id])
    if GameTooltip:IsOwned(self) then Icon_OnEnter(self) end
end

local function ItemIcon(x, y, id, count, note)
    usedIcons = usedIcons + 1
    local b = icons[usedIcons]
    if not b then
        b = CreateFrame("Frame", nil, content)
        b:SetSize(ICON, ICON)
        b:EnableMouse(true)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        b.count:SetPoint("BOTTOMRIGHT", -1, 1)
        b:SetScript("OnEnter", Icon_OnEnter)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnMouseUp", Icon_OnMouseUp)
        icons[usedIcons] = b
    end
    b.id, b.note = id, note
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", x, y)
    b.tex:SetTexture(ns.ItemIcon(id))
    local hidden = ns.db.hidden[id] and true or false
    b.tex:SetDesaturated(hidden)
    b:SetAlpha(hidden and 0.45 or 1)
    b.count:SetText(count > 1 and count or "")
    b:Show()
    return b
end

-- Lays out icons from y down, PER_ROW to a row; returns the y under them.
local function Icons(y, items, limit, noteFor)
    local n = math.min(#items, limit or #items)
    for i = 1, n do
        local it = items[i]
        local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
        ItemIcon(col * (ICON + ICON_GAP), y - row * (ICON + ICON_GAP), it.id, it.count, noteFor(it))
    end
    if n == 0 then return y end
    local rows = math.ceil(n / PER_ROW)
    y = y - rows * (ICON + ICON_GAP)
    if #items > n then
        Text("GameFontDisableSmall", 0, y - 1):SetText(L["and %d more"]:format(#items - n))
        y = y - 14
    end
    return y
end

------------------------------------------------------------------------
-- Pages
------------------------------------------------------------------------
local function Percent(part, whole)
    if not whole or whole <= 0 then return 0 end
    return math.floor(part * 100 / whole + 0.5)
end

local function Zones(y)
    local list = ns.History.ZoneList()
    if #list == 0 then
        Text("GameFontDisable", 0, y, INNER):SetText(L["Nothing caught yet. Go fishing!"])
        return y - 20
    end
    for _, z in ipairs(list) do
        local name = Text("GameFontNormal", 0, y, INNER * 0.55)
        name:SetText(z.name)
        name:SetTextColor(1, 0.82, 0)
        local stats = Text("GameFontHighlightSmall", INNER * 0.55, y - 1, INNER * 0.45)
        stats:SetJustifyH("RIGHT")
        stats:SetText(L["%d caught, %d casts"]:format(z.total, z.casts))
        y = y - 16
        local notes = { L["%d%% of casts caught something"]:format(Percent(z.catches, z.casts)) }
        local perHour = ns.History.PerHour(z.catches, z.seconds)
        if perHour then notes[#notes + 1] = L["about %d an hour"]:format(perHour) end
        Text("GameFontDisableSmall", 0, y, INNER):SetText(table.concat(notes, ", "))
        y = y - 15
        y = Icons(y, z.items, nil, function(it)
            return L["Caught here: %d (%d%% of the catch)"]:format(it.count, Percent(it.count, z.total))
        end)
        y = y - 12
    end
    return y
end

-- One session: when, where, how long, the catch.
local function SessionBlock(y, e, live)
    local head = Text("GameFontNormal", 0, y, INNER * 0.7)
    head:SetText(date("%d.%m.%Y %H:%M", e.started) .. "  |cffffffff" .. (e.zone or "") .. "|r"
        .. (live and ("  |cff66ff66" .. L["(going on)"] .. "|r") or ""))
    local minutes = math.max(1, math.floor((e.ended - e.started) / 60 + 0.5))
    local dur = Text("GameFontHighlightSmall", INNER * 0.7, y - 1, INNER * 0.3)
    dur:SetJustifyH("RIGHT")
    dur:SetText(L["%d min"]:format(minutes))
    y = y - 16
    local notes = { L["%d caught, %d casts"]:format(e.total, e.casts) }
    if e.skillFrom and e.skillTo and e.skillTo > e.skillFrom then
        notes[#notes + 1] = L["Fishing %d to %d"]:format(e.skillFrom, e.skillTo)
    end
    Text("GameFontDisableSmall", 0, y, INNER):SetText(table.concat(notes, ", "))
    y = y - 15
    y = Icons(y, e.items, SESSION_ICONS, function(it)
        return L["Caught this session: %d"]:format(it.count)
    end)
    return y - 12
end

local function Sessions(y)
    local list = ns.History.Sessions()
    if #list == 0 then
        Text("GameFontDisable", 0, y, INNER):SetText(L["No finished sessions yet."])
        return y - 20
    end
    for _, e in ipairs(list) do y = SessionBlock(y, e) end
    return y
end

local function TripDates(sum)
    local from = date("%d.%m.%Y %H:%M", sum.started)
    local to = date(date("%d.%m.%Y", sum.ended) == date("%d.%m.%Y", sum.started) and "%H:%M" or "%d.%m.%Y %H:%M",
        sum.ended)
    return from .. " – " .. to
end

local function TripNotes(sum)
    local notes = { L["%d caught, %d casts"]:format(sum.total, sum.casts),
        L["%d%% of casts caught something"]:format(Percent(sum.catches, sum.casts)) }
    local perHour = ns.History.PerHour(sum.catches, sum.seconds)
    if perHour then notes[#notes + 1] = L["about %d an hour"]:format(perHour) end
    return table.concat(notes, ", ")
end

local function Trips(y)
    local list = ns.Trip.List()
    local going = ns.Trip.Active()
    if going then
        Text("GameFontHighlight", 0, y, INNER):SetText("|cff66ff66" .. L["A fishing trip is going on since %s."]:format(
            date("%d.%m.%Y %H:%M", going.started)) .. "|r")
        SmallButton(INNER - 90, y + 3, L["Report"], function() HistoryWindow:ShowTrip(going) end)
        y = y - 26
    end
    if #list == 0 then
        Text("GameFontDisable", 0, y, INNER):SetText(L["No finished fishing trips yet. Start one with the trip button by the hook."])
        return y - 20
    end
    for _, t in ipairs(list) do
        local sum = ns.Trip.Summary(t)
        Text("GameFontNormal", 0, y, INNER - 96):SetText(TripDates(sum))
        SmallButton(INNER - 90, y + 3, L["Report"], function() HistoryWindow:ShowTrip(t) end)
        y = y - 16
        Text("GameFontDisableSmall", 0, y, INNER - 96):SetText(L["%d sessions, %s fishing"]:format(sum.sessions,
            ns.Duration(sum.seconds)) .. ", " .. L["%d caught, %d casts"]:format(sum.total, sum.casts))
        y = y - 17
        y = Icons(y, sum.items, SESSION_ICONS, function(it)
            return L["Caught this trip: %d"]:format(it.count)
        end)
        y = y - 12
    end
    return y
end

-- A trip's report: the totals, everything caught, then each session.
local function TripPage(y)
    local t = shownTrip
    if not t then return y end
    local sum = ns.Trip.Summary(t)
    local head = Text("GameFontNormalLarge", 0, y, INNER)
    head:SetText(TripDates(sum) .. (t.ended and "" or ("  |cff66ff66" .. L["(going on)"] .. "|r")))
    y = y - 24
    local lines = {
        L["Trip: %s, fishing: %s, %d sessions"]:format(ns.Duration(sum.ended - sum.started), ns.Duration(sum.seconds),
            sum.sessions),
        TripNotes(sum),
    }
    if sum.skillFrom and sum.skillTo and sum.skillTo > sum.skillFrom then
        lines[#lines + 1] = L["Fishing %d to %d"]:format(sum.skillFrom, sum.skillTo)
    end
    if #sum.zones > 0 then lines[#lines + 1] = L["Zones: %s"]:format(table.concat(sum.zones, ", ")) end
    for _, line in ipairs(lines) do
        local fs = Text("GameFontHighlight", 0, y, INNER)
        fs:SetText(line)
        y = y - math.max(16, fs:GetStringHeight() + 3)
    end
    y = y - 8
    local caught = Text("GameFontNormal", 0, y, INNER)
    caught:SetText(L["Caught"])
    y = y - 18
    if #sum.items == 0 then
        Text("GameFontDisable", 0, y, INNER):SetText(L["Nothing caught on this trip."])
        y = y - 18
    end
    y = Icons(y, sum.items, nil, function(it)
        return L["Caught this trip: %d (%d%% of the catch)"]:format(it.count, Percent(it.count, sum.total))
    end) - 12
    local sessions = Text("GameFontNormal", 0, y, INNER)
    sessions:SetText(L["Sessions (%d)"]:format(sum.sessions))
    y = y - 20
    for _, e in ipairs(sum.list) do y = SessionBlock(y, e, e == sum.live) end
    return y
end

local PAGES = { zones = Zones, sessions = Sessions, trips = Trips, trip = TripPage }

local function Build()
    for i = 1, usedTexts do texts[i]:Hide() end
    for i = 1, usedIcons do icons[i]:Hide() end
    for i = 1, usedButtons do buttons[i]:Hide() end
    usedTexts, usedIcons, usedButtons = 0, 0, 0
    local y = PAGES[tab](-4)
    content:SetHeight(math.max(1, -y))

    local caught, sessions = 0, #ns.History.Sessions()
    for _, z in pairs(ns.char.zones or {}) do caught = caught + (z.total or 0) end
    summary:SetText(L["Caught in all: %d, sessions: %d"]:format(caught, sessions))
    for key, b in pairs(tabs) do
        b:SetText(L[b.label])
        b:SetEnabled(key ~= tab)
    end
    frame.title:SetText(tab == "trip" and L["Fishing trip"] or L["Fishing history"])
    frame.clear:SetText(L["Clear history"])
end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------
local function Create()
    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", "CozyFishingHistory", UIParent, template)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    frame:Hide()
    tinsert(UISpecialFrames, "CozyFishingHistory") -- Esc closes it

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(24, 24)
    logo:SetPoint("TOPLEFT", 18, -16)
    logo:SetTexture(ns.LOGO)
    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("LEFT", logo, "RIGHT", 6, 0)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    tabs = {}
    local x = 18
    for _, t in ipairs({ { key = "zones", label = "By zone" }, { key = "sessions", label = "Sessions" },
        { key = "trips", label = "Trips" } }) do
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(130, 22)
        b:SetPoint("TOPLEFT", x, -46)
        b.label = t.label
        b:SetScript("OnClick", function() HistoryWindow:SetTab(t.key) end)
        tabs[t.key] = b
        x = x + 136
    end

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -78)
    scroll:SetPoint("BOTTOMRIGHT", -36, 44)
    frame.scroll = scroll
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(INNER, 1)
    scroll:SetScrollChild(content)

    summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("BOTTOMLEFT", 20, 20)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(140, 22)
    clear:SetPoint("BOTTOMRIGHT", -18, 14)
    clear:SetScript("OnClick", function()
        ns.Dialog("COZYFISHING_CLEAR_HISTORY", L["Clear the whole fishing history of this character?"],
            YES or "Yes", function()
                ns.History.Clear()
                HistoryWindow:Refresh()
            end, NO or "No")
    end)
    frame.clear = clear

    frame:SetScript("OnShow", Build)
end

function HistoryWindow:Toggle()
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end

function HistoryWindow:Refresh()
    if frame and frame:IsShown() then Build() end
end

function HistoryWindow:IsShown() return frame ~= nil and frame:IsShown() end

function HistoryWindow:SetTab(key)
    tab = key
    if frame and frame.scroll.SetVerticalScroll then frame.scroll:SetVerticalScroll(0) end
    self:Refresh()
end

-- A trip's report, in the window (opened if it's closed).
function HistoryWindow:ShowTrip(t)
    if not frame then Create() end
    shownTrip = t
    self:SetTab("trip")
    if not frame:IsShown() then frame:Show() end
end

function HistoryWindow:Tab() return tab end
