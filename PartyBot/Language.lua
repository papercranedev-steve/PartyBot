-- The language switch (minimap menu "语言 / Language", or /pblang zh|en) and telling the server.
--
-- Switching saves the choice (PartyBotLanguageDB, the PartyBot_Language addon) and reloads the
-- UI: the windows took their words while the files ran (Locale.lua).
-- The server says things in the account's language (bot speech, labels it sends). It is told
-- with `.partybot language <zh|en>` (answer PBOK;;language;<code>), once per login: with the
-- first command a click sends, or at once when in a group (1.14 only lets an addon /say from a
-- click or key).
-- Loaded right after Core.lua, before files keep their own copy of ns.SendCommand.

local _, ns = ...
local L = ns.L

local told = false

local function LanguageCommand()
    return ".partybot language " .. ns.lang
end

-- (once per login: a server without the command would answer every click with an error)
local SendCommand = ns.SendCommand
function ns.SendCommand(cmd)
    if not told then
        told = true
        SendCommand(LanguageCommand())
    end
    SendCommand(cmd)
end

local function TellServer()
    if not told and ns.SendCommandAuto(LanguageCommand()) then told = true end
end

ns.On("PBOK", function(msg)
    return msg:match("^PBOK;;language;") ~= nil
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", TellServer)

---------------------------------------------------------------------------
-- switching
---------------------------------------------------------------------------

local function Choose(lang)
    if not PartyBotLanguageDB then
        ns.ShowError(L["language.noaddon"])
        return
    end
    if lang == ns.lang then return end
    PartyBotLanguageDB.lang = lang
    ReloadUI()
end

StaticPopupDialogs["PARTYBOT_LANGUAGE"] = {
    text = "%s",
    button1 = OKAY,
    button2 = CANCEL,
    OnAccept = function(_, lang) Choose(lang) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function Other()
    return ns.lang == "zh" and "en" or "zh"
end

local function Offer(lang)
    local popup = StaticPopup_Show("PARTYBOT_LANGUAGE", L("language.switch", { lang = ns.LANGUAGE_NAMES[lang] }))
    if popup then popup.data = lang end
end

ns.RegisterPanel({
    id = "language",
    title = L("language.menu", { lang = ns.LANGUAGE_NAMES[ns.lang] }),
    order = 1000,
    toggle = function() Offer(Other()) end,
})

SLASH_PARTYBOTLANG1 = "/pblang"
SlashCmdList.PARTYBOTLANG = function(arg)
    arg = (arg or ""):lower():match("^%s*(%a*)")
    if ns.LOCALES[arg] then
        Choose(arg)
    else
        DEFAULT_CHAT_FRAME:AddMessage(L("language.usage", { lang = ns.LANGUAGE_NAMES[ns.lang] }))
    end
end
