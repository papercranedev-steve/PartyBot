-- Your own bag windows, whoever draws them: a bag addon (Bagnon) or Blizzard's ContainerFrames.
-- The team bags (TeamBags.lua) open beside them, and a companion's item can be dropped on them.
--
--   ns.PlayerBags.Main()           -> the window to dock beside (shown now), or nil
--   ns.PlayerBags.Shown()          -> every bag window shown now
--   ns.PlayerBags.SlotUnderMouse() -> bag (0-4), slot (from 1), button: the slot of your bags
--                                     under the mouse, or nil (a gap, the keyring, no window)
--   ns.PlayerBags.OnChange(fn)     -> fn() after one of them opened or closed
--
-- Another bag addon = one more entry in SOURCES: installed() (at login: hook it), available()
-- (ready now), frames(), buttons(frame) (its item slots: parent:GetID() = bag, GetID() = slot, as
-- Blizzard's), watch() (call Changed when its windows open or close). The first available one
-- with a window shown wins.

local _, ns = ...

local PlayerBags = {}
ns.PlayerBags = PlayerBags

local handlers = {}
local hooked = {}       -- frames whose OnShow/OnHide we watch

local function Changed()
    for _, fn in ipairs(handlers) do fn() end
end

-- true if it was new (it may have shown before we watched it)
local function Watch(frame)
    if not frame or hooked[frame] then return false end
    hooked[frame] = true
    frame:HookScript("OnShow", Changed)
    frame:HookScript("OnHide", Changed)
    return true
end

local SOURCES = {
    {   -- Bagnon: one window for every bag, made the first time it opens
        -- (its module list is filled when it enables itself, maybe after our PLAYER_LOGIN)
        installed = function() return Bagnon and Bagnon.Frames and Bagnon.Frames.Show end,
        available = function() return Bagnon and Bagnon.Frames and Bagnon.Frames.registry end,
        frames = function()
            local info = Bagnon.Frames:Get("inventory")
            return { info and info.object }
        end,
        -- (its slots sit on one frame per bag, whose ID is the bag, for Blizzard's click code)
        buttons = function(frame) return frame.itemGroup and frame.itemGroup.order or {} end,
        watch = function()
            -- (the window is made inside its first Show, and shown before this runs)
            hooksecurefunc(Bagnon.Frames, "Show", function()
                if not Bagnon.Frames.registry then return end
                local info = Bagnon.Frames:Get("inventory")
                if Watch(info and info.object) then Changed() end
            end)
        end,
    },
    {   -- Blizzard: one window per bag
        installed = function() return true end,
        available = function() return true end,
        frames = function()
            local list = {}
            for i = 1, NUM_CONTAINER_FRAMES or 13 do
                local f = _G["ContainerFrame" .. i]
                -- (bank bags use the same frames; only yours: backpack 0 and bags 1-4)
                if f and f:GetID() >= 0 and f:GetID() <= NUM_BAG_SLOTS then list[#list + 1] = f end
            end
            return list
        end,
        buttons = function(frame)
            local list, name = {}, frame:GetName()
            for i = 1, frame.size or 0 do list[#list + 1] = _G[name .. "Item" .. i] end
            return list
        end,
        watch = function()
            for i = 1, NUM_CONTAINER_FRAMES or 13 do Watch(_G["ContainerFrame" .. i]) end
            -- (opening another bag moves the others)
            if UpdateContainerFrameAnchors then hooksecurefunc("UpdateContainerFrameAnchors", Changed) end
        end,
    },
}

-- the windows shown now, and the source drawing them
local function ShownWith()
    for _, source in ipairs(SOURCES) do
        if source.available() then
            local list = {}
            for _, f in ipairs(source.frames()) do
                if f and f:IsShown() then list[#list + 1] = f end
            end
            if #list > 0 then return list, source end
        end
    end
    return {}
end

function PlayerBags.Shown() return (ShownWith()) end

function PlayerBags.SlotUnderMouse()
    local list, source = ShownWith()
    for _, f in ipairs(list) do
        if f:IsMouseOver() then
            for _, b in ipairs(source.buttons(f)) do
                if b:IsVisible() and b:IsMouseOver() then
                    local bag = b:GetParent() and b:GetParent():GetID()
                    if bag and bag >= 0 and bag <= NUM_BAG_SLOTS then return bag, b:GetID(), b end
                    return nil
                end
            end
        end
    end
end

-- the leftmost window (the topmost of that column): the panel opens to its left
function PlayerBags.Main()
    local best
    for _, f in ipairs(PlayerBags.Shown()) do
        local left, top = f:GetLeft(), f:GetTop()
        if left and top then
            local s = f:GetEffectiveScale()
            left, top = left * s, top * s
            if not best or left < best.left - 1 or (math.abs(left - best.left) <= 1 and top > best.top) then
                best = { frame = f, left = left, top = top }
            end
        end
    end
    return best and best.frame
end

function PlayerBags.OnChange(fn) handlers[#handlers + 1] = fn end

-- (bag addons are loaded by then)
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    for _, source in ipairs(SOURCES) do
        if source.installed() then source.watch() end
    end
end)
