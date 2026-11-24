-- Companion sheet, page 2: 好感 — where the player's own window has the pet tab.
-- What the companion thinks of you: affinity (0-100, what you did for it), its personality and
-- how long you know each other, and what it lets you do (信任: the server's affinity gates, grey
-- with the affinity they need until reached), and its friend traits (特质, at affinity 80 / 90).
-- All of it comes with the companion list, no request.

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local bar, standing, about, tags, known
local GATE_ROWS, GATE_ROW_H = 9, 13
local gateRows = {}
-- friend traits: one row per affinity they come at, the name in its rarity's colour, what it
-- does after it (the whole line in the tooltip)
local TRAIT_AT = ns.TRAIT_AT
local RARITY_COLOR = ns.TRAIT_RARITY_COLOR
local RARITY_TEXT = ns.TRAIT_RARITY_TEXT
local traitRows = {}

local function Line(page, label, anchor, y)
    local name = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    name:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    name:SetText(label)
    local value = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    value:SetPoint("LEFT", name, "LEFT", 60, 0)
    value:SetWidth(220)
    value:SetJustifyH("LEFT")
    return value, name
end

Sheet.AddPage({
    key = "affinity", title = L["sheet.affinity.title"], order = 20, levelLine = true,
    Build = function(page)
        Sheet.GeneralBackground(page)

        local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        title:SetPoint("TOPLEFT", 40, -82)
        title:SetText(L["sheet.affinity.heading"])

        -- the skill bar look (bordered), coloured like a reputation standing
        bar = CreateFrame("StatusBar", "PartyBotCompanionSheetAffinityBar", page, "SkillStatusBarTemplate")
        bar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
        bar:SetMinMaxValues(0, 100)
        bar:Show()
        bar.name = _G[bar:GetName() .. "SkillName"]
        bar.rank = _G[bar:GetName() .. "SkillRank"]
        bar.rank:ClearAllPoints()
        bar.rank:SetPoint("RIGHT", bar, "RIGHT", -8, 1)
        bar.rank:SetJustifyH("RIGHT")
        _G[bar:GetName() .. "FillBar"]:Hide()
        _G[bar:GetName() .. "Border"]:SetScript("OnClick", nil)
        _G[bar:GetName() .. "Border"]:EnableMouse(false)

        standing = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        standing:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -16)

        about = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        about:SetPoint("TOPLEFT", standing, "BOTTOMLEFT", 0, -8)
        about:SetWidth(280)
        about:SetJustifyH("LEFT")
        about:SetSpacing(3)

        -- what it lets you do: one row per gate, grey with the affinity it needs until reached
        local trust = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        trust:SetPoint("TOPLEFT", 40, -182)
        trust:SetText(L["sheet.affinity.trust"])
        for i = 1, GATE_ROWS do
            local label = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", trust, "BOTTOMLEFT", 0, -6 - (i - 1) * GATE_ROW_H)
            label:SetWidth(195)
            label:SetJustifyH("LEFT")
            local need = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            need:SetPoint("LEFT", label, "LEFT", 195, 0)
            need:SetWidth(80)
            need:SetJustifyH("RIGHT")
            gateRows[i] = { label = label, need = need }
        end

        local divider = page:CreateTexture(nil, "ARTWORK")
        divider:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
        divider:SetSize(300, 16)
        divider:SetPoint("TOPLEFT", 25, -325)
        divider:SetTexCoord(0, 1, 0, 0.25)

        local anchor = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        anchor:SetPoint("TOPLEFT", 40, -345)
        page.aboutTitle = anchor
        tags = Line(page, L["sheet.affinity.tags"], anchor, -12)
        known = Line(page, L["sheet.affinity.known"], anchor, -30)
        for i = 1, #TRAIT_AT do
            local value = Line(page, i == 1 and L["sheet.affinity.traits"] or "", anchor, -48 - (i - 1) * 16)
            value:SetWordWrap(false)
            -- the tooltip: name, rarity, what it does
            local hover = CreateFrame("Frame", nil, page)
            hover:SetAllPoints(value)
            hover:EnableMouse(true)
            hover:SetScript("OnEnter", function(self)
                local t = self.trait
                if not t then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText((RARITY_COLOR[t.rarity] or "") .. t.label .. FONT_COLOR_CODE_CLOSE)
                GameTooltip:AddLine(L("sheet.affinity.trait_tip", { rarity = RARITY_TEXT[t.rarity] or "", affinity = self.at }), 0.6, 0.6, 0.6)
                GameTooltip:AddLine(t.text, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
            traitRows[i] = { value = value, hover = hover }
        end
    end,
    Update = function(page, c)
        local value = c.affinity or 0
        local s = ns.AffinityStanding(value)
        bar:SetValue(value)
        bar:SetStatusBarColor(ns.AffinityColor(value))
        _G[bar:GetName() .. "Background"]:SetVertexColor(0, 0, 0, 0.5)
        bar.name:SetText(s.text)
        bar.rank:SetText(("%d / 100"):format(value))
        standing:SetText(L("sheet.affinity.standing", { name = c.name, standing = s.text }))
        about:SetText(L("sheet.affinity.about", { name = c.name }))
        page.aboutTitle:SetText(L("sheet.affinity.about_title", { name = c.name }))

        local gates = ns.AffinityGates(c.class)
        for i, row in ipairs(gateRows) do
            local g = gates[i]
            if not g then
                row.label:SetText("")
                row.need:SetText("")
            elseif value >= g.affinity and c.blocks and c.blocks[g.key] then
                -- unlocked, but he cannot do it now (no Rune of Portals)
                row.label:SetText(g.label)
                row.need:SetText((ORANGE_FONT_COLOR_CODE or "|cffff7f3f") .. c.blocks[g.key] .. FONT_COLOR_CODE_CLOSE)
            elseif value >= g.affinity then
                row.label:SetText(g.label)
                row.need:SetText(GREEN_FONT_COLOR_CODE .. L["sheet.affinity.unlocked"] .. FONT_COLOR_CODE_CLOSE)
            else
                row.label:SetText(GRAY_FONT_COLOR_CODE .. g.label .. FONT_COLOR_CODE_CLOSE)
                row.need:SetText(GRAY_FONT_COLOR_CODE .. L("sheet.affinity.need", { affinity = g.affinity }) .. FONT_COLOR_CODE_CLOSE)
            end
        end
        if #gates == 0 then
            gateRows[1].label:SetText(GRAY_FONT_COLOR_CODE .. L["sheet.affinity.no_gates"] .. FONT_COLOR_CODE_CLOSE)
        end

        local labels = ns.TagLabels(c.tags)
        tags:SetText(#labels > 0 and table.concat(labels, L["sheet.affinity.tag_sep"]) or (GRAY_FONT_COLOR_CODE .. L["sheet.affinity.tags_unknown"] .. FONT_COLOR_CODE_CLOSE))
        if c.recruitedAt and c.recruitedAt > 0 then
            local days = math.floor(math.max(0, time() - c.recruitedAt) / 86400)
            known:SetText(days == 0 and L["sheet.affinity.known_today"] or L("sheet.affinity.known_days", { days = days }))
        else
            known:SetText("")
        end

        for i, row in ipairs(traitRows) do
            local at = TRAIT_AT[i]
            local t = c.traits and c.traits[at]
            row.hover.trait = t
            row.hover.at = at
            if t then
                row.value:SetText((RARITY_COLOR[t.rarity] or "") .. t.label .. FONT_COLOR_CODE_CLOSE .. "  " .. t.text)
            else
                row.value:SetText(GRAY_FONT_COLOR_CODE .. L("sheet.affinity.trait_locked", { affinity = at }) .. FONT_COLOR_CODE_CLOSE)
            end
        end
    end,
})
