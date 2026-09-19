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

function NS.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    else
        print(PREFIX .. tostring(msg))
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
}

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
        for k in pairs(db) do db[k] = nil end
        db.binds       = type(binds) == "table" and binds or nil
        db.minimap     = type(minimap) == "table" and minimap or nil
        db.shown       = shown ~= false
        db.bindsSeeded = seeded and true or nil
        db.dbver       = NS.DBVER
    end
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
    if NS.FM and NS.FM.Toggle then NS.FM.Toggle() end
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

function NS.DO.help()
    Print("the window is /bish, or the button on your minimap. Also:")
    Print("  |cffb980ffshow|r |cffb980ffhide|r  the cells   |cffb980ffcenter|r  put them back")
    Print("  |cffb980ffmouse|r  drag spells onto a mouse    |cffb980ffrescan|r  look at the group again")
    Print("  |cffb980ffscan|r   what this client will tell me")
    Print("  |cffb980ffauras|r  mark every debuff, to prove the markers draw")
    Print("  |cffb980ffminimap|r  hide or show the button")
end

--------------------------------------------------------------------- slash --

-- /bishf is kept as an alias rather than retired: it is what has been typed here for a week, and
-- a command that stops existing teaches nothing at the moment you need it.
SLASH_BISHEALING1 = "/bish"
SLASH_BISHEALING2 = "/bisheals"
SLASH_BISHEALING3 = "/bishf"

SlashCmdList = SlashCmdList or {}
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
local MIRROR = { "binds", "minimap", "shown", "bindsSeeded", "dbver", "savedAt", "saves" }

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
