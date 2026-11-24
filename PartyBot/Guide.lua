-- New player guide to companions, once per character, after his first companion joined
-- (server PBTRIAL;<bot>;bond;1, CompanionMgr::TellBond):
--   1. welcome  a dialog once the companion is in the party (and out of combat): what companions
--               are, and "click the Companions button below"
--   2. arrow    a glow box with an arrow over the bottom bar button (Blizzard's micro button
--               alert look), the button pulses
--   3. tour     when the Companions panel opens: three glow boxes in turn (slots, the list,
--               affinity); closing the panel stops it, the next opening starts it again
-- No rules nor numbers here: the panel itself shows them.
-- PartyBotDB.guide[<player guid>] = { step = "welcome" | "arrow" | "tour" | "done", name = <bot> }
-- /pbguide shows it again from the start (it needs a companion's name for the welcome).

local _, ns = ...
local L = ns.L

local button = PartyBotCompanionsMicroButton      -- (CompanionsButton.lua)
local panel = ns.CompanionsFrame

local WAIT_PARTY_SEC = 20   -- the welcome waits this long for the companion to be in the party

local function State()
    if not ns.db then return nil end
    ns.db.guide = ns.db.guide or {}
    local key = UnitGUID("player")
    if not key then return nil end
    ns.db.guide[key] = ns.db.guide[key] or {}
    return ns.db.guide[key]
end

local ShowArrow, StartTour   -- (below)

---------------------------------------------------------------------------
-- glow boxes (Blizzard's GlowBoxTemplate + GlowBoxArrowTemplate, as its micro button alerts)
---------------------------------------------------------------------------

-- texture coords of the arrow and its glow, pointing down (HelpPlateArrowDOWN, -GlowDOWN)
local ARROW = { 0.78515625, 0.99218750, 0.54687500, 0.58789063, 53, 21 }
local GLOW = { 0.40625000, 0.66015625, 0.77343750, 0.82812500, 65, 28 }

-- `tex` shows `c` turned to point `dir` (DOWN, UP, LEFT)
local function Turn(tex, c, dir)
    local l, r, t, b, w, h = unpack(c)
    if dir == "UP" then
        tex:SetTexCoord(l, r, b, t)
        tex:SetSize(w, h)
    elseif dir == "LEFT" then   -- turned clockwise: the tip (bottom edge) on the left
        tex:SetTexCoord(l, b, r, b, l, t, r, t)
        tex:SetSize(h, w)
    else
        tex:SetTexCoord(l, r, t, b)
        tex:SetSize(w, h)
    end
end

-- where the arrow sits on the box, and which way it bobs
local ARROW_AT = {
    DOWN = { point = "TOP", rel = "BOTTOM", x = 0, y = 4, dx = 0, dy = -6 },
    UP   = { point = "BOTTOM", rel = "TOP", x = 0, y = -4, dx = 0, dy = 6 },
    LEFT = { point = "RIGHT", rel = "LEFT", x = 4, y = 0, dx = -6, dy = 0 },
}

local function Callout(width)
    local f = CreateFrame("Frame", nil, UIParent, "GlowBoxTemplate")
    f:SetWidth(width)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()

    f.Text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    f.Text:SetWidth(width - 32)
    f.Text:SetPoint("TOPLEFT", 16, -18)
    f.Text:SetJustifyV("TOP")
    f.Text:SetSpacing(4)

    f.Close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.Close:SetPoint("TOPRIGHT", 6, 6)

    f.Arrow = CreateFrame("Frame", nil, f, "GlowBoxArrowTemplate")
    local bob = f.Arrow:CreateAnimationGroup()
    bob:SetLooping("BOUNCE")
    f.Bob = bob:CreateAnimation("Translation")
    f.Bob:SetDuration(0.5)
    f.Bob:SetSmoothing("IN_OUT")
    f:SetScript("OnShow", function() bob:Play() end)
    f:SetScript("OnHide", function() bob:Stop() end)

    -- extra height below the text (buttons)
    f.foot = 0
    return f
end

local function PointArrow(f, dir)
    local at = ARROW_AT[dir]
    local a = f.Arrow
    a:ClearAllPoints()
    a:SetPoint(at.point, f, at.rel, at.x, at.y)
    Turn(a.Arrow, ARROW, dir)
    Turn(a.Glow, GLOW, dir)
    a:SetSize(a.Arrow:GetSize())
    a.Arrow:ClearAllPoints()
    a.Arrow:SetPoint("CENTER")
    a.Glow:ClearAllPoints()
    a.Glow:SetPoint("CENTER")
    f.Bob:SetOffset(at.dx, at.dy)
end

local function FitHeight(f)
    f:SetHeight(f.Text:GetStringHeight() + 36 + f.foot)
end

---------------------------------------------------------------------------
-- 1. welcome
---------------------------------------------------------------------------

local WIDTH, PAD, ICON, ROW_GAP = 400, 24, 30, 12
local PORTRAIT = 52

local welcome = CreateFrame("Frame", "PartyBotGuideWelcomeFrame", UIParent, "BackdropTemplate")
welcome:SetWidth(WIDTH)
welcome:SetPoint("CENTER", 0, 80)
welcome:SetFrameStrata("DIALOG")
welcome:SetToplevel(true)
welcome:EnableMouse(true)
welcome:SetClampedToScreen(true)
welcome:Hide()
welcome:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
tinsert(UISpecialFrames, welcome:GetName())

local header = welcome:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64)
header:SetPoint("TOP", 0, 12)
local title = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText(L["guide.welcome.title"])

local close = CreateFrame("Button", nil, welcome, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

local portrait = welcome:CreateTexture(nil, "ARTWORK")
portrait:SetSize(PORTRAIT, PORTRAIT)

local function Text(font, width)
    local fs = welcome:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    return fs
end

local intro = Text("GameFontHighlight", WIDTH - 2 * PAD - PORTRAIT - 12)

local ROWS = {
    { icon = "Interface\\Icons\\INV_Misc_Bag_10",
      title = L["guide.welcome.real.title"], text = L["guide.welcome.real.text"] },
    { icon = "Interface\\Icons\\INV_Misc_Map_01",
      title = L["guide.welcome.grow.title"], text = L["guide.welcome.grow.text"] },
    { icon = "Interface\\Icons\\INV_Letter_15",
      title = L["guide.welcome.person.title"], text = L["guide.welcome.person.text"] },
}
local rows = {}
for i, r in ipairs(ROWS) do
    local icon = welcome:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON, ICON)
    icon:SetTexture(r.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local name = welcome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
    name:SetText(r.title)
    local text = Text("GameFontHighlightSmall", WIDTH - 2 * PAD - ICON - 10)
    text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    text:SetText(r.text)
    rows[i] = { icon = icon, name = name, text = text }
end

local foot = Text("GameFontNormal", WIDTH - 2 * PAD)
foot:SetJustifyH("CENTER")
foot:SetText(L["guide.welcome.foot"])

local ok = CreateFrame("Button", nil, welcome, "UIPanelButtonTemplate")
ok:SetSize(110, 22)
ok:SetPoint("BOTTOM", 0, 20)
ok:SetText(L["guide.welcome.ok"])
ok:SetScript("OnClick", function() welcome:Hide() end)

local function LayoutWelcome()
    local y = 34
    portrait:SetPoint("TOPLEFT", PAD, -y)
    intro:SetPoint("LEFT", portrait, "RIGHT", 12, 0)
    y = y + math.max(PORTRAIT, intro:GetStringHeight())
    for _, r in ipairs(rows) do
        y = y + ROW_GAP + 2
        r.icon:SetPoint("TOPLEFT", PAD, -y)
        y = y + math.max(ICON, r.name:GetStringHeight() + 3 + r.text:GetStringHeight())
    end
    y = y + ROW_GAP + 8
    foot:SetPoint("TOP", 0, -y)
    y = y + foot:GetStringHeight()
    welcome:SetHeight(y + 20 + 22 + 20)
end

welcome:SetScript("OnShow", function()
    LayoutWelcome()
    PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
end)
-- however it closes (button, X, ESC), the arrow comes next
welcome:SetScript("OnHide", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    local s = State()
    if s and s.step == "welcome" then
        s.step = "arrow"
        ShowArrow()
    end
end)

local function ShowWelcome(name)
    local unit = ns.UnitOf(name)
    if unit then
        SetPortraitTexture(portrait, unit)
    else
        SetPortraitToTexture(portrait, ns.COMPANIONS_ICON)
    end
    intro:SetText(L("guide.welcome.intro", { name = name or "" }))
    welcome:Show()
end

-- Once he is in the party (he logs in again after his yes) and not while fighting; after
-- WAIT_PARTY_SEC without him in the party anyway.
local waiting = false
local function TryWelcome(waited)
    local s = State()
    if not s or s.step ~= "welcome" then
        waiting = false
        return
    end
    waited = waited or 0
    local inParty = s.name and ns.UnitOf(s.name) ~= nil
    if not InCombatLockdown() and not UnitIsDeadOrGhost("player") and (inParty or waited >= WAIT_PARTY_SEC) then
        waiting = false
        ShowWelcome(s.name)
        return
    end
    waiting = true
    C_Timer.After(1, function() TryWelcome(waited + 1) end)
end

local function Begin(name)
    local s = State()
    if not s then return end
    wipe(s)
    s.step = "welcome"
    s.name = name
    if not waiting then TryWelcome() end
end

---------------------------------------------------------------------------
-- 2. arrow over the bottom bar button
---------------------------------------------------------------------------

local arrow = Callout(220)
arrow.Text:SetText(L["guide.arrow"])
PointArrow(arrow, "DOWN")
if button then arrow:SetPoint("BOTTOM", button, "TOP", 0, 18) end
arrow:HookScript("OnShow", FitHeight)
-- X: no arrow any more; the tour still comes when the panel opens
arrow.Close:SetScript("OnClick", function()
    local s = State()
    if s and s.step == "arrow" then s.step = "tour" end
    arrow:Hide()
end)
arrow:HookScript("OnHide", function()
    if button and MicroButtonPulseStop then MicroButtonPulseStop(button) end
end)

ShowArrow = function()
    if panel and panel:IsShown() then
        StartTour()
        return
    end
    if not button or not button:IsVisible() then return end
    arrow:Show()
    if MicroButtonPulse then MicroButtonPulse(button) end
end

---------------------------------------------------------------------------
-- 3. tour of the Companions panel
---------------------------------------------------------------------------

local PAGES = {
    { text = "guide.tour.slots", dir = "UP",
      place = function(f) f:SetPoint("TOP", panel.summary, "BOTTOM", 0, -24) end },
    { text = "guide.tour.list", dir = "LEFT",
      place = function(f) f:SetPoint("LEFT", panel.Inset, "RIGHT", 24, 0) end },
    { text = "guide.tour.affinity", dir = "LEFT",
      place = function(f) f:SetPoint("LEFT", PartyBotCompanionShowcase or panel, "RIGHT", 28, 0) end },
}

local tour = Callout(260)
tour.foot = 30
tour.Page = tour:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
tour.Page:SetPoint("BOTTOMLEFT", 16, 14)
tour.Next = CreateFrame("Button", nil, tour, "UIPanelButtonTemplate")
tour.Next:SetSize(90, 22)
tour.Next:SetPoint("BOTTOMRIGHT", -12, 10)
tour:HookScript("OnShow", FitHeight)

local page = 0
local function ShowPage(n)
    local p = PAGES[n]
    if not p then return end
    page = n
    tour:Hide()
    tour:ClearAllPoints()
    p.place(tour)
    PointArrow(tour, p.dir)
    tour.Text:SetText(L[p.text])
    tour.Page:SetText(L("guide.tour.page", { page = n, total = #PAGES }))
    tour.Next:SetText(n < #PAGES and L["guide.tour.next"] or L["guide.tour.done"])
    FitHeight(tour)
    tour:Show()
end

local function EndTour()
    local s = State()
    if s then s.step = "done" end
    tour:Hide()
end

tour.Next:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    if page < #PAGES then ShowPage(page + 1) else EndTour() end
end)
tour.Close:SetScript("OnClick", EndTour)

-- after the list arrived (the slot count is empty before), at most a few seconds
StartTour = function()
    local s = State()
    if not s then return end
    s.step = "tour"
    arrow:Hide()
    local tries = 0
    local function Go()
        if not panel:IsShown() then return end
        tries = tries + 1
        if ns.CompanionsLoaded() or tries > 10 then ShowPage(1) else C_Timer.After(0.3, Go) end
    end
    C_Timer.After(0.3, Go)
end

if panel then
    panel:HookScript("OnShow", function()
        local s = State()
        if s and (s.step == "arrow" or s.step == "tour") then StartTour() end
    end)
    panel:HookScript("OnHide", function() tour:Hide() end)
end

---------------------------------------------------------------------------
-- triggers
---------------------------------------------------------------------------

-- his first companion (Recruit.lua prints the note of the same line)
ns.On("PBTRIAL", function(msg)
    local _, bot, kind, first = strsplit(";", msg)
    if kind == "bond" and first == "1" and bot and bot ~= "" then
        local s = State()
        if s and not s.step then Begin(bot) end
    end
end)

-- after a reload or the next login: where he left it
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    ns.OnLoad(function()
        C_Timer.After(3, function()
            local s = State()
            if not s then return end
            if s.step == "welcome" then
                if not waiting then TryWelcome() end
            elseif s.step == "arrow" then
                ShowArrow()
            end
        end)
    end)
end)

-- /pbguide [name]: from the start again (name: the companion the welcome is about)
SLASH_PARTYBOTGUIDE1 = "/pbguide"
SlashCmdList.PARTYBOTGUIDE = function(arg)
    local name = arg and strtrim(arg) or ""
    if name == "" then
        local list = ns.CompanionsList and ns.CompanionsList()
        name = list and list[1] and list[1].name or UnitName("party1") or ""
    end
    local s = State()
    if s then wipe(s) end   -- (before hiding: a hidden welcome moves on to the arrow)
    welcome:Hide()
    arrow:Hide()
    tour:Hide()
    Begin(name)
end
