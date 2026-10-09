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
            local kept, settings = nil, nil
            if NS.FK.Load then kept, settings = NS.FK.Load() end
            -- ASKED ONLY ONCE THE LIST IS IN. Before it arrives "no macro" is not an answer, and
            -- taking it for one seeded the class defaults - which the next save then wrote over
            -- the real macro (Arn's, 22 Sep: a grid position and no binds). So until Keep says
            -- the list is in, this asks again, and seeds nothing.
            FM.asked = NS.FK.read and true or false
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
                -- the gold ring's cell and the out-of-range dim (7 Oct); the next paint shows both
                if settings.ring then d.ring = settings.ring end
                if settings.dim then d.dim = settings.dim end
                if settings.hover ~= nil then d.hover = settings.hover end
                -- the three a player asked for on 23 Sep, all of them the layout's business
                if settings.layout then d.layout = settings.layout end
                if settings.target == true then
                    d.target = true
                    if settings.targetAt then d.targetAt = settings.targetAt end
                    if settings.targetPos then d.targetPos = settings.targetPos end
                    d.tot = settings.tot == true      -- the cell beside it, from the same row
                end
                -- and your own cell, which is a row of its own: it has nothing to do with the
                -- target block and a player may want one without the other
                -- BiS> NOW, which never came back at all until 5 Oct 2026. The block, the side it
                -- sits on, where it was dragged, and the order its buttons are in - including which
                -- had been EARNED, because a button's id only appears in that list once something
                -- happened to earn it. Without this the whole feature started again every login.
                if settings.now == true then
                    d.now = true
                    if settings.nowAt then d.nowAt = settings.nowAt end
                    if settings.nowPos then d.nowPos = settings.nowPos end
                    if settings.nowOrder and NS.FN and NS.FN.Decode then
                        NS.FN.Decode(settings.nowOrder)
                    end
                end
                -- the pets, which never used to come back at all
                if settings.pets then
                    d.pets = settings.pets
                    if settings.petAt then d.petAt = settings.petAt end
                    if settings.petPos then d.petPos = settings.petPos end
                end
                if settings.mana == true then
                    d.mana = true
                    if settings.manaAt then d.manaAt = settings.manaAt end
                    if settings.manaPos then d.manaPos = settings.manaPos end
                end
                if settings.me == true then
                    d.me = true
                    if settings.meAt then d.meAt = settings.meAt end
                    if settings.mePos then d.mePos = settings.mePos end
                end
                if settings.markers then
                    d.markers = settings.markers
                    if NS.FA then NS.FA.sig = nil end
                end
                if settings.layout or settings.target or settings.markers then
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
                end
                -- clicks handed to Clique: the relayout clears ours and registers every cell
                if settings.clique == true then
                    d.clique = true
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end
                end
                -- THE BUFF-DROP SOUND, both halves. `quiet` is only set when the macro carries an
                -- N row at all, so a player who never touched it is left alone - and the sounds
                -- are registered again right here rather than waited for, because one that only
                -- arms itself at the next SPELLS_CHANGED is one that misses the first pull.
                if settings.quiet ~= nil then
                    d.buffQuiet = settings.quiet and true or false
                    d.buffSound = settings.sound
                    if NS.FS and NS.FS.Sounds then NS.FS.Sounds() end
                end
                -- the buff watched on the GROUP, by name. Only set when the macro carries a U row,
                -- so a player who never chose one keeps the default of watching nothing.
                if type(settings.groupBuff) == "string" and settings.groupBuff ~= "" then
                    d.groupBuff = settings.groupBuff
                end
                if settings.hidden then
                    d.shown = false
                    if NS.FG and NS.FG.Layout then NS.FG.Layout() end   -- refuses in combat; the
                end                                                      -- grid's own retry obeys
            end
            -- CARRIED OVER FROM THE SHARED MACRO, once: the binds came from the old General one,
            -- so they are written into this character's own now, and the old one is left alone
            -- for the player to delete - it is theirs, and it may hold another character's mouse.
            if NS.FK.adopted then
                NS.FK.adopted = nil
                local wrote = NS.FK.Save and NS.FK.Save(d.binds)
                if NS.Print then
                    NS.Print(wrote and "your binds now live in this character's own BiSHealing macro."
                        .. " The old one in General Macros is no longer used - delete it whenever you like."
                        or "your binds were read from the shared BiSHealing macro in General Macros;"
                        .. " they move to this character's own at the next change out of combat.")
                end
            end
        end
    end
    -- a save that came before the list was in, now it is
    if NS.FK and NS.FK.pending and NS.FK.read and FM.asked then NS.FK.Save(d.binds) end
    -- SEEDED ONLY AFTER THE MACRO WAS ASKED: defaults written in before then were the empty mouse
    -- that got saved over a real one
    if FM.asked and not d.bindsSeeded and not next(d.binds) then
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

--- A PING AS A BIND (1 Oct 2026, Arn's design: "they would have the buttons on the mouse bind
--- window and its just drag and drop to the buttons").
---
--- `C_Ping.SendMacroPing` is forbidden to addon code - measured with `/bish ping`, which came back
--- with no Lua error at all and an ADDON_ACTION_FORBIDDEN naming us. But a secure button may hold
--- a MACRO, and a macro is Blizzard's code running Blizzard's own `/ping`, which this client has
--- (`SlashCmdList.PING`). So the one road that is open is the one the wheel already drives on:
--- `FM.ApplyWheel` has been putting `/target [@mouseover]` on hidden secure buttons for a fortnight.
---
--- Stored like a spell so every existing road still works - the macro that keeps your binds, the
--- trimmer, Set/Get/Clear - but MARKED, so nothing mistakes one for something castable. A bind is
--- "!ping:assist"; a spell can never collide with that, because no spell name begins with "!".
FM.PING_MARK = "!ping:"
--- `subject` is the name in the client's own `Enum.PingSubjectType`, which is how the art is found:
--- `C_Ping.GetTextureKitForType` turns the type into a kit word ("Assist", "OnMyWay") and the atlas
--- is `Ping_Chat_<kit>`. Measured 1 Oct 2026 by listing every atlas with "ping" in its name
--- (`C_Texture.GetAtlasElements`), after five guessed suffixes all missed.
FM.PINGS = {
    { key = "assist",  word = "Assist",    subject = "Assist"  },
    { key = "attack",  word = "Attack",    subject = "Attack"  },
    { key = "warning", word = "Warning",   subject = "Warning" },
    { key = "onmyway", word = "On My Way", subject = "OnMyWay" },
}

--- The client's own icon for a ping, or nil - and nil is a real answer, not a failure. Not every
--- subject type even has a kit (ActionNotReady has none), and two of them share one, so anything
--- built on this has to cope with a missing icon rather than assume one per type.
---
--- `Ping_Chat_*` is the small one, meant for a line of chat: the right size for a 16-pixel chip
--- and a 30-pixel slot. The big world art is `Ping_GroundMarker_Pin_*`.
function FM.PingAtlas(key)
    local p
    for _, e in ipairs(FM.PINGS) do if e.key == key then p = e break end end
    if not p then return nil end
    local subject = Enum and Enum.PingSubjectType and Enum.PingSubjectType[p.subject]
    local kitOf = C_Ping and C_Ping.GetTextureKitForType
    if subject == nil or type(kitOf) ~= "function" then return nil end
    local got, kit = pcall(kitOf, subject)
    if not got or type(kit) ~= "string" or kit == "" then return nil end
    local atlas = "Ping_Chat_" .. kit
    local exists = C_Texture and C_Texture.GetAtlasExists
    if type(exists) == "function" then
        local okE, yes = pcall(exists, atlas)
        if not okE or not yes then return nil end
    end
    return atlas
end

--- The ping a bind means, or nil when it is an ordinary spell.
function FM.PingOf(cast)
    if type(cast) ~= "string" then return nil end
    local key = cast:match("^" .. FM.PING_MARK .. "(%w+)$")
    if not key then return nil end
    for _, p in ipairs(FM.PINGS) do if p.key == key then return key end end
    return nil
end

--- What to store for a ping, and what to call it on screen.
function FM.PingBind(key) return FM.PING_MARK .. tostring(key) end

function FM.PingWord(key)
    for _, p in ipairs(FM.PINGS) do if p.key == key then return p.word end end
    return tostring(key)
end

--- A SPELL THAT GOES OFF FIRST (8 Oct 2026). Arn: "finally got nature's swiftness ... when i press
--- down a button it pops it before my big heal". Each of these makes the NEXT heal better and is
--- off the global cooldown, so one press can cast it and then the heal - the classic two-line
--- macro. Dropped onto a slot that already holds a heal, it rides IN FRONT of that heal:
--- "Nature's Swiftness+Healing Wave(Rank 10)". Stored as one string, so the macro that keeps the
--- binds, Set/Get/Clear and the trimmer all carry it untouched. On cooldown, the first line fails
--- quietly and the heal still goes out.
FM.BOOSTERS = { ["Nature's Swiftness"] = true, ["Inner Focus"] = true, ["Divine Favor"] = true }
FM.BOOST_MARK = "+"

--- THE HEALS, READY TO DRAG (8 Oct 2026). Arn: "look at how fojjicore made a little box that tells
--- you these spells are not max rank, and you can drag and drop them on your bar ... show all the
--- healing spells max rank dragable to the binds". FojjiCore's rows call C_Spell.PickupSpell(id)
--- with the rank it wants, which puts that spell on the cursor; a bind slot already reads a spell
--- off the cursor WITH its rank. So the palette is a row of this character's healing spells, each
--- picked up at its highest trained rank. Per class, in the order a healer reaches for them; only
--- what the spellbook has trained is shown. (No "not max rank" warning on the binds: a healer
--- downranks on purpose, and the rank button is how.)
FM.PALETTE = {
    SHAMAN  = { "Healing Wave", "Lesser Healing Wave", "Chain Heal", "Nature's Swiftness",
                "Cure Poison", "Cure Disease", "Ancestral Spirit" },
    PRIEST  = { "Flash Heal", "Greater Heal", "Heal", "Lesser Heal", "Renew", "Prayer of Healing",
                "Power Word: Shield", "Inner Focus", "Dispel Magic", "Abolish Disease", "Resurrection" },
    DRUID   = { "Healing Touch", "Regrowth", "Rejuvenation", "Swiftmend", "Nature's Swiftness",
                "Remove Curse", "Abolish Poison", "Rebirth" },
    PALADIN = { "Holy Light", "Flash of Light", "Holy Shock", "Divine Favor", "Cleanse",
                "Lay on Hands", "Blessing of Protection", "Redemption" },
}
FM.PALETTE_MAX = 11                 -- what fits across the bind window

--- This character's palette: { name, id (the highest trained rank's), rank } in class order.
function FM.Palette()
    local class = UnitClass and select(2, UnitClass("player"))
    local out = {}
    for _, name in ipairs(FM.PALETTE[class or ""] or {}) do
        local ranks = FM.Ranks(name)
        local top = ranks[#ranks]
        if top and top.spell then
            out[#out + 1] = { name = name, id = top.spell, rank = top.rank }
            if #out >= FM.PALETTE_MAX then break end
        end
    end
    return out
end

--- The bind window's tip about boosters, or nil: said only while one is trained and no bind, on
--- any modifier, has one in front of it yet. Short enough for the header line.
FM.BOOST_SHORT = { ["Nature's Swiftness"] = "NS", ["Inner Focus"] = "Inner Focus",
                   ["Divine Favor"] = "Divine Favor" }
function FM.BoostTip(palette)
    local trained
    for _, s in ipairs(palette or FM.Palette()) do
        if FM.BOOSTERS[s.name] then trained = s.name break end
    end
    if not trained then return nil end
    for _, cast in pairs(db().binds or {}) do
        if FM.Boost(cast) then return nil end
    end
    return "drop " .. (FM.BOOST_SHORT[trained] or trained) .. " on a heal: it goes first"
end

--- Put a spell on the cursor, the way FojjiCore's rows do. Out of combat only, like every bind.
function FM.PickUp(id)
    if not id or (InCombatLockdown and InCombatLockdown()) then return false end
    local pick = (C_Spell and C_Spell.PickupSpell) or PickupSpell
    if not pick then return false end
    return (pcall(pick, id))
end

--- The booster riding in front of a bind, and the bind without it. (nil, cast) when there is none.
function FM.Boost(cast)
    if type(cast) ~= "string" then return nil, cast end
    local boost, rest = cast:match("^(.-)%+(.+)$")
    if boost and FM.BOOSTERS[boost] then return boost, rest end
    return nil, cast
end

--- A booster in front of a heal - or the heal alone when there is no booster.
function FM.WithBoost(boost, cast)
    if not boost or not cast then return cast end
    return boost .. FM.BOOST_MARK .. cast
end

--- Split a stored bind back into its parts, for showing it. A booster in front is not part of the
--- name: the name is the heal's, so its icon, its ranks and its range are the heal's.
function FM.Split(cast)
    if type(cast) ~= "string" then return nil, nil end
    local _, plain = FM.Boost(cast)
    cast = plain
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
--- AND ITS SPELL ID, because a NAME is not what this call wants. EllesmereUI passes ids
--- (`C_Spell.IsSpellInRange(361469, unit)`) and their notes say why it matters: a spell the call
--- cannot answer for "stranded Evoker frames at full alpha" - which is exactly what Arn reported
--- on 30 Sep, a raid with nobody dimmed.
---
--- Second return: ANY id this character has for the spell. Not the bound rank's - every rank of a
--- heal has the same range, so matching it was a branch with nothing behind it (a mutation that
--- removed it changed no answer, which is the test telling you the code is pretending). nil when
--- the book has not answered yet, and then the name is all there is to try.
function FM.RangeSpell()
    -- LEFT AND RIGHT FIRST, then ANYTHING BOUND. Arn, 30 Sep, with /bish range answering "range is
    -- measured with nothing": his heals live on the wheel and the thumb buttons, and nothing at
    -- all is on left or right click. This looked at those two and gave up - so the dimming has
    -- never once run for him, on any character, since the day it was written.
    --
    -- Any heal he has bound answers the range question about as well as any other: they are all
    -- 40 yards, and "can I reach them with what I cast" is the question either way. Left and right
    -- stay first because that is what the hand reaches for.
    -- A PING IS NOT A SPELL AND HAS NO RANGE (1 Oct 2026). Without this, binding a ping to left
    -- click would hand "!ping:assist" to the range call, which answers "don't know" for a spell it
    -- cannot find - read as "in range", so the whole raid stays bright. That is exactly the bug
    -- 0.7.2 and 0.7.5 were spent on, and it would have come back through a new door.
    local function spellAt(mod, key)
        local c = FM.Get(mod, key)
        if c and FM.PingOf(c) then return nil end
        return c
    end
    -- THE LONGEST REACH OF EVERY HEAL YOU KNOW (7 Oct 2026). Arn: "now that we know more about
    -- the client can we check all the healing spells and use that range the biggest one". Every
    -- spell bound (left and right first, then the rest), then the class's own heals, each asked
    -- for its maximum range; the longest wins, and a tie keeps the earlier - the one the hand
    -- reaches for. A spell the client calls NOT helpful is skipped: a damage spell on a bind has
    -- a range too, and it answers nil about a friend, which is "no answer" for the whole raid.
    local order, seen = {}, {}
    local function add(cast)
        if not cast then return end
        local name = FM.Split(cast)
        if name and not seen[name] then seen[name] = true order[#order + 1] = name end
    end
    add(spellAt("", "left")) add(spellAt("", "right"))
    for _, slot in ipairs(FM.SLOTS) do
        for _, m in ipairs(FM.MODS) do add(spellAt(m.key, slot.key)) end
    end
    -- select(2, ...), not `local _, class = UnitClass and UnitClass(...)`: `x and f()` keeps only
    -- f's FIRST return, so that line left `class` nil and no class heal was ever asked (7 Oct -
    -- the truncated-returns landmine, which the suite caught and bislint did not)
    local class = UnitClass and select(2, UnitClass("player"))
    -- in a FIXED order: `pairs` has none, and between two equal heals the winner would be chance
    local defaults = FM.CLASS_DEFAULTS[class or ""] or {}
    for _, k in ipairs({ "left", "right", "shift-left" }) do add(defaults[k]) end

    local best, bestID, bestRange
    for _, name in ipairs(order) do
        local id
        for _, r in ipairs(FM.Ranks(name) or {}) do if r.spell then id = r.spell break end end
        if id then
            local helpful = FM.Helpful(id)
            if helpful ~= false then
                local reach = FM.MaxRange(id) or 0
                if not bestRange or reach > bestRange then best, bestID, bestRange = name, id, reach end
            end
        end
    end
    -- the reach rides along third, so /bish range can show its working
    if best then return best, bestID, bestRange end
    -- the book has not answered yet (login): the first bound spell by name is all there is to try
    return order[1]
end

--- Is this spell one you cast on a friend? true / false, or nil when the client will not say.
function FM.Helpful(id)
    local f = C_Spell and C_Spell.IsSpellHelpful
    if not f then return nil end
    local ok, v = pcall(f, id)
    if not ok or (NS.Secret and NS.Secret(v)) then return nil end
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

--- A spell's maximum range in yards, or nil. C_Spell.GetSpellInfo answers a TABLE (`maxRange`);
--- the old global answered it as the 6th return - both shapes, as RezComm learned on 17 Sep.
function FM.MaxRange(id)
    local get = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    if not get then return nil end
    local ok, a, _, _, _, _, six = pcall(get, id)
    if not ok then return nil end
    local r = (type(a) == "table") and a.maxRange or six
    if NS.Secret and NS.Secret(r) then return nil end
    return type(r) == "number" and r or nil
end

--- EVERY RANK OF A SPELL THIS CHARACTER KNOWS, oldest first, out of the spellbook.
---
--- Arn, 19 Sep: "did not let me do different rank on modifier and shift modifier". Dropping a
--- lower rank assumes the spellbook is showing you one to drag, and that is a setting - on a
--- book showing max ranks only there is nothing to drag and no way to say what you meant.
---
--- So the window stops depending on the drag for this: bind the spell once, then click the rank.
--- The list comes from the book itself, so it is exactly what this character has trained.
---
--- THE BOOK IS READ ONCE AND KEPT (8 Oct 2026). This used to walk all 500 slots on every call,
--- and it is called a great deal: the grid asks FM.RangeSpell for every cell on every tick, which
--- asks here about every spell on the mouse; BiS> now asks FB.Knows on every tick as well. Arn's
--- own mouse in a 25-man came to 126 walks a tick - 630,000 questions a second about a book that
--- had not changed since login. His addon list said so before anything else did: "Current CPU
--- 6%" with the addon off or the cells hidden, "63%" with them shown.
---
--- So one walk fills `book.names` for every spell at once, and it is thrown away when:
---   * the client says the book changed (SPELLS_CHANGED, PLAYER_ENTERING_WORLD - FM.BookChanged)
---   * it is FM.BOOK_TTL seconds old, in case there is a way to learn a spell that fires neither
---   * it came back EMPTY, which is never kept: at login the client has not filled the book in
---     yet, and an empty answer remembered is a mouse with no defaults for the whole session
local book = {}
-- 60, not 5 (8 Oct 2026). Arn's /bish range: "read 70 times since login" - the 5 s net was the
-- only thing still reading it. Learning a spell fires SPELLS_CHANGED, which re-reads at once; the
-- net is for a way nobody has seen, and "at level 60 you stop learning spells anyways".
FM.BOOK_TTL = 60
FM.bookReads = 0          -- how many times the book has been walked; /bish range prints it

--- The real spell id behind a book slot, or nil. The same read SelfBuff.lua has always done.
function book.idAt(i, bank)
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemInfo) then return nil end
    local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
    local id = ok and type(info) == "table" and NS.Plain(info.spellID) or nil
    return type(id) == "number" and id or nil
end

-- `index` IS A BOOK SLOT AND `spell` IS A SPELL ID, and they are not the same number (1 Oct
-- 2026). This field was called `id` and held the slot, which read like a spell id to everything
-- that touched it - so three callers asked the client about the wrong thing entirely, and the
-- only reason it was ever noticed is that `/bish byid` printed the number: Arn's Water Shield
-- came back as "id 35", which is a row in his spellbook.
--
-- The one that had been wrong longest is the range check (0.7.2), which has been asking
-- IsSpellInRange about slot numbers ever since and quietly working off its name fallback - a
-- bug hidden by its own safety net. A field named for what it is cannot be misread that way.
function book.add(into, nm, rank, index, spell)
    -- a secret string refuses to be a table key, and a name we may not read is not one we can
    -- be asked about by name either
    if type(nm) ~= "string" or nm == "" or NS.Secret(nm) then return false end
    local e = into[nm]
    if not e then
        e = { ranks = {}, seen = {}, ids = {} }
        into[nm] = e
    end
    -- every id under the name, rank or no rank: a buff is a different id at every rank
    if type(spell) == "number" then e.ids[#e.ids + 1] = spell end
    local key = tostring(rank or "")
    if e.seen[key] then return true end
    e.seen[key] = true
    e.ranks[#e.ranks + 1] = { rank = (type(rank) == "string" and rank ~= "") and rank or nil,
                              index = index, spell = spell }
    return true
end

--- Walk the modern book once, every slot, into a table keyed by spell name.
function book.readModern()
    local names, n = {}, 0
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
        -- cost: once per SPELLS_CHANGED / PLAYER_ENTERING_WORLD, or every FM.BOOK_TTL s - kept between
        for i = 1, 500 do
            local got, nm, sub = pcall(C_SpellBook.GetSpellBookItemName, i, bank)
            if got and type(nm) == "string" and nm ~= "" then
                if book.add(names, nm, sub, i, book.idAt(i, bank)) then n = n + 1 end
            end
        end
    end
    return names, n
end

--- The old book: (index, bookType), and a count per tab. Only ever asked about a name the modern
--- book did not have, which is what the walk-per-call did too.
function book.readOld()
    local names, n = {}, 0
    if GetSpellBookItemName and GetNumSpellTabs then
        -- cost: only when the modern book came back empty, and kept with it (book.get)
        for i = 1, 500 do
            local got, nm, sub = pcall(GetSpellBookItemName, i, "spell")
            if got and type(nm) == "string" and nm ~= "" then
                if book.add(names, nm, sub, i, nil) then n = n + 1 end
            end
        end
    end
    return names, n
end

--- The book as last read, or read now. Second return: the old book's table, filled only when a
--- caller needs it (pass true).
function book.get(wantOld)
    local now = GetTime and GetTime()
    local fresh = book.names and now and book.at and (now - book.at) >= 0 and (now - book.at) < FM.BOOK_TTL
    if not fresh then
        local names, n = book.readModern()
        local old, m = nil, 0
        if n == 0 then old, m = book.readOld() end      -- a client with only the old book
        FM.bookReads = FM.bookReads + 1
        if (n + m) > 0 and now then
            book.names, book.old, book.at = names, old, now
        elseif book.names and now then
            -- IT ONLY GOT OLD, AND NOW THE CLIENT ANSWERS NOTHING. Nobody said the book changed
            -- (FM.BookChanged empties book.names, and then this branch is not reached) - the kept
            -- one just reached its age, and the re-read came back empty. A character does not
            -- unlearn every spell in silence; a client that has gone quiet mid-fight is the
            -- likelier story, and this addon keeps what it last knew when that happens. Asked
            -- again in another FM.BOOK_TTL, not on every call: that would be the old cost back
            -- at exactly the moment the client is busiest.
            book.at = now
        else
            -- empty with nothing kept, or no clock to age it by: never kept
            book.names, book.old, book.at = nil, nil, nil
            return names, old
        end
    end
    if wantOld and not book.old then book.old = (book.readOld()) end
    return book.names, book.old
end

--- The client said the book changed, or something that knows it did is telling us. Cheap: the
--- next question walks it again, and a hundred of these in a row cost one walk.
function FM.BookChanged()
    book.names, book.at, book.old = nil, nil, nil
end

do
    local okF, f = pcall(CreateFrame, "Frame")
    if okF and f then
        for _, e in ipairs({ "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD" }) do
            pcall(f.RegisterEvent, f, e)        -- an event this client does not know must not abort the file
        end
        f:SetScript("OnEvent", function() FM.BookChanged() end)
        FM.bookEvents = f
    end
end

--- A fresh list every time, never the kept one: a caller that sorted or trimmed it in place
--- would be rewriting the memory every other caller reads.
function FM.Ranks(name)
    if not name or name == "" then return {} end
    local names = book.get()
    local e = names and names[name]
    if not e and GetSpellBookItemName and GetNumSpellTabs then
        local _, old = book.get(true)
        e = old and old[name]
    end
    local out = {}
    if e then for i, r in ipairs(e.ranks) do out[i] = r end end
    return out
end

--- Every spell id this character has under a name, one per rank, from the same single read.
--- SelfBuff's FS.SpellIds and the HoT markers' FA.HotIds each walked the book for this themselves.
function FM.BookIds(name)
    local out = {}
    if not name or name == "" then return out end
    local names = book.get()
    local e = names and names[name]
    if e then for i, id in ipairs(e.ids) do out[i] = id end end
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
    -- the booster in front stays in front: stepping the heal's rank must not drop Nature's Swiftness
    local new = FM.WithBoost((FM.Boost(cast)), FM.Cast(name, nextRank and nextRank.rank))
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
    if NS.FK and NS.FK.MacrosArrived then NS.FK.MacrosArrived() end   -- the event means the list is in
    local d = db()
    if FM.touched then return false end
    if d.bindsSeeded then
        for k in pairs(d.binds) do d.binds[k] = nil end
    elseif next(d.binds) then
        return false                   -- binds that came from the macro are not a guess to throw away
    end
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
                    cell:SetAttribute(prefix .. "macrotext" .. slot.attr, nil)
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
                -- EMPTY 3-5 TARGET BY MACRO. Measured on the beta (22 Sep): the thumbs and the
                -- wheel click reach the cell - a bound spell casts - but an empty one set to type
                -- "target" does nothing; the SecureUnitButton path honours "target" for buttons 1
                -- and 2 only. So 1-2 keep the built-in action, and 3-5 get a secure macro that does
                -- the same thing through the one unit the cursor is on.
                local kind, text, cast = nil, nil, spell
                local ping = FM.PingOf(spell)
                if ping then
                    -- `[@mouseover]` IS THE WHOLE THING (measured 1 Oct 2026). Without it the ping
                    -- fires at wherever the cursor is in the WORLD, so clicking a person's cell
                    -- pings the floor at your feet - which Arn saw, and which is worse than no
                    -- button at all. The same condition the wheel binds have used all along:
                    -- "/target [@mouseover]". Arn confirmed by hand before a line of this changed.
                    kind, text, cast = "macro", "/ping [@mouseover] " .. ping, nil
                elseif spell and FM.Boost(spell) then
                    -- THE BOOSTER FIRST, THEN THE HEAL, in one press: a macro, aimed like the ping
                    -- at the cell under the cursor (a click on a cell makes it the mouseover)
                    -- the wheel's guard too, so the cooldown is never spent on a dead or hostile cell
                    local boost, heal = FM.Boost(spell)
                    kind, cast = "macro", nil
                    text = "/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]\n"
                        .. "/cast " .. boost .. "\n/cast [@mouseover] " .. heal
                elseif spell then kind = "spell"
                elseif slot.attr <= 2 then kind = "target"
                else kind, text = "macro", "/target [@mouseover]" end
                cell:SetAttribute(prefix .. "type" .. slot.attr, kind)
                cell:SetAttribute(prefix .. "spell" .. slot.attr, cast or nil)
                cell:SetAttribute(prefix .. "macrotext" .. slot.attr, text)
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
                    -- A PING ON THE WHEEL (1 Oct 2026). Arn: "the ping system we build does not
                    -- work with mouse wheel up or down". It could not: the wheel is not a click,
                    -- so it never goes through ApplyTo where ping binds are turned into /ping -
                    -- it comes here instead, and arrived as `/cast !ping:assist`, which casts
                    -- nothing. The wheel is where his heals live, so it is where a ping belongs.
                    --
                    -- The guard is narrower than the cast one: a ping may go at anything you can
                    -- see, friend or enemy, so only "nothing under the cursor" stops it. `nohelp`
                    -- would make Attack pings impossible on the one bind that matters most.
                    local ping = FM.PingOf(spell)
                    local text
                    if ping then
                        text = "/stopmacro [@mouseover,noexists]\n/ping [@mouseover] " .. ping
                    elseif spell then
                        -- [@mouseover] is what makes a wheel turn land on the cell under the
                        -- cursor; the stopmacro keeps it quiet when the cursor is over nothing
                        -- healable. A booster rides between the two: after the guard, so Nature's
                        -- Swiftness is never spent on a wheel turn over nobody.
                        local boost, heal = FM.Boost(spell)
                        text = "/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]\n"
                            .. (boost and ("/cast " .. boost .. "\n") or "")
                            .. "/cast [@mouseover] " .. heal
                    end
                    b:SetAttribute("macrotext", text)
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
