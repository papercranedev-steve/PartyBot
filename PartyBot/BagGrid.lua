-- Bag grid: what the companion bag panels share (Bags.lua beside his sheet, TeamBags.lua beside
-- your own bags): each companion's inventory as the server last sent it, his bag slots drawn like
-- your bags, his item "held" on the mouse and where it can go.
--
--   local view = ns.BagGrid.NewView(parent, moneyBar)  -- moneyBar: frame whose bottom gets his coin
--   view:SetBot(name)  view:Render()  view.frame (sized by Render)  view.OnLayout = fn(view)
--   ns.BagGrid.Request(name)          ask the server again (.partybot bags)
--   ns.BagGrid.OnInventory(fn)        fn(name) after his inventory came (views redraw by themselves)
--   ns.BagGrid.OnRefused(fn)          fn(name, code): no bags for him (locked / notbot / notfound)
--   ns.BagGrid.DropOnBot(name)        a click or drop on something standing for him (a tab):
--                                     what you or another companion hold goes to him; true if so
--   ns.BagGrid.SlotDrop(name, bag, slot)  your item dropped (OnReceiveDrag) on that slot of his
--   ns.BagGrid.TakeYours(name, bag, slot) your item in your bag `bag`, slot from 1, goes to him
--   ns.BagGrid.GearSlots(itemId)      { [equipment slot 0-18] = true } where it can be worn, or nil
--   ns.BagGrid.OnHand(fn)             fn(itemId or nil) when what you hold changed (his item on
--                                     our icon, or yours on the game cursor): gear slots light up
--   frame.dropBotName = name          (or a function) a frame standing for him, for drags
--
-- Using the slots (the tooltip says it too):
--   right-click           your bags open (beside his, or anywhere): it goes to you (.partybot
--                         giveslot); else he equips / uses it (.partybot equipslot / useslot)
--   shift + right-click   the other one of the two
--   drag, or click + click  his bag slots, his gear on the sheet: move, equip, unequip, swap,
--                         merge (.partybot moveslot); another companion's slots, tab or panel:
--                         he hands it over (.partybot passslot); a slot of your bags or of your
--                         paper doll: it goes there (to your bags elsewhere in the window). The
--                         gear slots it fits light up, on the sheet and on your paper doll.
--   your item dropped on his slots, tab or panel: it goes to him (.partybot takeslot), on a slot
--                         into that slot (a gear slot: he puts it on)
-- A drop on one slot sends the slot along (`<bag 0-5> <slot>` at the end of giveslot / takeslot /
-- passslot): the item lands there, swaps with what is there, or he / you put it on; where it can't
-- go there it goes anywhere in the bags (server BotShared::Handover::Plan).
-- His bank (Bank.lua, at a banker) uses the same slots with bag 6 (the bank, slots 0-23, its bag
-- slots 24-29) and 7-12 (bank bags): frames with .dropToBank = true stand for his bank, and his
-- items dropped between his bank and his bags move over (.partybot autobank).
--   ns.BagGrid.NewView(parent, moneyBar, { bags = fn(view) -> { bag, ... }, inventory = fn(name), bank = true })
--   ns.BagGrid.SetRightClick({ click = fn(name, bag, slot, itemId) -> true if done, tip = fn(name, bag) })
--                                     another window takes right-click over while it is open (the
--                                     bank): tip gives its tooltip line, nil where it does not
--   ns.BagGrid.OnChanged(fn)          fn(name) when his inventory changed on the server
-- Replies: PBINV (bags; M = coin), PBOK equip/unequip/use/give/take/pass/takemoney/move, PBERR.

local _, ns = ...
local L = ns.L

local BagGrid = {}
ns.BagGrid = BagGrid

local BUTTON_SIZE = 37
local BUTTON_STEP = 39
local COLUMNS = 10
local BAG_GAP = 6
BagGrid.WIDTH = COLUMNS * BUTTON_STEP - (BUTTON_STEP - BUTTON_SIZE)
BagGrid.MONEY_HEIGHT = 22
BagGrid.BUTTON_SIZE, BagGrid.BUTTON_STEP, BagGrid.COLUMNS = BUTTON_SIZE, BUTTON_STEP, COLUMNS
local BANK = 6          -- bag index of his bank (7-12: his bank bags); below it: his bags and gear
BagGrid.BANK = BANK

local function IsBank(bag) return bag and bag >= BANK end

local SendCommand, ShowError, ShowOk, ItemName = ns.SendCommand, ns.ShowError, ns.ShowOk, ns.ItemName

---------------------------------------------------------------------------
-- inventories: [name] = { bags = { [0-4] = { size, items = { {id, count} or false } } },
--                         money = { copper, canTake, takeAt } or nil }
---------------------------------------------------------------------------

local inventories = {}
local incoming = {}     -- [name] = inventory being received
local pending = {}      -- [name] = true: a bags request without answer yet
local views = {}
local inventoryHandlers, refusedHandlers, changedHandlers = {}, {}, {}
local rightClick        -- SetRightClick: a window that takes right-click over (the bank)

function BagGrid.Inventory(name) return name and inventories[name] end

-- from a click (may go out as SAY) or from a timer while in a group
function BagGrid.Request(name)
    if not name then return end
    pending[name] = true
    if IsInGroup() then ns.SendCommandAuto(".partybot bags " .. name) else SendCommand(".partybot bags " .. name) end
end

function BagGrid.OnInventory(fn) inventoryHandlers[#inventoryHandlers + 1] = fn end
function BagGrid.OnRefused(fn) refusedHandlers[#refusedHandlers + 1] = fn end
function BagGrid.OnChanged(fn) changedHandlers[#changedHandlers + 1] = fn end
function BagGrid.SetRightClick(handler) rightClick = handler end

local function Viewed(name)
    for _, v in ipairs(views) do
        if v.name == name and v.frame:IsVisible() then return true end
    end
    return false
end

local fresh = {}        -- [name] = true: his bags came with the server's answer (before its PBOK)

-- other modules: his bags changed on the server (a quest drop, a hand-over). The bag commands'
-- answers carry his bags along (PBINV before PBOK): then nothing is asked again and nothing waits.
function ns.BotInventoryChanged(name)
    if not name then return end
    local arrived = fresh[name]
    fresh[name] = nil
    if arrived then
        -- (the views drew it already)
    elseif Viewed(name) then
        C_Timer.After(0.3, function() BagGrid.Request(name) end)
    else
        inventories[name] = nil     -- asked again when someone looks
    end
    local c = ns.Sheet and ns.Sheet.Current()
    if c and c.name == name then    -- his gear on the sheet
        if arrived then ns.Sheet.Reload() else C_Timer.After(0.3, ns.Sheet.Reload) end
    end
    for _, fn in ipairs(changedHandlers) do fn(name) end
end

---------------------------------------------------------------------------
-- what you hold: his item on our own mouse icon (the game cursor only holds your items)
-- positions are the server's: bag 0-4 + slot from 0, or bag 5 + equipment slot 0-18
---------------------------------------------------------------------------

local held      -- { name, bag, slot, itemId }
local PLAYER = {}       -- drop target: you (your bags, your gear)

---------------------------------------------------------------------------
-- gear slots an item goes to (server equipment slots 0-18), to light them up
---------------------------------------------------------------------------

-- server equipment slot -> paper doll slot name (your own slot button: "Character" .. name)
BagGrid.GEAR_SLOT_NAMES = {
    [0] = "HeadSlot", [1] = "NeckSlot", [2] = "ShoulderSlot", [3] = "ShirtSlot", [4] = "ChestSlot",
    [5] = "WaistSlot", [6] = "LegsSlot", [7] = "FeetSlot", [8] = "WristSlot", [9] = "HandsSlot",
    [10] = "Finger0Slot", [11] = "Finger1Slot", [12] = "Trinket0Slot", [13] = "Trinket1Slot",
    [14] = "BackSlot", [15] = "MainHandSlot", [16] = "SecondaryHandSlot", [17] = "RangedSlot", [18] = "TabardSlot",
}

-- (one-handers light up the off hand too, as yours do; the server knows who can dual wield)
local GEAR_SLOTS = {
    INVTYPE_HEAD = { 0 }, INVTYPE_NECK = { 1 }, INVTYPE_SHOULDER = { 2 }, INVTYPE_BODY = { 3 },
    INVTYPE_CHEST = { 4 }, INVTYPE_ROBE = { 4 }, INVTYPE_WAIST = { 5 }, INVTYPE_LEGS = { 6 },
    INVTYPE_FEET = { 7 }, INVTYPE_WRIST = { 8 }, INVTYPE_HAND = { 9 }, INVTYPE_FINGER = { 10, 11 },
    INVTYPE_TRINKET = { 12, 13 }, INVTYPE_CLOAK = { 14 }, INVTYPE_WEAPON = { 15, 16 },
    INVTYPE_2HWEAPON = { 15 }, INVTYPE_WEAPONMAINHAND = { 15 }, INVTYPE_WEAPONOFFHAND = { 16 },
    INVTYPE_SHIELD = { 16 }, INVTYPE_HOLDABLE = { 16 }, INVTYPE_RANGED = { 17 }, INVTYPE_THROWN = { 17 },
    INVTYPE_RANGEDRIGHT = { 17 }, INVTYPE_RELIC = { 17 }, INVTYPE_TABARD = { 18 },
}

function BagGrid.GearSlots(itemId)
    local equipLoc = itemId and select(4, GetItemInfoInstant(itemId))
    local list = equipLoc and GEAR_SLOTS[equipLoc]
    if not list then return nil end
    local set = {}
    for _, s in ipairs(list) do set[s] = true end
    return set
end

local handHandlers = {}
function BagGrid.OnHand(fn) handHandlers[#handHandlers + 1] = fn end

local function HandChanged()
    local itemId = held and held.itemId
    if not itemId then
        local kind, id = GetCursorInfo()
        if kind == "item" then itemId = id end
    end
    for _, fn in ipairs(handHandlers) do fn(itemId) end
end

-- your own gear slots light up for his item as for yours (Blizzard does it for the game cursor:
-- PaperDollItemSlotButton_OnEvent CURSOR_UPDATE)
local lit = {}
BagGrid.OnHand(function()
    for id in pairs(lit) do
        local b = _G["Character" .. BagGrid.GEAR_SLOT_NAMES[id]]
        if b and not CursorCanGoInSlot(b:GetID()) then b:UnlockHighlight() end
    end
    wipe(lit)
    for id in pairs(held and BagGrid.GearSlots(held.itemId) or {}) do
        local b = _G["Character" .. BagGrid.GEAR_SLOT_NAMES[id]]
        if b then
            b:LockHighlight()
            lit[id] = true
        end
    end
end)

---------------------------------------------------------------------------
-- his item on the mouse
---------------------------------------------------------------------------

local cursor = CreateFrame("Frame", "PartyBotBagsHeldItem", UIParent)
cursor:SetSize(BUTTON_SIZE, BUTTON_SIZE)
cursor:SetFrameStrata("TOOLTIP")
cursor:EnableMouse(false)
cursor.icon = cursor:CreateTexture(nil, "OVERLAY")
cursor.icon:SetAllPoints()
cursor:Hide()
tinsert(UISpecialFrames, "PartyBotBagsHeldItem")     -- Esc puts it back

-- over your bag windows and your gear slots while you hold his item: a click there would pick up
-- your own item. Over your bags, the slot under the mouse lights up and takes it.
local bagCatchers, gearCatchers = {}, {}

local function HideCatchers()
    for _, c in ipairs(bagCatchers) do c:Hide() end
    for _, c in pairs(gearCatchers) do c:Hide() end
end

function BagGrid.Cancel()
    held = nil
    cursor:Hide()
end
cursor:SetScript("OnHide", function()
    held = nil
    HideCatchers()
    HandChanged()
end)

local function MouseFocus()
    if GetMouseFoci then return GetMouseFoci()[1] end
    return GetMouseFocus()
end

-- who and which slot a frame stands for: name, bag, slot (bag nil: anywhere in his bags, or with
-- toBank anywhere in his bank), toBank. Server numbering: bag 0-4 + slot from 0, 5 + gear slot.
local function TargetOf(f)
    if not f then return nil end
    if f.isPlayerBags then
        local bag, slot = ns.PlayerBags.SlotUnderMouse()
        return PLAYER, bag, slot and slot - 1
    end
    if f.isPlayerGear then return PLAYER, 5, f.serverSlot end
    if f.isBotBagSlot then return f.view.name, f.bag, f.slot end
    if f.isSheetGear then
        local c = ns.Sheet and ns.Sheet.Current()
        return c and c.name, 5, f.serverSlot
    end
    local n = f.dropBotName
    if type(n) == "function" then n = n() end
    return n, nil, nil, f.dropToBank == true
end

-- the place a hand-over aims at, at the end of giveslot / takeslot / passslot ("": anywhere in the
-- bags; his bank's slots are not places for it)
local function At(bag, slot)
    if bag and slot and bag <= 5 then return (" %d %d"):format(bag, slot) end
    return ""
end

-- his held item goes to `name` (PLAYER: you), into that slot if given; dropped on his bank or his
-- bags as a whole, it moves from one into the other
local function PutHeld(name, bag, slot, toBank)
    local from = held
    BagGrid.Cancel()
    if not from or not name then return end
    if name == PLAYER then
        SendCommand((".partybot giveslot %s %d %d%s"):format(from.name, from.bag, from.slot, At(bag, slot)))
    elseif name ~= from.name then
        if IsBank(from.bag) then
            ShowError(L["baggrid.err.bank_pass"])   -- (hand-overs take what he carries)
        else
            SendCommand((".partybot passslot %s %d %d %s%s"):format(from.name, from.bag, from.slot, name, At(bag, slot)))
        end
    elseif bag then
        if bag ~= from.bag or slot ~= from.slot then
            SendCommand((".partybot moveslot %s %d %d %d %d"):format(from.name, from.bag, from.slot, bag, slot))
        end
    elseif from.bag ~= 5 and IsBank(from.bag) ~= (toBank == true) then
        SendCommand((".partybot autobank %s %d %d"):format(from.name, from.bag, from.slot))
    end
end

local function LockedContainerSlot(container, itemId)
    for slot = 1, GetContainerNumSlots(container) do
        local _, _, locked = GetContainerItemInfo(container, slot)
        if locked and GetContainerItemID(container, slot) == itemId then return slot end
    end
end

-- Which of your slots holds the item on the cursor: the source slot is locked while picked up.
-- Returns server numbering (your bank too, while it is open: bag 6-12 as his).
-- Note: for a split stack the whole source stack is moved.
local function FindCursorSource(itemId)
    for bag = 0, 4 do
        local slot = LockedContainerSlot(bag, itemId)
        if slot then return bag, slot - 1 end
    end
    for invSlot = 1, 19 do
        if IsInventoryItemLocked(invSlot) and GetInventoryItemID("player", invSlot) == itemId then
            return 5, invSlot - 1
        end
    end
    if not (BankFrame and BankFrame:IsShown()) and not ns.BankOpen then return nil end
    local slot = LockedContainerSlot(BANK_CONTAINER, itemId)
    if slot then return BANK, slot - 1 end
    for i = 1, NUM_BANKBAGSLOTS do
        slot = LockedContainerSlot(NUM_BAG_SLOTS + i, itemId)
        if slot then return BANK + i, slot - 1 end
        local invSlot = BankButtonIDToInvSlotID(i, 1)     -- the bank bag itself
        if IsInventoryItemLocked(invSlot) and GetInventoryItemID("player", invSlot) == itemId then
            return BANK, NUM_BANKGENERIC_SLOTS + i - 1
        end
    end
end

-- your item on the game cursor goes to `name`: into his bank if toBank, onto his slot bag/slot if
-- given. True if the cursor held an item.
local function GiveCursorItem(name, toBank, bag, slot)
    local kind, itemId = GetCursorInfo()
    if kind ~= "item" or not name or name == PLAYER then return false end
    local fromBag, fromSlot = FindCursorSource(itemId)
    ClearCursor()
    if not fromBag then
        ShowError(L["baggrid.err.drop_source"])
        return true
    end
    SendCommand((".partybot takeslot %s %d %d%s"):format(name, fromBag, fromSlot, toBank and " bank" or At(bag, slot)))
    return true
end

function BagGrid.DropOnBot(name, toBank)
    if GiveCursorItem(name, toBank) then return true end
    if held then
        PutHeld(name, nil, nil, toBank)
        return true
    end
    return false
end

function BagGrid.SlotDrop(name, bag, slot)
    return GiveCursorItem(name, IsBank(bag), bag, slot)
end

function BagGrid.TakeYours(name, bag, slot)
    if not name or not GetContainerItemID(bag, slot) then return end
    local _, _, locked = GetContainerItemInfo(bag, slot)
    if locked then return end
    SendCommand((".partybot takeslot %s %d %d"):format(name, bag, slot - 1))
end

local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"    -- (an item slot's own mouse-over light)

local function Catcher(isGear)
    local c = CreateFrame("Frame", nil, UIParent)
    c:EnableMouse(true)
    c.glow = c:CreateTexture(nil, "OVERLAY")
    c.glow:SetTexture(HIGHLIGHT)
    c.glow:SetBlendMode("ADD")
    c.glow:SetAllPoints()
    c.glow:Hide()
    c:SetScript("OnEnter", function(self)
        if isGear then self.glow:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(L[isGear and "baggrid.to_you_wear" or "baggrid.to_you"])
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function(self)
        if isGear then self.glow:Hide() end
        GameTooltip:Hide()
    end)
    c:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then PutHeld(TargetOf(self)) else BagGrid.Cancel() end
    end)
    return c
end

local function BagCatcher(i)
    if bagCatchers[i] then return bagCatchers[i] end
    local c = Catcher(false)
    c.isPlayerBags = true
    -- the light sits on the slot under the mouse (bag addons lay their slots out again at times)
    c:SetScript("OnUpdate", function(self)
        local b
        if self:IsMouseOver() then b = select(3, ns.PlayerBags.SlotUnderMouse()) end
        if b == self.litButton then return end
        self.litButton = b
        self.glow:ClearAllPoints()
        if b then self.glow:SetAllPoints(b) end
        self.glow:SetShown(b ~= nil)
    end)
    bagCatchers[i] = c
    return c
end

local function GearCatcher(serverSlot)
    if gearCatchers[serverSlot] then return gearCatchers[serverSlot] end
    local c = Catcher(true)
    c.isPlayerGear = true
    c.serverSlot = serverSlot
    gearCatchers[serverSlot] = c
    return c
end

local function ShowCatchers()
    HideCatchers()
    for i, f in ipairs(ns.PlayerBags.Shown()) do
        local c = BagCatcher(i)
        c:ClearAllPoints()
        c:SetAllPoints(f)
        c:SetFrameStrata("DIALOG")
        c.litButton = nil
        c.glow:Hide()
        c:Show()
    end
    if PaperDollFrame and PaperDollFrame:IsVisible() then
        for serverSlot, slotName in pairs(BagGrid.GEAR_SLOT_NAMES) do
            local b = _G["Character" .. slotName]
            if b and b:IsVisible() then
                local c = GearCatcher(serverSlot)
                c:ClearAllPoints()
                c:SetAllPoints(b)
                c:SetFrameStrata("DIALOG")
                c.glow:Hide()
                c:Show()
            end
        end
    end
end
local function CatchersAgain() if held then ShowCatchers() end end
ns.PlayerBags.OnChange(CatchersAgain)
if PaperDollFrame then
    PaperDollFrame:HookScript("OnShow", CatchersAgain)
    PaperDollFrame:HookScript("OnHide", CatchersAgain)
end

cursor:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    -- a drag ends where the button is let go; over nothing he keeps holding it (like your bags)
    if self.dragging and not IsMouseButtonDown("LeftButton") then
        self.dragging = false
        local name, bag, slot, toBank = TargetOf(MouseFocus())
        if name then PutHeld(name, bag, slot, toBank) end
    end
end)

local function PickUp(name, bag, slot, itemId, dragging)
    if not name then return end
    held = { name = name, bag = bag, slot = slot, itemId = itemId }
    cursor.icon:SetTexture(GetItemIcon(itemId))
    cursor.dragging = dragging
    cursor:Show()
    ShowCatchers()
    HandChanged()
end

function BagGrid.Holding() return held ~= nil end

---------------------------------------------------------------------------
-- a slot of his (bag slot or gear slot on the sheet): clicks and drags
---------------------------------------------------------------------------

-- What right-click and shift+right-click do with his item in a bag slot: "bank" (the bank window
-- took right-click over), "you" (into your bags: while yours are open, beside his or not), "use"
-- (he equips / uses it). Shift: into your bags, or he uses it when that is what right-click does.
local function RightClickActions(name, bag)
    local plain
    if rightClick and rightClick.tip(name, bag) then
        plain = "bank"
    else
        plain = ns.PlayerBags.Main() and "you" or "use"
    end
    return plain, plain == "you" and "use" or "you"
end

-- Returns true if handled. bag 5 = his gear.
function BagGrid.SlotClick(name, bag, slot, itemId, button)
    if not name then return false end
    if GiveCursorItem(name, IsBank(bag), bag, slot) then return true end
    if button == "LeftButton" then
        if held then
            PutHeld(name, bag, slot)
            return true
        end
        if itemId and not IsModifierKeyDown() then
            PickUp(name, bag, slot, itemId, false)
            return true
        end
        return false
    end
    if held then
        BagGrid.Cancel()    -- right click puts it back
        return true
    end
    if button ~= "RightButton" or not itemId then return false end
    local action
    if bag == 5 then
        action = IsShiftKeyDown() and "you" or "unequip"
    else
        local plain, shifted = RightClickActions(name, bag)
        action = IsShiftKeyDown() and shifted or plain
    end
    if action == "you" then
        SendCommand((".partybot giveslot %s %d %d"):format(name, bag, slot))
    elseif action == "bank" then
        rightClick.click(name, bag, slot, itemId)   -- (into his bank, or out of it)
    elseif action == "unequip" then
        SendCommand((".partybot unequipslot %s %d"):format(name, slot))
    elseif IsEquippableItem(itemId) then
        SendCommand((".partybot equipslot %s %d %d"):format(name, bag, slot))
    elseif GetItemSpell(itemId) then
        SendCommand((".partybot useslot %s %d %d"):format(name, bag, slot))
    else
        ShowError(L("baggrid.err.item", { item = ItemName(itemId), error = ns.ERROR_TEXT.notusable }))
    end
    return true
end

function BagGrid.SlotDragStart(name, bag, slot, itemId)
    if name and itemId and not held then PickUp(name, bag, slot, itemId, true) end
end

---------------------------------------------------------------------------
-- coin: shown under the slots, taken from affinity 50 on (server Gates TakeMoney)
---------------------------------------------------------------------------

local function TakeMoney(name, copper)
    if name and copper and copper > 0 then
        SendCommand((".partybot takemoney %s %d"):format(name, copper))
    end
end

-- like the guild bank's withdraw dialog
StaticPopupDialogs["PARTYBOT_TAKE_MONEY"] = {
    text = "%s",     -- L("baggrid.take_money.dialog"), filled in by the caller
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, name)
        TakeMoney(name, MoneyInputFrame_GetCopper(self.moneyInputFrame))
    end,
    OnHide = function(self)
        MoneyInputFrame_ResetMoney(self.moneyInputFrame)
    end,
    EditBoxOnEnterPressed = function(self, name)
        local parent = self:GetParent():GetParent()
        TakeMoney(name, MoneyInputFrame_GetCopper(parent.moneyInputFrame))
        parent:Hide()
    end,
    hasMoneyInputFrame = 1,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local moneyFrames = 0

local function BuildMoney(view, bar)
    moneyFrames = moneyFrames + 1
    local m = {}
    -- (MoneyFrame needs a name: its parts are found by it; coins only, like your backpack)
    m.money = CreateFrame("Frame", "PartyBotBagsMoneyFrame" .. moneyFrames, bar, "SmallMoneyFrameTemplate")
    MoneyFrame_SetType(m.money, "STATIC")
    m.money:SetPoint("BOTTOMLEFT", 14, 10)
    m.take = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    m.take:SetSize(80, 22)
    m.take:SetPoint("BOTTOMRIGHT", -6, 4)
    m.take:SetText(L["baggrid.take_money"])
    m.take:SetMotionScriptsWhileDisabled(true)
    m.take:SetScript("OnClick", function()
        if view.name then
            StaticPopup_Show("PARTYBOT_TAKE_MONEY", L("baggrid.take_money.dialog", { name = view.name }), nil, view.name)
        end
    end)
    m.take:SetScript("OnEnter", function(self)
        local inv = BagGrid.Inventory(view.name)
        if self:IsEnabled() or not inv or not inv.money then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["baggrid.take_money.tip"])
        GameTooltip:AddLine(L("baggrid.take_money.locked", { affinity = inv.money.takeAt }), 1, 1, 1)
        GameTooltip:Show()
    end)
    m.take:SetScript("OnLeave", GameTooltip_Hide)
    return m
end

local function RenderMoney(m, money)
    m.money:SetShown(money ~= nil)
    m.take:SetShown(money ~= nil)
    if money then
        MoneyFrame_Update(m.money, money.copper, true)     -- (forceShow: nothing is "0 copper", not blank)
        m.take:SetEnabled(money.canTake and money.copper > 0)
    end
end

---------------------------------------------------------------------------
-- view: his bags, one block of slots per bag, like your bag window
---------------------------------------------------------------------------

-- the tooltip line of a right-click action (RightClickActions), nil when it does nothing here
local function ActionTip(action, shifted, name, bag, itemId)
    if action == "bank" then return rightClick.tip(name, bag) end
    if action == "you" then return shifted and L["baggrid.tip.give"] or L["baggrid.tip.to_you"] end
    if IsEquippableItem(itemId) then return shifted and L["baggrid.tip.equip_shift"] or L["baggrid.tip.equip"] end
    if GetItemSpell(itemId) then return shifted and L["baggrid.tip.use_shift"] or L["baggrid.tip.use"] end
end

local function OnSlotEnter(self)
    if not self.itemId then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.itemId)
    GameTooltip:AddLine(" ")
    local plain, shifted = RightClickActions(self.view.name, self.bag)
    for i, action in ipairs({ plain, shifted }) do
        local tip = ActionTip(action, i == 2, self.view.name, self.bag, self.itemId)
        if tip then GameTooltip:AddLine(tip, 0, 1, 0) end
    end
    GameTooltip:AddLine(L["baggrid.tip.move"], 0, 1, 0)
    GameTooltip:Show()
end

local View = {}
View.__index = View

function View:Button(i)
    local b = self.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, self.frame, "ItemButtonTemplate")
    b.isBotBagSlot = true
    b.view = self
    b:RegisterForDrag("LeftButton")
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    b:SetScript("OnClick", function(s, button) BagGrid.SlotClick(self.name, s.bag, s.slot, s.itemId, button) end)
    b:SetScript("OnDragStart", function(s) BagGrid.SlotDragStart(self.name, s.bag, s.slot, s.itemId) end)
    b:SetScript("OnReceiveDrag", function(s) GiveCursorItem(self.name, IsBank(s.bag), s.bag, s.slot) end)
    b:SetScript("OnEnter", OnSlotEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    self.buttons[i] = b
    return b
end

function View:SetBot(name)
    self.name = name
    self.frame.dropBotName = name
    self:Render()
end

local HIS_BAGS = { 0, 1, 2, 3, 4 }

-- The quality border of an ItemButtonTemplate button (uncommon and up, like your own bags).
-- item: an item id or string, nil for none. Not cached yet: no border until GET_ITEM_INFO_RECEIVED.
function BagGrid.SetQualityBorder(b, item)
    local quality = item and select(3, GetItemInfo(item))
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS[quality]
    if color then
        b.IconBorder:SetVertexColor(color.r, color.g, color.b)
        b.IconBorder:Show()
    else
        b.IconBorder:Hide()
    end
end

-- Shows each item of an inventory entry ({id, count} or false) on an ItemButtonTemplate button.
function BagGrid.ShowItem(b, item)
    b.itemId = item and item.id or nil
    b.icon:SetTexture(item and GetItemIcon(item.id) or nil)
    b.icon:SetShown(item and true or false)
    b.Count:SetText(item and item.count > 1 and item.count or "")
    b.Count:SetShown(item and item.count > 1 or false)
    BagGrid.SetQualityBorder(b, item and item.id)
end

function View:Render()
    for _, b in ipairs(self.buttons) do b:Hide() end
    local inv = self.opts.inventory and self.opts.inventory(self.name) or BagGrid.Inventory(self.name)
    local y, n = 0, 0
    for _, bag in ipairs(self.opts.bags and self.opts.bags(self) or HIS_BAGS) do
        local info = inv and inv.bags[bag]
        if info and info.size > 0 then
            if n > 0 then y = y - BAG_GAP end
            for slot = 0, info.size - 1 do
                n = n + 1
                local b = self:Button(n)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (slot % COLUMNS) * BUTTON_STEP, y - math.floor(slot / COLUMNS) * BUTTON_STEP)
                b.bag, b.slot = bag, slot
                BagGrid.ShowItem(b, info.items[slot + 1])
                b:Show()
            end
            y = y - math.ceil(info.size / COLUMNS) * BUTTON_STEP + (BUTTON_STEP - BUTTON_SIZE)
        end
    end
    -- (a list that may be empty, the bank bags none of which is open: no room, no "loading")
    self.loading:SetShown(n == 0 and not self.opts.mayBeEmpty)
    if n == 0 then y = self.opts.mayBeEmpty and -1 or -40 end
    self.frame:SetSize(BagGrid.WIDTH, -y)
    if self.money then RenderMoney(self.money, inv and inv.money) end
    if self.OnLayout then self:OnLayout() end
end

-- opts (all optional): bags = fn(view) -> the bag indexes to show (default his bags 0-4),
-- inventory = fn(name) -> { bags = { [bag] = { size, items } } } (default his last PBINV),
-- bank = true (it shows his bank: things dropped on it go there), mayBeEmpty = true
function BagGrid.NewView(parent, moneyBar, opts)
    local view = setmetatable({ buttons = {}, opts = opts or {} }, View)
    local toBank = view.opts.bank == true
    view.frame = CreateFrame("Frame", nil, parent)
    view.frame:SetSize(BagGrid.WIDTH, 40)
    view.frame:EnableMouse(true)
    view.frame.dropToBank = toBank
    view.frame:SetScript("OnReceiveDrag", function() GiveCursorItem(view.name, toBank) end)
    view.frame:SetScript("OnMouseUp", function(_, button)
        if GiveCursorItem(view.name, toBank) then return end
        if held and button == "LeftButton" then PutHeld(view.name, nil, nil, toBank) else BagGrid.Cancel() end
    end)
    view.loading = view.frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    view.loading:SetPoint("CENTER")
    view.loading:SetText(L["baggrid.loading"])
    if moneyBar then view.money = BuildMoney(view, moneyBar) end
    views[#views + 1] = view
    return view
end

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

-- PBINV;<name>;BEGIN | M;<copper>;<may take 0/1>;<affinity it takes> | B;<bag>;<size>;<id:count|0>,... | END
ns.On("PBINV", function(msg)
    local _, name, a, b, c, d = strsplit(";", msg)
    if not name then return end
    if a == "BEGIN" then
        incoming[name] = { bags = {} }
    elseif a == "M" and incoming[name] then
        incoming[name].money = { copper = tonumber(b) or 0, canTake = c == "1", takeAt = tonumber(d) or 0 }
    elseif a == "B" and incoming[name] then
        local items, i = {}, 0
        for entry in (d or ""):gmatch("[^,]+") do
            i = i + 1
            local id, count = entry:match("^(%d+):(%d+)$")
            items[i] = id and { id = tonumber(id), count = tonumber(count) } or false
        end
        incoming[name].bags[tonumber(b)] = { size = tonumber(c) or 0, items = items }
    elseif a == "END" and incoming[name] then
        inventories[name] = incoming[name]
        incoming[name] = nil
        fresh[name] = not pending[name] or nil     -- (unasked: sent along with a command's answer)
        pending[name] = nil
        for _, v in ipairs(views) do
            if v.name == name then v:Render() end
        end
        for _, fn in ipairs(inventoryHandlers) do fn(name) end
    end
end)

ns.On("PBOK", function(msg)
    local _, name, a, b, c, d = strsplit(";", msg)
    if a == "equip" then
        ShowOk(L("baggrid.ok.equip", { name = name, item = ItemName(tonumber(b)) }))
    elseif a == "unequip" then
        ShowOk(L(c == "1" and "baggrid.ok.unequip_mailed" or "baggrid.ok.unequip", { name = name, item = ItemName(tonumber(b)) }))
    elseif a == "use" then
        ShowOk(L("baggrid.ok.use", { name = name, item = ItemName(tonumber(b)) }))
    elseif a == "take" or a == "give" or a == "move" then
        -- hand-overs and moves: no message, the slots just show the new places (user 2026-11-23)
    elseif a == "pass" then
        -- pass;<item>;<count>;<to>
        ns.BotInventoryChanged(d)
    elseif a == "takemoney" then
        -- takemoney;<copper>;<its money now>
        ShowOk(L("baggrid.ok.takemoney", { name = name, money = GetCoinTextureString(tonumber(b) or 0) }))
    else
        return
    end
    ns.BotInventoryChanged(name)
end)

-- No bags for him: locked (he does not trust you enough yet), or not your party bot (offline, not
-- in your group). The answer to a bags request, or he is shown and went away: the panels decide.
ns.On("PBERR", function(msg)
    local name, code = msg:match("^PBERR;([^;]*);([^;]*)")
    if not name then return end
    local asked = pending[name]
    if (code == "locked" and asked) or ((code == "notbot" or code == "notfound") and (asked or Viewed(name))) then
        pending[name] = nil
        inventories[name] = nil
        for _, fn in ipairs(refusedHandlers) do fn(name, code) end
        return true
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- your item picked up or put down (its slot locks and unlocks as well)
events:RegisterEvent("CURSOR_UPDATE")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:SetScript("OnEvent", function(_, event)
    if event ~= "GET_ITEM_INFO_RECEIVED" then return HandChanged() end
    for _, v in ipairs(views) do
        if v.frame:IsVisible() then v:Render() end
    end
end)
