--[[
  RezComm-1.0  --  announce-only rez claims on the BiSInnervate wire.

  Arn, 9 Sep 2026: "If I have a rez button I'll let you guys know who I'm rezzing,
  and will let you know if it fails. I don't have any other function than letting
  the world know."

  A player carrying ANY BiS addon that embeds this file puts their rez casts on
  the wire, so a BiSInnervate raid coordinates around them WITHOUT that player
  running Innervate - "one addon gets you half way". It says three things and
  nothing else:

      4|RCLAIM|<corpse>    my rez cast has started
      4|RFREE|<corpse>     it was interrupted, failed, or I stopped
      4|RDONE|<corpse>     it landed

  Announce-only: it registers NO receive handler, draws nothing, prints nothing,
  and holds no state past the one pending cast. Acting on a claim is the feature
  addon's job (BiSInnervate, and only it) - never this file's.

  It rides BiSInnervate's own pipe (prefix "BiSInn"), NOT LibBiSComm's "BiS".
  The protocol number MUST equal BiSInnervate's NS.PROTOCOL (Core/Util.lua). Read
  off disk 9 Sep 2026: 4. If Innervate ever bumps it, every emitter goes silent
  (its OnMessage rejects a mismatched proto and blames "a newer version"), so the
  test asserts the number this file sends and the mixed-raid world proves a real
  Innervate client accepts it.

  Rebirth is DELIBERATELY excluded (Arn: a long-cooldown combat rez reserved for
  the pull, never spent after a wipe) - same call BiSInnervate's rez table makes.

  Self-guarded like LibBiSComm: any BiS addon may ship a copy; newest MINOR wins
  and upgrades in place. It stands down entirely when BiSInnervate is installed,
  because Innervate announces its own casts and two emitters would double up.

  Canonical copy lives in _bisdev/RezComm-1.0/; copied byte-identical into each
  embedder under Libs\, never edited in place.
]]

local MAJOR, MINOR = "RezComm-1.0", 3
local RC = _G.BiSRezComm
if RC and (RC.MINOR or 0) >= MINOR then return end
RC = RC or {}
_G.BiSRezComm = RC
RC.MAJOR, RC.MINOR = MAJOR, MINOR

local PREFIX = "BiSInn"    -- BiSInnervate's pipe, not LibBiSComm's "BiS"
local PROTO  = 4           -- == BiSInnervate NS.PROTOCOL (Core/Util.lua); disk truth 9 Sep 2026
local SEP    = "|"
RC.PROTO = PROTO

-- Rez spell IDs, copied from BiSInnervate REZ_ID_CLASS (Core/Util.lua):
-- Priest Resurrection, Paladin Redemption, Shaman Ancestral Spirit, every rank.
-- No Rebirth, on purpose.
local REZ_ID = {}
for _, id in ipairs({
  2006, 2010, 10880, 10881, 20770, 25435,   -- Resurrection (priest)
  7328, 10322, 10324, 20772, 20773,         -- Redemption (paladin)
  2008, 20609, 20610, 20776, 20777, 25590,  -- Ancestral Spirit (shaman)
}) do REZ_ID[id] = true end

-- Match by ID first. As a net, also match by the localized spell NAME resolved
-- once from those IDs, so a rank whose id we missed is still caught - never match
-- a hardcoded English string (that is how a non-English client silently misses).
-- MINOR 2 (17 Sep 2026): the Forever beta (1.60.1.69893, TOC 16001) has no global
-- GetSpellInfo - only C_Spell.GetSpellInfo, and THAT one answers with a table
-- (info.name), not the name as the first return. Take the C_ one first, the global
-- second, and read whichever shape came back.
local function SpellName(id)
  local getInfo = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
  if not getInfo or not id then return nil end
  local info = getInfo(id)
  if type(info) == "table" then return info.name end
  return info
end
RC.SpellName = SpellName

local rezName
local function RezNames()
  if rezName then return rezName end
  rezName = {}
  for id in pairs(REZ_ID) do
    local n = SpellName(id)
    if n then rezName[n] = true end
  end
  return rezName
end

local function IsRez(spellID)
  if not spellID then return false end
  if REZ_ID[spellID] then return true end
  local n = SpellName(spellID)
  return (n and RezNames()[n]) and true or false
end
RC.IsRez = IsRez

--------------------------------------------------------------------
-- send
--------------------------------------------------------------------

-- A NAME THE CLIENT WILL NOT LET US READ (5 Oct 2026, from Arn's own screen).
--
--     RezComm-1.0.lua:104: attempt to index local 'name' (a secret string value, while execution
--     tainted by 'BiSGamba')
--
-- `UNIT_SPELLCAST_SENT` carries the name of whoever you are casting on, and on WoW Forever that
-- name can be a SECRET VALUE. It is truthy, so `if not name` let it straight through - and the two
-- calls in between did not help either: **`tostring()` and `Ambiguate()` both hand it back STILL
-- SECRET**, so the error only arrived at the `:match`, four lines from where it could have been
-- stopped. Nothing but `issecretvalue` catches one.
--
-- Third time this week the same shape has turned up underneath a guard built for it: BiSMemories
-- 0.5.1 fixed it in CHAT_MSG_LOOT, LibBiSComm minor 7 fixed it on the wire yesterday, and here it
-- was again in the other shared lib.
--
-- A nil is the honest answer: we do not know who that is. Every caller already handles not knowing,
-- and a claim nobody can be named in is a claim worth dropping - better a resurrection that is not
-- announced than an error in the middle of one.
local function Short(name)
  if name == nil then return nil end
  if issecretvalue ~= nil and issecretvalue(name) == true then return nil end
  if type(name) ~= "string" then
    name = tostring(name)
    -- tostring does not launder a secret on this client; ask again before touching it
    if issecretvalue ~= nil and issecretvalue(name) == true then return nil end
    if type(name) ~= "string" then return nil end
  end
  if Ambiguate then
    local short = Ambiguate(name, "none")
    if issecretvalue ~= nil and issecretvalue(short) == true then return nil end
    if type(short) == "string" then name = short end
  end
  return (name:match("^[^-]+")) or name
end

local function GroupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    return "INSTANCE_CHAT"     -- dungeon-finder group: RAID/PARTY are dropped entirely
  end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  return nil
end
RC.GroupChannel = GroupChannel

RC.sent = RC.sent or {}   -- last messages, for tests
local function Send(cmd, name)
  name = Short(name)
  if not name or name == "" then return false end
  local chan = GroupChannel()
  if not chan then return false end
  local msg = PROTO .. SEP .. cmd .. SEP .. name
  if #msg > 250 then return false end   -- the client silently drops >255; do not lose it
  -- REZ pushes IMMEDIATELY, both directions - no jitter, no throttle. LibBiSComm
  -- jitters answers 1-3s so 25 clients never reply on one tick; that rule is
  -- FATAL here. A rez is decided in its first second, so a claim delayed 1-3s
  -- lands after everyone else already clicked - the exact collision this exists
  -- to prevent. Do not "fix" this into a scheduled send.
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(PREFIX, msg, chan)
  elseif SendAddonMessage then
    SendAddonMessage(PREFIX, msg, chan)
  else
    return false
  end
  RC.sent[#RC.sent + 1] = msg
  RC.last = msg
  return true
end
RC._Send = Send

--------------------------------------------------------------------
-- the one pending cast
--------------------------------------------------------------------

-- Does an ending event (interrupt / fail / stop) concern OUR pending rez? Match
-- on the cast's own guid or spell id; never release a claim for a cast that was
-- not this one (the BiSRez v2.3 scar: any interrupted cast freed the corpse).
local function Mine(p, castGUID, spellID)
  if not p then return false end
  if castGUID and p.guid and castGUID == p.guid then return true end
  if spellID and p.spell and spellID == p.spell then return true end
  -- STOP can arrive with neither on some clients; a pending rez and no better
  -- signal still resolves, since only one cast is ever pending
  if castGUID == nil and spellID == nil then return true end
  return false
end

function RC:OnSent(unit, target, castGUID, spellID)
  if unit ~= "player" or not IsRez(spellID) then return end
  local name = Short(target)
  if not name or name == "" then return end
  self.pending = { name = name, guid = castGUID, spell = spellID }
  Send("RCLAIM", name)
end

function RC:OnSucceeded(unit, castGUID, spellID)
  local p = self.pending
  if unit ~= "player" or not p or not Mine(p, castGUID, spellID) then return end
  Send("RDONE", p.name)
  self.pending = nil
end

-- INTERRUPTED / FAILED / FAILED_QUIET / STOP all land here: the cast is over and
-- did not land, so free the corpse. STOP fires AFTER success/interrupt, but those
-- already cleared pending, so it is a no-op then; it only bites a plain cancel.
function RC:OnEnded(unit, castGUID, spellID)
  local p = self.pending
  if unit ~= "player" or not p or not Mine(p, castGUID, spellID) then return end
  Send("RFREE", p.name)
  self.pending = nil
end

--------------------------------------------------------------------
-- boot
--------------------------------------------------------------------

-- MINOR 2: C_AddOns first (Forever has no global IsAddOnLoaded), the global second
local function InnervateLoaded()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  return (isLoaded and isLoaded("BiSInnervate")) and true or false
end

function RC:Boot()
  if self._booted then return end
  self._booted = true
  -- Innervate announces its own casts; a second emitter would double every claim.
  -- This file is for players who do NOT run Innervate.
  if InnervateLoaded() then self.standDown = true; return end
  self.standDown = false

  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  elseif RegisterAddonMessagePrefix then
    pcall(RegisterAddonMessagePrefix, PREFIX)
  end

  local f = self._frame or (CreateFrame and CreateFrame("Frame"))
  if not f then return end
  self._frame = f
  local function reg(e) pcall(f.RegisterEvent, f, e) end
  reg("UNIT_SPELLCAST_SENT")
  reg("UNIT_SPELLCAST_SUCCEEDED")
  reg("UNIT_SPELLCAST_INTERRUPTED")
  reg("UNIT_SPELLCAST_FAILED")
  reg("UNIT_SPELLCAST_FAILED_QUIET")
  reg("UNIT_SPELLCAST_STOP")
  f:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
      RC:OnSent(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      RC:OnSucceeded(...)
    else
      RC:OnEnded(...)
    end
  end)
end

-- Self-boot at login (when IsAddOnLoaded is authoritative), so an embedder needs
-- only the TOC line - not a single call. One login frame, even across upgrades.
if CreateFrame and not RC._login then
  local b = CreateFrame("Frame")
  RC._login = b
  b:RegisterEvent("PLAYER_LOGIN")
  b:SetScript("OnEvent", function() RC:Boot() end)
end

return RC
