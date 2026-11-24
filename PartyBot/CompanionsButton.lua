-- Bottom bar (micro menu) button of the Companions panel (Companions.lua).
--
-- The bar is full once the talent button shows (level 10), so the button takes the Help
-- button's place: Help is hidden (it is still in the game menu). Built like the Character
-- button: its empty frame art with a portrait inside, the portrait shifted while pushed.
-- Only anchors and textures, nothing protected: safe in combat.

local _, ns = ...
local L = ns.L

local help = HelpMicroButton
local menu = MainMenuMicroButton
if not help or not menu then return end

local button = CreateFrame("Button", "PartyBotCompanionsMicroButton", help:GetParent(), "MainMenuBarMicroButton")
button:SetNormalTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Up")
button:SetPushedTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Down")
button:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
button:SetPoint("BOTTOMLEFT", menu, "BOTTOMRIGHT", -3, 0)
button.tooltipText = L["companionsbutton.tooltip"]
button.newbieText = L["companionsbutton.newbie"]

local portrait = button:CreateTexture(nil, "OVERLAY")
portrait:SetSize(18, 25)
portrait:SetPoint("TOP", 0, -28)
portrait:SetTexture(ns.COMPANIONS_ICON)

-- like CharacterMicroButton_SetPushed / _SetNormal
local function SetPushed()
    portrait:SetTexCoord(0.2666, 0.8666, 0, 0.8333)
    portrait:SetAlpha(0.5)
end

local function SetNormal()
    portrait:SetTexCoord(0.2, 0.8, 0.0666, 0.9)
    portrait:SetAlpha(1)
end

local function UpdateState()
    if PartyBotCompanionsFrame and PartyBotCompanionsFrame:IsShown() then
        button:SetButtonState("PUSHED", true)
        SetPushed()
    else
        button:SetButtonState("NORMAL")
        SetNormal()
    end
end

-- Toggled on mouse up, like the Character button: changing the button state in OnMouseUp
-- cancels the click, so there is no OnClick.
button:SetScript("OnMouseDown", function(_, mouseButton)
    if mouseButton == "LeftButton" then SetPushed() end
end)
button:SetScript("OnMouseUp", function(self, mouseButton)
    if mouseButton == "LeftButton" and self:IsMouseOver() then
        ns.ToggleCompanions()
    end
    UpdateState()
end)
ns.OnCompanionsShown = UpdateState

-- Help stays hidden; the button follows the bar when Blizzard moves or re-parents it
help:Hide()
hooksecurefunc(help, "Show", help.Hide)
hooksecurefunc("UpdateMicroButtons", UpdateState)
if UpdateMicroButtonsParent then
    hooksecurefunc("UpdateMicroButtonsParent", function(parent) button:SetParent(parent) end)
end

UpdateState()
