-- Companion sheet, page 3: 声望 — the factions the companion knows, grouped under their parent
-- faction like the player's reputation tab. Names come from the client (GetFactionInfoByID).

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local ROWS = 15
local ROW_H = 23

-- standing thresholds (ReputationMgr::ReputationToRank), standing 1 hated .. 8 exalted
local THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 43000 }

local rows = {}
local scroll
local collapsed = {}    -- [parent faction id] = true
local entries = {}      -- display list: { header = true, id, name } | { id, name, value, atWar }
local gender = 0

local function Standing(value)
    for i = 8, 1, -1 do
        if value >= THRESHOLDS[i] then return i end
    end
    return 1
end

local function StandingText(rank)
    local female = gender == 1 and _G["FACTION_STANDING_LABEL" .. rank .. "_FEMALE"]
    return female or _G["FACTION_STANDING_LABEL" .. rank] or tostring(rank)
end

local function FactionName(id)
    if id == 0 then return OTHER or L["sheet.reputation.other"] end
    local name = GetFactionInfoByID and GetFactionInfoByID(id)
    return name
end

local function BuildEntries(data)
    local groups, order = {}, {}
    for _, f in ipairs(data and data.lines.F or {}) do
        local id, parent = tonumber(f[1]), tonumber(f[2]) or 0
        local name = id and FactionName(id)
        if name then
            if not groups[parent] then
                groups[parent] = {}
                order[#order + 1] = parent
            end
            table.insert(groups[parent], { id = id, name = name, value = tonumber(f[3]) or 0, atWar = f[4] == "1" })
        end
    end
    -- a parent that is itself listed (it has a standing) is only a header
    table.sort(order, function(a, b)
        if (a == 0) ~= (b == 0) then return b == 0 end
        return (FactionName(a) or "") < (FactionName(b) or "")
    end)
    wipe(entries)
    for _, parent in ipairs(order) do
        entries[#entries + 1] = { header = true, id = parent, name = FactionName(parent) or "?" }
        if not collapsed[parent] then
            table.sort(groups[parent], function(a, b) return a.name < b.name end)
            for _, e in ipairs(groups[parent]) do
                if not groups[e.id] then entries[#entries + 1] = e end
            end
        end
    end
end

local function Render()
    local offset = FauxScrollFrame_GetOffset(scroll)
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
            local rank = Standing(e.value)
            local min, max = THRESHOLDS[rank], THRESHOLDS[rank + 1]
            local bar = row.bar
            bar:SetMinMaxValues(0, max - min)
            bar:SetValue(e.value - min)
            local color = FACTION_BAR_COLORS[rank]
            if color then bar:SetStatusBarColor(color.r, color.g, color.b) end
            bar.standingText = StandingText(rank)
            bar.tooltip = ("%d / %d"):format(e.value - min, max - min)
            bar.nameText:SetText(e.name)
            bar.standing:SetText(bar.standingText)
            bar.atWar:SetShown(e.atWar)
            bar:Show()
        end
    end
    FauxScrollFrame_Update(scroll, #entries, ROWS, ROW_H)
end

Sheet.AddPage({
    key = "reputation", title = REPUTATION or L["sheet.reputation.title"], order = 30, server = "rep",
    Build = function(page)
        Sheet.GeneralBackground(page)
        local faction = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        faction:SetPoint("TOPLEFT", 70, -57)
        faction:SetText(FACTION or L["sheet.reputation.faction"])
        local standingLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        standingLabel:SetPoint("TOPLEFT", 215, -59)
        standingLabel:SetText(STANDING or L["sheet.reputation.standing"])

        for i = 1, ROWS do
            local name = "PartyBotCompanionRepBar" .. i
            local bar = CreateFrame("StatusBar", name, page, "ReputationBarTemplate")
            bar:SetPoint("TOPLEFT", 150, -86 - (i - 1) * ROW_H)
            bar.nameText = _G[name .. "FactionName"]
            bar.standing = _G[name .. "FactionStanding"]
            bar.atWar = _G[name .. "AtWarCheck"]
            bar:SetScript("OnMouseUp", nil)     -- the player's detail frame is not for companions
            bar:SetScript("OnLeave", function(self)
                self.standing:SetText(self.standingText)
                _G[self:GetName() .. "Highlight1"]:Hide()
                _G[self:GetName() .. "Highlight2"]:Hide()
            end)

            local header = CreateFrame("Button", "PartyBotCompanionRepHeader" .. i, page, "ReputationHeaderTemplate")
            header:SetPoint("LEFT", bar, "LEFT", -125, 0)
            header:SetScript("OnClick", function(self)
                collapsed[self.id] = not collapsed[self.id] or nil
                BuildEntries(page.data)
                Render()
            end)
            rows[i] = { bar = bar, header = header }
        end

        scroll = CreateFrame("ScrollFrame", "PartyBotCompanionRepScrollFrame", page, "FauxScrollFrameTemplate")
        scroll:SetSize(296, 354)
        scroll:SetPoint("TOPRIGHT", page, "TOPRIGHT", -66, -76)
        scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Render)
        end)
        Sheet.ScrollBarArt(scroll, 108, 0.421875)

        page.empty = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
        page.empty:SetPoint("TOP", 0, -140)
    end,
    Update = function(page, c, data)
        gender = c.gender
        page.data = data
        BuildEntries(data)
        page.empty:SetText(not data and "" or (#entries == 0 and L["sheet.reputation.empty"] or ""))
        Render()
    end,
})
