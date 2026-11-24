-- Talent panel: a PartyBot's three talent trees.
--   Right-click a party member's portrait -> 查看天赋, the Bags panel's 天赋 button, or /pbtal [name]
--   Left-click a talent   -> one of the free points goes there (only in the panel for now)
--   Right-click a talent  -> takes back a point given since the panel opened
--   Closing the panel     -> asks once: yes sends them all (.partybot learntalent), and they stay
--                            for good; the bot's talents can't be changed after that
-- Replies: PBTAL (listing), PBERR.

local ADDON, ns = ...
local L = ns.L

local SendCommand = ns.SendCommand

local ICON_SIZE = 32
local STEP = 42
local COLUMNS = 4
local ROWS = 7
local PADDING = 14
local HEADER = 62          -- title + free points line
local TREE_HEADER = 24     -- tree name line inside each tree
local TREE_WIDTH = COLUMNS * STEP + 16
local TREE_HEIGHT = TREE_HEADER + ROWS * STEP + 8
local FOOTER = 40
local POINTS_PER_ROW = 5
local MAX_COMMAND = 240    -- chat line limit is 255

local TREE_NAMES = ns.TREE_NAMES
local CONFIRM = "PARTYBOT_TALENTS_CONFIRM"

-- state
local currentName   -- bot shown in the panel
local receiving     -- name we are receiving PBTAL lines for
local incoming
local data          -- { class, level, free, trees = { [0..2] = { talent, ... } }, byId = { [id] = talent } }
local pending = {}  -- [talentId] = points given in the panel, not sent yet
local pendingCount = 0

local function NewData()
    return { trees = { [0] = {}, [1] = {}, [2] = {} }, byId = {} }
end

local function ClearPending()
    pending = {}
    pendingCount = 0
end

local function RequestTalents(name)
    if name then SendCommand(".partybot talents " .. name) end
end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PartyBotTalentsFrame", UIParent, "BackdropTemplate")
frame:SetSize(PADDING * 2 + TREE_WIDTH * 3 + 16, HEADER + TREE_HEIGHT + FOOTER)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
tinsert(UISpecialFrames, "PartyBotTalentsFrame") -- Esc closes it

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.title:SetPoint("TOP", 0, -18)

frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
frame.close:SetPoint("TOPRIGHT", -6, -6)

frame.points = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.points:SetPoint("TOPLEFT", PADDING + 4, -42)

frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.hint:SetPoint("TOPRIGHT", -PADDING - 4, -44)

frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
frame.status:SetPoint("CENTER")

frame.notice = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.notice:SetPoint("BOTTOMLEFT", PADDING + 6, 20)

local INNER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local trees = {}
for tab = 0, 2 do
    local t = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    t:SetSize(TREE_WIDTH, TREE_HEIGHT)
    t:SetPoint("TOPLEFT", PADDING + 4 + tab * (TREE_WIDTH + 4), -HEADER)
    t:SetBackdrop(INNER_BACKDROP)
    t:SetBackdropColor(0, 0, 0, 0.6)
    t.name = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t.name:SetPoint("TOP", 0, -7)
    trees[tab] = t
end

-- closing asks (OnHide below)
frame.done = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
frame.done:SetSize(90, 22)
frame.done:SetText(L["talents.done"])
frame.done:SetPoint("BOTTOMRIGHT", -PADDING - 4, 14)
frame.done:SetScript("OnClick", function() frame:Hide() end)

---------------------------------------------------------------------------
-- talent rules (same as the server's LearnTalent), on the ranks with the panel's points
---------------------------------------------------------------------------

local function Rank(t)
    return t.rank + (pending[t.id] or 0)
end

local function FreePoints()
    return data.free - pendingCount
end

local function TreePoints(tab, rankOf)
    rankOf = rankOf or Rank
    local points = 0
    for _, t in ipairs(data.trees[tab]) do points = points + rankOf(t) end
    return points
end

-- nil if the talent can take a point now, else the reason
local function LearnBlocker(t, rankOf)
    rankOf = rankOf or Rank
    if rankOf(t) >= t.max then return "maxrank" end
    if TreePoints(t.tab, rankOf) < t.row * POINTS_PER_ROW then return "tier" end
    local dep = t.dep > 0 and data.byId[t.dep]
    if dep and rankOf(dep) < t.depRank + 1 then return "dep" end
end

-- nil if one of the panel's points can come off the talent, else the reason
local function TakeBackBlocker(t)
    if (pending[t.id] or 0) <= 0 then return "notpending" end
    local function after(x) return Rank(x) - (x == t and 1 or 0) end
    local rows = {}
    for _, other in ipairs(data.trees[t.tab]) do
        local rank = after(other)
        if rank > 0 then
            if other.dep == t.id and after(t) < other.depRank + 1 then return "dependent" end
            rows[other.row] = (rows[other.row] or 0) + rank
        end
    end
    for _, other in ipairs(data.trees[t.tab]) do
        if after(other) > 0 then
            local above = 0
            for row, points in pairs(rows) do
                if row < other.row then above = above + points end
            end
            if above < other.row * POINTS_PER_ROW then return "tier" end
        end
    end
end

local function TalentName(t)
    return (GetSpellInfo(t.spells[1])) or L("talents.unnamed", { id = t.id })
end

---------------------------------------------------------------------------
-- sending the panel's points
---------------------------------------------------------------------------

-- "<id>x<count>" tokens in an order the server can learn them: a talent goes once its tier and
-- required talent are reached (the player gave the points in some such order, so one exists)
local function LearnOrder()
    local sent = {}
    local function rankOf(t) return t.rank + (sent[t.id] or 0) end
    local tokens = {}
    local progress = true
    while progress do
        progress = false
        for tab = 0, 2 do
            for _, t in ipairs(data.trees[tab]) do
                local left = (pending[t.id] or 0) - (sent[t.id] or 0)
                if left > 0 and not LearnBlocker(t, rankOf) then
                    sent[t.id] = (sent[t.id] or 0) + left
                    tokens[#tokens + 1] = left > 1 and ("%dx%d"):format(t.id, left) or tostring(t.id)
                    progress = true
                end
            end
        end
    end
    return tokens
end

local function Commit()
    if not data or not currentName or pendingCount <= 0 then return end
    local prefix = ".partybot learntalent " .. currentName
    local line = prefix
    for _, token in ipairs(LearnOrder()) do
        if #line + 1 + #token > MAX_COMMAND then
            SendCommand(line)
            line = prefix
        end
        line = line .. " " .. token
    end
    if line ~= prefix then SendCommand(line) end
    ClearPending()
end

---------------------------------------------------------------------------
-- talent buttons
---------------------------------------------------------------------------

local buttons = {}
local Render

local function OnTalentEnter(self)
    local t = self.talent
    if not t then return end
    local rank = Rank(t)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = t.spells[math.max(rank, 1)]
    if shown then GameTooltip:SetSpellByID(shown) end
    GameTooltip:AddLine(L("talents.tip.rank", { rank = rank, max = t.max }), 1, 1, 1)

    if rank > 0 and rank < t.max and GetSpellDescription then
        local nextText = GetSpellDescription(t.spells[rank + 1])
        if nextText and nextText ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["talents.tip.next"], 1, 1, 1)
            GameTooltip:AddLine(nextText, 1, 0.82, 0, true)
        end
    end

    local blocker = LearnBlocker(t)
    if blocker == "tier" then
        GameTooltip:AddLine(L("talents.tip.need_tier", { tree = TREE_NAMES[data.class] and TREE_NAMES[data.class][t.tab + 1] or "", points = t.row * POINTS_PER_ROW }), 1, 0.1, 0.1)
    elseif blocker == "dep" then
        local dep = data.byId[t.dep]
        GameTooltip:AddLine(L("talents.tip.need_dep", { points = t.depRank + 1, talent = TalentName(dep) }), 1, 0.1, 0.1)
    end

    local canLearn = not blocker and FreePoints() > 0
    local pendingHere = pending[t.id] or 0
    if canLearn or pendingHere > 0 then GameTooltip:AddLine(" ") end
    if canLearn then
        GameTooltip:AddLine(L["talents.tip.learn"], 0, 1, 0)
    end
    if pendingHere > 0 then
        GameTooltip:AddLine(L("talents.tip.takeback", { points = pendingHere }), 0, 1, 0)
    end
    GameTooltip:Show()
end

local function OnTalentClick(self, button)
    local t = self.talent
    if not t or not currentName or not data then return end
    if button == "LeftButton" then
        local blocker = LearnBlocker(t) or (FreePoints() <= 0 and "nopoints")
        if blocker then
            ns.ShowError(ns.ERROR_TEXT[blocker] or ns.ERROR_TEXT.talentreq)
            return
        end
        pending[t.id] = (pending[t.id] or 0) + 1
        pendingCount = pendingCount + 1
    elseif button == "RightButton" then
        local blocker = TakeBackBlocker(t)
        if blocker == "notpending" then
            if t.rank > 0 then ns.ShowError(L["talents.err.fixed"]) end
            return
        elseif blocker then
            ns.ShowError(ns.ERROR_TEXT[blocker])
            return
        end
        pending[t.id] = pending[t.id] - 1
        if pending[t.id] == 0 then pending[t.id] = nil end
        pendingCount = pendingCount - 1
    else
        return
    end
    PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    Render()
    if GameTooltip:IsOwned(self) then OnTalentEnter(self) end
end

local function GetButton(i)
    local b = buttons[i]
    if b then return b end

    b = CreateFrame("Button", nil, frame)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()

    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.border:SetBlendMode("ADD")
    b.border:SetPoint("CENTER")
    b.border:SetSize(ICON_SIZE * 1.8, ICON_SIZE * 1.8)

    b.rankBg = b:CreateTexture(nil, "OVERLAY")
    b.rankBg:SetColorTexture(0, 0, 0, 0.75)
    b.rankBg:SetSize(26, 12)
    b.rankBg:SetPoint("BOTTOMRIGHT", 6, -4)

    b.rank = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", OnTalentEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", OnTalentClick)

    buttons[i] = b
    return b
end

---------------------------------------------------------------------------
-- render
---------------------------------------------------------------------------

function Render()
    for _, b in pairs(buttons) do b:Hide() end
    frame.title:SetText(L("talents.title", { name = currentName or "" }))

    local ready = data and data.class
    frame.status:SetText(ready and "" or L["talents.loading"])
    for tab = 0, 2 do trees[tab]:SetShown(ready) end
    frame.hint:SetText(L["talents.hint"])
    if not ready then
        frame.points:SetText("")
        frame.notice:SetText("")
        return
    end

    local free = FreePoints()
    local used = 0
    for tab = 0, 2 do used = used + TreePoints(tab) end
    local freeColor = free > 0 and "|cff20ff20" or "|cffffffff"
    frame.points:SetText(L("talents.points", { level = data.level, used = used, color = freeColor, free = free }))
    frame.notice:SetText(pendingCount > 0 and L("talents.pending", { points = pendingCount }) or "")

    local names = TREE_NAMES[data.class] or {}
    local index = 0
    for tab = 0, 2 do
        local tree = trees[tab]
        tree.name:SetText(("%s (%d)"):format(names[tab + 1] or L("talents.unnamed", { id = tab + 1 }), TreePoints(tab)))

        for _, t in ipairs(data.trees[tab]) do
            index = index + 1
            local b = GetButton(index)
            b.talent = t
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", tree, "TOPLEFT", 12 + t.col * STEP, -TREE_HEADER - 4 - t.row * STEP)
            b.icon:SetTexture(GetSpellTexture(t.spells[1]) or "Interface\\Icons\\INV_Misc_QuestionMark")

            local rank = Rank(t)
            local blocker = LearnBlocker(t)
            local canLearn = blocker == nil and free > 0
            -- like the Blizzard talent frame: gold = full, green = can take more, grey = locked
            local usable = rank > 0 or blocker == nil
            b.icon:SetDesaturated(not usable)
            b.icon:SetVertexColor(usable and 1 or 0.6, usable and 1 or 0.6, usable and 1 or 0.6)
            b.rank:SetText(rank .. "/" .. t.max)
            if rank >= t.max then
                b.rank:SetTextColor(1, 0.82, 0)
                b.border:SetVertexColor(1, 0.82, 0)
                b.border:Show()
            elseif canLearn then
                b.rank:SetTextColor(0.1, 1, 0.1)
                b.border:SetVertexColor(0.1, 1, 0.1)
                b.border:Show()
            elseif rank > 0 then
                b.rank:SetTextColor(0.1, 1, 0.1)
                b.border:Hide()
            else
                b.rank:SetTextColor(0.5, 0.5, 0.5)
                b.border:Hide()
            end
            b:Show()
        end
    end
end

---------------------------------------------------------------------------
-- closing: the points given in the panel are asked about once, then stay
---------------------------------------------------------------------------

StaticPopupDialogs[CONFIRM] = {
    text = "%s",            -- L("talents.confirm"), filled in by OnHide
    button1 = L["talents.confirm.yes"],
    button2 = L["talents.confirm.back"],
    button3 = L["talents.confirm.discard"],
    OnAccept = function() Commit() end,
    OnCancel = function() frame:Show() end,     -- also Esc: back to the panel
    OnAlt = function() ClearPending() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

frame:SetScript("OnHide", function(self)
    if self:IsShown() then return end   -- only UIParent was hidden (Alt+Z)
    if pendingCount > 0 and currentName then
        StaticPopup_Show(CONFIRM, L("talents.confirm", { name = currentName, points = pendingCount }))
    end
end)

---------------------------------------------------------------------------
-- open
---------------------------------------------------------------------------

-- Call from a click or slash command (the request goes out as SAY outside a group).
function ns.ShowTalents(name)
    if not name or name == "" then return end
    if StaticPopup_Visible(CONFIRM) then return end     -- answer the question first
    if pendingCount > 0 then
        if name ~= currentName then
            frame:Hide()        -- asks about the points given to the bot shown now
        else
            frame:Show()
        end
        return
    end
    if name ~= currentName then data = nil end
    currentName = name
    frame:Show()
    Render()
    RequestTalents(name)
end

local function ToggleForTarget()
    if frame:IsShown() then
        frame:Hide()
        return
    end
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
        ns.ShowTalents(UnitName("target"))
    elseif currentName then
        ns.ShowTalents(currentName)
    else
        ns.ShowError(L["talents.err.notarget"])
    end
end

SLASH_PARTYBOTTALENTS1 = "/pbtal"
SlashCmdList.PARTYBOTTALENTS = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    if msg ~= "" then ns.ShowTalents(msg) else ToggleForTarget() end
end


---------------------------------------------------------------------------
-- unit right-click menu: 查看天赋 for party / raid members
---------------------------------------------------------------------------

if UnitPopup_ShowMenu and UIDropDownMenu_AddButton then
    hooksecurefunc("UnitPopup_ShowMenu", function(_, which, unit, name)
        if UIDROPDOWNMENU_MENU_LEVEL ~= 1 or which == "SELF" then return end
        local who = unit or name
        if not who or not (UnitInParty(who) or UnitInRaid(who)) or UnitIsUnit(who, "player") then return end
        local botName = unit and UnitName(unit) or name
        if not botName then return end

        local info = UIDropDownMenu_CreateInfo()
        info.text = L["talents.menu.view"]
        info.notCheckable = true
        info.func = function() ns.ShowTalents(botName) end
        UIDropDownMenu_AddButton(info, 1)
    end)
end

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

local function ParseSpells(text)
    local spells = {}
    for id in (text or ""):gmatch("%d+") do spells[#spells + 1] = tonumber(id) end
    return spells
end

-- PBTAL;<name>;BEGIN;<class>;<level>;<free>;<debug> | T;<tab>;<id>;<row>;<col>;<rank>;<max>;<dep>;<depRank>;<spells> | END
ns.On("PBTAL", function(msg)
    local _, name, kind, a, b, c, d, e, f, g, h, i = strsplit(";", msg)
    if kind == "BEGIN" then
        receiving = name
        incoming = NewData()
        incoming.class, incoming.level, incoming.free = tonumber(a), tonumber(b) or 0, tonumber(c) or 0
    elseif kind == "T" and receiving == name and incoming then
        local t = {
            tab = tonumber(a) or 0, id = tonumber(b), row = tonumber(c) or 0, col = tonumber(d) or 0,
            rank = tonumber(e) or 0, max = tonumber(f) or 1, dep = tonumber(g) or 0, depRank = tonumber(h) or 0,
            spells = ParseSpells(i),
        }
        if incoming.trees[t.tab] and t.id then
            table.insert(incoming.trees[t.tab], t)
            incoming.byId[t.id] = t
        end
    elseif kind == "END" and receiving == name then
        receiving = nil
        if name == currentName then
            data = incoming
            ClearPending()      -- the panel's points were counted against the old listing
            if frame:IsShown() then Render() end
        end
        incoming = nil
    end
end)

-- not a bot (menu entry on a real player): close the panel, Core shows the error
ns.On("PBERR", function(msg)
    local name, code = msg:match("^PBERR;([^;]*);([^;]*)")
    if (code == "notbot" or code == "notfound") and name == currentName and not data then
        frame:Hide()
        currentName = nil
    end
end)
