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
        for k in pairs(db) do db[k] = nil end
        db.binds   = type(binds) == "table" and binds or nil
        db.minimap = type(minimap) == "table" and minimap or nil
        db.shown   = shown ~= false
        db.dbver   = NS.DBVER
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
        Print("not in combat -- the anchor is a secure frame")
        return
    end
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", -260, -120)
    Print("back to the middle")
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
    else
        NS.DO.help()
    end
end

---------------------------------------------------------------------- boot --

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    DB()
    if NS.FG and NS.FG.Start then NS.FG.Start() end
    Print(("%s -- /bish, or the button on your minimap"):format(NS.VERSION))
end)
NS.events = ev
