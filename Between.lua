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
--- Returns the auras AND whether the client refused to hand them over. Those were one value -
--- an empty list - and the difference matters: "nobody has Earth Shield" and "the client would
--- not say" read identically from an empty table, and the first of them gets printed in chat.
--- EllesmereUI's AuraKit made the case (28 Sep): the index walk hard-errors under instance
--- restrictions even out of combat, where `ShouldAurasBeSecret` still answers no.
local function auras(unit, filter)
    local out = {}
    -- guarded here as well as in Scan(): a helper that reads locked data should refuse on its own,
    -- so a future caller cannot forget. It also lets audit/lockdown.py see the guard, which it
    -- cannot do by following calls.
    if NS.Blind and NS.Blind() then return out, true end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return out, true end
    for i = 1, 40 do
        local ok, a = pcall(get, unit, i, filter)
        if not ok then return out, true end          -- refused: not the same as "no more auras"
        if not a then break end
        out[#out + 1] = a
    end
    return out, false
end

--- One field of an aura, or nil when the client will not let us read it. The aura table itself
--- can refuse to be indexed, so the read is guarded as well as the value.
local function field(a, k)
    local ok, v = pcall(function() return a[k] end)
    if not ok then return nil end
    return NS.Plain(v)
end

--- A name to write into a sentence, never a secret: the cell may paint a hidden name, a line of
--- chat may not be built from one.
local function nameOf(unit)
    local n = NS.FG and NS.FG.ShortName and NS.FG.ShortName(unit)
    n = NS.Plain(n)
    return type(n) == "string" and n or unit
end

--- What is wrong with the raid right now. Returns a list of { kind, unit, text } and never prints:
--- a scan that talks cannot be tested, and a scan that runs in combat cannot be trusted.
function FB.Scan()
    if NS.Blind and NS.Blind() then return nil, "blind: the client is hiding auras right now" end
    local found = {}
    local roster = (NS.FG and NS.FG.Roster and NS.FG.Roster()) or { "player" }

    -- EARTH SHIELD, ONLY IF YOU HAVE IT. This nagged a level-15 shaman grinding leather in the
    -- Barrens about a spell learned at 50, on a client where it may not exist at all: "BiS
    -- Healing: Earth Shield is not up on anyone", after every mob (Arn, 19 Sep). The spellbook
    -- answers whether this character has trained it, the same way the mouse's defaults do.
    -- EVERY VALUE IS ASKED ABOUT BEFORE IT IS USED, even with Blind() saying no. Blind() is the
    -- client's word for auras as a whole; a single field can still come back secret (a totem did,
    -- 21 Sep), and one unguarded `if` on it throws the whole scan. What cannot be read is treated
    -- as not known: never "missing", never "empty", never "dead".
    if FB.Knows(EARTH_SHIELD) then
        local esOn, unsure = nil, false
        for _, unit in ipairs(roster) do
            local list, refused = auras(unit, "HELPFUL")
            if refused then unsure = true end
            for _, a in ipairs(list) do
                local name = field(a, "name")
                if name == nil then unsure = true elseif name == EARTH_SHIELD then esOn = unit end
            end
        end
        if not esOn and not unsure then
            found[#found + 1] = { kind = "earthshield", text = "Earth Shield is not up on anyone" }
        end
    end

    for _, unit in ipairs(roster) do
        local who = nameOf(unit)
        -- a refused list simply has nothing in it to report, which is right: this half only ever
        -- says "somebody still HAS something", and a refusal is not evidence that they do
        for _, a in ipairs((auras(unit, "HARMFUL"))) do
            local kind = field(a, "dispelName")
            if kind and CURABLE[kind] then
                found[#found + 1] = { kind = "dispel", unit = unit,
                                      text = who .. " still has " .. (field(a, "name") or "a " .. kind:lower()) }
            end
        end
        if UnitIsDeadOrGhost and NS.Plain(UnitIsDeadOrGhost(unit)) == true then
            found[#found + 1] = { kind = "dead", unit = unit, text = who .. " is dead" }
        end
    end

    if GetTotemInfo then
        local empty, known = 0, 0
        for slot = 1, TOTEM_SLOTS do
            local ok, have = pcall(GetTotemInfo, slot)
            if ok then have = NS.Plain(have) else have = nil end   -- a failed ask is not "empty"
            if have ~= nil then
                known = known + 1
                if not have then empty = empty + 1 end
            end
        end
        -- kept for /bish scan and the suite: how many slots the client would actually answer
        -- for. A secret yes/no cannot be made to refuse a test outside the client, so "it was
        -- counted as unknown" is the evidence that it was never tested.
        FB.totemsKnown = known
        if known == TOTEM_SLOTS and empty == TOTEM_SLOTS then
            found[#found + 1] = { kind = "totems", text = "no totems down" }
        end
    end

    return found
end

--- Does this character actually have the spell? The spellbook, not a level check and not a guess.
function FB.Knows(name)
    if NS.FM and NS.FM.Ranks then return #NS.FM.Ranks(name) > 0 end
    return false
end

--- Say it once, in the chat frame the addon already owns. Quiet when there is nothing wrong:
--- an addon that speaks after every pull gets turned off after three.
---
--- THREE REASONS TO STAY QUIET, all of them learned from one screenshot (19 Sep 2026): the same
--- line six times in ninety seconds while grinding leather in the Barrens, each prefixed twice.
---
---   1. ALONE. This is a between-PULLS brain for a group: who still has a debuff, who is dead,
---      whether the shield is up. Solo, there is nobody to tell and nothing to fix.
---   2. THE SAME NEWS. A finding that has not changed since the last report is not news. It is
---      said again only when it changes, or after QUIET seconds have passed.
---   3. ITS OWN NAME. NS.Print already writes "BiS Healing:" - adding it here produced
---      "BiS Healing: BiS Healing: Earth Shield is not up on anyone".
local QUIET = 300          -- five minutes before the same news is worth repeating

--- OFF BY DEFAULT SINCE 23 SEP. Arn: "lets get rid of the reminders in the chat window that was
--- from tbc version. sometimes it says totems down that one lets put it away for now". The lines
--- were written for a TBC shaman with four totems and an Earth Shield to keep up, and on this
--- client they arrive between pulls with half of what they used to know. The machinery stays -
--- /bish scan asks for it outright, and `/bish between` turns the automatic ones back on.
function FB.Speaks()
    local d = NS.DB and NS.DB()
    return type(d) == "table" and d.between == true
end

function FB.Report(force)
    if not (force or FB.Speaks()) then return 0, "quiet" end
    local found, why = FB.Scan()
    if not found then return nil, why end
    if #found == 0 then return 0 end

    if not force then
        local grouped = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
        if not grouped then return 0, "alone" end

        local sig = {}
        for _, f in ipairs(found) do sig[#sig + 1] = tostring(f.kind) .. ":" .. tostring(f.unit) end
        table.sort(sig)
        sig = table.concat(sig, "|")
        local now = (GetTime and GetTime()) or 0
        if sig == FB.lastSig and (now - (FB.lastAt or 0)) < QUIET then
            return 0, "same as last time"
        end
        FB.lastSig, FB.lastAt = sig, now
    end

    local say = NS.Print or function(msg) print(msg) end
    for _, f in ipairs(found) do say(f.text) end
    return #found
end

--- What the scan SAW, not just what it decided. A report that says nothing is either a clean raid
--- or a broken read, and from the chat line alone those look identical -- so /bishf shows the
--- counts behind the verdict: who was scanned, how many auras came back, which totems are out.
function FB.Dump()
    local say = NS.Print or function(msg) print(msg) end
    if NS.Blind and NS.Blind() then
        say("BiS Healing: the client is hiding auras and totems right now -- in combat, or in"
            .. " an instance that keeps them hidden")
        return
    end
    local roster = (NS.FG and NS.FG.Roster and NS.FG.Roster()) or { "player" }
    say(("BiS Healing scan: %d unit(s)"):format(#roster))
    for _, unit in ipairs(roster) do
        local helpful, harmful = auras(unit, "HELPFUL"), auras(unit, "HARMFUL")
        local names = {}
        for _, a in ipairs(helpful) do names[#names + 1] = field(a, "name") or "(hidden)" end
        say(("  %s: %d buff(s), %d debuff(s)%s"):format(
            nameOf(unit), #helpful, #harmful,
            #names > 0 and ("  [" .. table.concat(names, ", ") .. "]") or ""))
    end
    if GetTotemInfo then
        for slot = 1, TOTEM_SLOTS do
            local ok, have, name = pcall(GetTotemInfo, slot)
            local plainHave = nil
            if ok then plainHave = NS.Plain(have) end
            local shown = plainHave == nil and "(hidden)"
                or (plainHave and (NS.Plain(name) or "(hidden)")) or "empty"
            say(("  totem %d: %s"):format(slot, shown))
        end
    end
    local found = FB.Scan()
    say(("  -> %d finding(s)"):format(found and #found or 0))
    if found then
        for _, f in ipairs(found) do say("     " .. f.text) end
    end
end

--- Armed by the grid. PLAYER_REGEN_ENABLED is the moment the lockdown lifts and every read this
--- brain needs starts answering again -- but the client is still settling on that exact frame, so
--- the scan waits a beat.
function FB.Start()
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
    -- The slash command used to be registered here, because this file was the only one with a
    -- reason to have one. Core.lua owns every door now: /bish scan is what this answers.
    return true
end
