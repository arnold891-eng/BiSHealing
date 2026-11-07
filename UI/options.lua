-- =========================================================================
-- BiS Healing -- UI/options.lua : the window, which is the menu
--
-- The old window had twenty-nine rows because the old addon had twenty-nine
-- opinions: bar colours, corner markers, pulse thresholds, chain-heal bounce
-- lines, an Earth Shield section, a wheel with its own keybinds. Arn, 19 Sep
-- 2026, looking at it on a client where none of that runs: "alot of the stuff
-- in the right click was legacy stuff that does not work."
--
-- This addon mostly asks the CLIENT to draw things, so there is very little to
-- have an opinion about. What is left is four switches and four buttons, and
-- every one of them goes through NS.DO -- the same table the slash command and
-- the minimap menu use, so the three doors cannot drift apart.
--
-- The window itself is BiSTheme's shared kit (Libs\BiSTheme\Options.lua), the
-- 230 px one every BiS addon wears.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

local CFG = {}
NS.CFG = CFG
CFG.SCALE = 1.25          -- the options window is drawn 25% larger than the shared kit's size

--- THE SAVED VARIABLES, ALWAYS THE LIVE ONES (8 Nov 2026, the BiS> dashboard). The dashboard is drawn once
--- and keeps the `db` it was handed; NS.DB() can hand back a different table later (a login, an alt's copy
--- claimed), so the dashboard is handed this instead: every read and write lands on NS.DB() as it is now.
--- It also tells a button row which door it was pressed from (fromPage below).
CFG.LIVE = setmetatable({}, {
    __index = function(_, k) return NS.DB()[k] end,
    __newindex = function(_, k, v) NS.DB()[k] = v end,
})

--- Pressed on the BiS> page (the dashboard hands its rows CFG.LIVE): the game's options go away first,
--- so the window a button opens is not left behind them. From the options window: false, nothing done.
local function fromPage(db)
    if db ~= CFG.LIVE then return false end
    local T = BiSTheme
    if T and T.CloseSettingsPanel then T.CloseSettingsPanel() end
    return true
end

--- The rows. A function, not a table: `get` is asked every time the window
--- paints, so a switch shows what is true now rather than what was true at
--- login.
function CFG.Sections()
    local DO = NS.DO or {}
    return {
        -- THE BINDS FIRST. Arn, 21 Sep: "always keep the bind on top". The minimap button opens
        -- this window and nothing else now, so the first row is the thing a healer came for.
        { title = "clicks", options = {
            { key = "mouse", kind = "button", label = "drag spells onto a mouse", help = "Opens the mouse: drag a spell onto a button (left, right, middle, 4, 5, the wheel) and clicking a cell casts it on that player.", button = "binds",
              action = function() if DO.mouse then DO.mouse() end end },
            -- MANA FOR MANA (Arn, 19 Oct: "i want a window in the option that breaks down the mana
            -- efficiency of my healing spells")
            { key = "efficiency", kind = "button", label = "which heal, mana for mana", help = "Every rank of your heals with your gear right now: how much each heals, per mana and per second, how long spamming it lasts - and which one heals the most in a fight of 15 seconds to 5 minutes.", button = "open",
              -- docked off the options' right edge, where the tank mark's preview rolls out; from the
              -- BiS> page, where the options window is not up, free in the middle
              action = function(db)
                  local fe = NS.FE
                  if fe and fe.Docked and fe.Docked() then fe.win:Hide() return end   -- a second press closes it
                  if fromPage(db) then
                      if DO.efficiency then DO.efficiency() end
                  elseif DO.efficiency then
                      DO.efficiency(CFG.frame)
                  end
              end },
            -- one owner of the clicks: ours, or Clique's (Arn, 22 Sep: "im a clique user")
            { key = "clique", kind = "toggle", label = "let Clique handle clicks", help = "If you use Clique, let it own the clicks on our cells; our own binds step aside.",
              get = function(db) return db.clique == true end,
              set = function(_, on) if DO.clique then DO.clique(on) end end },
        } },
        { title = "frames", options = {
            { key = "shown", kind = "toggle", label = "show the cells", help = "Show or hide the healing cells. Hidden, nothing is drawn and nothing is clicked.",
              get = function(db) return db.shown ~= false end,
              set = function(_, on) if DO.show then DO.show(on) end end },
            { key = "minimap", kind = "toggle", label = "minimap button", help = "Show the BiS Healing button on the minimap. /bish still opens everything.",
              get = function() return not (NS.MM and NS.MM.Hidden()) end,
              set = function(_, on) if NS.MM then NS.MM.SetHidden(not on) end end },
            -- a STEPPER, not a slider: the family's options lib has none, on purpose - "230 px has
            -- no room for a track, and a stepper is exact" (Libs/BiSTheme/Options.lua)
            { key = "scale", kind = "step", label = "size of the cells", help = "Scales every cell, bar and word together.",
              min = 0.6, max = 1.6, step = 0.05,
              get = function(db) return db.scale or 1 end,
              set = function(_, v) if NS.FG and NS.FG.SetScale then NS.FG.SetScale(v) end end,
              show = function(db) return ("%d%%"):format(math.floor((db.scale or 1) * 100 + 0.5)) end },
            { key = "center", kind = "button", label = "centre on screen", help = "Puts the cells back in the middle of the screen, if they were dragged out of reach.", button = "centre",
              action = function() if DO.center then DO.center() end end },
            -- FOREVER 1.0: off for a new install, so it needs a switch a player can find (it was a
            -- slash command only, /bish flash)
            { key = "flash", kind = "toggle", label = "LOS flash", help = "Flashes LOS in the middle of a cell when your heal could not see that player (line of sight).",
              get = function(db) return db.flash ~= false end,
              set = function(_, on) if DO.flash then DO.flash(on) end end },
        } },
        -- THE BUFF YOU KEEP FORGETTING (Arn, 23 Sep: "i am always forgetting about watershield").
        -- The header names it out of combat; the client makes a NOISE when it drops, which is the
        -- only half that works mid-fight, where your own buffs are secret. Two rows, because a
        -- switch and a number are two questions: whether, and which.
        { title = "reminders", options = {
            -- FOREVER 1.0: off for a new install. Off watches nothing (no header word, no sound) and
            -- keeps the player's own list; on brings it back (NS.FS.SetWatching)
            { key = "buffwatch", kind = "toggle", label = "watch my buff", help = "Names your own buff (Water Shield, Inner Fire...) in the grid's header when it is not on you. Off: nothing is watched - no header word, no sound.",
              get = function() return NS.FS and NS.FS.Watching and NS.FS.Watching() or false end,
              set = function(_, on) if DO.buff then DO.buff(on and "on" or "off") end end },
            { key = "buffsound", kind = "toggle", label = "sound when it drops", help = "A sound when your own buff (Water Shield, Inner Fire...) falls off - the one thing the game lets an addon say mid-fight. Needs 'watch my buff' on.",
              get = function(db) return db.buffQuiet ~= true end,
              set = function(_, on) if DO.buffsound then DO.buffsound(on and "on" or "off") end end },
            -- the shared lib has four control kinds and no free-text field, on purpose ("230 px
            -- has no room"). So the number lives in a drawer that unrolls under the window, built
            -- here out of the lib's own primitives - the copy under Libs\ is never edited.
            { key = "buffsoundid", kind = "button", label = "sound id", help = "Which sound plays when your buff drops: type a sound id in the drawer that opens.", button = "change",
              -- the drawer hangs under the options window, so from the BiS> page the window comes up with it
              action = function(db)
                  if fromPage(db) then CFG.Open() CFG.Drawer(true) else CFG.Drawer() end
              end },
        } },
        -- THE RIGHT-HAND COLUMN (7 Oct 2026). The window was at its fourteen-row cap and a player
        -- asked for two more settings; Arn: "can we make two colums". How the cells LOOK, and
        -- which cells there ARE, sit beside the rest instead of under it.
        { title = "look", column = 2, options = {
            -- three answers, so segments rather than a switch: "lost" is what they still need
            -- after incoming heals, blank at full
            { key = "number", kind = "seg", label = "number", help = "The number on each cell: lost - the health they still need after heals on the way; % - their health; off - none.",
              values = { "lost", "%", "off" },
              get = function(db)
                  local m = db.text
                  return (m == "percent" and "%") or (m == "off" and "off") or "lost"
              end,
              set = function(_, v)
                  if DO.number then DO.number((v == "%" and "percent") or (v == "off" and "off") or "missing") end
              end },
            { key = "colour", kind = "toggle", label = "bar colour by health", help = "Colour health bars green to red by how hurt they are, instead of by class.",
              get = function(db) return db.color == "health" end,
              set = function(_, on) if DO.colour then DO.colour(on) end end },
            -- a player's two asks, 7 Oct: "a toggle highlight self or highlight target", and "a
            -- slider for how much it dims out of range" - a stepper, like the cell size
            { key = "ring", kind = "seg", label = "gold ring", help = "The gold ring marks a cell: me - your own; target - whoever you have targeted.",
              values = { "me", "target" },
              get = function(db) return db.ring == "target" and "target" or "me" end,
              set = function(_, v) if DO.ring then DO.ring(v) end end },
            -- 7 Oct, Arn's cousin's idea: light up the cell of whoever the mouse is on
            { key = "hover", kind = "toggle", label = "mouse crosshair", help = "Light up the cell of whoever your mouse is on, anywhere on screen.",
              get = function(db) return db.hover ~= false end,
              set = function(_, on) if DO.hover then DO.hover(on) end end },
            { key = "dim", kind = "step", label = "out of range", help = "How far a cell dims when that player is out of your healing range.",
              min = 0.2, max = 0.9, step = 0.05,
              get = function(db) return db.dim or 0.30 end,
              set = function(_, v) if DO.dim then DO.dim(v) end end,
              show = function(db) return ("%d%%"):format(math.floor((db.dim or 0.30) * 100 + 0.5)) end },
            { key = "markers", kind = "step", label = "debuff marker size", help = "The size of the little squares the game draws on a cell for a debuff you can cure.",
              min = 6, max = 20, step = 2,
              get = function(db) return db.markers or 10 end,
              set = function(_, v) if DO.markers then DO.markers(v) end end,
              show = function(db) return ("%dpx"):format(db.markers or 10) end },
            -- the tank's teal X (BiS> now's Tank button), to taste (Arn, 14 Oct: "add the steppers
            -- to the tank x too") - the same two as BiS Tools' bg marks
            -- a stepper through names (Arn: "not all want x")
            { key = "tanklook", kind = "step", label = "tank mark", tankPreview = true, help = "The shape over your chosen tank (BiS> now's Tank button): X, saber, arrow, diamond or corners, in teal. Shows in the open world and battlegrounds - not inside dungeons or raids, where the game keeps friendly nameplates from addons.",
              min = 1, max = NS.FN and #NS.FN.LOOKS or 5, step = 1,
              get = function(db) return NS.FN and NS.FN.TankLook(db) or 1 end,
              set = function(db, v) db.tankLook = v if NS.FN then NS.FN.RedrawTank() end end,
              show = function(db) return NS.FN and NS.FN.LOOKS[NS.FN.TankLook(db)].word or "X" end },
            { key = "tanksize", kind = "step", label = "tank mark size", tankPreview = true, help = "How big the tank's mark is.",
              min = 50, max = 200, step = 10,
              get = function(db) return NS.FN and NS.FN.TankSize(db) or 100 end,
              set = function(db, v) db.tankSize = v if NS.FN then NS.FN.RedrawTank() end end,
              show = function(db) return ("%d%%"):format(NS.FN and NS.FN.TankSize(db) or 100) end },
            { key = "tanklift", kind = "step", label = "tank mark height", tankPreview = true, help = "Moves the tank's mark up or down on them.",
              min = -40, max = 40, step = 5,
              get = function(db) return NS.FN and NS.FN.TankLift(db) or 0 end,
              set = function(db, v) db.tankLift = v if NS.FN then NS.FN.RedrawTank() end end,
              show = function(db)
                  local v = NS.FN and NS.FN.TankLift(db) or 0
                  return v == 0 and "on them" or (v > 0 and (v .. " up") or (-v .. " down"))
              end },
        } },
        { title = "cells", column = 2, options = {
            -- FOUR SWITCHES, ONE ROW. Three of these had a row each and a fourth was asked for
            -- (paszczyszyn, 25 Sep: a cell for yourself), which would have been sixteen rows in a
            -- window whose own rule says thirteen was the last one. They are one question -
            -- "which extra cells do you want?" - and the answers are not exclusive, so this is
            -- not the lib's `seg`: it is built here from the lib's primitives, like the sound
            -- drawer, and each button lights on its own.
            { key = "cells", kind = "cells", label = "cells", help = "Extra cells beside the grid: target, target of target, and a mana list of your healers.", parts = {
                { key = "target", label = "target",
                  get = function(db) return db.target == true end,
                  set = function(on) if DO.target then DO.target(on) end end },
                { key = "tot", label = "tot",
                  get = function(db) return db.tot == true end,
                  set = function(on) if DO.tot then DO.tot(on) end end },
                { key = "mana", label = "mana",
                  get = function(db) return db.mana == true end,
                  set = function(on) if DO.mana then DO.mana(on) end end },
            } },
            -- PETS HAVE THREE ANSWERS, so they are not one of the switches above: in the main
            -- cells, in a block of their own, or nowhere (Arn, 26 Sep). One question, three
            -- answers, which is exactly what the lib's `seg` is for.
            { key = "pets", kind = "seg", label = "pets", help = "Pets: grid - in with their owners; own - a block of their own; off - no pet cells.",
              values = { "grid", "own", "off" },
              get = function() return (NS.FG and NS.FG.PetsMode and NS.FG.PetsMode()) or "off" end,
              set = function(_, v) if DO.pets then DO.pets(v) end end },
            -- THREE LAYOUTS, one row. A player asked for cells "vertically and horizontally"
            -- (paszczyszyn, 22 Sep); the pyramid was already here, so a switch became segments.
            { key = "layout", kind = "seg", label = "groups", help = "How groups are laid out: down - a column each; across - a row each; tanks - tanks on top, the rest below.",
              values = { "down", "across", "tanks" },
              get = function(db)
                  return (db.layout == "rows" and "across") or (db.layout == "pyramid" and "tanks") or "down"
              end,
              set = function(_, v)
                  if DO.layout then
                      DO.layout((v == "across" and "rows") or (v == "tanks" and "pyramid") or "columns")
                  end
              end },
            -- PVP MODE (Arn, 8 Nov 2026): three answers, one row - off, only in battlegrounds and
            -- arenas, or always. Starts off for everyone.
            { key = "pvp", kind = "seg", label = "PvP mode", help = "Beside each player, a small cell with whoever they are targeting - click it to cast your binds on it. Your groups setting keeps the shape (down = columns of 5). A gold edge marks the enemy most of your team is on. bg: only in battlegrounds and arenas.",
              values = { "off", "bg", "on" },
              get = function() return (NS.FG and NS.FG.PvPMode and NS.FG.PvPMode()) or "off" end,
              set = function(_, v) if DO.pvp then DO.pvp(v) end end },
            -- THE CAST ALERT (Arn, 8 Nov 2026: "lets make it an option for them glow or bounce")
            { key = "kickfx", kind = "seg", label = "cast alert", help = "PvP mode: when a teammate's target starts casting, your interrupt icon on its cell lights up - with a gold glow, a bounce, or both. Click the icon to cast your interrupt at it.",
              values = { "glow", "bounce", "both" },
              get = function() return (NS.FG and NS.FG.KickFx and NS.FG.KickFx()) or "both" end,
              set = function(_, v) if DO.kickfx then DO.kickfx(v) end end },
        } },
        -- "this client" held two diagnostics. "test the debuff marker" gave way to a setting on
        -- 22 Sep and "what can I see?" on the 23rd, when a player's three requests arrived at once.
        -- Both are still one word away: /bish auras and /bish scan. "look at the group again" paid
        -- for the sound rows the same way on the 23rd: the grid rescans on every roster event by
        -- itself, so the button was for a bug, and /bish rescan still presses it.
    }
end

--- The rows the window was built from, made once and kept: the BiS> page's dashboard is handed these
--- very tables, so the two can never hold two copies of one setting.
function CFG.Tables()
    if not CFG.tables then CFG.tables = CFG.Sections() end
    return CFG.tables
end

------------------------------------------------------- the cells row --
--
-- One row, four switches that are not exclusive: the target cell, its target, your own, and pets.
-- The shared lib has a `seg`, but a seg is one question with one answer and paints exactly one
-- value live - which would say "you can have the target cell OR your own", and you can have both.
-- So this is built from the lib's own primitives, the same escape hatch the sound drawer uses,
-- and the copy under Libs\ is not touched.
--
-- It is also what kept the window short. These were three rows and a fourth was wanted; the
-- window's own rule said thirteen was the last one it could afford.

function CFG.CellsRow(f, opt)
    local T = BiSTheme
    local P = T and T.OptionsPrimitives
    if not P then return f:Row({ kind = "button", label = opt.label, button = "?",
                                 action = function() end }, NS.DB()) end
    local O = T.OPTIONS
    local row = f:AddRow()
    row.opt = opt
    row.name = P.fs(row, opt.label, 8, "ink2")
    row.name:SetPoint("LEFT", O.INDENT, 0)

    -- the whole width left of the edge, shared out: a label this short does not need the 110 px
    -- the lib reserves for a control, and four words do
    local WIDE, GAP = 42, 3
    local buttons = {}
    for i, part in ipairs(opt.parts) do
        local b = P.flat(row, WIDE, 12, part.label)
        b:SetPoint("RIGHT", -6 - (#opt.parts - i) * (WIDE + GAP), 0)
        T.Fit(b.label, part.label, WIDE - 4)
        b:SetScript("OnClick", function()
            local db = NS.DB()
            local on = not (part.get(db) == true)
            part.set(on)
            f:Paint()
            f:Say(part.label .. (part.get(NS.DB()) and " on" or " off"),
                  part.get(NS.DB()) and "good" or "warn")
        end)
        buttons[i] = b
    end
    row.ctl = buttons
    CFG.cells = row                   -- so a suite can press the buttons, not just read the table
    row.paint = function()
        local db = NS.DB()
        for i, b in ipairs(buttons) do
            local on = opt.parts[i].get(db) == true
            b.edge:set(on and "accent" or "edge", 1)
            -- NO BRACKETS ROUND THE CALL. `(f())` keeps the FIRST return value and throws the
            -- rest away, so green and blue arrived as nil and the client refused the colour:
            -- five errors out of one click on the minimap button (Arn, 26 Sep). The same trap
            -- cost the header its regen number on the 23rd, in `GetManaRegen and GetManaRegen()`.
            local r, g, bl = T.rgb(on and "accent" or "muted")
            b.label:SetTextColor(r, g, bl, 1)
            -- hover must not leave a live one looking dead (the lib's seg learned this too)
            b:SetScript("OnLeave", function(x) x.edge:set(on and "accent" or "edge", 1) end)
        end
    end
    return row
end

---------------------------------------------------- the sound id drawer --
--
-- Arn, 23 Sep 2026: "toggle in options to turn sound on or off and unrolled window to put in
-- another sound id number if they want to change it".
--
-- WHY IT IS NOT A ROW. BiSTheme's options lib has four control kinds and says so in its own file:
-- no sliders, no free-text fields, no dropdowns, because the window is 230 pixels wide. That lib
-- is a COPY under Libs\ and the harness compares it to the canon byte for byte, so a fifth kind
-- would be a change to every addon in the family for one number in one addon. Instead this
-- unrolls underneath the window, where there is as much room as it needs, and is built from the
-- primitives the lib exports for exactly this.
--
-- A NUMBER, NOT A FILE NAME. Playing a game file by path is silent on this client and reports
-- success while it does it, which is how BiSGamba shipped with every cue mute. The box takes
-- digits only, and `hear` plays it before it is kept - the one test this addon cannot run itself.

function CFG.Drawer(want)
    local f = CFG.Build()
    if not f then return nil end
    local T = BiSTheme
    local P = T and T.OptionsPrimitives
    if not P then return nil end
    local FS, DO = NS.FS, NS.DO or {}

    local d = CFG.drawer
    if not d then
        d = CreateFrame("Frame", "BiSHealingSoundDrawer", f)
        d:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
        d:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
        d:SetHeight(40)
        P.tex(d, "BACKGROUND", "frame", 0.9)
        P.border(d, "edge", 0.35)

        local cap = P.fs(d, "a sound id, not a file name", 8, "muted")
        cap:SetPoint("TOPLEFT", 8, -6)

        local field = CreateFrame("Frame", nil, d)
        field:SetPoint("BOTTOMLEFT", 8, 7)
        field:SetSize(72, 14)
        P.tex(field, "BACKGROUND", "field", 0.9)
        P.border(field, "edge", 1)

        local box = CreateFrame("EditBox", nil, field)
        box:SetPoint("TOPLEFT", 3, 0)
        box:SetPoint("BOTTOMRIGHT", -3, 0)
        box:SetAutoFocus(false)             -- or it eats the keyboard the moment the window opens
        box:SetNumeric(true)                -- digits: see above
        box:SetMaxLetters(9)
        pcall(box.SetFont, box, STANDARD_TEXT_FONT, 9, "")
        d.box = box

        local hear = P.flat(d, 40, 14, "hear")
        hear:SetPoint("BOTTOMLEFT", field, "BOTTOMRIGHT", 6, 0)
        local set = P.flat(d, 40, 14, "set")
        set:SetPoint("BOTTOMLEFT", hear, "BOTTOMRIGHT", 4, 0)
        local ours = P.flat(d, 46, 14, "default")
        ours:SetPoint("BOTTOMLEFT", set, "BOTTOMRIGHT", 4, 0)

        --- What the box says, as a file id - or nil for "put it back to ours".
        local function typed()
            local t = box.GetText and box:GetText() or nil
            return tonumber(t and t:match("%d+") or nil)
        end

        local function keep()
            local id = typed()
            if DO.buffsound then DO.buffsound(id and tostring(id) or "default") end
            CFG.Fill()
            f:Paint()
            f:Say(id and ("sound " .. id) or "the usual sound", "good")
        end

        hear:SetScript("OnClick", function()
            local id = typed()
            local played, why = FS and FS.Play and FS.Play(id or (FS.File and FS.File()))
            f:Say(played and ("playing " .. tostring(id or (FS and FS.File and FS.File())))
                or tostring(why or "no sound"), played and "ink2" or "warn")
        end)
        set:SetScript("OnClick", keep)
        ours:SetScript("OnClick", function()
            if box.SetText then box:SetText("") end
            keep()
        end)
        box:SetScript("OnEnterPressed", function() keep() if box.ClearFocus then box:ClearFocus() end end)
        box:SetScript("OnEscapePressed", function()
            CFG.Fill()
            if box.ClearFocus then box:ClearFocus() end
            d:Hide()
        end)

        -- the drawer belongs to the window: closing one closes the other, so a panel cannot be
        -- left floating under a window that is no longer there
        f:HookScript("OnHide", function() if CFG.drawer then CFG.drawer:Hide() end end)
        CFG.drawer = d
        d:Hide()
    end

    if want == nil then want = not d:IsShown() end
    if want then
        CFG.Fill()
        d:Show()
    else
        d:Hide()
    end
    return d
end

--- The box shows what is actually set, every time it opens: the player's id, or ours.
function CFG.Fill()
    local d = CFG.drawer
    if not (d and d.box and d.box.SetText) then return nil end
    local FS = NS.FS
    local file = FS and FS.File and FS.File()
    d.box:SetText(type(file) == "number" and tostring(file) or "")
    return file
end

--------------------------------------------------------------- the window --

function CFG.Build()
    if CFG.built then return CFG.frame end
    if not (BiSTheme and BiSTheme.Options) then
        -- Options.lua ships embedded under Libs\, so this only happens when the
        -- TOC line is lost. Say it once rather than throwing on every /bish.
        NS.Print("Libs\\BiSTheme\\Options.lua did not load -- reinstall the addon")
        return nil
    end
    CFG.built = true
    local W = BiSTheme.OPTIONS.W
    local f = BiSTheme.Options("BiSHealingOptions", W, "Heal")
    CFG.frame = f
    -- 25% BIGGER (Arn, 7 Oct: "this is honestly too small ... bring up the size of the option
    -- window 25% its too hard to read"). The whole window scales - text, boxes, spacing - so the
    -- layout is the shared kit's, just larger. Here and not in the kit: the kit is embedded in six
    -- addons, and a bigger window everywhere is a lib change of its own.
    f:SetScale(CFG.SCALE)
    f:Recenter(60)
    -- TWO COLUMNS (Arn, 7 Oct: "can we make two colums"). The shared window stacks every row down
    -- one 230 px column. Rather than teach the shared lib columns - a change copied into six
    -- addons - each column is built as the lib builds it, from the top, and each row is then
    -- pinned into its own column. It leans on the lib's own fields (rows, _y, body); if those
    -- ever change, the window falls back to one column and the suite says so.
    local columns = f.rows and f.body and type(f._y) == "number"
    local col = {}                                   -- row -> its column
    local heights = {}
    for c = 1, 2 do
        if columns then f._y = 0 end
        for _, section in ipairs(CFG.Tables()) do
            if (section.column or 1) == c then
                local first = #f.rows + 1
                f:Section(section.title)
                for _, opt in ipairs(section.options) do
                    if opt.kind == "cells" then CFG.CellsRow(f, opt) else f:Row(opt, NS.DB()) end
                end
                for i = first, #f.rows do col[f.rows[i]] = c end
            end
        end
        heights[c] = f._y
    end
    if columns then
        local ROW = BiSTheme.OPTIONS.ROW
        local y = { 0, 0 }
        for _, r in ipairs(f.rows) do
            local c = col[r] or 1
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", f.body, "TOPLEFT", (c - 1) * W, -y[c])
            r:SetWidth(W)
            y[c] = y[c] + ROW
        end
        f:SetWidth(2 * W)
        f._y = math.max(heights[1] or 0, heights[2] or 0)
        CFG.columns = 2
    end
    f:Fit()
    -- the tank mark's roll-out preview (Arn, 14 Oct: "bis healing needs a preview like bis tools")
    if NS.FN and NS.FN.AttachPreview then NS.FN.AttachPreview(f) end
    return f
end

function CFG.Open()
    local f = CFG.Build()
    if f then f:Toggle(true) f:Paint() end
end

function CFG.Toggle()
    local f = CFG.Build()
    if f then
        f:Toggle()
        if f:IsShown() then f:Paint() end
    end
end

------------------------------------------------- the BiS> page in the game's options --
--
-- Arn, 7 Nov 2026 (Forever 1.0): "when they open the options, they go to add-ons ... they'll just see
-- BiS> ... click into that add-on". Esc > Options > AddOns > BiS> > BiS> Healing shows what is on and a
-- button to THIS window (kit minor 2, 8 Nov: the page never squeezes the window inside it any more -
-- Arn: "dont just shrink remake them all"). The minimap's right-click toggles this window straight
-- away, never the game's options (Arn: "i liked these old option windows that opened without opening
-- the game option window").

--- What is on, in a few words, for the BiS> front page.
function CFG.Status()
    local db = NS.DB()
    local function say(word, on) return word .. (on and " on" or " off") end
    local FS = NS.FS
    local sound = FS and FS.Watching and FS.Watching() and not (FS.Quiet and FS.Quiet())
    return table.concat({
        say("frames", db.shown ~= false),
        say("crosshair", db.hover ~= false),
        say("LOS flash", db.flash ~= false),
        say("buff sound", sound and true or false),
        "PvP " .. ((NS.FG and NS.FG.PvPMode and NS.FG.PvPMode()) or "off"),
    }, "  -  ")
end

--- THE DASHBOARD'S SECTIONS (8 Nov 2026, the family rule: every BiS> page is the kit's T.Dashboard).
--- The settings are the window's own rows (CFG.Tables), picked by key and sorted into sections by what
--- they are about; a section with an on/off of its own gets a switch through the same NS.DO door the
--- slash command uses. Only the shared kit's four kinds reach the page: the window's `cells` row (four
--- switches drawn by hand) arrives as four toggles over the very same get/set.
local CELL_WORDS = {
    target = { "a cell for your target", "A cell for whoever you have targeted, beside the grid. /bish target left|right|top|under, or drag its header." },
    tot    = { "your target's target", "And one for your target's target, beside it." },
    mana   = { "the healers' mana", "The other healers' mana, in a block of its own." },
}

function CFG.Entries()
    local DO = NS.DO or {}
    local db = CFG.LIVE
    local o = {}
    for _, sec in ipairs(CFG.Tables()) do
        for _, opt in ipairs(sec.options) do o[opt.key] = opt end
    end
    local function pick(...)
        local out = {}
        for _, k in ipairs({ ... }) do if o[k] then out[#out + 1] = o[k] end end
        return out
    end
    -- the cells row's four switches, one toggle each, then the pets
    local extra = {}
    for _, part in ipairs((o.cells and o.cells.parts) or {}) do
        local words = CELL_WORDS[part.key] or { part.label, o.cells.help }
        extra[#extra + 1] = { key = "cell" .. part.key, kind = "toggle", label = words[1], help = words[2],
                              get = part.get, set = function(_, on) part.set(on) end }
    end
    if o.pets then extra[#extra + 1] = o.pets end
    -- BiS> now's buff buttons, one per buff (Buffs.lua): the same /bish buffs <key> on|off
    local FU = NS.FU
    local buffs = {}
    for _, fam in ipairs((FU and FU.FAMILIES) or {}) do
        buffs[#buffs + 1] = { key = "buff" .. fam.key, kind = "toggle", label = fam.name,
            help = fam.name .. ": its button shows in BiS> now once you have trained it, and finds who lacks it.",
            get = function() return FU.FamilyOn(fam) and true or false end,
            set = function(_, on) if DO.buffs then DO.buffs(fam.key, on and "on" or "off") end end }
    end

    local list = {
        { key = "frames", title = "frames",
          desc = "The healing cells themselves: whether they show, how big they are, and the LOS flash on a cell your heal could not see. Off hides every cell - nothing is drawn and nothing is clicked.",
          switch = { get = function() return NS.DB().shown ~= false end,
                     set = function(on) if NS.DO.show then NS.DO.show(on) end end },
          options = pick("scale", "center", "flash"), db = db,
          usage = "/bish show  -  /bish hide  -  /bish center  -  /bish scale 90  -  /bish flash" },
        { key = "clicks", title = "binds & clicks",
          desc = "What a click on a cell casts. Drag a spell onto a mouse button in the binds window - or, if you use Clique, let it own the clicks.",
          open = { label = "mouse binds", func = function() if NS.DO.mouse then NS.DO.mouse() end end },
          options = pick("clique", "efficiency", "minimap"), db = db,
          usage = "/bish mouse  -  /bish clique  -  /bish efficiency" },
        { key = "look", title = "look",
          desc = "What each cell shows: the number on it, the bar colour, the gold ring, the mouse crosshair, how far it dims out of range and the size of the debuff markers.",
          options = pick("number", "colour", "ring", "hover", "dim", "markers"), db = db,
          usage = "/bish number  -  /bish colour  -  /bish ring me|target  -  /bish hover  -  /bish dim 40  -  /bish markers 12" },
        { key = "layout", title = "layout",
          desc = "How the groups sit: a column each, a row each, or tanks on top. PvP mode adds, beside everyone, whoever they are targeting, to click - in whichever of those shapes you picked.",
          options = pick("layout", "pvp", "kickfx"), db = db,
          usage = "/bish layout columns|across|pyramid  -  /bish pvpmode off|bg|on" },
        { key = "cells", title = "target & pets",
          desc = "Extra cells beside the grid - your target, its target, the other healers' mana - and where pets go.",
          options = extra, db = db,
          usage = "/bish target  -  /bish tot  -  /bish me  -  /bish mana  -  /bish pets grid|own|off" },
        { key = "now", title = "BiS> now",
          desc = "The block of buttons that matter right now, beside the grid. Its Tank button puts a teal mark over your tank, shaped and sized here.",
          switch = { get = function() return NS.DB().now == true end,
                     set = function(on) if NS.DO.now then NS.DO.now(on and "on" or "off") end end },
          options = pick("tanklook", "tanksize", "tanklift"), db = db,
          usage = "/bish now on|off  -  /bish now left|right|top|under" },
        { key = "buffs", title = "buff buttons",
          desc = "BiS> now's buff buttons: one click puts your group buff on whoever lacks it. Only buffs you have trained show. Switching them on switches BiS> now on too.",
          switch = { get = function() return NS.DB().buffs == true end,
                     set = function(on) if NS.DO.buffs then NS.DO.buffs(on and "on" or "off") end end },
          options = buffs, db = db,
          usage = "/bish buffs on|off  -  /bish buffs fort on|off" },
    }
    if o.buffwatch then
        list[#list + 1] = { key = "reminders", title = "buff reminder",
          desc = "Your own buff (Water Shield, Inner Fire...) named in the grid's header when it is not on you, and a sound when it drops - the one thing the game lets an addon say mid-fight.",
          switch = { get = function() return o.buffwatch.get(db) and true or false end,
                     set = function(on) o.buffwatch.set(db, on) end },
          options = pick("buffsound", "buffsoundid"), db = db,
          usage = "/bish buff on|off  -  /bish buff Water Shield  -  /bish buffsound <id>|off|on|default|test" }
    end
    -- THE SHARED CHANNEL (LibBiSComm): its own switch, the one /biscomm on|off flips; kept here at logout
    local lib = _G.LibBiSComm
    if lib and lib.Enabled and lib.SetEnabled then
        local share = {}
        if lib.Sharing and lib.SetSharing then
            share[1] = { key = "commshare", kind = "toggle", label = "share where I am",
                help = "Lets your guild's BiS addons show where you are on their map. Off: you still hear the channel.",
                get = function() return lib:Sharing() end,
                set = function(_, on) lib:SetSharing(on) if NS.Comm then NS.Comm.Save() end end }
        end
        list[#list + 1] = { key = "channel", title = "the channel",
          desc = "The hidden addon channel every BiS addon shares with your group and guild - never chat. Off: silent and deaf, and the cells still work on their own.",
          switch = { get = function() return lib:Enabled() end,
                     set = function(on)
                         lib:SetEnabled(on)
                         if on and lib.Hi then pcall(lib.Hi, lib) end
                         if NS.Comm then NS.Comm.Save() end
                     end },
          options = share, db = db,
          usage = "/biscomm on|off  -  /biscomm share on|off  -  /biscomm ver" }
    end
    return list
end

--- What the BiS> page draws: the kit's dashboard over the window's own rows.
function CFG.Model()
    return {
        entries = CFG.Entries,
        list = "SECTIONS",
        idle = "Point at anything on this page to read what it does. Right-click a section in the list to switch it on or off.",
        -- the options window, if it is up, shows the change too (the minimap's right-click keeps it open)
        onChange = function()
            local f = CFG.frame
            if f and f.IsShown and f:IsShown() and f.Paint then f:Paint() end
        end,
    }
end

function CFG.Page()
    local T = BiSTheme
    if not (T and T.SettingsPage) then return nil end
    return T.SettingsPage(ADDON, {
        title  = "Healing",
        about  = "Click-to-heal cells for any healer: drag a spell onto a mouse button, then click a cell to cast "
              .. "it on that player. A new install starts with the cells, your binds, cure boxes and your HoTs on - "
              .. "the crosshair, the LOS flash and the buff reminder wait here for you to switch them on.",
        status = CFG.Status,
        -- THE DASHBOARD (kit minor 3): drawn once over the page's body, painted every time it shows. The
        -- options window is never taken in - it stays the minimap's right-click, as it always was.
        build   = function(body) if T.Dashboard then CFG.dash = T.Dashboard(body, CFG.Model()) end end,
        refresh = function() if CFG.dash then CFG.dash:Paint() end end,
        open   ={ label = "mouse binds", func = function() if NS.DO and NS.DO.mouse then NS.DO.mouse() end end },
        api    = { name = "BiSHealingAPI", about = "what a click on a cell casts, the grid and BiS> now, the tank; "
              .. "opens the binds or the options" },
    })
end

-- At PLAYER_LOGIN: the window reads the saved variables, which are not there while the files load.
CFG.events = CreateFrame("Frame")
CFG.events:RegisterEvent("PLAYER_LOGIN")
CFG.events:SetScript("OnEvent", function() pcall(CFG.Page) end)

-- What a headless suite reads back. A window cannot be looked at, so the rows
-- and what each one says right now are the only honest things to assert on.
NS.UI = {
    Toggle = CFG.Toggle,
    Open   = CFG.Open,
    Drawer = function(want) return CFG.Drawer(want) end,
    Sections = function() return CFG.Sections() end,
    Rows   = function()
        local out = {}
        for _, sec in ipairs(CFG.Sections()) do
            for _, opt in ipairs(sec.options) do out[#out + 1] = opt end
        end
        return out
    end,
    Get    = function(key)
        for _, opt in ipairs(NS.UI.Rows()) do
            if opt.key == key and opt.get then return opt.get(NS.DB()) end
        end
        return nil
    end,
}
