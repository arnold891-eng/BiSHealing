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

--- The rows. A function, not a table: `get` is asked every time the window
--- paints, so a switch shows what is true now rather than what was true at
--- login.
function CFG.Sections()
    local DO = NS.DO or {}
    return {
        -- THE BINDS FIRST. Arn, 21 Sep: "always keep the bind on top". The minimap button opens
        -- this window and nothing else now, so the first row is the thing a healer came for.
        { title = "clicks", options = {
            { key = "mouse", kind = "button", label = "drag spells onto a mouse", button = "binds",
              action = function() if DO.mouse then DO.mouse() end end },
            -- one owner of the clicks: ours, or Clique's (Arn, 22 Sep: "im a clique user")
            { key = "clique", kind = "toggle", label = "let Clique handle clicks",
              get = function(db) return db.clique == true end,
              set = function(_, on) if DO.clique then DO.clique(on) end end },
        } },
        { title = "frames", options = {
            { key = "shown", kind = "toggle", label = "show the cells",
              get = function(db) return db.shown ~= false end,
              set = function(_, on) if DO.show then DO.show(on) end end },
            { key = "minimap", kind = "toggle", label = "minimap button",
              get = function() return not (NS.MM and NS.MM.Hidden()) end,
              set = function(_, on) if NS.MM then NS.MM.SetHidden(not on) end end },
            -- a STEPPER, not a slider: the family's options lib has none, on purpose - "230 px has
            -- no room for a track, and a stepper is exact" (Libs/BiSTheme/Options.lua)
            { key = "scale", kind = "step", label = "size of the cells",
              min = 0.6, max = 1.6, step = 0.05,
              get = function(db) return db.scale or 1 end,
              set = function(_, v) if NS.FG and NS.FG.SetScale then NS.FG.SetScale(v) end end,
              show = function(db) return ("%d%%"):format(math.floor((db.scale or 1) * 100 + 0.5)) end },
            { key = "center", kind = "button", label = "centre on screen", button = "centre",
              action = function() if DO.center then DO.center() end end },
        } },
        -- THE BUFF YOU KEEP FORGETTING (Arn, 23 Sep: "i am always forgetting about watershield").
        -- The header names it out of combat; the client makes a NOISE when it drops, which is the
        -- only half that works mid-fight, where your own buffs are secret. Two rows, because a
        -- switch and a number are two questions: whether, and which.
        { title = "reminders", options = {
            { key = "buffsound", kind = "toggle", label = "sound when it drops",
              get = function(db) return db.buffQuiet ~= true end,
              set = function(_, on) if DO.buffsound then DO.buffsound(on and "on" or "off") end end },
            -- the shared lib has four control kinds and no free-text field, on purpose ("230 px
            -- has no room"). So the number lives in a drawer that unrolls under the window, built
            -- here out of the lib's own primitives - the copy under Libs\ is never edited.
            { key = "buffsoundid", kind = "button", label = "sound id", button = "change",
              action = function() CFG.Drawer() end },
        } },
        -- THE RIGHT-HAND COLUMN (7 Oct 2026). The window was at its fourteen-row cap and a player
        -- asked for two more settings; Arn: "can we make two colums". How the cells LOOK, and
        -- which cells there ARE, sit beside the rest instead of under it.
        { title = "look", column = 2, options = {
            -- three answers, so segments rather than a switch: "lost" is what they still need
            -- after incoming heals, blank at full
            { key = "number", kind = "seg", label = "number",
              values = { "lost", "%", "off" },
              get = function(db)
                  local m = db.text
                  return (m == "percent" and "%") or (m == "off" and "off") or "lost"
              end,
              set = function(_, v)
                  if DO.number then DO.number((v == "%" and "percent") or (v == "off" and "off") or "missing") end
              end },
            { key = "colour", kind = "toggle", label = "bar colour by health",
              get = function(db) return db.color == "health" end,
              set = function(_, on) if DO.colour then DO.colour(on) end end },
            -- a player's two asks, 7 Oct: "a toggle highlight self or highlight target", and "a
            -- slider for how much it dims out of range" - a stepper, like the cell size
            { key = "ring", kind = "seg", label = "gold ring",
              values = { "me", "target" },
              get = function(db) return db.ring == "target" and "target" or "me" end,
              set = function(_, v) if DO.ring then DO.ring(v) end end },
            -- 7 Oct, Arn's cousin's idea: light up the cell of whoever the mouse is on
            { key = "hover", kind = "toggle", label = "mouse crosshair",
              get = function(db) return db.hover ~= false end,
              set = function(_, on) if DO.hover then DO.hover(on) end end },
            { key = "dim", kind = "step", label = "out of range",
              min = 0.2, max = 0.9, step = 0.05,
              get = function(db) return db.dim or 0.45 end,
              set = function(_, v) if DO.dim then DO.dim(v) end end,
              show = function(db) return ("%d%%"):format(math.floor((db.dim or 0.45) * 100 + 0.5)) end },
            { key = "markers", kind = "step", label = "marker size",
              min = 6, max = 20, step = 2,
              get = function(db) return db.markers or 10 end,
              set = function(_, v) if DO.markers then DO.markers(v) end end,
              show = function(db) return ("%dpx"):format(db.markers or 10) end },
        } },
        { title = "cells", column = 2, options = {
            -- FOUR SWITCHES, ONE ROW. Three of these had a row each and a fourth was asked for
            -- (paszczyszyn, 25 Sep: a cell for yourself), which would have been sixteen rows in a
            -- window whose own rule says thirteen was the last one. They are one question -
            -- "which extra cells do you want?" - and the answers are not exclusive, so this is
            -- not the lib's `seg`: it is built here from the lib's primitives, like the sound
            -- drawer, and each button lights on its own.
            { key = "cells", kind = "cells", label = "cells", parts = {
                { key = "target", label = "target",
                  get = function(db) return db.target == true end,
                  set = function(on) if DO.target then DO.target(on) end end },
                { key = "tot", label = "tot",
                  get = function(db) return db.tot == true end,
                  set = function(on) if DO.tot then DO.tot(on) end end },
                { key = "me", label = "me",
                  get = function(db) return db.me == true end,
                  set = function(on) if DO.me then DO.me(on) end end },
                { key = "mana", label = "mana",
                  get = function(db) return db.mana == true end,
                  set = function(on) if DO.mana then DO.mana(on) end end },
            } },
            -- PETS HAVE THREE ANSWERS, so they are not one of the switches above: in the main
            -- cells, in a block of their own, or nowhere (Arn, 26 Sep). One question, three
            -- answers, which is exactly what the lib's `seg` is for.
            { key = "pets", kind = "seg", label = "pets",
              values = { "grid", "own", "off" },
              get = function() return (NS.FG and NS.FG.PetsMode and NS.FG.PetsMode()) or "off" end,
              set = function(_, v) if DO.pets then DO.pets(v) end end },
            -- THREE LAYOUTS, one row. A player asked for cells "vertically and horizontally"
            -- (paszczyszyn, 22 Sep); the pyramid was already here, so a switch became segments.
            { key = "layout", kind = "seg", label = "groups",
              values = { "down", "across", "tanks" },
              get = function(db)
                  return (db.layout == "rows" and "across") or (db.layout == "pyramid" and "tanks") or "down"
              end,
              set = function(_, v)
                  if DO.layout then
                      DO.layout((v == "across" and "rows") or (v == "tanks" and "pyramid") or "columns")
                  end
              end },
        } },
        -- "this client" held two diagnostics. "test the debuff marker" gave way to a setting on
        -- 22 Sep and "what can I see?" on the 23rd, when a player's three requests arrived at once.
        -- Both are still one word away: /bish auras and /bish scan. "look at the group again" paid
        -- for the sound rows the same way on the 23rd: the grid rescans on every roster event by
        -- itself, so the button was for a bug, and /bish rescan still presses it.
    }
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
        for _, section in ipairs(CFG.Sections()) do
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
