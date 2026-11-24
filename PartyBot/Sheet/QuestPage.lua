-- Companion sheet, page 5: 任务 — his quest log, built like the player's own (L key): quests
-- grouped by zone, (完成)/(失败) tags, colours by his level, the selected quest's objectives with
-- their progress below the list, and the log's 放弃 / 共享 buttons. Works for offline companions
-- too (the server reads them from the database); the buttons need him online. While he is online
-- the page keeps itself fresh.
--
-- Request: .partybot questlog <guid> [abandon|share <quest>]
-- Reply:   server PlayerBots/Companions/CompanionQuestLog.cpp (PBQLOG;<guid>;BEGIN|Q|O|T|D|END)

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local PAGE_KEY = "quests"
local ROWS = 8
local ROW_H = 16
local LIST_W = 294
local MAX_LINES = 8
local REFRESH = 5           -- seconds between reloads while he is online and the page is shown
local MAX_QUESTS = MAX_QUESTLOG_QUESTS or 20

local page, scroll, detail, abandonButton, shareButton
local rows, objectiveLines = {}, {}
local current               -- guid shown
local data                  -- { online, quests = { quest, ... } } of `current`
local incoming              -- [guid] = data being received
local entries = {}          -- the list rows: { header = text } or { quest = q }
local collapsed = {}        -- [header] = true
local selected              -- quest id
local shownDetail           -- quest id the detail pane shows (keeps its scroll on reloads)

-- QuestInfo.dbc types the player's log tags
local TAGS = {
    [1] = ELITE or L["sheet.quests.tag.elite"],
    [41] = PVP or L["sheet.quests.tag.pvp"],
    [62] = RAID or L["sheet.quests.tag.raid"],
    [81] = L["sheet.quests.tag.dungeon"],
}

-- why an abandon or a share did not happen (server PBERR codes)
ns.ERROR_TEXT.noquest = L["sheet.quests.err.noquest"]
ns.ERROR_TEXT.questkeep = L["sheet.quests.err.keep"]
ns.ERROR_TEXT.notsharable = L["sheet.quests.err.notsharable"]
ns.ERROR_TEXT.questhave = L["sheet.quests.err.have"]
ns.ERROR_TEXT.questdone = L["sheet.quests.err.done"]
ns.ERROR_TEXT.questcant = L["sheet.quests.err.cant"]
ns.ERROR_TEXT.questlogfull = L["sheet.quests.err.logfull"]
ns.ERROR_TEXT.questbusy = L["sheet.quests.err.busy"]

---------------------------------------------------------------------------
-- data
---------------------------------------------------------------------------

local function Companion() return current and ns.FindCompanion(current) end

-- quest text tokens, filled in for him (the client does it for the player's own log)
local function Fill(text, c)
    if not text or text == "" then return "" end
    local race = c and ns.RaceInfo(c.race)
    text = text:gsub("%$[Gg]%s*([^:;]*):([^;]*);", function(male, female)
        return (c and c.gender == 1) and female or male
    end)
    text = text:gsub("%$[Bb]", "\n")
    text = text:gsub("%$[Nn]", c and c.name or "")
    text = text:gsub("%$[Cc]", c and ns.CLASS_TEXT[c.class] or "")
    text = text:gsub("%$[Rr]", race and race.raceName or "")
    return text
end

local function HeaderText(zone, header)
    if zone > 0 and C_Map and C_Map.GetAreaInfo then
        local name = C_Map.GetAreaInfo(zone)
        if name and name ~= "" then return name end
    end
    if header and header ~= "" then return header end
    return L["sheet.quests.header.other"]
end

-- his quest colours: by his level, as GetQuestDifficultyColor does for the player's
local function DifficultyColor(level, his)
    local diff = level - his
    if diff >= 5 then return QuestDifficultyColors.impossible end
    if diff >= 3 then return QuestDifficultyColors.verydifficult end
    if diff >= -2 then return QuestDifficultyColors.difficult end
    if -diff <= (GetQuestGreenRange and GetQuestGreenRange() or 8) then return QuestDifficultyColors.standard end
    return QuestDifficultyColors.trivial
end

local function QuestLevel(q, c)
    return q.level > 0 and q.level or (c and c.level or 1)
end

local function BuildEntries()
    wipe(entries)
    if not data then return end
    local order, byHeader = {}, {}
    for _, q in ipairs(data.quests) do
        if not byHeader[q.header] then
            byHeader[q.header] = {}
            order[#order + 1] = q.header
        end
        table.insert(byHeader[q.header], q)
    end
    for _, header in ipairs(order) do
        entries[#entries + 1] = { header = header }
        if not collapsed[header] then
            for _, q in ipairs(byHeader[header]) do entries[#entries + 1] = { quest = q } end
        end
    end
end

local function SelectedQuest()
    if not data then return nil end
    for _, q in ipairs(data.quests) do
        if q.id == selected then return q end
    end
end

-- he is in your party or raid (sharing needs it)
local function InGroupWithYou(c)
    return c and (UnitInParty(c.name) or UnitInRaid(c.name)) and true or false
end

---------------------------------------------------------------------------
-- server
---------------------------------------------------------------------------

local function Request(auto)
    if not current then return end
    local cmd = ".partybot questlog " .. current
    if auto then ns.SendCommandAuto(cmd) else ns.SendCommand(cmd) end
end

local function Act(verb, questId)
    if current then ns.SendCommand((".partybot questlog %d %s %d"):format(current, verb, questId)) end
end

StaticPopupDialogs["PARTYBOT_ABANDON_COMPANION_QUEST"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, questId) Act("abandon", questId) end,
    timeout = 0,
    whileDead = 1,
    exclusive = 1,
    hideOnEscape = 1,
}

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------

local function ObjectiveText(o)
    local pattern = (o.kind == "m" and QUEST_MONSTERS_KILLED) or (o.kind == "i" and QUEST_ITEMS_NEEDED)
        or QUEST_OBJECTS_FOUND or "%s: %d/%d"
    return pattern:format(o.name, o.have, o.need)
end

local function UpdateButtons()
    local q = SelectedQuest()
    local online = data and data.online
    abandonButton:SetEnabled(q ~= nil and online and true or false)
    shareButton:SetEnabled(q ~= nil and online and q.sharable and InGroupWithYou(Companion()) or false)
end

local function UpdateDetail()
    local q = SelectedQuest()
    if not q then
        detail:Hide()
        shownDetail = nil
        return
    end
    local c = Companion()
    local child = detail.child
    local title = Fill(q.title, c)
    if q.state < 0 then title = title .. " - (" .. FAILED .. ")" end
    child.title:SetText(title)
    child.objectives:SetText(Fill(q.objectives, c))

    local last = child.objectives
    for i, line in ipairs(objectiveLines) do
        local o = q.lines[i]
        if o and i <= MAX_LINES then
            local text = ObjectiveText(o)
            if o.have >= o.need then
                line:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
                text = text .. " (" .. COMPLETE .. ")"
            else
                line:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
            end
            line:SetText(text)
            line:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, i == 1 and -10 or -2)
            line:Show()
            last = line
        else
            line:Hide()
        end
    end
    child.descriptionTitle:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -10)
    child.description:SetText(Fill(q.description, c))
    detail:Show()
    detail:UpdateScrollChildRect()
    if shownDetail ~= q.id then
        _G[detail:GetName() .. "ScrollBar"]:SetValue(0)
        shownDetail = q.id
    end
end

local function Render()
    if not page then return end
    local c = Companion()
    local count = data and #data.quests or 0
    page.count:SetText((QUEST_LOG_COUNT_TEMPLATE or "%d/%d"):format(count, MAX_QUESTS))
    page.empty:SetText(data ~= nil and count == 0 and L["sheet.quests.empty"] or "")

    -- keep a selection, as the player's log does
    if not SelectedQuest() then
        selected = nil
        for _, e in ipairs(entries) do
            if e.quest then selected = e.quest.id break end
        end
    end

    local offset = FauxScrollFrame_GetOffset(scroll)
    page.highlight:Hide()
    for i, row in ipairs(rows) do
        local e = entries[offset + i]
        row.entry = e
        if not e then
            row:Hide()
        else
            local tag = _G[row:GetName() .. "Tag"]
            local color
            if e.header then
                row:SetText(e.header)
                row:SetNormalTexture(collapsed[e.header] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                row.highlightTexture:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
                tag:SetText("")
                color = QuestDifficultyColors.header
            else
                local q = e.quest
                row:SetText("  " .. Fill(q.title, c))
                row:SetNormalTexture("")
                row.highlightTexture:SetTexture("")
                local text = q.state < 0 and FAILED or q.state > 0 and COMPLETE or TAGS[q.type]
                tag:SetText(text and ("(" .. text .. ")") or "")
                color = DifficultyColor(QuestLevel(q, c), c and c.level or 1)
            end
            local normalText = _G[row:GetName() .. "NormalText"]
            normalText:SetWidth(LIST_W - 40 - tag:GetWidth())
            row:SetNormalFontObject(color.font)
            tag:SetTextColor(color.r, color.g, color.b)
            row.r, row.g, row.b = color.r, color.g, color.b
            if e.quest and e.quest.id == selected then
                page.highlightTexture:SetVertexColor(color.r, color.g, color.b)
                page.highlight:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                page.highlight:Show()
                tag:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
                row:LockHighlight()
            else
                row:UnlockHighlight()
            end
            row:Show()
        end
    end
    FauxScrollFrame_Update(scroll, #entries, ROWS, ROW_H, nil, nil, nil, page.highlight, LIST_W, LIST_W)
    UpdateDetail()
    UpdateButtons()
end

-- switches the page to companion `guid` (fresh state)
local function ShowCompanion(guid)
    if current == guid then return end
    current, data, selected, shownDetail = guid, nil, nil, nil
    FauxScrollFrame_SetOffset(scroll, 0)
    _G[scroll:GetName() .. "ScrollBar"]:SetValue(0)
    BuildEntries()
end

---------------------------------------------------------------------------
-- page (the player's QuestLogFrame layout, Interface_Vanilla/FrameXML/QuestLogFrame.xml, on the
-- character window's plain background)
---------------------------------------------------------------------------

local function ButtonTooltip(button, enabledText, disabledText)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnEnter", function(self)
        local text = self:IsEnabled() and enabledText or disabledText()
        if not text then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

local function Build(p)
    page = p
    Sheet.GeneralBackground(page)

    page.count = page:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    page.count:SetPoint("TOPRIGHT", -72, -59)

    page.empty = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    page.empty:SetPoint("TOP", -10, -140)

    page.highlight = CreateFrame("Frame", nil, page)
    page.highlight:SetSize(LIST_W, ROW_H)
    page.highlight:Hide()
    page.highlightTexture = page.highlight:CreateTexture(nil, "ARTWORK")
    page.highlightTexture:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    page.highlightTexture:SetBlendMode("ADD")
    page.highlightTexture:SetAllPoints()

    for i = 1, ROWS do
        local row = CreateFrame("Button", "PartyBotCompanionQuestTitle" .. i, page, "QuestLogTitleButtonTemplate")
        -- the template's scripts work on the player's own log
        row:UnregisterAllEvents()
        row:SetScript("OnEvent", nil)
        row:SetWidth(LIST_W)
        row:SetPoint("TOPLEFT", 22, -76 - (i - 1) * ROW_H)
        row.highlightTexture = _G[row:GetName() .. "Highlight"]
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if not e then return end
            if e.header then
                collapsed[e.header] = not collapsed[e.header] or nil
                BuildEntries()
            else
                selected = e.quest.id
                PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN)
            end
            Render()
        end)
        row:SetScript("OnEnter", function(self)
            _G[self:GetName() .. "Tag"]:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        end)
        row:SetScript("OnLeave", function(self)
            if not (self.entry and self.entry.quest and self.entry.quest.id == selected) and self.r then
                _G[self:GetName() .. "Tag"]:SetTextColor(self.r, self.g, self.b)
            end
        end)
        rows[i] = row
    end

    scroll = CreateFrame("ScrollFrame", "PartyBotCompanionQuestListScrollFrame", page, "FauxScrollFrameTemplate")
    scroll:SetSize(LIST_W, ROWS * ROW_H)
    scroll:SetPoint("TOPLEFT", 22, -76)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Render)
    end)

    -- the selected quest
    detail = CreateFrame("ScrollFrame", "PartyBotCompanionQuestDetailScrollFrame", page, "UIPanelScrollFrameTemplate")
    detail:SetSize(LIST_W, 182)
    detail:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
    local child = CreateFrame("Frame", nil, detail)
    child:SetSize(LIST_W, 182)
    detail:SetScrollChild(child)
    detail.child = child
    child.title = child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    child.title:SetWidth(LIST_W - 10)
    child.title:SetJustifyH("LEFT")
    child.title:SetPoint("TOPLEFT", 5, -5)
    child.objectives = child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    child.objectives:SetWidth(LIST_W - 15)
    child.objectives:SetJustifyH("LEFT")
    child.objectives:SetPoint("TOPLEFT", child.title, "BOTTOMLEFT", 0, -5)
    for i = 1, MAX_LINES do
        local line = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetWidth(LIST_W - 10)
        line:SetJustifyH("LEFT")
        line:Hide()
        objectiveLines[i] = line
    end
    child.descriptionTitle = child:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    child.descriptionTitle:SetWidth(LIST_W - 10)
    child.descriptionTitle:SetJustifyH("LEFT")
    child.descriptionTitle:SetText(QUEST_DESCRIPTION)
    child.description = child:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    child.description:SetWidth(LIST_W - 20)
    child.description:SetJustifyH("LEFT")
    child.description:SetPoint("TOPLEFT", child.descriptionTitle, "BOTTOMLEFT", 0, -5)
    -- room below the last line, as QuestLogSpacerFrame
    local spacer = CreateFrame("Frame", nil, child)
    spacer:SetSize(5, 25)
    spacer:SetPoint("TOP", child.description, "BOTTOM")
    detail:Hide()

    -- the log's buttons (QuestLogFrameAbandonButton, QuestFramePushQuestButton)
    abandonButton = CreateFrame("Button", "PartyBotCompanionQuestAbandonButton", page, "UIPanelButtonTemplate")
    abandonButton:SetSize(110, 21)
    abandonButton:SetPoint("BOTTOMLEFT", 22, 86)
    abandonButton:SetText(ABANDON_QUEST_ABBREV or L["sheet.quests.abandon"])
    abandonButton:SetScript("OnClick", function()
        local q, c = SelectedQuest(), Companion()
        if not q or not c then return end
        StaticPopup_Show("PARTYBOT_ABANDON_COMPANION_QUEST",
            L("sheet.quests.abandon_confirm", { name = c.name, quest = Fill(q.title, c) }), nil, q.id)
    end)
    ButtonTooltip(abandonButton, nil, function()
        return SelectedQuest() and L["sheet.quests.need_online"] or nil
    end)

    shareButton = CreateFrame("Button", "PartyBotCompanionQuestShareButton", page, "UIPanelButtonTemplate")
    shareButton:SetSize(110, 21)
    shareButton:SetPoint("BOTTOMRIGHT", -66, 86)
    shareButton:SetText(SHARE_QUEST_ABBREV or L["sheet.quests.share"])
    shareButton:SetScript("OnClick", function()
        local q = SelectedQuest()
        if q then Act("share", q.id) end
    end)
    ButtonTooltip(shareButton, L["sheet.quests.share_tip"], function()
        local q = SelectedQuest()
        if not q then return nil end
        if not (data and data.online) then return L["sheet.quests.need_online"] end
        if not q.sharable then return L["sheet.quests.err.notsharable"] end
        return L["sheet.quests.need_group"]
    end)

    -- (a tab click or a swap from the portraits: a click, allowed to go out as SAY)
    page:SetScript("OnShow", function()
        local c = Sheet.Current()
        if c then
            ShowCompanion(c.guid)
            Request(false)
        end
    end)
    -- while he is online his progress moves: ask again now and then (in a group only)
    local elapsed = 0
    page:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < REFRESH then return end
        elapsed = 0
        if data and data.online then Request(true) end
    end)
end

Sheet.AddPage({
    key = PAGE_KEY, title = QUESTS_LABEL or L["sheet.quests.title"], order = 50,
    Build = Build,
    Update = function(_, c)
        if c.guid ~= current then
            ShowCompanion(c.guid)
            Request(false)
        end
        Render()
    end,
})

-- Opens companion `guid`'s sheet on his quests (call from a click).
function ns.ShowCompanionQuests(guid)
    if ns.FindCompanion(guid) then Sheet.Open(guid, PAGE_KEY) end
end

-- By name (party frame menu): the list may not be here yet.
function ns.ShowCompanionQuestsByName(name)
    local c = ns.FindCompanionByName(name)
    if c then ns.ShowCompanionQuests(c.guid) return end
    ns.RequestCompanions(function()
        local found = ns.FindCompanionByName(name)
        if found then ns.ShowCompanionQuests(found.guid) else ns.ShowError(L("companionsheet.not_companion", { name = name })) end
    end)
end

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

local function QuestOf(d, id)
    for _, q in ipairs(d.quests) do
        if q.id == id then return q end
    end
end

ns.On("PBQLOG", function(msg)
    local guid, kind, rest = msg:match("^PBQLOG;(%d+);(%u+);?(.*)$")
    guid = tonumber(guid)
    if not guid then return true end
    if kind == "BEGIN" then
        incoming = incoming or {}
        incoming[guid] = { online = rest == "1", quests = {} }
        return true
    end
    local d = incoming and incoming[guid]
    if not d then return true end
    if kind == "END" then
        incoming[guid] = nil
        if guid == current then
            data = d
            BuildEntries()
            if page and page:IsVisible() then Render() end
        end
    elseif kind == "Q" then
        local id, level, state, qtype, sharable, zone, header, title = strsplit(";", rest, 8)
        zone = tonumber(zone) or 0
        d.quests[#d.quests + 1] = {
            id = tonumber(id), level = tonumber(level) or 0, state = tonumber(state) or 0, type = tonumber(qtype) or 0,
            sharable = sharable == "1", header = HeaderText(zone, header), title = title or "", lines = {},
            objectives = "", description = "",
        }
    elseif kind == "O" then
        local id, okind, have, need, name = strsplit(";", rest, 5)
        local q = QuestOf(d, tonumber(id))
        if q then
            q.lines[#q.lines + 1] = { kind = okind, have = tonumber(have) or 0, need = tonumber(need) or 0, name = name or "" }
        end
    elseif kind == "T" or kind == "D" then
        local id, piece = rest:match("^(%d+);(.*)$")
        local q = id and QuestOf(d, tonumber(id))
        if q then
            local field = kind == "T" and "objectives" or "description"
            q[field] = q[field] .. piece
        end
    end
    return true
end)

-- an abandon is followed by his log; a share by the native shared quest window
ns.On("PBOK", function(msg)
    local verb = msg:match("^PBOK;[^;]*;quest(%l+);%d+$")
    if verb ~= "abandon" and verb ~= "share" then return false end
    local sound = verb == "abandon" and (SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST or SOUNDKIT.IG_QUEST_CANCEL)
    if sound then PlaySound(sound) end
    return true
end)

-- the share button follows group changes
local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    if page and page:IsVisible() then UpdateButtons() end
end)
