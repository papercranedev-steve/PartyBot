-- Companions panel (伙伴): the companions you recruited. Two panes in one native UI panel
-- (ButtonFrameTemplate like the Social window; UIPanelWindows: docks left, pushes other panels,
-- ESC closes it):
--   left   the roster as cards: portrait in a target-frame ring (silver dragon at 信任, gold at
--          挚友), name, standing, level, spec and class, experience bar, where he is
--   right  the selected companion (CompanionShowcase.lua): model, the affinity ruler, actions
-- Left-click a card selects it, double-click opens the character sheet, right-click the menu.
-- Affinity gained since you last looked shows as "+N" (seen values in PartyBotDB.companionAffinitySeen).
--
-- Request: .partybot companions
-- Reply:   PBCMP;BEGIN;<count> | PBCMP;C;<guid>;<race>;<class>;<gender>;<level>;<xp>;<next xp, 0 = max>;
--          <a/b/c talent points>;<affinity 0-100>;<state 0 offline 1 online 2 in group 3 former>;<zone id>;
--          <recruited at>;<tag,tag>;<name> | PBCMP;END
--          PBCMP;GATE;<affinity>;<class mask>;<key>;<ready 1/0>;<label> lines (after BEGIN): what
--          affinity allows (ready 0 = not built yet; shown like any other gate)
--          PBCMP;BLOCK;<guid>;<gate key>;<text> (after its C line): an open gate he cannot serve now
--          PBCMP;TRAIT;<guid>;<80/90>;<key>;<rarity 0-2>;<label>;<text> (after its C line): a friend trait
--          PBCMP;SLOTS;<used>;<total>;<max>;<next free level, 0 = all open>;<can buy 1/0>;<price copper>;
--          <levels the free ones open at, l,l,...>   (the slots panel: CompanionSlots.lua)
--          PBCMP;ACC;<guid>;<1 joined at affinity 100, 2 one you made> (after its C line): one of
--          your account's characters (companion account doc)
-- Former companions (state 3, 故人) and your account's characters are lists of their own: the
-- attic buttons show them instead.

local _, ns = ...
local L = ns.L

ns.COMPANIONS_ICON = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude"

local FRAME_W, FRAME_H = 720, 460
local TOP = 60                  -- below the portrait and title (the "attic")
local BOTTOM = 6                -- (no button bar)
local LIST_W = 300              -- left pane
local CARD_W, CARD_H, CARD_GAP = 266, 56, 4
local CARDS = 6
local REFRESH_SECONDS = 15      -- while shown and in a group (outside a group only clicks can send)

-- FORMER: a former companion (故人): you said goodbye, he takes no slot (CompanionMenu.lua invites back)
local STATE_OFFLINE, STATE_ONLINE, STATE_GROUP, STATE_FORMER = 0, 1, 2, 3

ns.COMPANION_STATE = { OFFLINE = STATE_OFFLINE, ONLINE = STATE_ONLINE, GROUP = STATE_GROUP, FORMER = STATE_FORMER }
-- c.account of your account's characters (PBCMP;ACC): joined at affinity 100, or one you made
ns.ACCOUNT_KIND = { COMPANION = 1, OWN = 2 }

-- personality tag keys (server Companions/Personality.cpp) -> label
local TAG_TEXT = {
    diligent = L["companions.tag.diligent"], crafty = L["companions.tag.crafty"], frugal = L["companions.tag.frugal"], gatherer = L["companions.tag.gatherer"],
    homebody = L["companions.tag.homebody"], chatty = L["companions.tag.chatty"], quiet = L["companions.tag.quiet"], nightowl = L["companions.tag.nightowl"],
    spendthrift = L["companions.tag.spendthrift"], careless = L["companions.tag.careless"], lazy = L["companions.tag.lazy"],
}

-- affinity 0-100 -> standing like the reputation standings it grows through (4 neutral .. 8 exalted);
-- ring = the target frame art around his portrait. 100 = he can join your account.
local AFFINITY_STANDINGS = {
    { min = 100, standing = 8, text = L["companions.standing.8"], ring = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite" },
    { min = 80, standing = 7, text = L["companions.standing.7"], ring = "Interface\\TargetingFrame\\UI-TargetingFrame-Elite" },
    { min = 50, standing = 6, text = L["companions.standing.6"], ring = "Interface\\TargetingFrame\\UI-TargetingFrame-Rare" },
    { min = 20, standing = 5, text = L["companions.standing.5"], ring = "Interface\\TargetingFrame\\UI-TargetingFrame" },
    { min = 0,  standing = 4, text = L["companions.standing.4"], ring = "Interface\\TargetingFrame\\UI-TargetingFrame" },
}

local function AffinityStanding(value)
    for _, s in ipairs(AFFINITY_STANDINGS) do
        if value >= s.min then return s end
    end
    return AFFINITY_STANDINGS[#AFFINITY_STANDINGS]
end

local function AffinityColor(value)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[AffinityStanding(value).standing]
    if c then return c.r, c.g, c.b end
    return 0, 0.6, 0.1
end

ns.AFFINITY_STANDINGS = AFFINITY_STANDINGS     -- (highest first)
ns.AffinityStanding = AffinityStanding
ns.AffinityColor = AffinityColor

-- friend traits (server Companions/Affinity/Traits): the affinities they come at, and their rarity
-- in item quality colours (common green, rare blue, epic purple). c.traits[at] once he has it.
ns.TRAIT_AT = { 80, 90 }
ns.TRAIT_RARITY_COLOR = { [0] = "|cff1eff00", [1] = "|cff0070dd", [2] = "|cffa335ee" }
ns.TRAIT_RARITY_TEXT = { [0] = L["companions.rarity.common"], [1] = L["companions.rarity.rare"], [2] = L["companions.rarity.epic"] }

function ns.TagLabels(tags)
    local labels = {}
    for _, tag in ipairs(tags or {}) do labels[#labels + 1] = TAG_TEXT[tag] or tag end
    return labels
end

-- the portrait of a companion into `tex` (round): live if the client has him, else his race
function ns.CompanionPortrait(tex, c)
    local unit = ns.UnitOf(c.name)
    if unit then
        SetPortraitTexture(tex, unit)
        return true
    end
    SetPortraitToTexture(tex, ns.RacePortrait(c.race, c.gender) or ns.COMPANIONS_ICON)
    return false
end

-- The target frame ring around a round portrait of `size`, mirrored so the dragon (信任 / 挚友)
-- wraps the portrait's left side. In the art the 64 px portrait is centred at (182, 44) of 256x128;
-- the part right of x = 148 is used (left of it is the name and health bar frame). The ring's level
-- badge (centred at about (206, 66)) ends up at the portrait's lower left: PlaceAffinityRingLevel.
local RING_LEFT, RING_CX, RING_CY, RING_BOTTOM = 148, 182, 44, 100
local RING_LEVEL_X, RING_LEVEL_Y = 206, 66
function ns.PlaceAffinityRing(ring, portrait, size)
    local s = size / 64
    ring:SetSize((256 - RING_LEFT) * s, RING_BOTTOM * s)
    ring:SetTexCoord(1, RING_LEFT / 256, 0, RING_BOTTOM / 128)
    ring:ClearAllPoints()
    ring:SetPoint("TOPLEFT", portrait, "CENTER", -(256 - RING_CX) * s, RING_CY * s)
end

-- the level text into the ring's badge (small rings get a smaller font)
function ns.PlaceAffinityRingLevel(text, portrait, size)
    local s = size / 64
    text:ClearAllPoints()
    text:SetPoint("CENTER", portrait, "CENTER", -(RING_LEVEL_X - RING_CX) * s, -(RING_LEVEL_Y - RING_CY) * s)
    if s < 1 then
        local file, height, flags = text:GetFont()
        if file then text:SetFont(file, math.max(8, math.floor(height * s + 2.5)), flags) end
    end
end

-- A status bar in the character window's skill bar look (Blizzard SkillStatusBarTemplate: the
-- glossy skill bar fill inside UI-Character-Skills-BarBorder, which is 32 px tall around a 15 px
-- bar and 10 px longer). `thickness` scales the border; vertical bars fill upward and get the
-- art turned a quarter. bar.top is a frame above the border for ticks and the spark.
local BAR_FILL = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local BAR_BORDER = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder"
function ns.CreateFramedBar(parent, length, thickness, vertical)
    local k = thickness / 15
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BAR_FILL)
    bar:SetMinMaxValues(0, 100)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    bar.top = CreateFrame("Frame", nil, bar)
    bar.top:SetAllPoints()
    bar.top:SetFrameLevel(bar:GetFrameLevel() + 2)
    local border = bar.top:CreateTexture(nil, "BORDER")
    border:SetTexture(BAR_BORDER)
    border:SetPoint("CENTER")
    if vertical then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetSize(thickness, length)
        border:SetSize(32 * k, length + 10 * k)
        border:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)   -- the art's left end at the bottom
    else
        bar:SetSize(length, thickness)
        border:SetSize(length + 10 * k, 32 * k)
    end
    bar.border = border
    return bar
end

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------

local companions = {}   -- list of entries, sorted for display
local formers = {}      -- former companions (故人), sorted the same way
-- the other characters of your account (c.account: 1 a companion who joined it at affinity 100,
-- 2 one you made; companion account doc): called over like companions, no slot
local accounts = {}
local slots = { used = 0, total = 0, max = 0, nextLevel = 0, canBuy = false, price = 0, freeLevels = {} }
local view = "companions"   -- the list shown: "companions", "formers", "account"
local showFormers = false   -- (view == "formers")
local loaded = false    -- a list came from the server
local incoming
local gates = {}        -- what affinity allows (server Companions/Affinity/Gates), by affinity
local incomingGates
local selected          -- guid
local sortKey = "state"
local gains = {}        -- guid -> affinity gained since last looked (while the panel is open)

local function SpecIndex(c)
    local best, points = nil, 0
    for i = 1, 3 do
        if c.talents[i] > points then best, points = i, c.talents[i] end
    end
    return best
end

local function ClassLine(c)
    local class = ns.CLASS_TEXT[c.class] or ""
    local spec = SpecIndex(c)
    local trees = ns.TREE_NAMES[c.class]
    if spec and trees then return trees[spec] .. " " .. class end
    return class
end

ns.CompanionSpecIndex = SpecIndex
ns.CompanionClassLine = ClassLine

local function ByName(a, b) return a.name < b.name end

local SORTS = {
    { key = "state", text = L["companions.sort.state"], less = function(a, b)
        if a.state ~= b.state then return a.state > b.state end
        if a.affinity ~= b.affinity then return a.affinity > b.affinity end
        return ByName(a, b)
    end },
    { key = "affinity", text = L["companions.sort.affinity"], less = function(a, b)
        if a.affinity ~= b.affinity then return a.affinity > b.affinity end
        return ByName(a, b)
    end },
    { key = "level", text = L["companions.sort.level"], less = function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return ByName(a, b)
    end },
    { key = "class", text = L["companions.sort.class"], less = function(a, b)
        if a.class ~= b.class then return (ns.CLASS_TEXT[a.class] or "") < (ns.CLASS_TEXT[b.class] or "") end
        return ByName(a, b)
    end },
    { key = "name", text = L["companions.sort.name"], less = ByName },
}

local function SortOf(key)
    for _, s in ipairs(SORTS) do
        if s.key == key then return s end
    end
    return SORTS[1]
end

local function Sort()
    table.sort(companions, SortOf(sortKey).less)
    table.sort(formers, SortOf(sortKey).less)
    table.sort(accounts, SortOf(sortKey).less)
end

local function Shown()
    if view == "formers" then return formers end
    if view == "account" then return accounts end
    return companions
end

local function SetView(v)
    view = v
    showFormers = v == "formers"
end

-- the last list from the server (nil before the first one); former companions and your account's
-- characters too
function ns.FindCompanion(guid)
    for _, list in ipairs({ companions, formers, accounts }) do
        for _, c in ipairs(list) do
            if c.guid == guid then return c end
        end
    end
end

-- slots from the last list: used, total, max, nextLevel (0: all free ones open), canBuy, price (copper),
-- freeLevels (ascending: the levels the free ones open at)
function ns.CompanionSlots() return slots end

-- the companions (not the former ones) from the last list, sorted for display
function ns.CompanionsList() return companions end

function ns.CompanionsLoaded() return loaded end

-- The gates that apply to a companion of class `classId` (by affinity), from the last list.
function ns.AffinityGates(classId)
    local list = {}
    for _, g in ipairs(gates) do
        if g.classMask == 0 or (classId and classId > 0 and bit.band(g.classMask, bit.lshift(1, classId - 1)) ~= 0) then
            list[#list + 1] = g
        end
    end
    return list
end

-- Whether companion `c` lets you do what the gate `key` stands for (the server's Gates.cpp keys:
-- "bags", "summon", ...). Your account's characters have no gates (server Gates::Allows).
function ns.GateOpen(c, key)
    if c.account then return true end
    for _, g in ipairs(ns.AffinityGates(c.class)) do
        if g.key == key then return c.affinity >= g.affinity end
    end
    return false
end

-- (not the former ones: they are never with you)
function ns.FindCompanionByName(name)
    for _, list in ipairs({ companions, accounts }) do
        for _, c in ipairs(list) do
            if c.name == name then return c end
        end
    end
end

-- affinity gained since the player last opened the panel (0 if none)
function ns.CompanionAffinityGain(guid)
    return gains[guid] or 0
end

-- Asks for the list again; fn(list) runs when it arrives (only from clicks: may go out as SAY).
local listWaiters = {}
function ns.RequestCompanions(fn)
    if fn then listWaiters[#listWaiters + 1] = fn end
    ns.SendCommand(".partybot companions")
end

-- fn() runs every time a new list arrived (other windows redraw)
local listedHandlers = {}
function ns.OnCompanionsListed(fn) listedHandlers[#listedHandlers + 1] = fn end

-- The player is looking: what grew since the last look becomes a gain, and is seen now.
local function MarkSeen()
    if not ns.db then return end
    ns.db.companionAffinitySeen = ns.db.companionAffinitySeen or {}
    local seen = ns.db.companionAffinitySeen
    for _, c in ipairs(companions) do
        local before = seen[c.guid]
        if before and c.affinity > before then
            gains[c.guid] = (gains[c.guid] or 0) + c.affinity - before
        end
        seen[c.guid] = c.affinity
    end
end

---------------------------------------------------------------------------
-- frame (ButtonFrameTemplate, like the Social window)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PartyBotCompanionsFrame", UIParent, "ButtonFrameTemplate")
frame:SetSize(FRAME_W, FRAME_H)
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:Hide()
UIPanelWindows["PartyBotCompanionsFrame"] = { area = "left", pushable = 1, whileDead = 1, width = FRAME_W, height = FRAME_H }
ns.CompanionsFrame = frame
-- where the right pane goes (CompanionShowcase.lua)
ns.CompanionsLayout = { left = LIST_W + 8, top = TOP, right = 6, bottom = BOTTOM }

SetPortraitToTexture(frame.portrait, ns.COMPANIONS_ICON)
frame.TitleText:SetText(L["companions.title"])
-- no button bar (before the inset is placed: this re-anchors the inset)
if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end

frame.Inset:ClearAllPoints()
frame.Inset:SetPoint("TOPLEFT", 4, -TOP)
frame.Inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 4 + LIST_W, BOTTOM)

-- the attic: how many, and the sort (its label outside the menu: the menu only shows the key)
frame.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
frame.summary:SetPoint("TOPLEFT", 70, -38)

local sortMenu = CreateFrame("Frame", "PartyBotCompanionsSortMenu", frame, "UIDropDownMenuTemplate")
sortMenu:SetPoint("TOPRIGHT", frame, "TOPLEFT", LIST_W + 18, -30)
UIDropDownMenu_SetWidth(sortMenu, 80)
local sortLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
sortLabel:SetPoint("RIGHT", sortMenu, "LEFT", 14, 2)   -- (the menu art starts 16 px in)
sortLabel:SetText(L["companions.sort"])
UIDropDownMenu_Initialize(sortMenu, function()
    for _, s in ipairs(SORTS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = s.text
        info.checked = s.key == sortKey
        info.func = function()
            sortKey = s.key
            UIDropDownMenu_SetText(sortMenu, s.text)
            Sort()
            ns.UpdateCompanions()
        end
        UIDropDownMenu_AddButton(info)
    end
end)
UIDropDownMenu_SetText(sortMenu, SortOf(sortKey).text)

-- nobody yet
frame.empty = frame.Inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
frame.empty:SetPoint("CENTER", 0, 20)
frame.empty:SetWidth(LIST_W - 30)
frame.empty:SetText(L["companions.empty"])

---------------------------------------------------------------------------
-- cards
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", "PartyBotCompanionsScrollFrame", frame, "FauxScrollFrameTemplate")
scroll:SetSize(CARD_W, CARDS * (CARD_H + CARD_GAP))
scroll:SetPoint("TOPLEFT", frame.Inset, "TOPLEFT", 4, -6)
scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, CARD_H + CARD_GAP, ns.UpdateCompanions)
end)

local cards = {}

local function Select(c)
    if selected == c.guid then return end
    selected = c.guid
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    ns.UpdateCompanions()
end

local function CreateCard(i)
    local card = CreateFrame("Button", "PartyBotCompanionsCard" .. i, frame)
    card:SetSize(CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * (CARD_H + CARD_GAP))
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- class tinted, fading to the right
    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

    local hl = card:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.5)

    -- selected: gold glow and a thin gold edge
    card.glow = card:CreateTexture(nil, "BORDER")
    card.glow:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    card.glow:SetBlendMode("ADD")
    card.glow:SetVertexColor(1, 0.82, 0)
    card.glow:SetAllPoints()
    card.edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = card:CreateTexture(nil, "BORDER")
        e:SetColorTexture(1, 0.82, 0, 0.8)
        if side == "TOP" or side == "BOTTOM" then
            e:SetPoint(side .. "LEFT")
            e:SetPoint(side .. "RIGHT")
            e:SetHeight(1)
        else
            e:SetPoint("TOP" .. side)
            e:SetPoint("BOTTOM" .. side)
            e:SetWidth(1)
        end
        card.edges[#card.edges + 1] = e
    end

    -- portrait and its ring (on a frame above the next card: the dragon reaches a little past the card)
    card.portrait = card:CreateTexture(nil, "ARTWORK")
    card.portrait:SetSize(40, 40)
    card.portrait:SetPoint("CENTER", card, "LEFT", 46, 0)
    local over = CreateFrame("Frame", nil, card)
    over:SetAllPoints()
    over:SetFrameLevel(card:GetFrameLevel() + 3)
    card.ring = over:CreateTexture(nil, "ARTWORK")
    ns.PlaceAffinityRing(card.ring, card.portrait, 40)
    card.level = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.PlaceAffinityRingLevel(card.level, card.portrait, 40)

    local x = 76
    card.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    card.name:SetPoint("TOPLEFT", x, -7)
    card.standing = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    card.standing:SetPoint("LEFT", card.name, "RIGHT", 5, 0)
    card.where = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.where:SetPoint("TOPRIGHT", -8, -8)
    card.where:SetWidth(84)
    card.where:SetJustifyH("RIGHT")
    card.where:SetWordWrap(false)

    card.class = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.class:SetPoint("TOPLEFT", x, -24)

    card.gain = card:CreateFontString(nil, "ARTWORK", "GameFontGreenSmall")
    card.gain:SetPoint("LEFT", card.standing, "RIGHT", 3, 0)

    -- experience (affinity is in the right pane)
    local bar = ns.CreateFramedBar(card, 140, 9)
    bar:SetPoint("TOPLEFT", x + 2, -38)
    card.bar = bar
    card.value = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.value:SetPoint("LEFT", bar, "RIGHT", 8, 0)

    card:SetScript("OnClick", function(self, mouseButton)
        if not self.entry then return end
        Select(self.entry)
        if mouseButton == "RightButton" then ns.ShowCompanionMenu(self.entry) end
    end)
    card:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.entry.name, ns.ClassColor(self.entry.class))
        GameTooltip:AddLine(L["companions.card.doubleclick"], 1, 1, 1)
        GameTooltip:AddLine(L["companions.card.rightclick"], 1, 1, 1)
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", GameTooltip_Hide)
    card:SetScript("OnDoubleClick", function(self, mouseButton)
        if self.entry and mouseButton == "LeftButton" then ns.Sheet.Open(self.entry.guid) end
    end)
    return card
end

for i = 1, CARDS do cards[i] = CreateCard(i) end

local function Tint(tex, r, g, b, alpha)
    if tex.SetGradientAlpha then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradientAlpha("HORIZONTAL", r, g, b, alpha, r, g, b, 0.03)
    else
        tex:SetVertexColor(r, g, b, alpha * 0.5)
    end
end

local function ZoneName(zone)
    return zone and zone > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(zone) or nil
end
ns.CompanionZoneName = ZoneName

local function FillCard(card, c)
    -- (never "offline": one not in the world is at his place, 2026-11-21-companion-presence)
    local r, g, b = ns.ClassColor(c.class)
    local s = AffinityStanding(c.affinity)

    Tint(card.bg, r, g, b, 0.28)
    ns.CompanionPortrait(card.portrait, c)
    card.ring:SetTexture(s.ring)

    card.name:SetText(c.name)
    card.name:SetTextColor(r, g, b)
    if c.account == ns.ACCOUNT_KIND.OWN then
        -- (one you made: no affinity, a plain ring)
        card.ring:SetTexture(AFFINITY_STANDINGS[#AFFINITY_STANDINGS].ring)
        card.standing:SetText(L["companions.card.own"])
        card.standing:SetTextColor(0.75, 0.75, 0.75)
    else
        card.standing:SetText(s.text)
        local sr, sg, sb = AffinityColor(c.affinity)
        card.standing:SetTextColor(sr, sg, sb)
    end

    if c.state == STATE_GROUP then
        card.where:SetText(L["companions.card.in_group"])
        card.where:SetTextColor(GREEN_FONT_COLOR.r, GREEN_FONT_COLOR.g, GREEN_FONT_COLOR.b)
    elseif c.state == STATE_FORMER then
        card.where:SetText(ZoneName(c.zone) or L["companions.card.former"])
        card.where:SetTextColor(0.6, 0.6, 0.6)
    else
        card.where:SetText(ZoneName(c.zone) or "")
        card.where:SetTextColor(1, 1, 1)
    end

    card.level:SetText(c.level)
    card.class:SetText(ClassLine(c))
    card.class:SetTextColor(1, 1, 1)

    if c.nextXp > 0 then
        local pct = math.floor(c.xp * 100 / c.nextXp)
        card.bar:SetValue(pct)
        card.bar:SetStatusBarColor(0.58, 0, 0.55)       -- the experience bar's purple
        card.value:SetText(pct .. "%")
        card.value:SetTextColor(1, 1, 1)
    else
        card.bar:SetValue(100)
        card.bar:SetStatusBarColor(0.6, 0.5, 0.2)
        card.value:SetText(L["companions.card.max_level"])
        card.value:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end
    local gain = gains[c.guid] or 0
    card.gain:SetText(gain > 0 and ("+" .. gain) or "")

    local isSelected = c.guid == selected
    card.glow:SetShown(isSelected)
    for _, e in ipairs(card.edges) do e:SetShown(isSelected) end
end

local UpdateBar     -- (the attic buttons, below)

function ns.UpdateCompanions()
    local list = Shown()
    local total = #list
    local found = false
    for _, c in ipairs(list) do
        if c.guid == selected then found = true end
    end
    if not found then selected = list[1] and list[1].guid end

    if showFormers then
        frame.summary:SetText(L("companions.formers.summary", { count = total }))
    elseif view == "account" then
        frame.summary:SetText(L("companions.account.summary", { count = total }))
    elseif not frame.loaded then
        frame.summary:SetText("")
    else
        -- 伙伴 3/5: in the party and on the bench, of his slots; green while one is free, gold when full
        -- (when more open is in the slots panel, not here)
        local color = slots.used < slots.total and GREEN_FONT_COLOR or NORMAL_FONT_COLOR
        local count = color:WrapTextInColorCode(slots.used .. "/" .. slots.total)
        frame.summary:SetText(L("companions.summary", { count = count }))
    end
    frame.empty:SetText(showFormers and L["companions.formers.empty"]
        or view == "account" and L["companions.account.empty"] or L["companions.empty"])
    frame.empty:SetShown(total == 0 and frame.loaded)
    if UpdateBar then UpdateBar() end

    local offset = FauxScrollFrame_GetOffset(scroll)
    for i, card in ipairs(cards) do
        local c = list[offset + i]
        card.entry = c
        if c then
            FillCard(card, c)
            card:Show()
        else
            card:Hide()
        end
    end
    FauxScrollFrame_Update(scroll, total, CARDS, CARD_H + CARD_GAP)

    if ns.ShowcaseCompanion then ns.ShowcaseCompanion(ns.FindCompanion(selected)) end
end

---------------------------------------------------------------------------
-- bottom button bar
---------------------------------------------------------------------------

-- None (hidden where the frame is made): how to use a card is in its tooltip, and there is no
-- refresh button (the list comes on open, every REFRESH_SECONDS in a group, and on PBGATE).
-- The slot buttons sit in the attic, top right.

---------------------------------------------------------------------------
-- attic buttons: former companions, buying a slot (companion slots doc)
---------------------------------------------------------------------------

-- the former companions (故人) instead of the companions, and back
local formersButton = CreateFrame("Button", "PartyBotCompanionsFormersButton", frame, "UIPanelButtonTemplate")
formersButton:SetSize(90, 22)
formersButton:SetPoint("TOPRIGHT", -10, -32)
-- (each attic list button shows its list, or the companions again)
local function ToggleView(v)
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    SetView(view == v and "companions" or v)
    selected = nil
    FauxScrollFrame_SetOffset(scroll, 0)
    ns.UpdateCompanions()
end
formersButton:SetScript("OnClick", function() ToggleView("formers") end)
formersButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(showFormers and L["companions.formers_button.back.title"] or L["companions.formers_button.title"])
    GameTooltip:AddLine(showFormers and L["companions.formers_button.back.text"] or L["companions.formers_button.text"], 1, 1, 1, true)
    GameTooltip:Show()
end)
formersButton:SetScript("OnLeave", GameTooltip_Hide)

-- your account's characters instead of the companions, and back (companion account doc)
local accountButton = CreateFrame("Button", "PartyBotCompanionsAccountButton", frame, "UIPanelButtonTemplate")
accountButton:SetSize(90, 22)
accountButton:SetPoint("RIGHT", formersButton, "LEFT", -4, 0)
accountButton:SetScript("OnClick", function() ToggleView("account") end)
accountButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(view == "account" and L["companions.formers_button.back.title"] or L["companions.account_button.title"])
    GameTooltip:AddLine(view == "account" and L["companions.formers_button.back.text"] or L["companions.account_button.text"], 1, 1, 1, true)
    GameTooltip:Show()
end)
accountButton:SetScript("OnLeave", GameTooltip_Hide)

-- the slots panel (CompanionSlots.lua: when more open, buying more); it glows while a slot
-- opened that the player has not looked at yet (ns.CompanionSlotsUnseen)
local slotsButton = CreateFrame("Button", "PartyBotCompanionsSlotsButton", frame, "UIPanelButtonTemplate")
slotsButton:SetSize(90, 22)
slotsButton:SetPoint("RIGHT", accountButton, "LEFT", -4, 0)
slotsButton:SetText(L["companions.slots_button"])
slotsButton:SetScript("OnClick", function()
    if ns.ToggleCompanionSlots then ns.ToggleCompanionSlots() end
end)
slotsButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText(L["companions.slots_button.title"])
    GameTooltip:AddLine(L["companions.slots_button.text"], 1, 1, 1, true)
    if ns.CompanionSlotsUnseen and ns.CompanionSlotsUnseen() then
        GameTooltip:AddLine(L["companions.slots_button.new"], 0.1, 1, 0.1)
    end
    GameTooltip:Show()
end)
slotsButton:SetScript("OnLeave", GameTooltip_Hide)
-- the native button flash (like a micro button's), shown while there is something new
local slotsFlash = slotsButton:CreateTexture(nil, "OVERLAY")
slotsFlash:SetTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")   -- the button's own hover art
slotsFlash:SetTexCoord(0, 0.625, 0, 0.6875)
slotsFlash:SetBlendMode("ADD")
slotsFlash:SetAllPoints()
slotsFlash:Hide()

UpdateBar = function()
    formersButton:SetText(showFormers and L["companions.formers_button.back"] or L("companions.formers_button", { count = #formers }))
    accountButton:SetText(view == "account" and L["companions.formers_button.back"] or L("companions.account_button", { count = #accounts }))
    slotsButton:SetShown(frame.loaded and view == "companions")
    local unseen = ns.CompanionSlotsUnseen and ns.CompanionSlotsUnseen()
    if unseen and not UIFrameIsFlashing(slotsFlash) then
        UIFrameFlash(slotsFlash, 0.6, 0.6, -1, false, 0.2, 0.2)
    elseif not unseen and UIFrameIsFlashing(slotsFlash) then
        UIFrameFlashStop(slotsFlash)
    end
end
ns.UpdateCompanionsAttic = function() if UpdateBar then UpdateBar() end end

---------------------------------------------------------------------------
-- open / close, refresh
---------------------------------------------------------------------------

local sinceRefresh = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    sinceRefresh = sinceRefresh + elapsed
    if sinceRefresh >= REFRESH_SECONDS then
        sinceRefresh = 0
        ns.SendCommandAuto(".partybot companions")
    end
end)

frame:SetScript("OnShow", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    sinceRefresh = 0
    if loaded then MarkSeen() end
    ns.UpdateCompanions()
    ns.SendCommand(".partybot companions")   -- opened by a click or key press
    if ns.OnCompanionsShown then ns.OnCompanionsShown(true) end
end)

frame:SetScript("OnHide", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    wipe(gains)
    if ns.OnCompanionsShown then ns.OnCompanionsShown(false) end
end)

function ns.ToggleCompanions()
    if frame:IsShown() then HideUIPanel(frame) else ShowUIPanel(frame) end
end

ns.RegisterPanel({
    id = "companions", title = L["companions.panel.title"], order = 5, hint = L["companions.panel.hint"],
    toggle = ns.ToggleCompanions, isShown = function() return frame:IsShown() end,
})

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

local function Tags(text)
    local list = {}
    for tag in (text or ""):gmatch("[^,]+") do list[#list + 1] = tag end
    return list
end

-- PBGATE;<bot>;<gate key>: its affinity reached a gate (it said so in party chat): new list
ns.On("PBGATE", function()
    ns.SendCommandAuto(".partybot companions")
    return true
end)

ns.On("PBCMP", function(msg)
    local _, kind, guid, race, class, gender, level, xp, nextXp, talents, affinity, state, zone, recruitedAt, tags, name =
        strsplit(";", msg, 16)
    if kind == "BEGIN" then
        incoming = {}
        incomingGates = {}
    elseif kind == "GATE" and incomingGates then
        -- (fields: guid = affinity, race = class mask, class = key, gender = ready 1/0, level = label)
        incomingGates[#incomingGates + 1] = {
            affinity = tonumber(guid) or 0, classMask = tonumber(race) or 0, key = class,
            ready = gender ~= "0", label = level or "",
        }
    elseif kind == "C" and incoming then
        local a, b, c = (talents or ""):match("^(%d+)/(%d+)/(%d+)$")
        incoming[#incoming + 1] = {
            guid = tonumber(guid), race = tonumber(race) or 0, class = tonumber(class) or 0, gender = tonumber(gender) or 0,
            level = tonumber(level) or 0, xp = tonumber(xp) or 0, nextXp = tonumber(nextXp) or 0,
            talents = { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 },
            affinity = tonumber(affinity) or 0, state = tonumber(state) or 0, zone = tonumber(zone) or 0,
            recruitedAt = tonumber(recruitedAt) or 0, tags = Tags(tags), name = name or "?",
            blocks = {},
        }
    elseif kind == "ACC" and incoming then
        -- (fields: guid, race = kind 1 joined at affinity 100, 2 one you made) your account's character
        local c = incoming[#incoming]
        if c and c.guid == tonumber(guid) then c.account = tonumber(race) end
    elseif kind == "BLOCK" and incoming then
        -- (fields: guid, race = gate key, class = text) an open gate he cannot serve now
        local c = incoming[#incoming]
        if c and c.guid == tonumber(guid) and race then c.blocks[race] = class or "" end
    elseif kind == "TRAIT" and incoming then
        -- (fields: guid, race = the affinity it came at 80/90, class = key, gender = rarity 0-2,
        -- level = label, xp = text) a friend trait he has
        local c = incoming[#incoming]
        if c and c.guid == tonumber(guid) then
            c.traits = c.traits or {}
            c.traits[tonumber(race) or 0] = { key = class, rarity = tonumber(gender) or 0, label = level or "", text = xp or "" }
        end
    elseif kind == "SLOTS" and incoming then
        -- (fields: guid = used, race = total, class = max, gender = next free level, level = can buy,
        -- xp = price, nextXp = the free levels)
        local freeLevels = {}
        for l in (nextXp or ""):gmatch("%d+") do freeLevels[#freeLevels + 1] = tonumber(l) end
        slots = {
            used = tonumber(guid) or 0, total = tonumber(race) or 0, max = tonumber(class) or 0,
            nextLevel = tonumber(gender) or 0, canBuy = level == "1", price = tonumber(xp) or 0,
            freeLevels = freeLevels,
        }
    elseif kind == "END" and incoming then
        -- former companions (故人) and your account's characters are lists of their own
        local active, former, account = {}, {}, {}
        for _, c in ipairs(incoming) do
            if c.account then account[#account + 1] = c
            elseif c.state == STATE_FORMER then former[#former + 1] = c
            else active[#active + 1] = c end
        end
        companions = active
        formers = former
        accounts = account
        incoming = nil
        gates = incomingGates or {}
        incomingGates = nil
        loaded = true
        frame.loaded = true
        Sort()
        if frame:IsShown() then
            MarkSeen()
            ns.UpdateCompanions()
        end
        local waiters = listWaiters
        listWaiters = {}
        for _, fn in ipairs(waiters) do fn(companions) end
        for _, fn in ipairs(listedHandlers) do fn() end
    end
    return true
end)
