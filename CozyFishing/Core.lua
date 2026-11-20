local ADDON, ns = ...
local L = ns.L

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"
ns.LOGO = "Interface\\AddOns\\CozyFishing\\Media\\logo"
-- Used when the client has no bobber cursor texture.
ns.FISHING_ICON = "Interface\\Icons\\Trade_Fishing"
-- The cursor the game shows over a fishing bobber.
ns.HOOK_TEXTURE = "Interface\\Cursor\\Fishing"

local FISHING_SPELL = 7620
-- Fishing ranks (Apprentice .. Artisan, and later ones if the client has them).
local FISHING_IDS = { [7620] = true, [7731] = true, [7732] = true, [18248] = true, [33095] = true, [51294] = true }
local POLE_SLOT = INVSLOT_MAINHAND or 16
local OFF_SLOT = INVSLOT_OFFHAND or 17
local WEAPON_CLASS, FISHING_POLE_SUBCLASS = 2, 20
-- A saved session older than this (logged out with the pole on) isn't continued.
local RESUME_WINDOW = 30 * 60

-- Soft targeting makes the bobber the game's "interact" target, so the Interact with Target key (which the
-- icon's right click presses) reels it in. Turned on for the session and put back when the pole comes off.
local FISH_CVARS = { SoftTargetInteract = "3", SoftTargetInteractArc = "2", SoftTargetInteractRange = "30" }

local GetCVar = GetCVar or (C_CVar and C_CVar.GetCVar)
local SetCVar = SetCVar or (C_CVar and C_CVar.SetCVar)
local GetItemInfoInstant = GetItemInfoInstant or (C_Item and C_Item.GetItemInfoInstant)
local GetItemSubClassInfo = GetItemSubClassInfo or (C_Item and C_Item.GetItemSubClassInfo)

local DEFAULTS = {
    locale = "enUS",
    moveWith = "alt",
    summary = true,
    minimap = { hide = false, angle = 200 },
    -- Items dimmed in the catch (junk), shown at its end: hidden[itemID] = true.
    hidden = {},
    -- One-time messages already shown: keys (the keys can be set), picker (how a key picker works).
    seen = {},
    icon = {
        enabled = true,
        locked = false,
        size = 48,
        clearTarget = true,
        timer = true,
        lure = true,
        hideWithKeys = false,
        point = { "CENTER", "CENTER", 0, -140 },
    },
    grid = {
        enabled = true,
        locked = false,
        scale = 1,
        columns = 6,
        bgAlpha = 0,
        skill = true,
        point = { "TOPLEFT", "CENTER", 120, -100 },
    },
    -- The button that swaps the weapon for a fishing pole and back.
    swap = {
        enabled = true,
        locked = false,
        hideWithKey = false,
        size = 32,
        point = { "CENTER", "CENTER", -64, -140 },
    },
    -- The button that starts and stops a fishing trip (sessions that add up, with a report at the end).
    trip = {
        enabled = true,
        locked = false,
        size = 32,
        point = { "CENTER", "CENTER", -104, -140 },
    },
}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
function ns.Print(fmt, ...)
    local text = select("#", ...) > 0 and fmt:format(...) or fmt
    DEFAULT_CHAT_FRAME:AddMessage("|cff4fc3f7Cozy Fishing|r: " .. text)
end

-- Values the client hides from addons ("secret" values) can't be compared or read.
function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

local function DeepCopy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and DeepCopy(v) or v end
    return c
end

local function Fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = DeepCopy(v) else Fill(dst[k], v) end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function ns.DefaultPoint(key) return DeepCopy(DEFAULTS[key].point) end

function ns.ItemIcon(id)
    return GetItemInfoInstant and select(5, GetItemInfoInstant(id)) or 134400
end

function ns.FishingName()
    if not ns.fishName then
        ns.fishName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(FISHING_SPELL))
            or (GetSpellInfo and GetSpellInfo(FISHING_SPELL))
    end
    return ns.fishName or "Fishing"
end

function ns.FishingKnown()
    local book = C_SpellBook
    for id in pairs(FISHING_IDS) do
        if (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id))
            or (book and book.IsSpellKnown and book.IsSpellKnown(id))
            or (book and book.IsSpellInSpellBook and book.IsSpellInSpellBook(id)) then
            return true
        end
    end
    return false
end

local function IsFishingSpell(spellID)
    if spellID == nil or ns.IsSecret(spellID) then return false end
    if FISHING_IDS[spellID] then return true end
    local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
        or (GetSpellInfo and GetSpellInfo(spellID))
    return name ~= nil and name == ns.FishingName()
end

-- The game's name for the item type, for the [equipped:...] macro condition.
function ns.PoleTypeName()
    return (GetItemSubClassInfo and GetItemSubClassInfo(WEAPON_CLASS, FISHING_POLE_SUBCLASS)) or "Fishing Poles"
end

function ns.IsPole(id)
    if not id or not GetItemInfoInstant then return false end
    local classID, subclassID = select(6, GetItemInfoInstant(id))
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE_SUBCLASS
end

function ns.PoleEquipped()
    return ns.IsPole(GetInventoryItemID("player", POLE_SLOT))
end

-- The zone you're in, for the statistics by zone.
function ns.ZoneName()
    local z = GetRealZoneText and GetRealZoneText()
    if not z or z == "" or ns.IsSecret(z) then z = GetZoneText and GetZoneText() end
    if not z or z == "" or ns.IsSecret(z) then return UNKNOWN or "?" end
    return z
end

------------------------------------------------------------------------
-- Fishing skill: ns.skill = { rank = 150, max = 225, bonus = 120 } (the bonus from the pole and the lure),
-- or nil while it can't be read. Three ways, as clients differ: the profession API (GetProfessions' fourth value
-- is Fishing), the character's skill list, and the skill list with its collapsed headers opened for a moment.
------------------------------------------------------------------------
local FISHING_SKILL_LINE = 356
-- Opening collapsed headers changes the skill list, which fires SKILL_LINES_CHANGED, which reads the skill
-- again: not more often than this.
local EXPAND_EVERY = 10

local function Num(v) return type(v) == "number" and not ns.IsSecret(v) end

local function Skill(rank, max, bonus)
    return { rank = rank, max = Num(max) and max or rank, bonus = Num(bonus) and bonus or 0 }
end

local function FromProfessions()
    if not (GetProfessions and GetProfessionInfo) then return nil end
    local ok, _, _, _, fishing = pcall(GetProfessions)
    if not ok or not Num(fishing) then return nil end
    local _, _, rank, max, _, _, line, bonus = GetProfessionInfo(fishing)
    if Num(rank) and (line == nil or line == FISHING_SKILL_LINE) then return Skill(rank, max, bonus) end
end

local function IsFishing(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return false end
    local want = ns.FishingName()
    return name == want or name:lower() == want:lower() or name == "Fishing"
end

local function FromSkillLines()
    if not (GetNumSkillLines and GetSkillLineInfo) then return nil end
    for i = 1, GetNumSkillLines() do
        local name, header, _, rank, _, bonus, max = GetSkillLineInfo(i)
        if not header and IsFishing(name) and Num(rank) then return Skill(rank, max, bonus) end
    end
end

local lastExpand
local function FromCollapsed()
    if not (ExpandSkillHeader and CollapseSkillHeader and GetNumSkillLines and GetSkillLineInfo) then return nil end
    if InCombatLockdown() or (SkillFrame and SkillFrame:IsVisible()) then return nil end
    if lastExpand and GetTime() - lastExpand < EXPAND_EVERY then return nil end
    lastExpand = GetTime()
    local opened = {}
    local i = 1
    while i <= GetNumSkillLines() do
        local name, header, expanded = GetSkillLineInfo(i)
        if header and not expanded then
            opened[name] = true
            ExpandSkillHeader(i)
        end
        i = i + 1
    end
    if not next(opened) then return nil end
    local found = FromSkillLines()
    -- Closed again from the bottom up, so the indexes above stay right.
    for j = GetNumSkillLines(), 1, -1 do
        local name, header, expanded = GetSkillLineInfo(j)
        if header and expanded and opened[name] then CollapseSkillHeader(j) end
    end
    return found
end

function ns.UpdateSkill()
    local found = FromProfessions() or FromSkillLines() or FromCollapsed()
    -- Not read this time only because the headers were just opened: keep what was read then.
    if found or not (lastExpand and GetTime() - lastExpand < EXPAND_EVERY) then ns.skill = found end
    found = ns.skill
    local s = ns.session
    if s and found and not s.skillStart then s.skillStart = found.rank end
    return found
end

-- For /cf debug: what each way of reading the skill sees.
function ns.SkillReport()
    local parts = {}
    if GetProfessions then
        local ok, p1, p2, arch, fishing, cooking = pcall(GetProfessions)
        parts[#parts + 1] = ok and ("professions %s/%s/%s/fishing %s/%s"):format(tostring(p1), tostring(p2),
            tostring(arch), tostring(fishing), tostring(cooking)) or "professions: error"
    else
        parts[#parts + 1] = "no GetProfessions"
    end
    if GetNumSkillLines and GetSkillLineInfo then
        local n, collapsed, match = GetNumSkillLines(), 0, "none"
        for i = 1, n do
            local name, header, expanded, rank = GetSkillLineInfo(i)
            if header and not expanded then collapsed = collapsed + 1 end
            if type(name) == "string" and name:lower():find("fish", 1, true) then
                match = ("%s=%s"):format(name, tostring(rank))
            end
        end
        parts[#parts + 1] = ("skill lines %d (collapsed %d), fishing line: %s"):format(n, collapsed, match)
    else
        parts[#parts + 1] = "no GetSkillLineInfo"
    end
    local sk = ns.skill
    parts[#parts + 1] = sk and ("read: %d/%d +%d"):format(sk.rank, sk.max, sk.bonus) or "read: nothing"
    return table.concat(parts, "; ")
end

------------------------------------------------------------------------
-- Game settings for the hook
------------------------------------------------------------------------
function ns.SetFishingCVars(on)
    if not (GetCVar and SetCVar) then return end
    local saved = ns.db.cvarRestore
    if on then
        if saved then return end -- already on (also after a reload)
        saved = {}
        for cv, value in pairs(FISH_CVARS) do
            local old = GetCVar(cv)
            if old ~= nil then
                saved[cv] = old
                pcall(SetCVar, cv, value)
            end
        end
        ns.db.cvarRestore = saved
        -- Addons that keep these settings in their own profile (Plater keeps SoftTargetInteract) put their value
        -- back a moment after loading; set ours again then. Each cast checks them too (ns.EnsureFishingCVars).
        C_Timer.After(3, ns.EnsureFishingCVars)
    elseif saved then
        for cv, old in pairs(saved) do
            -- Only what we set: a value the player changed meanwhile stays.
            if GetCVar(cv) == FISH_CVARS[cv] then pcall(SetCVar, cv, old) end
        end
        ns.db.cvarRestore = nil
    end
end

-- While the session lasts, puts back any of our settings another addon (or the game) changed.
function ns.EnsureFishingCVars()
    if not (ns.db.cvarRestore and ns.session and GetCVar and SetCVar) then return end
    for cv, value in pairs(FISH_CVARS) do
        local now = GetCVar(cv)
        if now ~= nil and now ~= value then
            pcall(SetCVar, cv, value)
            if ns.Trace then ns.Trace("%s was %s, set to %s again", cv, tostring(now), value) end
        end
    end
end

------------------------------------------------------------------------
-- Session: from putting a fishing pole on to taking it off
------------------------------------------------------------------------
local function NewSession()
    local now = time()
    local skill = ns.UpdateSkill()
    return { started = now, last = now, items = {}, order = {}, total = 0, catches = 0, casts = 0, zones = {},
        skillStart = skill and skill.rank }
end

local function Minutes(s)
    return math.max(1, math.floor((time() - s.started) / 60 + 0.5))
end

function ns.PrintSession(s, over)
    s = s or ns.session
    if not s then
        ns.Print(L["no fishing session now: equip a fishing pole to start one."])
        return
    end
    ns.Print(over and L["session over: %d caught (%d casts) in %d min."] or L["this session: %d caught (%d casts) in %d min."],
        s.total, s.casts, Minutes(s))
end

local function StartSession(resume)
    local saved = ns.char.session
    if resume and saved and saved.last and time() - saved.last <= RESUME_WINDOW then
        ns.session = saved
        saved.zones = saved.zones or {}
    else
        -- One left from before (logged out with the pole on a while ago) goes to the history.
        if saved then ns.History.Archive(saved) end
        ns.session = NewSession()
        ns.char.session = ns.session
    end
end

local function EndSession(quiet)
    local s = ns.session
    ns.session = nil
    ns.char.session = nil
    if not s then return end
    ns.History.Archive(s)
    if not quiet and ns.db.summary and s.casts > 0 then ns.PrintSession(s, true) end
end

-- Starts a fresh catch for the session in progress.
function ns.ClearSession()
    if not ns.session then return end
    ns.History.Archive(ns.session)
    ns.session = NewSession()
    ns.char.session = ns.session
    ns.RefreshAll()
end

function ns.UpdatePole(initial)
    local on = ns.PoleEquipped()
    ns.poleOn = on
    ns.UpdateSkill()
    if on and not ns.session then
        StartSession(initial)
    elseif not on and ns.session then
        EndSession(initial)
    elseif not on and initial then
        ns.char.session = nil
    end
    ns.SetFishingCVars(on)
    ns.RefreshAll()
end

-- Loot of one catch: counted once, at LOOT_READY or LOOT_OPENED, whichever comes first (fast auto loot
-- can empty the window before LOOT_OPENED).
local lootCounted
local function CountLoot()
    local s = ns.session
    if lootCounted or not s or not (IsFishingLoot and IsFishingLoot()) then return end
    lootCounted = true
    s.catches = s.catches + 1
    s.last = time()
    local caught = {}
    for i = 1, GetNumLootItems() do
        local link = GetLootSlotLink(i)
        local id = link and not ns.IsSecret(link) and tonumber(link:match("item:(%d+)"))
        if id then
            local icon, _, qty, _, quality = GetLootSlotInfo(i)
            if ns.IsSecret(qty) or type(qty) ~= "number" or qty < 1 then qty = 1 end
            local e = s.items[id]
            if not e then
                e = { count = 0 }
                s.items[id] = e
                s.order[#s.order + 1] = id
            end
            e.count = e.count + qty
            if icon and not ns.IsSecret(icon) then e.icon = icon end
            if type(quality) == "number" and not ns.IsSecret(quality) then e.quality = quality end
            s.total = s.total + qty
            caught[#caught + 1] = { id = id, count = qty, icon = e.icon }
        end
    end
    ns.History.AddCatch(s, ns.ZoneName(), caught)
    ns.Grid:Refresh()
    ns.HistoryWindow:Refresh()
end

------------------------------------------------------------------------
-- Refresh / locking
------------------------------------------------------------------------
function ns.RefreshAll()
    if not ns.ready then return end
    ns.Icon:Refresh()
    ns.Lure:Refresh()
    ns.Swap:Refresh()
    ns.Trip:Refresh()
    ns.Keys:Refresh()
    ns.Grid:Refresh()
    ns.Minimap:Refresh()
    ns.HistoryWindow:Refresh()
end

function ns.SetAllLocked(locked)
    ns.db.icon.locked = locked
    ns.db.grid.locked = locked
    ns.db.swap.locked = locked
    ns.db.trip.locked = locked
    ns.RefreshAll()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.SetPlacing(on)
    ns.placing = on and true or nil
    ns.RefreshAll()
    if ns.RefreshOptions then ns.RefreshOptions() end
end

function ns.ResetPositions()
    if InCombatLockdown() then
        ns.Print(L["can't do this in combat."])
        return
    end
    ns.db.icon.point = ns.DefaultPoint("icon")
    ns.db.grid.point = ns.DefaultPoint("grid")
    ns.db.swap.point = ns.DefaultPoint("swap")
    ns.db.trip.point = ns.DefaultPoint("trip")
    ns.RefreshAll()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local events = CreateFrame("Frame")
local handlers = {}

local function On(event, fn, unit)
    handlers[event] = fn
    -- Events this client doesn't have are skipped instead of breaking the load.
    if unit then
        pcall(events.RegisterUnitEvent, events, event, unit)
    else
        pcall(events.RegisterEvent, events, event)
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then fn(...) end
end)

On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    CozyFishingDB = CozyFishingDB or {}
    CozyFishingCharDB = CozyFishingCharDB or {}
    Fill(CozyFishingDB, DEFAULTS)
    ns.db, ns.char = CozyFishingDB, CozyFishingCharDB
    ns.Keys:SetNames()
end)

On("PLAYER_LOGIN", function()
    ns.Icon:Create()
    ns.Lure:Create()
    ns.Swap:Create()
    ns.Trip:Create()
    ns.Grid:Create()
    ns.Minimap:Create()
    ns.InitOptions()
    ns.ready = true
end)

local entered
On("PLAYER_ENTERING_WORLD", function()
    if not entered then C_Timer.After(5, function() ns.Keys:Intro() end) end
    ns.UpdatePole(not entered)
    entered = true
end)

On("PLAYER_EQUIPMENT_CHANGED", function(slot)
    if not entered then return end
    if slot == nil or slot == POLE_SLOT then ns.UpdatePole() end
    if slot == nil or slot == POLE_SLOT or slot == OFF_SLOT then ns.Swap:EquipmentChanged() end
end)

-- A second look, in case a swap (by an equipment addon, or while loading) went by without the event above.
-- A lure going on or wearing off comes here too.
On("UNIT_INVENTORY_CHANGED", function()
    if not entered then return end
    if ns.PoleEquipped() ~= ns.poleOn then
        ns.UpdatePole()
    else
        ns.Lure:Refresh()
    end
    ns.Swap:EquipmentChanged()
end, "player")

On("BAG_UPDATE_DELAYED", function()
    if not entered then return end
    ns.Lure:Refresh()
    ns.Swap:Refresh()
    ns.Trip:Refresh()
end)

-- Skill-ups, and the lure's bonus coming and going.
local function SkillChanged()
    if not entered then return end
    ns.UpdateSkill()
    ns.Grid:Refresh()
end
On("SKILL_LINES_CHANGED", SkillChanged)
On("CHAT_MSG_SKILL", SkillChanged)

On("UPDATE_BINDINGS", function()
    if not entered then return end
    ns.Keys:Refresh()
    -- The hook and the swap button may hide, or come back, with the keys.
    ns.Icon:Refresh()
    ns.Swap:Refresh()
end)

On("SPELLS_CHANGED", function()
    ns.fishName = nil
    if entered then ns.Icon:Refresh() end
end)

On("UNIT_SPELLCAST_CHANNEL_START", function(_, _, spellID)
    if ns.Trace then
        ns.Trace("channel start: spell %s, fishing: %s", ns.IsSecret(spellID) and "<secret>" or tostring(spellID),
            tostring(IsFishingSpell(spellID)))
    end
    if not IsFishingSpell(spellID) then return end
    ns.EnsureFishingCVars()
    local s = ns.session
    if s then
        s.casts = s.casts + 1
        s.last = time()
        ns.History.AddCast(s, ns.ZoneName())
    end
    ns.Icon:SetReeling(true)
end, "player")

On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, _, spellID)
    if ns.reeling and (spellID == nil or ns.IsSecret(spellID) or IsFishingSpell(spellID)) then
        ns.Icon:SetReeling(false)
    end
end, "player")

On("LOOT_READY", CountLoot)
On("LOOT_OPENED", CountLoot)
On("LOOT_CLOSED", function() lootCounted = nil end)

On("PLAYER_REGEN_DISABLED", function() ns.Icon:EnterCombat() end)
On("PLAYER_REGEN_ENABLED", function()
    if entered and ns.PoleEquipped() ~= ns.poleOn then ns.UpdatePole() end
    ns.Icon:LeaveCombat()
    ns.Lure:Refresh()
    ns.Keys:Refresh()
end)

On("PLAYER_LOGOUT", function()
    -- Put the game settings back; they're set again at login if the pole is still on.
    ns.SetFishingCVars(false)
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
SLASH_COZYFISHING1 = "/cf"
SLASH_COZYFISHING2 = "/cozyfishing"
SlashCmdList.COZYFISHING = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "options" or msg == "config" then
        ns.OpenOptions()
    elseif msg == "lock" then
        ns.SetAllLocked(true)
        ns.Print(L["frames locked."])
    elseif msg == "unlock" then
        ns.SetAllLocked(false)
        ns.Print(L["frames unlocked: %s to move."], ns.MoveModeText():lower())
    elseif msg == "place" then
        ns.SetPlacing(not ns.placing)
        ns.Print(ns.placing and L["frames shown for placing."] or L["frames shown only with a fishing pole again."])
    elseif msg == "stats" then
        ns.PrintSession()
    elseif msg == "history" then
        ns.HistoryWindow:Toggle()
    elseif msg == "swap" then
        ns.Swap.Toggle()
    elseif msg == "trip" then
        ns.Trip.Toggle()
    elseif msg == "clear" then
        ns.ClearSession()
    elseif msg == "reset" then
        ns.ResetPositions()
    elseif msg == "minimap" then
        ns.db.minimap.hide = not ns.db.minimap.hide
        ns.RefreshAll()
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif msg == "debug off" then
        ns.db.debug = nil
        ns.db.debugLog = nil
        ns.Print("debug off")
    elseif msg == "debug" then
        -- Tracing on (a fresh log), and the state now. "/cf debug off" turns tracing off.
        ns.db.debug = true
        ns.db.debugLog = nil
        local function cv(name) local ok, v = pcall(GetCVar, name) return ok and tostring(v) or "?" end
        ns.Print("debug on (/cf debug off to stop)")
        ns.Print("SoftTargetInteract=%s Arc=%s Range=%s, saved: %s", cv("SoftTargetInteract"),
            cv("SoftTargetInteractArc"), cv("SoftTargetInteractRange"), tostring(ns.db.cvarRestore ~= nil))
        ns.Print("pole: %s, session: %s, line out: %s, target: %s", tostring(ns.PoleEquipped()),
            tostring(ns.session ~= nil), tostring(ns.reeling == true), tostring((UnitExists("target"))))
        ns.Print("soft target now: %s", ns.SoftInteractText())
        ns.Print("your Interact key: %s", tostring((GetBindingKey("INTERACTTARGET"))))
        ns.Print("Fishing skill (%s): %s", ns.FishingName(), ns.SkillReport())
    else
        ns.Print("/cf — %s", L["settings"])
        ns.Print("/cf lock | unlock — %s", L["lock or unlock the frames"])
        ns.Print("/cf place — %s", L["show the frames without a fishing pole, to place them"])
        ns.Print("/cf stats — %s", L["print the catch of this session"])
        ns.Print("/cf history — %s", L["fishing history and the catch by zone"])
        ns.Print("/cf swap — %s", L["swap the weapon and the fishing pole"])
        ns.Print("/cf trip — %s", L["start a fishing trip, or stop it and see its report"])
        ns.Print("/cf clear — %s", L["start the catch of this session over"])
        ns.Print("/cf reset — %s", L["put the frames back in their default places"])
        ns.Print("/cf minimap — %s", L["show or hide the minimap button"])
    end
end
