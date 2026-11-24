-- Crafting for you (design .kiro/docs/2026-11-21-companion-talk.md §3): "XX 的炼金术", the
-- native trade skill window (K) of the companion's profession, opened from the talk window's
-- "能帮我配点药水吗？" (like a vendor's "let me browse your goods"). The native window can only show
-- your own professions, so this is its own frame with the native art and layout: recipes on top
-- by category (folding), the selected one below with its materials, then [-] n [+], "全部",
-- "请他做". Colours as native: how likely making it raises HIS skill (he makes it, he learns).
-- [n] and "你有 3/5" count only YOUR bags: he uses only your materials (user 2026-11-21).
--
-- .partybot recipes <bot> <skill>   PBRCP;<bot>;BEGIN;<skill>;<value>;<max>
--                                   PBRCP;<bot>;R;<spell>;<item>;<per cast>;<difficulty 0-3>;<category>;<item:count,...>
--                                   PBRCP;<bot>;END
-- .partybot craft <bot> <spell> <count, 0 = all> | stop
--                                   PBOK;<bot>;craft;...   PBCRAFT;<bot>;made;<item>;<made>;<left>
--                                   PBCRAFT;<bot>;stop;<reason>
-- It closes when you walk away (he stops then too), on ESC and "退出"; closing it does not stop
-- him (as your own crafting goes on when the window closes).

local _, ns = ...
local L = ns.L

ns.ERROR_TEXT.noskill = L["craft.error.noskill"]
ns.ERROR_TEXT.norecipe = L["craft.error.norecipe"]

local ROWS = 8
local ROW_H = 16
local MAX_REAGENTS = 8
local CHECK_SEC = 0.3
local TALK_RANGE_INDEX = 2      -- CheckInteractDistance: trade range, a little more than the server's 10 yd

local SKILL_TEXT = {
    [171] = L["craft.skill.alchemy"], [164] = L["craft.skill.blacksmithing"], [165] = L["craft.skill.leatherworking"],
    [197] = L["craft.skill.tailoring"], [202] = L["craft.skill.engineering"],
    [333] = L["craft.skill.enchanting"], [129] = L["craft.skill.first_aid"], [185] = L["craft.skill.cooking"],
}
local SKILL_ICON = {
    [171] = "Interface\\Icons\\Trade_Alchemy", [164] = "Interface\\Icons\\Trade_BlackSmithing",
    [165] = "Interface\\Icons\\INV_Misc_ArmorKit_17", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving",
    [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", [185] = "Interface\\Icons\\INV_Misc_Food_15",
}

-- the server's categories (Shared/Crafting::CategoryOf); others are "<item class>.<subclass>"
local CATEGORY_TEXT = {
    potion = L["craft.category.potion"], elixir = L["craft.category.elixir"],
    flask = L["craft.category.flask"], transmute = L["craft.category.transmute"],
}
local CATEGORY_ORDER = { potion = 1, elixir = 2, flask = 3, transmute = 4 }

-- native trade skill colours (TradeSkillTypeColor): optimal, medium, easy, trivial; header
local DIFFICULTY = {
    [0] = { r = 1.00, g = 0.50, b = 0.25, font = "GameFontNormalLeftOrange" },
    [1] = { r = 1.00, g = 1.00, b = 0.00, font = "GameFontNormalLeftYellow" },
    [2] = { r = 0.25, g = 0.75, b = 0.25, font = "GameFontNormalLeftLightGreen" },
    [3] = { r = 0.50, g = 0.50, b = 0.50, font = "GameFontNormalLeftGrey" },
}
local HEADER_FONT = "GameFontNormalLeft"

local STOP_TEXT = {
    done = L["craft.stop.done"], nomats = L["craft.stop.nomats"], far = L["craft.stop.far"],
    combat = L["craft.stop.combat"],
    stopped = L["craft.stop.stopped"], bagsfull = L["craft.stop.bagsfull"], failed = L["craft.stop.failed"],
    cooldown = L["craft.stop.cooldown"],
    gone = L["craft.stop.gone"],
}

local function Font(name, fallback) return _G[name] and name or fallback end

---------------------------------------------------------------------------
-- state
---------------------------------------------------------------------------

local data              -- { bot, skill, value, max, recipes = { ... } }
local incoming
local collapsed = {}    -- category -> true
local selected          -- spell id
local filterText, haveOnly = "", false
local crafting          -- { spell, count, made } while he makes something for you
local list = {}         -- the rows on screen: { header = category } or { recipe = r }

local function Available(r)
    if #r.reagents == 0 then return 0 end
    local n
    for _, g in ipairs(r.reagents) do
        local can = math.floor(GetItemCount(g.id) / g.count)
        n = n and math.min(n, can) or can
    end
    return n or 0
end

local function RecipeName(r)
    local name = GetSpellInfo(r.spell)
    return name or ns.ItemName(r.item)
end

local function CategoryName(key)
    if CATEGORY_TEXT[key] then return CATEGORY_TEXT[key] end
    local class, subclass = key:match("^(%d+)%.(%d+)$")
    class, subclass = tonumber(class), tonumber(subclass)
    local name = class and GetItemSubClassInfo and GetItemSubClassInfo(class, subclass)
    if not name or name == "" then name = class and GetItemClassInfo and GetItemClassInfo(class) end
    return (name and name ~= "") and name or L["craft.category.other"]
end

local function Matches(r)
    if haveOnly and Available(r) == 0 then return false end
    if filterText == "" then return true end
    local needle = filterText:lower()
    local function Has(s) return s and s:lower():find(needle, 1, true) ~= nil end
    return Has(RecipeName(r)) or Has(GetItemInfo(r.item))
end

local function BuildList()
    wipe(list)
    if not data then return end
    local byCategory, categories = {}, {}
    for _, r in ipairs(data.recipes) do
        if Matches(r) then
            if not byCategory[r.category] then
                byCategory[r.category] = {}
                categories[#categories + 1] = r.category
            end
            table.insert(byCategory[r.category], r)
        end
    end
    table.sort(categories, function(a, b)
        local x, y = CATEGORY_ORDER[a] or 99, CATEGORY_ORDER[b] or 99
        if x ~= y then return x < y end
        return CategoryName(a) < CategoryName(b)
    end)
    for _, c in ipairs(categories) do
        list[#list + 1] = { header = c }
        if not collapsed[c] then
            table.sort(byCategory[c], function(a, b)
                if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
                return RecipeName(a) < RecipeName(b)
            end)
            for _, r in ipairs(byCategory[c]) do list[#list + 1] = { recipe = r } end
        end
    end
end

local function SelectedRecipe()
    if not data or not selected then return nil end
    for _, r in ipairs(data.recipes) do
        if r.spell == selected then return r end
    end
end

---------------------------------------------------------------------------
-- frame: the native trade skill window's art and places (Blizzard_TradeSkillUI.xml, 1.14.2)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "PartyBotCraftFrame", UIParent)
frame:SetSize(384, 512)
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:Hide()
UIPanelWindows["PartyBotCraftFrame"] = { area = "left", pushable = 3 }

local portrait = frame:CreateTexture(nil, "BACKGROUND")
portrait:SetSize(60, 60)
portrait:SetPoint("TOPLEFT", 7, -6)

local function Art(file, w, h, point)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetTexture(file)
    t:SetSize(w, h)
    t:SetPoint(point)
end
Art("Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopLeft", 256, 256, "TOPLEFT")
Art("Interface\\ClassTrainerFrame\\UI-ClassTrainer-TopRight", 128, 256, "TOPRIGHT")
Art("Interface\\TradeSkillFrame\\UI-TradeSkill-BotLeft", 256, 256, "BOTTOMLEFT")
Art("Interface\\ClassTrainerFrame\\UI-ClassTrainer-BotRight", 128, 256, "BOTTOMRIGHT")

local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
title:SetPoint("TOP", 0, -17)

do
    local left = frame:CreateTexture(nil, "ARTWORK")
    left:SetTexture("Interface\\TradeSkillFrame\\UI-TradeSkill-SkillBorder")
    left:SetSize(256, 8)
    left:SetPoint("TOPLEFT", 63, -50)
    left:SetTexCoord(0, 1, 0, 0.5)
    local right = frame:CreateTexture(nil, "ARTWORK")
    right:SetTexture("Interface\\TradeSkillFrame\\UI-TradeSkill-SkillBorder")
    right:SetSize(28, 8)
    right:SetPoint("LEFT", left, "RIGHT")
    right:SetTexCoord(0, 0.109375, 0.5, 1)
    local barLeft = frame:CreateTexture(nil, "ARTWORK")
    barLeft:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    barLeft:SetSize(256, 16)
    barLeft:SetPoint("TOPLEFT", 15, -221)
    barLeft:SetTexCoord(0, 1, 0, 0.25)
    local barRight = frame:CreateTexture(nil, "ARTWORK")
    barRight:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-HorizontalBar")
    barRight:SetSize(75, 16)
    barRight:SetPoint("LEFT", barLeft, "RIGHT")
    barRight:SetTexCoord(0, 0.29296875, 0.25, 0.5)
end

-- his rank: "炼金术 215/300"
local rank = CreateFrame("StatusBar", nil, frame)
rank:SetSize(268, 15)
rank:SetPoint("TOPLEFT", 73, -37)
rank:SetStatusBarTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar")
rank:SetStatusBarColor(0.0, 0.0, 1.0, 0.5)
do
    local bg = rank:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.0, 0.0, 0.75, 0.5)
    local border = rank:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Skills-BarBorder")
    border:SetSize(281, 32)
    border:SetPoint("LEFT", -5, 0)
end
rank.name = rank:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rank.name:SetPoint("LEFT", 6, 1)
rank.value = rank:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
rank.value:SetPoint("LEFT", rank.name, "RIGHT", 13, 0)

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -29, -8)

---------------------------------------------------------------------------
-- top bar: collapse all, search, "only what I have materials for"
---------------------------------------------------------------------------

local collapseAll = CreateFrame("Button", nil, frame)
collapseAll:SetSize(40, 22)
collapseAll:SetPoint("TOPLEFT", 23, -74)
collapseAll:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
collapseAll:GetNormalTexture():ClearAllPoints()
collapseAll:GetNormalTexture():SetSize(16, 16)
collapseAll:GetNormalTexture():SetPoint("LEFT", 3, 0)
collapseAll:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
collapseAll:GetHighlightTexture():ClearAllPoints()
collapseAll:GetHighlightTexture():SetSize(16, 16)
collapseAll:GetHighlightTexture():SetPoint("LEFT", 3, 0)
do
    local label = collapseAll:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("LEFT", 22, 0)
    label:SetText(ALL or L["craft.collapse_all"])
end

local ok, search = pcall(CreateFrame, "EditBox", "PartyBotCraftSearchBox", frame, "SearchBoxTemplate")
if not ok then search = CreateFrame("EditBox", "PartyBotCraftSearchBox", frame, "InputBoxTemplate") end
search:SetSize(118, 20)
search:SetPoint("TOPLEFT", 92, -74)
search:SetAutoFocus(false)

local have = CreateFrame("CheckButton", "PartyBotCraftHaveButton", frame, "UICheckButtonTemplate")
have:SetSize(24, 24)
have:SetPoint("TOPLEFT", 222, -72)
do
    local label = _G["PartyBotCraftHaveButtonText"] or have:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:ClearAllPoints()
    label:SetPoint("LEFT", have, "RIGHT", 0, 1)
    label:SetFontObject("GameFontNormalSmall")
    label:SetText(L["craft.have_only"])
end

---------------------------------------------------------------------------
-- the recipe list
---------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", "PartyBotCraftListScrollFrame", frame, "FauxScrollFrameTemplate")
scroll:SetSize(296, ROWS * ROW_H + 2)
scroll:SetPoint("TOPRIGHT", -67, -96)
do
    local top = scroll:CreateTexture(nil, "BACKGROUND")
    top:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    top:SetSize(31, 102)
    top:SetPoint("TOPLEFT", scroll, "TOPRIGHT", -2, 5)
    top:SetTexCoord(0, 0.484375, 0, 0.4)
    local bottom = scroll:CreateTexture(nil, "BACKGROUND")
    bottom:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
    bottom:SetSize(31, 106)
    bottom:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -2, -2)
    bottom:SetTexCoord(0.515625, 1, 0, 0.4140625)
end

local highlight = CreateFrame("Frame", nil, frame)
highlight:SetSize(293, 16)
highlight:Hide()
local highlightTex = highlight:CreateTexture(nil, "ARTWORK")
highlightTex:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
highlightTex:SetAllPoints()

local rows = {}
local Update, Select

for i = 1, ROWS do
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(293, ROW_H)
    b:SetPoint("TOPLEFT", 22, -96 - (i - 1) * ROW_H)
    b:SetFrameLevel(frame:GetFrameLevel() + 2)
    local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
    fs:SetPoint("LEFT", 20, 0)
    fs:SetPoint("RIGHT", -2, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b:SetScript("OnClick", function(self)
        local entry = self.entry
        if not entry then return end
        if entry.header then
            collapsed[entry.header] = not collapsed[entry.header] or nil
            Update()
        else
            Select(entry.recipe.spell)
        end
    end)
    b:SetScript("OnEnter", function(self)
        if self.entry and self.entry.recipe then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.entry.recipe.item)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = b
end

scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() Update() end)
end)

---------------------------------------------------------------------------
-- the selected recipe
---------------------------------------------------------------------------

local detail = CreateFrame("ScrollFrame", "PartyBotCraftDetailScrollFrame", frame, "UIPanelScrollFrameTemplate")
detail:SetSize(297, 176)
detail:SetPoint("TOPLEFT", 20, -234)
local child = CreateFrame("Frame", nil, detail)
child:SetSize(297, 150)
detail:SetScrollChild(child)

do
    local left = child:CreateTexture(nil, "BACKGROUND")
    left:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-DetailHeaderLeft")
    left:SetSize(256, 64)
    left:SetPoint("TOPLEFT", 0, 3)
    local right = child:CreateTexture(nil, "BACKGROUND")
    right:SetTexture("Interface\\ClassTrainerFrame\\UI-ClassTrainer-DetailHeaderRight")
    right:SetSize(64, 64)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT")
end

local icon = CreateFrame("Button", nil, child)
icon:SetSize(37, 37)
icon:SetPoint("TOPLEFT", 8, -3)
icon.texture = icon:CreateTexture(nil, "ARTWORK")
icon.texture:SetAllPoints()
icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
icon.count:SetPoint("BOTTOMRIGHT", -5, 2)
icon:SetScript("OnEnter", function(self)
    local r = SelectedRecipe()
    if r then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. r.item)
        GameTooltip:Show()
    end
end)
icon:SetScript("OnLeave", GameTooltip_Hide)
icon:SetScript("OnClick", function()
    local r = SelectedRecipe()
    local _, link = r and GetItemInfo(r.item)
    if link then HandleModifiedItemClick(link) end
end)

local recipeName = child:CreateFontString(nil, "ARTWORK", "GameFontNormal")
recipeName:SetPoint("TOPLEFT", 50, -5)
recipeName:SetWidth(244)
recipeName:SetJustifyH("LEFT")

local recipeLine = child:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
recipeLine:SetPoint("TOPLEFT", recipeName, "BOTTOMLEFT", 0, -2)
recipeLine:SetWidth(244)
recipeLine:SetJustifyH("LEFT")

local reagentLabel = child:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
reagentLabel:SetPoint("TOPLEFT", 8, -47)
reagentLabel:SetText(SPELL_REAGENTS or L["craft.reagents"])

local reagents = {}
for i = 1, MAX_REAGENTS do
    local name = "PartyBotCraftReagent" .. i
    local b = CreateFrame("Button", name, child, "QuestItemTemplate")
    if i == 1 then
        b:SetPoint("TOPLEFT", reagentLabel, "BOTTOMLEFT", -5, -3)
    elseif i % 2 == 0 then
        b:SetPoint("LEFT", reagents[i - 1], "RIGHT", 0, 0)
    else
        b:SetPoint("TOPLEFT", reagents[i - 2], "BOTTOMLEFT", 0, -2)
    end
    b.icon = _G[name .. "IconTexture"]
    b.name = _G[name .. "Name"]
    b.countText = _G[name .. "Count"]
    b:SetScript("OnEnter", function(self)
        if self.itemId then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetHyperlink("item:" .. self.itemId)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnClick", function(self)
        local _, link = self.itemId and GetItemInfo(self.itemId)
        if link then HandleModifiedItemClick(link) end
    end)
    b:Hide()
    reagents[i] = b
end

---------------------------------------------------------------------------
-- bottom: status, [-] n [+], 全部, 请他做, 退出
---------------------------------------------------------------------------

-- what he is doing (under his rank bar)
local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
status:SetPoint("TOPLEFT", 76, -57)
status:SetWidth(262)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)

local create = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
create:SetSize(80, 22)
create:SetPoint("CENTER", frame, "TOPLEFT", 224, -422)
create:SetText(L["craft.create"])

local exit = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
exit:SetSize(80, 22)
exit:SetPoint("CENTER", frame, "TOPLEFT", 305, -422)
exit:SetText(EXIT or L["craft.exit"])
exit:SetScript("OnClick", function() HideUIPanel(frame) end)

local createAll = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
createAll:SetSize(80, 22)
createAll:SetPoint("RIGHT", create, "LEFT", -86, 0)
createAll:SetText(L["craft.create_all"])

local function PageButton(prefix)
    local b = CreateFrame("Button", nil, frame)
    b:SetSize(23, 22)
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end
local decrement = PageButton("PrevPage")
decrement:SetPoint("LEFT", createAll, "RIGHT", 3, 0)

local input = CreateFrame("EditBox", "PartyBotCraftInputBox", frame, "InputBoxTemplate")
input:SetSize(30, 20)
input:SetPoint("LEFT", decrement, "RIGHT", 6, 0)
input:SetNumeric(true)
input:SetMaxLetters(3)
input:SetAutoFocus(false)
input:SetJustifyH("CENTER")
input:SetNumber(1)
input:SetScript("OnEnterPressed", input.ClearFocus)
input:SetScript("OnEscapePressed", input.ClearFocus)
input:SetScript("OnTextChanged", function(self)
    if self:GetText() == "0" then self:SetText("1") end
end)

local increment = PageButton("NextPage")
increment:SetPoint("RIGHT", create, "LEFT", -3, 0)

decrement:SetScript("OnClick", function()
    input:SetNumber(math.max(1, input:GetNumber() - 1))
    input:ClearFocus()
end)
increment:SetScript("OnClick", function()
    input:SetNumber(math.min(999, input:GetNumber() + 1))
    input:ClearFocus()
end)

---------------------------------------------------------------------------
-- drawing
---------------------------------------------------------------------------

local function ShowDetail()
    local r = SelectedRecipe()
    if not r then
        icon:Hide()
        recipeName:SetText("")
        recipeLine:SetText("")
        reagentLabel:Hide()
        for _, b in ipairs(reagents) do b:Hide() end
        return
    end
    icon:Show()
    reagentLabel:Show()
    icon.texture:SetTexture(GetItemIcon(r.item) or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon.count:SetText(r.count > 1 and r.count or "")
    recipeName:SetText(RecipeName(r))
    local itemName, _, quality = GetItemInfo(r.item)
    if itemName and quality and ITEM_QUALITY_COLORS[quality] then
        recipeLine:SetText(ITEM_QUALITY_COLORS[quality].hex .. itemName .. "|r")
    else
        recipeLine:SetText("")
    end
    for i, b in ipairs(reagents) do
        local g = r.reagents[i]
        if g then
            b.itemId = g.id
            local haveCount = GetItemCount(g.id)
            if b.icon then
                b.icon:SetTexture(GetItemIcon(g.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
                local shade = haveCount >= g.count and 1 or 0.5
                b.icon:SetVertexColor(shade, shade, shade)
            end
            if b.name then
                b.name:SetText(GetItemInfo(g.id) or ns.ItemName(g.id))
                local c = haveCount >= g.count and HIGHLIGHT_FONT_COLOR or GRAY_FONT_COLOR
                b.name:SetTextColor(c.r, c.g, c.b)
            end
            if b.countText then
                local shown = haveCount >= 100 and "*" or tostring(haveCount)
                b.countText:SetText(shown .. " /" .. g.count)
                if haveCount >= g.count then b.countText:SetTextColor(1, 1, 1) else b.countText:SetTextColor(1, 0.1, 0.1) end
            end
            b:Show()
        else
            b.itemId = nil
            b:Hide()
        end
    end
    detail:UpdateScrollChildRect()
end

local function UpdateButtons()
    local r = SelectedRecipe()
    if crafting then
        create:SetText(L["craft.stop"])
        create:Enable()
        createAll:Disable()
    else
        create:SetText(L["craft.create"])
        local can = r and Available(r) > 0
        create:SetEnabled(can and true or false)
        createAll:SetEnabled(can and true or false)
    end
end

Update = function()
    if not data then return end
    title:SetText(L("craft.title", { name = data.bot, skill = SKILL_TEXT[data.skill] or "" }))
    rank.name:SetText(SKILL_TEXT[data.skill] or "")
    rank:SetMinMaxValues(0, math.max(1, data.max))
    rank:SetValue(data.value)
    rank.value:SetText(data.value .. "/" .. data.max)
    SetPortraitToTexture(portrait, SKILL_ICON[data.skill] or "Interface\\Icons\\INV_Misc_QuestionMark")

    BuildList()
    FauxScrollFrame_Update(scroll, #list, ROWS, ROW_H, nil, nil, nil, highlight, 293, 316)
    local offset = FauxScrollFrame_GetOffset(scroll)
    local width = scroll:IsShown() and 293 or 323
    highlight:Hide()
    local anyCollapsed = false
    for c in pairs(collapsed) do anyCollapsed = true break end
    for i, b in ipairs(rows) do
        local entry = list[offset + i]
        b.entry = entry
        b:SetWidth(width)
        b:UnlockHighlight()
        if not entry then
            b:Hide()
        elseif entry.header then
            b:SetNormalFontObject(Font(HEADER_FONT, "GameFontNormal"))
            b:SetText(CategoryName(entry.header))
            b:SetNormalTexture(collapsed[entry.header] and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            local t = b:GetNormalTexture()
            t:ClearAllPoints()
            t:SetSize(16, 16)
            t:SetPoint("LEFT", 3, 0)
            b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
            local h = b:GetHighlightTexture()
            h:ClearAllPoints()
            h:SetSize(16, 16)
            h:SetPoint("LEFT", 3, 0)
            b:Show()
        else
            local r = entry.recipe
            local color = DIFFICULTY[r.difficulty] or DIFFICULTY[3]
            b:SetNormalFontObject(Font(color.font, "GameFontNormal"))
            b:SetNormalTexture("")
            b:SetHighlightTexture("")
            local n = Available(r)
            b:SetText(n > 0 and (" " .. RecipeName(r) .. " [" .. n .. "]") or (" " .. RecipeName(r)))
            if r.spell == selected then
                highlight:ClearAllPoints()
                highlight:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                highlight:SetWidth(width)
                highlightTex:SetVertexColor(color.r, color.g, color.b)
                highlight:Show()
                b:LockHighlight()
            end
            b:Show()
        end
    end
    collapseAll:SetNormalTexture(anyCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    local t = collapseAll:GetNormalTexture()
    t:ClearAllPoints()
    t:SetSize(16, 16)
    t:SetPoint("LEFT", 3, 0)
    ShowDetail()
    UpdateButtons()
end

Select = function(spell)
    selected = spell
    input:SetNumber(1)
    Update()
end

collapseAll:SetScript("OnClick", function()
    local anyCollapsed = next(collapsed) ~= nil
    wipe(collapsed)
    if not anyCollapsed and data then
        for _, r in ipairs(data.recipes) do collapsed[r.category] = true end
    end
    Update()
end)

search:HookScript("OnTextChanged", function(self)
    filterText = self:GetText() or ""
    Update()
end)
have:SetScript("OnClick", function(self)
    haveOnly = self:GetChecked() and true or false
    Update()
end)

---------------------------------------------------------------------------
-- asking him
---------------------------------------------------------------------------

local function Ask(count)
    local r = SelectedRecipe()
    if not data or not r then return end
    input:ClearFocus()
    ns.SendCommand((".partybot craft %s %d %d"):format(data.bot, r.spell, count))
end

create:SetScript("OnClick", function()
    if crafting then
        ns.SendCommand(".partybot craft " .. data.bot .. " stop")
        return
    end
    Ask(math.max(1, input:GetNumber()))
end)
createAll:SetScript("OnClick", function()
    local r = SelectedRecipe()
    if r then input:SetNumber(math.max(1, Available(r))) end
    Ask(0)
end)

-- walked away: it closes (he stops by himself at the server's range)
local sinceCheck = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck < CHECK_SEC or not data then return end
    sinceCheck = 0
    local unit = ns.UnitOf(data.bot)
    if not unit or not CheckInteractDistance(unit, TALK_RANGE_INDEX) then HideUIPanel(frame) end
end)

frame:SetScript("OnShow", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
    Update()
end)
frame:SetScript("OnHide", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    search:ClearFocus()
    input:ClearFocus()
end)

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function()
    if frame:IsShown() then Update() end
end)

-- the talk window's "能帮我配点药水吗？" (Talk.lua): his recipes, then the window
ns.talkWindows = ns.talkWindows or {}
ns.talkWindows.craft = function(bot, skill)
    if not ns.SendCommandAuto((".partybot recipes %s %s"):format(bot, skill or "")) then
        ns.ShowError(L["craft.need_party"])
    end
end

---------------------------------------------------------------------------
-- server lines
---------------------------------------------------------------------------

ns.On("PBRCP", function(msg)
    local _, bot, kind = strsplit(";", msg, 4)
    if kind == "BEGIN" then
        local _, _, _, skill, value, max = strsplit(";", msg)
        incoming = { bot = bot, skill = tonumber(skill) or 0, value = tonumber(value) or 0, max = tonumber(max) or 0, recipes = {} }
    elseif kind == "R" and incoming and incoming.bot == bot then
        local _, _, _, spell, item, count, difficulty, category, mats = strsplit(";", msg, 9)
        local r = {
            spell = tonumber(spell), item = tonumber(item), count = tonumber(count) or 1,
            difficulty = tonumber(difficulty) or 3, category = category or "0.0", reagents = {},
        }
        for id, n in (mats or ""):gmatch("(%d+):(%d+)") do
            r.reagents[#r.reagents + 1] = { id = tonumber(id), count = tonumber(n) }
            GetItemInfo(tonumber(id))
        end
        GetItemInfo(r.item)
        incoming.recipes[#incoming.recipes + 1] = r
    elseif kind == "END" and incoming and incoming.bot == bot then
        local sameWindow = data and data.bot == incoming.bot and data.skill == incoming.skill
        data = incoming
        incoming = nil
        if not sameWindow then
            selected, crafting = nil, nil
            wipe(collapsed)
            status:SetText("")
        end
        if not SelectedRecipe() then
            BuildList()
            for _, e in ipairs(list) do
                if e.recipe then selected = e.recipe.spell break end
            end
        end
        if frame:IsShown() then Update() else ShowUIPanel(frame) end
    end
    return true
end)

ns.On("PBCRAFT", function(msg)
    local _, bot, kind, a, b, c = strsplit(";", msg)
    if not data or data.bot ~= bot then return true end
    if kind == "made" then
        crafting = crafting or {}
        local item, made, left = tonumber(a), tonumber(b) or 0, tonumber(c) or 0
        status:SetText(L("craft.made", { made = made, item = item and L("craft.made_item", { item = ns.ItemName(item) }) or "", left = left }))
        if frame:IsShown() then Update() end
    elseif kind == "stop" then
        crafting = nil
        status:SetText(STOP_TEXT[a] or STOP_TEXT.stopped)
        if a ~= "done" and a ~= "stopped" then ns.ShowError(L("craft.stop_error", { name = bot, reason = STOP_TEXT[a] or STOP_TEXT.stopped })) end
        if frame:IsShown() then Update() end
        -- his skill may have risen: the colours again
        if frame:IsShown() then ns.SendCommandAuto((".partybot recipes %s %d"):format(bot, data.skill)) end
    end
    return true
end)

ns.On("PBOK", function(msg)
    local bot, what = msg:match("^PBOK;([^;]*);craft;([^;]*)")
    if not bot then return false end
    if data and data.bot == bot and what ~= "stop" then
        crafting = { spell = tonumber(what) }
        status:SetText(L["craft.started"])
        if frame:IsShown() then Update() end
    end
    return true
end)
