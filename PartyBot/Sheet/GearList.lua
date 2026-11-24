-- Companion sheet, 角色 page: his gear as a list beside the sheet, like MerInspect does for your
-- own character window: item level, slot and name in its quality colour, the average item level
-- on top. MerInspect needs your character window or a unit in inspect range; this reads the gear
-- the character page already has from the server, so it works offline too.
-- Right of the sheet, or right of his bags when they are open (Bags.lua). A child of the
-- character page: it goes with the page and the sheet. On/off on the Options page (sheetGearList).

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local List = {}
ns.SheetGearList = List

local SLOT_NAMES = ns.BagGrid.GEAR_SLOT_NAMES
-- top to bottom as on the paper doll; shirt and tabard have no item level worth a line
local ORDER = { 0, 1, 2, 14, 4, 8, 9, 5, 6, 7, 10, 11, 12, 13, 15, 16, 17 }

local ROW_H = 16
local WIDTH = 260
local PAD = 10
local HEADER_H = 22

local frame
local rows = {}
local items             -- [server slot] = { entry, enchant, suffix } shown, nil: no data yet

local function Enabled() return not (ns.db and ns.db.sheetGearList == false) end

local function RowTooltip(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(Sheet.ItemString(self.item))
    GameTooltip:Show()
end

local function RowClick(self)
    if not self.item then return end
    local _, link = GetItemInfo(Sheet.ItemString(self.item))
    if not link then return end
    if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(link)
    elseif IsModifiedClick("DRESSUP") then DressUpItemLink(link) end
end

local function Place()
    local bags = ns.BagsPanel
    local sheet = Sheet.Frame()
    frame:ClearAllPoints()
    if bags and bags:IsShown() then
        frame:SetPoint("TOPLEFT", bags, "TOPRIGHT", 2, 0)
    else
        frame:SetPoint("TOPLEFT", sheet, "TOPRIGHT", -30, -12)
    end
end

function List.Build(page)
    frame = CreateFrame("Frame", "PartyBotCompanionGearList", page, "BackdropTemplate")
    frame:SetSize(WIDTH, HEADER_H + #ORDER * ROW_H + PAD * 2)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(1, 1, 1)
    frame:EnableMouse(true)
    frame:Hide()

    frame.average = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.average:SetPoint("TOPLEFT", PAD, -PAD)

    for i, slot in ipairs(ORDER) do
        local r = CreateFrame("Button", nil, frame)
        r:SetSize(WIDTH - PAD * 2, ROW_H)
        r:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H + (i - 1) * ROW_H))
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.level = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.level:SetPoint("LEFT")
        r.level:SetWidth(24)
        r.level:SetJustifyH("RIGHT")
        r.level:SetTextColor(1, 0.82, 0)
        r.slotLabel = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        r.slotLabel:SetPoint("LEFT", r.level, "RIGHT", 6, 0)
        r.slotLabel:SetWidth(52)
        r.slotLabel:SetJustifyH("LEFT")
        local slotName = SLOT_NAMES[slot]
        r.slotLabel:SetText(_G[strupper(slotName)] or slotName)
        r.name = r:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        r.name:SetPoint("LEFT", r.slotLabel, "RIGHT", 4, 0)
        r.name:SetPoint("RIGHT")
        r.name:SetJustifyH("LEFT")
        r.name:SetWordWrap(false)
        r:SetScript("OnEnter", RowTooltip)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:SetScript("OnClick", RowClick)
        r.slot = slot
        rows[i] = r
    end

    if ns.BagsPanel then
        ns.BagsPanel:HookScript("OnShow", function() if frame:IsShown() then Place() end end)
        ns.BagsPanel:HookScript("OnHide", function() if frame:IsShown() then Place() end end)
    end
end

-- Draws the list again from what is shown (an item's name or level came from the server).
function List.Render()
    if not frame then return end
    if not (items and Enabled()) then frame:Hide() return end
    local sum, count = 0, 0
    for _, r in ipairs(rows) do
        local item = items[r.slot]
        r.item = item
        local name, _, quality, level = nil, nil, nil, nil
        if item then name, _, quality, level = GetItemInfo(Sheet.ItemString(item)) end
        if item and level then
            sum, count = sum + level, count + 1
        end
        r.level:SetText(level or "")
        local color = quality and ITEM_QUALITY_COLORS[quality]
        r.name:SetText(item and (name or ns.ItemName(item.entry)) or "")
        if color then r.name:SetTextColor(color.r, color.g, color.b) else r.name:SetTextColor(1, 1, 1) end
    end
    frame.average:SetText(L("sheet.gearlist.average", { level = count > 0 and ("%.1f"):format(sum / count) or "—" }))
    Place()
    frame:Show()
end

-- items: his gear from the character page, nil while the server has not sent it
function List.Update(newItems)
    items = newItems
    List.Render()
end

ns.Options.AddHeader(L["sheet.gearlist.options_header"])
ns.Options.AddCheck({
    label = L["sheet.gearlist.option"],
    tip = L["sheet.gearlist.option.tip"],
    get = Enabled,
    set = function(on)
        ns.db.sheetGearList = not on and false or nil
        List.Render()
    end,
})
