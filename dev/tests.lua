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

local function newFrame(kind, name, parent)
    -- SHOWN, like the client's. A frame you create is visible until you hide it, and a mock that
    -- starts everything hidden turns "I never hid this" into a passing test - which is exactly
    -- how the mouse window shipped needing two clicks to open.
    local f = { __kind = kind, __name = name, __attrs = {}, __scripts = {}, __shown = true,
                __alpha = 1, points = {}, __parent = parent }
    -- SCALE IS INHERITED, as in the client: a child of a frame at 1.4 is itself at 1.4, so an
    -- offset written in its own units covers 1.4 times the screen it used to. The mock had no
    -- parents and no effective scale at all, which is how the target cell's free position could
    -- be stored in the wrong units and no test noticed (Arn, 23 Sep: "when i increased the scale
    -- size ... the target frames moved up and to the right").
    function f:GetParent() return self.__parent end
    function f:GetEffectiveScale()
        local s = self.__scale or 1
        local p = self.__parent
        while p do
            s = s * (p.__scale or 1)
            p = p.__parent
        end
        return s
    end
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
    function f:SetAlpha(a)
        -- A WIDGET MAY REFUSE A SECRET. Which ones accept them is not in any census, so the mock
        -- can be told to say no - and the addon has to leave the cell readable when it does,
        -- rather than throwing in the middle of a pull.
        if STATE.alphaRefusesSecret and getmetatable(a) == secretMeta then
            error("SetAlpha: a secret alpha is refused by this client", 2)
        end
        self.__alpha = a
    end
    function f:GetAlpha() return self.__alpha end
    function f:SetFrameStrata(v) self.__strata = v end
    function f:SetScale(v) self.__scale = v end
    function f:GetScale() return self.__scale or 1 end
    function f:SetSize(w, h) self.__w, self.__h = w, h end
    -- a width on its own is a size too. It was an auto no-op, so "how wide did it draw that" had
    -- no answer at all - which is how a bar could be drawn at any width and pass (23 Sep).
    function f:SetWidth(w) self.__w = w end
    function f:SetHeight(h) self.__h = h end
    function f:GetWidth() return self.__w end
    function f:GetHeight() return self.__h end
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
            -- A TEXTURE REMEMBERS WHAT COLOUR IT WAS PAINTED. This was a no-op, so "what
            -- colour is that cell's ring" had no answer at all - the same shape of lie as the
            -- font string that accepted a colour with no green in it (26 Sep).
            SetColorTexture = function(t, r, g, b, a)
                if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                    error("bad argument to SetColorTexture: needs r, g, b numbers", 2)
                end
                t.__color = { r, g, b, a }
            end,
            SetWidth  = function(t, w) t.__w = w end,
            SetHeight = function(t, h) t.__h = h end,
            SetSize   = function(t, w, h) t.__w, t.__h = w, h end,
            GetWidth  = function(t) return t.__w end,
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
            -- THE FORMAT SETTER, which is how a secret number reaches the screen without anybody
            -- reading it: the client does the formatting. EllesmereUI's healer mana is one line of
            -- exactly this, and it is the whole reason "nobody can show another player's mana"
            -- turned out to be wrong. It records what it was GIVEN, including a secret, so a test
            -- can tell "drew the value" from "drew nothing".
            SetFormattedText = function(self2, fmt, v)
                if STATE.formatRefusesSecret and getmetatable(v) == secretMeta then
                    error("SetFormattedText: this client refuses a secret here", 2)
                end
                self2.__formatted = { fmt, v }
                self2.__text = getmetatable(v) == secretMeta and "(secret)" or tostring(v)
            end,
            GetText = function(self2) return self2.__text end,
            -- THE CLIENT REFUSES A COLOUR WITH A HOLE IN IT: "bad argument #1 to 'SetTextColor'
            -- (Usage: self:SetTextColor(color [, a]))". This used to record whatever it was
            -- handed, so `local r, g, b = (T.rgb(name))` - brackets that keep only the FIRST
            -- return value - painted r with g and b nil, passed the suite, and threw five times
            -- on one click of the minimap button (26 Sep). A widget that takes anything cannot
            -- tell you that you gave it nothing.
            SetTextColor = function(self2, r, g, b, a)
                if type(r) == "table" then self2.__color = r return end      -- the color-object form
                if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
                    error("bad argument #1 to 'SetTextColor' (Usage: self:SetTextColor(color [, a]))", 2)
                end
                self2.__color = { r, g, b, a }
            end,
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
    -- AN EDIT BOX HOLDS WHAT WAS TYPED IN IT. Every method not written down here answers nil,
    -- which for a text field is the kindest lie there is: GetText() would come back nil, the addon
    -- would read it as "nothing typed", and the suite would call that a pass while the player's
    -- 567458 sat in the box in front of them. The client's own box answers "" when it is empty,
    -- never nil, and takes digits only once SetNumeric is on - so this one does the same.
    if kind == "EditBox" then
        f.__text = ""
        function f:SetText(t)
            t = tostring(t or "")
            if self.__numeric then t = t:gsub("%D", "") end
            self.__text = t
        end
        function f:GetText() return self.__text or "" end
        function f:GetNumber() return tonumber(self.__text) or 0 end
        function f:SetNumeric(on) self.__numeric = on and true or false end
        function f:SetAutoFocus(on) self.__autofocus = on and true or false end
        function f:SetMaxLetters(n) self.__max = n end
        function f:SetFocus() self.__focus = true end
        function f:ClearFocus() self.__focus = false end
        -- what a player actually does: type, then press Enter. The client fires the script itself.
        function f:__type(t)
            self:SetText(t)
            local fn = self.__scripts.OnEnterPressed
            if fn then fn(self) end
        end
    end
    frames[#frames + 1] = f
    return autoMethods(f)
end

_G.CreateFrame = function(kind, name, parent) return newFrame(kind, name, parent) end
_G.UIParent = newFrame("Frame")
_G.InCombatLockdown = function() return STATE.inCombat end
-- the shift key, held or not, as the client answers it
_G.IsShiftKeyDown = function() return STATE.shift and true or false end
-- A SOUND THAT DOES NOT EXIST DOES NOT PLAY. The client answers PlaySoundFile with false for a
-- file id it has not got, and a mock that says "played it" for every number turns "did that id
-- work?" into a question nobody can ask - which is the whole reason the drawer has a `hear`
-- button. STATE.sounds is the client's sound folder; STATE.played is what came out of it.
STATE.sounds = { [567458] = true, [567474] = true }      -- the two Arn listened to, 23 Sep
STATE.played = {}
_G.PlaySoundFile = function(file, channel)
    if type(file) ~= "number" or not STATE.sounds[file] then return false end
    STATE.played[#STATE.played + 1] = { file = file, channel = channel }
    return true, #STATE.played
end
-- A CLOCK THAT MOVES, like the client's. There was none at all, so GetTime was nil everywhere and
-- anything cached "for this frame" was cached for the whole suite - kinder than the client, where
-- the number changes sixty times a second. TICK() is a frame going by.
local CLOCK = 1000
_G.GetTime = function() return CLOCK end
local function TICK(seconds) CLOCK = CLOCK + (seconds or 0.1) return CLOCK end
_G.UnitExists = function(u) return STATE.units[u] and true or false end
_G.IsInRaid = function() return false end
_G.UnitName = function(u) return "Name-" .. tostring(u) end
_G.UnitClass = function()
    if STATE.classSecret then return secret(), secret() end
    return "Shaman", "SHAMAN"
end
-- CAN I ATTACK THIS? The target cell holds whatever you clicked, which on a hunter is usually a
-- mob - and in combat the answer is a secret like everything else about somebody else.
STATE.hostile = {}
STATE.hostileSecret = false
_G.UnitCanAttack = function(_, u)
    if STATE.hostileSecret then return secret() end
    return STATE.hostile[u] and true or false
end
-- IS THIS PERSON EVEN HERE? EllesmereUI's raid frames say of this pair: "UnitIsDeadOrGhost /
-- UnitIsConnected return clean booleans for group units (only UnitIsAFK can be secret)" - which is
-- a measurement, so the mock answers plainly unless a test asks it not to.
STATE.offline = {}
_G.UnitIsConnected = function(u)
    if STATE.connectedSecret then return secret() end
    return not STATE.offline[u]
end
-- AWAY FROM THE KEYBOARD, which EllesmereUI's frames also show. Their note is what sets this one
-- apart from dead and offline: "only UnitIsAFK can be secret" - so the mock can be told to hide it.
STATE.afk = {}
_G.UnitIsAFK = function(u)
    if STATE.afkSecret then return secret() end
    return STATE.afk[u] and true or false
end
_G.UnitIsDeadOrGhost = function(u)
    if STATE.deadSecret then return secret() end       -- a secret BOOLEAN, in combat
    return STATE.dead[u] and true or false
end
_G.UnitHealth = function() return secret() end
_G.UnitHealthMax = function(u) if u == "player" then return 297 end return secret() end
-- IN COMBAT THE ANSWER IS A SECRET, like everything else about somebody else. It used to answer
-- plainly always, so "the dimming works" was only ever proved for the half of the time it is not
-- needed - and the pcall round it swallowed the refusal in the other half without a word.
-- WHAT IT WAS ASKED WITH, recorded. EllesmereUI passes spell IDS to this call and their notes
-- say a spell it cannot answer for leaves everyone at full alpha - so "did we ask with the id or
-- the name" is the question, and a mock that ignores its first argument cannot be asked it.
STATE.rangeAsked = {}
STATE.rangeNil = false          -- the client declining to answer, which is a real shape
_G.IsSpellInRange = function(ident, u)
    STATE.rangeAsked[#STATE.rangeAsked + 1] = ident
    if STATE.rangeSecret then return secret() end
    if STATE.rangeNil then return nil end
    return STATE.range[u] == 0 and 0 or 1
end
-- THE OTHER QUESTION: about the unit rather than the spell. On this client it is the secret
-- boolean, which is the whole reason the grid can use it at all now.
STATE.unitRange = {}
_G.UnitInRange = function(u)
    if STATE.unitRangeSecret then return secret() end
    if STATE.unitRange[u] == nil then return nil end
    return STATE.unitRange[u] and true or false
end
-- the client's ternary: it picks one of two values from a boolean nobody else may test
_G.C_CurveUtil = _G.C_CurveUtil or {}
_G.C_CurveUtil.EvaluateColorValueFromBoolean = function(b, whenTrue, whenFalse)
    if getmetatable(b) == secretMeta then
        -- a secret in, a secret out: the client knows which one it picked and we do not
        if STATE.curveRefuses then error("the curve refuses this value", 2) end
        return secret()
    end
    if type(b) ~= "boolean" then error("EvaluateColorValueFromBoolean needs a boolean", 2) end
    return b and whenTrue or whenFalse
end
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
        local c = newFrame(kind, nil, parent)
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

-- ANOTHER PLAYER'S MANA, AS A PERCENTAGE THE CLIENT WORKS OUT. UnitPowerPercent is what
-- EllesmereUI's healer mana is built on, with their own note beside it: "which can be secret in
-- combat: it only ever reaches a format setter". So this answers a secret in combat, and a plain
-- number out of it - and either way nothing may read it.
STATE.powerSecret = false
_G.CurveConstants = { ScaleTo100 = "scale100" }
_G.UnitPowerPercent = function(unit, powerType, _, scale)
    if STATE.powerNoCall then error("no such call on this client", 2) end
    if STATE.powerSecret then return secret() end
    return (STATE.power and STATE.power[unit]) or 100
end
STATE.power = {}

-- MACROS, WHICH ARE THE ONE THING THIS CLIENT GIVES BACK. They live on the server, so they
-- survive the restart that empties every SavedVariables file. This is the store, and it behaves
-- like the client's: CreateMacro appends, EditMacro needs a real index, GetNumMacros counts the
-- two kinds separately, and a name that is not there answers 0 rather than nil.
--
-- TWO TABS, BY INDEX, AND A STRICT FLAG. Arn, 22 Sep 2026, a screenshot of the macro window: the
-- BiSHealing macro sat in GENERAL Macros, shared by every character on the account, holding only
-- a grid position. CreateMacro had been handed `1` for "this character only" since the day
-- Keep.lua was written, and the client put it in the shared tab. This store used to take any
-- true-ish value as per-character and kept both tabs in one list, so the suite passed "this
-- character's own - not a general slot" over exactly that bug. Now General is 1..120 and the
-- character's tab 121..138, as in the client, and only a real `true` makes a character macro.
local MACROS = {}                -- index -> { name, icon, body }; General 1..120, character 121+
_G.MAX_ACCOUNT_MACROS, _G.MAX_CHARACTER_MACROS = 120, 18
local function macroIndices()
    local ks = {}
    for i in pairs(MACROS) do ks[#ks + 1] = i end
    table.sort(ks)
    return ks
end
_G.GetMacroIndexByName = function(n)
    for _, i in ipairs(macroIndices()) do if MACROS[i].name == n then return i end end
    return 0
end
_G.GetMacroInfo = function(i)
    local m = MACROS[i]
    if not m then return nil end
    return m.name, m.icon, m.body
end
_G.GetMacroBody = function(i) return MACROS[i] and MACROS[i].body or nil end
_G.GetNumMacros = function()
    local g, p = 0, 0
    for i in pairs(MACROS) do if i > 120 then p = p + 1 else g = g + 1 end end
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
    local first, last = 1, 120
    if perChar == true then first, last = 121, 138 end
    for i = first, last do
        if not MACROS[i] then
            MACROS[i] = { name = n, icon = icon, body = asTheClientStoresIt(body) }
            return i
        end
    end
    error("macro tab is full", 2)
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
-- ONE LINE IN THE CHAT FRAME, AND IT FORMATS. NS.Print took a single argument and dropped the
-- rest, so every call that passed values printed its own punctuation: "asking: %s". /bish range
-- did that for the two days it existed, in front of Arn, while he was using it to find out why
-- nothing was dimming (30 Sep). The suite could not see it because its own stub for Print had the
-- same single argument.
do
    local heard = {}
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    NS.Print("asking: %s", "C_Spell.IsSpellInRange")
    ok(heard[1] and heard[1]:find("C_Spell.IsSpellInRange", 1, true)
       and not heard[1]:find("%%s"),
       "a value handed to Print lands in the line, not a literal %s", tostring(heard[1]))
    NS.Print("%d of %d", 3, 7)
    ok(heard[2] and heard[2]:find("3 of 7", 1, true), "numbers too", tostring(heard[2]))
    -- a line with a percent sign and nothing to put in it is left exactly as it is
    NS.Print("mana is at 100% now")
    ok(heard[3] and heard[3]:find("100% now", 1, true),
       "and a bare percent sign in a message is not a format at all", tostring(heard[3]))
    -- a format that does not match its arguments says the message rather than throwing in chat
    ok(pcall(NS.Print, "%d things", "not a number"), "a mismatched format does not throw")
    _G.DEFAULT_CHAT_FRAME = realChat
end

-- THE MACRO LIST ARRIVES. The client sends UPDATE_MACROS once it has the list, at every login;
-- until then Keep writes nothing (the 22 Sep wipe). This is that moment. The before-it case has
-- its own block, "NOTHING IS WRITTEN BEFORE THE LIST IS IN".
NS.FK.MacrosArrived()
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

-- AND IT SAYS SO IN WORDS. Arn, 30 Sep, with EllesmereUI's raid frames on screen: "it shows when
-- they are dead and offline". The word takes the number's place - how much health a corpse is
-- missing is not a question anybody has, and both on one 84 pixel line print through each other.
ok(f.htext.__text == "DEAD", "and the cell says DEAD where the number goes", tostring(f.htext.__text))
STATE.dead.party1 = nil
STATE.offline.party1 = true
FG.Paint(f)
ok(f.htext.__text == "OFFLINE", "someone logged out says OFFLINE", tostring(f.htext.__text))
STATE.dead.party1 = true
FG.Paint(f)
ok(f.htext.__text == "OFFLINE",
   "and offline wins over dead - a corpse that logged out is not coming back to it",
   tostring(f.htext.__text))
STATE.dead.party1, STATE.offline.party1 = nil, nil
FG.Paint(f)
ok(f.htext.__text ~= "DEAD" and f.htext.__text ~= "OFFLINE",
   "and alive and present, the number is back", tostring(f.htext.__text))
-- AND IN THE NUMBER'S COLOUR. The word is grey and the number is red; without putting the colour
-- back, a living raider's missing health stayed grey from the moment they first died.
ok(f.htext.__color and f.htext.__color[1] > 0.9 and f.htext.__color[2] < 0.7,
   "in the number's own colour, not the grey the word was left in",
   f.htext.__color and table.concat(f.htext.__color, ","))

-- AND AFK, which is the only one of the three you can still heal through - so it comes last, and
-- a corpse or an absent player is never called merely away.
STATE.afk.party1 = true
FG.Paint(f)
ok(f.htext.__text == "AFK", "someone at the keyboard's fault says AFK", tostring(f.htext.__text))
STATE.dead.party1 = true
FG.Paint(f)
ok(f.htext.__text == "DEAD", "a dead AFK is dead first", tostring(f.htext.__text))
STATE.offline.party1 = true
FG.Paint(f)
ok(f.htext.__text == "OFFLINE", "and an offline one is offline first", tostring(f.htext.__text))
STATE.dead.party1, STATE.offline.party1 = nil, nil

-- THIS ONE CAN GO SECRET where the other two cannot (their note: "only UnitIsAFK can be secret").
-- When it does the cell shows the number again rather than a word that may be ten minutes old.
STATE.afkSecret = true
FG.Paint(f)
ok(f.htext.__text ~= "AFK", "a hidden AFK is not shown at all", tostring(f.htext.__text))
STATE.afkSecret = false
STATE.afk.party1 = nil

-- A WORD THE CLIENT WILL NOT CONFIRM IS NOT SHOWN. Their note says these two are clean for group
-- units, which is a measurement and not a promise; a secret answer falls back to the number.
STATE.connectedSecret = true
STATE.dead.party1 = true
ok(pcall(FG.Paint, f), "a secret connection answer does not throw")
ok(f.htext.__text == "DEAD", "a secret 'is he here' does not hide a dead man", tostring(f.htext.__text))
STATE.connectedSecret = false
STATE.deadSecret = true
FG.Paint(f)
ok(f.htext.__text ~= "DEAD", "and a secret 'is he dead' says nothing rather than guessing",
   tostring(f.htext.__text))
STATE.deadSecret = false
STATE.dead.party1 = nil

-- RANGE, PLAINLY: out of combat the client answers 1 or 0 and the addon reads it
STATE.range.party1 = 0
FG.Paint(f)
ok(f:GetAlpha() == 0.45, "out of range dims the cell")
ok(FG.rangeSeen == "plain", "read plainly, which is what happens between pulls", FG.rangeSeen)
STATE.range.party1 = nil
FG.Paint(f)
ok(f:GetAlpha() == 1, "back in range, full alpha")

-- THE RANGE SPELL IS WHATEVER IS BOUND, not only left or right click. Arn, 30 Sep, with /bish
-- range finally able to answer him: "range is measured with nothing - bind a spell to left click".
-- His heals are on the wheel and the thumbs; left and right are empty. The dimming had never run
-- for him once, on any character, since the day it was written - and every test of it had put a
-- spell on left click first, which is the one arrangement that hid the bug.
do
    local d = NS.DB()
    local kept = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }          -- a wheel healer, like his
    local name, id = NS.FM.RangeSpell()
    ok(name == "Healing Wave",
       "with nothing on left or right click, the wheel answers for range", tostring(name))

    d.binds = { ["shift-button5"] = "Chain Heal(Rank 1)" }      -- and a thumb, under a modifier
    ok(NS.FM.RangeSpell() == "Chain Heal", "so does a thumb button with a modifier",
       tostring(NS.FM.RangeSpell()))

    -- left click still wins when there IS one: it is what the hand reaches for
    d.binds = { ["left"] = "Lesser Healing Wave(Rank 3)", ["wheelup"] = "Healing Wave(Rank 2)" }
    ok(NS.FM.RangeSpell() == "Lesser Healing Wave", "left click comes first when it is bound",
       tostring(NS.FM.RangeSpell()))

    -- PLAIN RIGHT CLICK BEATS SHIFT-LEFT. The sweep below walks slot by slot and would take
    -- shift-left first, because left comes first in the list - but a bare right click is the one
    -- a hand actually reaches for, and that is what the two named checks are there to prefer.
    d.binds = { ["shift-left"] = "Chain Heal(Rank 1)", ["right"] = "Healing Wave(Rank 2)" }
    ok(NS.FM.RangeSpell() == "Healing Wave",
       "a bare right click is preferred over a modifier on the left",
       tostring(NS.FM.RangeSpell()))

    -- and a mouse with nothing on it at all says so, rather than naming something
    d.binds = {}
    ok(NS.FM.RangeSpell() == nil, "an empty mouse measures nothing", tostring(NS.FM.RangeSpell()))
    d.binds = kept
end

-- ASKED WITH THE SPELL ID, NOT ITS NAME. Arn, 30 Sep: a whole raid at full alpha, nobody dimmed.
-- EllesmereUI passes ids, and their note names the failure exactly - a spell the call cannot
-- answer for "stranded Evoker frames at full alpha", because nil is not "no" and the cell stays
-- bright. The name was all this ever passed.
do
    STATE.rangeAsked = {}
    STATE.range.party1 = 0
    FG.Paint(f)
    local asked = STATE.rangeAsked[1]
    ok(type(asked) == "number", "the range call is asked with a spell id, not a name", tostring(asked))

    -- AND WHEN IT WILL NOT ANSWER, A DIFFERENT QUESTION. nil means "cannot say about this spell";
    -- UnitInRange answers about the unit instead, and this client makes THAT one a secret - which
    -- is what the client's own ternary is for.
    STATE.rangeNil = true
    STATE.unitRange.party1 = false
    f:SetAlpha(1)
    FG.Paint(f)
    ok(f:GetAlpha() == FG.DIM, "a spell it will not range-check falls back to the unit", f:GetAlpha())
    ok(FG.rangeSeen == "unit", "and says which question it ended up asking", tostring(FG.rangeSeen))

    STATE.unitRangeSecret = true
    f:SetAlpha(1)
    ok(pcall(FG.Paint, f), "a secret answer from that one does not throw either")
    ok(getmetatable(f.__alpha) == getmetatable(secret()),
       "it goes through the client's ternary like the other secret did")
    STATE.unitRangeSecret = false

    -- nothing can answer: nobody is dimmed, and the state says so rather than guessing
    STATE.unitRange.party1 = nil
    f:SetAlpha(FG.DIM)
    FG.Paint(f)
    ok(f:GetAlpha() == 1 and FG.rangeSeen == "no answer",
       "with nothing able to answer, nobody is dimmed and /bish range says so",
       tostring(FG.rangeSeen))

    STATE.rangeNil = false
    STATE.range.party1 = nil
    FG.Paint(f)
end

-- AND IN A FIGHT, WHERE THE ANSWER IS A SECRET. This is the half that has never worked: "are
-- they in range" goes secret with everything else, the pcall round it swallowed the refusal, and
-- the cell stayed bright - so the dimming only ever ran when it was least needed. The client's
-- own ternary picks the alpha from a boolean we may not test (ForeverAuras 0.8.6, 28 Sep).
do
    STATE.rangeSecret = true
    f:SetAlpha(1)
    ok(pcall(FG.Paint, f), "a secret range answer does not throw")
    ok(FG.rangeSeen == "secret", "the client is asked to choose the dimming for us", FG.rangeSeen)
    ok(getmetatable(f.__alpha) == getmetatable(secret()),
       "and what it chose goes to the widget unread, like every other secret")

    -- A WIDGET THAT WILL NOT TAKE IT leaves the cell readable, rather than throwing mid-pull.
    -- Which widgets accept a secret is in no census, so this is a real possibility and not a
    -- hypothetical - the grid has met a refusal before, on SetMinMaxValues.
    STATE.alphaRefusesSecret = true
    -- LEFT DIM ON PURPOSE before the paint: a cell that is already bright cannot show whether the
    -- addon put it back, and "the recovery works" was passing on a cell that never moved.
    f:SetAlpha(FG.DIM)
    ok(pcall(FG.Paint, f), "a widget refusing the secret does not throw either")
    ok(f:GetAlpha() == 1, "and the cell is put back to bright rather than left half faded")
    ok(FG.rangeSeen == "alpha refused", "and the reason is recorded for /bish range",
       FG.rangeSeen)
    STATE.alphaRefusesSecret = false

    -- a client with no such call at all: the same, said differently
    local realCurve = _G.C_CurveUtil.EvaluateColorValueFromBoolean
    _G.C_CurveUtil.EvaluateColorValueFromBoolean = nil
    f:SetAlpha(1)
    ok(pcall(FG.Paint, f) and f:GetAlpha() == 1, "and a client without the call leaves it bright")
    ok(FG.rangeSeen == "secret, no curve", "saying which of the two it was", FG.rangeSeen)
    _G.C_CurveUtil.EvaluateColorValueFromBoolean = realCurve

    -- AND A CALL THAT THROWS OUTRIGHT is not "everybody is out of range". The same mistake as the
    -- aura walk on the 28th: a refusal is not an answer, and dimming the whole raid on one is
    -- worse than dimming nobody.
    local realRange = _G.C_Spell and _G.C_Spell.IsSpellInRange
    if _G.C_Spell then _G.C_Spell.IsSpellInRange = function() error("no", 2) end end
    local realBare = _G.IsSpellInRange
    _G.IsSpellInRange = function() error("no", 2) end
    f:SetAlpha(FG.DIM)
    ok(pcall(FG.Paint, f), "a range call that throws does not take the paint with it")
    ok(f:GetAlpha() == 1 and FG.rangeSeen == "refused",
       "and nobody is dimmed on a refusal", tostring(FG.rangeSeen) .. " / " .. tostring(f:GetAlpha()))
    if _G.C_Spell then _G.C_Spell.IsSpellInRange = realRange end
    _G.IsSpellInRange = realBare

    STATE.rangeSecret = false
    FG.Paint(f)
    ok(f:GetAlpha() == 1, "and out of the fight it reads plainly again")
end
ok(pcall(NS.DO.range), "/bish range says what the client answered, without throwing")

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
    local function count() local n = 0 for _ in pairs(MACROS) do n = n + 1 end return n end
    local wrote = FK.Save({ ["wheelup"] = "Healing Wave(Rank 2)" })
    ok(wrote == true and count() == 1, "the first save makes the macro")
    ok(MACROS[121] and MACROS[121].name == FK.MACRO,
       "named, and in THIS CHARACTER's tab - not General, where every character would share it")
    FK.Save({ ["wheelup"] = "Healing Wave(Rank 3)" })
    ok(count() == 1, "the second save edits it rather than making another")
    ok(FK.Load()["wheelup"] == "Healing Wave(Rank 3)", "and reading it back gives the new one")

    -- the player's own macros are none of our business
    MACROS = { [1] = { name = "1 Focus", body = "/focus party1" } }
    FK.Save({ ["left"] = "Healing Wave(Rank 1)" })
    ok(MACROS[1].name == "1 Focus" and MACROS[1].body == "/focus party1",
       "a macro that is not ours is never touched")
    ok(count() == 2 and MACROS[121] and MACROS[121].name == FK.MACRO, "ours is made beside it")

    -- OFF THE SHARED MACRO. Every install before this fix wrote BiSHealing into General (Arn's
    -- screenshot, 22 Sep). Its binds are read once, written into this character's own, and the
    -- shared one is never written again - it may hold another character's mouse.
    MACROS = { [5] = { name = FK.MACRO, body = "BiSH1;Healing Wave#u=1:2\n" } }
    local mine, shared = FK.Find()
    ok(mine == nil and shared == 5, "a shared one in General is found as shared, not as ours")
    local back = FK.Load()
    ok(back and back["wheelup"] == "Healing Wave(Rank 2)" and FK.adopted,
       "its binds are read, once, and marked as carried over")
    FK.Save(back)
    ok(MACROS[121] and MACROS[121].body:find("u=1:2", 1, true), "and written into this character's own")
    FK.Save({ ["left"] = "Chain Heal(Rank 1)" })
    ok(MACROS[5].body == "BiSH1;Healing Wave#u=1:2\n", "the shared one is never written again")
    ok(MACROS[121].body:find("Chain Heal", 1, true), "every later save goes to the character's own")
    local m2 = FK.Find()
    ok(m2 == 121, "and it is the one found from now on, the shared one beside it or not")
    FK.adopted = nil

    -- A CLIENT THAT FILES IT UNDER GENERAL EVEN FOR `true`: said once, and no pile of copies
    local realCreate = _G.CreateMacro
    _G.CreateMacro = function(n, icon, body) return realCreate(n, icon, body, false) end
    MACROS, FK.landedShared = {}, nil
    local okA, whyA = FK.Save({ ["left"] = "Healing Wave(Rank 1)" })
    ok(okA == false and tostring(whyA):find("General"), "it says the client put it in General", tostring(whyA))
    FK.Save({ ["left"] = "Healing Wave(Rank 2)" })
    FK.Save({ ["left"] = "Healing Wave(Rank 3)" })
    ok(count() == 1, "and does not make a second and a third", count())
    _G.CreateMacro, FK.landedShared = realCreate, nil

    -- in combat the client will not make a macro, and pretending otherwise loses the change
    STATE.inCombat = true
    local no, why = FK.Save({ ["left"] = "Healing Wave(Rank 2)" })
    ok(no == false and why == "combat", "in combat it refuses, and says which refusal it is")
    STATE.inCombat = false

    -- and there is no room left
    MACROS = {}
    for i = 121, 138 do MACROS[i] = { name = "mine" .. i, body = "x" } end
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
    local kept = MACROS[121] and MACROS[121].body
    local realInfo, realNum, realIndex = _G.GetMacroInfo, _G.GetNumMacros, _G.GetMacroIndexByName
    _G.GetMacroInfo = function() return nil end              -- an empty list, as it reads at login
    _G.GetNumMacros = function() return 0, 0 end
    _G.GetMacroIndexByName = function() return 0 end
    FK.read = false

    -- NOTHING IS WRITTEN BEFORE THE LIST IS IN. Arn's macro on 22 Sep: "BiSH1#P=5960:5164", a grid
    -- position and no binds - something saved before the list had been read, over the real one.
    local d = NS.DB()
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    ok(FM.Get("", "left") == nil, "with the list not in yet, no class default is seeded")
    ok(FM.Get("", "wheelup") == nil, "and the kept wheel bind is not there yet")
    d.gridPos = { point = "CENTER", rel = "CENTER", x = 40, y = -20 }   -- dragged, before the list
    local early, why = FK.Save(d.binds)                      -- the grid's position, say
    ok(early == false and why == "not read yet", "a save this early is refused, and says why", tostring(why))
    ok(MACROS[121] and MACROS[121].body == kept, "and the real macro is untouched",
       MACROS[121] and MACROS[121].body)

    _G.GetMacroInfo, _G.GetNumMacros, _G.GetMacroIndexByName = realInfo, realNum, realIndex
    ok(fire(FG.events, "UPDATE_MACROS"), "the grid asked for UPDATE_MACROS in the first place")
    ok(FM.Get("", "wheelup") == "Healing Wave(Rank 2)",
       "the kept bind arrives once the list does", tostring(FM.Get("", "wheelup")))
    ok(FM.Get("", "left") == nil, "and no guess of ours is on left click")
    ok(MACROS[121] and MACROS[121].body:find("u=1:2", 1, true)
       and MACROS[121].body:find("P=5040:4980", 1, true),
       "and the waiting save went once the list was in - the drag AND the real binds",
       MACROS[121] and MACROS[121].body)
    d.gridPos = nil

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
    -- THE SHAPE, as Arn set it on 30 Sep looking at a 40-man: "third row max 4 cells, 4th row max
    -- 4 cells, 5th row and below 8 cells half size of 3rd and 4th cell". It was 1,2 then sixes.
    ok(rows(25) == "1,2,4,4,8,6", "a 25-man: a pair, two rows of four, then eights", rows(25))
    ok(rows(40) == "1,2,4,4,8,8,8,5", "and a 40-man fills the eights", rows(40))
    local p = FG.Pyramid(9)
    -- p1 is the apex, p2 and p3 are the pair on row two, p4 begins row three
    ok(p[1].wide and p[2].wide and p[3].wide and not p[4].wide,
       "the apex and the pair are full width; the rows under them are not")

    -- AND EVERY ROW DIVIDES ONE SPAN. Four of row three and eight of row five come to the same
    -- line as the two cells of row two - otherwise the rows drift against each other and the
    -- thing stops being a pyramid.
    local wide = FG.Pyramid(40)
    local function span(row)
        local n, w = 0, 0
        for _, q in ipairs(wide) do if q.row == row then n = n + 1; w = q.w end end
        return n * w + (n - 1) * 3
    end
    ok(span(2) == span(3), "row three is as wide as row two", span(2) .. " vs " .. span(3))
    ok(math.abs(span(5) - span(3)) <= 4, "and so is row five", span(5) .. " vs " .. span(3))
    local mid, tail
    for _, q in ipairs(wide) do
        if q.row == 3 then mid = q.w elseif q.row == 5 then tail = q.w end
    end
    ok(tail * 2 <= mid + 4 and tail * 2 >= mid - 4,
       "and a row-five cell is half a row-three cell, which is what was asked for",
       tail .. " vs " .. mid)

    -- THE ORDER: tanks first, then damage, then the healers, and raid order kept inside each.
    -- Arn, 23 Sep: "tanks dps and healers at the bottom" - in a fight you watch the tank and
    -- whoever is in the fire; the other healers are the glance you take last.
    local raid = { "raid1", "raid2", "raid3", "raid4", "raid5", "raid6", "raid7" }
    STATE.roles = { raid1 = "DAMAGER", raid2 = "HEALER", raid3 = "TANK", raid4 = "DAMAGER",
                    raid5 = "TANK", raid6 = "NONE", raid7 = "HEALER" }
    local by = table.concat(FG.ByRole(raid), " ")
    ok(by == "raid3 raid5 raid1 raid4 raid2 raid7 raid6",
       "tanks, then damage, then healers, then nobody - and nobody reshuffled within a role", by)

    -- AND MELEE ABOVE CASTERS INSIDE A ROLE. Arn, 30 Sep: "favor melee classes up top and caster
    -- at the bottom of pyramid". Melee stand in whatever the boss is doing, so they belong where
    -- the eye already is. The role sort still wins: a caster tank is above a melee dps.
    local realClass = _G.UnitClass
    local CLASS = { raid1 = "MAGE", raid4 = "ROGUE", raid3 = "WARRIOR", raid5 = "PRIEST",
                    raid2 = "PRIEST", raid7 = "DRUID", raid6 = "HUNTER" }
    _G.UnitClass = function(u)
        if STATE.classSecret then return secret(), secret() end
        return CLASS[u] or "Shaman", CLASS[u] or "SHAMAN"
    end
    local mixed = table.concat(FG.ByRole(raid), " ")
    ok(mixed == "raid3 raid5 raid4 raid1 raid7 raid2 raid6",
       "melee first inside each role, and the roles themselves unchanged", mixed)
    ok(mixed:find("raid3 raid5", 1, true) == 1,
       "the tanks keep the top whatever they are", mixed)

    -- A CLASS THE CLIENT HIDES SORTS IN THE MIDDLE, between the melee and the casters - not with
    -- either. With EVERY class hidden they all land together and the order cannot change, so this
    -- needs a mixed group: one rogue, one hidden, one mage, all three in the damage band.
    STATE.roles.raid6 = "DAMAGER"
    _G.UnitClass = function(u)
        if u == "raid6" then return secret(), secret() end        -- this one only
        return CLASS[u] or "Shaman", CLASS[u] or "SHAMAN"
    end
    local middle = table.concat(FG.ByRole(raid), " ")
    ok(middle:find("raid4 raid6 raid1", 1, true) ~= nil,
       "a hidden class sorts between the melee and the casters, not with them", middle)
    -- AND THE OTHER WAY ROUND, because one arrangement can only catch one mistake: with the
    -- hidden one FIRST in raid order, treating it as melee would put it above the rogue.
    _G.UnitClass = function(u)
        if u == "raid1" then return secret(), secret() end
        if u == "raid6" then return "Mage", "MAGE" end
        return CLASS[u] or "Shaman", CLASS[u] or "SHAMAN"
    end
    local firstHidden = table.concat(FG.ByRole(raid), " ")
    ok(firstHidden:find("raid4 raid1 raid6", 1, true) ~= nil,
       "and is not promoted above the melee just because it came first", firstHidden)
    STATE.roles.raid6 = "NONE"

    -- and with the lot hidden, nothing is reordered beyond the roles
    STATE.classSecret = true
    _G.UnitClass = function() return secret(), secret() end
    local hidden = table.concat(FG.ByRole(raid), " ")
    ok(hidden == "raid3 raid5 raid1 raid4 raid2 raid7 raid6",
       "with every class hidden, nothing is reordered beyond the roles", hidden)
    STATE.classSecret = false
    _G.UnitClass = realClass

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

    -- AND ACROSS. A player's request (paszczyszyn, 22 Sep): cells "vertically and horizontally".
    -- The same group, turned: what was a column of names is a row of them. Measured from where
    -- the cells are actually put, not from the setting.
    local function xy(f)
        local p = f.points and f.points[#f.points]
        return p and p[4] or 0, p and p[5] or 0
    end
    d.layout = "columns"
    FG.Layout(FG.anchor)
    local downX, downY = xy(FG.frames[2])
    ok(downX == 0 and downY < 0, "down the screen, the second cell is BELOW the first",
       ("%s,%s"):format(downX, downY))
    local tallW, tallH = FG.anchor.__w, FG.anchor.__h

    d.layout = "rows"
    FG.Layout(FG.anchor)
    local acrossX, acrossY = xy(FG.frames[2])
    ok(acrossY == 0 and acrossX > 0, "across the screen, it is BESIDE it",
       ("%s,%s"):format(acrossX, acrossY))
    ok(FG.frames[1].unit == "player", "with the same order and the same groups")
    -- the grid's own size follows, so the header spans the cells rather than one of them. Not a
    -- swap of width and height: a cell is 84 x 34, so three across is wider than three down is tall.
    ok(FG.anchor.__w == 3 * (84 + 3) - 3 and FG.anchor.__h == 34,
       "and the grid is as wide as the group is long, one row deep",
       ("%sx%s (was %sx%s)"):format(FG.anchor.__w, FG.anchor.__h, tallW, tallH))

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
    -- THREE LAYOUTS since 23 Sep (a player asked for cells "vertically and horizontally"), so the
    -- no-argument command walks: columns -> rows -> pyramid -> columns.
    ok(NS.DO.layout() == "rows" and d.layout == "rows", "/bish layout with nothing goes to rows")
    ok(NS.DO.layout() == "pyramid", "then the pyramid")
    ok(NS.DO.layout() == "columns", "then back to columns")
    ok(NS.DO.layout("pyramid") == "pyramid", "or it can be told which")
    ok(NS.DO.layout("across") == "rows", "and 'across' is another word for rows")
    NS.DO.layout("columns")

    local found
    for _, sec in ipairs(NS.CFG.Sections()) do
        for _, o in ipairs(sec.options) do if o.key == "layout" then found = o end end
    end
    ok(found and found.kind == "seg" and #found.values == 3,
       "the options window offers all three layouts in one row")
    ok(found and found.get(d) == "down", "and it reads 'down' while the grid is in columns")
    found.set(d, "across")
    ok(d.layout == "rows", "picking 'across' turns the grid")
    found.set(d, "down")
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

    -- THREE SETTINGS SINCE 26 SEP, not two: in the main cells, in a block of their own, or
    -- nowhere. Off is still what a fresh install gets - the three are about WHERE, not whether.
    ok(FG.PetsMode() == "off", "pets are off on a fresh install", FG.PetsMode())
    local off = table.concat(FG.Roster(), " ")
    ok(not off:find("pet", 1, true), "and while off, no pet is in the roster even when one exists", off)

    ok(NS.DO.pets("grid") == "grid" and FG.PetsInGrid(), "/bish pets grid puts them in the cells")
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

    -- a bare /bish pets walks the three, so the options button and the old habit both work
    ok(NS.DO.pets() == "own", "a bare /bish pets walks on to the block")
    ok(NS.DO.pets() == "off", "and then to off")
    ok(NS.DO.pets() == "grid", "and round again")
    -- A MACRO WRITTEN BEFORE TODAY HOLDS A BOOLEAN, and it still means what it meant
    d.pets = true
    ok(FG.PetsMode() == "grid", "an old `true` reads as the main cells", FG.PetsMode())
    d.pets = false
    ok(FG.PetsMode() == "off", "and an old `false` as off", FG.PetsMode())
    ok(NS.DO.pets("off") == "off", "and /bish pets off turns them off again")
    STATE.units.pet, STATE.units.partypet1 = nil, nil
    FG.Layout(FG.anchor)
end

-- A HALF-SIZE CELL GIVES UP ITS ROLE ICON SO THE NAME CAN SHOW. Arn, 30 Sep, with a 40 pixel
-- pyramid cell reading "Ch...": "lets try and modify the half size ones ... so at least the name
-- can show". The icon only appears on cells that live in the pyramid, where the shape already
-- says the role - so it is repeating in 11 pixels what the position says for nothing.
do
    local cell = FG.frames[1]
    STATE.roles = { party1 = "HEALER" }
    cell.unit = "party1"

    FG.FitCell(cell, 84)
    FG.PaintRole(cell)
    ok(cell.__narrow == false, "an ordinary cell is not narrow")
    local wide = cell.name.points[#cell.name.points]
    -- SetPoint("TOPRIGHT", x, y) with no relative frame: the offset is the SECOND value
    ok(wide and wide[1] == "TOPRIGHT" and wide[2] == -14,
       "and its name stops short of the role icon", wide and tostring(wide[2]))
    ok(cell.role:IsShown(), "which is shown")

    FG.FitCell(cell, 40)
    FG.PaintRole(cell)
    ok(cell.__narrow == true, "a half-size one is")
    local thin = cell.name.points[#cell.name.points]
    ok(thin and thin[1] == "TOPRIGHT" and thin[2] == -3,
       "its name takes the whole width", thin and tostring(thin[2]))
    ok(not cell.role:IsShown(), "and the role icon is gone - the pyramid's shape already says it")

    -- AND THE NAME IS CUT TO WHAT THE CELL HOLDS, not to a fixed twelve characters
    _G.UnitName = function() return "Chevgchelio" end
    ok(#FG.CellName(cell, "party1") <= 7,
       "the name is cut to what 40 pixels can hold", FG.CellName(cell, "party1"))
    FG.FitCell(cell, 84)
    ok(#FG.CellName(cell, "party1") > 7,
       "and a full-width cell still gets the whole of it", FG.CellName(cell, "party1"))

    -- a name the client hides cannot be cut at all - it goes over whole and the client clips it
    _G.UnitName = function() return secret() end
    FG.FitCell(cell, 40)
    ok(pcall(FG.CellName, cell, "party1"), "a hidden name does not throw on the way through")
    _G.UnitName = function(u) return "Name-" .. tostring(u) end

    -- AND THE LAYOUT IS WHAT APPLIES IT. Calling FitCell by hand proves the function; it does not
    -- prove that a cell ever meets it. The pyramid is where narrow cells come from, so lay one out
    -- and look at the cell the shape made small.
    _G.UnitName = function(u) return "Name-" .. tostring(u) end
    local d = NS.DB()
    local wasLayout = d.layout
    d.layout = "pyramid"
    for i = 1, 30 do STATE.units["raid" .. i] = true end
    local realRaid = _G.IsInRaid
    _G.IsInRaid = function() return true end
    FG.Layout(FG.anchor)
    local small, big = nil, nil
    for _, g in ipairs(FG.frames) do
        if g:IsShown() and g.__narrow == true then small = small or g end
        if g:IsShown() and g.__narrow == false then big = big or g end
    end
    ok(small ~= nil, "a pyramid in a 30-man actually produces narrow cells")
    ok(big ~= nil, "and wide ones above them")
    ok(small and not small.role:IsShown(), "the narrow ones have no role icon after a real layout")

    _G.IsInRaid = realRaid
    for i = 1, 30 do STATE.units["raid" .. i] = nil end
    d.layout = wasLayout
    FG.Layout(FG.anchor)
    STATE.roles = nil
end

-- A FRAME ROUND THE PEOPLE WHO MATTER. Arn, 30 Sep: "yellow frame around the healers and a gold
-- frame around self". The bar is inset by a pixel, so the cell's background shows as a ring - and
-- colouring that background is the whole implementation.
do
    local cell = FG.frames[1]
    local realIsUnit = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) return a == "player" and b == "player" end
    STATE.roles = { player = "HEALER", party1 = "HEALER", party2 = "DAMAGER" }

    -- FOUR LINES ABOVE THE BAR, NOT THE BACKDROP. The backdrop was the first attempt and lasted
    -- an hour: a StatusBar only paints up to its value, so the backdrop shows through wherever the
    -- health is MISSING and the gold filled the empty half of the cell (Arn: "only the outline not
    -- the whole cell"). The lines are their own textures, over the bar.
    local function ringColour(c)
        local t = c.edge and c.edge.top
        return t and t.__shown and t.__color or nil
    end
    cell.unit = "party1"
    FG.PaintEdge(cell, "party1")
    local ring = ringColour(cell)
    ok(ring and math.abs(ring[1] - FG.EDGE.healer[1]) < 0.01
       and math.abs(ring[3] - FG.EDGE.healer[3]) < 0.01,
       "another healer gets the yellow ring", ring and table.concat(ring, ","))
    ok(cell.bg.__color and cell.bg.__color[1] < 0.2,
       "and the cell's own backdrop stays dark, so missing health is not gold",
       cell.bg.__color and cell.bg.__color[1])
    -- all four sides, not just the one a test happened to read: three of them were deletable
    local lit = 0
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = cell.edge[side]
        if t.__shown and t.__color and math.abs(t.__color[1] - FG.EDGE.healer[1]) < 0.01 then
            lit = lit + 1
        end
    end
    ok(lit == 4, "and it is a ring - all four sides lit, not one", lit)

    FG.PaintEdge(cell, "player")
    ring = ringColour(cell)
    ok(ring and math.abs(ring[1] - FG.EDGE.me[1]) < 0.01
       and math.abs(ring[3] - FG.EDGE.me[3]) < 0.01,
       "you get the gold one", ring and table.concat(ring, ","))
    ok(FG.EDGE.me[3] ~= FG.EDGE.healer[3], "and the two are not the same colour")

    FG.PaintEdge(cell, "party2")
    ok(not (cell.edge.top.__shown and cell.edge.left.__shown),
       "everyone else has no ring at all")
    ok(cell.edge.top.__shown == false and cell.edge.bottom.__shown == false
       and cell.edge.left.__shown == false and cell.edge.right.__shown == false,
       "all four sides of it, not just the one a test looked at")

    -- THROUGH FG.Paint, not just by hand: a cell is painted by the loop, and a test that only
    -- ever calls the painter directly lets the CALL be deleted without noticing.
    cell.unit = "party1"
    cell.edge.top.__color = nil
    FG.Paint(cell)
    ok(ringColour(cell) and math.abs(ringColour(cell)[1] - FG.EDGE.healer[1]) < 0.01,
       "and the ordinary paint puts the ring on", ringColour(cell) and ringColour(cell)[1])

    -- WITHOUT UnitIsUnit AT ALL, your own cell is still yours. That call can be missing or secret;
    -- the unit token "player" is neither.
    _G.UnitIsUnit = nil
    FG.PaintEdge(cell, "player")
    ok(math.abs(ringColour(cell)[1] - FG.EDGE.me[1]) < 0.01,
       "with no UnitIsUnit on the client, the player token is enough",
       table.concat(ringColour(cell), ","))
    _G.UnitIsUnit = function(a, b) return a == "player" and b == "player" end

    -- A ROLE THE CLIENT HIDES KEEPS THE LAST RING. Who someone IS does not change mid-pull, and a
    -- cell that flickers between gold and nothing every time the client goes quiet is worse than
    -- one that holds still.
    FG.PaintEdge(cell, "party1")
    STATE.roleSecret = true
    ok(FG.PaintEdge(cell, "party1") == "healer",
       "a hidden role keeps the ring it had", tostring(FG.PaintEdge(cell, "party1")))
    ok(math.abs(ringColour(cell)[1] - FG.EDGE.healer[1]) < 0.01, "and the colour with it")
    STATE.roleSecret = false

    STATE.roles = nil
    _G.UnitIsUnit = realIsUnit
    cell.unit = "party1"
end

-- AN ENEMY SHOULD NOT LOOK LIKE A FRIEND. Arn, 28 Sep, on his hunter: the target and tot cells
-- cast on hostile units perfectly well - which nobody designed and everybody likes - but "enemies
-- look like friendlies". The bar goes red for anything you could attack.
do
    local d = NS.DB()
    d.target = false
    NS.DO.target(true)
    local t = FG.target
    ok(t.mayBeHostile == true, "the target cell asks whether its unit can be attacked")
    ok(FG.frames[1].mayBeHostile ~= true, "and a group cell does not - your party is not hostile")

    STATE.units.target = true
    STATE.hostile.target = true
    t.unit = "target"
    FG.Paint(t)
    ok(t.bar.__color and math.abs(t.bar.__color[1] - FG.HOSTILE[1]) < 0.01,
       "a unit you can attack paints hostile", t.bar.__color and t.bar.__color[1])
    ok(FG.hostileSeen == "plain", "read plainly out of combat", tostring(FG.hostileSeen))

    STATE.hostile.target = false
    FG.Paint(t)
    ok(math.abs(t.bar.__color[1] - FG.HOSTILE[1]) > 0.01,
       "and a friendly one does not", t.bar.__color[1])

    -- IN COMBAT THE ANSWER IS SECRET, which is exactly when you are looking at the thing you are
    -- fighting. The client's own ternary picks each channel; nothing here tests the boolean.
    STATE.hostileSecret = true
    ok(pcall(FG.Paint, t), "a secret answer does not throw")
    ok(FG.hostileSeen == "secret", "the client chooses the colour for us", tostring(FG.hostileSeen))
    -- ALL THREE CHANNELS, not just the red one: each is its own call, and a test that checks one
    -- leaves the other two free to be deleted. (The green and blue were, by a mutation.)
    local chans = 0
    for i = 1, 3 do
        if getmetatable(t.bar.__color[i]) == getmetatable(secret()) then chans = chans + 1 end
    end
    ok(chans == 3, "and every channel reaches the bar unread, not just the first", chans)

    -- a client that will not take it leaves the cell in its friendly colour rather than throwing
    local realCurve = _G.C_CurveUtil.EvaluateColorValueFromBoolean
    _G.C_CurveUtil.EvaluateColorValueFromBoolean = nil
    ok(pcall(FG.Paint, t), "and a client without the ternary does not throw")
    ok(FG.hostileSeen == "secret, no curve", "saying so", tostring(FG.hostileSeen))
    ok(type(t.bar.__color[1]) == "number", "the bar keeps a colour it can draw")
    _G.C_CurveUtil.EvaluateColorValueFromBoolean = realCurve

    STATE.hostileSecret = false
    STATE.hostile.target, STATE.units.target = nil, nil
    NS.DO.target(false)
    FG.Layout(FG.anchor)
end

-- THE OTHER HEALERS' MANA. Arn, 28 Sep, with a screenshot of EllesmereUI's party frames: "the top
-- thing is the healer mana" - on a client where this addon's own Between.lua had written, since
-- the 17th, that "who is low on mana" could not be answered "by this addon, not by any addon".
--
-- It was right about READING the number and wrong about SHOWING it, which is the one mistake this
-- addon exists to avoid. UnitPowerPercent's answer goes straight into SetFormattedText and the
-- client does the rest.
do
    local d = NS.DB()
    d.mana = false
    STATE.roles = { player = "HEALER", party1 = "HEALER", party2 = "DAMAGER" }
    FG.Layout(FG.anchor)
    ok(FG.manaAnchor == nil or not FG.manaAnchor:IsShown(), "off by default: no mana block")

    ok(NS.DO.mana(true) == true, "/bish mana turns it on")
    ok(FG.manaAnchor and FG.manaAnchor:IsShown(), "the block is there")
    local who = {}
    for _, row in ipairs(FG.manaRows or {}) do if row:IsShown() then who[#who + 1] = row.unit end end
    ok(#who == 2, "one row per healer, and nobody else", table.concat(who, ","))
    ok(who[1] == "player" and who[2] == "party1", "you included - your own bar is the one you check most",
       table.concat(who, ","))

    -- THE NUMBER IS NEVER READ. It goes to the format setter, which is the client's own drawing.
    local row = FG.manaRows[1]
    ok(row.pct.__formatted and row.pct.__formatted[1]:find("%%d"),
       "the percentage is handed to the client to format")
    STATE.power.player = 42
    FG.PaintMana(row, "player")
    ok(row.pct.__formatted[2] == 42, "out of combat that is a plain number", row.pct.__formatted[2])

    -- IN COMBAT IT IS A SECRET, and that changes nothing: there is no branch to break.
    STATE.powerSecret = true
    ok(pcall(FG.PaintMana, row, "player"), "a secret percentage does not throw")
    ok(getmetatable(row.pct.__formatted[2]) == getmetatable(secret()),
       "it reaches the setter unread, like every other secret")
    ok(FG.manaSeen == "drawn", "and is drawn", tostring(FG.manaSeen))

    -- A CLIENT THAT REFUSES IT says nothing rather than a number it made up.
    STATE.formatRefusesSecret = true
    row.pct:SetText("stale")
    ok(pcall(FG.PaintMana, row, "player"), "a client refusing the secret does not throw either")
    ok(row.pct.__text == "", "and the row is blanked rather than left with an old number",
       tostring(row.pct.__text))
    ok(FG.manaSeen == "refused", "with the reason recorded", tostring(FG.manaSeen))
    STATE.formatRefusesSecret = false
    STATE.powerSecret = false

    -- a client without the call at all
    STATE.powerNoCall = true
    ok(pcall(FG.PaintMana, row, "player"), "and a client without the call is quiet, not broken")
    STATE.powerNoCall = false

    -- A ROLE THE CLIENT HIDES IS NOT A HEALER. Yours is read separately when you have a cell of
    -- your own (you are out of the roster then), and that read has its own guard to keep.
    d.me = true
    STATE.roleSecret = true
    local hidden = FG.Healers()
    local sawPlayer = false
    for _, u in ipairs(hidden) do if u == "player" then sawPlayer = true end end
    ok(not sawPlayer, "a role the client will not say is not a healer", table.concat(hidden, ","))
    STATE.roleSecret = false
    d.me = false

    -- IT IS A BLOCK, so it takes a side of its own like the others
    NS.DO.target("top")
    NS.DO.mana("top")
    ok(d.manaAt ~= "top", "it does not land on a side another block is using", tostring(d.manaAt))
    -- and switched on with a plain yes, which is what the options window sends: the remembered
    -- side may belong to somebody else by now, and that path names no spot at all
    NS.DO.mana(false)
    d.manaAt = "top"
    NS.DO.mana(true)
    ok(d.manaAt ~= "top", "switching it on with no side named dodges too", tostring(d.manaAt))

    -- AND IT SURVIVES A RESTART
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    NS.DO.mana("under")
    local body = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(body and body:find("A=1", 1, true), "where it sits goes into the macro", body)
    d.binds, d.bindsSeeded, NS.FM.asked, d.mana, d.manaAt = {}, nil, false, false, "right"
    NS.FM.Get("", "wheelup")
    ok(d.mana == true and d.manaAt == "under", "and comes back after a restart",
       tostring(d.mana) .. "/" .. tostring(d.manaAt))
    d.binds = keptBinds
    MACROS = {}

    -- a group with no other healer in it shows nothing at all, rather than an empty box
    STATE.roles = { player = "DAMAGER", party1 = "DAMAGER" }
    NS.DO.mana(true)
    ok(not FG.manaAnchor:IsShown(), "no healers, no block")
    STATE.roles = nil
    d.mana = false
    FG.Layout(FG.anchor)
end

-- A CELL FOR YOURSELF, OUT OF THE GROUP. A player's request (paszczyszyn on CurseForge, 25 Sep
-- 2026): "optional (like target) self target? It may be nice option to lock yourself in one spot
-- outside groups just to get use to it and have it in same spot for solo/or raid groups?".
--
-- The spot never moving IS the feature, which is why switching it on takes you out of the grid.
do
    local d = NS.DB()
    d.me = false
    FG.Layout(FG.anchor)
    ok(FG.me == nil or not FG.me:IsShown(), "off by default: no cell of your own")
    ok(table.concat(FG.Roster(), " "):find("player", 1, true), "and you are in the group grid")

    ok(NS.DO.me(true) == true, "/bish me turns it on")
    local mine = FG.me
    ok(mine ~= nil and mine:IsShown(), "the cell is there")
    ok(mine:GetAttribute("unit") == "player", "and it is you", tostring(mine:GetAttribute("unit")))
    ok(mine.__attrs["*type1"] ~= nil, "with the mouse binds on it, like any other cell")
    ok(mine.handle and mine.handle.__fontstrings
       and mine.handle.__fontstrings[1].__text == "BiS> me", "under a bar that says which cell it is",
       mine.handle and mine.handle.__fontstrings and tostring(mine.handle.__fontstrings[1].__text))

    -- THE POINT OF THE WHOLE THING: out of the roster, so the grid cannot reshape around you
    local roster = table.concat(FG.Roster(), " ")
    ok(not roster:find("player", 1, true), "and you are OUT of the group grid", roster)
    ok(roster:find("party1", 1, true), "while everyone else is still in it", roster)

    -- in a raid it is the same, and "which one is me" is the client's own answer
    local realRaid, realIsUnit = _G.IsInRaid, _G.UnitIsUnit
    _G.IsInRaid = function() return true end
    STATE.units.raid1, STATE.units.raid2 = true, true
    _G.UnitIsUnit = function(a, b) return a == "raid2" and b == "player" end
    local raid = table.concat(FG.Roster(), " ")
    ok(raid:find("raid1", 1, true) and not raid:find("raid2", 1, true),
       "in a raid, the slot that IS you is the one left out", raid)
    -- and an identity the client hides leaves the cell where it is, rather than dropping a raider
    _G.UnitIsUnit = function() return secret() end
    local hidden = table.concat(FG.Roster(), " ")
    ok(hidden:find("raid1", 1, true) and hidden:find("raid2", 1, true),
       "an identity it will not confirm leaves everybody in the raid", hidden)
    _G.IsInRaid, _G.UnitIsUnit = realRaid, realIsUnit
    STATE.units.raid1, STATE.units.raid2 = nil, nil

    -- it has its own spot, so moving it does not move the target block
    NS.DO.target("top")
    local function spotOf(f)
        local p = f and f.points and f.points[#f.points]
        return p and (tostring(p[1]) .. "->" .. tostring(p[3])) or "nowhere"
    end
    ok(FG.SelfSpot() == "left", "it starts on the grid's left, away from the target block")
    ok(spotOf(mine) == "TOPRIGHT->TOPLEFT", "which is where it is drawn", spotOf(mine))
    NS.DO.me("right")
    ok(FG.SelfSpot() == "right" and d.targetAt == "top",
       "moving it leaves the target cell where it was", tostring(d.targetAt))

    -- a drag on its bar writes ITS place, not the target's
    local realUC = UIParent.GetCenter
    UIParent.GetCenter = function() return 960, 540 end
    mine.GetCenter = function() return 860, 590 end            -- 100 left, 50 up
    local h = mine.handle
    h.__scripts.OnDragStart(h)
    h.__scripts.OnDragStop(h)
    ok(d.meAt == "free" and d.mePos and d.mePos.x == -100 and d.mePos.y == 50,
       "dragging it sets it free and remembers where",
       d.mePos and ("%s,%s"):format(d.mePos.x, d.mePos.y))
    ok(d.targetAt == "top" and d.targetPos == nil,
       "and the target block is untouched by it", tostring(d.targetAt))
    UIParent.GetCenter, mine.GetCenter = realUC, nil

    -- AND IT SURVIVES A RESTART, which on this client means the macro
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    NS.DO.me("under")
    local body = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(body and body:find("Y=1", 1, true), "where it sits goes into the macro", body)
    d.binds, d.bindsSeeded, NS.FM.asked, d.me, d.meAt = {}, nil, false, false, "left"
    NS.FM.Get("", "wheelup")
    ok(d.me == true and d.meAt == "under", "and after a restart it is back, in the same place",
       tostring(d.me) .. "/" .. tostring(d.meAt))
    d.binds = keptBinds
    MACROS = {}

    ok(NS.DO.me(false) == false, "/bish me turns it off")
    ok(not FG.me:IsShown() and FG.me.unit == nil, "the cell goes")
    WATCH_TICK()
    ok(not FG.me:IsShown(), "and the client's watch does not bring it back")
    ok(table.concat(FG.Roster(), " "):find("player", 1, true), "and you are back in the group grid")
    d.me = false
    FG.Layout(FG.anchor)
end

-- TWO BLOCKS NEVER SHARE A SIDE. Arn, 26 Sep, with one bar reading "BiS> meget" - the target's
-- word and yours printed through each other: "if target is already taking up the top and i also
-- turn on me dont overlap them send them to the next available slot".
do
    local d = NS.DB()
    d.target, d.me, d.tot, d.pets = false, false, false, "off"
    d.targetAt, d.meAt, d.petAt = "top", "left", "under"
    FG.Layout(FG.anchor)

    NS.DO.target("top")
    NS.DO.me("top")                                  -- asking for a side that is already taken
    ok(d.targetAt == "top", "the block that was there first keeps its place", tostring(d.targetAt))
    ok(d.meAt ~= "top", "and the one arriving does not land on it", tostring(d.meAt))
    ok(FG.TARGET_SPOTS[d.meAt], "it lands on a real side", tostring(d.meAt))
    ok(d.meAt == "right", "the next one round the ring", tostring(d.meAt))

    -- AND THE OTHER WAY ROUND: yours there first, the target arriving. Tested both ways because
    -- each block is a separate line in the "is anyone here?" question, and a test that only ever
    -- collides one pair one way leaves the other line free to be deleted.
    NS.DO.target(false)
    NS.DO.me("top")
    NS.DO.target("top")
    ok(d.meAt == "top" and d.targetAt ~= "top",
       "yours first, and the target cell is the one that moves",
       ("me %s, target %s"):format(tostring(d.meAt), tostring(d.targetAt)))

    -- TWO SIDES TAKEN, so the walk has to step more than once. With only one in use, a ring walk
    -- that gives up immediately lands on the same answer as one that looks properly.
    NS.DO.me("top")
    NS.DO.target("right")
    NS.DO.pets("own")
    d.petAt = "top"                                  -- and now ask it to sit on an occupied side
    NS.DO.pets("own")
    ok(d.petAt == "under",
       "with top and right in use, the third block walks past both",
       ("pets %s, me %s, target %s"):format(tostring(d.petAt), tostring(d.meAt), tostring(d.targetAt)))
    ok(d.petAt ~= d.targetAt and d.petAt ~= d.meAt,
       "and lands on a side neither of the others is on")

    -- SWITCHED ON WITH A PLAIN yes, which is what the options window sends: the remembered side
    -- may be somebody else's by now, and nothing in that path passes through a spot word.
    NS.DO.me(false)
    d.meAt = "right"                                 -- where the target block is sitting
    NS.DO.me(true)
    ok(d.meAt ~= "right", "switching it on with no side named still avoids the others",
       ("me %s, target %s"):format(tostring(d.meAt), tostring(d.targetAt)))
    -- and the target cell, switched on the same way, onto a side yours is already using
    NS.DO.target(false)
    d.targetAt = d.meAt
    NS.DO.target(true)
    ok(d.targetAt ~= d.meAt, "and so does the target cell, switched on the same way",
       ("target %s, me %s"):format(tostring(d.targetAt), tostring(d.meAt)))
    -- AND THE PET BLOCK IS SOMETHING TO AVOID, not just something that avoids. It is the only
    -- block that is not a single cell, and it was the last line of the question to be written.
    NS.DO.pets("own")
    NS.DO.me(false)
    d.meAt = d.petAt
    NS.DO.me(true)
    ok(d.meAt ~= d.petAt, "a block is in the way of others, as well as avoiding them",
       ("me %s, pets %s"):format(tostring(d.meAt), tostring(d.petAt)))
    NS.DO.pets("off")

    -- a shift-click walks past an occupied side too, rather than stopping on it
    local h = FG.me.handle
    STATE.shift = true
    h.dragged = nil
    h.__scripts.OnMouseUp(h, "LeftButton")
    STATE.shift = false
    ok(d.meAt ~= d.targetAt and d.meAt ~= d.petAt,
       "shift-clicking round the ring skips the sides in use",
       ("me %s, target %s, pets %s"):format(tostring(d.meAt), tostring(d.targetAt), tostring(d.petAt)))

    -- "FREE" IS NOT A SIDE, it is wherever a drag put it - so any number of blocks can be free at
    -- once and none of them is ever in another's way.
    NS.DO.me(false)
    NS.DO.pets("off")
    NS.DO.target("top")                              -- one block in play, so the answer is its own
    ok(FG.SpotTaken("top", FG.PET_KEYS) == true, "a block ON a side is in the way")
    ok(FG.SpotTaken("free", FG.PET_KEYS) == false, "but nothing is ever in the way of a drag")
    d.targetAt, d.targetPos = "free", { x = 10, y = 10 }
    ok(FG.SpotTaken("top", FG.PET_KEYS) == false, "and one that was dragged away leaves its side")
    ok(FG.SpotTaken("free", FG.PET_KEYS) == false, "even to another block being dragged")

    d.target, d.me, d.tot, d.pets = false, false, false, "off"
    d.targetAt, d.meAt, d.petAt, d.mePos, d.targetPos = "top", "left", "under", nil, nil
    FG.Layout(FG.anchor)
end

-- PETS IN A BLOCK OF THEIR OWN. paszczyszyn, 25 Sep: "separete pet group (being able to have
-- different setup's for it and move it alone, just to make it smaller and in different possition,
-- as pets are not that important as players but still being able to cast on them)".
do
    local d = NS.DB()
    STATE.units.pet, STATE.units.partypet1 = true, true

    NS.DO.pets("own")
    ok(FG.PetsOwnBlock(), "/bish pets own gives them a block")
    local roster = table.concat(FG.Roster(), " ")
    ok(not roster:find("pet", 1, true), "and they come OUT of the main grid", roster)
    ok(FG.petAnchor and FG.petAnchor:IsShown(), "the block is there")
    ok(FG.petFrames and FG.petFrames[1] and FG.petFrames[1]:IsShown(), "with a cell in it")
    ok(FG.petFrames[1]:GetAttribute("unit") == "pet"
       and FG.petFrames[2]:GetAttribute("unit") == "partypet1",
       "one per pet, in the group's order",
       tostring(FG.petFrames[1]:GetAttribute("unit")))
    ok(FG.petFrames[1].__attrs["*type1"] ~= nil,
       "and the mouse binds on them, because a pet is still something you heal")
    ok(FG.petAnchor.handle and FG.petAnchor.handle.__fontstrings
       and FG.petAnchor.handle.__fontstrings[1].__text == "BiS> pets",
       "under a bar of its own",
       FG.petAnchor.handle and FG.petAnchor.handle.__fontstrings
       and tostring(FG.petAnchor.handle.__fontstrings[1].__text))

    -- MOVED AS ONE THING. The cells hang off the block, so the bar drags all of them at once -
    -- which is the whole difference between a block and a handful of loose cells.
    ok(FG.petFrames[1]:GetParent() == FG.petAnchor, "the cells hang off the block")
    local realUC = UIParent.GetCenter
    UIParent.GetCenter = function() return 960, 540 end
    FG.petAnchor.GetCenter = function() return 760, 440 end          -- 200 left, 100 down
    local h = FG.petAnchor.handle
    h.__scripts.OnDragStart(h)
    h.__scripts.OnDragStop(h)
    ok(d.petAt == "free" and d.petPos and d.petPos.x == -200 and d.petPos.y == -100,
       "and dragging the bar moves the block, and remembers where",
       d.petPos and ("%s,%s"):format(d.petPos.x, d.petPos.y))
    UIParent.GetCenter, FG.petAnchor.GetCenter = realUC, nil

    -- IT RIDES IN THE MACRO, which pets never did before today: "pets on" was forgotten at every
    -- single login, quietly, for as long as the option has existed.
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    NS.DO.pets("own")
    NS.DO.me("left")                                  -- something else to share the row with
    local body = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(body and body:find("V=2", 1, true), "the pet setting goes into the macro", body)
    d.binds, d.bindsSeeded, NS.FM.asked, d.pets = {}, nil, false, "off"
    NS.FM.Get("", "wheelup")
    ok(FG.PetsMode() == "own", "and after a restart the pets are still in their block",
       FG.PetsMode())
    d.binds = keptBinds
    MACROS = {}

    NS.DO.pets("off")
    ok(not FG.petAnchor:IsShown(), "switched off, the block goes")
    ok(FG.petFrames[1].unit == nil, "and its cells stop being watched")
    WATCH_TICK()
    ok(not FG.petFrames[1]:IsShown(), "so the client does not bring them back")

    STATE.units.pet, STATE.units.partypet1 = nil, nil
    d.me, d.pets = false, "off"
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

-- A CELL FOR YOUR TARGET, and how big the markers are. Both asked for by a player on CurseForge
-- (paszczyszyn, 22 Sep), with the layout above: "Any chance to a separate cell appear for your
-- current target?" and "an option to adjust the size of buffs and debuffs?".
do
    local FM = NS.FM
    local d = NS.DB()
    d.target = false
    FG.Layout(FG.anchor)
    ok(FG.target == nil or not FG.target:IsShown(), "off by default: no target cell")

    ok(NS.DO.target(true) == true, "/bish target turns it on")
    local t = FG.target
    ok(t ~= nil and t:IsShown(), "the cell is there")
    ok(t and t:GetAttribute("unit") == "target",
       "and it is the CLIENT's target token, so it follows your target in a fight",
       t and tostring(t:GetAttribute("unit")))
    local function spot()
        local p = FG.target and FG.target.points and FG.target.points[#FG.target.points]
        return p and (tostring(p[1]) .. "->" .. tostring(p[3])) or "nowhere"
    end
    -- TOP BY DEFAULT. Arn, 23 Sep: under the grid, the handle is in the gap between the two and
    -- the grid covers it - "you cant see the header to move it".
    ok(spot() == "BOTTOMLEFT->TOPLEFT", "above the grid to begin with", spot())
    -- said in two places, and both have to agree: the fresh-install default (Core) and the answer
    -- for a table that has no such key at all (Grid)
    local realDB = NS.DB
    NS.DB = function() return { target = true } end          -- a table with no spot in it at all
    ok(FG.TargetSpot() == "top", "and with nothing saved at all, still the top", FG.TargetSpot())
    NS.DB = function() return { target = true, targetAt = "sideways" } end   -- or nonsense in it
    ok(FG.TargetSpot() == "top", "and a spot it does not know is the top too", FG.TargetSpot())
    NS.DB = realDB
    ok(t.__attrs["*type1"] ~= nil, "with the mouse binds on it like any other cell")

    -- FOUR PLACES, and its own handle for anywhere else. Arn, 23 Sep: "lets do a toggle under grid
    -- to the right left or top. and we can give it its own little header where they can drag it
    -- where ever they want on screen".
    -- AND ALWAYS THE GRID'S OWN GAP AWAY FROM IT: three pixels, the same as between two columns.
    -- Anything else reads as "nearly lined up" (Arn, 23 Sep: "make sure all the windows line up").
    local function offs()
        local p = FG.target and FG.target.points and FG.target.points[#FG.target.points]
        return (p and p[4]) or 0, (p and p[5]) or 0
    end
    NS.DO.target("right")
    ok(spot() == "TOPLEFT->TOPRIGHT" and d.targetAt == "right", "/bish target right puts it beside the grid", spot())
    ok(offs() == 3, "one column's gap from the grid, not two", offs())
    NS.DO.target("left")
    ok(spot() == "TOPRIGHT->TOPLEFT" and d.targetAt == "left", "left is the other side", spot())
    ok(offs() == -3, "and the same gap on that side", offs())
    NS.DO.target("top")
    ok(spot() == "BOTTOMLEFT->TOPLEFT" and d.targetAt == "top", "top is above it", spot())
    -- 2 (the grid's bar floats) + 16 (that bar) + 3 (the gap). Its own bar is above it and needs
    -- nothing underneath, which is what the old 34 was paying for.
    ok(select(2, offs()) == 21, "clear of the grid's own bar by that same gap", select(2, offs()))
    NS.DO.target("under")
    ok(spot() == "TOPLEFT->BOTTOMLEFT", "and under hangs it below the grid")
    -- THE HEADER STAYS ON TOP OF ITS OWN CELL, everywhere. It used to swap to the underside here,
    -- because a bare 8 px handle in the gap was covered by the grid ("you cant see the header to
    -- move it"). It carries a NAME now - and a named bar under the thing it names is the label of
    -- whatever sits beneath it, which under the grid is the tot cell. So the block drops clear
    -- instead: far enough that the header has its own room between the two.
    local function handleAt()
        local hp = t.handle and t.handle.points and t.handle.points[#t.handle.points]
        return hp and (tostring(hp[1]) .. "->" .. tostring(hp[3])) or "nowhere"
    end
    local function dropOf()
        local p = FG.target and FG.target.points and FG.target.points[#FG.target.points]
        return p and p[5] or 0
    end
    ok(handleAt() == "BOTTOMRIGHT->TOPRIGHT", "its header is above it, under the grid", handleAt())
    -- EXACTLY THE ROOM ITS BAR NEEDS, AND THE GRID'S OWN GAP. Arn, 23 Sep: "make sure all the
    -- windows line up". A block a different distance from the grid than the grid's own columns
    -- are from each other reads as "nearly lined up", which is worse than plainly apart.
    -- 3 (the cells' own gap) + 1 (a bar floats a pixel above its cell) + 14 (the bar).
    ok(dropOf() == -18, "and it drops by exactly its bar plus the grid's own gap", dropOf())
    NS.DO.target("top")
    ok(handleAt() == "BOTTOMRIGHT->TOPRIGHT", "and above it everywhere else", handleAt())
    ok(t.handle and t.handle.__fontstrings and #t.handle.__fontstrings == 1
       and t.handle.__fontstrings[1].__text == "BiS> target",
       "and it says which cell it is - one label in the bar, per the header law",
       t.handle and t.handle.__fontstrings and t.handle.__fontstrings[1]
       and tostring(t.handle.__fontstrings[1].__text))
    ok(NS.DO.target("sideways") ~= nil and d.targetAt == "top",
       "a word it does not know moves nothing")

    -- SHIFT-CLICK WALKS IT ROUND THE GRID. Arn, 23 Sep: "if we shift click the header it toggles
    -- between top left right bottom and left click still drags".
    NS.DO.target("top")
    local hclick = t.handle and t.handle.__scripts and t.handle.__scripts.OnMouseUp
    ok(hclick ~= nil, "the handle takes a click as well as a drag")
    STATE.shift = true
    hclick(t.handle, "LeftButton")
    ok(d.targetAt == "right", "top goes to right", tostring(d.targetAt))
    hclick(t.handle, "LeftButton")
    ok(d.targetAt == "under", "right goes to under", tostring(d.targetAt))
    hclick(t.handle, "LeftButton")
    hclick(t.handle, "LeftButton")
    ok(d.targetAt == "top", "left, and round to the top again", tostring(d.targetAt))
    STATE.shift = false
    hclick(t.handle, "LeftButton")
    ok(d.targetAt == "top", "without shift, a click moves nothing - that is the drag's business")
    STATE.shift = true
    STATE.inCombat = true
    hclick(t.handle, "LeftButton")
    ok(d.targetAt == "top", "and not in combat either: the cell is a secure frame")
    STATE.inCombat = false
    STATE.shift = false

    -- the handle: a drag sets it free, and where it landed is remembered
    local h = t.handle
    ok(h ~= nil and h.__scripts and h.__scripts.OnDragStart, "the cell has a handle to drag")
    local realUC = UIParent.GetCenter
    UIParent.GetCenter = function() return 960, 540 end
    t.GetCenter = function() return 660, 440 end            -- 300 left, 100 down
    h.__scripts.OnDragStart(h)
    h.__scripts.OnDragStop(h)
    -- the mouse-up that ends a drag is not a shift-click, even with shift held
    STATE.shift = true
    h.__scripts.OnMouseUp(h, "LeftButton")
    STATE.shift = false
    ok(d.targetAt == "free" and d.targetPos and d.targetPos.x == -300 and d.targetPos.y == -100,
       "dragging it sets it free, and remembers where",
       d.targetPos and ("%s,%s"):format(d.targetPos.x, d.targetPos.y))
    local fp = t.points and t.points[#t.points]
    ok(fp and fp[1] == "CENTER" and math.abs((fp[4] or 0) - -300) < 1,
       "and it is pinned to the screen, not the grid", fp and tostring(fp[1]))
    -- AND IT STAYS PUT WHEN THE GRID IS RESIZED. Arn, 23 Sep: "when i increased the scale size the
    -- main window moved down and the target frames moved up and to the right". The cell is a child
    -- of the grid, so it wears the grid's scale: an offset written in its own units covers more
    -- screen at 1.4 than at 1.0, and the cell slides away from the middle. What is stored is the
    -- offset ON SCREEN, and the point is worked back from it at whatever scale is in force.
    local function screenXY()
        local p = t.points and t.points[#t.points]
        local k = (t.GetEffectiveScale and t:GetEffectiveScale()) or 1
        return p and (p[4] or 0) * k, p and (p[5] or 0) * k
    end
    -- and a drag made while the grid is BIGGER than life size writes the same kind of number: at
    -- 1.0 the cell's own units and the screen's agree, so only a drag at another scale can tell
    -- which of the two was written down
    FG.SetScale(1.4)
    h.__scripts.OnDragStart(h)
    h.__scripts.OnDragStop(h)
    local atBig = d.targetPos and d.targetPos.x
    local onScreenBig = select(2, FG.ScreenOffsetOf(t))
    ok(atBig == onScreenBig, "a drag at another scale writes where it is on screen",
       ("%s vs %s"):format(tostring(atBig), tostring(onScreenBig)))
    FG.SetScale(1)
    ok(d.targetPos.x == atBig, "and that number does not change when the grid is resized back")

    local wasX, wasY = screenXY()
    FG.SetScale(1.4)
    local nowX, nowY = screenXY()
    ok(math.abs(nowX - wasX) < 1 and math.abs(nowY - wasY) < 1,
       "a dragged target cell does not move on screen when the grid is resized",
       ("%s,%s -> %s,%s"):format(wasX, wasY, nowX, nowY))
    FG.SetScale(1)

    -- AND THE GRID ITSELF stays where it is: the anchor is pinned by its centre, so resizing grows
    -- it about that centre rather than walking it across the screen.
    local function anchorScreenXY()
        local p = FG.anchor.points and FG.anchor.points[#FG.anchor.points]
        local k = (FG.anchor.GetEffectiveScale and FG.anchor:GetEffectiveScale()) or 1
        return p and (p[4] or 0) * k, p and (p[5] or 0) * k
    end
    FG.anchor:ClearAllPoints()
    FG.anchor:SetPoint("CENTER", UIParent, "CENTER", 120, -80)
    FG.SavePos()
    local gx, gy = anchorScreenXY()
    FG.SetScale(1.4)
    local gx2, gy2 = anchorScreenXY()
    ok(math.abs(gx2 - gx) < 1 and math.abs(gy2 - gy) < 1,
       "and the grid stays where it was put when it is resized",
       ("%s,%s -> %s,%s"):format(gx, gy, gx2, gy2))
    FG.SetScale(1)

    UIParent.GetCenter, t.GetCenter = realUC, nil

    -- AND WHOEVER THEY ARE TARGETING, under it. Arn, 23 Sep: "another option that frame will also
    -- have target of target with its on header on top BiS>tot the frames are attached to each
    -- other".
    do
        NS.DO.target("top")
        ok(FG.tot == nil or not FG.tot:IsShown(), "off by default: no target-of-target cell")
        ok(NS.DO.tot(true) == true, "/bish tot turns it on")
        local tt = FG.tot
        ok(tt ~= nil and tt:IsShown(), "the second cell is there")
        ok(tt:GetAttribute("unit") == "targettarget",
           "and it is the client's own target-of-target token", tostring(tt:GetAttribute("unit")))

        -- ATTACHED, which means a CHILD of the target cell: a drag moves one frame and the other
        -- goes with it, and when you have no target at all the client hides the parent and this
        -- with it. Two frames merely placed beside each other would come apart at the first drag.
        ok(tt:GetParent() == t, "it hangs off the target cell, so the two cannot come apart")
        -- BESIDE IT, NOT UNDER IT. It was stacked underneath to begin with, and a column four
        -- frames deep hung across the grid as soon as the block was dragged near it. Arn: "i want
        -- tot to the right of the target window".
        local tp = tt.points and tt.points[#tt.points]
        ok(tp and tp[1] == "TOPLEFT" and tp[3] == "TOPRIGHT",
           "and it sits to the RIGHT of the target cell",
           tp and (tostring(tp[1]) .. "->" .. tostring(tp[3])))
        local hp = tt.handle and tt.handle.points and tt.handle.points[#tt.handle.points]
        ok(hp and hp[1] == "BOTTOMRIGHT" and hp[3] == "TOPRIGHT",
           "with its own bar on top of its own cell, level with the target's",
           hp and (tostring(hp[1]) .. "->" .. tostring(hp[3])))
        -- LINED UP WITH THE GRID. The gap between the two cells is the gap between two grid
        -- columns, so the pair is exactly as wide as two columns - which on the pyramid is one
        -- wide cell, and the edges agree. It was twice that, and the block overhung by 3 pixels.
        ok(tp and tp[4] == 3, "the gap between them is the grid's own, so the edges agree", tp and tp[4])

        -- AND IT GROWS AWAY FROM THE GRID. Parked on the grid's left, a tot on the right-hand
        -- side sits straight on top of the raid - Arn moved it over and saw it: "when i move it
        -- to the left now it should not overlap the tot".
        NS.DO.target("left")
        local lp = tt.points and tt.points[#tt.points]
        ok(lp and lp[1] == "TOPRIGHT" and lp[3] == "TOPLEFT" and lp[4] == -3,
           "on the grid's left the pair mirrors, so the tot is on the outside",
           lp and (tostring(lp[1]) .. "->" .. tostring(lp[3]) .. " " .. tostring(lp[4])))
        NS.DO.target("right")
        local rp = tt.points and tt.points[#tt.points]
        ok(rp and rp[1] == "TOPLEFT" and rp[3] == "TOPRIGHT",
           "and on the right it is back on the right", rp and tostring(rp[1]))
        -- and by the OTHER door: a shift-click on a bar walks the block round the grid without
        -- going near the layout, so the side has to be decided where the spot is set
        NS.DO.target("under")
        STATE.shift = true
        -- the mouse-up that ended the drag further up is still owed: a drag is not a click, and
        -- the bar swallows exactly one. The second is a player pressing the button on purpose.
        t.handle.__scripts.OnMouseUp(t.handle, "LeftButton")
        t.handle.__scripts.OnMouseUp(t.handle, "LeftButton")      -- under -> left
        STATE.shift = false
        local sp = tt.points and tt.points[#tt.points]
        ok(d.targetAt == "left" and sp and sp[1] == "TOPRIGHT",
           "a shift-click onto the grid's left mirrors it too",
           tostring(d.targetAt) .. " " .. (sp and tostring(sp[1]) or "nowhere"))
        NS.DO.target("top")
        ok(tt.handle and tt.handle.__fontstrings and tt.handle.__fontstrings[1].__text == "BiS> tot",
           "with its own header on top of it",
           tt.handle and tt.handle.__fontstrings and tostring(tt.handle.__fontstrings[1].__text))

        -- A DRAG ON THE TOT'S BAR MOVES THE TARGET CELL, and writes down where the TARGET cell
        -- landed. Asking the tot where it is would write a spot a cell's height too low, and the
        -- block would walk down the screen a little at every login.
        local realUC2, moved = UIParent.GetCenter, nil
        UIParent.GetCenter = function() return 960, 540 end
        t.GetCenter = function() return 760, 640 end            -- 200 left, 100 up
        t.StartMoving = function() moved = "target" end
        tt.StartMoving = function() moved = "tot" end
        tt.handle.__scripts.OnDragStart(tt.handle)
        tt.handle.__scripts.OnDragStop(tt.handle)
        ok(moved == "target", "dragging the tot's bar picks up the whole block", tostring(moved))
        ok(d.targetPos and d.targetPos.x == -200 and d.targetPos.y == 100,
           "and remembers where the TARGET cell landed, not where the tot did",
           d.targetPos and ("%s,%s"):format(d.targetPos.x, d.targetPos.y))
        UIParent.GetCenter, t.GetCenter = realUC2, nil
        t.StartMoving, tt.StartMoving = nil, nil
        NS.DO.target("top")

        -- IT RIDES IN THE TARGET'S OWN MACRO ROW. One row for one block: a row of its own could
        -- say "tot on" while the target row says "target off", and then the setting means nothing.
        MACROS = {}
        local keep = d.binds
        d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
        NS.DO.tot(true)
        local stored = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
        ok(stored and stored:find("G=4:1", 1, true), "the target row carries it after the colon", stored)
        local _, back = NS.FK.Decode(stored or "")
        ok(back.target == true and back.tot == true and back.targetAt == "top", "and both come back")
        -- the cold start: a login with no clicks has the second cell up
        d.binds, d.bindsSeeded, FM.asked, d.target, d.tot = {}, nil, false, false, false
        FM.Get("", "wheelup")
        ok(d.target == true and d.tot == true, "after a restart both cells are back",
           tostring(d.target) .. "/" .. tostring(d.tot))
        d.binds = keep
        MACROS = {}

        -- SWITCHED ON FROM COLD it turns the target cell on with it, rather than doing nothing
        -- visible: it has nothing to hang off otherwise.
        NS.DO.target(false)
        NS.DO.tot(false)
        NS.DO.tot(true)
        ok(d.target == true and FG.tot and FG.tot:IsShown(),
           "asking for it with the target cell off switches that one on too")

        -- and switching the TARGET cell off takes it with it: the parent is gone
        STATE.units.target, STATE.units.targettarget = true, true
        NS.DO.target(false)
        ok(not FG.tot:IsShown() and FG.tot.unit == nil, "switching the target cell off takes it too")
        WATCH_TICK()
        ok(not FG.tot:IsShown(), "and the client's watch does not bring it back on its own")
        STATE.units.target, STATE.units.targettarget = nil, nil
        d.tot = false
    end

    -- it goes away again, and takes the client's watch with it. STATE.units.target says you HAVE
    -- a target, which is exactly when a still-watched cell would be shown again by the client.
    STATE.units.target = true
    NS.DO.target(false)
    ok(not FG.target:IsShown() and FG.target.unit == nil, "switched off, the cell goes")
    WATCH_TICK()
    ok(not FG.target:IsShown(), "and the unit watch does not bring it back, even with a target up")
    STATE.units.target = nil

    -- MARKER SIZE. One number for the dispel marker and the heal-over-time icons.
    local FA = NS.FA
    ok(FA.MarkerSize() == 10, "ten pixels to begin with")
    ok(NS.DO.markers(16) == 16 and FA.MarkerSize() == 16, "/bish markers 16 makes them bigger")
    ok(NS.DO.markers(2) == 6 and NS.DO.markers(99) == 20, "and it is held between 6 and 20")
    NS.DO.markers(14)
    FA.sig = nil
    local cell = FG.frames[1]
    cell.auras = nil
    FA.Attach(cell, "party1")
    local dispel = cell.auras.slots["BiSHealDispel"]
    ok(dispel and dispel.__w == 14, "and the dispel marker is built at that size",
       dispel and tostring(dispel.__w))
    -- and the size is part of the containers' fingerprint, so a cell built at one size is rebuilt
    -- at another even when nothing cleared it by hand (the macro restoring a size does exactly that)
    d.markers = 10
    TICK()                      -- a frame goes by, so the per-frame fingerprint is asked again
    FA.Attach(cell, "party1")
    ok(cell.auras.slots["BiSHealDispel"].__w == 10,
       "a size changed underneath them rebuilds the markers on their own",
       cell.auras.slots["BiSHealDispel"].__w)

    -- ALL THREE RIDE IN THE MACRO, like the size and the binds before them
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    NS.DO.layout("rows"); NS.DO.target("left"); NS.DO.markers(14)
    local body = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(body and body:find("L=1", 1, true) and body:find("G=3", 1, true) and body:find("M=14", 1, true),
       "the layout, the target cell (with its place) and the marker size are all written", body)
    local _, st = NS.FK.Decode(body or "")
    ok(st and st.layout == "rows" and st.target == true and st.targetAt == "left" and st.markers == 14,
       "and all of it reads back")

    d.layout, d.target, d.markers, d.targetAt = "columns", false, 10, "under"
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false
    FM.Get("", "wheelup")                                    -- the first read after a restart
    ok(d.layout == "rows" and d.target == true and d.targetAt == "left" and d.markers == 14,
       "after a restart all of it is back, the target cell on the side it was put",
       ("%s / %s %s / %s"):format(tostring(d.layout), tostring(d.target), tostring(d.targetAt),
                                  tostring(d.markers)))

    -- and a DRAGGED one comes back where it was dragged, not against the grid
    d.targetAt, d.targetPos = "free", { x = -300, y = -100 }
    NS.FK.Save(d.binds)
    local dragged = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(dragged and dragged:find("G=5", 1, true) and dragged:find("Q=4700:4900", 1, true),
       "a dragged target cell writes where it is", dragged)
    d.targetAt, d.targetPos = "under", nil
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false
    FM.Get("", "wheelup")
    ok(d.targetAt == "free" and d.targetPos and d.targetPos.x == -300,
       "and comes back there after a restart",
       d.targetPos and ("%s,%s"):format(d.targetPos.x, d.targetPos.y))
    d.targetAt, d.targetPos = "under", nil

    -- an older install skips all three. Trimmed first, because the client adds a newline to every
    -- macro body and an anchored row pattern chokes on it - a different bug, fixed on 19 Sep.
    local reads = 0
    local trimmed = (body or ""):match("^%s*(.-)%s*$")
    for row in (trimmed:match("#(.*)$") or ""):gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and ({ l = 1, r = 1, u = 1, d = 1, m = 1, ["4"] = 1, ["5"] = 1 })[code:sub(-1)] then reads = reads + 1 end
    end
    ok(reads == 1, "an older install reads the one bind and skips L, G and M", reads)

    NS.DO.layout("columns"); NS.DO.target(false); NS.DO.markers(10)
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = keptBinds, nil, false, nil
    FG.Layout(FG.anchor)
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

-- THE FIVE SECOND RULE. Arn, 23 Sep: "can we add a the 5 second mana regen rule ... itll be like
-- a bar thats filling backwards in the header". Spend mana and your standing-still regeneration
-- stops for five seconds; what you get in the meantime is the character sheet's "while casting"
-- share, which already carries the talents. Your own mana is yours to read - none of this asks
-- about anybody else.
do
    local FR = NS.FR
    local realRegen, realCost = _G.GetManaRegen, _G.C_Spell.GetSpellPowerCost
    local realPower, realForType = _G.GetPowerRegen, _G.GetPowerRegenForPowerType
    _G.GetManaRegen = function() return 100, 30 end          -- 30% while casting, as a talent gives
    _G.C_Spell.GetSpellPowerCost = function(id)
        if id == 999 then return { { type = 0, cost = 0 } } end       -- a free spell
        return { { type = 0, cost = 250 } }
    end
    FR.spentAt = nil

    ok(FR.Left() == 0 and FR.Fraction() == 1, "standing still, you regenerate everything")
    ok(FR.Text() == "regen 100%", "and it says so", tostring(FR.Text()))

    ok(FR.OnCast("player", 331) == true, "a spell that costs mana starts the five seconds")
    ok(math.abs(FR.Left() - 5) < 0.01, "five of them", FR.Left())
    ok(FR.Fraction() == 0.3 and FR.Text() == "regen 30%",
       "and while they run you get the character sheet's share", tostring(FR.Text()))

    TICK(2)
    ok(math.abs(FR.Left() - 3) < 0.01, "two seconds later, three are left", FR.Left())
    TICK(3.5)
    ok(FR.Left() == 0 and FR.Fraction() == 1, "and after five you are regenerating again")

    -- a free spell does not stop your regeneration
    FR.spentAt = nil
    ok(FR.OnCast("player", 999) == false and FR.Left() == 0, "a spell that costs no mana starts nothing")
    ok(FR.OnCast("party1", 331) == false, "and somebody else casting is none of our business")

    -- THE BAR, draining across the header
    local h = FG.header
    FR.spentAt = nil
    FG.PaintRegen(h)
    ok(h.fsr and h.fsr.__shown == false, "with the rule not running, no bar")
    -- ONE WORD AFTER "BiS>". Arn, 23 Sep: "BiS> always stays . we then cycle when nothing is
    -- happening keep healing , when combat starts switch to regen mode and the % and the glow".
    ok(FG.HeaderWord() == "Healing", "out of combat the prompt says the addon's name",
       FG.HeaderWord())

    h:SetWidth(200)
    FR.OnCast("player", 331)
    FG.PaintRegen(h)
    ok(h.fsr.__shown ~= false and math.abs((h.fsr.__w or 0) - 200) < 1,
       "the moment you spend mana it fills the header", tostring(h.fsr.__w))
    STATE.inCombat = true
    ok(FG.HeaderWord() == "regen 30%", "and in a fight the word becomes what your mana is doing",
       FG.HeaderWord())
    FG.PaintRegen(h)
    ok(h.title and h.title.__text == "BiS> regen 30%", "written where the prompt goes",
       h.title and tostring(h.title.__text))
    -- AND IT FITS THE BAR IT IS IN. Arn, 23 Sep, on a party grid: "in the regular down toggel the
    -- regen gets cut off". The header is as wide as the grid, and one group down is one cell -
    -- 84 pixels, where "BiS> regen 30%" came out of the client as "BiS> regen ...". It trims from
    -- the right, so the part it threw away was the number: the only part worth reading.
    h:SetWidth(84)
    FG.PaintRegen(h)
    ok(h.title.__text == "BiS> 30%", "on a one-cell bar the number stands alone, and fits",
       tostring(h.title.__text))
    h:SetWidth(200)
    FG.PaintRegen(h)
    ok(h.title.__text == "BiS> regen 30%", "and the moment there is room, the word is back",
       tostring(h.title.__text))
    STATE.inCombat = false
    FG.PaintRegen(h)
    ok(h.title.__text == "BiS> Healing", "and back to the name when the fight ends",
       tostring(h.title.__text))
    TICK(2.5)
    FG.PaintRegen(h)
    ok(math.abs((h.fsr.__w or 0) - 100) < 2, "halfway through, it is half the header",
       tostring(h.fsr.__w))
    TICK(3)
    FG.PaintRegen(h)
    ok(h.fsr.__shown == false, "and when the five seconds are up it is gone")

    -- WHICHEVER CALL THIS CLIENT ANSWERS. Arn, 23 Sep, mid-fight: the header said "Healing" while
    -- he was casting, which means GetManaRegen answered nothing on that character. There are four
    -- ways to ask on this client; the first that gives two real numbers wins.
    FR.OnCast("player", 331)
    _G.GetManaRegen = function() return nil end
    _G.GetPowerRegen = function() return 200, 50 end
    ok(select(3, FR.Rates()) == "GetPowerRegen" and FR.Text() == "regen 25%",
       "with the first call silent, the next one answers", tostring(FR.Text()))
    _G.GetPowerRegen = nil
    _G.GetPowerRegenForPowerType = function() return 100, 45 end
    ok(FR.Text() == "regen 45%", "and the one after that", tostring(FR.Text()))

    -- IN A FIGHT IT IS A SECRET, so what was read out of combat is what the header shows.
    -- Measured in game 23 Sep: out of combat all three answer; the moment the pull starts all
    -- three come back secret. "/bish regen" printed exactly that, twice.
    _G.GetManaRegen = function() return 16.88, 10.44 end     -- 62%, read while standing about
    _G.GetPowerRegenForPowerType, _G.GetPowerRegen = nil, nil
    FR.known = nil
    ok(FR.Text() == "regen 62%", "read live while it can be", tostring(FR.Text()))  -- no Remember()
    _G.GetManaRegen = function() return secret(), secret() end        -- and now the pull starts
    ok(FR.Live() == nil, "in the fight the client says nothing")
    local f, remembered = FR.Fraction()
    ok(f and math.abs(f - 0.62) < 0.01 and remembered == true,
       "so the share is the one it last told us", tostring(f))
    ok(FR.Text() == "regen 62%", "and the header says it plainly", tostring(FR.Text()))
    ok(pcall(FG.PaintRegen, h), "and the header survives it")

    -- with nothing ever read, it still says which mode it is in rather than inventing a number
    FR.known = nil
    ok(FR.Fraction() == nil and FR.Text() == "regen ?",
       "with nothing ever read, no number is invented", tostring(FR.Text()))
    _G.GetManaRegen = nil
    ok(FR.Fraction() == nil, "nor does a client with none of the calls at all")

    _G.GetManaRegen, _G.C_Spell.GetSpellPowerCost = realRegen, realCost
    _G.GetPowerRegen, _G.GetPowerRegenForPowerType = realPower, realForType
    FR.spentAt = nil
    FG.PaintRegen(h)
end

-- THE BUFF YOU KEEP FORGETTING. Arn, 23 Sep: "for our healers can we add to the header their main
-- healing buffs on themselves. like i am always forgetting about watershield ... can the header say
-- in and out of combat. missing water shield". Your own buffs read out of combat and are secret in
-- a fight, so what the client last said is what the header shows.
do
    local FS, FA_AURAS = NS.FS, nil
    local d = NS.DB()
    d.selfBuffs = nil
    BOOK[21] = { name = "Water Shield", rank = "Rank 1" }        -- this shaman has trained it
    local realClass = _G.UnitClass
    _G.UnitClass = function() return "Shaman", "SHAMAN" end
    local mine = {}                                              -- the buffs on the player
    local realAuras = _G.C_UnitAuras
    _G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
        if STATE.inCombat then error("Auras cannot be accessed when secret while tainted", 2) end
        if unit ~= "player" or filter ~= "HELPFUL" then return nil end
        return mine[i]
    end }

    ok(table.concat(FS.List(), ",") == "Water Shield", "a shaman watches Water Shield",
       table.concat(FS.List(), ","))
    local missing, readable = FS.Missing()
    ok(readable and missing and missing[1] == "Water Shield",
       "with nothing on you, it is missing", missing and missing[1])
    FS.Check()
    ok(FS.Word() == "no Water Shield", "and the header says so", tostring(FS.Word()))
    ok(FG.HeaderWord() == "no Water Shield", "instead of the addon's name", FG.HeaderWord())
    -- and on a bar one cell wide, where the whole name would be trimmed to "no Water Shi..."
    ok(FS.Initials("Water Shield") == "WS" and FS.Initials("Omen of Clarity") == "OoC",
       "a long name comes down to its initials", FS.Initials("Omen of Clarity"))
    ok(FG.HeaderWord(84) == "no WS", "so a party grid says 'no WS' rather than half a name",
       FG.HeaderWord(84))
    ok(FG.HeaderWord(200) == "no Water Shield", "and a raid-wide bar says all of it",
       FG.HeaderWord(200))

    mine[1] = { name = "Water Shield" }
    FS.Check()
    ok(FS.Word() == nil and FG.HeaderWord() == "Healing", "up, and the header goes back to normal")

    -- IN A FIGHT the client says nothing, so what it last said stands - and a check made during
    -- the fight must not overwrite it with "nothing missing"
    mine[1] = nil
    FS.Check()                                                   -- read while standing about
    STATE.inCombat = true
    local _, readableNow = FS.Missing()
    ok(readableNow == false, "in the fight the client will not say")
    mine[1] = { name = "Water Shield" }                           -- and it cannot see this either
    FS.Check()
    ok(FS.Word() == "no Water Shield",
       "a check made in the fight changes nothing: what it last knew is what is shown",
       tostring(FS.Word()))
    STATE.inCombat = false
    FS.Check()
    ok(FS.Word() == nil, "and the moment the fight ends it reads again")
    mine[1] = nil
    FS.Check()

    -- an aura it cannot read is not proof that nothing is missing: a secret NAME in the list
    -- means the whole read is unreliable, so the last known answer stands
    mine[1] = { name = "Water Shield" }
    FS.Check()
    ok(FS.Word() == nil, "with the shield up, nothing is missing")
    mine[1] = { name = secret() }
    local m2, readable2 = FS.Missing()
    -- THE CONTRACT CHANGED ON 25 SEP, and this is the change: it used to answer `nil, false` - no
    -- news at all - the moment one buff came back unreadable, which threw away the answers about
    -- every other. Now it answers with what it DID learn and a flag saying the list is not whole.
    -- What must never change: a buff the client would not talk about is never called missing.
    ok(type(m2) == "table" and #m2 == 0 and readable2 == false,
       "a name the client hides is not 'missing' - and the list says it is not whole",
       tostring(m2) .. " / " .. tostring(readable2))
    FS.Check()
    ok(FS.Word() == nil, "so the last answer stands, rather than a guess at what is missing")
    mine[1] = nil
    FS.Check()
    ok(FS.Word() == "no Water Shield", "and a real read says what is missing again",
       tostring(FS.Word()))

    -- a spell this character has not trained is never mentioned. The Earth Shield mistake, 19 Sep:
    -- a level 15 shaman told six times in ninety seconds about a spell learned at 50.
    BOOK[21] = nil
    FS.Check()
    ok(FS.Word() == nil, "a buff you have not trained is not a buff you forgot", tostring(FS.Word()))
    BOOK[21] = { name = "Water Shield", rank = "Rank 1" }

    -- ASKED ABOUT ONE AURA, BY ID (read off Overlord 1.0.16, 24 Sep 2026). The walk above compares
    -- NAMES, and a name is the first thing this client hides; these two calls need none.
    --
    -- The mock is as unkind as the client: the lookup THROWS when the aura is secret and is not
    -- asked about first, the aura table it hands back can be one that may not be read, and
    -- ShouldSpellAuraBeSecret can answer with a secret of its own.
    do
        local hidden, up = {}, {}                    -- spellID -> is it secret / is it on you
        local auras = _G.C_UnitAuras
        local realSecrets, asked = _G.C_Secrets, {}
        _G.C_Secrets = setmetatable({
            ShouldSpellAuraBeSecret = function(id)
                asked[id] = (asked[id] or 0) + 1
                return hidden[id] and true or false
            end,
        }, { __index = realSecrets })
        auras.GetPlayerAuraBySpellID = function(id)
            -- the client does not hand a secret aura to somebody who did not ask first
            if hidden[id] then error("aura is secret", 2) end
            return up[id] or nil
        end
        local realInfo = _G.C_SpellBook.GetSpellBookItemInfo
        _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
            if type(bank) ~= "number" then error("bad argument", 2) end
            return n == 21 and { spellID = 24398 } or nil
        end

        FS.state, FS.known = {}, nil
        FS.Check()
        ok(asked[24398] and asked[24398] > 0, "the client is asked about that one aura first")
        ok(FS.Word() == "no Water Shield", "and with it off, the header says so", tostring(FS.Word()))

        up[24398] = { name = "Water Shield", spellId = 24398 }
        FS.Check()
        ok(FS.Word() == nil, "with it on, nothing is missing")

        -- IN A FIGHT. This is the whole point of asking per spell: the blanket question says no to
        -- everything inside the lockdown, so the reminder has only ever worked between pulls. If
        -- the client will still answer about THIS aura, the answer is current.
        STATE.inCombat = true
        up[24398] = nil
        FS.Check()
        ok(FS.Word() == "no Water Shield",
           "a buff the client will still talk about mid-fight is answered mid-fight",
           tostring(FS.Word()))

        -- and when it will not talk about it, the last answer stands - never "missing"
        up[24398] = { name = "Water Shield" }
        FS.Check()
        hidden[24398] = true
        FS.Check()
        ok(FS.Word() == nil, "a buff it has gone quiet about keeps what it last was",
           tostring(FS.Word()))
        local before = asked[24398]
        FS.Check()
        ok(pcall(FS.Check), "and the lookup is never made on a secret aura, so nothing throws")
        ok(asked[24398] > before, "because the question is asked every time, not cached")
        hidden[24398] = false
        STATE.inCombat = false

        -- AN AURA TABLE THAT MAY NOT BE READ is not an aura that is missing. canaccessvalue is
        -- what Overlord asks of the table itself - issecretvalue is not for tables.
        local realAccess = _G.canaccessvalue
        up[24398] = nil
        FS.state, FS.known = {}, nil
        FS.Check()
        ok(FS.Word() == "no Water Shield", "it is missing, plainly")
        up[24398] = { name = "Water Shield" }
        _G.canaccessvalue = function() return false end
        FS.state, FS.known = {}, nil
        FS.Check()
        -- ASKED OF FS.Present, NOT OF THE HEADER. "Unknown" and "it is on you" both leave the
        -- header saying nothing, so the header cannot tell them apart - and a test that cannot
        -- tell them apart passes with the guard deleted. This one names the state.
        ok(FS.Present("Water Shield") == nil,
           "a table the client will not let us read is UNKNOWN, not 'on you'",
           tostring(FS.Present("Water Shield")))
        ok(FS.Word() == nil, "so the header says nothing rather than something made up")
        _G.canaccessvalue = realAccess
        ok(FS.Present("Water Shield") == true, "and with the guard answering yes, it is on you")

        -- A BOOK WITH NO IDS STILL HAS TO ANSWER. The by-id call exists on this client, but the
        -- spellbook can name a spell and refuse its id - which is the ordinary state at login,
        -- before the book has filled in. The old walk is the answer then, not "cannot say".
        _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
            if type(bank) ~= "number" then error("bad argument", 2) end
            return nil                                    -- named, but no id
        end
        -- ON you, so the two answers differ: the walk says "up", and skipping the walk entirely
        -- says "missing" - which is the lie this is here to catch. A test with the buff OFF gets
        -- the same word out of both and proves nothing.
        mine[1] = { name = "Water Shield" }
        FS.state, FS.known = {}, nil
        ok(FS.Present("Water Shield") == true,
           "with no spell id to ask about, the old walk still answers",
           tostring(FS.Present("Water Shield")))
        mine[1] = nil
        FS.state, FS.known = {}, nil
        FS.Check()
        ok(FS.Word() == "no Water Shield", "and still says what is missing that way",
           tostring(FS.Word()))
        _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
            if type(bank) ~= "number" then error("bad argument", 2) end
            return n == 21 and { spellID = 24398 } or nil
        end

        -- a secret ANSWER to "is it secret?" is itself an unknown, not a no
        _G.C_Secrets.ShouldSpellAuraBeSecret = function() return secret() end
        ok(FS.Present("Water Shield") == nil,
           "a secret answer about secrecy is unknown, not permission")
        _G.C_Secrets.ShouldSpellAuraBeSecret = function() error("no such call", 2) end
        ok(FS.Present("Water Shield") == nil, "and so is an error")

        _G.C_Secrets = realSecrets
        _G.C_SpellBook.GetSpellBookItemInfo = realInfo
        auras.GetPlayerAuraBySpellID = nil
        FS.state, FS.known = {}, nil
        FS.Check()
    end

    -- TAKING A BUFF OFF THE LIST FORGETS WHAT IT WAS. The memory is per name and outlives the
    -- answer that filled it, so a name that comes back after being taken off would arrive with
    -- its old verdict already in place - "no Water Shield" from ten minutes ago, before the
    -- client has been asked once about it.
    do
        local auras = _G.C_UnitAuras
        local realWalk = auras.GetAuraDataByIndex
        mine[1] = nil
        FS.state, FS.known = {}, nil
        FS.Check()
        ok(FS.Word() == "no Water Shield", "it is missing, and remembered as missing")
        -- ONE call: the class default becomes an explicit list holding the same name. Two calls
        -- would take it off again and leave NOTHING watched, where every answer is nil and the
        -- test proves nothing - which is exactly what the first draft of this did.
        -- FS.Add, not the slash command: /bish buff prints a report, and the report asks the
        -- client again on its way past - so the verdict is back before the silence begins and
        -- the forgetting is invisible. (The sound tests learned this the same way.)
        FS.Add("Water Shield")
        auras.GetAuraDataByIndex = function() error("the client is not answering", 2) end
        FS.Check()
        ok(FS.Word() == nil,
           "a change to the list forgets the verdict, and a silent client does not refill it",
           tostring(FS.Word()))
        -- AND THE SILENCE ITSELF IS NOT AN ANSWER. A client that throws on the first aura slot
        -- used to walk out of the loop and report an empty aura bar, which reads as every watched
        -- buff missing.
        ok(FS.Present("Water Shield") == nil,
           "a client that refuses the walk is unknown, not an empty aura bar",
           tostring(FS.Present("Water Shield")))
        auras.GetAuraDataByIndex = realWalk
        NS.DO.buff("reset")
        FS.state, FS.known = {}, nil
        FS.Check()
    end

    -- the player's own list: add, take away, reset
    NS.DO.buff("Lightning Shield")
    ok(table.concat(FS.List(), ",") == "Lightning Shield", "/bish buff <name> watches it instead",
       table.concat(FS.List(), ","))
    NS.DO.buff("Lightning Shield")
    ok(#FS.List() == 0, "the same name again stops watching it", #FS.List())
    NS.DO.buff("reset")
    ok(table.concat(FS.List(), ",") == "Water Shield", "and reset goes back to the class's one")

    -- A SOUND WHEN IT DROPS, played by the client. The header cannot say it mid-fight - your own
    -- buffs are secret there - but C_UnitAuras.AddAuraSound makes a noise without anything being
    -- read. Registered per spell id, so every rank is covered, and taken down when the list changes.
    local registered, removed, nextID = {}, {}, 0
    local auras = _G.C_UnitAuras
    auras.AddAuraSound = function(trigger, opts)
        if type(opts) ~= "table" or not opts.spellID then return nil end
        nextID = nextID + 1
        registered[nextID] = { trigger = trigger, spellID = opts.spellID, unit = opts.unitToken,
                               file = opts.soundFileID or opts.soundFileName }
        return nextID
    end
    auras.RemoveAuraSound = function(id) removed[id] = true; registered[id] = nil end
    local realEnum = _G.Enum
    _G.Enum = setmetatable({ UnitAuraSoundTrigger = { Added = 1, Removed = 2 } },
                           { __index = realEnum })
    BOOK[22] = { name = "Water Shield", rank = "Rank 2" }      -- two ranks trained
    local realInfo2 = _G.C_SpellBook.GetSpellBookItemInfo
    _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
        if type(bank) ~= "number" then error("bad argument", 2) end
        if n == 21 then return { spellID = 24398 } end
        if n == 22 then return { spellID = 24399 } end
        return nil
    end

    local howMany = FS.Sounds()
    ok(howMany == 2, "both ranks of the buff are registered", tostring(howMany))
    local trig, whose, ids = nil, nil, {}
    for _, r in pairs(registered) do trig, whose = r.trigger, r.unit; ids[r.spellID] = true end
    ok(trig == 2 and whose == "player", "for when it LEAVES you, on you", tostring(trig))
    ok(ids[24398] and ids[24399], "one for each rank")

    -- changing the list takes the old registrations down. FS.Add, not the slash command: that
    -- prints a report which asks for the sounds anyway, and would hide a missing refresh here.
    FS.Add("Lightning Shield")
    local live = 0
    for _ in pairs(registered) do live = live + 1 end
    ok(next(removed) ~= nil and live == 0,
       "watching something else removes the old sounds rather than leaving them playing", live)
    FS.Reset()

    -- switched off, and a client without the call: both quiet, neither an error
    NS.DO.buffsound("off")
    ok(FS.Sounds() == false, "off registers nothing")
    NS.DO.buffsound("on")

    -- THE SWITCH AND THE NUMBER ARE TWO QUESTIONS (Arn, 23 Sep: "toggle in options to turn sound
    -- on or off and unrolled window to put in another sound id number"). They were one field to
    -- begin with, where `false` meant silence - so switching the sound off and on again threw the
    -- player's number away, silently, and left them with ours.
    NS.DO.buffsound("31578")
    ok(d.buffSound == 31578 and FS.File() == 31578, "a number sets which sound", tostring(d.buffSound))
    NS.DO.buffsound("off")
    NS.DO.buffsound("on")
    ok(d.buffSound == 31578 and not FS.Quiet(),
       "off and on again keeps the number the player typed", tostring(d.buffSound))
    local withTheirs = nil
    for _, r in pairs(registered) do withTheirs = r.file end
    ok(withTheirs == 31578, "and the client is asked to play THEIR number, not ours",
       tostring(withTheirs))
    NS.DO.buffsound("default")
    ok(d.buffSound == nil and FS.File() == FS.SOUND, "default goes back to ours", tostring(d.buffSound))

    -- HEARD BEFORE IT IS KEPT. A file id is a number out of the game's own files and a player
    -- typing one has no other way to know they got it right - and a wrong one must say so rather
    -- than look like it worked.
    local n0 = #STATE.played
    ok(FS.Play(567458) == true and #STATE.played == n0 + 1, "hear plays the id")
    -- the one we ship, played with no argument at all: a default nobody can hear is a default
    -- nobody chose. This one Arn chose by ear (567474, 23 Sep) after listening to 567458.
    ok(FS.Play() == true and STATE.played[#STATE.played].file == FS.SOUND,
       "and with nothing typed it plays the one we ship", tostring(FS.SOUND))
    ok(STATE.played[#STATE.played].channel == "Master", "on the master channel, so it is audible")
    local played, whyNot = FS.Play(4242)
    ok(played == false and tostring(whyNot):find("id"),
       "an id this client has not got says so rather than reporting success", tostring(whyNot))
    local pathOk, pathWhy = FS.Play("Interface\\Sounds\\Alarm.ogg")
    ok(pathOk == false and tostring(pathWhy):find("sound id"),
       "and a file PATH is called what it is on this client: silent", tostring(pathWhy))

    auras.AddAuraSound = nil
    local none, why = FS.Sounds()
    ok(none == false and tostring(why):find("no aura sounds"),
       "a client without the call says so rather than throwing", tostring(why))

    _G.Enum = realEnum
    BOOK[22] = nil
    _G.C_SpellBook.GetSpellBookItemInfo = realInfo2
    _G.C_UnitAuras, _G.UnitClass = realAuras, realClass
    d.selfBuffs, d.buffSound, d.buffQuiet = nil, nil, false
    FS.known, FS.soundIDs = nil, {}
end

-- AND IT SURVIVES A RESTART, which on this client means the macro. Saved variables never come
-- back on Forever, so a sound switched off at midnight is on again at the next login unless it
-- rides in the same 255 characters as everything else.
do
    local FK, d = NS.FK, NS.DB()
    local body = FK.Encode({}, { sound = 31578, quiet = true })
    ok(body:find("N=31578:1"), "the id AND the switch go into one row", body)
    local _, back = FK.Decode(body)
    ok(back.sound == 31578 and back.quiet == true, "and both come back",
       tostring(back.sound) .. "/" .. tostring(back.quiet))

    -- OFF WITH OUR OWN SOUND BEHIND IT. "N=0" is the id nobody chose; the 1 is what silence is.
    local _, quietOnly = FK.Decode(FK.Encode({}, { quiet = true }))
    ok(quietOnly.sound == nil and quietOnly.quiet == true, "silence with no number of its own")

    -- A MACRO THAT SAYS NOTHING ABOUT THE SOUND LEAVES IT ALONE. `quiet` is nil, not false: the
    -- difference between "the player wants it on" and "the player never touched it".
    local _, silent = FK.Decode(FK.Encode({}, { scale = 1.2 }))
    ok(silent.quiet == nil, "an untouched macro has no opinion about the sound", tostring(silent.quiet))

    -- THE COLD START. Nobody clicks anything at login, so what the macro holds has to be LIVE
    -- after the read: the setting back in the table AND the client asked to make the noise again.
    -- A sound that only arms itself at the next SPELLS_CHANGED is a sound that misses the pull.
    local FM = NS.FM
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = { ["wheelup"] = "Healing Wave(Rank 2)" }, true, false, nil
    NS.DO.buffsound("31578")
    NS.DO.buffsound("off")
    local stored = GetMacroBody(GetMacroIndexByName(FK.MACRO))
    ok(stored and stored:find("N=31578:1", 1, true), "changing it writes it into the macro", stored)

    local asked, realSounds = 0, NS.FS.Sounds
    NS.FS.Sounds = function() asked = asked + 1 return 0 end
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false                       -- the restart
    d.buffSound, d.buffQuiet = nil, false
    FM.Get("", "wheelup")
    ok(d.buffSound == 31578 and d.buffQuiet == true,
       "and after a restart the sound is what the macro said",
       tostring(d.buffSound) .. " / " .. tostring(d.buffQuiet))
    ok(asked > 0, "the client is asked to play it again at login, not at the next spell change", asked)
    NS.FS.Sounds = realSounds

    d.buffSound, d.buffQuiet = nil, false
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")
end

-- THE HANDLE. Arn, 19 Sep 2026: "lets add a our header to this so we can drag and move". The
-- anchor had none: the cells were the only thing on screen, and a secure button cannot be dragged
-- without taking its click away. So the header moves the ANCHOR and every cell follows.
do
    local h = FG.header
    ok(h ~= nil, "the grid has a header to grab")

    -- LABELS IN THE BAR MUST NOT SHARE A SIDE. Twice in one day a second FontString printed
    -- straight through the first: "BiS> Hrsalinge" on an 84 pixel header. The rule was "one
    -- label", which held until the five second rule earned a number of its own (23 Sep) - so the
    -- rule is the one that actually mattered: the prompt is pinned LEFT, anything else RIGHT, and
    -- a hint still belongs in a tooltip where it costs no pixels at all.
    ok(#(h.__fontstrings or {}) <= 1,
       ("the header carries %d labels; one bar, one label - a second one printed through the first"
        .. " twice in one day, and again on 23 Sep"):format(#(h.__fontstrings or {})))

    -- ONE THING IN THE BAR. A "drag" caption on the right printed straight through the prompt's
    -- rotating word on a header the width of one cell: "BiS> Hrsalinge" (seen in game, 19 Sep).
    -- The hint is a tooltip now, and the prompt is trimmed to the header it is in.
    FG.Layout(anchor)
    ok(h.con == nil or h.con.width <= FRAME_W_FOR_TEST,
       "the prompt is trimmed to the header's own width, not 120px")
    ok(h.__scripts.OnEnter and h.__scripts.OnLeave, "the hint lives in a tooltip instead")

    -- ONE WORD, so nothing can print through anything: the prompt says "Healing" while nothing is
    -- happening and the regen share in a fight (FG.HeaderWord). The two-label version lasted one
    -- screenshot - "BiS>Healing" over "regen 62%" on a party grid, 23 Sep.
    ok(#(h.__fontstrings or {}) <= 1, ("the header is back to %d label")
       :format(#(h.__fontstrings or {})))

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
-- FORMATS LIKE THE REAL ONE. The stub used to take one argument and drop the rest - the same lie
-- NS.Print itself was telling - so `Print("asking: %s", call)` looked fine here and printed a
-- literal "%s" in Arn's chat frame for two days (30 Sep).
NS.Print = function(msg, ...)
    local text = tostring(msg)
    if select("#", ...) > 0 then
        local ok, made = pcall(string.format, text, ...)
        if ok then text = made end
    end
    SAID[#SAID + 1] = text
end

STATE.inCombat = true
local blindScan, why = FB.Scan()
ok(blindScan == nil and why ~= nil, "the brain refuses to scan inside the lockdown")
STATE.inCombat = false

-- THIS CHARACTER HAS THE WATCHED BUFF, and is in a group. Both matter: the brain does not nag
-- about a spell you have not trained (a level-15 shaman grinding leather was told six times in
-- ninety seconds that it was not up), and it says nothing at all when you are playing alone.
--
-- The spell is CHOSEN now rather than hardcoded (1 Oct 2026). It was "Earth Shield", which does
-- not exist on a 1.60 client - so the check it guards could never run, and these tests were the
-- only place it ever did. Nothing is watched until the player says so.
BOOK[20] = { name = "Lightning Shield", rank = "Rank 1" }
NS.DB().groupBuff = "Lightning Shield"
local GROUPED = true
_G.IsInGroup = function() return GROUPED end

-- nothing up: the watched buff missing and no totems out, both worth saying between pulls
local found = FB.Scan()
local kinds = {}
for _, f in ipairs(found) do kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
ok(kinds.groupbuff == 1, "a missing watched buff is reported")
ok(kinds.totems == 1, "four empty totem slots are reported")

-- CAN THE AURA LIST BE WALKED AT ALL? The client answers that by throwing, not by saying so:
-- EllesmereUI 9.3's AuraKit probes one slot and catches the refusal, because the index walk
-- hard-errors under instance restrictions even where ShouldAurasBeSecret answers no.
do
    local realGet = _G.C_UnitAuras.GetAuraDataByIndex
    ok(NS.Restricted() == false, "with the client answering, the list can be walked")
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("aura access denied here", 2) end
    ok(NS.Restricted() == true, "and when it throws, that is the answer")
    -- THE CLEAR ANSWER IS NEVER CACHED. A stale "you may walk" sends the next caller into a scan
    -- that throws; a stale "you may not" costs one frame of a display nobody was watching. So the
    -- restriction is remembered for the frame and the permission is asked again every time.
    _G.C_UnitAuras.GetAuraDataByIndex = realGet
    ok(NS.Restricted() == true,
       "the refusal is remembered for the rest of the frame - building that error is the cost")
    TICK()
    ok(NS.Restricted() == false,
       "and the next frame asks again, rather than holding the refusal over")
    -- AND PERMISSION IS NEVER CACHED, even for the frame it was given in: restriction engages
    -- mid-frame at a zone edge, and a held-over "you may walk" is what sends the next caller into
    -- a scan that throws.
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("aura access denied here", 2) end
    ok(NS.Restricted() == true,
       "restriction arriving inside the same frame is noticed at once")
    _G.C_UnitAuras.GetAuraDataByIndex = realGet
    TICK()
end

-- A CLIENT THAT REFUSES THE AURA LIST IS NOT A RAID WITH NO BUFFS ON IT. Read off EllesmereUI 9.3
-- on 28 Sep: the index walk hard-errors under instance restrictions even out of combat, where
-- ShouldAurasBeSecret still answers no. The walk broke out of its loop on the error and handed
-- back an empty list, which is indistinguishable from "nobody has it" - and that one gets printed
-- in chat. "<buff> is not up on anyone", to a raid where it was up the whole time.
do
    local realGet = _G.C_UnitAuras.GetAuraDataByIndex
    _G.C_UnitAuras.GetAuraDataByIndex = function() error("aura access denied here", 2) end
    local refusedScan = FB.Scan()
    local said = {}
    for _, f in ipairs(refusedScan or {}) do said[f.kind] = true end
    ok(not said.groupbuff,
       "a refused aura list is never reported as a missing watched buff")
    ok(not said.dispel, "and never as somebody standing there with a debuff on them")
    _G.C_UnitAuras.GetAuraDataByIndex = realGet
    -- and with the client answering again, the report comes back rather than staying quiet
    local backScan = FB.Scan()
    local kinds2 = {}
    for _, f in ipairs(backScan or {}) do kinds2[f.kind] = true end
    ok(kinds2.groupbuff, "and when the client answers again, so does the brain")
end

-- with the watched buff up on the tank, it stops nagging
AURAS.party1.HELPFUL[1] = { name = "Lightning Shield", dispelName = nil }
TOTEMS[1] = true
found = FB.Scan()
kinds = {}
for _, f in ipairs(found) do kinds[f.kind] = (kinds[f.kind] or 0) + 1 end
ok(kinds.groupbuff == nil, "the watched buff up on anyone is enough")
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

-- QUIET BY DEFAULT SINCE 23 SEP. Arn: "lets get rid of the reminders in the chat window that was
-- from tbc version ... lets put it away for now". They were written for a TBC shaman; on this
-- client they arrive between pulls knowing half of what they used to.
SAID = {}
ok(select(1, FB.Report()) == 0 and #SAID == 0,
   "with the reminders off, a fight ending says nothing at all")
ok(FB.Report(true) ~= 0 and #SAID > 0, "/bish scan still asks outright")
ok(NS.DO.between(true) == true, "/bish between turns them back on")

-- it speaks only when there is something to say
SAID = {}
FB.lastSig = nil
local n = FB.Report()
ok(n and n > 0 and #SAID == n, "Report says one line per finding")
ok(not tostring(SAID[1]):find("BiS Healing", 1, true),
   "and does NOT write its own name: NS.Print already does that")

-- THE SAME NEWS IS NOT NEWS. The screenshot that started this had one line six times in ninety
-- seconds, once per mob killed. A finding that has not changed is said again only after QUIET.
SAID = {}
ok(FB.Report() == 0 and #SAID == 0, "the same findings a moment later are not repeated")
ok(FB.Report(true) ~= 0 and #SAID > 0, "unless asked for outright (/bish scan)")

-- OUT OF COMBAT IS NOT "EVERYTHING READS". Arn, 21 Sep, in a dungeon, two seconds after a pull:
-- "attempt to perform boolean test on local 'have' (a secret boolean value)" from GetTotemInfo.
-- The brain asks the client whether auras are hidden (as ForeverAuras does), and guards every
-- value it reads even when the client says no.
do
    local realSecrets = _G.C_Secrets
    _G.C_Secrets = setmetatable({ ShouldAurasBeSecret = function() return true end },
                                { __index = realSecrets })
    local s, w = FB.Scan()
    ok(s == nil and tostring(w):find("hiding"), "out of combat, the client saying auras are hidden is enough", tostring(w))
    _G.C_Secrets.ShouldAurasBeSecret = function() return secret() end
    ok(NS.Blind() == true, "and an answer that is itself secret counts as hidden")
    _G.C_Secrets.ShouldAurasBeSecret = function() error("no", 2) end
    ok(NS.Blind() == true, "as does one that errors")
    _G.C_Secrets = realSecrets
    ok(NS.Blind() == false, "and back in the open world, it scans again")

    -- the client says auras are fine, and a single value comes back secret anyway: the crash
    local realTotem, realDead = _G.GetTotemInfo, _G.UnitIsDeadOrGhost
    _G.GetTotemInfo = function() return secret(), secret() end
    _G.UnitIsDeadOrGhost = function() return secret() end
    AURAS.party2.HARMFUL[3] = { name = secret(), dispelName = secret() }
    AURAS.party1.HELPFUL[1] = { name = secret() }
    local ran, got = pcall(FB.Scan)
    ok(ran, "a secret totem, dead flag and aura do not throw the scan: " .. tostring(got))
    local kinds2 = {}
    for _, f in ipairs(ran and got or {}) do kinds2[f.kind] = true end
    ok(not kinds2.totems, "a totem it cannot see is not reported as missing")
    ok(FB.totemsKnown == 0, "and all four are counted as unknown - never put in an `if`",
       tostring(FB.totemsKnown))
    ok(not kinds2.dead, "nobody is called dead on a flag it cannot read")
    ok(not kinds2.groupbuff, "and an unreadable buff is not called a missing one")
    ok(pcall(FB.Dump), "/bish scan's dump survives them too")
    _G.GetTotemInfo, _G.UnitIsDeadOrGhost = realTotem, realDead
    AURAS.party2.HARMFUL[3] = nil
    AURAS.party1.HELPFUL[1] = { name = "Earth Shield", dispelName = nil }

    -- a hidden NAME: the cell paints it whole; nothing tries to cut it
    local realName = _G.UnitName
    _G.UnitName = function() return secret() end
    local r2, nm = pcall(FG.ShortName, "party1")
    ok(r2 and getmetatable(nm) == secretMeta, "a hidden name goes to the cell whole, not cut")
    _G.UnitName = realName
end

-- ALONE, IT SAYS NOTHING AT ALL. This is a brain for a group: who still has a debuff, who is
-- dead, whether the shield is up. Solo there is nobody to tell.
SAID = {}
GROUPED = false
FB.lastSig = nil                                  -- as if the news had changed
local quiet, reason = FB.Report()
ok(quiet == 0 and reason == "alone" and #SAID == 0, "playing alone, it stays quiet")
GROUPED = true
FB.lastSig = nil
NS.DO.between(false)                              -- back to the shipped default: quiet
ok(NS.DB().between == false and select(1, FB.Report()) == 0, "and off again is the default")
NS.DO.between(true)

-- and a character who has not trained Earth Shield is never told it is missing
BOOK[20] = nil
local noES = FB.Scan()
local mentions = 0
for _, f in ipairs(noES) do if f.kind == "groupbuff" then mentions = mentions + 1 end end
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
    ok(cell.__attrs["*spell1"] == nil,
       "clearing a slot removes the spell rather than leaving a dead one")
    -- AN EMPTY BUTTON TARGETS. A player's request (22 Sep): "if a key is not bound to anything on
    -- the mouse that defaults to target". The client's own secure "target" action, so a fight
    -- does not stop it.
    ok(cell.__attrs["*type1"] == "target", "and the cleared button now targets the person",
       tostring(cell.__attrs["*type1"]))
    ok(cell.__attrs["alt-type2"] == "target" and cell.__attrs["alt-spell2"] == nil,
       "empty right click targets too, with a modifier")
    -- BUTTONS 3-5 ARE DIFFERENT. Measured on the beta (22 Sep): an empty thumb or wheel click set to
    -- type "target" did nothing - the SecureUnitButton path honours "target" for buttons 1-2 only -
    -- while a spell bound to the same button cast. So 3-5 target through a secure macro instead.
    for _, b in ipairs({ 3, 4, 5 }) do
        for _, p in ipairs({ "*", "shift-", "ctrl-", "alt-" }) do
            if not FM.Get(p == "*" and "" or p, ({ [3] = "middle", [4] = "button4", [5] = "button5" })[b]) then
                ok(cell.__attrs[p .. "type" .. b] == "macro"
                   and cell.__attrs[p .. "macrotext" .. b] == "/target [@mouseover]",
                   ("empty %stype%d targets by macro, not the 'target' type the client ignores there"):format(p, b),
                   tostring(cell.__attrs[p .. "type" .. b]))
            end
        end
    end
    ok(cell.__attrs["*macrotext1"] == nil and cell.__attrs["*macrotext2"] == nil,
       "buttons 1-2 keep the built-in target, with no macro on them")
    FM.Set("", "button4", "Healing Wave(Rank 1)")
    FM.ApplyTo(cell)
    ok(cell.__attrs["*type4"] == "spell" and cell.__attrs["*macrotext4"] == nil,
       "a spell dropped on a thumb button replaces the target macro, and none is left behind")
    FM.Clear("", "button4")
    FM.Set("", "left", "Healing Wave(Rank 1)")
    FM.ApplyTo(cell)
    ok(cell.__attrs["*type1"] == "spell" and cell.__attrs["*spell1"] == "Healing Wave(Rank 1)",
       "and a bound button still casts")

    -- LET CLIQUE HAVE THEM. Arn, 22 Sep: "im a clique user and it uses all of theirs". One owner:
    -- switched on, nothing of ours is left on the cell and the cell is in ClickCastFrames.
    -- The registry behaves like Clique v5.1's (core.lua): nil or false unregisters.
    local realCCF = _G.ClickCastFrames
    local registered = {}
    _G.ClickCastFrames = setmetatable({}, { __newindex = function(_, k, v)
        if v == nil or v == false then registered[k] = nil else registered[k] = true end
    end })
    local d = NS.DB()
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { left = "Healing Wave(Rank 1)", wheelup = "Healing Wave(Rank 2)" }
    NS.DO.clique(true)
    FM.ApplyTo(cell)
    local ours = 0
    for k, v in pairs(cell.__attrs) do
        if (k:find("type%d$") or k:find("spell%d$") or k:find("macrotext%d$")) and v ~= nil then ours = ours + 1 end
    end
    ok(ours == 0, "with Clique on, none of our click attributes are left on the cell", ours)
    ok(registered[cell] == true, "and the cell is registered with Clique")
    local wheelBound = false
    for key in pairs(BOUND) do if key:find("MOUSEWHEEL") then wheelBound = true end end
    ok(not wheelBound, "and the wheel is let go too")
    local stored = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(stored and stored:find("K=1", 1, true), "Clique mode is kept in the macro", stored)
    local _, st = NS.FK.Decode(stored or "")
    ok(st and st.clique == true, "and reads back")

    NS.DO.clique(false)
    FM.ApplyTo(cell)
    ok(registered[cell] == nil, "switched off, the cell is unregistered")
    ok(cell.__attrs["*type1"] == "spell" and cell.__attrs["*spell1"] == "Healing Wave(Rank 1)",
       "and our binds are back on it")
    stored = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(stored and not stored:find("K=", 1, true), "and off - the default - writes nothing")

    -- no click-cast addon at all: switching on still leaves one clean owner, and nothing throws
    _G.ClickCastFrames = nil
    ok(pcall(NS.DO.clique, true) and pcall(FM.ApplyTo, cell), "with no Clique loaded, it does not throw")
    ok(type(_G.ClickCastFrames) == "table" and _G.ClickCastFrames[cell] == true,
       "and the cell waits in the list for Clique to pick up when it loads")
    NS.DO.clique(false)
    FM.ApplyTo(cell)
    ok(_G.ClickCastFrames[cell] == nil,
       "off removes it outright - Clique would register a leftover `false` when it loads")

    _G.ClickCastFrames = realCCF
    d.binds = keptBinds
    MACROS = {}
    FM.ApplyTo(cell)
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

        -- NOT IN COMBAT. SetPropagateKeyboardInput is protected in the lockdown - the client
        -- blocked it with a popup when Arn pressed a key mid-pull (21 Sep). The mock blocks it the
        -- same way: it counts, and the check is that nothing was ever asked of it in a fight.
        local blocked, realProp = 0, w.SetPropagateKeyboardInput
        w.SetPropagateKeyboardInput = function(self, on)
            if InCombatLockdown() then blocked = blocked + 1; return end
            self.__propagate = on
        end
        STATE.inCombat = true
        w:Show()
        w.__scripts.OnKeyDown(w, "A")
        w.__scripts.OnKeyDown(w, "ESCAPE")
        ok(blocked == 0, "no protected keyboard call in combat", blocked)
        ok(w:IsShown() == false, "and Escape still closes the window mid-fight")
        STATE.inCombat = false
        w.SetPropagateKeyboardInput = realProp

        ok(pcall(FM.Toggle) and pcall(FM.Toggle), "toggling it open and shut does not throw")

        -- THE FIRST CLICK MUST OPEN IT. Arn: "have to click the mouse bind button twice for
        -- window to open". A frame is SHOWN by default in this game, and building the window is
        -- what the first click does - so the first click found a window already "open", hid it,
        -- and looked like nothing happened. This starts from nothing, the way a fresh login does.
        FM.win = nil
        ok(FM.Toggle() == true, "the very first click opens the window")
        ok(FM.Toggle() == false, "and the second one shuts it")
        -- Arn, 22 Sep: "write on the bottom of the window anything not bound targets the unit"
        ok(FM.win and FM.win.targetsNote and FM.win.targetsNote.__text == "anything not bound targets the unit",
           "the window says that an empty button targets", FM.win and FM.win.targetsNote and FM.win.targetsNote.__text)

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
        elseif opt.kind == "cells" then
            -- four switches in one row, each with its own get and set
            for _, part in ipairs(opt.parts) do
                ok(pcall(part.get, NS.DB()), ("reading %q threw"):format(part.key))
            end
        else
            ok(pcall(opt.get, NS.DB()), ("reading %q threw"):format(opt.key))
        end
    end
    for _, want in ipairs({ "shown", "minimap", "mouse", "clique", "layout", "cells",
                            "markers", "buffsound", "buffsoundid" }) do
        ok(keys[want], ("the window lost %q"):format(want))
    end
    -- and every cell the window is supposed to offer is still in that one row
    do
        local parts = {}
        for _, part in ipairs((keys.cells or {}).parts or {}) do parts[part.key] = part end
        for _, want in ipairs({ "target", "tot", "me", "mana" }) do
            ok(parts[want], ("the cells row lost %q"):format(want))
        end
        ok(keys.pets and keys.pets.kind == "seg",
           "and pets is a row of its own, because it has three answers",
           keys.pets and keys.pets.kind)
        -- AND EACH SWITCH READS ITS OWN SETTING. Four buttons side by side in one row is four
        -- chances to wire one to its neighbour's key, and the window would look perfectly
        -- sensible: the wrong button simply lights up.
        local db, was = NS.DB(), {}
        for _, k in ipairs({ "target", "tot", "me", "mana" }) do was[k] = db[k] end
        for _, k in ipairs({ "target", "tot", "me", "mana" }) do db[k] = false end
        for _, k in ipairs({ "target", "tot", "me", "mana" }) do
            db[k] = true
            local lit = {}
            for name, part in pairs(parts) do
                if part.get(db) == true then lit[#lit + 1] = name end
            end
            ok(#lit == 1 and lit[1] == k,
               ("only the %q switch lights for the %q setting"):format(k, k),
               table.concat(lit, ", "))
            db[k] = false
        end
        for _, k in ipairs({ "target", "tot", "me", "mana" }) do db[k] = was[k] end

        -- AND PRESSING ONE CHANGES ITS OWN SETTING. Reading is half the wiring; a `set` pointed at
        -- the neighbour's command looks identical until somebody clicks it.
        -- the window has to be BUILT for there to be a button to press, and the shared lib it is
        -- built from is one the TOC loop above skips
        if not (BiSTheme and BiSTheme.Options) then
            local lib = assert(loadfile("Libs/BiSTheme/Options.lua"))
            ok(pcall(lib), "the shared options lib loads headless")
        end
        NS.CFG.Build()
        local row = NS.CFG and NS.CFG.cells
        ok(row and row.ctl and #row.ctl == 4, "the row has its four buttons", row and #(row.ctl or {}))
        if row and row.ctl then
            for i, part in ipairs(keys.cells.parts) do
                for _, k in ipairs({ "target", "tot", "me", "mana" }) do db[k] = false end
                local click = row.ctl[i].__scripts and row.ctl[i].__scripts.OnClick
                if click then click(row.ctl[i], "LeftButton") end
                ok(db[part.key] == true,
                   ("pressing %q switches %q on"):format(part.label, part.key),
                   tostring(db[part.key]))
            end
            for _, k in ipairs({ "target", "tot", "me", "mana" }) do db[k] = was[k] end
            NS.DO.me(was.me == true)
            FG.Layout(FG.anchor)
        end
    end
    -- 10 -> 12 (20 Sep) -> 13 (23 Sep), each time on purpose and not to make a red line go away.
    -- The last note said the next row was a decision: fold the two diagnostics rather than bump the
    -- number. Both are folded now - "test the debuff marker" went on the 22nd, "what can I see?" on
    -- the 23rd, and each is still one word away (/bish auras, /bish scan). Three of a player's
    -- requests then arrived at once, and two of them are settings: a cell for your target, and the
    -- size of the markers. The third shares the old pyramid row, since "groups: down / across /
    -- tanks" is one question with three answers.
    --
    -- THIRTEEN IS THE LAST ONE. There is nothing left to fold: every row is a setting a player
    -- asked for. The next one costs a real setting, or the window grows a second page.
    --
    -- And on 23 Sep it cost one, as promised. Two rows arrived - the buff-drop sound, and the id
    -- behind it - and "look at the group again" paid for one of them: the grid rescans on every
    -- roster event by itself, so that button was a fix for a bug, not a setting. Then a fifteenth
    -- came the same afternoon and the window grew, which is the other half of the rule.
    --
    -- ON 26 SEP IT CAME BACK DOWN. A fourth cell was asked for (paszczyszyn: one for yourself),
    -- which would have been sixteen rows - and three of the fifteen were the same question asked
    -- three times. "Which extra cells do you want?" is one row of switches. Pets then grew a
    -- third answer the same day and left that row for one of their own, which is what the lib's
    -- `seg` is for. Fourteen, two fewer than the fifteen this window was at when the day started.
    --
    -- The rule was never about the number; it is about a window you can read in one look.
    ok(#NS.UI.Rows() <= 14, "the window stays short: " .. #NS.UI.Rows())

    -- THE DRAWER, where the sound id lives. The shared options lib has four control kinds and no
    -- free-text field, and it is a COPY under Libs\ that the harness compares byte for byte to the
    -- canon - so a number that only this addon wants goes in a panel of its own, underneath.
    do
        local d = NS.DB()
        d.buffSound, d.buffQuiet = nil, false
        -- the shared lib, which the TOC loop skips: the drawer is built out of ITS primitives, so
        -- a suite that fakes them is a suite that proves nothing about the window a player opens
        if not (BiSTheme and BiSTheme.Options) then
            local lib = assert(loadfile("Libs/BiSTheme/Options.lua"))
            local loaded, why = pcall(lib)
            ok(loaded, "the shared options lib loads headless", tostring(why))
        end
        local drawer = NS.UI.Drawer(true)
        ok(drawer ~= nil and drawer:IsShown(), "the sound id drawer unrolls")
        ok(drawer.box ~= nil, "with a box to type a number in")
        ok(drawer.box:GetText() == tostring(NS.FS.SOUND),
           "showing the sound that is actually set", drawer.box:GetText())

        -- typed, then Enter - which is what a player does, and is the client's own script
        drawer.box:__type("31578")
        ok(d.buffSound == 31578, "Enter keeps the number", tostring(d.buffSound))
        ok(drawer.box.__numeric == true and drawer.box.__autofocus == false,
           "digits only, and it does not steal the keyboard when the window opens")

        -- and it closes with the window it hangs off, rather than floating over the game alone
        local win = NS.CFG.frame
        NS.UI.Drawer(true)
        win:Hide()
        local onHide = win.__scripts and win.__scripts.OnHide
        if onHide then onHide(win) end
        ok(not drawer:IsShown(), "closing the options window rolls the drawer up with it")

        d.buffSound, d.buffQuiet = nil, false
    end

    -- and the slash command reaches them. "/bish nonsense" prints the help rather than throwing.
    for _, cmd in ipairs({ "", "show", "hide", "mouse", "rescan", "scan", "auras", "nonsense" }) do
        ok(pcall(SlashCmdList.BISHEALING, cmd), ("/bish %s threw"):format(cmd))
    end
    NS.DO.auras()          -- back off again: the debug marker must not be left on
end

--------------------------------------------- auras asked for by spell id (0.8.0) --
--
-- THE CLIENT THIS MOCKS is the one EllesmereUI and ForeverAuras both describe: in a raid or a
-- dungeon the index walk hard-errors even out of combat, while a by-id lookup still answers. So
-- GetAuraDataByIndex here THROWS and GetUnitAuraBySpellID answers, which is the combination the
-- whole release exists for. A mock where both work would pass without testing anything.
do
    local FB, FG = NS.FB, NS.FG
    local realAuras, realSecrets = _G.C_UnitAuras, _G.C_Secrets
    local realIsUnit, realRanks, realRoster = _G.UnitIsUnit, NS.FM.Ranks, FG.Roster

    local up, asked, mode = { player = {}, party1 = {} }, {}, "answer"
    _G.C_UnitAuras = {
        GetAuraDataByIndex = function()
            error("Auras cannot be accessed when secret while tainted", 2)
        end,
        GetUnitAuraBySpellID = function(unit, id)
            asked[#asked + 1] = tostring(unit) .. ":" .. tostring(id)
            if mode == "refuse" then error("cannot be accessed", 2) end
            if mode == "secret" then return secret() end
            return up[unit] and up[unit][id] or nil
        end,
    }
    -- A SPELL THIS MODE ACTUALLY HAS. It was Earth Shield until Arn pointed out there is no such
    -- thing on a 1.60 client - which is exactly the bug the watch is now generic to avoid, so the
    -- suite should not quietly re-enshrine it either. Two ranks, each its own id, which is why one
    -- buff is several questions.
    NS.FM.Ranks = function(name)
        if name ~= "Lightning Shield" then return {} end
        return { { rank = "Rank 1", id = 974 }, { rank = "Rank 2", id = 32593 } }
    end
    local realDB = NS.DB()
    realDB.groupBuff = "Lightning Shield"
    FG.Roster = function() return { "player", "party1" } end

    -- ---------------------------------------------------------------- NS.AuraById
    up.party1[32593] = { name = "Earth Shield", spellId = 32593 }
    local a, why = NS.AuraById("party1", 32593)
    ok(type(a) == "table" and why == nil, "an aura the client hands over is read")
    ok(NS.auraSeen == "read", "and it says so", tostring(NS.auraSeen))

    a, why = NS.AuraById("player", 974)
    ok(a == nil and why == "none", "an aura that is not there is 'none', not a refusal", tostring(why))

    mode = "secret"
    a, why = NS.AuraById("party1", 32593)
    ok(a == nil and why == "secret", "a secret answer is never read", tostring(why))

    mode = "refuse"
    a, why = NS.AuraById("party1", 32593)
    ok(a == nil and why == "refused", "a call that throws is 'refused'", tostring(why))
    mode = "answer"

    a, why = NS.AuraById("party1", "notanid")
    ok(a == nil and why == "no spell", "nonsense in, no question asked", tostring(why))

    -- NOT GATED ON Blind(), which is the point: every other reader in the addon refuses in
    -- combat, and this one must not, because it is the only question the client still answers.
    STATE.inCombat = true
    a = NS.AuraById("party1", 32593)
    ok(type(a) == "table", "by-id still answers inside the lockdown - the whole reason it is used")
    STATE.inCombat = false

    -- ------------------------------------------------------------- NS.AnyAuraById
    ok(NS.AnyAuraById("party1", { 974, 32593 }) == true, "any one rank up is 'up'")
    ok(NS.AnyAuraById("player", { 974, 32593 }) == false,
       "every rank answered and none up is a real 'no'")
    mode = "refuse"
    ok(NS.AnyAuraById("player", { 974, 32593 }) == nil,
       "one refusal makes the whole answer nil - never a confident 'no'")
    mode = "answer"
    ok(NS.AnyAuraById("player", {}) == nil, "no ids is not evidence of anything")

    -- ------------------------------------------------------------- FB.Watched
    local who, unsure = FB.Watched({ "player", "party1" })
    ok(who == "party1" and not unsure, "the shield is found on the one who has it", tostring(who))
    ok(FB.watchBy == "id", "and recorded as asked by id even though it returned early", tostring(FB.watchBy))

    up.party1[32593] = nil
    who, unsure = FB.Watched({ "player", "party1" })
    ok(who == nil and unsure == false, "nobody has it, and the client said so for everyone")
    ok(FB.watchBy == "id", "by id, while the index walk throws", tostring(FB.watchBy))

    mode = "refuse"
    who, unsure = FB.Watched({ "player", "party1" })
    ok(who == nil and unsure == true, "a refusal is unsure, not 'nobody has it'")
    mode = "answer"

    -- THE 0.6.1 RULE, now at the level that matters: a raid where the walk is refused used to
    -- report nothing at all. It reports properly now - and still says nothing when unsure.
    local found = FB.Scan()
    local said = false
    for _, f in ipairs(found or {}) do if f.kind == "groupbuff" then said = true end end
    ok(said, "in a raid where the walk is refused, the reminder finally works")

    mode = "refuse"
    found = FB.Scan()
    said = false
    for _, f in ipairs(found or {}) do if f.kind == "groupbuff" then said = true end end
    ok(not said, "and when the client will not say, it still says nothing")
    mode = "answer"

    -- a client with no by-id call at all falls back to the walk, as TBC must
    _G.C_UnitAuras.GetUnitAuraBySpellID = nil
    FB.Watched({ "player" })
    ok(FB.watchBy == "walk", "with no by-id call, the old walk is still there", tostring(FB.watchBy))

    -- ------------------------------------------------- the two new secret guards
    _G.C_Secrets = { HasSecretRestrictions = function() return true end }
    ok(NS.CanCompareUnits() == true, "a client with no opinion lets us compare unit tokens")

    _G.C_Secrets.CanCompareUnitTokens = function() return false end
    ok(NS.CanCompareUnits() == false, "a clear no stops us")
    _G.C_Secrets.CanCompareUnitTokens = function() return secret() end
    ok(NS.CanCompareUnits() == false, "so does a secret answer")
    _G.C_Secrets.CanCompareUnitTokens = function() error("nope", 2) end
    ok(NS.CanCompareUnits() == false, "and so does a refusal")
    _G.C_Secrets.CanCompareUnitTokens = function() return true end

    _G.UnitIsUnit = function(x, y) return x == "player" and y == "player" end
    ok(NS.IsPlayer("player") == true, "UnitIsUnit answers first")
    ok(NS.IsPlayer("party1") == false, "and says when it is not you")

    -- UnitIsUnit refusing, the compare allowed: the string road still works
    _G.UnitIsUnit = function() return secret() end
    ok(NS.IsPlayer("player") == true, "a secret UnitIsUnit falls back to the compare")

    -- both roads shut: nil, so a caller can tell "not you" from "could not tell"
    _G.C_Secrets.CanCompareUnitTokens = function() return false end
    ok(NS.IsPlayer("player") == nil, "with neither road open, the answer is 'could not tell'")
    _G.C_Secrets.CanCompareUnitTokens = function() return true end
    _G.UnitIsUnit = function(x, y) return x == "player" and y == "player" end

    -- stats secrecy is a live question now, not a decision made at login
    ok(NS.StatsSecret() == nil, "with no call for it, we do not pretend to know")
    _G.C_Secrets.ShouldUnitStatsBeSecret = function() return false end
    ok(NS.StatsSecret() == false, "the client can say stats are readable")
    _G.C_Secrets.ShouldUnitStatsBeSecret = function() return true end
    ok(NS.StatsSecret() == true, "and that they are not")
    _G.C_Secrets.ShouldUnitStatsBeSecret = function() error("nope", 2) end
    ok(NS.StatsSecret() == true, "a refusal counts as secret - the safe side")

    -- ------------------------------------------------------- the two commands
    -- THIS IS A REGRESSION TEST FOR A BUG WRITTEN TODAY: the new diagnostic was first called
    -- NS.DO.auras, which silently replaced the debug-marker command of the same name. NS.DO being
    -- one table is what keeps the three doors in step; it also makes this collision possible.
    ok(type(NS.DO.byid) == "function", "the by-id diagnostic has its own name")
    ok(type(NS.DO.auras) == "function", "and the debug marker still has its")

    -- NOTHING WATCHED IS THE DEFAULT, and the whole lesson of the day: a hardcoded spell name was
    -- wrong about this game mode for twelve days. With nothing chosen, nothing is said.
    local keep = NS.DB().groupBuff
    NS.DB().groupBuff = nil
    local quiet = FB.Scan()
    local spoke = false
    for _, f in ipairs(quiet or {}) do if f.kind == "groupbuff" then spoke = true end end
    ok(not spoke, "with nothing watched, the group-buff reminder says nothing at all")
    ok(select(1, FB.Watched({ "player" })) == nil, "and nothing is asked about")

    -- IT HAS TO SURVIVE A RESTART. SavedVariables never come back on this client, so a setting
    -- that is not in the macro is a setting the player sets once per session - and the row carries
    -- only digits, so the NAME rides as an index into the leading spell list, like a bind does.
    NS.DB().groupBuff = "Lightning Shield"
    local FK = NS.FK
    local body = FK.Encode({ left = "Healing Wave(Rank 1)" }, { groupBuff = "Lightning Shield" })
    ok(type(body) == "string" and body:find("Lightning Shield", 1, true) ~= nil,
       "the watched buff's name is written into the macro", tostring(body))
    local _, settings = FK.Decode(body)
    ok(settings and settings.groupBuff == "Lightning Shield",
       "and comes back out of it", tostring(settings and settings.groupBuff))

    local plain = FK.Encode({ left = "Healing Wave(Rank 1)" }, {})
    local _, none = FK.Decode(plain)
    ok(none and none.groupBuff == nil,
       "a macro with no U row leaves the watch alone rather than clearing it")

    -- the command, both ways
    NS.DO.watch("Lightning Shield")
    ok(NS.DB().groupBuff == "Lightning Shield", "/bish watch <spell> sets it")
    NS.DO.watch("off")
    ok(NS.DB().groupBuff == nil, "/bish watch off stops it")
    ok(pcall(SlashCmdList.BISHEALING, "watch Lightning Shield"), "/bish watch <spell> threw")
    ok(pcall(SlashCmdList.BISHEALING, "watch"), "/bish watch threw")
    NS.DB().groupBuff = keep
    ok(pcall(SlashCmdList.BISHEALING, "byid"), "/bish byid threw")
    ok(pcall(SlashCmdList.BISHEALING, "scan"), "/bish scan threw with the walk refusing")

    _G.C_UnitAuras, _G.C_Secrets = realAuras, realSecrets
    _G.UnitIsUnit, NS.FM.Ranks, FG.Roster = realIsUnit, realRanks, realRoster
end

--------------------------------------------------- a ping on a mouse button (0.8.0) --
--
-- Arn's design, and the only road left after SendMacroPing came back forbidden: the cell holds a
-- MACRO running Blizzard's own /ping, the same way the wheel binds run /target [@mouseover].
do
    local FM, FG = NS.FM, NS.FG

    ok(FM.PingOf("!ping:assist") == "assist", "a ping bind is recognised")
    ok(FM.PingOf("!ping:nonsense") == nil, "a ping type we do not offer is not one")
    ok(FM.PingOf("Healing Wave(Rank 3)") == nil, "a spell is not a ping")
    ok(FM.PingOf(nil) == nil, "and nothing is not a ping")
    ok(FM.PingBind("assist") == "!ping:assist", "a ping is stored under a mark no spell can wear")
    ok(FM.PingWord("onmyway") == "On My Way", "and shown by its own name")

    local keepLeft, keepAlt = FM.Get("", "left"), FM.Get("alt-", "left")

    -- IT BECOMES A MACRO, NOT A SPELL. If it ever went in as a spell the cell would try to cast
    -- something called "!ping:assist", which is a visible error in the middle of a fight.
    FM.Set("alt-", "left", FM.PingBind("assist"))
    FM.Apply()
    local cell = FG.frames[1]
    ok(cell.__attrs["alt-type1"] == "macro", "a ping binds as a macro", tostring(cell.__attrs["alt-type1"]))
    ok(cell.__attrs["alt-macrotext1"] == "/ping assist", "running Blizzard's own command",
       tostring(cell.__attrs["alt-macrotext1"]))
    ok(cell.__attrs["alt-spell1"] == nil, "and never as a spell", tostring(cell.__attrs["alt-spell1"]))

    -- THE REGRESSION THAT MATTERS. The range check takes "whatever you have bound", and a ping is
    -- not a spell: handing it one answers "don't know", which reads as "in range", which is the
    -- whole raid staying bright. That bug cost 0.7.2 and 0.7.5; it is not coming back this way.
    FM.Clear("", "left")
    FM.Clear("", "right")
    for _, slot in ipairs(FM.SLOTS) do
        for _, m in ipairs(FM.MODS) do FM.Clear(m.key, slot.key) end
    end
    FM.Set("alt-", "left", FM.PingBind("assist"))
    ok(FM.RangeSpell() == nil,
       "with only a ping bound, range is measured with nothing - never with the ping",
       tostring(FM.RangeSpell()))
    FM.Set("", "left", "Healing Wave(Rank 3)")
    ok(FM.RangeSpell() == "Healing Wave", "and a real spell is still found", tostring(FM.RangeSpell()))

    -- IT HAS TO SURVIVE A RESTART like any other bind, which it gets for free by riding in the
    -- spell list as a name - but free is not the same as tested.
    local body = NS.FK.Encode({ ["alt-left"] = FM.PingBind("assist"),
                                left = "Healing Wave(Rank 3)" }, {})
    ok(type(body) == "string" and body:find("!ping:assist", 1, true) ~= nil,
       "a ping bind is written into the macro", tostring(body))
    local back = NS.FK.Decode(body)
    local found = false
    for _, v in pairs(back or {}) do if v == "!ping:assist" then found = true end end
    ok(found, "and comes back out of it")

    FM.Clear("alt-", "left")
    if keepLeft then FM.Set("", "left", keepLeft) else FM.Clear("", "left") end
    if keepAlt then FM.Set("alt-", "left", keepAlt) end
    FM.Apply()
end

------------------------------------------------------- can we send a ping (0.8.0) --
--
-- A MEASUREMENT, so what is tested is that it reports honestly - not that pings work. The client
-- is the authority on that and only Arn can run it. What must hold here: it never throws, it says
-- "no" when there is nothing to call, and a protected refusal is RECORDED rather than guessed at.
do
    local realPing, realEnum = _G.C_Ping, _G.Enum

    -- no ping system at all: the TBC case, and the honest answer is "no"
    _G.C_Ping = nil
    ok(NS.DO.ping() == false, "with no C_Ping, it says so instead of throwing")
    ok(pcall(SlashCmdList.BISHEALING, "ping"), "/bish ping threw with no ping system")

    -- CAPTURE THE LISTENER FRAME BEFORE THE FIRST CALL. The blocked-action watcher is memoised, so
    -- it is built on the first /bish ping and never again - wrapping CreateFrame afterwards catches
    -- nothing, and the test below then silently does not run. Caught because the check count did
    -- not move when it was added (890 before, 890 after), which is the only reason it was noticed.
    local frames = {}
    local realCreate = _G.CreateFrame
    _G.CreateFrame = function(...)
        local f = realCreate(...)
        frames[#frames + 1] = f
        return f
    end

    -- BLIZZARD'S SLASH DOOR, found or not found. This is the one that decides whether ping buttons
    -- can live in the mouse window at all, so it must not quietly report a yes.
    local realSlashList, realToken = _G.SlashCmdList, _G.SLASH_PING1
    _G.SlashCmdList = {}
    _G.SLASH_PING1 = nil
    ok(pcall(NS.DO.ping), "with no /ping command, the diagnostic still runs")
    _G.SlashCmdList = { PING = function() end }
    _G.SLASH_PING1 = "/ping"
    ok(pcall(NS.DO.ping), "and with one, it still runs")
    _G.SlashCmdList, _G.SLASH_PING1 = realSlashList, realToken

    -- a client that has the system and lets us call it
    local sent = {}
    _G.C_Ping = {
        IsPingSystemEnabled = function() return true end,
        GetCooldownInfo = function() return { ready = true } end,
        SendMacroPing = function(t) sent[#sent + 1] = t end,
    }
    _G.Enum = _G.Enum or {}
    _G.Enum.PingSubjectType = { Attack = 0, Warning = 1, OnMyWay = 2, Assist = 3 }
    local worked = NS.DO.ping()
    ok(worked ~= nil and worked ~= false, "when the call goes through, it says which argument worked")
    ok(#sent > 0, "and it actually tried")

    -- ONE ARGUMENT WHEN ASKED, so a measurement can be repeated on the type that matters
    sent = {}
    NS.DO.ping(3)
    ok(#sent == 1 and sent[1] == 3, "a type given on the command is the only one tried", tostring(sent[1]))

    -- THE PROTECTED CASE, which is the whole reason this exists. A refusal must not throw, and
    -- must come back as "no", not as a shrug.
    _G.C_Ping.SendMacroPing = function() error("You can't do that yet", 2) end
    ok(NS.DO.ping(3) == nil or NS.DO.ping(3) == false,
       "a refused ping is reported, not raised")
    ok(pcall(SlashCmdList.BISHEALING, "ping 3"), "/bish ping 3 threw on a refusing client")

    -- THE SHAPE THE REAL CLIENT ACTUALLY USED (measured 1 Oct 2026): the call raises nothing at
    -- all, and the refusal arrives as ADDON_ACTION_FORBIDDEN naming this addon. A verdict that
    -- trusts "no error" over a fired event reports a yes when the answer is no, which is exactly
    -- what the first run did.
    _G.CreateFrame = realCreate
    local fired = false
    _G.C_Ping.SendMacroPing = function()
        -- THE CLIENT'S ACTUAL SHAPE: it returns quietly and fires the forbidden event DURING the
        -- call. Firing it beforehand instead would be wiped by the arming step, which is how the
        -- first version of this test fooled itself.
        for _, f in ipairs(frames) do
            local on = f.__scripts and f.__scripts.OnEvent
            -- NAMED, the way the client names it. Passing nil here would slip through the handler's
            -- "unnamed" branch and prove nothing about the test that matters below.
            if on then on(f, "ADDON_ACTION_FORBIDDEN", "BiSHealing", "SendMacroPing()"); fired = true end
        end
    end
    local verdict = NS.DO.ping(2)
    ok(fired, "the blocked-action listener was found, so this test can actually run")
    ok(verdict == false,
       "a forbidden action beats 'no error' - the verdict is no, however quiet the call was")

    -- AND SOMEBODY ELSE'S BLOCKED ACTION IS NOT OURS. Half the addons on this client trip the
    -- forbidden event sooner or later; reading one of those as our own verdict would retire a
    -- feature that works.
    _G.C_Ping.SendMacroPing = function()
        for _, f in ipairs(frames) do
            local on = f.__scripts and f.__scripts.OnEvent
            if on then on(f, "ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "DoSomething()") end
        end
    end
    ok(NS.DO.ping(2) ~= false,
       "another addon being blocked is not our refusal")

    _G.C_Ping, _G.Enum = realPing, realEnum
end

print(fail == 0 and ("== BiS Healing ok (" .. checks .. " checks)")
      or ("!! BiS Healing: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
