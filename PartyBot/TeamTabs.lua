-- Team tabs over a team window (TeamBags.lua, Bank.lua): the people of the selected group as
-- portrait tabs down one side of the window (like the spellbook's side tabs: a group has at most
-- five, so they always fit, whatever their names), and the raid's groups as small number tabs in
-- the window's attic (only when more than one group has someone). Hovering a group's number while
-- holding an item switches to that group, so items can go to someone of another group.
--
--   local tabs = ns.TeamTabs.New(frame, "PartyBotXxx", {
--       left = 60,                              -- the group tabs start right of the portrait
--       onSelect = fn(number, name),            -- a tab was clicked (name nil: a group tab)
--       onMemberClick = fn(name) -> true,       -- before selecting: true if it did something else
--       onMemberDrop = fn(name),                -- something dragged onto a member tab
--       memberTip = fn(name) -> text, r, g, b,  -- an extra tooltip line, green by default (his
--                                               -- name and level are always there)
--       memberLocked = fn(name) -> bool,        -- shown grey (onSelect still decides)
--   })
--   tabs:SetSide("RIGHT" | "LEFT")              -- the side the portraits stand on (away from the
--                                               -- window it is docked to); before Layout
--   tabs:Layout(groups, selectedGroup, selectedName, anchor)   -- anchor: the inset below the attic
--   tabs:MinHeight()                            -- the window height its portraits need
--   ns.TeamTabs.INSET_TOP                       -- where the inset starts (below the attic)
--   ns.TeamTabs.SIDE_WIDTH                      -- how far the portraits stick out of the window
--   ns.TeamTabs.Groups(include)  -> { { number, names = { ... } }, ... } your group's people for
--                                   whom include(name) is true, by raid group

local _, ns = ...
local L = ns.L

local TeamTabs = {}
ns.TeamTabs = TeamTabs

TeamTabs.INSET_TOP = 60
TeamTabs.SIDE_WIDTH = 36

local MEMBER_SIZE = 32
local MEMBER_STEP = 49          -- the spellbook's spacing (32 + 17)
local GROUP_TEXT_MIN = 10        -- a number tab: its text (+ the tab's 32 px of side art)
local SWITCH_DELAY = 0.4        -- hovering a group number while holding an item

function TeamTabs.Groups(include)
    local byNumber, list = {}, {}
    local function Add(number, name)
        if not name or not include(name) then return end
        local g = byNumber[number]
        if not g then
            g = { number = number, names = {} }
            byNumber[number] = g
            list[#list + 1] = g
        end
        g.names[#g.names + 1] = name
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup = GetRaidRosterInfo(i)
            Add(subgroup or 1, name)
        end
    else
        for i = 1, GetNumSubgroupMembers() do Add(1, UnitName("party" .. i)) end
    end
    table.sort(list, function(a, b) return a.number < b.number end)
    return list
end

-- your item on the cursor, or a companion's item held by the bag grid
local function Holding()
    return GetCursorInfo() == "item" or (ns.BagGrid and ns.BagGrid.Holding())
end

local Tabs = {}
Tabs.__index = Tabs

function TeamTabs.New(frame, prefix, opts)
    return setmetatable({ frame = frame, prefix = prefix, opts = opts, side = "RIGHT",
        groupTabs = {}, memberTabs = {} }, Tabs)
end

function Tabs:SetSide(side) self.side = side == "LEFT" and "LEFT" or "RIGHT" end

---------------------------------------------------------------------------
-- people: portrait tabs down the side
---------------------------------------------------------------------------

local function Portrait(tex, name)
    local c = ns.FindCompanionByName(name)
    if c then
        ns.CompanionPortrait(tex, c)
        return c
    end
    local unit = ns.UnitOf(name)
    if unit then SetPortraitTexture(tex, unit) else tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
end

local function MemberTooltip(tab, opts)
    GameTooltip:SetOwner(tab, tab.side == "LEFT" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    GameTooltip:SetText(tab.name)
    local c = ns.FindCompanionByName(tab.name)
    if c then
        local race = ns.RaceInfo(c.race)
        GameTooltip:AddLine(PLAYER_LEVEL and PLAYER_LEVEL:format(c.level, race and race.raceName or "", ns.CLASS_TEXT[c.class] or "")
            or L("companionsheet.level_class", { level = c.level, class = ns.CLASS_TEXT[c.class] or "" }), 1, 1, 1)
    end
    if opts.memberTip then
        local extra, r, g, b = opts.memberTip(tab.name)
        if extra then GameTooltip:AddLine(extra, r or 0, g or 1, b or 0, true) end
    end
    GameTooltip:Show()
end

function Tabs:MemberTab(i)
    local tab = self.memberTabs[i]
    if tab then return tab end
    local opts = self.opts
    tab = CreateFrame("CheckButton", self.prefix .. "MemberTab" .. i, self.frame)
    tab:SetSize(MEMBER_SIZE, MEMBER_SIZE)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    tab.bg:SetSize(64, 64)
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetAllPoints()
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
    tab:RegisterForClicks("LeftButtonUp")
    tab:SetScript("OnClick", function(t)
        t:SetChecked(t.name == self.selectedName)      -- (the click toggled it; Layout decides)
        if opts.onMemberClick and opts.onMemberClick(t.name) then return end
        if t.name == self.selectedName then return end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        opts.onSelect(self.selectedGroup, t.name)
    end)
    tab:SetScript("OnReceiveDrag", function(t)
        if opts.onMemberDrop then opts.onMemberDrop(t.name) end
    end)
    tab:SetScript("OnEnter", function(t) MemberTooltip(t, opts) end)
    tab:SetScript("OnLeave", GameTooltip_Hide)
    self.memberTabs[i] = tab
    return tab
end

-- the spellbook's tab art faces right; on the left side it is mirrored
local function PlaceMember(tab, frame, side, i)
    tab.side = side
    tab:ClearAllPoints()
    tab.bg:ClearAllPoints()
    local y = -(TeamTabs.INSET_TOP + 4) - (i - 1) * MEMBER_STEP
    if side == "LEFT" then
        tab:SetPoint("TOPRIGHT", frame, "TOPLEFT", 0, y)
        tab.bg:SetPoint("TOPRIGHT", 3, 11)
        tab.bg:SetTexCoord(1, 0, 0, 1)
    else
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, y)
        tab.bg:SetPoint("TOPLEFT", -3, 11)
        tab.bg:SetTexCoord(0, 1, 0, 1)
    end
end

---------------------------------------------------------------------------
-- groups: number tabs in the attic
---------------------------------------------------------------------------

function Tabs:GroupTab(i)
    local tab = self.groupTabs[i]
    if tab then return tab end
    tab = CreateFrame("Button", self.prefix .. "GroupTab" .. i, self.frame, "TabButtonTemplate")
    tab:SetScript("OnShow", function(t) PanelTemplates_TabResize(t, 0, nil, GROUP_TEXT_MIN) end)
    tab:SetScript("OnClick", function(t)
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        self.opts.onSelect(t.number, nil)
    end)
    tab:SetScript("OnEnter", function(t)
        GameTooltip:SetOwner(t, "ANCHOR_TOP")
        GameTooltip:SetText(L("teambags.group", { number = t.number }))
        GameTooltip:Show()
        t.hoverAt = GetTime()
    end)
    tab:SetScript("OnLeave", function(t)
        t.hoverAt = nil
        GameTooltip:Hide()
    end)
    -- holding an item over it for a moment: that group (to hand the item to one of them)
    tab:SetScript("OnUpdate", function(t)
        if t.hoverAt and GetTime() - t.hoverAt >= SWITCH_DELAY then
            t.hoverAt = nil
            if Holding() and t.number ~= self.selectedGroup then self.opts.onSelect(t.number, nil) end
        end
    end)
    self.groupTabs[i] = tab
    return tab
end

-- How tall the window must be for the portraits of the last Layout (a companion without extra
-- bags has a short window).
function Tabs:MinHeight()
    local n = self.shownMembers or 0
    if n == 0 then return 0 end
    return TeamTabs.INSET_TOP + 4 + (n - 1) * MEMBER_STEP + MEMBER_SIZE + 16
end

-- Returns true if the attic shows group tabs.
function Tabs:Layout(groups, selectedGroup, selectedName, anchor)
    self.selectedGroup, self.selectedName = selectedGroup, selectedName
    for _, t in ipairs(self.groupTabs) do t:Hide() end
    for _, t in ipairs(self.memberTabs) do t:Hide() end

    local withGroups = #groups > 1
    if withGroups then
        for i, g in ipairs(groups) do
            local tab = self:GroupTab(i)
            tab.number = g.number
            tab:ClearAllPoints()
            if i == 1 then
                tab:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", self.opts.left or 60, -1)
            else
                tab:SetPoint("LEFT", self.groupTabs[i - 1], "RIGHT", 0, 0)
            end
            tab:SetText(g.number)
            PanelTemplates_TabResize(tab, 0, nil, GROUP_TEXT_MIN)
            if g.number == selectedGroup then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
            tab:Show()
        end
    end

    local names
    for _, g in ipairs(groups) do
        if g.number == selectedGroup then names = g.names end
    end
    self.shownMembers = #(names or {})
    for i, name in ipairs(names or {}) do
        local tab = self:MemberTab(i)
        tab.name = name
        tab.dropBotName = name
        PlaceMember(tab, self.frame, self.side, i)
        Portrait(tab.icon, name)
        tab.icon:SetDesaturated(self.opts.memberLocked and self.opts.memberLocked(name) or false)
        tab:SetChecked(name == selectedName)
        tab:Show()
    end
    return withGroups
end
