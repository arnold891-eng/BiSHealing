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

-- Every row is one entry in NS.DO, the table Core.lua keeps of everything this addon can be
-- asked to do. The slash command reads the same table, and so does the options window: three
-- doors, one implementation, and none of them can drift from the others.
local function act(name)
    return function()
        local fn = NS.DO and NS.DO[name]
        if fn then fn() end
    end
end

local function onOff(v) return v and "on" or "off" end

--- The db bucket for the button itself: the angle it was dragged to, and whether it is hidden.
--- Its own corner, so clearing anything else cannot lose where the button sits.
function MM.DB()
    local db = (NS.DB and NS.DB()) or {}
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    return db.minimap
end

--- The rows. A FUNCTION, not a table: it is called every time the menu opens, so a row says what
--- is true NOW - which is the thing a printed command answer could do and a static menu cannot.
---
--- Kept short on purpose. The old addon had twenty-eight commands; turning all of them into rows
--- would have been the same problem with a mouse.
function MM.Rows()
    local db = (NS.DB and NS.DB()) or {}
    return {
        { text = "options",            note = "/bish", func = act("options") },
        { text = "mouse binds",        note = "drag a spell", func = act("mouse") },
        { sep = true },
        { text = "show the cells",     checked = db.shown ~= false, func = act("show") },
        { text = "centre on screen",   func = act("center") },
        { text = "look at the group again", note = "/bish rescan", func = act("rescan") },
        { sep = true },
        { text = "what can I see?",    note = "/bish scan", func = act("scan") },
        { text = "test the debuff marker", note = onOff(NS.FA and NS.FA.debug),
          checked = (NS.FA and NS.FA.debug) and true or false, func = act("auras") },
        { sep = true },
        { text = "hide this button",   note = "options to bring it back",
          func = function() MM.SetHidden(true) end },
    }
end

--- Build it, once. Returns the button, or nil on a client with no minimap frame (the headless
--- case) or with the shared lib missing from the TOC.
function MM.Build()
    if MM.button then return MM.button end
    if not (BiSTheme and BiSTheme.Minimap) then return nil end
    MM.button = BiSTheme.Minimap("BiSHealing", {
        icon    = "Interface\\Icons\\Spell_Nature_HealingWaveGreater",
        label   = "Healing",
        db      = MM.DB(),
        menu    = MM.Rows,
        onRight = act("options"),
        tooltip = { "the commands, without the commands" },
    })
    return MM.button
end

--- Put the button back where the db says, and show or hide it to match. Called from the options
--- toggle, so the switch and the button cannot disagree.
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

-- Built at PLAYER_LOGIN rather than at load: the saved variables are not there yet while the
-- files are running, and the angle this button sits at is one of them.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    MM.Build()
end)
MM.frame = ev
