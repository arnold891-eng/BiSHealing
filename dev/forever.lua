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

local NS = {}
for _, rel in ipairs({ "Forever/Lockdown.lua", "Forever/Grid.lua" }) do
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

-- in combat: no layout, no attribute changes. Both are blocked by the client, and trying anyway
-- is how an addon gets itself locked out of its own frames for the rest of the fight.
STATE.inCombat = true
ok(FG.Layout(anchor) == false, "layout refuses itself in combat")
ok(FG.Bind(FG.frames[1], "party2") == false, "binds refuse themselves in combat")
ok(pcall(FG.Paint, FG.frames[1]), "painting still works in combat -- that is the whole point")
STATE.inCombat = false

print(fail == 0 and ("== forever ok (" .. checks .. " checks)")
      or ("!! forever: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
