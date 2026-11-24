-- Companion sheet: one companion's character window, built like the player's own (C key):
-- the same frame art, tabs along the bottom, a native UI panel (docks left, ESC closes it).
-- Works for offline companions too: the server reads them from the database.
--
-- Pages register themselves (Sheet/*.lua) with ns.Sheet.AddPage and get the page data the
-- server sends for them. Adding a page = one new file, nothing here changes.
--
--   page = { key, title, order, server = "char"|"rep"|"skill"|nil, levelLine = bool,
--            Build = fn(pageFrame, sheet), Update = fn(pageFrame, companion, data) }
--   data = { online = bool, lines = { [kind] = { {field, ...}, ... } } } (nil until it came)
--
-- Request: .partybot companion <guid> <server page>
-- Reply:   PBCMV;<guid>;BEGIN;<page>;<online> | PBCMV;<guid>;<kind>;<fields...> | PBCMV;<guid>;END;<page>

local _, ns = ...
local L = ns.L

local Sheet = { pages = {} }
ns.Sheet = Sheet

local FRAME_W, FRAME_H = 384, 512

local frame             -- built on first open, after every page file registered
local current           -- guid shown
local currentPage       -- page key
local cache = {}        -- [guid] = { [server page] = data }
local incoming = {}     -- [guid .. page] = data being received
local changeHandlers = {}

function Sheet.AddPage(page)
    table.insert(Sheet.pages, page)
    table.sort(Sheet.pages, function(a, b) return (a.order or 99) < (b.order or 99) end)
end

---------------------------------------------------------------------------
-- shared look
---------------------------------------------------------------------------

-- the plain character window background (reputation, skills and quests use it)
function Sheet.GeneralBackground(page)
    local parts = {
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",     256, 256, 2,   -1 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",    128, 256, 258, -1 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft",  256, 256, 2,   -257 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight", 128, 256, 258, -257 },
    }
    for _, p in ipairs(parts) do
        local t = page:CreateTexture(nil, "BORDER")
        t:SetTexture(p[1])
        t:SetSize(p[2], p[3])
        t:SetPoint("TOPLEFT", p[4], p[5])
    end
end

-- scroll bar art of the character window lists
function Sheet.ScrollBarArt(scroll, bottomHeight, bottomCoord)
    local top = scroll:CreateTexture(nil, "BACKGROUND")
    top:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    top:SetSize(31, 256)
    top:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, 5)
    top:SetTexCoord(0, 0.484375, 0, 1)
    local bottom = scroll:CreateTexture(nil, "BACKGROUND")
    bottom:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    bottom:SetSize(31, bottomHeight or 108)
    bottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, -4)
    bottom:SetTexCoord(0.515625, 1, 0, bottomCoord or 0.421875)
end

-- the item string of a piece of his gear ({ entry, enchant, suffix } from the char page's I lines)
function Sheet.ItemString(item)
    return ("item:%d:%d:::::%d"):format(item.entry, item.enchant, item.suffix)
end

function Sheet.Current() return current and ns.FindCompanion(current) end

-- the key of the page shown (nil before the first open)
function Sheet.CurrentPage() return currentPage end

-- fn(companion) runs after the sheet opened or switched to someone (the frame exists by then)
function Sheet.OnChange(fn) changeHandlers[#changeHandlers + 1] = fn end

---------------------------------------------------------------------------
-- frame
---------------------------------------------------------------------------

local function UpdateHeader(c)
    frame.name:SetText(c and c.name or "")
    if c then
        local race = ns.RaceInfo(c.race)
        frame.level:SetText(PLAYER_LEVEL and PLAYER_LEVEL:format(c.level, race and race.raceName or "", ns.CLASS_TEXT[c.class] or "")
            or L("companionsheet.level_class", { level = c.level, class = ns.CLASS_TEXT[c.class] or "" }))
    end
    local unit = c and ns.UnitOf(c.name)
    if unit then
        SetPortraitTexture(frame.portrait, unit)
        frame.portrait:SetTexCoord(0, 1, 0, 1)
    else
        local file = c and ns.RacePortrait(c.race, c.gender)
        frame.portrait:SetTexture(file or ns.COMPANIONS_ICON)
    end
end

local function PageByKey(key)
    for _, p in ipairs(Sheet.pages) do
        if p.key == key then return p end
    end
end

local function DataFor(page)
    return page.server and current and cache[current] and cache[current][page.server]
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    local c = Sheet.Current()
    UpdateHeader(c)
    local page = PageByKey(currentPage)
    if page and c then
        frame.level:SetShown(page.levelLine and true or false)
        page.Update(page.frame, c, DataFor(page))
    end
end
Sheet.Refresh = Refresh

local function Request(page)
    if page.server and current then
        ns.SendCommand((".partybot companion %d %s"):format(current, page.server))
    end
end

local function ShowPage(key)
    currentPage = key
    for i, p in ipairs(Sheet.pages) do
        p.frame:SetShown(p.key == key)
        if p.key == key then PanelTemplates_SetTab(frame, i) end
    end
    Refresh()
    local page = PageByKey(key)
    if page then Request(page) end      -- a click: allowed to go out as SAY
end

local function Build()
    frame = CreateFrame("Frame", "PartyBotCompanionSheet", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetHitRectInsets(0, 30, 0, 45)
    frame:Hide()
    UIPanelWindows["PartyBotCompanionSheet"] = { area = "left", pushable = 3, xoffset = -16, yoffset = 12,
        bottomClampOverride = 152, width = 353, height = 424, whileDead = 1 }

    frame.portrait = frame:CreateTexture(nil, "BACKGROUND")
    frame.portrait:SetSize(60, 60)
    frame.portrait:SetPoint("TOPLEFT", 7, -6)

    -- name and level float over every page (frame level above the pages)
    local top = CreateFrame("Frame", nil, frame)
    top:SetAllPoints()
    top:SetFrameLevel(frame:GetFrameLevel() + 10)
    frame.name = top:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.name:SetSize(300, 12)
    frame.name:SetPoint("CENTER", frame, "CENTER", 6, 232)
    frame.name:SetTextColor(1, 1, 1)
    frame.level = top:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.level:SetPoint("TOP", frame.name, "BOTTOM", 0, -6)

    local close = CreateFrame("Button", "PartyBotCompanionSheetCloseButton", top, "UIPanelCloseButton")
    close:SetPoint("CENTER", frame, "TOPRIGHT", -44, -25)
    close:SetScript("OnClick", function() HideUIPanel(frame) end)

    for i, page in ipairs(Sheet.pages) do
        page.frame = CreateFrame("Frame", "PartyBotCompanionSheetPage" .. page.key, frame)
        page.frame:SetAllPoints()
        page.frame:Hide()
        page.Build(page.frame, Sheet)

        local tab = CreateFrame("Button", "PartyBotCompanionSheetTab" .. i, frame, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(page.title)
        if i == 1 then
            tab:SetPoint("CENTER", frame, "BOTTOMLEFT", 60, 62)
        else
            tab:SetPoint("LEFT", _G["PartyBotCompanionSheetTab" .. (i - 1)], "RIGHT", -16, 0)
        end
        tab:SetScript("OnClick", function(self)
            PanelTemplates_Tab_OnClick(self, frame)
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            ShowPage(page.key)
        end)
        tab:SetScript("OnEnter", nil)
        PanelTemplates_TabResize(tab, 0, nil, 36, 88)
    end
    PanelTemplates_SetNumTabs(frame, #Sheet.pages)

    -- quiet: swapped in place of the player's own window, which plays its own sound
    frame:SetScript("OnShow", function() if not frame.quiet then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end end)
    frame:SetScript("OnHide", function() if not frame.quiet then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end end)
end

-- Opens the sheet of a companion from the list (call from a click). quiet: no open sound.
function Sheet.Open(guid, pageKey, quiet)
    if not frame then Build() end
    local c = ns.FindCompanion(guid)
    if not c then return end
    if current ~= guid then cache[guid] = nil end    -- fresh data for someone else
    current = guid
    if not frame:IsShown() then
        frame.quiet = quiet
        ShowUIPanel(frame)
        frame.quiet = nil
    end
    ShowPage(pageKey or currentPage or Sheet.pages[1].key)
    for _, fn in ipairs(changeHandlers) do fn(c) end
end

-- quiet: no close sound
function Sheet.Close(quiet)
    if not frame or not frame:IsShown() then return end
    frame.quiet = quiet
    HideUIPanel(frame)
    frame.quiet = nil
end

-- By name (party frame menu): the list may not be here yet.
function Sheet.OpenByName(name)
    local c = ns.FindCompanionByName(name)
    if c then Sheet.Open(c.guid) return end
    ns.RequestCompanions(function()
        local found = ns.FindCompanionByName(name)
        if found then Sheet.Open(found.guid) else ns.ShowError(L("companionsheet.not_companion", { name = name })) end
    end)
end

-- the sheet's frame (nil until first opened), for panels docked beside it (Bags.lua)
function Sheet.Frame() return frame end

-- Asks the server again for the page shown (his gear changed). From events too: may be dropped
-- outside a group, like every automatic request.
function Sheet.Reload()
    if not frame or not frame:IsShown() or not current then return end
    local page = PageByKey(currentPage)
    if page and page.server then
        ns.SendCommandAuto((".partybot companion %d %s"):format(current, page.server))
    end
end

function Sheet.Toggle(guid)
    if frame and frame:IsShown() and current == guid then HideUIPanel(frame) else Sheet.Open(guid) end
end

-- the list changed (online state, level): redraw
ns.OnCompanionsListed(Refresh)

---------------------------------------------------------------------------
-- server replies
---------------------------------------------------------------------------

ns.On("PBCMV", function(msg)
    local fields = { strsplit(";", msg) }
    local guid, kind = tonumber(fields[2]), fields[3]
    if not guid then return true end
    if kind == "BEGIN" then
        incoming[guid .. fields[4]] = { online = fields[5] == "1", lines = {} }
        incoming.last = guid .. fields[4]
    elseif kind == "END" then
        local key = guid .. fields[4]
        local data = incoming[key]
        incoming[key] = nil
        if data then
            cache[guid] = cache[guid] or {}
            cache[guid][fields[4]] = data
            if guid == current then Refresh() end
        end
    else
        local data = incoming[incoming.last]
        if data then
            local list = data.lines[kind] or {}
            data.lines[kind] = list
            list[#list + 1] = { select(4, unpack(fields)) }
        end
    end
    return true
end)
