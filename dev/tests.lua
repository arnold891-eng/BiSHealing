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
    function f:SetValue(v) self.__value = v end          -- what the bar was handed, kept as given
    function f:SetMinMaxValues(lo, hi)
        if STATE.maxRefusesSecret and getmetatable(hi) == secretMeta then
            error("SetMinMaxValues: a secret max is refused by this client", 2)
        end
        self.__min, self.__max = lo, hi
    end
    function f:SetStatusBarColor(r, g, b) self.__color = { r, g, b } end
    function f:CreateTexture() return autoMethods({ SetColorTexture = function() end }) end
    function f:CreateFontString()
        -- RECORDED. "How many labels are in this bar" is a question a suite can only ask if the
        -- mock remembers: two labels in one 84px header printed through each other in game, twice
        -- (the mouse window in the morning, the grid header in the afternoon).
        local fs = autoMethods({ SetText = function(self2, t) self2.__text = t end })
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
_G.RegisterUnitWatch = function() end
_G.C_Secrets = { HasSecretRestrictions = function() return true end }

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
-- THE SPELLBOOK, AS THIS CLIENT ACTUALLY ANSWERS IT. The old stub let a SPELL ID answer a rank,
-- and that is precisely why the missing rank got shipped: on the real client an id answers a name
-- and nothing else, and C_Spell.GetSpellSubtext is the only call that knows the rank. A mock
-- kinder than the client is a mock that tests nothing.
--
--   C_SpellBook.GetSpellBookItemName(index) -> name, rank   (a BOOK INDEX, never an id)
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
_G.C_SpellBook.GetSpellBookItemName = function(n)
    if type(n) ~= "number" then error("bad argument #1 (not a numerical value)", 2) end
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
ok(FG.frames[1].__attrs["*spell1"] == "Healing Wave", "left click casts through a secure attribute")
ok(FG.frames[1].__attrs["shift-spell1"] == "Chain Heal", "shift-click is the chain")
ok(NS.FM.Defaults().left == "Healing Wave", "a shaman's mouse starts on Healing Wave")

-- ONLY WHAT IS IN THE BOOK. Arn, on a shaman who had not trained it yet: "it setts it back to
-- chain heals which i dont have yet". A default is a courtesy; a default for a spell you cannot
-- cast is a button that does nothing and a line of red text when you press it.
do
    local FM = NS.FM
    local keep = BOOK[5]                              -- Chain Heal
    BOOK[5] = nil
    local defaults, booked = FM.Defaults()
    ok(defaults.left == "Healing Wave", "the spells this character HAS are still offered")
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
ok(FG.ShortName("party1") == "Name-part" or #FG.ShortName("party1") <= 9,
   "a name is cut to what the cell holds")
_G.UnitName = function() return "Longnamedhealer-Realmone" end
ok(FG.ShortName("party1") == "Longnamed", "the realm is dropped before the cut")
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
    ok(cell.__attrs["*spell2"] == "Lesser Healing Wave",
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

    -- the menu's rows
    local rows = NS.MM.Rows()
    ok(#rows >= 8, "the minimap menu has its rows")
    local dead = 0
    for _, row in ipairs(rows) do
        if not row.sep and type(row.func) ~= "function" then dead = dead + 1 end
    end
    ok(dead == 0, ("%d menu row(s) lead nowhere"):format(dead))

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
    ok(#NS.UI.Rows() <= 10, "the window stays short: " .. #NS.UI.Rows())

    -- and the slash command reaches them. "/bish nonsense" prints the help rather than throwing.
    for _, cmd in ipairs({ "", "show", "hide", "mouse", "rescan", "scan", "auras", "nonsense" }) do
        ok(pcall(SlashCmdList.BISHEALING, cmd), ("/bish %s threw"):format(cmd))
    end
    NS.DO.auras()          -- back off again: the debug marker must not be left on
end

print(fail == 0 and ("== BiS Healing ok (" .. checks .. " checks)")
      or ("!! BiS Healing: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
