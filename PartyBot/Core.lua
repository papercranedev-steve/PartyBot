-- PartyBot core: shared helpers, saved variables and server reply dispatch.
--
-- The server answers addon commands with system messages "<PREFIX>;..." (PBINV, PBOK, PBERR,
-- PBQUEST, PBACC, PBCHR). They are hidden from chat and passed to the handlers registered with
-- ns.On(prefix, fn). Every handler of a prefix gets the full message.
-- PBERR is shown on screen unless a handler returns true.
--
-- Add-on packages (PartyBot_Assist, PartyBot_Dev) build on this addon: their Init.lua makes their
-- own namespace read through PartyBotCore, so their files use ns.L, ns.db, ns.On, ns.OnLoad,
-- ns.RegisterPanel, ns.SetQuickPanel, ns.SendCommand(Auto), ns.ShowError / ShowOk and the class
-- tables as if they were part of it. Their words go into ns.LOCALES (their own Locales/*.lua),
-- their settings into PartyBotDB.

local ADDON, ns = ...
local L = ns.L

PartyBotCore = ns

ns.ERROR_TEXT = {
    notfound    = L["core.err.notfound"],
    notbot      = L["core.err.notbot"],
    empty       = L["core.err.empty"],
    level       = L["core.err.level"],
    skill       = L["core.err.skill"],
    class       = L["core.err.class"],
    combat      = L["core.err.combat"],
    notequip    = L["core.err.notequip"],
    bagsfull    = L["core.err.bagsfull"],
    noslot      = L["core.err.noslot"],
    usage       = L["core.err.usage"],
    notusable   = L["core.err.notusable"],
    dead        = L["core.err.dead"],
    cooldown    = L["core.err.cooldown"],
    castfail    = L["core.err.castfail"],
    bagnotempty = L["core.err.bagnotempty"],
    mybagsfull  = L["core.err.mybagsfull"],
    botbagsfull = L["core.err.botbagsfull"],
    far         = L["core.err.far"],
    bound       = L["core.err.bound"],
    notalent    = L["core.err.notalent"],
    nopoints    = L["core.err.nopoints"],
    maxrank     = L["core.err.maxrank"],
    talentreq   = L["core.err.talentreq"],
    dependent   = L["core.err.dependent"],
    tier        = L["core.err.tier"],
    notcompanion = L["core.err.notcompanion"],
    locked      = L["core.err.locked"],
    nomoney     = L["core.err.nomoney"],
    maxmoney    = L["core.err.maxmoney"],
    nobank      = L["core.err.nobank"],
    notingroup  = L["core.err.notingroup"],
    tempbot     = L["core.err.tempbot"],
    bankfull    = L["core.err.bankfull"],
    botbankfull = L["core.err.botbankfull"],
    needbankslot = L["core.err.needbankslot"],
    allbankslots = L["core.err.allbankslots"],
    mynomoney   = L["core.err.mynomoney"],
    other       = L["core.err.other"],
}

---------------------------------------------------------------------------
-- classes and roles (class ids as in ChrClasses)
---------------------------------------------------------------------------

ns.CLASS_ORDER = { 1, 2, 3, 4, 5, 7, 8, 9, 11 }

ns.CLASS_FILE = {
    [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST",
    [7] = "SHAMAN", [8] = "MAGE", [9] = "WARLOCK", [11] = "DRUID",
}
ns.CLASS_TEXT = {
    [1] = L["core.class.1"], [2] = L["core.class.2"], [3] = L["core.class.3"], [4] = L["core.class.4"], [5] = L["core.class.5"],
    [7] = L["core.class.7"], [8] = L["core.class.8"], [9] = L["core.class.9"], [11] = L["core.class.11"],
}

-- talent tree names in talent tab order (TalentTab.dbc m_orderIndex), by class id
ns.TREE_NAMES = {
    [1]  = { L["core.tree.1.1"], L["core.tree.1.2"], L["core.tree.1.3"] },
    [2]  = { L["core.tree.2.1"], L["core.tree.2.2"], L["core.tree.2.3"] },
    [3]  = { L["core.tree.3.1"], L["core.tree.3.2"], L["core.tree.3.3"] },
    [4]  = { L["core.tree.4.1"], L["core.tree.4.2"], L["core.tree.4.3"] },
    [5]  = { L["core.tree.5.1"], L["core.tree.5.2"], L["core.tree.5.3"] },
    [7]  = { L["core.tree.7.1"], L["core.tree.7.2"], L["core.tree.7.3"] },
    [8]  = { L["core.tree.8.1"], L["core.tree.8.2"], L["core.tree.8.3"] },
    [9]  = { L["core.tree.9.1"], L["core.tree.9.2"], L["core.tree.9.3"] },
    [11] = { L["core.tree.11.1"], L["core.tree.11.2"], L["core.tree.11.3"] },
}

ns.ROLE_TEXT = { auto = L["core.role.auto"], tank = L["core.role.tank"], healer = L["core.role.healer"], meleedps = L["core.role.meleedps"], rangedps = L["core.role.rangedps"] }

-- roles that make sense per class; "auto" lets the server pick from class and talents
ns.CLASS_ROLES = {
    [1]  = { "auto", "tank", "meleedps" },
    [2]  = { "auto", "tank", "healer", "meleedps" },
    [3]  = { "auto", "rangedps" },
    [4]  = { "auto", "meleedps" },
    [5]  = { "auto", "healer", "rangedps" },
    [7]  = { "auto", "healer", "meleedps", "rangedps" },
    [8]  = { "auto", "rangedps" },
    [9]  = { "auto", "rangedps" },
    [11] = { "auto", "tank", "healer", "meleedps", "rangedps" },
}

function ns.ClassColor(classId)
    local file = ns.CLASS_FILE[classId]
    local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- a unit token the client has for this player right now, if any (it must be in view)
local UNIT_TOKENS = { "target", "mouseover", "focus" }
for i = 1, 4 do UNIT_TOKENS[#UNIT_TOKENS + 1] = "party" .. i end
for i = 1, 40 do UNIT_TOKENS[#UNIT_TOKENS + 1] = "raid" .. i end
for i = 1, 40 do UNIT_TOKENS[#UNIT_TOKENS + 1] = "nameplate" .. i end

function ns.UnitOf(name)
    if not name then return nil end
    for _, token in ipairs(UNIT_TOKENS) do
        if UnitExists(token) and UnitIsPlayer(token) and UnitName(token) == name then return token end
    end
end

-- C_CreatureInfo.GetRaceInfo: raceName, clientFileString
function ns.RaceInfo(race)
    return race and C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(race)
end

-- race portrait for someone the client cannot draw (gender as the server sends it: 0 male, 1 female)
function ns.RacePortrait(race, gender)
    local info = ns.RaceInfo(race)
    if not info or not info.clientFileString then return nil end
    return "Interface\\CharacterFrame\\TemporaryPortrait-" .. (gender == 1 and "Female" or "Male") .. "-" .. info.clientFileString
end

-- 'step' entries forward (negative = back) from 'current' in 'list', wrapping around
function ns.Cycle(list, current, step)
    local index = 1
    for i, v in ipairs(list) do
        if v == current then index = i break end
    end
    return list[(index - 1 + step) % #list + 1]
end

---------------------------------------------------------------------------
-- sending commands
---------------------------------------------------------------------------

local function ChatChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return "SAY"
end

-- Use from clicks, key presses and slash commands (hardware events).
function ns.SendCommand(cmd)
    SendChatMessage(cmd, ChatChannel())
end

-- Use from timers and events. 1.14 blocks SAY without a hardware event, so this only sends
-- when in a group (party/raid channel is allowed). Returns true if sent.
function ns.SendCommandAuto(cmd)
    if not IsInGroup() then return false end
    SendChatMessage(cmd, ChatChannel())
    return true
end

---------------------------------------------------------------------------
-- display helpers
---------------------------------------------------------------------------

function ns.ShowError(text)
    UIErrorsFrame:AddMessage(text, 1.0, 0.1, 0.1, 1.0)
end

function ns.ShowOk(text)
    UIErrorsFrame:AddMessage(text, 0.2, 1.0, 0.2, 1.0)
end

function ns.ItemName(id)
    local name = GetItemInfo(id)
    return name or ("item " .. tostring(id))
end

---------------------------------------------------------------------------
-- windows: each one registers itself; the minimap menu lists them in 'order'
---------------------------------------------------------------------------

ns.panels = {}

-- panel = { id, title, order, toggle = fn(), isShown = fn() -> bool, hint = "tooltip line" }
function ns.RegisterPanel(panel)
    table.insert(ns.panels, panel)
    table.sort(ns.panels, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

function ns.FindPanel(id)
    for _, p in ipairs(ns.panels) do
        if p.id == id then return p end
    end
end

function ns.TogglePanel(id)
    local p = ns.FindPanel(id)
    if p then p.toggle() end
end

-- the window the minimap button's right-click opens; an add-on package can take it over
ns.quickPanel = "companions"

function ns.SetQuickPanel(id)
    ns.quickPanel = id
end

---------------------------------------------------------------------------
-- saved variables: PartyBotDB (account wide)
---------------------------------------------------------------------------

-- the role your account's characters join with: PartyBotDB.roles[characterName] = role,
-- "auto" is not stored (companions menu, PartyBot_Assist's roster window)
local function Roles()
    ns.db.roles = ns.db.roles or {}
    return ns.db.roles
end

function ns.SavedRole(name)
    return Roles()[name] or "auto"
end

function ns.SaveRole(name, role)
    Roles()[name] = (role ~= "auto") and role or nil
end

local loadCallbacks = {}

-- fn() runs once PartyBotDB is available
function ns.OnLoad(fn)
    if ns.db then fn() else loadCallbacks[#loadCallbacks + 1] = fn end
end

---------------------------------------------------------------------------
-- server reply dispatch
---------------------------------------------------------------------------

local handlers = {} -- prefix -> { fn, ... }

function ns.On(prefix, fn)
    handlers[prefix] = handlers[prefix] or {}
    table.insert(handlers[prefix], fn)
end

local function Prefix(msg)
    return type(msg) == "string" and msg:match("^(PB%u+);") or nil
end

local function Dispatch(msg)
    local prefix = Prefix(msg)
    local list = prefix and handlers[prefix]
    local handled = false
    if list then
        for _, fn in ipairs(list) do
            if fn(msg) then handled = true end
        end
    end

    if prefix == "PBERR" and not handled then
        local name, code = msg:match("^PBERR;([^;]*);([^;]*)")
        local text = ns.ERROR_TEXT[code] or ns.ERROR_TEXT.other
        ns.ShowError((name and name ~= "") and L("core.err_named", { name = name, text = text }) or text)
    end
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    local prefix = Prefix(msg)
    return prefix ~= nil and (handlers[prefix] ~= nil or prefix == "PBERR")
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_SYSTEM")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "CHAT_MSG_SYSTEM" then
        if Prefix(arg1) then Dispatch(arg1) end
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        -- The client's language filter also rewrites system messages: the zhCN word list has
        -- number strings ("4749", "525", "502", "881"...), which turned spell and talent ids
        -- in the server replies into "1#$%^". The replies are numbers, so the filter stays off.
        if GetCVar("profanityFilter") ~= "0" then SetCVar("profanityFilter", "0") end
        PartyBotDB = PartyBotDB or {}
        ns.db = PartyBotDB
        for _, fn in ipairs(loadCallbacks) do fn() end
        wipe(loadCallbacks)
    end
end)
