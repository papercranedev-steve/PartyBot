-- Bag panel beside a companion's sheet (CompanionSheet.lua, the character page). Opened with
-- ns.ShowBags(name): the unit menu's 查看背包, the list menu, his "让我看看你的包" in the talk
-- window. Needs him online in your group (the server's party bot). The slots, what clicks and
-- drags do, his coin: BagGrid.lua. Here: the window, and his gear on the sheet while it is open
-- (right-click unequips, shift gives it to you, drag moves it).
-- A companion shows its bags from affinity 22 on (server Gates ManageBags; before: PBERR locked,
-- no panel) and lets you take money from 50 on (TakeMoney).

local ADDON, ns = ...
local L = ns.L
local BagGrid = ns.BagGrid

local INSET_PAD = 6
local TOP = 24
local BOTTOM = 26       -- the button bar: his coin

local currentName      -- bot shown in the panel

local panel = CreateFrame("Frame", "PartyBotBagsFrame", UIParent, "ButtonFrameTemplate")
panel:SetFrameStrata("HIGH")
panel:EnableMouse(true)
panel:Hide()
ButtonFrameTemplate_HidePortrait(panel)
panel.Inset:ClearAllPoints()
panel.Inset:SetPoint("TOPLEFT", 4, -TOP)
panel.Inset:SetPoint("BOTTOMRIGHT", -6, BOTTOM)
panel.CloseButton:SetScript("OnClick", function() panel:Hide() end)

local view = BagGrid.NewView(panel, panel)
view.frame:SetPoint("TOPLEFT", panel.Inset, "TOPLEFT", INSET_PAD, -INSET_PAD)
function view.OnLayout(v)
    panel:SetSize(BagGrid.WIDTH + 10 + INSET_PAD * 2, v.frame:GetHeight() + TOP + BOTTOM + INSET_PAD * 2)
end
panel.dropBotName = function() return currentName end
panel:SetScript("OnReceiveDrag", function() BagGrid.DropOnBot(currentName) end)
panel:SetScript("OnMouseUp", function()
    if not BagGrid.DropOnBot(currentName) then BagGrid.Cancel() end
end)
panel:HookScript("OnHide", BagGrid.Cancel)
ns.BagsPanel = panel        -- other panels beside the sheet line up after it (Sheet/GearList.lua)

---------------------------------------------------------------------------
-- beside the companion sheet
---------------------------------------------------------------------------

local function SheetShown()
    local f = ns.Sheet and ns.Sheet.Frame()
    return f and f:IsShown()
end

local function Close()
    panel:Hide()
    currentName = nil
end

local hooked
local function Open(c)
    ns.Sheet.Open(c.guid, "character")
    local sheet = ns.Sheet.Frame()
    if not sheet or not sheet:IsShown() then return end
    if not hooked then
        hooked = true
        sheet:HookScript("OnHide", Close)
    end
    currentName = c.name
    panel.TitleText:SetText(L("bags.title", { name = c.name }))
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", sheet, "TOPRIGHT", -30, -12)
    view:SetBot(c.name)
    -- shown with what we know, or once the server sends it; offline or not his bot: no panel
    if BagGrid.Inventory(c.name) then panel:Show() end
    BagGrid.Request(c.name)
end

-- Opens the companion's sheet on the character page with his bags beside it (call from a click).
function ns.ShowBags(name)
    local c = ns.FindCompanionByName(name)
    if c then return Open(c) end
    ns.RequestCompanions(function()
        local found = ns.FindCompanionByName(name)
        if found then Open(found) end
    end)
end

BagGrid.OnInventory(function(name)
    if name == currentName and SheetShown() then panel:Show() end
end)

BagGrid.OnRefused(function(name)
    if name == currentName then panel:Hide() end
end)

-- his gear on the sheet (bag 5 on the server side): picked up, unequipped while his bags are open;
-- what you hold (yours, or a companion's from the team bags) goes on him any time
local Gear = {}

local function SheetName()
    local c = ns.Sheet.Current()
    return c and c.name
end

function Gear.Click(serverSlot, button, itemId)
    if not serverSlot then return false end
    if BagGrid.Holding() or GetCursorInfo() == "item" then
        return BagGrid.SlotClick(SheetName(), 5, serverSlot, itemId, button)
    end
    if not currentName or not panel:IsShown() then return false end
    return BagGrid.SlotClick(currentName, 5, serverSlot, itemId, button)
end

function Gear.DragStart(serverSlot, itemId)
    if currentName and panel:IsShown() then BagGrid.SlotDragStart(currentName, 5, serverSlot, itemId) end
end

function Gear.Drop(serverSlot)
    BagGrid.SlotDrop(SheetName(), 5, serverSlot)
end

local function HookSheet()
    ns.Sheet.Gear = Gear
    -- the sheet went to someone else: these bags are not his
    hooksecurefunc(ns.Sheet, "Open", function()
        local c = ns.Sheet.Current()
        if currentName and (not c or c.name ~= currentName) then Close() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, arg1)
    if arg1 == ADDON then HookSheet() end      -- (every file of the addon is loaded now)
end)
