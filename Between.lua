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
-- even out of combat, so this brain cannot READ who is low and cannot report on it in words.
--
-- THAT SENTENCE USED TO END "not by this addon, not by any addon", and that part was wrong. Arn
-- sent a screenshot of EllesmereUI's party frames on 28 Sep 2026 with the other healers' mana
-- along the top of them. Reading it is impossible; SHOWING it is not: UnitPowerPercent's answer
-- goes straight into SetFormattedText and the client draws the number nobody is allowed to see.
-- The grid's mana block does exactly that (/bish mana). A sentence about what no one can do is
-- worth checking every few weeks - this one stood for eleven days.
--
-- Scan() is a pure read that returns findings; Report() is the only thing that talks. That split
-- is what lets dev/forever.lua drive the whole brain against a fake client with the game shut.

local ADDON, NS = ...
NS = NS or {}

local FB = {}
NS.FB = FB

-- A BUFF TO WATCH ON THE GROUP, and EMPTY ON PURPOSE -- the same decision FA.WATCH records in
-- Auras.lua, for the same reason, and this file did not get the memo until 1 Oct 2026.
--
-- This used to be the string "Earth Shield", hardcoded. Arn: "there is no earth shield in this
-- game mode." He is right, and Auras.lua:45 had already written it down on 19 Sep: Earth Shield is
-- a TBC spell and Forever is a 1.60 client. So the check could never run here -- FB.Knows asks the
-- spellbook and the spellbook has never heard of it -- which is also the real reason the 0.6.1
-- "not up on anyone" bug went away. It was not fixed. It became unreachable.
--
-- So nothing is hardcoded now. The watch is a spell NAME the player chooses, every rank of it
-- found in their own book, and the reminder only ever speaks about a spell they have actually
-- trained. That way it is right in whatever this mode turns out to contain, without this file
-- holding an opinion about the game's spell list -- which is the thing it kept getting wrong.
local function watched()
    local d = NS.DB and NS.DB()
    local name = type(d) == "table" and d.groupBuff or nil
    return (type(name) == "string" and name ~= "") and name or nil
end
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

--- The spell ids for something this character has trained, every rank. The book is already read
--- for the mouse binds, and each rank is its own id -- so "Earth Shield" is several questions.
local function idsFor(name)
    local out = {}
    if not (NS.FM and NS.FM.Ranks) then return out end
    for _, r in ipairs(NS.FM.Ranks(name)) do
        if type(r.spell) == "number" then out[#out + 1] = r.spell end
    end
    return out
end

--- WHO HAS THE WATCHED BUFF -- asked by spell id now, and the walk only as a fallback (1 Oct 2026).
---
--- The walk is the thing that hard-errors under instance restrictions, which is the one place a
--- shaman most wants this answered: a raid, out of combat, between pulls. There `ShouldAurasBeSecret`
--- says auras are not secret, so `Blind()` lets the scan run, and then every single
--- `GetAuraDataByIndex` throws -- forty refusals per unit, and the whole question comes back
--- "unsure". Silence, in exactly the situation the reminder exists for.
---
--- By id the client answers. See `NS.AuraById`: it is the one aura question that survives.
---
--- Returns unit-or-nil, unsure. `unsure` is the load-bearing half -- see NS.AnyAuraById.
function FB.Watched(roster, name)
    name = name or watched()
    if not name then return nil, false end
    local ids = idsFor(name)
    if #ids > 0 and C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
        -- recorded BEFORE the loop: finding the shield returns early, and `/bish byid` saying
        -- "walk" right after a by-id answer is the kind of wrong that costs an evening
        FB.watchBy = "id"
        local unsure = false
        for _, unit in ipairs(roster) do
            local up = NS.AnyAuraById(unit, ids)
            if up == true then return unit, false end
            if up == nil then unsure = true end
        end
        return nil, unsure
    end

    -- no by-id lookup on this client (TBC, or a beta older than the call): the old walk, which is
    -- better than nothing out in the world and no worse than before anywhere else
    FB.watchBy = "walk"
    local onUnit, unsure = nil, false
    for _, unit in ipairs(roster) do
        local list, refused = auras(unit, "HELPFUL")
        if refused then unsure = true end
        for _, a in ipairs(list) do
            local got = field(a, "name")
            if got == nil then unsure = true elseif got == name then onUnit = unit end
        end
    end
    return onUnit, unsure
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
    local watch = watched()
    if watch and FB.Knows(watch) then
        local onUnit, unsure = FB.Watched(roster, watch)
        if not onUnit and not unsure then
            -- "not up on anyone" reads as nonsense when there is only one person it could be on -
            -- solo, or watching a buff that only goes on yourself. Arn, on Lightning Shield: "i
            -- can only throw shield on my self." Same answer, said the way it is meant.
            found[#found + 1] = { kind = "groupbuff",
                                  text = watch .. (#roster > 1 and " is not up on anyone"
                                                                or " is not up on you") }
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
