-- Requests: a companion asks the player something (soul companions doc §5).
-- PBREQ;<bot>;<id>;open;<intent>;<timeoutSec>;<race:gender:class>;<key=label,key=label>;<text>
-- PBREQ;<bot>;<id>;turn;<timeoutSec>     (a queued question's clock starts: timeoutSec 0 in its open line)
-- PBREQ;<bot>;<id>;close;<answer>
-- PBREQ;<bot>;<id>;note;<tier>;<text>   (after the open line: a line under the question, popup only;
--                                         tier 1-6 = the trainer's lesson tiers, 0 = plain)
-- A label "item:<id>[:<count>]" is a reward item, shown in the client's language with its tooltip.
-- The player's click sends ".partybot reply <id> <key>". No click: the server takes the
-- request's fallback when the timeout passes, the dialog closes by itself.
--
-- The dialog is the shared dialog page (DialogPage.lua: portrait, parchment, letter by letter).
-- This file adds the queue (more pages behind while others wait to speak), the notes under the
-- question and the time left (a fuse along the bottom).

local _, ns = ...
local L = ns.L
local Dialog = ns.DialogPage

ns.ERROR_TEXT.notyours = L["requests.err.notyours"]
ns.ERROR_TEXT.badoption = L["requests.err.badoption"]
ns.ERROR_TEXT.notcompanion = L["requests.err.notcompanion"]

local queue = {}    -- open requests, oldest first: { id, bot, intent, race, gender, class, text, options = { {key, label} }, untilTime, totalTime }

local INK, INK_SOFT, GOLD = Dialog.INK, Dialog.INK_SOFT, Dialog.GOLD
local COLUMN_X, COLUMN_W, PAD = Dialog.COLUMN_X, Dialog.COLUMN_W, Dialog.PAD
local Font, Play = Dialog.Font, Dialog.Play
local URGENT_SEC = 5

local d = Dialog.Create("PartyBotRequestFrame")
local frame, page = d.frame, d.page

-- more pages behind this one while others are waiting to speak
local stack = {}
for i = 2, 1, -1 do
    local s = CreateFrame("Frame", nil, frame, Dialog.TEMPLATE)
    s:SetFrameLevel(frame:GetFrameLevel() + 3 - i)
    s:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 * i, -6 * i)
    s:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6 * i, -6 * i)
    Dialog.Paper(s, 0.78 - 0.12 * i)
    if s.SetBackdrop then
        Dialog.GoldBorder(s, Dialog.DIALOG_EDGE, 26, 8)
        s:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)    -- the gold border, dimmed behind
    end
    s:Hide()
    stack[i] = s
end

-- the notes under the question (lessons by tier, money), shown with the answers
local notes = page:CreateFontString(nil, "OVERLAY", Font("QuestFontNormalSmall", "GameFontHighlightSmall"))
notes:SetPoint("TOPLEFT", d.text, "BOTTOMLEFT", 0, -8)
notes:SetWidth(COLUMN_W)
notes:SetJustifyH("LEFT")
notes:SetSpacing(2)
notes:SetShadowColor(0, 0, 0, 0)
notes:SetTextColor(INK[1], INK[2], INK[3])
notes:Hide()

-- dark enough to read on parchment; one line per tier (Life/Errands/Trip/LessonPriority.h)
local NOTE_TIERS = {
    [1] = { label = L["requests.tier.1"], color = { 0.05, 0.25, 0.60 } },
    [2] = { label = L["requests.tier.2"], color = { 0.42, 0.10, 0.55 } },
    [3] = { label = L["requests.tier.3"], color = { 0.05, 0.42, 0.08 } },
    [4] = { label = L["requests.tier.4"], color = { 0.62, 0.32, 0.02 } },
    [5] = { label = L["requests.tier.5"], color = INK },
    [6] = { label = L["requests.tier.6"], color = { 0.45, 0.42, 0.38 } },
}

local function Hex(c)
    return string.format("ff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function NotesText(r)
    if not r or not r.notes or #r.notes == 0 then return nil end
    local byTier, plain = {}, {}
    for _, n in ipairs(r.notes) do
        if NOTE_TIERS[n.tier] then
            byTier[n.tier] = byTier[n.tier] or {}
            table.insert(byTier[n.tier], n.text)
        else
            table.insert(plain, n.text)
        end
    end
    local lines = {}
    for tier = 1, 6 do
        local names = byTier[tier]
        if names then
            local t = NOTE_TIERS[tier]
            table.insert(lines, "|c" .. Hex(t.color) .. L("requests.note_line", { label = t.label, names = table.concat(names, L["requests.list_sep"]) }) .. "|r")
        end
    end
    for _, p in ipairs(plain) do
        table.insert(lines, "|c" .. Hex(INK_SOFT) .. p .. "|r")
    end
    return table.concat(lines, "\n")
end

-- the time left: a thin fuse along the bottom of the page
local fuse = CreateFrame("StatusBar", nil, page)
fuse:SetHeight(4)
fuse:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", COLUMN_X, 22)
fuse:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 4, 22)
fuse:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
fuse:SetMinMaxValues(0, 1)
local fuseBg = fuse:CreateTexture(nil, "BACKGROUND")
fuseBg:SetAllPoints()
fuseBg:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.25)

local timer = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timer:SetPoint("BOTTOMRIGHT", fuse, "TOPRIGHT", 0, 3)
timer:SetShadowColor(0, 0, 0, 0)
timer:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])

local waiting = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
waiting:SetPoint("BOTTOMLEFT", fuse, "TOPLEFT", 0, 3)
waiting:SetShadowColor(0, 0, 0, 0)
waiting:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])

---------------------------------------------------------------------------
-- answers
---------------------------------------------------------------------------

local function ItemOf(label)
    local id, count = label:match("^item:(%d+):?(%d*)$")
    if not id then return nil end
    return tonumber(id), tonumber(count)
end

-- a yes / no question (keys as the server sends them, RequestBoard.h): tick and cross; other
-- answers (several choices) keep the speech bubble
local ANSWER_LOOK = ns.DialogPage.ANSWER_LOOK

-- item names in a darker shade of their quality colour so they read on parchment
local function LabelText(label)
    local id, count = ItemOf(label)
    if not id then return label, INK end
    local itemName, _, quality = GetItemInfo(id)
    local shown = itemName or ns.ItemName(id)
    if count and count > 1 then shown = shown .. " x" .. count end
    local c = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c then return shown, { c.r * 0.55, c.g * 0.55, c.b * 0.55 } end
    return shown, INK
end

local function Remove(id)
    for i, r in ipairs(queue) do
        if r.id == id then table.remove(queue, i) return true end
    end
    return false
end

local Render

local function Answers(r)
    local list = {}
    for _, o in ipairs(r.options) do
        local itemId = ItemOf(o.label)
        local shown, color = LabelText(o.label)
        local a = { label = shown, color = color, itemId = itemId }
        if itemId then
            a.iconSize = 20
            a.icon = GetItemIcon and GetItemIcon(itemId) or "Interface\\Icons\\INV_Misc_QuestionMark"
        else
            local look = ANSWER_LOOK[o.key]
            a.icon = look and look.icon or "Interface\\GossipFrame\\GossipGossipIcon"
            if look then a.color = look.color end
        end
        a.onClick = function()
            Play("IG_QUEST_LIST_SELECT")
            ns.SendCommand(".partybot reply " .. r.id .. " " .. o.key)
            Remove(r.id)
            Render()
        end
        list[#list + 1] = a
    end
    return list
end

---------------------------------------------------------------------------
-- showing one request
---------------------------------------------------------------------------

local current            -- the request on the page

d.LayoutExtra = function(_, top)
    local noteText = NotesText(current)
    notes:SetText(noteText or "")
    if noteText then
        notes:SetShown(not d.revealing)
        return top + notes:GetStringHeight() + 8
    end
    notes:Hide()
    return top
end

d.OnRevealDone = function()
    if NotesText(current) then notes:Show() end
end

local function Waiting()
    local others = #queue - (current and 1 or 0)
    waiting:SetText(others > 0 and L("requests.waiting", { count = others }) or "")
    for i, s in ipairs(stack) do s:SetShown(others >= i) end
end

local function Show(r)
    current = r
    d:Begin({ bot = r.bot, race = r.race, gender = r.gender, class = r.class }, r.text)
    d:SetAnswers(Answers(r))
    Waiting()
end

-- after the page fades out: the next speaker, or nothing
d.OnGone = function()
    current = nil
    if queue[1] then
        Show(queue[1])
    else
        Play("IG_QUEST_LIST_CLOSE")
    end
end

Render = function()
    local r = queue[1]
    if r ~= current then
        if current and frame:IsShown() then d:Dismiss()
        elseif r then Show(r)
        end
        return
    end
    if r then
        d:SetAnswers(Answers(r))
        Waiting()
    end
end

d.OnItemInfo = function() Render() end

local acc = 0
d.OnTick = function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.1 then return end
    acc = 0

    local now = GetTime()
    local changed = false
    for i = #queue, 1, -1 do
        local untilTime = queue[i].untilTime
        if untilTime and untilTime <= now then table.remove(queue, i) changed = true end
    end
    if changed then Render() end

    local r = current
    if r and d.phase ~= "out" and not r.untilTime then
        -- its turn line is on the way (the earlier question was just answered): a full fuse
        fuse:SetValue(1)
        fuse:SetStatusBarColor(0.80, 0.56, 0.16)
        timer:SetText("")
    elseif r and d.phase ~= "out" then
        local left = math.max(0, r.untilTime - now)
        fuse:SetValue(r.totalTime > 0 and left / r.totalTime or 0)
        if left <= URGENT_SEC then
            fuse:SetStatusBarColor(0.75, 0.15, 0.08)
            timer:SetTextColor(0.6, 0.1, 0.05)
        else
            fuse:SetStatusBarColor(0.80, 0.56, 0.16)
            timer:SetTextColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3])
        end
        timer:SetText(L("requests.seconds", { seconds = math.ceil(left) }))
    end
end

---------------------------------------------------------------------------
-- server lines
---------------------------------------------------------------------------

-- the server runs one question's clock at a time per player: a queued question gets its
-- timeout when its turn comes
local function StartClock(request, seconds)
    request.untilTime = GetTime() + seconds
    request.totalTime = seconds
end

ns.On("PBREQ", function(msg)
    local turnId, turnSec = msg:match("^PBREQ;[^;]*;(%d+);turn;(%d+)")
    if turnId then
        for _, r in ipairs(queue) do
            if r.id == tonumber(turnId) then StartClock(r, tonumber(turnSec)) break end
        end
        return true
    end

    local bot, id, intent, timeout, looks, options, question =
        msg:match("^PBREQ;([^;]*);(%d+);open;([^;]*);(%d+);([^;]*);([^;]*);(.*)$")
    if bot then
        local race, gender, class = looks:match("^(%d+):(%d+):(%d+)$")
        local request = {
            id = tonumber(id), bot = bot, intent = intent, text = question,
            race = tonumber(race), gender = tonumber(gender), class = tonumber(class),
            options = {}, totalTime = 0,    -- untilTime nil: waits its turn
        }
        if tonumber(timeout) > 0 then StartClock(request, tonumber(timeout)) end
        for pair in options:gmatch("[^,]+") do
            local key, label = pair:match("^([^=]*)=(.*)$")
            if key and key ~= "" then
                table.insert(request.options, { key = key, label = label ~= "" and label or key })
                local itemId = ItemOf(label or "")
                if itemId then GetItemInfo(itemId) end    -- asks the server, GET_ITEM_INFO_RECEIVED re-renders
            end
        end
        Remove(request.id)
        table.insert(queue, request)
        if #queue > 1 then Play("TELL_MESSAGE") end   -- someone else is waiting to speak
        Render()
        return true
    end

    local noteId, noteTier, noteText = msg:match("^PBREQ;[^;]*;(%d+);note;(%d+);(.*)$")
    if noteId then
        for _, r in ipairs(queue) do
            if r.id == tonumber(noteId) then
                r.notes = r.notes or {}
                table.insert(r.notes, { tier = tonumber(noteTier), text = noteText })
                if r == current then d:Relayout() end
                break
            end
        end
        return true
    end

    local closedId = msg:match("^PBREQ;[^;]*;(%d+);close;")
    if closedId then
        if Remove(tonumber(closedId)) then Render() end
        return true
    end
end)

-- the reply's echo
ns.On("PBOK", function(msg)
    return msg:match("^PBOK;;reply;") ~= nil
end)
