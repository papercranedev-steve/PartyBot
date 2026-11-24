-- A "伙伴" tab at the bottom of the player's own character window (C): opens the Companions panel
-- (Companions.lua) next to it. It is never the selected tab, it only opens the other panel.
-- It follows the last shown tab (the pet tab hides for classes without pets, honor may hide).

local _, ns = ...
local L = ns.L

local character = CharacterFrame
if not character then return end

local tab = CreateFrame("Button", "PartyBotCharacterCompanionsTab", character, "CharacterFrameTabButtonTemplate")
tab:SetText(L["companionscharactertab.tab"])
tab:SetScript("OnClick", function()
    PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    ns.ToggleCompanions()
end)
tab:SetScript("OnShow", function(self) PanelTemplates_TabResize(self, 0) end)
tab:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["companionscharactertab.tooltip.title"], 1, 1, 1)
    GameTooltip:AddLine(L["companionscharactertab.tooltip.text"], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    GameTooltip:Show()
end)
tab:SetScript("OnLeave", GameTooltip_Hide)
PanelTemplates_TabResize(tab, 0)
PanelTemplates_DeselectTab(tab)

local function Place()
    local last
    for i = 1, character.numTabs or 5 do
        local t = _G["CharacterFrameTab" .. i]
        if t and t:IsShown() then last = t end
    end
    tab:ClearAllPoints()
    if last then
        tab:SetPoint("LEFT", last, "RIGHT", -16, 0)
    else
        tab:SetPoint("TOPLEFT", character, "BOTTOMLEFT", 11, 46)
    end
    PanelTemplates_DeselectTab(tab)
end

character:HookScript("OnShow", Place)
if PetTab_Update then hooksecurefunc("PetTab_Update", Place) end
if HonorFrame_UpdateShown then hooksecurefunc("HonorFrame_UpdateShown", Place) end
