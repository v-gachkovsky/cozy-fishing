local ADDON, ns = ...
local L = ns.L

-- The settings page, in the game's Settings > AddOns (or Interface Options on older clients). /ef opens it.
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
        btn = CreateFrame("Frame", "EasyFishingSelect" .. selectCount, content, "UIDropDownMenuTemplate")
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
    title:SetText("Easy Fishing |cff888888" .. ns.VERSION .. "|r")
    y = -56

    Select("Language", ns.LANGUAGES, function() return db.locale end, function(v) db.locale = v end)
    Select("Move frames with", ns.GetMoveModes, function() return db.moveWith end, function(v) db.moveWith = v end)
    Check("Show the frames without a fishing pole (to place them)", function() return ns.placing end, function(v) ns.placing = v or nil end)

    Header("Fishing hook icon")
    Check("Show the icon while a fishing pole is in hand", function() return db.icon.enabled end, function(v) db.icon.enabled = v end)
    Check("Lock the icon", function() return db.icon.locked end, function(v) db.icon.locked = v end)
    Slider("Icon size", 16, 160, 1, function() return db.icon.size end, function(v) db.icon.size = v end)
    Check("Clear the target when casting (so the hook goes to the bobber, not the target)",
        function() return db.icon.clearTarget end, function(v) db.icon.clearTarget = v end)
    Note("Left-click casts. Right-click on the icon while the line is out hooks the fish: for the session the addon turns on the game's soft targeting of objects, which makes the bobber the interact target, and puts those settings back when the pole comes off.")

    Header("Catch of the session")
    Check("Show the catch", function() return db.grid.enabled end, function(v) db.grid.enabled = v end)
    Check("Lock the catch", function() return db.grid.locked end, function(v) db.grid.locked = v end)
    Slider("Scale", 0.5, 3, 0.05, function() return db.grid.scale end, function(v) db.grid.scale = v end, Percent)
    Slider("Columns", 1, 12, 1, function() return db.grid.columns end, function(v) db.grid.columns = v end)
    Slider("Background opacity, %", 0, 100, 5, function() return db.grid.bgAlpha end, function(v) db.grid.bgAlpha = v end)
    Check("Print the catch to chat when the session ends", function() return db.summary end, function(v) db.summary = v end)
    Note("A session lasts from putting a fishing pole on to taking it off or changing it for a weapon.")

    y = y - 6
    Button("Reset positions", 160, function() ns.ResetPositions(); ns.RefreshOptions() end)
    Button("Start the catch over", 180, function() ns.ClearSession() end, LEFT + 170)
    y = y - 34

    content:SetHeight(-y + 20)
end

function ns.InitOptions()
    panel = CreateFrame("Frame")
    panel.name = "Easy Fishing"
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH, 600)
    scroll:SetScrollChild(content)
    Build()
    panel:SetScript("OnShow", ns.RefreshOptions)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Easy Fishing")
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
