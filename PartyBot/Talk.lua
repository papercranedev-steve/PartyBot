-- Talking to a companion like to an NPC (design .kiro/docs/2026-11-21-companion-talk.md §1).
-- Walk up to him and open it (party unit menu or the companions list "交谈", or the key binding
-- "与目标伙伴交谈"): he turns to you, greets you, and below are the things he can do for you now.
-- The window is the dialog page of his requests (DialogPage.lua). What is offered is the
-- server's (Companions/Talk services); this file only draws it.
--
-- .partybot talk <bot>          PBTALK;<bot>;BEGIN;<race:gender:class>;<words>
--                               PBTALK;<bot>;OPT;<id>;<icon key>;<price copper>;<your words>
--                               PBTALK;<bot>;END
--                               PBTALK;<bot>;BUSY;<words>   (he or you fight)    PBERR;<bot>;far
-- .partybot talk <bot> <id>     a new page, PBTALK;<bot>;CLOSE, or PBTALK;<bot>;OPEN;<window>;<arg>
--
-- It closes when you walk away (a little more than the server's 10 yd), on ESC and on "再见".

local _, ns = ...
local L = ns.L
local Dialog = ns.DialogPage

ns.ERROR_TEXT.far = L["talk.err.far"]
ns.ERROR_TEXT.notgroup = L["talk.err.notgroup"]
ns.ERROR_TEXT.notbot = L["talk.err.notbot"]

local Play = Dialog.Play
local INK_SOFT = Dialog.INK_SOFT

-- the native gossip icons, by the server's keys (Companions/Talk/TalkService.h); folder: a
-- sub-page of options (互动, 队伍), the guild master's scroll, so it stands apart from talk
local ICONS = {
    chat    = "Interface\\GossipFrame\\GossipGossipIcon",
    vendor  = "Interface\\GossipFrame\\VendorGossipIcon",
    taxi    = "Interface\\GossipFrame\\TaxiGossipIcon",
    trainer = "Interface\\GossipFrame\\TrainerGossipIcon",
    binder  = "Interface\\GossipFrame\\BinderGossipIcon",
    banker  = "Interface\\GossipFrame\\BankerGossipIcon",
    folder  = "Interface\\GossipFrame\\PetitionGossipIcon",
}
-- yes / no answers: tick and cross, as the request dialog's
for key, look in pairs(Dialog.ANSWER_LOOK) do ICONS[key] = look.icon end

local CHECK_SEC = 0.3
-- CheckInteractDistance index 2: trade range (11.1 yd), a little more than the server's 10 yd;
-- someone not of your party (a stranger, Population/StrangerTalk: 30 yd): index 4, follow (28 yd)
local TALK_RANGE_INDEX = 2
local MEET_RANGE_INDEX = 4

local d = Dialog.Create("PartyBotTalkFrame")
tinsert(UISpecialFrames, "PartyBotTalkFrame")    -- ESC closes it

local talk          -- the page on screen: { bot, race, gender, class, text, options }
local incoming      -- a page coming in (BEGIN .. END)
local waiting       -- an option was picked, his answer is on the way

local function Close()
    if d.frame:IsShown() then d:Dismiss() end
end

d.OnGone = function()
    talk, waiting = nil, nil
    Play("IG_QUEST_LIST_CLOSE")
end

local function Answers(page)
    local list = {}
    for _, o in ipairs(page.options) do
        list[#list + 1] = {
            label = o.text, icon = ICONS[o.icon] or ICONS.chat, price = o.price,
            color = Dialog.ANSWER_LOOK[o.icon] and Dialog.ANSWER_LOOK[o.icon].color,
            onClick = function()
                if waiting then return end
                waiting = true
                Play("IG_QUEST_LIST_SELECT")
                ns.SendCommand(".partybot talk " .. page.bot .. " " .. o.id)
            end,
        }
    end
    -- the last line, as a player would end it
    list[#list + 1] = {
        label = L["talk.goodbye"], icon = ICONS.chat, color = INK_SOFT,
        onClick = function() Close() end,
    }
    return list
end

local function ShowPage(page)
    talk, waiting = page, nil
    d:Begin({ bot = page.bot, race = page.race, gender = page.gender, class = page.class }, page.text)
    d:SetAnswers(Answers(page))
end

-- Opens the talk window with `name` (from a click or a key press: it may go out as SAY).
function ns.Talk(name)
    if not name or name == "" then return end
    if talk and talk.bot == name and d:IsOpen() then return end
    ns.SendCommand(".partybot talk " .. name)
end

-- the key binding (Bindings.xml): the one you target, a companion or someone you met
-- (people of the world talk too, recruiting doc §2.1)
function PartyBot_TalkToTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then
        ns.ShowError(L["talk.err.notarget"])
        return
    end
    if not (UnitInParty("target") or UnitInRaid("target")) and not CheckInteractDistance("target", TALK_RANGE_INDEX) then
        ns.ShowError(ns.ERROR_TEXT.far)
        return
    end
    ns.Talk(UnitName("target"))
end

BINDING_HEADER_PARTYBOT = "PartyBot"
BINDING_NAME_PARTYBOT_TALK = L["talk.binding"]

-- First login of a character with the addon: if the talk binding has no key, it gets F, else E,
-- when that key is free or still on Blizzard's default action (F assist, E strafe right); a key
-- the player set himself is not taken. Once per character (PartyBotDB.talkKeyCheck2[guid]),
-- so a key the player removes later stays removed.
local DEFAULT_TALK_KEYS = {
    { key = "F", blizzard = "ASSISTTARGET" },
    { key = "E", blizzard = "STRAFERIGHT" },
}

local function BindTalkKey()
    local guid = UnitGUID("player")
    ns.db.talkKeyCheck2 = ns.db.talkKeyCheck2 or {}
    if ns.db.talkKeyCheck2[guid] then return end
    ns.db.talkKeyCheck2[guid] = true
    if GetBindingKey("PARTYBOT_TALK") then return end
    for _, k in ipairs(DEFAULT_TALK_KEYS) do
        local action = GetBindingAction(k.key) or ""
        if action == "" or action == k.blizzard then
            if SetBinding(k.key, "PARTYBOT_TALK") then
                SaveBindings(GetCurrentBindingSet())
                if action == "" then
                    print(L("talk.key_bound", { key = k.key }))
                else
                    print(L("talk.key_replaced", { key = k.key, old = _G["BINDING_NAME_" .. action] or action }))
                end
            end
            return
        end
    end
end

local bindEvents = CreateFrame("Frame")
bindEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
bindEvents:SetScript("OnEvent", function(self, event)
    -- (key bindings cannot change in combat: after it)
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self:UnregisterAllEvents()
    ns.OnLoad(BindTalkKey)
end)

-- walked away: it closes, as an NPC's gossip does
local sinceCheck = 0
d.OnTick = function(_, elapsed)
    if not talk or not d:IsOpen() then return end
    sinceCheck = sinceCheck + elapsed
    if sinceCheck < CHECK_SEC then return end
    sinceCheck = 0
    local unit = ns.UnitOf(talk.bot)
    -- (someone not of the party may not be on any unit token: the server checks on a click)
    if not unit then
        if UnitInParty(talk.bot) or UnitInRaid(talk.bot) then Close() end
        return
    end
    local member = UnitInParty(unit) or UnitInRaid(unit)
    if not CheckInteractDistance(unit, member and TALK_RANGE_INDEX or MEET_RANGE_INDEX) then Close() end
end

---------------------------------------------------------------------------
-- windows a service opens (the talk window closes first)
---------------------------------------------------------------------------

ns.talkWindows = ns.talkWindows or {}

-- his bags: his sheet with the bags panel (Bags.lua)
ns.talkWindows.bags = function(bot)
    ns.ShowBags(bot)
end

-- 互动 (server LookService): his sheet, talents, quest log, as the unit menu opens them
ns.talkWindows.sheet = function(bot)
    local c = ns.FindCompanionByName(bot)
    if c then ns.Sheet.Open(c.guid) else ns.Sheet.OpenByName(bot) end
end
ns.talkWindows.talents = function(bot)
    ns.ShowTalents(bot)
end
ns.talkWindows.quests = function(bot)
    local c = ns.FindCompanionByName(bot)
    if c then ns.ShowCompanionQuests(c.guid) else ns.ShowCompanionQuestsByName(bot) end
end

---------------------------------------------------------------------------
-- server lines
---------------------------------------------------------------------------

ns.On("PBTALK", function(msg)
    local _, bot, kind, a, b, c, rest = strsplit(";", msg, 7)
    if kind == "BEGIN" then
        -- (fields: a = looks, then the words may hold ';')
        local looks, words = msg:match("^PBTALK;[^;]*;BEGIN;([^;]*);(.*)$")
        local race, gender, class = (looks or ""):match("^(%d+):(%d+):(%d+)$")
        incoming = { bot = bot, race = tonumber(race), gender = tonumber(gender), class = tonumber(class),
                     text = words or "", options = {} }
    elseif kind == "OPT" and incoming and incoming.bot == bot then
        local id, icon, price, words = msg:match("^PBTALK;[^;]*;OPT;([^;]*);([^;]*);(%d+);(.*)$")
        if id then
            incoming.options[#incoming.options + 1] = { id = id, icon = icon, price = tonumber(price) or 0, text = words }
        end
    elseif kind == "END" and incoming and incoming.bot == bot then
        local page = incoming
        incoming = nil
        ShowPage(page)
    elseif kind == "CLOSE" then
        if talk and talk.bot == bot then Close() end
    elseif kind == "OPEN" then
        if talk and talk.bot == bot then Close() end
        local open = ns.talkWindows[a or ""]
        if open then open(bot, b) end
    elseif kind == "BUSY" then
        local words = msg:match("^PBTALK;[^;]*;BUSY;(.*)$") or ""
        if talk and talk.bot == bot then Close() end
        ns.ShowError(L("talk.busy", { name = bot, words = words }))
    end
    return true
end)

-- he is gone, dead or far: the window closes with the error on screen (Core shows PBERR)
ns.On("PBERR", function(msg)
    local bot = msg:match("^PBERR;([^;]*);")
    if talk and bot == talk.bot then
        waiting = nil
        if msg:match("^PBERR;[^;]*;far") or msg:match("^PBERR;[^;]*;dead") or msg:match("^PBERR;[^;]*;notfound") then
            Close()
        end
    end
    return false
end)
