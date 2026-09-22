--[[
  BiSHealing / Forever :: Forever/Mouse.lua - bind spells to the mouse you actually hold.

  Healium gives you a row of buttons beside each name and you drag spells onto them. This does the
  same job the other way round: a picture of a MOUSE, and you drop a spell on the button you intend
  to press. Left click, right click, middle, the two thumb buttons, wheel up and wheel down - times
  no modifier, shift, ctrl and alt. Twenty-eight slots, each one a place your hand already knows.

  TWO MECHANISMS, because the client has two.

    buttons 1-5   a secure attribute on every grid cell: `*type1`/`*spell1`, `shift-type1`, ...
                  The click lands on the cell under the cursor, and Blizzard's own secure code
                  does the casting. An addon may not cast; it may only say what a click means.

    the wheel     NOT a click a button can take. It is a BINDING, so it goes through a hidden
                  secure action button holding `/cast [@mouseover] <spell>` and
                  SetOverrideBindingClick("MOUSEWHEELUP", ...). Hover a cell, turn the wheel, and
                  the macro's [@mouseover] picks the unit. The TBC pyramid has done it this way
                  since September; the API is on Forever too (measured).

  EVERY BIND IS SET OUT OF COMBAT. Secure attributes and override bindings are both refused once
  the lockdown is on, so changes made mid-fight are queued and applied when it lifts - the same
  rule the grid's layout already follows.
]]
local ADDON, NS = ...
NS = NS or {}

local FM = {}
NS.FM = FM

-- Where each slot sits on the drawing, and what the client calls it.
--   attr   the secure attribute suffix for a click (nil = the wheel, which is a binding)
--   bind   the binding name for the wheel
-- Laid out like the thing in your hand: the two big buttons across the top, the wheel between
-- them, the middle click UNDER the wheel (because that is what pressing it is), and the two thumb
-- buttons down the left flank.
FM.SLOTS = {
    { key = "left",      label = "Left click",  attr = 1, x = -34, y =  52 },
    { key = "right",     label = "Right click", attr = 2, x =  34, y =  52 },
    { key = "wheelup",   label = "Wheel up",    bind = "MOUSEWHEELUP",   x = 0, y =  66 },
    { key = "wheeldown", label = "Wheel down",  bind = "MOUSEWHEELDOWN", x = 0, y =  40 },
    { key = "middle",    label = "Wheel click", attr = 3, x =   0, y =  10 },
    { key = "button4",   label = "Thumb 1",     attr = 4, x = -46, y = -22 },
    { key = "button5",   label = "Thumb 2",     attr = 5, x = -46, y = -46 },
}

FM.MODS = { { key = "", label = "no modifier" }, { key = "shift-", label = "shift" },
            { key = "ctrl-", label = "ctrl" }, { key = "alt-", label = "alt" } }

--- The binds live in SavedVariables when there are any. Before the DB exists - this file loads
--- before BiSHealing.lua, and a harness has no SavedVariables at all - they live in one table
--- here. Without that fallback every call made a FRESH table, so a bind was written to one and
--- read from another: set it, apply it, get nothing, with no error anywhere. The suite caught it.
-- What a fresh install already knows. The mouse owns EVERY click meaning: the grid used to set
-- these itself, and then applying an empty bind list wiped them - a grid with no click-casting at
-- all, silently. One owner, seeded once.
--
-- ONE LIST PER CLASS, and it is the only class-shaped thing in the addon. Everything else asks
-- the client what this character can do; a fresh install cannot, because "what would you like on
-- the left button" has no answer until you have dragged one. So each healer gets the two or three
-- spells they would have dragged first, and anyone else gets nothing rather than a guess.
--
-- These are courtesies, not opinions. Drag over them and they are gone.
FM.CLASS_DEFAULTS = {
    SHAMAN  = { left = "Healing Wave",    right = "Lesser Healing Wave", ["shift-left"] = "Chain Heal" },
    PRIEST  = { left = "Greater Heal",    right = "Flash Heal",          ["shift-left"] = "Renew" },
    PALADIN = { left = "Holy Light",      right = "Flash of Light",      ["shift-left"] = "Cleanse" },
    DRUID   = { left = "Healing Touch",   right = "Regrowth",            ["shift-left"] = "Rejuvenation" },
}

--- What this character starts with - AND ONLY WHAT THEY HAVE ACTUALLY TRAINED.
---
--- Arn, 19 Sep, at level something on a fresh shaman: "it setts it back to chain heals which i
--- dont have yet". A default is a courtesy; a default for a spell you cannot cast is a button
--- that does nothing and a line of red text when you press it. The spellbook is asked, and
--- anything not in it is left out.
---
--- `booked` comes back false when the book answered nothing at all - a real possibility at login,
--- before the client has filled it in - and the caller uses that to try again later rather than
--- writing an empty mouse down as "seeded".
function FM.Defaults()
    local class
    if UnitClass then
        local ok, _, token = pcall(UnitClass, "player")
        if ok then class = token end
    end
    local list = FM.CLASS_DEFAULTS[class or ""] or {}
    local out, booked = {}, false
    for slot, spell in pairs(list) do
        local ranks = FM.Ranks(spell)
        if #ranks > 0 then
            -- WITH THE RANK ON IT, the highest trained. A bare name casts your biggest rank
            -- anyway, so this changes nothing about what the button does - but it puts a number
            -- in the corner of the slot, and that number is the button you click to walk down to
            -- a cheaper rank. Seeded bare, the slot has nothing to click and the one feature this
            -- addon is FOR is invisible until you drag something yourself. (19 Sep 2026: Arn's
            -- first working login showed "Healing Wave" with no rank. Healium shipped the same
            -- decision the same day - "menu selections now track the highest learned rank;
            -- drag-and-drop can assign a specific lower rank" - which is a good sign it is right.)
            out[slot] = FM.Cast(spell, ranks[#ranks].rank)
            booked = true
        end
    end
    return out, booked
end

-- kept as a name because the suite and the options window both ask what a fresh install believes
FM.DEFAULTS = setmetatable({}, { __index = function(_, k) return FM.Defaults()[k] end })

local memory = { binds = {} }
local function db()
    local d = (NS.DB and NS.DB()) or _G.BiSHealingDB
    if type(d) ~= "table" then
        if not memory.seeded then
            for k, v in pairs(FM.Defaults()) do memory.binds[k] = v end
            memory.seeded = true
        end
        return memory
    end
    -- The binds live at the top of the table now. They used to sit under `d.forever`, from the
    -- days when this was the Forever half of another addon; Core.lua's migration carries them.
    d.binds = type(d.binds) == "table" and d.binds or {}
    if next(memory.binds) and not next(d.binds) then
        d.binds = memory.binds                -- carry anything bound before the DB arrived
    end
    -- SEEDED ONCE, AND ONLY INTO AN EMPTY MOUSE.
    --
    -- It used to fill any slot that happened to be nil, which meant clearing a bind and reloading
    -- brought it back - the addon quietly overruling a deliberate act. "the binds are not surving
    -- a reload it setts it back to chain heals": the saved variables were fine all along (the
    -- file on disk had his ranks in it), this was the seeding writing over the gaps.
    --
    -- So: only when there is nothing bound at all, and only spells the spellbook confirms. If the
    -- book answered nothing - which can happen at login, before the client has filled it in - the
    -- flag is NOT set, and the next call tries again rather than writing an empty mouse down as
    -- done forever.
    -- THE MACRO FIRST, then the defaults. On a client that hands back no saved variables the
    -- class default is not a courtesy, it is a bully: it lands on left click at every single
    -- login, and a player who wants the spell on their wheel has to drag it back every time.
    -- Arn, twice in ten minutes - "it did it to left click i put it back on mousewheel", then
    -- "reloaded and it put it back on left click". Asking Keep first means a remembered bind
    -- makes the mouse non-empty, and seeding never runs at all.
    if not FM.asked and not next(d.binds) then
        if NS.FK and NS.FK.Ready and NS.FK.Ready() then
            FM.asked = true                    -- the api answered, so once is enough
            local kept, settings = nil, nil
            if NS.FK.Load then kept, settings = NS.FK.Load() end
            if type(kept) == "table" then for k, v in pairs(kept) do d.binds[k] = v end end
            -- AND THE SIZE, which rides in the same macro because it would not survive a restart
            -- anywhere else on this client. Applied WITHOUT saving: writing back to the macro in
            -- the middle of reading it would store a half-restored mouse.
            if type(settings) == "table" and settings.scale then
                d.scale = settings.scale
                if NS.FG and NS.FG.SetScale then NS.FG.SetScale(settings.scale, true) end
            end
            -- the number and the colour ride the same way; the next paint picks them up
            if type(settings) == "table" then
                if settings.text then d.text = settings.text end
                if settings.color then d.color = settings.color end
                -- and where the grid was, and whether it was hidden: Arn, 21 Sep, "when i log on
                -- it puts the frames back in the center". Pinned by the centre, as it was saved.
                if type(settings.pos) == "table" then
                    d.gridPos = { point = "CENTER", rel = "CENTER", x = settings.pos.x, y = settings.pos.y }
                    if NS.FG and NS.FG.RestorePos and not (InCombatLockdown and InCombatLockdown()) then
                        NS.FG.RestorePos()
                    end
                end
                -- heals over time switched off: forget the containers' fingerprint and lay out again
                -- (after the one in progress), so every cell is rebuilt without them
                if settings.hots == false then
                    d.hots = false
                    if NS.FA then NS.FA.sig = nil end
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
                end
                -- clicks handed to Clique: the relayout clears ours and registers every cell
                if settings.clique == true then
                    d.clique = true
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
                end
                if settings.hidden then
                    d.shown = false
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end   -- refuses in combat; the
                end                                                      -- grid's own retry obeys
            end
        end
    end
    if not d.bindsSeeded and not next(d.binds) then
        local defaults, booked = FM.Defaults()
        for k, v in pairs(defaults) do d.binds[k] = v end
        if booked then d.bindsSeeded = true end
    end
    return d
end

--- The rank of a spell id, as the client words it: "Rank 4". Asked for separately from the name
--- because THE NAME PATH NEVER CARRIES IT. Arn, 19 Sep, after the rank went in: "the rank is
--- still not showing in the mouse keybind thing". GetCursorInfo hands back (spellBookIndex,
--- "spell", spellID); the code asked the LAST number first, which is the id, and the id answers
--- a name and nothing else. C_Spell.GetSpellSubtext is the one call on this client that answers
--- the rank for an id, and it was never asked.
function FM.RankOf(id)
    if type(id) ~= "number" then return nil end
    if C_Spell and C_Spell.GetSpellSubtext then
        local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
        if ok and type(sub) == "string" and sub ~= "" then return sub end
    end
    if GetSpellSubtext then
        local ok, sub = pcall(GetSpellSubtext, id)
        if ok and type(sub) == "string" and sub ~= "" then return sub end
    end
    return nil
end

--- A name and a rank for one number, from whichever call this client answers.
function FM.NameOf(n)
    local name, rank
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        local ok, nm, sub = pcall(C_SpellBook.GetSpellBookItemName, n)
        if ok and type(nm) == "string" and nm ~= "" then name, rank = nm, sub end
    end
    if not name and GetSpellInfo then              -- classic: name, rank, icon, ...
        local ok, nm, sub = pcall(GetSpellInfo, n)
        if ok and type(nm) == "string" and nm ~= "" then name, rank = nm, sub end
    end
    if not name and C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, n)
        if ok and info then
            if type(info) == "table" then name, rank = info.name, info.subtext or info.rank
            elseif type(info) == "string" then name = info end
        end
    end
    if name and (type(rank) ~= "string" or rank == "") then rank = FM.RankOf(n) end
    if type(rank) ~= "string" or rank == "" then rank = nil end
    return name, rank
end

--- What the cursor is holding: a cast string, plus the name and rank behind it. Nil for anything
--- that is not a spell.
function FM.CursorSpell()
    if not GetCursorInfo then return nil end
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return nil end

    -- The clients disagree about what comes back, and Forever disagrees with both: it hands
    -- (kind, spellBookIndex, "spell", spellID) and its C_SpellBook.GetSpellBookItemName takes ONE
    -- argument, not two - "bad argument #1 (not a numerical value)" when handed the old pair.
    local numbers = {}
    for _, v in ipairs({ a, b, c }) do
        if type(v) == "number" then numbers[#numbers + 1] = v end
    end

    -- PREFER THE ANSWER WITH A RANK. The old loop returned the first number that gave a name,
    -- which is the spell id, which never gives a rank - so every drop bound a bare name and every
    -- slot looked the same whatever you dropped on it. Now each number is asked, and a name with
    -- a rank wins over a name without one; the plain name is the fallback, not the answer.
    local plain
    for i = #numbers, 1, -1 do
        local name, rank = FM.NameOf(numbers[i])
        if name and name ~= "" then
            FM.lastDrop = { numbers = numbers, name = name, rank = rank, from = numbers[i] }
            if rank then return FM.Cast(name, rank), name, rank end
            plain = plain or name
        end
    end
    if plain then return FM.Cast(plain), plain, nil end
    return nil
end

--- What goes into the secure attribute. "Healing Wave(Rank 3)" is what the client understands,
--- and what a macro would say; a bare name means max rank, which is a different spell in practice.
function FM.Cast(name, rank)
    if not name or name == "" then return nil end
    if type(rank) == "string" and rank:match("%d") then return name .. "(" .. rank .. ")" end
    return name
end

--- Split a stored bind back into its parts, for showing it.
function FM.Split(cast)
    if type(cast) ~= "string" then return nil, nil end
    local name, rank = cast:match("^(.-)%((.-)%)$")
    if name then return name, rank end
    return cast, nil
end

--- The spell the grid asks about when it wants to know who is reachable: whatever is on the left
--- button, without its rank - a rank has no bearing on range, and "Healing Wave(Rank 3)" is a
--- cast string, not a spell name the range call would recognise.
---
--- This is why the grid holds no spell names at all now. The range that matters is the range of
--- the thing your click would actually cast, which is a different spell for every class and a
--- different spell again when you drag something new onto the mouse.
function FM.RangeSpell()
    local cast = FM.Get("", "left") or FM.Get("", "right")
    if not cast then return nil end
    return (FM.Split(cast))
end

--- EVERY RANK OF A SPELL THIS CHARACTER KNOWS, oldest first, by walking the spellbook.
---
--- Arn, 19 Sep: "did not let me do different rank on modifier and shift modifier". Dropping a
--- lower rank assumes the spellbook is showing you one to drag, and that is a setting - on a
--- book showing max ranks only there is nothing to drag and no way to say what you meant.
---
--- So the window stops depending on the drag for this: bind the spell once, then click the rank.
--- The list comes from the book itself, so it is exactly what this character has trained.
function FM.Ranks(name)
    if not name or name == "" then return {} end
    local out, seen = {}, {}
    local function add(nm, rank, id)
        if nm ~= name then return end
        local key = tostring(rank or "")
        if seen[key] then return end
        seen[key] = true
        out[#out + 1] = { rank = (type(rank) == "string" and rank ~= "") and rank or nil, id = id }
    end

    -- THE MODERN BOOK TAKES TWO ARGUMENTS: the slot, and which bank it is in. Measured in game
    -- on 1.60.1.69913, 19 Sep 2026, after this function had been answering "no ranks" forever:
    --
    --   C_SpellBook.GetSpellBookItemName(1)     -> error: bad argument #1 (not a numerical value)
    --   C_SpellBook.GetSpellBookItemName(1, 0)  -> "Attack"
    --
    -- Called with one argument it errors on EVERY slot. The pcall caught that and the loop just
    -- kept going, so the list came back empty and stayed empty - and three separate things
    -- quietly did nothing: the class defaults were never seeded (a blank mouse at every login),
    -- the rank button had nothing to walk through, and the binder showed no ranks. Arn reported
    -- all three as separate complaints over two days. One missing argument.
    --
    -- It swallowed its own cause, which is the lesson: a pcall around a call whose SIGNATURE you
    -- are guessing turns "I am calling this wrong" into "the client has nothing", and those two
    -- look identical from here. The suite could not catch it either, because the mock answered
    -- the one-argument call - it refuses it now.
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        for i = 1, 500 do
            local got, nm, sub = pcall(C_SpellBook.GetSpellBookItemName, i, bank)
            if got and type(nm) == "string" and nm ~= "" then add(nm, sub, i) end
        end
    end
    -- the old book: (index, bookType), and a count per tab
    if #out == 0 and GetSpellBookItemName and GetNumSpellTabs then
        for i = 1, 500 do
            local got, nm, sub = pcall(GetSpellBookItemName, i, "spell")
            if got and type(nm) == "string" and nm ~= "" then add(nm, sub, i) end
        end
    end
    return out
end

--- Put the next rank of whatever is in this slot into this slot. Wraps, so clicking it enough
--- times comes back to where it started - which is what makes it safe to click without reading.
function FM.CycleRank(mod, slotKey)
    local cast = FM.Get(mod, slotKey)
    if not cast then return nil end
    local name, rank = FM.Split(cast)
    local ranks = FM.Ranks(name)
    if #ranks < 2 then return cast end            -- one rank, or a spell that has none
    local at = 1
    for i, r in ipairs(ranks) do
        if r.rank == rank then at = i break end
    end
    local nextRank = ranks[(at % #ranks) + 1]
    local new = FM.Cast(name, nextRank and nextRank.rank)
    FM.Set(mod, slotKey, new)
    return new
end

--- Remember a bind. Returns the spell, or nil and why not.
--- Written to the macro as well as the table, because the table does not survive this client.
--- A refusal is not an error here: in combat the client will not make a macro, and the next
--- change out of combat writes the whole mouse anyway - there is no half-saved state to repair.
local function keep(d)
    FM.touched = true              -- a deliberate act, never to be thrown away by us
    if NS.FK and NS.FK.Save then NS.FK.Save(d.binds) end
end

--- The macro list is not always populated the moment we first ask. If it filled in late, what
--- is on the mouse now is OUR guess - the class defaults - and the player's real binds are
--- sitting in a macro we have already stopped asking about. Worse, the next spell they drag
--- would write the guess over them.
---
--- So: when the client says the macros changed, throw away a mouse that only we put there and
--- ask again. Never a mouse the player has touched - FM.touched is the difference between our
--- guess and their act, and their act wins every time.
function FM.Reconsider()
    local d = db()
    if FM.touched then return false end
    if not d.bindsSeeded then return false end
    for k in pairs(d.binds) do d.binds[k] = nil end
    d.bindsSeeded, FM.asked = nil, false
    db()                           -- asks the macro first, seeds again only if it is empty
    return true
end

function FM.Set(mod, slotKey, spell)
    if type(spell) ~= "string" or spell == "" then return nil, "not a spell" end
    local d = db()
    d.binds[(mod or "") .. slotKey] = spell
    keep(d)
    return spell
end

function FM.Get(mod, slotKey)
    return db().binds[(mod or "") .. slotKey]
end

function FM.Clear(mod, slotKey)
    local d = db()
    d.binds[(mod or "") .. slotKey] = nil
    keep(d)
end

--- Write every click bind onto one cell. OUT OF COMBAT ONLY: SetAttribute on a secure frame is
--- refused inside the lockdown, so this answers false there and the caller tries again later.
---
--- AN EMPTY BUTTON TARGETS. Arn, 22 Sep 2026, from a player's request: "if a key is not bound to
--- anything on the mouse that defaults to target". A click with nothing on it used to do nothing
--- at all; now it selects the person, the way Blizzard's own frames do - through the client's
--- built-in "target" action, which is secure and so works in a fight too. The wheel is not a
--- click on the cell (FM.ApplyWheel) and is untouched: an empty wheel still zooms the camera.
---
--- LET CLIQUE HAVE THEM. Arn, 22 Sep: "im a clique user and it uses all of theirs". Two addons
--- writing what a click means onto the same frame is a race - whichever wrote last wins, and that
--- changes with every layout. So it is ONE OWNER, by the player's switch (d.clique):
---   on   our click attributes are cleared, the wheel is let go, and the cell is registered in
---        ClickCastFrames - the shared list Clique (and Clicked, oUF, Healium) use. Clique then
---        owns every click, key and wheel turn on the grid.
---   off  the cell is unregistered and our binds go back on. With `= nil`, not `= false`: Clique
---        (v5.1, core.lua CaptureGlobalRegistry) takes nil and false alike as "unregister" once it
---        has loaded, but a frame already in the list when it loads is registered WHATEVER its
---        value - a `false` left behind before Clique arrived would register the cell anyway.
--- Registration is the documented `ClickCastFrames[frame] = true`; the table is made only when no
--- click-cast addon has made it yet, never written over (see the Blizzard-global test).
function FM.CliqueOn()
    local d = NS.DB and NS.DB()
    return type(d) == "table" and d.clique == true
end

local function cliqueRegister(cell, on)
    if on then
        if not ClickCastFrames then ClickCastFrames = {} end
        ClickCastFrames[cell] = true
        cell.__clique = true
    elseif cell.__clique then
        if ClickCastFrames then ClickCastFrames[cell] = nil end
        cell.__clique = nil
    end
end

function FM.ApplyTo(cell)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not cell or not cell.SetAttribute then return false end
    if FM.CliqueOn() then
        -- clear everything of ours first, so nothing of ours is left for Clique to fight
        for _, slot in ipairs(FM.SLOTS) do
            if slot.attr then
                for _, m in ipairs(FM.MODS) do
                    local prefix = m.key == "" and "*" or m.key
                    cell:SetAttribute(prefix .. "type" .. slot.attr, nil)
                    cell:SetAttribute(prefix .. "spell" .. slot.attr, nil)
                end
            end
        end
        cliqueRegister(cell, true)
        return true, 0
    end
    cliqueRegister(cell, false)
    local n = 0
    for _, slot in ipairs(FM.SLOTS) do
        if slot.attr then
            for _, m in ipairs(FM.MODS) do
                local spell = FM.Get(m.key, slot.key)
                local prefix = m.key == "" and "*" or m.key
                cell:SetAttribute(prefix .. "type" .. slot.attr, spell and "spell" or "target")
                cell:SetAttribute(prefix .. "spell" .. slot.attr, spell or nil)
                if spell then n = n + 1 end
            end
        end
    end
    return true, n
end

--- The wheel, which no button can take as a click: one hidden secure action button per direction
--- and modifier, holding a macro that aims at whatever the cursor is over.
local wheelButtons = {}

function FM.ApplyWheel(owner)
    if InCombatLockdown and InCombatLockdown() then return false end
    owner = owner or (NS.FG and NS.FG.anchor) or UIParent
    if ClearOverrideBindings then pcall(ClearOverrideBindings, owner) end
    if FM.CliqueOn() then return true, 0 end      -- Clique owns the wheel too: let it go
    local n = 0
    for _, slot in ipairs(FM.SLOTS) do
        if slot.bind then
            for _, m in ipairs(FM.MODS) do
                local spell = FM.Get(m.key, slot.key)
                local name = "BiSHealWheel" .. m.key:gsub("%-", "") .. slot.key
                local b = wheelButtons[name]
                if spell and not b then
                    b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
                    b:RegisterForClicks("AnyDown")
                    wheelButtons[name] = b
                end
                if b then
                    b:SetAttribute("type", spell and "macro" or nil)
                    -- [@mouseover] is what makes a wheel turn land on the cell under the cursor;
                    -- the stopmacro keeps it quiet when the cursor is over nothing healable.
                    b:SetAttribute("macrotext", spell and
                        ("/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]\n/cast [@mouseover] " .. spell)
                        or nil)
                end
                if spell and SetOverrideBindingClick then
                    local key = (m.key == "" and "" or m.key:upper():gsub("%-", "-")) .. slot.bind
                    pcall(SetOverrideBindingClick, owner, true, key, name, "LeftButton")
                    n = n + 1
                end
            end
        end
    end
    return true, n
end

--- Push every bind onto every cell and the wheel. Queued when the fight is on.
function FM.Apply()
    if InCombatLockdown and InCombatLockdown() then
        FM.pending = true
        return false
    end
    FM.pending = false
    local cells = 0
    for _, cell in ipairs((NS.FG and NS.FG.frames) or {}) do
        if FM.ApplyTo(cell) then cells = cells + 1 end
    end
    FM.ApplyWheel()
    return true, cells
end
