-- Team bags: when you open your bags (B, or a bag addon's window), your companions' bags open
-- beside them, so you can sort the whole team's bags by dragging (BagGrid.lua: what clicks and
-- drags do; a companion's item dropped on another one's tab goes to him).
-- Tabs (TeamTabs.lua): the raid's group numbers in the attic (only when more than one group has
-- someone), the portraits of that group's people down the side away from your bags. The people
-- you may manage: companions in your group whose bags gate is open (affinity), your account's
-- characters. Nobody to manage: no window.
-- While it is open, right-click on his item puts it in your bags (BagGrid); Alt+right-click on
-- yours puts it in his (below).
-- Setting: PartyBotDB.teamBags (false = off), on the options page.

local _, ns = ...
local L = ns.L
local BagGrid = ns.BagGrid

local INSET_PAD = 6
local BOTTOM = 26                           -- the button bar: his coin
local TAB_LEFT = 60                         -- right of the portrait
local WIDTH = BagGrid.WIDTH + 10 + INSET_PAD * 2

local function Enabled() return not ns.db or ns.db.teamBags ~= false end

local selectedGroup, selectedName
local dismissed         -- closed with its button: stays closed until your bags close
local refused = {}      -- [name] = true: the server said no bags (until the next companions list)
local groups = {}       -- { { number, names = { ... } }, ... } from the last Update

local frame = CreateFrame("Frame", "PartyBotTeamBagsFrame", UIParent, "ButtonFrameTemplate")
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
frame.dropBotName = function() return selectedName end
frame:SetScript("OnReceiveDrag", function() BagGrid.DropOnBot(selectedName) end)
frame:SetScript("OnMouseUp", function()
    if not BagGrid.DropOnBot(selectedName) then BagGrid.Cancel() end
end)

local view = BagGrid.NewView(frame, frame)
view.frame:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
local tabs      -- (below)
local function Resize()
    local top = ns.TeamTabs.INSET_TOP
    -- (tall enough for the portraits beside it, even with only his backpack)
    frame:SetHeight(math.max(view.frame:GetHeight() + top + BOTTOM + INSET_PAD * 2, tabs and tabs:MinHeight() or 0))
end
view.OnLayout = Resize

---------------------------------------------------------------------------
-- who: your group's people whose bags you may manage, by raid group
---------------------------------------------------------------------------

local function Manageable(name)
    local c = name and not refused[name] and ns.FindCompanionByName(name)
    return c and c.state == ns.COMPANION_STATE.GROUP and ns.GateOpen(c, "bags")
end

local function Groups() return ns.TeamTabs.Groups(Manageable) end

local function Find(list, pred)
    for _, v in ipairs(list) do
        if pred(v) then return v end
    end
end

---------------------------------------------------------------------------
-- tabs (TeamTabs.lua)
---------------------------------------------------------------------------

local Select

tabs = ns.TeamTabs.New(frame, "PartyBotTeamBags", {
    left = TAB_LEFT,
    onSelect = function(number, name) Select(number, name) end,
    onMemberClick = function(name) return BagGrid.DropOnBot(name) end,     -- something you hold goes to him
    onMemberDrop = function(name) BagGrid.DropOnBot(name) end,
    memberTip = function(name)
        if BagGrid.Holding() or GetCursorInfo() == "item" then return L("teambags.give_to", { name = name }) end
    end,
})

local function LayoutTabs()
    frame.Inset:SetPoint("TOPLEFT", 4, -ns.TeamTabs.INSET_TOP)
    tabs:Layout(groups, selectedGroup, selectedName, frame.Inset)
end

-- shows `name` of group `number` (nil: the first one / the one shown before, if still there);
-- his bags are asked for when he is someone else, or `fresh`
function Select(number, name, fresh)
    local group = Find(groups, function(g) return g.number == number end)
        or Find(groups, function(g) return tContains(g.names, selectedName or "") end)
        or groups[1]
    if not group then return end
    selectedGroup = group.number
    if not (name and tContains(group.names, name)) then
        name = tContains(group.names, selectedName or "") and selectedName or group.names[1]
    end
    local changed = name ~= view.name
    selectedName = name
    LayoutTabs()
    frame.TitleText:SetText(L("bags.title", { name = name }))
    local c = ns.FindCompanionByName(name)
    if c then ns.CompanionPortrait(frame.portrait, c) end
    if changed then view:SetBot(name) else Resize() end
    if changed or fresh then BagGrid.Request(name) end
end

-- another window shows `name` (the bank): his bags here too, if he is among them
function ns.TeamBagsShow(name)
    if not frame:IsShown() or not name or name == selectedName then return end
    local g = Find(groups, function(g) return tContains(g.names, name) end)
    if g then Select(g.number, name) end
end

---------------------------------------------------------------------------
-- beside your bags
---------------------------------------------------------------------------

local function Place(main)
    frame:SetFrameStrata(main:GetFrameStrata())
    frame:SetFrameLevel(main:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    -- the portraits stand on the side away from your bags
    local room = (main:GetLeft() or 0) * main:GetEffectiveScale()
    if room >= (frame:GetWidth() + ns.TeamTabs.SIDE_WIDTH) * frame:GetEffectiveScale() then
        frame:SetPoint("TOPRIGHT", main, "TOPLEFT", -2, 0)
        tabs:SetSide("LEFT")
    else
        frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 2, 0)     -- your bags sit on the left
        tabs:SetSide("RIGHT")
    end
end

local asked     -- asked the server for the companions list while the bags were open

local function Update()
    local main = ns.PlayerBags.Main()
    if not main then
        dismissed, asked = nil, nil
        frame:Hide()
        return
    end
    if not Enabled() or dismissed or not IsInGroup() then
        frame:Hide()
        return
    end
    if not ns.CompanionsLoaded() then
        if not asked then asked = ns.SendCommandAuto(".partybot companions") end
        return      -- (shown when the list came)
    end
    groups = Groups()
    if #groups == 0 then
        frame:Hide()
        return
    end
    local opening = not frame:IsShown()
    Place(main)     -- (first: it picks the side the portraits stand on)
    Select(selectedGroup, selectedName, opening)    -- (fresh bags on every open)
    frame:Show()
end

-- (after the bag windows placed themselves)
local function UpdateSoon() C_Timer.After(0, Update) end

ns.PlayerBags.OnChange(UpdateSoon)
ns.OnCompanionsListed(function()
    wipe(refused)
    if ns.PlayerBags.Main() then Update() end
end)

BagGrid.OnRefused(function(name)
    refused[name] = true
    if frame:IsShown() then Update() end
end)

frame:HookScript("OnHide", BagGrid.Cancel)

---------------------------------------------------------------------------
-- Alt+right-click on your own bag item: it goes to him
---------------------------------------------------------------------------
-- Plain right-click stays Blizzard's (UseContainerItem is protected for items that cast: an addon
-- must not take that click over). A modified click only runs ContainerFrameItemButton_OnModifiedClick,
-- which does nothing with Alt, so a hook after it is safe; bag addons that use Blizzard's slot
-- template (Bagnon) go through it too.

local function AltGives()
    return frame:IsShown() and selectedName and not BagGrid.Holding()
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
    if button ~= "RightButton" or not IsAltKeyDown() or not AltGives() then return end
    local bag = self:GetParent() and self:GetParent():GetID()
    if bag and bag >= 0 and bag <= NUM_BAG_SLOTS then BagGrid.TakeYours(selectedName, bag, self:GetID()) end
end)

-- the hint in your item's tooltip
hooksecurefunc(GameTooltip, "SetBagItem", function(tip, bag)
    if not bag or bag < 0 or bag > NUM_BAG_SLOTS or not AltGives() then return end
    tip:AddLine(L("teambags.tip.alt_right_click", { name = selectedName }), 0, 1, 0)
    tip:Show()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    if frame:IsShown() then UpdateSoon() end
end)

---------------------------------------------------------------------------
-- setting
---------------------------------------------------------------------------

ns.Options.AddHeader(L["teambags.options.header"])
ns.Options.AddCheck({
    label = L["teambags.options.enable"],
    tip = L["teambags.options.enable.tip"],
    get = Enabled,
    set = function(on)
        ns.db.teamBags = on and true or false
        Update()
    end,
})
