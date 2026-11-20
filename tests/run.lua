-- Loads the whole addon against a fake WoW API (tests/fakewow.lua) and plays fishing sessions:
-- `lua tests/run.lua` from the repo root. It catches load errors and logic bugs, not layout or the real game.
dofile("tests/strict.lua")
local game = dofile("tests/fakewow.lua")

local failed, passed = 0, 0
local function check(name, cond, detail)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
    end
end

local POLE, SWORD = 6256, 2488
local FISH, MACKEREL, JUNK = 6291, 6303, 6309
local ATTRACTOR, NIGHTCRAWLERS = 6533, 6530
game.items[POLE] = { classID = 2, subclassID = 20 }
game.items[SWORD] = { classID = 2, subclassID = 7 }
game.skills = {
    { name = "Secondary Skills", header = true },
    { name = "Fishing", rank = 75, max = 150, bonus = 0 },
}
game.bindings["CLICK CozyFishingIcon:LeftButton"] = { "F" }
game.bindings.COZYFISHING_HOOK = { "G" }

local ns = game.Load("CozyFishing", "CozyFishing")
-- The addon's dialogs, by name, as they come up.
local realDialog = ns.Dialog
function ns.Dialog(which, ...)
    game.popups[#game.popups + 1] = which
    return realDialog(which, ...)
end
game.Fire("ADDON_LOADED", "CozyFishing")
game.Fire("PLAYER_LOGIN")
game.Fire("PLAYER_ENTERING_WORLD")

local icon = _G.CozyFishingIcon
local grid = _G.CozyFishingGrid
local lure = _G.CozyFishingLure

local function Equip(id)
    game.mainhand = id
    game.Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
    game.Fire("UNIT_INVENTORY_CHANGED", "player")
end

local function Cast(seconds)
    game.channel = { startMS = game.now * 1000, endMS = (game.now + (seconds or 20)) * 1000, spellID = 7620 }
    game.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-guid", 7620)
end

local function Catch(items)
    game.channel = nil
    game.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-guid", 7620)
    game.loot = { fishing = true, items = items }
    game.Fire("LOOT_READY", false)
    game.Fire("LOOT_OPENED", false)
    game.loot = nil
    game.Fire("LOOT_CLOSED")
end

local function Has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

------------------------------------------------------------------------
-- Loading
------------------------------------------------------------------------
check("loads with its saved variables", ns.db ~= nil and ns.char ~= nil)
check("binding names", _G["BINDING_NAME_CLICK CozyFishingIcon:LeftButton"] == "Cast"
    and _G.BINDING_NAME_COZYFISHING_HOOK == "Hook the fish" and _G.BINDING_HEADER_COZYFISHING == "Cozy Fishing")
check("no pole: no session", ns.session == nil)
check("no pole: hook hidden", not icon:IsShown())
check("no pole: grid hidden", not grid:IsShown())
check("no pole: hook key not bound over", game.KeyAction("G") == "COZYFISHING_HOOK")

------------------------------------------------------------------------
-- A session
------------------------------------------------------------------------
Equip(POLE)
check("pole: session", ns.session ~= nil)
check("pole: hook shown", icon:IsShown())
check("pole: grid shown", grid:IsShown())
check("pole: soft targeting on", game.cvars.SoftTargetInteract == "3", game.cvars.SoftTargetInteract)
check("pole: hook key interacts", game.KeyAction("G") == "INTERACTTARGET", game.KeyAction("G"))
check("pole: cast key clicks the icon", game.KeyAction("F") == "CLICK CozyFishingIcon:LeftButton")
check("cast macro", (icon:GetAttribute("macrotext1") or ""):find("/cast Fishing", 1, true) ~= nil)
check("skill read", ns.skill and ns.skill.rank == 75 and ns.skill.max == 150)
check("session remembers the skill at start", ns.session.skillStart == 75)
-- Under a collapsed header: opened for a moment, read, closed again; not again at once on the event that follows.
game.skills[1].collapsed = true
game.Advance(11)
game.Fire("SKILL_LINES_CHANGED")
check("collapsed header: skill still read", ns.skill and ns.skill.rank == 75)
check("collapsed header: closed again", game.skills[1].collapsed == true)
local toggles = game.skillToggles
game.Fire("SKILL_LINES_CHANGED")
check("collapsed header: not opened again at once", game.skillToggles == toggles and ns.skill ~= nil)
game.skills[1].collapsed = false
-- The profession API, where the client has it, comes first.
function GetProfessions() return nil, nil, nil, 4, nil end
function GetProfessionInfo(i) if i == 4 then return "Fishing", 0, 76, 150, 0, 0, 356, 0 end end
game.Fire("SKILL_LINES_CHANGED")
check("profession API", ns.skill and ns.skill.rank == 76)
GetProfessions, GetProfessionInfo = nil, nil
game.Fire("SKILL_LINES_CHANGED")
check("grid shows the skill", grid.skill:IsShown() and grid.skill.text:GetText():find("75/150", 1, true) ~= nil,
    grid.skill.text:GetText())

-- No lure in the bags: no reminder.
check("no lure in bags: no reminder", not lure:IsShown())
-- Lures in the bags: the best the skill allows (the Attractor needs 100, Nightcrawlers 50).
game.bags[ATTRACTOR], game.bags[NIGHTCRAWLERS] = 2, 5
game.Fire("BAG_UPDATE_DELAYED")
check("lure reminder shown", lure:IsShown())
check("lure: the best one the skill allows", (lure:GetAttribute("macrotext1") or ""):find("item:6530", 1, true) ~= nil,
    lure:GetAttribute("macrotext1"))
check("lure: put on the main hand", (lure:GetAttribute("macrotext1") or ""):find("/use 16", 1, true) ~= nil)
game.skills[2].rank = 120
game.Fire("SKILL_LINES_CHANGED")
game.Fire("BAG_UPDATE_DELAYED")
check("lure: better one with more skill", (lure:GetAttribute("macrotext1") or ""):find("item:6533", 1, true) ~= nil)
-- The lure goes on: the reminder goes away; it wears off: back (the ticker, no event).
game.enchant = 600
game.skills[2].bonus = 100
game.Fire("UNIT_INVENTORY_CHANGED", "player")
check("lure on: no reminder", not lure:IsShown())
game.enchant = nil
game.Advance(1.5)
check("lure wore off: reminder again", lure:IsShown())
game.enchant = 600

-- Casting: the bar over the hook counts down.
Cast(20)
check("line out", ns.reeling == true)
check("cast counted", ns.session.casts == 1)
check("timer bar shown", icon.bar:IsShown())
game.Advance(5)
check("timer bar counts down", math.abs((icon.bar.value or 0) - 0.75) < 0.05, icon.bar.value)
check("timer text in seconds", icon.bar.text:GetText() == "15", icon.bar.text:GetText())
Catch({ { id = FISH, count = 1 } })
check("line in: bar hidden", not icon.bar:IsShown())
check("catch counted", ns.session.total == 1 and ns.session.catches == 1)
check("grid cell", #ns.Grid.Shown() == 1 and ns.Grid.Shown()[1] == FISH)

-- A cast that missed the school: cast again at once, line out; only the new cast counts on.
game.Advance(3)
Cast(20)
game.Advance(2)
Cast(20)
check("recast while the line is out", ns.session.casts == 3 and ns.reeling == true)
Catch({ { id = MACKEREL, count = 2 }, { id = JUNK, count = 1 } })
check("several items in one catch", ns.session.total == 4 and #ns.Grid.Shown() == 3)

-- Skill-up during the session.
game.skills[2].rank = 122
game.Fire("CHAT_MSG_SKILL", "Your skill in Fishing has increased to 122.")
check("skill gain since the start of the session", ns.SkillGain() == 47, ns.SkillGain())
check("grid shows the gain", grid.skill.text:GetText():find("+47 this session", 1, true) ~= nil, grid.skill.text:GetText())
check("grid shows the bonus", grid.skill.text:GetText():find("+100|r", 1, true) ~= nil)

-- Hiding junk with a right click on its cell.
local junkCell
for _, f in ipairs(game.frames) do
    if f.id == JUNK and f.parent == grid and f:IsShown() then junkCell = f end
end
check("junk cell found", junkCell ~= nil)
if junkCell then junkCell.scripts.OnMouseUp(junkCell, "RightButton") end
local shownIds = ns.Grid.Shown()
check("junk dimmed, still shown, at the end", ns.db.hidden[JUNK] == true and shownIds[#shownIds] == JUNK
    and junkCell.dim and junkCell.alpha < 1 and #shownIds == 3, table.concat(shownIds, " "))
-- Everything dimmed: still every cell shown.
ns.SetHidden(FISH, true)
ns.SetHidden(MACKEREL, true)
check("all dimmed: cells still shown", #ns.Grid.Shown() == 3, #ns.Grid.Shown())
ns.SetHidden(FISH, false)
ns.SetHidden(MACKEREL, false)
check("hidden still counts in the total", ns.session.total == 4)
check("grid title", grid.title:GetText() == "Caught: 4", grid.title:GetText())

-- Zone statistics.
game.zone = "Westfall"
game.Advance(4)
Cast(20)
Catch({ { id = FISH, count = 1 } })
local zones = ns.History.ZoneList()
check("two zones", #zones == 2, #zones)
check("most caught first", zones[1].name == "Elwynn Forest" and zones[1].catches == 2 and zones[1].total == 4)
check("zone casts", zones[1].casts == 3 and zones[2].casts == 1)
-- Casts 8 s and 2 s apart in Elwynn; the first cast in Westfall adds nothing there.
check("zone time counts gaps between casts", ns.char.zones["Elwynn Forest"].seconds == 10,
    ns.char.zones["Elwynn Forest"].seconds)
check("zone items most first", zones[1].items[1].id == MACKEREL and zones[1].items[1].count == 2)

------------------------------------------------------------------------
-- The pole comes off: the session goes to the history
------------------------------------------------------------------------
game.printed = {}
Equip(SWORD)
check("sword: no session", ns.session == nil)
check("sword: hook hidden", not icon:IsShown())
check("sword: grid hidden", not grid:IsShown())
check("sword: lure reminder hidden", not lure:IsVisible())
check("sword: soft targeting back", game.cvars.SoftTargetInteract == "1", game.cvars.SoftTargetInteract)
check("sword: hook key back", game.KeyAction("G") == "COZYFISHING_HOOK", game.KeyAction("G"))
check("summary printed", #game.printed == 1 and game.printed[1]:find("5 caught", 1, true) ~= nil, game.printed[1])
local hist = ns.History.Sessions()
check("session in the history", #hist == 1)
local e = hist[1] or {}
check("history entry", e.total == 5 and e.casts == 4 and e.catches == 3 and e.zone == "Elwynn Forest",
    ("%s %s %s %s"):format(tostring(e.total), tostring(e.casts), tostring(e.catches), tostring(e.zone)))
check("history skill", e.skillFrom == 75 and e.skillTo == 122)
check("history items in order", e.items and e.items[1].id == FISH and e.items[1].count == 2)

------------------------------------------------------------------------
-- Swaps in combat: the state driver hides the hook; the rest waits for the end of combat
------------------------------------------------------------------------
Equip(POLE)
check("pole again: new session", ns.session ~= nil and ns.session.total == 0)
game.combat = true
game.Fire("PLAYER_REGEN_DISABLED")
Equip(SWORD)
check("combat swap: hook hidden by the state driver", not icon:IsShown())
game.combat = false
game.Fire("PLAYER_REGEN_ENABLED")
check("after combat: session over", ns.session == nil)
check("after combat: hook key back", game.KeyAction("G") == "COZYFISHING_HOOK", game.KeyAction("G"))
check("after combat: hook still hidden", not icon:IsShown())
check("an empty session isn't in the history", #ns.History.Sessions() == 1)

-- The pole goes on in combat: the hook shows, the hook key comes when combat ends.
game.combat = true
game.Fire("PLAYER_REGEN_DISABLED")
Equip(POLE)
check("combat equip: hook shown by the state driver", icon:IsShown())
game.combat = false
game.Fire("PLAYER_REGEN_ENABLED")
check("after combat: hook key bound", game.KeyAction("G") == "INTERACTTARGET", game.KeyAction("G"))
check("nothing blocked in combat", #game.blocked == 0, table.concat(game.blocked, ", "))

-- A swap the equipment event missed (an equipment addon): the next inventory event catches it.
game.mainhand = SWORD
game.Fire("UNIT_INVENTORY_CHANGED", "player")
check("missed swap caught", ns.session == nil and not icon:IsShown())

------------------------------------------------------------------------
-- The swap button and key: a fishing pole from the bags, and back to the weapons you had
------------------------------------------------------------------------
local swap = _G.CozyFishingSwap
local DAGGER, SHIELD = 2092, 2129
game.items[POLE].twoHand, game.items[POLE].icon, game.items[POLE].name = true, 1001, "Fishing Pole"
game.items[DAGGER] = { classID = 2, subclassID = 15, icon = 1002, name = "Dagger" }
game.items[SHIELD] = { classID = 4, subclassID = 6, icon = 1003, name = "Shield", offhand = true }
game.Advance(1)
check("no pole in the bags: no swap button", not swap:IsShown())
game.printed = {}
CozyFishing_Swap()
check("no pole in the bags: says so", #game.equips == 0 and #game.printed == 1
    and game.printed[1]:find("no fishing pole in the bags", 1, true) ~= nil, game.printed[1])

game.mainhand, game.offhand = DAGGER, SHIELD
game.bags[POLE], game.bags[SWORD] = 1, 1
game.Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
game.Fire("BAG_UPDATE_DELAYED")
game.Advance(1)
check("pole in the bags: swap button", swap:IsShown())
check("swap button shows the pole", swap.icon.texture == 1001, swap.icon.texture)
swap.scripts.OnClick(swap, "LeftButton")
check("click: the pole asked for", #game.equips == 1 and game.equips[1].id == POLE and game.equips[1].slot == 16)
game.ApplyEquips()
check("pole on: session", ns.session ~= nil and icon:IsShown())
check("pole on: weapons in the bags", game.bags[DAGGER] == 1 and game.bags[SHIELD] == 1 and game.offhand == nil)
game.Advance(1)
check("both weapons remembered", ns.char.weapons and ns.char.weapons.main == DAGGER and ns.char.weapons.off == SHIELD)
check("swap button shows the weapon", swap.icon.texture == 1002, swap.icon.texture)

-- The key: the main hand first, the off hand once it's in.
CozyFishing_Swap()
check("key: main hand first", #game.equips == 1 and game.equips[1].id == DAGGER and game.equips[1].slot == 16)
game.ApplyEquips()
check("back: dagger and shield", game.mainhand == DAGGER and game.offhand == SHIELD, tostring(game.offhand))
check("back: session over, pole in the bags", ns.session == nil and game.bags[POLE] == 1)
game.Advance(1)
check("back: still remembered", ns.char.weapons.main == DAGGER and ns.char.weapons.off == SHIELD)

-- In combat (a mob came while fishing): both ways, nothing blocked.
game.blocked = {}
game.combat = true
game.Fire("PLAYER_REGEN_DISABLED")
SlashCmdList.COZYFISHING("swap")
game.ApplyEquips()
check("combat: pole on", game.mainhand == POLE and icon:IsShown())
game.Advance(1)
CozyFishing_Swap()
game.ApplyEquips()
check("combat: weapons back", game.mainhand == DAGGER and game.offhand == SHIELD and not icon:IsShown())
check("combat: swap button still there", swap:IsShown())
game.combat = false
game.Fire("PLAYER_REGEN_ENABLED")
check("combat swaps: nothing blocked", #game.blocked == 0, table.concat(game.blocked, ", "))

-- A pole put on by hand: the weapons in hand are remembered all the same.
game.mainhand, game.offhand = SWORD, nil
game.bags[SWORD], game.bags[DAGGER], game.bags[SHIELD] = 0, 1, 1
game.Fire("PLAYER_EQUIPMENT_CHANGED", 16, false)
game.Advance(1)
EquipItemByName(POLE)
game.ApplyEquips()
game.Advance(1)
check("pole by hand: sword remembered", ns.char.weapons.main == SWORD and ns.char.weapons.off == nil)
CozyFishing_Swap()
game.ApplyEquips()
check("pole by hand: back to the sword", game.mainhand == SWORD and game.offhand == nil)
-- The weapon you had sold meanwhile: the button goes away, the key says why.
EquipItemByName(POLE)
game.ApplyEquips()
game.Advance(1)
game.bags[SWORD] = 0
game.Fire("BAG_UPDATE_DELAYED")
check("weapon gone: no swap button", not swap:IsShown())
game.printed = {}
CozyFishing_Swap()
check("weapon gone: says so", #game.equips == 0 and (game.printed[1] or ""):find("isn't in the bags", 1, true) ~= nil,
    game.printed[1])
game.bags[SWORD] = 1
game.Fire("BAG_UPDATE_DELAYED")
check("weapon back in the bags: swap button", swap:IsShown())
ns.db.swap.enabled = false
ns.RefreshAll()
check("swap button turned off", not swap:IsShown())
ns.db.swap.enabled = true
-- Hidden while there's a key to swap; the key still swaps.
ns.db.swap.hideWithKey = true
ns.RefreshAll()
check("hide with key: no key yet, button stays", swap:IsShown())
game.bindings.COZYFISHING_SWAP = { "K" }
game.Fire("UPDATE_BINDINGS")
check("hide with key: button hidden", not swap:IsShown())
CozyFishing_Swap()
game.ApplyEquips()
check("hide with key: the key still swaps", game.mainhand == SWORD)
ns.SetPlacing(true)
check("hide with key: shown while placing", swap:IsShown())
ns.SetPlacing(false)
game.bindings.COZYFISHING_SWAP = nil
game.Fire("UPDATE_BINDINGS")
check("hide with key: key gone, button back", swap:IsShown())
ns.db.swap.hideWithKey = false
EquipItemByName(POLE)
game.ApplyEquips()
game.Advance(1)
ns.db.swap.enabled = true
ns.RefreshAll()

------------------------------------------------------------------------
-- Windows, commands, settings
------------------------------------------------------------------------
SlashCmdList.COZYFISHING("history")
check("history window opens", ns.HistoryWindow:IsShown())
ns.HistoryWindow:SetTab("sessions")
ns.HistoryWindow:SetTab("zones")
local hiddenIcon
for _, f in ipairs(game.frames) do
    if f.id == JUNK and f.note and f:IsShown() then hiddenIcon = f end
end
check("history shows hidden items dimmed", hiddenIcon ~= nil and hiddenIcon.alpha < 1)
if hiddenIcon then hiddenIcon.scripts.OnMouseUp(hiddenIcon, "RightButton") end
check("right click in the history shows it again", not ns.db.hidden[JUNK])
SlashCmdList.COZYFISHING("history")
check("history window closes", not ns.HistoryWindow:IsShown())

for _, cmd in ipairs({ "", "lock", "unlock", "place", "place", "stats", "clear", "reset", "minimap", "minimap",
    "debug", "debug off", "help" }) do
    local ok, err = pcall(SlashCmdList.COZYFISHING, cmd)
    check("/cf " .. cmd, ok, err)
end
check("options panel", game.optionsPanel ~= nil)
ns.RefreshOptions()

-- Key pickers in the settings: a click, then a key with its modifiers.
local function Popups(name)
    local n = 0
    for _, p in ipairs(game.popups) do if p == name then n = n + 1 end end
    return n
end
local dialog = _G.CozyFishingDialog
local function Accept(name)
    check("dialog up: " .. name, dialog:IsShown() and dialog.which == name, dialog.which)
    dialog.ok.scripts.OnClick(dialog.ok, "LeftButton")
end
check("keys intro shown once after the first login", Popups("COZYFISHING_KEYS_INTRO") == 1, Popups("COZYFISHING_KEYS_INTRO"))
-- Nothing on screen takes the keyboard, the message about keys included: the game must still hear keys.
local function KeyboardTakers()
    local list = {}
    for _, f in ipairs(game.frames) do
        if (f.keyboard or f.gamepad) and f:IsVisible() then list[#list + 1] = f.name or f.command or f.kind end
    end
    return list
end
check("keys intro: the keyboard stays the game's", #KeyboardTakers() == 0, table.concat(KeyboardTakers(), ", "))
check("keys intro: Esc closes it", Has(UISpecialFrames, "CozyFishingDialog"))
local opened = game.optionsOpened or 0
Accept("COZYFISHING_KEYS_INTRO")
check("keys intro opens the settings", (game.optionsOpened or 0) > opened)
game.Fire("PLAYER_ENTERING_WORLD")
game.Advance(6)
check("keys intro not again", Popups("COZYFISHING_KEYS_INTRO") == 1)

local pickers = {}
for _, f in ipairs(game.frames) do if f.command then pickers[f.command] = f end end
-- A key press, as the game hands it out: to the key catcher while it's shown, else not to the addon at all.
local function Key(k)
    local c = _G.CozyFishingKeyCatcher
    if c and c:IsVisible() then c.scripts.OnKeyDown(c, k) end
end
local function Pad(k)
    local c = _G.CozyFishingKeyCatcher
    if c and c:IsVisible() then c.scripts.OnGamePadButtonDown(c, k) end
end
local sp, hp = pickers.COZYFISHING_SWAP, pickers.COZYFISHING_HOOK
check("key pickers", sp ~= nil and hp ~= nil and pickers["CLICK CozyFishingIcon:LeftButton"] ~= nil)
check("swap key not set", sp.text:find("not set", 1, true) ~= nil, sp.text)
-- The first click explains first: no key is taken until Continue.
sp.scripts.OnClick(sp, "LeftButton")
check("first click: the explanation", Popups("COZYFISHING_KEY_HELP") == 1 and not sp.waiting)
Key("W")
check("first click: keys aren't taken before Continue", game.bindings.COZYFISHING_SWAP == nil)
Accept("COZYFISHING_KEY_HELP")
check("Continue: waits for a key", sp.waiting and sp.text:find("Press a key", 1, true) ~= nil, sp.text)
check("waiting: only the key catcher takes keys", #KeyboardTakers() == 1 and KeyboardTakers()[1] == "CozyFishingKeyCatcher",
    table.concat(KeyboardTakers(), ", "))
game.shift = true
Key("LSHIFT")
check("a modifier alone isn't a key", sp.waiting)
Key("X")
game.shift = false
check("swap key set", (game.bindings.COZYFISHING_SWAP or {})[1] == "SHIFT-X" and not sp.waiting)
check("one key only", #game.bindings.COZYFISHING_SWAP == 1)
check("key picked: the keyboard is the game's again", #KeyboardTakers() == 0, table.concat(KeyboardTakers(), ", "))
check("bindings saved", game.savedBindings > 0 and game.bindingSet == 2)
check("picker shows the key", sp.text == "SHIFT-X", sp.text)
Key("Y")
check("keys after that aren't taken", game.bindings.COZYFISHING_SWAP[1] == "SHIFT-X" and game.bindings.COZYFISHING_SWAP[2] == nil)
-- The explanation only the first time.
sp.scripts.OnClick(sp, "LeftButton")
check("explanation only once", Popups("COZYFISHING_KEY_HELP") == 1 and sp.waiting)
sp.scripts.OnClick(sp, "Button4")
check("mouse button as the key", #game.bindings.COZYFISHING_SWAP == 1 and game.bindings.COZYFISHING_SWAP[1] == "BUTTON4")
sp.scripts.OnClick(sp, "LeftButton")
Key("ESCAPE")
check("Esc cancels", not sp.waiting and game.bindings.COZYFISHING_SWAP[1] == "BUTTON4")
sp.scripts.OnClick(sp, "LeftButton")
game.Advance(11)
check("no key for a while: stops waiting", not sp.waiting and #KeyboardTakers() == 0)
Key("Z")
check("a key after that isn't taken", game.bindings.COZYFISHING_SWAP[1] == "BUTTON4")

-- Gamepad: a button, a combination with the gamepad's shift.
game.cvars.GamePadEmulateShift = "PADLTRIGGER"
sp.scripts.OnClick(sp, "LeftButton")
Pad("PADLTRIGGER")
check("gamepad modifier alone isn't a key", sp.waiting)
game.shift = true
Pad("PAD2")
game.shift = false
check("gamepad combination", game.bindings.COZYFISHING_SWAP[1] == "SHIFT-PAD2", game.bindings.COZYFISHING_SWAP[1])
sp.scripts.OnClick(sp, "LeftButton")
Pad("PAD1")
check("gamepad button", game.bindings.COZYFISHING_SWAP[1] == "PAD1")

-- A key that does something else: asks first; nothing changes on Cancel.
game.bindings.MOVEFORWARD = { "W" }
BINDING_NAME_MOVEFORWARD = "Move Forward"
game.popups = {}
sp.scripts.OnClick(sp, "LeftButton")
Key("W")
check("taken key: asks", Popups("COZYFISHING_KEY_TAKEN") == 1 and game.bindings.MOVEFORWARD[1] == "W"
    and game.bindings.COZYFISHING_SWAP[1] == "PAD1")
check("taken key: says what it does", dialog.text:GetText():find("Move Forward", 1, true) ~= nil, dialog.text:GetText())
Accept("COZYFISHING_KEY_TAKEN")
check("taken key: bound after yes", game.bindings.COZYFISHING_SWAP[1] == "W" and game.bindings.MOVEFORWARD == nil)
-- Let go of: it moves forward again.
game.printed = {}
sp.scripts.OnClick(sp, "RightButton")
check("right click: no key", game.bindings.COZYFISHING_SWAP == nil)
check("right click: the key does what it did", (game.bindings.MOVEFORWARD or {})[1] == "W")
check("chat says so", (game.printed[1] or ""):find("W is back to: Move Forward", 1, true) ~= nil, game.printed[1])
-- Another key of ours: asks, and it isn't given back to it later.
sp.scripts.OnClick(sp, "LeftButton")
Key("G")
check("hook key taken: asks", Popups("COZYFISHING_KEY_TAKEN") == 2)
dialog.no.scripts.OnClick(dialog.no, "LeftButton")
check("Cancel: the key stays where it was", not dialog:IsShown() and (game.bindings.COZYFISHING_HOOK or {})[1] == "G"
    and game.bindings.COZYFISHING_SWAP == nil)
-- The hook key changed during a session: the new key hooks, the old one is let go.
check("session for the hook key", ns.session ~= nil)
hp.scripts.OnClick(hp, "LeftButton")
Key("H")
check("new hook key interacts", game.KeyAction("H") == "INTERACTTARGET", game.KeyAction("H"))
check("old hook key let go", game.KeyAction("G") == nil, game.KeyAction("G"))
game.combat = true
hp.scripts.OnClick(hp, "LeftButton")
Key("J")
game.combat = false
check("no key changes in combat", game.bindings.COZYFISHING_HOOK[1] == "H" and #game.blocked == 0)

-- Hiding the hook when both keys are set: not drawn, no mouse, still there for the cast key's click.
local cp = pickers["CLICK CozyFishingIcon:LeftButton"]
ns.db.icon.hideWithKeys = true
ns.RefreshAll()
check("hide with keys: hook not drawn", icon:IsShown() and icon.art.alpha == 0, icon.art.alpha)
check("hide with keys: takes no mouse", icon.mouse == false)
check("hide with keys: cast key still clicks it", game.KeyAction("F") == "CLICK CozyFishingIcon:LeftButton")
Cast(20)
check("hide with keys: no timer bar", not icon.bar:IsShown())
check("hide with keys: no resize grip", icon.noGrip == true)
check("hide with keys: icon's mouse stays off with the line out", icon.mouse == false)
Catch({ { id = FISH, count = 1 } })
cp.scripts.OnClick(cp, "RightButton")
check("no cast key: hook drawn again", icon.art.alpha == 1 and icon.mouse == true)
cp.scripts.OnClick(cp, "LeftButton")
Key("F")
check("cast key again: hook hidden again", icon.art.alpha == 0)
ns.SetPlacing(true)
check("placing: hook drawn", icon.art.alpha == 1)
ns.SetPlacing(false)
ns.db.icon.hideWithKeys = false
ns.RefreshAll()
check("option off: hook drawn", icon.art.alpha == 1 and icon.mouse == true)
ns.Keys:OpenBindings()
check("key bindings open", game.keyBindingsOpened)

-- The minimap button: shift-click opens the history.
local mm = _G.CozyFishingMinimapButton
game.shift = true
mm.scripts.OnClick(mm, "LeftButton")
game.shift = false
check("minimap shift-click: history", ns.HistoryWindow:IsShown())

------------------------------------------------------------------------
-- A fishing trip: the sessions between start and stop add up, and a report at the end
------------------------------------------------------------------------
local trip = _G.CozyFishingTrip
local dlg = _G.CozyFishingDialog
local function TextShown(pattern)
    for _, f in ipairs(game.frames) do
        if f.kind == "FontString" and f:IsVisible() and (f.text or ""):find(pattern, 1, true) then return true end
    end
    return false
end
check("pole in hand: trip button", trip:IsShown() and trip.play:IsShown() and not trip.stop:IsShown())
local sessionsBefore = #ns.History.Sessions()
Cast(20)
Catch({ { id = JUNK, count = 1 } })
trip.scripts.OnClick(trip, "LeftButton")
check("trip started", ns.Trip.Active() ~= nil and trip.stop:IsShown() and not trip.play:IsShown())
check("trip starts on a fresh session", ns.session and ns.session.total == 0
    and #ns.History.Sessions() == sessionsBefore + 1)
check("the session before the trip isn't in it", #ns.Trip.Active().sessions == 0)
-- First session: in Elwynn.
game.zone = "Elwynn Forest"
Cast(20)
Catch({ { id = MACKEREL, count = 2 } })
game.Advance(60)
CozyFishing_Swap()
game.ApplyEquips()
check("pole off: the session goes into the trip", #ns.Trip.Active().sessions == 1 and ns.session == nil)
check("trip button stays without a pole while the trip goes on", trip:IsShown())
-- Second one: in Westfall, still going when the trip stops.
game.zone = "Westfall"
CozyFishing_Swap()
game.ApplyEquips()
Cast(20)
Catch({ { id = FISH, count = 3 } })
Cast(20)
game.channel = nil
game.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "cast-guid", 7620)
local live = ns.Trip.Summary(ns.Trip.Active())
check("trip so far counts the session going on", live.sessions == 2 and live.total == 5 and live.casts == 3,
    ("%d %d %d"):format(live.sessions, live.total, live.casts))
check("trip time under the button", trip.time:GetText() ~= "")
-- The trip survives a reload: it's in the character's saved variables.
check("trip kept per character", ns.char.trip == ns.Trip.Active())
-- Stop: asks first.
trip.scripts.OnClick(trip, "LeftButton")
check("stop asks first", dlg:IsShown() and dlg.which == "COZYFISHING_STOP_TRIP" and ns.Trip.Active() ~= nil)
dlg.ok.scripts.OnClick(dlg.ok, "LeftButton")
check("trip over", ns.Trip.Active() == nil and trip.play:IsShown())
local done = ns.Trip.List()[1]
check("trip in the history", done ~= nil and #done.sessions == 2 and done.ended ~= nil)
local sum = ns.Trip.Summary(done)
check("trip totals", sum.total == 5 and sum.casts == 3 and sum.catches == 2 and sum.sessions == 2)
check("trip items, most first", sum.items[1].id == FISH and sum.items[1].count == 3 and sum.items[2].id == MACKEREL)
check("trip zones", #sum.zones == 2)
check("fishing goes on in a new session", ns.session ~= nil and ns.session.total == 0)
check("report shown", ns.HistoryWindow:IsShown() and ns.HistoryWindow:Tab() == "trip")
check("report: the sessions", TextShown("Sessions (2)"))
check("report: the totals", TextShown("5 caught, 3 casts"))
-- Past trips in the history, each with its report.
ns.HistoryWindow:SetTab("trips")
local reportButton
for _, f in ipairs(game.frames) do
    if f.text == "Report" and f:IsVisible() then reportButton = f end
end
check("trips tab: a report button", reportButton ~= nil)
if reportButton then reportButton.scripts.OnClick(reportButton) end
check("report from the trips tab", ns.HistoryWindow:Tab() == "trip")
-- A trip with nothing in it isn't kept.
SlashCmdList.COZYFISHING("trip")
SlashCmdList.COZYFISHING("trip")
dlg.ok.scripts.OnClick(dlg.ok, "LeftButton")
check("empty trip: not kept", #ns.Trip.List() == 1)
check("empty trip: report says so", TextShown("Nothing caught on this trip."))
-- Without a pole anywhere and no trip: no button.
ns.db.trip.enabled = false
ns.RefreshAll()
check("trip button turned off", not trip:IsShown())
ns.db.trip.enabled = true
ns.RefreshAll()
ns.HistoryWindow:SetTab("zones")

-- Clearing the history asks first.
local hw = _G.CozyFishingHistory
hw.clear.scripts.OnClick(hw.clear, "LeftButton")
local cd = _G.CozyFishingDialog
check("clear history asks first", cd:IsShown() and cd.which == "COZYFISHING_CLEAR_HISTORY")
cd.no.scripts.OnClick(cd.no, "LeftButton")
check("clear history: No keeps it", #ns.History.Sessions() > 0)
hw.clear.scripts.OnClick(hw.clear, "LeftButton")
cd.ok.scripts.OnClick(cd.ok, "LeftButton")
check("clear history: sessions and trips gone", #ns.History.Sessions() == 0 and #ns.Trip.List() == 0)

-- Ukrainian: everything translated, and the bindings follow the language.
ns.db.locale = "ukUA"
ns.RefreshAll()
check("binding names in Ukrainian", _G.BINDING_NAME_COZYFISHING_HOOK == "Підсікти")
ns.db.locale = "enUS"

------------------------------------------------------------------------
-- Every text the addon shows has a Ukrainian translation, and the translation keeps the % formats.
------------------------------------------------------------------------
local uk = ns.LOCALES.ukUA
local keys = {}
for _, f in ipairs({ "Core", "Widgets", "History", "Keys", "Icon", "Lure", "Swap", "Trip", "Grid", "HistoryWindow",
    "Minimap", "Options" }) do
    local src = assert(io.open("CozyFishing/" .. f .. ".lua")):read("a")
    for k in src:gmatch('L%["(.-)"%]') do keys[k] = true end
    if f == "Options" then
        for _, fn in ipairs({ "Label", "Check", "Note", "Header", "Button", "Select", "Slider", "KeyPicker" }) do
            for k in src:gmatch(fn .. '%("(.-)"') do keys[k] = true end
        end
    end
    for k in src:gmatch('label = "(.-)"') do keys[k] = true end
    for k in src:gmatch('text = "(.-)"') do keys[k] = true end
end
local function Formats(s)
    local list = {}
    for spec in s:gsub("%%%%", ""):gmatch("%%[%d%.]*%a") do list[#list + 1] = spec end
    return table.concat(list, " ")
end
local languageNames = { English = true, ["Українська"] = true }
for k in pairs(keys) do
    if not languageNames[k] then
        check("translated: " .. k, uk[k] ~= nil)
        if uk[k] then check("formats kept: " .. k, Formats(uk[k]) == Formats(k), uk[k]) end
    end
end
for k in pairs(uk) do check("translation used: " .. k, keys[k]) end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
