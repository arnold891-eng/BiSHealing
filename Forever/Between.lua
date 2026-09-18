-- BiSHealing / Forever -- the brain, and the only window it is allowed to think in.
--
-- Shape B, step 2. Inside the secure lockdown this client tells an addon nothing: health, auras,
-- cooldowns and stats are all secret, and the combat log never fires. OUT of combat every one of
-- them reads normally. So the thinking moves to the gap between pulls, where it is still legal --
-- and where a healer can actually act on it.
--
-- What it checks, all of it measured as readable out of combat on 1.60.1.69893:
--
--   * Earth Shield -- is it up at all, and on whom. It falls off between pulls and the tank
--     notices two seconds into the next one.
--   * totems -- which of the four slots are empty.
--   * dispel debt -- poison and disease still on the group after the fight ended. In combat the
--     addon cannot see a debuff at all, so this is the only moment it can tell you.
--   * the dead -- who needs a rez before the next pull.
--
-- What it deliberately does NOT check: anything about mana. `UnitPower` is secret on this client
-- even out of combat, so "who is low on mana" cannot be answered at all -- not by this addon, not
-- by any addon. Saying nothing beats guessing.
--
-- Scan() is a pure read that returns findings; Report() is the only thing that talks. That split
-- is what lets dev/forever.lua drive the whole brain against a fake client with the game shut.

local ADDON, NS = ...
NS = NS or {}

local FB = {}
NS.FB = FB

local EARTH_SHIELD = "Earth Shield"
local TOTEM_SLOTS = 4
local CURABLE = { Poison = true, Disease = true }     -- what a shaman can actually remove

--- Every aura on a unit, as the client hands them over. Out of combat only: inside the lockdown
--- `GetAuraDataByIndex` errors outright and `AuraUtil.FindAuraByName` quietly returns nil, which
--- is worse -- so this refuses to run there rather than reporting an empty raid.
local function auras(unit, filter)
    local out = {}
    -- guarded here as well as in Scan(): a helper that reads locked data should refuse on its own,
    -- so a future caller cannot forget. It also lets audit/lockdown.py see the guard, which it
    -- cannot do by following calls.
    if NS.Blind and NS.Blind() then return out end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return out end
    for i = 1, 40 do
        local ok, a = pcall(get, unit, i, filter)
        if not ok or not a then break end
        out[#out + 1] = a
    end
    return out
end

--- What is wrong with the raid right now. Returns a list of { kind, unit, text } and never prints:
--- a scan that talks cannot be tested, and a scan that runs in combat cannot be trusted.
function FB.Scan()
    if NS.Blind and NS.Blind() then return nil, "blind: inside the lockdown" end
    local found = {}
    local roster = (NS.FG and NS.FG.Roster and NS.FG.Roster()) or { "player" }

    local esOn
    for _, unit in ipairs(roster) do
        for _, a in ipairs(auras(unit, "HELPFUL")) do
            if a.name == EARTH_SHIELD then esOn = unit end
        end
    end
    if not esOn then
        found[#found + 1] = { kind = "earthshield", text = "Earth Shield is not up on anyone" }
    end

    for _, unit in ipairs(roster) do
        for _, a in ipairs(auras(unit, "HARMFUL")) do
            if CURABLE[a.dispelName] then
                found[#found + 1] = { kind = "dispel", unit = unit,
                                      text = (NS.FG and NS.FG.ShortName(unit) or unit) ..
                                             " still has " .. tostring(a.name) }
            end
        end
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then
            found[#found + 1] = { kind = "dead", unit = unit,
                                  text = (NS.FG and NS.FG.ShortName(unit) or unit) .. " is dead" }
        end
    end

    if GetTotemInfo then
        local empty = 0
        for slot = 1, TOTEM_SLOTS do
            local ok, have = pcall(GetTotemInfo, slot)
            if ok and not have then empty = empty + 1 end
        end
        if empty == TOTEM_SLOTS then
            found[#found + 1] = { kind = "totems", text = "no totems down" }
        end
    end

    return found
end

--- Say it once, in the chat frame the addon already owns. Quiet when there is nothing wrong:
--- an addon that speaks after every pull gets turned off after three.
function FB.Report()
    local found, why = FB.Scan()
    if not found then return nil, why end
    if #found == 0 then return 0 end
    local say = NS.Print or function(msg) print(msg) end
    for _, f in ipairs(found) do say("BiS Healing: " .. f.text) end
    return #found
end

--- Armed by the grid. PLAYER_REGEN_ENABLED is the moment the lockdown lifts and every read this
--- brain needs starts answering again -- but the client is still settling on that exact frame, so
--- the scan waits a beat.
function FB.Start()
    if not NS.SECRET then return false end
    if FB.frame then return true end
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        if C_Timer and C_Timer.After then
            C_Timer.After(2, FB.Report)
        else
            FB.Report()
        end
    end)
    FB.frame = f
    return true
end
