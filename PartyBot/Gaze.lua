-- Tells the server which players are on your screen, so the bots around you (town residents,
-- travellers, bots in the field) wave, bow or admire you when you are looking at them, not behind
-- your back (server: PlayerBots/Shared/Gaze.h). The server only knows which way your character
-- faces, not your camera.
--
-- On screen = their nameplate is shown (the client shows nameplates only for units in view), or
-- under the mouse. Friendly nameplates are off by default: if they are off, this turns them on
-- and makes the plates of players you cannot attack invisible and click-through, so nothing
-- looks different. Your own setting is put back when you log out. If you change the setting
-- yourself, it is yours again and the plates are left alone.
--
-- Sent as an addon whisper to yourself (prefix PBSEE, guid lows in hex, comma separated): when
-- the set changes and every REFRESH seconds while it is not empty, at most once a TICK.
-- Party and raid members are left out (they are not strangers).

local _, ns = ...

local PREFIX = "PBSEE"
local TICK = 1                  -- seconds (the client lets an addon prefix send about one a second)
local REFRESH = 3               -- the server forgets a report after 5 s
local MAX_BODY = 240            -- bytes (an addon message holds 255)

local plates = {}               -- nameplate unit token -> guid low (hex), shown players only
local lastBody = nil
local lastSentAt = 0
local owned = false             -- we turned friendly nameplates on (ns.db.gazeOwnsFriendPlates)

---------------------------------------------------------------------------
-- who
---------------------------------------------------------------------------

-- the server's guid low (hex, no leading zeros) of a stranger player unit, else nil
local function LowOf(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") or
       UnitInParty(unit) or UnitInRaid(unit) then
        return nil
    end
    local hex = UnitGUID(unit) and UnitGUID(unit):match("^Player%-%d+%-(%x+)$")
    local n = hex and tonumber(hex, 16)
    return n and n > 0 and string.format("%x", n) or nil
end

local function Body()
    local seen, list = {}, {}
    local function add(low)
        if low and not seen[low] then
            seen[low] = true
            list[#list + 1] = low
        end
    end
    add(LowOf("mouseover"))
    for _, low in pairs(plates) do add(low) end
    table.sort(list)
    local body = ""
    for _, low in ipairs(list) do
        if #body + #low + 1 > MAX_BODY then break end
        body = body == "" and low or (body .. "," .. low)
    end
    return body
end

local function Send(body)
    C_ChatInfo.SendAddonMessage(PREFIX, body == "" and "-" or body, "WHISPER", UnitName("player"))
    lastBody = body
    lastSentAt = GetTime()
end

local Relinquish

local function Tick()
    -- the player turned friendly nameplates off himself: his setting again
    if owned and GetCVar("nameplateShowFriends") ~= "1" then Relinquish() end
    local body = Body()
    if body ~= lastBody or (body ~= "" and GetTime() - lastSentAt >= REFRESH) then
        Send(body)
    end
end

---------------------------------------------------------------------------
-- friendly nameplates, invisible when we turned them on
---------------------------------------------------------------------------

local function SetClickThrough(on)
    if C_NamePlate.SetNamePlateFriendlyClickThrough then
        C_NamePlate.SetNamePlateFriendlyClickThrough(on)
    end
end

local function Dress(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local frame = plate and plate.UnitFrame
    if not frame then return end
    -- plates are reused for other units: set the alpha back for the ones we do not hide
    frame:SetAlpha((owned and UnitIsFriend("player", unit)) and 0 or 1)
end

local function TakeFriendPlates()
    if GetCVar("nameplateShowFriends") == "1" and not ns.db.gazeOwnsFriendPlates then
        return      -- the player's own: left as they are
    end
    owned = true
    ns.db.gazeOwnsFriendPlates = true
    SetCVar("nameplateShowFriends", "1")
    SetClickThrough(true)
end

local function GiveBackFriendPlates()
    if not owned then return end
    SetCVar("nameplateShowFriends", "0")
    SetClickThrough(false)
end

function Relinquish()
    owned = false
    ns.db.gazeOwnsFriendPlates = nil
    SetClickThrough(false)
    for unit in pairs(plates) do Dress(unit) end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LOGOUT")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        TakeFriendPlates()
        C_Timer.NewTicker(TICK, Tick)
    elseif event == "PLAYER_LOGOUT" then
        GiveBackFriendPlates()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        plates[arg1] = LowOf(arg1)
        Dress(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        plates[arg1] = nil
    end
    -- plate changes and the mouseover (read each tick): sent with the next tick
end)
