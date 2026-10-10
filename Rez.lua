-- BiSHealing / Rez.lua -- NO DOUBLE RES (10 Oct 2026).
--
-- Arn, asked what BiS Healing users could do together (the addon nearing 1,000 downloads): this
-- one first. Two healers walking up to the same corpse after a wipe and casting the same 10-second
-- res is the commonest waste there is.
--
-- The wire already exists. RezComm-1.0 (embedded, announce-only) puts every BiS user's res casts
-- on BiSInnervate's pipe - "4|RCLAIM|<corpse>", "4|RFREE|<corpse>", "4|RDONE|<corpse>". Until now
-- only BiSInnervate (frozen with TBC) LISTENED. This file listens, and the grid shows the claim
-- where it matters: "rez: Arn" in place of DEAD on that cell, until the res lands, fails, or
-- FZ.HOLD seconds pass (a res is 10 s; a claim that never hears back must not stick).
--
-- What it will not do: guess. A message the client hides (chat lockdown in an instance) is
-- dropped, and a corpse whose NAME the client hides cannot be matched to a cell - that cell simply
-- says DEAD, as it always did. Between pulls, where res happens, names and messages are plain.

local ADDON, NS = ...
local FZ = {}
NS.FZ = FZ

FZ.PREFIX = "BiSInn"            -- RezComm rides BiSInnervate's pipe, not LibBiSComm's "BiS"
FZ.PROTO = "4"                  -- == RezComm's PROTO; a mismatch is someone else's message
FZ.HOLD = 12                    -- seconds a claim stands without an RDONE / RFREE
FZ.claims = {}                  -- corpse short name -> { by = short name, at = GetTime() }

local function now() return (GetTime and GetTime()) or 0 end
local function secret(v) return NS.Secret and NS.Secret(v) end

--- "Name-Realm" -> "Name"; nil for anything hidden or not a name.
function FZ.Short(name)
    if name == nil or secret(name) or type(name) ~= "string" or name == "" then return nil end
    return (name:match("^([^%-]+)")) or name
end

--- One message off the wire. Answers true when it changed a claim.
function FZ.OnMessage(prefix, msg, channel, sender)
    -- the PREFIX first, on one question (the cost pass): every addon's messages come through here
    if secret(prefix) or prefix ~= FZ.PREFIX then return false end
    if secret(msg) or secret(sender) or type(msg) ~= "string" then return false end
    local proto, cmd, corpse = msg:match("^(%d+)|(%u+)|(.+)$")
    if proto ~= FZ.PROTO then return false end
    local who, dead = FZ.Short(sender), FZ.Short(corpse)
    if not (who and dead) then return false end
    local me = UnitName and FZ.Short((UnitName("player")))
    if who == me then return false end        -- your own res: you know, and RezComm sent it
    if cmd == "RCLAIM" then
        FZ.claims[dead] = { by = who, at = now() }
        return true
    elseif cmd == "RFREE" or cmd == "RDONE" then
        local c = FZ.claims[dead]
        if c and c.by == who then FZ.claims[dead] = nil return true end
    end
    return false
end

--- Who is ressing the person in this unit, or nil. Called only for a cell already showing DEAD,
--- and returns at once when nobody is claiming anything - the paint stays as cheap as it was.
function FZ.ClaimOn(unit)
    if not next(FZ.claims) or not UnitName then return nil end
    local ok, name = pcall(UnitName, unit)
    local dead = ok and FZ.Short(name)
    local c = dead and FZ.claims[dead]
    if not c then return nil end
    if now() - c.at > FZ.HOLD then FZ.claims[dead] = nil return nil end
    return c.by
end

function FZ.Start()
    if FZ.frame then return true end
    local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if reg then pcall(reg, FZ.PREFIX) end
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender)
        FZ.OnMessage(prefix, msg, channel, sender)
    end)
    FZ.frame = f
    return true
end

FZ.Start()
