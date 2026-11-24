-- Recruiting (design .kiro/docs/2026-11-21-companion-recruiting.md): someone you met plays along
-- with you for a while (搭伙). Do quests or a dungeon together and he may want to stay. The
-- talk itself is Talk.lua (also with people who are not in your party).
--
-- PBTRIAL;<bot>;start;<done>;<needed>   he joined you as a trial partner
-- PBTRIAL;<bot>;quest;<done>;<needed>   a quest done together
-- PBTRIAL;<bot>;bond;<first 1/0>        he is your companion now (also the first companion, who
--                                       joins without a trial; first = 1: Guide.lua's welcome)

local _, ns = ...
local L = ns.L

local GOLD = "|cffffd100"

local function Note(text)
    DEFAULT_CHAT_FRAME:AddMessage(L("recruit.note", { text = text }), 1.0, 0.82, 0.5)
end

ns.On("PBTRIAL", function(msg)
    local _, bot, kind, a, b = strsplit(";", msg)
    if not bot or bot == "" then return true end
    local who = GOLD .. bot .. "|r"
    if kind == "start" then
        Note(L("recruit.start", { name = who, quests = b or "3" }))
    elseif kind == "quest" then
        Note(L("recruit.quest", { name = who, done = a or "?", total = b or "?" }))
    elseif kind == "bond" then
        Note(L("recruit.bond", { name = who }))
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
    end
    return true
end)
