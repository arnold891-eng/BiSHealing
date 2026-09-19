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
FM.DEFAULTS = {
    ["left"]        = "Healing Wave",
    ["right"]       = "Lesser Healing Wave",
    ["shift-left"]  = "Chain Heal",
}

local memory = { binds = {} }
local function db()
    local d = (NS.DB and NS.DB()) or _G.BiSHealingDB
    if type(d) ~= "table" then
        if not memory.seeded then
            for k, v in pairs(FM.DEFAULTS) do memory.binds[k] = v end
            memory.seeded = true
        end
        return memory
    end
    d.forever = type(d.forever) == "table" and d.forever or {}
    d.forever.binds = type(d.forever.binds) == "table" and d.forever.binds or {}
    if next(memory.binds) and not next(d.forever.binds) then
        d.forever.binds = memory.binds        -- carry anything bound before the DB arrived
    end
    -- NOTE the table: `d` is the whole SavedVariables, `d.forever` is ours. Seeding into `d` read
    -- `d.binds`, which does not exist - "attempt to index field 'binds' (a nil value)" on every
    -- click. One letter of scope, one error per frame.
    local mine = d.forever
    if not mine.seeded then                   -- a fresh install gets the defaults, once
        for k, v in pairs(FM.DEFAULTS) do
            if mine.binds[k] == nil then mine.binds[k] = v end
        end
        mine.seeded = true
    end
    return mine
end

--- What the cursor is holding, as a spell name - or nil. The two clients disagree about what
--- GetCursorInfo hands back (a spellbook index on classic, a spell id on modern), so ask for the
--- name both ways rather than deciding from a build number.
function FM.CursorSpell()
    if not GetCursorInfo then return nil end
    local kind, a, b, c = GetCursorInfo()
    if kind ~= "spell" then return nil end

    -- The clients disagree about what comes back, and Forever disagrees with both: it hands
    -- (kind, spellBookIndex, "spell", spellID) and its C_SpellBook.GetSpellBookItemName takes ONE
    -- argument, not two - "bad argument #1 (not a numerical value)" when handed the old pair.
    -- So: collect the numbers, and try each way of turning a number into a name.
    local numbers = {}
    for _, v in ipairs({ a, b, c }) do
        if type(v) == "number" then numbers[#numbers + 1] = v end
    end

    -- Name AND RANK. On a 1.60 client a spell has ranks, and "/cast Healing Wave" always throws
    -- the biggest one you know - which for a healer is the difference between topping someone up
    -- and spending three times the mana to do it. The spellbook is the only source that hands the
    -- rank back: GetSpellBookItemName returns (name, subName) where subName is "Rank 3".
    local function nameOf(n)
        if C_SpellBook and C_SpellBook.GetSpellBookItemName then
            local ok, nm, sub = pcall(C_SpellBook.GetSpellBookItemName, n)
            if ok and nm and nm ~= "" then return nm, sub end
        end
        if GetSpellInfo then                       -- classic: name, rank, icon, ...
            local ok, nm, sub = pcall(GetSpellInfo, n)
            if ok and nm and nm ~= "" then return nm, sub end
        end
        if C_Spell and C_Spell.GetSpellInfo then
            local ok, info = pcall(C_Spell.GetSpellInfo, n)
            if ok and info then
                if type(info) == "table" then return info.name, info.subtext or info.rank end
                return info
            end
        end
        return nil
    end

    -- the LAST number is the spell id on the clients that send both; try it first
    for i = #numbers, 1, -1 do
        local name, rank = nameOf(numbers[i])
        if name and name ~= "" then return FM.Cast(name, rank), name, rank end
    end
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

--- Remember a bind. Returns the spell, or nil and why not.
function FM.Set(mod, slotKey, spell)
    if type(spell) ~= "string" or spell == "" then return nil, "not a spell" end
    local d = db()
    d.binds[(mod or "") .. slotKey] = spell
    return spell
end

function FM.Get(mod, slotKey)
    return db().binds[(mod or "") .. slotKey]
end

function FM.Clear(mod, slotKey)
    db().binds[(mod or "") .. slotKey] = nil
end

--- Write every click bind onto one cell. OUT OF COMBAT ONLY: SetAttribute on a secure frame is
--- refused inside the lockdown, so this answers false there and the caller tries again later.
function FM.ApplyTo(cell)
    if InCombatLockdown and InCombatLockdown() then return false end
    if not cell or not cell.SetAttribute then return false end
    local n = 0
    for _, slot in ipairs(FM.SLOTS) do
        if slot.attr then
            for _, m in ipairs(FM.MODS) do
                local spell = FM.Get(m.key, slot.key)
                local prefix = m.key == "" and "*" or m.key
                cell:SetAttribute(prefix .. "type" .. slot.attr, spell and "spell" or nil)
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
