-- Companion menus: right-click on a card of the companions list, and the unit menu of a
-- companion in your party / raid (end of the file). The list menu is sorted into groups with
-- sub-menus (user 2026-11-21: too many lines in one list): 查看 (sheet, talents, bags), 职责
-- (your account's characters), 关系 (join the account, send back, farewell). Talents need the
-- companion online, bags (his sheet with the bags panel) him in your group and his affinity
-- gate open (not offered before), talking him in view (the server checks the 10 yd of talking).
-- Your account's characters (companion account doc): called over with their saved role (the
-- ns.SavedRole in Core.lua), no slot, no farewell; one who joined at affinity 100 can be sent back.

local _, ns = ...
local L = ns.L

local menuFrame = CreateFrame("Frame", "PartyBotCompanionMenu", UIParent, "UIDropDownMenuTemplate")

local function Disabled(entry, reason)
    entry.disabled = true
    entry.tooltipTitle = entry.text
    entry.tooltipText = reason
    entry.tooltipOnButton = true
    return entry
end

local function Entry(text, func)
    return { text = text, notCheckable = true, func = func }
end

-- a group of entries (nil when it would be empty)
local function Group(text, list)
    if #list == 0 then return nil end
    return { text = text, notCheckable = true, hasArrow = true, menuList = list }
end

-- The entries in order (nil ones left out), then 取消.
local function Show(...)
    local list = {}
    for i = 1, select("#", ...) do
        local item = select(i, ...)
        if item then list[#list + 1] = item end
    end
    list[#list + 1] = { text = CANCEL, notCheckable = true }
    EasyMenu(list, menuFrame, "cursor", 0, 0, "MENU")
end

-- 道别 / 永别 (companion slots doc §3), into / out of the account: asked once more, they are
-- not small things
StaticPopupDialogs["PARTYBOT_FAREWELL"] = {
    text = "%s",
    button1 = L["companionmenu.farewell"],
    button2 = CANCEL,
    OnAccept = function(_, guid) ns.SendCommand(".partybot farewell " .. guid) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}
StaticPopupDialogs["PARTYBOT_FORGET"] = {
    text = "%s",
    button1 = L["companionmenu.forget"],
    button2 = CANCEL,
    OnAccept = function(_, guid) ns.SendCommand(".partybot forget " .. guid) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
}
-- Into the account with the name the player gives him (server Companions/Account/Naming), once:
-- after the yes in his talk window (its window "name") and from 关系 ▸ 纳入名册. The box holds his
-- name, selected: Enter keeps it, typing replaces it. The server checks the name; a refused one
-- opens the box again with the reason and what was typed (PBERR;<name>;name_<why>;<typed>).
-- data = { guid, name, text, typed }
local naming    -- the data of the box last sent, for a refused name

StaticPopupDialogs["PARTYBOT_NAME_COMPANION"] = {
    text = "%s",
    button1 = L["companionmenu.name.button"],
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 12,
    OnShow = function(self, data)
        self.editBox:SetText(data.typed or data.name)
        self.editBox:HighlightText()
        self.editBox:SetFocus()
    end,
    OnAccept = function(self, data)
        local typed = strtrim(self.editBox:GetText() or "")
        if typed == "" then typed = data.name end
        naming = data
        ns.SendCommand((".partybot joinaccount %d %s"):format(data.guid, typed))
    end,
    -- from his talk window he kneels while the box is open: 取消 is "现在还不行", he rises
    OnCancel = function(_, data)
        naming = nil
        if data and data.bot then ns.SendCommandAuto((".partybot talk %s account:later"):format(data.bot)) end
    end,
    EditBoxOnEnterPressed = function(self, data)
        local popup = self:GetParent()
        StaticPopupDialogs[popup.which].OnAccept(popup, data)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self, data)
        local popup = self:GetParent()
        StaticPopupDialogs[popup.which].OnCancel(popup, data)
        popup:Hide()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- `intro`: the text above the box (a key with {name}), `why`: a refused name's reason first
-- `bot`: asked in his talk window (he kneels), nil from the menu
local function AskName(guid, name, intro, why, typed, bot)
    local text = L(intro, { name = name })
    if why then text = "|cffff6060" .. why .. "|r\n\n" .. text end
    StaticPopup_Show("PARTYBOT_NAME_COMPANION", text, nil,
        { guid = tonumber(guid), name = name, intro = intro, typed = typed, bot = bot })
end

-- his talk window's "我来为你起个名字。" (server JoinOffer: PBTALK;<bot>;OPEN;name;<guid>)
ns.talkWindows = ns.talkWindows or {}
ns.talkWindows.name = function(bot, guid)
    if tonumber(guid) then AskName(guid, bot, "companionmenu.name.ask", nil, nil, bot) end
end

local NAME_ERRORS = {
    name_empty = "companionmenu.name.err.empty",
    name_short = "companionmenu.name.err.short",
    name_long = "companionmenu.name.err.long",
    name_repeat = "companionmenu.name.err.repeat",
    name_chars = "companionmenu.name.err.chars",
    name_reserved = "companionmenu.name.err.reserved",
    name_taken = "companionmenu.name.err.taken",
}

ns.On("PBERR", function(msg)
    local name, code, typed = msg:match("^PBERR;([^;]*);(name_%a+);(.*)$")
    if not code then return false end
    local data = naming
    if data and data.name == name then
        AskName(data.guid, name, data.intro, L[NAME_ERRORS[code] or "companionmenu.name.err.reserved"], typed, data.bot)
    else
        ns.ShowError(L[NAME_ERRORS[code] or "companionmenu.name.err.reserved"])
    end
    return true
end)
StaticPopupDialogs["PARTYBOT_SEND_BACK"] = {
    text = "%s",
    button1 = L["companionmenu.sendback.button"],
    button2 = CANCEL,
    OnAccept = function(_, guid) ns.SendCommand(".partybot sendback " .. guid) end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- the dialogs' text is "%s": the question (a key with {name}) is filled in here
local function Confirm(which, key, c)
    StaticPopup_Show(which, L(key, { name = c.name }), nil, c.guid)
end

-- a former companion (故人): invite back, look, part for good
local function ShowFormerMenu(c)
    local slots = ns.CompanionSlots()
    local rehire = Entry(L["companionmenu.rehire"], function() ns.SendCommand(".partybot rehire " .. c.guid) end)
    if slots.used >= slots.total then
        Disabled(rehire, slots.nextLevel > 0 and L("companionmenu.rehire.full_next", { level = slots.nextLevel })
            or L["companionmenu.rehire.full"])
    end
    Show(
        { text = c.name, isTitle = true, notCheckable = true },
        rehire,
        Entry(L["companionmenu.view"], function() ns.Sheet.Open(c.guid) end),
        Entry(L["companionmenu.forget"], function() Confirm("PARTYBOT_FORGET", "companionmenu.forget.confirm", c) end)
    )
end

local function IsAccountCharacter(c)
    return c.account ~= nil
end

local function SavedRole(c)
    return ns.SavedRole and ns.SavedRole(c.name) or "auto"
end

-- 查看: his sheet, talents (online), quests, bags (in your group; only once he lets you)
local function LookGroup(c)
    local online = c.state == ns.COMPANION_STATE.ONLINE or c.state == ns.COMPANION_STATE.GROUP
    local talents = Entry(L["companionmenu.talents"], function() ns.ShowTalents(c.name) end)
    if not online then Disabled(talents, L["companionmenu.talents.disabled"]) end
    local bags
    if ns.GateOpen(c, "bags") then
        bags = Entry(L["companionmenu.bags"], function() ns.ShowBags(c.name) end)
        if c.state ~= ns.COMPANION_STATE.GROUP then Disabled(bags, L["companionmenu.bags.disabled"]) end
    end
    return Group(L["companionmenu.group.look"], {
        Entry(L["companionmenu.sheet"], function() ns.Sheet.Open(c.guid) end),
        talents,
        -- (offline too: the server reads his log from the database)
        Entry(L["companionmenu.quests"], function() ns.ShowCompanionQuests(c.guid) end),
        bags,
    })
end

-- 职责 of your account's character: remembered for the next call; with you, at once
local function ChooseRole(c, role)
    if ns.SaveRole then ns.SaveRole(c.name, role) end
    if c.state == ns.COMPANION_STATE.GROUP then
        ns.SendCommand((".partybot setrole %s %s"):format(role, c.name))
    else
        ns.ShowOk(L("companionmenu.role.saved", { name = c.name, role = ns.ROLE_TEXT[role] or role }))
    end
end

local function RoleGroup(c)
    local current = SavedRole(c)
    local list = {}
    for _, role in ipairs(ns.CLASS_ROLES[c.class] or { "auto" }) do
        list[#list + 1] = {
            text = ns.ROLE_TEXT[role] or role,
            checked = role == current,
            func = function()
                ChooseRole(c, role)
                CloseDropDownMenus()
            end,
        }
    end
    return Group(L["companionmenu.group.role"], list)
end

-- 关系: into the account (affinity 100), back to being a companion (one who joined), farewell
local function RelationGroup(c)
    local list = {}
    if not IsAccountCharacter(c) then
        if c.affinity >= 100 then
            list[#list + 1] = Entry(L["companionmenu.joinaccount"], function()
                AskName(c.guid, c.name, "companionmenu.joinaccount.confirm")
            end)
        end
        list[#list + 1] = Entry(L["companionmenu.farewell"], function()
            Confirm("PARTYBOT_FAREWELL", "companionmenu.farewell.confirm", c)
        end)
    elseif c.account == ns.ACCOUNT_KIND.COMPANION then
        list[#list + 1] = Entry(L["companionmenu.sendback"], function()
            Confirm("PARTYBOT_SEND_BACK", "companionmenu.sendback.confirm", c)
        end)
    end
    return Group(L["companionmenu.group.relation"], list)
end

local function CallOverEntry(c)
    -- (with you already; an offline member of your group, who did not come back with you, is
    -- called over like the others)
    if c.state == ns.COMPANION_STATE.GROUP then
        local unit = ns.UnitOf(c.name)
        if unit and UnitIsConnected(unit) then return nil end
    end
    -- one not with you: he comes from where he is (server CompanionMgr::CallOver)
    return Entry(L["companionmenu.callover"], function()
        if IsAccountCharacter(c) then
            ns.SendCommand((".partybot callover %d %s"):format(c.guid, SavedRole(c)))
        else
            ns.SendCommand(".partybot callover " .. c.guid)
        end
    end)
end

local function TalkEntry(name, unit)
    local talk = Entry(L["companionmenu.talk"], function() ns.Talk(name) end)
    if not unit then Disabled(talk, L["companionmenu.talk.disabled"]) end
    return talk
end

function ns.ShowCompanionMenu(c)
    if c.state == ns.COMPANION_STATE.FORMER then return ShowFormerMenu(c) end
    local unit = ns.UnitOf(c.name)
    Show(
        { text = c.name, isTitle = true, notCheckable = true },
        CallOverEntry(c),
        TalkEntry(c.name, unit),
        LookGroup(c),
        IsAccountCharacter(c) and RoleGroup(c) or nil,
        RelationGroup(c)
    )
end

-- `.partybot callover` (the companion logs in where he is and comes; his line says from where)
ns.ERROR_TEXT.notyours = L["companionmenu.err.notyours"]
ns.ERROR_TEXT.online = L["companionmenu.err.online"]
ns.ERROR_TEXT.full = L["companionmenu.err.full"]
ns.ERROR_TEXT.failed = L["companionmenu.err.failed"]
ns.ERROR_TEXT.enemy = L["companionmenu.err.enemy"]

ns.On("PBOK", function(msg)
    if not msg:match("^PBOK;[^;]*;callover$") then return false end
    -- (the list shows him in the group once he is in)
    C_Timer.After(3, function() ns.SendCommand(".partybot companions") end)
    return true
end)

-- companion slots and former companions (server CompanionCommands: farewell, rehire, forget, buyslot)
ns.ERROR_TEXT.former = L["companionmenu.err.former"]
ns.ERROR_TEXT.notformer = L["companionmenu.err.notformer"]
ns.ERROR_TEXT.leaving = L["companionmenu.err.leaving"]
ns.ERROR_TEXT.notyet = L["companionmenu.err.notyet"]
ns.ERROR_TEXT.maxslots = L["companionmenu.err.maxslots"]
ns.ERROR_TEXT.nomoney = L["companionmenu.err.nomoney"]
ns.ERROR_TEXT.noslot = L["companionmenu.err.noslot"]
-- your account's characters (server CompanionCommands: joinaccount, sendback)
ns.ERROR_TEXT.inaccount = L["companionmenu.err.inaccount"]
ns.ERROR_TEXT.notinaccount = L["companionmenu.err.notinaccount"]
ns.ERROR_TEXT.accountfull = L["companionmenu.err.accountfull"]
ns.ERROR_TEXT.self = L["companionmenu.err.self"]

ns.On("PBOK", function(msg)
    local name, what, extra = msg:match("^PBOK;([^;]*);(%a+);?(.*)$")
    if what == "farewell" then
        -- (online he says goodbye himself; the list shows him among the former ones)
        C_Timer.After(1, function() ns.SendCommand(".partybot companions") end)
    elseif what == "rehire" then
        if extra ~= "1" then
            DEFAULT_CHAT_FRAME:AddMessage(L("companionmenu.rehired", { name = name }), 1, 0.82, 0)
        end
        C_Timer.After(3, function() ns.SendCommand(".partybot companions") end)
    elseif what == "forget" then
        DEFAULT_CHAT_FRAME:AddMessage(L("companionmenu.forgotten", { name = name }), 1, 0.82, 0)
        ns.SendCommand(".partybot companions")
    elseif what == "buyslot" then
        local total, paid = extra:match("^(%d+);(%d+)$")
        DEFAULT_CHAT_FRAME:AddMessage(L("companionmenu.slot_bought", { total = total or "?", cost = GetCoinTextureString(tonumber(paid) or 0) }), 1, 0.82, 0)
        ns.SendCommand(".partybot companions")
    elseif what == "joinaccount" then
        -- (also after the yes in his talk window: Account/JoinOffer); extra: his new name
        naming = nil
        if extra ~= "" then
            -- what is kept by his name goes with him (his saved role)
            local role = ns.SavedRole and ns.SavedRole(name)
            if role and role ~= "auto" and ns.SaveRole then
                ns.SaveRole(extra, role)
                ns.SaveRole(name, "auto")
            end
            DEFAULT_CHAT_FRAME:AddMessage(L("companionmenu.joined.named", { name = extra, old = name }), 1, 0.82, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage(L("companionmenu.joined", { name = name }), 1, 0.82, 0)
        end
        ns.SendCommandAuto(".partybot companions")
    elseif what == "sendback" then
        DEFAULT_CHAT_FRAME:AddMessage(L(extra == "1" and "companionmenu.sentback" or "companionmenu.sentback.former", { name = name }), 1, 0.82, 0)
        ns.SendCommandAuto(".partybot companions")
    else
        return false
    end
    return true
end)

-- a roster member could not join (server PopulationMgr::UpdateRecruits): PBERR;<name>;noslot;<used>;<total>;<next free level>
ns.On("PBERR", function(msg)
    local name, used, total, nextLevel = msg:match("^PBERR;([^;]*);noslot;(%d+);(%d+);(%d+)$")
    if not name then return false end
    nextLevel = tonumber(nextLevel)
    local why = nextLevel > 0 and L("companionmenu.noslot.next", { level = nextLevel }) or L["companionmenu.noslot.hint"]
    ns.ShowError(L("companionmenu.noslot", { used = used, total = total, name = name, why = why }))
    return true
end)

-- the party's last order (PBOK;;stay|follow): only the useful one is offered; nil = not known yet
local teamStays

-- why a warlock cannot summon you (`.partybot summon`, server Companions/Travel/SummonOffer)
ns.ERROR_TEXT.notlearned = L["companionmenu.err.notlearned"]
ns.ERROR_TEXT.noshard = L["companionmenu.err.noshard"]
ns.ERROR_TEXT.nohelpers = L["companionmenu.err.nohelpers"]
ns.ERROR_TEXT.here = L["companionmenu.err.here"]
ns.ERROR_TEXT.near = L["companionmenu.err.near"]
ns.ERROR_TEXT.busy = L["companionmenu.err.busy"]
ns.ERROR_TEXT.nowarlock = L["companionmenu.err.nowarlock"]
ns.ERROR_TEXT.fighting = L["companionmenu.err.fighting"]

ns.On("PBOK", function(msg)
    if msg:match("^PBOK;[^;]*;summon$") or msg:match("^PBOK;;gather") then return true end
    local order, count = msg:match("^PBOK;;(%a+);(%d+)$")
    if order == "stay" or order == "follow" then
        teamStays = order == "stay"
        if tonumber(count) == 0 then ns.ShowError(L["companionmenu.nobody_heard"]) end
        return true
    end
    -- one bot by name (`.partybot stay <name>`)
    return msg:match("^PBOK;[^;]+;stay;") ~= nil or msg:match("^PBOK;[^;]+;follow;") ~= nil
end)

---------------------------------------------------------------------------
-- unit menu of a companion (right-click on its party / raid frame, or on the target frame)
---------------------------------------------------------------------------
-- Blizzard's own menu, cleaned of what means nothing with a bot (promote, duel, whisper, ...),
-- with our lines in its sections and at most one sub-menu level (user 2026-11-22). Built on the
-- 1.14.2 tables (Interface_Vanilla/FrameXML/UnitPopup.lua): our keys go into UnitPopupMenus and
-- UnitPopupButtons, UnitPopup_HideButtons decides each time the menu opens (post-hook writing
-- UnitPopupShown), and clicks come through UnitPopup_OnClick (post-hook reading self.value).
-- 观察 opens our companion sheet instead of the native inspect.

local UNIT_MENUS = { "PARTY", "RAID_PLAYER", "RAID" }
local IS_UNIT_MENU = {}
for _, which in ipairs(UNIT_MENUS) do IS_UNIT_MENU[which] = true end

-- native lines left out for a companion
local HIDDEN = {}
for _, key in ipairs({ "ADD_FRIEND", "ADD_FRIEND_MENU", "RAF_SUMMON", "RAF_GRANT_LEVEL", "PROMOTE", "PROMOTE_GUIDE",
    "LOOT_PROMOTE", "RAID_LEADER", "RAID_PROMOTE", "RAID_DEMOTE", "WHISPER", "INSPECT", "FOLLOW", "DUEL",
    "PET_BATTLE_PVP_DUEL", "VOICE_CHAT", "REPORT_PLAYER", "PVP_REPORT_AFK", "VOTE_TO_KICK" }) do
    HIDDEN[key] = true
end

-- the companion the open menu is for: { name, unit, c (nil until the list came), classId }
local shownFor

local function MenuCompanion(menu)
    if not menu or not IS_UNIT_MENU[menu.which] or not menu.name then return nil end
    if menu.unit and UnitIsUnit(menu.unit, "player") then return nil end
    local c = ns.FindCompanionByName(menu.name)
    -- before the list came every party member counts (they are bots here)
    if not c and ns.CompanionsLoaded() then return nil end
    return { name = menu.name, unit = menu.unit, c = c,
        classId = (menu.unit and select(3, UnitClass(menu.unit))) or (c and c.class) }
end

-- Our lines. shown(x) / disabled(x) are asked when the menu opens (disabled: why, as the tooltip).
local OWN = {}

local function InReach(x, index) return x.unit and CheckInteractDistance(x.unit, index) end

OWN.PB_TALK = {
    text = L["companionmenu.talk"], why = L["companionmenu.talk.disabled"],
    disabled = function(x) return not InReach(x, 2) end,      -- trade range, as Talk.lua
    click = function(x) ns.Talk(x.name) end,
}
OWN.PB_INSPECT = {
    text = L["companionmenu.inspect"],
    click = function(x) if x.c then ns.Sheet.Open(x.c.guid) else ns.Sheet.OpenByName(x.name) end end,
}
OWN.PB_TALENTS = {
    text = L["companionmenu.talents"],
    click = function(x) ns.ShowTalents(x.name) end,
}
OWN.PB_QUESTS = {   -- his quest log (the sheet's quest tab, Sheet/QuestPage.lua)
    text = L["companionmenu.quests"],
    click = function(x)
        if x.c then ns.ShowCompanionQuests(x.c.guid) else ns.ShowCompanionQuestsByName(x.name) end
    end,
}
OWN.PB_BAGS = {   -- his sheet with the bags panel (Bags.lua); only once he lets you (affinity gate)
    text = L["companionmenu.bags"],
    shown = function(x) return x.c and ns.GateOpen(x.c, "bags") end,
    click = function(x) ns.ShowBags(x.name) end,
}
OWN.PB_SUMMON_ME = {   -- a warlock summons you back to the team (any distance; the server says why not)
    text = L["companionmenu.summon_me"],
    shown = function(x) return x.classId == 9 end,
    click = function(x) ns.SendCommand(".partybot summon " .. x.name) end,
}

-- 职责 of your account's character: the line says the current one, the sub-menu the choices
OWN.PB_ROLE = {
    text = function()
        local role = shownFor and shownFor.c and SavedRole(shownFor.c)
        return L("companionmenu.role.current", { role = ns.ROLE_TEXT[role] or role or "" })
    end,
    nested = 1,
    shown = function(x) return x.c and IsAccountCharacter(x.c) end,
}
local ROLE_KEYS = {}
do
    local seen = {}
    for _, roles in pairs(ns.CLASS_ROLES) do
        for _, role in ipairs(roles) do seen[role] = true end
    end
    for _, role in ipairs({ "auto", "tank", "healer", "meleedps", "rangedps" }) do
        if seen[role] then
            local key = "PB_ROLE_" .. role
            ROLE_KEYS[#ROLE_KEYS + 1] = key
            OWN[key] = {
                text = function()
                    local current = shownFor and shownFor.c and SavedRole(shownFor.c) == role
                    return (ns.ROLE_TEXT[role] or role) .. (current and " |TInterface\\Buttons\\UI-CheckBox-Check:0|t" or "")
                end,
                shown = function(x) return x.c and tContains(ns.CLASS_ROLES[x.c.class] or { "auto" }, role) end,
                click = function(x) ChooseRole(x.c, role) end,
            }
        end
    end
end

-- 大家: the whole party's orders (Talk.lua and the server's Commander/Coordination/Situation/Stay.h)
OWN.PB_TEAM = { text = L["companionmenu.group.team"], nested = 1 }
OWN.PB_STAY = {
    text = L["companionmenu.stay"],
    shown = function() return teamStays ~= true end,
    click = function() ns.SendCommand(".partybot stay") end,
}
OWN.PB_FOLLOW = {
    text = L["companionmenu.follow"],
    shown = function() return teamStays ~= false end,
    click = function() ns.SendCommand(".partybot follow") end,
}
OWN.PB_SUMMON_ALL = {   -- the team's warlocks summon those left behind (server Commander GatherPlanner)
    text = L["companionmenu.summon_all"],
    click = function() ns.SendCommand(".partybot summon all") end,
}

local function InsertAt(list, index, keys)
    for i, key in ipairs(keys) do table.insert(list, index + i - 1, key) end
end

local function IndexOf(list, key)
    for i, v in ipairs(list) do
        if v == key then return i end
    end
end

if UnitPopupMenus and UnitPopupButtons and UnitPopupShown then
    for key, own in pairs(OWN) do
        local button = { text = own.text, nested = own.nested }
        if own.why then
            button.tooltipText = own.why
            button.tooltipWhileDisabled = 1
            button.noTooltipWhileEnabled = 1
            button.tooltipOnButton = 1
            button.IsDisabledFn = function() return button.isUninteractable end
        end
        UnitPopupButtons[key] = button
    end
    UnitPopupMenus.PB_ROLE = ROLE_KEYS
    UnitPopupMenus.PB_TEAM = { "PB_STAY", "PB_FOLLOW", "PB_SUMMON_ALL" }

    -- 互动: talk and look first; a warlock's summon, 职责 and 大家 close the section
    for _, which in ipairs(UNIT_MENUS) do
        local list = UnitPopupMenus[which]
        if list then
            local cancel = IndexOf(list, "CANCEL") or (#list + 1)
            InsertAt(list, IndexOf(list, "OTHER_SUBSECTION_TITLE") or cancel, { "PB_SUMMON_ME", "PB_ROLE", "PB_TEAM" })
            local interact = IndexOf(list, "INTERACT_SUBSECTION_TITLE")
            InsertAt(list, interact and interact + 1 or 1, { "PB_TALK", "PB_INSPECT", "PB_TALENTS", "PB_QUESTS", "PB_BAGS" })
        end
    end

    local asked
    hooksecurefunc("UnitPopup_HideButtons", function()
        local menu = UIDROPDOWNMENU_INIT_MENU
        local level = UIDROPDOWNMENU_MENU_LEVEL
        -- (the same list UnitPopup_HideButtons went through)
        local list = menu and (UnitPopupMenus[UIDROPDOWNMENU_MENU_VALUE] or UnitPopupMenus[menu.which])
        if not list or not UnitPopupShown[level] then return end
        local x = MenuCompanion(menu)
        if x and not ns.CompanionsLoaded() and not asked then
            asked = ns.SendCommandAuto(".partybot companions")
        end
        shownFor = x
        for index, key in ipairs(list) do
            local own = OWN[key]
            if own then
                local shown = x and (not own.shown or own.shown(x))
                if not shown then
                    UnitPopupShown[level][index] = 0
                elseif own.why then
                    -- decided as it opens: UnitPopup_OnUpdate keeps it (isUninteractable)
                    UnitPopupButtons[key].isUninteractable = own.disabled(x) and true or nil
                end
            elseif x and HIDDEN[key] then
                UnitPopupShown[level][index] = 0
            end
        end
    end)

    hooksecurefunc("UnitPopup_OnClick", function(self)
        local own = OWN[self.value]
        if own and own.click and shownFor then own.click(shownFor) end
    end)
end
