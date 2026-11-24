-- Companion sheet, page 4: 技能 — professions, weapon skills, armor and languages grouped like
-- the player's skill tab, with a detail bar for the selected one below the list.
-- Skill names: the client has no lookup by id, so a table of the usual ones in Chinese; the
-- rest use the name the server's DBC has.

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local ROWS = 12
local ROW_H = 18

-- SkillLine.dbc category -> header, in the player's skill tab order
local CATEGORIES = {
    { id = 7,  text = L["sheet.skill.category.class"] },
    { id = 11, text = L["sheet.skill.category.professions"] },
    { id = 9,  text = L["sheet.skill.category.secondary"] },
    { id = 6,  text = L["sheet.skill.category.weapons"] },
    { id = 8,  text = L["sheet.skill.category.armor"] },
    { id = 10, text = L["sheet.skill.category.languages"] },
}

local SKILL_NAMES = {
    -- weapons
    [43] = L["sheet.skill.name.sword"], [44] = L["sheet.skill.name.axe"], [45] = L["sheet.skill.name.bow"],
    [46] = L["sheet.skill.name.gun"], [54] = L["sheet.skill.name.mace"], [55] = L["sheet.skill.name.sword_2h"],
    [95] = L["sheet.skill.name.defense"],
    [118] = L["sheet.skill.name.dual_wield"], [136] = L["sheet.skill.name.staff"], [160] = L["sheet.skill.name.mace_2h"],
    [162] = L["sheet.skill.name.unarmed"], [172] = L["sheet.skill.name.axe_2h"], [173] = L["sheet.skill.name.dagger"],
    [176] = L["sheet.skill.name.thrown"], [226] = L["sheet.skill.name.crossbow"], [228] = L["sheet.skill.name.wand"],
    [229] = L["sheet.skill.name.polearm"], [473] = L["sheet.skill.name.fist"],
    -- armor
    [293] = L["sheet.skill.name.plate"], [413] = L["sheet.skill.name.mail"], [414] = L["sheet.skill.name.leather"],
    [415] = L["sheet.skill.name.cloth"], [433] = L["sheet.skill.name.shield"],
    -- professions
    [164] = L["sheet.skill.name.blacksmithing"], [165] = L["sheet.skill.name.leatherworking"],
    [171] = L["sheet.skill.name.alchemy"], [182] = L["sheet.skill.name.herbalism"], [186] = L["sheet.skill.name.mining"],
    [197] = L["sheet.skill.name.tailoring"], [202] = L["sheet.skill.name.engineering"],
    [333] = L["sheet.skill.name.enchanting"], [393] = L["sheet.skill.name.skinning"],
    -- secondary
    [129] = L["sheet.skill.name.first_aid"], [185] = L["sheet.skill.name.cooking"], [356] = L["sheet.skill.name.fishing"],
    -- languages
    [98] = L["sheet.skill.name.lang_common"], [109] = L["sheet.skill.name.lang_orcish"],
    [111] = L["sheet.skill.name.lang_dwarven"], [113] = L["sheet.skill.name.lang_darnassian"],
    [115] = L["sheet.skill.name.lang_taurahe"], [137] = L["sheet.skill.name.lang_thalassian"],
    [138] = L["sheet.skill.name.lang_draconic"], [139] = L["sheet.skill.name.lang_demonic"],
    [140] = L["sheet.skill.name.lang_titan"], [141] = L["sheet.skill.name.lang_old_tongue"],
    [313] = L["sheet.skill.name.lang_gnomish"], [315] = L["sheet.skill.name.lang_troll"],
    [673] = L["sheet.skill.name.lang_gutterspeak"],
    -- class
    [633] = L["sheet.skill.name.lockpicking"], [40] = L["sheet.skill.name.poisons"],
}

local rows = {}
local scroll, detail
local collapsed = {}
local entries = {}
local selected      -- skill id

local function BuildEntries(data)
    local byCategory = {}
    for _, f in ipairs(data and data.lines.K or {}) do
        local id, category = tonumber(f[1]), tonumber(f[2])
        local max = tonumber(f[4]) or 0
        -- class skills: only the ones with a rank (lockpicking, poisons), not the talent trees
        if id and category and (category ~= 7 or max > 1) then
            byCategory[category] = byCategory[category] or {}
            table.insert(byCategory[category], {
                id = id, value = tonumber(f[3]) or 0, max = max, bonus = tonumber(f[5]) or 0,
                name = SKILL_NAMES[id] or f[6] or tostring(id), category = category,
            })
        end
    end
    wipe(entries)
    for _, cat in ipairs(CATEGORIES) do
        local list = byCategory[cat.id]
        if list then
            entries[#entries + 1] = { header = true, id = cat.id, name = cat.text }
            if not collapsed[cat.id] then
                table.sort(list, function(a, b) return a.name < b.name end)
                for _, e in ipairs(list) do entries[#entries + 1] = e end
            end
        end
    end
end

-- one skill on a SkillStatusBarTemplate bar (the player's skill tab colours)
local function SetBar(bar, e)
    local name = bar:GetName()
    _G[name .. "SkillName"]:SetText(e.name)
    local rank = _G[name .. "SkillRank"]
    rank:ClearAllPoints()
    rank:SetPoint("LEFT", _G[name .. "SkillName"], "RIGHT", 13, 0)
    rank:SetJustifyH("LEFT")
    _G[name .. "FillBar"]:Hide()
    if e.max <= 1 then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetStatusBarColor(0.5, 0.5, 0.5)
        _G[name .. "Background"]:SetVertexColor(1, 1, 1, 0.5)
        rank:SetText("")
    else
        bar:SetMinMaxValues(0, e.max)
        bar:SetValue(e.value)
        bar:SetStatusBarColor(0, 0, 1, 0.5)
        _G[name .. "Background"]:SetVertexColor(0, 0, 0.75, 0.5)
        if e.bonus ~= 0 then
            local color = e.bonus > 0 and (GREEN_FONT_COLOR_CODE .. "+") or RED_FONT_COLOR_CODE
            rank:SetText(e.value .. " (" .. color .. e.bonus .. FONT_COLOR_CODE_CLOSE .. ")/" .. e.max)
        else
            rank:SetText(e.value .. "/" .. e.max)
        end
    end
end

local function Render()
    local offset = FauxScrollFrame_GetOffset(scroll)
    local selectedEntry
    for _, e in ipairs(entries) do
        if not e.header and e.id == selected then selectedEntry = e end
    end
    for i, row in ipairs(rows) do
        local e = entries[offset + i]
        row.header:Hide()
        row.bar:Hide()
        if e and e.header then
            row.header.id = e.id
            row.header:SetText(e.name)
            row.header:SetNormalTexture(collapsed[e.id] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            row.header:Show()
        elseif e then
            row.bar.entry = e
            SetBar(row.bar, e)
            local border = _G[row.bar:GetName() .. "Border"]
            if e.id == selected then border:LockHighlight() else border:UnlockHighlight() end
            row.bar:Show()
        end
    end
    FauxScrollFrame_Update(scroll, #entries, ROWS, ROW_H)

    if selectedEntry then
        SetBar(detail, selectedEntry)
        detail:Show()
    else
        detail:Hide()
    end
end

Sheet.AddPage({
    key = "skills", title = SKILLS or L["sheet.skill.title"], order = 40, server = "skill",
    Build = function(page)
        local parts = {
            { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft", 256, 256, "TOPLEFT" },
            { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight", 128, 256, "TOPRIGHT" },
            { "Interface\\PaperDollInfoFrame\\SkillFrame-BotLeft", 256, 256, "BOTTOMLEFT" },
            { "Interface\\PaperDollInfoFrame\\SkillFrame-BotRight", 128, 256, "BOTTOMRIGHT" },
        }
        for _, p in ipairs(parts) do
            local t = page:CreateTexture(nil, "BORDER")
            t:SetTexture(p[1])
            t:SetSize(p[2], p[3])
            t:SetPoint(p[4], 2, -1)
        end
        local hbar = page:CreateTexture(nil, "ARTWORK")
        hbar:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
        hbar:SetSize(256, 16)
        hbar:SetPoint("TOPLEFT", 15, -290)
        hbar:SetTexCoord(0, 1, 0, 0.25)
        local hbar2 = page:CreateTexture(nil, "ARTWORK")
        hbar2:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
        hbar2:SetSize(75, 16)
        hbar2:SetPoint("LEFT", hbar, "RIGHT")
        hbar2:SetTexCoord(0, 0.29296875, 0.25, 0.5)

        for i = 1, ROWS do
            local bar = CreateFrame("StatusBar", "PartyBotCompanionSkillBar" .. i, page, "SkillStatusBarTemplate")
            bar:SetPoint("TOPLEFT", 38, -79 - (i - 1) * ROW_H)
            _G[bar:GetName() .. "Border"]:SetScript("OnClick", function(self)
                local e = self:GetParent().entry
                selected = e and e.id
                Render()
            end)
            local header = CreateFrame("Button", "PartyBotCompanionSkillHeader" .. i, page, "SkillLabelTemplate")
            header:SetPoint("LEFT", bar, "LEFT", -16, 0)
            header:SetScript("OnClick", function(self)
                collapsed[self.id] = not collapsed[self.id] or nil
                BuildEntries(page.data)
                Render()
            end)
            rows[i] = { bar = bar, header = header }
        end

        scroll = CreateFrame("ScrollFrame", "PartyBotCompanionSkillScrollFrame", page, "FauxScrollFrameTemplate")
        scroll:SetSize(296, 220)
        scroll:SetPoint("TOPRIGHT", page, "TOPRIGHT", -67, -75)
        scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Render)
        end)
        local top = scroll:CreateTexture(nil, "BACKGROUND")
        top:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-ScrollBar")
        top:SetSize(30, 128)
        top:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -3, 5)
        top:SetTexCoord(0, 0.46875, 0, 1)
        local bottom = scroll:CreateTexture(nil, "BACKGROUND")
        bottom:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-ScrollBar")
        bottom:SetSize(30, 128)
        bottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -3, -2)
        bottom:SetTexCoord(0.53125, 1, 0, 1)

        -- the selected skill, in the detail area below the bar
        detail = CreateFrame("StatusBar", "PartyBotCompanionSkillDetailBar", page, "SkillStatusBarTemplate")
        detail:SetPoint("TOPLEFT", 38, -318)
        _G[detail:GetName() .. "Border"]:EnableMouse(false)

        page.empty = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        page.empty:SetPoint("TOP", 0, -140)
    end,
    Update = function(page, c, data)
        page.data = data
        BuildEntries(data)
        page.empty:SetText(data and #entries == 0 and L["sheet.skill.empty"] or "")
        Render()
    end,
})
