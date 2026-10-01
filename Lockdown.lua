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
