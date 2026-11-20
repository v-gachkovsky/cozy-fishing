local _, ns = ...
local L = ns.L

-- The swap button: takes a fishing pole from the bags, and puts the weapon you had back. The weapons in hand
-- before the pole went on are remembered per character (char.weapons = { main, off }), whatever put the pole on;
-- the pole too (char.pole), for the next time. A plain (not secure) button: the game lets weapons be swapped in
-- combat, so it works there too, the way a mob coming at you while fishing needs it.
-- A key for it: the COZYFISHING_SWAP binding (Bindings.xml calls CozyFishing_Swap).
local Swap = {}
ns.Swap = Swap

local MAIN, OFF = INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17
-- Equipment events of one swap come apart (the off hand empties, then the pole lands, or the other way round):
-- the weapons in hand are taken as the ones to remember only once the hands have been still for this long.
local SETTLE = 0.6
-- The off hand goes on once the main hand weapon is in (both at once can leave the pole's two hands in the way).
local OFF_WAIT = 5

local GetItemCount = GetItemCount or (C_Item and C_Item.GetItemCount)
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local EquipItemByName = EquipItemByName or (C_Item and C_Item.EquipItemByName)
local Container = C_Container or {}
local NumSlots = Container.GetContainerNumSlots or GetContainerNumSlots
local SlotItemID = Container.GetContainerItemID or GetContainerItemID
local BAGS = NUM_BAG_SLOTS or 4

local btn
local settle = 0      -- a counter, so only the last of a burst of equipment events takes the snapshot
local pendingOff      -- { id, until }: the off hand to put on after the main hand

local function Cfg() return ns.db.swap end

local function InBags(id) return id ~= nil and GetItemCount ~= nil and (GetItemCount(id) or 0) > 0 end

local function ItemName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if not name or ns.IsSecret(name) then return ("item:%d"):format(id) end
    return name
end

------------------------------------------------------------------------
-- What's in hand, what to remember
------------------------------------------------------------------------
local function Hands()
    return GetInventoryItemID("player", MAIN), GetInventoryItemID("player", OFF)
end

-- The weapons in hand now, when there's no pole among them.
local function Remember()
    local main, off = Hands()
    if main and ns.IsPole(main) then
        ns.char.pole = main
        return
    end
    if main or off then ns.char.weapons = { main = main, off = off } end
end

-- After any equipment change: remembered once things settle; the off hand that waits goes on.
function Swap:EquipmentChanged()
    settle = settle + 1
    local mine = settle
    C_Timer.After(SETTLE, function()
        if mine ~= settle then return end
        Remember()
        Swap:Refresh()
    end)
    local p = pendingOff
    if p then
        local main, off = Hands()
        if GetTime() > p.till or off == p.id then
            pendingOff = nil
        elseif not (main and ns.IsPole(main)) then
            pendingOff = nil
            EquipItemByName(p.id, OFF)
        end
    end
    self:Refresh()
end

-- A fishing pole in the bags: the one used last, or the first found.
function Swap.FindPole()
    local last = ns.char.pole
    if InBags(last) then return last end
    if not (NumSlots and SlotItemID) then return nil end
    for bag = 0, BAGS do
        for slot = 1, NumSlots(bag) or 0 do
            local id = SlotItemID(bag, slot)
            if id and ns.IsPole(id) then return id end
        end
    end
end

-- The remembered weapons that are in the bags: main, off (either may be nil).
function Swap.Weapons()
    local w = ns.char.weapons
    if not w then return nil, nil end
    return InBags(w.main) and w.main or nil, InBags(w.off) and w.off or nil
end

-- What a click does now: "pole", id / "weapons", main, off / nil.
function Swap.Next()
    if ns.PoleEquipped() then
        local main, off = Swap.Weapons()
        if main or off then return "weapons", main, off end
        return nil
    end
    local pole = Swap.FindPole()
    if pole then return "pole", pole end
end

function Swap.Toggle()
    if not EquipItemByName then return end
    if ns.PoleEquipped() then
        local main, off = Swap.Weapons()
        if not (main or off) then
            ns.Print(ns.char.weapons and L["the weapon you had isn't in the bags."]
                or L["no weapon to go back to yet: it's remembered when the fishing pole goes on."])
            return
        end
        if main then
            EquipItemByName(main, MAIN)
            if off then pendingOff = { id = off, till = GetTime() + OFF_WAIT } end
        else
            EquipItemByName(off, OFF)
        end
        if ns.Trace then ns.Trace("swap: back to %s / %s", tostring(main), tostring(off)) end
    else
        local pole = Swap.FindPole()
        if not pole then
            ns.Print(L["no fishing pole in the bags."])
            return
        end
        Remember() -- what's in hand now is what comes back
        pendingOff = nil
        EquipItemByName(pole, MAIN)
        if ns.Trace then ns.Trace("swap: fishing pole %d", pole) end
    end
end

-- The key binding (Bindings.xml).
function CozyFishing_Swap() Swap.Toggle() end

------------------------------------------------------------------------
-- The button
------------------------------------------------------------------------
local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Swap the fishing pole"], 1, 1, 1)
    local what, a, b = Swap.Next()
    if what == "pole" then
        GameTooltip:AddLine(L["Click: take %s"]:format(ItemName(a)), 0.9, 0.8, 0.5)
    elseif what == "weapons" then
        local names = {}
        if a then names[#names + 1] = ItemName(a) end
        if b then names[#names + 1] = ItemName(b) end
        GameTooltip:AddLine(L["Click: back to %s"]:format(table.concat(names, ", ")), 0.9, 0.8, 0.5)
    end
    local key = ns.Keys:Text(ns.Keys.SWAP)
    if key then GameTooltip:AddLine(L["Key: %s"]:format(key), 0.9, 0.8, 0.5) end
    if not Cfg().locked then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["%s to move, the corner to resize"]:format(ns.MoveModeText()), 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

function Swap:Create()
    btn = CreateFrame("Button", "CozyFishingSwap", UIParent)
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
    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    btn:SetScript("OnClick", function()
        if ns.MoveModifierDown() and not Cfg().locked then return end -- that click was for moving it
        Swap.Toggle()
    end)
    btn:SetScript("OnEnter", Tooltip)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    ns.MakeMovable(btn, Cfg)
    ns.MakeGrip(btn, {
        get = function() return Cfg().size end,
        set = function(v) Cfg().size = math.floor(v + 0.5) end,
        min = 16, max = 96,
        apply = function() Swap:Refresh() end,
    })
    Remember()
end

-- Not secure, so it can show and hide in combat too.
function Swap:Refresh()
    if not btn then return end
    local cfg = Cfg()
    btn:SetSize(cfg.size, cfg.size)
    ns.ApplyPoint(btn, cfg.point)
    local what, a, b = Swap.Next()
    local id = a or b
    if id then btn.icon:SetTexture(ns.ItemIcon(id)) end
    if not id and ns.placing then btn.icon:SetTexture(ns.FISHING_ICON) end
    -- With a key to swap, the button can go (shown while placing the frames).
    local byKey = cfg.hideWithKey and not ns.placing and ns.Keys:Text(ns.Keys.SWAP) ~= nil
    btn:SetShown(cfg.enabled and not byKey and (what ~= nil or ns.placing) or false)
    if GameTooltip:IsOwned(btn) then Tooltip(btn) end
end
