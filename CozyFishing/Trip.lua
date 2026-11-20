local _, ns = ...
local L = ns.L

-- The fishing trip: a long session made of the short ones. A session lasts from putting a fishing pole on to
-- taking it off; a trip lasts from a click on the start button to a click on the stop button that takes its place,
-- and holds every session in between. At the end, a report: all of them, and the totals.
--   char.trip  = { started, skillStart, sessions = { history lines, oldest first } }: the trip going on
--                (kept over a reload or a logout until it's stopped);
--   char.trips = { newest first, at most MAX_TRIPS } of finished ones: the same, with ended and skillTo.
-- A trip starts and ends on a fresh session (the one in progress goes to the history first), so its sessions
-- are whole.
local Trip = {}
ns.Trip = Trip

local MAX_TRIPS = 30
local PLAY_TEXTURE = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"

local btn

local function Cfg() return ns.db.trip end

function Trip.Active() return ns.char.trip end

function Trip.List()
    ns.char.trips = ns.char.trips or {}
    return ns.char.trips
end

-- "1 h 05 min", "12 min".
function ns.Duration(seconds)
    local minutes = math.max(0, math.floor((seconds or 0) / 60 + 0.5))
    if minutes >= 60 then return L["%d h %02d min"]:format(math.floor(minutes / 60), minutes % 60) end
    return L["%d min"]:format(minutes)
end

-- The totals of a trip; one going on counts the session in progress too (sum.live).
--   { sessions, casts, catches, total, seconds (fishing), started, ended, skillFrom, skillTo,
--     items = { { id, count }, ... } most caught first, zones = { names, most sessions first }, list = { lines } }
function Trip.Summary(t)
    local sum = { casts = 0, catches = 0, total = 0, seconds = 0, started = t.started, ended = t.ended or time(),
        skillFrom = t.skillStart, skillTo = t.skillTo, items = {}, zones = {}, list = {} }
    for _, e in ipairs(t.sessions) do sum.list[#sum.list + 1] = e end
    if not t.ended then
        sum.live = ns.History.Entry(ns.session)
        if sum.live then sum.list[#sum.list + 1] = sum.live end
        if not sum.skillTo then sum.skillTo = ns.skill and ns.skill.rank end
    end
    sum.sessions = #sum.list
    local counts, first, zoneCount = {}, {}, {}
    for _, e in ipairs(sum.list) do
        sum.casts = sum.casts + (e.casts or 0)
        sum.catches = sum.catches + (e.catches or 0)
        sum.total = sum.total + (e.total or 0)
        sum.seconds = sum.seconds + math.max(0, (e.ended or e.started) - e.started)
        for _, it in ipairs(e.items or {}) do
            if not counts[it.id] then
                first[#first + 1] = it.id
                counts[it.id] = 0
            end
            counts[it.id] = counts[it.id] + it.count
        end
        if e.zone then zoneCount[e.zone] = (zoneCount[e.zone] or 0) + 1 end
        if not sum.skillFrom then sum.skillFrom = e.skillFrom end
    end
    local order = {}
    for i, id in ipairs(first) do
        order[id] = i
        sum.items[i] = { id = id, count = counts[id] }
    end
    table.sort(sum.items, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return order[a.id] < order[b.id]
    end)
    for zone in pairs(zoneCount) do sum.zones[#sum.zones + 1] = zone end
    table.sort(sum.zones, function(a, b)
        if zoneCount[a] ~= zoneCount[b] then return zoneCount[a] > zoneCount[b] end
        return a < b
    end)
    return sum
end

function Trip.Start()
    if ns.char.trip then return end
    if ns.session then ns.ClearSession() end -- the trip begins with a fresh session
    local skill = ns.UpdateSkill()
    ns.char.trip = { started = time(), sessions = {}, skillStart = skill and skill.rank }
    ns.Print(L["fishing trip started: every session from now on adds up until you stop it."])
    Trip:Refresh()
end

-- Ends the trip and shows its report. The session in progress goes into it; fishing goes on in a new one.
function Trip.Stop()
    local t = ns.char.trip
    if not t then return end
    if ns.session then ns.ClearSession() end
    t.ended = time()
    local skill = ns.UpdateSkill()
    t.skillTo = skill and skill.rank or t.skillStart
    ns.char.trip = nil
    if #t.sessions > 0 then
        local list = Trip.List()
        table.insert(list, 1, t)
        while #list > MAX_TRIPS do table.remove(list) end
    end
    Trip:Refresh()
    ns.HistoryWindow:ShowTrip(t)
end

-- The button and /cf trip: start at once; stop after a question (a stray click shouldn't end a long trip).
function Trip.Toggle()
    if not ns.char.trip then return Trip.Start() end
    ns.Dialog("COZYFISHING_STOP_TRIP", L["Stop the fishing trip and see its report?"], L["Stop the trip"], Trip.Stop)
end

------------------------------------------------------------------------
-- The button: start (a play arrow) or stop (a red square), with the trip's time under it.
------------------------------------------------------------------------
local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Fishing trip"], 1, 1, 1)
    local t = ns.char.trip
    if t then
        local sum = Trip.Summary(t)
        GameTooltip:AddLine(L["Going for %s, %d sessions"]:format(ns.Duration(time() - t.started), sum.sessions),
            0.9, 0.9, 0.9)
        GameTooltip:AddLine(L["%d caught, %d casts"]:format(sum.total, sum.casts), 0.9, 0.9, 0.9)
        GameTooltip:AddLine(L["Click: stop the trip and see the report"], 0.9, 0.8, 0.5)
    else
        GameTooltip:AddLine(L["Click: start a fishing trip. Every session from then on adds up until you stop it, and then you get a report of all of them."],
            0.9, 0.8, 0.5, true)
    end
    if not Cfg().locked then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["%s to move, the corner to resize"]:format(ns.MoveModeText()), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function ShowTime()
    local t = ns.char.trip
    btn.time:SetText(t and ns.Duration(time() - t.started) or "")
end

function Trip:Create()
    btn = CreateFrame("Button", "CozyFishingTrip", UIParent)
    btn:SetFrameStrata("MEDIUM")
    btn:RegisterForClicks("LeftButtonUp")
    btn:Hide()

    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.8)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon:SetTexture(ns.FISHING_ICON)
    btn.play = btn:CreateTexture(nil, "OVERLAY")
    btn.play:SetPoint("CENTER")
    btn.play:SetTexture(PLAY_TEXTURE)
    btn.stop = btn:CreateTexture(nil, "OVERLAY")
    btn.stop:SetPoint("CENTER")
    btn.stop:SetColorTexture(0.85, 0.12, 0.1, 0.95)
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn.time = btn:CreateFontString(nil, "OVERLAY")
    ns.SetOutlineFont(btn.time, 11)
    btn.time:SetPoint("TOP", btn, "BOTTOM", 0, -2)

    btn:SetScript("OnClick", function()
        if ns.MoveModifierDown() and not Cfg().locked then return end -- that click was for moving it
        Trip.Toggle()
    end)
    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    local t = 0
    btn:SetScript("OnUpdate", function(_, e)
        t = t + e
        if t < 1 then return end
        t = 0
        ShowTime()
    end)

    ns.MakeMovable(btn, Cfg)
    ns.MakeGrip(btn, {
        get = function() return Cfg().size end,
        set = function(v) Cfg().size = math.floor(v + 0.5) end,
        min = 16, max = 96,
        apply = function() Trip:Refresh() end,
    })
end

-- Not secure: shows and hides in combat too. Shown while a trip goes on, and otherwise when there's a fishing
-- pole in hand or in the bags to fish with.
function Trip:Refresh()
    if not btn then return end
    local cfg = Cfg()
    local size = cfg.size
    btn:SetSize(size, size)
    ns.ApplyPoint(btn, cfg.point)
    local on = ns.char.trip ~= nil
    btn.play:SetSize(size * 0.75, size * 0.75)
    btn.stop:SetSize(size * 0.4, size * 0.4)
    btn.play:SetShown(not on)
    btn.stop:SetShown(on)
    btn.icon:SetVertexColor(on and 1 or 0.55, on and 1 or 0.55, on and 1 or 0.55)
    ShowTime()
    local want = on or ns.placing or ns.PoleEquipped() or ns.Swap.FindPole() ~= nil
    btn:SetShown(cfg.enabled and want and true or false)
    if GameTooltip:IsOwned(btn) then Tooltip(btn) end
end
