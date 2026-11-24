-- Party portraits beside the character window (C) and the companion sheet, like a party bar in
-- Baldur's Gate: you and your group in rectangular portraits, five at a time (in a raid one raid
-- group per page, arrows on top). A click swaps the window in place to that person, on the same
-- kind of tab: you -> Blizzard's CharacterFrame, a companion -> his sheet (CompanionSheet.lua).
-- Shown only while one of your companions is in the group. Others (real players, bots that are not
-- yours) are greyed out and do nothing. Both windows move right to make room (their xoffset).

local _, ns = ...
local L = ns.L
local Sheet = ns.Sheet

local character = CharacterFrame
if not character or not Sheet then return end

local PER_PAGE = 5
local CARD_W, CARD_H, CARD_GAP = 52, 64, 6
local PAGER_H = 22
local STRIP_GAP, STRIP_TOP = 4, -14        -- from the window's top left corner
local XOFFSET_PLAIN = -16                  -- the windows' own UIPanelWindows xoffset
local XOFFSET_STRIP = XOFFSET_PLAIN + CARD_W + STRIP_GAP + 8
local LIST_RETRY_SECONDS = 30

-- character window sub frame <-> sheet page (same tab slot: the pet tab is the affinity tab;
-- the honor tab and the sheet's quest tab have no match, they swap to the first tab)
local PAGE_OF_SUBFRAME = {
    PaperDollFrame = "character", PetPaperDollFrame = "affinity",
    ReputationFrame = "reputation", SkillFrame = "skills",
}
local SUBFRAME_OF_PAGE = {}
for sub, page in pairs(PAGE_OF_SUBFRAME) do SUBFRAME_OF_PAGE[page] = sub end

local strip = CreateFrame("Frame", "PartyBotPartyPortraits", UIParent)
strip:SetSize(CARD_W, PAGER_H + PER_PAGE * (CARD_H + CARD_GAP))
strip:Hide()

local cards = {}
local viewGroup             -- raid group shown (1 in a party)
local sheetHooked
local pendingPosition       -- a window to move once combat ends
local listAskedAt = 0

---------------------------------------------------------------------------
-- the group
---------------------------------------------------------------------------

-- everyone in display order: { unit, name, group, companion }
local function Members()
    local list = {}
    local function Add(unit, group, index)
        local name = UnitName(unit)
        if not name then return end
        list[#list + 1] = { unit = unit, name = name, group = group, index = index,
            companion = not UnitIsUnit(unit, "player") and ns.FindCompanionByName(name) or nil }
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, _, group = GetRaidRosterInfo(i)
            Add(UnitIsUnit("raid" .. i, "player") and "player" or "raid" .. i, group or 1, i)
        end
        table.sort(list, function(a, b)
            if a.group ~= b.group then return a.group < b.group end
            return a.index < b.index
        end)
    elseif IsInGroup() then
        Add("player", 1, 0)
        for i = 1, GetNumSubgroupMembers() do Add("party" .. i, 1, i) end
    end
    return list
end

local function HasCompanion(members)
    for _, m in ipairs(members) do
        if m.companion then return true end
    end
    return false
end

-- the window the strip belongs to right now
local function Owner()
    if character:IsShown() then return character end
    local sheet = Sheet.Frame()
    if sheet and sheet:IsShown() then return sheet end
end

-- the name shown in the window
local function ShownName(owner)
    if owner == character then return UnitName("player") end
    local c = Sheet.Current()
    return c and c.name
end

---------------------------------------------------------------------------
-- room for the strip: the windows' xoffset (UIParent's panel layout reads it)
---------------------------------------------------------------------------

local offsets = {}          -- [frame] = xoffset set (UIParent's GetUIPanelAttribute is local)
local function PlacePanel(frame, wanted)
    if not frame or not UIPanelWindows[frame:GetName()] or offsets[frame] == wanted then return end
    offsets[frame] = wanted
    SetUIPanelAttribute(frame, "xoffset", wanted)
    if frame:IsShown() then
        if InCombatLockdown() then pendingPosition = frame else UpdateUIPanelPositions(frame) end
    end
end

local function PlacePanels(withStrip)
    local x = withStrip and XOFFSET_STRIP or XOFFSET_PLAIN
    PlacePanel(character, x)
    PlacePanel(Sheet.Frame(), x)
end

---------------------------------------------------------------------------
-- cards
---------------------------------------------------------------------------

local BORDER_NORMAL = { 0.55, 0.55, 0.55 }
local BORDER_SELECTED = { 1, 0.82, 0 }

local function SetPortrait(card, m)
    local visible = UnitIsVisible(m.unit) and UnitIsConnected(m.unit)
    local key = m.unit .. m.name .. (visible and "1" or "0")
    if card.portraitKey == key then return end
    card.portraitKey = key
    if visible then
        card.model:Show()
        card.still:Hide()
        card.model:SetUnit(m.unit)
        card.model:SetPortraitZoom(1)
        return
    end
    -- the client has no model for him (far away, offline): his race portrait
    card.model:Hide()
    local c = m.companion
    local file = c and ns.RacePortrait(c.race, c.gender)
    if not file then
        local _, raceFile = UnitRace(m.unit)
        if raceFile then
            file = "Interface\\CharacterFrame\\TemporaryPortrait-" .. (UnitSex(m.unit) == 3 and "Female" or "Male") .. "-" .. raceFile
        end
    end
    card.still:SetTexture(file or ns.COMPANIONS_ICON)
    card.still:Show()
end

local function ShowTooltip(card)
    local m = card.member
    if not m then return end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    local className, classFile = UnitClass(m.unit)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    GameTooltip:SetText(m.name, color and color.r or 1, color and color.g or 1, color and color.b or 1)
    local level = m.companion and m.companion.level or UnitLevel(m.unit)
    if PLAYER_LEVEL and level and level > 0 then
        GameTooltip:AddLine(PLAYER_LEVEL:format(level, UnitRace(m.unit) or "", className or ""), 1, 1, 1)
    end
    if not UnitIsConnected(m.unit) then
        GameTooltip:AddLine(PLAYER_OFFLINE, 0.5, 0.5, 0.5)
    end
    if m.unit ~= "player" and not m.companion then
        GameTooltip:AddLine(L["partyportraits.not_companion"], 0.5, 0.5, 0.5)
    end
    GameTooltip:Show()
end

local Update    -- below

-- swaps the window to member `m` (a click)
local function Select(m)
    local owner = Owner()
    if not owner or m.name == ShownName(owner) then return end
    if m.unit == "player" then
        if InCombatLockdown() then return ns.ShowError(ERR_NOT_IN_COMBAT) end
        local sub = SUBFRAME_OF_PAGE[Sheet.CurrentPage() or ""] or "PaperDollFrame"
        Sheet.Close(true)
        ToggleCharacter(sub)
        -- (no pet, honor off: that tab does not open)
        if not character:IsShown() then ToggleCharacter("PaperDollFrame") end
    elseif m.companion then
        if owner == character then
            if InCombatLockdown() then return ns.ShowError(ERR_NOT_IN_COMBAT) end
            local sub = CHARACTERFRAME_SUBFRAMES and CHARACTERFRAME_SUBFRAMES[character.selectedTab or 1]
            HideUIPanel(character)
            Sheet.Open(m.companion.guid, PAGE_OF_SUBFRAME[sub or ""] or "character", true)
        else
            PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
            Sheet.Open(m.companion.guid)
        end
    end
    Update()
end

local function CreateCard(i)
    local card = CreateFrame("Button", "PartyBotPartyPortrait" .. i, strip, "BackdropTemplate")
    card:SetSize(CARD_W, CARD_H)
    card:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0, 0, 0, 1)

    card.model = CreateFrame("PlayerModel", nil, card)
    card.model:SetPoint("TOPLEFT", 4, -4)
    card.model:SetPoint("BOTTOMRIGHT", -4, 4)
    card.still = card:CreateTexture(nil, "ARTWORK")
    card.still:SetPoint("TOPLEFT", 4, -4)
    card.still:SetPoint("BOTTOMRIGHT", -4, 4)
    card.still:SetTexCoord(0.15, 0.85, 0.08, 0.92)

    -- above the model: grey shade, hover light, level
    local top = CreateFrame("Frame", nil, card)
    top:SetPoint("TOPLEFT", 4, -4)
    top:SetPoint("BOTTOMRIGHT", -4, 4)
    top:SetFrameLevel(card.model:GetFrameLevel() + 2)
    card.shade = top:CreateTexture(nil, "ARTWORK")
    card.shade:SetAllPoints()
    card.shade:SetColorTexture(0, 0, 0, 0.6)
    card.hover = top:CreateTexture(nil, "OVERLAY")
    card.hover:SetAllPoints()
    card.hover:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    card.hover:SetBlendMode("ADD")
    card.hover:SetAlpha(0.5)
    card.hover:Hide()
    card.level = top:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    card.level:SetPoint("BOTTOMRIGHT", -1, 2)

    card:SetScript("OnEnter", function(self)
        self.hover:SetShown(self.usable)
        ShowTooltip(self)
    end)
    card:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip_Hide()
    end)
    card:SetScript("OnClick", function(self)
        if self.usable and self.member then Select(self.member) end
    end)
    return card
end

for i = 1, PER_PAGE do
    local card = CreateCard(i)
    card:SetPoint("TOPLEFT", 0, -PAGER_H - (i - 1) * (CARD_H + CARD_GAP))
    cards[i] = card
end

---------------------------------------------------------------------------
-- pager (raid groups)
---------------------------------------------------------------------------

local pager = CreateFrame("Frame", nil, strip)
pager:SetPoint("TOPLEFT")
pager:SetSize(CARD_W, PAGER_H)
pager:EnableMouse(true)
pager.text = pager:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pager.text:SetPoint("CENTER")
pager:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L("partyportraits.group", { n = viewGroup or 1 }))
    GameTooltip:Show()
end)
pager:SetScript("OnLeave", GameTooltip_Hide)

local groupsShown = {}      -- the raid groups that have someone, ascending

local function PagerButton(art, step, point)
    local b = CreateFrame("Button", nil, pager)
    b:SetSize(20, 20)
    b:SetPoint(point)
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "Page-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
        viewGroup = ns.Cycle(groupsShown, viewGroup, step)
        Update()
    end)
    return b
end
pager.prev = PagerButton("Prev", -1, "LEFT")
pager.next = PagerButton("Next", 1, "RIGHT")

---------------------------------------------------------------------------
-- update
---------------------------------------------------------------------------

-- members the list does not know may be companions it has not heard of yet (just joined)
local function AskForList(members)
    if GetTime() - listAskedAt < LIST_RETRY_SECONDS then return end
    for _, m in ipairs(members) do
        if m.unit ~= "player" and not m.companion then
            listAskedAt = GetTime()
            ns.SendCommandAuto(".partybot companions")
            return
        end
    end
end

Update = function()
    local owner = Owner()
    local members = owner and Members() or {}
    local show = owner and HasCompanion(members)
    PlacePanels(show)
    if owner then AskForList(members) end
    if not show then
        strip:Hide()
        return
    end

    if strip:GetParent() ~= owner then
        strip:SetParent(owner)
        strip:ClearAllPoints()
        strip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -STRIP_GAP, STRIP_TOP)
        strip:SetFrameLevel(owner:GetFrameLevel() + 20)
        for _, card in ipairs(cards) do card.portraitKey = nil end   -- models redraw after a reparent
    end

    -- the raid groups with someone; stay on the one looked at, else yours
    wipe(groupsShown)
    local mine
    for _, m in ipairs(members) do
        if groupsShown[#groupsShown] ~= m.group then groupsShown[#groupsShown + 1] = m.group end
        if m.unit == "player" then mine = m.group end
    end
    if not tContains(groupsShown, viewGroup) then viewGroup = mine or groupsShown[1] end
    local paged = #groupsShown > 1
    pager:SetShown(paged)
    pager.text:SetText(viewGroup)
    strip:Show()    -- (before the models: a hidden model does not take its unit)

    local shownName = ShownName(owner)
    local i = 0
    for _, m in ipairs(members) do
        if m.group == viewGroup and i < PER_PAGE then
            i = i + 1
            local card = cards[i]
            card.member = m
            card.usable = m.unit == "player" or m.companion ~= nil
            SetPortrait(card, m)
            card.shade:SetShown(not card.usable or not UnitIsConnected(m.unit))
            local level = m.companion and m.companion.level or UnitLevel(m.unit)
            card.level:SetText(level and level > 0 and level or "")
            local border = m.name == shownName and BORDER_SELECTED or BORDER_NORMAL
            card:SetBackdropBorderColor(border[1], border[2], border[3])
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", 0, -(paged and PAGER_H or 0) - (i - 1) * (CARD_H + CARD_GAP))
            card:Show()
        end
    end
    for j = i + 1, PER_PAGE do
        cards[j].member = nil
        cards[j]:Hide()
    end
end

---------------------------------------------------------------------------
-- hooks and events
---------------------------------------------------------------------------

character:HookScript("OnShow", Update)
character:HookScript("OnHide", Update)

-- the sheet is built on its first open: hook it then
Sheet.OnChange(function()
    local sheet = Sheet.Frame()
    if not sheetHooked and sheet then
        sheetHooked = true
        sheet:HookScript("OnShow", Update)
        sheet:HookScript("OnHide", Update)
    end
    Update()
end)

ns.OnCompanionsListed(function() if Owner() then Update() end end)

local events = CreateFrame("Frame")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_CONNECTION")
events:RegisterEvent("UNIT_LEVEL")
events:RegisterEvent("UNIT_MODEL_CHANGED")
events:RegisterEvent("UNIT_PORTRAIT_UPDATE")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingPosition and pendingPosition:IsShown() then UpdateUIPanelPositions(pendingPosition) end
        pendingPosition = nil
        return
    end
    if not strip:IsShown() and not Owner() then return end
    if event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" then
        -- he came into view or changed looks: redraw his portrait
        for _, card in ipairs(cards) do
            if card.member and unit and UnitIsUnit(card.member.unit, unit) then card.portraitKey = nil end
        end
    end
    Update()
end)
