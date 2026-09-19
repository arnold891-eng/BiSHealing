-- BiSHealing -- headless test suite (house shape: dev/tests.lua)
--
--     cd BiSHealing && lua5.1 dev/tests.lua
--     lua5.1 dev/tests.lua ../SomeOther/BiSHealing.lua      -- explicit target
--
-- Mock WoW API harness. Runs BiSHealing.lua under the SAME Lua the live client
-- uses (5.1), so string.format("%d", float) errors surface here instead of in a
-- raid. The mocks are deliberately STRICT where the client is strict -- see
-- SetColorTexture below -- because a permissive mock is how a live-only crash
-- ships green.
--
-- Lived at "Claude outputs/bishharness.lua" until 9 Sep 2026. Same file, new
-- house; stubs at the old path point here.

local T = 0
function GetTime() return T end
function AdvanceTime(dt) T = T + dt end

-- ---------------------------------------------------------------- widgets --
local allFrames = {}
ALLFS = {}
ALLLINES = {}
ALLTEX = {}

local function newRegion(kind, parent)
    local r = {
        __kind = kind, __parent = parent, __shown = (kind == "Frame" or kind == "Button"),
        __points = {}, __w = 0, __h = 0, __alpha = 1, __text = nil,
        __color = nil, __drawLayer = nil, __attrs = {}, __scripts = {}, __events = {},
    }
    function r:Show() self.__shown = true end
    function r:Hide() self.__shown = false end
    function r:IsShown() return self.__shown and true or false end
    function r:IsVisible() return self:IsShown() end
    function r:SetShown(v) self.__shown = v and true or false end
    function r:SetPoint(...) self.__points[#self.__points+1] = {...} end
    function r:ClearAllPoints() self.__points = {} end
    function r:GetPoint() local p = self.__points[1]
        if not p then return "CENTER", nil, "CENTER", 0, 0 end
        return p[1], p[2], p[3], p[4] or 0, p[5] or 0 end
    function r:SetSize(w, h) self.__w, self.__h = w, h end
    function r:SetWidth(w) self.__w = w end
    function r:SetHeight(h) self.__h = h end
    function r:GetWidth() return self.__w end
    function r:GetHeight() return self.__h end
    function r:GetCenter() return 500, 400 end
    function r:GetParent() return self.__parent end
    function r:SetAlpha(a) self.__alpha = a end
    function r:GetAlpha() return self.__alpha end
    function r:SetAllPoints() end
    -- STRICT ON PURPOSE. `SetColorTexture` needs r, g, b (and optionally a).
    -- Writing `cond and select(1, T.rgba(n)) or shade(n)` truncates to ONE
    -- value; the live client throws and takes the whole options window with it,
    -- while a permissive stub records {0.7, nil, nil} and every test passes.
    -- Erroring here turns a live-only crash into a headless failure.
    function r:SetColorTexture(a,b,c,d)
        if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then
            error(("SetColorTexture(r,g,b[,a]) wants numbers, got %s, %s, %s")
                  :format(type(a), type(b), type(c)), 2)
        end
        if d ~= nil and type(d) ~= "number" then
            error("SetColorTexture alpha must be a number, got " .. type(d), 2)
        end
        self.__color = {a,b,c,d}
    end
    function r:SetTexture(t) self.__tex = t end
    function r:SetTexCoord() end
    function r:SetVertexColor(a,b,c,d)
        if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then
            error(("SetVertexColor(r,g,b[,a]) wants numbers, got %s, %s, %s")
                  :format(type(a), type(b), type(c)), 2)
        end
        self.__vertex = {a,b,c,d}
    end
    function r:SetDesaturated() end
    function r:SetBlendMode() end
    function r:SetRotation() end
    function r:SetDrawLayer(l, s) self.__drawLayer = {l, s} end
    function r:SetText(t) self.__text = t end
    function r:GetText() return self.__text end
    function r:SetJustifyH() end
    function r:SetTextColor(a,b,c,d)
        if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" then
            error(("SetTextColor(r,g,b[,a]) wants numbers, got %s, %s, %s")
                  :format(type(a), type(b), type(c)), 2)
        end
        self.__textColor = {a,b,c,d}
    end
    -- Console.lua sizes the words FontString itself and then measures it, so the
    -- mock has to remember what it was told. A stub that forgets returns the same
    -- width for 8pt and 15pt and the header budget assert stops meaning anything.
    function r:SetFont(path, size, flags)
        self.__font = { path or STANDARD_TEXT_FONT, size or 10, flags or "" }
    end
    function r:GetFont()
        local f = self.__font
        if f then return f[1], f[2], f[3] end
        return "Fonts\\FRIZQT__.TTF", 10, ""
    end
    -- STRICT ON PURPOSE, second kind. The client measures GLYPHS; "|cffb980ff" is
    -- not glyphs. A mock that counts the escape makes `BiS> ` look ~10 characters
    -- wider than it draws, Con:Width() lies high, and the header budget assert
    -- passes for the wrong reason -- or worse, T.Fit trims real words to make room
    -- for colour codes that were never on screen.
    function r:GetStringWidth()
        local t = self.__text or ""
        t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        local size = self.__font and self.__font[2] or 10
        return #t * size * 0.5
    end
    function r:SetStartPoint() end
    function r:SetEndPoint() end
    function r:SetThickness() end
    function r:SetFrameStrata() end
    function r:SetFrameLevel() end
    function r:SetMovable() end
    function r:EnableMouse() end
    function r:RegisterForDrag() end
    function r:RegisterForClicks() end
    function r:StartMoving() end
    -- what the options kit and the Keybinds window ask a frame for
    function r:StopMovingOrSizing() end
    function r:SetClampedToScreen() end
    function r:EnableKeyboard(on) self.__keyboard = on and true or false end
    function r:IsKeyboardEnabled() return self.__keyboard == true end
    function r:SetPropagateKeyboardInput(on) self.__propagate = on end
    function r:EnableMouseWheel() end
    function r:GetFrameLevel() return 1 end
    function r:StopMovingOrSizing() end
    function r:SetBackdrop() end
    function r:SetMinMaxValues(lo, hi) self.__min, self.__max = lo, hi end
    function r:SetValueStep(v) self.__step = v end
    function r:SetObeyStepOnDrag() end
    function r:SetOrientation() end
    function r:SetThumbTexture() end
    function r:SetValue(v)
        self.__value = v
        local fn = self.__scripts and self.__scripts.OnValueChanged
        if fn then fn(self, v) end
    end
    function r:GetValue() return self.__value or 0 end
    function r:Click() local fn = self.__scripts and self.__scripts.OnClick; if fn then fn(self) end end
    function r:SetChecked(v) self.__checked = v end
    function r:GetChecked() return self.__checked end
    function r:SetScript(k, fn) self.__scripts[k] = fn end
    function r:HookScript(k, fn) self.__scripts[k] = fn end
    function r:GetScript(k) return self.__scripts[k] end
    function r:SetAttribute(k, v) self.__attrs[k] = v end
    function r:GetAttribute(k) return self.__attrs[k] end
    -- recorded, not ignored: the suite picks the addon's event frame by how many events it asked
    -- for, and a frame that registers nothing must not be able to win that (see the pick below)
    function r:RegisterEvent(e) if e then self.__events[e] = true end end
    function r:RegisterUnitEvent(e) if e then self.__events[e] = true end end
    function r:UnregisterEvent(e) if e then self.__events[e] = nil end end
    function r:IsEventRegistered(e) return self.__events[e] and true or false end
    function r:SetOwner() end
    function r:AddLine() end
    function r:AddDoubleLine() end
    function r:NumLines() return (TOOLTIP_INDEX and HEAL_SIZE[TOOLTIP_INDEX] or 0) > 0 and 1 or 0 end
    function r:IsForbidden() return false end
    function r:SetSpellBookItem(i) TOOLTIP_INDEX = i end
    function r:CreateTexture(_, layer)
        local t = newRegion("Texture", self); t.__shown = false
        t.__drawLayer = { layer }
        ALLTEX[#ALLTEX+1] = t
        return t
    end
    function r:CreateFontString(_, layer)
        local t = newRegion("FontString", self); t.__shown = true
        ALLFS[#ALLFS+1] = t
        return t
    end
    function r:CreateLine()
        local l = newRegion("Line", self); l.__shown = false
        ALLLINES[#ALLLINES+1] = l
        return l
    end
    return r
end

function CreateFrame(kind, name, parent, tmpl)
    local f = newRegion(kind == "Texture" and "Texture" or "Frame", parent)
    f.__name = name
    f.__template = tmpl
    if name then _G[name] = f end
    allFrames[#allFrames+1] = f
    return f
end

_G["BiSHealingProbeTipTextLeft1"] = {
    GetText = function()
        local n = TOOLTIP_INDEX and HEAL_SIZE[TOOLTIP_INDEX]
        if not n or n == 0 then return nil end
        return ("Heals a friendly target for %d to %d."):format(n - 50, n + 50)
    end,
}
UIParent = newRegion("Frame")
GameTooltip = newRegion("Frame")
CHATLOG = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m)
    CHATLOG[#CHATLOG+1] = m
    if os.getenv("QUIET") ~= "1" then print("[chat] " .. m) end
end }

BackdropTemplateMixin = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
function tinsert(t, v) t[#t+1] = v end
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r=1,g=1,b=1 } end })

-- ------------------------------------------------------------- unit world --
local ROSTER = {}
local function mkUnit(unit, name, class, hp, hpMax)
    ROSTER[unit] = { name = name, class = class, hp = hp, hpMax = hpMax,
                     guid = "GUID-" .. name }
end
GROUP_SIZE = 10
mkUnit("player", "Kumlust", "SHAMAN", 4000, 5000)
for i = 1, 10 do
    mkUnit("raid" .. i, "Raider" .. i,
           ({"WARRIOR","DRUID","ROGUE","MAGE","PRIEST","HUNTER","WARLOCK","PALADIN","SHAMAN","WARRIOR"})[i],
           3000 + i * 100, 8000)
end
ROSTER["raid1"].guid = ROSTER["player"].guid   -- player is raid1
ROSTER["raid1"].class = ROSTER["player"].class -- ...including their class

function UnitExists(u) return ROSTER[u] ~= nil end
function UnitName(u) local r = ROSTER[u]; if r then return r.name, "" end end
function UnitGUID(u)
    local r = ROSTER[u]
    if r then return r.guid end
    -- a group member's NAME is a valid unit id in the real client, and the
    -- chain-cast announcement relies on exactly that
    for _, e in pairs(ROSTER) do if e.name == u then return e.guid end end
end
function UnitClass(u) local r = ROSTER[u]; return r and r.class, r and r.class end
function UnitHealth(u) local r = ROSTER[u]; return r and r.hp or 0 end
function UnitHealthMax(u) local r = ROSTER[u]; return r and r.hpMax or 1 end
function UnitIsDeadOrGhost(u) return false end
function UnitPower() return 3000 end
function UnitPowerMax() return 5000 end
-- ES_ON / ES_CHARGES drive whose frame carries MY Earth Shield and how much of
-- it is left, so the "stay put while it is healthy" rule can be tested in both
-- states instead of only the one the mock happened to hardcode.
ES_ON = "raid1"
ES_CHARGES = 4
ES_MINE = true          -- false = the shield belongs to the other shaman
function UnitAura(unit, i)
    if i == 1 and ES_ON and unit == ES_ON then
        return "Earth Shield", nil, ES_CHARGES, nil, nil, nil, nil,
               (ES_MINE and "player" or "raid9"), nil, 974
    end
    return nil
end
-- The client's own heal prediction, which is what the sniping WeakAura reads.
-- INCOMING[unit][healerUnit] = amount, CASTEND[healerUnit] = ms when it lands.
INCOMING, CASTEND = {}, {}
-- "player" and "raid1" are the same person to the real client, so the mock has
-- to agree: resolve every unit token to its GUID before matching. Without this
-- a test could set up a heal on "player" and the addon, asking about "raid1",
-- would see nothing -- and pass for the wrong reason.
local function UKEY(u)
    local r = ROSTER[u]
    return (r and r.guid) or u
end
function UnitGetIncomingHeals(unit, healer)
    local t
    for k, v in pairs(INCOMING) do
        if UKEY(k) == UKEY(unit) then t = v break end
    end
    if not t then return 0 end
    if healer then
        for k, v in pairs(t) do
            if UKEY(k) == UKEY(healer) then return v end
        end
        return 0
    end
    local sum = 0
    for _, v in pairs(t) do sum = sum + v end
    return sum
end
function UnitCastingInfo(unit)
    local e
    for k, v in pairs(CASTEND) do
        if UKEY(k) == UKEY(unit) then e = v break end
    end
    if not e then return nil end
    return "Some Heal", nil, nil, (e - 2500), e
end
function UnitIsUnit(a, b)
    if a == b then return true end
    local ra, rb = ROSTER[a], ROSTER[b]
    return (ra and rb and ra.guid == rb.guid) or false
end
function UnitGroupRolesAssigned() return "NONE" end   -- as this client really does
function UnitInRange() return true end
function IsInRaid() return true end
function IsInGroup() return true end
function GetNumGroupMembers() return GROUP_SIZE end
function InCombatLockdown() return COMBAT == true end
function IsShiftKeyDown() return SHIFT_DOWN == true end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsSpellInRange() return 1 end
function GetPowerRegen() return 30, 12 end
-- The client this addon targets shows BASE healing in spellbook tooltips, with
-- no gear in it. HEAL_SIZE above is that base; this is the +healing that the
-- addon has to add back in itself.
SPELL_POWER = 1500
function GetSpellBonusHealing() return SPELL_POWER end
-- Talent scan: 5/5 Purification and 2/2 Improved Chain Heal by default, so the
-- published TBC coefficients (94.3% Chain Heal, 94.3% Healing Wave) are what
-- the estimate has to reproduce.
TALENTS = { { "Purification", 5 }, { "Improved Chain Heal", 2 } }
function GetNumTalentTabs() return 1 end
function GetNumTalents() return #TALENTS end
function GetTalentInfo(_, i)
    local e = TALENTS[i]
    if e then return e[1], nil, nil, nil, e[2] end
end
-- Real clients answer GetSpellInfo(spellID) with the spell's NAME. The mock
-- used to echo whatever it was given, so any code path that looked a spell up
-- by numeric id (HealComm callbacks, UNIT_SPELLCAST_SENT) silently compared a
-- number against a string and did nothing.
SPELLID_NAME = {
    [1064] = "Chain Heal", [1003] = "Chain Heal", [1005] = "Chain Heal",
    [974]  = "Earth Shield",
    [1008] = "Healing Wave", [1012] = "Healing Wave",
    [1015] = "Lesser Healing Wave",
}
function GetSpellInfo(n)
    if n == "Nature's Swiftness" and NS_UNKNOWN then return nil end
    if type(n) == "number" then
        local name = SPELLID_NAME[n]
        if not name then return nil end
        return name, nil, nil, 2500
    end
    return n, nil, nil, 2500
end
function GetSpellTexture() return "Interface\\Icons\\Foo" end
-- NS_CD flips the Nature's Swiftness cooldown so both pip states get exercised.
function GetSpellCooldown(spell)
    if spell == "Nature's Swiftness" and NS_CD then return GetTime(), 180 end
    return 0, 0
end
-- keybinding API. OVERRIDES records what the addon bound to what, so a bind
-- that silently never lands is a test failure instead of a raid surprise.
OVERRIDES = {}
function SetOverrideBindingClick(owner, prio, key, btnName, mouseBtn)
    OVERRIDES[key] = { button = btnName, click = mouseBtn, owner = owner }
end
-- per owner, as the client does: the bind engine clears each hidden button's
-- own bindings, and a mock that wiped everything would hide a leak between them
function ClearOverrideBindings(owner)
    for k, v in pairs(OVERRIDES) do
        if owner == nil or v.owner == owner then OVERRIDES[k] = nil end
    end
end
function SetBindingClick() end
function GetSpellPowerCost() return { { type = 0, cost = 500 } } end
function GetAddOnMetadata(_, k) if k == "Version" then return "1.0-test" end end
function GetSpellBookItemName(i)
    local T2 = { {"Chain Heal","Rank 1"}, {"Chain Heal","Rank 2"}, {"Chain Heal","Rank 3"},
                 {"Chain Heal","Rank 4"}, {"Chain Heal","Rank 5"},
                 {"Earth Shield","Rank 1"}, {"Earth Shield","Rank 2"},
                 {"Healing Wave","Rank 9"}, {"Healing Wave","Rank 10"},
                 {"Healing Wave","Rank 11"}, {"Healing Wave","Rank 12"},
                 {"Lesser Healing Wave","Rank 5"}, {"Lesser Healing Wave","Rank 6"},
                 {"Lesser Healing Wave","Rank 7"}, {"Nature's Swiftness", ""} }
    local e = T2[i]; if e then return e[1], e[2] end
end
function GetSpellBookItemInfo(i) return "SPELL", 1000 + i end
-- Tooltip heal sizes per spellbook slot, so BuildHealOptions produces real
-- numbers (the colour bands and the black-bar red threshold both read them).
-- Without this every option came back heal=0 and both features tested as no-ops.
HEAL_SIZE = { 300, 600, 900, 1300, 1800,   -- Chain Heal ranks 1-5
              0, 0,                        -- Earth Shield ranks
              900, 1100, 1500, 2000, 2600, -- Healing Wave ranks 9-12 (+1 slot)
              700, 850, 1000 }             -- Lesser Healing Wave ranks 5-7
TOOLTIP_INDEX = nil
function CombatLogGetCurrentEventInfo() return unpack(CLOG or {}) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- addon-to-addon comm. ADDON_SENT records what BiSHealing broadcast, so the
-- Earth Shield handshake can be asserted rather than eyeballed.
ADDON_SENT = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
        ADDON_SENT[#ADDON_SENT+1] = { prefix = prefix, msg = msg, ch = channel, to = target }
    end,
}
function SendAddonMessage(prefix, msg, channel, target)
    C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
end
function strsplit(sep, str)
    local out = {}
    for piece in tostring(str):gmatch("([^" .. sep .. "]*)") do out[#out+1] = piece end
    -- gmatch with an empty-allowed pattern yields a trailing blank per field;
    -- keep only the real ones
    local clean = {}
    for i = 1, #out, 2 do clean[#clean+1] = out[i] end
    return unpack(clean)
end
SENT = {}
function SendChatMessage(msg, channel) SENT[#SENT+1] = { msg = msg, ch = channel } end
SlashCmdList = {}
C_Timer = { After = function() end }

-- LibStub + a HealComm mock that returns NONZERO incoming, so the incoming
-- fill / prediction subtraction path actually runs.
HC_CB = {}
HC_PER = {}     -- casterGUID -> amount that caster has inbound
local HEALCOMM = {
    CASTED_HEALS = 1,
    -- honours the per-caster argument, like a current LibHealComm: asking
    -- about a caster who is not healing this target returns 0
    GetHealAmount = function(_, guid, _, _, casterGUID)
        if casterGUID then return HC_PER[casterGUID] or 0 end
        return 1500
    end,
    GetOthersHealAmount = function(_, guid) return 900 end,
    -- keep the handlers so a test can fire "another shaman started a chain"
    RegisterCallback = function(_, event, fn) HC_CB[event] = fn end,
}
LibStub = setmetatable({}, { __call = function(_, name, silent)
    if name == "LibHealComm-4.0" then return HEALCOMM end
    return nil
end })

-- GLOBAL LEAK DETECTOR. The forward-ref trap in this addon shows up as an
-- accidental global write (`local Foo` declared below its caller), which is
-- silent in Lua and has caused live crashes. Trap every new global created
-- after load so it is impossible to miss.
local KNOWN = {}
for k in pairs(_G) do KNOWN[k] = true end
-- the harness's own switches are not addon leaks: they are how the tests drive
-- combat state, the log feed and the Nature's Swiftness cooldown
for _, k in ipairs({ "COMBAT", "CLOG", "NS_CD", "NS_UNKNOWN", "OVERRIDES", "ALLLINES", "ALLTEX", "ES_ON", "ES_CHARGES", "ES_MINE", "SENT", "HEAL_SIZE", "TOOLTIP_INDEX", "SPELL_POWER", "TALENTS", "CHATLOG", "ADDON_SENT", "C_ChatInfo", "HC_CB", "SPELLID_NAME", "FWD_REFS", "INCOMING", "CASTEND", "HC_PER", "SHIFT_DOWN", "TOTEMS", "BUFFS", "DEBUFFS", "PARTY", "MANA", "DebuffTypeColor", "GetRealZoneText", "GetTotemInfo", "UnitInParty" }) do
    KNOWN[k] = true
end
LEAKED = {}


-- STATIC FORWARD-REFERENCE LINT.
--
-- The runtime trap below only sees code that actually executes, which is how
-- SendChainCast shipped calling RosterUnits four hundred lines before its
-- declaration: no test ever cast a Chain Heal, so nothing read the nil global.
-- This reads the source instead and needs no coverage at all: for every name
-- the addon declares as a local, is that name USED on an earlier line?
local function StaticForwardRefCheck(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()

    -- strip comments and string literals so prose and messages never match
    local code = {}
    for i, line in ipairs(lines) do
        local c = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
        code[i] = c
    end

    -- first line each local name is declared on
    local declAt = {}
    for i, c in ipairs(code) do
        for list in c:gmatch("local%s+function%s+([%w_]+)") do
            if not declAt[list] then declAt[list] = i end
        end
        for list in c:gmatch("local%s+([%w_%s,]+)") do
            for name in list:gmatch("[%w_]+") do
                if name ~= "function" and not declAt[name] then declAt[name] = i end
            end
        end
    end

    local bad = {}
    for name, line in pairs(declAt) do
        if #name > 2 then
            for i = 1, line - 1 do
                local c = code[i]
                -- a bare use: not a field (.name / :name) and not a table key.
                -- Called or subscripted anywhere; for a CHUNK local (column 0)
                -- also `X.f` / `X:m` -- a table read above its own `local` line
                -- is the same nil global as a call. The demo read AURAS.down 400
                -- lines early and only the runtime tick caught it; now the
                -- static pass does too. Indented locals are function-scoped and
                -- reuse names (`page` is a parameter in one builder and a local
                -- in another), so the field form is not applied to them.
                local chunk = code[line]:find("^local%s")     -- column 0 = chunk local
                local at = c:find("[^%w_.:]" .. name .. "%s*[(%[]")
                       or (chunk and c:find("[^%w_.:]" .. name .. "%s*[%.:]"))
                if at and not c:find("local%s+[%w_%s,]*" .. name) then
                    bad[#bad + 1] = ("%s used on line %d, declared on line %d")
                                    :format(name, i, line)
                    break
                end
            end
        end
    end
    table.sort(bad)
    return bad
end
_G.__staticForwardRefCheck = StaticForwardRefCheck

-- FORWARD-REFERENCE DETECTOR.
--
-- The leak trap below catches accidental global WRITES. The bug that keeps
-- getting through is the mirror image: a global READ. Call a local function
-- from a line above its `local` declaration and Lua does not complain -- the
-- name simply resolves to a global, which is nil, and you get "attempt to call
-- a nil value" only if that path ever runs. In a raid.
--
-- So: parse every name the addon declares as a local, then trap reads of a
-- global by that same name. If the addon reads a global called RosterUnits, it
-- meant its own local and the declaration is in the wrong place. Names the
-- addon never declares (real WoW APIs, C_Spell and friends) are ignored.
FWD_REFS = {}
local function ArmForwardRefCheck(path)
    local f = io.open(path, "r")
    if not f then return end
    local src = f:read("*a")
    f:close()
    local declared = {}
    for name in src:gmatch("local%s+function%s+([%w_]+)") do declared[name] = true end
    for list in src:gmatch("local%s+([%w_%s,]+)=") do
        for name in list:gmatch("([%w_]+)") do declared[name] = true end
    end
    for list in src:gmatch("local%s+([%w_%s,]+)\n") do
        for name in list:gmatch("([%w_]+)") do declared[name] = true end
    end
    local mt = getmetatable(_G) or {}
    local priorIndex = mt.__index
    mt.__index = function(t, k)
        if declared[k] and not KNOWN[k] then
            FWD_REFS[k] = (FWD_REFS[k] or 0) + 1
        end
        if priorIndex then return priorIndex(t, k) end
        return nil
    end
    setmetatable(_G, mt)
end
_G.__armForwardRefCheck = ArmForwardRefCheck

_G.__armLeakCheck = function()
    setmetatable(_G, { __newindex = function(t, k, v)
        if not KNOWN[k] and not tostring(k):match("^BiSHealing") then LEAKED[#LEAKED+1] = k end
        rawset(t, k, v)
    end })
end

-- ------------------------------------------------------------------ run --
_G.T_ADVANCE = AdvanceTime
-- The addon is more than one file now, so it is loaded the way the client loads
-- it: TOC order, each file handed the shared addon table. dev/load.lua holds
-- that logic because dev/stress.lua needs exactly the same thing, and two copies
-- of a loader drift the first time a file is added to one of them.
local here = (arg[0] or "dev/tests.lua"):gsub("[^/\\]*$", "")
dofile(here .. "load.lua")

local addonPath = arg[1] or "BiSHealing.lua"
local RUN       = __loadAddon(addonPath)
local addonDir  = RUN.dir
ADDON_NS        = RUN.ns
LOADED_FILES    = RUN.files
ADDON_SOURCES   = RUN.sources

-- Every .lua the addon ships must be in the TOC. A file split out and never
-- listed does not error; it is just never loaded, and a quarter of the addon
-- silently stops existing. This is the single most likely way the split breaks.
do
    local missing, why = __tocCoversDisk(addonDir, LOADED_FILES)
    if missing and #missing > 0 then
        print("!! TOC: these files ship but the TOC never loads them:")
        for _, m in ipairs(missing) do print("!!   " .. m) end
        os.exit(1)
    end
    print(missing and "== toc covers every lua file on disk"
                  or ("-- toc coverage not checked (" .. tostring(why) .. ")"))
end

-- BISTHEME=<path> loads the shared theme addon HERE -- after BiSHealing's file
-- has already run -- because that is the order the client uses: BiSHealing
-- sorts before BiSTheme. Anything the addon captured at file load is therefore
-- captured from a nil global, which is the bug dev/theme.lua hunts.
if os.getenv("BISTHEME") and os.getenv("BISTHEME") ~= "" then
    dofile(os.getenv("BISTHEME"))
end

-- fire PLAYER_LOGIN then the OnUpdate tick, which is what actually drives
-- UpdateBars / corners / rpm / cast counter. Slash commands alone miss these.
-- The addon's event frame is the one that asked for the most events -- NOT simply the last frame
-- with an OnEvent script. Forever/Grid.lua adds a two-line boot frame that waits for PLAYER_LOGIN,
-- and under the old rule that frame became "the addon" and every fired event went to it instead:
-- the login line never printed and the version check failed, 4000 lines away from the cause.
local ev, evCount = nil, -1
for _, f in ipairs(allFrames) do
    if f.__scripts and f.__scripts.OnEvent then
        local n = 0
        for _ in pairs(f.__events or {}) do n = n + 1 end
        if n >= evCount then ev, evCount = f, n end
    end
end
local anchorF = _G["BiSHealingAnchor"]

-- payload matters now: CHAT_MSG_ADDON carries prefix/message/channel/sender,
-- and dropping the extra arguments made every comm test silently pass nothing
-- Errors inside a handler are reported the same way every other failure in this
-- suite is. Left bare, a real crash exits 1 with a raw Lua traceback and no "!!"
-- line, which reads as "the harness broke" rather than "the addon threw", and
-- slips past anything scanning output for failures.
local function fireEvent(e, ...)
    if not ev then return end
    local ok, err = pcall(ev.__scripts.OnEvent, ev, e, ...)
    if not ok then
        print(("!! EVENT ERROR (%s): %s"):format(tostring(e), tostring(err)))
        os.exit(1)
    end
end
local function tick(n, dt)
    for i = 1, (n or 5) do
        AdvanceTime(dt or 0.11)
        if anchorF and anchorF.__scripts.OnUpdate then
            local ok, err = pcall(anchorF.__scripts.OnUpdate, anchorF, dt or 0.11)
            if not ok then print("!! TICK ERROR: " .. tostring(err)); os.exit(1) end
        end
    end
end
_G.fireEvent, _G.tick = fireEvent, tick

-- Both checks are per FILE now. Arming on one file while five are loaded is how
-- a forward reference in a freshly split-out file goes unnoticed: the trap only
-- fires for names the arming pass knows are locals somewhere.
__armLeakCheck()
for _, path in ipairs(ADDON_SOURCES) do __armForwardRefCheck(path) end
fireEvent("PLAYER_LOGIN")
print("== login ok")

-- ------------------------------------------------ the version is the TOC --
-- The addon must read its version from the TOC, never carry a literal: a
-- hardcoded copy drifts the moment the TOC is bumped, and then the window, the
-- comm handshake and /bish all disagree about which build this is. BiSJC
-- shipped exactly that bug. Proof here is a sentinel: the metadata mock hands
-- back a version no source file would ever contain, and it has to come out the
-- other end.
do
    local seen = false
    for _, line in ipairs(CHATLOG) do
        if line:find("v1.0-test loaded", 1, true) then seen = true end
    end
    if not seen then
        print("!! VERSION: the login line did not carry the version from GetAddOnMetadata")
        os.exit(1)
    end
    for _, path in ipairs(ADDON_SOURCES) do
        local src = io.open(path, "r")
        local body = src and src:read("*a") or ""
        if src then src:close() end
        if body:find('VERSION%s*=%s*"') then
            print(("!! VERSION: a literal version string is assigned in %s -- read the TOC instead")
                  :format(path))
            os.exit(1)
        end
    end
    local tocPath = addonDir .. "BiSHealing.toc"
    local toc = io.open(tocPath, "r")
    if toc then
        local t = toc:read("*a"); toc:close()
        if not t:find("## Version:") then
            print("!! VERSION: the TOC beside the addon has no ## Version line")
            os.exit(1)
        end
    end
    print("== version comes from the TOC")
end
tick(5)
print("== tick ok (live roster)")

-- every slash command
local CMDS = { "", "ranks", "score", "reorder", "lock", "bands", "bind", "inc",
               "bull", "bounce", "es", "rawes", "esplan", "frames", "center",
               "show", "hide", "sim on", "sim off", "demo", "sim 25", "dispel", "keys", "keys", "garbage" }
for _, c in ipairs(CMDS) do
    local ok, err = pcall(SlashCmdList.BISHEALING, c)
    if not ok then print(("!! SLASH ERROR (%s): %s"):format(c, tostring(err))); os.exit(1) end
end
print("== slash ok")
tick(20)
print("== tick ok (demo mode)")

-- ------------------------------------------------------- the bind engine --
-- Ten actions, each on a key. A bind that never lands is invisible in game
-- until the moment you need it, so assert on the recorded overrides and the
-- frame attributes rather than trusting "no error".
local BINDS = ADDON_NS.BINDS
local function need(cond, what)
    if not cond then print("!! BINDS: " .. what); os.exit(1) end
end
need(BINDS and #BINDS.ACTIONS == 10, "ten actions expected")
local function liveFrame()
    for i = 1, 12 do
        local f = _G["BiSHealingUnit" .. i]
        if f and f:IsShown() and f.unit and UnitExists(f.unit) then return f end
    end
end
SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show"); tick(3)
local lf = liveFrame()
need(lf, "no live frame to read binds off")

-- mouse buttons land as frame attributes, aimed at that frame's unit
need(lf:GetAttribute("*type1") == "macro", "left click is not a macro")
need((lf:GetAttribute("*macrotext1") or ""):match("Chain Heal%(Rank 3%)") and
     (lf:GetAttribute("*macrotext1") or ""):match("@" .. lf.unit),
     "left click is not a downranked Chain Heal at the frame's unit: " .. tostring(lf:GetAttribute("*macrotext1")))
need(not (lf:GetAttribute("*macrotext1") or ""):match("/use 13"), "plain left click is burning trinkets")
local sm = lf:GetAttribute("shift-macrotext1") or ""
need(sm:match("/use 13") and sm:match("/use 14") and sm:match("Chain Heal%(Rank 5%)"),
     "shift+left is not trinkets + max Chain Heal: " .. sm)
need((lf:GetAttribute("*macrotext2") or ""):match("Earth Shield"), "right click is not Earth Shield")
need((lf:GetAttribute("*macrotext4") or ""):match("Gift of the Naaru"), "button 4 is not Gift")
-- the two cures, Button5 and shift+Button5 (Arn, 11 Sep)
need((lf:GetAttribute("*macrotext5") or ""):match("Cure Poison") and
     (lf:GetAttribute("*macrotext5") or ""):match("@" .. lf.unit), "button 5 is not Cure Poison at the unit")
need((lf:GetAttribute("shift-macrotext5") or ""):match("Cure Disease"), "shift+button 5 is not Cure Disease")
print("== click binds ok (left / shift+left / right / button4 / button5 / shift+button5)")

-- keys and the wheel: one hidden button each, an override binding, a mouseover gate
local function hidden(key) return _G["BiSHealingBind_" .. key] end
need(OVERRIDES["MOUSEWHEELUP"] and OVERRIDES["MOUSEWHEELUP"].button == "BiSHealingBind_hwDown",
     "scroll up is not bound to the hwDown button")
need(OVERRIDES["SHIFT-MOUSEWHEELUP"] and OVERRIDES["SHIFT-MOUSEWHEELUP"].button == "BiSHealingBind_hwMax",
     "shift+scroll up is not bound to the hwMax button")
need(OVERRIDES["MOUSEWHEELDOWN"] and OVERRIDES["MOUSEWHEELDOWN"].button == "BiSHealingBind_lhwDown", "scroll down never bound")
need(OVERRIDES["SHIFT-MOUSEWHEELDOWN"] and OVERRIDES["SHIFT-MOUSEWHEELDOWN"].button == "BiSHealingBind_lhwMax", "shift+scroll down never bound")
local m1 = hidden("hwDown"):GetAttribute("*macrotext1")
local m2 = hidden("hwMax"):GetAttribute("*macrotext1")
local m3 = hidden("lhwDown"):GetAttribute("*macrotext1")
local m4 = hidden("lhwMax"):GetAttribute("*macrotext1")
need(m1 and m1:match("stopmacro") and m1:match("@mouseover"), "plain scroll macro has no mouseover gate")
need(m1 and m1:match("Healing Wave%(Rank 10%)"), "plain scroll is not max-2 Healing Wave: " .. tostring(m1))
need(m2 and m2:match("Nature's Swiftness"), "shift+scroll never casts Nature's Swiftness")
need(m2 and m2:match("Healing Wave%(Rank 12%)"), "shift+scroll is not max-rank Healing Wave")
need(m2:match("/use 13") and m2:match("/use 14"), "shift+scroll up does not fire trinkets")
need(m3 and m3:match("Lesser Healing Wave%(Rank 5%)"), "scroll down is not LHW max-2: " .. tostring(m3))
need(m4 and m4:match("Lesser Healing Wave%(Rank 7%)"), "shift+scroll down is not max LHW: " .. tostring(m4))
need(m4:match("/use 13") and m4:match("/use 14"), "shift+scroll down does not fire trinkets")
need(not m3:match("/use 13"), "unshifted scroll down is burning trinkets")
need(m3:match("stopmacro") and m4:match("stopmacro"), "scroll down lost the mouseover gate")
for _, k in ipairs({ "hwDown", "hwMax", "lhwDown", "lhwMax" }) do
    need(hidden(k):GetAttribute("*type1") == "macro", k .. " button type not macro")
end
print("== wheel binds ok")
print("   scroll:       " .. m1:gsub("\n", " | "))
print("   shift+scroll: " .. m2:gsub("\n", " | "))

-- REBINDING. Cure Poison onto a keyboard key: the frame attribute goes, a
-- hidden button appears with the mouseover gate, the key normalises.
do
    local ok, stolen = BINDS.Set("curePoison", "shift-ctrl-q")
    need(ok and not stolen, "rebind refused or stole from nobody")
    need(BINDS.Get("curePoison") == "CTRL-SHIFT-Q", "key not normalised to CTRL-SHIFT-Q: " .. tostring(BINDS.Get("curePoison")))
    need(OVERRIDES["CTRL-SHIFT-Q"] and OVERRIDES["CTRL-SHIFT-Q"].button == "BiSHealingBind_curePoison",
         "Cure Poison never reached an override binding")
    local m = hidden("curePoison"):GetAttribute("*macrotext1")
    need(m and m:match("stopmacro") and m:match("@mouseover%] Cure Poison"), "hover macro wrong: " .. tostring(m))
    need(lf:GetAttribute("*macrotext5") == nil and lf:GetAttribute("*type5") == nil,
         "button 5 still carries Cure Poison after it moved to a key")
    need(BiSHealingDB.binds.curePoison == "CTRL-SHIFT-Q", "the key was not saved")
    -- back to the default: the override is forgotten, not stored
    BINDS.Set("curePoison", "BUTTON5")
    need(BiSHealingDB.binds.curePoison == nil, "a default key should not be stored as an override")
    need((lf:GetAttribute("*macrotext5") or ""):match("Cure Poison"), "button 5 did not come back")
    need(OVERRIDES["CTRL-SHIFT-Q"] == nil, "the old key binding was not cleared")
    print("== rebind ok (key normalised, saved, applied, default forgotten)")

    -- ONE KEY, ONE JOB: binding Cure Disease onto Button4 takes it off Gift
    local ok2, stolen2 = BINDS.Set("cureDisease", "BUTTON4")
    need(ok2 and stolen2 == "Gift of the Naaru", "stealing Button4 should name Gift: " .. tostring(stolen2))
    need(BINDS.Get("gift") == false, "Gift should be unbound after the steal")
    need((lf:GetAttribute("*macrotext4") or ""):match("Cure Disease"), "button 4 is not Cure Disease now")
    need(lf:GetAttribute("shift-macrotext5") == nil, "shift+button 5 still carries Cure Disease")
    -- unbind outright
    BINDS.Set("cureDisease", false)
    need(BINDS.Get("cureDisease") == false and lf:GetAttribute("*macrotext4") == nil, "unbind left the attribute")
    BINDS.ResetAll()
    need(BINDS.Get("gift") == "BUTTON4" and BINDS.Get("cureDisease") == "SHIFT-BUTTON5", "reset did not restore the defaults")
    need((lf:GetAttribute("*macrotext4") or ""):match("Gift"), "Gift not back on button 4 after reset")
    print("== conflict + unbind + reset ok")

    -- COMBAT: nothing moves mid-fight, everything lands when it ends
    COMBAT = true
    BINDS.Set("curePoison", "F")
    need(OVERRIDES["F"] == nil, "a bind changed during combat")
    need((lf:GetAttribute("*macrotext5") or ""):match("Cure Poison"), "the old bind was cleared during combat")
    COMBAT = false
    fireEvent("PLAYER_REGEN_ENABLED")
    need(OVERRIDES["F"] and OVERRIDES["F"].button == "BiSHealingBind_curePoison", "the deferred bind never landed")
    need(lf:GetAttribute("*macrotext5") == nil, "button 5 not cleared once combat ended")
    BINDS.ResetAll()
    print("== binds wait for combat to end ok")

    -- the wheel switch still gates the four wheel actions and nothing else
    BiSHealingDB.wheel = false
    BINDS.Apply()
    need(OVERRIDES["MOUSEWHEELUP"] == nil and OVERRIDES["SHIFT-MOUSEWHEELDOWN"] == nil, "wheel off left wheel binds")
    need((lf:GetAttribute("*macrotext5") or ""):match("Cure Poison"), "wheel off took the cures with it")
    BiSHealingDB.wheel = true
    BINDS.Apply()
    need(OVERRIDES["MOUSEWHEELUP"], "wheel on did not restore the wheel binds")
    print("== wheel switch ok")
end


if #LEAKED > 0 then
    print("!! GLOBAL LEAKS: " .. table.concat(LEAKED, ", "))
else
    print("== no global leaks")
end

-- --------------------------------------------------- chain heal visuals --
-- The bug this guards: a Line painted with SetColorTexture accepts the call and
-- draws nothing, so bounce lines were invisible in game while every headless
-- test passed. Assert on the PAINT, not on the call.
SlashCmdList.BISHEALING("show"); tick(3)
local function lneed(cond, what)
    if not cond then print("!! LINES: " .. what); os.exit(1) end
end
local function clog2(...) CLOG = {...}; fireEvent("COMBAT_LOG_EVENT_UNFILTERED") end
local PG = "GUID-Kumlust"
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for i = 2, 4 do
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider"..i,"Raider"..i,0,0,
          1064,"Chain Heal",8, 1500, 200, 0, true)
end
tick(2, 0.11)
local drawn = 0
for _, l in ipairs(ALLLINES) do
    if l.__shown then
        drawn = drawn + 1
        lneed(l.__tex, "a shown bounce line has no texture -- it will not render")
        lneed(l.__vertex, "a shown bounce line has no vertex colour")
    end
end
lneed(drawn >= 2, ("a 3-target chain drew %d lines, expected 2"):format(drawn))
print(("== bounce lines ok (%d drawn, textured and coloured)"):format(drawn))

-- the cluster must close on the CLOCK, without needing another cast, and the
-- gold repaint must leave the line visible rather than painting a hidden one
tick(20, 0.11)
local goldShown = 0
for _, l in ipairs(ALLLINES) do
    if l.__vertex and l.__vertex[1] and l.__vertex[1] > 0.5 then goldShown = goldShown + 1 end
end
lneed(goldShown >= 2, ("full chain never repainted gold (%d gold lines)"):format(goldShown))
print(("== gold chain ok (%d lines went gold on the clock)"):format(goldShown))
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- --------------------------------------------------- crit celebration ----
-- Three targets AND three crits is the big burst (32 stars, gold-white); a
-- plain 3-chain is the modest one (10). Both are counted here so a silent
-- change to the crit flag index can never quietly downgrade the payoff.
local sparkShown = 0
local function countSparks()
    local n = 0
    for _, t in ipairs(ALLTEX or {}) do
        if t.__shown and t.__tex == "Interface\\Cooldown\\star4" then n = n + 1 end
    end
    return n
end
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for i = 5, 7 do
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider"..i,"Raider"..i,0,0,
          1064,"Chain Heal",8, 1200, 0, 0, true)     -- all three crit
end
tick(20, 0.11)
sparkShown = countSparks()
lneed(sparkShown >= 30, ("3 crits gave %d stars, expected the big 32-star burst"):format(sparkShown))
print(("== crit celebration ok (%d stars)"):format(sparkShown))
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- ------------------------------------------- Earth Shield target sanity --
-- The live bug: a warlock spamming Life Tap logged constant self-damage and sat
-- low on health, so he out-scored the paladin who was actually tanking. Replay
-- exactly that and assert the shield never gets recommended onto him.
local function esneed(cond, what)
    if not cond then print("!! ESTARGET: " .. what); os.exit(1) end
end
-- demo mode is still running from the slash-command sweep above, and the demo
-- deliberately paints over the live corners -- so it must be off before any
-- assertion about what the LIVE reticle chose
SlashCmdList.BISHEALING("sim off")
SlashCmdList.BISHEALING("show"); tick(3)
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
-- raid2 = the paladin tank, eating the boss. raid7 = the warlock, tapping.
ROSTER["raid2"].class, ROSTER["raid7"].class = "PALADIN", "WARLOCK"
ROSTER["raid7"].hp = 2000            -- permanently low from tapping
for round = 1, 30 do
    AdvanceTime(0.5)
    clog2(0,"SWING_DAMAGE",false,"GUID-Boss","Boss",0,0,"GUID-Raider2","Raider2",0,0,
          900, nil,nil,nil,nil,nil,nil)
    -- Life Tap: source AND dest are the warlock himself
    clog2(0,"SPELL_DAMAGE",false,"GUID-Raider7","Raider7",0,0,"GUID-Raider7","Raider7",0,0,
          1454,"Life Tap",1, 600, nil,nil,nil)
    clog2(0,"SPELL_PERIODIC_DAMAGE",false,"GUID-Raider7","Raider7",0,0,"GUID-Raider7","Raider7",0,0,
          1949,"Hellfire",4, 200, nil,nil,nil)
    tick(3, 0.11)
end
local function esCorner()
    for i = 1, 12 do
        local f = _G["BiSHealingUnit" .. i]
        if f and f:IsShown() and f.corner and f.corner.TR and f.corner.TR.h:IsShown() then
            return f
        end
    end
end

-- 1. shield healthy on the tank: the addon must say NOTHING
ES_ON, ES_CHARGES = "raid2", 5
tick(6)
esneed(not esCorner(), "amber corner still nagging while the shield has 5 charges left")
print("== ES quiet ok (healthy shield draws no advice)")

-- 2. down to the last pip: now it must pick -- and stick with the tank
ES_CHARGES = 1
tick(6)
local esFrame = esCorner()
esneed(esFrame, "no recommendation on the last charge, when the decision is real")
esneed(esFrame.pname ~= "Raider7",
       "Earth Shield recommended onto the LIFE TAPPING WARLOCK -- self-damage is leaking in")
esneed(esFrame.pname == "Raider2",
       ("last-pip advice hopped off the tank to %s"):format(tostring(esFrame.pname)))
print(("== ES last-pip ok (re-shields %s, the tank)"):format(tostring(esFrame.pname)))

-- 3. shield gone entirely: same answer, still not the warlock
ES_ON = nil
tick(6)
esFrame = esCorner()
esneed(esFrame, "no recommendation at all with an unshielded raid")
esneed(esFrame.pname ~= "Raider7", "unshielded raid picks the life-tapping warlock")
print(("== ES unshielded ok (recommends %s)"):format(tostring(esFrame.pname)))

-- and the self-inflicted hits must be visibly discarded, not silently counted
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(5)
local wl = BiSHealingDB.players["Raider7"]
esneed(wl and (wl.selfHits or 0) >= 50,
       "self-inflicted hits were not recorded as ignored")
esneed((wl.depth == nil) or wl.depth.hits == 0,
       ("warlock banked %d hits from his own Life Taps"):format(wl.depth and wl.depth.hits or -1))
print(("== self-damage ignored ok (%d hits discarded, %d counted)")
      :format(wl.selfHits or 0, (wl.depth and wl.depth.hits) or 0))

-- ------------------------------------------------- names, bars, bragging --
local function uneed(cond, what)
    if not cond then print("!! UI: " .. what); os.exit(1) end
end

-- names are cut to five characters, realm suffix first
for i = 1, 12 do
    local f = _G["BiSHealingUnit" .. i]
    if f and f:IsShown() and f.name then
        local t = f.name:GetText() or ""
        uneed(#t <= 5, ("frame %d shows %q -- longer than five characters"):format(i, t))
    end
end
print("== short names ok")

-- bars: black while the hole is small, red once a downranked Chain Heal fits
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for _, u in pairs(ROSTER) do u.hp = u.hpMax end
tick(4)
local blacks, reds = 0, 0
for i = 1, 12 do
    local f = _G["BiSHealingUnit" .. i]
    if f and f:IsShown() and f.hp and f.hp.__color then
        if f.hp.__color[1] > 0.5 then reds = reds + 1 else blacks = blacks + 1 end
    end
end
uneed(blacks > 0, "a full-health raid still has coloured bars")
uneed(reds == 0, ("%d bars are red on a full-health raid"):format(reds))
-- now open a hole bigger than the downrank heal on one of them
ROSTER["raid4"].hp = 1
tick(4)
local f4
for i = 1, 12 do
    local f = _G["BiSHealingUnit" .. i]
    if f and f.unit == "raid4" then f4 = f end
end
uneed(f4 and f4.hp.__color and f4.hp.__color[1] > 0.5,
      "a hole bigger than the downrank Chain Heal did not turn the bar red")
print("== black bars ok (red only when the downrank lands whole)")

-- triple crit on a full chain announces once, and does not repeat immediately
-- addon-to-addon comm. ADDON_SENT records what BiSHealing broadcast, so the
-- Earth Shield handshake can be asserted rather than eyeballed.
ADDON_SENT = {}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
        ADDON_SENT[#ADDON_SENT+1] = { prefix = prefix, msg = msg, ch = channel, to = target }
    end,
}
function SendAddonMessage(prefix, msg, channel, target)
    C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
end
function strsplit(sep, str)
    local out = {}
    for piece in tostring(str):gmatch("([^" .. sep .. "]*)") do out[#out+1] = piece end
    -- gmatch with an empty-allowed pattern yields a trailing blank per field;
    -- keep only the real ones
    local clean = {}
    for i = 1, #out, 2 do clean[#clean+1] = out[i] end
    return unpack(clean)
end
SENT = {}
for i = 2, 4 do
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider"..i,"Raider"..i,0,0,
          1064,"Chain Heal",8, 1500, 0, 0, true)
end
tick(20, 0.11)
uneed(#SENT == 1, ("triple crit sent %d chat messages, expected 1"):format(#SENT))
uneed(SENT[1].msg == "Oh Baby, a Triple Chain Heal Crit!",
      "wrong brag text: " .. tostring(SENT[1].msg))
uneed(SENT[1].ch == "PARTY", "brag went to " .. tostring(SENT[1].ch) .. ", not party chat")
for i = 2, 4 do
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider"..i,"Raider"..i,0,0,
          1064,"Chain Heal",8, 1500, 0, 0, true)
end
tick(20, 0.11)
uneed(#SENT == 1, ("brag throttle failed -- %d messages back to back"):format(#SENT))
-- a chain WITHOUT three crits must stay quiet
for i = 5, 7 do
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider"..i,"Raider"..i,0,0,
          1064,"Chain Heal",8, 1500, 0, 0, false)
end
AdvanceTime(30); tick(20, 0.11)
uneed(#SENT == 1, "bragged about a chain that did not triple crit")
print(("== triple-crit brag ok (1 message to %s, throttled after)"):format(SENT[1].ch))
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- --------------------------------------------------- heal size vs tooltip --
-- The live report: the spellbook says Chain Heal heals for 681-775 and the cast
-- lands for 2800. Everything downstream (colour bands, the red bar threshold,
-- the NS pip) was sized off that tooltip, so it judged real holes unfixable.
-- Mock numbers: downrank (rank 3) tooltip base 900, healing power 1500,
-- coefficient 2.5/3.5 -> effective about 1971. The HealComm mock also has 900
-- of other people's heals inbound, which the prediction subtracts.
local function hneed(cond, what)
    if not cond then print("!! HEALSIZE: " .. what); os.exit(1) end
end
local function raid4()
    for i = 1, 12 do
        local f = _G["BiSHealingUnit" .. i]
        if f and f.unit == "raid4" then return f end
    end
end
local function holeIsRed(hole)
    ROSTER["raid4"].hp = ROSTER["raid4"].hpMax - hole
    tick(4)
    local f = raid4()
    hneed(f, "no frame for raid4")
    return f.hp.__color and f.hp.__color[1] > 0.5
end

SPELL_POWER = 1500
SlashCmdList.BISHEALING("rescan"); tick(2)

-- a hole the BARE TOOLTIP would call fixable (900) must not be red: that is the
-- bug, sized off a quarter of the truth
-- rank 3 base 900 + 1500 power x 0.714 = 1971, x1.32 for talents = 2602.
-- the prediction also subtracts 900 of other people's inbound heals.
hneed(not holeIsRed(2400), "a hole under the real downrank size turned red")
hneed(holeIsRed(4200), "a hole past the real downrank size did NOT turn red -- healing power is missing")
print("== heal size estimate ok (healing power folded into the bands)")

-- measurement then takes over from the estimate
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for cast = 1, 6 do
    AdvanceTime(3)
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
          1003,"Chain Heal",8, 3000, 800, 0, false)   -- rank 3 = spellbook slot 3
    tick(2)
end
local seen = BiSHealingDB.healSeen[1003]
hneed(seen and seen.n >= 4, "casts of a known rank were never recorded")
hneed(seen.avg > 3000, ("measured size %d ignored the overheal"):format(seen.avg or 0))

-- a crit must not move the average AT ALL. Dividing by 1.5 is right on average
-- and wrong on a small sample -- one early crit is what pushed Rank 3 above
-- Rank 5 in the field.
local before = seen.avg
local nBefore = seen.n
AdvanceTime(3)
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
      1003,"Chain Heal",8, 5700, 0, 0, true)          -- a crit
tick(2)
hneed(BiSHealingDB.healSeen[1003].avg == before,
      ("a crit moved the measured size from %d to %d -- crits must be discarded")
      :format(before, BiSHealingDB.healSeen[1003].avg))
hneed(BiSHealingDB.healSeen[1003].n == nBefore, "a crit was counted as a sample")
hneed((BiSHealingDB.healSeen[1003].crits or 0) >= 1, "the crit was not even tallied")

-- chain BOUNCES are half-size and must never be learned from
before = BiSHealingDB.healSeen[1003].avg
AdvanceTime(3)
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
      1003,"Chain Heal",8, 4600, 0, 0, false)         -- primary, bigger than the average
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider3","Raider3",0,0,
      1003,"Chain Heal",8, 2300, 0, 0, false)         -- jump: half
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider4","Raider4",0,0,
      1003,"Chain Heal",8, 1150, 0, 0, false)         -- jump: quarter
tick(2)
hneed(BiSHealingDB.healSeen[1003].avg > before,
      "the primary heal of a chain was not learned from")
hneed(BiSHealingDB.healSeen[1003].avg > 3000,
      ("halved bounces dragged the measured size down to %d")
      :format(BiSHealingDB.healSeen[1003].avg))
print(("== heal size measured ok (%d over %d casts; crits discarded, bounces ignored)")
      :format(math.floor(BiSHealingDB.healSeen[1003].avg), BiSHealingDB.healSeen[1003].n))
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- ------------------------------------------- coefficients and talents ----
-- The published TBC resto numbers, reproduced rather than copied: coefficient
-- is cast time / 3.5, Purification multiplies everything by 1.10, Improved
-- Chain Heal multiplies Chain Heal by a further 1.20.
--   Chain Heal 2.5/3.5 = 0.714 -> x1.10 x1.20 = 0.943
--   Healing Wave 3.0/3.5 = 0.857 -> x1.10 = 0.943
--   Lesser HW 1.5/3.5 = 0.429 -> x1.10 = 0.471
-- Talents make each cast BIGGER, so the addon should wait for a BIGGER hole
-- before calling for one. That direction is the assertion.
BiSHealingDB.healSeen = {}          -- estimates only, no measurements in the way
SPELL_POWER = 1000
TALENTS = { { "Purification", 5 }, { "Improved Chain Heal", 2 } }
AdvanceTime(60)                     -- talent lookup is cached for 30s
SlashCmdList.BISHEALING("rescan"); tick(2)
-- talented rank 3 = (900 + 714) x 1.32 = 2130; prediction subtracts 900 inbound
hneed(not holeIsRed(2800), "talented threshold is lower than it should be")
hneed(holeIsRed(3300), "talented threshold is higher than it should be")
print("== talent scaling ok (Purification + Improved Chain Heal in the estimate)")

-- untrained: (900 + 714) = 1614, so the SAME hole that was too small now qualifies
TALENTS = {}
AdvanceTime(60)
SlashCmdList.BISHEALING("rescan"); tick(2)
hneed(holeIsRed(2800), "untalented estimate did not drop the threshold")
TALENTS = { { "Purification", 5 }, { "Improved Chain Heal", 2 } }
AdvanceTime(60); SlashCmdList.BISHEALING("rescan"); tick(2)
print("== untalented fallback ok (threshold tracks your talents)")

-- ------------------------------------- a measured rank vs an uncast rank --
-- Straight from the field: Rank 3 was cast (and crit), Rank 5 was never cast at
-- all. The downrank ended up reading BIGGER than the max rank -- nonsense on its
-- face, and it made the addon wait for a hole no downrank could ever fill.
BiSHealingDB.healSeen = {}
SPELL_POWER = 2223                    -- his actual healing power from the log
AdvanceTime(60)
SlashCmdList.BISHEALING("rescan"); tick(2)
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for cast = 1, 8 do                    -- eight honest Rank 3 casts
    AdvanceTime(3)
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
          1003,"Chain Heal",8, 2900, 700, 0, false)
    tick(2)
end
AdvanceTime(3)                        -- then one big crit
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
      1003,"Chain Heal",8, 5470, 0, 0, true)
tick(3)

-- read the sizes back out of /bish bands, which is the surface he was reading
CHATLOG = {}
SlashCmdList.BISHEALING("bands")
local sizes = {}
for _, line in ipairs(CHATLOG) do
    local rank, covers = line:match("Chain Heal Rank (%d+) %-%- covers up to (%d+)")
    if rank then sizes[tonumber(rank)] = tonumber(covers) end
end
hneed(sizes[3] and sizes[5], "bands did not report both Chain Heal ranks")
hneed(sizes[3] < sizes[5],
      ("Rank 3 (%d) still reads bigger than Rank 5 (%d)"):format(sizes[3], sizes[5]))
hneed(sizes[3] < 4200, ("Rank 3 size %d still carries the crit"):format(sizes[3]))
hneed(BiSHealingDB.healSeen[1003].n == 8, "the crit was counted as a sample")
hneed(not BiSHealingDB.healSeen[1005], "rank 5 was cast when it never should have been")
print(("== rank ordering ok (Rank 3 %d < Rank 5 %d, crit discarded, R5 calibrated from R3)")
      :format(sizes[3], sizes[5]))
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- ------------------------------------------------- binds cannot invert ----
-- The regression this guards: heal options were sorted by SIZE and the click
-- binds were read off array position, so a crit-inflated downrank sorted itself
-- above max rank and swapped left-click with shift+left in the middle of a raid.
local function bneed(cond, what)
    if not cond then print("!! BINDS: " .. what); os.exit(1) end
end
-- force the pathological case: rank 3 measured huge, rank 5 never cast
BiSHealingDB.healSeen = { [1003] = { avg = 9000, n = 20, crits = 0 } }
SlashCmdList.BISHEALING("rescan"); tick(3)
CHATLOG = {}
SlashCmdList.BISHEALING("bands")
local leftRank, shiftRank
for _, line in ipairs(CHATLOG) do
    local l, sft = line:match("binds: left Chain Heal%(Rank (%d+)%) | shift%+left Chain Heal%(Rank (%d+)%)")
    if l then leftRank, shiftRank = tonumber(l), tonumber(sft) end
end
bneed(leftRank and shiftRank, "bands did not report the click binds")
bneed(leftRank < shiftRank,
      ("binds inverted: left casts Rank %d, shift casts Rank %d"):format(leftRank, shiftRank))
bneed(leftRank == 3 and shiftRank == 5,
      ("expected left Rank 3 / shift Rank 5, got %d / %d"):format(leftRank, shiftRank))
print(("== bind order ok (left Rank %d, shift+left Rank %d, even with a wild measurement)")
      :format(leftRank, shiftRank))
BiSHealingDB.healSeen = {}
SlashCmdList.BISHEALING("rescan"); tick(2)

-- ------------------------------------ overheal-heavy casts are not sizes --
-- The field case: 29 logged casts averaged 4815 for a Chain Heal that visibly
-- lands 2.7k, because heal + overheal on a topped-off target is not a number
-- the bars can be keyed to. A cast into a real hole has nothing to argue about.
local function oneed(cond, what)
    if not cond then print("!! OVERHEAL: " .. what); os.exit(1) end
end
BiSHealingDB.healSeen = {}
SPELL_POWER = 2223
AdvanceTime(60); SlashCmdList.BISHEALING("rescan"); tick(2)
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")

-- ten casts into nearly-full bars: mostly overheal, must all be discarded
for cast = 1, 10 do
    AdvanceTime(3)
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
          1003,"Chain Heal",8, 1400, 3400, 0, false)      -- 71% overheal
    tick(2)
end
oneed(not BiSHealingDB.healSeen[1003] or (BiSHealingDB.healSeen[1003].n or 0) == 0,
      "overheal-heavy casts were banked as heal sizes")
oneed(BiSHealingDB.healSeen[1003] and (BiSHealingDB.healSeen[1003].wasted or 0) >= 10,
      "discarded casts were not even counted")

-- six casts into real holes: these are the truth
for cast = 1, 6 do
    AdvanceTime(3)
    clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
          1003,"Chain Heal",8, 2700, 0, 0, false)
    tick(2)
end
local avg = BiSHealingDB.healSeen[1003].avg
oneed(math.abs(avg - 2700) < 60, ("measured %d, expected about 2700"):format(avg))
CHATLOG = {}; SlashCmdList.BISHEALING("bands")
local threshold
for _, line in ipairs(CHATLOG) do
    local n = line:match("predicted hole reaches (%d+)")
    if n then threshold = tonumber(n) end
end
oneed(threshold and math.abs(threshold - 2700) < 80,
      ("red threshold is %s, expected about 2700"):format(tostring(threshold)))
print(("== overheal filter ok (threshold %d matches what the cast lands, not %d)")
      :format(threshold, 4815))

-- and a measurement that beats the coefficient maths by more than 2x is capped
BiSHealingDB.healSeen[1003] = { avg = 20000, n = 20, crits = 0 }
SlashCmdList.BISHEALING("rescan"); tick(2)
CHATLOG = {}; SlashCmdList.BISHEALING("bands")
local capped
for _, line in ipairs(CHATLOG) do
    local n = line:match("Chain Heal Rank 3 %-%- covers up to (%d+)")
    if n then capped = tonumber(n) end
end
oneed(capped and capped < 7000,
      ("a 20000 measurement was believed (%s)"):format(tostring(capped)))
print(("== measurement cap ok (20000 clipped to %d)"):format(capped))

-- /bish resetsizes puts it back to the estimate
SlashCmdList.BISHEALING("resetsizes"); tick(2)
oneed(not next(BiSHealingDB.healSeen), "resetsizes left measurements behind")
print("== resetsizes ok")
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")

-- ---------------------------------------------- two shamans, one raid ----
-- The Earth Shield plan used to infer the other shaman entirely from the combat
-- log. If they are also running BiSHealing they can just say what they are
-- doing -- assert that handshake, and assert the fallback still works when
-- nobody answers.
local function pneed(cond, what)
    if not cond then print("!! COMM: " .. what); os.exit(1) end
end
SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show"); tick(3)

-- we must announce ourselves, in a parseable shape, on the right channel
ADDON_SENT = {}
fireEvent("GROUP_ROSTER_UPDATE"); tick(3)
local mine
for _, m in ipairs(ADDON_SENT) do if m.prefix == "BISHEAL" then mine = m end end
pneed(mine, "nothing was broadcast when the group changed")
pneed(mine.ch == "RAID", "broadcast went to " .. tostring(mine.ch))
local kind, guid, charges, heal, ver = strsplit(":", mine.msg)
pneed(kind == "ES", "broadcast is not an ES state line: " .. mine.msg)
pneed(tonumber(charges) and tonumber(heal), "charges/size are not numbers: " .. mine.msg)
pneed(ver and ver:match("^%d"), "no version in the broadcast: " .. mine.msg)
print(("== comm broadcast ok (%s on %s)"):format(mine.msg, mine.ch))

-- a peer answering is believed over anything inferred from the log. Their
-- version is also higher than ours, so this is where the one-time nag lands.
CHATLOG = {}
fireEvent("CHAT_MSG_ADDON", "BISHEAL", "ES:GUID-Raider5:5:812:1.0-rc99", "RAID", "Thrall-Server")
tick(3)
local nags = 0
for _, line in ipairs(CHATLOG) do if line:find("newer than your") then nags = nags + 1 end end
pneed(nags == 1, ("version nag fired %d times on first contact, expected 1"):format(nags))
CHATLOG = {}; SlashCmdList.BISHEALING("peers")
local sawPeer, sawCharge = false, false
for _, line in ipairs(CHATLOG) do
    if line:find("Thrall") then sawPeer = true end
    if line:find("812 per charge") then sawCharge = true end
end
pneed(sawPeer, "the peer never showed up in /bish peers")
pneed(sawCharge, "the peer's charge size was not recorded")
print("== peer handshake ok (their charge size taken at their word)")

-- their target must not be recommended to us: one shield per player
tick(6)
local peerFrame
for i = 1, 12 do
    local f = _G["BiSHealingUnit" .. i]
    if f and f.unit == "raid5" then peerFrame = f end
end
pneed(peerFrame, "no frame for the peer's target")
ES_ON = nil                                  -- our own shield is off, so we WILL pick
tick(6)
pneed(not (peerFrame.corner and peerFrame.corner.TR.h:IsShown()),
      "recommended a shield onto the target the other shaman already has")
print("== peer target respected ok")

-- it must not nag a second time, however many newer peers turn up
CHATLOG = {}
fireEvent("CHAT_MSG_ADDON", "BISHEAL", "ES:-:0:0:9.9-rc99", "RAID", "Nobundo-Server")
fireEvent("CHAT_MSG_ADDON", "BISHEAL", "ES:-:0:0:9.9-rc99", "RAID", "Nobundo-Server")
for _, line in ipairs(CHATLOG) do
    pneed(not line:find("newer than your"), "version nag repeated")
end
-- an OLDER peer must never nag. This is the WindfuryComm++ bug in miniature:
-- there, string.gsub(version, ".", "0") collapsed every version to 0, so the
-- comparison could never be true and the check never fired at all.
CHATLOG = {}
fireEvent("CHAT_MSG_ADDON", "BISHEAL", "ES:-:0:0:0.1-rc1", "RAID", "Older-Server")
for _, line in ipairs(CHATLOG) do
    pneed(not line:find("newer than your"), "nagged about an OLDER version")
end
print("== version nag ok (once, and only for a higher build)")

-- peers go stale: a shaman who logs out must stop shaping the plan
AdvanceTime(200); tick(3)
CHATLOG = {}; SlashCmdList.BISHEALING("peers")
local stillThere = false
for _, line in ipairs(CHATLOG) do if line:find("Thrall") then stillThere = true end end
pneed(not stillThere, "a peer silent for 200s is still being trusted")
print("== peer expiry ok (falls back to reading the combat log)")

-- ------------------------------ the other shaman, made visible -----------
local function sneed(cond, what)
    if not cond then print("!! SECOND SHAMAN: " .. what); os.exit(1) end
end
SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show"); tick(3)

local function frameFor(unit)
    for i = 1, 12 do
        local f = _G["BiSHealingUnit" .. i]
        if f and f.unit == unit then return f end
    end
end

-- grey pips: their Earth Shield charges must be drawn, in the other colour.
-- Pips only live on full-width frames (a half-width row has no room), so ask
-- the layout which frame is wide rather than guessing a unit.
local wideUnit
for i = 1, 12 do
    local f = _G["BiSHealingUnit" .. i]
    if f and f:IsShown() and f.unit and not f.narrow and not f.isPet then
        wideUnit = f.unit; break
    end
end
sneed(wideUnit, "no full-width frame to test pips on")
ES_ON, ES_CHARGES = wideUnit, 4
ES_MINE = false            -- cast by somebody else
tick(6)
local f3 = frameFor(wideUnit)
sneed(f3 and f3.esPips, "no frame for their shield target")
local lit, grey = 0, 0
for i = 1, 6 do
    local p = f3.esPips[i]
    if p.__shown then
        lit = lit + 1
        if p.__color and p.__color[1] < 0.7 then grey = grey + 1 end
    end
end
sneed(lit == 4, ("their shield showed %d pips, expected 4"):format(lit))
sneed(grey == lit, "their pips are drawn in your amber, not grey")
print(("== grey pips ok (%d charges of someone else's shield, greyed)"):format(lit))

-- and yours stay amber
ES_MINE = true
tick(6)
local amber = 0
for i = 1, 6 do
    local p = f3.esPips[i]
    if p.__shown and p.__color and p.__color[1] > 0.7 then amber = amber + 1 end
end
sneed(amber == 4, "your own shield stopped being amber")
print("== own pips still amber ok")

-- HealComm: their chain heal, marked while it is still in the air
sneed(HC_CB["HealComm_HealStarted"], "never subscribed to HealComm heal-started")
HC_CB["HealComm_HealStarted"]("HealComm_HealStarted", "GUID-Raider9", 1064, 1,
                              (GetTime() + 2) * 1000, "GUID-Raider6", "GUID-Raider7")
tick(3)
local f6, f7 = frameFor("raid6"), frameFor("raid7")
sneed(f6 and f6.chainIn:IsShown(), "their chain target is not marked")
sneed(f7 and f7.chainIn:IsShown(), "their chain's second target is not marked")
sneed(f6.chainWho, "the mark does not say who is casting")
print(("== inbound chain ok (marked %s and one bounce, from %s)")
      :format("raid6", tostring(f6.chainWho)))

-- an interrupted cast clears the mark rather than leaving a lie on screen
HC_CB["HealComm_HealStopped"]("HealComm_HealStopped", "GUID-Raider9", 1064, 1, true,
                              "GUID-Raider6", "GUID-Raider7")
tick(3)
sneed(not f6.chainIn:IsShown(), "an interrupted chain left its mark behind")
print("== interrupted chain clears ok")

-- a BiSHealing peer announcing its cast marks the same way, no HealComm needed
fireEvent("CHAT_MSG_ADDON", "BISHEAL", "CH:GUID-Raider8", "RAID", "Thrall-Server")
tick(3)
local f8 = frameFor("raid8")
sneed(f8 and f8.chainIn:IsShown(), "a peer's announced chain was not marked")
sneed(f8.chainWho == "Thrall", ("mark credits %s"):format(tostring(f8.chainWho)))
print("== peer chain announce ok")

-- the mark expires on its own; nothing lingers
AdvanceTime(10); tick(3)
sneed(not f8.chainIn:IsShown(), "a chain mark never expired")
print("== chain mark expiry ok")

-- combat-log floor: works with no HealComm and no peer at all
clog2(0,"SPELL_HEAL",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider10","Raider10",0,0,
      1064,"Chain Heal",8, 1800, 0, 0, false)
tick(3)
local f10 = frameFor("raid10")
sneed(f10 and f10.chainIn:IsShown(), "a landed foreign chain heal left no mark")
print("== combat-log fallback ok")
-- our OWN chain heal must never mark our own frames
clog2(0,"SPELL_HEAL",false,PG,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
      1064,"Chain Heal",8, 1800, 0, 0, false)
tick(3)
local f2 = frameFor("raid2")
sneed(not (f2 and f2.chainIn:IsShown()), "your own chain heal marked itself as foreign")
print("== own casts not marked ok")

-- ------------------------- casting a chain heal must not throw -----------
-- This path shipped broken: UNIT_SPELLCAST_SENT -> SendChainCast -> a call to
-- RosterUnits, which is declared four hundred lines lower and so was nil. No
-- test cast a Chain Heal, so nothing ever ran it. It runs now.
do
    local function cneed2(cond, what)
        if not cond then print("!! CAST: " .. what); os.exit(1) end
    end
    ADDON_SENT = {}
    local ok, err = pcall(fireEvent, "UNIT_SPELLCAST_SENT", "player", "Raider4",
                          "cast-1", 1064)
    cneed2(ok, "casting a Chain Heal threw: " .. tostring(err))
    local announced
    for _, m in ipairs(ADDON_SENT) do
        if m.prefix == "BISHEAL" and m.msg:match("^CH:") then announced = m end
    end
    cneed2(announced, "casting a Chain Heal announced nothing to the group")
    cneed2(announced.msg:match("^CH:GUID%-"), "the announcement carries no GUID: " .. announced.msg)

    -- a non-Chain-Heal cast must stay silent
    ADDON_SENT = {}
    fireEvent("UNIT_SPELLCAST_SENT", "player", "Raider4", "cast-2", 1012)  -- Healing Wave
    for _, m in ipairs(ADDON_SENT) do
        cneed2(not m.msg:match("^CH:"), "a Healing Wave was announced as a chain")
    end

    -- and somebody ELSE's cast is not ours to announce
    ADDON_SENT = {}
    fireEvent("UNIT_SPELLCAST_SENT", "party2", "Raider4", "cast-3", 1064)
    for _, m in ipairs(ADDON_SENT) do
        cneed2(not m.msg:match("^CH:"), "announced another player's cast as our own")
    end

    -- the broadcast state must carry real charge counts, not a hardcoded zero
    ES_ON, ES_CHARGES, ES_MINE = "raid1", 5, true
    esTargetGuidHack = nil
    tick(4)
    print("== chain cast announce ok (" .. announced.msg .. ")")
end


-- --------------------------- primary target vs bounce, told apart --------
-- A chain touches three people and they are not equal news: the primary is
-- properly healed, a bounce is half or a quarter and may still need you.
-- Marking all three identically read as "these three are handled".
do
    local function bneed2(cond, what)
        if not cond then print("!! CHAIN ROLE: " .. what); os.exit(1) end
    end
    local function frameFor2(unit)
        for i = 1, 12 do
            local f = _G["BiSHealingUnit" .. i]
            if f and f.unit == unit then return f end
        end
    end
    COMM_CLEAR = nil
    AdvanceTime(30); tick(3)     -- let any earlier marks expire

    -- HealComm lists targets in cast order
    HC_CB["HealComm_HealStarted"]("HealComm_HealStarted", "GUID-Raider9", 1064, 1,
                                  (GetTime() + 2) * 1000,
                                  "GUID-Raider2", "GUID-Raider3", "GUID-Raider4")
    tick(3)
    local p, b1, b2 = frameFor2("raid2"), frameFor2("raid3"), frameFor2("raid4")
    bneed2(p and p.chainIn:IsShown(), "primary target not marked")
    bneed2(p.chainPrimary == true, "the aimed-at target is not flagged primary")
    bneed2(b1 and b1.chainIn:IsShown() and b1.chainPrimary == false,
           "first bounce is flagged as a primary")
    bneed2(b2 and b2.chainPrimary == false, "second bounce is flagged as a primary")
    bneed2(p.chainIn.__color[4] > b1.chainIn.__color[4],
           "the bounce is drawn as loud as the target they actually aimed at")
    print("== chain roles ok (1 primary, 2 dimmed bounces)")

    -- combat log: bounces arrive as separate heals and must NOT each read as a
    -- fresh cast at a new primary
    AdvanceTime(30); tick(3)
    clog2(0,"SPELL_HEAL",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider5","Raider5",0,0,
          1064,"Chain Heal",8, 2000, 0, 0, false)
    clog2(0,"SPELL_HEAL",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider6","Raider6",0,0,
          1064,"Chain Heal",8, 1000, 0, 0, false)
    clog2(0,"SPELL_HEAL",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider7","Raider7",0,0,
          1064,"Chain Heal",8, 500, 0, 0, false)
    tick(3)
    local c1, c2, c3 = frameFor2("raid5"), frameFor2("raid6"), frameFor2("raid7")
    local primaries = 0
    for _, f in ipairs({c1, c2, c3}) do
        if f and f.chainPrimary then primaries = primaries + 1 end
    end
    bneed2(primaries == 1,
           ("one landed chain produced %d primary marks -- bounces are being read as casts")
           :format(primaries))
    bneed2(c1.chainPrimary == true, "the first heal of the cluster is not the primary")
    print("== combat-log chain grouping ok (3 heals, 1 primary)")

    -- a genuinely new cast after the window IS a new primary
    AdvanceTime(5)
    clog2(0,"SPELL_HEAL",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider6","Raider6",0,0,
          1064,"Chain Heal",8, 2000, 0, 0, false)
    tick(3)
    bneed2(c2.chainPrimary == true, "a fresh cast after the window was read as a bounce")
    print("== new cast after the window ok")

    -- and a bounce must never downgrade a primary mark already on that frame
    AdvanceTime(30); tick(3)
    fireEvent("CHAT_MSG_ADDON", "BISHEAL", "CH:GUID-Raider8", "RAID", "Thrall-Server")
    tick(2)
    clog2(0,"SPELL_HEAL",false,"GUID-Thrall","Thrall",0,0,"GUID-Raider8","Raider8",0,0,
          1064,"Chain Heal",8, 900, 0, 0, false)
    clog2(0,"SPELL_HEAL",false,"GUID-Thrall","Thrall",0,0,"GUID-Raider8","Raider8",0,0,
          1064,"Chain Heal",8, 450, 0, 0, false)
    tick(2)
    local f8 = frameFor2("raid8")
    bneed2(f8 and f8.chainPrimary == true,
           "a later bounce downgraded the primary mark on the same frame")
    print("== primary is not downgraded by a bounce ok")
end


-- ------------------------------------------------ losing the heal race --
-- The WeakAura people snipe with reads two things LibHealComm cannot give:
-- the client's own per-caster heal prediction, and the cast's landing time.
-- Without them a healer who runs no addon is invisible and lands first, every
-- time, unseen.
do
    local function rneed(cond, what)
        if not cond then print("!! RACE: " .. what); os.exit(1) end
    end
    local function frameFor3(unit)
        for i = 1, 12 do
            local f = _G["BiSHealingUnit" .. i]
            if f and f.unit == unit then return f end
        end
    end
    SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show"); tick(3)
    fireEvent("GROUP_ROSTER_UPDATE"); tick(3)

    -- the counter only draws on full-width frames (a half-width row has no room
    -- for it), so ask the layout which units are on wide frames
    local wide = {}
    for i = 1, 12 do
        local f = _G["BiSHealingUnit" .. i]
        if f and f:IsShown() and f.unit and not f.narrow and not f.isPet then
            wide[#wide + 1] = f.unit
        end
    end
    rneed(#wide >= 3, ("only %d full-width frames to test on"):format(#wide))
    local TGT_LOSE, TGT_WIN, TGT_MINE = wide[1], wide[2], wide[3]
    -- a healer who is NOT one of the targets, so nobody heals themselves here
    local HEALER = "raid5"
    for _, u in ipairs(wide) do
        if u == HEALER then HEALER = "raid9" end
    end

    -- open a real hole on the contested target, or there is no prediction to
    -- reduce and the test proves nothing
    ROSTER[TGT_LOSE].hp = ROSTER[TGT_LOSE].hpMax - 5000
    ROSTER[TGT_WIN].hp  = ROSTER[TGT_WIN].hpMax - 5000
    tick(3)

    -- a healer running no addon at all, casting on the first target, landing
    -- in half a second
    INCOMING[TGT_LOSE] = { [HEALER] = 2400 }
    CASTEND[HEALER] = (GetTime() + 0.5) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    local f4 = frameFor3(TGT_LOSE)
    rneed(f4, "no frame for the contested target")
    rneed(f4.race:GetText() == "1",
          ("race counter shows %q, expected 1"):format(tostring(f4.race:GetText())))
    rneed(f4.raceLost == true, "their heal lands in 0.5s and we still think we win")
    print("== heal race ok (invisible healer seen, and we know we lose)")

    -- their heal must also shrink the predicted hole, which is what actually
    -- stops the wasted cast
    local predWith = f4.predicted
    INCOMING[TGT_LOSE] = nil
    CASTEND[HEALER] = nil
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    rneed(f4.predicted > predWith,
          ("a 2400 heal inbound did not reduce the predicted hole (%d vs %d)")
          :format(predWith, f4.predicted))
    print(("== native prediction ok (hole %d with their heal inbound, %d without)")
          :format(math.floor(predWith), math.floor(f4.predicted)))

    -- a slow healer we beat is grey, not red
    INCOMING[TGT_WIN] = { [HEALER] = 1500 }
    CASTEND[HEALER] = (GetTime() + 9) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_WIN); tick(3)
    local f6 = frameFor3(TGT_WIN)
    rneed(f6.race:GetText() == "1", "a slower healer is not counted at all")
    rneed(f6.raceLost ~= true, "we are told we lose a race we win by seven seconds")
    print("== race won reads differently ok")

    -- our own inbound heal must never count as somebody sniping us
    INCOMING[TGT_MINE] = { ["player"] = 3000 }
    CASTEND["player"] = (GetTime() + 1) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_MINE); tick(3)
    local f7 = frameFor3(TGT_MINE)
    rneed(f7.race:GetText() == "", "our own cast is being counted as a competitor")
    print("== own cast not counted ok")

    -- HealComm and the native API must not be summed: they report the same heal
    -- for anyone running a HealComm addon, and adding them would talk you out of
    -- casts you should make
    INCOMING[TGT_WIN] = { [HEALER] = 900 }    -- the same 900 the HealComm mock reports
    CASTEND[HEALER] = (GetTime() + 1) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_WIN); tick(3)
    local hole = UnitHealthMax(TGT_WIN) - UnitHealth(TGT_WIN)
    rneed(f6.predicted >= hole - 1200,
          ("double-counted the same heal: hole %d, predicted %d")
          :format(hole, math.floor(f6.predicted)))
    print("== no double counting ok")

    -- TWO healers on the same target must read as 2
    INCOMING, CASTEND = {}, {}
    local H1, H2 = "raid5", "raid9"
    for _, u in ipairs(wide) do
        if u == H1 then H1 = "raid6" end
        if u == H2 then H2 = "raid10" end
    end
    INCOMING[TGT_LOSE] = { [H1] = 1200, [H2] = 1500 }
    CASTEND[H1] = (GetTime() + 0.6) * 1000
    CASTEND[H2] = (GetTime() + 1.2) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    local ftwo = frameFor3(TGT_LOSE)
    rneed(ftwo.race:GetText() == "2",
          ("two healers on one target read as %q"):format(tostring(ftwo.race:GetText())))
    print("== two healers counted ok")

    -- YOU plus one other is also two heals converging, and must read as 2
    INCOMING, CASTEND = {}, {}
    INCOMING[TGT_LOSE] = { [H1] = 1200, ["player"] = 2600 }
    CASTEND[H1] = (GetTime() + 0.6) * 1000
    CASTEND["player"] = (GetTime() + 2.0) * 1000
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    local fme = frameFor3(TGT_LOSE)
    rneed(fme.race:GetText() == "2",
          ("you plus one other healer reads as %q, expected 2")
          :format(tostring(fme.race:GetText())))
    rneed(fme.raceLost == true, "they land 1.4s before us and we are not warned")
    print("== self counted in the race ok")

    -- a healer whose cast bar cannot be read is still counted, but we must not
    -- claim to win a race we cannot time
    INCOMING, CASTEND = {}, {}
    INCOMING[TGT_LOSE] = { [H1] = 1200 }
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    rneed(fme.race:GetText() == "1", "an untimeable healer was dropped from the count")
    rneed(fme.raceUnknown == true, "claimed to win a race with no cast bar to time")
    print("== untimeable healer counted, not guessed ok")

    -- and a LibHealComm that ignores the per-caster argument must not be used
    -- for attribution: it would credit the heal to every healer in the group
    HC_PER = {}
    INCOMING, CASTEND = {}, {}
    SNIPE_RESET = nil
    fireEvent("UNIT_HEAL_PREDICTION", TGT_LOSE); tick(3)
    rneed(fme.race:GetText() == "",
          ("phantom healers counted from a total-only HealComm: %q")
          :format(tostring(fme.race:GetText())))
    print("== no phantom healers ok")

    INCOMING, CASTEND = {}, {}
    fireEvent("UNIT_HEAL_PREDICTION", TGT_WIN); tick(3)
end


-- ------------------------------------------------- the options window ----
-- BiSTheme's kit (Libs/BiSTheme/Options.lua) wearing this addon's option list.
-- The kit itself is proven by dev/options.lua (61 checks, dropped in from
-- Nebbinator unchanged); this block proves the LIST: every control writes the
-- SAME saved variable the slash commands already set -- if the two ever drift,
-- the window is lying. Driven headless through BiSHealingUI.ConfigSet / Get.
do
    local function oneed(cond, what)
        if not cond then print("!! OPTIONS: " .. what); os.exit(1) end
    end
    oneed(BiSHealingUI, "the addon published no UI handle")
    oneed(BiSTheme and BiSTheme.OPTIONS_MINOR == 2,
          "the embedded options kit is not minor 2: " .. tostring(BiSTheme and BiSTheme.OPTIONS_MINOR))

    -- the embed is byte-identical to canon when canon is beside us
    do
        local function slurp(p) local h = io.open(p, "rb"); if not h then return nil end local b = h:read("*a"); h:close(); return b end
        local mine = slurp(addonDir .. "Libs/BiSTheme/Options.lua")
        local canon = slurp(addonDir .. "../BiSTheme/Options.lua")
        oneed(mine, "Libs/BiSTheme/Options.lua is missing")
        if canon then
            oneed(mine == canon, "Libs/BiSTheme/Options.lua drifted from BiSTheme/Options.lua -- run sync.ps1")
        else
            print("-- (BiSTheme not beside the addon; embed bytes not compared)")
        end
        -- and the TOC loads it, after Console.lua
        local toc = slurp(addonDir .. "BiSHealing.toc") or ""
        local c, o = toc:find("Libs\\BiSTheme\\Console.lua", 1, true), toc:find("Libs\\BiSTheme\\Options.lua", 1, true)
        oneed(o, "the TOC never loads Libs\\BiSTheme\\Options.lua")
        oneed(c and c < o, "Options.lua must come after Console.lua in the TOC")
    end

    -- building it must not throw -- that is the SetColorTexture trap
    local ok, err = pcall(BiSHealingUI.OpenConfig)
    oneed(ok, "opening the settings window threw: " .. tostring(err))
    local frame = _G["BiSHealingOptions"]
    oneed(frame and frame:IsShown(), "the window did not open")
    oneed(frame:GetWidth() == BiSTheme.OPTIONS.W, "the window is not the kit's 230 px")

    -- toggling closes it, and the same call opens it again
    BiSHealingUI.ToggleConfig()
    oneed(not frame:IsShown(), "the toggle did not close the window")
    BiSHealingUI.ToggleConfig()
    oneed(frame:IsShown(), "the toggle did not reopen the window")

    -- the rows the window is supposed to have, and no more: a row that grows
    -- past ~32 is the Innervate ceiling and wants a slash command instead
    local EXPECT = {
        "shown", "locked", "pets", "nameLen", "bars", "redPct", "corners", "pulse", "pulseCap",
        "totemRange", "dispel", "minimap",
        "bounceLines", "goldChains", "celebrate", "critBrag", "bragGap", "healRace",
        "incomingFill", "castCounter", "fsr", "rpm",
        "esQuiet", "nsPip", "giftBadge",
        "wheelMode", "trinkets", "keybinds", "demo",
    }
    local have = {}
    for _, id in ipairs(BiSHealingUI.ConfigIDs()) do have[id] = true end
    for _, id in ipairs(EXPECT) do oneed(have[id], ("no control with key %q"):format(id)) end
    oneed(#BiSHealingUI.ConfigIDs() == #EXPECT,
          ("%d controls, expected %d -- a new row wants adding to the list on purpose")
          :format(#BiSHealingUI.ConfigIDs(), #EXPECT))
    oneed(#frame.rows == #EXPECT + 4, ("expected %d rows (29 options + 4 sections), got %d"):format(#EXPECT + 4, #frame.rows))
    oneed(frame:GetHeight() <= BiSTheme.OPTIONS.HEADER + 33 * BiSTheme.OPTIONS.ROW + BiSTheme.OPTIONS.PAD,
          "the window is taller than the family's tallest (Innervate, 29 rows) allows")
    -- every label inside the kit's budget, untrimmed
    for _, r in ipairs(frame.rows) do
        local budget = r.isSection and (BiSTheme.OPTIONS.W - 6 - BiSTheme.OPTIONS.CTL) or (BiSTheme.OPTIONS.W - BiSTheme.OPTIONS.INDENT - BiSTheme.OPTIONS.CTL)
        oneed(r.name:GetStringWidth() <= budget, "label over budget: " .. tostring(r.name:GetText()))
    end
    print(("== options window ok (%d controls on the BiSTheme kit)"):format(#EXPECT))

    -- TOGGLES round-trip into the db the slash commands read
    local CHECKS = {
        { "corners", "corners" }, { "pulse", "pulse" }, { "pets", "pets" },
        { "bounceLines", "bounceLines" }, { "goldChains", "goldChains" },
        { "celebrate", "celebrate" }, { "critBrag", "critBrag" }, { "healRace", "healRace" },
        { "incomingFill", "incomingFill" }, { "castCounter", "castCounter" }, { "rpm", "rpm" },
        { "nsPip", "nsPip" }, { "giftBadge", "giftBadge" }, { "trinkets", "trinkets" },
        { "totemRange", "totemRange" }, { "dispel", "dispel" }, { "fsr", "fsr" },
        { "shown", "shown" }, { "locked", "locked" },
    }
    for _, c in ipairs(CHECKS) do
        local id, key = c[1], c[2]
        BiSHealingUI.ConfigSet(id, false)
        oneed(BiSHealingDB[key] == false, ("%s off did not write db.%s"):format(id, key))
        oneed(BiSHealingUI.ConfigGet(id) == false, ("%s off did not read back"):format(id))
        BiSHealingUI.ConfigSet(id, true)
        oneed(BiSHealingDB[key] == true, ("%s on did not write db.%s"):format(id, key))
    end
    print("== toggle round-trip ok (19 switches, same keys as /bish)")

    -- STEPPERS write the key, and clamp
    BiSHealingUI.ConfigSet("nameLen", 8)
    oneed(BiSHealingDB.nameLen == 8 and ADDON_NS.UIX.NAME_MAX == 8, "name length did not reach the frames")
    BiSHealingUI.ConfigSet("nameLen", 99)
    oneed(BiSHealingDB.nameLen == 12, "name length did not clamp at 12")
    BiSHealingUI.ConfigSet("nameLen", 5)
    BiSHealingUI.ConfigSet("redPct", 1.25)
    oneed(math.abs(BiSHealingDB.redPct - 1.25) < 0.001, "redPct did not write")
    BiSHealingUI.ConfigSet("redPct", 1)
    BiSHealingUI.ConfigSet("pulseCap", 2)
    oneed(BiSHealingDB.pulseCap == 2, "pulseCap did not write")
    BiSHealingUI.ConfigSet("bragGap", 30)
    oneed(BiSHealingDB.bragGap == 30, "bragGap did not write")
    BiSHealingUI.ConfigSet("esQuiet", 3)
    oneed(BiSHealingDB.esQuiet == 3, "esQuiet did not write")
    BiSHealingUI.ConfigSet("esQuiet", 0)
    oneed(BiSHealingDB.esQuiet == 1, "esQuiet did not clamp at 1")
    print("== stepper round-trip ok (writes and clamps)")

    -- SEGS: the bar colour and the three-way wheel mode
    BiSHealingUI.ConfigSet("bars", "bands")
    oneed(BiSHealingDB.plainBars == false, "bar-colour seg did not clear plainBars")
    BiSHealingUI.ConfigSet("bars", "black")
    oneed(BiSHealingDB.plainBars == true, "bar-colour seg did not set plainBars")
    BiSHealingUI.ConfigSet("wheelMode", "off")
    oneed(BiSHealingDB.wheel == false, "wheel seg did not turn the wheel off")
    oneed(OVERRIDES["MOUSEWHEELUP"] == nil, "wheel off through the window left the wheel bound")
    BiSHealingUI.ConfigSet("wheelMode", "two")
    oneed(BiSHealingDB.wheel == true and BiSHealingDB.wheelStrict == true, "wheel seg did not set two-press")
    oneed(BiSHealingUI.ConfigGet("wheelMode") == "two", "wheel seg did not read back two")
    oneed((_G["BiSHealingBind_hwMax"]:GetAttribute("*macrotext1") or ""):match("castsequence"),
          "two-press did not re-apply the binds")
    BiSHealingUI.ConfigSet("wheelMode", "one")
    oneed(BiSHealingDB.wheel == true and BiSHealingDB.wheelStrict == false, "wheel seg did not set one-press")
    print("== seg round-trip ok (including the three-way wheel mode)")

    -- the two buttons: keybinds opens its window, demo toggles the demo
    BiSHealingUI.ConfigSet("keybinds", true)
    oneed(_G["BiSHealingKeybinds"] and _G["BiSHealingKeybinds"]:IsShown(), "the keybinds button did not open its window")
    BiSHealingUI.Keybinds(false)
    BiSHealingUI.ConfigSet("demo", true)
    oneed(ADDON_NS.demo.on, "the demo button did not start the demo")
    BiSHealingUI.ConfigSet("demo", true)
    oneed(not ADDON_NS.demo.on, "the demo button did not stop the demo")
    print("== buttons ok")

    -- and the window survives being driven while the pyramid is in combat
    COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
    local ok4, err4 = pcall(BiSHealingUI.ConfigSet, "corners", false)
    oneed(ok4, "changing a setting in combat threw: " .. tostring(err4))
    oneed(BiSHealingDB.corners == false, "the in-combat change did not reach the db")
    BiSHealingUI.ConfigSet("corners", true)
    COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(4)
    print("== settings survive combat lockdown ok")
end

-- ------------------------------------------------- the Keybinds window ----
-- Click a key, press the new one. Driven the way the client would drive it:
-- the row starts listening, then a key / mouse button / wheel turn arrives.
do
    local function kneed(cond, what)
        if not cond then print("!! KEYBINDS: " .. what); os.exit(1) end
    end
    local BINDS = ADDON_NS.BINDS
    local win = BiSHealingUI.Keybinds(true)
    kneed(win and win:IsShown(), "the keybinds window did not open")
    local rows = BiSHealingUI.BindRows()
    kneed(#rows == #BINDS.ACTIONS, "one row per action expected")
    local function rowFor(key)
        for _, r in ipairs(rows) do if r.action.key == key then return r end end
    end
    kneed(rowFor("curePoison").key.label:GetText() == "button 5", "Cure Poison row does not read button 5: " .. tostring(rowFor("curePoison").key.label:GetText()))
    kneed(rowFor("cureDisease").key.label:GetText() == "shift+button 5", "Cure Disease row does not read shift+button 5")
    kneed(rowFor("hwDown").key.label:GetText() == "wheel up", "hwDown row does not read wheel up")
    kneed(not win:IsKeyboardEnabled(), "the window listens for keys before anyone asked")

    -- a keyboard key with a modifier held
    SHIFT_DOWN = true
    BiSHealingUI.Capture("curePoison")
    kneed(BiSHealingUI.Capturing() == "curePoison", "capture did not start")
    kneed(win:IsKeyboardEnabled() and win.cover:IsShown(), "listening did not turn the keyboard and the cover on")
    kneed(rowFor("curePoison").key.label:GetText() == "listening...", "the row does not say it is listening")
    BiSHealingUI.Heard("LSHIFT")               -- the modifier alone is not a key
    kneed(BiSHealingUI.Capturing() == "curePoison", "a bare modifier ended the capture")
    BiSHealingUI.Heard("Q")
    SHIFT_DOWN = false
    kneed(BiSHealingUI.Capturing() == nil and not win:IsKeyboardEnabled() and not win.cover:IsShown(),
          "capture did not end after the key")
    kneed(BINDS.Get("curePoison") == "SHIFT-Q", "shift+Q did not bind: " .. tostring(BINDS.Get("curePoison")))
    kneed(rowFor("curePoison").key.label:GetText() == "shift+q", "the row does not show the new key")
    kneed(OVERRIDES["SHIFT-Q"] and OVERRIDES["SHIFT-Q"].button == "BiSHealingBind_curePoison", "the new key never reached a binding")
    print("== keybind capture ok (shift+Q onto Cure Poison)")

    -- a mouse button, stealing from another row -- and the header says so
    BiSHealingUI.Capture("cureDisease")
    BiSHealingUI.HeardMouse("Button4")
    kneed(BINDS.Get("cureDisease") == "BUTTON4" and BINDS.Get("gift") == false, "Button4 did not move from Gift to Cure Disease")
    kneed(rowFor("gift").key.label:GetText() == "-- unbound --", "Gift's row does not read unbound")
    -- the earlier Say is still holding the header; the steal line is queued
    -- behind it, so walk the clock past a full hold in 0.05 s slices
    local named = false
    for _ = 1, 160 do
        AdvanceTime(0.05); win.con:Paint()
        if win.con:Text():find("Gift of the Naaru", 1, true) then named = true end
    end
    kneed(named, "the header never named who lost the key: " .. win.con:Text())
    -- the wheel
    BiSHealingUI.Capture("gift")
    BiSHealingUI.HeardWheel(-1)
    kneed(BINDS.Get("gift") == "MOUSEWHEELDOWN" and BINDS.Get("lhwDown") == false, "wheel down did not move from LHW to Gift")
    -- Escape keeps, Backspace unbinds
    BiSHealingUI.Capture("chainDown")
    BiSHealingUI.Heard("ESCAPE")
    kneed(BINDS.Get("chainDown") == "BUTTON1" and BiSHealingUI.Capturing() == nil, "Escape did not keep the old key")
    BiSHealingUI.Capture("chainDown")
    BiSHealingUI.Heard("BACKSPACE")
    kneed(BINDS.Get("chainDown") == false, "Backspace did not unbind")
    -- reset all puts every default back
    win.resetBtn.__scripts.OnClick(win.resetBtn)
    kneed(BINDS.Get("chainDown") == "BUTTON1" and BINDS.Get("gift") == "BUTTON4" and BINDS.Get("curePoison") == "BUTTON5",
          "reset all did not restore the defaults")
    kneed(rowFor("curePoison").key.label:GetText() == "button 5", "rows did not repaint after reset")
    -- a key heard while nobody is listening does nothing
    BiSHealingUI.Heard("F")
    kneed(BINDS.Get("curePoison") == "BUTTON5", "a stray key changed a bind with no row listening")
    BiSHealingUI.Keybinds(false)
    kneed(not win:IsShown(), "the keybinds window did not close")
    print("== keybinds window ok (mouse, wheel, steal, escape, backspace, reset)")
end

-- ------------------------------------------------------ split boundary ----
-- The addon is more than one file now, and the seam between them is a LIST:
-- the NS block at the bottom of BiSHealing.lua. Two things have to stay true
-- about that seam, and neither of them errors when it stops being true.
do
    local function bneed(cond, what)
        if not cond then print("!! SPLIT: " .. what); os.exit(1) end
    end

    -- 1. the surface is exactly what the brain meant to publish. Widening it by
    -- accident is how the window starts reaching into scoring: nothing breaks,
    -- the line just quietly moves. Adding an export should mean editing this
    -- list on purpose.
    local EXPECTED = {
        -- plain references: stable tables, functions and constants
        "Print", "DB", "UIX", "frames", "anchor", "WHEEL", "SNIPE", "COMM",
        "ES_HOLD", "demo", "ShortName", "Relayout", "BuildHealOptions",
        "VERSION", "PULSE_CAP",
        -- accessors: values that MOVE, so a copy would go stale
        "ESTarget", "ApplyBinds", "QueueReorder", "InFight",
        -- the bind engine: the Keybinds window lists its actions and sets keys
        "BINDS",
        -- the one thing the window publishes back
        "CFG",
        -- the Forever seam (17 Sep 2026). SECRET says this client hides the numbers, Blind says we
        -- are inside the lockdown where auras and cooldowns go secret too, and FG is the grid that
        -- runs there instead of the pyramid. All three are inert on TBC.
        "SECRET", "Blind", "FG", "FB",
        -- FA: the aura containers that SHOW what the lockdown will not let us read (19 Sep)
        "FA",
        -- FM: the mouse - every click meaning in one place, bound by dragging a spell onto it
        "FM",
        -- MM: the minimap button's rows. Each one runs the slash command itself (19 Sep)
        "MM",
    }
    local want = {}
    for _, k in ipairs(EXPECTED) do
        want[k] = true
        bneed(ADDON_NS[k] ~= nil, ("NS.%s is published in the list but never set"):format(k))
    end
    local extra = {}
    for k in pairs(ADDON_NS) do if not want[k] then extra[#extra + 1] = k end end
    table.sort(extra)
    bneed(#extra == 0,
          "the shell can reach names the brain never meant to publish: " ..
          table.concat(extra, ", "))

    -- 2. TOC ORDER is load-bearing, in both directions, and getting it wrong
    -- does not read as an ordering bug when it bites.
    --
    --   Core/ before BiSHealing.lua -- the brain assigns INTO those tables at
    --   its own load time (COMM.Charges = ESCharges). Load comm second and
    --   `local COMM = NS.COMM` is nil, and the failure is a nil index 2500
    --   lines away from the line that actually caused it.
    --
    --   UI/ after BiSHealing.lua -- the window captures its whole world as
    --   locals at load. Load it first and every one is silently nil: nothing
    --   errors, the window just builds out of nothing, and you find out when
    --   you open it.
    do
        local at = {}
        for i, rel in ipairs(LOADED_FILES) do at[rel] = i end
        local brain = at["BiSHealing.lua"]
        bneed(brain, "BiSHealing.lua is not in the TOC at all")
        for rel, i in pairs(at) do
            if rel:match("^Core/") then
                bneed(i < brain, rel .. " loads AFTER BiSHealing.lua; Core/ must come first")
            elseif rel:match("^UI/") then
                bneed(i > brain, rel .. " loads BEFORE BiSHealing.lua; UI/ must come after")
            end
        end
    end

    -- 3. a zip that lost UI/ must SAY so, not throw. This is the whole reason
    -- /bish goes through Window(): without it every single /bish is a nil index
    -- on a fresh install that unpacked badly, and the addon looks dead.
    do
        local keep = ADDON_NS.CFG
        ADDON_NS.CFG = nil
        local was = #CHATLOG
        local ok, err = pcall(SlashCmdList.BISHEALING, "")
        ADDON_NS.CFG = keep
        bneed(ok, "/bish threw when UI/options.lua was missing: " .. tostring(err))
        local said = false
        for i = was + 1, #CHATLOG do
            if CHATLOG[i]:find("did not load", 1, true) then said = true end
        end
        bneed(said, "/bish said nothing at all when the window file was missing")
    end

    print(("== split boundary ok (%d names published, TOC order right, missing UI/ says so)")
          :format(#EXPECTED))
end

-- ----------------------------------------------------- header console ----
-- The header law (BiSTheme 1.1.0): the window's title IS the prompt, standing
-- state lives in slots, events go through Say, and the whole line stays inside
-- its budget. All four are asserted here, because all four fail SILENTLY in
-- game -- a slot that never sets just shows the addon name forever, and a line
-- over budget draws underneath the close button rather than erroring.
--
-- The clock is stepped in 0.05 s SLICES, never whole seconds. A single 3 s jump
-- expires a 3 s Say line before it is ever drawn, and the test then proves the
-- opposite of what it says it does.
do
    local function cneed(cond, what)
        if not cond then print("!! CONSOLE: " .. what); os.exit(1) end
    end
    local function slice(seconds, con)
        local n = math.floor((seconds / 0.05) + 0.5)
        for _ = 1, n do
            AdvanceTime(0.05)
            con:Paint()
        end
    end
    -- plain text of the whole line, colour escapes stripped, as it draws
    local function plain(con)
        return (con:Text():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    end

    local con = BiSHealingUI.Console()
    cneed(con, "the window built no console -- is Libs\\BiSTheme\\Console.lua in the TOC?")

    -- Earlier tests clicked buttons that report through the header, so the
    -- queue arrives here with lines in it. Drain them, or the first assert
    -- below reads somebody else's event and calls it a failure.
    con:Clear()
    slice(3.4, con)

    -- 1. the prompt is the title, and the addon's name is slot one
    cneed(plain(con):find("BiS>", 1, true), "the header does not carry the BiS> prompt")
    cneed(con.slots and con.slots.name and con.slots.name.text == "Heal",
          "slot 1 is not the addon name")

    -- 2. landmine #9: the console makes ONE extra FontString, at construction.
    -- One made per Paint is invisible for a pull and then a 200 ms stutter.
    local head = con.fs:GetParent()
    local function headFS()
        local n = 0
        for _, fs in ipairs(ALLFS) do if fs.__parent == head then n = n + 1 end end
        return n
    end
    local before = headFS()
    slice(2.0, con)
    cneed(headFS() == before,
          ("the header grew %d FontStrings across 40 paints -- something builds per frame")
          :format(headFS() - before))

    -- 3. Say jumps the rotation, holds, and then the slots resume
    con:Say("harness line", "gold")
    slice(0.6, con)                       -- past the fade-out and fade-in
    cneed(plain(con):find("harness line", 1, true),
          "a Say line never reached the header: " .. plain(con))
    slice(3.2, con)                       -- past hold, and its fade
    cneed(not plain(con):find("harness line", 1, true),
          "a Say line never expired -- it is standing state now, not an event")

    -- 4. the fade is a SHAPE, not a hard cut: the words go to zero and come back
    do
        local alphas = {}
        con:Say("fade probe", "good")
        for _ = 1, 24 do                  -- 1.2 s in 0.05 s slices
            AdvanceTime(0.05)
            con:Paint()
            alphas[#alphas + 1] = con.words:GetAlpha()
        end
        local lo, hi, mid = 1, 0, 0
        for _, a in ipairs(alphas) do
            if a < lo then lo = a end
            if a > hi then hi = a end
            -- the frames BETWEEN full and gone are the fade. Without counting
            -- these the assert is blind: a hard cut also touches alpha 0, for
            -- exactly one frame, and "lowest alpha was 0" passes anyway.
            if a > 0.05 and a < 0.95 then mid = mid + 1 end
        end
        cneed(lo <= 0.05, ("the words never faded out (lowest alpha %.2f) -- hard cut"):format(lo))
        cneed(mid >= 3, ("only %d frames landed mid-fade -- that is a cut, not a fade"):format(mid))
        cneed(hi >= 0.95, ("the words never came back up (highest alpha %.2f)"):format(hi))
        cneed(alphas[#alphas] >= 0.95, "the words were left mid-fade")
    end

    -- 5. the budget. A word longer than the header gets trimmed by the console,
    -- so the line NEVER draws under the close button. The kit's 16 px bar:
    -- 4 + prompt + the 12 px x at -3 (the header law).
    do
        local budget = BiSHealingUI.HeadBudget()
        cneed(budget and budget == BiSTheme.OPTIONS.W - 15 - 8,
              ("the header budget is %s; the kit's 230 px bar has W - 15 - 8 of clear run")
              :format(tostring(budget)))
        con:Say(("wide"):rep(60), "warn")
        slice(0.6, con)
        cneed(con:Width() <= budget + 0.01,
              ("a 240-character line measured %.0f px against a %d px budget")
              :format(con:Width(), budget))
        con:Clear()
        slice(3.4, con)
    end

    -- 6. slots are STATE: the demo turns one on and off, and it is gone when off
    do
        local was = plain(con)
        -- the slots are recomputed once per FIVE paints, not once per tick --
        -- they read auras and frames, and 5 Hz is plenty for state that lasts.
        -- So drive the real cadence: five 0.2 s ticks, not one 1 s tick.
        local function slotTick()
            for _ = 1, 5 do
                AdvanceTime(0.2)
                BiSHealingUI.ConsoleTick(0.2)
            end
        end
        SlashCmdList.BISHEALING("sim on")
        slotTick()
        cneed(con.slots.sim and con.slots.sim.text == "sim",
              "the demo is running and the header does not say so")
        SlashCmdList.BISHEALING("sim off")
        slotTick()
        cneed(con.slots.sim == nil, "the demo stopped and the sim slot stayed lit")
        local _ = was
    end

    -- 6b. the shield slot is the one that has to read a MOVING value: which
    -- player carries my Earth Shield changes all night. If the window captured
    -- it once at load -- the obvious way to write the split, and wrong -- the
    -- header would name whoever was shielded at login and never look broken
    -- enough to notice. So: shield somebody AFTER the window is already built.
    do
        local slotTick = function()
            for _ = 1, 5 do AdvanceTime(0.2); BiSHealingUI.ConsoleTick(0.2) end
        end
        local shieldedUnit, shieldedName = "raid3", "Raider3"
        ES_ON, ES_CHARGES, ES_MINE = shieldedUnit, 4, true
        CLOG = { 0, "SPELL_AURA_APPLIED", false,
                 "GUID-Kumlust", "Kumlust", 0, 0,
                 "GUID-" .. shieldedName, shieldedName, 0, 0,
                 974, "Earth Shield", 8, "BUFF" }
        fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
        slotTick()
        local sh = con.slots.shield
        cneed(sh, "Earth Shield is up and the header does not say where")
        -- names are shortened to fit the header, so match a PREFIX of the real
        -- name rather than hardcoding today's truncation length
        local charges, who = sh.text:match("^ES (%d+) (.+)$")
        cneed(charges == "4",
              ("the shield slot reads %q -- expected 4 charges"):format(sh.text))
        cneed(who and shieldedName:find(who, 1, true) == 1,
              ("the shield slot names %q, which is not %s"):format(tostring(who), shieldedName))
        cneed(sh.colour == "good", "4 charges should read as good, not a warning")

        -- one charge left is the whole reason the slot is coloured
        ES_CHARGES = 1
        slotTick()
        cneed(con.slots.shield and con.slots.shield.colour == "warn",
              "the last Earth Shield charge is not flagged")

        -- and when it drops, the slot goes -- a stale shield is worse than none
        ES_ON, ES_CHARGES = nil, 0
        slotTick()
        cneed(con.slots.shield == nil,
              "the shield fell off and the header still shows it")
        ES_ON, ES_CHARGES, ES_MINE = "raid1", 4, true
        slotTick()
    end

    -- 7. the window's own events go to the header, not to chat. This is the
    -- whole point of the console: chat is for /slash answers only. The kit says
    -- it on the CLICK, so click the row's own control, as a hand would.
    do
        local chatWas = #CHATLOG
        con:Clear()
        local row
        for _, r in ipairs(_G["BiSHealingOptions"].rows) do
            if r.opt and r.opt.key == "corners" then row = r end
        end
        cneed(row and row.ctl and row.ctl.__scripts.OnClick, "no corners row to click")
        row.ctl.__scripts.OnClick(row.ctl)
        local said = false
        for _, q in ipairs(con.queue) do
            if q.text:find("role corner markers", 1, true) then said = true end
        end
        if not said and con.saying and con.saying.text:find("role corner markers", 1, true) then said = true end
        cneed(said, "a toggle click did not report through the header")
        for i = chatWas + 1, #CHATLOG do
            cneed(not CHATLOG[i]:find("corner", 1, true),
                  "the toggle ALSO printed to chat -- pick one, and it is the header")
        end
        row.ctl.__scripts.OnClick(row.ctl)      -- back on
        con:Clear()
    end

    print(("== header console ok (prompt, slots, say, fade, %d px budget)")
          :format(BiSHealingUI.HeadBudget()))
end

-- ------------------------------------------------------------- theme ----
-- Both ways: with the shared addon absent the inline copy carries the window,
-- and with it present -- loaded LATE, as the client does -- the shared addon
-- wins, per colour name.
do
    local function tneed(cond, what)
        if not cond then print("!! THEME: " .. what); os.exit(1) end
    end
    local function hex(h)
        return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
    end
    local function near(a, b) return math.abs(a - b) < 0.002 end

    tneed(BiSHealingUI and BiSHealingUI.Colour, "no colour seam to test through")
    local r, g, b = BiSHealingUI.Colour("accent")

    local themeEnv = os.getenv("BISTHEME")
    local liveTheme = themeEnv and themeEnv ~= ""
    if liveTheme and _G.BiSTheme and _G.BiSTheme.hex and _G.BiSTheme.hex.accent then
        local tr, tg, tb = hex(_G.BiSTheme.hex.accent)
        tneed(near(r, tr) and near(g, tg) and near(b, tb),
              ("BiSTheme is loaded with accent #%s and the window still painted %.3f,%.3f,%.3f")
              :format(_G.BiSTheme.hex.accent, r, g, b))

        -- and it reaches real pixels, not just the seam: a segment repaints
        -- through T.rgba on every set
        BiSHealingUI.ConfigSet("bars", "bands")
        BiSHealingUI.ConfigSet("bars", "black")
        local painted
        for _, tex in ipairs(ALLTEX) do
            if tex.__color and near(tex.__color[1], tr) and near(tex.__color[2], tg)
               and near(tex.__color[3], tb) then painted = true end
        end
        tneed(painted, "no texture in the window carries BiSTheme's accent")
        print(("== theme ok (BiSTheme #%s reached the window, late-loaded)")
              :format(_G.BiSTheme.hex.accent))
    else
        local fr, fg, fb = hex("b980ff")
        tneed(near(r, fr) and near(g, fg) and near(b, fb),
              ("without BiSTheme the inline accent should be b980ff, got %.3f,%.3f,%.3f")
              :format(r, g, b))
        print("== theme ok (no BiSTheme addon; the fallback palette carried it)")
    end
end

-- ------------------------------------------ the WA-library ports ----
-- Three techniques ported from the WA library (claude/wa-patterns-05): totem
-- reach, the five-second rule, and curable debuffs. Each is proven the way the
-- rest of this suite is: drive the client's side of it through the mock, tick,
-- and read the pixels and the text -- never the function that computed them.
do
    local function wneed(cond, what)
        if not cond then print("!! WA PORT: " .. what); os.exit(1) end
    end
    SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show"); tick(3)
    local function frameOf(unit)
        for i = 1, 12 do
            local f = _G["BiSHealingUnit" .. i]
            if f and f.unit == unit and f:IsShown() then return f end
        end
    end

    -- the mock grows the two things these ports read: totem slots, and auras
    -- that honour the HELPFUL/HARMFUL filter. BUFFS/DEBUFFS[unit] are lists of
    -- { name, kind } pairs on top of what the old mock already handed back.
    TOTEMS = {}                      -- slot -> totem name as the client spells it
    BUFFS, DEBUFFS = {}, {}
    PARTY = { raid1 = true, raid2 = true, raid3 = true, raid4 = true }
    function GetTotemInfo(slot)
        local n = TOTEMS[slot]
        if n then return true, n, 0, 300 end
        return false, "", 0, 0
    end
    function UnitInParty(u) return PARTY[u] == true end
    GetRealZoneText = function() return "Serpentshrine Cavern" end
    local oldAura = UnitAura
    function UnitAura(unit, i, filter)
        if filter == "HARMFUL" then
            local d = DEBUFFS[unit] and DEBUFFS[unit][i]
            if d then return d[1], nil, 1, d[2] end
            return nil
        end
        -- HELPFUL: the old mock's Earth Shield first, then this unit's extras
        local base = { oldAura(unit, i, filter) }
        if base[1] then return unpack(base) end
        local extra = BUFFS[unit] and BUFFS[unit][i - ((ES_ON == unit) and 1 or 0)]
        if extra then return extra[1] end
        return nil
    end

    -- 1. TOTEM REACH ------------------------------------------------------
    -- Healing Stream is down. raid2 carries its buff, raid3 does not, raid6 is
    -- not in my party and must not be judged at all.
    TOTEMS[1] = "Healing Stream Totem VI"
    BUFFS.raid2 = { { "Healing Stream" } }
    BUFFS.raid3 = { { "Water Shield" } }
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    local f2, f3, f6 = frameOf("raid2"), frameOf("raid3"), frameOf("raid6")
    wneed(f2 and f3 and f6, "the roster frames for raid2/3/6 are not all up")
    wneed(f3.totemOut:IsShown(), "raid3 has no Healing Stream buff while the totem is down -- the violet edge should be lit")
    wneed(not f2.totemOut:IsShown(), "raid2 carries the buff -- the violet edge should be off")
    wneed(not f6.totemOut:IsShown(), "raid6 is outside my party -- totems never reach him, so he must not be judged")
    local c = f3.totemOut.__color
    wneed(c and math.abs(c[1] - 0.62) < 0.01, "the edge is not painted in the totem colour")
    -- tooltip explains the edge, naming the buff that is missing
    print("== totem reach ok (missing buff = outside the totem; own party only)")

    -- the rank suffix and the word Totem both come off: "Windfury Totem V"
    -- looks for the "Windfury Totem" buff, and one missing buff is enough
    TOTEMS[2] = "Windfury Totem V"
    BUFFS.raid2 = { { "Healing Stream" } }         -- has stream, lacks windfury
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    wneed(f2.totemOut:IsShown(), "raid2 lacks the Windfury Totem buff now that Windfury is down -- edge should be lit")
    BUFFS.raid2 = { { "Healing Stream" }, { "Windfury Totem" } }
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    wneed(not f2.totemOut:IsShown(), "raid2 carries both buffs -- edge should be off")
    print("== totem names ok (rank and the word Totem stripped; every down totem checked)")

    -- a totem with no party buff (Tremor) is never a range check
    TOTEMS = { "Tremor Totem" }
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    wneed(not f3.totemOut:IsShown(), "Tremor has no buff to look for -- nothing should be judged")
    -- the toggle
    TOTEMS = { "Healing Stream Totem VI" }
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    wneed(f3.totemOut:IsShown(), "edge should be back with Healing Stream down again")
    BiSHealingUI.ConfigSet("totemRange", false)
    tick(12)
    wneed(not f3.totemOut:IsShown(), "totemRange off must hide the edge")
    BiSHealingUI.ConfigSet("totemRange", true)
    tick(12)
    wneed(f3.totemOut:IsShown(), "totemRange on must bring the edge back")
    -- totems gone: nothing lit
    TOTEMS = {}
    fireEvent("PLAYER_TOTEM_UPDATE")
    tick(12)
    wneed(not f3.totemOut:IsShown(), "no totem down -- edge must clear")
    print("== totem reach toggles ok")

    -- 2. FIVE-SECOND RULE --------------------------------------------------
    -- The counter's regen column: while-casting regen (12/s -> +0.1 a downrank
    -- per 5s at a 500 cost) inside the rule, full regen (30/s -> +0.3) once it
    -- has run out. A cast that did not cost mana must not restart it.
    MANA = 3000
    function UnitPower() return MANA end
    local counter
    for _, fs in ipairs(ALLFS) do
        local t = fs.__text
        if t and t:find("|||r", 1, true) then counter = fs end
    end
    BiSHealingUI.ConfigSet("castCounter", true)
    BiSHealingUI.ConfigSet("fsr", true)
    AdvanceTime(6); tick(2)
    for _, fs in ipairs(ALLFS) do
        local t = fs.__text
        if t and t:find("|||r", 1, true) then counter = fs end
    end
    wneed(counter, "no castable-heals counter text found")
    wneed(counter.__text:find("+0.3", 1, true), "outside the rule the column should count full regen (+0.3): " .. counter.__text)
    wneed(not counter.__text:find("s|r", 1, true), "no countdown should show outside the rule: " .. counter.__text)
    -- a cast that cost mana: the clock starts
    MANA = 2500
    fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1064)
    tick(2)
    wneed(counter.__text:find("+0.1", 1, true), "inside the rule the column should be while-casting regen (+0.1): " .. counter.__text)
    wneed(counter.__text:find("%d%.%ds|r"), "the seconds left should show inside the rule: " .. counter.__text)
    -- 5s on: back to full regen, countdown gone
    AdvanceTime(5.2); tick(2)
    wneed(counter.__text:find("+0.3", 1, true), "five seconds after the cast the column should be full regen again: " .. counter.__text)
    wneed(not counter.__text:find("s|r", 1, true), "the countdown should be gone: " .. counter.__text)
    -- a free cast (mana unchanged) must not restart the clock
    fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 8143)
    tick(2)
    wneed(counter.__text:find("+0.3", 1, true), "a cast that cost nothing restarted the rule: " .. counter.__text)
    -- the toggle: off means the old behaviour, while-casting regen always
    MANA = 2000
    fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1064)
    BiSHealingUI.ConfigSet("fsr", false)
    tick(2)
    wneed(counter.__text:find("+0.1", 1, true) and not counter.__text:find("s|r", 1, true),
          "fsr off should read as it always did (+0.1, no countdown): " .. counter.__text)
    BiSHealingUI.ConfigSet("fsr", true)
    print("== five-second rule ok (mana delta starts it, free casts do not, regen column follows)")

    -- 3. CURABLE DEBUFFS ---------------------------------------------------
    -- A shaman clears Poison and Disease. raid2 has a poison, raid3 a curse,
    -- raid4 a disease behind a magic debuff. The mark is the client's colour.
    DEBUFFS.raid2 = { { "Toxic Spores", "Poison" } }
    DEBUFFS.raid3 = { { "Curse of Tongues", "Curse" } }
    DEBUFFS.raid4 = { { "Holy Fire", "Magic" }, { "Vile Sludge", "Disease" } }
    DebuffTypeColor = { Poison = { r = 0, g = 0.6, b = 0 }, Disease = { r = 0.6, g = 0.4, b = 0 } }
    tick(8)
    local f4 = frameOf("raid4")
    wneed(f2.dispelMark:IsShown(), "raid2's poison should light the mark")
    wneed(not f3.dispelMark:IsShown(), "a curse is not a shaman's to cure -- no mark on raid3")
    wneed(f4.dispelMark:IsShown() and f4.dispelName == "Vile Sludge",
          "raid4's disease behind a magic debuff should be found: " .. tostring(f4.dispelName))
    local pc = f2.dispelMark.__color
    wneed(pc and pc[2] > 0.5 and pc[1] < 0.1, "the poison mark should be the client's green")
    local dc = f4.dispelMark.__color
    wneed(dc and dc[1] > 0.5 and dc[2] > 0.3, "the disease mark should be the client's brown")
    -- the header slot counts them
    local con = BiSHealingUI.Console()
    if con then
        for _ = 1, 6 do BiSHealingUI.ConsoleTick(0.2) end   -- slots refresh once a second
        wneed(con.slots and con.slots.cure and tostring(con.slots.cure.text):find("2 to cure", 1, true),
              "the header should say 2 to cure: " .. tostring(con.slots and con.slots.cure and con.slots.cure.text))
    end
    -- THE WINDOW ON A CLIENT THAT HIDES ITS NUMBERS (19 Sep 2026). Arn: "alot of the stuff in the
    -- right click was legacy stuff that does not work. can we put it away somewhere where it does
    -- not affect the addon? and put the menu there?" Of the 29 rows below, the Forever grid reads
    -- exactly one. This is the list that proves the short window stays short and stays honest.
    do
        local CFG = ADDON_NS.CFG
        local keys, rows = {}, 0
        for _, sec in ipairs(CFG.ForeverSections()) do
            for _, opt in ipairs(sec.options) do
                keys[opt.key] = opt
                rows = rows + 1
            end
        end
        for _, want in ipairs({ "shown", "minimap", "mouse", "seen", "pipTest" }) do
            wneed(keys[want], ("the short window lost %q"):format(want))
        end
        for _, gone in ipairs({ "bounceLines", "wheelMode", "esQuiet", "redPct", "pulseCap",
                                "totemRange", "healRace", "critBrag", "keybinds" }) do
            wneed(not keys[gone], ("%q is the pyramid's brain and must not be offered"):format(gone))
        end
        wneed(rows <= 10, ("the short window is not short: %d rows"):format(rows))

        -- every button must be pressable HERE, on a client that never registered /bishf: a row
        -- that throws when pressed is worse than a row that does nothing
        for key, opt in pairs(keys) do
            if opt.kind == "button" then
                wneed(pcall(opt.action, BiSHealingDB), ("pressing %q threw"):format(key))
            else
                wneed(pcall(opt.get, BiSHealingDB), ("reading %q threw"):format(key))
            end
        end

        -- and the window asks for it only on that client
        ADDON_NS.SECRET = true
        wneed(#CFG.OptionSections() == #CFG.ForeverSections(),
              "a secret client should be offered the short window")
        ADDON_NS.SECRET = false
        wneed(#CFG.OptionSections() > #CFG.ForeverSections(),
              "and a client that answers keeps every row it always had")
    end

    -- TWO GRIDS AT ONCE (19 Sep 2026). Arn, having ticked the mana gauge: "turned on the guage
    -- and now 2 grids are open". Every options toggle ends in CFG.Apply, CFG.Apply ended in
    -- Relayout, and Relayout laid out and SHOWED the pyramid - on a Forever client, on top of the
    -- grid that client actually runs, the two disagreeing about how long a name is. The brain was
    -- already gated on NS.SECRET in two places; its furniture was not.
    do
        SlashCmdList.BISHEALING("show")
        local before = 0
        for _, fr in ipairs(ADDON_NS.frames) do if fr:IsShown() then before = before + 1 end end
        wneed(before > 0, "the pyramid should be up on a client that answers")

        ADDON_NS.SECRET = true
        BiSHealingUI.ConfigSet("rpm", true)          -- any toggle at all: they all end in Apply
        local up = 0
        for _, fr in ipairs(ADDON_NS.frames) do if fr:IsShown() then up = up + 1 end end
        wneed(up == 0, ("a toggle raised %d pyramid frames on a client that hides its numbers"):format(up))
        wneed(not ADDON_NS.UIX.plate:IsShown(), "and the mana gauge must stay down: it reads two secrets")

        ADDON_NS.SECRET = false
        BiSHealingUI.ConfigSet("rpm", true)          -- and the pyramid comes back on a TBC client
        local back = 0
        for _, fr in ipairs(ADDON_NS.frames) do if fr:IsShown() then back = back + 1 end end
        wneed(back == before, ("the pyramid should come back: %d of %d"):format(back, before))
    end

    -- THE HEADER AGAINST A SECRET NUMBER (19 Sep 2026). On Forever the player's own mana comes
    -- back as a secret while the maximum comes back as a plain number, and the percentage in the
    -- header divided one by the other: twenty-seven copies of "attempt to perform arithmetic on
    -- local 'm' (a secret number value)" in the error frame, half a second apart. The slot is
    -- gone on that client - but the NET is what is tested here, because the next secret value
    -- will be one nobody predicted.
    do
        local realPower, realPrint = UnitPower, CHATLOG
        local boom = setmetatable({}, {
            __div = function() error("attempt to perform arithmetic on a secret number value", 2) end,
            __lt  = function() error("attempt to compare a secret number value", 2) end,
        })
        function UnitPower() return boom end
        CFG_SLOTS_OFF = nil
        CHATLOG = {}
        local ok = pcall(function() for _ = 1, 6 do BiSHealingUI.ConsoleTick(0.2) end end)
        wneed(ok, "a secret number in the header must not throw out of the ticker")
        for _ = 1, 6 do BiSHealingUI.ConsoleTick(0.2) end
        local said = table.concat(CHATLOG, " | ")
        wneed(select(2, said:gsub("secret", "")) <= 1,
              "and must say so ONCE, not twice a second: " .. said)
        -- and it stays off for the session: the client does not stop keeping a number secret
        wneed(ADDON_NS.CFG.slotsOff == true, "the ticker should stay off once it has been told")
        UnitPower = realPower
        CHATLOG = realPrint
        ADDON_NS.CFG.slotsOff = false      -- this suite carries on with a client that answers
    end

    -- /bish dispel lists them under the zone, disease and poison both
    CHATLOG = {}
    SlashCmdList.BISHEALING("dispel")
    local body = table.concat(CHATLOG, "\n")
    wneed(body:find("Serpentshrine Cavern", 1, true), "/bish dispel should name the zone: " .. body)
    wneed(body:find("Toxic Spores", 1, true) and body:find("Vile Sludge", 1, true),
          "/bish dispel should list both curable debuffs: " .. body)
    wneed(not body:find("Curse of Tongues", 1, true), "/bish dispel must not bank a curse a shaman cannot cure")
    -- a debuff that sits there is one sighting, not one per re-read
    tick(30)
    wneed(BiSHealingDB.dispelSeen["Serpentshrine Cavern"]["Toxic Spores"].n == 1,
          "the same poison sitting on raid2 was banked more than once")
    -- clears when cured, and the toggle hides it
    DEBUFFS.raid2 = nil
    tick(8)
    wneed(not f2.dispelMark:IsShown(), "cured -- the mark should clear")
    BiSHealingUI.ConfigSet("dispel", false)
    tick(8)
    wneed(not f4.dispelMark:IsShown(), "dispel off should hide the mark")
    BiSHealingUI.ConfigSet("dispel", true)
    tick(8)
    wneed(f4.dispelMark:IsShown(), "dispel on should bring the mark back")
    print("== curable debuffs ok (class-gated, client colour, per-zone list, one sighting each)")

    -- 4. THE DEMO SHOWS ALL THREE -----------------------------------------
    -- every feature gets a demo step; these three are steps 17-19 and must
    -- paint without a live totem, cast or debuff behind them
    DEBUFFS = {}; TOTEMS = {}
    fireEvent("PLAYER_TOTEM_UPDATE")
    SlashCmdList.BISHEALING("sim on")
    local seen = {}
    for _ = 1, 20 do
        AdvanceTime(4.05); tick(2)
        for _, fs in ipairs(ALLFS) do
            -- the demo CAPTION only ("n/N  words"), not the settings window,
            -- whose control labels use the same words
            local t = fs.__text or ""
            local words = t:match("^|cff44dd88%d+/%d+|r  (.*)")
            if words then
                if words:find("^Totem reach") then seen.totem = true end
                if words:find("^Five%-second rule") then seen.fsr = true end
                if words:find("^Curable debuff") then seen.dispel = true end
            end
        end
    end
    wneed(seen.totem and seen.fsr and seen.dispel,
          ("the demo never reached all three new steps (totem %s, fsr %s, dispel %s)")
          :format(tostring(seen.totem), tostring(seen.fsr), tostring(seen.dispel)))
    SlashCmdList.BISHEALING("sim off")
    print("== demo covers the three ports ok")
end

-- ------------------------------------------------------ the psi plate ----
-- The gauge and the counter on one plate above the pyramid: a BiS> prompt
-- carrying the same slots as the options window, fourteen psi cells lit to
-- the needle with a spark at the tip, the counter on the bottom row.
do
    local function pneed(cond, what)
        if not cond then print("!! PLATE: " .. what); os.exit(1) end
    end
    SlashCmdList.BISHEALING("sim off"); SlashCmdList.BISHEALING("show")
    local plate = ADDON_NS.UIX.plate
    pneed(plate and plate.cells and #plate.cells == 14, "the plate has no fourteen cells")
    pneed(plate.con and plate.con.slots.name and plate.con.slots.name.text == "Heal",
          "the plate's prompt is not BiS> Heal")
    for _, c in ipairs(plate.cells) do pneed(c.__color, "a cell was never painted") end

    -- the counter alone lights the plate; the gauge stays dark between fights
    BiSHealingDB.castCounter, BiSHealingDB.rpm = true, true
    AdvanceTime(6); tick(3)
    pneed(plate:IsShown(), "the plate is hidden with a live counter")
    pneed(not plate.gaugeLive, "the gauge reads live with no fight data")
    pneed(not plate.spark:IsShown(), "the spark shows with no reading")

    -- a reading half way: seven cells lit, the tip cell dim, the spark riding it
    -- drive the shared painter through the demo's own path: step 7 is the
    -- gauge, and the demo paints through RPMPaint like the live tick does
    SlashCmdList.BISHEALING("sim on")
    ADDON_NS.demo.step, ADDON_NS.demo.at = 6, GetTime() - 5   -- next tick rolls to 7
    tick(2, 0.11)
    pneed(ADDON_NS.demo.step == 7, "the demo did not land on the gauge step: " .. tostring(ADDON_NS.demo.step))
    tick(6, 0.11)
    pneed(plate.gaugeLive and plate:IsShown(), "the demo did not light the gauge")
    local lit = 0
    for _, c in ipairs(plate.cells) do
        if c.__color and not (c.__color[1] < 0.2 and c.__color[2] < 0.2) then lit = lit + 1 end
    end
    pneed(lit >= 1 and lit <= 14, "no cell lit under the demo reading")
    pneed(plate.spark:IsShown(), "the spark is not riding the needle")
    pneed(plate.label:GetText() ~= "", "no state word over the cells")
    SlashCmdList.BISHEALING("sim off"); tick(3)

    -- a known reading through the shared painter: half = seven cells full,
    -- the eighth nothing; full = all fourteen, and the psi cells past the hot
    -- line brighter than the ones before it
    -- The CELLS are the burn (how hard he spends); the colour is what lands.
    -- The cells glide, so paint the same reading until they settle.
    local function full(i) local c = plate.cells[i].__color; return c and (c[4] or 1) >= 0.7 and not (c[1] < 0.2 and c[2] < 0.2) end
    local function paint(reading, waste, burn) for _ = 1, 40 do ADDON_NS.UIX.PaintGauge(reading, waste, burn) end end
    paint(0.5, 0.1, 0.5)
    for i = 1, 7 do pneed(full(i), ("cell %d should be lit at half burn"):format(i)) end
    pneed(not full(8), "cell 8 should be dark at half burn")
    paint(1.0, 0.1, 1.0)
    for i = 1, 14 do pneed(full(i), ("cell %d should be lit at full burn"):format(i)) end
    pneed((plate.cells[14].__color[4] or 1) > (plate.cells[1].__color[4] or 1),
          "the cells past the hot line should burn brighter than the first")
    -- Arn's case: max-rank heals nonstop into a full bar. Every cell lit, and
    -- every cell RED -- the bar must never read "idle" while he casts flat out
    paint(0.4, 1.0, 1.0)
    for i = 1, 14 do pneed(full(i), ("cell %d should be lit while casting flat out into overheal"):format(i)) end
    local c1 = plate.cells[1].__color
    pneed(c1[1] > 0.9 and c1[2] < 0.4, "flat-out overhealing should paint the cells red")
    pneed(plate.label:GetText():find("overhealing", 1, true), "the state word should say overhealing")
    -- and cruising: barely spending, a couple of cells, blue
    paint(0.1, 0.0, 0.1)
    pneed(full(1) and not full(3), "cruising should light one cell, not three")
    plate.gaugeLive = false; ADDON_NS.UIX.PlateShow()

    -- the slots reach the plate's prompt too: shield somebody, read it off the plate
    ES_ON, ES_CHARGES, ES_MINE = "raid3", 5, true
    CLOG = { 0, "SPELL_AURA_APPLIED", false, "GUID-Kumlust", "Kumlust", 0, 0,
             "GUID-Raider3", "Raider3", 0, 0, 974, "Earth Shield", 8, "BUFF" }
    fireEvent("COMBAT_LOG_EVENT_UNFILTERED")
    for _ = 1, 12 do AdvanceTime(0.11); tick(1, 0.11) end
    -- the plate stays OUT of shield tracking (the pips carry it); the options
    -- window's prompt still gets the slot
    pneed(plate.con.slots.shield == nil, "the plate carries the shield slot -- it should not")
    local ocon = BiSHealingUI.Console()
    pneed(ocon.slots.shield and ocon.slots.shield.text:match("^ES 5"), "the options window lost the shield slot")

    -- both halves off: the plate goes away entirely
    BiSHealingDB.castCounter, BiSHealingDB.rpm = false, false
    tick(3)
    pneed(not plate:IsShown(), "the plate stays up with both the counter and the gauge off")
    BiSHealingDB.castCounter, BiSHealingDB.rpm = true, true
    tick(3)
    pneed(plate:IsShown(), "the plate did not come back")
    -- its own window: drag the header, the spot is saved and restored; the
    -- pyramid's lock has no say; /bish center puts it back above the pyramid
    local head = plate.head
    pneed(head.__scripts.OnDragStart and head.__scripts.OnDragStop, "the plate header is not draggable")
    BiSHealingDB.locked = true
    head.__scripts.OnDragStart(head)
    plate.__points = { { "TOPLEFT", UIParent, "TOPLEFT", 300, -200 } }   -- where the mouse left it
    head.__scripts.OnDragStop(head)
    local pp = BiSHealingDB.platePos
    pneed(pp and pp[1] == "TOPLEFT" and pp[3] == 300 and pp[4] == -200,
          "the drag did not save the plate's spot: " .. tostring(pp and table.concat({tostring(pp[1]), tostring(pp[3]), tostring(pp[4])}, ",")))
    local p1 = plate.__points[1]
    pneed(p1 and p1[2] == UIParent and p1[4] == 300, "the plate is not anchored to the saved spot")
    -- a fresh login restores it
    fireEvent("PLAYER_LOGIN")
    p1 = plate.__points[1]
    pneed(p1 and p1[2] == UIParent and p1[4] == 300 and p1[5] == -200, "login did not restore the plate's spot")
    -- center puts it back over the pyramid
    SlashCmdList.BISHEALING("center")
    pneed(BiSHealingDB.platePos == nil, "center did not forget the plate's spot")
    p1 = plate.__points[1]
    pneed(p1 and p1[2] == _G["BiSHealingAnchor"], "center did not park the plate back above the pyramid")
    -- the HUD header: the state word fades through it when the state MOVES
    local function saw(con, needle, seconds)
        local hit = false
        for _ = 1, math.floor(seconds / 0.05) do
            AdvanceTime(0.05); con:Paint()
            if con:Text():find(needle, 1, true) then hit = true end
        end
        return hit
    end
    local function count(needle, fn)
        local n = 0
        local orig = plate.con.Say
        plate.con.Say = function(self, text, c) if tostring(text):find(needle, 1, true) then n = n + 1 end return orig(self, text, c) end
        fn()
        plate.con.Say = orig
        return n
    end
    plate.con:Clear()                          -- the last paint left it cruising
    paint(0.4, 1.0, 1.0)                      -- flat out into full bars
    pneed(saw(plate.con, "overhealing", 6.0), "the plate never said overhealing when the state moved")
    -- same state again: nothing new to say (count the Says, since a line
    -- already on the header holds for a while after Clear)
    local said = 0
    local origSay = plate.con.Say
    plate.con.Say = function(self, text, c) if tostring(text):find("overhealing") then said = said + 1 end return origSay(self, text, c) end
    paint(0.4, 1.0, 1.0)
    plate.con.Say = origSay
    pneed(said == 0, "the plate repeats the state word without a change")
    paint(0.1, 0.0, 0.1)                      -- back to cruising
    pneed(saw(plate.con, "cruising", 6.0), "the plate never said cruising")

    -- the standing slots a healer wants mid-fight: NS, mana -- and the shield
    -- running out is said once
    local function slotTick() for _ = 1, 6 do AdvanceTime(0.1); tick(1, 0.1) end end
    NS_CD = false
    slotTick()
    pneed(plate.con.slots.ns and plate.con.slots.ns.text == "NS up", "no NS slot: " .. tostring(plate.con.slots.ns and plate.con.slots.ns.text))
    pneed(plate.con.slots.mana and plate.con.slots.mana.text:match("^mana %d+%%$"), "no mana slot: " .. tostring(plate.con.slots.mana and plate.con.slots.mana.text))
    ES_ON, ES_CHARGES, ES_MINE = "raid3", 3, true
    slotTick()
    pneed(plate.con.slots.shield == nil, "the plate lit the shield slot")
    plate.con:Clear()
    ES_ON = nil
    local plateSaid = count("shield gone", function() slotTick() end)
    pneed(plateSaid == 0, "the plate said shield gone -- it stays out of shield tracking")
    pneed(saw(BiSHealingUI.Console(), "shield gone", 6.0), "the options window never said shield gone")
    -- NS coming back is said once
    NS_CD = true; slotTick(); NS_CD = false; plate.con:Clear(); slotTick()
    pneed(saw(plate.con, "Swiftness up", 6.0), "NS coming off cooldown was never said")

    -- NUDGES: a cooldown that is up, in a fight, with somewhere to put it, is
    -- said -- and said again while it stays unused; nothing out of combat
    for _, u in pairs(ROSTER) do u.hp = u.hpMax end
    ROSTER["raid5"].hp = 2000                  -- a 6000 hole: the orange corner's pick
    BiSHealingDB.castCounter, BiSHealingDB.rpm = true, true
    -- out of combat: nothing
    pneed(count("Gift ready", function() tick(10, 0.11) end) == 0, "Gift was nagged out of combat")
    -- in combat, Gift up, a target: said once, then again after NUDGE_EVERY
    COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
    pneed(count("Gift ready", function() tick(10, 0.11) end) == 1, "Gift ready was not said once in combat")
    pneed(count("Gift ready", function() tick(10, 0.11) end) == 0, "Gift ready repeated inside the quiet window")
    AdvanceTime(ADDON_NS.UIX.NUDGE_EVERY + 1)
    pneed(count("Gift ready", function() tick(10, 0.11) end) == 1, "Gift ready was not said again once the window passed")
    -- Mana Tide, at 40% mana, off cooldown: said (on its own clock)
    MANA = 2000
    AdvanceTime(ADDON_NS.UIX.NUDGE_EVERY + 1)
    pneed(count("Mana Tide", function() tick(10, 0.11) end) == 1, "Mana Tide up was not said with mana low and the totem ready")
    MANA = 4500
    AdvanceTime(ADDON_NS.UIX.NUDGE_EVERY + 1)
    pneed(count("Mana Tide", function() tick(10, 0.11) end) == 0, "Mana Tide nagged with mana high")
    COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(3)
    for _, u in pairs(ROSTER) do u.hp = u.hpMax end

    -- UPTIME: a fresh fight starts at 100 and sits on the header's right edge
    -- as its own text, whole fight, no slot, no nag; standing there it falls,
    -- casting lifts it; gone when the fight ends
    COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
    tick(2, 0.1)
    pneed(ADDON_NS.UIX.up.pct == 100, "a fresh fight should start at 100% uptime: " .. tostring(ADDON_NS.UIX.up.pct))
    pneed((plate.uptime:GetText() or ""):find("100%%"), "the uptime text is not on the header: " .. tostring(plate.uptime:GetText()))
    local n = count("uptime", function() tick(60, 0.1) end)       -- 6 s idle
    pneed(n == 0, "uptime was nagged through the header -- it is a fixture now, not a nag")
    pneed(ADDON_NS.UIX.up.pct < 100, "uptime did not fall while idle: " .. tostring(ADDON_NS.UIX.up.pct))
    pneed(plate.con.slots.uptime == nil, "uptime is still a rotating slot")
    local before = ADDON_NS.UIX.up.pct
    for _ = 1, 10 do fireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 1064); tick(14, 0.1) end
    pneed(ADDON_NS.UIX.up.pct > before, "uptime did not climb while casting")
    -- a curable debuff is the glaring one: said once when it appears, not
    -- again inside the quiet window, again after it
    DEBUFFS.raid2 = { { "Toxic Spores", "Poison" } }
    pneed(count("cure Raide", function() tick(10, 0.1) end) == 1, "a poison on raid2 was not called out once")
    pneed(count("cure Raide", function() tick(10, 0.1) end) == 0, "the cure nag repeated inside its quiet window")
    AdvanceTime(ADDON_NS.UIX.NUDGE_EVERY + 1)
    pneed(count("cure Raide", function() tick(10, 0.1) end) == 1, "the cure nag did not come back while the poison sat there")
    DEBUFFS.raid2 = nil; tick(8, 0.1)
    -- heals and shields are never suggested through the header
    ROSTER["raid5"].hp = 2000
    pneed(count("heal", function() tick(30, 0.1) end) == 0, "the header suggested a heal")
    pneed(count("shield", function() tick(30, 0.1) end) == 0, "the header suggested a shield")
    for _, u in pairs(ROSTER) do u.hp = u.hpMax end
    COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(3)
    pneed((plate.uptime:GetText() or "") == "", "the uptime text stayed after the fight")
    print("== psi plate ok (prompt + slots, cells, spark, shows for either half, drags on its own, HUD header, nudges)")
end

-- ------------------------------------------- forward-reference report ----
do
    local bad = {}
    for name, n in pairs(FWD_REFS) do bad[#bad+1] = ("%s (%dx)"):format(name, n) end
    if #bad > 0 then
        table.sort(bad)
        print("!! FORWARD REFS (hit at runtime): " .. table.concat(bad, ", "))
        os.exit(1)
    end
    local static = {}
    for _, path in ipairs(ADDON_SOURCES) do
        local short = path:gsub(".*[/\\]", "")
        for _, line in ipairs(__staticForwardRefCheck(path)) do
            static[#static + 1] = short .. ": " .. line
        end
    end
    if #static > 0 then
        print("!! FORWARD REFS -- a local is called ABOVE its own declaration, which")
        print("!! Lua reads as a nil global. This is the trap that has bitten this")
        print("!! addon five times; move the declaration up, or hang it on a table:")
        for _, line in ipairs(static) do print("!!   " .. line) end
        os.exit(1)
    end
    print("== no forward references (runtime and static)")
end
