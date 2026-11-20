local _, ns = ...

-- Fishing history, per character (CozyFishingCharDB):
--   char.zones[zone] = { casts, catches, total, seconds, items = { [itemID] = count }, last }
--     what was caught in each zone, kept up to date with every cast and catch, over all sessions;
--   char.history = { newest first, at most MAX_SESSIONS } of finished sessions:
--     { started, ended, casts, catches, total, zone, items = { { id, count }, ... }, skillFrom, skillTo };
--   char.trip, char.trips: the fishing trip going on and the finished ones (Trip.lua).
local History = {}
ns.History = History

local MAX_SESSIONS = 100
-- Time between two casts counts as fishing time when it's shorter than this (a break isn't fishing).
local MAX_GAP = 90

local function Zones()
    ns.char.zones = ns.char.zones or {}
    return ns.char.zones
end

local function Zone(name)
    local zones = Zones()
    local z = zones[name]
    if not z then
        z = { casts = 0, catches = 0, total = 0, seconds = 0, items = {} }
        zones[name] = z
    end
    return z
end

function History.Sessions()
    ns.char.history = ns.char.history or {}
    return ns.char.history
end

function History.AddCast(s, zone)
    local now = time()
    local z = Zone(zone)
    z.casts = z.casts + 1
    if s.lastCast and now - s.lastCast <= MAX_GAP and s.lastZone == zone then
        z.seconds = z.seconds + (now - s.lastCast)
    end
    z.last = now
    s.lastCast, s.lastZone = now, zone
end

-- items: { { id, count }, ... } of one catch.
function History.AddCatch(s, zone, items)
    local z = Zone(zone)
    z.catches = z.catches + 1
    z.last = time()
    for _, it in ipairs(items) do
        z.items[it.id] = (z.items[it.id] or 0) + it.count
        z.total = z.total + it.count
    end
    s.zones = s.zones or {}
    s.zones[zone] = (s.zones[zone] or 0) + 1
end

-- The zone of a session: where most of it was caught.
local function MainZone(s)
    local best, n = nil, 0
    for zone, c in pairs(s.zones or {}) do
        if c > n or (c == n and best and zone < best) then best, n = zone, c end
    end
    return best
end

-- A session as a history line (also one still going, for a trip's report), or nil for one without a single cast.
function History.Entry(s)
    if not s or (s.casts or 0) == 0 and (s.total or 0) == 0 then return nil end
    local items = {}
    for _, id in ipairs(s.order or {}) do
        local e = s.items[id]
        if e then items[#items + 1] = { id = id, count = e.count } end
    end
    local skill = ns.skill
    local entry = {
        started = s.started,
        ended = s.last or s.started,
        casts = s.casts or 0,
        catches = s.catches or 0,
        total = s.total or 0,
        zone = MainZone(s),
        items = items,
        skillFrom = s.skillStart,
        skillTo = skill and skill.rank or s.skillStart,
    }
    return entry
end

-- Puts a finished session in the history, and in the fishing trip going on, if there is one.
function History.Archive(s)
    local entry = History.Entry(s)
    if not entry then return end
    local list = History.Sessions()
    table.insert(list, 1, entry)
    while #list > MAX_SESSIONS do table.remove(list) end
    local trip = ns.char.trip
    if trip then trip.sessions[#trip.sessions + 1] = entry end
end

-- Zones with anything caught, most catches first: { { name, casts, catches, total, seconds, items }, ... }
-- where items is { { id, count }, ... }, most caught first.
function History.ZoneList()
    local list = {}
    for name, z in pairs(Zones()) do
        if z.catches > 0 then
            local items = {}
            for id, count in pairs(z.items) do items[#items + 1] = { id = id, count = count } end
            table.sort(items, function(a, b)
                if a.count ~= b.count then return a.count > b.count end
                return a.id < b.id
            end)
            list[#list + 1] = { name = name, casts = z.casts, catches = z.catches, total = z.total,
                seconds = z.seconds, items = items }
        end
    end
    table.sort(list, function(a, b)
        if a.catches ~= b.catches then return a.catches > b.catches end
        return a.name < b.name
    end)
    return list
end

-- Catches per hour of fishing time, once there's enough of it to say.
function History.PerHour(catches, seconds)
    if not seconds or seconds < 300 then return nil end
    return math.floor(catches * 3600 / seconds + 0.5)
end

-- The fishing trip going on, if any, stays.
function History.Clear()
    ns.char.history = {}
    ns.char.zones = {}
    ns.char.trips = {}
end
