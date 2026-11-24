-- The addon's page in the game's Interface Options (Esc -> 界面 -> 插件 -> PartyBot), also from
-- the minimap menu. Every setting of PartyBot and its packages goes here: a file adds its own
-- section with the functions below (VoiceOptions.lua is one), the page lays them out top down.
--
--   ns.Options.AddHeader(text)
--   ns.Options.AddChoice{ label, choices = { { value, text, tip }, ... }, get = fn() -> value, set = fn(value) }
--   ns.Options.AddCheck{ label, tip, get = fn() -> bool, set = fn(bool) }
--   ns.Options.Open()
-- get is read each time the page is shown (after PartyBotDB is loaded); set runs on a click.
--
-- A package that wants its own entry in the addon list (next to PartyBot) makes a page:
--   local page = ns.Options.NewPage{ name, title, subtitle }   -- same functions as above

local _, ns = ...
local L = ns.L

local PAD = 16
local INDENT = 12

local function Tooltip(widget, label, tip)
    if not tip then return end
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function NewPage(def)
    local panel = CreateFrame("Frame")
    panel.name = def.name
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", PAD, -PAD)
    title:SetText(def.title or def.name)

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", -PAD, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(def.subtitle or "")

    local y = -64                   -- layout cursor
    local refreshers = {}           -- fn() per control, run when the page is shown

    -- a check or radio button with its label on the right
    local function Button(template, x, label, tip)
        local b = CreateFrame("CheckButton", nil, panel, template)
        b:SetPoint("TOPLEFT", x, y)
        b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        b.label:SetPoint("LEFT", b, "RIGHT", 4, 1)
        b.label:SetText(label)
        b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 8), 0, 0)
        Tooltip(b, label, tip)
        return b
    end

    local page = { panel = panel }

    function page.AddHeader(text)
        y = y - 8
        local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", PAD, y)
        h:SetText(text)
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 0.82, 0, 0.25)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -3)
        line:SetPoint("RIGHT", -PAD, 0)
        y = y - 24
    end

    function page.AddChoice(c)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("TOPLEFT", PAD + INDENT, y)
        label:SetText(c.label)
        y = y - 20
        local buttons = {}
        local function Refresh()
            local current = c.get()
            for _, b in ipairs(buttons) do b:SetChecked(b.value == current) end
        end
        for _, choice in ipairs(c.choices) do
            local b = Button("UIRadioButtonTemplate", PAD + INDENT * 2, choice[2], choice[3])
            b.value = choice[1]
            b:SetScript("OnClick", function(self)
                c.set(self.value)
                Refresh()
            end)
            buttons[#buttons + 1] = b
            y = y - 22
        end
        refreshers[#refreshers + 1] = Refresh
        y = y - 6
    end

    function page.AddCheck(c)
        local b = Button("UICheckButtonTemplate", PAD + INDENT, c.label, c.tip)
        b:SetScript("OnClick", function(self) c.set(self:GetChecked() and true or false) end)
        refreshers[#refreshers + 1] = function() b:SetChecked(c.get()) end
        y = y - 30
    end

    -- run the get functions again (a setting changed while the page is open)
    function page.Refresh()
        if not ns.db or not panel:IsVisible() then return end
        for _, fn in ipairs(refreshers) do fn() end
    end

    -- (1.14.2: the first call only opens the frame on the first category; the second selects ours)
    function page.Open()
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end

    panel:SetScript("OnShow", function()
        if not ns.db then return end
        for _, fn in ipairs(refreshers) do fn() end
    end)

    InterfaceOptions_AddCategory(panel)
    return page
end

ns.Options = NewPage({ name = L["options.name"], title = L["options.title"], subtitle = L["options.subtitle"] })
ns.Options.NewPage = NewPage

local panel = ns.Options.panel

ns.RegisterPanel({
    id = "options", title = L["options.panel"], order = 990,
    toggle = function()
        if InterfaceOptionsFrame:IsShown() and panel:IsVisible() then
            InterfaceOptionsFrame:Hide()
        else
            ns.Options.Open()
        end
    end,
    isShown = function() return panel:IsVisible() end,
})
