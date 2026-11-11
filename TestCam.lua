--[[
  BiSHealing :: TestCam.lua - THE TEST CAMERA, a secret alpha feature (9 Nov 2026).

  Arn: "If this pip ever fires, please take a screenshot ... then we compare with the logs." In a fight nobody can
  watch the radar AND play, and nobody can /reload to look. So while a test is on, the addon takes the pictures
  itself, and writes down the second and the reason of each one. Afterwards Claude pairs every picture with the
  combat log file at that second (_bisdev/companion/testshots.py): the log says who was hurt, the picture says what
  the radar showed.

  WHEN IT SHOOTS (only what the addon can SEE - "pip lit" and "below 90%" are decided by the client's curves on secret
  health, so those moments come from a timer shot plus the log):
    pull   PLAYER_REGEN_DISABLED
    timer  every `every` seconds in a fight (20 by default, 0 = none)
    a tool cast: Mana Tide, a mana potion (and whatever else the radar's own cast clock names, RD.OnCast) - not Mana
           Spring, which is cast too often to be worth a picture
    end    PLAYER_REGEN_ENABLED
  Two seconds apart at least (the file name is the second: two in one second would share it); a reason that comes
  inside that gap is added to the shot just taken ("timer+tide"). At most CAP shots in one fight.

  WHAT IT WRITES. Each shot: the file stem the client uses (WoWScrnShot_MMDDYY_HHMMSS), why, the run, the fight, and
  whether the client said it was written (SCREENSHOT_SUCCEEDED / _FAILED). Account-wide (`cam`), so the list reaches
  disk at the next /reload or logout. Only these files are the test's: Arn's own PrintScreens are left alone.

  ARMED, NOT ALWAYS ON. The alpha being on is not enough - nobody wants a Screenshots folder full of every fight
  for a week. `/bish alpha cam start [minutes]` arms it (120 by default); it stops by itself after that, and on
  `/bish alpha cam stop`.

  THE PROBE. Screenshot() in a fight is unproven on Forever (BiS Memories shoots out of one). If the client blocks
  it, ADDON_ACTION_BLOCKED/_FORBIDDEN names us and Screenshot(): the camera stops shooting in fights, says so at the
  fight's end, and remembers it (`cam.blocked`). Nothing secret is read anywhere in this file.

  COST. Disarmed or out of a fight there is no OnUpdate at all; in a fight the OnUpdate adds up `elapsed` and asks
  the client nothing until a shot is due.
]]
local ADDON, NS = ...

local CAM = {}
NS.CAM = CAM

CAM.KEY = "cam"
CAM.GAP = 2              -- seconds between two shots at least
CAM.CAP = 60             -- shots in one fight at most
CAM.KEEP = 400           -- shots remembered at most (the oldest go first)
CAM.EVERY = 20           -- the timer, seconds
CAM.MINUTES = 120        -- how long `start` arms it
CAM.SKIP = { spring = true }

local Print = NS.Print

local function now() return (GetTime and GetTime()) or 0 end
local function wall() return (time and time()) or 0 end

local function db()
    local d = NS.DB()
    d.cam = type(d.cam) == "table" and d.cam or {}
    local c = d.cam
    c.shots = type(c.shots) == "table" and c.shots or {}
    return c
end
CAM.DB = db

--- The stem the client gives the picture: WoWScrnShot_MMDDYY_HHMMSS (BiS Memories reads it the same way).
function CAM.Stem()
    return "WoWScrnShot_" .. ((date and date("%m%d%y_%H%M%S")) or tostring(wall()))
end

--- Is the camera armed right now? The black box recording (BlackBox.lua) - or the alpha, this feature, and inside the
--- time `start` gave it. Both need the black box KEY on this PC (10 Nov: the same gate as the black box - a player
--- who reads this code can't arm it by accident; without the key addon there is no camera at all).
function CAM.Armed()
    local BB = NS.BB
    if not (BB and BB.Key and BB.Key()) then return false end
    if BB.Recording() then return true end
    if not (NS.AlphaOn and NS.AlphaOn(CAM.KEY)) then return false end
    local c = db()
    return type(c.untilAt) == "number" and wall() < c.untilAt
end

--- One picture, for a reason. Returns the shot's entry, or nil (not armed, too soon, the cap, blocked in a fight).
function CAM.Shot(why)
    if not CAM.Armed() or not Screenshot then return nil end
    local c = db()
    local fight = CAM.inFight == true
    -- refused once in a fight: no more in one - but the pull's shot comes just before the lockdown starts
    if fight and c.blocked and why ~= "pull" then return nil end
    local t = now()
    local last = CAM.last
    if last and t - last.t < CAM.GAP then
        -- inside the gap: the reason joins the shot just taken (the saved entry itself)
        local e = last.entry
        if not ("+" .. e.why .. "+"):find("+" .. why .. "+", 1, true) then e.why = e.why .. "+" .. why end
        return nil
    end
    if fight and (CAM.fightShots or 0) >= CAM.CAP then return nil end
    local e = { stem = CAM.Stem(), why = why, run = c.run, fight = fight and CAM.fight or nil, at = wall() }
    CAM.last = { t = t, entry = e }
    c.shots[#c.shots + 1] = e
    while #c.shots > CAM.KEEP do table.remove(c.shots, 1) end
    if fight then CAM.fightShots = (CAM.fightShots or 0) + 1 end
    CAM.pending = e
    CAM.taken = (CAM.taken or 0) + 1
    pcall(Screenshot)
    return e
end

-- ------------------------------------------------------------------ the fight's clock

local ticker = CreateFrame("Frame")
CAM.ticker = ticker

-- every frame of a fight while armed: arithmetic only (CAM.every is read once, at the pull)
local function onUpdate(_, elapsed)
    CAM.acc = (CAM.acc or 0) + (elapsed or 0)
    local every = CAM.every or CAM.EVERY
    if every <= 0 or CAM.acc < every then return end
    CAM.acc = 0
    if not CAM.Armed() then ticker:SetScript("OnUpdate", nil) return end
    CAM.Shot("timer")
end

function CAM.Pull()
    CAM.inFight = true
    if not CAM.Armed() then return end
    local c = db()
    c.fights = (c.fights or 0) + 1
    CAM.fight, CAM.fightShots, CAM.acc = c.fights, 0, 0
    CAM.every = c.every or CAM.EVERY
    CAM.Shot("pull")
    if CAM.every > 0 and not c.blocked then ticker:SetScript("OnUpdate", onUpdate) end
end

function CAM.FightOver()
    ticker:SetScript("OnUpdate", nil)
    local was = CAM.inFight
    CAM.inFight = nil
    if not was or not CAM.Armed() then return end
    local n = CAM.fightShots or 0
    CAM.Shot("end")
    local c = db()
    if c.blocked and CAM.blockedNow then
        CAM.blockedNow = nil
        Print("|cffffb340test camera: the game refused a screenshot in the fight|r - from now on only the pull and the end")
    else
        Print("|cff968eadtest camera: %d shot%s in that fight|r", n + 1, n == 0 and "" or "s")
    end
end

--- A tool cast the radar's clock named (Radar.lua hands it over).
function CAM.Cast(kind)
    if not kind or CAM.SKIP[kind] then return nil end
    return CAM.Shot(tostring(kind))
end
NS.CamShot = CAM.Cast

-- ------------------------------------------------------------------ the words

local function status()
    local c = db()
    if CAM.Armed() then
        local left = math.max(0, math.floor(((c.untilAt or 0) - wall()) / 60 + 0.5))
        Print("test camera |cff5dff9barmed|r for %d more min - run %d, %d shot%s so far.  |cff968ead/bish alpha cam stop|r",
            left, c.run or 0, CAM.taken or 0, (CAM.taken or 0) == 1 and "" or "s")
    else
        Print("test camera: off.  |cff968ead/bish alpha cam start [minutes]|r")
    end
    local every = c.every or CAM.EVERY
    Print("  |cff968eadshoots at the pull, %s, on Mana Tide and potions, and at the fight's end|r",
        every > 0 and ("every " .. every .. " s in a fight") or "no timer")
    if c.blocked then Print("  |cffffb340the game refused a screenshot in a fight once - only pull and end now|r") end
    Print("  |cff968ead%d shot%s remembered. Say done to Claude after a /reload.|r", #c.shots, #c.shots == 1 and "" or "s")
end

function CAM.Command(rest)
    local c = db()
    local word, arg = tostring(rest or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if word == "start" then
        if not NS.AlphaOn(CAM.KEY) then
            Print("test camera: the alpha is off - /bish alpha on first")
            return false
        end
        if not (NS.BB and NS.BB.Key and NS.BB.Key()) then
            Print("test camera: needs the black box key on this PC (_bisdev/companion/bbkey.sh)")
            return false
        end
        local mins = tonumber(arg) or CAM.MINUTES
        mins = math.max(1, math.min(600, math.floor(mins)))
        c.run = (c.run or 0) + 1
        c.untilAt = wall() + mins * 60
        CAM.taken, CAM.last = 0, nil
        Print("test camera |cff5dff9bON|r for %d min (run %d).  |cff968ead/bish alpha cam stop|r", mins, c.run)
        if CAM.inFight then CAM.Pull() end
        return true
    elseif word == "stop" then
        c.untilAt = nil
        ticker:SetScript("OnUpdate", nil)
        Print("test camera off - %d shot%s this run. Say done to Claude after a /reload.", CAM.taken or 0,
            (CAM.taken or 0) == 1 and "" or "s")
        return true
    elseif word == "every" then
        local s = tonumber(arg)
        if not s then Print("test camera: /bish alpha cam every <seconds>  (0 = no timer)") return false end
        c.every = math.max(0, math.min(120, math.floor(s)))
        if c.every > 0 and c.every < 5 then c.every = 5 end
        if CAM.inFight then CAM.every = c.every end
        Print("test camera: %s", c.every > 0 and ("a shot every " .. c.every .. " s in a fight") or "no timer shots")
        return true
    elseif word == "now" then
        local e = CAM.Shot("asked")
        if not e then Print("test camera: no shot (%s)", CAM.Armed() and "too soon" or "not armed - /bish alpha cam start") end
        return e ~= nil
    elseif word == "clear" then
        c.shots, c.blocked = {}, nil
        Print("test camera: the list is empty (the pictures themselves are untouched)")
        return true
    end
    status()
    return CAM.Armed()
end

-- ------------------------------------------------------------------ events

local ev = CreateFrame("Frame")
CAM.events = ev
for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
                     "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_REGEN_DISABLED" then CAM.Pull()
    elseif event == "PLAYER_REGEN_ENABLED" then CAM.FightOver()
    elseif event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
        local e = CAM.pending
        if e then e.ok = (event == "SCREENSHOT_SUCCEEDED") CAM.pending = nil end
    elseif a1 == ADDON and tostring(a2):find("Screenshot", 1, true) then
        -- the probe's answer: refused. A shot in a fight never again, until `clear`.
        local c = db()
        if CAM.pending then CAM.pending.ok = false CAM.pending = nil end
        if CAM.inFight then
            c.blocked, CAM.blockedNow = true, true
            ticker:SetScript("OnUpdate", nil)
        end
    end
end)

NS.AlphaFeature{ key = CAM.KEY, name = "the test camera",
                 desc = "takes screenshots by itself in fights for testing (/bish alpha cam start), for Claude to pair with the combat log",
                 apply = function() if not CAM.Armed() then ticker:SetScript("OnUpdate", nil) end end,
                 cmd = function(rest) return CAM.Command(rest) end }
