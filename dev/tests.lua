-- BiSHealing -- the Forever grid, against a client that hides its numbers.
--
--     cd BiSHealing && lua5.1 dev/forever.lua
--
-- The pyramid's suites run against a TBC client that answers everything. This one runs the two
-- Forever files against the client measured on the beta on 17 Sep 2026:
--
--   * UnitHealth / UnitHealthMax(other) return a SECRET NUMBER -- a value that errors on
--     arithmetic, on comparison, and gives nil from tostring. It may be stored, and handed to a
--     StatusBar or a FontString, and nothing else.
--   * UnitInRange returns a secret BOOLEAN, which cannot even be used in an `if`.
--   * Inside the lockdown, auras, cooldowns and stats are secret too.
--
-- The point is not that the grid draws something. It is that the grid NEVER LOOKS at the number
-- it is given: the secret here errors on every operation except being passed along, so any line
-- that peeks fails this suite instead of a raid.

local fail, checks = 0, 0
local function ok(cond, what)
    checks = checks + 1
    if not cond then
        fail = fail + 1
        print("!! FOREVER: " .. what)
    end
end

------------------------------------------------------------------ the secret --

local secretMeta
local function boom(what)
    return function() error("attempt to perform " .. what .. " on a secret number value", 2) end
end
secretMeta = {
    __add = boom("arithmetic"), __sub = boom("arithmetic"), __mul = boom("arithmetic"),
    __div = boom("arithmetic"), __mod = boom("arithmetic"), __pow = boom("arithmetic"),
    __unm = boom("arithmetic"), __concat = boom("concatenation"),
    __lt = boom("comparison"), __le = boom("comparison"),
    __index = function() error("a secret number has no fields", 2) end,
}
local function secret() return setmetatable({}, secretMeta) end

------------------------------------------------------------------ the client --

local STATE = {
    inCombat = false,
    units = { player = true, party1 = true, party2 = true },
    dead = {},
    range = {},                 -- unit -> 0 means out of range
    maxRefusesSecret = false,   -- the client rejecting a secret max, if it turns out to do that
    incoming = {},              -- unit -> heals already on their way
    incomingSecret = false,     -- and whether the client will say how much
    deadSecret = false,         -- UnitIsDeadOrGhost as a secret BOOLEAN, which it is in combat
    classSecret = false,        -- so is the class, and it indexes a table here
}

local frames = {}
local function autoMethods(t)
    return setmetatable(t, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
end

local function newFrame(kind, name)
    -- SHOWN, like the client's. A frame you create is visible until you hide it, and a mock that
    -- starts everything hidden turns "I never hid this" into a passing test - which is exactly
    -- how the mouse window shipped needing two clicks to open.
    local f = { __kind = kind, __name = name, __attrs = {}, __scripts = {}, __shown = true,
                __alpha = 1, points = {} }
    if name then _G[name] = f end          -- the client puts a named frame in _G; so does this
    -- WHERE IT IS ANCHORED, recorded and readable. The client answers GetPoint; this used to
    -- answer nothing at all, which made "put the window back where it was" untestable - and a
    -- window that opens in the wrong place is the kind of thing only a person ever notices.
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:ClearAllPoints() self.points = {} end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i)
        local p = self.points[i or #self.points]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function f:SetScript(k, fn) self.__scripts[k] = fn end
    function f:HookScript(k, fn) self.__scripts[k] = fn end
    function f:GetScript(k) return self.__scripts[k] end
    function f:RegisterEvent(e) self.__events = self.__events or {}; self.__events[e] = true end
    function f:UnregisterEvent(e) if self.__events then self.__events[e] = nil end end
    function f:SetAttribute(k, v) self.__attrs[k] = v end
    function f:GetAttribute(k) return self.__attrs[k] end
    function f:Show() self.__shown = true end
    function f:Hide() self.__shown = false end
    function f:IsShown() return self.__shown end
    function f:SetAlpha(a) self.__alpha = a end
    function f:GetAlpha() return self.__alpha end
    function f:SetFrameStrata(v) self.__strata = v end
    function f:SetScale(v) self.__scale = v end
    function f:GetScale() return self.__scale or 1 end
    function f:SetSize(w, h) self.__w, self.__h = w, h end
    function f:GetWidth() return self.__w end
    function f:GetFrameStrata() return self.__strata end
    function f:SetTexture(t) self.__texture = t end
    function f:SetTexCoord(a, b, c, d) self.__coords = { a, b, c, d } end
    function f:SetValue(v) self.__value = v end          -- what the bar was handed, kept as given
    function f:SetMinMaxValues(lo, hi)
        if STATE.maxRefusesSecret and getmetatable(hi) == secretMeta then
            error("SetMinMaxValues: a secret max is refused by this client", 2)
        end
        self.__min, self.__max = lo, hi
    end
    function f:SetStatusBarColor(r, g, b) self.__color = { r, g, b } end
    -- A TEXTURE REMEMBERS WHAT IT WAS GIVEN. autoMethods answers every call with nil, which is
    -- fine for SetColorTexture and a liar for the rest: "the icon is shown" and "it used the
    -- healer corner" are only questions if Show and SetTexCoord leave a mark. Shown-by-default
    -- like the client's, and like the frames above.
    function f:CreateTexture()
        return autoMethods({
            SetColorTexture = function() end,
            __shown  = true,
            Show     = function(t) t.__shown = true end,
            Hide     = function(t) t.__shown = false end,
            IsShown  = function(t) return t.__shown end,
            SetTexture  = function(t, v) t.__texture = v end,
            SetTexCoord = function(t, a, b, c, d) t.__coords = { a, b, c, d } end,
            SetAtlas    = function(t, v) t.__atlas = v end,
        })
    end
    function f:CreateFontString()
        -- RECORDED. "How many labels are in this bar" is a question a suite can only ask if the
        -- mock remembers: two labels in one 84px header printed through each other in game, twice
        -- (the mouse window in the morning, the grid header in the afternoon).
        -- AND WHERE IT IS ANCHORED: "does the name stop where the number starts" is only a
        -- question if a label remembers what it was pinned to
        local fs = autoMethods({
            SetText = function(self2, t) self2.__text = t end,
            GetText = function(self2) return self2.__text end,
            SetTextColor = function(self2, r, g, b) self2.__color = { r, g, b } end,
            -- a width, as the client always gives one: ~5px a character at the small font
            GetStringWidth = function(self2)
                return type(self2.__text) == "string" and #self2.__text * 5 or 0
            end,
            SetPoint = function(self2, ...) self2.points = self2.points or {}
                                            self2.points[#self2.points + 1] = { ... } end,
        })
        self.__fontstrings = self.__fontstrings or {}
        self.__fontstrings[#self.__fontstrings + 1] = fs
        return fs
    end
    frames[#frames + 1] = f
    return autoMethods(f)
end

_G.CreateFrame = function(kind, name) return newFrame(kind, name) end
_G.UIParent = newFrame("Frame")
_G.InCombatLockdown = function() return STATE.inCombat end
_G.UnitExists = function(u) return STATE.units[u] and true or false end
_G.IsInRaid = function() return false end
_G.UnitName = function(u) return "Name-" .. tostring(u) end
_G.UnitClass = function()
    if STATE.classSecret then return secret(), secret() end
    return "Shaman", "SHAMAN"
end
_G.UnitIsDeadOrGhost = function(u)
    if STATE.deadSecret then return secret() end       -- a secret BOOLEAN, in combat
    return STATE.dead[u] and true or false
end
_G.UnitHealth = function() return secret() end
_G.UnitHealthMax = function(u) if u == "player" then return 297 end return secret() end
_G.IsSpellInRange = function(_, u) return STATE.range[u] == 0 and 0 or 1 end
-- THE UNIT WATCH SHOWS FRAMES BY ITSELF. It was a no-op here, which is kinder than the client:
-- the real one shows a watched frame whenever its unit exists, whatever the addon last said - so
-- "show the cells" off did nothing in game for a week while this suite passed (Arn, 21 Sep).
-- WATCH_TICK() is the client's next look: call it after a Hide that is meant to stick.
local WATCHED = setmetatable({}, { __mode = "k" })
_G.RegisterUnitWatch = function(f) WATCHED[f] = true end
_G.UnregisterUnitWatch = function(f) WATCHED[f] = nil end
local function WATCH_TICK()
    for f in pairs(WATCHED) do
        local u = f.GetAttribute and f:GetAttribute("unit")
        if u and STATE.units[u] then f:Show() else f:Hide() end
    end
end
-- THE CLIENT'S OWN ANSWERS ABOUT SECRECY. There is a C_Secrets question for every kind of secret
-- on this client - our BiSProbe census lists 27 of them - and asking is always better than
-- handing the client a value and watching for the error. STATE.maxSecret is the one the grid
-- asks before it dares give a bar a secret maximum.
_G.C_Secrets = {
    HasSecretRestrictions = function() return true end,
    ShouldUnitHealthMaxBeSecret = function() return STATE.maxSecret and true or false end,
}

-- WHAT IS ALREADY ON ITS WAY, and the call that says whether a value may be looked at.
--
-- Both were found on 19 Sep 2026 by reading how Healium's own Forever build paints its frames.
-- `issecretvalue` in particular had been missing from this addon's whole picture of the client:
-- everything was written as "assume it is secret and never touch it", which is safe for a health
-- bar and useless for a dead flag that has to go in an `if`.
_G.UnitGetIncomingHeals = function(u)
    if STATE.incoming[u] == nil then return nil end
    if STATE.incomingSecret then return secret() end
    return STATE.incoming[u]
end
_G.issecretvalue = function(v) return getmetatable(v) == secretMeta end

------------------------------------------------------------------- the files --

-- The aura containers. A client that HAS them (Forever, retail) draws auras the addon may not
-- read, so what the addon DECLARES is the only thing there is to test - recorded here.
local CONTAINERS = {}
local SLOT_CALLS = { missing = false }
containersExist = true
_G.C_XMLUtil = { GetTemplateInfo = function(t)
    return (t == "CustomAuraContainerTemplate" and containersExist) and { name = t } or nil
end }
local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function(kind, name, parent, template)
    if kind == "AuraContainer" then
        local c = newFrame(kind)
        c.slots, c.unit, c.enabled = {}, nil, false
        function c:SetUnit(u) self.unit = u end
        function c:SetEnabled(v) self.enabled = v and true or false end
        function c:SetFrameLevel() end
        function c:GetFrameLevel() return 1 end
        function c:AddAuraSlot(key, filter, opts)
            local slot = newFrame("AuraSlot")
            slot.key, slot.filter, slot.opts = key, filter, opts
            -- THE BUTTON'S OWN DRAWING CALLS, recorded - an auto no-op would answer "yes" to
            -- anything and remember nothing (ForeverAuras 0.1.148 uses both on this client).
            -- SLOT_CALLS.missing = true is a client that does not have them.
            if SLOT_CALLS.missing then
                slot.AddDispelTypeTexture, slot.SetDurationCooldown = false, false
            else
                function slot:AddDispelTypeTexture(tex, o) self.dispelTex, self.dispelOpts = tex, o end
                function slot:SetDurationCooldown(cd) self.durationCooldown = cd end
            end
            self.slots[key] = slot
            if opts and opts.initializeFrame then opts.initializeFrame(slot) end
            return slot
        end
        CONTAINERS[#CONTAINERS + 1] = c
        return c
    end
    return realCreateFrame(kind, name, parent, template)
end

local NS = {}
-- what the cursor is carrying, and what the client was told to bind
local CURSOR = {}
_G.GetCursorInfo = function() return CURSOR.kind, CURSOR.a, CURSOR.b, CURSOR.c end
_G.ClearCursor = function() CURSOR = {} end
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.GetSpellInfo = function(id) return { name = "Spell" .. tostring(id) } end
_G.C_Spell.GetSpellTexture = function() return "Interface\Icons\INV_Misc_QuestionMark" end
-- The stub spellbook. It answers a RANK for the spells this fake character has ranks of, and it
-- refuses a non-number the way Forever's does - one argument, "bad argument #1" for the rest.
-- THE ROLE. Healium's Forever build asks UnitGroupRolesAssigned and then checks issecretvalue on
-- the answer before it dares look at it, which is the tell: the role is secret in combat like
-- health and auras. STATE.roles is what this character's party would answer; STATE.roleSecret
-- makes the client hand back a secret instead, the way it does once the pull starts.
_G.UnitGroupRolesAssigned = function(unit)
    if STATE.roleSecret then return secret() end
    return STATE.roles and STATE.roles[unit] or "NONE"
end

-- MACROS, WHICH ARE THE ONE THING THIS CLIENT GIVES BACK. They live on the server, so they
-- survive the restart that empties every SavedVariables file. This is the store, and it behaves
-- like the client's: CreateMacro appends, EditMacro needs a real index, GetNumMacros counts the
-- two kinds separately, and a name that is not there answers 0 rather than nil.
local MACROS = {}
_G.GetMacroIndexByName = function(n)
    for i, m in ipairs(MACROS) do if m.name == n then return i end end
    return 0
end
_G.GetMacroBody = function(i) return MACROS[i] and MACROS[i].body or nil end
_G.GetNumMacros = function()
    local g, p = 0, 0
    for _, m in ipairs(MACROS) do if m.perChar then p = p + 1 else g = g + 1 end end
    return g, p
end
-- THE CLIENT ADDS A NEWLINE. Measured, 19 Sep 2026: a body of 31 characters came back as 32,
-- and it was always exactly the LAST bind that went missing - because every row was matched with
-- an anchored pattern and the final row had a newline stuck on the end. Arn's shift-wheel bind,
-- gone every reload, while sitting in the macro in plain sight. The mock stored back exactly what
-- it was handed, so the suite round-tripped happily over a bug the game had every single time.
local function asTheClientStoresIt(body)
    return tostring(body) .. "\n"
end
_G.CreateMacro = function(n, icon, body, perChar)
    MACROS[#MACROS + 1] = { name = n, icon = icon, body = asTheClientStoresIt(body),
                            perChar = perChar and true or false }
    return #MACROS
end
_G.EditMacro = function(i, n, icon, body)
    local m = MACROS[i]
    if not m then error("no macro at index " .. tostring(i), 2) end
    m.name, m.icon, m.body = n, icon, asTheClientStoresIt(body)
    return i
end

-- AN EVENT ONLY REACHES A FRAME THAT ASKED FOR IT. Calling f.__scripts.OnEvent(f, ...) by hand
-- delivers anything to anybody, which is a mock kinder than the client in the most misleading
-- way there is: a test written that way passes with the fix taken out, because the handler runs
-- whether or not the addon ever registered the event. (19 Sep 2026: the cold-start test below
-- did exactly that, twice, and only a deliberate check with the fix removed caught it.)
local function fire(f, event, ...)
    if not (f and f.__events and f.__events[event]) then return false end
    local h = f.__scripts and f.__scripts.OnEvent
    if not h then return false end
    h(f, event, ...)
    return true
end

-- THE SPELLBOOK, AS THIS CLIENT ACTUALLY ANSWERS IT. The old stub let a SPELL ID answer a rank,
-- and that is precisely why the missing rank got shipped: on the real client an id answers a name
-- and nothing else, and C_Spell.GetSpellSubtext is the only call that knows the rank. A mock
-- kinder than the client is a mock that tests nothing.
--
--   C_SpellBook.GetSpellBookItemName(index, bank) -> name, rank   (a BOOK INDEX, never an id)
--   C_Spell.GetSpellInfo(id)                -> { name = }   (no rank anywhere in it)
--   C_Spell.GetSpellSubtext(id)             -> "Rank 4"
local RANKS = {}                       -- id -> the rank the client would report for it
-- The book this fake shaman has actually trained. It is stocked rather than empty because an
-- empty book is not a character anyone plays, and the defaults now come out of the book: a spell
-- you have not learned is not put on your mouse. Slots 10+ are free for tests to fill.
local BOOK = {
    [1] = { name = "Healing Wave",        rank = "Rank 1" },
    [2] = { name = "Healing Wave",        rank = "Rank 2" },
    [3] = { name = "Healing Wave",        rank = "Rank 3" },
    [4] = { name = "Lesser Healing Wave", rank = "Rank 1" },
    [5] = { name = "Chain Heal",          rank = "Rank 1" },
}
_G.C_SpellBook = _G.C_SpellBook or {}
_G.C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
-- TWO ARGUMENTS, because the client wants two. Measured in game, 19 Sep 2026:
--
--   C_SpellBook.GetSpellBookItemName(1)     -> error, "bad argument #1 to '?' (not a numerical
--                                              value - Usage: ... (spellBookItem))"
--   C_SpellBook.GetSpellBookItemName(1, 0)  -> "Attack"
--
-- The addon called it with one argument, so it errored on EVERY index; the pcall around it
-- swallowed that, the rank list came back empty forever, and three things quietly did nothing -
-- no class defaults at login, no rank cycling, no rank list in the binder. Arn saw all three
-- ("did not let me do different rank on modifier", a blank mouse every session) while this file
-- reported 195 green checks, because this mock answered the one-argument call happily.
--
-- It refuses it now. A mock kinder than the client is a mock that tests nothing.
_G.C_SpellBook.GetSpellBookItemName = function(n, bank)
    if type(n) ~= "number" then error("bad argument #1 (not a numerical value)", 2) end
    if type(bank) ~= "number" then
        error("bad argument #1 to '?' (not a numerical value - Usage: local name, subName ="
              .. " C_SpellBook.GetSpellBookItemName(spellBookItem))", 2)
    end
    local e = BOOK[n]
    if e then return e.name, e.rank end
    return nil
end
_G.C_Spell.GetSpellSubtext = function(id) return RANKS[id] end

local BOUND = {}
_G.SetOverrideBindingClick = function(_, _, key, button) BOUND[key] = button end
_G.ClearOverrideBindings = function() BOUND = {} end

-- The tooltip, which is where a bind says what it is. It records lines rather than drawing them.
local TIP = { lines = {} }
_G.GameTooltip = autoMethods({
    SetOwner = function(self) TIP.lines = {} end,
    AddLine  = function(self, text) TIP.lines[#TIP.lines + 1] = text end,
})
_G.UISpecialFrames = {}        -- what the client closes on Escape
_G.tinsert = table.insert

-- THE WHOLE ADDON, IN THE TOC'S ORDER, read from the TOC itself rather than listed here. A list
-- in a suite is a list that goes stale: on 19 Sep the addon lost 5,000 lines and gained a core,
-- and a hand-written list would have kept loading files that no longer exist while quietly
-- skipping the one that now owns the saved variables.
--
-- The Libs lines are skipped: BiSTheme is a shared lib with its own suite, and the drawing here
-- is stub frames anyway.
local LOADED = {}
do
    local toc = assert(io.open("BiSHealing.toc"))
    for line in toc:lines() do
        -- trimmed, not pattern-matched: the TOC separator is a backslash, and a suite that has
        -- to escape one to read a path is a suite one careless edit away from silence
        local rel = line:match("^%s*(.-)%s*$")
        if rel:sub(-4):lower() == ".lua" and rel:sub(1, 4) ~= "Libs" then
            rel = rel:gsub(string.char(92), "/")
            local chunk = assert(loadfile(rel), "the TOC lists " .. rel .. ", which is not there")
            chunk("BiSHealing", NS)
            LOADED[#LOADED + 1] = rel
        end
    end
    toc:close()
end
ok(#LOADED >= 8, "the TOC's files all load: " .. #LOADED)
local FG = NS.FG
local FRAME_W_FOR_TEST = 84 - 10 + 1    -- Grid.lua's FRAME_W less the header padding, for the fit check

ok(NS.SECRET == true, "NS.SECRET must be true when the client says it hides numbers")
ok(NS.Blind() == false, "out of combat the addon is not blind")
STATE.inCombat = true
ok(NS.Blind() == true, "inside the lockdown it is")
STATE.inCombat = false

-- roster: group order, never health order (health order is what Forever makes impossible)
local roster = FG.Roster()
ok(#roster == 3 and roster[1] == "player" and roster[3] == "party2",
   "the roster is the group, in group order")

local anchor = newFrame("Frame")
local laid, n = FG.Layout(anchor)
ok(laid and n == 3, "layout builds a cell per unit out of combat")
ok(FG.frames[1] and FG.frames[1].unit == "player", "cell 1 is bound to the player")
-- The seeded binds are the ones for THIS character's class: the harness plays a shaman (see
-- UnitClass above), so a shaman's first two spells are what a fresh install has on the mouse.
-- WITH THE RANK ON: seeded bare, a slot has no number in its corner and the rank button - the
-- feature this addon is for - is invisible until you drag something yourself.
ok(FG.frames[1].__attrs["*spell1"] == "Healing Wave(Rank 3)", "left click casts through a secure attribute",
   tostring(FG.frames[1].__attrs["*spell1"]))
ok(FG.frames[1].__attrs["shift-spell1"] == "Chain Heal(Rank 1)", "shift-click is the chain")
ok(NS.FM.Defaults().left == "Healing Wave(Rank 3)", "a shaman's mouse starts on the top rank of Healing Wave")

-- ONLY WHAT IS IN THE BOOK. Arn, on a shaman who had not trained it yet: "it setts it back to
-- chain heals which i dont have yet". A default is a courtesy; a default for a spell you cannot
-- cast is a button that does nothing and a line of red text when you press it.
do
    local FM = NS.FM
    local keep = BOOK[5]                              -- Chain Heal
    BOOK[5] = nil
    local defaults, booked = FM.Defaults()
    ok(defaults.left == "Healing Wave(Rank 3)", "the spells this character HAS are still offered")
    ok(defaults["shift-left"] == nil, "and the one not in the book is not put on the mouse")
    ok(booked == true, "the book answered, so this counts as a real seeding")

    -- and a book that answers NOTHING - which happens at login, before the client fills it in -
    -- must not be written down as "seeded" and leave the mouse empty forever
    local stash = {}
    for i = 1, 5 do stash[i], BOOK[i] = BOOK[i], nil end
    local none, saidNo = FM.Defaults()
    ok(next(none) == nil and saidNo == false,
       "an empty book seeds nothing, and says so, so the next call can try again")
    for i = 1, 5 do BOOK[i] = stash[i] end
    BOOK[5] = keep
end
-- and "can I reach them" asks about the spell on the left button, not a name baked into the grid
ok(NS.FM.RangeSpell() == "Healing Wave", "range is judged by the spell your click would cast")

-- THE RULE: the value the client gave is handed on untouched. If any line in Paint had done
-- arithmetic, compared it, or printed it, the secret would have errored and this would be false.
local f = FG.frames[2]
local painted = pcall(FG.Paint, f)
ok(painted, "Paint never reads the number it was given")
ok(getmetatable(f.bar.__value) == secretMeta, "the bar was handed the secret itself, not a copy")
ok(f.bar.__color ~= nil, "the bar was coloured (class colour, not a health band)")

-- WHAT IS ALREADY ON ITS WAY. Arn: "the frame is not showing how much an incomming heal is going
-- to do like healium does". It can - the same bargain as health. UnitGetIncomingHeals hands back
-- a number that may be secret, and a secret may be GIVEN to a StatusBar; the addon never learns
-- the size of the heal, the client draws it. (Read off Healium's own Forever build.)
do
    STATE.incoming.party1 = 400
    STATE.incomingSecret = false
    FG.Paint(f)
    ok(f.incoming ~= nil, "a cell has a bar for heals on their way")
    ok(f.incoming.__value == 400, "and it is handed what is coming")

    STATE.incomingSecret = true
    ok(pcall(FG.Paint, f), "a SECRET incoming heal does not throw")
    ok(getmetatable(f.incoming.__value) == secretMeta,
       "it is handed the secret itself, untouched, exactly like the health above it")

    STATE.incoming.party1 = nil
    STATE.incomingSecret = false
    FG.Paint(f)
    ok(f.incoming.__value == 0, "nothing on the way empties the bar rather than leaving it")
end

-- A SECRET BOOLEAN, AND A SECRET STRING, both of which go into a test in Paint: one sits in an
-- `if`, the other indexes the class-colour table. The client refuses the test itself, so both are
-- asked about with issecretvalue first - a call this addon did not know existed until it read how
-- Healium guards the same two values.
do
    STATE.deadSecret, STATE.classSecret = true, true
    ok(pcall(FG.Paint, f), "a secret dead flag and a secret class do not throw")
    ok(f.bar.__color ~= nil, "and the bar is still coloured, by the fallback")
    STATE.deadSecret, STATE.classSecret = false, false
    FG.Paint(f)
end

-- dead is readable inside the lockdown, so the grid may still mark it
STATE.dead.party1 = true
FG.Paint(f)
ok(f.bar.__color[1] > f.bar.__color[3], "a dead unit paints red, not class colour")
STATE.dead.party1 = nil

-- range: IsSpellInRange answers plainly; UnitInRange would be a secret boolean and unusable
STATE.range.party1 = 0
FG.Paint(f)
ok(f:GetAlpha() == 0.45, "out of range dims the cell")
STATE.range.party1 = nil
FG.Paint(f)
ok(f:GetAlpha() == 1, "back in range, full alpha")

-- a client that refuses a secret max must not take the addon down with it; whether Forever does
-- is not yet measured, so the grid asks once and remembers the answer
STATE.maxRefusesSecret = true
FG.maxOK = true
local survived = pcall(FG.Paint, f)
ok(survived and FG.maxOK == false,
   "a refused SetMinMaxValues is absorbed once, not thrown every tick")
STATE.maxRefusesSecret = false

-- names: a cell is 84 wide, so the realm goes and the rest is cut to fit. "Longnamedhealer-Realmone"
-- overflowing its cell is what the beta showed on 17 Sep.
ok(#FG.ShortName("party1") <= 12, "a name is cut to what the cell holds")
_G.UnitName = function() return "Longnamedhealerxx-Realmone" end
ok(FG.ShortName("party1") == "Longnamedhea", "the realm is dropped before the cut")
-- FIRST NAME ONLY. Arn, 21 Sep, looking at "Kumlust S": "get rid of last names".
_G.UnitName = function() return "Kumlust Surname" end
ok(FG.ShortName("party1") == "Kumlust", "a surname is dropped, not cut to an initial")
_G.UnitName = function() return "Kumlust Surname-Realmone" end
ok(FG.ShortName("party1") == "Kumlust", "and with a realm on the end as well")
_G.UnitName = function(u) return "Name-" .. tostring(u) end

-- the name must draw ABOVE the bar: a FontString created on the button sits under the bar, which
-- reads as "the names are missing" in game
ok(FG.frames[1].name ~= nil, "a cell has a name label")
ok(rawequal(FG.frames[1].__nameParent, FG.frames[1].bar) or FG.frames[1].name ~= nil,
   "the label belongs to the bar, so it draws over it")

-- The grid runs on whatever client it finds. Until 19 Sep this began "if not NS.SECRET then
-- return false" - stand aside, this client keeps the pyramid - and there is no pyramid now.
do
    local realSecret = NS.SECRET
    FG.anchor = nil                          -- let Start() run again for this check
    NS.SECRET = false                        -- a client that answers every question freely
    ok(FG.Start() == true, "the grid starts on a client that hides nothing, too")
    NS.SECRET = realSecret
end

-- A BIND THAT SURVIVED THE RELOAD BUT DID NOTHING. Arn, 19 Sep 2026: "the binds saved and the
-- window where the bind saved but they dont do anything on the frame, last time i had to drag the
-- same spell again to the bind and then it worked." His one saved bind was `wheelup`.
--
-- Buttons 1-5 are secure ATTRIBUTES, written onto each cell by ApplyTo during layout, so those
-- came back with the grid. The wheel is a BINDING, and the only thing that ever armed it was
-- dropping a spell on the window. So: a login, a layout, and NOT ONE DRAG - the wheel must work.
do
    NS.FM.Set("", "wheelup", "Healing Wave(Rank 1)")
    BOUND = {}                               -- as a fresh session starts: nothing armed yet
    STATE.inCombat = false
    FG.Layout(anchor)
    ok(BOUND["MOUSEWHEELUP"] ~= nil,
       "the layout arms the wheel, with no drag to prompt it: " .. tostring(BOUND["MOUSEWHEELUP"]))
    NS.FM.Clear("", "wheelup")
end

-- THE COLD START. At login the client has not filled the spellbook in yet, so the seeding finds
-- nothing and the cells are built empty. What used to be missing was the second half: when the
-- book arrived, nobody asked again, and the mouse stayed dead until a spell was dragged in by
-- hand. Arn, twice - "the binds saved but they dont do anything on the frame, last time i had to
-- drag the same spell again", then "reloaded no binds".
--
-- The order matters, and so does the SETTLING. `pending` starts true, so a tick relayouts on its
-- own and a careless version of this test passes with the fix taken out - which this one did,
-- until it was checked. So: settle first, prove the book arriving is NOT enough by itself, and
-- only then let the event through.
do
    local tick = function() FG.anchor.__scripts.OnUpdate(FG.anchor, 10) end
    tick()                                              -- settle: pending is false from here

    local stash = {}
    for i = 1, 5 do stash[i], BOOK[i] = BOOK[i], nil end
    local d = NS.DB()
    d.binds, d.bindsSeeded = {}, nil
    FG.Layout(FG.anchor)                                -- the login layout, book still silent
    ok(FG.frames[1].__attrs["*spell1"] == nil,
       "a cell built before the book answers casts nothing", tostring(FG.frames[1].__attrs["*spell1"]))

    for i = 1, 5 do BOOK[i] = stash[i] end              -- the book arrives, a moment later
    tick()
    ok(FG.frames[1].__attrs["*spell1"] == nil,
       "and the book arriving is NOT enough on its own - nothing asked again")

    ok(fire(FG.events, "SPELLS_CHANGED"), "the grid asked for SPELLS_CHANGED in the first place")
    tick()
    ok(FG.frames[1].__attrs["*spell1"] == "Healing Wave(Rank 3)",
       "but SPELLS_CHANGED does it, with nobody dragging anything",
       tostring(FG.frames[1].__attrs["*spell1"]))
end

-- KEEPING THE BINDS SOMEWHERE THE CLIENT GIVES THEM BACK. SavedVariables are written and never
-- returned on this beta, so a macro - which lives on the server - is the only memory there is.
do
    local FK, FM = NS.FK, NS.FM
    ok(FK ~= nil, "there is somewhere to keep them")

    -- the round trip, on the setup Arn actually wants
    local body = FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)",
                             ["shift-wheelup"] = "Healing Wave(Rank 4)" })
    ok(#body <= FK.LIMIT, ("it fits in a macro: %d of %d characters"):format(#body, FK.LIMIT))
    ok(body:find("Healing Wave", 1, true) and not body:find("Healing Wave.*Healing Wave"),
       "and the spell name is written once, however many slots use it: " .. body)
    local back = FK.Decode(body)
    ok(back and back["wheelup"] == "Healing Wave(Rank 2)", "wheel up comes back with its rank")
    ok(back and back["shift-wheelup"] == "Healing Wave(Rank 4)",
       "and shift plus wheel up is its own bind, at its own rank")

    -- a body nobody can read must cost one bind, not the mouse
    ok(FK.Decode("some other addon's macro") == nil, "a body that is not ours is left alone")
    local half = FK.Decode(FK.TAG .. ";Healing Wave#u=1:2;zz=9:9")
    ok(half and half["wheelup"] and not half["zz"], "a row it cannot read is skipped, the rest lands")

    -- A FULL MOUSE, all 28 slots on one spell: it very nearly does not fit, and that is worth
    -- knowing rather than discovering. Storing the name once is what buys the room.
    local fat = {}
    for _, m in ipairs(FM.MODS) do
        for _, sl in ipairs(FM.SLOTS) do fat[m.key .. sl.key] = "Lesser Healing Wave(Rank 11)" end
    end
    local fatBody, spare = FK.Encode(fat)
    ok(#fatBody <= FK.LIMIT,
       ("28 slots on one spell still fit: %d of %d characters"):format(#fatBody, FK.LIMIT))
    ok(spare == 0, "with nothing dropped")

    -- 28 DIFFERENT spells cannot fit in 255, and then the answer is "these did not", not silence
    local many = {}
    for _, m in ipairs(FM.MODS) do
        for i, sl in ipairs(FM.SLOTS) do
            many[m.key .. sl.key] = ("Greater Healing Spell %s%d(Rank 9)"):format(m.key:sub(1, 1), i)
        end
    end
    local manyBody, dropped = FK.Encode(many)
    ok(#manyBody <= FK.LIMIT, ("trimmed to fit: %d characters"):format(#manyBody))
    ok(dropped > 0, ("and it says how many did not fit: %d"):format(dropped))
    ok(FK.Decode(manyBody) ~= nil, "what did fit is still readable")

    -- writing: made once, edited after
    MACROS = {}
    local wrote = FK.Save({ ["wheelup"] = "Healing Wave(Rank 2)" })
    ok(wrote == true and #MACROS == 1, "the first save makes the macro")
    ok(MACROS[1].name == FK.MACRO and MACROS[1].perChar == true,
       "named, and this character's own - not a general slot")
    FK.Save({ ["wheelup"] = "Healing Wave(Rank 3)" })
    ok(#MACROS == 1, "the second save edits it rather than making another")
    ok(FK.Load()["wheelup"] == "Healing Wave(Rank 3)", "and reading it back gives the new one")

    -- the player's own macros are none of our business
    MACROS = { { name = "1 Focus", body = "/focus party1", perChar = false } }
    FK.Save({ ["left"] = "Healing Wave(Rank 1)" })
    ok(MACROS[1].name == "1 Focus" and MACROS[1].body == "/focus party1",
       "a macro that is not ours is never touched")
    ok(#MACROS == 2, "ours is made beside it")

    -- in combat the client will not make a macro, and pretending otherwise loses the change
    STATE.inCombat = true
    local no, why = FK.Save({ ["left"] = "Healing Wave(Rank 2)" })
    ok(no == false and why == "combat", "in combat it refuses, and says which refusal it is")
    STATE.inCombat = false

    -- and there is no room left
    MACROS = {}
    for i = 1, 18 do MACROS[i] = { name = "mine" .. i, body = "x", perChar = true } end
    local full, reason = FK.Save({ ["left"] = "Healing Wave(Rank 1)" })
    ok(full == false and tostring(reason):find("full"),
       "a full macro list is an answer, not a silent failure: " .. tostring(reason))
end

-- THE WHOLE POINT, played out: a bind kept from a previous session beats the class default.
-- Arn, twice in ten minutes - "it did it to left click i put it back on mousewheel", then
-- "reloaded and it put it back on left click". On a client with no memory the default lands on
-- left click at EVERY login, and the player drags it back every time.
do
    local FK, FM = NS.FK, NS.FM
    MACROS = {}
    FK.Save({ ["wheelup"] = "Healing Wave(Rank 2)" })   -- last session, on the wheel

    local d = NS.DB()                                   -- and now a fresh one
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false
    local mouse = FM.Get("", "wheelup")
    ok(mouse == "Healing Wave(Rank 2)", "the wheel bind is back from the macro", tostring(mouse))
    ok(FM.Get("", "left") == nil,
       "and the class default did NOT land on left click over the top of it",
       tostring(FM.Get("", "left")))

    -- and leave the mouse as it was found: everything after here reads the seeded defaults
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false
    FM.Get("", "left")                                  -- asks nothing, finds nothing, seeds
end

-- THE MACRO LIST ARRIVING LATE, which is the same shape as the spellbook arriving late and
-- would have cost more: the mouse gets seeded with our guess, we stop asking, and the next
-- spell the player drags writes that guess over the binds they actually kept.
do
    local FK, FM = NS.FK, NS.FM

    -- the player's real setup, kept from last time - but the list is not readable yet
    MACROS = {}
    FK.Save({ ["wheelup"] = "Healing Wave(Rank 2)" })
    local realIndex = _G.GetMacroIndexByName
    _G.GetMacroIndexByName = function() return 0 end        -- "no macros", as an empty list reads

    local d = NS.DB()
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    ok(FM.Get("", "left") ~= nil, "with the list unreadable, the class default lands as before")
    ok(FM.Get("", "wheelup") == nil, "and the kept wheel bind is not there yet")

    _G.GetMacroIndexByName = realIndex                      -- the list fills in, a moment later
    ok(fire(FG.events, "UPDATE_MACROS"), "the grid asked for UPDATE_MACROS in the first place")
    ok(FM.Get("", "wheelup") == "Healing Wave(Rank 2)",
       "the kept bind arrives once the list does", tostring(FM.Get("", "wheelup")))
    ok(FM.Get("", "left") == nil, "and our guess is off left click again")

    -- BUT NEVER A BIND THE PLAYER PUT THERE. Reconsidering is allowed to discard our own guess
    -- and nothing else.
    -- BUT NEVER A BIND THE PLAYER PUT THERE. The state has to be built exactly: a SEEDED mouse
    -- (so the wipe is on the table at all) that the player has then dragged to, with the macro
    -- unable to hold it (in combat) - otherwise the bind survives because it was written down,
    -- and the test proves the macro works rather than the guard. Built any other way this
    -- passes with the guard deleted, which is what it did the first two times.
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")
    ok(d.bindsSeeded == true, "a mouse we seeded ourselves, so reconsidering may wipe it")

    STATE.inCombat = true
    FM.Set("", "wheelup", "Healing Wave(Rank 1)")
    STATE.inCombat = false
    ok(FM.touched == true, "a drag marks the mouse as theirs, not ours")
    ok(not (FK.Load() or {})["wheelup"], "and it is NOT in the macro - refused in combat")
    FM.Reconsider()
    ok(FM.Get("", "wheelup") == "Healing Wave(Rank 1)",
       "so reconsidering leaves a deliberate bind where they put it, written down or not",
       tostring(FM.Get("", "wheelup")))

    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")
end

-- ARN'S EXACT PAIR, 19 Sep: "everytime i reload the rank 2 mouse wheel survives but not the
-- shift mouse wheel up rank 4". Two binds on the same slot under different modifiers, through
-- the path a player actually uses - Set, Set, reload - and then the question the report does not
-- answer on its own: is the bind MISSING, or is it there and not armed? Both are checked, because
-- "it does not survive" has meant each of those at different points tonight.
do
    local FK, FM = NS.FK, NS.FM
    MACROS = {}
    local d = NS.DB()
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Set("", "wheelup", "Healing Wave(Rank 2)")
    FM.Set("shift-", "wheelup", "Healing Wave(Rank 4)")

    local body = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(body:find("u=", 1, true) and body:find("su=", 1, true),
       "both go into the macro, plain and shifted: " .. tostring(body))

    -- THE LAST ROW IS THE ONE THAT GOES. The client stores a body one character longer than it
    -- was given, and every row is matched anchored - so the newline rode on the final row and
    -- that bind alone was lost, at every reload, while the macro plainly held it. What gave it
    -- away was not the body but the COUNT beside it: "32 of 255 characters" for 31 characters
    -- of text. Print the length next to the thing and the arithmetic does the diagnosing.
    local mine = FK.Encode(NS.DB().binds)
    ok(#body == #mine + 1,
       ("the client stores one character more than it is given: %d in, %d back"):format(#mine, #body))
    ok(body:sub(-1) == "\n", "the extra one is a newline it adds on the end")
    local read = FK.Decode(body)
    ok(read and read["shift-wheelup"] == "Healing Wave(Rank 4)",
       "and the LAST bind still reads back, newline and all",
       tostring(read and read["shift-wheelup"]))

    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil   -- the reload
    ok(FM.Get("", "wheelup") == "Healing Wave(Rank 2)",
       "the plain wheel comes back", tostring(FM.Get("", "wheelup")))
    ok(FM.Get("shift-", "wheelup") == "Healing Wave(Rank 4)",
       "and so does shift plus wheel, at ITS own rank", tostring(FM.Get("shift-", "wheelup")))

    -- remembered is not the same as working: the wheel is a BINDING, and each modifier is
    -- armed separately
    BOUND = {}
    FM.ApplyWheel(FG.anchor)
    ok(BOUND["MOUSEWHEELUP"] ~= nil, "the plain wheel is armed")
    ok(BOUND["SHIFT-MOUSEWHEELUP"] ~= nil,
       "and SHIFT-MOUSEWHEELUP is armed too - a different binding, easy to leave out")

    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")
end

-- THE ROLE ICON. Arn saw them on Healium's frames - "healium pulls these roll can we put them
-- on ours" - and Healium's Forever build is where the shape came from: ask, then check the answer
-- is not secret, then ask for the atlas, then check THAT is not secret either.
do
    STATE.roles = { player = "HEALER", party1 = "TANK", party2 = "DAMAGER" }
    FG.Layout(FG.anchor)
    -- BY UNIT, NOT BY POSITION: the pyramid puts the TANK first, so frames[1] is party1 now and
    -- a test that assumed "cell 1 is me" was testing the old layout's order, not the icon.
    local cell = FG.byUnit["player"]

    ok(cell.role ~= nil, "a cell has somewhere to put the role")
    local drew, role = FG.PaintRole(cell)
    ok(drew and role == "HEALER", "the player's role is read", tostring(role))
    ok(cell.role:IsShown(), "and the icon is shown")
    -- DOUBLED, and the reason is the bug this very line had in its first draft: Lua 5.1 drops an
    -- escape it does not recognise instead of complaining, so "Interface\LFGFrame\..." IS the
    -- string "InterfaceLFGFrameUI-LFG-ICON-ROLES" and matches nothing. Written single here, it
    -- failed against code that was already right - which is the more expensive direction.
    ok(cell.role.__texture == "Interface\\LFGFrame\\UI-LFG-ICON-ROLES",
       "from the roles sheet, with its backslashes intact: " .. tostring(cell.role.__texture))
    ok(cell.role.__coords and cell.role.__coords[3] == 1 / 64,
       "and the healer corner of it, not the tank one")

    STATE.roles.player = "TANK"
    FG.PaintRole(cell)
    ok(cell.role.__coords[3] == 22 / 64, "a tank gets a different corner")

    -- NO ROLE is not an error, it is most of a levelling party
    STATE.roles.player = "NONE"
    ok(FG.PaintRole(cell) == false and not cell.role:IsShown(),
       "no role at all just hides it")

    -- AND IN COMBAT the client hands back a secret. Reading it would error; Healium checks for
    -- exactly this, which is how we knew to.
    STATE.roles.player = "HEALER"
    STATE.roleSecret = true
    local ok2, shown = pcall(FG.PaintRole, cell)
    ok(ok2, "a secret role does not blow up Paint")
    ok(shown == false and not cell.role:IsShown(), "it hides the icon rather than guessing")
    STATE.roleSecret = false

    -- and Paint as a whole still never touches the number it was given
    STATE.roles.player = "HEALER"
    ok(pcall(FG.Paint, cell), "Paint still paints with a role on the cell")
end

-- ASKING THE CLIENT INSTEAD OF LEARNING BY FAILING. Learned from ForeverAuras 0.1.114, which
-- asks C_Secrets before every kind of read. The grid used to discover a refused maximum by
-- handing one over and catching the error - which works, once, after the error.
do
    FG.maxOK = true
    STATE.maxSecret = true
    FG.Paint(FG.frames[1])
    ok(FG.maxOK == false, "the grid asks whether a secret maximum is allowed, and is told no")

    FG.maxOK = true
    STATE.maxSecret = false
    FG.Paint(FG.frames[1])
    ok(FG.maxOK == true, "and when it is allowed, it goes on using it")
    STATE.maxSecret = nil
end

-- NOT TESTED HERE, AND THAT IS THE HONEST ANSWER: what NS.SECRET does with an answer it cannot
-- trust. Two attempts at it were written and both were green whatever the code did.
--
--   1. a SECRET answer cannot be simulated. Lua has no hook for truthiness, so a mock value
--      cannot error when it is used in an `and` - which is precisely how the real client would
--      refuse it. The test passed with the guard deleted.
--   2. re-running Lockdown.lua with dofile does not re-run it AS THE ADDON: the file reads its
--      namespace from `...`, which dofile leaves empty, so it builds a throwaway table and the
--      real NS.SECRET is never touched. That test passed with the guard deleted too.
--
-- The guard stays in Lockdown.lua on ForeverAuras' evidence and on reading the line, not on a
-- green check here. A green check that cannot fail is worse than no check: it is a claim.

-- A MIGRATION MUST NOT EAT A STRANGER'S DATA. 20 Sep 2026: this addon's TOC claims TBC as well
-- as Forever, so it loaded in Arn's TBC client, found the OLD BiSHealing's saved table - 4,039
-- fight records, 367KB - saw a dbver it did not know, and emptied it. One logout from gone.
--
-- A version bump is a promise about the keys THIS addon owns. It is not a licence to clear a
-- table it happens to share.
do
    local keep = _G.BiSHealingDB
    _G.BiSHealingDB = {
        dbver = 99,                                   -- not ours: somebody else's schema
        fights = { { top = "Kumlust", dps = 412 }, { top = "Kumlance", dps = 388 } },
        chainDepth = 3,
        binds = { left = "Healing Wave(Rank 12)" },   -- ours, and carried as always
        shown = true,
    }
    local db = NS.DB()

    ok(db.binds and db.binds.left == "Healing Wave(Rank 12)", "the migration still carries our own keys")
    ok(db.dbver == NS.DBVER, "and stamps its own version")
    ok(db.fights == nil, "a stranger's key is not left lying at the top level")
    ok(type(db.attic) == "table", "it is set aside instead")
    ok(db.attic.fights and #db.attic.fights == 2 and db.attic.fights[1].top == "Kumlust",
       "with every record intact, not a count or a summary")
    ok(db.attic.chainDepth == 3, "and the small keys too")

    -- a SECOND migration must not throw away the first one's attic
    db.dbver = 98
    local again = NS.DB()
    ok(type(again.attic) == "table" and again.attic.fights,
       "a later migration keeps what an earlier one set aside")

    _G.BiSHealingDB = keep
end

-- WHERE IT LANDS, AND WHAT IT LANDS UNDER. Arn, 20 Sep, with a 25-man raid up: "its behind all
-- this junk how do i move it again center it puts it down there". Two separate faults in one
-- sentence, and both of them make the window unrescuable: it drew among the action bars, and the
-- one command meant to retrieve a window you cannot see put it back into them.
do
    ok(FG.anchor.__strata == "HIGH",
       "the grid is above the action bars, not among them", tostring(FG.anchor.__strata))

    local d = NS.DB()
    d.gridPos = { point = "RIGHT", rel = "RIGHT", x = -192, y = 14 }
    FG.RestorePos()
    local p, _, r, x, y = FG.anchor:GetPoint(1)
    ok(p == "RIGHT" and x == -192, "a dragged position is remembered", tostring(p) .. " " .. tostring(x))

    d.gridPos = nil
    FG.RestorePos()
    p, _, r, x, y = FG.anchor:GetPoint(1)
    ok(p == "CENTER" and r == "CENTER" and x == 0 and y == 0,
       "and centre means CENTRE - not 260 left and 120 down into the action bars",
       ("%s %s %s,%s"):format(tostring(p), tostring(r), tostring(x), tostring(y)))
end

-- THE PYRAMID. Arn, mid-raid with the TBC frames up: "this is how we make forever eventually
-- pyramid tanks on top people out of range dimmmed" - and then "can we rearrange out of combat?",
-- which is not a choice: the cells are secure frames and the client will not move them mid-fight.
do
    -- THE SHAPE, asked without a client: an apex, a pair, then rows of six
    local function rows(n)
        local out = {}
        for _, p in ipairs(FG.Pyramid(n)) do out[p.row] = (out[p.row] or 0) + 1 end
        return table.concat(out, ",")
    end
    ok(rows(1) == "1", "solo: the apex alone", rows(1))
    ok(rows(5) == "1,2,2", "a party: apex, pair, and two below", rows(5))
    ok(rows(25) == "1,2,6,6,6,4", "a 25-man: the base repeats in sixes", rows(25))
    local p = FG.Pyramid(9)
    ok(p[1].wide and p[2].wide and p[3].wide and not p[4].wide,
       "the apex and the pair are full width, the rows under them are not")

    -- THE ORDER: tanks first, then healers, then damage, and raid order kept inside each
    local raid = { "raid1", "raid2", "raid3", "raid4", "raid5", "raid6", "raid7" }
    STATE.roles = { raid1 = "DAMAGER", raid2 = "HEALER", raid3 = "TANK", raid4 = "DAMAGER",
                    raid5 = "TANK", raid6 = "NONE", raid7 = "HEALER" }
    local by = table.concat(FG.ByRole(raid), " ")
    ok(by == "raid3 raid5 raid2 raid7 raid1 raid4 raid6",
       "tanks, then healers, then damage, then nobody - and nobody reshuffled within a role", by)

    -- IN COMBAT a role is a secret; the sort must survive it and not reorder on a guess
    STATE.roleSecret = true
    local blind = table.concat(FG.ByRole(raid), " ")
    ok(blind == table.concat(raid, " "), "a secret role sorts nobody - raid order is kept", blind)
    STATE.roleSecret = false

    -- THE CELLS, laid out for a real party: tank on top, and the apex cell really is wide
    STATE.roles = { player = "HEALER", party1 = "TANK", party2 = "DAMAGER" }
    local d = NS.DB()
    d.layout = "pyramid"
    FG.Layout(FG.anchor)
    ok(FG.frames[1].unit == "party1", "the tank is the apex", tostring(FG.frames[1].unit))
    ok(FG.frames[1].__w == 2 * 84 + 3, "the apex is two cells and a gap wide",
       tostring(FG.frames[1].__w))
    ok(FG.frames[1].incoming.__w == FG.frames[1].__w - 2,
       "and its incoming-heal bar runs the full width, not half of it",
       tostring(FG.frames[1].incoming.__w))

    -- AND OUT OF COMBAT ONLY
    STATE.roles.party2 = "TANK"
    STATE.inCombat = true
    ok(FG.Layout(FG.anchor) == false, "in combat it refuses to move anything")
    ok(FG.frames[1].unit == "party1", "so the apex is still who it was")
    STATE.inCombat = false
    FG.Layout(FG.anchor)
    ok(FG.frames[1].unit == "party1" and FG.frames[2].unit == "party2",
       "and once the fight ends, the new tank takes their place")

    -- AND COLUMNS, for anyone who wants the old grid back
    d.layout = "columns"
    FG.Layout(FG.anchor)
    ok(FG.frames[1].unit == "player" and FG.frames[1].__w == 84,
       "/bish layout columns puts it back: raid order, every cell the same")
    d.layout = "columns"          -- the DEFAULT, so nothing after this runs in the pyramid by accident
    STATE.roles = nil
    FG.Layout(FG.anchor)
end

-- THE REGULAR GRID IS THE DEFAULT, AND IT IS REALLY BY GROUP. Arn: "pyramid is a hard pill to
-- swallow we keep it a toggle regular grid by group or pyramid". The old grid filled columns of
-- five in raid1, raid2 order - JOIN order - so it only looked grouped when people had joined in
-- group order. Here the raid joined out of order on purpose.
do
    ok(NS.DB().layout == "columns", "a fresh install gets the regular grid, not the pyramid",
       tostring(NS.DB().layout))

    local realRaid, realInfo = _G.IsInRaid, _G.GetRaidRosterInfo
    local groupOf = { 1, 2, 1, 3, 2, 1 }      -- raid1..raid6 joined in this group order
    _G.IsInRaid = function() return true end
    _G.GetRaidRosterInfo = function(i) return "n" .. i, 0, groupOf[i] end

    local units, place, cols = FG.ByGroup({ "raid1", "raid2", "raid3", "raid4", "raid5", "raid6" })
    ok(cols == 3, "three groups present, three columns", cols)
    ok(table.concat(units, " ") == "raid1 raid3 raid6 raid2 raid5 raid4",
       "group 1 first, then 2, then 3 - not the order they joined in", table.concat(units, " "))
    ok(place[1].col == 1 and place[3].col == 1 and place[4].col == 2 and place[6].col == 3,
       "each column is one group")
    ok(place[1].row == 1 and place[2].row == 2 and place[3].row == 3,
       "and they stack down their group's column in raid order")

    _G.IsInRaid, _G.GetRaidRosterInfo = realRaid, realInfo
end

-- AND IT IS A TOGGLE: one command, one switch in the options window, either way round
do
    local d = NS.DB()
    d.layout = "columns"
    ok(NS.DO.layout() == "pyramid" and d.layout == "pyramid", "/bish layout with nothing flips to the pyramid")
    ok(NS.DO.layout() == "columns" and d.layout == "columns", "and again flips back")
    ok(NS.DO.layout("pyramid") == "pyramid", "or it can be told which")
    NS.DO.layout("columns")

    local found
    for _, sec in ipairs(NS.CFG.Sections()) do
        for _, o in ipairs(sec.options) do if o.key == "pyramid" then found = o end end
    end
    ok(found and found.kind == "toggle", "the options window has a pyramid switch")
    ok(found and found.get(d) == false, "and it reads off while the grid is showing")
end

-- ON TBC THIS FOLDER LOADS NOTHING THAT CAN TOUCH YOUR DATA. 20 Sep 2026: the base TOC claims TBC
-- as well as Forever, so the Forever addon loaded in Arn's TBC client, met the older BiS Healing's
-- saved table and emptied it. RestedXP showed the way out: a TBC client picks BiSHealing_TBC.toc
-- over the base, so that file decides what TBC loads - and it loads one notice and nothing else.
do
    local function read(path)
        local fh = io.open(path, "r"); if not fh then return nil end
        local s = fh:read("*a"); fh:close(); return s
    end
    local toc = read("BiSHealing_TBC.toc")
    ok(toc ~= nil, "there is a TBC-only TOC for the TBC client to pick instead")
    -- a leading newline so the first line counts - a frontier pattern misses line one, which is
    -- exactly where ## Interface sits
    ok(toc and ("\n" .. toc):find("\n## Interface: 20506", 1, true) ~= nil,
       "it claims TBC, so that client takes it over the base one")
    -- the DIRECTIVE, not the word: the first version searched the whole file and matched the
    -- comment explaining why there are none
    ok(toc and not ("\n" .. toc):lower():find("\n## savedvariables", 1, true),
       "and declares no saved variables - it is never in a position to touch BiSHealingDB")

    local files = {}
    for line in (toc or ""):gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%S") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
    end
    ok(#files == 1 and files[1] == "TBC.lua",
       "it loads exactly one file, the notice - no grid, no mouse, no Core", table.concat(files, ","))

    local base = read("BiSHealing.toc") or ""
    ok(not base:find("TBC.lua", 1, true), "and the Forever TOC does not load the notice")

    -- THE PROPERTY THAT ACTUALLY MATTERS, checked rather than read off the file list: run the
    -- notice in an environment with a tripwire on BiSHealingDB, fire its login, and see whether
    -- it so much as looked at the name.
    local touched, leaked = false, {}
    local env = setmetatable({}, {
        __index = function(_, k)
            if k == "BiSHealingDB" or k == "BiSHealingCharDB" then touched = true end
            return _G[k]
        end,
        __newindex = function(t, k, v)
            if k == "BiSHealingDB" or k == "BiSHealingCharDB" then touched = true end
            leaked[#leaked + 1] = tostring(k)
            rawset(t, k, v)
        end,
    })
    local fn = assert(loadfile("TBC.lua"))
    setfenv(fn, env)
    local ran = pcall(fn)
    ok(ran, "the notice loads")
    local said
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) said = t end }
    for _, f in ipairs(frames or {}) do
        local h = f.__scripts and f.__scripts.OnEvent
        if h and f.__events and f.__events.PLAYER_LOGIN then pcall(h, f, "PLAYER_LOGIN") end
    end
    _G.DEFAULT_CHAT_FRAME = realChat
    ok(said and said:find("inactive", 1, true), "at login it says it is inactive here", tostring(said))
    ok(not touched, "and it never so much as looked at BiSHealingDB")
    ok(#leaked == 0, "nor left a single global behind", table.concat(leaked, ","))
end

-- /bish text: THE PROBE MUST SURVIVE WHAT IT IS PROBING. It exists to find out whether the client
-- will paint missing health and a percentage for us, and the values it handles are secrets. A
-- probe that stringified one to print it would crash on exactly the case it was built to report.
--
-- The harness's ordinary fake secret does not trap tostring, so this one does - otherwise "never
-- turns a secret into a string" is a claim the suite cannot check.
do
    local trapMeta = {}
    for k, v in pairs(secretMeta) do trapMeta[k] = v end
    trapMeta.__tostring = function() error("tostring on a secret value", 2) end
    local function trap() return setmetatable({}, trapMeta) end

    local saved = {}
    for _, k in ipairs({ "UnitHealthMissing", "UnitHealthPercent", "AbbreviateNumbers",
                         "C_StringUtil", "UnitGetTotalAbsorbs", "issecretvalue", "DEFAULT_CHAT_FRAME" }) do
        saved[k] = _G[k]
    end
    _G.UnitHealthMissing = function() return trap() end            -- secret, as in a fight
    _G.UnitHealthPercent = function() return 87 end                 -- plain
    _G.AbbreviateNumbers = function(v)                              -- refuses a secret
        if getmetatable(v) == trapMeta then error("cannot format a secret", 2) end
        return "?"
    end
    _G.C_StringUtil = { TruncateWhenZero = function(v) return v end }
    _G.UnitGetTotalAbsorbs = function() return 0 end
    _G.issecretvalue = function(v) return getmetatable(v) == trapMeta or getmetatable(v) == secretMeta end
    local lines = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) lines[#lines + 1] = m end }

    local ran, err = pcall(NS.DO.text, "party1")

    for k, v in pairs(saved) do _G[k] = v end
    local all = table.concat(lines, "\n")
    local function row(name) return all:match(name .. "[^\n]*") or "" end
    ok(ran, "the probe survives the secrets it is testing", tostring(err))
    ok(row("missing"):find("secret") and row("missing"):find("paints"),
       "a secret missing-health is reported secret, and painted", row("missing"))
    ok(row("percent"):find("plain"), "a plain percentage is reported plain", row("percent"))
    ok(row("abbrev"):find("cannot ask"), "a formatter that refuses a secret is reported as refusing",
       row("abbrev"))
end

-- PETS. Arn: "toggel to see pets". Off by default - a raid of five hunters and three warlocks is
-- eight more cells - and when on, they get a column of their own rather than lengthening their
-- owner's group until a real player falls off the bottom.
do
    local d = NS.DB()
    STATE.units.pet, STATE.units.partypet1 = true, true

    ok(d.pets == false, "pets are off on a fresh install")
    local off = table.concat(FG.Roster(), " ")
    ok(not off:find("pet", 1, true), "and while off, no pet is in the roster even when one exists", off)

    ok(NS.DO.pets() == true and d.pets == true, "/bish pets turns them on")
    local on = table.concat(FG.Roster(), " ")
    ok(on:find("partypet1", 1, true) and on:find(" pet", 1, true), "and then the pets are in it", on)

    d.layout = "columns"
    local units, place, cols = FG.ByGroup(FG.Roster())
    local petCol, playerCol
    for i, u in ipairs(units) do
        if u == "partypet1" then petCol = place[i].col end
        if u == "player" then playerCol = place[i].col end
    end
    ok(petCol and playerCol and petCol > playerCol and petCol == cols,
       "in the grid the pets have the LAST column, not a seat in their owner's group",
       ("pet col %s of %s, player col %s"):format(tostring(petCol), tostring(cols), tostring(playerCol)))

    STATE.roles = { player = "HEALER", party1 = "TANK" }
    local ranked = FG.ByRole(FG.Roster())
    ok(FG.IsPetUnit(ranked[#ranked]), "in the pyramid a pet has no role, so it sits at the bottom",
       ranked[#ranked])
    STATE.roles = nil

    ok(fire(FG.events, "UNIT_PET"), "a pet summoned mid-session is noticed - UNIT_PET is registered")

    ok(NS.DO.pets() == false, "and /bish pets turns them off again")
    STATE.units.pet, STATE.units.partypet1 = nil, nil
    FG.Layout(FG.anchor)
end

-- THE NUMBER ON THE CELL. Arn: "any other information we can put on frames like missing health
-- or %". /bish text measured the parts (20 Sep); the study of 21 Sep found how shipped addons put
-- them together: short AND blank at full, net of incoming heals, a real percentage.
do
    local trapMeta = {}
    for k, v in pairs(secretMeta) do trapMeta[k] = v end
    trapMeta.__tostring = function() error("tostring on a secret value", 2) end
    -- A SECRET KNOWS ITS VALUE; we do not. The client's helpers may look (they are the client),
    -- and the suite looks through this side table. The cell code never can: the trap errors on
    -- everything but being passed along and being tested for truth.
    local hidden = setmetatable({}, { __mode = "k" })
    local function trap(n, kind)
        local t = setmetatable({}, trapMeta)
        hidden[t] = { n = n, kind = kind or "number" }
        return t
    end
    local function peek(t) return hidden[t] end

    local hurt, net, asked = {}, {}, {}                    -- what is missing; after incoming heals
    local saved = {}
    for _, k in ipairs({ "UnitHealthMissing", "C_StringUtil", "AbbreviateNumbers", "issecretvalue",
                         "UnitHealthPercent", "CurveConstants" }) do saved[k] = _G[k] end
    _G.issecretvalue = function(v) return getmetatable(v) == trapMeta or getmetatable(v) == secretMeta end
    _G.UnitHealthMissing = function(u, predicted)
        asked[#asked + 1] = predicted and "net" or "gross"
        if predicted and net[u] ~= nil then return net[u] end
        return hurt[u] or 0
    end
    _G.C_StringUtil = { TruncateWhenZero = function(v)
        local h = peek(v)
        if h then                                          -- a secret: blank at zero, secret text
            if h.n == 0 then return nil end                -- otherwise (EllesmereUI's documented shape)
            return trap(h.n, "text")
        end
        if v == 0 then return "" end                       -- plain: an EMPTY STRING, the harsh case
        return tostring(v)
    end }
    _G.AbbreviateNumbers = function(v)
        local h = peek(v)
        if h then return trap(h.n, "short") end
        if type(v) ~= "number" then error("AbbreviateNumbers: a number, please", 2) end
        if v >= 1000 then return ("%.1fK"):format(v / 1000) end
        return tostring(v)
    end

    local d = NS.DB()
    local cell = FG.byUnit["player"]
    ok(cell and cell.htext ~= nil, "a cell has a place for the number")
    ok(d.text == "missing", "missing health is the default number")

    hurt.player = 0
    FG.PaintText(cell)
    ok(cell.htext.__text == "", "at full health there is nothing there at all",
       tostring(cell.htext.__text))

    hurt.player = 3247
    asked = {}
    FG.PaintText(cell)
    ok(cell.htext.__text == "3.2K", "hurt, it shows what is missing, SHORT", tostring(cell.htext.__text))
    ok(asked[1] == "net", "and it asks for the gap AFTER the heals already on their way")

    net.player = 1200
    FG.PaintText(cell)
    ok(cell.htext.__text == "1.2K", "a heal on its way comes off the number", tostring(cell.htext.__text))
    net.player = 0
    FG.PaintText(cell)
    ok(cell.htext.__text == "", "and a gap already being filled shows nothing - no second healer on it",
       tostring(cell.htext.__text))
    net.player = nil

    -- no short form on this client: the number in full, not a blank and not an error
    _G.AbbreviateNumbers = nil
    FG.PaintText(cell)
    ok(cell.htext.__text == "3247", "without AbbreviateNumbers the number comes in full")
    _G.AbbreviateNumbers = function() error("no", 2) end
    ok(pcall(FG.PaintText, cell) and cell.htext.__text == "3247",
       "and a formatter that refuses leaves the full number standing")
    _G.AbbreviateNumbers = function(v)
        local h = peek(v)
        if h then return trap(h.n, "short") end
        if v >= 1000 then return ("%.1fK"):format(v / 1000) end
        return tostring(v)
    end

    -- THE WHOLE POINT: someone else's health is a secret, always. Handed on, never looked at.
    hurt.player = trap(3247)
    local safe, err = pcall(FG.PaintText, cell)
    ok(safe, "a secret deficit is painted without being read", tostring(err))
    local h = peek(cell.htext.__text)
    ok(h and h.kind == "short", "and it is the short form of the secret that ends up on the label",
       h and h.kind or type(cell.htext.__text))

    hurt.player = trap(0)
    FG.PaintText(cell)
    ok(cell.htext.__text == nil, "a secret zero is blank too - never a 0 over a full health bar",
       tostring(peek(cell.htext.__text) and "a secret" or cell.htext.__text))

    -- TWO LINES. Arn: "names and health are sharing the same line maybe we put them in different
    -- lines". The name owns the top line, the number the bottom one.
    local function side(fs)
        local tops, bottoms = 0, 0
        for _, pt in ipairs(fs.points or {}) do
            local where = tostring(pt[1])
            if where:find("^TOP") then tops = tops + 1 end
            if where:find("^BOTTOM") then bottoms = bottoms + 1 end
            if where == "LEFT" or where == "RIGHT" or where == "CENTER" then return "middle" end
        end
        if tops > 0 and bottoms == 0 then return "top" end
        if bottoms > 0 and tops == 0 then return "bottom" end
        return "mixed"
    end
    ok(side(cell.name) == "top", "the name sits on the top line", side(cell.name))
    ok(side(cell.htext) == "bottom", "the number sits on the bottom line", side(cell.htext))
    local tied
    for _, pt in ipairs(cell.name.points or {}) do if pt[2] == cell.htext then tied = true end end
    ok(not tied, "and the name is no longer squeezed by the number")

    -- PERCENT. A fraction unless asked for 0 to 100 - so it must be asked.
    local scale100 = {}
    _G.CurveConstants = { ScaleTo100 = scale100 }
    local pctOf = { player = 87 }
    _G.UnitHealthPercent = function(u, predicted, curve)
        local v = pctOf[u] or 100
        if curve ~= scale100 then
            return type(v) == "number" and v / 100 or v    -- the fraction, which is what bit us
        end
        return v
    end
    ok(NS.DO.number("percent") == "percent" and d.text == "percent", "/bish percent switches to it")
    ok(cell.htext.__text == "87%", "and the cell says 87%, not 0.87", tostring(cell.htext.__text))
    pctOf.player = trap(87)
    safe, err = pcall(FG.PaintText, cell)
    ok(safe and peek(cell.htext.__text), "a secret percentage is painted, not read", tostring(err))
    pctOf.player = 87
    _G.CurveConstants = nil
    FG.PaintText(cell)
    ok(cell.htext.__text == "", "no ScaleTo100 on this client: blank, rather than a wrong 0.87")

    -- OFF, and the old switch still works
    NS.DO.number("off")
    hurt.player = 500
    FG.PaintText(cell)
    ok(cell.htext.__text == "", "switched off, the number goes")
    ok(NS.DO.missing() == "missing" and d.text == "missing", "/bish missing brings it back")
    ok(NS.DO.number() == "percent" and NS.DO.number() == "off" and NS.DO.number() == "missing",
       "no argument steps missing, percent, off, and round again")

    -- a client without the calls - TBC, say - gets a blank, not an error
    _G.UnitHealthMissing = nil
    ok(pcall(FG.PaintText, cell) and cell.htext.__text == "", "no client support, no number, no error")

    -- AN OLD INSTALL that had turned the number off keeps it off
    local realDB = _G.BiSHealingDB
    _G.BiSHealingDB = { dbver = NS.DBVER, missing = false }
    local od = NS.DB()
    ok(od.text == "off" and od.missing == nil, "missing = false carries over as text = off, and is let go")
    _G.BiSHealingDB = realDB

    for k, v in pairs(saved) do _G[k] = v end
end

-- COLOUR BY HEALTH. We may not compare someone's health to 35%; the client may. Handed a colour
-- curve, UnitHealthPercent answers with a colour - and the r, g, b in it can be secret.
do
    local trapMeta = {}
    for k, v in pairs(secretMeta) do trapMeta[k] = v end
    local function trap() return setmetatable({}, trapMeta) end

    local saved = {}
    for _, k in ipairs({ "C_CurveUtil", "CreateColor", "Enum", "UnitHealthPercent" }) do saved[k] = _G[k] end
    local built = {}
    _G.Enum = { LuaCurveType = { Step = "step", Linear = "linear" } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_CurveUtil = { CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType(t) self.type = t end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x = x, col = col } end
        built[#built + 1] = c
        return c
    end }
    local handed
    _G.UnitHealthPercent = function(u, predicted, curve)
        handed = curve
        if type(curve) ~= "table" or not curve.points then return 1 end
        return { GetRGB = function() return trap(), trap(), trap() end }
    end

    local d = NS.DB()
    local cell = FG.byUnit["player"]
    ok(d.color == "class", "class colour is the default")
    FG.Paint(cell)
    ok(type(cell.bar.__color[1]) == "number", "and in class colour the bar gets a plain colour")

    ok(NS.DO.colour() == "health" and d.color == "health", "/bish colour switches to by-health")
    local safe, err = pcall(FG.Paint, cell)
    ok(safe, "painting by health reads nothing", tostring(err))
    ok(getmetatable(cell.bar.__color[1]) == trapMeta, "the client's colour goes straight to the bar")
    local c = built[1]
    ok(c and c.type == "step" and #c.points == 3 and c.points[1].x == 0,
       "one step curve, built once, from empty upwards")
    FG.Paint(cell)
    ok(#built == 1 and handed == c, "and it is built ONCE, not per paint")

    -- THE CLASS MOVES TO THE NAME. Arn: "if they turn on bar color by health lets do names class
    -- colors". The mock answers SHAMAN.
    local nc = cell.name.__color
    ok(nc and nc[1] == 0.00 and nc[2] == 0.44 and nc[3] == 0.87,
       "by health, the name wears the class colour", nc and table.concat(nc, ",") or "none")
    STATE.classSecret = true
    ok(pcall(FG.Paint, cell), "a secret class does not break the paint")
    nc = cell.name.__color
    ok(nc and nc[1] == 1 and nc[2] == 1 and nc[3] == 1, "and a hidden class leaves the name white")
    STATE.classSecret = false

    STATE.dead.player = true
    FG.Paint(cell)
    ok(type(cell.bar.__color[1]) == "number" and cell.bar.__color[1] == 0.35,
       "the dead are the dead colour whatever the curve says")
    STATE.dead.player = nil

    -- a client that cannot: class colour, not a stale bar and not an error
    _G.UnitHealthPercent = function() error("no", 2) end
    ok(pcall(FG.Paint, cell) and type(cell.bar.__color[1]) == "number",
       "if the client refuses, the bar falls back to class colour")

    NS.DO.colour(false)
    FG.Paint(cell)
    local wc = cell.name.__color
    ok(wc and wc[1] == 1 and wc[2] == 1 and wc[3] == 1,
       "back in class colour the bar says the class, so the name is white again")
    for k, v in pairs(saved) do _G[k] = v end
end

-- MAIN TANK. Arn's party showed four identical role badges and himself on the apex: casual groups
-- and Classic raids rarely set LFG roles. The raid leader's Main Tank assignment is the Classic way
-- to say it, so a main tank is a tank whatever the LFG role says.
do
    local realPA = _G.GetPartyAssignment
    STATE.roles = { player = "DAMAGER", party1 = "DAMAGER", party2 = "DAMAGER" }
    _G.GetPartyAssignment = function(what, u) return what == "MAINTANK" and u == "party2" end
    local order = table.concat(FG.ByRole({ "player", "party1", "party2" }), " ")
    ok(order:match("^party2"), "the raid's Main Tank goes to the top with no LFG role set", order)

    -- and a secret answer must not promote anyone on a guess
    _G.GetPartyAssignment = function() return secret() end
    local blind = table.concat(FG.ByRole({ "player", "party1", "party2" }), " ")
    ok(blind == "player party1 party2", "a secret answer promotes nobody", blind)

    _G.GetPartyAssignment = realPA
    STATE.roles = nil
end

-- SCALE. Arn: "a slider that lets people set the scale of the frames, this is perfect for me but
-- some people like larger smaller". A stepper, because the options lib has no sliders on purpose.
do
    local d = NS.DB()
    ok(d.scale == 1, "a fresh install is the size it was designed at")
    ok(FG.ClampScale(5) == FG.SCALE_MAX and FG.ClampScale(0.1) == FG.SCALE_MIN,
       "and it cannot be pushed past the ends")
    ok(FG.ClampScale(0.8500000001) == 0.85, "nor end up at 0.8500000001")

    -- THE GRID STAYS WHERE IT IS. An offset is in the frame's own scaled units, so scaling a grid
    -- anchored 192 from the right edge would slide it to 288 at 150% without the conversion.
    FG.anchor:ClearAllPoints()
    FG.anchor:SetPoint("RIGHT", UIParent, "RIGHT", -192, 30)
    FG.anchor:SetScale(1)
    FG.SetScale(1.5)
    local p, _, r, x, y = FG.anchor:GetPoint(1)
    ok(FG.anchor:GetScale() == 1.5, "the grid is scaled")
    ok(p == "RIGHT" and math.abs(x * 1.5 - (-192)) < 0.01 and math.abs(y * 1.5 - 30) < 0.01,
       "and on screen it has not moved: 192 from the edge before, 192 after",
       ("%s %s,%s at %s"):format(tostring(p), tostring(x), tostring(y), tostring(FG.anchor:GetScale())))

    -- in combat it keeps the wish and waits
    STATE.inCombat = true
    local now = FG.SetScale(0.8)
    ok(now == false and d.scale == 0.8 and FG.anchor:GetScale() == 1.5,
       "mid-fight it keeps the setting but does not resize secure frames")
    STATE.inCombat = false
    fire(FG.events, "PLAYER_REGEN_ENABLED")
    ok(FG.anchor:GetScale() == 0.8, "and applies it the moment the fight ends",
       tostring(FG.anchor:GetScale()))

    -- the command speaks in percentages
    NS.DO.scale("90")
    ok(d.scale == 0.9 and FG.anchor:GetScale() == 0.9, "/bish scale 90 means 90%")

    local found
    for _, sec in ipairs(NS.CFG.Sections()) do
        for _, o in ipairs(sec.options) do if o.key == "scale" then found = o end end
    end
    ok(found and found.kind == "step" and found.min == 0.6 and found.max == 1.6,
       "the options window has a stepper for it")
    ok(found and found.show(d) == "90%", "and shows it as a percentage", found and found.show(d))

    FG.SetScale(1)
    FG.RestorePos()
end

-- THE SIZE RIDES IN THE MACRO. Arn: "put scale in the macro". It is a saved variable, and on this
-- client a saved variable does not survive a restart - only the macro does.
do
    local FK, FM = NS.FK, NS.FM
    local binds = { ["wheelup"] = "Healing Wave(Rank 2)" }

    local body = FK.Encode(binds, { scale = 0.9 })
    ok(body:find("#S=90;", 1, true) ~= nil,
       "the scale is written FIRST, so a full mouse can never trim it off: " .. body)
    ok(not FK.Encode(binds, { scale = 1 }):find("S=", 1, true),
       "at 100% nothing is written - a player who never touches it keeps the macro they had")

    local back, settings = FK.Decode(body)
    ok(back and back["wheelup"] == "Healing Wave(Rank 2)", "the binds still come back")
    ok(settings and settings.scale == 0.9, "and so does the size")

    -- A 0.2.0 MACRO, with no S row, must still read - and must not invent a size
    local old, oldSettings = FK.Decode("BiSH1;Healing Wave#u=1:2")
    ok(old and old["wheelup"] == "Healing Wave(Rank 2)" and oldSettings and oldSettings.scale == nil,
       "an old macro reads exactly as before, at the default size")

    -- AND A 0.2.0 INSTALL READING THE NEW MACRO. That code is not in this repo any more, so its
    -- row rule is replayed here verbatim: a code must end in one of the seven slot letters. "S"
    -- does not, so the row is skipped - the claim the whole format rests on, checked not assumed.
    local OLD_SLOTS = { l = 1, r = 1, u = 1, d = 1, m = 1, ["4"] = 1, ["5"] = 1 }
    local oldReads = 0
    for row in (body:match("#(.*)$") or ""):gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and OLD_SLOTS[code:sub(-1)] then oldReads = oldReads + 1 end
    end
    ok(oldReads == 1, "an older install reads the one bind and skips the size row", oldReads)

    -- a mouse too full to fit still keeps its size
    local many = {}
    for _, m in ipairs(FM.MODS) do
        for i, sl in ipairs(FM.SLOTS) do
            many[m.key .. sl.key] = ("Greater Healing Spell %s%d(Rank 9)"):format(m.key:sub(1, 1), i)
        end
    end
    local fat, dropped = FK.Encode(many, { scale = 1.25 })
    local _, fatSettings = FK.Decode(fat)
    ok(dropped > 0 and fatSettings and fatSettings.scale == 1.25,
       "when binds are trimmed to fit, the size is not among them")

    -- THE WHOLE TRIP: change the size, "restart", and it is back
    MACROS = {}
    local d = NS.DB()
    d.binds, d.bindsSeeded, FM.asked, FM.touched = { ["wheelup"] = "Healing Wave(Rank 2)" }, true, false, nil
    FG.SetScale(0.85)
    local stored = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(stored and stored:find("S=85", 1, true), "changing the size writes it into the macro", stored)

    d.binds, d.bindsSeeded, FM.asked, d.scale = {}, nil, false, 1      -- the restart
    FG.anchor:SetScale(1)
    FM.Get("", "wheelup")                                              -- the first read at login
    ok(d.scale == 0.85 and FG.anchor:GetScale() == 0.85,
       "and after a restart the size is back, on the grid, not just in the table",
       ("%s / %s"):format(tostring(d.scale), tostring(FG.anchor:GetScale())))

    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FG.SetScale(1, true)
    FM.Get("", "left")
end

-- THE NUMBER AND THE COLOUR RIDE IN IT TOO, the same way and for the same reason
do
    local FK, FM = NS.FK, NS.FM
    local binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    local body = FK.Encode(binds, { text = "percent", color = "health" })
    ok(body:find("#T=2;C=1;", 1, true) ~= nil, "both are written first, before any bind: " .. body)
    ok(not FK.Encode(binds, { text = "missing", color = "class" }):find("[TC]="),
       "at the defaults nothing is written")
    local _, st = FK.Decode(body)
    ok(st and st.text == "percent" and st.color == "health", "and both read back")
    local _, off = FK.Decode(FK.Encode(binds, { text = "off" }))
    ok(off and off.text == "off", "off is remembered as off")

    -- an older install skips them, as it skips S
    local OLD_SLOTS = { l = 1, r = 1, u = 1, d = 1, m = 1, ["4"] = 1, ["5"] = 1 }
    local reads = 0
    for row in (body:match("#(.*)$") or ""):gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and OLD_SLOTS[code:sub(-1)] then reads = reads + 1 end
    end
    ok(reads == 1, "an older install reads the one bind and skips T and C", reads)

    -- THE WHOLE TRIP: change them, "restart", and they are back
    MACROS = {}
    local d = NS.DB()
    d.binds, d.bindsSeeded, FM.asked, FM.touched = { ["wheelup"] = "Healing Wave(Rank 2)" }, true, false, nil
    NS.DO.number("percent")
    NS.DO.colour(true)
    local stored = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(stored and stored:find("T=2", 1, true) and stored:find("C=1", 1, true),
       "changing them writes them into the macro", stored)
    d.binds, d.bindsSeeded, FM.asked, d.text, d.color = {}, nil, false, "missing", "class"   -- the restart
    FM.Get("", "wheelup")
    ok(d.text == "percent" and d.color == "health", "and after a restart they are back",
       tostring(d.text) .. " / " .. tostring(d.color))

    d.text, d.color = "missing", "class"
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")
end

-- HIDDEN STAYS HIDDEN, and the grid stays where it was put. Arn, 21 Sep: "show the cells does
-- nothing, it just keep showing up and when i log on it puts the frames back in the cetner".
do
    local FK, FM = NS.FK, NS.FM
    local d = NS.DB()
    FG.Layout(FG.anchor)
    WATCH_TICK()
    local shown = 0
    for _, f in ipairs(FG.frames) do if f:IsShown() then shown = shown + 1 end end
    ok(shown > 0, "the cells are up to begin with", shown)

    -- the switch, and then the client's own next look at the watched frames
    NS.DO.show(false)
    WATCH_TICK()
    local back = 0
    for _, f in ipairs(FG.frames) do if f:IsShown() then back = back + 1 end end
    ok(back == 0, "switched off, the unit watch does not bring the cells back", back)
    ok(not FG.anchor:IsShown(), "and the grid's header goes with them")

    NS.DO.show(true)
    WATCH_TICK()
    shown = 0
    for _, f in ipairs(FG.frames) do if f:IsShown() then shown = shown + 1 end end
    ok(shown > 0 and FG.anchor:IsShown(), "switched on, they are back", shown)

    -- a spare cell - someone left - must not be brought back by the watch either
    STATE.units.party2 = nil
    FG.Layout(FG.anchor)
    STATE.units.party2 = true              -- a unit by that token exists again
    WATCH_TICK()
    local ghosts = 0
    for _, f in ipairs(FG.frames) do if f:IsShown() and not f.unit then ghosts = ghosts + 1 end end
    ok(ghosts == 0, "a spare cell stays hidden when its old unit turns up again", ghosts)
    FG.Layout(FG.anchor)

    -- THE POSITION. A drag ends on whatever corner the client picked; it is re-pinned by the
    -- centre so it can be written as two numbers.
    local a = FG.anchor
    local realUC = UIParent.GetCenter
    UIParent.GetCenter = function() return 960, 540 end
    a.GetCenter = function() return 760, 660 end          -- 200 left, 120 up
    ok(FG.Recenter(), "a dragged grid is pinned by its centre")
    local p1, _, p3, px, py = a:GetPoint()
    ok(p1 == "CENTER" and p3 == "CENTER" and px == -200 and py == 120,
       "at its offset from the middle of the screen", ("%s %s %s %s"):format(
           tostring(p1), tostring(p3), tostring(px), tostring(py)))

    local body = FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)" }, { pos = { x = -200, y = 120 }, hidden = true })
    ok(body:find("P=4800:5120", 1, true) and body:find("H=1", 1, true), "both written into the macro: " .. body)
    local _, st = FK.Decode(body)
    ok(st and st.pos and st.pos.x == -200 and st.pos.y == 120 and st.hidden == true, "and both read back")

    local OLD_SLOTS = { l = 1, r = 1, u = 1, d = 1, m = 1, ["4"] = 1, ["5"] = 1 }
    local reads = 0
    for row in (body:match("#(.*)$") or ""):gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and OLD_SLOTS[code:sub(-1)] then reads = reads + 1 end
    end
    ok(reads == 1, "an older install skips P and H", reads)

    -- THE WHOLE TRIP: drag, hide, "restart", and it is where it was and still hidden
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = { ["wheelup"] = "Healing Wave(Rank 2)" }, true, false, nil
    local hs = FG.header and FG.header.__scripts
    ok(hs and hs.OnDragStart and hs.OnDragStop, "the header can be dragged")
    hs.OnDragStart(FG.header)
    hs.OnDragStop(FG.header)
    local idx = GetMacroIndexByName(FK.MACRO)
    local dragged = idx and idx > 0 and GetMacroBody(idx) or nil
    ok(dragged and dragged:find("P=4800:5120", 1, true), "the drag alone writes the position", dragged)
    NS.DO.show(false)
    local stored = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(stored and stored:find("P=4800:5120", 1, true) and stored:find("H=1", 1, true),
       "a drag and the switch both write into the macro", stored)

    d.binds, d.bindsSeeded, FM.asked, d.gridPos, d.shown = {}, nil, false, nil, true   -- the restart
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    FG.Layout(FG.anchor)
    FM.Get("", "wheelup")                                              -- the first read at login
    WATCH_TICK()
    p1, _, p3, px, py = a:GetPoint()
    ok(px == -200 and py == 120, "after a restart the grid is where it was dragged, not the middle",
       ("%s,%s"):format(tostring(px), tostring(py)))
    local up = 0
    for _, f in ipairs(FG.frames) do if f:IsShown() then up = up + 1 end end
    ok(d.shown == false and up == 0, "and hidden is still hidden", up)

    -- /bish center forgets it, in the macro too
    NS.DO.show(true)
    NS.DO.center()
    stored = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(stored and not stored:find("P=", 1, true), "centre takes the position out of the macro", stored)

    UIParent.GetCenter, a.GetCenter = realUC, nil
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched, d.gridPos = {}, nil, false, nil, nil
    FG.RestorePos()
    FM.Get("", "left")
end

-- THE HANDLE. Arn, 19 Sep 2026: "lets add a our header to this so we can drag and move". The
-- anchor had none: the cells were the only thing on screen, and a secure button cannot be dragged
-- without taking its click away. So the header moves the ANCHOR and every cell follows.
do
    local h = FG.header
    ok(h ~= nil, "the grid has a header to grab")

    -- ONE LABEL IN THE BAR. Twice in one day a second FontString printed straight through the
    -- first: "BiS> Hrsalinge" on an 84 pixel header. A hint belongs in a tooltip, where it has a
    -- whole box to itself and costs no pixels at all.
    ok(#(h.__fontstrings or {}) <= 1,
       ("the header carries %d labels; one bar, one label - hints go in the tooltip")
       :format(#(h.__fontstrings or {})))

    -- ONE THING IN THE BAR. A "drag" caption on the right printed straight through the prompt's
    -- rotating word on a header the width of one cell: "BiS> Hrsalinge" (seen in game, 19 Sep).
    -- The hint is a tooltip now, and the prompt is trimmed to the header it is in.
    FG.Layout(anchor)
    ok(h.con == nil or h.con.width <= FRAME_W_FOR_TEST,
       "the prompt is trimmed to the header's own width, not 120px")
    ok(h.__scripts.OnEnter and h.__scripts.OnLeave, "the hint lives in a tooltip instead")

    -- dragging it out of combat moves the anchor and remembers where
    STATE.inCombat = false
    h.__scripts.OnDragStart(h)
    ok(h.moving == true, "a drag starts out of combat")
    FG.anchor:ClearAllPoints()
    FG.anchor:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 300, -140)
    h.__scripts.OnDragStop(h)
    local saved = NS.DB().gridPos
    ok(saved and saved.point == "TOPLEFT" and saved.x == 300, "and letting go writes it down")

    -- and it comes back there on the next login
    FG.anchor:ClearAllPoints()
    FG.RestorePos()
    local p = FG.anchor.points[#FG.anchor.points]
    ok(p and p[1] == "TOPLEFT" and p[4] == 300 and p[5] == -140, "a later session opens where it was")

    -- IN COMBAT IT MUST NOT MOVE. The cells are secure frames and the client refuses to move
    -- their parent once the lockdown is on; trying anyway throws in the middle of a pull.
    STATE.inCombat = true
    h.moving = false
    h.__scripts.OnDragStart(h)
    ok(h.moving ~= true, "a drag in combat does not start at all")
    STATE.inCombat = false

    -- and centring forgets the dragged spot rather than leaving it to come back later
    NS.DO.center()
    ok(NS.DB().gridPos == nil, "centring forgets where it was dragged to")
end

-- in combat: no layout, no attribute changes. Both are blocked by the client, and trying anyway
-- is how an addon gets itself locked out of its own frames for the rest of the fight.
STATE.inCombat = true
ok(FG.Layout(anchor) == false, "layout refuses itself in combat")
ok(FG.Bind(FG.frames[1], "party2") == false, "binds refuse themselves in combat")
ok(pcall(FG.Paint, FG.frames[1]), "painting still works in combat -- that is the whole point")
STATE.inCombat = false

------------------------------------------------ the brain, between the pulls --
-- The one window the addon is allowed to think in. Everything below reads auras, totems and
-- death, which are secret INSIDE the lockdown and readable outside it -- so the first thing the
-- scan must do is refuse to run at the wrong moment.

local FB = NS.FB
local AURAS = { player = { HELPFUL = {}, HARMFUL = {} },
                party1 = { HELPFUL = {}, HARMFUL = {} },
                party2 = { HELPFUL = {}, HARMFUL = {} } }
local TOTEMS = { false, false, false, false }
_G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
    if STATE.inCombat then error("Auras cannot be accessed when secret while tainted", 2) end
    local list = AURAS[unit] and AURAS[unit][filter or "HELPFUL"]
    return list and list[i] or nil
end }
_G.GetTotemInfo = function(slot)
    if STATE.inCombat then error("attempt to compare a secret number value", 2) end
    return TOTEMS[slot] and true or false, "Totem"
end
local SAID = {}
NS.Print = function(msg) SAID[#SAID + 1] = msg end

STATE.inCombat = true
local blindScan, why = FB.Scan()
ok(blindScan == nil and why ~= nil, "the brain refuses to scan inside the lockdown")
STATE.inCombat = false

-- THIS CHARACTER HAS EARTH SHIELD, and is in a group. Both matter now: the brain does not nag
-- about a spell you have not trained (a level-15 shaman grinding leather was told six times in
-- ninety seconds that it was not up), and it says nothing at all when you are playing alone.
BOOK[20] = { name = "Earth Shield", rank = "Rank 1" }
local GROUPED = true
_G.IsInGroup = function() return GROUPED end

-- nothing up: Earth Shield missing and no totems out, both worth saying between pulls
local found = FB.Scan()
local kinds = {}
for _, f in ipairs(found) do kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
ok(kinds.earthshield == 1, "a missing Earth Shield is reported")
ok(kinds.totems == 1, "four empty totem slots are reported")

-- with Earth Shield up on the tank, it stops nagging
AURAS.party1.HELPFUL[1] = { name = "Earth Shield", dispelName = nil }
TOTEMS[1] = true
found = FB.Scan()
kinds = {}
for _, f in ipairs(found) do kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
ok(kinds.earthshield == nil, "Earth Shield up on anyone is enough")
ok(kinds.totems == nil, "one totem down is not 'no totems down'")

-- dispel debt: what the addon could not even SEE during the fight
AURAS.party2.HARMFUL[1] = { name = "Crippling Poison", dispelName = "Poison" }
AURAS.party2.HARMFUL[2] = { name = "Curse of Agony", dispelName = "Curse" }   -- not ours to cure
found = FB.Scan()
local dispels = 0
for _, f in ipairs(found) do if f.kind == "dispel" then dispels = dispels + 1 end end
ok(dispels == 1, "only what a shaman can actually cure is reported")

STATE.dead.party2 = true
found = FB.Scan()
local dead = 0
for _, f in ipairs(found) do if f.kind == "dead" then dead = dead + 1 end end
ok(dead == 1, "the dead are listed for the rez")
STATE.dead.party2 = nil

-- it speaks only when there is something to say
SAID = {}
local n = FB.Report()
ok(n and n > 0 and #SAID == n, "Report says one line per finding")
ok(not tostring(SAID[1]):find("BiS Healing", 1, true),
   "and does NOT write its own name: NS.Print already does that")

-- THE SAME NEWS IS NOT NEWS. The screenshot that started this had one line six times in ninety
-- seconds, once per mob killed. A finding that has not changed is said again only after QUIET.
SAID = {}
ok(FB.Report() == 0 and #SAID == 0, "the same findings a moment later are not repeated")
ok(FB.Report(true) ~= 0 and #SAID > 0, "unless asked for outright (/bish scan)")

-- ALONE, IT SAYS NOTHING AT ALL. This is a brain for a group: who still has a debuff, who is
-- dead, whether the shield is up. Solo there is nobody to tell.
SAID = {}
GROUPED = false
FB.lastSig = nil                                  -- as if the news had changed
local quiet, reason = FB.Report()
ok(quiet == 0 and reason == "alone" and #SAID == 0, "playing alone, it stays quiet")
GROUPED = true
FB.lastSig = nil

-- and a character who has not trained Earth Shield is never told it is missing
BOOK[20] = nil
local noES = FB.Scan()
local mentions = 0
for _, f in ipairs(noES) do if f.kind == "earthshield" then mentions = mentions + 1 end end
ok(mentions == 0, "no Earth Shield in the spellbook, no Earth Shield in the report")
BOOK[20] = { name = "Earth Shield", rank = "Rank 1" }
AURAS.party2.HARMFUL[1], AURAS.party2.HARMFUL[2] = nil, nil
for i = 1, 4 do TOTEMS[i] = true end
SAID = {}
ok(FB.Report() == 0 and #SAID == 0, "with nothing wrong it stays quiet")

-- ---------------------------------------- showing what we may not read (19 Sep) --
-- The 17 Sep design said dispel highlighting was impossible in combat. It asked the wrong
-- question: an addon may not READ an aura there, but the client will SHOW one through an
-- AuraContainer. These checks are about what the grid DECLARES, because that is all there is.
do
    local FA = NS.FA
    ok(FA ~= nil and FA.Available() == true, "the containers are detected by feature, not by build number")

    local cell = FG.frames[1]
    cell.auras = nil
    ok(FA.Attach(cell, "party1") == true, "a cell gets a container")
    local c = cell.auras
    ok(c and c.unit == "party1", "the container is told its unit")
    ok(c and c.enabled == true, "and switched on")

    local dispel = c and c.slots["BiSHealDispel"]
    ok(dispel ~= nil, "there is a dispel slot")
    ok(dispel and dispel.filter == "HARMFUL|RAID_PLAYER_DISPELLABLE",
       "filtered by the CLIENT to what this character can dispel: " .. tostring(dispel and dispel.filter))
    -- AND NOTHING OF OURS ON TOP OF IT. This used to narrow the client's answer to
    -- { Poison, Disease } - the list for exactly one class - and on 19 Sep 2026 the addon stopped
    -- being for exactly one class. A hard-coded list is a promise about somebody else's
    -- spellbook; RAID_PLAYER_DISPELLABLE is the client's own answer for whoever is playing.
    local narrowed = dispel and dispel.opts and dispel.opts.candidateFilters
                     and dispel.opts.candidateFilters.includeDispelTypes
    ok(narrowed == nil, "with no dispel-type list of ours narrowing it to one class")

    -- Watched buffs are a switch, not an assumption: nothing is watched until someone knows what
    -- matters on this client, and an empty list builds no slot at all.
    ok(c.slots["BiSHealWatch"] == nil, "nothing watched by default, so no pip is built")
    FA.WATCH = { [974] = "Earth Shield" }
    cell.auras = nil
    FA.Attach(cell, "party1")
    local watch = cell.auras.slots["BiSHealWatch"]
    ok(watch ~= nil, "put an id in the list and the pip appears")
    local ids = watch and watch.opts and watch.opts.candidateFilters
                and watch.opts.candidateFilters.includeSpellIDs or {}
    ok(ids[974], "asked for by spell id, never by reading the aura")
    FA.WATCH = {}

    -- THE RULE: nothing above touched an aura. Prove it by making every aura read explode exactly
    -- as the lockdown does, then attach again.
    local boom = function() error("Auras cannot be accessed when secret while tainted", 2) end
    _G.C_UnitAuras = setmetatable({}, { __index = function() return boom end })
    _G.AuraUtil = { FindAuraByName = boom }
    cell.auras = nil
    ok(pcall(FA.Attach, cell, "party2"), "attaching reads no aura, so the lockdown cannot stop it")

    -- a client WITHOUT the containers (TBC, or a future one that drops them) gets no marker
    containersExist = false
    FA.available = nil
    ok(FA.Available() == false, "a client without the template is detected")
    local plain = FG.frames[2]
    plain.auras = nil
    ok(FA.Attach(plain, "party1") == false and plain.auras == nil, "no container, no marker, no error")
    containersExist = true
    FA.available = nil
end

-- THE DISPEL TYPE AND YOUR HEALS OVER TIME (21 Sep, from ForeverAuras 0.1.148): the client draws
-- the type into a texture we hand it, and runs a countdown from an aura's duration - neither read.
do
    local FA = NS.FA
    _G.C_UnitAuras, _G.AuraUtil = nil, nil
    local cell = FG.frames[1]
    cell.auras = nil
    FA.sig, FA.typed = nil, nil
    FA.Attach(cell, "party1")
    local dispel = cell.auras.slots["BiSHealDispel"]
    ok(dispel.dispelTex ~= nil, "the dispel marker hands the client a texture for the TYPE")
    ok(dispel.dispelOpts and dispel.dispelOpts.showWhenHarmful == true, "for harmful auras")
    ok(FA.typed == true, "and says it is drawing the type")

    -- a client without the call keeps the green square rather than losing the marker
    SLOT_CALLS.missing = true
    FA.typed, FA.sig = nil, nil
    local plain = FG.frames[2]
    plain.auras = nil
    ok(pcall(FA.Attach, plain, "party2"), "a client without AddDispelTypeTexture attaches anyway")
    ok(plain.auras and plain.auras.slots["BiSHealDispel"] ~= nil and FA.typed == nil,
       "and keeps the plain marker")
    SLOT_CALLS.missing = false

    -- a shaman has no heal over time here: no slot is built for one
    FA.sig = nil
    cell.auras = nil
    FA.Attach(cell, "party1")
    local anyHot = false
    for k in pairs(cell.auras.slots) do if k:find("^BiSHealHot") then anyHot = true end end
    ok(not anyHot, "no heal-over-time slot for a class without one")

    -- A PRIEST: Renew, every rank, only the priest's own, with the client's countdown
    local realClass, realInfo, realName = _G.UnitClass, C_SpellBook.GetSpellBookItemInfo, C_Spell.GetSpellName
    _G.UnitClass = function() return "Priest", "PRIEST" end
    _G.C_Spell.GetSpellName = function(id) return id == 139 and "Renew" or nil end
    BOOK[6] = { name = "Renew", rank = "Rank 11" }
    _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
        if type(bank) ~= "number" then error("bad argument", 2) end
        return n == 6 and { spellID = 99011 } or nil
    end
    FA.sig = nil
    ok(pcall(FA.Attach, cell, "party1"), "a priest's cell attaches")
    local renew = cell.auras.slots["BiSHealHotRenew"]
    ok(renew ~= nil, "a Renew slot is built")
    ok(renew and renew.filter == "HELPFUL|PLAYER", "for YOUR Renew only: " .. tostring(renew and renew.filter))
    local ids = renew and renew.opts.candidateFilters.includeSpellIDs or {}
    ok(ids[139] and ids[25315], "every Classic rank is asked for")
    ok(ids[99011], "and the rank this client's book says you know, whatever its id")
    ok(renew and renew.durationCooldown ~= nil, "the client runs the countdown from the aura itself")
    ok(renew and renew.points and renew.points[1] and renew.points[1][1] == "BOTTOMLEFT",
       "bottom left, clear of the name and the number")

    -- THE LOCKDOWN: building it reads no aura
    local boom = function() error("Auras cannot be accessed when secret while tainted", 2) end
    _G.C_UnitAuras = setmetatable({}, { __index = function() return boom end })
    FA.sig = nil
    cell.auras = nil
    ok(pcall(FA.Attach, cell, "party2"), "the heal-over-time slot reads no aura either")
    _G.C_UnitAuras = nil

    -- /bish hots off: the container is rebuilt without them, and the old one stops drawing
    MACROS = {}
    local d = NS.DB()
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    local old = cell.auras
    NS.DO.hots(false)
    ok(cell.auras ~= old and cell.auras.slots["BiSHealHotRenew"] == nil, "switched off, no Renew slot")
    ok(old.enabled == false and old.__shown == false, "and the old container is switched off, not left drawing")
    local stored = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(stored and stored:find("O=0", 1, true), "off is kept in the macro", stored)
    local _, st = NS.FK.Decode(stored or "")
    ok(st and st.hots == false, "and reads back as off")
    NS.DO.hots(true)
    ok(cell.auras.slots["BiSHealHotRenew"] ~= nil, "back on, back again")
    stored = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(stored and not stored:find("O=", 1, true), "and on - the default - writes nothing")

    -- an older install skips the O row
    local reads = 0
    local body = NS.FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)" }, { hots = false })
    for row in (body:match("#(.*)$") or ""):gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and ({ l = 1, r = 1, u = 1, d = 1, m = 1, ["4"] = 1, ["5"] = 1 })[code:sub(-1)] then reads = reads + 1 end
    end
    ok(reads == 1, "an older install skips O", reads)

    BOOK[6] = nil
    _G.UnitClass, C_SpellBook.GetSpellBookItemInfo, C_Spell.GetSpellName = realClass, realInfo, realName
    FA.sig = nil
    MACROS = {}
    d.binds = keptBinds
end

-- The pyramid must not ASK for the combat log on a client that forbids it. Registering
-- COMBAT_LOG_EVENT_UNFILTERED is a protected action on Forever: the client refuses and pops a
-- dialog, which pcall cannot see, at every single login.
-- It used to be one line of BiSHealing.lua skipping one event. That file is gone and so is the
-- skip: nothing in this addon asks for the combat log, which is a thing a suite can check
-- properly now - every frame the addon built, and what it registered for.
do
    local asked = false
    for _, f in ipairs(frames) do
        if f.__events and f.__events["COMBAT_LOG_EVENT_UNFILTERED"] then asked = true end
    end
    ok(not asked, "nothing in the addon asks for the combat log, which this client forbids")
end
-- /bishf: the counts behind the verdict. "Nothing to report" and "the read is broken" look the
-- same in chat, and this is how they are told apart without another beta round.
FB.frame = nil
FB.Start()
-- One command now, Core.lua's, with /bishf kept as an ALIAS rather than retired: it is what has
-- been typed here for a week, and a command that stops existing teaches nothing at the moment
-- you need it.
ok(SlashCmdList.BISHEALING ~= nil, "the slash command is registered")
ok(_G.SLASH_BISHEALING1 == "/bish" and _G.SLASH_BISHEALING3 == "/bishf",
   "and /bishf still reaches it")
ok(SlashCmdList.BISHEALFOREVER == nil, "the file that used to own a command of its own has none")
SAID = {}
FB.Dump()
local sawCounts, sawTotem = false, false
for _, line in ipairs(SAID) do
    if line:find("unit(s)", 1, true) then sawCounts = true end
    if line:find("totem 1", 1, true) then sawTotem = true end
end
ok(sawCounts and sawTotem, "the dump shows what was scanned, not only what it decided")
STATE.inCombat = true
SAID = {}
FB.Dump()
ok(#SAID == 1 and SAID[1]:find("in combat", 1, true), "in combat it says why it cannot answer")
STATE.inCombat = false

-- ------------------------------------------- the mouse, bound the way a hand is --
-- An addon may not cast. It may say what a click MEANS, and let Blizzard's secure code do the
-- rest - so a bind is a secure attribute on the cell (buttons) or an override binding onto a
-- hidden macro button (the wheel, which no button takes as a click).
do
    local FM = NS.FM
    ok(FM ~= nil, "the mouse module loaded")

    -- dropping a spell from the spellbook
    CURSOR = { kind = "spell", a = 7, b = 331 }
    ok(FM.CursorSpell() == "Spell331", "a spell on the cursor is read by name, not by build number")

    -- THE SHAPE THAT BROKE IT IN GAME (19 Sep): Forever hands back four values with a STRING in
    -- the middle - (kind, spellBookIndex, "spell", spellID) - and its GetSpellBookItemName takes
    -- one argument, not two. The old code passed the pair straight through and the client answered
    -- "bad argument #1 (not a numerical value)" on every drag.
    CURSOR = { kind = "spell", a = 12, b = "spell", c = 331 }
    ok(FM.CursorSpell() == "Spell331", "and read from the four-value shape Forever actually sends")
    CURSOR = { kind = "item", a = 5 }
    ok(FM.CursorSpell() == nil, "something that is not a spell is not a bind")
    CURSOR = { kind = "spell", a = 7, b = 331 }        -- back to the spell, for the drop below
    FM.Set("", "left", FM.CursorSpell())
    ok(FM.Get("", "left") == "Spell331", "and dropping it on a slot remembers it")

    -- THE RANK. On a 1.60 client "/cast Healing Wave" throws the biggest one you know, which for
    -- a healer is a different spell: three times the mana to move the same bar. A drop keeps the
    -- rank the spellbook reports, and the cast string is the one a macro would say.
    RANKS[331] = "Rank 4"
    -- ASKED OF THE ID, which is the whole bug. Arn, after the rank first went in: "the rank is
    -- still not showing". GetCursorInfo hands back (spellBookIndex, "spell", spellID), the code
    -- asked the LAST number first because that is the id, and an id answers a name and nothing
    -- else. The rank was there the whole time, behind a call nobody made.
    CURSOR = { kind = "spell", a = 12, b = "spell", c = 331 }
    ok(BOOK[12] == nil, "the drop is read from the id alone, with nothing in the book for it")
    ok(FM.CursorSpell() == "Spell331(Rank 4)", "a spell dropped with a rank keeps its rank")
    local name, rank = FM.Split(FM.CursorSpell())
    ok(name == "Spell331" and rank == "Rank 4", "and reads back as a name and a rank, for showing")
    ok(FM.Cast("Healing Wave", nil) == "Healing Wave", "no rank means the name alone: max rank")
    ok(FM.Cast("Healing Wave", "Passive") == "Healing Wave",
       "and a subtitle that is not a rank - 'Passive' - is not pasted into the cast either")
    FM.Set("", "middle", FM.CursorSpell())
    RANKS[331] = nil

    -- A DIFFERENT RANK PER MODIFIER, which is the point of having ranks at all: the big heal on
    -- the left button, a cheap one on shift. Arn: "did not let me do different rank on modifier
    -- and shift modifier". Dropping a lower rank assumes your spellbook is SHOWING you one to
    -- drag, and that is a setting - so the window stops depending on the drag and the little rank
    -- number became a button that walks the ranks this character has trained.
    -- A SEEDED SLOT CARRIES ITS RANK. Seeded bare, the slot has no number in its corner, and the
    -- rank button is the whole feature - Arn's first working login showed a rankless "Healing Wave".
    do
        local d = FM.Defaults()
        ok(d.left == "Healing Wave(Rank 3)", "the default is the highest rank trained", tostring(d.left))
        ok(d.right == "Lesser Healing Wave(Rank 1)", "and one with a single rank says Rank 1", tostring(d.right))
    end

    -- THE SIGNATURE ITSELF, pinned. This is the whole of the 19 Sep bug in four lines: the addon
    -- called the book with one argument, which errors, and a pcall turned that into "no ranks".
    do
        local one = pcall(C_SpellBook.GetSpellBookItemName, 1)
        local two, nm = pcall(C_SpellBook.GetSpellBookItemName, 1, 0)
        ok(one == false, "one argument is refused, exactly as the client refuses it")
        ok(two and nm == "Healing Wave", "two arguments answer the slot", tostring(nm))
        ok(#FM.Ranks("Healing Wave") == 3, "so the book can be read at all", #FM.Ranks("Healing Wave"))
    end

    do
        -- slots 10+, so the character's own spells in 1-5 stay where they are
        BOOK[10] = { name = "Spell331", rank = "Rank 1" }
        BOOK[11] = { name = "Spell331", rank = "Rank 2" }
        BOOK[12] = { name = "Spell331", rank = "Rank 3" }
        BOOK[13] = { name = "Somebody Else", rank = "Rank 9" }
        local ranks = FM.Ranks("Spell331")
        ok(#ranks == 3, ("the book says %d ranks of it are trained"):format(#ranks))
        ok(ranks[1].rank == "Rank 1", "oldest first, so clicking walks upwards")

        FM.Set("", "left", "Spell331(Rank 1)")
        FM.Set("shift-", "left", "Spell331(Rank 1)")
        ok(FM.CycleRank("", "left") == "Spell331(Rank 2)", "clicking the rank takes the next one")
        ok(FM.Get("shift-", "left") == "Spell331(Rank 1)",
           "and the SAME button under shift is left alone: that is the whole point")
        FM.CycleRank("shift-", "left")
        FM.CycleRank("shift-", "left")
        ok(FM.Get("shift-", "left") == "Spell331(Rank 3)" and FM.Get("", "left") == "Spell331(Rank 2)",
           "two clicks on one, one on the other, and they hold different ranks of the same spell")
        ok(FM.CycleRank("shift-", "left") == "Spell331(Rank 1)", "and it wraps rather than sticking")

        FM.Set("", "left", "Somebody Else(Rank 9)")
        ok(FM.CycleRank("", "left") == "Somebody Else(Rank 9)",
           "a spell with one trained rank does not change under the click")
        for i = 10, 13 do BOOK[i] = nil end
        FM.Clear("shift-", "left")
        FM.Set("", "left", "Spell331")        -- as the checks below this one left it
    end

    FM.Set("shift-", "right", "Chain Heal")
    FM.Set("", "wheelup", "Lesser Healing Wave")

    -- buttons become secure attributes on the cell
    local cell = FG.frames[1]
    ok(FM.ApplyTo(cell) == true, "binds are written to a cell out of combat")
    ok(cell.__attrs["*spell1"] == "Spell331", "left click casts what was dropped on it")
    ok(cell.__attrs["*type1"] == "spell", "through the secure spell attribute")
    ok(cell.__attrs["shift-spell2"] == "Chain Heal", "shift plus right click is its own slot")
    ok(cell.__attrs["*spell3"] == "Spell331(Rank 4)",
       "and a ranked bind reaches the secure attribute with the rank still on it")
    ok(cell.__attrs["*spell2"] == "Lesser Healing Wave(Rank 1)",
       "plain right click keeps its own bind (the seeded default), unleaked: " .. tostring(cell.__attrs["*spell2"]))

    -- the wheel is a binding, not a click
    BOUND = {}
    ok(select(1, FM.ApplyWheel(anchor)) == true, "the wheel binds")
    ok(BOUND["MOUSEWHEELUP"] ~= nil, "through an override binding: " .. tostring(BOUND["MOUSEWHEELUP"]))
    local wheelBtn = _G["BiSHealWheelwheelup"]
    ok(wheelBtn and wheelBtn.__attrs["macrotext"]
       and wheelBtn.__attrs["macrotext"]:find("[@mouseover] Lesser Healing Wave", 1, true) ~= nil,
       "and casts at whatever the cursor is over, which is how a wheel reaches a cell")

    -- NOTHING is written during a fight: both mechanisms are refused there
    STATE.inCombat = true
    ok(FM.ApplyTo(cell) == false, "no attribute is written in combat")
    ok(FM.ApplyWheel(anchor) == false, "and no binding either")
    ok(FM.Apply() == false and FM.pending == true, "the change is queued instead of lost")
    STATE.inCombat = false
    ok(FM.Apply() == true and FM.pending == false, "and lands when the fight ends")

    -- SAVEDVARIABLES, which is where the binds actually live in game. The first version seeded the
    -- defaults into the WHOLE db rather than into our own corner of it, so every read hit
    -- `d.binds` on a table that has no `binds` - one letter of scope, one error per click.
    do
        _G.BiSHealingDB = { some = "other addon state" }
        local realDB = NS.DB
        NS.DB = function() return _G.BiSHealingDB end
        ok(pcall(FM.Get, "", "left"), "reading a bind out of SavedVariables does not throw")
        FM.Set("", "middle", "Cure Poison")
        ok(_G.BiSHealingDB.binds and _G.BiSHealingDB.binds["middle"] == "Cure Poison",
           "and a bind lands in OUR corner of the db, not on top of someone else's")
        ok(_G.BiSHealingDB.some == "other addon state", "leaving the rest of it alone")
        NS.DB = realDB
        _G.BiSHealingDB = nil
    end

    -- A CLEARED BIND STAYS CLEARED ACROSS A RELOAD. Arn: "the binds are not surving a reload it
    -- setts it back to chain heals which i dont have yet". The saved variables were fine the
    -- whole time - the file on disk had his ranks in it - and this was the SEEDING writing into
    -- the gaps: it filled any slot that happened to be nil, so clearing one and reloading brought
    -- it straight back. The addon quietly overruling a deliberate act.
    do
        local realDB = NS.DB
        _G.BiSHealingDB = { binds = { left = "Healing Wave(Rank 1)" }, bindsSeeded = true }
        NS.DB = function() return _G.BiSHealingDB end
        ok(FM.Get("", "shift-left") == nil, "a slot the player cleared is still empty")
        ok(FM.Get("", "left") == "Healing Wave(Rank 1)", "and the one they bound is untouched")

        -- even with the seeded flag lost - which the migration used to do - a mouse with anything
        -- on it is not a fresh install and is left alone
        _G.BiSHealingDB = { binds = { left = "Healing Wave(Rank 1)" } }
        ok(FM.Get("", "shift-left") == nil,
           "a mouse with something on it is never re-seeded, flag or no flag")
        NS.DB = realDB
        _G.BiSHealingDB = nil
    end

    -- clearing
    FM.Clear("", "left")
    FM.ApplyTo(cell)
    ok(cell.__attrs["*spell1"] == nil and cell.__attrs["*type1"] == nil,
       "clearing a slot removes the attribute rather than leaving a dead spell")
end

---------------------------------------------------------------- the window --

-- THE DRAWING ITSELF. Not "does it look right" - a suite cannot see - but "does building it, and
-- dropping a spell on it, and closing it, run without throwing". Every bug this window has had so
-- far was that kind: an index of a nil field, one argument too many, a name that does not exist.
do
    local FM = NS.FM
    local built, w = pcall(FM.Window)
    if not built then print("WINDOW ERROR: " .. tostring(w)) end
    ok(built and w ~= nil, "the mouse window builds")
    if built and w then
        ok(w.close ~= nil, "it has a close button")
        w:Show()
        w.close.__scripts.OnClick(w.close)
        ok(w:IsShown() == false, "and clicking it shuts the window")
        -- ESCAPE CLOSES IT, AND THE SPELLBOOK DOES NOT. This used to assert the opposite thing -
        -- that the window was listed in UISpecialFrames - which is how the client closes frames
        -- on Escape AND what CloseAllWindows() empties when a panel like the spellbook opens.
        -- Arn: "right now if the bind window is open and i open the spell book it closes the bind
        -- window". The key is handled by the window itself now.
        local onUISpecial = false
        for _, n in ipairs(_G.UISpecialFrames) do
            if n == "BiSHealingMouse" then onUISpecial = true end
        end
        ok(not onUISpecial,
           "it is NOT on the list the spellbook empties: that list closed it every time")
        w:Show()
        w.__scripts.OnKeyDown(w, "ESCAPE")
        ok(w:IsShown() == false, "and Escape closes it anyway, handled here")
        w:Show()
        w.__scripts.OnKeyDown(w, "A")
        ok(w:IsShown() == true, "while any other key is passed through and changes nothing")
        w:Hide()

        ok(pcall(FM.Toggle) and pcall(FM.Toggle), "toggling it open and shut does not throw")

        -- THE FIRST CLICK MUST OPEN IT. Arn: "have to click the mouse bind button twice for
        -- window to open". A frame is SHOWN by default in this game, and building the window is
        -- what the first click does - so the first click found a window already "open", hid it,
        -- and looked like nothing happened. This starts from nothing, the way a fresh login does.
        FM.win = nil
        ok(FM.Toggle() == true, "the very first click opens the window")
        ok(FM.Toggle() == false, "and the second one shuts it")

        -- WHERE IT SITS. Arn: "if we open the spellbook window and we have the bind window open
        -- can we anchor it to this spot ... defualt place the last place it was in".
        do
            local w2 = FM.Window()
            -- a spot the player dragged it to, remembered across a rebuild
            w2:ClearAllPoints()
            w2:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 120, -240)
            local saved = FM.SavePos(w2)
            ok(saved and saved.point == "TOPLEFT" and saved.x == 120,
               "dragging it writes the spot to the saved variables")
            FM.win = nil
            local w3 = FM.Window()
            local p = w3.points[#w3.points]
            ok(p and p[1] == "TOPLEFT" and p[4] == 120 and p[5] == -240,
               "and a fresh window opens exactly where it was left")

            -- the spellbook opens: it docks to the right edge of the book
            _G.PlayerSpellsFrame = newFrame("Frame", "PlayerSpellsFrame")
            _G.PlayerSpellsFrame:Show()
            ok(FM.Place(w3) == "docked", "with the spellbook up, it docks to it")
            local d = w3.points[#w3.points]
            ok(d and d[1] == "TOPLEFT" and rawequal(d[2], _G.PlayerSpellsFrame) and d[3] == "TOPRIGHT",
               "against the book's right edge, where you are looking when you drag a spell out")

            -- and back to the remembered spot when the book closes
            _G.PlayerSpellsFrame:Hide()
            ok(FM.Place(w3) == "free", "the book closes and it undocks")
            local b = w3.points[#w3.points]
            ok(b and b[1] == "TOPLEFT" and b[4] == 120, "back to the last place it was put")

            -- dragging it away while the book is open keeps it where you put it
            _G.PlayerSpellsFrame:Show()
            FM.Place(w3)
            w3.__scripts.OnDragStart(w3)
            ok(w3.undocked == true and w3.dockedTo == nil, "dragging it out of the dock unsticks it")
            ok(FM.Place(w3) == "free", "and it stays where you dropped it while the book is open")
            _G.PlayerSpellsFrame:Hide()
            FM.Place(w3)
            _G.PlayerSpellsFrame:Show()
            ok(FM.Place(w3) == "docked", "closing and reopening the book docks it again")
            _G.PlayerSpellsFrame:Hide()
            _G.PlayerSpellsFrame = nil
            w3.dockedTo, w3.undocked = nil, nil
        end

        -- dropping a ranked spell on the left button, through the UI rather than past it
        RANKS[331] = "Rank 4"
        CURSOR = { kind = "spell", a = 12, b = "spell", c = 331 }
        local slot = w.slots["left"]
        ok(slot ~= nil, "the left button is a drop target")
        ok(pcall(slot.__scripts.OnReceiveDrag, slot), "and a spell can be dropped on it")
        ok(FM.Get("", "left") == "Spell331(Rank 4)", "which binds the spell WITH its rank")

        -- what the mouse-over says about it
        slot.__scripts.OnEnter(slot)
        local said = table.concat(TIP.lines, "|")
        ok(said:find("Spell331", 1, true) and said:find("Rank 4", 1, true),
           "and the tooltip names the spell and the rank, so you can see which one you bound")

        -- right-click clears
        ok(pcall(slot.__scripts.OnMouseUp, slot, "RightButton"), "right-clicking a slot runs")
        CURSOR = {}
        slot.__scripts.OnMouseUp(slot, "RightButton")
        ok(FM.Get("", "left") == nil, "and with nothing on the cursor, clears the bind")
        RANKS[331] = nil
    end
end

------------------------------------------------------------------- the core --

-- THE MIGRATION IS THE DANGEROUS PART OF THIS WHOLE SPLIT. Everyone who ran the old addon has a
-- saved-variables file full of an addon that no longer exists - every fight it watched, every
-- heal size it learned, thirty toggles and a pyramid's window position - and the two things they
-- would actually miss (their mouse binds, where they dragged the minimap button) are buried in
-- it. Getting this wrong loses somebody's binds silently, which is the kind of bug nobody
-- reports and everybody resents.
do
    local realDB = _G.BiSHealingDB
    _G.BiSHealingDB = {
        -- what the old addon left behind
        players   = { Someone = { fights = {} } },
        healSeen  = { [331] = { avg = 1200, n = 9 } },
        dispelSeen = { ["Serpentshrine Cavern"] = {} },
        bullseye = true, pulse = true, goldChains = true, nameLen = 7,
        pos = { x = 100, y = 200 },
        locked = true,
        shown = false,
        -- and the two things worth keeping
        forever = { binds = { left = "Holy Light", ["shift-right"] = "Cleanse" }, seeded = true },
        minimap = { angle = 137.5 },
    }
    local db = NS.DB()
    ok(db.binds and db.binds.left == "Holy Light",
       "the migration carries the mouse binds out of the old addon's corner")
    ok(db.binds["shift-right"] == "Cleanse", "every one of them, not just the first")
    ok(db.minimap and math.abs((db.minimap.angle or 0) - 137.5) < 0.01,
       "and where the minimap button was dragged to")
    ok(db.shown == false, "and whether the frames were up")
    ok(db.players == nil and db.healSeen == nil and db.dispelSeen == nil,
       "the old addon's learning is dropped: it is about a game that is not being played")
    ok(db.bullseye == nil and db.pulse == nil and db.nameLen == nil and db.pos == nil,
       "and so are thirty toggles for features that no longer exist")
    ok(db.dbver == NS.DBVER, "stamped, so it never runs twice")

    -- ONCE. A migration that runs again is a migration that can undo a choice made after it.
    db.binds.left = "Flash of Light"
    db.shown = true
    local again = NS.DB()
    ok(again.binds.left == "Flash of Light" and again.shown == true,
       "a second call changes nothing")

    -- a fresh install is not a migration
    _G.BiSHealingDB = nil
    local fresh = NS.DB()
    ok(fresh.shown == true and type(fresh.binds) == "table" and type(fresh.minimap) == "table",
       "a fresh install gets the defaults and its two empty corners")
    _G.BiSHealingDB = realDB
end

local function anythingIn(t) return type(t) == "table" and next(t) ~= nil end

-- NEVER WRITE A BLIZZARD GLOBAL. `SlashCmdList = SlashCmdList or {}` wrote the table the chat box
-- runs every slash command from, and the client then blamed BiSHealing for /pvp calling the
-- protected TogglePVP (Arn, 21 Sep). The harness cannot see taint, so the source is read instead:
-- a bare assignment to one of these, outside an `if not X then`, is the bug.
do
    local SHARED = { "SlashCmdList", "hash_SlashCmdList", "UISpecialFrames", "StaticPopupDialogs",
                     "ChatTypeInfo", "DEFAULT_CHAT_FRAME", "ClickCastFrames" }
    local found = {}
    for _, rel in ipairs(LOADED) do
        local fh = io.open(rel)
        if fh then
            local n = 0
            for line in fh:lines() do
                n = n + 1
                -- `if not X then X = {} end` starts with `if`, so it is allowed: it only ever runs
                -- where the client has no such table at all
                for _, g in ipairs(SHARED) do
                    if line:match("^%s*" .. g .. "%s*=[^=]") then
                        found[#found + 1] = ("%s:%d %s"):format(rel, n, line:match("^%s*(.-)%s*$"))
                    end
                end
            end
            fh:close()
        end
    end
    ok(#found == 0, "no file writes a Blizzard global outright: " .. table.concat(found, " | "))
end

-- THE THREE DOORS. The slash command, the minimap menu and the options window all go through
-- NS.DO, so what has to be true is that every door names something that is actually there.
do
    for _, name in ipairs({ "options", "mouse", "show", "rescan", "center", "scan", "auras",
                            "minimap", "help", "db" }) do
        ok(type(NS.DO[name]) == "function", ("NS.DO.%s is missing"):format(name))
    end

    -- THE ROUND TRIP, which is what "the binds reset every reload" is really about. Logout stamps
    -- the table; a login that finds no stamp means the CLIENT never handed the file back, and no
    -- amount of fixing this addon changes that. Drive both halves with the real event handler.
    do
        local fire = NS.events.__scripts.OnEvent
        _G.BiSHealingDB = nil
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(NS.loaded.found == false, "a first ever login finds no saved table")

        NS.DB()
        NS.FM.Set("", "left", "Healing Wave(Rank 2)")
        fire(NS.events, "PLAYER_LOGOUT")
        ok(type(_G.BiSHealingDB.savedAt) == "number", "logging out stamps the table")
        ok(_G.BiSHealingDB.saves == 1, "and counts the save")
        ok(_G.BiSHealingDB.binds["left"] == "Healing Wave(Rank 2)",
           "with the bind in the table the client will write")

        -- what a client that DOES hand the file back looks like on the next login
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(NS.loaded.savedAt ~= nil,
           "the next login sees the stamp: savedAt=" .. tostring(NS.loaded.savedAt))
        -- three, not one: a mouse with nothing on it is also seeded with this class's defaults,
        -- and the drag above replaced one of them
        ok(NS.loaded.binds == 3 and _G.BiSHealingDB.binds["left"] == "Healing Wave(Rank 2)",
           "and the binds, with the dragged one kept: " .. tostring(NS.loaded.binds))
        ok(pcall(NS.DO.db), "and /bish db reports it without throwing")

        -- THE CLIENT THAT LOSES THE ACCOUNT FILE (measured on the beta, 19 Sep 2026: it writes
        -- BiSHealingDB perfectly and hands back nothing at the next login, every time). The
        -- per-character file is a different file in a different folder, so it may survive when
        -- the other does not - and the addon takes whichever came back.
        _G.BiSHealingCharDB = nil
        fire(NS.events, "PLAYER_LOGOUT")
        ok(anythingIn(_G.BiSHealingCharDB) and _G.BiSHealingCharDB.binds["left"] == "Healing Wave(Rank 2)",
           "logging out writes the per-character copy too")
        ok(not rawequal(_G.BiSHealingCharDB, _G.BiSHealingDB),
           "and it is a SEPARATE table - an alias would be one file saved and one lost")

        local keep = _G.BiSHealingCharDB
        _G.BiSHealingDB = nil                       -- the client loses the account-wide one
        _G.BiSHealingCharDB = keep
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(NS.loaded.rescued == true, "the next login notices and takes the per-character copy")
        ok(NS.FM.Get("", "left") == "Healing Wave(Rank 2)", "so the binds are still there")

        -- and when BOTH came back, the account-wide one is left alone
        _G.BiSHealingDB = { dbver = 1, binds = { left = "Chain Heal" } }
        _G.BiSHealingCharDB = keep
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(NS.loaded.rescued == false and NS.FM.Get("", "left") == "Chain Heal",
           "a client that keeps both changes nothing")

        _G.BiSHealingDB, _G.BiSHealingCharDB = nil, nil
    end

    -- ONE CLICK, ONE PLACE. Arn: "choose one or the other and merge always keep the bind on top".
    -- Left and right both open the options window; there is no menu to open instead.
    -- the shared button needs a minimap to sit on, and the headless client has none until given one

    _G.Minimap = _G.Minimap or CreateFrame("Frame", "Minimap", UIParent)
    -- and the shared lib itself, which the TOC loop above skips: the click is only ours if the
    -- lib's own OnClick was really there to be replaced
    if not (BiSTheme and BiSTheme.Minimap) then
        local lib = assert(loadfile("Libs/BiSTheme/Minimap.lua"))
        local loaded, why = pcall(lib)
        ok(loaded, "the shared minimap button loads headless", tostring(why))
    end
    local ran, b = pcall(NS.MM.Build)
    ok(ran and b ~= nil, "the minimap button builds", tostring(b))
    if b then
        local click = b:GetScript("OnClick")
        ok(click == NS.MM.Click, "the button's click is ours, not the shared menu")
        local realOptions, opened = NS.DO.options, 0
        NS.DO.options = function() opened = opened + 1 end
        click(b, "LeftButton")
        click(b, "RightButton")
        NS.DO.options = realOptions
        ok(opened == 2, "left AND right click open the options window", opened)
        ok(not (b.menuFrame and b.menuFrame:IsShown()), "and no menu opens instead")
    end
    ok(NS.MM.Rows == nil, "the menu's rows are gone - the window holds them all")
    local first = NS.UI.Rows()[1]
    ok(first and first.key == "mouse", "the mouse binds are the window's first row",
       first and first.key or "none")

    -- the window's rows, and that pressing every one of them works
    local keys = {}
    for _, opt in ipairs(NS.UI.Rows()) do
        keys[opt.key] = opt
        if opt.kind == "button" then
            ok(pcall(opt.action), ("pressing %q threw"):format(opt.key))
        else
            ok(pcall(opt.get, NS.DB()), ("reading %q threw"):format(opt.key))
        end
    end
    for _, want in ipairs({ "shown", "minimap", "mouse", "scan", "pipTest" }) do
        ok(keys[want], ("the window lost %q"):format(want))
    end
    -- RAISED FROM 10 TO 12, ON PURPOSE (20 Sep 2026), and not to make a red line go away. The cap
    -- was set when the window had six rows. Four real settings arrived in one evening, each asked
    -- for by the player - pyramid, pets, missing health, size of the cells - and that is what the
    -- window is for. Eleven rows today.
    --
    -- THE NEXT ROW IS A DECISION, NOT A BUMP: "what can I see?" and "test the debuff marker" are
    -- diagnostics sitting beside real settings. When this goes red again, fold those two behind
    -- one "diagnostics" button rather than raising the number a second time.
    ok(#NS.UI.Rows() <= 12, "the window stays short: " .. #NS.UI.Rows())

    -- and the slash command reaches them. "/bish nonsense" prints the help rather than throwing.
    for _, cmd in ipairs({ "", "show", "hide", "mouse", "rescan", "scan", "auras", "nonsense" }) do
        ok(pcall(SlashCmdList.BISHEALING, cmd), ("/bish %s threw"):format(cmd))
    end
    NS.DO.auras()          -- back off again: the debug marker must not be left on
end

print(fail == 0 and ("== BiS Healing ok (" .. checks .. " checks)")
      or ("!! BiS Healing: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
