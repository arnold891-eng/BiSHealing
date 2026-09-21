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
    -- THE REGULAR GRID BY DEFAULT, the pyramid a choice. Arn, having asked for the pyramid and
    -- then thought about it: "pyramid is a hard pill to swallow we keep it a toggle regular grid
    -- by group or pyramid". A layout nobody asked for is not a default.
    layout  = "columns", -- "columns" (one per raid group) or "pyramid" (tanks on top)
    pets    = false,     -- hunter and warlock pets as cells of their own (Arn: "toggel to see pets")
    missing = true,      -- the health a cell is missing, on its right; blank at full health
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
               and k ~= "dbver" and k ~= "forever" and k ~= "attic" and DEFAULTS[k] == nil then
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

--- What is actually in the macro, which is the only memory this client has. Prints the body
--- raw, because a bind that is missing from THAT is a different bug from a bind that is in it
--- and not on the mouse - and the two have been confused once already.
function NS.DO.keep()
    local FK = NS.FK
    if not (FK and FK.Ready and FK.Ready()) then
        Print("no macro api on this client - nothing is being kept")
        return
    end
    local idx = GetMacroIndexByName and GetMacroIndexByName(FK.MACRO) or 0
    if not idx or idx <= 0 then
        Print(("no macro called |cffb980ff%s|r yet - bind something and it appears"):format(FK.MACRO))
        return
    end
    local body = GetMacroBody and GetMacroBody(idx) or ""
    Print(("macro |cffb980ff%s|r at slot %d, %d of %d characters:"):format(FK.MACRO, idx, #body, FK.LIMIT))
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
function NS.DO.layout(mode)
    local d = DB()
    if mode ~= "pyramid" and mode ~= "columns" then
        mode = (d.layout == "pyramid") and "columns" or "pyramid"
    end
    d.layout = mode
    if InCombatLockdown and InCombatLockdown() then
        Print(("%s after this fight -- the cells are secure frames and will not move mid-pull")
              :format(mode == "pyramid" and "pyramid" or "grid by group"))
        -- nothing to queue: the grid relayouts on PLAYER_REGEN_ENABLED anyway, and reads
        -- d.layout fresh when it does. (A `NS.FG.pending = true` here once looked like the
        -- mechanism and did nothing at all - the grid's pending flag is a local of its own.)
        return mode
    end
    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
    Print(mode == "pyramid" and "pyramid: tanks on top, then healers, then damage"
          or "grid: one column per raid group")
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
        -- THE ONE WE ACTUALLY WANT is both: abbreviated AND blank at full health. Each helper was
        -- tried alone; which order they compose in is a separate question, so both are asked.
        { "abbr>hide", function() return C_StringUtil.TruncateWhenZero(AbbreviateNumbers(UnitHealthMissing(unit))) end },
        { "hide>abbr", function() return AbbreviateNumbers(C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit))) end },
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

--- Pets on or off. No argument flips it, which is what a toggle wants.
function NS.DO.pets(on)
    local d = DB()
    if on == nil then on = not d.pets end
    d.pets = on and true or false
    if not (InCombatLockdown and InCombatLockdown()) and NS.FG and NS.FG.Layout then NS.FG.Layout() end
    Print(d.pets and "pets shown - in a column of their own" or "pets hidden")
    return d.pets
end

--- The missing-health number on the cells, on or off. No argument flips it.
function NS.DO.missing(on)
    local d = DB()
    if on == nil then on = d.missing == false end
    d.missing = on and true or false
    if NS.FG and NS.FG.frames then
        for _, f in ipairs(NS.FG.frames) do if NS.FG.PaintMissing then NS.FG.PaintMissing(f) end end
    end
    Print(d.missing and "missing health shown on the cells" or "missing health hidden")
    return d.missing
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
    elseif msg == "keep" or msg == "macro" then
        NS.DO.keep()
    elseif msg == "missing" or msg == "deficit" then
        NS.DO.missing()
    elseif msg == "pets" or msg == "pet" then
        NS.DO.pets()
    elseif msg == "text" or msg:match("^text%s") then
        NS.DO.text(msg:match("^text%s+(%S+)"))
    elseif msg == "layout" or msg == "pyramid" or msg == "grid" or msg == "columns"
        or msg:match("^layout%s") then
        local want = msg:match("^layout%s+(%a+)")
        if msg == "pyramid" then want = "pyramid" elseif msg == "grid" or msg == "columns" then want = "columns" end
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
