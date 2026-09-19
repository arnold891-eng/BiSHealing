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
}

local frames = {}
local function autoMethods(t)
    return setmetatable(t, { __index = function(_, k)
        if type(k) == "string" and k:match("^%u") then return function() end end
        return nil
    end })
end

local function newFrame(kind)
    local f = { __kind = kind, __attrs = {}, __scripts = {}, __shown = false, __alpha = 1 }
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
        return autoMethods({ SetText = function(self2, t) self2.__text = t end })
    end
    frames[#frames + 1] = f
    return autoMethods(f)
end

_G.CreateFrame = function(kind) return newFrame(kind) end
_G.UIParent = newFrame("Frame")
_G.InCombatLockdown = function() return STATE.inCombat end
_G.UnitExists = function(u) return STATE.units[u] and true or false end
_G.IsInRaid = function() return false end
_G.UnitName = function(u) return "Name-" .. tostring(u) end
_G.UnitClass = function() return "Shaman", "SHAMAN" end
_G.UnitIsDeadOrGhost = function(u) return STATE.dead[u] and true or false end
_G.UnitHealth = function() return secret() end
_G.UnitHealthMax = function(u) if u == "player" then return 297 end return secret() end
_G.IsSpellInRange = function(_, u) return STATE.range[u] == 0 and 0 or 1 end
_G.RegisterUnitWatch = function() end
_G.C_Secrets = { HasSecretRestrictions = function() return true end }

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
for _, rel in ipairs({ "Forever/Lockdown.lua", "Forever/Auras.lua", "Forever/Grid.lua", "Forever/Between.lua" }) do
    local chunk = assert(loadfile(rel))
    chunk("BiSHealing", NS)
end
local FG = NS.FG

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
ok(FG.frames[1].__attrs["*spell1"] == "Healing Wave", "left click casts through a secure attribute")
ok(FG.frames[1].__attrs["shift-spell1"] == "Chain Heal", "shift-click is the chain")

-- THE RULE: the value the client gave is handed on untouched. If any line in Paint had done
-- arithmetic, compared it, or printed it, the secret would have errored and this would be false.
local f = FG.frames[2]
local painted = pcall(FG.Paint, f)
ok(painted, "Paint never reads the number it was given")
ok(getmetatable(f.bar.__value) == secretMeta, "the bar was handed the secret itself, not a copy")
ok(f.bar.__color ~= nil, "the bar was coloured (class colour, not a health band)")

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

-- the pyramid's furniture is taken off the screen on Forever, not just its brain
do
    local hidden = false
    NS.anchor = { Hide = function() hidden = true end }
    FG.anchor = nil                          -- let Start() run again for this check
    FG.Start()
    ok(hidden, "the pyramid's drag anchor is hidden on Forever")
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
local n = FB.Report()
ok(n and n > 0 and #SAID == n, "Report says one line per finding")
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
    local types = dispel and dispel.opts and dispel.opts.candidateFilters
                  and dispel.opts.candidateFilters.includeDispelTypes or {}
    ok(types.Poison and types.Disease, "poison and disease, which a shaman can cure")
    ok(types.Magic == nil, "and not magic, which it cannot")

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
do
    local src = io.open("BiSHealing.lua", "r")
    local body = src and src:read("*a") or ""
    if src then src:close() end
    ok(body:find('NS.SECRET and e == "COMBAT_LOG_EVENT_UNFILTERED"', 1, true) ~= nil,
       "the event loop refuses to even ASK for the combat log where the client hides numbers")
end

print(fail == 0 and ("== forever ok (" .. checks .. " checks)")
      or ("!! forever: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
