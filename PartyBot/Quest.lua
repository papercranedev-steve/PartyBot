-- Quest messages: bots taking the player's quests and getting copies of quest drops.
-- PBQUEST;<bot>;accept;<questId>;<title>
-- PBQUEST;<bot>;skip;<questId>;<reason>;<title>
-- PBQUEST;<bot>;item;<itemId>;<count>
-- PBQUEST;<bot>;itemfail;<itemId>
-- PBQUEST;<bot>;mirrorfull;<questId>;<title>   (the bot's quest does not fit in the player's log)
-- PBQUEST;<bot>;mirrorshown;<mirrorQuestId>    (the bot's quest went into the player's log)
-- The title is last and may contain ';', so it is matched as the rest of the line.

local _, ns = ...
local L = ns.L

-- sound/interface/iquestactivate.ogg, the chime the client plays when you accept a quest
-- (no SOUNDKIT name in 1.14)
local QUEST_ACCEPT_SOUND_FILE = 567400

-- why a bot did not take a quest
local QUEST_SKIP_TEXT = {
    done     = L["quest.skip.done"],
    far      = L["quest.skip.far"],
    level    = L["quest.skip.level"],
    class    = L["quest.skip.class"],
    race     = L["quest.skip.race"],
    prev     = L["quest.skip.prev"],
    skill    = L["quest.skip.skill"],
    rep      = L["quest.skip.rep"],
    logfull  = L["quest.skip.logfull"],
    bagsfull = L["quest.skip.bagsfull"],
    other    = L["quest.skip.other"],
}

-- localized title from our own quest log, else the server's title
local function QuestTitle(id, fallback)
    for i = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(i)
        if not isHeader and questId == id then return title end
    end
    return fallback ~= "" and fallback or ("quest " .. id)
end

local function QuestMessage(text, r, g, b)
    DEFAULT_CHAT_FRAME:AddMessage(L("quest.message", { text = text }), r, g, b)
end

ns.On("PBQUEST", function(msg)
    local name, id, title = msg:match("^PBQUEST;([^;]*);accept;(%d+);(.*)$")
    if name then
        QuestMessage(L("quest.accepted", { name = name, quest = QuestTitle(tonumber(id), title) }), 1.0, 0.82, 0.0)
        return
    end

    local reason
    name, id, reason, title = msg:match("^PBQUEST;([^;]*);skip;(%d+);([^;]*);(.*)$")
    if name then
        QuestMessage(L("quest.skipped", { name = name, quest = QuestTitle(tonumber(id), title), reason = QUEST_SKIP_TEXT[reason] or QUEST_SKIP_TEXT.other }), 1.0, 0.5, 0.25)
        return
    end

    local count
    name, id, count = msg:match("^PBQUEST;([^;]*);item;(%d+);(%d+)$")
    if name then
        count = tonumber(count)
        QuestMessage(L("quest.item", { name = name, item = ns.ItemName(tonumber(id)), count = count > 1 and (" x" .. count) or "" }), 1.0, 0.82, 0.0)
        ns.BotInventoryChanged(name)
        return
    end

    -- the companion's quest cannot go into the player's quest log (mirror quest, log full)
    name, id, title = msg:match("^PBQUEST;([^;]*);mirrorfull;(%d+);(.*)$")
    if name then
        QuestMessage(L("quest.mirrorfull", { name = name, quest = QuestTitle(tonumber(id), title) }), 1.0, 0.5, 0.25)
        return
    end

    -- the companion's quest went into the player's log: the server put it there, so the client
    -- played no accept sound
    if msg:match("^PBQUEST;[^;]*;mirrorshown;%d+$") then
        pcall(PlaySoundFile, QUEST_ACCEPT_SOUND_FILE)
        return
    end

    name, id = msg:match("^PBQUEST;([^;]*);itemfail;(%d+)$")
    if name then
        QuestMessage(L("quest.itemfail", { name = name, item = ns.ItemName(tonumber(id)) }), 1.0, 0.1, 0.1)
    end
end)

-- PBAFF;<bot>;<affinity now>;<added>;<reason>   (companion affinity, 0..100)
ns.On("PBAFF", function(msg)
    local name, now, added = msg:match("^PBAFF;([^;]*);(%d+);(%d+);")
    if name then
        DEFAULT_CHAT_FRAME:AddMessage(L("quest.affinity", { name = name, added = added, now = now }), 1.0, 0.6, 0.8)
    end
end)
