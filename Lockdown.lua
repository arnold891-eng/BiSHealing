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
--   * COMBAT_LOG_EVENT_UNFILTERED registers and then never fires.
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

local ok, secret = pcall(function()
    return C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()
end)

NS.SECRET = (ok and secret) and true or false

--- True when the client is hiding numbers AND we are inside the secure lockdown: the window in
--- which auras, cooldowns and stats are secret too. Out of combat on the same client, they read.
function NS.Blind()
    if not NS.SECRET then return false end
    return InCombatLockdown and InCombatLockdown() or false
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
