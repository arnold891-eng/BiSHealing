-- BiSHealing -- headless stress suite (house shape: dev/stress.lua)
--
--     cd BiSHealing && lua5.1 dev/stress.lua
--
-- Every toggle both ways, a full fight of combat log, demo mode in and out of
-- combat, the lockdown paths, and the wheel binds under all of it. Where
-- dev/tests.lua asserts behaviour, this one asserts nothing falls over.
--
-- Lived at "Claude outputs/bishharnessstress.lua" until 9 Sep 2026.

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
        __color = nil, __drawLayer = nil, __attrs = {}, __scripts = {},
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
    function r:SetFont() end
    function r:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "" end
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
    function r:RegisterEvent() end
    function r:UnregisterEvent() end
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
    OVERRIDES[key] = { button = btnName, click = mouseBtn }
end
function ClearOverrideBindings() OVERRIDES = {} end
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
for _, k in ipairs({ "COMBAT", "CLOG", "NS_CD", "NS_UNKNOWN", "OVERRIDES", "ALLLINES", "ALLTEX", "ES_ON", "ES_CHARGES", "ES_MINE", "SENT", "HEAL_SIZE", "TOOLTIP_INDEX", "SPELL_POWER", "TALENTS", "CHATLOG", "ADDON_SENT", "C_ChatInfo", "HC_CB", "SPELLID_NAME", "FWD_REFS", "INCOMING", "CASTEND", "HC_PER" }) do
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
                -- a bare use: not a field (.name / :name) and not a table key
                local at = c:find("[^%w_.:]" .. name .. "%s*[(%[]")
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
local chunk, err = loadfile(arg[1] or "BiSHealing.lua")
if not chunk then error(err) end
local ok, e = pcall(chunk)
if not ok then print("!! LOAD ERROR: " .. tostring(e)); os.exit(1) end
print("== loaded ok")

-- fire PLAYER_LOGIN then the OnUpdate tick, which is what actually drives
-- UpdateBars / corners / rpm / cast counter. Slash commands alone miss these.
local ev
for _, f in ipairs(allFrames) do
    if f.__scripts and f.__scripts.OnEvent then ev = f end
end
local anchorF = _G["BiSHealingAnchor"]

-- payload matters now: CHAT_MSG_ADDON carries prefix/message/channel/sender,
-- and dropping the extra arguments made every comm test silently pass nothing
local function fireEvent(e, ...) if ev then ev.__scripts.OnEvent(ev, e, ...) end end
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

__armLeakCheck()
__armForwardRefCheck(arg[1] or "BiSHealing.lua")
fireEvent("PLAYER_LOGIN")
print("== login ok")
tick(5)
print("== tick ok (live roster)")

-- every slash command
local CMDS = { "", "ranks", "score", "reorder", "lock", "bands", "bind", "inc",
               "bull", "bounce", "es", "rawes", "esplan", "frames", "center",
               "show", "hide", "sim on", "sim off", "demo", "sim 25", "garbage",
               "wheel", "wheel on", "wheel off", "wheel strict", "wheel on",
               "wheel strict", "wheel nonsense" }
for _, c in ipairs(CMDS) do
    local ok, err = pcall(SlashCmdList.BISHEALING, c)
    if not ok then print(("!! SLASH ERROR (%s): %s"):format(c, tostring(err))); os.exit(1) end
end
print("== slash ok")
tick(20)
print("== tick ok (demo mode)")
if #LEAKED > 0 then
    print("!! GLOBAL LEAKS: " .. table.concat(LEAKED, ", "))
else
    print("== no global leaks")
end
SlashCmdList.BISHEALING("show")
local function clog(...) CLOG = {...}; fireEvent("COMBAT_LOG_EVENT_UNFILTERED") end
local P = "GUID-Kumlust"

COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
for round = 1, 40 do
    AdvanceTime(0.4)
    for i = 2, 10 do
        local g = "GUID-Raider" .. i
        clog(0,"SWING_DAMAGE",false,"GUID-Boss","Boss",0,0,g,"Raider"..i,0,0,
             300 + i*20, nil,nil,nil,nil,nil,nil)
        clog(0,"SPELL_DAMAGE",false,"GUID-Boss","Boss",0,0,g,"Raider"..i,0,0,
             111,"Cleave",1, 500, nil,nil,nil)
        clog(0,"SPELL_DAMAGE",false,g,"Raider"..i,0,0,"GUID-Boss","Boss",0,0,
             222,"Sunder",1, 800, nil,nil,nil)
    end
    -- my chain heal: 3 bounces, all crit
    clog(0,"SPELL_HEAL",false,P,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
         1064,"Chain Heal",8, 1500, 200, 0, true)
    clog(0,"SPELL_HEAL",false,P,"Kumlust",0,0,"GUID-Raider3","Raider3",0,0,
         1064,"Chain Heal",8, 750, 100, 0, true)
    clog(0,"SPELL_HEAL",false,P,"Kumlust",0,0,"GUID-Raider4","Raider4",0,0,
         1064,"Chain Heal",8, 375, 300, 0, true)
    -- earth shield lifecycle, mine and the other shaman's
    clog(0,"SPELL_AURA_APPLIED",false,P,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
         974,"Earth Shield",8)
    clog(0,"SPELL_HEAL",false,"GUID-Raider2","Raider2",0,0,"GUID-Raider2","Raider2",0,0,
         974,"Earth Shield",8, 400, 50, 0, false)
    clog(0,"SPELL_AURA_REMOVED_DOSE",false,P,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,
         974,"Earth Shield",8)
    clog(0,"SPELL_AURA_APPLIED",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider5","Raider5",0,0,
         974,"Earth Shield",8)
    clog(0,"SPELL_HEAL",false,"GUID-Raider5","Raider5",0,0,"GUID-Raider5","Raider5",0,0,
         974,"Earth Shield",8, 350, 0, 0, false)
    clog(0,"SPELL_AURA_REMOVED_DOSE",false,"GUID-Raider9","Raider9",0,0,"GUID-Raider5","Raider5",0,0,
         974,"Earth Shield",8)
    clog(0,"ENVIRONMENTAL_DAMAGE",false,"","",0,0,"GUID-Raider6","Raider6",0,0,"FALLING",120)
    tick(3, 0.11)
end
clog(0,"SPELL_AURA_REMOVED",false,P,"Kumlust",0,0,"GUID-Raider2","Raider2",0,0,974,"Earth Shield",8)
print("== combat log ok")
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED")
print("== endfight ok")
tick(10)
for _, c in ipairs({"score","es","esplan","bull","bands","inc","rawes","bounce"}) do
    local ok, err = pcall(SlashCmdList.BISHEALING, c)
    if not ok then print("!! SLASH " .. c .. ": " .. tostring(err)); os.exit(1) end
end
print("== post-fight diagnostics ok")

-- every toggle OFF, then every toggle ON, ticking both ways
local keys = {"shown","corners","pulse","incomingFill","castCounter","bounceLines",
              "goldChains","celebrate","trinkets","giftBadge","rpm","pets",
              "bullseye","esBadge","esReticle","wheel","nsPip"}
for _, v in ipairs({false, true}) do
    for _, k in ipairs(keys) do BiSHealingDB[k] = v end
    SlashCmdList.BISHEALING("reorder"); tick(15)
    SlashCmdList.BISHEALING("sim on"); tick(120)   -- full demo cycle
    SlashCmdList.BISHEALING("sim off"); tick(5)
    print(("== all toggles %s: ok"):format(tostring(v)))
end
-- combat lockdown: reorder must queue, not crash
COMBAT = true
SlashCmdList.BISHEALING("reorder"); SlashCmdList.BISHEALING("sim on")
fireEvent("GROUP_ROSTER_UPDATE"); tick(10)
tick(150)                       -- demo must survive a full cycle IN COMBAT
print("== demo in combat ok")
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(10)
SlashCmdList.BISHEALING("sim off"); tick(5)
print("== lockdown path ok")
-- reset while frames live
SlashCmdList.BISHEALING("reset"); tick(10)
print("== reset ok")

-- ------------------------------------------------- wheel bind stress --
-- Every combination that changes what the wheel casts, plus both Nature's
-- Swiftness cooldown states, plus the case where he never trained it.
local function wneed(cond, what)
    if not cond then print("!! WHEEL: " .. what); os.exit(1) end
end
local wb = _G["BiSHealingWheel"]
wneed(wb, "wheel button never created")

-- strict mode: two-press castsequence, and it must still be mouseover-gated
BiSHealingDB.wheel, BiSHealingDB.wheelStrict = true, true
SlashCmdList.BISHEALING("reorder"); tick(5)
local m2 = wb:GetAttribute("*macrotext2")
wneed(m2:match("castsequence"), "strict mode did not produce a castsequence")
wneed(m2:match("stopmacro"), "strict mode lost the mouseover gate")

-- combo mode: one press, NS then the heal, no sequence state to desync
BiSHealingDB.wheelStrict = false
SlashCmdList.BISHEALING("reorder"); tick(5)
m2 = wb:GetAttribute("*macrotext2")
wneed(not m2:match("castsequence"), "combo mode still using a castsequence")
wneed(m2:match("Nature's Swiftness"), "combo mode lost Nature's Swiftness")

-- wheel off: bindings must be released, not left pointing at a dead button
BiSHealingDB.wheel = false
SlashCmdList.BISHEALING("reorder"); tick(5)
wneed(next(OVERRIDES) == nil, "wheel off left bindings behind")
wneed(wb:GetAttribute("*type3") == nil and wb:GetAttribute("*type4") == nil,
      "wheel off left the scroll-down clicks set")
wneed(wb:GetAttribute("*type1") == nil, "wheel off left the click type set")
BiSHealingDB.wheel = true
SlashCmdList.BISHEALING("reorder"); tick(5)
wneed(OVERRIDES["MOUSEWHEELUP"], "wheel back on did not rebind")

-- trinkets off: no shifted direction may still be popping slots
BiSHealingDB.trinkets = false
SlashCmdList.BISHEALING("reorder"); tick(5)
for _, k in ipairs({ "*macrotext2", "*macrotext4" }) do
    local m = wb:GetAttribute(k)
    wneed(not m:match("/use 13"), k .. " still fires trinkets with the setting off")
end
BiSHealingDB.trinkets = true
SlashCmdList.BISHEALING("reorder"); tick(5)
for _, k in ipairs({ "*macrotext2", "*macrotext4" }) do
    wneed(wb:GetAttribute(k):match("/use 13"), k .. " lost its trinkets")
end
-- and no UNshifted direction may ever fire them
for _, k in ipairs({ "*macrotext1", "*macrotext3" }) do
    wneed(not wb:GetAttribute(k):match("/use 1"), k .. " burns trinkets unshifted")
end

-- both NS cooldown states drive the pip painter
for _, cd in ipairs({ true, false }) do
    NS_CD = cd
    tick(20)
end
NS_CD = false

-- shaman without the talent: shift+scroll must fall back to a plain heal
NS_UNKNOWN = true
BiSHealingDB.wheel = true
fireEvent("SPELLS_CHANGED"); tick(30)
SlashCmdList.BISHEALING("rescan"); tick(5)
m2 = wb:GetAttribute("*macrotext2")
wneed(not m2:match("Nature's Swiftness"), "untrained NS still bound: " .. m2)
wneed(m2:match("Healing Wave"), "untrained NS lost the heal entirely")
NS_UNKNOWN = nil
SlashCmdList.BISHEALING("rescan"); tick(5)

-- toggling in combat must queue, never taint or error
COMBAT = true; fireEvent("PLAYER_REGEN_DISABLED")
SlashCmdList.BISHEALING("wheel off"); tick(10)
wneed(OVERRIDES["MOUSEWHEELUP"], "wheel unbound DURING combat -- that is blocked")
SlashCmdList.BISHEALING("wheel on")
COMBAT = false; fireEvent("PLAYER_REGEN_ENABLED"); tick(10)
SlashCmdList.BISHEALING("bind"); tick(5)
print("== wheel stress ok")

if #LEAKED > 0 then print("!! GLOBAL LEAKS: " .. table.concat(LEAKED, ", ")); os.exit(1) end
print("== ALL CLEAN")

-- ------------------------------------------- forward-reference report ----
do
    local bad = {}
    for name, n in pairs(FWD_REFS) do bad[#bad+1] = ("%s (%dx)"):format(name, n) end
    if #bad > 0 then
        table.sort(bad)
        print("!! FORWARD REFS (hit at runtime): " .. table.concat(bad, ", "))
        os.exit(1)
    end
    local static = __staticForwardRefCheck(arg[1] or "BiSHealing.lua")
    if #static > 0 then
        print("!! FORWARD REFS -- a local is called ABOVE its own declaration, which")
        print("!! Lua reads as a nil global. This is the trap that has bitten this")
        print("!! addon five times; move the declaration up, or hang it on a table:")
        for _, line in ipairs(static) do print("!!   " .. line) end
        os.exit(1)
    end
    print("== no forward references (runtime and static)")
end
