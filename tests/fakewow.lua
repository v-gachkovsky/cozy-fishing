-- A small fake of the WoW API, enough to load Cozy Fishing and play a fishing session. The game state lives in
-- `game` (returned): the main hand, bags, skill, combat, bindings, the channel, the loot window.
-- Like the game, it refuses what insecure code can't do to a secure frame in combat (blocked[]).
unpack = unpack or table.unpack

local game = {
    now = 1000,         -- GetTime()
    clock = 1700000000, -- time()
    combat = false,
    mainhand = nil,     -- item ID
    offhand = nil,      -- item ID
    items = {},         -- [itemID] = { classID, subclassID, icon, name, twoHand, offhand }
    equips = {},        -- EquipItemByName calls the "server" hasn't done yet (game.ApplyEquips)
    savedBindings = 0,
    bags = {},          -- [itemID] = count
    enchant = nil,      -- { seconds left } of the main hand's lure
    skills = {},        -- { { name, header, rank, bonus, max } }
    bindings = {},      -- [command] = { key, ... }
    overrides = {},     -- [owner] = { [key] = action }
    cvars = { SoftTargetInteract = "1", SoftTargetInteractArc = "0", SoftTargetInteractRange = "10" },
    channel = nil,      -- { startMS, endMS, spellID }
    loot = nil,         -- { fishing = true, items = { { id, count } } }
    zone = "Elwynn Forest",
    printed = {},
    blocked = {},
    frames = {},
    timers = {},
    drivers = {},       -- [frame] = rule
    popups = {},
}

------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------
local Frame = {}
Frame.__index = function(_, k)
    local m = rawget(Frame, k)
    if m then return m end
    if type(k) == "string" and k:find("^%u") then return function() end end -- other widget methods do nothing
end

local function Protected(o)
    while o do
        if o.secure then return true end
        o = o.parent
    end
    return false
end

-- Insecure code touching a secure frame in combat: the game blocks it.
local function Guard(o, what)
    if game.combat and o.secure and not game.secureCall then
        game.blocked[#game.blocked + 1] = (o.name or "?") .. ":" .. what
        return true
    end
end

local function New(kind, name, parent, template)
    local o = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, attrs = {}, shown = true,
        w = 0, h = 0, text = "", events = {}, unitEvents = {}, alpha = 1 }, Frame)
    if template and template:find("Secure") then o.secure = true end
    if name then _G[name] = o end
    game.frames[#game.frames + 1] = o
    return o
end

-- Like the game: a key script turns on the frame's keyboard (a visible one then takes every key), a gamepad
-- button script its gamepad buttons.
function Frame:SetScript(s, fn)
    self.scripts[s] = fn
    if fn and (s == "OnKeyDown" or s == "OnKeyUp") then self.keyboard = true end
    if fn and (s == "OnGamePadButtonDown" or s == "OnGamePadButtonUp") then self.gamepad = true end
end
function Frame:EnableGamePadButton(on) self.gamepad = on and true or false end
function Frame:GetScript(s) return self.scripts[s] end
function Frame:HookScript(s, fn)
    local old = self.scripts[s]
    self.scripts[s] = function(...)
        if old then old(...) end
        return fn(...)
    end
end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:RegisterUnitEvent(e) self.events[e] = true end
function Frame:Show()
    if Guard(self, "Show") then return end
    if not self.shown then
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
end
function Frame:Hide()
    if Guard(self, "Hide") then return end
    if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
    local o = self
    while o do
        if not o.shown then return false end
        o = o.parent
    end
    return true
end
function Frame:IsProtected() return Protected(self) end
function Frame:GetParent() return self.parent end
function Frame:SetAttribute(k, v)
    if Guard(self, "SetAttribute") then return end
    self.attrs[k] = v
end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:SetSize(w, h)
    if Guard(self, "SetSize") then return end
    self.w, self.h = w, h
end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetSize() return self.w, self.h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:SetPoint(...)
    if Guard(self, "SetPoint") then return end
    self.point = { ... }
end
function Frame:ClearAllPoints() if Guard(self, "ClearAllPoints") then return end end
function Frame:EnableKeyboard(on) self.keyboard = on and true or false end
function Frame:EnableMouse(on)
    if Guard(self, "EnableMouse") then return end
    self.mouse = on
end
function Frame:SetMouseClickEnabled(on)
    if Guard(self, "SetMouseClickEnabled") then return end
    self.clicks = on
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetCenter() return 500, 400 end
function Frame:GetLeft() return 100 end
function Frame:GetTop() return 600 end
function Frame:GetFrameLevel() return 1 end
function Frame:IsMouseOver() return false end
function Frame:SetText(t) self.text = t == nil and "" or tostring(t) end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #self.text * 6 end
function Frame:GetStringHeight() return 14 end
function Frame:SetTexture(t) self.texture = t; return true end
function Frame:SetDesaturated(on) self.desaturated = on end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:SetValue(v) self.value = v end
function Frame:GetValue() return self.value end
function Frame:SetChecked(v) self.checked = v end
function Frame:GetChecked() return self.checked end
function Frame:SetEnabled(v) self.enabled = v end
function Frame:IsOwned(owner) return self.owner == owner end
function Frame:SetOwner(owner) self.owner = owner; self.lines = {} end
function Frame:AddLine(t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end
function Frame:SetItemByID(id) self.lines = self.lines or {}; self.lines[#self.lines + 1] = "item:" .. id end
function Frame:CreateTexture(name) return New("Texture", name, self) end
function Frame:CreateFontString(name) return New("FontString", name, self) end
function Frame:CreateAnimationGroup()
    local g = New("AnimationGroup", nil, self)
    g.playing = false
    function g:CreateAnimation() return New("Animation", nil, g) end
    function g:Play() self.playing = true end
    function g:Stop()
        self.playing = false
        if self.scripts.OnStop then self.scripts.OnStop(self) end
    end
    function g:IsPlaying() return self.playing end
    return g
end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:SetScrollChild(c) self.child = c end
function Frame:AddMessage(t) game.printed[#game.printed + 1] = t end

function CreateFrame(kind, name, parent, template)
    if kind == "DropdownButton" then error("no such frame type") end -- this client: the old dropdowns
    return New(kind, name, parent, template)
end

UIParent = New("Frame", "UIParent")
Minimap = New("Frame", "Minimap")
Minimap.w, Minimap.h = 140, 140
GameTooltip = New("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = New("Frame", "ChatFrame1")
function GameTooltip_Hide() GameTooltip:Hide() end

------------------------------------------------------------------------
-- State drivers: [combat], [equipped:X] and plain results, like SecureCmdOptionParse.
------------------------------------------------------------------------
local function Evaluate(rule)
    for raw in (rule .. ";"):gmatch("([^;]*);") do
        local clause = raw:match("^%s*(.-)%s*$")
        local conds, result = clause:match("^%[(.-)%]%s*(.*)$")
        if not conds then return clause end
        local ok = true
        for part in conds:gmatch("[^,]+") do
            local c = part:match("^%s*(.-)%s*$")
            local name, value = c:match("^(%a+):?(.*)$")
            local pass
            if name == "combat" then pass = game.combat
            elseif name == "nocombat" then pass = not game.combat
            elseif name == "equipped" then
                local it = game.mainhand and game.items[game.mainhand]
                pass = it ~= nil and it.subclassID == 20 and value == "Fishing Poles"
            else error("condition the fake doesn't know: " .. c) end
            if not pass then ok = false end
        end
        if ok then return result end
    end
end

function game.Drive()
    game.secureCall = true
    for f, rule in pairs(game.drivers) do
        local v = Evaluate(rule)
        if v == "show" then f:Show() elseif v == "hide" then f:Hide() end
    end
    game.secureCall = false
end

function RegisterStateDriver(f, attr, rule)
    assert(attr == "visibility")
    if Guard(f, "RegisterStateDriver") then return end
    game.drivers[f] = rule
    game.Drive()
end

------------------------------------------------------------------------
-- Time and events
------------------------------------------------------------------------
C_Timer = {}
function C_Timer.After(sec, fn) game.timers[#game.timers + 1] = { at = game.now + sec, fn = fn } end
function GetTime() return game.now end
function time() return game.clock end
date = os.date

function game.Advance(seconds)
    local steps = math.max(1, math.floor(seconds / 0.25 + 0.5))
    for _ = 1, steps do
        game.now = game.now + seconds / steps
        game.clock = game.clock + seconds / steps
        local due, later = {}, {}
        for _, t in ipairs(game.timers) do table.insert(t.at <= game.now and due or later, t) end
        game.timers = later
        for _, t in ipairs(due) do t.fn() end
        for _, f in ipairs(game.frames) do
            if f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, seconds / steps) end
        end
        game.Drive()
    end
    game.clock = math.floor(game.clock + 0.5)
end

function game.Fire(event, ...)
    for _, f in ipairs(game.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
    game.Drive()
end

------------------------------------------------------------------------
-- The game's API
------------------------------------------------------------------------
function GetAddOnMetadata() return "test" end
function InCombatLockdown() return game.combat end
function GetCVar(k) return game.cvars[k] end
function SetCVar(k, v) game.cvars[k] = tostring(v) end
function GetInventoryItemID(_, slot)
    if slot == 16 then return game.mainhand end
    if slot == 17 then return game.offhand end
end
function GetItemInfo(id) local it = game.items[id] return it and it.name end
function EquipItemByName(id, slot) game.equips[#game.equips + 1] = { id = id, slot = slot } end
-- The server doing the swaps asked for, one by one, with their events. Two hands: a two-handed main hand
-- and an off hand don't go together.
function game.ApplyEquips()
    while #game.equips > 0 do
        local e = table.remove(game.equips, 1)
        local it = game.items[e.id]
        if (game.bags[e.id] or 0) > 0 and it then
            local function ToBag(x) if x then game.bags[x] = (game.bags[x] or 0) + 1 end end
            game.bags[e.id] = game.bags[e.id] - 1
            local slot = e.slot or (it.offhand and 17 or 16)
            if slot == 16 then
                ToBag(game.mainhand)
                game.mainhand = e.id
                if it.twoHand then ToBag(game.offhand); game.offhand = nil end
            else
                local m = game.mainhand and game.items[game.mainhand]
                if m and m.twoHand then ToBag(game.mainhand); game.mainhand = nil end
                ToBag(game.offhand)
                game.offhand = e.id
            end
            game.Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
            game.Fire("PLAYER_EQUIPMENT_CHANGED", 17, false)
            game.Fire("UNIT_INVENTORY_CHANGED", "player")
        end
    end
end
-- One bag holding everything in game.bags.
local function BagList()
    local list = {}
    for id, n in pairs(game.bags) do if n > 0 then list[#list + 1] = id end end
    table.sort(list)
    return list
end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
    GetContainerItemID = function(bag, slot) if bag == 0 then return BagList()[slot] end end,
}
function GetItemInfoInstant(id)
    local it = game.items[id]
    if not it then return id, nil, nil, nil, 134400 end
    return id, nil, nil, nil, it.icon or 134400, it.classID, it.subclassID
end
function GetItemSubClassInfo(class, sub) if class == 2 and sub == 20 then return "Fishing Poles" end end
function GetItemCount(id) return game.bags[id] or 0 end
function GetSpellInfo(id) if id == 7620 then return "Fishing" end return "Spell " .. id end
function IsPlayerSpell(id) return id == 7620 end
function UnitChannelInfo(unit)
    local c = unit == "player" and game.channel
    if not c then return nil end
    return "Fishing", nil, nil, c.startMS, c.endMS, false, false, c.spellID
end
function IsFishingLoot() return game.loot ~= nil and game.loot.fishing end
function GetNumLootItems() return game.loot and #game.loot.items or 0 end
function GetLootSlotLink(i) return ("|cffffffff|Hitem:%d::::|h[Item]|h|r"):format(game.loot.items[i].id) end
function GetLootSlotInfo(i) return 134400, "Item", game.loot.items[i].count, nil, 1 end
-- The skill list as the game shows it: a collapsed header hides the lines under it.
local function SkillLines()
    local list, hiding = {}, false
    for _, s in ipairs(game.skills) do
        if s.header then
            list[#list + 1] = s
            hiding = s.collapsed
        elseif not hiding then
            list[#list + 1] = s
        end
    end
    return list
end
function GetNumSkillLines() return #SkillLines() end
function GetSkillLineInfo(i)
    local s = SkillLines()[i]
    return s.name, s.header, s.header and not s.collapsed, s.rank, 0, s.bonus or 0, s.max
end
function ExpandSkillHeader(i) SkillLines()[i].collapsed = false; game.skillToggles = (game.skillToggles or 0) + 1 end
function CollapseSkillHeader(i) SkillLines()[i].collapsed = true; game.skillToggles = (game.skillToggles or 0) + 1 end
function GetWeaponEnchantInfo()
    if game.enchant then return true, game.enchant * 1000, 0, 0 end
    return false
end
function GetRealZoneText() return game.zone end
function GetZoneText() return game.zone end
function GetBindingKey(command) return unpack(game.bindings[command] or {}) end
function GetBindingText(key) return key end
function GetBindingAction(key, checkOverride)
    if checkOverride then
        for _, map in pairs(game.overrides) do if map[key] then return map[key] end end
    end
    for command, keys in pairs(game.bindings) do
        for _, k in ipairs(keys) do if k == key then return command end end
    end
    return ""
end
function SetBinding(key, command)
    if game.combat then game.blocked[#game.blocked + 1] = "SetBinding"; return end
    for c, keys in pairs(game.bindings) do
        for i = #keys, 1, -1 do if keys[i] == key then table.remove(keys, i) end end
        if #keys == 0 then game.bindings[c] = nil end
    end
    if command then
        game.bindings[command] = game.bindings[command] or {}
        table.insert(game.bindings[command], key)
    end
    return true
end
function GetCurrentBindingSet() return 2 end
function SaveBindings(set) game.savedBindings = game.savedBindings + 1; game.bindingSet = set end
function SetOverrideBinding(owner, _, key, action)
    if game.combat then game.blocked[#game.blocked + 1] = "SetOverrideBinding"; return end
    game.overrides[owner] = game.overrides[owner] or {}
    game.overrides[owner][key] = action
end
function SetOverrideBindingClick(owner, prio, key, button, mouse)
    SetOverrideBinding(owner, prio, key, "CLICK " .. button .. ":" .. (mouse or "LeftButton"))
end
function ClearOverrideBindings(owner)
    if game.combat then game.blocked[#game.blocked + 1] = "ClearOverrideBindings"; return end
    game.overrides[owner] = nil
end
-- The action a key does now: an addon's override first, then the normal binding.
function game.KeyAction(key)
    for _, map in pairs(game.overrides) do if map[key] then return map[key] end end
    for command, keys in pairs(game.bindings) do
        for _, k in ipairs(keys) do if k == key then return command end end
    end
end
function UnitExists() return false end
function UnitGUID() return nil end
function UnitName() return nil end
function SetCursor() end
function ResetCursor() end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return game.shift or false end
function IsMetaKeyDown() return false end
function IsMacClient() return true end
function IsMouseButtonDown() return false end
function GetCursorPosition() return 0, 0 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
INVSLOT_MAINHAND = 16
YES, NO, UNKNOWN = "Yes", "No", "Unknown"
UISpecialFrames = {}
-- The game's popups take the whole keyboard on this client: the addon mustn't use them.
StaticPopupDialogs = setmetatable({}, { __newindex = function(_, k) error("StaticPopup used: " .. k) end })
function StaticPopup_Show(name) error("StaticPopup used: " .. name) end
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SlashCmdList = {}
function InterfaceOptions_AddCategory(panel) game.optionsPanel = panel end
function InterfaceOptionsFrame_OpenToCategory() game.optionsOpened = (game.optionsOpened or 0) + 1 end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function KeyBindingFrame_LoadUI() game.keyBindingsOpened = true end
function ShowUIPanel() end

------------------------------------------------------------------------
-- Loading the addon from its TOC
------------------------------------------------------------------------
function game.Load(dir, name)
    local ns = {}
    for raw in io.lines(dir .. "/" .. name .. ".toc") do
        local line = raw:gsub("\r", "")
        if line ~= "" and not line:find("^##") then
            local path = dir .. "/" .. line:gsub("\\", "/")
            local chunk = assert(loadfile(path))
            chunk(name, ns)
        end
    end
    return ns
end

return game
