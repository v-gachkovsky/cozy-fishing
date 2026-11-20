local _, ns = ...
local L = ns.L

-- The settings page, in the game's Settings > AddOns (or Interface Options on older clients). /cf opens it.
local panel, content, category
local refreshers = {}
local y = 0
local LEFT, RIGHT = 16, 300
local WIDTH = 600

function ns.RefreshOptions()
    for _, r in ipairs(refreshers) do r() end
end

local function Changed()
    ns.RefreshAll()
    ns.RefreshOptions()
end

------------------------------------------------------------------------
-- Widgets (texts are looked up on every refresh, so they follow the language)
------------------------------------------------------------------------
local function Label(key, x, template, width)
    local fs = content:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x or LEFT, y)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(L[key])
    refreshers[#refreshers + 1] = function() fs:SetText(L[key]) end
    return fs
end

local function Header(key)
    y = y - 12
    Label(key, LEFT - 4, "GameFontNormalLarge")
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", LEFT - 4, y - 22)
    line:SetPoint("TOPRIGHT", -12, y - 22)
    y = y - 32
end

local function Check(key, get, set)
    local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", LEFT - 4, y + 4)
    local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetWidth(WIDTH - LEFT - 50)
    fs:SetJustifyH("LEFT")
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Changed() end)
    refreshers[#refreshers + 1] = function()
        fs:SetText(L[key])
        cb:SetChecked(get() and true or false)
    end
    y = y - 26
end

local function Slider(key, min, max, step, get, set, format)
    Label(key, LEFT, nil, RIGHT - LEFT - 8)
    local s = CreateFrame("Slider", nil, content)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 16)
    s:SetPoint("TOPLEFT", RIGHT, y + 1)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:EnableMouse(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(0, 0, 0, 0.6)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(6)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local val = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    val:SetPoint("LEFT", s, "RIGHT", 12, 0)
    local function Show(v) val:SetText(format and format(v) or tostring(v)) end
    s:SetScript("OnValueChanged", function(self, v)
        if self.refreshing then return end
        v = math.floor(v / step + 0.5) * step
        Show(v)
        if v ~= get() then
            set(v)
            ns.RefreshAll()
        end
    end)
    refreshers[#refreshers + 1] = function()
        s.refreshing = true
        s:SetValue(get())
        s.refreshing = nil
        Show(get())
    end
    y = y - 28
end

-- Dropdown: the new menu system where the client has it, the old UIDropDownMenu otherwise.
local selectCount = 0
local function Select(key, values, get, set)
    Label(key, LEFT, nil, RIGHT - LEFT - 8)
    local function List() return type(values) == "function" and values() or values end
    local function Pick(value) set(value); Changed() end
    local ok, btn = pcall(CreateFrame, "DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    if ok and btn and btn.SetupMenu then
        btn:SetSize(200, 22)
        btn:SetPoint("TOPLEFT", RIGHT, y + 4)
        btn:SetupMenu(function(_, root)
            for _, item in ipairs(List()) do
                root:CreateRadio(L[item.text], function() return get() == item.value end, function() Pick(item.value) end)
            end
        end)
        refreshers[#refreshers + 1] = function() btn:GenerateMenu() end
    else
        selectCount = selectCount + 1 -- the old template needs a named frame
        btn = CreateFrame("Frame", "CozyFishingSelect" .. selectCount, content, "UIDropDownMenuTemplate")
        btn:SetPoint("TOPLEFT", RIGHT - 16, y + 6)
        UIDropDownMenu_SetWidth(btn, 180)
        UIDropDownMenu_Initialize(btn, function(_, level)
            for _, item in ipairs(List()) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = L[item.text]
                info.checked = get() == item.value
                info.func = function() Pick(item.value) end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
        refreshers[#refreshers + 1] = function()
            local label = tostring(get())
            for _, item in ipairs(List()) do
                if item.value == get() then label = L[item.text] end
            end
            UIDropDownMenu_SetText(btn, label)
        end
    end
    y = y - 30
end

local function Button(key, width, onClick, x)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", x or LEFT, y + 4)
    b:SetScript("OnClick", onClick)
    refreshers[#refreshers + 1] = function() b:SetText(L[key]) end
    return b
end

-- A key picker: a click, then a key or a combination (with Shift, Ctrl, Alt), a mouse button or a gamepad button
-- (with the game's gamepad modifiers). The first click ever explains it first (Keys:BeginPick); a key that already
-- does something asks before it's taken (Keys:Choose). Esc, a left click or WAIT seconds without a key cancel;
-- a right click removes the key.
local MODIFIER_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    LMETA = true, RMETA = true }
local PAD_MODIFIERS = { "GamePadEmulateShift", "GamePadEmulateCtrl", "GamePadEmulateAlt" }
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
local WAIT = 10
local pickers = {}

-- The keys go to a frame of their own, shown only while a picker waits. Not to the picker: a key script turns
-- the frame's keyboard on, and the settings page counts as shown until the game first opens it, so pickers with
-- key scripts took every key after each login and /reload. A hidden frame hears no keys.
local catcher
local function Catcher()
    if catcher then return catcher end
    catcher = CreateFrame("Frame", "CozyFishingKeyCatcher", UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetSize(1, 1)
    catcher:SetPoint("CENTER")
    catcher:Hide()
    catcher:EnableKeyboard(true)
    catcher:SetScript("OnKeyDown", function(_, k) if catcher.picker then catcher.picker.OnKey(k) end end)
    pcall(catcher.SetScript, catcher, "OnGamePadButtonDown", function(_, k)
        if catcher.picker then catcher.picker.OnPad(k) end
    end)
    if catcher.EnableGamePadButton then pcall(catcher.EnableGamePadButton, catcher, true) end
    return catcher
end

local function IsModifier(key)
    if MODIFIER_KEYS[key] then return true end
    for _, cv in ipairs(PAD_MODIFIERS) do
        local ok, v = pcall(GetCVar, cv)
        if ok and v == key then return true end
    end
    return false
end

local function Combo(key)
    local mods = ""
    if IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
    return mods .. key
end

local function KeyPicker(key, command)
    Label(key, LEFT, nil, RIGHT - LEFT - 8)
    local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    b:SetSize(200, 22)
    b:SetPoint("TOPLEFT", RIGHT, y + 4)
    b:RegisterForClicks("AnyUp")
    b.command = command
    pickers[#pickers + 1] = b

    local function Show()
        if b.waiting then
            b:SetText("|cffffd200" .. L["Press a key (Esc: cancel)"] .. "|r")
        else
            b:SetText(ns.Keys:Text(command) or ("|cff888888" .. L["not set"] .. "|r"))
        end
    end
    local function Wait(on)
        b.waiting = on or nil
        b.waitID = (b.waitID or 0) + 1
        local c = Catcher()
        if on then
            c.picker = b
            c:Show()
        elseif c.picker == b then
            c.picker = nil
            c:Hide()
        end
        if on then
            local id = b.waitID
            C_Timer.After(WAIT, function() if b.waiting and b.waitID == id then Wait(false) end end)
        end
        Show()
    end
    b.Cancel = function() if b.waiting then Wait(false) end end
    local function Pick(k)
        if not b.waiting or IsModifier(k) then return end
        Wait(false)
        ns.Keys:Choose(command, Combo(k), ns.RefreshOptions)
    end

    b:SetScript("OnClick", function(_, mouse)
        if b.waiting then
            if MOUSE_KEYS[mouse] then Pick(MOUSE_KEYS[mouse]) else Wait(false) end
        elseif mouse == "RightButton" then
            if ns.Keys:Text(command) and ns.Keys:Set(command, nil) then ns.RefreshOptions() end
        elseif mouse == "LeftButton" then
            ns.Keys:BeginPick(command, function()
                for _, other in ipairs(pickers) do other.Cancel() end
                Wait(true)
            end)
        end
    end)
    b.OnKey = function(k)
        if k == "ESCAPE" then Wait(false) else Pick(k) end
    end
    b.OnPad = Pick
    b:SetScript("OnHide", b.Cancel)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L[key], 1, 1, 1)
        GameTooltip:AddLine(L["Click, then press a key or a combination (a gamepad button too). Right-click: no key."], 0.9, 0.8, 0.5)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    refreshers[#refreshers + 1] = Show
    y = y - 30
end

local function Note(key)
    local fs = Label(key, LEFT, "GameFontDisableSmall", WIDTH - LEFT - 20)
    y = y - (fs:GetStringHeight() + 10)
    -- The height of a translated note can differ; good enough with some room left below.
end

local function Percent(v) return math.floor(v * 100 + 0.5) .. "%" end

------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------
local function Build()
    local db = ns.db

    local logo = content:CreateTexture(nil, "ARTWORK")
    logo:SetSize(32, 32)
    logo:SetPoint("TOPLEFT", LEFT - 4, -12)
    logo:SetTexture(ns.LOGO)
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("Cozy Fishing |cff888888" .. ns.VERSION .. "|r")
    y = -56

    Select("Language", ns.LANGUAGES, function() return db.locale end, function(v) db.locale = v end)
    Select("Move frames with", ns.GetMoveModes, function() return db.moveWith end, function(v) db.moveWith = v end)
    Check("Show the frames without a fishing pole (to place them)", function() return ns.placing end, function(v) ns.placing = v or nil end)
    Check("Show the minimap button", function() return not db.minimap.hide end, function(v) db.minimap.hide = not v end)

    Header("Fishing hook icon")
    Check("Show the icon while a fishing pole is in hand", function() return db.icon.enabled end, function(v) db.icon.enabled = v end)
    Check("Hide the icon and its cast timer when there are keys to cast and to hook",
        function() return db.icon.hideWithKeys end, function(v) db.icon.hideWithKeys = v end)
    Check("Lock the icon", function() return db.icon.locked end, function(v) db.icon.locked = v end)
    Slider("Icon size", 16, 160, 1, function() return db.icon.size end, function(v) db.icon.size = v end)
    Check("Clear the target when casting (so the hook goes to the bobber, not the target)",
        function() return db.icon.clearTarget end, function(v) db.icon.clearTarget = v end)
    Check("Show how long the line stays out (a bar over the hook)",
        function() return db.icon.timer end, function(v) db.icon.timer = v end)
    Check("Lure reminder: a button by the hook puts a lure from the bags on the pole",
        function() return db.icon.lure end, function(v) db.icon.lure = v end)
    Note("Left-click casts. Right-click on the icon while the line is out hooks the fish: for the session the addon turns on the game's soft targeting of objects, which makes the bobber the interact target, and puts those settings back when the pole comes off.")

    Header("Weapon and fishing pole")
    Check("Show the button that swaps the weapon for a fishing pole and back",
        function() return db.swap.enabled end, function(v) db.swap.enabled = v end)
    Check("Hide the button when there's a key to swap",
        function() return db.swap.hideWithKey end, function(v) db.swap.hideWithKey = v end)
    Check("Lock the button", function() return db.swap.locked end, function(v) db.swap.locked = v end)
    Note("A click takes a fishing pole from the bags; the next one puts back the weapon you had (it's remembered whenever a fishing pole goes on). Works in combat too.")

    Header("Fishing trip")
    Check("Show the fishing trip button", function() return db.trip.enabled end, function(v) db.trip.enabled = v end)
    Check("Lock the trip button", function() return db.trip.locked end, function(v) db.trip.locked = v end)
    Note("A session lasts while the fishing pole is in hand. A trip holds all the sessions between a click on start and a click on stop, and ends with a report: every session and the totals. Past trips are in the fishing history.")

    Header("Keys")
    Note("Your own key or combination for each, if you like: cast and hook are separate, so a cast that missed can be cast again at once. A mouse button or a gamepad button works too (with the gamepad turned on in the game's settings). They're also in the game's Key Bindings, under AddOns > Cozy Fishing.")
    KeyPicker("Cast", ns.Keys.CAST)
    KeyPicker("Hook the fish", ns.Keys.HOOK)
    KeyPicker("Swap the fishing pole", ns.Keys.SWAP)
    y = y - 4
    Button("Key bindings", 160, function() ns.Keys:OpenBindings() end)
    y = y - 34

    Header("Catch of the session")
    Check("Show the catch", function() return db.grid.enabled end, function(v) db.grid.enabled = v end)
    Check("Lock the catch", function() return db.grid.locked end, function(v) db.grid.locked = v end)
    Slider("Scale", 0.5, 3, 0.05, function() return db.grid.scale end, function(v) db.grid.scale = v end, Percent)
    Slider("Columns", 1, 12, 1, function() return db.grid.columns end, function(v) db.grid.columns = v end)
    Slider("Background opacity, %", 0, 100, 5, function() return db.grid.bgAlpha end, function(v) db.grid.bgAlpha = v end)
    Check("Show the Fishing skill", function() return db.grid.skill end, function(v) db.grid.skill = v end)
    Check("Print the catch to chat when the session ends", function() return db.summary end, function(v) db.summary = v end)
    Note("A right click on an item in the catch dims it and puts it at the end (junk); another right click brings it back. Every item caught is always shown and counts in the total.")
    local unhide = Button("Bring back all dimmed items", 260, function()
        wipe(db.hidden)
        Changed()
        ns.HistoryWindow:Refresh()
    end)
    refreshers[#refreshers + 1] = function()
        local n = ns.HiddenCount()
        unhide:SetText(L["Bring back all dimmed items"] .. (n > 0 and (" (%d)"):format(n) or ""))
        unhide:SetEnabled(n > 0)
    end
    y = y - 34
    Note("A session lasts from putting a fishing pole on to taking it off or changing it for a weapon.")

    y = y - 6
    Button("Reset positions", 160, function() ns.ResetPositions(); ns.RefreshOptions() end)
    Button("Start the catch over", 180, function() ns.ClearSession() end, LEFT + 170)
    Button("Fishing history", 160, function() ns.HistoryWindow:Toggle() end, LEFT + 360)
    y = y - 34

    content:SetHeight(-y + 20)
end

function ns.InitOptions()
    panel = CreateFrame("Frame")
    panel.name = "Cozy Fishing"
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 600)
    scroll:SetScrollChild(content)
    Build()
    panel:SetScript("OnShow", ns.RefreshOptions)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Cozy Fishing")
        if ok and cat then
            category = cat
            pcall(Settings.RegisterAddOnCategory, cat)
        end
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ns.OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        if not pcall(Settings.OpenToCategory, id) then pcall(Settings.OpenToCategory, category) end
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice: the first call may only open the window.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end
