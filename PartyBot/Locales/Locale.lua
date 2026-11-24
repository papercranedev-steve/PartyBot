-- Languages of the PartyBot addon: Chinese (zh) and English (en). Loaded first.
--
-- The words live in i18n/<addon>/<lang>.json at the repository root (zh.json is the base: every
-- key is there). `node tools/i18n.mjs build` turns them into <addon>/Locales/<lang>.lua, which
-- fill ns.LOCALES.zh / .en (PartyBot_Assist's fill the same tables); never edit those by hand.
-- `node tools/i18n.mjs check` checks keys and variables.
--
-- Every file reads its words from ns.L by key (`local L = ns.L`):
--   L["quest.panel"]                                 a fixed text
--   L("quest.accepted", { name = n, quest = q })     a text with {variables}; one not given stays as {name}
-- A key the chosen language does not have yet is shown in Chinese; a key no language has shows
-- the key itself (a typo is seen in game, not hidden). With a third language this chain becomes
-- chosen -> English -> Chinese (the user's rule: players see English rather than a key).
--
-- The language is chosen once per load (windows are built while the files run): the saved
-- choice (PartyBot_Language addon, PartyBotLanguageDB.lang), else the client's language
-- (zhCN / zhTW: Chinese, anything else: English). Changing it reloads the UI (Language.lua).
-- Text the server sends (what a bot says, trait names) is in the language the server has for
-- the account: Language.lua tells it (.partybot language zh|en).

local _, ns = ...

ns.LANGUAGES = { "zh", "en" }
ns.LANGUAGE_NAMES = { zh = "中文", en = "English" }     -- each in its own language
ns.LOCALES = { zh = {}, en = {} }

local function ClientLanguage()
    local locale = GetLocale()
    return (locale == "zhCN" or locale == "zhTW") and "zh" or "en"
end

function ns.SavedLanguage()
    local saved = PartyBotLanguageDB and PartyBotLanguageDB.lang
    return ns.LOCALES[saved or ""] and saved or nil
end

ns.lang = ns.SavedLanguage() or ClientLanguage()

ns.L = setmetatable({}, {
    __index = function(self, key)
        local text = ns.LOCALES[ns.lang][key] or ns.LOCALES.zh[key] or key
        rawset(self, key, text)
        return text
    end,
    __call = function(self, key, vars)
        return (self[key]:gsub("{([%w_]+)}", function(name)
            local value = vars and vars[name]
            if value ~= nil then return tostring(value) end
        end))
    end,
})
