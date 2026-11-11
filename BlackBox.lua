--[[
  BiSHealing :: BlackBox.lua - THE BLACK BOX, the radar's BOTTOM rail (10 Nov 2026).

  Arn, from a photo of a jet's radio panel: "bottom rail is going to be utility, it's going to have the status bar of
  turning on combat recording our 'black box' ... I enter a ping or alpha numeric number and when I hit the submit
  button it starts the combat log and informs the companion app to be ready for screenshots and to run the live logs,
  it'll put a timer when it's safe to reload for the addon to import the data" ... "When I submit if it's the correct
  code it reloads the game" ... "Build the bottom raid with the squawk box thing".

  THE RAIL: under the tool rail and the square, the hull's dark. Left, ONE LAMP with a soft glow; beside it the words
  BLACK BOX, the status, and a small screen (the scratchpad) where the code you type shows. Right, a keypad: the squawk
  digits 1-7 and 0, an A, CLR and EXEC (the mockup's keys).

  THE LAMP (Arn: "red all the time, green when it's safe to reload, yellow when it's close to a log read, red no
  reload. Soft glow"). Red is the resting state, not an alarm.
      off   REC OFF          red     not recording (everyone without the key, always)
      rec   REC mm:ss        red     recording; in a fight, or no fight yet
      wait  WAIT n s         yellow  a fight just ended: the log is being written and read (BB.WAIT seconds)
      safe  SAFE TO RELOAD   green   /reload now and the addon imports what the companion made

  NO CODE IN THIS ADDON (Arn: "Other people won't have this companion and I don't want them to accidentally guess the
  code so it can't be in the addon where they can sniff it out"). The code lives in a tiny KEY ADDON on Arn's PC only
  (Interface/AddOns/BiSBlackBox, written by _bisdev/companion/bbkey.sh, never on GitHub or CurseForge). It sets
  BiSBlackBoxKey = { Check = function(code) ... end }. Without it every code is refused with a reply, the lamp stays
  red, and nothing ever reloads, logs or takes a picture.

  THE KEYPAD SHOWS FOR EVERYONE (Arn: "it'll be the Diablo 2 lobby gem flavor they will always be curious what it does
  and try codes to see if they can crack it"). No tooltip, no help line, no word about it anywhere. Refusals are short
  and cold; one in BB.RARE is a rarer one ("Yes rare replies ... in the spirit of star wars imperial navy" - our own
  words, nothing from the films).

  THE RIGHT CODE, out of a fight only:
    not recording -> START: the combat log on (remembered as ours only if it was off - courtesy: logging someone else
                     turned on is never turned off by us), the test camera armed for the run (TestCam.lua), the run
                     written to the account save, then ReloadUI(). The reload is the point: SavedVariables reach the
                     disk only at a reload, and that file is how the companion learns a recording started.
    recording     -> STOP: the log off if we turned it on, the camera disarmed, then ReloadUI() (the companion learns
                     it stopped the same way).
  After a reload the log is turned back on if it fell off. A recording stops itself after BB.MINUTES.

  SOUNDS: none yet - Arn picks them in the sound explorer (11 Nov); BB.SOUND is where they go.

  COST: no key = no OnUpdate ever (a reply clears itself through one, then it goes). Recording: one tick a second,
  and a font string is set only when its words change.
]]
local ADDON, NS = ...

local BB = {}
NS.BB = BB

BB.MIN, BB.MAX = 4, 6         -- a code's length
BB.WAIT = 15                  -- seconds after a fight before it is safe to reload
BB.MINUTES = 120              -- a recording stops itself after this
BB.SAY = 3                    -- seconds a reply stays on the screen
BB.RARE = 8                   -- one refusal in RARE is a rare one
BB.RAIL_H = 46
BB.KW, BB.KH, BB.KGAP = 18, 17, 2
BB.SOUND = {}                 -- click / deny / arm: Arn's picks from the sound explorer (11 Nov)
-- the keypad, two rows (the mockup's keys: squawk digits 0-7, an A, CLR, EXEC)
BB.ROWS = { { "1", "2", "3", "4", "5", "CLR" }, { "6", "7", "0", "A", "EXEC" } }
BB.WIDE = { CLR = 32, EXEC = 52 }

BB.COL = { lilac = { 0.79, 0.72, 1.00 }, dim = { 0.44, 0.42, 0.53 }, green = { 0.36, 1.00, 0.61 },
           amber = { 1.00, 0.70, 0.28 }, red = { 1.00, 0.36, 0.36 }, screen = { 0.03, 0.04, 0.05 },
           key = { 0.07, 0.09, 0.10 } }
BB.LAMP = { off = "red", rec = "red", wait = "amber", safe = "green" }

-- refusals: terse, cold, a fleet's terminal (our own words)
BB.DENY = { "ACCESS DENIED", "CODE REJECTED", "NOT AUTHORIZED", "INVALID CLEARANCE" }
BB.DENY_RARE = { "ATTEMPT LOGGED", "THIS TERMINAL IS MONITORED", "REMAIN AT YOUR STATION",
                 "REPORT TO THE DECK OFFICER", "CLEARANCE INSUFFICIENT", "SECURITY NOTIFIED" }

BB.pad = ""

local Print = NS.Print
local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local DISC = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local function now() return (GetTime and GetTime()) or 0 end
local function wall() return (time and time()) or 0 end
local function combat() return (InCombatLockdown and InCombatLockdown()) and true or false end

local function db()
    local d = NS.DB()
    d.bb = type(d.bb) == "table" and d.bb or {}
    return d.bb
end
BB.DB = db

--- The key addon, when it is installed on this PC (never shipped): { Check = function(code) -> true }.
function BB.Key()
    local k = _G.BiSBlackBoxKey
    if type(k) == "table" and type(k.Check) == "function" then return k end
    return nil
end

--- Recording right now? The key, a started run, inside its time.
function BB.Recording()
    local b = db()
    return b.on == true and BB.Key() ~= nil and type(b.untilAt) == "number" and wall() < b.untilAt
end

function BB.State()
    if not BB.Recording() then return "off" end
    if BB.inFight then return "rec" end
    if BB.waitUntil then return now() < BB.waitUntil and "wait" or "safe" end
    return "rec"
end

local function logging()
    if not LoggingCombat then return false end
    local ok, on = pcall(LoggingCombat)
    return ok and on and true or false
end

-- ------------------------------------------------------------------ start / stop

function BB.Start()
    local b = db()
    b.run = (b.run or 0) + 1
    b.on, b.at, b.untilAt = true, wall(), wall() + BB.MINUTES * 60
    b.stoppedAt, b.stopWhy = nil, nil
    local was = logging()
    b.logOurs = (not was) or nil
    if not was and LoggingCombat then pcall(LoggingCombat, true) end
    BB.waitUntil = nil
    -- the test camera's run counts with the recording (TestCam.lua arms itself while BB.Recording())
    local CAM = NS.CAM
    if CAM and CAM.DB then
        local c = CAM.DB()
        c.run = (c.run or 0) + 1
        CAM.taken, CAM.last = 0, nil
    end
end

function BB.Stop(why)
    local b = db()
    if b.logOurs and LoggingCombat then pcall(LoggingCombat, false) end
    b.on, b.untilAt, b.logOurs = nil, nil, nil
    b.stoppedAt, b.stopWhy = wall(), why
    BB.waitUntil = nil
end

function BB.Reload()
    if combat() or not ReloadUI then return false end
    BB.reloads = (BB.reloads or 0) + 1
    ReloadUI()
    return true
end

-- ------------------------------------------------------------------ the screen's words

--- A refusal. `roll` (1..RARE) for the tests; 1 = a rare one.
function BB.Deny(roll, pick)
    local r = roll or math.random(1, BB.RARE)
    local list = (r == 1) and BB.DENY_RARE or BB.DENY
    return list[pick or math.random(1, #list)]
end

function BB.Say(words, col)
    BB.said, BB.saidCol = words, col or "red"
    BB.sayUntil = now() + BB.SAY
    BB.Paint()
    BB.Wake()
end

-- ------------------------------------------------------------------ the keys

--- EXEC. Returns what happened: "combat", "short", "denied", "start", "stop".
function BB.Exec()
    local code = BB.pad
    BB.pad = ""
    if combat() then BB.Say("NOT IN COMBAT", "amber") return "combat" end
    if #code < BB.MIN then BB.Say("ENTER " .. BB.MIN .. " TO " .. BB.MAX, "amber") return "short" end
    local k, good = BB.Key(), false
    if k then
        local ok, r = pcall(k.Check, code)
        good = ok and r == true
    end
    if not good then
        BB.denied = (BB.denied or 0) + 1
        BB.Say(BB.Deny(), "red")
        return "denied"
    end
    local what
    if BB.Recording() then
        BB.Stop("code")
        BB.Say("RECORDER OFF", "green")
        what = "stop"
    else
        BB.Start()
        BB.Say("CODE ACCEPTED", "green")
        what = "start"
    end
    BB.Reload()
    return what
end

function BB.Press(k)
    if k == "EXEC" then return BB.Exec() end
    if k == "CLR" then
        if BB.sayUntil then BB.sayUntil = nil else BB.pad = BB.pad:sub(1, -2) end
    elseif #BB.pad < BB.MAX then
        BB.pad = BB.pad .. k
        BB.sayUntil = nil
    end
    BB.Paint()
    return k
end

-- ------------------------------------------------------------------ painting

local function setText(fs, s)
    if fs and fs.__bbt ~= s then fs:SetText(s) fs.__bbt = s end
end
local function hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end

local function clock(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

--- The status words for a state.
function BB.Status(state)
    state = state or BB.State()
    if state == "rec" then return "REC " .. clock(wall() - (db().at or wall())), "red" end
    if state == "wait" then return "WAIT " .. math.max(1, math.ceil((BB.waitUntil or 0) - now())) .. "s", "amber" end
    if state == "safe" then return "SAFE TO RELOAD", "green" end
    return "REC OFF", "dim"
end

function BB.Paint()
    local b = db()
    -- its time ran out without a reload: stop it (the log off if ours)
    if b.on and type(b.untilAt) == "number" and wall() >= b.untilAt then BB.Stop("time") end
    if BB.sayUntil and now() >= BB.sayUntil then BB.sayUntil = nil end
    local r = BB.rail
    if not r then return end
    local state = BB.State()
    if r.lampState ~= state then
        r.lampState = state
        local c = BB.COL[BB.LAMP[state]]
        for _, t in ipairs(r.lamp.discs) do t:SetVertexColor(c[1], c[2], c[3], t.__a) end
    end
    local s, col = BB.Status(state)
    setText(r.status, hex(BB.COL[col]) .. s .. "|r")
    if BB.sayUntil then
        setText(r.screen, hex(BB.COL[BB.saidCol] or BB.COL.red) .. BB.said .. "|r")
    else
        setText(r.screen, hex(BB.COL.lilac) .. "[" .. BB.pad .. "|r" .. hex(BB.COL.dim) .. "_|r" .. hex(BB.COL.lilac) .. "]|r")
    end
    if not (BB.Recording() or BB.sayUntil) then BB.Wake() end
end

-- one tick a second while recording or while a reply shows; nothing at all otherwise
local acc = 0
local function onUpdate(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 1 then return end
    acc = 0
    BB.Paint()
end
BB.OnUpdate = onUpdate

function BB.Wake()
    local r = BB.rail
    if not r then return end
    local need = BB.Recording() or BB.sayUntil ~= nil
    if need == (r.ticking == true) then return end
    r.ticking = need or nil
    acc = 0
    r:SetScript("OnUpdate", need and onUpdate or nil)
end

-- ------------------------------------------------------------------ building

local function disc(parent, px, a, add)
    local t = parent:CreateTexture(nil, add and "ARTWORK" or "OVERLAY")
    t:SetTexture(DISC)
    t:SetSize(px, px)
    t:SetPoint("CENTER", parent, "CENTER", 0, 0)
    if add and t.SetBlendMode then t:SetBlendMode("ADD") end
    t.__a = a
    return t
end

local function text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "")
    if justify and fs.SetJustifyH then fs:SetJustifyH(justify) end
    return fs
end

local function buildKey(parent, label, x, y)
    local w = BB.WIDE[label] or BB.KW
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, BB.KH)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetTexture(NS.RD.WHITE)
    b.bg:SetVertexColor(BB.COL.key[1], BB.COL.key[2], BB.COL.key[3], 1)
    -- the hover wash (every clickable thing pops on hover)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(b)
    b.hl:SetTexture(NS.RD.WHITE)
    b.hl:SetVertexColor(BB.COL.lilac[1], BB.COL.lilac[2], BB.COL.lilac[3], 0.22)
    b.txt = text(b, 9)
    b.txt:SetPoint("CENTER", b, "CENTER", 0, 0)
    local c = (label == "EXEC" and BB.COL.green) or (label == "CLR" and BB.COL.amber) or BB.COL.lilac
    b.txt:SetTextColor(c[1], c[2], c[3], 1)
    b.txt:SetText(label)
    b.label = label
    b:SetScript("OnClick", function() BB.Press(label) end)
    return b, w
end

--- The bottom rail, under the tool rail and the square (Radar.lua's RD.BuildRails hands over its rail maker).
function BB.Build(f, toolRail, makeRail)
    if BB.rail then return BB.rail end
    local RD = NS.RD
    local gap = RD.RAIL_GAP
    local r = makeRail(f)
    r:SetHeight(BB.RAIL_H)
    r:SetPoint("TOPLEFT", toolRail, "BOTTOMLEFT", 0, -gap)
    r:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -gap)
    r:EnableMouse(true)                            -- the rail eats a stray click, never the world behind it
    BB.rail = r
    local L = r:GetFrameLevel()

    -- the lamp: a core and two halos, added light = a soft glow
    local lamp = CreateFrame("Frame", nil, r)
    lamp:SetSize(24, 24)
    lamp:SetPoint("LEFT", r, "LEFT", 4, 0)
    lamp:SetFrameLevel(L + 2)
    lamp.discs = { disc(lamp, 24, 0.14, true), disc(lamp, 14, 0.32, true), disc(lamp, 7, 1) }
    r.lamp = lamp

    -- the keypad, right
    local pad = CreateFrame("Frame", nil, r)
    local padW = BB.KW * 5 + BB.KGAP * 5 + BB.WIDE.CLR
    pad:SetSize(padW, BB.KH * 2 + BB.KGAP)
    pad:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    pad:SetFrameLevel(L + 2)
    r.keys = {}
    for row, keys in ipairs(BB.ROWS) do
        local x = 0
        for _, label in ipairs(keys) do
            local b, w = buildKey(pad, label, x, -(row - 1) * (BB.KH + BB.KGAP))
            r.keys[label] = b
            x = x + w + BB.KGAP
        end
    end
    r.pad = pad

    -- the words, between the lamp and the keypad
    r.label = text(r, 8, "LEFT")
    r.label:SetPoint("TOPLEFT", lamp, "TOPRIGHT", 4, 2)
    r.label:SetTextColor(BB.COL.dim[1], BB.COL.dim[2], BB.COL.dim[3], 1)
    r.label:SetText("BLACK BOX")
    r.status = text(r, 9, "RIGHT")
    r.status:SetPoint("TOPRIGHT", pad, "TOPLEFT", -8, -3)
    local scr = CreateFrame("Frame", nil, r)
    scr:SetHeight(18)
    scr:SetPoint("BOTTOMLEFT", lamp, "BOTTOMRIGHT", 2, -4)
    scr:SetPoint("RIGHT", pad, "LEFT", -6, 0)
    scr:SetFrameLevel(L + 1)
    scr.bg = scr:CreateTexture(nil, "BACKGROUND")
    scr.bg:SetAllPoints(scr)
    scr.bg:SetTexture(RD.WHITE)
    scr.bg:SetVertexColor(BB.COL.screen[1], BB.COL.screen[2], BB.COL.screen[3], 1)
    r.screen = text(scr, 9, "LEFT")
    r.screen:SetPoint("LEFT", scr, "LEFT", 5, 0)
    r.scr = scr

    BB.Paint()
    BB.Wake()
    return r
end

-- ------------------------------------------------------------------ events

function BB.Login()
    local b = db()
    if b.on then
        if not BB.Key() then
            BB.Stop("key gone")
        elseif type(b.untilAt) ~= "number" or wall() >= b.untilAt then
            BB.Stop("time")
        else
            -- back from the reload: the log on again if it fell off
            if not logging() and LoggingCombat then pcall(LoggingCombat, true) end
            if Print then Print("|cffff5d5dblack box: REC|r - combat log on, camera armed") end
        end
    end
    BB.Paint()
    BB.Wake()
end

local ev = CreateFrame("Frame")
BB.events = ev
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then BB.Login() return end
    if event == "PLAYER_REGEN_DISABLED" then
        BB.inFight, BB.waitUntil = true, nil
    else
        BB.inFight = nil
        if BB.Recording() then BB.waitUntil = now() + BB.WAIT end
    end
    BB.Paint()
    BB.Wake()
end)
