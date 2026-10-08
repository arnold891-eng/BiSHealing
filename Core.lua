--[[
  BiS Healing :: Core.lua - the saved variables, the words it says, and one slash command.

  THE SECOND ADDON OF THIS NAME. The first was 5,000 lines built around one class and one spell:
  a shaman's Chain Heal, ranked by who was actually taking damage, learned out of the combat log.
  On a client where health is a secret and the combat log never fires, not one line of that can
  run - so on 19 Sep 2026 it was tagged `tbc-final` and taken out, rather than left in to be
  switched off by a flag in twenty places.

  What survived the move is what was written for THIS client and works on any of them:

      Lockdown.lua   does this client hide its numbers?
      Grid.lua       cells that hand the client a number they never read
      Auras.lua      markers the client draws for auras we are not allowed to see
      Mouse.lua      every click meaning, dropped onto a picture of a mouse
      Between.lua    what can be learned between pulls, when the lockdown lifts

  And it is for EVERY healer now, not one. Nothing here knows what class you are: the cells ask
  the client to draw a health bar, the dispel marker asks the client what THIS character can cure,
  and the clicks cast whatever you dropped on them. The only class-shaped thing in the addon is
  the list of spells a fresh install puts on the left and right buttons, and that is a courtesy
  you can drag over in five seconds.
]]
local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"

--- The version, from the TOC - the only place it lives, so a release cannot disagree with itself.
local function metadata(field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON, field)
        if ok and v then return v end
    end
    if GetAddOnMetadata then
        local ok, v = pcall(GetAddOnMetadata, ADDON, field)
        if ok and v then return v end
    end
    return nil
end
NS.VERSION = metadata("Version") or "0.0.0"

local PREFIX = "|cffb980ffBiS Healing|r: "

--- One line in the chat frame, with the addon's name on it.
---
--- IT FORMATS WHEN IT IS GIVEN SOMETHING TO FORMAT. It used to take one argument and silently drop
--- the rest, so `Print("asking: %s", call)` put the literal "%s" on screen - which is exactly what
--- /bish range did for the two days it existed, in front of Arn, while he was trying to find out
--- why nothing was dimming (30 Sep). Seven call sites were printing their own punctuation.
---
--- With no extra arguments the message is passed through untouched, so a line that happens to
--- contain a percent sign is safe. A format that does not match its arguments falls back to the
--- raw message rather than throwing in the chat frame.
function NS.Print(msg, ...)
    local text = tostring(msg)
    if select("#", ...) > 0 then
        local ok, made = pcall(string.format, text, ...)
        if ok then text = made end
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
    else
        print(PREFIX .. text)
    end
end
local Print = NS.Print

------------------------------------------------------------------------ db --

-- What a fresh install believes. Small on purpose: the old addon had thirty toggles because it
-- had thirty opinions, and this one mostly asks the client to draw things.
local DEFAULTS = {
    shown   = true,      -- are the cells up at all
    binds   = nil,       -- mouse binds, seeded per class on first run (Mouse.lua)
    minimap = nil,       -- the button's angle, and whether it is hidden
    -- THE REGULAR GRID BY DEFAULT, the pyramid a choice. Arn, having asked for the pyramid and
    -- then thought about it: "pyramid is a hard pill to swallow we keep it a toggle regular grid
    -- by group or pyramid". A layout nobody asked for is not a default.
    layout  = "columns", -- "columns" (one per raid group) or "pyramid" (tanks on top)
    -- "grid" (a column inside the main grid), "own" (a block of their own), or "off". A boolean
    -- from before 26 Sep still reads: true is "grid", false is "off". Off by default still, since
    -- most healers heal a pet by exception - the three settings are about WHERE, not whether.
    pets    = "off",
    petAt   = "under",   -- where the pet block sits when it has one: under the grid by default
    petPos  = nil,       -- where it was dragged to, from the middle of the screen
    hots    = true,      -- your own heals over time on the cells, with the client's countdown
    between = false,     -- the between-pulls reminders in chat; off since 23 Sep ("put it away")
    clique  = false,     -- hand every click on the cells to Clique instead of our mouse binds
    target  = false,     -- a cell of its own for whoever you have targeted
    tot     = false,     -- and one under it for whoever THEY have targeted
    mana    = false,     -- the other healers' mana, in a block of its own
    manaAt  = "right",   -- where that block sits; "free" once dragged
    manaPos = nil,
    me      = false,     -- a cell for yourself, out of the group, in the same place always
    meAt    = "left",    -- where it sits: left / right / top / under, or "free" once dragged
    mePos   = nil,       -- where it was dragged to, from the middle of the screen
    targetAt = "top",    -- where it sits: top / left / right / under, or "free" once dragged
    targetPos = nil,     -- where it was dragged to, from the middle of the screen
    markers = 10,        -- how big the dispel marker and the heal-over-time icons are, in pixels
    -- THE GOLD RING: on your own cell ("me", 30 Sep) or on whoever you have targeted ("target").
    -- A player's ask, 7 Oct: "a toggle highlight self or highlight target".
    ring    = "me",
    -- how far an out-of-range cell fades: the alpha it is drawn at, 0.2 to 0.9 (same ask)
    dim     = 0.30,      -- fresh installs: 30% (Arn, 7 Oct); a saved 0.45 is kept
    -- the number on a cell's right: "missing" (what they still need after incoming heals, short,
    -- blank at full), "percent", or "off". Replaced `missing = true/false` on 21 Sep.
    text    = "missing",
    color   = "class",   -- the bar: "class" colour, or "health" - red, amber, green as they drop
    scale   = 1,         -- the whole grid, 0.6 to 1.6; 1 is the size it was designed at
    buffQuiet = false,   -- no noise when a watched buff drops; it keeps the chosen id for later
    now     = false,     -- BiS> now: the block of buttons that matter right now, help first
    nowAt   = "under",   -- where it sits: top / left / right / under, or "free" once dragged
    nowPos  = nil,       -- where it was dragged to, from the middle of the screen
}

-- Keys with no useful default, which a migration must still carry: `selfBuffs` is a table (a
-- default table here would be SHARED with the database and mutated by the first /bish buff), and
-- `buffSound` is a file id where nil means ours. Without this list the migration below would set
-- them aside in the attic as if they belonged to another addon - a setting that quietly moves
-- house looks exactly like one that was never saved.
local CARRY = { "selfBuffs", "buffSound", "holds" }

NS.DBVER = 1

--- The saved variables, created on demand and migrated once.
---
--- THE OLD ADDON'S TABLE IS STILL ON DISK: every fight it ever watched, every heal size it
--- learned, thirty feature toggles and a pyramid's window position. None of it means anything
--- now, and leaving it there is not harmless - it is a saved-variables file that grows forever
--- and a reader who cannot tell which keys are live. So the migration keeps the two things this
--- addon owns and drops the rest, ONCE, stamped with a version so it never runs twice.
function NS.DB()
    BiSHealingDB = BiSHealingDB or {}
    local db = BiSHealingDB
    if db.dbver ~= NS.DBVER then
        -- the mouse binds used to live under `forever` while this was two addons in one folder
        local binds = (type(db.forever) == "table" and db.forever.binds) or db.binds
        local minimap = db.minimap
        local shown = db.shown
        -- and the fact that the mouse has already been seeded once. Losing this used to mean the
        -- class defaults were offered again at the next login, so a bind the player had CLEARED
        -- came back - the addon overruling a deliberate act. Mouse.lua refuses to re-seed a mouse
        -- with anything on it now, but throwing the flag away was the cause and it is carried.
        local seeded = db.bindsSeeded or (type(db.forever) == "table" and db.forever.seeded)
        local carried = {}
        for _, k in ipairs(CARRY) do carried[k] = db[k] end

        -- WHAT WE DO NOT RECOGNISE IS MOVED, NEVER DELETED. This line used to be
        --
        --     for k in pairs(db) do db[k] = nil end
        --
        -- and on 20 Sep 2026 it ate 367KB of Arn's TBC history: 4,039 fight records, the whole
        -- point of the addon this one replaced. The TOC claims 20506 as well as 16001, so the
        -- Forever addon loads in the TBC client, found a table whose dbver it did not know, and
        -- emptied it. The addon that wrote those records is a `git checkout tbc-final` away, but
        -- the records themselves were one logout from being gone for good.
        --
        -- A version bump is a promise about the keys THIS addon owns. It is not permission to
        -- throw away somebody else's data that happens to share a table. So anything unknown is
        -- set aside under `attic` - readable, restorable, and out of the way - and the migration
        -- carries what it always carried.
        local attic = {}
        for k, v in pairs(db) do
            if k ~= "binds" and k ~= "minimap" and k ~= "shown" and k ~= "bindsSeeded"
               and k ~= "dbver" and k ~= "forever" and k ~= "attic" and DEFAULTS[k] == nil
               and carried[k] == nil then
                attic[k] = v
            end
        end
        local hadAttic = type(db.attic) == "table" and db.attic or nil
        for k in pairs(db) do db[k] = nil end
        if next(attic) then
            db.attic = attic
        elseif hadAttic then
            db.attic = hadAttic        -- a second migration must not lose the first one's attic
        end
        db.binds       = type(binds) == "table" and binds or nil
        db.minimap     = type(minimap) == "table" and minimap or nil
        db.shown       = shown ~= false
        db.bindsSeeded = seeded and true or nil
        for k, v in pairs(carried) do db[k] = v end
        db.dbver       = NS.DBVER
    end
    -- the old on/off switch for the number, carried into the three-way one and then let go
    if db.missing == false and db.text == nil then db.text = "off" end
    db.missing = nil
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil and v ~= nil then db[k] = v end
    end
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    db.binds   = type(db.binds) == "table" and db.binds or {}
    return db
end
local DB = NS.DB

-------------------------------------------------------------- what it does --

-- Every door into this addon, in one table: the slash command reads it, and so does the minimap
-- menu and the options window. One implementation, three doors, and none of them can drift.
NS.DO = {}

function NS.DO.options()
    if NS.CFG and NS.CFG.Toggle then NS.CFG.Toggle() end
end

function NS.DO.mouse()
    if NS.FM and NS.FM.CliqueOn and NS.FM.CliqueOn() then
        Print("Clique is handling clicks on the cells, so these binds are off - /bish clique to take them back")
    end
    if NS.FM and NS.FM.Toggle then NS.FM.Toggle() end
end

--- Hand every click on the cells to Clique, or take them back. One owner at a time: two addons
--- writing what a click means onto the same frame is a race (FM.ApplyTo). No argument flips it.
function NS.DO.clique(on)
    local d = DB()
    if on == nil then on = not (d.clique == true) end
    d.clique = on and true or false
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, yes = pcall(C_AddOns.IsAddOnLoaded, "Clique")
        loaded = ok and yes and true or false
    end
    local now = NS.FM and NS.FM.Apply and NS.FM.Apply()
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    if d.clique then
        Print("clicks on the cells now belong to Clique"
            .. (loaded and "" or " - it is not loaded, so they do nothing until it is")
            .. ((now == false) and " (after this fight)" or ""))
    else
        Print("BiS Healing's mouse binds are back on the cells" .. ((now == false) and " (after this fight)" or ""))
    end
    return d.clique
end

function NS.DO.show(on)
    local db = DB()
    if on == nil then on = not (db.shown ~= false) end
    db.shown = on and true or false
    if InCombatLockdown and InCombatLockdown() then
        Print("the frames change when the fight ends: the client will not move them now")
        return db.shown
    end
    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
    -- kept in the macro, so hidden stays hidden after a restart (Keep.lua, H=1)
    if NS.FK and NS.FK.Save then NS.FK.Save(db.binds or {}) end
    local vis = 0
    for _, f in ipairs((NS.FG and NS.FG.frames) or {}) do
        if f:IsShown() then vis = vis + 1 end
    end
    Print(("%s -- %d cell(s)"):format(db.shown and "shown" or "hidden", vis))
    return db.shown
end

function NS.DO.rescan()
    if not (NS.FG and NS.FG.Layout) then return end
    local ok, n = NS.FG.Layout()
    Print(ok and ("looked again: %d in the group"):format(n or 0)
             or "not now -- the client will not move frames in combat")
end

function NS.DO.center()
    local a = NS.FG and NS.FG.anchor
    if not a then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("not in combat -- the cells are secure frames and the client will not move them now")
        return
    end
    DB().gridPos = nil              -- forget where it was dragged to, then take the default
    if NS.FG.RestorePos then NS.FG.RestorePos() end
    if NS.FK and NS.FK.Save then NS.FK.Save(DB().binds or {}) end   -- and out of the macro
    Print("back to the middle -- drag the header to put it somewhere else")
end

function NS.DO.scan()
    if NS.FB and NS.FB.Dump then NS.FB.Dump() end
end

function NS.DO.auras()
    if not (NS.FA and NS.FA.Debug) then return end
    local on = NS.FA.Debug(not NS.FA.debug)
    Print(("debug aura marker %s"):format(
        on and "ON -- take any debuff and watch the cells" or "off"))
    if NS.FA.slotRefused then
        Print("the client will not let markers be placed, so none are: |cfff08cb0%s|r", NS.FA.slotRefused)
    end
end

--- Your heals over time on the cells (Renew, Rejuvenation, Regrowth), on or off. No argument flips.
function NS.DO.hots(on)
    local d = DB()
    if on == nil then on = d.hots == false end
    local now = NS.FA and NS.FA.SetHots and NS.FA.SetHots(on)
    d.hots = on and true or false
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    Print((d.hots and "your heals over time shown on the cells" or "heals over time hidden")
        .. ((now == false) and " - after this fight" or ""))
    return d.hots
end

--- WHAT THIS CLIENT SAYS ABOUT YOUR MANA. The header showed "regen ?" for Arn mid-fight, which is
--- the honest answer when no call will say what you regenerate while casting. This prints what
--- each one answered, so the next question is about a number rather than a guess.
function NS.DO.regen()
    local FR = NS.FR
    if not FR then Print("the five second rule is not loaded") return end
    Print(("the five second rule: %s"):format(
        FR.Left() > 0 and ("%.1fs left"):format(FR.Left()) or "not running"))
    for _, src in ipairs(FR.SOURCES or {}) do
        local ok, base, casting = pcall(src.get)
        local pb, pc = NS.Plain(base), NS.Plain(casting)
        Print(("  %-26s %s"):format(src.name,
            not ok and "|cfff08cb0refused|r"
            or (pb == nil and base ~= nil and "|cfff08cb0secret|r")
            or (pb == nil and "nothing")
            or ("%s standing, %s casting"):format(tostring(pb), tostring(pc))))
    end
    local base, casting, from, remembered = FR.Rates()
    if not base then
        Print("  -> none of them will say, and nothing was read earlier: the header shows regen ?")
        return
    end
    local k = FR.known
    local age = (k and GetTime) and (GetTime() - (k.at or 0)) or nil
    Print(("  -> %s: %s%s"):format(from, FR.Text() or "?",
        remembered and (" (remembered%s - your own regen is a secret in a fight)")
            :format(age and (", %ds ago"):format(math.floor(age)) or "") or " (live)"))
end

--- The between-pulls reminders in chat, on or off. Off since 23 Sep: they were written for a TBC
--- shaman and say less than they used to on this client. /bish scan still asks outright.
function NS.DO.between(on)
    local d = DB()
    if on == nil then on = not d.between end
    d.between = on and true or false
    Print(d.between and "between-pulls reminders on - what is missing after each fight"
        or "between-pulls reminders off - /bish scan still asks")
    return d.between
end

--- The buffs the header reminds you about. No argument lists them; a name adds it, the same name
--- again takes it off, and "reset" goes back to your class's one.
--- BiS> NOW: the block of buttons that matter right now (1 Oct 2026, Arn's design).
---
--- Off by default, like every other block. `on`/`off`, or a side to put it on.
function NS.DO.now(arg)
    local d = DB()
    local FG, FN = NS.FG, NS.FN
    if arg and FG and FG.TARGET_SPOTS and FG.TARGET_SPOTS[arg] then
        -- the side you asked for, or the next free one: two blocks never share a side, and this
        -- door was the one that did not know that (1 Oct)
        d.nowAt = (FG.FreeSpot and FG.FreeSpot(arg, NS.FN and NS.FN.NOW_KEYS)) or arg
        d.nowPos = nil
        d.now = true
    elseif arg == "off" then d.now = false
    elseif arg == "on" then d.now = true
    elseif arg == nil then d.now = not d.now
    end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    if FG and FG.Layout then FG.Layout() end
    Print("BiS> now is %s%s", d.now and "|cff4fd0cfon|r" or "|cfff08cb0off|r",
        d.now and (" - " .. tostring(d.nowAt or "under")) or "")
    if d.now and FN then
        local mine = FN.Mine and FN.Mine() or {}
        Print("  buttons: |cffb980ff%s|r", #mine > 0 and table.concat(mine, " ") or "none yet")
        Print("  the help button is painted: |cffb980ff%s|r", tostring(FN.seen or "not yet"))
    end
    return d.now
end

--- A BUFF TO WATCH ON THE GROUP, by name, from your own spellbook (1 Oct 2026).
---
--- `/bish buff` watches something on YOU. This watches something on everyone, and it exists
--- because Between.lua had "Earth Shield" written into it -- a TBC spell, on a 1.60 client, so the
--- check could never once have run. Nothing is hardcoded now: you name a spell you have trained,
--- every rank of it is looked up in your book, and the reminder says only what the client answered.
---
--- `off` stops it. With nothing watched, nothing is said, which is the default.
function NS.DO.watch(name)
    local d = DB()
    if name == "off" or name == "none" then
        d.groupBuff = nil
        if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
        Print("not watching anything on the group")
        return nil
    end
    if name and name ~= "" then
        d.groupBuff = name
        if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    end
    local watch = d.groupBuff
    if not watch then
        Print("nothing watched on the group - |cffb980ff/bish watch <spell>|r, a spell you have trained")
        return nil
    end
    local knows = NS.FB and NS.FB.Knows and NS.FB.Knows(watch)
    Print("watching |cffb980ff%s|r on the group - %s", watch,
        knows and "|cff4fd0cfin your spellbook|r"
        or "|cfff08cb0not in your spellbook, so nothing will be said|r")
    if knows and NS.FB and NS.FB.Watched then
        local roster = (NS.FG and NS.FG.Roster and NS.FG.Roster()) or { "player" }
        local onUnit, unsure = NS.FB.Watched(roster, watch)
        Print("  %s", onUnit and ("up on |cff4fd0cf" .. tostring(onUnit) .. "|r")
            or (unsure and "|cffe5c04athe client would not say|r"
                or ("|cfff08cb0not up on " .. (#roster > 1 and "anyone" or "you") .. "|r")))
        if #roster <= 1 then
            Print("  %s", "|cff968eadyou are on your own, so this is only about you - a buff that"
                .. " only goes on yourself belongs in |r|cffb980ff/bish buff|r")
        end
    end
    return watch
end

function NS.DO.buff(name)
    local FS = NS.FS
    if not FS then return end
    if name == "reset" or name == "default" then
        FS.Reset()
        Print("watching your class's usual: " .. (table.concat(FS.List(), ", ") ~= "" and table.concat(FS.List(), ", ") or "nothing"))
        return FS.List()
    end
    if name and name ~= "" then
        local added, removed = FS.Add(name)
        Print(added and ("watching |cffb980ff%s|r"):format(added)
            or ("no longer watching |cffb980ff%s|r"):format(tostring(removed or name)))
    end
    local list = FS.List()
    Print(#list == 0 and "no self buffs watched - /bish buff Water Shield"
        or ("watching: " .. table.concat(list, ", ")))
    local sounds, why = FS.Sounds()
    Print(sounds and sounds > 0 and ("  a sound when one drops: %d registered"):format(sounds)
        or ("  no sound when one drops (%s)"):format(tostring(why or "nothing to register")))
    local missing = FS.Check()
    if type(missing) == "table" and #missing > 0 then
        Print("  missing now: " .. table.concat(missing, ", "))
    elseif missing then
        Print("  all up")
    else
        Print("  the client will not say while you are in a fight")
    end
    return list
end

--- The sound the client plays when a watched buff leaves you. A number is a file id, "off" is
--- silence, and "on" brings it back - WITH the number the player chose, which is why the switch
--- and the id are two fields rather than one. "default" goes back to the client's own alarm, and
--- "test" plays whatever is set, so a number can be heard before it is kept.
function NS.DO.buffsound(arg)
    local d, FS = DB(), NS.FS
    if not FS then return end
    if arg == "off" or arg == "none" then
        d.buffQuiet = true
    elseif arg == "on" then
        d.buffQuiet = false
    elseif arg == "default" or arg == "reset" then
        d.buffSound, d.buffQuiet = nil, false
    elseif arg == "test" or arg == "hear" then
        local played, why = FS.Play()
        Print(played and ("playing %s"):format(tostring(FS.File()))
            or ("no sound: %s"):format(tostring(why or "nothing to play")))
        return d.buffSound
    elseif arg ~= nil and arg ~= "" then
        d.buffSound = tonumber(arg) or arg
        d.buffQuiet = false
    end
    local n, why = FS.Sounds()
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end      -- it outlives a restart
    if FS.Quiet() then
        Print("no sound when a watched buff drops -- /bish buffsound on")
    else
        Print(n and n > 0 and ("a sound when a watched buff drops: %d spell(s) registered with %s")
            :format(n, tostring(FS.File()))
            or ("could not register a sound: %s"):format(tostring(why or "nothing to register")))
    end
    return d.buffSound
end

--- WHAT THE CLIENT SAYS ABOUT RANGE, and whether the dimming can act on it. The same shape as
--- /bish regen, and for the same reason: "the cells are not dimming" has four possible causes and
--- from the screen they all look identical.
--- DOES ANYTHING STILL TELL US SOMEBODY WAS HIT? (1 Oct 2026.)
---
--- Arn wants the pyramid to learn: whoever takes more HITS - not more damage, just more hits -
--- rises within their band when it rearranges, tanks still on top, the main tank holding the apex.
---
--- THE COMBAT LOG IS NOT THE ROAD. It never fires here, and registering it is a PROTECTED call
--- (Lockdown.lua, and the dialog that named PartyHealingDisplay). It is deliberately NOT registered
--- below: we know that answer, and re-asking it only pops the blocked dialog at Arn.
---
--- But "who got hit" and "how hard" are different questions, and only the second is a number. The
--- old per-unit combat event predates the combat log and carries the first without us reading the
--- second - we would be COUNTING NOTIFICATIONS, never reading a value. So: register the candidates,
--- count what arrives, and let Arn go and get hit.
---
--- Deliberately crude: it counts, it does not interpret. What it is for is answering whether the
--- signal exists at all, before anything is designed around it.
local hits
local function watchHits()
    if hits then return hits end
    hits = { counts = {}, units = {}, refused = {} }
    local okF, f = pcall(CreateFrame, "Frame")
    if not okF or not f then return hits end
    for _, e in ipairs({ "UNIT_COMBAT", "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH" }) do
        local okR = pcall(f.RegisterEvent, f, e)
        if not okR then hits.refused[#hits.refused + 1] = e end
    end
    f:SetScript("OnEvent", function(_, event, unit)
        hits.counts[event] = (hits.counts[event] or 0) + 1
        local u = NS.Plain(unit)
        if type(u) == "string" then
            hits.units[u] = hits.units[u] or {}
            hits.units[u][event] = (hits.units[u][event] or 0) + 1
        end
    end)
    hits.frame = f
    hits.since = (GetTime and GetTime()) or 0
    return hits
end

function NS.DO.hits(arg)
    local h = watchHits()
    if arg == "reset" then
        h.counts, h.units, h.since = {}, {}, (GetTime and GetTime()) or 0
        Print("counting again from now")
        return true
    end
    if #h.refused > 0 then
        Print("refused to register: |cfff08cb0%s|r", table.concat(h.refused, ", "))
    end
    Print("listening for: |cffb980ffUNIT_COMBAT UNIT_HEALTH UNIT_HEALTH_FREQUENT UNIT_MAXHEALTH|r")
    Print("  %s", "|cff968eadnot the combat log: it never fires here and registering it is"
        .. " protected - that question is already answered|r")
    local any = false
    for _, e in ipairs({ "UNIT_COMBAT", "UNIT_HEALTH", "UNIT_HEALTH_FREQUENT", "UNIT_MAXHEALTH" }) do
        local n = h.counts[e]
        if n then any = true end
        Print("  %-22s |cff%s%s|r", e, n and "4fd0cf" or "968ead", n and tostring(n) or "nothing")
    end
    if not any then
        Print("  %s", "|cffe5c04ago and get hit, then run this again|r - nothing has arrived yet")
    else
        local shown = 0
        for u, by in pairs(h.units) do
            if shown < 8 then
                local parts = {}
                for e, n in pairs(by) do parts[#parts + 1] = e:gsub("^UNIT_", "") .. "=" .. n end
                table.sort(parts)
                Print("    %s: %s", u, table.concat(parts, " "))
                shown = shown + 1
            end
        end
    end
    Print("  %s", "|cff968eadUNIT_COMBAT firing per unit is the one that would work - a count of"
        .. " notifications, never a damage number|r")
    return true
end

--- WHO IS FEARED, AND MAY I TELL ANYONE? (1 Oct 2026.)
---
--- Arn's idea: a feared player's addon lights a button, and the shaman in their group gets a
--- Tremor Totem button to click. Three questions decide whether it is one addon or two, and
--- whether it works in the only moment it matters.
---
---   1. Is loss-of-control data PLAIN? Auras go secret in a fight; C_LossOfControl is a different
---      door, and ForeverAuras reaches for it. A secret answer cannot be tested, so there would be
---      nothing to light the button with.
---   2. Does it read for OTHER UNITS? GetActiveLossOfControlDataByUnit exists on this client. If it
---      answers about party members, the shaman's own addon sees the fear and NOBODY ELSE NEEDS THE
---      ADDON - which is a far better feature than the one that was asked for.
---   3. If it is self-only, can we even tell them? This client has InChatMessagingLockdown, so
---      addon messages may be shut exactly when a fight is on. LibBiSComm is already embedded in
---      six BiS addons, so the channel is not the work - permission is.
function NS.DO.control()
    local LC = C_LossOfControl
    if not LC then Print("this client has no C_LossOfControl") return false end
    local names = {}
    for _, n in ipairs({ "GetActiveLossOfControlData", "GetActiveLossOfControlDataCount",
                         "GetActiveLossOfControlDataByUnit", "GetActiveLossOfControlDataCountByUnit",
                         "GetActiveLossOfControlDuration" }) do
        if type(LC[n]) == "function" then names[#names + 1] = n end
    end
    Print("C_LossOfControl: |cffb980ff%s|r", #names > 0 and table.concat(names, ", ") or "none")

    local function say(label, ok, v)
        if not ok then Print("  %s: |cfff08cb0refused|r", label) return end
        if v == nil then Print("  %s: |cff968eadnothing right now|r", label) return end
        if NS.Secret(v) then Print("  %s: |cffe5c04aa secret|r - cannot be tested", label) return end
        if type(v) == "table" then
            local kind = nil
            local okF, got = pcall(function() return v.lossOfControlType or v.locType end)
            if okF then kind = got end
            Print("  %s: |cff4fd0cfplain|r (%s)", label,
                NS.Secret(kind) and "its type is secret" or tostring(kind or "a table"))
            return
        end
        Print("  %s: |cff4fd0cfplain|r (%s)", label, tostring(v))
    end

    if LC.GetActiveLossOfControlDataCount then
        local ok, n = pcall(LC.GetActiveLossOfControlDataCount)
        say("how many things hold me", ok, n)
    end
    if LC.GetActiveLossOfControlData then
        local ok, d = pcall(LC.GetActiveLossOfControlData, 1)
        say("the first one on me", ok, d)
    end

    -- THE ONE THAT DECIDES THE WHOLE SHAPE
    local unit = (UnitExists and UnitExists("target") and "target")
        or (IsInGroup and IsInGroup() and "party1") or "player"
    if LC.GetActiveLossOfControlDataCountByUnit then
        local ok, n = pcall(LC.GetActiveLossOfControlDataCountByUnit, unit)
        say("how many hold " .. unit, ok, n)
    end
    if LC.GetActiveLossOfControlDataByUnit then
        local ok, d = pcall(LC.GetActiveLossOfControlDataByUnit, unit, 1)
        say("the first one on " .. unit, ok, d)
    end

    -- and whether we could tell a shaman, if we had to
    local CI = C_ChatInfo
    if CI then
        local okL, locked = pcall(CI.InChatMessagingLockdown)
        local okR, restricted = pcall(CI.AreOutgoingAddonChatMessagesRestricted)
        Print("  addon messages locked down: |cffb980ff%s|r   restricted: |cffb980ff%s|r",
            okL and tostring(NS.Plain(locked)) or "refused",
            okR and tostring(NS.Plain(restricted)) or "refused")
    end
    Print("  %s", "|cff968eadplain + reads for other units = the shaman alone needs the addon."
        .. " plain but self-only = both of you do, and only if messages get through in a fight.|r")
    return true
end

--- WHAT HAS ACTUALLY HELD ANYBODY SINCE LOGIN (3 Oct 2026).
---
--- `/bish control` is a probe: it answers for the half-second you type it, which is never the
--- half-second somebody is feared. Arn ran it three times in Blackfathom Deeps and got `plain (0)`
--- every time, which is what a probe is for and also exactly why a probe cannot settle this.
---
--- The addon is already watching. Every paint of the Tremor button asks every unit in the group
--- what is holding it, and has been writing the answers down since 0.8.0 - into a table nothing
--- could read. This is the door to it. Play a dungeon, come back, ask.
---
--- The line that matters is the last one. "reads for SOMEBODY ELSE" is the single unproven claim
--- the whole Tremor design rests on, and it cannot be proved by a client that keeps answering nil
--- because nobody happens to be feared.
function NS.DO.holds()
    local FN = NS.FN
    if not FN then Print("the now block is not loaded") return false end
    local seen = FN.seenHolds or {}

    local kinds, other, inFight = {}, false, false
    for kind in pairs(seen) do kinds[#kinds + 1] = kind end
    table.sort(kinds)

    -- WHAT WAS KEPT ACROSS LOGINS (6 Oct 2026): first sightings only, see FN.KeepHold
    local kept = type(DB().holds) == "table" and DB().holds or {}
    local keptKinds, keptOther = {}, nil
    for kind, k in pairs(kept) do
        if type(k) == "table" then
            keptKinds[#keptKinds + 1] = kind
            if k.otherAt and (not keptOther or k.otherAt < keptOther.otherAt) then
                keptOther = { kind = kind, otherAt = k.otherAt, otherUnit = k.otherUnit,
                              otherFight = k.otherFight }
            end
        end
    end
    table.sort(keptKinds)
    local function when(t) return (date and t and date("%d %b %H:%M", t)) or tostring(t) end

    if #keptKinds > 0 then
        Print("kept across logins:")
        for _, kind in ipairs(keptKinds) do
            local k = kept[kind]
            Print("  |cffb980ff%s|r  first %s%s", kind, when(k.firstAt),
                k.otherAt and ("  |cff4fd0cfon somebody else|r: " .. tostring(k.otherUnit) .. ", "
                    .. when(k.otherAt) .. (k.otherFight and " (in a fight)" or ""))
                or "  |cff968eadonly ever on you|r")
        end
    end
    -- Overlord (6 Oct): this beta can still OMIT a saved file at login. Say so rather than show a
    -- record that quietly started again today.
    local L = NS.loaded or {}
    if not L.found or L.savedAt == nil then
        Print("  |cfff08cb0the saved file did not come back this login|r - anything kept above started"
            .. " fresh this session")
    end

    if #kinds == 0 then
        Print("nothing has held anybody since login.")
        Print("  %s", "|cff968eadThe block has to be ON and drawn for this to be watching at all -"
            .. " it is the Tremor button's own paint that asks. |cffb980ff/bish now on|r|r")
        if keptOther then
            Print("  |cff4fd0cfREAD ON SOMEBODY ELSE|r - %s on %s, %s. The shaman alone needs the addon.",
                keptOther.kind, tostring(keptOther.otherUnit), when(keptOther.otherAt))
        end
        return true
    end

    Print("held since login:")
    for _, kind in ipairs(kinds) do
        local rec = seen[kind]
        -- 0.8.0 and 0.8.1 counted with a bare number; a session that started on one of those and
        -- reloaded into this is not worth a crash
        if type(rec) ~= "table" then rec = { n = rec, units = {}, other = false, fight = false } end
        local who = {}
        for unit, n in pairs(rec.units or {}) do
            who[#who + 1] = unit .. (n > 1 and (" x" .. n) or "")
        end
        table.sort(who)
        if rec.other then other = true end
        if rec.fight then inFight = true end
        Print("  |cffb980ff%s|r x%d%s%s", kind, rec.n or 0,
            #who > 0 and ("  on " .. table.concat(who, ", ")) or "",
            rec.fight and "  |cff968ead(in a fight)|r" or "")
    end

    local lit = {}
    for _, b in ipairs(FN.BUTTONS or {}) do
        if FN.earned and FN.earned[b.key] and not b.always then lit[#lit + 1] = b.word or b.key end
    end
    Print("  buttons earned by something that happened: %s",
        #lit > 0 and ("|cff4fd0cf" .. table.concat(lit, ", ") .. "|r") or "|cff968eadnone yet|r")

    Print("  in a fight: |cffb980ff%s|r", tostring(inFight))
    if other then
        Print("  |cff4fd0cfREAD ON SOMEBODY ELSE - the shaman alone needs the addon.|r")
    elseif keptOther then
        Print("  |cff4fd0cfREAD ON SOMEBODY ELSE|r - not this session, but kept: %s on %s, %s.",
            keptOther.kind, tostring(keptOther.otherUnit), when(keptOther.otherAt))
    else
        Print("  |cffe5c04aevery one of these was on YOU.|r %s",
            "|cff968eadLoss of control reading for another unit is still unproven;"
            .. " until it is seen, the Tremor button is a design resting on a maybe.|r")
    end
    return true
end

--- WILL THE CLIENT PICK A BRIGHTNESS FROM A SECRET NUMBER? (1 Oct 2026.)
---
--- The whole of `BiS> now` rests on this one question. Arn's design: a help button at alpha 0
--- while you are healthy, growing more opaque as your health drops, red and glowing at the bottom.
--- Three mappings from one secret number - alpha, tint, glow - and the addon must learn none of
--- them.
---
--- We already know the BOOLEAN half works: `EvaluateColorValueFromBoolean` is what made range
--- dimming real in 0.6.2, and `SetAlpha` accepts what it hands back. What is unmeasured is the
--- NUMBER half: `C_CurveUtil.CreateCurve` and `CreateColorCurve` are both on this client, nothing
--- here has ever called one, and how a curve is fed is not something to guess at - five guessed
--- atlas suffixes in a row this evening is the argument against guessing.
---
--- So: name what is there, build a curve, DUMP ITS METHODS, and then try the two questions that
--- matter - does it evaluate a plain number, and does it evaluate a secret one into something a
--- texture will take.
function NS.DO.curve()
    local CU = C_CurveUtil
    if not CU then Print("this client has no C_CurveUtil") return false end
    local names = {}
    for _, n in ipairs({ "CreateCurve", "CreateColorCurve", "EvaluateColorValueFromBoolean" }) do
        if type(CU[n]) == "function" then names[#names + 1] = n end
    end
    Print("C_CurveUtil: |cffb980ff%s|r", #names > 0 and table.concat(names, ", ") or "no functions")

    local function methodsOf(o)
        local out, seen = {}, {}
        local function take(t)
            if type(t) ~= "table" then return end
            for k, v in pairs(t) do
                if type(k) == "string" and type(v) == "function" and not seen[k] then
                    seen[k] = true
                    out[#out + 1] = k
                end
            end
        end
        take(o)
        local mt = getmetatable(o)
        if type(mt) == "table" then take(mt.__index) take(mt) end
        table.sort(out)
        return out
    end

    for _, maker in ipairs({ "CreateCurve", "CreateColorCurve" }) do
        if type(CU[maker]) == "function" then
            local got, obj = pcall(CU[maker])
            if not got then
                Print("  %s: |cfff08cb0refused with no arguments|r (%s)", maker,
                    tostring(obj):gsub("^.*:%s*", ""))
            else
                local m = methodsOf(obj)
                Print("  %s -> |cffb980ff%s|r", maker, type(obj))
                Print("    methods: %s", #m > 0 and ("|cff4fd0cf" .. table.concat(m, " ") .. "|r")
                    or "|cfff08cb0none visible|r")
            end
        end
    end

    -- AND THE QUESTION UNDER THE QUESTION: a texture will take a number. Will it take the client's
    -- answer about a number nobody may read? That is the whole bargain, and it is the one thing a
    -- dumped method list cannot tell us.
    local okHP, raw = pcall(UnitHealth, "player")
    Print("  your own health reads as: |cffb980ff%s|r",
        not okHP and "refused" or (NS.Secret(raw) and "a secret" or "a plain number"))
    local tex = NS.DO.__curveTex
    if not tex then
        local okF, f = pcall(CreateFrame, "Frame", nil, UIParent)
        if okF and f then
            f:Hide()
            tex = f
            NS.DO.__curveTex = f
        end
    end
    if tex and okHP then
        local okA = pcall(tex.SetAlpha, tex, raw)
        Print("  SetAlpha straight from that value: %s",
            okA and "|cff4fd0cftaken|r - the client did not object" or "|cfff08cb0refused|r")
    end
    Print("  %s", "|cff968eadwhat BiS> now needs: a curve that turns that value into an alpha,"
        .. " evaluated by the client, never read by us|r")
    return true
end

--- CAN THIS ADDON SEND A PING? A measurement, not a feature (1 Oct 2026).
---
--- Arn's idea was an automatic ping when his health drops. The trigger half is already answered -
--- UnitHealth is secret on every unit including your own, so "am I low" is a comparison the client
--- refuses, and nothing can be built on it. The other half is open: can we send a ping AT ALL, from
--- a button the player pressed? `C_Ping.SendMacroPing` is named for the macro door, which usually
--- means it wants a real keypress; whether our secure button counts is not something to guess.
---
--- SO THIS DISCOVERS RATHER THAN ASSUMES. It names what is there, dumps whatever Ping enum the
--- client has instead of hardcoding a type number, and only then tries the call. Twice today a
--- hardcoded fact about this game turned out to be wrong (Earth Shield, Water Shield), and both
--- times the right answer was already available by asking.
---
--- THE BLOCKED DIALOG NAMES THE ADDON AND NOT THE FUNCTION, so "BiSHealing has been blocked" would
--- leave us guessing which line did it. The client fires an event that DOES name it; it is listened
--- for here, the way BiSProbe does, so a refusal is evidence instead of a mystery.
local blocked
local function watchBlocked()
    if blocked then return blocked end
    blocked = {}
    local ok, f = pcall(CreateFrame, "Frame")
    if not ok or not f then return blocked end
    for _, e in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, who, what)
        if who ~= nil and who ~= ADDON then return end      -- somebody else's problem
        blocked.seen = tostring(event) .. " on " .. tostring(what or "?")
    end)
    blocked.frame = f
    return blocked
end

function NS.DO.ping(which)
    local P = C_Ping
    if not P then Print("this client has no C_Ping at all") return false end
    local names = { "IsPingSystemEnabled", "SendMacroPing", "GetDefaultPingOptions",
                    "GetCooldownInfo", "TogglePingListener", "GetTextureKitForType" }
    local have = {}
    for _, n in ipairs(names) do if type(P[n]) == "function" then have[#have + 1] = n end end
    Print("C_Ping: |cffb980ff%s|r", #have > 0 and table.concat(have, ", ") or "no functions")

    local on = select(2, pcall(P.IsPingSystemEnabled))
    Print("  ping system enabled: |cffb980ff%s|r", tostring(NS.Plain(on)))

    -- the ping TYPES, from the client rather than from memory
    local found = {}
    if type(Enum) == "table" then
        for k, v in pairs(Enum) do
            if type(k) == "string" and k:lower():find("ping") and type(v) == "table" then
                local keys = {}
                for name, val in pairs(v) do keys[#keys + 1] = tostring(name) .. "=" .. tostring(val) end
                table.sort(keys)
                found[#found + 1] = k .. ": " .. table.concat(keys, " ")
            end
        end
    end
    if #found == 0 then Print("  %s", "|cff968eadno Ping enum on this client - trying bare numbers|r") end
    for _, line in ipairs(found) do Print("  |cffb980ff%s|r", line) end

    if type(P.GetCooldownInfo) == "function" then
        local okcd, cd = pcall(P.GetCooldownInfo)
        Print("  cooldown info: |cffb980ff%s|r", okcd and type(cd) == "table" and "a table" or tostring(cd))
    end

    -- BLIZZARD'S OWN SLASH DOOR, which is the whole plan now (Arn, 1 Oct): ping types as buttons in
    -- the mouse window, dragged onto a mouse button like a spell, and the cell fires the ping at
    -- whoever is in it. We cannot call SendMacroPing - it is forbidden - but a secure button may
    -- hold a MACRO, and a macro is Blizzard's code. Mouse.lua already does exactly this for the
    -- wheel ("/target [@mouseover]"), so the machinery is there; what is missing is the command.
    local slash, token = nil, nil
    for k in pairs(SlashCmdList or {}) do
        if type(k) == "string" and k:lower():find("ping") then slash = k break end
    end
    for i = 1, 4 do
        local t = _G["SLASH_PING" .. i] or (slash and _G["SLASH_" .. slash .. i])
        if t then token = tostring(t) break end
    end
    -- THE TOKEN IS THE EVIDENCE, NOT THE TABLE. This printed "no /ping in SlashCmdList as /ping"
    -- on 1 Oct - nonsense on its face, and worse, misleading: /ping demonstrably works, because
    -- the ping binds built on it work. A command handled by the client itself need not appear in
    -- SlashCmdList at all, so an empty table there proves nothing and SLASH_PING1 proves plenty.
    Print("  Blizzard's own ping command: %s%s",
        token and ("|cff4fd0cf" .. token .. "|r works") or "|cfff08cb0no SLASH_PING token|r",
        slash and (" (and SlashCmdList." .. slash .. ")") or " (handled by the client, not SlashCmdList)")
    if token or slash then
        Print("  %s", "|cff968eadand the cells use \"" .. (token or "/ping")
            .. " [@mouseover] <type>\" - the condition is what aims it at the cell"
            .. " rather than at the floor|r")
    end

    -- THE ART, so the mouse window can show an icon instead of a word (Arn, 1 Oct). The client has
    -- GetTextureKitForType; what it hands back, and what atlas names are built from it, is not
    -- something to guess at - PingTextureType says the art comes in three pieces (Center, Expand,
    -- Rotation), so each is asked for and C_Texture.GetAtlasInfo says which of them actually exist.
    local kitOf = P.GetTextureKitForType
    local atlasInfo = C_Texture and C_Texture.GetAtlasInfo
    if type(kitOf) == "function" and type(Enum) == "table" and type(Enum.PingSubjectType) == "table" then
        local order = {}
        for name, val in pairs(Enum.PingSubjectType) do order[#order + 1] = { name = name, val = val } end
        table.sort(order, function(a, b) return (tonumber(a.val) or 0) < (tonumber(b.val) or 0) end)
        for _, e in ipairs(order) do
            local gotKit, kit = pcall(kitOf, e.val)
            local line = ("  %s=%s kit: |cffb980ff%s|r"):format(e.name, tostring(e.val),
                gotKit and tostring(kit) or "refused")
            Print("%s", line)
        end

        -- ASK THE CLIENT FOR THE NAMES RATHER THAN INVENTING THEM. The kits come back as bare
        -- words ("Assist", "Attack", "OnMyWay"), so the atlas name is those composed into some
        -- format - and five guessed suffixes all missed. C_Texture.GetAtlasElements lists what
        -- actually exists, which ends the guessing for good (1 Oct 2026).
        local elements = C_Texture and C_Texture.GetAtlasElements
        if type(elements) == "function" then
            local okE, list = pcall(elements)
            local hits = {}
            if okE and type(list) == "table" then
                for k, v in pairs(list) do
                    local nm = (type(k) == "string" and k) or (type(v) == "string" and v) or nil
                    if nm and nm:lower():find("ping") then hits[#hits + 1] = nm end
                end
            end
            table.sort(hits)
            if #hits == 0 then
                Print("  %s", "|cfff08cb0no atlas with 'ping' in its name|r")
            else
                Print("  atlases with 'ping' in the name: |cffb980ff%d|r", #hits)
                for i = 1, math.min(#hits, 24) do Print("    |cff4fd0cf%s|r", hits[i]) end
                if #hits > 24 then Print("    ... and %d more", #hits - 24) end
            end
        elseif atlasInfo then
            Print("  %s", "|cff968eadno GetAtlasElements - cannot list what exists|r")
        end
    end

    if type(P.SendMacroPing) ~= "function" then
        Print("  %s", "|cfff08cb0no SendMacroPing - nothing to try|r")
        return false
    end

    -- THE ATTEMPT. `which` is whatever you want to pass; with nothing given it tries no argument
    -- and then 0..3, stopping at the first that does not throw. Each is guarded, and the blocked
    -- listener is armed first so a protected refusal is caught rather than inferred.
    local watch = watchBlocked()
    watch.seen = nil
    local tried, worked = {}, nil
    local args = { }
    if tonumber(which) then args[#args + 1] = tonumber(which) else
        args[1] = false            -- a marker for "call it with nothing"
        for i = 0, 3 do args[#args + 1] = i end
    end
    for _, a in ipairs(args) do
        local okc, err
        if a == false then okc, err = pcall(P.SendMacroPing) else okc, err = pcall(P.SendMacroPing, a) end
        tried[#tried + 1] = (a == false and "no argument" or tostring(a)) .. ": "
            .. (okc and "|cff4fd0cfno error|r" or ("|cfff08cb0" .. tostring(err):gsub("^.*:%s*", "") .. "|r"))
        if okc and worked == nil then worked = (a == false) and "no argument" or tostring(a) end
    end
    for _, line in ipairs(tried) do Print("  %s", line) end
    Print("  blocked by the client: |cffb980ff%s|r", tostring(watch.seen or "nothing reported"))

    -- A BLOCKED ACTION BEATS "no error", and this line used to let them argue (measured 1 Oct 2026,
    -- Arn's first run). Every type came back "no error" AND the client fired ADDON_ACTION_FORBIDDEN
    -- naming this addon: a forbidden call is refused by the EVENT, not by raising into our pcall.
    -- So a diagnostic that weighs the two equally reports a yes when the answer is no - which is
    -- the same failure as a mock being kinder than the client, in the one tool built to prevent it.
    if watch.seen then
        Print("  %s", "|cfff08cb0VERDICT: forbidden to addon code.|r |cff968eadNo error was raised -"
            .. " the client blocks it by firing that event instead, so 'no error' means nothing"
            .. " here. A secure button running Blizzard's own /ping is the only road left.|r")
        return false
    end
    Print("  %s", "|cff968eadVERDICT: nothing refused it. Now the real question - did a ping actually"
        .. " appear in game? A call that is accepted and silently dropped looks exactly like this.|r")
    return worked
end

--- WHAT WILL THIS CLIENT TELL ME ABOUT SOMEONE ELSE'S AURAS? (1 Oct 2026.)
---
--- Built the same way `/bish range` was, and for the same reason: the dimming was broken for nine
--- days because nobody could see which branch ran. By-id aura lookups have exactly that shape --
--- several roads, each failing silently in its own way -- so the client is asked to say out loud
--- which one answered, on the unit you have selected.
---
--- NOT called `auras`: that is already the debug switch that marks every debuff, and defining a
--- second NS.DO.auras here quietly replaced it -- the whole point of NS.DO being one table is that
--- this kind of collision is possible, so it is worth saying where it nearly happened.
function NS.DO.byid()
    local byID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    Print("asking by spell id: |cffb980ff%s|r",
        byID and "C_UnitAuras.GetUnitAuraBySpellID" or "missing on this client - the walk is all we have")
    Print("  the index walk: %s", (NS.Restricted and NS.Restricted())
        and "|cfff08cb0refused right now|r - this is the case by-id exists for"
        or "|cff4fd0cfanswering|r")
    Print("  auras secret right now: %s", (NS.Blind and NS.Blind())
        and "|cffe5c04ayes|r" or "|cff4fd0cfno|r")

    -- SOMETHING THIS CHARACTER ACTUALLY HAS. This used to ask for Earth Shield's ids, which on a
    -- 1.60 client is a spell that does not exist - so the diagnostic reported "no spell ids" and
    -- looked like a broken client rather than a wrong question (Arn, 1 Oct).
    local unit = (UnitExists and UnitExists("target") and "target") or "player"
    local ids, from = {}, nil
    local function take(name)
        if #ids > 0 or not name then return end
        local got = (NS.FM and NS.FM.Ranks and NS.FM.Ranks(name)) or {}
        for _, r in ipairs(got) do if type(r.spell) == "number" then ids[#ids + 1] = r.spell end end
        if #ids == 0 and NS.FS and NS.FS.SpellIds then
            for _, id in ipairs(NS.FS.SpellIds(name)) do ids[#ids + 1] = id end
        end
        if #ids > 0 then from = name end
    end
    take(DB().groupBuff)                                   -- what /bish watch is set to
    take(((NS.FS and NS.FS.List and NS.FS.List()) or {})[1])   -- else your own watched buff
    if #ids == 0 then
        Print("  %s", "|cff968eadno spell ids to ask with - set |r|cffb980ff/bish watch <spell>|r"
            .. "|cff968ead, or /bish buff|r")
    else
        Print("  asking with |cffb980ff%s|r", tostring(from))
        local a, why = NS.AuraById(unit, ids[1])
        Print("  about %s, id %d: %s", unit, ids[1], a and "|cff4fd0cfread it|r"
            or ("|cffe5c04a" .. tostring(why) .. "|r"))
    end
    Print("  last answer: |cffb980ff%s|r", tostring(NS.auraSeen or "nothing asked yet"))
    Print("  the watched buff asked by: |cffb980ff%s|r",
        tostring((NS.FB and NS.FB.watchBy) or "not yet - run /bish scan"))
    Print("  may I compare unit tokens: %s", NS.CanCompareUnits and NS.CanCompareUnits()
        and "|cff4fd0cfyes|r" or "|cffe5c04ano - UnitIsUnit only|r")
    Print("  unit stats secret: |cffb980ff%s|r", tostring(NS.StatsSecret and NS.StatsSecret()))
    Print("  %s", "|cff968eadread = the client handed it over · none = answered, not on them"
        .. " · hidden = it is hiding auras, so nil proves nothing · secret/refused = it would not"
        .. " say, and we never guess|r")
end

function NS.DO.range()
    local FG = NS.FG
    -- written out, not `NS.FM and NS.FM.RangeSpell()`: an `and` keeps only the first return
    local spell, _, reach
    if NS.FM and NS.FM.RangeSpell then spell, _, reach = NS.FM.RangeSpell() end
    Print("range is measured with |cffb980ff%s|r%s - your longest-reaching heal (a tie keeps your click)",
        tostring(spell or "nothing - no heal bound or trained"),
        (reach and reach > 0) and (" (" .. reach .. " yd)") or "")
    local call = (C_Spell and C_Spell.IsSpellInRange and "C_Spell.IsSpellInRange")
        or (IsSpellInRange and "IsSpellInRange") or "no call on this client"
    Print("  asking: |cffb980ff%s|r", call)
    local unit = (UnitExists and UnitExists("target") and "target") or "player"
    local range = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    if range and spell then
        local ok, answer = pcall(range, spell, unit)
        Print("  about %s: %s", unit, not ok and "|cfff08cb0refused|r"
            or (NS.Secret and NS.Secret(answer) and "|cffe5c04aa secret|r - which is the interesting case"
                or ("|cff4fd0cf" .. tostring(answer) .. "|r")))
    end
    local curve = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    Print("  the client's boolean-to-value call: %s",
        curve and "|cff4fd0cfthere|r" or "|cfff08cb0missing|r")
    Print("  last paint: |cffb980ff%s|r", tostring(FG and FG.rangeSeen or "nothing painted yet"))
    Print("  %s", "|cff968eadplain = read normally · secret = the client chose the dimming for us"
        .. " · alpha refused = it would not take it|r")
end

function NS.DO.minimap()
    if not NS.MM then return end
    local hidden = NS.MM.Hidden()
    NS.MM.SetHidden(not hidden)
    Print(hidden and "minimap button back" or "minimap button hidden -- /bish minimap to undo")
end

--- WHAT THE CLIENT HANDED BACK, and what is in the table now. One command, because "the binds
--- reset every reload" has three possible causes and they are indistinguishable from the outside:
--- the client did not load the file, our writes never reached the table, or something cleared it.
function NS.DO.db()
    local L, db = NS.loaded or {}, DB()
    local now = 0
    for _ in pairs(db.binds or {}) do now = now + 1 end

    if not L.found then
        Print("at load: |cfff08cb0no saved table at all|r - the client did not hand one back")
    elseif L.savedAt == nil then
        Print("at load: a table, but |cfff08cb0no stamp|r - this addon has never written to it, or"
              .. " the write was not kept")
    else
        Print(("at load: a table stamped %s, saved %d time(s) before"):format(
            date and date("%H:%M:%S", L.savedAt) or tostring(L.savedAt), L.saves or 0))
    end
    Print(("  binds at load %d, binds now %d, dbver %s"):format(
        L.binds or 0, now, tostring(db.dbver)))
    Print(("  per-character copy: %s%s"):format(
        L.char and "|cff4fd0cfthere|r" or "empty",
        L.rescued and " - |cff4fd0cfand it is what you are using|r" or ""))
    Print(("  the table this addon writes to %s the saved one"):format(
        rawequal(db, _G.BiSHealingDB) and "IS" or "|cfff08cb0is NOT|r"))
    for _, key in ipairs({ "left", "right", "shift-left" }) do
        local v = NS.FM and NS.FM.Get and NS.FM.Get(key:match("^shift%-") and "shift-" or "",
                                                    key:gsub("^shift%-", ""))
        Print(("  %-11s %s"):format(key, v or "-"))
    end
    Print("reload, then run this again: a stamp that comes back means the file is being read")
end

--- What is actually in the macro, which is the only memory this client has. Prints the body
--- raw, because a bind that is missing from THAT is a different bug from a bind that is in it
--- and not on the mouse - and the two have been confused once already.
function NS.DO.keep()
    local FK = NS.FK
    if not (FK and FK.Ready and FK.Ready()) then
        Print("no macro api on this client - nothing is being kept")
        return
    end
    -- WHICH TAB, said out loud: the shared one in General was the whole 22 Sep bug
    local mine, shared = FK.Find()
    if shared then
        Print(("an old shared |cffb980ff%s|r is in General Macros (slot %d) - no longer used, safe to delete")
            :format(FK.MACRO, shared))
    end
    local idx = mine
    if not idx then
        Print(("no |cffb980ff%s|r in this character's macros yet - bind something and it appears"):format(FK.MACRO))
        return
    end
    local body = GetMacroBody and GetMacroBody(idx) or ""
    Print(("macro |cffb980ff%s|r in this character's macros (slot %d), %d of %d characters:")
        :format(FK.MACRO, idx, #body, FK.LIMIT))
    Print("  " .. tostring(body))
    local back = FK.Decode(body)
    if not back then
        Print("  |cfff08cb0and it does not read back|r - the body is not one of ours")
        return
    end
    local n = 0
    for _, m in ipairs(NS.FM.MODS) do
        for _, sl in ipairs(NS.FM.SLOTS) do
            local key = m.key .. sl.key
            if back[key] then
                n = n + 1
                local live = NS.FM.Get(m.key, sl.key)
                Print(("  %-16s %s%s"):format(key, back[key],
                    live == back[key] and "" or ("  |cfff08cb0on the mouse: " .. tostring(live) .. "|r")))
            end
        end
    end
    Print(("  %d bind(s) kept"):format(n))
end

--- Switch layout. No argument flips between the two, which is what a toggle button wants.
-- THREE LAYOUTS SINCE 23 SEP. A player asked for cells "vertically and horizontally"
-- (paszczyszyn, CurseForge): a group can be a column of names, or a row of them. The pyramid is
-- the third. No argument still walks through them, so the old `/bish layout` keeps working.
local LAYOUTS = { columns = "grid: one column per raid group",
                  rows    = "grid: one row per raid group, names across",
                  pyramid = "pyramid: tanks on top, then damage, healers at the bottom" }
local NEXT_LAYOUT = { columns = "rows", rows = "pyramid", pyramid = "columns" }

function NS.DO.layout(mode)
    local d = DB()
    if mode == "grid" or mode == "cols" then mode = "columns" end
    if mode == "across" or mode == "horizontal" then mode = "rows" end
    if not LAYOUTS[mode or ""] then mode = NEXT_LAYOUT[d.layout or "columns"] or "columns" end
    d.layout = mode
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end     -- it outlives a restart
    if InCombatLockdown and InCombatLockdown() then
        Print(("%s after this fight -- the cells are secure frames and will not move mid-pull")
              :format(LAYOUTS[mode]))
        -- nothing to queue: the grid relayouts on PLAYER_REGEN_ENABLED anyway, and reads
        -- d.layout fresh when it does. (A `NS.FG.pending = true` here once looked like the
        -- mechanism and did nothing at all - the grid's pending flag is a local of its own.)
        return mode
    end
    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
    Print(LAYOUTS[mode])
    return mode
end

--- CAN THE CLIENT DRAW HEALTH TEXT FOR US? Asked before building it, not after.
---
--- Missing health is max minus current, and a percentage is current over max: both are exactly
--- the arithmetic this client refuses on a secret. But it offers the answers itself -
--- UnitHealthMissing, UnitHealthPercent - and formatting that may accept a secret and hand back
--- something paintable. "Exists in the census" is not "works with a secret", though: the combat
--- log looked open right up until registering it was a protected call. So this pushes each one
--- through a REAL FontString and reports two things per call - was the value secret, and did the
--- client let us paint it. Run it out of combat AND in one; only the second answer counts.
function NS.DO.text(unit)
    unit = (unit and unit ~= "") and unit or "target"
    if not (UnitExists and UnitExists(unit)) then
        Print(("no %s to ask about - target someone, or /bish text party1"):format(unit))
        return
    end
    NS.textProbe = NS.textProbe or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local fs = NS.textProbe
    fs:Hide()
    local fighting = InCombatLockdown and InCombatLockdown()
    Print(("health text for |cffb980ff%s|r, %s:"):format(unit,
        fighting and "|cfff08cb0in combat|r" or "out of combat - run it in a fight as well"))
    local function try(name, get)
        local asked, v = pcall(get)
        if not asked then
            Print(("  %-10s |cfff08cb0cannot ask|r  %s"):format(name, tostring(v)))
            return
        end
        -- never tostring(v) here: v may be the very secret being tested
        local secret = NS.Secret(v)
        local painted = pcall(fs.SetText, fs, v)
        Print(("  %-10s %-7s %s"):format(name, secret and "secret" or "plain",
            painted and "|cff4fd0cfpaints|r" or "|cfff08cb0refused|r"))
    end
    local variants = {
        { "missing",   function() return UnitHealthMissing(unit) end },
        { "percent",   function() return UnitHealthPercent(unit) end },
        { "abbrev",    function() return AbbreviateNumbers(UnitHealthMissing(unit)) end },
        { "hide-zero", function() return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit)) end },
        { "absorbs",   function() return UnitGetTotalAbsorbs(unit) end },
        -- WHAT THE CELLS NOW DO (21 Sep), so one screenshot checks them. The two helpers do not
        -- compose (measured 20 Sep); the cells let the label be the test instead - see
        -- FG.PaintText. "cell" is exactly what a cell paints, through the same code.
        { "net",       function() return C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit, true)) end },
        { "pct100",    function() return UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) end },
        { "pct%",      function() return string.format("%.0f%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)) end },
        { "cell",      function()
            NS.textCell = NS.textCell or UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            NS.textCell:Hide()
            NS.FG.PaintText({ htext = NS.textCell, unit = unit })
            return NS.textCell:GetText()
        end },
    }
    for _, v in ipairs(variants) do try(v[1], v[2]) end

    -- AND SHOW THEM. "It paints" says nothing about what it paints - 87, 0.87 or 87% - and a
    -- secret cannot be read back to find out. So each variant is drawn, labelled, on a small
    -- panel, and a person looks at it. One screenshot answers what the chat lines cannot.
    local p = NS.textPanel
    if not p then
        p = CreateFrame("Frame", nil, UIParent)
        p:SetSize(230, 20 * #variants + 30)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        p:SetFrameStrata("DIALOG")
        local bg = p:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.85)
        p.head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        p.head:SetPoint("TOPLEFT", 10, -8)
        p.rows = {}
        for i = 1, #variants do
            local label = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            label:SetPoint("TOPLEFT", 10, -12 - i * 20)
            local val = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            val:SetPoint("TOPLEFT", 110, -10 - i * 20)
            p.rows[i] = { label = label, val = val }
        end
        p:EnableMouse(true)
        p:SetScript("OnMouseDown", function(self) self:Hide() end)   -- click it away
        NS.textPanel = p
    end
    p.head:SetText(("|cffb980ff%s|r  -  click to close"):format(unit))
    for i, v in ipairs(variants) do
        local r = p.rows[i]
        r.label:SetText(v[1])
        local asked, got = pcall(v[2])
        if not (asked and pcall(r.val.SetText, r.val, got)) then
            r.val:SetText("|cfff08cb0refused|r")
        end
    end
    p:Show()
end

--- PETS, THREE WAYS. Arn, 26 Sep: "pets should have 3 setting default is they show up on the main
--- cells, solo cell only pets and off on all cells" - which is paszczyszyn's "separete pet group"
--- request in the shape Arn wants it.
---
---   grid  a column of their own inside the main grid (what "pets on" always meant)
---   own   a block of their own, dragged where you like, nothing but pets in it
---   off   nowhere
---
--- No argument walks the three, so the button in the options window and a bare /bish pets both
--- keep working. `true` and `false` are still understood: any macro written before today has a
--- boolean in it, and a player who types "on" means the grid.
local PET_WORDS = { grid = "grid", main = "grid", on = "grid", [true] = "grid",
                    own = "own", solo = "own", block = "own",
                    off = "off", none = "off", [false] = "off" }
local PET_NEXT = { grid = "own", own = "off", off = "grid" }
local PET_SAID = { grid = "pets in the main cells, in a column of their own",
                   own = "pets in a block of their own - drag its bar to move it",
                   off = "no pets anywhere" }

function NS.DO.pets(how)
    local d = DB()
    local FG = NS.FG
    local was = FG and FG.PetsMode and FG.PetsMode() or "off"
    local want
    if how == nil then
        want = PET_NEXT[was] or "grid"
    else
        want = PET_WORDS[type(how) == "string" and how:lower() or how]
        if not want then
            Print("pets: %s, %s or %s", "|cffb980ffgrid|r", "|cffb980ffown|r", "|cffb980ffoff|r")
            return was
        end
    end
    d.pets = want
    -- the block may need a side of its own, and the grid rebuilds either way: pets leaving the
    -- roster changes every column in it
    if want == "own" and FG and FG.FreeSpot then
        d.petAt = FG.FreeSpot(FG.PetSpot(), FG.PET_KEYS)
    end
    local done = true
    if not (InCombatLockdown and InCombatLockdown()) and FG and FG.Layout then
        done = FG.Layout() and true or false
    else
        done = false
    end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    Print((PET_SAID[want] or want) .. (done and "" or " - after this fight"))
    return want
end

--- A cell for whoever you have targeted, under the grid. A player's request (paszczyszyn, 22 Sep).
--- No argument flips it.
function NS.DO.target(on)
    local d = DB()
    -- "under", "left", "right" or "top" both places it and turns it on; a drag on its own little
    -- header sets "free" and remembers where (FG.TargetHandle)
    if type(on) == "string" then
        local where = on:lower()
        if where == "bottom" or where == "below" then where = "under" end
        if where == "above" then where = "top" end
        if NS.FG and NS.FG.TARGET_SPOTS and NS.FG.TARGET_SPOTS[where] then
            d.targetAt = NS.FG.FreeSpot and NS.FG.FreeSpot(where, NS.FG.TARGET_KEYS) or where
            if where ~= "free" then d.targetPos = nil end
            on = true
        else
            on = nil
        end
    end
    if on == nil then on = not d.target end
    d.target = on and true or false
    if d.target and NS.FG and NS.FG.FreeSpot then
        d.targetAt = NS.FG.FreeSpot(NS.FG.TargetSpot(), NS.FG.TARGET_KEYS)
    end
    local done = true
    if NS.FG and NS.FG.LayoutTarget then done = NS.FG.LayoutTarget() and true or false end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    local where = (NS.FG and NS.FG.TargetSpot and NS.FG.TargetSpot()) or "under"
    local said = { under = "under the grid", right = "to the right of the grid",
                   left = "to the left of the grid", top = "above the grid",
                   free = "where you dragged it" }
    Print((d.target and ("a cell for your target, " .. (said[where] or "under the grid"))
        or "no target cell") .. (done and "" or " - after this fight"))
    return d.target
end

--- AND WHOEVER THEY ARE TARGETING, under that one. Arn, 23 Sep: "another option that frame will
--- also have target of target with its on header on top BiS>tot the frames are attached to each
--- other". It hangs off the target cell, so asking for it turns that one on as well - a target of
--- no target is nothing, and a switch that silently does nothing is worse than one that says so.
function NS.DO.tot(on)
    local d = DB()
    if on == nil then on = not d.tot end
    d.tot = on and true or false
    local grew = false
    if d.tot and not d.target then
        d.target = true
        grew = true
    end
    local done = true
    if NS.FG and NS.FG.LayoutTarget then done = NS.FG.LayoutTarget() and true or false end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    Print((d.tot and ("a cell for your target's target, under the target's"
            .. (grew and " - which is on now too" or ""))
        or "no target-of-target cell") .. (done and "" or " - after this fight"))
    return d.tot
end

--- THE OTHER HEALERS' MANA. Arn, 28 Sep, with a screenshot of EllesmereUI's party frames: "the
--- top thing is the healer mana". This addon had written that off as impossible - and it was
--- right about reading the number and wrong about showing it, which is the mistake the whole
--- thing was built to avoid. The client works out the percentage; nothing here ever learns it.
function NS.DO.mana(on)
    local d = DB()
    if type(on) == "string" then
        local where = on:lower()
        if where == "bottom" or where == "below" then where = "under" end
        if where == "above" then where = "top" end
        if NS.FG and NS.FG.TARGET_SPOTS and NS.FG.TARGET_SPOTS[where] then
            d.manaAt = NS.FG.FreeSpot and NS.FG.FreeSpot(where, NS.FG.MANA_KEYS) or where
            if where ~= "free" then d.manaPos = nil end
            on = true
        else
            on = nil
        end
    end
    if on == nil then on = not d.mana end
    d.mana = on and true or false
    if d.mana and NS.FG and NS.FG.FreeSpot then
        d.manaAt = NS.FG.FreeSpot(NS.FG.ManaSpot(), NS.FG.MANA_KEYS)
    end
    local done = true
    if NS.FG and NS.FG.LayoutMana then done = NS.FG.LayoutMana() and true or false end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    local n = (NS.FG and NS.FG.Healers and #NS.FG.Healers()) or 0
    Print((d.mana and ("the healers' mana, %d in the group right now"):format(n)
        or "no mana block") .. (done and "" or " - after this fight"))
    return d.mana
end

--- A CELL FOR YOURSELF, OUT OF THE GROUP. A player's request (paszczyszyn, 25 Sep 2026): "lock
--- yourself in one spot outside groups just to get use to it and have it in same spot for solo/or
--- raid groups". Switching it on takes you out of the grid, which is the whole point: a spot that
--- moves when the group changes is not a spot you can learn.
function NS.DO.me(on)
    local d = DB()
    if type(on) == "string" then
        local where = on:lower()
        if where == "bottom" or where == "below" then where = "under" end
        if where == "above" then where = "top" end
        if NS.FG and NS.FG.TARGET_SPOTS and NS.FG.TARGET_SPOTS[where] then
            d.meAt = NS.FG.FreeSpot and NS.FG.FreeSpot(where, NS.FG.SELF_KEYS) or where
            if where ~= "free" then d.mePos = nil end
            on = true
        else
            on = nil
        end
    end
    if on == nil then on = not d.me end
    d.me = on and true or false
    -- ARRIVING ON AN OCCUPIED SIDE MOVES YOU ALONG. Arn, 26 Sep, with both bars printed across
    -- each other - "BiS> meget": "if target is already taking up the top and i also turn on me
    -- dont overlap them send them to the next available slot". The block that has just been
    -- switched on is the one that moves; whatever was already there keeps its place.
    if d.me and NS.FG and NS.FG.FreeSpot then
        d.meAt = NS.FG.FreeSpot(NS.FG.SelfSpot(), NS.FG.SELF_KEYS)
    end
    -- the whole grid is rebuilt, not just the cell: you leaving the roster changes every column
    local done = true
    if NS.FG and NS.FG.Layout then done = NS.FG.Layout() and true or false end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    local where = (NS.FG and NS.FG.SelfSpot and NS.FG.SelfSpot()) or "left"
    local said = { under = "under the grid", right = "to the right of the grid",
                   left = "to the left of the grid", top = "above the grid",
                   free = "where you dragged it" }
    Print((d.me and ("a cell of your own, " .. (said[where] or "beside the grid")
            .. " - and you are out of the group grid")
        or "no cell of your own - you are back in the group grid")
        .. (done and "" or " - after this fight"))
    return d.me
end

--- How big the dispel marker and the heal-over-time icons are. A player's request (paszczyszyn):
--- "Is there a possibility of an option to adjust the size of buffs and debuffs?".
function NS.DO.markers(px)
    local d = DB()
    local n = tonumber(px)
    if not n then
        Print(("markers are %d pixels - /bish markers 14 (6 to 20)"):format(d.markers or 10))
        return d.markers or 10
    end
    n = math.floor(n + 0.5)
    if n < 6 then n = 6 elseif n > 20 then n = 20 end
    d.markers = n
    if NS.FA then NS.FA.sig = nil end                   -- the containers are rebuilt at the size
    local done = true
    if not (InCombatLockdown and InCombatLockdown()) and NS.FG and NS.FG.Layout then
        NS.FG.Layout()
    else
        done = false
    end
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
    Print(("markers %d pixels%s"):format(n, done and "" or " - after this fight"))
    return n
end

--- Repaint every cell now, rather than waiting for somebody's health to change.
local function repaint()
    if NS.FG and NS.FG.frames and NS.FG.Paint then
        for _, f in ipairs(NS.FG.frames) do if f.unit then pcall(NS.FG.Paint, f) end end
    end
end

--- And write it down, in the macro with the binds: a saved variable does not survive a restart on
--- this client (Keep.lua). The client will not touch a macro in combat; then it waits, and goes in
--- with the next thing that is saved.
local function remember()
    local d = DB()
    if NS.FK and NS.FK.Save then
        local done, why = NS.FK.Save(d.binds or {})
        if not done and why == "combat" then Print("saved for this session - it goes in the macro after the fight") end
    end
end

local TEXT_SAY = {
    missing = "cells show what is missing, after incoming heals",
    percent = "cells show health as a percentage",
    off     = "no number on the cells",
}
local TEXT_NEXT = { missing = "percent", percent = "off", off = "missing" }

--- The number on the cells: "missing", "percent" or "off". No argument moves to the next one.
function NS.DO.number(mode)
    local d = DB()
    local now = (NS.FG and NS.FG.TextMode and NS.FG.TextMode()) or d.text or "missing"
    if mode == "%" or mode == "pct" then mode = "percent" end
    if not TEXT_SAY[mode or ""] then mode = TEXT_NEXT[now] or "missing" end
    d.text = mode
    repaint()
    remember()
    Print(TEXT_SAY[mode])
    return mode
end

--- The old switch, still typed: /bish missing turns the number off, or back to missing health.
function NS.DO.missing(on)
    local d = DB()
    if on == nil then on = d.text == "off" end
    return NS.DO.number(on and "missing" or "off")
end

--- The bars: class colour, or by health. No argument flips it.
function NS.DO.colour(byHealth)
    local d = DB()
    if byHealth == nil then byHealth = d.color ~= "health" end
    d.color = byHealth and "health" or "class"
    repaint()
    remember()
    Print(byHealth and "bars coloured by health - red, amber, green" or "bars in class colours")
    return d.color
end

--- /bish ring me | target - which cell wears the gold ring. No argument flips it.
function NS.DO.ring(how)
    local d = DB()
    if how ~= "me" and how ~= "target" then how = (d.ring == "target") and "me" or "target" end
    d.ring = how
    repaint()
    remember()
    Print(how == "target" and "the gold ring is on your target" or "the gold ring is on your own cell")
    return d.ring
end

--- /bish hover [on|off] - the white crosshair on whoever your mouse is on (7 Oct 2026, Arn's
--- cousin's idea). On by default.
function NS.DO.hover(how)
    local d = DB()
    local on
    if how == "on" or how == true then on = true
    elseif how == "off" or how == false then on = false
    else on = d.hover == false end
    -- on is the default and stores nothing. Not `on and nil or false`: `x and nil` is always nil,
    -- so that line stored "off" for both (the suite caught it, 7 Oct - landmine #8 again)
    if on then d.hover = nil else d.hover = false end
    if NS.FG and NS.FG.HoverAll then NS.FG.HoverAll() end
    remember()
    Print(on and "the white crosshair follows your mouse" or "no crosshair for your mouse")
    return on
end

--- /bish dim 40 - how bright an out-of-range cell stays, as a percentage, 20 to 90.
function NS.DO.dim(pct)
    local d = DB()
    local n = tonumber(pct)
    if not n then
        Print(("out of range cells are drawn at %d%% - /bish dim 20 to 90"):format(
            math.floor((d.dim or 0.30) * 100 + 0.5)))
        return d.dim or 0.30
    end
    if n > 1 then n = n / 100 end                       -- 40 and 0.4 both mean 40%
    if n < 0.2 then n = 0.2 elseif n > 0.9 then n = 0.9 end
    d.dim = math.floor(n * 100 + 0.5) / 100
    repaint()
    remember()
    Print(("out of range cells are drawn at %d%%"):format(math.floor(d.dim * 100 + 0.5)))
    return d.dim
end

--- /bish scale 90 - a percentage, because nobody thinks of a frame as being 0.9 big.
function NS.DO.scale(pct)
    local n = tonumber(pct)
    if not n then
        local d = DB()
        Print(("the grid is at %d%% - /bish scale 60 to 160"):format(math.floor((d.scale or 1) * 100 + 0.5)))
        return d.scale or 1
    end
    local applied, s = NS.FG.SetScale(n / 100)
    Print(("grid scale %d%%%s"):format(math.floor(s * 100 + 0.5),
        applied and "" or " - after this fight, the cells will not resize mid-pull"))
    return s
end

function NS.DO.help()
    Print("the window is /bish, or the button on your minimap. Also:")
    Print("  |cffb980ffshow|r |cffb980ffhide|r  the cells   |cffb980ffcenter|r  put them back")
    Print("  |cffb980ffmouse|r  drag spells onto a mouse    |cffb980ffrescan|r  look at the group again")
    Print("  |cffb980ffscan|r   what this client will tell me")
    Print("  |cffb980ffbyid|r   what it will tell me about someone else's auras")
    Print("  |cffb980ffping|r   can this addon send a ping at all (a measurement)")
    Print("  |cffb980ffcurve|r  will the client pick a brightness from a secret (a measurement)")
    Print("  |cffb980ffcontrol|r  who is feared, and may I tell anyone (a measurement)")
    Print("  |cffb980ffholds|r  what has actually held anybody since login")
    Print("  |cffb980ffhits|r   does anything still say somebody was hit (a measurement)")
    Print("  |cffb980ffnow|r    BiS> now - the buttons that matter right now")
    Print("  |cffb980ffwatch|r  a buff to watch on the GROUP - |cffb980ffwatch off|r to stop")
    Print("  |cffb980ffauras|r  mark every debuff, to prove the markers draw")
    Print("  |cffb980ffminimap|r  hide or show the button")
    Print("  |cffb980ffmissing|r |cffb980ffpercent|r |cffb980ffnumber off|r  the number on the cells")
    Print("  |cffb980ffcolour|r  bars by class, or by health")
    Print("  |cffb980ffhots|r  your heals over time on the cells, on or off")
    Print("  |cffb980ffring|r  the gold ring on |cffb980ffring me|r or on |cffb980ffring target|r")
    Print("  |cffb980ffdim|r  how bright an out of range cell stays - |cffb980ffdim 40|r (20 to 90)")
    Print("  |cffb980ffclique|r  let Clique handle clicks on the cells, or take them back")
    Print("  |cffb980fftarget|r  a cell for your current target - |cffb980fftarget left|r |cffb980ffright|r"
        .. " |cffb980fftop|r |cffb980ffunder|r, or drag its header")
    Print("  |cffb980fftot|r  and one for your target's target, beside it")
    Print("  |cffb980ffmana|r  the other healers' mana, in a block of its own")
    Print("  |cffb980ffme|r  a cell for yourself, out of the group - |cffb980ffme left|r"
        .. " |cffb980ffright|r |cffb980fftop|r |cffb980ffunder|r, or drag its header")
    Print("  |cffb980ffmarkers 12|r  how big the dispel and heal-over-time markers are")
    Print("  |cffb980ffbuff Water Shield|r  a buff on yourself the header reminds you about")
    Print("  |cffb980ffbuffsound|r  the noise when one drops - a sound id, |cffb980ffoff|r,"
        .. " |cffb980ffon|r, |cffb980ffdefault|r, |cffb980fftest|r")
end

--------------------------------------------------------------------- slash --

-- /bishf is kept as an alias rather than retired: it is what has been typed here for a week, and
-- a command that stops existing teaches nothing at the moment you need it.
SLASH_BISHEALING1 = "/bish"
SLASH_BISHEALING2 = "/bisheals"
SLASH_BISHEALING3 = "/bishf"

-- NEVER `SlashCmdList = SlashCmdList or {}`. Writing a Blizzard global - even writing back the
-- value it already had - marks it as ours, and the chat box reads this table to run EVERY slash
-- command. From then on each one ran as BiSHealing's, and the first protected one was refused and
-- blamed on us: Arn typed /pvp on 21 Sep and got "AddOn 'BiSHealing' tried to call the protected
-- function 'TogglePVP()'". Only a client with no table at all (the test harness) gets one made.
if not SlashCmdList then SlashCmdList = {} end
SlashCmdList.BISHEALING = function(input)
    local msg = tostring(input or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "config" or msg == "options" or msg == "settings" then
        NS.DO.options()
    elseif msg == "show" then
        NS.DO.show(true)
    elseif msg == "hide" then
        NS.DO.show(false)
    elseif msg == "mouse" or msg == "binds" then
        NS.DO.mouse()
    elseif msg == "center" or msg == "centre" then
        NS.DO.center()
    elseif msg == "rescan" then
        NS.DO.rescan()
    elseif msg == "scan" or msg == "see" then
        NS.DO.scan()
    elseif msg == "auras" then
        NS.DO.auras()
    elseif msg == "minimap" then
        NS.DO.minimap()
    elseif msg == "db" or msg == "saved" then
        NS.DO.db()
    elseif msg == "keep" or msg == "macro" then
        NS.DO.keep()
    elseif msg == "scale" or msg:match("^scale%s") then
        NS.DO.scale(msg:match("^scale%s+(%d+)"))
    elseif msg == "missing" or msg == "deficit" then
        NS.DO.number("missing")
    elseif msg == "percent" or msg == "%" then
        NS.DO.number("percent")
    elseif msg == "number" or msg:match("^number%s") then
        NS.DO.number(msg:match("^number%s+(%S+)"))
    elseif msg == "colour" or msg == "color" then
        NS.DO.colour()
    elseif msg == "pets" or msg == "pet" then
        NS.DO.pets()
    elseif msg:match("^pets?%s+%a+$") then
        NS.DO.pets(msg:match("^pets?%s+(%a+)$"))
    elseif msg == "target" or msg == "targetcell" then
        NS.DO.target()
    elseif msg:match("^target%s+%a+$") then
        NS.DO.target(msg:match("^target%s+(%a+)$"))
    elseif msg == "tot" or msg == "targetoftarget" or msg == "totcell" then
        NS.DO.tot()
    elseif msg == "me" or msg == "self" then
        NS.DO.me()
    elseif msg == "mana" then
        NS.DO.mana()
    elseif msg:match("^mana%s+%a+$") then
        NS.DO.mana(msg:match("^mana%s+(%a+)$"))
    elseif msg:match("^me%s+%a+$") or msg:match("^self%s+%a+$") then
        NS.DO.me(msg:match("^%a+%s+(%a+)$"))
    elseif msg == "regen" or msg == "fsr" then
        NS.DO.regen()
    elseif msg == "range" then
        NS.DO.range()
    elseif msg == "byid" then
        NS.DO.byid()
    elseif msg == "curve" then
        NS.DO.curve()
    elseif msg == "control" or msg == "fear" then
        NS.DO.control()
    elseif msg == "holds" then
        NS.DO.holds()
    elseif msg == "now" then
        NS.DO.now()
    elseif msg:match("^now%s+%a+$") then
        NS.DO.now(msg:match("^now%s+(%a+)$"))
    elseif msg == "hits" then
        NS.DO.hits()
    elseif msg == "hits reset" then
        NS.DO.hits("reset")
    elseif msg == "ping" then
        NS.DO.ping()
    elseif msg:match("^ping%s+%d+$") then
        NS.DO.ping(tonumber(msg:match("^ping%s+(%d+)$")))
    elseif msg == "watch" then
        NS.DO.watch()
    elseif msg:match("^watch%s") then
        -- the name as typed, capitals and all, the same way /bish buff takes one
        NS.DO.watch((input or ""):match("^%s*[Ww][Aa][Tt][Cc][Hh]%s+(.-)%s*$"))
    elseif msg == "between" or msg == "reminders" then
        NS.DO.between()
    elseif msg == "buffsound" or msg:match("^buffsound%s") then
        NS.DO.buffsound(msg:match("^buffsound%s+(%S+)"))
    elseif msg == "buff" or msg == "buffs" then
        NS.DO.buff()
    elseif msg:match("^buffs?%s") then
        -- the name as the player typed it, capitals and all: "water shield" is not a spell name
        NS.DO.buff((input or ""):match("^%s*[Bb][Uu][Ff][Ff][Ss]?%s+(.-)%s*$"))
    elseif msg == "markers" or msg:match("^markers%s") then
        NS.DO.markers(msg:match("^markers%s+(%d+)"))
    elseif msg == "hots" or msg == "hot" then
        NS.DO.hots()
    elseif msg == "ring" or msg:match("^ring%s") then
        NS.DO.ring(msg:match("^ring%s+(%S+)"))
    elseif msg == "hover" or msg:match("^hover%s") then
        NS.DO.hover(msg:match("^hover%s+(%a+)"))
    elseif msg == "dim" or msg:match("^dim%s") then
        NS.DO.dim(msg:match("^dim%s+([%d%.]+)"))
    elseif msg == "clique" then
        NS.DO.clique()
    elseif msg == "text" or msg:match("^text%s") then
        NS.DO.text(msg:match("^text%s+(%S+)"))
    elseif msg == "layout" or msg == "pyramid" or msg == "grid" or msg == "columns"
        or msg == "rows" or msg == "across" or msg:match("^layout%s") then
        local want = msg:match("^layout%s+(%a+)")
        if msg ~= "layout" and msg ~= "" and not msg:match("^layout%s") then want = msg end
        NS.DO.layout(want)
    else
        NS.DO.help()
    end
end

---------------------------------------------------------------------- boot --

-- WAS THE SAVED FILE READ BACK? (19 Sep 2026)
--
-- Arn: "the bis healing is not surviving reload the key binds reset every reload", and the file on
-- disk says `binds = {}` - not even the class defaults. Two very different faults look identical
-- from the outside: our writes never reach the table, or the client never hands the table back.
--
-- So the addon stamps the db on the way out and reports, at the next login, whether the stamp came
-- back. `/bish db` prints it. No stamp after a reload means the CLIENT did not load the saved
-- variables, and no amount of fixing this addon would change that - which is worth knowing before
-- spending an evening on it.
NS.loaded = { found = false }

-- THE SECOND COPY. 19 Sep 2026, measured in game: this beta client WRITES `BiSHealingDB` perfectly
-- (the file on disk is valid Lua and holds the logout stamp) and then hands back nothing at the
-- next login - "no saved table at all", every time. BugGrabber's session counter is stuck at 1 and
-- BiSMemories' log empties the same way, so it is the client, not us. The TBC client on the same
-- disk carries a db that has been migrated six times, so it is this client only.
--
-- A second channel costs nothing and might work: `## SavedVariablesPerCharacter` is a different
-- file in a different folder, and a client that has lost one may still have the other. We write
-- both and, at login, take whichever came back.
--
-- These are SEPARATE TABLES, never aliases: two globals pointing at one table is one file saved
-- and one lost, which would look exactly like the bug we are working around.
local MIRROR = { "binds", "minimap", "shown", "bindsSeeded", "dbver", "savedAt", "saves", "holds" }

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

local function anything(t)
    return type(t) == "table" and next(t) ~= nil
end

--- Put what matters into the per-character table, on the way out.
local function mirrorOut()
    BiSHealingCharDB = type(BiSHealingCharDB) == "table" and BiSHealingCharDB or {}
    local src = BiSHealingDB
    if type(src) ~= "table" then return end
    for _, k in ipairs(MIRROR) do BiSHealingCharDB[k] = copy(src[k]) end
end

--- Take it back at login, but ONLY when the account-wide table came back empty and the
--- per-character one did not. A client that keeps both will never reach this.
local function mirrorIn()
    local acct, char = BiSHealingDB, BiSHealingCharDB
    if anything(acct) and anything(acct.binds) then return false end
    if not (anything(char) and anything(char.binds)) then return false end
    BiSHealingDB = type(acct) == "table" and acct or {}
    for _, k in ipairs(MIRROR) do BiSHealingDB[k] = copy(char[k]) end
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        -- READ IT RAW, before DB() has a chance to create or migrate anything
        local raw = _G.BiSHealingDB
        local binds, n = type(raw) == "table" and raw.binds, 0
        if type(binds) == "table" then for _ in pairs(binds) do n = n + 1 end end
        local rescued = mirrorIn()          -- the per-character copy, if that is all there is
        NS.loaded = {
            found   = type(raw) == "table",
            savedAt = type(raw) == "table" and tonumber(raw.savedAt) or nil,
            saves   = type(raw) == "table" and tonumber(raw.saves) or nil,
            binds   = n,
            dbver   = type(raw) == "table" and raw.dbver or nil,
            char    = anything(_G.BiSHealingCharDB) and true or false,
            rescued = rescued,
        }
        return
    end

    if event == "PLAYER_LOGOUT" then
        local db = DB()
        db.savedAt = (time and time()) or 0
        db.saves = (tonumber(db.saves) or 0) + 1
        mirrorOut()
        return
    end

    DB()
    if NS.FG and NS.FG.Start then NS.FG.Start() end
    Print(("%s -- /bish, or the button on your minimap"):format(NS.VERSION))
    if not NS.loaded.found or NS.loaded.savedAt == nil then
        -- said once, at login, because it explains every other odd thing that follows
        Print("|cfff08cb0this client did not hand back a saved file|r - binds and settings will not"
              .. " survive a reload. |cffb980ff/bish db|r for what was seen.")
    end
end)
NS.events = ev
