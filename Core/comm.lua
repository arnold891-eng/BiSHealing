-- =========================================================================
-- BiS Healing -- Core/comm.lua : two shamans talking to each other
--
-- Split out of BiSHealing.lua on 9 Sep 2026. Carried whole: the BISHEAL prefix,
-- the ES state line, the version nag, the peer TTL, the chain-cast announce.
-- None of it changed in the move.
--
-- This file loads FIRST, before BiSHealing.lua, and that is deliberate: the
-- rest of the addon assigns into this table at ITS load time
-- (COMM.Charges = ESCharges, COMM.Unit = GuidToUnit), so the table has to
-- already exist. The cost of loading first is that nothing from BiSHealing.lua
-- exists yet, so the three things this file needs from over there -- Print, the
-- version string, and who currently carries my Earth Shield -- are reached
-- through NS at CALL time, never captured at load. Capture them here and they
-- are all nil forever.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

-- ------------------------------------------------------------ addon comm --
-- Two shamans, two shields, one raid. Until now the second shaman was inferred
-- from the combat log: watch for somebody else's Earth Shield charges, average
-- them, and hope. That works, eventually, and it is blind until they have
-- actually shielded someone in front of you.
--
-- If they are also running BiSHealing, none of that guesswork is necessary --
-- they can simply say who they are shielding and how big their charge is. This
-- is a strict upgrade: when a peer answers, the plan uses their real numbers;
-- when nobody answers, everything falls back to exactly the old inference.
--
-- Sent over ChatThrottleLib when it is loaded (it ships with LibHealComm in
-- Libs/), which keeps a raid full of addons from queueing each other into a
-- disconnect. Falls back to the raw API when it is absent.
local COMM = {
    PREFIX  = "BISHEAL",
    peers   = {},        -- name -> { guid=, charges=, heal=, at=, version= }
    TTL     = 90,        -- seconds of silence before a peer is forgotten
    BEAT    = 5,         -- heartbeat while in combat
    BEAT_IDLE = 20,      -- and out of it
    lastSend = 0,
    lastState = nil,     -- last state string sent, to skip identical repeats
    nagged  = false,
}

-- "1.0-rc42" -> 1000042. Written out deliberately rather than with a clever
-- gsub: WindfuryComm++ does this with string.gsub(v, ".", "0"), and "." is a
-- pattern matching ANY character, so every version there collapses to 0 and its
-- update check has never once fired. Escape the dot, parse the parts.
function COMM.VerNum(str)
    if type(str) ~= "string" then return 0 end
    local major, minor = str:match("^(%d+)%.(%d+)")
    local rc = str:match("rc(%d+)")
    return (tonumber(major) or 0) * 1000000
         + (tonumber(minor) or 0) * 1000
         + (tonumber(rc) or 0)
end

function COMM.Channel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

function COMM.Send(msg)
    local channel = COMM.Channel()
    if not channel then return end
    if ChatThrottleLib then
        ChatThrottleLib:SendAddonMessage("NORMAL", COMM.PREFIX, msg, channel)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(COMM.PREFIX, msg, channel)
    elseif SendAddonMessage then
        SendAddonMessage(COMM.PREFIX, msg, channel)
    end
    COMM.lastSend = GetTime()
end

-- Everything about my shield in one line: who has it, how many charges are
-- left, and what one charge of mine is worth.
function COMM.State()
    local charges = 0
    local esTarget = NS.ESTarget()
    if esTarget then
        -- COMM.Unit / COMM.Charges, not GuidToUnit / ESCharges: both of those
        -- locals are declared hundreds of lines BELOW this function, so naming
        -- them here read nil globals and every broadcast claimed zero charges.
        -- They are attached to the table where they are defined instead.
        local u = COMM.Unit and COMM.Unit(esTarget)
        if u and COMM.Charges then charges = select(1, COMM.Charges(u)) or 0 end
    end
    return ("ES:%s:%d:%d:%s"):format(esTarget or "-", charges or 0,
                                     math.floor(COMM.MyCharge() or 0), NS.VERSION)
end

-- What one of MY charges heals for: measured from real charges when the log has
-- seen some, otherwise the 28.6% coefficient seed.
function COMM.MyCharge()
    if COMM.CasterHeal then
        local h = COMM.CasterHeal(UnitName("player"))
        if h and h > 0 then return h end
    end
    return 0
end

function COMM.Tick(force)
    if not COMM.Channel() then return end
    local now = GetTime()
    local beat = InCombatLockdown() and COMM.BEAT or COMM.BEAT_IDLE
    local state = COMM.State()
    -- send when the state actually changed, or on the heartbeat so a shaman who
    -- zoned in mid-fight learns the picture without having to ask
    if force or state ~= COMM.lastState or (now - COMM.lastSend) >= beat then
        COMM.lastState = state
        COMM.Send(state)
    end
end

-- Our own Chain Heal, announced as the cast is SENT rather than when it lands.
-- UNIT_SPELLCAST_SENT is the only event that carries the target, so it is worth
-- the extra handler: it puts a mark on their frames a full cast time early.
function COMM.SendChainCast(targetName)
    if not targetName then return end
    -- A group member's NAME is itself a valid unit id, so this is one lookup
    -- and no roster walk. It also avoids RosterUnits, which is declared four
    -- hundred lines below here -- calling it from this early in the file read a
    -- nil global and threw on every Chain Heal cast.
    local guid = UnitGUID(targetName)
    if guid then COMM.Send("CH:" .. guid) end
end

function COMM.OnMessage(prefix, message, _, sender)
    if prefix ~= COMM.PREFIX or not message then return end
    local me = UnitName("player")
    local short = sender and (sender:match("^[^-]+") or sender)
    if not short or short == me then return end

    local kind, guid, charges, heal, ver = strsplit(":", message)

    if kind == "CH" then
        -- a peer just started a chain at this target
        -- COMM.CastTime, not ChainCastTime: the local is declared a hundred
        -- lines BELOW this function, so the bare name here would compile to a
        -- global read and silently be nil forever -- the trap in the header.
        -- a peer announces the target they SENT the cast at: always the primary
        COMM.MarkChain(guid, short,
                       (COMM.CastTime and COMM.CastTime() or 2.5) + COMM.CHAIN_HOLD,
                       true)
        return
    end

    if kind ~= "ES" then return end

    local p = COMM.peers[short] or {}
    p.guid    = (guid ~= "-") and guid or nil
    p.charges = tonumber(charges) or 0
    p.heal    = tonumber(heal) or 0
    p.version = ver
    p.at      = GetTime()
    COMM.peers[short] = p

    -- version nag, once, and only for a genuinely higher build
    if not COMM.nagged and COMM.VerNum(ver) > COMM.VerNum(NS.VERSION) then
        COMM.nagged = true
        -- the header lives in UI/options.lua, which loads after this file; NS is
        -- the only thing that crosses, and this only ever runs at play time
        local W = NS.CFG
        if W and W.Say then W.Say(("%s has v%s"):format(short, tostring(ver)), "gold") end
        NS.Print(("%s is running v%s -- newer than your v%s"):format(short, ver, NS.VERSION))
    end
end

-- Peers that have spoken recently. Anyone quiet for TTL is dropped: they logged
-- out, left, or turned the addon off, and a stale shield target is worse than
-- no shield target.
function COMM.Live()
    local out, now = {}, GetTime()
    for name, p in pairs(COMM.peers) do
        if (now - (p.at or 0)) <= COMM.TTL then out[name] = p
        else COMM.peers[name] = nil end
    end
    return out
end

-- Is this GUID already carrying another BiSHealing shaman's shield? Known the
-- moment they cast it, rather than when our own aura sweep next runs.
function COMM.ShieldedByPeer(guid)
    if not guid then return nil end
    for name, p in pairs(COMM.Live()) do
        if p.guid == guid and (p.charges or 0) > 0 then return name end
    end
    return nil
end

-- BiSHealing.lua picks this up as its own local, so all 80-odd COMM.* lines
-- over there read exactly as they did when this was one file.
NS.COMM = COMM
