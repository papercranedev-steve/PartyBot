-- Companions panel, right pane: the selected companion (Companions.lua selects). Name, level,
-- spec, where he is and experience are on his card, so this pane only shows what the card has not:
--   background  his main talent tree's art (the talent frame's backgrounds)
--   left        personality; the model (drag to turn) when the client has
--               him (party, target, nearby nameplate), else his race portrait in a ring
--   right       the affinity ruler: a vertical bar 0 (bottom) .. 100 (top), standings on its left,
--               on its right every gate's benefit and the friend traits (80 / 90) at their tick
--               (pushed apart with a leader line where ticks are close); gained since the last look fills up with a sound.
--               Below it a link to "如何获得好感？" (AffinityHelp.lua)
--   actions     详细资料 (character sheet), 交谈 (in view), 查看天赋 (online)

local _, ns = ...
local L = ns.L

local frame = ns.CompanionsFrame
local layout = ns.CompanionsLayout
if not frame or not layout then return end

local PANE_W = frame:GetWidth() - layout.left - layout.right
local PANE_H = frame:GetHeight() - layout.top - layout.bottom
local INNER_W, INNER_H = PANE_W - 6, PANE_H - 6
local MODEL_W = 140
local RULER_X = MODEL_W + 8         -- the ruler's left edge (standing names)
local STAND_W = 28
local BAR_T = 15                    -- bar thickness
local BAR_X = RULER_X + STAND_W + 6
local ELBOW_X = BAR_X + BAR_T + 7   -- where a leader line bends
local LABEL_X = BAR_X + BAR_T + 14
local LABEL_W = INNER_W - LABEL_X - 6
local BAR_TOP, BAR_BOTTOM = 46, 64  -- distance from the pane's top / bottom
local BAR_L = INNER_H - BAR_TOP - BAR_BOTTOM
local LABEL_GAP = 3
local FILL_SECONDS = 1.2

-- talent tree backgrounds (Interface\TalentFrame\<name>-TopLeft ...), tab order like ns.TREE_NAMES
local TREE_ART = {
    [1]  = { "WarriorArms", "WarriorFury", "WarriorProtection" },
    [2]  = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    [3]  = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    [4]  = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    [5]  = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    [7]  = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    [8]  = { "MageArcane", "MageFire", "MageFrost" },
    [9]  = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    [11] = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
}

local pane = CreateFrame("Frame", "PartyBotCompanionShowcase", frame, "InsetFrameTemplate")
pane:SetPoint("TOPLEFT", layout.left, -layout.top)
pane:SetPoint("BOTTOMRIGHT", -layout.right, layout.bottom)

-- Three sibling layers with fixed frame levels (a scroll child is drawn above frames made
-- next to its scroll frame, so the text must sit on a frame clearly above it):
--   clip  (+1)  the talent art (scroll child +2)
--   dim   (+6)  the shades over the art
--   upper (+10) model, portrait, ruler, buttons (ring and level badge above it)
local inner = CreateFrame("Frame", nil, pane)
inner:SetPoint("TOPLEFT", 3, -3)
inner:SetSize(INNER_W, INNER_H)
local BASE = inner:GetFrameLevel()

local function Layer(level)
    local f = CreateFrame("Frame", nil, inner)
    f:SetAllPoints()
    f:SetFrameLevel(BASE + level)
    return f
end

---------------------------------------------------------------------------
-- background: the talent art at the pane's width, cropped to its height (a scroll frame clips)
---------------------------------------------------------------------------

-- the art is 320x384, but only the left ART_W px are painted (the rest is the talent frame's edge)
local ART_W, ART_H = 304, 384
local clip = CreateFrame("ScrollFrame", nil, inner)
clip:SetAllPoints()
clip:SetFrameLevel(BASE + 1)
clip:EnableMouse(false)
local art = CreateFrame("Frame", nil, clip)
local scale = INNER_W / ART_W
art:SetSize(INNER_W, ART_H * scale)
clip:SetScrollChild(art)

local artParts = {}
for _, p in ipairs({
    { "TopLeft", 256, 256, 0, 0 }, { "TopRight", 64, 256, 256, 0 },
    { "BottomLeft", 256, 128, 0, 256 }, { "BottomRight", 64, 128, 256, 256 },
}) do
    local t = art:CreateTexture(nil, "BACKGROUND")
    t:SetSize(p[2] * scale, p[3] * scale)
    t:SetPoint("TOPLEFT", p[4] * scale, -p[5] * scale)
    artParts[p[1]] = t
end

local dim = Layer(6)
local upper = Layer(10)

local shade = dim:CreateTexture(nil, "BACKGROUND", nil, 1)
shade:SetAllPoints()
shade:SetColorTexture(0, 0, 0, 0.35)
-- darker under the ruler
local rulerShade = dim:CreateTexture(nil, "BACKGROUND", nil, 2)
rulerShade:SetPoint("TOPLEFT", RULER_X - 30, 0)
rulerShade:SetPoint("BOTTOMRIGHT")
rulerShade:SetTexture("Interface\\Buttons\\WHITE8X8")
if rulerShade.SetGradientAlpha then
    rulerShade:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.7)
else
    rulerShade:SetVertexColor(0, 0, 0, 0.45)
end

local function SetArt(c)
    local spec = ns.CompanionSpecIndex(c) or 1
    local name = TREE_ART[c.class] and TREE_ART[c.class][spec]
    for part, t in pairs(artParts) do
        if name then t:SetTexture("Interface\\TalentFrame\\" .. name .. "-" .. part) end
        t:SetShown(name ~= nil)
    end
    -- centred vertically (the scroll range is only known once laid out)
    clip:UpdateScrollChildRect()
    clip:SetVerticalScroll(math.max(0, (ART_H * scale - INNER_H) / 2))
end

---------------------------------------------------------------------------
-- left: personality, known for, model (or portrait)
---------------------------------------------------------------------------

local tagsLine = upper:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tagsLine:SetPoint("TOPLEFT", 8, -14)
tagsLine:SetWidth(MODEL_W - 4)
tagsLine:SetJustifyH("LEFT")

local model = CreateFrame("PlayerModel", nil, upper)
model:SetPoint("TOPLEFT", 4, -40)
model:SetSize(MODEL_W, INNER_H - 40 - 36)
model:EnableMouse(true)
local facing, dragX = 0, nil
model:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then dragX = GetCursorPosition() end
end)
model:SetScript("OnMouseUp", function() dragX = nil end)
model:SetScript("OnHide", function() dragX = nil end)
model:SetScript("OnUpdate", function(self)
    if not dragX then return end
    local x = GetCursorPosition()
    facing = facing + (x - dragX) * 0.015
    dragX = x
    self:SetFacing(facing)
end)

-- shadow under his feet
local floor = upper:CreateTexture(nil, "BORDER")
floor:SetTexture("Interface\\Buttons\\WHITE8X8")
floor:SetVertexColor(0, 0, 0, 0.45)
floor:SetSize(100, 10)
floor:SetPoint("BOTTOM", model, "BOTTOM", 0, 24)
if floor.SetMask then floor:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask") end

local portrait = upper:CreateTexture(nil, "ARTWORK")
portrait:SetSize(88, 88)
portrait:SetPoint("CENTER", model, "CENTER", 12, 20)
local ringFrame = Layer(16)
local ring = ringFrame:CreateTexture(nil, "ARTWORK")
ns.PlaceAffinityRing(ring, portrait, 88)
local ringLevel = ringFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ns.PlaceAffinityRingLevel(ringLevel, portrait, 88)
local away = upper:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
away:SetPoint("TOP", portrait, "BOTTOM", -12, -30)
away:SetWidth(MODEL_W - 10)

local function ShowFigure(c, standing)
    local unit = ns.UnitOf(c.name)
    if unit then
        portrait:Hide()
        ring:Hide()
        ringLevel:Hide()
        away:Hide()
        model:Show()
        floor:Show()
        if model.guid ~= c.guid or not model.hasUnit then
            facing = 0
            model:ClearModel()
            model:SetUnit(unit)
            model:SetFacing(facing)
        end
        model.guid, model.hasUnit = c.guid, true
        return
    end
    model:Hide()
    floor:Hide()
    model.guid, model.hasUnit = nil, false
    portrait:Show()
    ring:Show()
    ringLevel:Show()
    away:Show()
    SetPortraitToTexture(portrait, ns.RacePortrait(c.race, c.gender) or ns.COMPANIONS_ICON)
    ring:SetTexture(standing.ring)
    ringLevel:SetText(c.level)
    away:SetText(L["companionshowcase.away"])
end

---------------------------------------------------------------------------
-- right: the affinity ruler
---------------------------------------------------------------------------

local ruler = CreateFrame("Frame", nil, upper)
ruler:SetAllPoints()

-- (no standing heading: the ruler's standing names show where he is)
local valueText = ruler:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
valueText:SetPoint("TOPRIGHT", -10, -14)
local gainText = ruler:CreateFontString(nil, "OVERLAY", "GameFontGreen")
gainText:SetPoint("RIGHT", valueText, "LEFT", -4, 0)

local bar = ns.CreateFramedBar(ruler, BAR_L, BAR_T, true)
bar:SetPoint("BOTTOMLEFT", BAR_X, BAR_BOTTOM)

-- the current value: a cast bar spark turned across the bar
local spark = bar.top:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")
spark:SetSize(BAR_T * 2.4, 24)
spark:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
bar:SetScript("OnValueChanged", function(_, value)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", bar, "BOTTOM", 0, BAR_L * value / 100)
    spark:SetShown(value > 0 and value < 100)
end)

local function Y(value) return BAR_L * value / 100 end

-- standings on the left of the bar, at where each begins
local standings = {}
for _, s in ipairs(ns.AFFINITY_STANDINGS) do
    local fs = ruler:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("RIGHT", bar, "BOTTOMLEFT", -6, math.min(BAR_L - 4, math.max(6, Y(s.min))))
    fs:SetText(s.text)
    local notch = bar.top:CreateTexture(nil, "OVERLAY")
    notch:SetSize(5, 1)
    notch:SetPoint("RIGHT", bar, "BOTTOMLEFT", -1, Y(s.min))
    notch:SetShown(s.min > 0 and s.min < 100)
    standings[#standings + 1] = { min = s.min, text = fs, notch = notch }
end

-- one row per gate: a notch across the bar, the benefit on the right, a leader line between
local rows = {}
local function Row(i)
    if rows[i] then return rows[i] end
    local r = {}
    r.notch = bar.top:CreateTexture(nil, "OVERLAY")
    r.notch:SetSize(BAR_T, 2)
    r.stub = ruler:CreateTexture(nil, "ARTWORK")
    r.riser = ruler:CreateTexture(nil, "ARTWORK")
    r.lead = ruler:CreateTexture(nil, "ARTWORK")
    r.button = CreateFrame("Button", nil, ruler)
    r.button:SetWidth(LABEL_W)
    r.text = r.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT")
    r.text:SetWidth(LABEL_W)
    r.text:SetJustifyH("LEFT")
    r.button:SetScript("OnEnter", function(self)
        local g, c = self.gate, self.entry
        if not g or not c then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if g.traitAt then
            local t = c.traits and c.traits[g.traitAt]
            if t then
                GameTooltip:AddLine((ns.TRAIT_RARITY_COLOR[t.rarity] or "") .. t.label .. "|r")
                GameTooltip:AddLine(L("companionshowcase.trait.gained_at", { rarity = ns.TRAIT_RARITY_TEXT[t.rarity] or "", affinity = g.affinity }), 0.6, 0.6, 0.6)
                GameTooltip:AddLine(t.text, 1, 1, 1, true)
            else
                GameTooltip:AddLine(L["companionshowcase.trait.title"], 1, 1, 1)
                GameTooltip:AddLine(L("companionshowcase.trait.reveals_at", { affinity = g.affinity }), 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
            return
        end
        GameTooltip:AddLine(g.label, 1, 1, 1, true)
        local blocked = c.blocks and c.blocks[g.key]
        if c.affinity >= g.affinity and blocked then
            GameTooltip:AddLine(L("companionshowcase.gate.unlocked_blocked", { reason = blocked }), 1, 0.5, 0.25, true)
        elseif c.affinity >= g.affinity then
            GameTooltip:AddLine(L["companionshowcase.gate.unlocked"], 0.1, 1, 0.1)
        else
            GameTooltip:AddLine(L("companionshowcase.gate.unlocks_at", { affinity = g.affinity }), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    r.button:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
    return r
end

local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:12:12:0:0|t"
local GOLD, GREY = "|cffffd100", "|cff8c8c8c"
local ORANGE = ORANGE_FONT_COLOR_CODE or "|cffff7f3f"

local function RowText(g, c, isNext)
    if g.traitAt then
        local t = c.traits and c.traits[g.traitAt]
        if t then
            return CHECK .. GOLD .. L["companionshowcase.trait.row_label"] .. "|r" .. (ns.TRAIT_RARITY_COLOR[t.rarity] or "") .. t.label .. "|r"
        elseif isNext then
            return GOLD .. g.affinity .. "|r  " .. L["companionshowcase.trait.row_pending"]
        end
        return GREY .. g.affinity .. "  " .. L["companionshowcase.trait.row_pending"] .. "|r"
    end
    local blocked = c.blocks and c.blocks[g.key]
    if c.affinity >= g.affinity and blocked then
        return CHECK .. ORANGE .. L("companionshowcase.gate.row_blocked", { label = g.label, reason = blocked }) .. "|r"
    elseif c.affinity >= g.affinity then
        return CHECK .. GOLD .. g.label .. "|r"
    elseif isNext then
        return GOLD .. g.affinity .. "|r  " .. g.label
    end
    return GREY .. g.affinity .. "  " .. g.label .. "|r"
end

-- Labels as near their ticks as fits: bottom-up, then pushed down from the top if they overflow.
local function Spread(items)
    local prev
    for _, it in ipairs(items) do
        it.y = it.want
        if prev then it.y = math.max(it.y, prev.y + prev.h / 2 + LABEL_GAP + it.h / 2) end
        prev = it
    end
    local limit = BAR_L + BAR_TOP - 30       -- up to just under the heading
    local nextItem
    for i = #items, 1, -1 do
        local it = items[i]
        local top = nextItem and (nextItem.y - nextItem.h / 2 - LABEL_GAP) or limit
        it.y = math.min(it.y, top - it.h / 2)
        nextItem = it
    end
end

local function Line(tex, reached)
    if reached then tex:SetColorTexture(1, 0.82, 0, 0.8) else tex:SetColorTexture(0.55, 0.55, 0.55, 0.6) end
end

local function ShowRuler(c)
    local value = c.affinity
    -- the gates, and the friend traits at their affinities (marks like a gate)
    local gates = {}
    for _, g in ipairs(ns.AffinityGates(c.class)) do gates[#gates + 1] = g end
    for _, at in ipairs(ns.TRAIT_AT) do
        gates[#gates + 1] = { affinity = at, traitAt = at }
    end
    local nextAt
    for _, g in ipairs(gates) do
        if value < g.affinity and (not nextAt or g.affinity < nextAt) then nextAt = g.affinity end
    end

    local items = {}
    for i, g in ipairs(gates) do
        local r = Row(i)
        r.button.gate, r.button.entry = g, c
        r.text:SetText(RowText(g, c, g.affinity == nextAt))
        local h = r.text:GetStringHeight()
        if not h or h < 1 then h = 12 end
        r.button:SetHeight(h)
        items[#items + 1] = { row = r, gate = g, want = Y(g.affinity), h = h }
    end
    table.sort(items, function(a, b)
        if a.gate.affinity ~= b.gate.affinity then return a.gate.affinity < b.gate.affinity end
        return not a.gate.traitAt and b.gate.traitAt ~= nil      -- a trait above a gate at the same mark
    end)
    Spread(items)

    local barRight = BAR_X + BAR_T
    for _, it in ipairs(items) do
        local r, reached = it.row, value >= it.gate.affinity
        local want, y = it.want, it.y
        r.notch:ClearAllPoints()
        r.notch:SetPoint("CENTER", bar, "BOTTOM", 0, want)
        if reached then r.notch:SetColorTexture(1, 0.82, 0, 0.9) else r.notch:SetColorTexture(0, 0, 0, 0.8) end

        r.stub:ClearAllPoints()
        r.stub:SetPoint("LEFT", bar, "BOTTOMRIGHT", 3, want)
        r.stub:SetSize(ELBOW_X - barRight - 3, 1)
        Line(r.stub, reached)
        r.riser:ClearAllPoints()
        r.riser:SetPoint("BOTTOM", bar, "BOTTOMRIGHT", ELBOW_X - barRight, math.min(want, y))
        r.riser:SetSize(1, math.max(1, math.abs(y - want)))
        r.riser:SetShown(math.abs(y - want) >= 1)
        Line(r.riser, reached)
        r.lead:ClearAllPoints()
        r.lead:SetPoint("LEFT", bar, "BOTTOMRIGHT", ELBOW_X - barRight, y)
        r.lead:SetSize(LABEL_X - ELBOW_X - 3, 1)
        Line(r.lead, reached)

        r.button:ClearAllPoints()
        r.button:SetPoint("LEFT", bar, "BOTTOMRIGHT", LABEL_X - barRight, y)
        r.notch:Show()
        r.stub:Show()
        r.lead:Show()
        r.button:Show()
    end
    for i = #gates + 1, #rows do
        local r = rows[i]
        r.notch:Hide()
        r.stub:Hide()
        r.riser:Hide()
        r.lead:Hide()
        r.button:Hide()
    end
end

local help = ns.AffinityHelpLink(ruler)
help:SetPoint("BOTTOMLEFT", RULER_X, 38)

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------

local current     -- the shown entry

local function Action(text, onClick)
    local b = CreateFrame("Button", nil, upper, "UIPanelButtonTemplate")
    b:SetSize(92, 22)
    b:SetText(text)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnClick", function()
        if current then onClick(current) end
    end)
    b:SetScript("OnEnter", function(self)
        if self.reason and not self:IsEnabled() then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(text)
            GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local sheetButton = Action(L["companionshowcase.sheet"], function(c) ns.Sheet.Open(c.guid) end)
sheetButton:SetPoint("BOTTOMRIGHT", -8, 8)
local talkButton = Action(L["companionshowcase.talk"], function(c) ns.Talk(c.name) end)
talkButton:SetPoint("RIGHT", sheetButton, "LEFT", -4, 0)
local talentsButton = Action(L["companionshowcase.talents"], function(c) ns.ShowTalents(c.name) end)
talentsButton:SetPoint("RIGHT", talkButton, "LEFT", -4, 0)

local function Allow(button, ok, reason)
    button:SetEnabled(ok)
    button.reason = not ok and reason or nil
end

---------------------------------------------------------------------------
-- affinity: heading, standings, the fill animation
---------------------------------------------------------------------------

local fill      -- { from, to, t } while filling
local filled = {}   -- guid -> filled once this opening

bar:HookScript("OnUpdate", function(self, elapsed)
    if not fill then return end
    fill.t = fill.t + elapsed
    local k = math.min(1, fill.t / FILL_SECONDS)
    k = 1 - (1 - k) * (1 - k)       -- ease out
    self:SetValue(fill.from + (fill.to - fill.from) * k)
    if k >= 1 then fill = nil end
end)

local function ShowAffinity(c, standing)
    local value = c.affinity
    local r, g, b = ns.AffinityColor(value)
    valueText:SetText(("%d / 100"):format(value))
    bar:SetStatusBarColor(r, g, b)

    for _, s in ipairs(standings) do
        if s.min == standing.min then
            s.text:SetTextColor(r, g, b)
        elseif value >= s.min then
            s.text:SetTextColor(0.75, 0.75, 0.75)
        else
            s.text:SetTextColor(0.45, 0.45, 0.45)
        end
        s.notch:SetColorTexture(0.7, 0.7, 0.7, 0.8)
    end

    local gain = ns.CompanionAffinityGain(c.guid)
    gainText:SetText(gain > 0 and ("+" .. gain) or "")
    if gain > 0 and not filled[c.guid] then
        filled[c.guid] = true
        fill = { from = math.max(0, value - gain), to = value, t = 0 }
        bar:SetValue(fill.from)
        PlaySoundFile(567516)       -- sound/interface/iquestupdate.ogg
    elseif not fill or current ~= c then
        fill = nil
        bar:SetValue(value)
    end

    ShowRuler(c)
end

---------------------------------------------------------------------------
-- show
---------------------------------------------------------------------------

local empty = upper:CreateFontString(nil, "OVERLAY", "GameFontDisable")
empty:SetPoint("CENTER")
empty:SetText(L["companionshowcase.empty"])

function ns.ShowcaseCompanion(c)
    if not c then
        current = nil
        ruler:Hide()
        tagsLine:Hide()
        model:Hide()
        floor:Hide()
        portrait:Hide()
        ring:Hide()
        ringLevel:Hide()
        away:Hide()
        for _, t in pairs(artParts) do t:Hide() end
        sheetButton:Hide()
        talkButton:Hide()
        talentsButton:Hide()
        empty:SetShown(ns.CompanionsLoaded())
        return
    end
    empty:Hide()
    -- (one of your own characters has no affinity: no ruler)
    local own = c.account == ns.ACCOUNT_KIND.OWN
    ruler:SetShown(not own)
    tagsLine:Show()
    sheetButton:Show()
    talkButton:Show()
    talentsButton:Show()

    local standing = ns.AffinityStanding(c.affinity)
    SetArt(c)
    ShowFigure(c, standing)

    local tags = ns.TagLabels(c.tags)
    tagsLine:SetText(#tags > 0 and table.concat(tags, L["companionshowcase.tags.separator"]) or "")

    if not own then ShowAffinity(c, standing) end

    local unit = ns.UnitOf(c.name)
    Allow(talkButton, unit ~= nil, L["companionshowcase.talk.too_far"])
    Allow(talentsButton, c.state == ns.COMPANION_STATE.ONLINE or c.state == ns.COMPANION_STATE.GROUP, L["companionshowcase.talents.not_here"])
    current = c
end

pane:SetScript("OnHide", function()
    wipe(filled)
    fill = nil
end)
