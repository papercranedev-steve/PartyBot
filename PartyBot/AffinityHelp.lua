-- "如何获得好感？": a small native dialog (dialog box art, header, close button, ESC closes) that
-- tells what raises a companion's affinity. On purpose without numbers: only what to do together.
-- The sources are the server's (Companions/Affinity, design doc 2026-11-21-companion-affinity).
--   ns.AffinityHelpLink(parent)   a link-style button that opens it
--   ns.ToggleAffinityHelp()       opens it beside the Companions panel (else centred), or closes it

local _, ns = ...
local L = ns.L

local WIDTH = 340
local PAD = 22
local ICON = 30
local TEXT_W = WIDTH - 2 * PAD - ICON - 10
local ROW_GAP = 12

local SOURCES = {
    { icon = "Interface\\Icons\\Spell_Holy_WordFortitude", title = L["affinityhelp.levels.title"],
      text = L["affinityhelp.levels.text"] },
    { icon = "Interface\\Icons\\INV_Scroll_03", title = L["affinityhelp.class_quest.title"],
      text = L["affinityhelp.class_quest.text"] },
    { icon = "Interface\\Icons\\INV_Misc_Coin_01", title = L["affinityhelp.loan.title"],
      text = L["affinityhelp.loan.text"] },
    { icon = "Interface\\Icons\\INV_Misc_Key_03", title = L["affinityhelp.dungeon.title"],
      text = L["affinityhelp.dungeon.text"] },
    { icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", title = L["affinityhelp.raid.title"],
      text = L["affinityhelp.raid.text"] },
}

local frame = CreateFrame("Frame", "PartyBotAffinityHelpFrame", UIParent, "BackdropTemplate")
frame:SetWidth(WIDTH)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:Hide()
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
tinsert(UISpecialFrames, frame:GetName())

local header = frame:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64)
header:SetPoint("TOP", 0, 12)
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText(L["affinityhelp.title"])

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local function Text(font, width)
    local fs = frame:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    return fs
end

local intro = Text("GameFontHighlightSmall", WIDTH - 2 * PAD)
intro:SetText(L["affinityhelp.intro"])

local rows = {}
for i, s in ipairs(SOURCES) do
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetTexture(s.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    name:SetText(s.title)
    local text = Text("GameFontHighlightSmall", TEXT_W)
    text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    text:SetText(s.text)
    rows[i] = { icon = icon, name = name, text = text }
end

local foot = Text("GameFontDisableSmall", WIDTH - 2 * PAD)
foot:SetText(L["affinityhelp.foot"])

-- top to bottom by the real text heights (known once the fonts are laid out: on show)
local function Layout()
    local y = 32
    intro:SetPoint("TOPLEFT", PAD, -y)
    y = y + intro:GetStringHeight()
    for _, r in ipairs(rows) do
        y = y + ROW_GAP
        r.icon:SetPoint("TOPLEFT", PAD, -y)
        y = y + math.max(ICON, r.name:GetStringHeight() + 3 + r.text:GetStringHeight())
    end
    y = y + ROW_GAP + 4
    foot:SetPoint("TOPLEFT", PAD, -y)
    y = y + foot:GetStringHeight()
    frame:SetHeight(y + 22)
end

frame:SetScript("OnShow", function()
    Layout()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
end)
frame:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE) end)

function ns.ToggleAffinityHelp()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    local panel = ns.CompanionsFrame
    frame:ClearAllPoints()
    if panel and panel:IsShown() then
        frame:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, -30)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
end

if ns.CompanionsFrame then
    ns.CompanionsFrame:HookScript("OnHide", function() frame:Hide() end)
end

-- A link-style button: a quest "?" and "如何获得好感？" in link blue (white on hover).
local LINK_R, LINK_G, LINK_B = 0.44, 0.84, 1
function ns.AffinityHelpLink(parent)
    local b = CreateFrame("Button", nil, parent)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT")
    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", icon, "RIGHT", 2, 0)
    text:SetText(L["affinityhelp.link"])
    text:SetTextColor(LINK_R, LINK_G, LINK_B)
    b:SetSize(112, 16)
    b:SetScript("OnEnter", function(self)
        text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["affinityhelp.link.tip.title"])
        GameTooltip:AddLine(L["affinityhelp.link.tip.text"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        text:SetTextColor(LINK_R, LINK_G, LINK_B)
        GameTooltip_Hide()
    end)
    b:SetScript("OnClick", function() ns.ToggleAffinityHelp() end)
    return b
end
