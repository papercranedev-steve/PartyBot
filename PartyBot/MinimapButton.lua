-- Minimap button: left-click opens a menu of all windows, right-click the AI command panel,
-- drag moves it around the minimap edge.
-- Position is saved as an angle in PartyBotDB.minimapAngle (degrees, 0 = right, counter-clockwise).

local _, ns = ...
local L = ns.L

local DEFAULT_ANGLE = 200
local RADIUS = 80

local button = CreateFrame("Button", "PartyBotMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(17, 17)
icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Human_01")
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetPoint("TOPLEFT", 7, -6)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local function Place(angle)
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    ns.db.minimapAngle = angle
    Place(angle)
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", OnDragUpdate)
end)
button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

---------------------------------------------------------------------------
-- left-click menu: one line per registered window (ns.RegisterPanel)
---------------------------------------------------------------------------

local MENU_W, LINE_H = 190, 22

local menu = CreateFrame("Frame", "PartyBotMinimapMenu", UIParent, "BackdropTemplate")
menu:SetFrameStrata("DIALOG")
menu:SetWidth(MENU_W)
menu:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
menu:SetBackdropColor(0, 0, 0, 0.9)
menu:Hide()
tinsert(UISpecialFrames, "PartyBotMinimapMenu")

local lines = {}
local awaySince

local function BuildMenu()
    for i, p in ipairs(ns.panels) do
        local line = lines[i]
        if not line then
            line = CreateFrame("Button", nil, menu)
            line:SetSize(MENU_W - 16, LINE_H)
            line:SetPoint("TOPLEFT", 8, -6 - (i - 1) * LINE_H)
            line:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line.text:SetPoint("LEFT", 6, 0)
            line.hint = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            line.hint:SetPoint("RIGHT", -6, 0)
            line:SetScript("OnClick", function(self)
                menu:Hide()
                ns.TogglePanel(self.id)
            end)
            lines[i] = line
        end
        line.id = p.id
        local mark = (p.isShown and p.isShown()) and "|cff20ff20● |r" or "    "
        line.text:SetText(mark .. p.title)
        line.hint:SetText(p.hint or "")
        line:Show()
    end
    for i = #ns.panels + 1, #lines do lines[i]:Hide() end
    menu:SetHeight(12 + #ns.panels * LINE_H)
end

-- closes by itself once the mouse has been away from the menu and the button for a moment
menu:SetScript("OnUpdate", function(self)
    if MouseIsOver(self) or MouseIsOver(button) then
        awaySince = nil
    elseif not awaySince then
        awaySince = GetTime()
    elseif GetTime() - awaySince > 1.5 then
        self:Hide()
    end
end)

local function ToggleMenu()
    if menu:IsShown() then menu:Hide() return end
    BuildMenu()
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 8, 8)
    awaySince = nil
    menu:Show()
end

button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
        ToggleMenu()
    elseif mouseButton == "RightButton" then
        menu:Hide()
        ns.TogglePanel(ns.quickPanel)
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["minimapbutton.tip.title"])
    GameTooltip:AddLine(L["minimapbutton.tip.left"], 1, 1, 1)
    local quick = ns.FindPanel(ns.quickPanel)
    if quick then
        GameTooltip:AddLine(L("minimapbutton.tip.right", { panel = quick.title }), 1, 1, 1)
    end
    GameTooltip:AddLine(L["minimapbutton.tip.drag"], 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

button:Hide()
ns.OnLoad(function()
    Place(ns.db.minimapAngle or DEFAULT_ANGLE)
    button:Show()
end)
