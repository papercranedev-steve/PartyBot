-- Companion sheet, 角色 page: the stats panel under the model, ported from CharacterStatsClassic
-- 3.8.4 (getov/CharacterStatsClassic, CharacterStatsClassicUI/Utils/Callbacks.lua): two dropdowns
-- picking a category each (base, melee, ranged, spell, defenses), five stats per category, the
-- same tooltips. CharacterStatsClassic reads the player's own API (GetCritChance, GetHitModifier,
-- GetSpellCritChance...), which the client has for nobody else, so every number here comes from
-- the server instead (PBCMV S lines, Companions/CompanionSheet.cpp); talent crit and hit are
-- worked out there too, for every class, instead of CharacterStatsClassic's per-class talent code.
-- Left out: Argent Dawn "vs undead" bonuses and the options panel.

local _, ns = ...
local L = ns.L

local Stats = {}
ns.SheetStats = Stats

local CATEGORIES = {
    PLAYERSTAT_BASE_STATS,
    PLAYERSTAT_MELEE_COMBAT,
    PLAYERSTAT_RANGED_COMBAT,
    PLAYERSTAT_SPELL_COMBAT,
    PLAYERSTAT_DEFENSES,
}
local BASE, MELEE, RANGED, SPELL, DEFENSES = unpack(CATEGORIES)

local NUM_STATS_TO_SHOW = 5
local TAB = "    "      -- CSC_SYMBOL_TAB ("\t" does not show in tooltips)
local STAT_KEYS = { "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT" }
-- tooltip order of the schools (server school 1-6 = SPELL_SCHOOL<n>_CAP)
local SCHOOL_ORDER = { 1, 2, 4, 6, 5, 3 }

local panel, offline
local leftRows, rightRows = {}, {}
local shown             -- { s = stat table, c = companion } of the last Update

---------------------------------------------------------------------------
-- helpers (CharacterStatsClassicUtils.lua)
---------------------------------------------------------------------------

local function SetLabelAndText(statFrame, label, text, isPercentage, numericValue, precision)
    if isPercentage then
        statFrame.Value:SetText(format(precision or "%.1F%%", numericValue))
    else
        statFrame.Value:SetText(text)
    end
    statFrame.numericValue = numericValue
    if statFrame.Label then
        statFrame.Label:SetText(format(STAT_FORMAT, label))
        statFrame.Label:SetWidth(statFrame:GetWidth() - statFrame.Value:GetWidth() - 20)
        statFrame.Label:SetHeight(statFrame:GetHeight())
        statFrame.Label:SetJustifyH("LEFT")
    end
    statFrame:Show()
end

local function NotApplicable(statFrame, label)
    SetLabelAndText(statFrame, label, NOT_APPLICABLE, false, 0)
end

local function FormatStat(name, base, posBuff, negBuff)
    local effective = max(0, base + posBuff + negBuff)
    local text = HIGHLIGHT_FONT_COLOR_CODE .. name .. " " .. effective
    if posBuff == 0 and negBuff == 0 then
        text = text .. FONT_COLOR_CODE_CLOSE
    else
        if posBuff > 0 or negBuff < 0 then text = text .. " (" .. base .. FONT_COLOR_CODE_CLOSE end
        if posBuff > 0 then text = text .. FONT_COLOR_CODE_CLOSE .. GREEN_FONT_COLOR_CODE .. "+" .. posBuff .. FONT_COLOR_CODE_CLOSE end
        if negBuff < 0 then text = text .. RED_FONT_COLOR_CODE .. " " .. negBuff .. FONT_COLOR_CODE_CLOSE end
        if posBuff > 0 or negBuff < 0 then text = text .. HIGHLIGHT_FONT_COLOR_CODE .. ")" .. FONT_COLOR_CODE_CLOSE end
        -- a debuff shows the number red even with buffs, otherwise green
        if negBuff < 0 then
            effective = RED_FONT_COLOR_CODE .. effective .. FONT_COLOR_CODE_CLOSE
        elseif posBuff > 0 then
            effective = GREEN_FONT_COLOR_CODE .. effective .. FONT_COLOR_CODE_CLOSE
        end
    end
    return effective, text
end

local function Pct(value) return format("%.2F%%", value) end

-- CSC_GetPlayerMissChances
local function MissChances(playerHit, totalWeaponSkill)
    local hitChance = playerHit
    local missChanceVsNPC = 5       -- level 60 npcs with 300 def
    local missChanceVsBoss = 9
    local missChanceVsPlayer = 5    -- level 60 player def is 300 base
    if totalWeaponSkill then
        local bossDefense = 315     -- level 63
        local delta = bossDefense - totalWeaponSkill
        if delta > 10 then
            if hitChance >= 1 then hitChance = hitChance - 1 end
            missChanceVsBoss = 5 + delta * 0.2
        else
            missChanceVsBoss = 5 + delta * 0.1
        end
    end
    local dwNpc = math.max(0, (missChanceVsNPC * 0.8 + 20) - playerHit)
    local dwBoss = math.max(0, (missChanceVsBoss * 0.8 + 20) - hitChance)
    local dwPlayer = math.max(0, (missChanceVsPlayer * 0.8 + 20) - playerHit)
    return math.max(0, missChanceVsNPC - playerHit), math.max(0, missChanceVsBoss - hitChance),
        math.max(0, missChanceVsPlayer - playerHit), dwNpc, dwBoss, dwPlayer
end

local function Hide() GameTooltip:Hide() end

local function OwnTooltip(statFrame, onEnter)
    statFrame:SetScript("OnEnter", onEnter)
    statFrame:SetScript("OnLeave", Hide)
end

---------------------------------------------------------------------------
-- tooltips (CharacterStatsClassicCallbacks.lua)
---------------------------------------------------------------------------

local function Line(left, right)
    GameTooltip:AddDoubleLine(left, right, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
        HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
end

local function Title(self, text)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
end

local function DamageOnEnter(self)
    Title(self, self.TooltipMainTxt)
    Line(ATTACK_SPEED_COLON, format("%.2F", self.attackSpeed))
    Line(DAMAGE_COLON, self.damage)
    Line(DAMAGE_PER_SECOND, format("%.1F", self.dps))
    Line(ATTACK_TOOLTIP .. ":", self.attackRating)
    if self.offhandAttackSpeed then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(INVTYPE_WEAPONOFFHAND, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        Line(ATTACK_SPEED_COLON, format("%.2F", self.offhandAttackSpeed))
        Line(DAMAGE_COLON, self.offhandDamage)
        Line(DAMAGE_PER_SECOND, format("%.1F", self.offhandDps))
    end
    GameTooltip:Show()
end

local function SchoolLines(self, values, suffix)
    for _, school in ipairs(SCHOOL_ORDER) do
        Line(_G["SPELL_SCHOOL" .. school .. "_CAP"] .. " " .. suffix .. ": ", values(school))
    end
end

local function SpellDamageOnEnter(self)
    Title(self, STAT_SPELLPOWER)
    GameTooltip:AddDoubleLine(STAT_SPELLPOWER_TOOLTIP)
    GameTooltip:AddLine(" ")
    SchoolLines(self, function(school) return format("%.2F", self.s["sd" .. school]) end, DAMAGE)
    GameTooltip:Show()
end

local function SpellCritOnEnter(self)
    Title(self, STAT_CRITICAL_STRIKE)
    GameTooltip:AddLine(" ")
    SchoolLines(self, function(school) return format("%.2F", self.s["sc" .. school]) .. "%" end, CRIT_ABBR)
    GameTooltip:Show()
end

local function ManaRegenOnEnter(self)
    Title(self, MANA_REGEN_TOOLTIP)
    GameTooltip:AddDoubleLine(L["sheet.stats.mp5_gear"], self.mp5FromGear)
    GameTooltip:AddDoubleLine(L["sheet.stats.mp5_casting"], self.mp5Casting)
    GameTooltip:AddDoubleLine(L["sheet.stats.mp5_not_casting"], self.mp5NotCasting)
    GameTooltip:Show()
end

local function BlockOnEnter(self)
    Title(self, " ")
    GameTooltip:AddDoubleLine(BLOCK_CHANCE .. ": ", self.blockChance)
    GameTooltip:AddDoubleLine(ITEM_MOD_BLOCK_VALUE_SHORT .. ": ", self.blockValue)
    GameTooltip:Show()
end

local function MissLines(npc, player, boss, dwNpc, dwPlayer, dwBoss)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["sheet.stats.miss_vs"])
    local function Row(text, dw)
        if dw then
            GameTooltip:AddDoubleLine(TAB .. text, L("sheet.stats.dual_wield", { pct = Pct(dw) }))
        else
            GameTooltip:AddLine(TAB .. text)
        end
    end
    Row(L("sheet.stats.vs_npc", { level = 60, pct = Pct(npc) }), dwNpc)
    Row(L("sheet.stats.vs_player", { level = 60, pct = Pct(player) }), dwPlayer)
    Row(L("sheet.stats.vs_boss", { level = 63, pct = Pct(boss) }), dwBoss)
end

local function HitChanceOnEnter(self)
    local npc, boss, player, dwNpc, dwBoss, dwPlayer = MissChances(self.hitChance, self.s.mskill)
    Title(self, STAT_HIT_CHANCE)
    GameTooltip:AddLine(L["sheet.stats.hit_tip"])
    MissLines(npc, player, boss, dwNpc, dwPlayer, dwBoss)
    GameTooltip:Show()
end

local function RangedHitChanceOnEnter(self)
    local npc, boss, player = MissChances(self.hitChance, self.s.rskill)
    Title(self, STAT_HIT_CHANCE)
    GameTooltip:AddLine(L["sheet.stats.hit_tip"])
    MissLines(npc, player, boss)
    GameTooltip:Show()
end

local function SpellHitChanceOnEnter(self)
    local s = self.s
    Title(self, L("sheet.stats.spell_hit", { pct = format("%d%%", s.shit) }))
    -- per school once a talent adds hit to some of them (CSC: mage and warlock trees)
    local differs = false
    for school = 1, 6 do
        if math.abs(s["sh" .. school] - s.shit) > 0.001 then differs = true end
    end
    if differs then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["sheet.stats.spell_hit_schools"])
        for _, school in ipairs(SCHOOL_ORDER) do
            GameTooltip:AddDoubleLine(TAB .. _G["SPELL_SCHOOL" .. school .. "_CAP"], format("%d%%", s["sh" .. school]))
        end
    end
    GameTooltip:Show()
end

local function MeleeCritOnEnter(self)
    local s = self.s
    local totalWeaponSkill = s.mskill
    local _, missChanceVsBoss, _, _, dwMissChanceVsBoss = MissChances(s.mhit, totalWeaponSkill)
    if not totalWeaponSkill or totalWeaponSkill == 0 then totalWeaponSkill = 300 end

    local critSuppression = 4.8
    local glancingChance = 40
    local extraWeaponSkill = totalWeaponSkill - 300
    local bossDefense = 315 -- level 63
    local dodgeChance = 5 + (bossDefense - totalWeaponSkill) * 0.1
    local critCap = 100 - missChanceVsBoss - dodgeChance - glancingChance + critSuppression + extraWeaponSkill * 0.04

    Title(self, self.criticalStrikeTxt)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["sheet.stats.crit_cap_vs"])
    local critChance = s.mcrit
    local function Cap(cap)
        return (critChance > cap and ORANGE_FONT_COLOR_CODE or GREEN_FONT_COLOR_CODE) .. Pct(cap) .. FONT_COLOR_CODE_CLOSE
    end
    local bossLine = TAB .. L("sheet.stats.vs_boss", { level = 63, pct = Cap(critCap) })
    if s.ospd > 0 then
        local critCapDw = 100 - dwMissChanceVsBoss - dodgeChance - glancingChance + critSuppression + extraWeaponSkill * 0.04
        GameTooltip:AddDoubleLine(bossLine, L("sheet.stats.dual_wield", { pct = Cap(critCapDw) }))
    else
        GameTooltip:AddLine(bossLine)
    end
    GameTooltip:Show()
end

local function DefenseOnEnter(self)
    local s, level = self.s, self.level
    local defense = s.def + s.defB
    Title(self, DEFENSE)
    GameTooltip:AddLine(L["sheet.stats.defense_tip"])
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["sheet.stats.effect_vs"])
    GameTooltip:AddLine(TAB .. L("sheet.stats.vs_npc", { level = level, pct = Pct(math.max(0, defense - level * 5) * 0.04) }))
    GameTooltip:AddLine(TAB .. L("sheet.stats.vs_boss", { level = 63, pct = Pct(math.max(0, defense - 315) * 0.04) }))
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- stats (CharacterStatsClassicUtils.lua, CSC_PaperDollFrame_Set*)
---------------------------------------------------------------------------

local function SetPrimaryStats(rows, s, c)
    local classFile = ns.CLASS_FILE[c.class] or ""
    for i = 1, #STAT_KEYS do
        local effective, posBuff, negBuff = s["st" .. i], s["sp" .. i], s["sn" .. i]
        local name = _G["SPELL_STAT" .. i .. "_NAME"]
        local tooltipText = HIGHLIGHT_FONT_COLOR_CODE .. name .. " "
        local classStatText = _G[classFile .. "_" .. STAT_KEYS[i] .. "_TOOLTIP"] or _G["DEFAULT_" .. STAT_KEYS[i] .. "_TOOLTIP"]
        local frameText
        if posBuff == 0 and negBuff == 0 then
            frameText = effective
            rows[i].tooltip = tooltipText .. effective .. FONT_COLOR_CODE_CLOSE
        else
            tooltipText = tooltipText .. effective
            if posBuff > 0 or negBuff < 0 then tooltipText = tooltipText .. " (" .. (effective - posBuff - negBuff) .. FONT_COLOR_CODE_CLOSE end
            if posBuff > 0 then tooltipText = tooltipText .. FONT_COLOR_CODE_CLOSE .. GREEN_FONT_COLOR_CODE .. "+" .. posBuff .. FONT_COLOR_CODE_CLOSE end
            if negBuff < 0 then tooltipText = tooltipText .. RED_FONT_COLOR_CODE .. " " .. negBuff .. FONT_COLOR_CODE_CLOSE end
            if posBuff > 0 or negBuff < 0 then tooltipText = tooltipText .. HIGHLIGHT_FONT_COLOR_CODE .. ")" .. FONT_COLOR_CODE_CLOSE end
            rows[i].tooltip = tooltipText
            frameText = (negBuff < 0 and RED_FONT_COLOR_CODE or GREEN_FONT_COLOR_CODE) .. effective .. FONT_COLOR_CODE_CLOSE
        end
        rows[i].tooltip2 = classStatText
        SetLabelAndText(rows[i], name, frameText, false, effective)
    end
end

-- speed in seconds; offhand nil without one; the bonus fields are the physical school's
local function DamageTexts(minDamage, maxDamage, speed, physicalBonusPos, physicalBonusNeg, percentMod)
    if percentMod == 0 then percentMod = 1 end
    if speed == 0 then speed = 1 end
    local displayMin, displayMax = max(floor(minDamage), 1), max(ceil(maxDamage), 1)
    minDamage = (minDamage / percentMod) - physicalBonusPos - physicalBonusNeg
    maxDamage = (maxDamage / percentMod) - physicalBonusPos - physicalBonusNeg
    local baseDamage = (minDamage + maxDamage) * 0.5
    local fullDamage = (baseDamage + physicalBonusPos + physicalBonusNeg) * percentMod
    local totalBonus = fullDamage - baseDamage
    local dps = max(fullDamage, 1) / speed
    local tooltip = max(floor(minDamage), 1) .. " - " .. max(ceil(maxDamage), 1)
    local colorPos, colorNeg = "|cff20ff20", "|cffff2020"
    if totalBonus < 0.1 and totalBonus > -0.1 then totalBonus = 0 end
    local sep = (displayMin < 100 and displayMax < 100) and " - " or "-"
    local text = displayMin .. sep .. displayMax
    if totalBonus ~= 0 then
        text = (totalBonus > 0 and colorPos or colorNeg) .. text .. "|r"
        if physicalBonusPos > 0 then tooltip = tooltip .. colorPos .. " +" .. physicalBonusPos .. "|r" end
        if physicalBonusNeg < 0 then tooltip = tooltip .. colorNeg .. " " .. physicalBonusNeg .. "|r" end
        if percentMod > 1 then
            tooltip = tooltip .. colorPos .. " x" .. floor(percentMod * 100 + 0.5) .. "%|r"
        elseif percentMod < 1 then
            tooltip = tooltip .. colorNeg .. " x" .. floor(percentMod * 100 + 0.5) .. "%|r"
        end
    end
    return text, tooltip, dps, displayMax
end

local function SetDamage(statFrame, s, category)
    local ranged = category == RANGED
    if ranged and s.rw == 0 then return NotApplicable(statFrame, DAMAGE) end
    OwnTooltip(statFrame, DamageOnEnter)
    local speed = (ranged and s.rspd or s.mspd) / 1000
    local text, tooltip, dps, displayMax = DamageTexts(ranged and s.rmin or s.mmin, ranged and s.rmax or s.mmax,
        speed, s.dpos, s.dneg, s.dpct)
    SetLabelAndText(statFrame, DAMAGE, text, false, displayMax)
    statFrame.damage = tooltip
    statFrame.attackSpeed = speed > 0 and speed or 1
    statFrame.dps = dps
    statFrame.attackRating = ranged and s.rskill or s.mskill
    statFrame.TooltipMainTxt = ranged and INVTYPE_RANGED or INVTYPE_WEAPONMAINHAND
    statFrame.offhandAttackSpeed = nil
    if not ranged and s.ospd > 0 then
        local offSpeed = s.ospd / 1000
        local _, offTooltip, offDps = DamageTexts(s.omin, s.omax, offSpeed, s.dpos, s.dneg, s.dpct)
        statFrame.offhandDamage = offTooltip
        statFrame.offhandAttackSpeed = offSpeed
        statFrame.offhandDps = offDps
    end
end

local function SetAttackPower(statFrame, name, base, posBuff, negBuff, tooltipFormat)
    local valueText, tooltipText = FormatStat(name, base, posBuff, negBuff)
    local valueNum = max(0, base + posBuff + negBuff)
    SetLabelAndText(statFrame, STAT_ATTACK_POWER, valueText, false, valueNum)
    statFrame.tooltip = tooltipText
    statFrame.tooltip2 = format(tooltipFormat, valueNum / ATTACK_POWER_MAGIC_NUMBER)
end

local function SetAttackSpeed(statFrame, speed, offhandSpeed)
    local displaySpeed = format("%.2F", speed)
    if offhandSpeed then displaySpeed = displaySpeed .. " / " .. format("%.2F", offhandSpeed) end
    SetLabelAndText(statFrame, WEAPON_SPEED, displaySpeed, false, speed)
    statFrame.tooltip = format(PAPERDOLLFRAME_TOOLTIP_FORMAT, ATTACK_SPEED) .. " " .. displaySpeed
end

local function SetMelee(rows, s)
    SetDamage(rows[1], s, MELEE)
    SetAttackPower(rows[2], MELEE_ATTACK_POWER, s.ap, s.apP, s.apN, MELEE_ATTACK_POWER_TOOLTIP)
    SetAttackSpeed(rows[3], s.mspd / 1000, s.ospd > 0 and s.ospd / 1000 or nil)

    OwnTooltip(rows[4], MeleeCritOnEnter)
    SetLabelAndText(rows[4], STAT_CRITICAL_STRIKE, s.mcrit, true, s.mcrit)
    rows[4].criticalStrikeTxt = format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_CRITICAL_STRIKE) .. " " .. Pct(s.mcrit)

    OwnTooltip(rows[5], HitChanceOnEnter)
    SetLabelAndText(rows[5], STAT_HIT_CHANCE, s.mhit, true, s.mhit)
    rows[5].hitChance = s.mhit
end

local function SetRanged(rows, s)
    SetDamage(rows[1], s, RANGED)
    if s.rw == 0 then
        NotApplicable(rows[2], STAT_ATTACK_POWER)
        NotApplicable(rows[3], WEAPON_SPEED)
        NotApplicable(rows[4], STAT_CRITICAL_STRIKE)
        NotApplicable(rows[5], STAT_HIT_CHANCE)
        return
    end
    if s.rw == 2 then
        NotApplicable(rows[2], STAT_ATTACK_POWER)   -- wands have no attack power
    else
        SetAttackPower(rows[2], RANGED_ATTACK_POWER, s.rap, s.rapP, s.rapN, RANGED_ATTACK_POWER_TOOLTIP)
    end
    SetAttackSpeed(rows[3], s.rspd / 1000)

    SetLabelAndText(rows[4], STAT_CRITICAL_STRIKE, s.rcrit, true, s.rcrit)
    rows[4].tooltip = format(PAPERDOLLFRAME_TOOLTIP_FORMAT, STAT_CRITICAL_STRIKE) .. " " .. Pct(s.rcrit)

    OwnTooltip(rows[5], RangedHitChanceOnEnter)
    SetLabelAndText(rows[5], STAT_HIT_CHANCE, s.rhit, true, s.rhit)
    rows[5].hitChance = s.rhit
end

local function SetSpell(rows, s)
    local maxDamage, maxCrit = 0, 0
    for school = 1, 6 do
        maxDamage = max(maxDamage, s["sd" .. school])
        maxCrit = max(maxCrit, s["sc" .. school])
    end
    OwnTooltip(rows[1], SpellDamageOnEnter)
    SetLabelAndText(rows[1], STAT_SPELLPOWER, BreakUpLargeNumbers(maxDamage), false, maxDamage)

    SetLabelAndText(rows[2], STAT_SPELLHEALING, s.heal, false, s.heal)
    rows[2].tooltip = STAT_SPELLHEALING .. " " .. s.heal
    rows[2].tooltip2 = STAT_SPELLHEALING_TOOLTIP

    if s.mana == 0 then
        NotApplicable(rows[3], MANA_REGEN)
    else
        OwnTooltip(rows[3], ManaRegenOnEnter)
        local casting = BreakUpLargeNumbers(floor(s.mpc + 0.5))
        SetLabelAndText(rows[3], MANA_REGEN, casting, false, s.mpc)
        rows[3].mp5FromGear = BreakUpLargeNumbers(floor(s.mp5 + 0.5))
        rows[3].mp5Casting = casting
        rows[3].mp5NotCasting = BreakUpLargeNumbers(floor(s.mpn + 0.5))
    end

    OwnTooltip(rows[4], SpellCritOnEnter)
    SetLabelAndText(rows[4], STAT_CRITICAL_STRIKE, maxCrit, true, maxCrit)

    OwnTooltip(rows[5], SpellHitChanceOnEnter)
    SetLabelAndText(rows[5], STAT_HIT_CHANCE, s.shit, true, s.shit)
end

local function SetDefenses(rows, s, c)
    local level = c.level or 1
    local armorBase = s.arm - s.armP - s.armN
    local armorReduction = s.arm / ((85 * level) + 400)
    armorReduction = 100 * (armorReduction / (armorReduction + 1))
    local valueText, tooltipText = FormatStat(ARMOR, armorBase, s.armP, s.armN)
    SetLabelAndText(rows[1], STAT_ARMOR, valueText, false, max(0, s.arm))
    rows[1].tooltip = tooltipText
    rows[1].tooltip2 = format(ARMOR_TOOLTIP, level, armorReduction)

    OwnTooltip(rows[2], DefenseOnEnter)
    local defenseText = FormatStat(DEFENSE_COLON, s.def, max(s.defB, 0), min(s.defB, 0))
    SetLabelAndText(rows[2], DEFENSE, defenseText, false, max(0, s.def + s.defB))
    rows[2].level = level

    SetLabelAndText(rows[3], STAT_DODGE, s.dodge, true, s.dodge, "%.2F%%")
    rows[3].tooltip = format(PAPERDOLLFRAME_TOOLTIP_FORMAT, DODGE_CHANCE) .. " " .. Pct(s.dodge)

    SetLabelAndText(rows[4], STAT_PARRY, s.parry, true, s.parry, "%.2F%%")
    rows[4].tooltip = format(PAPERDOLLFRAME_TOOLTIP_FORMAT, PARRY_CHANCE) .. " " .. Pct(s.parry)

    OwnTooltip(rows[5], BlockOnEnter)
    SetLabelAndText(rows[5], STAT_BLOCK, s.block, true, s.block, "%.2F%%")
    rows[5].blockChance = Pct(s.block)
    rows[5].blockValue = s.bval
end

---------------------------------------------------------------------------
-- panel (CharacterStatsClassicUI.lua)
---------------------------------------------------------------------------

local function ResetRows(rows, s)
    for i = 1, NUM_STATS_TO_SHOW do
        local row = rows[i]
        row:Hide()
        row:SetScript("OnEnter", row.OnEnterCallback)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row.tooltip, row.tooltip2, row.tooltip3 = nil, nil, nil
        row.Background:SetAlpha(0)
        row.s = s
    end
end

local function Fill(rows, index)
    local s, c = shown and shown.s, shown and shown.c
    ResetRows(rows, s)
    if not s then return end
    local category = CATEGORIES[index]
    if category == BASE then
        SetPrimaryStats(rows, s, c)
    elseif category == MELEE then
        SetMelee(rows, s)
    elseif category == RANGED then
        SetRanged(rows, s)
    elseif category == SPELL then
        SetSpell(rows, s)
    elseif category == DEFENSES then
        SetDefenses(rows, s, c)
    end
end

local function Selected(side)
    local db = ns.db or {}
    return (side == "left" and db.sheetStatsLeft) or (side == "right" and db.sheetStatsRight) or (side == "left" and 1 or 2)
end

local function FillAll()
    Fill(leftRows, Selected("left"))
    Fill(rightRows, Selected("right"))
end

local function Dropdown(side, x)
    local dropdown = CreateFrame("Frame", "PartyBotCompanionSheetStats" .. side, panel, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
    UIDropDownMenu_Initialize(dropdown, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        for _, name in ipairs(CATEGORIES) do
            info.text = name
            info.checked = false
            info.func = function(button)
                if ns.db then ns.db[side == "left" and "sheetStatsLeft" or "sheetStatsRight"] = button:GetID() end
                UIDropDownMenu_SetSelectedID(dropdown, button:GetID())
                Fill(side == "left" and leftRows or rightRows, button:GetID())
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedID(dropdown, Selected(side))
    UIDropDownMenu_SetWidth(dropdown, 99)
    UIDropDownMenu_JustifyText(dropdown, "LEFT")
    return dropdown
end

local function Rows(parent, rows)
    local offset = 32
    for i = 1, NUM_STATS_TO_SHOW do
        local row = CreateFrame("Frame", nil, parent, "CharacterStatFrameTemplate")
        row:SetPoint("LEFT", parent, "TOPLEFT", 10, -offset)
        row:SetWidth(130)
        row.OnEnterCallback = row:GetScript("OnEnter")
        rows[i] = row
        offset = offset + 15
    end
end

-- Stats.Build(page): the panel where the paper doll's attribute boxes are
function Stats.Build(page)
    panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("LEFT", page, "BOTTOMLEFT", 50, 75)
    panel:SetHeight(320)
    panel:SetWidth(200)
    local left = Dropdown("left", 0)
    local right = Dropdown("right", 115)
    Rows(left, leftRows)
    Rows(right, rightRows)

    offline = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    offline:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -40)
    offline:SetWidth(240)
    offline:SetText(L["sheet.character.stats_offline"])
    offline:Hide()
end

-- Stats.Update(s, c, offlineNow): s = the merged S lines (nil before they come or offline)
function Stats.Update(s, c, isOffline)
    shown = s and { s = s, c = c } or nil
    offline:SetShown(isOffline and not s)
    FillAll()
end
