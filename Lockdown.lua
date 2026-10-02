-- BiSHealing / Forever -- is this the client that hides the numbers?
--
-- Measured on the Forever beta (1.60.1.69893) on 17 Sep 2026, see
-- _bisdev/docs/forever-secret-values.md:
--
--   * a unit's health is a SECRET NUMBER. It can be stored and handed to a StatusBar or a
--     FontString -- the client paints it -- but arithmetic and comparison on it are refused,
--     and tostring() gives nil.
--   * while InCombatLockdown() is true, auras, cooldowns and unit stats are secret as well.
--     Out of combat they read normally. The addon is blind for exactly as long as the pull.
--   * COMBAT_LOG_EVENT_UNFILTERED registers and then never fires. Worse than silent, as it
--     turns out: on 1.60.1.69913 (19 Sep 2026) registering it is a PROTECTED call. Arn enabled
--     PartyHealingDisplay, a retail addon that reads every number it shows out of the combat
--     log, and the client answered before it drew anything:
--
--       [ADDON_ACTION_FORBIDDEN] AddOn 'PartyHealingDisplay' tried to call the protected
--       function 'Frame:RegisterEvent()'
--
--     So the combat log is not a way around the secret values. It looked like one - the log
--     hands out PLAIN numbers (amount, overhealing, absorbed) where UnitHealth is secret, which
--     would have been enough to show a healer that a rank overhealed and ought to be smaller.
--     It is shut. Anything built on "read what actually landed" is not available on this client.
--
-- So the pyramid's brain -- ranking by missing health, heal-size estimates, the combat-log
-- score -- cannot run there at all. This flag is the seam: everything that reads a number sits
-- behind it, the TBC addon is untouched, and Forever gets the grid in Forever/Grid.lua.
--
-- Deliberately NOT a TOC check or a build-number check: the question is "does this client hide
-- the numbers", and the client answers it directly. If Blizzard loosens the lockdown before
-- launch, this file starts saying false and the old addon comes back on its own.

local ADDON, NS = ...
NS = NS or {}

-- THE ANSWER CAN ITSELF BE A SECRET, and that is not paranoia - ForeverAuras (the WeakAuras
-- fork for this client, 0.1.114) guards exactly this, and they have had more eyes on this beta
-- than anyone. It matters here more than it does there: this runs at FILE SCOPE, so a secret
-- coming back would be tested by the `and` below - and if the client refuses that test, the error
-- takes the whole addon down at load with a stack trace about a line nobody would think to look
-- at. The pcall only ever covered the CALL, never what came back from it.
--
-- WHETHER IT REFUSES IS NOT SETTLED, and this comment used to say it was. Corrected 21 Sep 2026:
-- EllesmereUI tests secret TEXT for truth on purpose ("ONLY feed it to SetText or test truthiness"),
-- so for a secret string the test is allowed. A secret BOOLEAN in an `if` is another matter -
-- Healium guards those (see NS.Secret below), and a boolean's truth would give its value away. We
-- have measured neither ourselves. The guard below is right either way: it never makes the test.
--
-- So: the call is guarded, the answer is checked for secrecy, and an answer that is not a plain
-- boolean is treated as "restricted" rather than guessed at.
local ok, answer = pcall(function()
    return C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
end)

local function plainBool(v)
    if issecretvalue then
        local asked, yes = pcall(issecretvalue, v)
        if asked and yes then return nil end          -- the answer is secret: no answer at all
    end
    if type(v) ~= "boolean" then return nil end
    return v
end

local told = ok and plainBool(answer) or nil
-- nil means the client would not say. On a client with C_Secrets AT ALL that means restricted;
-- on TBC, where C_Secrets does not exist, `ok` is true and `answer` is nil, and nothing is secret.
if told ~= nil then
    NS.SECRET = told
else
    NS.SECRET = (C_Secrets ~= nil) and true or false
end

--- True when the client is hiding numbers AND auras are secret right now.
---
--- IT IS NOT ONLY COMBAT. This used to be "inside the secure lockdown", on the 17 Sep measurement
--- that out of combat everything reads. Then, 21 Sep, in a dungeon, two seconds after a pull:
--- "attempt to perform boolean test on local 'have' (a secret boolean value)" - GetTotemInfo, out
--- of combat, still secret. ForeverAuras 0.1.148 never trusted combat for this: it asks
--- C_Secrets.ShouldAurasBeSecret, and re-asks on ENCOUNTER_STATE_CHANGED, CHALLENGE_MODE_START and
--- the restriction events. So this asks the client too. An answer that is itself secret, or an
--- error, counts as blind - the safe side of not knowing.
function NS.Blind()
    if not NS.SECRET then return false end
    if InCombatLockdown and InCombatLockdown() then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, yes = pcall(C_Secrets.ShouldAurasBeSecret)
        if not ok or NS.Secret(yes) then return true end
        if yes == true then return true end
    end
    return false
end

--- AND THE ANSWER THE CLIENT GIVES BY THROWING (28 Sep 2026, read off EllesmereUI 9.3's AuraKit).
---
--- `ShouldAurasBeSecret` is a question. Walking the aura list is the thing that actually happens,
--- and EllesmereUI's own note says the two do not always agree: "12.1: index scan hard-errors
--- under restrictions (M+/raid) even OOC; whitelisted lookups still work". So the honest test is
--- to TRY one slot and see whether the client refuses.
---
--- CACHED ON ONE SIDE ONLY, which is their trick and worth keeping: a "restricted" answer is
--- cached for the rest of the frame because building the error is what costs, while a "clear"
--- answer is re-probed every time - a stale `false` sends the caller into a scan that throws,
--- and a stale `true` costs one frame of a display nobody was watching.
local restrictedAt = -1

function NS.Restricted()
    if NS.Blind() then return true end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return true end
    local now = (GetTime and GetTime()) or 0
    if now == restrictedAt then return true end
    if pcall(get, "player", 1, "HELPFUL") then return false end
    restrictedAt = now
    return true
end

--- IS THIS PARTICULAR VALUE SECRET? (19 Sep 2026)
---
--- The client has `issecretvalue`, and this addon spent three days not knowing it: everything so
--- far was written as "assume it is secret and never touch it", which is safe for a health bar
--- and useless for a dead flag. `UnitIsDeadOrGhost` comes back as a secret BOOLEAN in combat,
--- and `if UnitIsDeadOrGhost(u) then` is refused - the client will not even let the test happen -
--- so the choice is not "read it or not", it is "ask first, then read".
---
--- Found by reading how Healium's Forever build paints its frames. It guards every value it puts
--- in a condition this way, and it is right to.
---
--- Answers false on a client without the function, which is exactly right: there, nothing is.
function NS.Secret(v)
    if not issecretvalue then return false end
    local ok, yes = pcall(issecretvalue, v)
    return (ok and yes) and true or false
end

--- A value you may put in an `if`, or nil when the client will not let you look. Saves every
--- caller writing the same two lines, and makes "we asked and were refused" visible in the code
--- rather than implied by a pcall.
function NS.Plain(v)
    if NS.Secret(v) then return nil end
    return v
end

--- ONE AURA, BY SPELL ID -- and the only way to ask that works while auras are secret (1 Oct 2026).
---
--- `NS.Restricted()` above exists because the INDEX walk hard-errors under instance restrictions.
--- This is the other half of that finding, and the more useful half. ForeverAuras 0.42.11 says it
--- plainly in its own source: there is no way to iterate a unit's auras while auras are secret,
--- "but we can call C_UnitAuras.GetUnitAuraBySpellID for each spell id we're interested in". They
--- then check `issecretvalue` on what comes back and skip it if it is secret.
---
--- SO THIS IS DELIBERATELY NOT GATED ON Blind(). Every other reader in this addon refuses while
--- the client is hiding auras, and that is right for a walk. A by-id lookup is the one question
--- the client will still answer, so gating it here would throw away the whole point. What it is
--- gated on instead is the answer: a secret table, or a call that throws, is never read.
---
--- The price, also from their comment: two auras with the same spell id are one answer, and you
--- cannot choose which. For a healer that is nearly free -- one Renew per target, one Earth Shield
--- in the raid -- and it is why this returns at most one aura and says so.
---
--- Returns aura, why:
---   table, nil        the client handed over an aura we may read
---   nil, "none"       the client answered, and that aura is not on them
---   nil, "secret"     the answer came back secret
---   nil, "refused"    the call itself threw
---   nil, "no spell"   no usable spell id was given
---   nil, "no api"     this client has no GetUnitAuraBySpellID (TBC, and older betas)
---
--- `NS.auraSeen` keeps the last `why` for `/bish auras`, the same way the range check keeps its
--- own. Guessing which branch ran is how an evening disappears; the client can just say.
function NS.AuraById(unit, spellID)
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not get then NS.auraSeen = "no api" return nil, "no api" end
    if type(unit) ~= "string" or type(spellID) ~= "number" then
        NS.auraSeen = "no spell"
        return nil, "no spell"
    end
    local ok, a = pcall(get, unit, spellID)
    if not ok then NS.auraSeen = "refused" return nil, "refused" end
    if NS.Secret(a) then NS.auraSeen = "secret" return nil, "secret" end
    if a == nil or a == false then NS.auraSeen = "none" return nil, "none" end
    NS.auraSeen = "read"
    return a, nil
end

--- Is one of these spell ids on them? Ranks are separate ids, so "Renew" is five questions, and
--- a shaman's Earth Shield is however many they have trained.
---
--- Returns true (one of them is up), false (the client answered for all of them and none is), or
--- nil -- which is the answer this addon cares most about getting right. nil means SOMETHING went
--- unanswered, and 0.6.1 shipped because an unanswered question read as a confident "no": a
--- refused aura list became "Earth Shield is not up on anyone", printed to a raid where it was up.
function NS.AnyAuraById(unit, ids)
    if type(ids) ~= "table" or #ids == 0 then return nil end
    local answered = false
    for _, id in ipairs(ids) do
        local a, why = NS.AuraById(unit, id)
        if a then return true end
        if why == "none" then answered = true else return nil end
    end
    -- NOT `return answered and false or nil`. That reads like the ternary it is pretending to be
    -- and is not one: `answered and false` is false, and `false or nil` is nil, so the function
    -- could never say a confident no. Written and caught the same hour (1 Oct 2026) - and it is
    -- the 0.6.1 bug's twin, an answered question coming back as "we could not tell".
    if answered then return false end
    return nil
end

--- MAY I COMPARE TWO UNIT TOKENS? (1 Oct 2026, read off EllesmereUI 9.3.4.)
---
--- `unit == "player"` is in four places in this addon, and on a client that can hand back a secret
--- unit token that comparison is exactly the shape that gets refused -- the same trap as a secret
--- boolean in an `if`, which cost us a dungeon on 21 Sep. EllesmereUI asks
--- `C_Secrets.CanCompareUnitTokens` before it compares, so we ask too.
---
--- Answers TRUE when the client has no opinion, because that is the honest default: on TBC, and on
--- a client without the function, comparing unit tokens is ordinary Lua. Only a clear "no" stops
--- the caller.
function NS.CanCompareUnits()
    if not (C_Secrets and C_Secrets.CanCompareUnitTokens) then return true end
    local ok, yes = pcall(C_Secrets.CanCompareUnitTokens)
    if not ok then return false end          -- the client refused to answer: do not compare
    local plain = NS.Plain(yes)
    if plain == nil then return false end    -- the answer is itself secret: same
    return plain ~= false
end

--- Is this unit the player? The question the four comparisons were really asking, with the guard
--- in one place. `UnitIsUnit` is the client's own answer and survives secret tokens; the string
--- compare is the fallback, and only when the client says comparing is allowed.
---
--- Returns nil when neither road is open, so a caller can tell "not you" from "could not tell".
function NS.IsPlayer(unit)
    if type(unit) ~= "string" then return nil end
    if UnitIsUnit then
        local ok, same = pcall(UnitIsUnit, unit, "player")
        if ok then
            local plain = NS.Plain(same)
            if plain ~= nil then return plain and true or false end
        end
    end
    if not NS.CanCompareUnits() then return nil end
    return unit == "player"
end

--- ARE UNIT STATS SECRET RIGHT NOW? (1 Oct 2026.)
---
--- Until now this addon had one answer for everything -- `NS.SECRET`, decided once at load -- and
--- treated health, mana and the rest as hidden for the whole session. That is safe and it is also
--- wrong: `C_Secrets.ShouldUnitStatsBeSecret` is a live question, separate from the aura one, and
--- the client will answer it. Where it says no, a plain read is allowed.
---
--- Nothing is rewritten to depend on this yet, on purpose: it goes into `/bish scan` first so the
--- answer can be watched for a few days before anything is built on it. The display bargain --
--- hand the value to the client, never read it -- keeps working either way.
function NS.StatsSecret()
    if not NS.SECRET then return false end
    if not (C_Secrets and C_Secrets.ShouldUnitStatsBeSecret) then return nil end
    local ok, yes = pcall(C_Secrets.ShouldUnitStatsBeSecret)
    if not ok then return true end
    local plain = NS.Plain(yes)
    if plain == nil then return true end
    return plain and true or false
end
