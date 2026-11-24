-- Companion bank: at a banker, beside your bank window, the bank of the party bots in your group
-- (BagGrid.lua: what clicks and drags do; his bags are in the team bags, TeamBags.lua, which the
-- bank opens with your bags). Like your own bank: his 24 slots, his 6 bank bag slots (click one to
-- show what is in it, drag a bag onto it), buying the next bag slot for him (you pay what you pay
-- for yours), right-click moves an item between his bags and his bank.
-- Tabs (TeamTabs.lua; group numbers in the attic, portraits down the right side): everyone of
-- your group whose bank you could see; one who does not trust you enough yet (affinity, server Gates ManageBags, the same as his bags) is grey,
-- and so is a temporary party bot (never saved: what went into his bank would be gone with him).
-- Nobody: no window. The server checks you stand at the banker (.partybot bank / bankteam).

local _, ns = ...
local L = ns.L
local BagGrid = ns.BagGrid
local SendCommandAuto, ShowError, ShowOk = ns.SendCommandAuto, ns.ShowError, ns.ShowOk

local BANK = BagGrid.BANK                       -- 6: his bank's slots, 24-29 its bag slots
local NUM_SLOTS = NUM_BANKGENERIC_SLOTS or 24
local NUM_BAGS = NUM_BANKBAGSLOTS or 6
local FIRST_BANK_BAG = BANK + 1                 -- 7-12: in bank bag 1-6

local INSET_PAD = 6
local BOTTOM = 26                               -- the button bar: buying a bag slot
local TAB_LEFT = 60                             -- right of the portrait
local WIDTH = BagGrid.WIDTH + 10 + INSET_PAD * 2
local GAP = 8

local function IsBank(bag) return bag and bag >= BANK end

local function Request(name)
    if name then SendCommandAuto(".partybot bank " .. name) end
end

---------------------------------------------------------------------------
-- state: who (PBBANKT), their banks (PBBANK)
---------------------------------------------------------------------------

local bankOpen          -- your bank window is open (BANKFRAME_OPENED .. CLOSED)
local dismissed         -- closed with its button: stays closed until the bank closes
local members = {}      -- [name] = { may = bool, needs = affinity it takes }
local incomingMembers
local banks = {}        -- [name] = { bags = { [6-12] = { size, items } }, bagSlots = { id or false }, bought, price }
local incoming = {}
local pending = {}      -- [name] = true: a bank request without answer yet
local openBags = {}     -- [7-12] = true: what is in that bank bag is shown
local selectedGroup, selectedName
local groups = {}

local function BankOf(name) return name and banks[name] end

local function Manages(name)
    local m = bankOpen and name and members[name]
    return m and m.may
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PartyBotBankFrame", UIParent, "ButtonFrameTemplate")
frame:SetWidth(WIDTH)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:Hide()
frame.Inset:ClearAllPoints()
frame.Inset:SetPoint("BOTTOMRIGHT", -6, BOTTOM)
frame.CloseButton:SetScript("OnClick", function()
    dismissed = true
    frame:Hide()
end)
frame.dropBotName = function() return Manages(selectedName) and selectedName or nil end
frame.dropToBank = true
frame:SetScript("OnReceiveDrag", function() BagGrid.DropOnBot(frame.dropBotName(), true) end)
frame:SetScript("OnMouseUp", function()
    if not BagGrid.DropOnBot(frame.dropBotName(), true) then BagGrid.Cancel() end
end)
frame:HookScript("OnHide", BagGrid.Cancel)

-- his 24 slots
local slotsView = BagGrid.NewView(frame, nil, {
    bags = function() return { BANK } end,
    inventory = BankOf,
    bank = true,
})
slotsView.frame:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD, -INSET_PAD)

-- his 6 bank bag slots
local bagLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bagLabel:SetPoint("TOPLEFT", slotsView.frame, "BOTTOMLEFT", 2, -GAP)
bagLabel:SetText(BAGSLOTTEXT)

local bagButtons = {}
local Render

local function BagSlotEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local bank = BankOf(selectedName)
    if self.itemId then
        GameTooltip:SetHyperlink("item:" .. self.itemId)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["bank.tip.bag"], 0, 1, 0)
        GameTooltip:AddLine(L["baggrid.tip.move"], 0, 1, 0)
    elseif bank and self.index > bank.bought then
        GameTooltip:SetText(BANK_BAG_PURCHASE)
    else
        GameTooltip:SetText(BANK_BAG)
    end
    GameTooltip:Show()
end

local function BagSlotClick(self, button)
    local name = slotsView.name
    if button == "LeftButton" and self.itemId and not BagGrid.Holding() and GetCursorInfo() ~= "item"
        and not IsModifierKeyDown() then
        local bag = FIRST_BANK_BAG + self.index - 1
        openBags[bag] = not openBags[bag] or nil
        PlaySound(openBags[bag] and SOUNDKIT.IG_BACKPACK_OPEN or SOUNDKIT.IG_BACKPACK_CLOSE)
        Render()
        return
    end
    BagGrid.SlotClick(name, self.bag, self.slot, self.itemId, button)
end

for i = 1, NUM_BAGS do
    local b = CreateFrame("Button", nil, frame, "ItemButtonTemplate")
    b.isBotBagSlot = true
    b.view = slotsView
    b.index = i
    b.bag, b.slot = BANK, NUM_SLOTS + i - 1
    b:RegisterForDrag("LeftButton")
    b.open = b:CreateTexture(nil, "OVERLAY")
    b.open:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.open:SetBlendMode("ADD")
    b.open:SetAllPoints()
    b.open:Hide()
    b:SetScript("OnClick", BagSlotClick)
    b:SetScript("OnDragStart", function(s) BagGrid.SlotDragStart(slotsView.name, s.bag, s.slot, s.itemId) end)
    b:SetScript("OnReceiveDrag", function(s) BagGrid.SlotClick(slotsView.name, s.bag, s.slot, s.itemId, "LeftButton") end)
    b:SetScript("OnEnter", BagSlotEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    if i == 1 then
        b:SetPoint("TOPLEFT", bagLabel, "BOTTOMLEFT", -2, -4)
    else
        b:SetPoint("LEFT", bagButtons[i - 1], "RIGHT", BagGrid.BUTTON_STEP - BagGrid.BUTTON_SIZE, 0)
    end
    bagButtons[i] = b
end

-- what is in the bank bags clicked open
local bagsView = BagGrid.NewView(frame, nil, {
    bags = function(view)
        local list, bank = {}, BankOf(view.name)
        for bag = FIRST_BANK_BAG, FIRST_BANK_BAG + NUM_BAGS - 1 do
            local info = bank and bank.bags[bag]
            if openBags[bag] and info and info.size > 0 then list[#list + 1] = bag end
        end
        return list
    end,
    inventory = BankOf,
    bank = true,
    mayBeEmpty = true,
})
bagsView.frame:SetPoint("TOPLEFT", bagButtons[1], "BOTTOMLEFT", 0, -GAP)

-- not trusted enough yet
local lockText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lockText:SetPoint("TOP", frame.Inset, "TOP", 0, -40)
lockText:SetWidth(WIDTH - 60)

-- buying his next bag slot (the bottom bar, like the cost line of your bank)
local costLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
costLabel:SetPoint("BOTTOMLEFT", 14, 8)
costLabel:SetText(COSTS_LABEL)
local cost = CreateFrame("Frame", "PartyBotBankCostMoneyFrame", frame, "SmallMoneyFrameTemplate")
MoneyFrame_SetType(cost, "STATIC")
cost:SetPoint("LEFT", costLabel, "RIGHT", 6, 0)
local buy = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
buy:SetSize(124, 22)
buy:SetPoint("BOTTOMRIGHT", -6, 4)
buy:SetText(BANKSLOTPURCHASE)

local buyFor        -- { name, price } of the dialog shown

StaticPopupDialogs["PARTYBOT_BUY_BANK_SLOT"] = {
    text = "%s",        -- L("bank.buy.confirm"), filled in by the caller
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        if buyFor and Manages(buyFor.name) then
            SendCommandAuto(".partybot buybankslot " .. buyFor.name)
        end
    end,
    OnShow = function(self)
        MoneyFrame_Update(self.moneyFrame, buyFor and buyFor.price or 0)
    end,
    hasMoneyFrame = 1,
    timeout = 0,
    hideOnEscape = 1,
}

buy:SetScript("OnClick", function()
    local bank = BankOf(selectedName)
    if not bank or bank.price == 0 then return end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    buyFor = { name = selectedName, price = bank.price }
    StaticPopup_Show("PARTYBOT_BUY_BANK_SLOT", L("bank.buy.confirm", { name = selectedName }))
end)

local function RenderBagSlots(bank)
    for i, b in ipairs(bagButtons) do
        local id = bank and bank.bagSlots[i]
        local bag = FIRST_BANK_BAG + i - 1
        if id then
            BagGrid.ShowItem(b, { id = id, count = 1 })
        else
            BagGrid.ShowItem(b, nil)
            b.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            b.icon:Show()
            openBags[bag] = nil
        end
        if bank and i > bank.bought then
            SetItemButtonTextureVertexColor(b, 1.0, 0.1, 0.1)
        else
            SetItemButtonTextureVertexColor(b, 1.0, 1.0, 1.0)
        end
        b.open:SetShown(openBags[bag] == true)
    end
end

local function RenderCost(bank)
    local show = bank ~= nil and bank.price > 0
    costLabel:SetShown(show)
    cost:SetShown(show)
    buy:SetShown(show)
    if show then
        MoneyFrame_Update(cost, bank.price)
        SetMoneyFrameColor("PartyBotBankCostMoneyFrame", GetMoney() >= bank.price and "white" or "red")
    end
end

local function Top() return ns.TeamTabs.INSET_TOP end

local tabs      -- (below)

function Render()
    local m = selectedName and members[selectedName]
    local locked = m and not m.may
    local bank = not locked and BankOf(selectedName)

    lockText:SetShown(locked and true or false)
    slotsView.frame:SetShown(not locked)
    bagsView.frame:SetShown(not locked)
    bagLabel:SetShown(not locked)
    for _, b in ipairs(bagButtons) do b:SetShown(not locked) end

    local inner
    if locked then
        lockText:SetText(m.temp and L("bank.temp", { name = selectedName })
            or L("bank.locked", { name = selectedName, affinity = m.needs }))
        inner = 120
        RenderCost(nil)
    else
        RenderBagSlots(bank)
        slotsView:Render()
        bagsView:Render()
        RenderCost(bank or nil)
        inner = slotsView.frame:GetHeight() + GAP + 18 + BagGrid.BUTTON_SIZE + GAP + bagsView.frame:GetHeight()
    end
    -- (tall enough for the portraits beside it)
    frame:SetHeight(math.max(inner + Top() + BOTTOM + INSET_PAD * 2, tabs and tabs:MinHeight() or 0))
end

---------------------------------------------------------------------------
-- tabs: your group's people (TeamTabs.lua)
---------------------------------------------------------------------------

local function Find(list, pred)
    for _, v in ipairs(list) do
        if pred(v) then return v end
    end
end

local Select

tabs = ns.TeamTabs.New(frame, "PartyBotBank", {
    left = TAB_LEFT,
    onSelect = function(number, name) Select(number, name) end,
    onMemberClick = function(name)
        return Manages(name) and BagGrid.DropOnBot(name, true)     -- something you hold goes to his bank
    end,
    onMemberDrop = function(name)
        if Manages(name) then BagGrid.DropOnBot(name, true) end
    end,
    memberTip = function(name)
        local m = members[name]
        if m and m.temp then return L["core.err.tempbot"], 1, 0.1, 0.1 end
        if m and not m.may then return L("bank.locked.tip", { affinity = m.needs }), 1, 0.1, 0.1 end
        if BagGrid.Holding() or GetCursorInfo() == "item" then return L("bank.put_in", { name = name }) end
    end,
    memberLocked = function(name) return not Manages(name) end,
})

local function FirstManaged(names)
    for _, n in ipairs(names) do
        if Manages(n) then return n end
    end
    return names[1]
end

-- shows `name` of group `number` (nil: the one shown before if still there, else the first one you
-- may manage); his bank is asked for when he is someone else, or `fresh`
function Select(number, name, fresh)
    local group = Find(groups, function(g) return g.number == number end)
        or Find(groups, function(g) return tContains(g.names, selectedName or "") end)
        or Find(groups, function(g) return Manages(FirstManaged(g.names)) end)
        or groups[1]
    if not group then return end
    selectedGroup = group.number
    if not (name and tContains(group.names, name)) then
        name = tContains(group.names, selectedName or "") and selectedName or FirstManaged(group.names)
    end
    local changed = name ~= slotsView.name
    selectedName = name
    frame.Inset:SetPoint("TOPLEFT", 4, -Top())
    tabs:Layout(groups, selectedGroup, selectedName, frame.Inset)
    frame.TitleText:SetText(L("bank.title", { name = name }))
    local c = ns.FindCompanionByName(name)
    local unit = ns.UnitOf(name)
    if c then
        ns.CompanionPortrait(frame.portrait, c)
    elseif unit then
        SetPortraitTexture(frame.portrait, unit)
    end
    if changed then
        wipe(openBags)
        slotsView:SetBot(name)
        bagsView:SetBot(name)
    end
    Render()
    if Manages(name) then
        if changed or fresh then
            pending[name] = true
            Request(name)
        end
        if ns.TeamBagsShow then ns.TeamBagsShow(name) end   -- his bags beside yours: the same one
    end
end

---------------------------------------------------------------------------
-- beside your bank window
---------------------------------------------------------------------------

local function BankWindow()
    if BankFrame and BankFrame:IsShown() then return BankFrame, -28, -12 end
    local bagnon = Bagnon and Bagnon.Frames and Bagnon.Frames.registry and Bagnon.Frames:Get("bank")
    local object = bagnon and bagnon.object
    if object and object:IsShown() then return object, 2, 0 end
end

local function Place()
    local main, x, y = BankWindow()
    frame:ClearAllPoints()
    if main then
        frame:SetFrameStrata(main:GetFrameStrata())
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", x, y)
    else
        frame:SetFrameStrata("HIGH")
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
    end
end

local function Update(fresh)
    if not bankOpen or dismissed then
        frame:Hide()
        return
    end
    groups = ns.TeamTabs.Groups(function(name) return members[name] ~= nil end)
    if #groups == 0 then
        frame:Hide()
        return
    end
    Select(selectedGroup, selectedName, fresh or not frame:IsShown())
    Place()
    frame:Show()
end

local function AskMembers()
    -- (a party bot in your group means you are in a group: the party channel works from events)
    SendCommandAuto(".partybot bankteam")
end

-- right-click on his items while his bank is open: into his bank, or out of it into his bags
BagGrid.SetRightClick({
    click = function(name, bag, slot)
        if not Manages(name) or bag == 5 then return false end
        SendCommandAuto((".partybot autobank %s %d %d"):format(name, bag, slot))
        return true
    end,
    tip = function(name, bag)
        if not Manages(name) or bag == 5 then return nil end
        return L[IsBank(bag) and "bank.tip.to_bags" or "bank.tip.to_bank"]
    end,
})

BagGrid.OnChanged(function(name)
    if frame:IsShown() and name == selectedName and Manages(name) then
        C_Timer.After(0.3, function() Request(name) end)
    end
end)

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

-- PBBANKT;BEGIN | M;<name>;<may 0/1>;<affinity it takes>;<affinity now>;<temporary 0/1> | END
ns.On("PBBANKT", function(msg)
    local _, a, name, may, needs, _, temp = strsplit(";", msg)
    if a == "BEGIN" then
        incomingMembers = {}
    elseif a == "M" and incomingMembers and name then
        incomingMembers[name] = { may = may == "1", needs = tonumber(needs) or 0, temp = temp == "1" }
    elseif a == "END" and incomingMembers then
        members = incomingMembers
        incomingMembers = nil
        Update()
    end
    return true
end)

local function ParseItems(list)
    local items, i = {}, 0
    for entry in (list or ""):gmatch("[^,]+") do
        i = i + 1
        local id, count = entry:match("^(%d+):(%d+)$")
        items[i] = id and { id = tonumber(id), count = tonumber(count) } or false
    end
    return items
end

-- PBBANK;<name>;BEGIN | B;<bag>;<size>;<id:count|0>,... | G;<bought>;<price>;<id|0>,... | M;<copper> | END
ns.On("PBBANK", function(msg)
    local _, name, a, b, c, d = strsplit(";", msg)
    if not name then return end
    if a == "BEGIN" then
        incoming[name] = { bags = {}, bagSlots = {}, bought = 0, price = 0 }
    elseif a == "B" and incoming[name] then
        incoming[name].bags[tonumber(b)] = { size = tonumber(c) or 0, items = ParseItems(d) }
    elseif a == "G" and incoming[name] then
        local bank = incoming[name]
        bank.bought, bank.price = tonumber(b) or 0, tonumber(c) or 0
        local i = 0
        for id in (d or ""):gmatch("[^,]+") do
            i = i + 1
            bank.bagSlots[i] = id ~= "0" and tonumber(id) or false
        end
    elseif a == "END" and incoming[name] then
        banks[name] = incoming[name]
        incoming[name] = nil
        pending[name] = nil
        if frame:IsShown() and name == selectedName then Render() end
    end
    return true
end)

ns.On("PBOK", function(msg)
    local _, name, a, b, c = strsplit(";", msg)
    if a ~= "bankslot" then return end
    -- bankslot;<bought>;<price paid>
    PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
    ShowOk(L("bank.ok.slot", { name = name, money = GetCoinTextureString(tonumber(c) or 0) }))
    if name == selectedName then Request(name) end
end)

-- The answer to a bank request: he does not trust you enough yet (locked), or he cannot be managed
-- here (nobank: you left the banker; notingroup / notbot / notfound / tempbot): no bank for him.
local REFUSALS = { locked = true, nobank = true, notingroup = true, notbot = true, notfound = true, tempbot = true }

ns.On("PBERR", function(msg)
    local name, code = msg:match("^PBERR;([^;]*);([^;]*)")
    if not name or not pending[name] or not REFUSALS[code] then return end
    pending[name] = nil
    banks[name] = nil
    if code == "locked" and members[name] then
        members[name].may = false
    elseif code == "nobank" then
        frame:Hide()
        return true
    else
        members[name] = nil
    end
    if frame:IsShown() then Update() end
    return true
end)

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        bankOpen, dismissed = true, nil
        ns.BankOpen = true
        wipe(members)
        wipe(banks)
        -- (after the bank window and your bags placed themselves)
        C_Timer.After(0, AskMembers)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen, dismissed = nil, nil
        ns.BankOpen = nil
        wipe(pending)
        frame:Hide()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if bankOpen then AskMembers() end
    elseif event == "PLAYER_MONEY" then
        if frame:IsShown() then RenderCost(BankOf(selectedName)) end
    end
end)
