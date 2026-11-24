-- The dialog page a companion talks to you on, like an NPC: above the action bars, the
-- speaker's portrait on the left (the real 3D model when the client has a unit for the bot, else
-- a race portrait or the class icon), parchment with a gold border (brass scrollwork on its
-- corners, heavier on the right) and an inner trim, the name as a heading over a scrollwork line. The words come in letter by letter while the portrait talks; the answers
-- appear when the speaker is done (click the page to skip). Left-drag moves it, right-click puts
-- it back above the action bars (both dialogs share the place).
--
-- Used by the requests a companion asks you (Requests.lua) and the talk window (Talk.lua):
--   local d = ns.DialogPage.Create("GlobalFrameName")
--   d:Begin({ bot =, race =, gender =, class = }, words)   rises in if hidden, then speaks
--   d:SetAnswers({ { label =, color = {r,g,b}, icon =, iconSize =, price =, itemId =, onClick = fn } })
--   d:Relayout()      after changing what LayoutExtra draws
--   d:Dismiss()       fades out, then d.OnGone()
-- Hooks (optional): d.LayoutExtra(d, top) -> top (lines between the words and the answers),
-- d.OnRevealDone(d), d.OnTick(d, elapsed) (every frame), d.OnGone(d), d.OnItemInfo(d).

local _, ns = ...

local Dialog = {}
ns.DialogPage = Dialog

---------------------------------------------------------------------------
-- look
---------------------------------------------------------------------------

local WIDTH = 600
local PAD = 18
local TOP = 26                                  -- the portrait and the name heading start here
local PORTRAIT = 112
local RULE_H = 20                               -- the ink line under the name
local COLUMN_X = PAD + PORTRAIT + 20            -- the text column, right of the portrait
local COLUMN_W = WIDTH - COLUMN_X - PAD - 4
local ROW_HEIGHT = 22
local MAX_ANSWERS = 10

local INK = { 0.20, 0.12, 0.04 }                -- quest text brown
local INK_SOFT = { 0.36, 0.25, 0.12 }
local GOLD = { 1.00, 0.84, 0.52 }
local PARCHMENT = { 0.87, 0.78, 0.60 }          -- when no parchment texture can be found

local LETTERS_PER_SEC = 32
local FADE_LETTERS = 8
local TWEEN_IN, TWEEN_OUT = 0.28, 0.18
local SLIDE = 18                                -- the dialog rises this far when it opens

-- emote animations: talk, talk with "!", talk with "?", then stand
local ANIM_TALK, ANIM_EXCLAIM, ANIM_QUESTION, ANIM_STAND = 60, 64, 65, 0

-- the quest page: only the top left of the file is paper (torn right edge, transparent around it),
-- so it is cropped to the clean part and laid over a solid parchment colour that always fills
local PARCHMENT_FILE = "Interface\\QuestFrame\\QuestBG"
local PARCHMENT_COORDS = { 0.01, 0.55, 0.01, 0.64 }

local TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
-- the gold border of bind-on-pickup loot rolls (LootFrame.lua): drawn gold, so it is not tinted
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border"
local THIN_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
-- aged brass scrollwork on the border, the addon's own art (tools/ornaments.mjs). The portrait and
-- the text start weigh the page to the left, so the right corners get the long vines and the left
-- ones a small stud; the bottom pieces are the top ones flipped. Each piece is drawn round a
-- border point (the corner of the gold line, BORDER_LINE in from the page's edge).
local ORNAMENT_DIR = "Interface\\AddOns\\" .. (...) .. "\\Textures\\"
local BORDER_LINE = 9
local RIGHT_W, RIGHT_H, RIGHT_POINT = 256, 128, 20     -- border point 236,20: 20 in from top right
local LEFT_SIZE, LEFT_POINT = 64, 14                   -- border point 14,14
-- the ink line under the name (tools/ornaments.mjs): drawn 1:1, COLUMN_W wide in the left of a
-- 512x32 canvas with the art in rows 6..26, so it is cropped, never stretched
local RULE_FILE = "DialogRule"
local RULE_COORDS = { 0, COLUMN_W / 512, 6 / 32, 26 / 32 }

Dialog.WIDTH, Dialog.PAD, Dialog.COLUMN_X, Dialog.COLUMN_W, Dialog.ROW_HEIGHT = WIDTH, PAD, COLUMN_X, COLUMN_W, ROW_HEIGHT
Dialog.INK, Dialog.INK_SOFT, Dialog.GOLD = INK, INK_SOFT, GOLD
Dialog.TEMPLATE, Dialog.DIALOG_EDGE = TEMPLATE, DIALOG_EDGE

-- the answers of a yes / no question: agreeing gets a green tick, declining a red cross (requests
-- and talk pages); other answers keep their gossip icon
Dialog.ANSWER_LOOK = {
    yes = { icon = "Interface\\RaidFrame\\ReadyCheck-Ready",    color = { 0.08, 0.38, 0.06 } },
    no  = { icon = "Interface\\RaidFrame\\ReadyCheck-NotReady", color = { 0.55, 0.08, 0.04 } },
}

local function Font(name, fallback)
    return _G[name] and name or fallback
end
Dialog.Font = Font

function Dialog.Play(kit)
    local id = SOUNDKIT and SOUNDKIT[kit]
    if id then pcall(PlaySound, id) end
end
local Play = Dialog.Play

-- parchment inside 'f' (inset 8 for the dialog border), tinted by 'shade' (1 = as is)
function Dialog.Paper(f, shade)
    local base = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetPoint("TOPLEFT", 8, -8)
    base:SetPoint("BOTTOMRIGHT", -8, 8)
    base:SetColorTexture(PARCHMENT[1] * shade, PARCHMENT[2] * shade, PARCHMENT[3] * shade, 1)

    local grain = f:CreateTexture(nil, "BACKGROUND", nil, -7)
    grain:SetAllPoints(base)
    if grain:SetTexture(PARCHMENT_FILE) == false then    -- false: the client does not have the file
        grain:Hide()
    else
        grain:SetTexCoord(unpack(PARCHMENT_COORDS))
        grain:SetVertexColor(shade, shade, shade)
    end
    return base
end
local Paper = Dialog.Paper

function Dialog.GoldBorder(f, edge, size, inset)
    f:SetBackdrop({ edgeFile = edge, edgeSize = size, insets = { left = inset, right = inset, top = inset, bottom = inset } })
    if edge == DIALOG_EDGE then
        f:SetBackdropBorderColor(1, 1, 1, 1)
    else
        f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
end
local GoldBorder = Dialog.GoldBorder

---------------------------------------------------------------------------
-- position: above the action bars, or where the player dragged it (shared by every dialog)
---------------------------------------------------------------------------

local function BarsTop()
    local top = 0
    local scale = UIParent:GetEffectiveScale()
    for _, bar in ipairs({ MainMenuBar, MultiBarBottomLeft, MultiBarBottomRight }) do
        if bar and bar:IsShown() and bar:GetTop() then
            top = math.max(top, bar:GetTop() * bar:GetEffectiveScale() / scale)
        end
    end
    return top > 0 and top or 100
end

local function Smooth(t)
    t = math.min(1, math.max(0, t))
    return 1 - (1 - t) * (1 - t)
end

local function TalkAnimation(words)
    local s = (words or ""):gsub("%s+$", "")
    local function Ends(suffix) return s:sub(-#suffix) == suffix end
    if Ends("?") or Ends("？") then return ANIM_QUESTION end
    if Ends("!") or Ends("！") then return ANIM_EXCLAIM end
    return ANIM_TALK
end

---------------------------------------------------------------------------
-- one dialog
---------------------------------------------------------------------------

local Methods = {}
Methods.__index = Methods

function Dialog.Create(globalName)
    local d = setmetatable({}, Methods)
    d.base = { x = 0, y = 0 }
    d.phaseTime = 0
    d.reveal, d.letters, d.revealing, d.answersAlpha = 0, 0, false, 0
    d.rows = {}

    -- 'frame' only holds things (position, mouse, fading); everything drawn is on 'page' (and
    -- on pages a user puts behind it), which are its children at higher levels
    local frame = CreateFrame("Frame", globalName, UIParent)
    frame:SetSize(WIDTH, 160)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    d.frame = frame

    local page = CreateFrame("Frame", nil, frame, TEMPLATE)
    page:SetAllPoints()
    page:SetFrameLevel(frame:GetFrameLevel() + 3)
    d.page = page
    local paper = Paper(page, 1)

    -- a little darker towards the bottom, like an old page
    local shade = page:CreateTexture(nil, "BACKGROUND", nil, -6)
    shade:SetAllPoints(paper)
    shade:SetColorTexture(1, 1, 1, 1)
    if shade.SetGradientAlpha then
        shade:SetGradientAlpha("VERTICAL", 0.35, 0.22, 0.08, 0.25, 0.35, 0.22, 0.08, 0)
    else
        shade:Hide()
    end

    if page.SetBackdrop then GoldBorder(page, DIALOG_EDGE, 26, 8) end

    -- a thin inner trim, a little inside the gold border, like a bound book page
    local trim = CreateFrame("Frame", nil, page, TEMPLATE)
    trim:SetPoint("TOPLEFT", 10, -10)
    trim:SetPoint("BOTTOMRIGHT", -10, 10)
    if trim.SetBackdrop then
        trim:SetBackdrop({ edgeFile = THIN_EDGE, edgeSize = 8 })
        trim:SetBackdropBorderColor(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.7)
    end

    -- the portrait: a dark well with a gold rim
    local well = CreateFrame("Frame", nil, page, TEMPLATE)
    well:SetSize(PORTRAIT, PORTRAIT)
    well:SetPoint("TOPLEFT", PAD, -TOP)
    local wellBg = well:CreateTexture(nil, "BACKGROUND")
    wellBg:SetPoint("TOPLEFT", 3, -3)
    wellBg:SetPoint("BOTTOMRIGHT", -3, 3)
    wellBg:SetColorTexture(0.06, 0.05, 0.04, 1)
    if well.SetBackdrop then GoldBorder(well, THIN_EDGE, 14, 3) end

    local model = CreateFrame("PlayerModel", nil, well)
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 4)
    d.model = model
    local function FramePortrait()
        model:SetPortraitZoom(1)
        model:SetCamDistanceScale(1)
        model:SetPosition(0, 0, 0)
    end
    d.FramePortrait = FramePortrait
    if model:HasScript("OnModelLoaded") then model:SetScript("OnModelLoaded", FramePortrait) end

    local flat = well:CreateTexture(nil, "ARTWORK")
    flat:SetPoint("TOPLEFT", 4, -4)
    flat:SetPoint("BOTTOMRIGHT", -4, 4)
    d.flat = flat

    -- scrollwork on the border: the four corners and a crest in the middle of the top and bottom
    local ornaments = CreateFrame("Frame", nil, page)
    ornaments:SetAllPoints()
    ornaments:SetFrameLevel(well:GetFrameLevel() + 5)
    local function Ornament(file, w, h, point, x, y, l, r, t, b)
        local tex = ornaments:CreateTexture(nil, "OVERLAY")
        tex:SetSize(w, h)
        tex:SetPoint(point, x, y)
        if tex:SetTexture(ORNAMENT_DIR .. file) == false then tex:Hide() end
        tex:SetTexCoord(l, r, t, b)
    end
    local r = RIGHT_POINT - BORDER_LINE
    Ornament("DialogCornerRight", RIGHT_W, RIGHT_H, "TOPRIGHT", r, r, 0, 1, 0, 1)
    Ornament("DialogCornerRight", RIGHT_W, RIGHT_H, "BOTTOMRIGHT", r, -r, 0, 1, 1, 0)
    local l = LEFT_POINT - BORDER_LINE
    Ornament("DialogCornerLeft", LEFT_SIZE, LEFT_SIZE, "TOPLEFT", -l, l, 0, 1, 0, 1)
    Ornament("DialogCornerLeft", LEFT_SIZE, LEFT_SIZE, "BOTTOMLEFT", -l, -l, 0, 1, 1, 0)

    -- the speaker's name as the page's heading, race and class beside it
    local name = page:CreateFontString(nil, "OVERLAY", Font("QuestTitleFont", "GameFontNormalLarge"))
    name:SetPoint("TOPLEFT", COLUMN_X, -TOP)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(INK[1], INK[2], INK[3])
    name:SetShadowColor(0, 0, 0, 0)
    d.name = name

    local who = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    who:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 10, 1)
    who:SetJustifyH("LEFT")
    who:SetShadowColor(0, 0, 0, 0)
    d.who = who

    -- an ink line under the name (a plain line if the texture can't be loaded)
    local rule = page:CreateTexture(nil, "ARTWORK")
    rule:SetSize(COLUMN_W, RULE_H)
    rule:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    if rule:SetTexture(ORNAMENT_DIR .. RULE_FILE) == false then
        rule:SetHeight(1)
        rule:SetColorTexture(INK_SOFT[1], INK_SOFT[2], INK_SOFT[3], 0.45)
    else
        rule:SetTexCoord(unpack(RULE_COORDS))
    end

    -- words
    local text = page:CreateFontString(nil, "OVERLAY", Font("QuestFont", "GameFontHighlight"))
    text:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -(2 + RULE_H + 4))
    text:SetWidth(COLUMN_W)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetTextColor(INK[1], INK[2], INK[3])
    text:SetShadowColor(0, 0, 0, 0)
    d.text = text

    -- the answers, shown once the speaker is done
    local answers = CreateFrame("Frame", nil, page)
    answers:SetWidth(COLUMN_W)
    answers:Hide()
    d.answers = answers

    -- drag, skip, back above the bars
    frame:SetScript("OnDragStart", function(self)
        d.dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        d.dragging = false
        d.base.x = (self:GetLeft() + self:GetRight()) / 2 - UIParent:GetWidth() / 2
        d.base.y = self:GetBottom()
        ns.db.dialogPos = { d.base.x, d.base.y }
        d:Place()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if ns.db then ns.db.dialogPos = nil end
            d:ResetBase()
            d:Place()
        elseif d.revealing then
            d:FinishReveal()
        end
    end)
    frame:SetScript("OnUpdate", function(_, elapsed) d:Update(elapsed) end)
    -- hidden without fading (ESC through UISpecialFrames): the same as gone
    frame:SetScript("OnHide", function()
        if d.phase then d:Gone() end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:SetScript("OnEvent", function(_, event)
        if not d.speaker or not frame:IsShown() then return end
        if event == "GET_ITEM_INFO_RECEIVED" then
            if d.OnItemInfo then d.OnItemInfo(d) end
        elseif not d.speaker.hasModel and ns.UnitOf(d.speaker.bot) then
            -- the speaker came into view: swap the flat portrait for the model
            d:ShowSpeaker(d.speaker)
            d:Animate(d.revealing and TalkAnimation(d.words) or ANIM_STAND)
        end
    end)
    return d
end

function Methods:ResetBase()
    local p = ns.db and ns.db.dialogPos
    if p then
        self.base.x, self.base.y = p[1], p[2]
    else
        self.base.x, self.base.y = 0, BarsTop() + 12
    end
end

function Methods:Place(offsetY)
    self.frame:ClearAllPoints()
    self.frame:SetPoint("BOTTOM", UIParent, "BOTTOM", self.base.x, self.base.y + (offsetY or 0))
end

function Methods:IsOpen()
    return self.phase == "in" or self.phase == "show"
end

function Methods:Animate(id)
    if self.model:IsShown() then self.model:SetAnimation(id) end
end

-- the model if the client can draw this bot, else a race portrait, else the class icon
function Methods:ShowSpeaker(s)
    local model, flat = self.model, self.flat
    local token = ns.UnitOf(s.bot)
    if token then
        flat:Hide()
        model:Show()
        model:ClearModel()
        model:SetUnit(token)
        self.FramePortrait()
        s.hasModel = true
        return
    end

    s.hasModel = false
    model:Hide()
    flat:Show()
    flat:SetTexCoord(0, 1, 0, 1)
    local info = ns.RaceInfo(s.race)
    local file = info and info.clientFileString
    local sex = s.gender == 1 and "Female" or "Male"
    if file and flat:SetTexture("Interface\\CharacterFrame\\TemporaryPortrait-" .. sex .. "-" .. file) then return end

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[ns.CLASS_FILE[s.class] or ""]
    if coords then
        flat:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        flat:SetTexCoord(unpack(coords))
    else
        flat:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
end

---------------------------------------------------------------------------
-- answers
---------------------------------------------------------------------------

function Methods:Row(i)
    if self.rows[i] then return self.rows[i] end
    local b = CreateFrame("Button", nil, self.answers)
    b:SetHeight(ROW_HEIGHT)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 2, 0)

    b.price = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.price:SetPoint("RIGHT", -4, 0)
    b.price:SetShadowColor(0, 0, 0, 0)
    b.price:SetTextColor(INK[1], INK[2], INK[3])

    b.label = b:CreateFontString(nil, "OVERLAY", Font("QuestFont", "GameFontHighlight"))
    b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT", b.price, "LEFT", -6, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetShadowColor(0, 0, 0, 0)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints()
    hl:SetAlpha(0.6)

    b:SetScript("OnClick", function(row)
        if row.answer and row.answer.onClick then row.answer.onClick(row.answer) end
    end)
    b:SetScript("OnEnter", function(row)
        local id = row.answer and row.answer.itemId
        if id then
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. id)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rows[i] = b
    return b
end

-- answers = { { label, color = {r,g,b}, icon, iconSize, price (copper), itemId, onClick = fn(answer) } }
function Methods:SetAnswers(answers)
    self.answerList = answers or {}
    self:FillAnswers()
    self:Relayout()
end

function Methods:FillAnswers()
    local list = self.answerList or {}
    local count = math.min(#list, MAX_ANSWERS)
    for i = 1, MAX_ANSWERS do
        local a = list[i]
        if i <= count and a then
            local b = self:Row(i)
            b.answer = a
            b.label:SetText(a.label or "")
            local c = a.color or INK
            b.label:SetTextColor(c[1], c[2], c[3])
            local size = a.iconSize or 16
            b.icon:SetSize(size, size)
            b.icon:SetTexture(a.icon or "Interface\\GossipFrame\\GossipGossipIcon")
            if a.price and a.price > 0 and GetCoinTextureString then
                b.price:SetText(GetCoinTextureString(a.price))
            else
                b.price:SetText("")
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", self.answers, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
            b:SetPoint("TOPRIGHT", self.answers, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
            b:Show()
        elseif self.rows[i] then
            self.rows[i]:Hide()
        end
    end
    self.answers:SetHeight(math.max(1, count * ROW_HEIGHT))
    self.answerCount = count
end

function Methods:Relayout()
    local top = TOP + self.name:GetStringHeight() + 2 + RULE_H + 4 + self.text:GetStringHeight() + 12
    if self.LayoutExtra then top = self.LayoutExtra(self, top) end
    self.answers:ClearAllPoints()
    self.answers:SetPoint("TOPLEFT", self.frame, "TOPLEFT", COLUMN_X - 2, -top)
    local contentHeight = top + (self.answerCount or 0) * ROW_HEIGHT + 42
    self.frame:SetHeight(math.max(TOP + PORTRAIT + 36, contentHeight))
end

---------------------------------------------------------------------------
-- speaking: rise in, speak, answer, fade out
---------------------------------------------------------------------------

function Methods:FinishReveal()
    if not self.revealing then return end
    self.revealing = false
    if self.text.SetAlphaGradient then self.text:SetAlphaGradient(1024, 1) end
    self:Animate(ANIM_STAND)
    self.answers:Show()
    self.answers:SetAlpha(0)
    self.answersAlpha = 0
    if self.OnRevealDone then self.OnRevealDone(self) end
end

-- s = { bot, race, gender, class }
function Methods:Begin(s, words)
    self.speaker = s
    if not self:IsOpen() then
        self:ResetBase()
        self.phase, self.phaseTime = "in", 0
        self.frame:SetAlpha(0)
        self:Place(-SLIDE)
        self.frame:Show()    -- before the model is set: a hidden model frame may not take the unit
        Play("IG_QUEST_LIST_OPEN")
    end
    self:ShowSpeaker(s)

    self.name:SetText(s.bot)
    local info = ns.RaceInfo(s.race)
    local cr, cg, cb = ns.ClassColor(s.class)
    local classText = ns.CLASS_TEXT[s.class]
    local parts = {}
    if info and info.raceName then parts[#parts + 1] = info.raceName end
    if classText then parts[#parts + 1] = classText end
    self.who:SetText(table.concat(parts, " "))
    self.who:SetTextColor(cr * 0.6, cg * 0.6, cb * 0.6)

    words = (words and words ~= "") and words or "……"
    self.words = words
    self.text:SetText(words)
    self.letters = strlenutf8 and strlenutf8(words) or #words
    self.reveal = 0
    self.revealing = self.text.SetAlphaGradient ~= nil
    self.answers:Hide()
    self:Relayout()

    if self.revealing then
        self.text:SetAlphaGradient(0, FADE_LETTERS)
        self:Animate(TalkAnimation(words))
    else
        self.revealing = true
        self:FinishReveal()
    end
end

function Methods:Dismiss()
    if self.phase == "out" or not self.frame:IsShown() then return end
    self.phase, self.phaseTime = "out", 0
    self.revealing = false
    self:Animate(ANIM_STAND)
end

-- after the page faded out (or was hidden)
function Methods:Gone()
    self.phase = nil
    self.speaker = nil
    self.frame:Hide()
    GameTooltip:Hide()
    if self.OnGone then self.OnGone(self) end
end

function Methods:Update(elapsed)
    local frame = self.frame
    self.phaseTime = self.phaseTime + elapsed

    if self.phase == "in" then
        local t = Smooth(self.phaseTime / TWEEN_IN)
        frame:SetAlpha(t)
        if not self.dragging then self:Place(-SLIDE * (1 - t)) end
        if t >= 1 then self.phase = "show" end
    elseif self.phase == "out" then
        local t = Smooth(self.phaseTime / TWEEN_OUT)
        frame:SetAlpha(math.min(frame:GetAlpha(), 1 - t))
        if t >= 1 then self:Gone() return end
    end

    if self.revealing then
        self.reveal = self.reveal + elapsed * LETTERS_PER_SEC
        self.text:SetAlphaGradient(math.floor(self.reveal), FADE_LETTERS)
        if self.reveal >= self.letters + FADE_LETTERS then self:FinishReveal() end
    elseif self.answers:IsShown() and self.answersAlpha < 1 then
        self.answersAlpha = math.min(1, self.answersAlpha + elapsed / 0.25)
        self.answers:SetAlpha(self.answersAlpha)
    end

    if self.OnTick then self.OnTick(self, elapsed) end
end
