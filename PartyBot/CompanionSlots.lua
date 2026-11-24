-- 伙伴位置: how many companions the player can have and when more open (companion slots doc
-- .kiro/docs/2026-11-21-companion-slots.md). A native dialog beside the Companions panel, opened
-- from its attic button 伙伴位置:
--   top     companions / open slots
--   crown   above the track: more slots for gold once every free one is open, up to the maximum
--           (locked look before; the 扩充 button only then; no price on the panel, the confirm
--           dialog says it)
--   track   a vertical bar from level 1 (bottom) to the last free slot's level (top), one tick per
--           free slot, evenly spaced (between two ticks it fills by level and experience); your
--           portrait rides it. At each tick a socket: a companion's portrait (in the order they
--           joined), an empty socket if open, else the level it opens at (the next one gold,
--           glowing). Right of it what that slot means for the party.
-- A slot that opened since the player last looked (PartyBotDB.companionSlotsSeen, per character)
-- is unlocked in front of him: the bar fills up to it, the socket flashes, the quest-complete
-- chime. Reaching such a level says so on screen and pulses the Companions micro button.
--   ns.ToggleCompanionSlots()     open beside the Companions panel / close
--   ns.CompanionSlotsUnseen()     a free slot opened that he has not seen here yet

local _, ns = ...
local L = ns.L

local WIDTH = 400
local PAD = 20
local STEP = 44                 -- between two ticks
local S = 30                    -- socket size
local TRACK_TOP = 168           -- the top tick, from the frame's top
local TRACK_BOTTOM = 34         -- the bar's bottom, from the frame's bottom
local BAR_X, BAR_T = 92, 13
local ME_X = 74                 -- centre of the player's portrait
local LEVEL_RIGHT = 58          -- right edge of the level labels
local SOCKET_X = 140            -- socket centre
local TEXT_X = SOCKET_X + S / 2 + 10
local TEXT_W = WIDTH - TEXT_X - PAD
local UNLOCK_STEP_SECONDS = 0.55
local FILL_COLOR = { 0.95, 0.72, 0.1 }

local CHIME_UNLOCK = 567439     -- sound/interface/iquestcomplete.ogg
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.5, 0.5, 0.5 }

---------------------------------------------------------------------------
-- facts
---------------------------------------------------------------------------

-- (before this session's first list: the levels kept from the last one)
local function Levels()
    local levels = ns.CompanionSlots().freeLevels
    if levels and #levels > 0 then return levels end
    return ns.db and ns.db.companionSlotLevels or {}
end

-- free slots open at the player's level (the server's Slots::FreeAt)
local function FreeOpen(levels, level)
    local n = 0
    for _, l in ipairs(levels) do
        if l <= level then n = n + 1 end
    end
    return n
end

-- how far the bar is filled (0-100): whole steps per open slot, inside a step by level and xp
local function FillPct(levels)
    local n = #levels
    if n == 0 then return 0 end
    local level = UnitLevel("player")
    local maxXp = UnitXPMax("player")
    local lv = level + ((maxXp and maxXp > 0) and UnitXP("player") / maxXp or 0)
    local prev = 1
    for k, l in ipairs(levels) do
        if lv < l then
            local frac = math.max(0, math.min(1, (lv - prev) / math.max(1, l - prev)))
            return (k - 1 + frac) / n * 100
        end
        prev = l
    end
    return 100
end

-- what slot i means for the party (the player + i companions; from 5 on the bench)
local function Meaning(i, n)
    if i == n and n == 8 then return L["companionslots.meaning.every_class"] end
    if i == 1 then return L["companionslots.meaning.two"] end
    if i == 2 then return L["companionslots.meaning.three"] end
    if i == 3 then return L["companionslots.meaning.four"] end
    if i == 4 then return L["companionslots.meaning.five"] end
    if i == 5 then return L["companionslots.meaning.bench"] end
    return L["companionslots.meaning.bench_more"]
end

-- companions in the order they joined (the first one has the first slot)
local function ByJoining()
    local list = {}
    for _, c in ipairs(ns.CompanionsList()) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        if a.recruitedAt ~= b.recruitedAt then return a.recruitedAt < b.recruitedAt end
        return a.name < b.name
    end)
    return list
end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "") end

local function SeenFree()
    local seen = ns.db and ns.db.companionSlotsSeen
    return seen and seen[CharKey()] or 0
end

local function MarkSeen(n)
    if not ns.db then return end
    ns.db.companionSlotsSeen = ns.db.companionSlotsSeen or {}
    ns.db.companionSlotsSeen[CharKey()] = n
end

function ns.CompanionSlotsUnseen()
    return FreeOpen(Levels(), UnitLevel("player")) > SeenFree()
end

---------------------------------------------------------------------------
-- frame (the dialog box, like AffinityHelp)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PartyBotCompanionSlotsFrame", UIParent, "BackdropTemplate")
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
title:SetText(L["companionslots.title"])

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -4, -4)

-- companions / open slots
local count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
count:SetPoint("TOP", 0, -34)
local countNote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
countNote:SetPoint("TOP", count, "BOTTOM", 0, -4)

local function Glow(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "OVERLAY")
    t:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    t:SetBlendMode("ADD")
    t:SetSize(size, size)
    t:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    return t
end

-- an alpha animation on `tex`: from -> to over `seconds` (looping BOUNCE if `loop`)
local function Fade(tex, from, to, seconds, loop)
    local group = tex:CreateAnimationGroup()
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(seconds)
    if loop then
        group:SetLooping("BOUNCE")
    else
        group:SetScript("OnFinished", function() tex:SetAlpha(to) end)
    end
    return group
end

---------------------------------------------------------------------------
-- crown: more slots for gold after the last free one
---------------------------------------------------------------------------

local crown = CreateFrame("Frame", nil, frame, "BackdropTemplate")
crown:SetPoint("TOPLEFT", PAD, -84)
crown:SetPoint("TOPRIGHT", -PAD, -84)
crown:SetHeight(58)
crown:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
crown:SetBackdropColor(0, 0, 0, 0.6)

crown.icon = crown:CreateTexture(nil, "ARTWORK")
crown.icon:SetSize(36, 36)
crown.icon:SetPoint("LEFT", 10, 0)
crown.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
crown.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
crown.title = crown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
crown.title:SetPoint("TOPLEFT", crown.icon, "TOPRIGHT", 8, 0)
crown.text = crown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
crown.text:SetPoint("TOPLEFT", crown.title, "BOTTOMLEFT", 0, -3)
crown.text:SetJustifyH("LEFT")

crown.flash = crown:CreateTexture(nil, "OVERLAY")
crown.flash:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
crown.flash:SetBlendMode("ADD")
crown.flash:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
crown.flash:SetPoint("TOPLEFT", 4, -4)
crown.flash:SetPoint("BOTTOMRIGHT", -4, 4)
crown.flash:SetAlpha(0)
crown.flashAnim = Fade(crown.flash, 1, 0, 1.2)

-- one more slot (the server checks again: Companions/Slots). The price is said here only.
StaticPopupDialogs["PARTYBOT_BUY_SLOT"] = {
    text = "%s",     -- L("companionslots.buy.confirm"), filled in by the button
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function() ns.SendCommand(".partybot buyslot") end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

local buy = CreateFrame("Button", "PartyBotCompanionSlotsBuyButton", crown, "UIPanelButtonTemplate")
buy:SetSize(64, 22)
buy:SetPoint("RIGHT", -10, 0)
buy:SetText(L["companionslots.buy.button"])
buy:SetMotionScriptsWhileDisabled(true)
buy:SetScript("OnClick", function()
    local slots = ns.CompanionSlots()
    StaticPopup_Show("PARTYBOT_BUY_SLOT",
        L("companionslots.buy.confirm", { cost = GetCoinTextureString(slots.price), now = slots.total, max = slots.max }))
end)
buy:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["companionslots.buy.tip.title"])
    GameTooltip:AddLine(L["companionslots.buy.tip.text"], 1, 1, 1, true)
    if not self:IsEnabled() then GameTooltip:AddLine(L["companionslots.buy.tip.no_money"], 1, 0.2, 0.2) end
    GameTooltip:Show()
end)
buy:SetScript("OnLeave", GameTooltip_Hide)

local function ShowCrown(slots, n, lastLevel)
    local bought = math.max(0, slots.total - n)
    local allOpen = slots.nextLevel == 0 and n > 0
    crown.icon:SetDesaturated(not allOpen)
    crown.text:SetWidth(WIDTH - 2 * PAD - 60 - (allOpen and slots.canBuy and 70 or 0))
    if not allOpen then
        crown.title:SetText(L("companionslots.crown.after_level", { level = lastLevel }))
        crown.title:SetTextColor(GREY[1], GREY[2], GREY[3])
        crown.text:SetText(L("companionslots.crown.locked", { max = slots.max }))
        crown.text:SetTextColor(0.6, 0.6, 0.6)
    else
        crown.title:SetText(L["companionslots.crown.title"])
        crown.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        crown.text:SetTextColor(1, 1, 1)
        if slots.canBuy then
            crown.text:SetText(bought > 0 and L("companionslots.crown.bought", { bought = bought, max = slots.max })
                or L("companionslots.crown.can_buy", { max = slots.max }))
        else
            crown.text:SetText(L("companionslots.crown.at_max", { bought = bought }))
        end
    end
    crown:SetBackdropBorderColor(allOpen and GOLD[1] or 0.5, allOpen and GOLD[2] or 0.5, allOpen and GOLD[3] or 0.5)
    -- (the buy button only once every free slot is open)
    buy:SetShown(allOpen and slots.canBuy)
    buy:SetEnabled(GetMoney() >= slots.price)
end

---------------------------------------------------------------------------
-- track
---------------------------------------------------------------------------

local bar = ns.CreateFramedBar(frame, STEP, BAR_T, true)
bar:SetPoint("BOTTOMLEFT", BAR_X, TRACK_BOTTOM)
bar:SetStatusBarColor(FILL_COLOR[1], FILL_COLOR[2], FILL_COLOR[3])

-- from the crown down to the track
local chain = frame:CreateTexture(nil, "ARTWORK")
chain:SetWidth(2)
chain:SetPoint("TOP", crown, "BOTTOMLEFT", BAR_X + BAR_T / 2 - PAD, 0)
chain:SetPoint("BOTTOM", bar, "TOP", 0, 4)

local spark = bar.top:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetSize(BAR_T * 2.4, 24)
spark:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)

-- you are here: your portrait in a small ring, riding the bar
local me = CreateFrame("Frame", nil, frame)
me:SetSize(22, 22)
me:SetFrameLevel(bar:GetFrameLevel() + 4)
me.portrait = me:CreateTexture(nil, "ARTWORK")
me.portrait:SetAllPoints()
me.ring = me:CreateTexture(nil, "OVERLAY")
me.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
me.ring:SetSize(22 * 53 / 20, 22 * 53 / 20)
me.ring:SetPoint("TOPLEFT", -22 * 7 / 20, 22 * 5 / 20)
me:EnableMouse(true)
me:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L("companionslots.me.level", { level = UnitLevel("player") }))
    GameTooltip:Show()
end)
me:SetScript("OnLeave", GameTooltip_Hide)

-- (also after the bar's length changes: the same value fires no OnValueChanged)
local function PlaceMarker()
    local value = bar:GetValue()
    local y = bar:GetHeight() * value / 100
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "BOTTOM", 0, y)
    spark:SetShown(value > 0 and value < 100)
    me:ClearAllPoints()
    me:SetPoint("CENTER", bar, "BOTTOMLEFT", ME_X - BAR_X, y)
end
bar:HookScript("OnValueChanged", PlaceMarker)

local startLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
startLabel:SetPoint("RIGHT", bar, "BOTTOMLEFT", LEVEL_RIGHT - BAR_X, 0)
startLabel:SetText(L("companionslots.level", { level = 1 }))

-- one row per free slot: a notch, the level on the left, a socket and its meaning on the right
local rows = {}

local function Row(i)
    if rows[i] then return rows[i] end
    local r = {}
    r.notch = bar.top:CreateTexture(nil, "OVERLAY")
    r.notch:SetSize(BAR_T, 2)
    r.level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.stub = frame:CreateTexture(nil, "ARTWORK")

    -- the socket: a minimap-button ring around a round portrait or a dark disc
    local s = CreateFrame("Button", nil, frame)
    s:SetSize(S, S)
    s:SetFrameLevel(bar:GetFrameLevel() + 3)
    local k = S / 20
    s.bg = s:CreateTexture(nil, "BACKGROUND")
    s.bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    s.bg:SetAllPoints()
    s.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
    s.portrait = s:CreateTexture(nil, "ARTWORK")
    s.portrait:SetAllPoints()
    s.plus = s:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    s.plus:SetPoint("CENTER", 0, 1)
    s.plus:SetTextColor(0.1, 1, 0.1)
    s.plus:SetText("+")
    s.number = s:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    s.number:SetPoint("CENTER", 0, 0)
    s.ring = s:CreateTexture(nil, "OVERLAY")
    s.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    s.ring:SetSize(53 * k, 53 * k)
    s.ring:SetPoint("TOPLEFT", -7 * k, 5 * k)
    -- the next one glows; one that just opened flashes
    s.glow = Glow(s, S * 1.9)
    s.glow:SetPoint("CENTER")
    s.glowAnim = Fade(s.glow, 0.25, 0.9, 0.9, true)
    s.burst = Glow(s, S * 3)
    s.burst:SetPoint("CENTER")
    s.burst:SetAlpha(0)
    s.burstAnim = Fade(s.burst, 1, 0, 0.9)
    -- "已开放" rising and fading beside it
    s.float = s:CreateFontString(nil, "OVERLAY", "GameFontGreen")
    s.float:SetPoint("LEFT", s, "RIGHT", 6, 0)
    s.float:SetText(L["companionslots.slot.opened"])
    s.float:SetAlpha(0)
    s.floatAnim = s.float:CreateAnimationGroup()
    local rise = s.floatAnim:CreateAnimation("Translation")
    rise:SetOffset(0, 18)
    rise:SetDuration(1.4)
    local fadeIn = s.floatAnim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.15)
    fadeIn:SetOrder(1)
    local fadeOut = s.floatAnim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(0.9)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(1)
    s.floatAnim:SetScript("OnFinished", function() s.float:SetAlpha(0) end)

    s:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip[1], self.tip[2], self.tip[3], self.tip[4])
        for i = 5, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", GameTooltip_Hide)
    s:SetScript("OnClick", function(self)
        if self.entry then ns.Sheet.Open(self.entry.guid) end
    end)
    r.socket = s

    r.line1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.line1:SetJustifyH("LEFT")
    r.line1:SetWidth(TEXT_W)
    r.line1:SetWordWrap(false)
    r.line2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.line2:SetJustifyH("LEFT")
    r.line2:SetWidth(TEXT_W)
    r.line2:SetWordWrap(false)
    rows[i] = r
    return r
end

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

-- slot i: `open` how many free slots show open (during an unlock fewer than are), `who` the
-- companion in it, `isNext` the next one to open
local function FillRow(r, i, n, level, open, who, isNext)
    local s = r.socket
    local reached = i <= open
    local meaning = Meaning(i, n)
    s.entry = who
    s.portrait:SetShown(who ~= nil)
    s.plus:SetShown(not who and reached)
    s.number:SetShown(not who and not reached)
    s.number:SetText(level)
    s.ring:SetDesaturated(not reached and not who)
    s.ring:SetVertexColor(1, 1, 1, (reached or who) and 1 or 0.6)
    if isNext then
        s.glow:Show()
        if not s.glowAnim:IsPlaying() then s.glowAnim:Play() end
    else
        s.glowAnim:Stop()
        s.glow:Hide()
    end

    -- line 1: how many companions this stage allows; line 2: who has it / open / when
    r.line1:SetText(L("companionslots.slot.allows", { count = i, meaning = meaning }))
    SetColor(r.line1, (reached or who) and GOLD or (isNext and { 1, 1, 1 } or GREY))
    if who then
        ns.CompanionPortrait(s.portrait, who)
        r.line2:SetText(who.name)
        r.line2:SetTextColor(ns.ClassColor(who.class))
        s.tip = { who.name, ns.ClassColor(who.class) }
        s.tip[5] = L("companionslots.slot.tip.taken", { slot = i, level = level })
        s.tip[6] = L["companionslots.slot.tip.click"]
    elseif reached then
        r.line2:SetText(L["companionslots.slot.empty"])
        SetColor(r.line2, { 0.1, 1, 0.1 })
        s.tip = { L["companionslots.slot.empty"], 0.1, 1, 0.1, L["companionslots.slot.tip.empty"] }
    else
        r.line2:SetText(L("companionslots.slot.opens_at", { level = level }))
        SetColor(r.line2, isNext and GOLD or GREY)
        s.tip = { L("companionslots.slot.opens_at", { level = level }), GOLD[1], GOLD[2], GOLD[3], L("companionslots.slot.tip.then", { count = i, meaning = meaning }) }
    end
    s.number:SetTextColor(isNext and GOLD[1] or GREY[1], isNext and GOLD[2] or GREY[2], isNext and GOLD[3] or GREY[3])
    SetColor(r.level, reached and GOLD or (isNext and { 1, 1, 1 } or GREY))
    if reached then r.notch:SetColorTexture(1, 0.82, 0, 0.9) else r.notch:SetColorTexture(0, 0, 0, 0.8) end
    if reached or who then r.stub:SetColorTexture(1, 0.82, 0, 0.7) else r.stub:SetColorTexture(0.5, 0.5, 0.5, 0.5) end
end

local function PlaceRow(r, i, level)
    local y = i * STEP
    r.notch:ClearAllPoints()
    r.notch:SetPoint("CENTER", bar, "BOTTOM", 0, y)
    r.level:ClearAllPoints()
    r.level:SetPoint("RIGHT", bar, "BOTTOMLEFT", LEVEL_RIGHT - BAR_X, y)
    r.level:SetText(L("companionslots.level", { level = level }))
    r.stub:ClearAllPoints()
    r.stub:SetPoint("LEFT", bar, "BOTTOMRIGHT", 3, y)
    r.stub:SetSize(SOCKET_X - S / 2 - BAR_X - BAR_T - 3, 1)
    r.socket:ClearAllPoints()
    r.socket:SetPoint("CENTER", bar, "BOTTOMLEFT", SOCKET_X - BAR_X, y)
    r.line1:ClearAllPoints()
    r.line1:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", TEXT_X - BAR_X, y + 1)
    r.line2:ClearAllPoints()
    r.line2:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", TEXT_X - BAR_X, y - 1)
    for _, part in ipairs({ r.notch, r.level, r.stub, r.socket, r.line1, r.line2 }) do part:Show() end
end

---------------------------------------------------------------------------
-- show, and the unlock
---------------------------------------------------------------------------

local unlock        -- { from, to, t, seconds, open, upTo } while slots open in front of him

local noData = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
noData:SetPoint("TOP", 0, -50)
noData:SetWidth(WIDTH - 2 * PAD)
noData:SetText(L["companionslots.no_data"])
noData:Hide()

local function Draw(open)
    local slots = ns.CompanionSlots()
    local levels = Levels()
    local n = #levels
    local level = UnitLevel("player")
    local lastLevel = levels[n] or 60

    local free = FreeOpen(levels, level)
    count:SetText(("%d / %d"):format(slots.used, slots.total))
    if slots.used >= slots.total and slots.nextLevel > 0 then
        countNote:SetText(L["companionslots.count.full"])
    else
        countNote:SetText(L["companionslots.count.note"])
    end

    -- (no levels: the list came from a server without the slots data, i.e. not updated yet)
    local hasData = n > 0
    for _, part in ipairs({ crown, bar, chain, me, startLabel }) do part:SetShown(hasData) end
    noData:SetShown(not hasData)
    if not hasData then
        count:SetText("")
        countNote:SetText("")
        for _, r in ipairs(rows) do
            for _, part in ipairs({ r.notch, r.level, r.stub, r.socket, r.line1, r.line2 }) do part:Hide() end
        end
        frame:SetHeight(130)
        return 0, 0
    end

    ShowCrown(slots, n, lastLevel)
    startLabel:SetShown(levels[1] > 1)     -- (the first tick says "1 级" itself)

    bar:SetHeight(n * STEP)
    bar.border:SetHeight(bar:GetHeight() + 10 * BAR_T / 15)
    frame:SetHeight(TRACK_TOP + n * STEP + TRACK_BOTTOM)
    chain:SetColorTexture(slots.nextLevel == 0 and 1 or 0.5, slots.nextLevel == 0 and 0.82 or 0.5,
        slots.nextLevel == 0 and 0 or 0.5, 0.6)

    local joined = ByJoining()
    for i, l in ipairs(levels) do
        local r = Row(i)
        PlaceRow(r, i, l)
        FillRow(r, i, n, l, open, joined[i], i == open + 1)
    end
    for i = n + 1, #rows do
        local r = rows[i]
        for _, part in ipairs({ r.notch, r.level, r.stub, r.socket, r.line1, r.line2 }) do part:Hide() end
    end
    SetPortraitTexture(me.portrait, "player")
    PlaceMarker()
    return free, n
end

local Start

local function Refresh()
    if not frame:IsShown() then return end
    if unlock then
        Draw(unlock.open)
        return
    end
    local levels = Levels()
    local free = FreeOpen(levels, UnitLevel("player"))
    if free > SeenFree() then
        Start()     -- (one opened while the panel is open: unlock it in front of him)
        return
    end
    Draw(free)
    bar:SetValue(FillPct(levels))
    PlaceMarker()
end

local function Open(i)
    local r = rows[i]
    if not r then return end
    local s = r.socket
    s.burstAnim:Stop()
    s.burst:SetAlpha(1)
    s.burstAnim:Play()
    s.floatAnim:Stop()
    s.floatAnim:Play()
    PlaySoundFile(CHIME_UNLOCK)
end

-- the bar fills from the last seen slot up to now; each tick it passes opens its socket
bar:HookScript("OnUpdate", function(self, elapsed)
    if not unlock then return end
    unlock.t = unlock.t + elapsed
    local k = math.min(1, unlock.t / unlock.seconds)
    k = 1 - (1 - k) * (1 - k)       -- ease out
    local value = unlock.from + (unlock.to - unlock.from) * k
    self:SetValue(value)
    local n = #Levels()
    while unlock.open < unlock.upTo and n > 0 and value >= (unlock.open + 1) / n * 100 - 0.01 do
        unlock.open = unlock.open + 1
        Draw(unlock.open)
        Open(unlock.open)
    end
    if k >= 1 then
        unlock = nil
        Refresh()
    end
end)

Start = function()
    local levels = Levels()
    local n = #levels
    local free = FreeOpen(levels, UnitLevel("player"))
    local seen = math.min(SeenFree(), free)
    unlock = nil
    if n > 0 and free > seen then
        local steps = free - seen
        unlock = { from = seen / n * 100, to = FillPct(levels), t = 0, open = seen, upTo = free,
            seconds = 0.4 + steps * UNLOCK_STEP_SECONDS }
        MarkSeen(free)      -- (seen once it plays, even if he closes it half way)
        Draw(seen)
        bar:SetValue(unlock.from)
        PlaceMarker()
    else
        Refresh()
    end
    if ns.UpdateCompanionsAttic then ns.UpdateCompanionsAttic() end
end

frame:SetScript("OnShow", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
    if PartyBotAffinityHelpFrame then PartyBotAffinityHelpFrame:Hide() end
    Start()
end)
frame:SetScript("OnHide", function()
    PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    if unlock then unlock = nil end
end)

function ns.ToggleCompanionSlots()
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
    -- (the micro button stops pulsing once the panel is looked at)
    ns.CompanionsFrame:HookScript("OnShow", function()
        if PartyBotCompanionsMicroButton and MicroButtonPulseStop then MicroButtonPulseStop(PartyBotCompanionsMicroButton) end
    end)
end
if PartyBotAffinityHelpFrame then
    PartyBotAffinityHelpFrame:HookScript("OnShow", function() frame:Hide() end)
end

---------------------------------------------------------------------------
-- server replies and events
---------------------------------------------------------------------------

-- a new list (Companions.lua parsed it first: it registered first): redraw, keep the levels
ns.On("PBCMP", function(msg)
    if msg:match("^PBCMP;END") then
        local levels = Levels()
        if ns.db and #levels > 0 then ns.db.companionSlotLevels = levels end
        Refresh()
        if ns.UpdateCompanionsAttic then ns.UpdateCompanionsAttic() end
    end
    return false
end)

-- bought one (CompanionMenu.lua says it in chat and asks for the list): the crown shines
ns.On("PBOK", function(msg)
    if msg:match("^PBOK;[^;]*;buyslot") and frame:IsShown() then
        crown.flashAnim:Stop()
        crown.flash:SetAlpha(1)
        crown.flashAnim:Play()
        PlaySound(SOUNDKIT.LOOT_WINDOW_COIN_SOUND)
        PlaySoundFile(CHIME_UNLOCK)
    end
    return false
end)

-- reaching a free slot's level: said on screen, the Companions micro button pulses
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:SetScript("OnEvent", function(_, event, level)
    if event == "PLAYER_XP_UPDATE" then
        if frame:IsShown() and not unlock then bar:SetValue(FillPct(Levels())) end
        return
    end
    for i, l in ipairs(Levels()) do
        if l == level then
            local text = L("companionslots.levelup.notice", { count = i })
            RaidNotice_AddMessage(RaidBossEmoteFrame, text, ChatTypeInfo["SYSTEM"])
            DEFAULT_CHAT_FRAME:AddMessage(L("companionslots.levelup.chat", { text = text }), 1, 0.82, 0)
            if PartyBotCompanionsMicroButton and MicroButtonPulse then MicroButtonPulse(PartyBotCompanionsMicroButton) end
            C_Timer.After(1.5, function() PlaySoundFile(CHIME_UNLOCK) end)
            if ns.UpdateCompanionsAttic then ns.UpdateCompanionsAttic() end
            break
        end
    end
end)
