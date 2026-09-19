-- =========================================================================
-- BiS Healing -- UI/minimap.lua : the button on the minimap, and what is behind it
--
-- Arn, 19 Sep 2026: "lets make a minimap button with the options too many /
-- commands". There are twenty-five of them under /bish and three under /bishf,
-- and a command you have to remember is a feature only its author uses.
--
-- EVERY ROW RUNS THE SLASH COMMAND. Not a copy of what the command does --
-- SlashCmdList.BISHEALING("lock") itself. One implementation behind two doors,
-- so the menu cannot drift from the command the way a second copy would, and
-- anything the command prints still gets printed.
--
-- The button and the menu are BiSTheme's (Libs\BiSTheme\Minimap.lua, shared with
-- the rest of the family). This file is only the list of rows and the two live
-- questions each one answers: is it on, and what does it say it is set to.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

-- Captured at load, which is safe only because the TOC runs BiSHealing.lua and
-- UI\options.lua before this file. See the same note at the top of options.lua.
local DB = NS.DB

local MM = {}
NS.MM = MM

-- Running a command is a function the menu can hold. `cmd` is /bish, `fcmd` is
-- /bishf -- the Forever side, which only exists on a client that hides its
-- numbers.
local function cmd(what)
    return function()
        if SlashCmdList and SlashCmdList.BISHEALING then SlashCmdList.BISHEALING(what) end
    end
end

local function fcmd(what)
    return function()
        if SlashCmdList and SlashCmdList.BISHEALFOREVER then
            SlashCmdList.BISHEALFOREVER(what)
        end
    end
end

local function onOff(v) return v and "on" or "off" end

--- The db bucket for the button itself: the angle it was dragged to, and whether
--- it is hidden. Its own corner, so /bish reset can clear the frames without
--- losing where the button sits.
function MM.DB()
    local db = (DB and DB()) or {}
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    return db.minimap
end

--- The rows. A FUNCTION, not a table: it is called every time the menu opens, so
--- "lock frames / on" is what is true now rather than what was true at login.
---
--- Kept SHORT on purpose. Twenty-eight commands do not become twenty-eight rows
--- -- that is the same problem with a mouse. These are the ones worth a click;
--- the rest stay commands, and the options window holds every setting.
function MM.Rows()
    local db = (DB and DB()) or {}
    local forever = NS.SECRET and true or false
    return {
        { text = "options",            note = "/bish config", func = cmd("config") },
        { text = "mouse binds",        note = forever and "/bishf mouse" or "not here",
          func = fcmd("mouse"),        disabled = not (forever and NS.FM) },
        { sep = true },
        { text = "show the frames",    checked = db.shown ~= false,
          func = cmd(db.shown ~= false and "hide" or "show") },
        { text = "lock the anchor",    note = onOff(db.locked), checked = db.locked and true or false,
          func = cmd("lock") },
        { text = "centre on screen",   func = cmd("center") },
        { text = "look at the group again", note = "/bish rescan", func = cmd("rescan") },
        { sep = true },
        { text = "wheel heals",        note = onOff(db.wheel), checked = db.wheel and true or false,
          func = cmd("wheel") },
        { text = "walk every feature", note = "demo",
          checked = (NS.demo and NS.demo.on) and true or false,
          func = cmd((NS.demo and NS.demo.on) and "sim off" or "sim on") },
        { sep = true },
        -- the Forever pair. On a TBC client there is nothing behind either, so
        -- they are greyed rather than hidden: a row that vanishes teaches
        -- nothing, and a greyed one says this client does not do that.
        { text = "what can I see?",    note = forever and "/bishf" or "forever only",
          func = fcmd(""), disabled = not forever },
        { text = "test the debuff pip", note = (NS.FA and NS.FA.debug) and "on" or "forever only",
          checked = (NS.FA and NS.FA.debug) and true or false,
          func = fcmd("auras"), disabled = not (forever and NS.FA) },
        { sep = true },
        { text = "hide this button",   note = "options to bring it back",
          func = function() MM.SetHidden(true) end },
    }
end

--- Build it, once. Returns the button, or nil on a client with no minimap frame
--- (the headless case) or with the shared lib missing from the TOC.
function MM.Build()
    if MM.button then return MM.button end
    if not (BiSTheme and BiSTheme.Minimap) then return nil end
    MM.button = BiSTheme.Minimap("BiSHealing", {
        icon    = "Interface\\Icons\\Spell_Nature_HealingWaveGreater",
        label   = "Healing",
        db      = MM.DB(),
        menu    = MM.Rows,
        onRight = cmd("config"),
        tooltip = { "the commands, without the commands" },
    })
    return MM.button
end

--- Put the button back where the db says, and show or hide it to match. Called
--- from the options toggle, so the switch and the button cannot disagree.
function MM.Refresh()
    local b = MM.Build()
    if b then return b:Refresh() end
    return false
end

function MM.SetHidden(hide)
    MM.DB().hide = hide and true or false
    local b = MM.Build()
    if b then b:SetHidden(hide) end
    return not hide
end

function MM.Hidden()
    return MM.DB().hide and true or false
end

-- Built at PLAYER_LOGIN rather than at load: the saved variables are not there
-- yet while the files are running, and the angle this button sits at is one of
-- them.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    MM.Build()
end)
MM.frame = ev
