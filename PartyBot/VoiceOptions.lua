-- Settings of what the companions say in party chat during a run (the server's party voice,
-- Commander/Commands/Voice/PartyVoice.h): how talkative they are, and whether they put raid target
-- marks on what they crowd-control. On the Options page (Options.lua).
--
-- Saved in PartyBotDB (voiceLevel, voiceMarks); the server keeps them until it restarts, so they
-- are sent again after login and when joining a group (like the AI panel's pull method).
--   .partybot voice <quiet|normal|chatty> marks <on|off>  ->  PBOK;;voice;<level>;<on|off>

local _, ns = ...
local L = ns.L

local DEFAULT_LEVEL = "normal"

local confirmed = false     -- the server answered with our settings since login
local changed = false       -- the player changed one: show the answer

local function Level() return (ns.db and ns.db.voiceLevel) or DEFAULT_LEVEL end
local function Marks() return not (ns.db and ns.db.voiceMarks == false) end
local function IsDefault() return Level() == DEFAULT_LEVEL and Marks() end

local function Command()
    return (".partybot voice %s marks %s"):format(Level(), Marks() and "on" or "off")
end

local function Send()
    changed = true
    ns.SendCommand(Command())
end

ns.Options.AddHeader(L["voiceoptions.header"])
ns.Options.AddChoice({
    label = L["voiceoptions.level"],
    choices = {
        { "quiet", L["voiceoptions.quiet"], L["voiceoptions.quiet.tip"] },
        { "normal", L["voiceoptions.normal"], L["voiceoptions.normal.tip"] },
        { "chatty", L["voiceoptions.chatty"], L["voiceoptions.chatty.tip"] },
    },
    get = Level,
    set = function(level)
        ns.db.voiceLevel = level ~= DEFAULT_LEVEL and level or nil
        Send()
    end,
})
ns.Options.AddCheck({
    label = L["voiceoptions.marks"],
    tip = L["voiceoptions.marks.tip"],
    get = Marks,
    set = function(on)
        ns.db.voiceMarks = (not on) and false or nil
        Send()
    end,
})

ns.On("PBOK", function(msg)
    local level, marks = msg:match("^PBOK;;voice;(%a+);(%a+)")
    if not level then return end
    confirmed = level == Level() and (marks == "on") == Marks()
    if changed then
        changed = false
        ns.ShowOk(L("voiceoptions.ok", { level = L["voiceoptions." .. level] or level }))
    end
    return true
end)

-- after login / joining a group: tell the server again (outside a group an event cannot send)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function()
    if ns.db and not confirmed and not IsDefault() then
        ns.SendCommandAuto(Command())
    end
end)
