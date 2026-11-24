-- Companion sheet, page 1: 角色 — gear, model and stats, laid out like the player's paper doll.
-- Gear works offline (the server reads it from the database); stats and the model need the
-- companion online (stats are computed at login), the model also needs it in view.
-- The gear slots have quality borders; the gear list beside the sheet: GearList.lua.

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

-- server equipment slot (0-18) -> paper doll slot name (GetInventorySlotInfo gives the empty art)
local SLOTS = ns.BagGrid.GEAR_SLOT_NAMES

-- the paper doll layout: left column, right column, weapons along the bottom
local LEFT  = { 0, 1, 2, 14, 4, 3, 18, 8 }
local RIGHT = { 9, 5, 6, 7, 10, 11, 12, 13 }
local BOTTOM = { 15, 16, 17 }

-- resistance icons top to bottom (UI-Character-ResistanceIcons rows) -> key in the stat lines (r<school>)
local RESISTANCES = {
    { key = "r6", top = 0.2265625,  bottom = 0.33984375, name = RESISTANCE6_NAME or L["sheet.character.resist_arcane"] },
    { key = "r2", top = 0,          bottom = 0.11328125, name = RESISTANCE2_NAME or L["sheet.character.resist_fire"] },
    { key = "r3", top = 0.11328125, bottom = 0.2265625,  name = RESISTANCE3_NAME or L["sheet.character.resist_nature"] },
    { key = "r4", top = 0.33984375, bottom = 0.453125,   name = RESISTANCE4_NAME or L["sheet.character.resist_frost"] },
    { key = "r5", top = 0.453125,   bottom = 0.56640625, name = RESISTANCE5_NAME or L["sheet.character.resist_shadow"] },
}

local slots = {}
local resists = {}
local model, notNear
local shownUnit

local ItemString = Sheet.ItemString

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------

local function Background(page)
    local parts = {
        { "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-L1",          256, 256, 0,   0 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-R1",          128, 256, 256, 0 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-BottomLeft",  256, 256, 0,   -256 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-BottomRight", 128, 256, 256, -256 },
    }
    for _, p in ipairs(parts) do
        local t = page:CreateTexture(nil, "BORDER")
        t:SetTexture(p[1])
        t:SetSize(p[2], p[3])
        t:SetPoint("TOPLEFT", p[4], p[5])
    end
end

local function BuildModel(page)
    model = CreateFrame("PlayerModel", "PartyBotCompanionSheetModel", page)
    model:SetSize(233, 224)
    model:SetPoint("TOPLEFT", 65, -78)
    if Model_OnLoad then
        Model_OnLoad(model, MODELFRAME_MAX_PLAYER_ZOOM)
        model:SetScript("OnUpdate", Model_OnUpdate)
        model:SetScript("OnMouseDown", Model_OnMouseDown)
        model:SetScript("OnMouseUp", Model_OnMouseUp)
        model:SetScript("OnHide", Model_OnHide)
    end

    local function Rotate(name, anchorTo, texture, fn)
        local b = CreateFrame("Button", name, model)
        b:SetSize(35, 35)
        if anchorTo then b:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT") else b:SetPoint("TOPLEFT") end
        b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        b:SetNormalTexture("Interface\\Buttons\\UI-Rotation" .. texture .. "-Button-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-Rotation" .. texture .. "-Button-Down")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
        b:SetScript("OnClick", function() if fn then fn(model) end end)
        return b
    end
    local right = Rotate("PartyBotCompanionSheetModelRotateRight", nil, "Left", Model_RotateRight)
    Rotate("PartyBotCompanionSheetModelRotateLeft", right, "Right", Model_RotateLeft)

    notNear = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    notNear:SetPoint("CENTER", model, "CENTER", 0, 0)
    notNear:SetWidth(200)
end

local function StatTooltip(self)
    if not self.tipTitle then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tipTitle, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
    if self.tipText then GameTooltip:AddLine(self.tipText, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true) end
    GameTooltip:Show()
end

local function BuildResistances(page)
    -- resistances down the right edge of the model
    local column = CreateFrame("Frame", nil, page)
    column:SetSize(32, 160)
    column:SetPoint("TOPRIGHT", page, "TOPLEFT", 297, -77)
    local above
    for i, res in ipairs(RESISTANCES) do
        local f = CreateFrame("Frame", nil, column)
        f:SetSize(32, 29)
        if above then f:SetPoint("TOP", above, "BOTTOM") else f:SetPoint("TOP", column, "TOP") end
        local icon = f:CreateTexture(nil, "BACKGROUND")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons")
        icon:SetTexCoord(0, 1, res.top, res.bottom)
        f.value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.value:SetPoint("BOTTOM", 0, 3)
        f.tipTitle = res.name
        f:SetScript("OnEnter", StatTooltip)
        f:SetScript("OnLeave", GameTooltip_Hide)
        resists[i] = f
        above = f
    end
end

local function SlotTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item then
        GameTooltip:SetHyperlink(ItemString(self.item))
    else
        GameTooltip:SetText(_G[strupper(self.slotName)] or self.slotName)
    end
    GameTooltip:Show()
end

-- Sheet.Gear: whoever manages his gear (Bags.lua: picking up while his bags are open beside the
-- sheet; what you hold, yours or a companion's, put on him any time)
--   Click(serverSlot, button, itemId or nil) -> true if it handled the click
--   DragStart(serverSlot, itemId)
--   Drop(serverSlot)                 your item let go on the slot
-- The slot buttons carry isSheetGear + serverSlot, so a drop on them can be found. The slots an
-- item in your hand fits light up (BagGrid.OnHand), as on your own paper doll.
local function SlotClick(self, button)
    local gear = Sheet.Gear
    if gear and gear.Click(self.serverSlot, button, self.item and self.item.entry) then return end
    if button == "RightButton" then
        return
    elseif self.item and IsModifiedClick("CHATLINK") then
        local _, link = GetItemInfo(ItemString(self.item))
        if link then ChatEdit_InsertLink(link) end
    elseif self.item and IsModifiedClick("DRESSUP") then
        local _, link = GetItemInfo(ItemString(self.item))
        if link then DressUpItemLink(link) end
    end
end

local function BuildSlots(page)
    local function Slot(id, anchor, point, relPoint, x, y)
        local name = SLOTS[id]
        local b = CreateFrame("Button", "PartyBotCompanionSheet" .. name, page, "ItemButtonTemplate")
        b:SetPoint(point, anchor, relPoint, x, y)
        b.slotName = name
        b.serverSlot = id
        b.isSheetGear = true
        local _, empty = GetInventorySlotInfo(name)
        b.empty = empty
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            if self.item and Sheet.Gear then Sheet.Gear.DragStart(self.serverSlot, self.item.entry) end
        end)
        b:SetScript("OnReceiveDrag", function(self)
            if Sheet.Gear then Sheet.Gear.Drop(self.serverSlot) end
        end)
        b:SetScript("OnEnter", SlotTooltip)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b:SetScript("OnClick", SlotClick)
        slots[id] = b
        return b
    end
    local prev
    for _, id in ipairs(LEFT) do
        prev = prev and Slot(id, prev, "TOPLEFT", "BOTTOMLEFT", 0, -4) or Slot(id, page, "TOPLEFT", "TOPLEFT", 21, -74)
    end
    prev = nil
    for _, id in ipairs(RIGHT) do
        prev = prev and Slot(id, prev, "TOPLEFT", "BOTTOMLEFT", 0, -4) or Slot(id, page, "TOPLEFT", "TOPLEFT", 306, -74)
    end
    prev = nil
    for _, id in ipairs(BOTTOM) do
        prev = prev and Slot(id, prev, "TOPLEFT", "TOPRIGHT", 5, 0) or Slot(id, page, "TOPLEFT", "BOTTOMLEFT", 122, 127)
    end
end

ns.BagGrid.OnHand(function(itemId)
    local fits = ns.BagGrid.GearSlots(itemId)
    for id, b in pairs(slots) do
        if fits and fits[id] then b:LockHighlight() else b:UnlockHighlight() end
    end
end)

---------------------------------------------------------------------------
-- update
---------------------------------------------------------------------------

-- the S lines (key=value pairs, Companions/CompanionSheet.cpp) merged into one table of numbers
local function StatTable(data)
    if not (data and data.lines.S) then return nil end
    local s = {}
    for _, fields in ipairs(data.lines.S) do
        for _, pair in ipairs(fields) do
            local key, value = pair:match("^([%w]+)=(.*)$")
            if key then s[key] = tonumber(value) or 0 end
        end
    end
    return s
end

local function UpdateStats(c, data)
    local s = StatTable(data)
    local isOffline = data and not data.online
    for i, f in ipairs(resists) do
        f.value:SetText(s and (s[RESISTANCES[i].key] or 0) or (isOffline and (GRAY_FONT_COLOR_CODE .. "—" .. FONT_COLOR_CODE_CLOSE) or ""))
        f.tipText = not s and isOffline and L["sheet.character.stats_offline"] or nil
    end
    ns.SheetStats.Update(s, c, isOffline)
end

-- his gear from the I lines: [server slot] = { entry, enchant, suffix }
local function GearOf(data)
    local items = {}
    for _, f in ipairs(data and data.lines.I or {}) do
        local slot = tonumber(f[1])
        if slot then
            items[slot] = { entry = tonumber(f[2]) or 0, enchant = tonumber(f[3]) or 0, suffix = tonumber(f[4]) or 0 }
        end
    end
    return items
end

local function ShowSlots()
    for _, b in pairs(slots) do
        SetItemButtonTexture(b, b.item and GetItemIcon(b.item.entry) or b.empty)
        ns.BagGrid.SetQualityBorder(b, b.item and b.item.entry)
    end
end

local function UpdateSlots(items)
    for id, b in pairs(slots) do b.item = items[id] end
    ShowSlots()
end

local function UpdateModel(c)
    local unit = ns.UnitOf(c.name)
    if unit then
        notNear:Hide()
        model:Show()
        if shownUnit ~= c.name then
            model:SetUnit(unit)
            shownUnit = c.name
        end
    else
        model:Hide()
        shownUnit = nil
        notNear:SetText(L("sheet.character.not_near", { name = c.name }))
        notNear:Show()
    end
end

Sheet.AddPage({
    key = "character", title = CHARACTER or L["sheet.character.title"], order = 10, server = "char", levelLine = true,
    Build = function(page)
        Background(page)
        BuildModel(page)
        BuildResistances(page)
        ns.SheetStats.Build(page)
        BuildSlots(page)
        ns.SheetGearList.Build(page)

        -- an item's quality came from the server after the slots were drawn
        page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        page:SetScript("OnEvent", function(self)
            if not self:IsVisible() then return end
            ShowSlots()
            ns.SheetGearList.Render()
        end)
    end,
    Update = function(page, c, data)
        local items = GearOf(data)
        UpdateModel(c)
        UpdateSlots(items)
        UpdateStats(c, data)
        ns.SheetGearList.Update(data and items)
    end,
})
