local _, ns = ...
local L = ns.L

-- Key bindings, set in the addon's settings or in the game's Key Bindings under "Cozy Fishing" (gamepad buttons
-- too, with the gamepad turned on in the game's settings): one casts, one hooks the fish, one swaps the weapon
-- for a fishing pole and back. Cast and hook are separate, so a cast that missed the school of fish can be cast
-- again at once, line out or not.
--   Cast: a click on the hook icon, so it casts the way the icon does.
--   Hook: while a fishing pole is in hand, its keys are bound over to Interact with Target, which reels in the
--   bobber (soft targeting makes it the interact target for the session). Without a pole they do nothing, and
--   the game's own Interact with Target key stays as it is.
local Keys = {}
ns.Keys = Keys

Keys.CAST = "CLICK CozyFishingIcon:LeftButton"
Keys.HOOK = "COZYFISHING_HOOK"
Keys.SWAP = "COZYFISHING_SWAP"

local owner = CreateFrame("Frame")
local applied = "" -- the hook keys bound over now, joined

function Keys:SetNames()
    BINDING_HEADER_COZYFISHING = "Cozy Fishing"
    _G["BINDING_NAME_" .. Keys.CAST] = L["Cast"]
    _G["BINDING_NAME_" .. Keys.HOOK] = L["Hook the fish"]
    _G["BINDING_NAME_" .. Keys.SWAP] = L["Swap the fishing pole"]
end

-- A binding's name as the Key Bindings window shows it.
local function ActionName(action)
    return _G["BINDING_NAME_" .. action] or action
end

-- The keys of a binding, as the game writes them ("F", "Shift-G"), or nil.
function Keys:Text(command)
    local keys = { GetBindingKey(command) }
    if #keys == 0 then return nil end
    for i, key in ipairs(keys) do keys[i] = GetBindingText and GetBindingText(key) or key end
    return table.concat(keys, ", ")
end

local OURS = { [Keys.CAST] = true, [Keys.HOOK] = true, [Keys.SWAP] = true }

local function KeyText(key) return GetBindingText and GetBindingText(key) or key end

-- Keys that ours took from another action, to give back when ours lets them go: [key] = action.
-- Kept with the binding set in use (the character's own, or the account's).
local function Replaced()
    local set = GetCurrentBindingSet and GetCurrentBindingSet() or 1
    local t = set == 2 and ns.char or ns.db
    t.replacedKeys = t.replacedKeys or {}
    return t.replacedKeys
end

-- Binds key ("SHIFT-F", "PAD1"; nil: none) to command, in place of the keys it had, and saves the bindings.
-- A key ours lets go of does again what it did before ours took it.
function Keys:Set(command, key)
    if InCombatLockdown() then
        ns.Print(L["can't do this in combat."])
        return false
    end
    local replaced = Replaced()
    for _, old in ipairs({ GetBindingKey(command) }) do
        if old ~= key then
            SetBinding(old)
            local back = replaced[old]
            if back then
                replaced[old] = nil
                SetBinding(old, back)
                ns.Print(L["%s is back to: %s."]:format(KeyText(old), ActionName(back)))
            end
        end
    end
    if key then
        local before = GetBindingAction(key)
        if before and before ~= "" and not OURS[before] and replaced[key] == nil then replaced[key] = before end
        SetBinding(key, command)
    end
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    ns.RefreshAll()
    return true
end

local function Popup(name, text, accept, onAccept) ns.Dialog(name, text, accept, onAccept) end

-- A key picked in the settings: bound at once when it's free; a key that already does something asks first.
function Keys:Choose(command, key, done)
    local before = GetBindingAction(key)
    local function Bind()
        if self:Set(command, key) and done then done() end
    end
    if not before or before == "" or before == command then return Bind() end
    local text = L["%s is already bound to: %s."]:format(KeyText(key), ActionName(before)) .. "\n\n"
        .. L["Bind it to: %s?"]:format(ActionName(command))
    if not OURS[before] then
        text = text .. "\n" .. L["When you change or clear this key later, it goes back to: %s."]:format(ActionName(before))
    end
    Popup("COZYFISHING_KEY_TAKEN", text, L["Bind"], Bind)
end

-- The first click on a key picker explains what comes next; after that it starts at once.
function Keys:BeginPick(command, start)
    if ns.db.seen.picker then return start() end
    ns.db.seen.picker = true
    Popup("COZYFISHING_KEY_HELP", L["Setting a key for: %s."]:format(ActionName(command)) .. "\n\n"
        .. L["After Continue, the next key or combination you press is bound to it (a mouse or gamepad button too). Esc cancels. A right click on the button removes the key."],
        L["Continue"], start)
end

-- Once, at the first login with the addon: keys can be set.
function Keys:Intro()
    if ns.db.seen.keys or InCombatLockdown() then return end
    ns.db.seen.keys = true
    Popup("COZYFISHING_KEYS_INTRO", "Cozy Fishing\n\n"
        .. L["Casting, hooking the fish and swapping the weapon for a fishing pole can each have a key of your own, a gamepad button too. Set them in the addon's settings, under Keys."],
        L["Open settings"], function() ns.OpenOptions() end)
end

-- Bindings can't change in combat; the end of combat calls this again.
function Keys:Refresh()
    self:SetNames() -- the language may have changed
    if InCombatLockdown() then return end
    local want = ns.session and { GetBindingKey(Keys.HOOK) } or {}
    local sig = table.concat(want, " ")
    if sig == applied then return end
    ClearOverrideBindings(owner)
    for _, key in ipairs(want) do SetOverrideBinding(owner, false, key, "INTERACTTARGET") end
    applied = sig
    if ns.Trace then ns.Trace("hook keys: %s", sig ~= "" and sig or "none") end
end

-- The game's Key Bindings window.
function Keys:OpenBindings()
    if InCombatLockdown() then
        ns.Print(L["can't do this in combat."])
        return
    end
    if Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
        pcall(Settings.OpenToCategory, Settings.KEYBINDINGS_CATEGORY_ID)
    else
        if KeyBindingFrame_LoadUI then KeyBindingFrame_LoadUI() end
        if KeyBindingFrame then ShowUIPanel(KeyBindingFrame) end
    end
end
