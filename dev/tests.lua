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
local function ok(cond, what, ...)
    checks = checks + 1
    if not cond then
        fail = fail + 1
        -- the third argument many checks pass is what was seen: print it beside the line
        local seen = select("#", ...) > 0 and ("  [" .. tostring((...)) .. "]") or ""
        print("!! FOREVER: " .. what .. seen)
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

-- A SECRET STRING (14 Oct 2026, the tank X in a battleground: a nameplate's name came back secret).
-- On the client `type()` of one says "string", so a `type(n) ~= "string"` guard does NOT stop it -
-- the mock's plain secret is a table, which that guard did stop, and the bug went through green.
-- These answer "string" to type(); everything else about them is the secret above.
local secretStrings = setmetatable({}, { __mode = "k" })
local function secretString()
    local s = setmetatable({}, secretMeta)
    secretStrings[s] = true
    return s
end
-- A SECRET NUMBER (8 Nov 2026, Arn's BugSack: the radar compared a party member's max health). On the client `type()`
-- of one says "number", so a `type(mx) == "number"` guard does NOT stop it - the plain secret above is a table, which
-- that guard did stop, and the bug went through green. These answer "number"; everything else is the secret above.
local secretNumbers = setmetatable({}, { __mode = "k" })
local function secretNumber()
    local s = setmetatable({}, secretMeta)
    secretNumbers[s] = true
    return s
end
do
    local rawType = type
    _G.type = function(v)
        if secretStrings[v] then return "string" end
        if secretNumbers[v] then return "number" end
        return rawType(v)
    end
end

------------------------------------------------------------------ the client --

local STATE = {
    inCombat = false,
    units = { player = true, party1 = true, party2 = true },
    dead = {},
    range = {},                 -- unit -> 0 means out of range
    maxRefusesSecret = false,   -- the client rejecting a secret max, if it turns out to do that
    incoming = {},              -- unit -> heals already on their way
    incomingSecret = false,     -- and whether the client will say how much
    absorb = {},                -- unit -> the shield on them, which a healer must see
    healAbsorb = {},            -- unit -> healing they cannot take (a heal-absorb debuff)
    absorbSecret = false,       -- and whether the client will say how big it is
    deadSecret = false,         -- UnitIsDeadOrGhost as a secret BOOLEAN, which it is in combat
    classSecret = false,        -- so is the class, and it indexes a table here
}

local frames = {}
-- EVERY LABEL EVER MADE, walked by fitsIn() (6 Oct 2026, ported from BiSTools).
local LABELS = {}
-- the client's own font templates, in points. A label made from one of these was 12 pt to the
-- mock whatever it said, and GameFontNormalSmall is 10 on every client we have measured.
local FONT_SIZE = { GameFontNormal = 12, GameFontHighlight = 12, GameFontDisable = 12,
                    GameFontNormalSmall = 10, GameFontHighlightSmall = 10, GameFontDisableSmall = 10,
                    GameFontNormalLarge = 16, GameFontHighlightLarge = 16, NumberFontNormal = 14 }
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
    -- a frame can change parents, as in the client (the mana window docks onto the options, 19 Oct)
    function f:SetParent(p) self.__parent = p end
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
    -- ONE ANCHOR PER POINT, as in the client (10 Nov 2026): setting TOPRIGHT again moves the TOPRIGHT, it does not add
    -- a second one - the mock appended, so a test reading the first TOPRIGHT read a stale one (the radar's hot window)
    function f:SetPoint(...)
        local p = { ... }
        for i, q in ipairs(self.points) do if q[1] == p[1] then self.points[i] = p return end end
        self.points[#self.points + 1] = p
    end
    -- a frame laid over another remembers which (8 Oct 2026): the cell's ink layer covers the bar,
    -- and the fit check has to follow it there to measure the words on it
    function f:SetAllPoints(rel) self.__allpoints = rel or true end
    -- and ClearAllPoints takes that away too, as the client's does (8 Nov 2026, the BiS> dashboard kit)
    function f:ClearAllPoints() self.points = {} self.__allpoints = nil end
    function f:GetNumPoints() return #self.points end
    -- WHAT A FRAME LISTENS TO, recorded (8 Nov 2026, the dashboard). A Button the client was not told
    -- RegisterForClicks("RightButtonUp") never sees a right-click, and an auto no-op could not say so.
    -- A DRAG, AS THE CLIENT HOLDS IT (8 Nov 2026, the drag audit after BiS Tools' boss window held Arn's mouse until he
    -- killed the game). StartMoving glues the frame to the cursor; only StopMovingOrSizing lets go. The client refuses
    -- both on a SECURE frame inside the lockdown - so a drag on a cell still going when the fight starts can never be
    -- stopped from the mouse-up. A frame that hides or stops taking the mouse mid-drag never hears the button come up
    -- either. Each of those counts STATE.strandedDrag, so a suite can forbid it. These were auto no-ops: every drag
    -- "ended" here, whenever and however it was asked to.
    -- PROTECTED = secure itself, or holding a secure frame (IsProtected's second answer, "explicit", exists because of
    -- the second kind): the grid's anchor carries every cell, so moving it moves them
    function f:IsProtected() return (self.__secure or self.__secureKids) and true or false, self.__secure and true or false end
    function f:StartMoving()
        if self:IsProtected() and STATE.inCombat then error("StartMoving on a protected frame in combat", 2) end
        self.__moving = true
    end
    function f:StopMovingOrSizing()
        if self.__moving and self:IsProtected() and STATE.inCombat then
            STATE.strandedDrag = (STATE.strandedDrag or 0) + 1      -- refused: still on the cursor
            return
        end
        self.__moving = nil
    end
    function f:EnableMouse(v)
        if not v and self.__moving then STATE.strandedDrag = (STATE.strandedDrag or 0) + 1 end
        self.__mouse = v and true or false
    end
    function f:IsMouseEnabled() return self.__mouse == true end
    function f:RegisterForClicks(...) self.__clicks = { ... } end
    function f:GetPoint(i)
        local p = self.points[i or #self.points]
        if not p then return nil end
        return p[1], p[2], p[3], p[4], p[5]
    end
    function f:SetScript(k, fn) self.__scripts[k] = fn end
    -- HookScript CHAINS, it does not replace. The mock did replace, which is kinder than the
    -- client in the one way that matters here: SecureUnitButtonTemplate installs its own OnEnter to
    -- make you the mouseover, the help button's `/ping [@mouseover] assist` aims at exactly that,
    -- and a mock that quietly dropped the original would let a clobbering bug through green.
    function f:HookScript(k, fn)
        local prev = self.__scripts[k]
        if not prev then self.__scripts[k] = fn return end
        self.__scripts[k] = function(...) prev(...) return fn(...) end
        self.__hooked = self.__hooked or {}
        self.__hooked[k] = (self.__hooked[k] or 0) + 1
    end
    function f:IsMouseOver() return self.__mouseOver == true end
    function f:GetScript(k) return self.__scripts[k] end
    -- AN EVENT THE CLIENT DOES NOT KNOW IS REFUSED (9 Nov 2026, the range signal): the client throws "attempt to
    -- register unknown event"; the mock accepted anything. STATE.unknownEvents names the ones a test pretends are gone.
    function f:RegisterEvent(e)
        if STATE.unknownEvents and STATE.unknownEvents[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"", 2) end
        self.__events = self.__events or {}; self.__events[e] = true
    end
    -- as the client's: the event reaches this frame only for the units named (fire() keeps the filter)
    function f:RegisterUnitEvent(e, ...)
        self.__events = self.__events or {}; self.__events[e] = true
        self.__unitFilter = self.__unitFilter or {}
        local units = {}
        for _, u in ipairs({ ... }) do units[u] = true end
        self.__unitFilter[e] = units
    end
    function f:UnregisterEvent(e) if self.__events then self.__events[e] = nil end end
    function f:SetAttribute(k, v) self.__attrs[k] = v end
    function f:GetAttribute(k) return self.__attrs[k] end
    function f:Show() self.__shown = true end
    function f:Hide()
        if self.__shown and self.__moving then STATE.strandedDrag = (STATE.strandedDrag or 0) + 1 end
        self.__shown = false
    end
    function f:IsShown() return self.__shown end
    function f:SetShown(v) self.__shown = v and true or false end
    -- A CLICK RUNS OnClick, as the client's Button:Click() does - and not on a disabled button
    function f:Click(button)
        if self.__disabled then return end
        local fn = self.__scripts.OnClick
        if fn then return fn(self, button or "LeftButton", false) end
    end
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
    -- ALPHA MULTIPLIES DOWN TO THE CHILDREN, as in the client: a header on a cell dimmed to 20%
    -- draws at 20% too (Arn, 7 Oct: dimming out-of-range cells "also dimmed the header of target
    -- and tot"). The mock kept each frame's own alpha and nothing else, so it could not see that.
    -- SetIgnoreParentAlpha(true) stops the chain at that frame, as the client's does.
    function f:SetIgnoreParentAlpha(v) self.__ignoreParentAlpha = v and true or false end
    function f:IsIgnoringParentAlpha() return self.__ignoreParentAlpha == true end
    function f:GetEffectiveAlpha()
        local a = type(self.__alpha) == "number" and self.__alpha or 1
        local p = (not self.__ignoreParentAlpha) and self.__parent
        while p do
            a = a * (type(p.__alpha) == "number" and p.__alpha or 1)
            if p.__ignoreParentAlpha then break end
            p = p.__parent
        end
        return a
    end
    -- THE CLIENT'S OWN TERNARY ON A FRAME (ClickMend 0.16.1's target border, and a dozen
    -- EllesmereUI modules, on this client): the alpha is picked from a boolean the addon may not
    -- test. An auto no-op here would answer "drawn" for a ring nobody ever showed. A plain boolean
    -- picks; a secret stays the client's choice (recorded, so a test can tell it was handed over);
    -- anything else is refused like the curve call.
    function f:SetAlphaFromBoolean(b, whenTrue, whenFalse)
        if getmetatable(b) == secretMeta then
            self.__alpha, self.__alphaFromSecret = secret(), true
            return
        end
        if type(b) ~= "boolean" then error("SetAlphaFromBoolean needs a boolean", 2) end
        self.__alpha, self.__alphaFromSecret = b and whenTrue or whenFalse, false
    end
    function f:SetFrameStrata(v) self.__strata = v end
    -- THE CLAMP'S INSETS, RECORDED (9 Nov 2026, the radar's top rail): the auto no-op swallowed them, so "the rails stay
    -- on the screen" passed with nothing set. The client takes four numbers: left, right, top, bottom.
    function f:SetClampRectInsets(l, r, t, b)
        for _, v in ipairs({ l, r, t, b }) do
            if type(v) ~= "number" then error("SetClampRectInsets wants four numbers", 2) end
        end
        self.__clamp = { l, r, t, b }
    end
    -- AN ANIMATION GROUP, RECORDED (12 Oct 2026, the shield's pulse). The auto no-op answered nil
    -- to CreateAnimationGroup, so "does it pulse" was a question with no answer; the client hands
    -- back a group that makes animations, loops and plays - and runs them itself, not in Lua.
    function f:CreateAnimationGroup()
        local g = { anims = {}, playing = false }
        function g:CreateAnimation(kind)
            local a = { kind = kind }
            function a:SetFromAlpha(v) self.from = v end
            function a:SetToAlpha(v) self.to = v end
            function a:SetDuration(v) self.duration = v end
            function a:SetSmoothing(v) self.smoothing = v end
            -- a Scale animation's own setters (the interrupt icon's bounce, 8 Nov 2026)
            function a:SetScaleFrom(x, y) self.scaleFrom = { x, y } end
            function a:SetScaleTo(x, y) self.scaleTo = { x, y } end
            function a:SetOrigin(p, x, y) self.origin = p end
            function a:SetOrder(n) self.order = n end
            self.anims[#self.anims + 1] = a
            return a
        end
        function g:SetLooping(v) self.looping = v end
        -- the client's group takes scripts (OnFinished) and can hold its last frame, as the LoS mark's
        -- fade does (18 Oct); FINISH() plays the end the client would
        function g:SetToFinalAlpha(v) self.finalAlpha = v end
        function g:SetScript(k, fn) self.scripts = self.scripts or {} self.scripts[k] = fn end
        function g:FINISH()
            self.playing = false
            if self.scripts and self.scripts.OnFinished then self.scripts.OnFinished(self) end
        end
        function g:Play() self.playing = true end
        function g:Stop() self.playing = false end
        function g:IsPlaying() return self.playing end
        self.__animGroups = self.__animGroups or {}
        self.__animGroups[#self.__animGroups + 1] = g
        return g
    end
    -- A FRAME HAS A LEVEL, and a child starts one above its parent, as in the client (8 Oct 2026).
    -- Both were auto no-ops answering nil, so "does the overheal band paint over the number" had
    -- no answer - and in 0.8.3 it did (Arn: "magenta over laps the numbers").
    function f:SetFrameLevel(l) self.__level = l end
    function f:GetFrameLevel()
        if type(self.__level) == "number" then return self.__level end
        local p = self.__parent
        return ((p and p.GetFrameLevel and p:GetFrameLevel()) or 0) + 1
    end
    function f:SetScale(v) self.__scale = v end
    function f:GetScale() return self.__scale or 1 end
    function f:SetSize(w, h) self.__w, self.__h = w, h end
    -- a width on its own is a size too. It was an auto no-op, so "how wide did it draw that" had
    -- no answer at all - which is how a bar could be drawn at any width and pass (23 Sep).
    function f:SetWidth(w) self.__w = w end
    function f:SetHeight(h) self.__h = h end
    -- an unsized frame answers 0, as the client's does - never nil (8 Nov 2026, the BiS> page kit)
    function f:GetWidth() return self.__w or 0 end
    function f:GetHeight() return self.__h or 0 end
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
    -- and the client's getters, which /bish overheal reads back (8 Oct 2026) - handed back as given,
    -- a secret stays a secret
    function f:GetValue() return self.__value end
    function f:GetMinMaxValues() return self.__min, self.__max end
    function f:SetStatusBarColor(r, g, b, a) self.__color = { r, g, b, a } end   -- the client keeps the alpha too
    -- A STATUS BAR HAS A FILL TEXTURE, and hands back the same one every time (7 Oct 2026). This was
    -- an auto no-op answering nil, so every "anchored to the end of the fill" in the suite was
    -- anchored to nil - and the overheal's tick, which is built only when the fill answers, was
    -- never built at all.
    function f:GetStatusBarTexture()
        if not self.__fill then self.__fill = self:CreateTexture() end
        return self.__fill
    end
    -- CLIPPING AND REVERSE FILL, RECORDED (6 Oct 2026). Both were auto no-ops, so "the heal bar
    -- stops at the cell's edge" had no answer - and on Arn's screen it ran straight across the
    -- next cell. EllesmereUIRaidFrames uses both on Forever (healClip, missClip, backfillBar).
    function f:SetClipsChildren(v) self.__clips = v and true or false end
    function f:DoesClipChildren() return self.__clips == true end
    -- A MASK TEXTURE is a texture that trims others (8 Oct 2026); it records what it covers through
    -- SetAllPoints, and which textures carry it through their AddMaskTexture
    function f:CreateMaskTexture()
        local m = self:CreateTexture()
        m.__isMask = true
        return m
    end
    function f:SetReverseFill(v) self.__reverse = v and true or false end
    function f:GetReverseFill() return self.__reverse == true end
    -- WHICH WAY A BAR FILLS, RECORDED (8 Nov 2026, the fuel tape): an auto no-op answered "filled from the bottom" for a
    -- bar that was never told. The client's default is HORIZONTAL; it takes only its two words.
    function f:SetOrientation(o)
        if o ~= "HORIZONTAL" and o ~= "VERTICAL" then error("SetOrientation wants HORIZONTAL or VERTICAL", 2) end
        self.__orient = o
    end
    function f:GetOrientation() return self.__orient or "HORIZONTAL" end
    -- A TEXTURE REMEMBERS WHAT IT WAS GIVEN. autoMethods answers every call with nil, which is
    -- fine for SetColorTexture and a liar for the rest: "the icon is shown" and "it used the
    -- healer corner" are only questions if Show and SetTexCoord leave a mark. Shown-by-default
    -- like the client's, and like the frames above.
    -- A LINE IS A REAL OBJECT (14 Oct 2026): the client's CreateLine always hands one back. The
    -- generic auto-method answered nil, so the first code to draw a tank mark on a plain frame (the
    -- options' preview) died here on "index a nil value" - a mock harsher than the client is a lie too.
    function f:CreateLine()
        local l = autoMethods({ __shown = true })
        function l:SetStartPoint(_, _, x, y) self.from = { x, y } end
        function l:SetEndPoint(_, _, x, y) self.to = { x, y } end
        function l:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
        function l:SetThickness(w) self.thick = w end
        -- and its alpha, as the client's does (10 Nov 2026: the radar's view button shows one sign or the other)
        function l:SetAlpha(a) self.__alpha = a end
        function l:GetAlpha() return self.__alpha end
        function l:Show() self.__shown = true end
        function l:Hide() self.__shown = false end
        function l:IsShown() return self.__shown end
        return l
    end
    -- A FRAME LISTS ITS TEXTURES (GetRegions), as the client does (9 Nov: "is the see-through square gone?" had no answer)
    function f:GetRegions() return unpack(self.__regions or {}) end
    function f:CreateTexture(_, layer, _, sublevel)
        self.__regions = self.__regions or {}
        local made = autoMethods({
            -- A REGION, NOT A FRAME (12 Nov 2026): a frame holding secure buttons may not be pinned to one, anywhere down
            -- its anchor chain - "Cannot anchor protected frames to regions" (Arn's BugSack, BiS Tools' box on the radar)
            __texture = true,
            GetObjectType = function() return "Texture" end,
            IsObjectType = function(_, k) return k == "Texture" or k == "Region" end,
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
            SetShown = function(t, v) t.__shown = v and true or false end,
            SetTexture  = function(t, v) t.__texture = v end,
            SetTexCoord = function(t, a, b, c, d) t.__coords = { a, b, c, d } end,
            SetAtlas    = function(t, v) t.__atlas = v end,
            -- A TEXTURE REMEMBERS ITS ALPHA, ITS BLEND AND WHERE IT SITS. All three were no-ops,
            -- so "does the button react to a hover" and "does the icon take the press" had no
            -- answer - the same shape of lie as a texture that forgot its colour (26 Sep).
            SetAlpha    = function(t, a) t.__alpha = a end,
            GetAlpha    = function(t) return t.__alpha end,
            SetBlendMode = function(t, m) t.__blend = m end,
            -- AND ITS TINT (12 Oct 2026, the shield's red icon): "is it red" needs an answer
            SetVertexColor = function(t, r, g, b, a) t.__vertex = { r, g, b, a } end,
            SetDesaturated = function(t, v) t.__desat = v and true or false end,
            -- A TURN, in radians (8 Nov 2026, the radar's role signs: rotated plain textures, since a Line's colour from
            -- the client's curve left a pip white in Arn's game)
            SetRotation = function(t, r) if type(r) ~= "number" then error("SetRotation wants radians", 2) end t.__rot = r end,
            -- WHAT it covers, not just that it does (8 Oct 2026): a mask laid over curClip must say so
            SetAllPoints = function(t, rel) t.__allpoints = rel or true end,
            -- A MASK ON A TEXTURE (8 Oct 2026, the overheal rebuilt on EllesmereUI's mask). An auto
            -- no-op would answer "masked" for a band nobody ever trimmed.
            AddMaskTexture = function(t, m) t.__masks = t.__masks or {} t.__masks[#t.__masks + 1] = m end,
            -- AND WHAT IT IS PINNED TO (6 Oct 2026). __point kept only the offsets, so a label hung
            -- off an icon could not say where it STARTS; the fit check below follows `points`.
            SetPoint    = function(t, p, a, b, c, d)
                t.points = t.points or {}
                t.points[#t.points + 1] = { p, a, b, c, d }
                if type(a) == "table" then t.__point = { p, c or 0, d or 0 }
                else t.__point = { p, a or 0, b or 0 } end
            end,
            ClearAllPoints = function(t) t.points = {} t.__allpoints = nil end,
            __parent = self,
            -- its draw layer and sublevel, as the client takes them (9 Nov: "the rails draw over the radar's disc")
            __layer = layer, __sublevel = sublevel,
        })
        self.__regions[#self.__regions + 1] = made
        return made
    end
    function f:CreateFontString(_, _, template)
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
            -- recorded (17 Oct 2026): "is the name centred beside the cure column" needs an answer
            SetJustifyH = function(self2, j) self2.__justify = j end,
            SetJustifyV = function(self2, j) self2.__justifyV = j end,
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
            ClearAllPoints = function(self2) self2.points = {} end,
            -- A LABEL KNOWS ITS SIZE, ITS BOX AND WHETHER IT IS SHOWN (6 Oct 2026). Show and Hide
            -- were auto no-ops, so a hidden label still read as drawn; the font template and
            -- SetFont were dropped, so nothing knew how big the letters are. The fit check needs
            -- all of it: Arn's "a check for cut offs or overflows that happens often".
            __shown  = true,
            Show     = function(self2) self2.__shown = true end,
            Hide     = function(self2) self2.__shown = false end,
            IsShown  = function(self2) return self2.__shown end,
            __parent = self,
            GetParent = function(self2) return self2.__parent end,
            __size   = FONT_SIZE[template or ""] or 12,
            -- the font FILE is kept too, as the client keeps it (8 Nov 2026: "which type is this label in" for the cockpit)
            SetFont  = function(self2, file, size)
                self2.__fontFile = file
                if type(size) == "number" then self2.__size = size end
            end,
            SetFontObject = function(self2, o)
                self2.__fontFile = nil
                self2.__size = FONT_SIZE[o] or (type(o) == "table" and o.__size) or self2.__size
            end,
            SetWidth = function(self2, w) self2.__w = w end,
            SetWordWrap = function(self2, v) self2.__wrap = v and true or false end,
        })
        self.__fontstrings = self.__fontstrings or {}
        self.__fontstrings[#self.__fontstrings + 1] = fs
        LABELS[#LABELS + 1] = fs
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
-- EVERY UNIT HAD THE SAME CLASS (17 Oct 2026): this answered "Shaman" whoever was asked, so "res the
-- mage before the warrior" had no answer. STATE.classes[unit] is that unit's class; you stay a shaman.
_G.UnitClass = function(u)
    if STATE.classSecret then return secret(), secret() end
    local c = STATE.classes and u and STATE.classes[u]
    if c then return c, c end
    return "Shaman", "SHAMAN"
end
-- released (a ghost has no corpse to res) and a res already on its way
_G.UnitIsGhost = function(u) return STATE.ghost and STATE.ghost[u] and true or false end
_G.UnitHasIncomingResurrection = function(u) return STATE.resComing and STATE.resComing[u] and true or false end
-- CAN I ATTACK THIS? The target cell holds whatever you clicked, which on a hunter is usually a
-- mob - and in combat the answer is a secret like everything else about somebody else.
STATE.hostile = {}
STATE.hostileSecret = false
_G.UnitCanAttack = function(_, u)
    if STATE.hostileSecret then return secret() end
    return STATE.hostile[u] and true or false
end
-- WHO IS IT (8 Nov 2026, PvP mode's team focus). The client answers a GUID for a unit that exists and
-- NIL for one that does not: "party1target" while party1 targets nobody is nil, never "". Inside an
-- instance it can be secret like a name (a string to type(), refusing everything else).
-- STATE.guids[unit] is that unit's GUID; STATE.guidSecret[unit] hands back a secret one instead.
STATE.guids, STATE.guidSecret = {}, {}
_G.UnitGUID = function(u)
    if not STATE.units[u] then return nil end
    if STATE.guidSecret[u] then return secretString() end
    return STATE.guids[u] or ("Player-0-" .. tostring(u))
end
-- WHERE YOU ARE, in the client's two answers: inside an instance or not, and which kind - "none",
-- "pvp" (a battleground), "arena", "party", "raid". STATE.instance is the kind; nil is the open world.
STATE.instance = nil
_G.IsInInstance = function()
    if STATE.instance then return true, STATE.instance end
    return false, "none"
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
_G.UnitHealthMax = function(u) if u == "player" then return 297 end return secretNumber() end
-- YOUR OWN MANA (8 Nov 2026, the radar's fuel gauge). Measured on the beta: UnitPower is SECRET (GetPowerTypeSecrecy(0)
-- = 2), so it answers a secret that says "number" to type(), always. UnitPowerMax was never measured: it answers plain
-- out of a fight and secret in one, the harsher half - so anything the addon works out from it must be done between pulls.
STATE.powerMax = 1375
_G.UnitPower = function() return secretNumber() end
_G.UnitPowerMax = function()
    if STATE.inCombat or STATE.powerMaxSecret then return secretNumber() end
    return STATE.powerMax
end
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
    -- a spell that cannot be used on that unit answers NIL, not "in range" - a heal on a mob
    -- (7 Oct 2026: Arn's hostile target was dimmed; the mock had answered 1 for anyone at all)
    if STATE.hostile[u] then return nil end
    return STATE.range[u] == 0 and 0 or 1
end
-- THE OTHER QUESTION: about the unit rather than the spell. On this client it is the secret
-- boolean, which is the whole reason the grid can use it at all now.
STATE.unitRange = {}
-- TWO ANSWERS, AS THE CLIENT GIVES THEM: inRange, and whether it CHECKED at all (7 Oct 2026). It
-- only checks party and raid members; for a token like "targettarget" it says false, false - "not
-- in range", but only because it never looked. The mock answered the one value, so the grid read
-- that false as "out of range" and dimmed Arn's tot cell - which was Arn himself.
_G.UnitInRange = function(u)
    -- in combat BOTH answers are secret (Arn's BugGrabber, 7 Oct: checked=<secret boolean>)
    if STATE.unitRangeBothSecret then
        STATE.lastChecked = secret()
        return secret(), STATE.lastChecked
    end
    if STATE.unitRangeSecret then return secret(), true end
    local grouped = u == "player" or tostring(u):match("^party%d") or tostring(u):match("^raid%d")
    if not grouped then return false, false end
    if STATE.unitRange[u] == nil then return nil end
    return STATE.unitRange[u] and true or false, true
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
-- the CLIENT showing and hiding is never "an addon in combat": it goes round the lockdown guard (f.__client)
local function clientShow(f, on)
    local c = f.__client
    if c then if on then c.Show(f) else c.Hide(f) end elseif on then f:Show() else f:Hide() end
end
local function WATCH_TICK()
    for f in pairs(WATCHED) do
        local u = f.GetAttribute and f:GetAttribute("unit")
        clientShow(f, u and STATE.units[u])
    end
end
-- A STATE DRIVER IS THE CLIENT'S TOO (18 Oct: the target cell's cure boxes). A driven frame is shown
-- and hidden by its condition at the client's next look, whatever the addon last said - so DRIVE_TICK
-- overrules any Show or Hide in between, as the real one does. Only the one condition shape we use:
-- "[@<unit>,help] show; hide" - help is a unit that exists and is not in HOSTILE.
local DRIVEN = setmetatable({}, { __mode = "k" })
local HOSTILE = {}
_G.RegisterStateDriver = function(f, state, cond) if state == "visibility" then DRIVEN[f] = cond end end
_G.UnregisterStateDriver = function(f, state) if state == "visibility" then DRIVEN[f] = nil end end
local function DRIVE_TICK()
    for f, cond in pairs(DRIVEN) do
        local u = tostring(cond):match("^%[@([%w]+),help%] show; hide$")
        assert(u, "a state driver this mock does not understand: " .. tostring(cond))
        clientShow(f, STATE.units[u] and not HOSTILE[u])
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
-- THE SHIELD. The client answers with a number that may be secret, exactly like an incoming heal -
-- and the grid hands it straight to a bar. A stub that always said 0 (the one further down, for the
-- probe) made the whole absorb path untestable: the branch simply never ran.
_G.UnitGetTotalAbsorbs = function(u)
    if STATE.absorb[u] == nil then return nil end
    if STATE.absorbSecret then return secret() end
    return STATE.absorb[u]
end
-- HEALING THEY CANNOT TAKE (8 Nov 2026): the heal absorb, the same shape and the same secrecy as the shield
_G.UnitGetTotalHealAbsorbs = function(u)
    if STATE.healAbsorb[u] == nil then return nil end
    if STATE.healAbsorbSecret then return secret() end
    return STATE.healAbsorb[u]
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
-- A SECURE FRAME IN A FIGHT IS THE CLIENT'S (8 Nov 2026, the radar; BiS Tools' boss list hit it the same night:
-- "tried to call the protected function 'Button:Show()'"). Show, Hide, SetShown, SetAttribute and EnableMouse on a
-- frame made from a Secure template are REFUSED inside the lockdown - the call itself, even one that changes
-- nothing. The client blocks it and fires ADDON_ACTION_BLOCKED; here it is an error, so a suite sees it.
local function lockdownGuard(f)
    f.__client = { Show = f.Show, Hide = f.Hide }
    for _, m in ipairs({ "Show", "Hide", "SetShown", "SetAttribute", "EnableMouse" }) do
        local real = f[m]
        if real then
            f[m] = function(self, ...)
                if STATE.inCombat then
                    error("ADDON_ACTION_BLOCKED: " .. m .. " on a secure frame in combat", 2)
                end
                return real(self, ...)
            end
        end
    end
    return f
end
_G.CreateFrame = function(kind, name, parent, template)
    local f = _G.CreateFrameUnguarded(kind, name, parent, template)
    if type(f) == "table" and type(template) == "string" and template:find("Secure", 1, true) then lockdownGuard(f) end
    return f
end
_G.CreateFrameUnguarded = function(kind, name, parent, template)
    -- SecureUnitButtonTemplate ARRIVES WITH AN OnEnter ALREADY ON IT. That handler is what makes
    -- the button the mouseover, and the help button's `/ping [@mouseover] assist` aims at exactly
    -- it. A mock that handed back a bare frame made "did we put our own script in its place" a
    -- question with no answer - so anything that clobbered it would have shipped green.
    if type(template) == "string" and template:find("SecureUnitButton", 1, true) then
        local b = newFrame(kind, name, parent)
        b.__scripts.OnEnter = function(self) self.__wasMouseover = true end
        b.__secure, b.__template = true, template                        -- protected: the lockdown applies
        if type(parent) == "table" then parent.__secureKids = true end    -- and so is what holds it
        return b
    end
    if kind == "AuraContainer" then
        local c = newFrame(kind, nil, parent)
        c.slots, c.unit, c.enabled = {}, nil, false
        function c:SetUnit(u) self.unit = u end
        function c:SetEnabled(v) self.enabled = v and true or false end
        function c:SetFrameLevel(l) self.__level = l end
        function c:GetFrameLevel() return self.__level or 1 end
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
                -- the count, written by the client into a font string through a formatter
                -- (12 Oct 2026, the shield's charges: EllesmereUI, ForeverAuras use it)
                function slot:SetApplicationCount(fs, o) self.countText, self.countOpts = fs, o end
                function slot:SetMouseClickEnabled(v) self.clicks = v end
            end
            -- A SLOT THE CLIENT WILL NOT LET US TOUCH (6 Oct 2026, 0.8.1 on a player's own PC):
            -- "Auras.lua:317: calling 'SetSize' on bad self (Attempt to access forbidden object
            -- from code tainted by an AddOn)", 442 times - the container took SetSize, the slot it
            -- handed back did not. The mock let us size and place it every time, so the throw
            -- that stopped the whole grid's layout at the first cell never ran here.
            -- STATE.slotForbidden = that client.
            -- BUT NOT INSIDE ITS CREATION (14 Oct 2026, read off EllesmereUI's AuraContainers: "SetPoint
            -- on the returned button is denied while auras are secret (12.1 button access
            -- restriction)" - they anchor it INSIDE initializeFrame, "the creation window"). So the
            -- forbidden methods answer while STATE.inInit, and refuse everywhere else.
            if STATE.slotForbidden then
                for _, m in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints",
                                     "SetAllPoints", "Show", "Hide", "SetAlpha", "SetFrameLevel" }) do
                    local allowed = slot[m]
                    slot[m] = function(...)
                        if STATE.inInit then
                            STATE.slotPlacedInInit = (STATE.slotPlacedInInit or 0) + 1
                            if allowed then return allowed(...) end
                            return
                        end
                        STATE.slotTouched = (STATE.slotTouched or 0) + 1
                        error("calling '" .. m .. "' on bad self (Attempt to access forbidden object"
                              .. " from code tainted by an AddOn - Usage: self:" .. m .. "(x, y))", 2)
                    end
                end
            end
            self.slots[key] = slot
            -- THE BUTTON ARRIVES WITH THE AURA, NOT WITH THE SLOT (12 Oct 2026). Fojji's consume
            -- bar for Forever builds a slot, asks UpdateAllAuras, and finds no button until the
            -- buff is on - initializeFrame is the client handing over a button it just made for
            -- an aura. STATE.lazyAuras = that client; the eager call stays for the older checks.
            if opts and opts.initializeFrame then
                if STATE.lazyAuras then
                    local init = opts.initializeFrame
                    slot.__init = function(...) STATE.inInit = true local r = init(...) STATE.inInit = false return r end
                else
                    STATE.inInit = true
                    opts.initializeFrame(slot)
                    STATE.inInit = false
                end
            end
            return slot
        end
        CONTAINERS[#CONTAINERS + 1] = c
        return c
    end
    local made = realCreateFrame(kind, name, parent, template)
    if type(made) == "table" then made.__template = template end      -- which template, so a suite can ask
    if type(made) == "table" and type(template) == "string" and template:find("Secure", 1, true) then
        made.__secure = true
        if type(parent) == "table" then parent.__secureKids = true end
    end
    -- A COOLDOWN FRAME, as the client's: it takes a duration object (secret or not) and runs the sweep itself
    if type(made) == "table" and kind == "Cooldown" then
        function made:SetCooldownFromDurationObject(o) self.__durObj = o end
        function made:SetCooldown(s, d) self.__start, self.__dur = s, d end
        function made:Clear() self.__durObj, self.__start, self.__dur = nil, nil, nil end
        function made:SetDrawBling(v) self.__bling = v end
        function made:SetDrawEdge(v) self.__edgeOn = v end
        function made:SetHideCountdownNumbers(v) self.__noNumbers = v end
        function made:SetSwipeColor(...) self.__swipe = { ... } end
        function made:SetSwipeTexture(t) self.__swipeTex = t end
    end
    return made
end

local NS = {}
-- what the cursor is carrying, and what the client was told to bind
local CURSOR = {}
_G.GetCursorInfo = function() return CURSOR.kind, CURSOR.a, CURSOR.b, CURSOR.c end
_G.ClearCursor = function() CURSOR = {} end
-- PICKING A SPELL UP BY ID puts it on the cursor in Forever's four-value shape (kind, book slot,
-- "spell", id) - the shape FM.CursorSpell is built for. FojjiCore's rank rows drive it this way.
-- WHAT YOU WEAR (10 Oct 2026, trinkets first): the item id in an equipment slot, and its icon.
-- 13 and 14 are the two trinket slots. A slot with nothing in it answers nil, as the client does.
STATE.worn = { [13] = 19950, [14] = 11832 }      -- Zandalarian Hero Charm, Burst of Knowledge
_G.GetInventoryItemID = function(unit, slot)
    if unit ~= "player" then return nil end
    return STATE.worn[slot]
end
_G.GetInventoryItemTexture = function(unit, slot)
    return (unit == "player" and STATE.worn[slot]) and ("Interface\\Icons\\Trinket" .. slot) or nil
end
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.PickupSpell = function(id)
    if type(id) ~= "number" then error("bad argument #1 to 'PickupSpell'", 2) end
    STATE.pickedUp = id
    CURSOR = { kind = "spell", a = 0, b = "spell", c = id }
end
_G.C_Spell = _G.C_Spell or {}
_G.C_Spell.GetSpellInfo = function(id) return { name = "Spell" .. tostring(id) } end   -- see BOOK
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
    local only = f.__unitFilter and f.__unitFilter[event]
    if only and not only[(...)] then return false end           -- a unit event for a unit this frame did not ask for
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
local PAGES = {
    [1] = { name = "Healing Wave",        rank = "Rank 1" },
    [2] = { name = "Healing Wave",        rank = "Rank 2" },
    [3] = { name = "Healing Wave",        rank = "Rank 3" },
    [4] = { name = "Lesser Healing Wave", rank = "Rank 1" },
    [5] = { name = "Chain Heal",          rank = "Rank 1" },
}
-- THE CLIENT SAYS SO WHEN THE BOOK CHANGES (8 Oct 2026). The addon keeps what it read now, so a
-- book that changed in silence would be a mock kinder than the client in a new way: every test
-- that trains or forgets a spell would be testing a re-read the client never gets for free.
--
-- So BOOK is the door and PAGES is the paper. Writing through BOOK is "the character learned or
-- lost a spell", and the client fires SPELLS_CHANGED for that - delivered here through fire(),
-- which only reaches a frame that REGISTERED for it. Take the registration out of Mouse.lua and
-- every test below that changes the book goes red, which is the point.
--
-- ONLY TO THE BOOK'S OWN LISTENER, on purpose. The grid, the self-buff watch and the regen bar
-- listen for the same event, and the cold-start test further down exists to prove each of them
-- asked for it: it lets the book arrive, shows that nothing happens, and only then fires the
-- event at the grid by hand. Delivering it to everybody from here would make that test pass
-- with the grid's registration removed.
--
-- rawset(PAGES, ...) is a book that changed and did NOT say so. One test wants exactly that.
local BOOK = setmetatable({}, {
    __index = PAGES,
    __newindex = function(_, slot, page)
        PAGES[slot] = page
        local FM = NS.FM
        if FM and FM.bookEvents then fire(FM.bookEvents, "SPELLS_CHANGED") end
    end,
})
-- AND WHEN A TEST SWAPS THE CALL RATHER THAN THE PAGE. Several blocks below replace
-- C_SpellBook.GetSpellBookItemInfo to give a spell a different id, or none - which stands for the
-- book filling in its ids at login, or a rank being learned. The client fires the same event for
-- that; a swapped function is silent, so the test says it out loud. Same door, same limit.
local function bookSaid()
    local FM = NS.FM
    return FM and FM.bookEvents and fire(FM.bookEvents, "SPELLS_CHANGED") or false
end
-- A SPELL HAS A RANGE, and the client says whether it is cast on a friend (7 Oct 2026: the grid
-- now measures range with the longest-reaching heal you know). STATE.spellRange[name] overrides
-- the 40 yards most heals have; STATE.harmful[name] marks a damage spell. Defined HERE, below
-- BOOK, so the lookup sees this local and not an empty global.
STATE.spellRange, STATE.harmful = {}, {}
local function bookName(id)
    local e = type(id) == "number" and BOOK[id - 1000]
    return e and e.name or nil
end
_G.C_Spell.GetSpellInfo = function(id)
    STATE.spellAsks = (STATE.spellAsks or 0) + 1      -- counted, for the same reason the book is
    local n = bookName(id)
    return { name = n or ("Spell" .. tostring(id)), maxRange = (n and STATE.spellRange[n]) or 40 }
end
_G.C_Spell.IsSpellHelpful = function(id)
    local n = bookName(id)
    if not n then return nil end
    return not STATE.harmful[n]
end
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
    -- EVERY QUESTION IS COUNTED (8 Oct 2026). The addon walked all 500 slots for every spell on
    -- the mouse, for every cell, ten times a second - and nothing here could see it, because a
    -- mock answers in no time at all. The client does not: Arn's addon list read 63% with the
    -- grid up and 6% with it hidden. A cost the suite cannot measure is a cost it cannot hold.
    STATE.bookAsks = (STATE.bookAsks or 0) + 1
    local e = BOOK[n]
    if e then return e.name, e.rank end
    return nil
end
-- A BOOK SLOT IS NOT A SPELL ID, and this mock had neither - so nothing could tell them apart and
-- a caller passing the slot number looked exactly like a caller passing the id. That is how the
-- range check spent from 0.7.2 to 1 Oct asking C_Spell.IsSpellInRange about row numbers, with a
-- green test named "the range call is asked with a spell id" standing over it: the slot IS a
-- number, so the assertion held while the meaning was wrong.
--
-- The ids here are deliberately nothing like the slots (1000 + slot), so passing the wrong one is
-- always visible.
_G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
    if type(n) ~= "number" or type(bank) ~= "number" then error("bad argument", 2) end
    if not BOOK[n] then return nil end
    return { spellID = 1000 + n }
end

-- and the book's own spells answer their rank by id too, as the client's do (8 Oct 2026): the
-- heal palette picks a spell up BY ID, and only RANKS - filled by hand in a few tests - answered,
-- so a book spell came off the cursor rankless. Kinder than nothing, less than the client.
_G.C_Spell.GetSpellSubtext = function(id)
    if RANKS[id] then return RANKS[id] end
    local e = type(id) == "number" and BOOK[id - 1000]
    return e and e.rank or nil
end

local BOUND = {}
_G.SetOverrideBindingClick = function(_, _, key, button) BOUND[key] = button end
_G.ClearOverrideBindings = function() BOUND = {} end

-- The tooltip, which is where a bind says what it is. It records lines rather than drawing them.
local TIP = { lines = {} }
_G.GameTooltip = autoMethods({
    SetOwner = function(self) TIP.lines = {} end,
    AddLine  = function(self, text) TIP.lines[#TIP.lines + 1] = text end,
    -- the client's own item tooltip (11 Oct 2026, the oil button): records WHICH item it was asked for
    SetItemByID = function(self, id) TIP.item = id TIP.lines[#TIP.lines + 1] = "item:" .. tostring(id) end,
})
_G.UISpecialFrames = {}        -- what the client closes on Escape
_G.tinsert = table.insert

-- THE TOC, AS THE CLIENT READS IT (6 Nov 2026, the version mark). This answered nothing at all, so
-- NS.VERSION was "0.0.0" in every run and "does the window show the version" had no answer. The
-- client hands back a `## Key: value` line from the TOC it loaded, and nil for a key it lacks - and
-- only a copy deploy.sh stamped carries X-BiS-Build, so that one is nil here unless a test sets
-- __BUILD (the shape deploy.sh writes: "<branch>@<sha>[+] <MMDD-HHMM>").
do
    local meta = {}
    local toc = io.open("BiSHealing.toc")
    if toc then
        for line in toc:lines() do
            local k, v = line:match("^##%s*([^:]-)%s*:%s*(.-)%s*$")
            if k then meta[k] = v end
        end
        toc:close()
    end
    _G.GetAddOnMetadata = function(addon, key)
        if addon ~= "BiSHealing" then return nil end
        if key == "X-BiS-Build" then return rawget(_G, "__BUILD") end
        return meta[key]
    end
end

-- THE WHOLE ADDON, IN THE TOC'S ORDER, read from the TOC itself rather than listed here. A list
-- in a suite is a list that goes stale: on 19 Sep the addon lost 5,000 lines and gained a core,
-- and a hand-written list would have kept loading files that no longer exist while quietly
-- skipping the one that now owns the saved variables.
--
-- The Libs lines are skipped: BiSTheme is a shared lib with its own suite, and the drawing here
-- is stub frames anyway.
local LOADED = {}
local beforeLoad = {}
for k in pairs(_G) do beforeLoad[k] = true end
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

-- THE GLOBALS THE ADDON MAKES BY LOADING, and nothing else (16 Oct 2026, with the API). A named
-- frame lands in _G in the client as here, so those are not counted; everything else must be on
-- this list, and a new one is a choice made here, not an accident.
local ALLOWED_GLOBALS = {
    BiSHealingAPI = true,      -- API.lua, for other addons (playbook 5a)
    SLASH_BISHEALING1 = true, SLASH_BISHEALING2 = true, SLASH_BISHEALING3 = true,   -- /bish and its aliases
    -- the client's own table; the mock has none before load, so Core's `if not SlashCmdList` makes
    -- it here (the source check "no file writes a Blizzard global outright" guards the client side)
    SlashCmdList = true,
}
do
    local leaked = {}
    for k, v in pairs(_G) do
        if not beforeLoad[k] and not ALLOWED_GLOBALS[k]
           and not (type(v) == "table" and rawget(v, "__kind")) then
            leaked[#leaked + 1] = tostring(k)
        end
    end
    table.sort(leaked)
    ok(#leaked == 0, "loading the addon makes no global off the allowed list: " .. table.concat(leaked, ", "))
end

-- BiSHealingAPI BEFORE LOGIN: the grid is not built yet, so every question answers nil, "not
-- ready" - and nothing throws, and nothing is created by being asked.
do
    local A = _G.BiSHealingAPI
    ok(type(A) == "table" and A.major == 1 and A.version == 2, "BiSHealingAPI is there, major 1 version 2")
    ok(A.Look() == nil and A.RadarEdge() == nil, "version 2's Look and RadarEdge: nil before login too")
    ok(NS.FG and NS.FG.anchor == nil, "(the grid is not started yet, as before PLAYER_LOGIN)")
    local hadDB = _G.BiSHealingDB
    for _, name in ipairs({ "Ready", "Shown", "CliqueOn", "Slots", "Binds", "Bind", "Now", "Tank",
                            "OpenBinds", "OpenOptions" }) do
        local fn = A and A[name]
        local ran, v, why = pcall(fn or error, "left")
        ok(ran and v == nil and why == "not ready", "before login " .. name .. "() answers nil, \"not ready\": "
           .. tostring(v) .. " " .. tostring(why))
    end
    ok(_G.BiSHealingDB == hadDB, "and asking created no saved table")
end
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
-- THE CLASSIC LOOK for everything below that checks it (8 Nov 2026: the cockpit look is the default; it has its own
-- section, "THE COCKPIT LOOK", near the end). A cell takes the look it is made in, so this is set before any is made.
NS.DB().look = "classic"

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

-- THE SHIELD (5 Oct 2026). Arn: "ellesmear draws the shield on the frames can we do the same?"
-- Yes, by the same bargain as the health and the incoming heal: UnitGetTotalAbsorbs hands back a
-- number that may be secret, and a secret may be GIVEN to a StatusBar. The addon never learns how
-- big the shield is; the client draws it. EllesmereUIRaidFrames does exactly this on this client
-- (`topBar:SetValue(absorbAmt)`), so it is a measured pattern and not a hopeful one.
--
-- Until now a shielded healer and a hurt one looked identical on the grid - which is the one thing
-- a healer most wants to tell apart, because a bubble is the difference between topping someone up
-- and wasting the cast.
do
    STATE.absorb.party1 = 1200
    STATE.absorbSecret = false
    FG.Paint(f)
    ok(f.absorb ~= nil, "a cell has a bar for the shield on them")
    ok(f.absorb.__value == 1200, "and it is handed how big it is")

    STATE.absorbSecret = true
    ok(pcall(FG.Paint, f), "a SECRET absorb does not throw")
    ok(getmetatable(f.absorb.__value) == secretMeta,
       "it is handed the secret itself, untouched, like the health under it")

    -- IT IS NOT THE INCOMING BAR. Two bars growing from the same place must never be confused for
    -- each other: one is what has already happened, one is what has not happened yet.
    ok(f.absorb ~= f.incoming, "the shield is its own bar, not the incoming one reused")

    STATE.absorb.party1 = nil
    STATE.absorbSecret = false
    FG.Paint(f)
    ok(f.absorb.__value == 0, "a shield that broke empties the bar rather than leaving it")
end

-- HEALING THEY CANNOT TAKE (8 Nov 2026). Arn, on VuhDo: "we come back to absorb bar". A heal absorb eats the next
-- N healing; that much of their health is not really there. The client's number (maybe secret) goes to a bar
-- that is cut back from the END of the health fill (reverse, one anchor on the fill's end, on the health's own
-- scale) and trimmed to the filled health by the same mask as the overheal - nothing compares the two here.
do
    local ha = f.healAbsorb
    ok(ha ~= nil and ha ~= f.absorb and ha ~= f.overheal, "a cell has its own band for healing they cannot take")
    local endOfFill = false
    for _, p in ipairs(ha.points or {}) do
        if p[1] == "TOPRIGHT" and p[2] == f.bar:GetStatusBarTexture() and p[3] == "TOPRIGHT" then endOfFill = true end
    end
    ok(endOfFill, "it hangs off the END of the health fill, so it moves with their health")
    ok(ha.__reverse == true or (ha.GetReverseFill and ha:GetReverseFill()) == true,
       "and fills leftwards, back into the health")

    STATE.healAbsorb.party1 = 900
    STATE.healAbsorbSecret = false
    FG.Paint(f)
    ok(ha.__value == 900, "it is handed how much healing they cannot take")
    STATE.healAbsorbSecret = true
    ok(pcall(FG.Paint, f), "a SECRET heal absorb does not throw")
    ok(getmetatable(ha.__value) == secretMeta, "it is handed the secret itself, untouched")
    STATE.healAbsorb.party1 = nil
    STATE.healAbsorbSecret = false
    FG.Paint(f)
    ok(ha.__value == 0, "when it is gone the band empties")

    -- a client without the call: nothing breaks, the band stays as it was
    local realHA = _G.UnitGetTotalHealAbsorbs
    _G.UnitGetTotalHealAbsorbs = nil
    ok(pcall(FG.Paint, f), "a client with no heal-absorb call still paints")
    _G.UnitGetTotalHealAbsorbs = function() error("refused") end
    ok(pcall(FG.Paint, f), "a call that refuses still paints")
    _G.UnitGetTotalHealAbsorbs = realHA

    -- the test switch forces a third, then lets go
    local realTime = _G.GetTime
    _G.GetTime = function() return 100 end
    FG.healAbsorbTest = 105
    FG.Paint(f)
    ok(ha.__value == 0.33, "/bish healabsorb test forces the band to a third")
    FG.healAbsorbTest = 99
    FG.Paint(f)
    ok(ha.__value == 0, "and after 10 seconds it shows the truth again")
    FG.healAbsorbTest = nil
    _G.GetTime = realTime

    ok(FG.UNIT_EVENTS and table.concat(FG.UNIT_EVENTS, " "):find("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", 1, true),
       "a heal absorb landing or breaking repaints that cell at once")
    ok(NS.SHORT.healabsorb and #NS.SHORT.healabsorb <= 4, "/bish healabsorb has a short word")
end

-- INSIDE THE CELL, AND THE OVERHEAL AS A FEATURE (6 Oct 2026). Arn's screenshot: a Chain Heal on
-- its way ran the green bar straight out of the cell and over the next one - and he used that spill
-- to hold a cast until the heal would not be wasted. So the heal and the shield are clipped to the
-- EMPTY part of the bar, and the overheal is drawn inside the FILLED part: a bar filling from the
-- right edge by the incoming amount, clipped to the fill, shows only where incoming is more than
-- missing. The client does that geometry - nothing here compares a heal with a health.
do
    local function clips(fr) return fr and fr.__clips == true end
    local function anchoredTo(fr, point, rel, relPoint)
        for _, p in ipairs(fr.points or {}) do
            if p[1] == point and p[2] == rel and p[3] == relPoint then return true end
        end
        return false
    end
    local tex = f.bar:GetStatusBarTexture()

    -- THE SHORT SPILL LANE (Arn, 7 Oct, picking "both": the heal may stick out past the edge so an
    -- overheal is SEEN, but only FG.LANE pixels - never across the next cell)
    local function anchoredAt(fr, point, rel, relPoint, x)
        for _, p in ipairs(fr.points or {}) do
            if p[1] == point and p[2] == rel and p[3] == relPoint and (p[4] or 0) == x then return true end
        end
        return false
    end
    ok(f.incoming.__parent == f.healClip and clips(f.healClip),
       "the heals on their way sit inside a frame that clips")
    -- (Arn, same evening: "in the bar of different color" - the lane went to 0; the overheal is
    -- the band over the health, below, and nothing leaves the cell)
    ok(FG.LANE == 0 and anchoredAt(f.healClip, "BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 0),
       "which stops at the cell's right edge - the overheal is shown inside the bar", FG.LANE)
    ok(f.absorb.__parent == f.missClip and anchoredAt(f.missClip, "BOTTOMRIGHT", f.bar, "BOTTOMRIGHT", 0),
       "the shield keeps the cell's own edge too")
    ok(anchoredTo(f.missClip, "TOPLEFT", tex, "TOPRIGHT") and anchoredTo(f.missClip, "BOTTOMRIGHT", f.bar, "BOTTOMRIGHT"),
       "and that frame is the EMPTY part of the bar: from the end of the fill to the right edge")

    ok(f.overheal ~= nil, "a cell has an overheal bar")
    -- BOLD, AND TICKED (Arn: the 70% amber read as "a little line"): solid orange-red, and a white
    -- tick on the left edge of the overheal's own fill - where the wasted part begins
    local oc = f.overheal.__color
    ok(oc and oc[1] >= 0.9 and oc[2] <= 0.3 and oc[3] >= 0.7, "the overheal band is a bold magenta - never a damage red, and off every class colour")
    -- AND IT STANDS OFF EVERY CLASS COLOUR, since it is drawn ON one (the classic nine)
    do
        local CLASSES = { WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
            HUNTER = { 0.67, 0.83, 0.45 }, ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 },
            SHAMAN = { 0.00, 0.44, 0.87 }, MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 },
            DRUID = { 1.00, 0.49, 0.04 } }
        local nearest, who = 9, nil
        for k, c in pairs(CLASSES) do
            local d = math.sqrt((oc[1] - c[1]) ^ 2 + (oc[2] - c[2]) ^ 2 + (oc[3] - c[3]) ^ 2)
            if d < nearest then nearest, who = d, k end
        end
        ok(nearest >= 0.4, "the band is far from every class colour (nearest: " .. tostring(who) .. ")", nearest)
    end
    ok(f.overTick ~= nil, "a white tick marks where the overheal begins")
    ok(f.overTick and f.overTick.__color and f.overTick.__color[1] == 1 and f.overTick.__w == 2,
       "white, 2 px")
    ok(f.overheal ~= f.incoming, "its own bar, not the heal bar reused")
    -- A MASK, NOT A CLIP (8 Oct 2026). `/bish overheal test` forced the band on and Arn saw nothing:
    -- a clip frame anchored to a secret-sized fill draws no children (EllesmereUI's note; it only
    -- ever showed on the tot, which was Arn - his own health is not secret). So: never under a
    -- frame that clips, and trimmed by a mask laid over the filled part instead.
    local p, underClip = f.overheal.__parent, false
    while p do if clips(p) then underClip = true end p = p.__parent end
    ok(not underClip, "the band is under NO clipping frame - that is what drew nothing in game")
    ok(f.overheal.__parent == f.bar, "it is a child of the health bar, as EllesmereUI's backfill is")
    ok(anchoredTo(f.curClip, "TOPLEFT", f.bar, "TOPLEFT") and anchoredTo(f.curClip, "BOTTOMRIGHT", tex, "BOTTOMRIGHT"),
       "curClip is the FILLED part's shape: from the left edge to the end of the fill")
    ok(f.curMask and f.curMask.__isMask and f.curMask.__allpoints == f.curClip,
       "a mask texture covers exactly that shape")
    ok(f.curMask and f.curMask.__texture == "Interface\\Buttons\\WHITE8X8",
       "a plain white mask (clamped, so it bounds instead of smearing)")
    local bandFill = f.overheal:GetStatusBarTexture()
    local function masked(t) for _, m in ipairs(t and t.__masks or {}) do if m == f.curMask then return true end end end
    ok(masked(bandFill) and masked(f.overTick), "the band's fill and its tick both carry the mask")
    ok(f.overheal.__reverse == true, "it fills from the RIGHT")
    ok(anchoredTo(f.overheal, "TOPRIGHT", f.bar, "TOPRIGHT"), "starting at the cell's right edge")
    ok(f.overheal.__w == f.incoming.__w, "as wide as the heal bar, so the two are on one scale")

    STATE.incoming.party1 = 700
    STATE.incomingSecret = true
    ok(pcall(FG.Paint, f), "a secret heal paints the overheal without throwing")
    ok(getmetatable(f.overheal.__value) == secretMeta,
       "the overheal bar is handed the same secret, untouched - the client works out the overlap")
    -- two secrets are never ==, each UnitHealthMax call is its own; same KIND of max is the claim
    ok(f.overheal.__max ~= nil and getmetatable(f.overheal.__max) == getmetatable(f.incoming.__max)
       and (getmetatable(f.incoming.__max) == secretMeta or f.overheal.__max == f.incoming.__max),
       "on the same scale as the heal bar")
    STATE.incoming.party1 = nil
    STATE.incomingSecret = false
    FG.Paint(f)
    ok(f.overheal.__value == 0, "nothing coming, no overheal drawn")

    -- the half-width pyramid cells resize every bar, the shield included (it was left out)
    local sized = true
    for _, b in ipairs({ "incoming", "absorb", "overheal" }) do
        if f[b].__w ~= f.incoming.__w then sized = false end
    end
    ok(sized, "after a layout every bar in the cell is the same width")
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
ok(f:GetAlpha() == 0.30, "out of range dims the cell - to 30% on a fresh install (Arn, 7 Oct)")
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

    -- THE LONGEST REACH WINS (Arn, 7 Oct: "check all the healing spells and use that range the
    -- biggest one"). Ties keep the hand's order (above); a longer heal anywhere beats it.
    STATE.spellRange["Lesser Healing Wave"] = 30
    d.binds = { ["left"] = "Lesser Healing Wave(Rank 1)", ["shift-button5"] = "Chain Heal(Rank 1)" }
    ok(NS.FM.RangeSpell() == "Chain Heal", "a 40 yd heal on a thumb beats a 30 yd one on left click",
       tostring(NS.FM.RangeSpell()))
    -- not even bound: the class's own heals are asked too, if trained (shaman: Healing Wave)
    d.binds = { ["left"] = "Lesser Healing Wave(Rank 1)" }
    -- (the shaman's own heals in their fixed order: Healing Wave, Lesser Healing Wave, Chain Heal -
    -- the first 40 yd one wins every time, never by chance)
    ok(NS.FM.RangeSpell() == "Healing Wave", "a trained class heal that is not bound still counts",
       tostring(NS.FM.RangeSpell()))
    -- a DAMAGE spell has a range too, and answers nil about a friend: never chosen, however long
    STATE.spellRange["Chain Heal"] = 50
    STATE.harmful["Chain Heal"] = true
    d.binds = { ["left"] = "Lesser Healing Wave(Rank 1)", ["wheelup"] = "Chain Heal(Rank 1)" }
    ok(NS.FM.RangeSpell() ~= "Chain Heal", "a spell the client says is not helpful is never the range spell",
       tostring(NS.FM.RangeSpell()))
    STATE.spellRange, STATE.harmful = {}, {}

    -- an empty mouse on a healer still measures, with the class heal it has trained...
    d.binds = {}
    ok(NS.FM.RangeSpell() == "Healing Wave", "an empty mouse on a healer measures with a trained heal",
       tostring(NS.FM.RangeSpell()))
    -- ...and a class with no heal of its own says "nothing", rather than naming something
    local realClass = UnitClass
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
    ok(NS.FM.RangeSpell() == nil, "an empty mouse on a class with no heals measures nothing",
       tostring(NS.FM.RangeSpell()))
    UnitClass = realClass
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
    -- AND IT IS THE RIGHT NUMBER. "a number" was satisfied by a spellbook ROW for months: slots and
    -- ids are both numbers, so the old assertion held while the call was being handed the wrong one.
    -- The mock's ids are 1000 + slot, so a slot leaking through is unmistakable.
    ok(asked and asked > 1000, "and it is the spell's id, not its row in the spellbook",
       tostring(asked))

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
-- /bish cpu (10 Oct 2026, Arn: "make it /bish cpu so i dont paste"), against the client's profiler
-- in its real shape: GetAddOnMetric(name, Enum.AddOnProfilerMetric.X) -> a number
do
    local keep = { P = _G.C_AddOnProfiler, E = _G.Enum, A = _G.C_AddOns, chat = _G.DEFAULT_CHAT_FRAME }
    local ADDONS = { { "Ace3", 5, 581.7, 0.2 }, { "BiSHealing", 0, 12.0, 0.08 }, { "Questie", 9, 240.0, 0.5 } }
    _G.Enum = setmetatable({ AddOnProfilerMetric = { PeakTime = 1, RecentAverageTime = 2, CountTimeOver100Ms = 3 } },
                           { __index = keep.E })
    _G.C_AddOnProfiler = { GetAddOnMetric = function(name, m)
        for _, a in ipairs(ADDONS) do
            if a[1] == name then return ({ [3] = a[2], [1] = a[3], [2] = a[4] })[m] end
        end
        return 0
    end }
    _G.C_AddOns = setmetatable({ GetNumAddOns = function() return #ADDONS end,
                                 GetAddOnInfo = function(i) return ADDONS[i][1] end,
                                 IsAddOnLoaded = function() return true end }, { __index = keep.A })
    local heard = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    local rows, ours = NS.DO.cpu()
    ok(rows and rows[1].name == "Questie" and rows[2].name == "Ace3",
       "/bish cpu ranks the addons by how often they hitch")
    ok(ours and ours.spikes == 0 and ours.peak == 12.0, "and adds up the BiS family on a line of its own")
    ADDONS[3][2] = 12
    heard = {}
    NS.DO.cpu()
    local said = table.concat(heard, "\n")
    ok(said:find("+3 since you last asked", 1, true) and said:find("(none new)", 1, true),
       "asked again, it says which are still hitching and which have stopped", said)
    _G.C_AddOnProfiler = nil
    heard = {}
    ok(pcall(NS.DO.cpu) and table.concat(heard):find("no addon profiler", 1, true),
       "a client without the profiler gets a sentence, not an error")
    _G.C_AddOnProfiler, _G.Enum, _G.C_AddOns, _G.DEFAULT_CHAT_FRAME = keep.P, keep.E, keep.A, keep.chat
end
-- /bish overheal (8 Oct: Arn sees only green, never the band). It must survive secrets, and its
-- test mode must really force the band, or it diagnoses nothing.
do
    local keptChat = _G.DEFAULT_CHAT_FRAME
    local heard = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    ok(pcall(NS.DO.overheal), "/bish overheal prints what the band is made of, without throwing")
    local all = table.concat(heard, "\n")
    ok(all:find("fills from the right", 1, true) and all:find("widths:", 1, true),
       "and names the facts that decide whether it can show", all)
    ok(pcall(NS.DO.overheal, "test") and FG.overhealTest, "/bish overheal test arms the forced band")
    -- what it SAYS: Arn's paste read "60%%" and "orange-red" after the band went magenta
    local said = heard[#heard] or ""
    ok(said:find("60% ", 1, true) and not said:find("%%", 1, true) and said:find("magenta", 1, true),
       "and says 60% (not 60%%) and the band's real colour", said)
    local cell = FG.frames and FG.frames[1]
    if cell and cell.unit then
        FG.Paint(cell)
        ok(cell.overheal:GetValue() == 0.6 and select(2, cell.overheal:GetMinMaxValues()) == 1,
           "and the next paint draws it at 60% from the right")
    end
    FG.overhealTest = nil
    _G.DEFAULT_CHAT_FRAME = keptChat
end
-- NO DOUBLE RES (10 Oct 2026, Rez.lua). RezComm puts every BiS user's res casts on BiSInnervate's
-- pipe; BiS Healing now listens, and a dead cell says who is already ressing them.
do
    local FZ = NS.FZ
    ok(FZ and FZ.frame and FZ.frame.__events and FZ.frame.__events.CHAT_MSG_ADDON,
       "the res watch listens for addon messages")
    local realName = _G.UnitName
    -- names the way the client gives them: name, then realm as a SECOND return
    local NAMES = { player = "Arn", party1 = "Kumlust", party2 = "Chain" }
    _G.UnitName = function(u) return NAMES[u], nil end
    FZ.claims = {}
    STATE.dead.party1 = true
    ok(FG.StatusWord("party1") == "DEAD", "a corpse nobody is ressing says DEAD")
    ok(FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", "Chain-Dreamscythe"),
       "a res claim from another healer is taken")
    ok(FG.StatusWord("party1") == "rez: Chain", "and the dead cell says who is ressing them",
       tostring(FG.StatusWord("party1")))
    -- only the claimer can free it; anyone else's RFREE is not theirs to send
    FZ.OnMessage("BiSInn", "4|RFREE|Kumlust", "PARTY", "Someoneelse")
    ok(FG.StatusWord("party1") == "rez: Chain", "another player cannot clear Chain's claim")
    FZ.OnMessage("BiSInn", "4|RDONE|Kumlust", "PARTY", "Chain")
    ok(FG.StatusWord("party1") == "DEAD", "the res lands (RDONE): back to DEAD until they accept")
    FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", "Chain")
    FZ.OnMessage("BiSInn", "4|RFREE|Kumlust", "PARTY", "Chain")
    ok(FG.StatusWord("party1") == "DEAD", "a res that failed or was stopped (RFREE) clears it")
    -- a claim that never hears back does not stick
    FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", "Chain")
    TICK(FZ.HOLD + 1)
    ok(FG.StatusWord("party1") == "DEAD", "a claim nobody followed up goes after " .. FZ.HOLD .. " s")
    -- what it ignores
    ok(not FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", "Arn"), "your own claim (you know)")
    ok(not FZ.OnMessage("BiSInn", "5|RCLAIM|Kumlust", "PARTY", "Chain"), "another protocol's message")
    ok(not FZ.OnMessage("DBM-Core", "4|RCLAIM|Kumlust", "PARTY", "Chain"), "another addon's message")
    ok(not FZ.OnMessage("BiSInn", secret(), "PARTY", "Chain")
       and not FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", secret()),
       "a message or sender the client hides (chat lockdown) is dropped, never guessed")
    -- a corpse whose NAME is hidden cannot be matched: it stays DEAD
    FZ.OnMessage("BiSInn", "4|RCLAIM|Kumlust", "PARTY", "Chain")
    _G.UnitName = function() return secret() end
    ok(FG.StatusWord("party1") == "DEAD", "a hidden name is never matched to a claim")
    _G.UnitName = function(u) return NAMES[u], nil end
    -- LEAN: another addon's chatter costs one question each
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local n = Cost.Count(function()
        for _ = 1, 500 do FZ.frame.__scripts.OnEvent(FZ.frame, "CHAT_MSG_ADDON", "DBM-Core", "x", "RAID", "Chain") end
    end)
    ok(n <= 500, "500 other addons' messages cost at most one client question each: " .. n)
    -- BiS Healing CARRIES RezComm too, byte for byte the family's copy, so its own res casts are told
    local function bytes(p) local fh = io.open(p, "rb") if not fh then return nil end local b = fh:read("*a") fh:close() return b end
    local mine, canon = bytes("Libs/RezComm-1.0/RezComm-1.0.lua"), bytes("../_bisdev/RezComm-1.0/RezComm-1.0.lua")
    ok(mine and (not canon or mine == canon), "the embedded RezComm is the canonical copy (run _bisdev/sync.ps1)")
    -- (the suite skips Libs lines - each lib has its own suite - so this one is loaded by hand)
    local loaded = pcall(function() assert(loadfile("Libs/RezComm-1.0/RezComm-1.0.lua"))() end)
    ok(loaded and _G.BiSRezComm and _G.BiSRezComm.MINOR, "and it loads in this client's shape")
    -- RezComm minor 4 (12 Oct 2026, debt 37): a claim is never thrown into a lockdown, and the
    -- client's "try again" is heard. Minor 5 (18 Oct): the realm's "restricted" is NOT a block -
    -- Forever says plain true while it delivers (Arn's /run), and minor 4 held every claim on it
    local RC = _G.BiSRezComm
    local keepCI = _G.C_ChatInfo
    _G.C_ChatInfo = { InChatMessagingLockdown = function() return true end }
    local okL, whyL = RC.MaySend()
    _G.C_ChatInfo = { InChatMessagingLockdown = function() return secret() end }
    local okS = RC.MaySend()
    _G.C_ChatInfo = { AreOutgoingAddonChatMessagesRestricted = function() return true end }
    local okB, whyB = RC.MaySend()
    _G.C_ChatInfo = keepCI
    ok(okL == false and whyL == "chat lockdown", "RezComm holds a claim in the chat lockdown")
    ok(okS == false, "and when the client hides whether chat is locked")
    ok(okB == true and whyB == nil, "Forever's 'restricted' (always true) does not hold a claim")
    ok(RC.Again(3) and RC.Again(8) and not RC.Again(0) and not RC.Again(nil) and not RC.Again(true),
       "a throttle answer means try again; success (or no answer, 2.5.x) does not")
    FZ.claims = {}
    STATE.dead.party1 = nil
    _G.UnitName = realName
end
-- THE SHARED BIS CHANNEL (0.13.0; Arn, 18 Oct: "Can we add the library to bis healing?") - a healer
-- running only BiS Healing never shared a spot with the guild's map
do
    local function bytes(p) local fh = io.open(p, "rb") if not fh then return nil end local b = fh:read("*a") fh:close() return b end
    local mine, canon = bytes("Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua"), bytes("../_bisdev/LibBiSComm-1.0/LibBiSComm-1.0.lua")
    ok(mine and (not canon or mine == canon), "the embedded LibBiSComm is the canonical copy (run _bisdev/sync.ps1)")
    local toc = bytes("BiSHealing.toc") or ""
    ok(toc:find("Libs\\LibBiSComm-1.0\\LibBiSComm-1.0.lua", 1, true) ~= nil, "the TOC loads it")
    local loaded, err = pcall(function() assert(loadfile("Libs/LibBiSComm-1.0/LibBiSComm-1.0.lua"))() end)
    local lib = _G.LibBiSComm
    ok(loaded and lib and lib.MINOR == 18, "LibBiSComm minor 18 loads in this client's shape", tostring(err))
    if lib then
        ok(NS.Comm.Boot() and lib:AddonsBlob():find("BiSHealing", 1, true), "booted at login, BiS Healing named in it",
           lib:AddonsBlob())
        -- /biscomm share off survives a logout
        lib:SetSharing(false)
        NS.Comm.Save()
        ok(NS.DB().commShare == false, "share off is saved")
        lib:SetSharing(true)
        NS.Comm.Boot()
        ok(lib:Sharing() == false, "and the next login keeps it off")
        lib:SetSharing(true)
        NS.Comm.Save()
        ok(NS.DB().commShare == true, "share on again")
    end
end
-- AND SHOWS ITS WORKING (7 Oct). Arn read "Healing Wave" and could not tell if that was the
-- longest or just the left click - the line still said "left click first". The yards settle it.
do
    local keptChat, keptRange = _G.DEFAULT_CHAT_FRAME, STATE.spellRange
    local heard = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    STATE.spellRange = { ["Healing Wave"] = 40 }
    NS.DO.range()
    _G.DEFAULT_CHAT_FRAME, STATE.spellRange = keptChat, keptRange
    local first = heard[1] or ""
    ok(first:find("40 yd", 1, true) ~= nil, "/bish range names the yards of the heal it picked", first)
    ok(first:find("left click first", 1, true) == nil, "and no longer claims the old left-click rule", first)
    local when
    for _, t in ipairs(heard) do if t:find("when:", 1, true) then when = t end end
    ok(when and (when:find("UNIT_IN_RANGE_UPDATE", 1, true) or when:find("every", 1, true)),
       "/bish range says WHEN range is asked: on the game's signal, or the old beat", when)
end

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
-- A PET OR AN NPC IS NO "FIRST NAME + SURNAME" (Arn, 8 Nov, Wailing Caverns: a pet cell that said only "The"). The
-- surname rule is for players; anything else keeps the whole words that fit in the 12
do
    local keepUIP = _G.UnitIsPlayer
    _G.UnitName = function() return "The Rake" end
    ok(FG.ShortName("partypet1") == "The Rake", "a pet keeps its whole name, not 'The'", FG.ShortName("partypet1"))
    _G.UnitIsPlayer = function() return false end
    _G.UnitName = function() return "Deviate Raptor" end
    ok(FG.ShortName("target") == "Deviate", "an NPC: whole words that fit, never cut mid-word", FG.ShortName("target"))
    _G.UnitName = function() return "Disciple of Naralex" end
    ok(FG.ShortName("target") == "Disciple", "and never ending on a little word ('Disciple of')", FG.ShortName("target"))
    _G.UnitIsPlayer = function() return true end
    _G.UnitName = function() return "Kumlust Surname" end
    ok(FG.ShortName("party1") == "Kumlust", "a player still loses the surname")
    _G.UnitIsPlayer = keepUIP
end
_G.UnitName = function(u) return "Name-" .. tostring(u) end

-- the name must draw ABOVE the bar: a FontString created on the button sits under the bar, which
-- reads as "the names are missing" in game
ok(FG.frames[1].name ~= nil, "a cell has a name label")
ok(rawequal(FG.frames[1].__nameParent, FG.frames[1].bar) or FG.frames[1].name ~= nil,
   "the label belongs to the bar, so it draws over it")
-- AND OVER EVERY BAND ON IT (Arn, 0.8.3: "magenta over laps the numbers"): the words and the role
-- icon live on an ink layer above the overheal, the shield and the incoming heal
do
    local c = FG.frames[1]
    local ink = c.ink
    ok(ink and ink.__parent == c.bar, "the ink layer rides on the health bar (dims with it)")
    ok(c.htext.__parent == ink and c.name.__parent == ink and c.role.__parent == ink,
       "the number, the name and the role icon are on it")
    local inkL = ink and ink:GetFrameLevel() or 0
    local over = 0
    for _, b in ipairs({ c.overheal, c.absorb, c.incoming }) do
        if b and b:GetFrameLevel() > over then over = b:GetFrameLevel() end
    end
    ok(inkL > over, "and it is above every band - the overheal cannot paint over the number",
       inkL .. " vs " .. over)
end

-- The grid runs on whatever client it finds. Until 19 Sep this began "if not NS.SECRET then
-- return false" - stand aside, this client keeps the pyramid - and there is no pyramid now.
do
    local realSecret = NS.SECRET
    FG.anchor = nil                          -- let Start() run again for this check
    NS.SECRET = false                        -- a client that answers every question freely
    ok(FG.Start() == true, "the grid starts on a client that hides nothing, too")
    NS.SECRET = realSecret
end

-- A /RELOAD IN A FIGHT (Arn, 11 Nov 2026: "how is vuhdo able to redraw fine after a reload, and ellesmere ... in
-- combat"). The client lets secure frames be laid out while the loading events are handed out; the lockdown is back
-- before the first update tick. So the grid lays out INSIDE PLAYER_LOGIN (FG.Start) and PLAYER_ENTERING_WORLD.
do
    ok(FG.startLaidOut == true, "the grid's first layout happened inside the login itself, not on a later tick")
    local keepLayout, keepCombat = FG.Layout, STATE.inCombat
    local calls, laid = 0, nil
    FG.Layout = function(a) calls = calls + 1 laid = keepLayout(a) return laid end
    STATE.inCombat = false                   -- the loading window: the lockdown not back yet
    fire(FG.events, "PLAYER_ENTERING_WORLD")
    STATE.inCombat = true                    -- and back right after it
    ok(calls == 1 and laid == true, "PLAYER_ENTERING_WORLD lays the grid out right then, while the window is open", calls)
    local okFight = pcall(fire, FG.events, "PLAYER_ENTERING_WORLD")
    ok(okFight and calls == 2 and laid == false, "the same event with the lockdown already on: refused quietly, left for the fight's end")
    FG.Layout, STATE.inCombat = keepLayout, keepCombat
end

-- THE ROSTER KEPT (Arn, 11 Nov 2026: "do the roster macro trick like vuhdo"). A relog in a fight can come back before
-- the game knows the group; the shape written down at the pull lays the grid out, in the loading window only.
do
    local FK = NS.FK
    local keep = { raid = _G.IsInRaid, info = _G.GetRaidRosterInfo, time = _G.time, macros = MACROS,
                   combat = STATE.inCombat, members = _G.GetNumGroupMembers }
    local WALL = 1762900000
    _G.time = function() return WALL end
    MACROS = { [121] = { name = "Heal Focus", body = "/cast [@focus] Healing Wave\n" } }   -- the player's own, untouched
    STATE.inCombat = false
    local groupOf = { 1, 1, 2, 2, 2, 3 }
    _G.IsInRaid = function() return true end
    _G.GetRaidRosterInfo = function(i) if groupOf[i] then return "n" .. i, 0, groupOf[i] end return nil end
    _G.GetNumGroupMembers = function() return #groupOf end
    FK.rosterShape = nil
    ok(FK.SaveRoster() == true, "in a raid, out of a fight: the shape is written")
    local idx = FK.FindRoster()
    local body = idx and MACROS[idx].body
    ok(idx and idx > 120 and body == "BiSR R " .. WALL .. " 112223" .. string.rep("0", 34) .. "\n" and MACROS[121].body:find("focus"),
       "in this character's own macro BiSHealingRoster (the client's newline and all), the player's macro left alone", body)
    local d = NS.DB()
    ok(d.rosterSnap == "BiSR R " .. WALL .. " 112223" .. string.rep("0", 34), "and in the saved variables (there at a /reload before the macro list is)")
    local snap = FK.RosterDecode(body)
    ok(snap and snap.kind == "R" and snap.at == WALL and snap.subs[3] == 2 and snap.subs[6] == 3 and snap.subs[7] == 0,
       "it reads back: each raid index's group (the trailing newline is no trouble)")
    WALL = WALL + 30
    ok(FK.SaveRoster() == false and MACROS[idx].body == body, "nothing changed: not written again (no macro edit a roster event)")
    ok(FK.SaveRoster(true) == true and MACROS[idx].body:find(tostring(WALL), 1, true), "the pull: written fresh even unchanged")
    STATE.inCombat = true
    groupOf[7] = 4
    ok(FK.SaveRoster(true) == false, "never in a fight")
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local inFight = Cost.Count(function() FK.SaveRoster() end)
    ok(inFight <= 1, "a roster event in a fight: one question (the lockdown) and out", inFight)
    STATE.inCombat = false
    local quiet = Cost.Count(function() FK.SaveRoster() end)
    FK.rosterShape = nil
    ok(quiet <= 22, "out of a fight, a 7-player raid that changed: its slots read once (the size asked first), then one macro edit", quiet)
    -- the pull itself, through the event (it comes just before the lockdown)
    WALL = WALL + 30
    fire(FK.rosterEvents, "PLAYER_REGEN_DISABLED")
    ok(MACROS[idx].body:find("1122234", 1, true) and MACROS[idx].body:find(tostring(WALL), 1, true), "PLAYER_REGEN_DISABLED writes it")
    -- THE LOAD: the game says nobody is with you (no raid, no party member it knows yet)
    keep.units = STATE.units
    STATE.units = { player = keep.units.player or true }
    _G.IsInRaid = function() return false end
    _G.GetRaidRosterInfo = function() return nil end
    WALL = WALL + 60
    local r = FK.RosterAtLoad()
    ok(r and r.kind == "R" and r.subs[7] == 4, "a minute later: the kept shape is fresh")
    FG.loading = true
    local roster = FG.Roster()
    FG.loading = nil
    ok(#roster == 7 and roster[1] == "raid1" and roster[7] == "raid7" and FG.snapSubs, "loading, and the game knows no group: the grid lays out the kept raid")
    local units, place = FG.ByGroup(roster)
    ok(units[1] == "raid1" and units[3] == "raid3" and place[3].col == 2 and place[7].col == 4 and place[7].row == 1,
       "in their kept groups: a column per group, raid7 alone in group 4", place[7] and place[7].col)
    local later = FG.Roster()
    ok(#later == 1 and later[1] == "player" and FG.snapSubs == nil, "not loading: the game's answer only (you alone)")
    WALL = WALL + FK.ROSTER_FRESH + 1
    FG.loading = true
    ok(#FG.Roster() == 1 and FK.RosterAtLoad() == nil, "a shape older than 15 minutes: not trusted")
    FG.loading = nil
    -- the macro newer than the saved variables wins (a disconnect: the macro was written, the save never was)
    WALL = WALL + 10
    d.rosterSnap = "BiSR P " .. (WALL - 500) .. " 2"
    MACROS[idx].body = "BiSR P " .. (WALL - 5) .. " 4\n"
    r = FK.RosterAtLoad()
    ok(r and r.kind == "P" and r.n == 4, "the newer of the macro and the saved variables wins")
    FG.loading = true
    roster = FG.Roster()
    FG.loading = nil
    ok(#roster == 5 and roster[5] == "party4", "a kept party: you and four")
    ok(FK.RosterDecode("BiSR R 1 12") == nil and FK.RosterDecode("hello") == nil, "anything else in the macro is ignored")
    -- alone, with no macro yet: no character slot spent on nothing
    MACROS = {}
    FK.rosterShape = nil
    ok(FK.SaveRoster() == false and FK.FindRoster() == nil and NS.DB().rosterSnap:find("^BiSR S"), "alone: saved, but no macro made for it")
    _G.IsInRaid, _G.GetRaidRosterInfo, _G.time, MACROS, STATE.inCombat = keep.raid, keep.info, keep.time, keep.macros, keep.combat
    _G.GetNumGroupMembers = keep.members
    STATE.units = keep.units
    NS.DB().rosterSnap, FK.rosterShape = nil, nil
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
    -- AND WITH THE GRID HIDDEN (Arn 8 Nov: "when i tried to do my heals on the ellesmere frames my binds used to work on
    -- that"): the wheel is a mouseover binding over ANY addon's frames, so a hidden grid must not leave it dead
    local dd = NS.DB()
    local keepShown = dd.shown
    dd.shown = false
    BOUND = {}
    FG.Layout(anchor)
    ok(BOUND["MOUSEWHEELUP"] ~= nil, "the grid hidden (/bish hide), a fresh layout: the wheel is still armed for other frames",
       tostring(BOUND["MOUSEWHEELUP"]))
    dd.shown = keepShown
    FG.Layout(anchor)
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
    -- and NOT over Blizzard's windows (Arn's cousin, 14 Oct: the quest window opened under the grid):
    -- MEDIUM, Blizzard's own layer, high inside it - a Blizzard window raises itself over it on open
    ok(FG.anchor.__strata == "MEDIUM" and FG.anchor.__level == FG.LEVEL,
       "the grid is high in Blizzard's own layer: over the bars, under a window that opens", tostring(FG.anchor.__strata))

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
    -- THEN SIXES, NOT EIGHTS (Arn, 19 Oct: "the bottom one end up being so crowded with the debuff
    -- stuff" - a 40 px cell with two cure boxes down its side had six letters of name)
    ok(rows(40) == "1,2,4,4,6,6,6,6,5", "a 40-man: a pair, two rows of four, then sixes", rows(40))
    -- AND SPREAD EVENLY (Arn, 19 Oct: "row 5 still randomly smaller than the rest" - six at 55 over a
    -- last five stretched to 66)
    ok(rows(25) == "1,2,4,4,5,5,4", "a 25-man: its fourteen spread 5, 5, 4", rows(25))
    ok(rows(22) == "1,2,4,4,6,5", "twenty-two: 6 and 5", rows(22))
    local uneven
    for n = 12, 40 do
        local w0
        for _, q in ipairs(FG.Pyramid(n)) do
            if q.row >= 5 then
                w0 = w0 or q.w
                if q.w ~= w0 then uneven = n end
            end
        end
    end
    ok(uneven == nil, "every tail row is one width, whatever the raid's size", uneven)
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
    ok(tail * 3 <= mid * 2 + 6 and tail * 3 >= mid * 2 - 6,
       "and a row-five cell is two-thirds of a row-three cell", tail .. " vs " .. mid)
    -- room for the name beside nothing: two cure boxes down the side (18 px) leave a name its 36
    ok(tail >= 55, "a tail cell is 55 px - the cure boxes no longer eat the name", tail)

    -- EVERY PYRAMID CELL IS TALL, AND A SHORT TAIL SHARES THE LINE (Arn, 17 Oct: "it bother me
    -- that the bottoms row cuts off their names" ... and after IMAX: "no imax but we just make them
    -- taller enough for the names and move the debuff out of that row")
    local p16 = FG.Pyramid(16)
    local last, row4, apex = p16[16], p16[11], p16[1]
    ok(last.tall and row4.tall and apex.tall, "every row is tall, the apex too")
    ok(last.h == FG.CELL_H + FG.NAME_BAND and apex.h == last.h, "taller by the name's band, all alike", last.h)
    ok(last.y == row4.y + row4.h + FG.CELL_PAD, "and each row starts under the one above", last.y)
    ok(last.w > tail and last.w <= mid, "five in a tail row are wider than six, never wider than a cell",
       last.w .. " (six: " .. tail .. ", a cell: " .. mid .. ")")
    ok(math.abs((5 * last.w + 4 * 3) - span(2)) <= 5, "and they still end where the rows above end")
    ok(FG.Pyramid(40)[40].y == FG.Pyramid(40)[33].y + FG.CELL_H + FG.NAME_BAND + FG.CELL_PAD,
       "every tail row is tall, not just the last")
    ok(NS.DO.imax == nil, "the IMAX try-out is gone")

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
    ok(FG.anchor.__w == 3 * (84 + 3) - 3 and FG.anchor.__h == FG.CELL_H + FG.NAME_BAND,
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
    -- a tail cell after a real layout: tall, its name across the top, the boxes under it
    ok(small and small.__tall and small:GetHeight() == FG.CELL_H + FG.NAME_BAND,
       "a tail cell is laid out tall", small and tostring(small:GetHeight()))
    local nameL, nameR
    for _, pt in ipairs(small and small.name.points or {}) do
        if pt[1] == "TOPLEFT" then nameL = pt[2] elseif pt[1] == "TOPRIGHT" then nameR = pt[2] end
    end
    ok(nameL == 3 and nameR == -3, "its name runs the whole width, over the boxes",
       tostring(nameL) .. " / " .. tostring(nameR))
    local bx = small and small.cureBoxes and small.cureBoxes[1]
    if bx and bx:IsShown() then
        local by = bx.points and bx.points[#bx.points]
        ok(by and by[5] and -by[5] >= FG.NAME_BAND, "and its first cure box starts under the name",
           by and tostring(by[5]))
    end
    ok(big.__tall and big:GetHeight() == FG.CELL_H + FG.NAME_BAND, "and the wide ones above are tall too")

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
    -- NO CURE BOXES ON AN ENEMY (Arn, 23 Oct: "enemies are still getting poison boxes for me to debuff")
    if not t.auras and NS.FA and NS.FA.Attach then NS.FA.Attach(t, "target") FG.Paint(t) end
    ok(t.auras and t.auras:GetAlpha() == 0, "an enemy: its cure boxes and hots fade to nothing",
       t.auras and tostring(t.auras:GetAlpha()))

    STATE.hostile.target = false
    FG.Paint(t)
    ok(math.abs(t.bar.__color[1] - FG.HOSTILE[1]) > 0.01,
       "and a friendly one does not", t.bar.__color[1])
    ok(t.auras and t.auras:GetAlpha() == 1, "a friend: the boxes back")

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
    ok(t.auras and getmetatable(t.auras:GetAlpha()) == getmetatable(secret()),
       "in a fight the client picks the boxes' alpha from its own secret answer - never tested here")

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

    -- BIS> NOW SURVIVES A RESTART (5 Oct 2026). It never did. Every other block has ridden the
    -- macro since Keep.lua was written and this one was simply left out, so the headline feature of
    -- 0.8.0 - live on CurseForge since 0.8.1 - started again at EVERY login. This client hands back
    -- no SavedVariables at all (Keep.lua's header, proved six ways), so a setting that is not in the
    -- macro does not exist.
    --
    -- Driven the way the player drives it: turn it on, wipe the table the way a login wipes it, read
    -- the macro back. No FK.Encode by hand - that would test the engine and not the wiring, which is
    -- exactly how FN.Settle sat unreachable for a week.
    do
        MACROS = {}
        local keep = d.binds
        d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
        local FN = NS.FN

        FN.Reset()
        FN.Note("tremor") FN.Settle()          -- a fear happened; the button is earned
        NS.DO.now("left")

        -- IT SHOULD FEEL LIKE A BUTTON (5 Oct 2026). Arn: "they feel 2d id like if you hover over
        -- them it changes a little to give it a feel that its a button".
        --
        -- Driven through the scripts the client would call, on a button the addon really built -
        -- and the hover must be its OWN texture, because FN.Paint rewrites the icon's colour on
        -- every update from the client's answer about health. A tint on the icon would be gone
        -- within a frame, and fighting Paint would let a hover lie about how hurt somebody is.
        do
            local btn = FN.buttons and FN.buttons.help
            ok(btn ~= nil, "the help button is built")
            if btn then
                ok(btn.hover ~= nil, "it has a hover texture of its own, separate from the icon")
                ok(btn.hover.__blend == "ADD",
                   "added rather than laid over, so a dim or red icon still lifts",
                   tostring(btn.hover.__blend))
                ok(btn.hover.__alpha == 0, "invisible until hovered", tostring(btn.hover.__alpha))

                -- HOOKED, NOT SET: the secure template's own OnEnter is what makes you the
                -- mouseover, and `/ping [@mouseover] assist` aims at exactly that.
                ok(btn.__hooked and btn.__hooked.OnEnter,
                   "the hover is HOOKED onto the template's OnEnter, not put in its place")

                btn.__wasMouseover = nil
                btn.__scripts.OnEnter(btn)
                ok(btn.hover.__alpha > 0, "hovering lights it", tostring(btn.hover.__alpha))
                ok(btn.__wasMouseover == true,
                   "and the template's own OnEnter still ran - the button is still the mouseover,"
                   .. " which is what /ping [@mouseover] aims at")

                btn.__scripts.OnMouseDown(btn)
                ok(btn.art.__point and btn.art.__point[2] ~= 0,
                   "and pressing moves the icon, so the click is felt")
                local pressed = btn.hover.__alpha

                btn.__mouseOver = true
                btn.__scripts.OnMouseUp(btn)
                ok(btn.art.__point[2] == 0 and btn.art.__point[3] == 0, "letting go puts it back")
                ok(btn.hover.__alpha < pressed and btn.hover.__alpha > 0,
                   "still lit while the mouse is on it", tostring(btn.hover.__alpha))

                -- a press that ends with the mouse somewhere else must not leave it stuck lit or
                -- stuck pressed
                btn.__scripts.OnMouseDown(btn)
                btn.__scripts.OnLeave(btn)
                ok(btn.hover.__alpha == 0, "leaving puts it out")
                ok(btn.art.__point[2] == 0, "and un-presses an icon the mouse was dragged off")
            end
        end

        local nowBody = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
        ok(nowBody and nowBody:find("R=3", 1, true), "the now block goes into the macro", nowBody)
        ok(nowBody and nowBody:find("R=3:", 1, true),
           "with the button order in the same row, not a row of its own", nowBody)

        -- the login: the table is empty and nothing has been clicked
        d.now, d.nowAt, d.nowPos = nil, nil, nil
        d.binds, d.bindsSeeded, NS.FM.asked = {}, nil, false
        FN.Reset()
        ok(FN.Earned("tremor") == false, "a fresh table has earned nothing")

        NS.FM.Get("", "wheelup")
        ok(d.now == true, "the block comes back on", tostring(d.now))
        ok(d.nowAt == "left", "on the side it was put", tostring(d.nowAt))
        ok(FN.Earned("tremor") == true,
           "and the Tremor button is still earned - a fear last week is not forgotten at login")

        -- PUT THE BENCH BACK. Leaving the block on "left" made thirteen later tests fail, because
        -- they ask which sides are free and this one had quietly taken one.
        d.now, d.nowAt, d.nowPos = nil, nil, nil
        d.binds = keep
        MACROS = {}
        FN.Reset()
    end

    -- a group with no other healer in it shows nothing at all, rather than an empty box
    STATE.roles = { player = "DAMAGER", party1 = "DAMAGER" }
    NS.DO.mana(true)
    ok(not FG.manaAnchor:IsShown(), "no healers, no block")
    STATE.roles = nil
    d.mana = false
    FG.Layout(FG.anchor)
end

-- THE "ME" CELL IS RETIRED (Arn, 8 Nov 2026: "in the cells remove the me option" - picked "retire it"). It was a
-- player's request (paszczyszyn, 25 Sep: a cell for yourself, out of the group); now you are always in your group's
-- column, an old save or an old macro that had it on included, and /bish me only says so.
do
    local d = NS.DB()
    d.me, d.meAt = true, "left"                      -- a save from before, with the cell on
    FG.Layout(FG.anchor)
    ok(FG.me == nil or not FG.me:IsShown(), "an old save with the cell on: no cell of your own")
    ok(table.concat(FG.Roster(), " "):find("player", 1, true), "and you are in the group grid")
    -- an old macro's "me" row (Y=1) is read and ignored
    MACROS = {}
    local keptBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 2)" }
    NS.FK.Save(d.binds)
    local body = GetMacroBody(GetMacroIndexByName(NS.FK.MACRO))
    ok(body and not body:find("Y=", 1, true), "a new save writes no \"me\" row", body)
    local idx = GetMacroIndexByName(NS.FK.MACRO)
    MACROS[idx].body = MACROS[idx].body:gsub("#", "#Y=3;", 1)       -- what a 1.0.0 macro could hold
    d.binds, d.bindsSeeded, NS.FM.asked, d.me = {}, nil, false, false
    NS.FM.Get("", "wheelup")
    ok(d.me ~= true, "an old macro with the cell on does not bring it back", tostring(d.me))
    d.binds = keptBinds
    MACROS = {}
    -- the command only says so, and puts back anyone who still had it
    d.me = true
    local heardMe, realChatMe = {}, _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heardMe[#heardMe + 1] = t end }
    ok(NS.DO.me() == false and d.me == false, "/bish me: retired, and switched off for an old save")
    _G.DEFAULT_CHAT_FRAME = realChatMe
    ok((heardMe[#heardMe] or ""):find("retired", 1, true), "and it says so", heardMe[#heardMe])
    -- the options: the cells row is target, tot and mana
    local parts = {}
    for _, o in ipairs(NS.UI.Rows()) do
        if o.key == "cells" then for _, p in ipairs(o.parts or {}) do parts[#parts + 1] = p.key end end
    end
    ok(table.concat(parts, ",") == "target,tot,mana", "the cells row has no \"me\"", table.concat(parts, ","))
    d.me = false
    FG.Layout(FG.anchor)
end

-- TWO BLOCKS NEVER SHARE A SIDE. Arn, 26 Sep, with one bar reading "BiS> meget" - the target's
-- word and yours printed through each other: "if target is already taking up the top and i also
-- turn on me dont overlap them send them to the next available slot".
do
    local d = NS.DB()
    d.target, d.mana, d.tot, d.pets = false, false, false, "off"
    d.targetAt, d.manaAt, d.petAt = "top", "left", "under"
    FG.Layout(FG.anchor)

    NS.DO.target("top")
    NS.DO.mana("top")                                  -- asking for a side that is already taken
    ok(d.targetAt == "top", "the block that was there first keeps its place", tostring(d.targetAt))
    ok(d.manaAt ~= "top", "and the one arriving does not land on it", tostring(d.manaAt))
    ok(FG.TARGET_SPOTS[d.manaAt], "it lands on a real side", tostring(d.manaAt))
    ok(d.manaAt == "right", "the next one round the ring", tostring(d.manaAt))

    -- AND THE OTHER WAY ROUND: yours there first, the target arriving. Tested both ways because
    -- each block is a separate line in the "is anyone here?" question, and a test that only ever
    -- collides one pair one way leaves the other line free to be deleted.
    NS.DO.target(false)
    NS.DO.mana("top")
    NS.DO.target("top")
    ok(d.manaAt == "top" and d.targetAt ~= "top",
       "yours first, and the target cell is the one that moves",
       ("mana %s, target %s"):format(tostring(d.manaAt), tostring(d.targetAt)))

    -- TWO SIDES TAKEN, so the walk has to step more than once. With only one in use, a ring walk
    -- that gives up immediately lands on the same answer as one that looks properly.
    NS.DO.mana("top")
    NS.DO.target("right")
    NS.DO.pets("own")
    d.petAt = "top"                                  -- and now ask it to sit on an occupied side
    NS.DO.pets("own")
    ok(d.petAt == "under",
       "with top and right in use, the third block walks past both",
       ("pets %s, me %s, target %s"):format(tostring(d.petAt), tostring(d.manaAt), tostring(d.targetAt)))
    ok(d.petAt ~= d.targetAt and d.petAt ~= d.manaAt,
       "and lands on a side neither of the others is on")

    -- SWITCHED ON WITH A PLAIN yes, which is what the options window sends: the remembered side
    -- may be somebody else's by now, and nothing in that path passes through a spot word.
    NS.DO.mana(false)
    d.manaAt = "right"                                 -- where the target block is sitting
    NS.DO.mana(true)
    ok(d.manaAt ~= "right", "switching it on with no side named still avoids the others",
       ("mana %s, target %s"):format(tostring(d.manaAt), tostring(d.targetAt)))
    -- and the target cell, switched on the same way, onto a side yours is already using
    NS.DO.target(false)
    d.targetAt = d.manaAt
    NS.DO.target(true)
    ok(d.targetAt ~= d.manaAt, "and so does the target cell, switched on the same way",
       ("target %s, me %s"):format(tostring(d.targetAt), tostring(d.manaAt)))
    -- AND THE PET BLOCK IS SOMETHING TO AVOID, not just something that avoids. It is the only
    -- block that is not a single cell, and it was the last line of the question to be written.
    NS.DO.pets("own")
    NS.DO.mana(false)
    d.manaAt = d.petAt
    NS.DO.mana(true)
    ok(d.manaAt ~= d.petAt, "a block is in the way of others, as well as avoiding them",
       ("mana %s, pets %s"):format(tostring(d.manaAt), tostring(d.petAt)))
    NS.DO.pets("off")

    -- a shift-click walks past an occupied side too, rather than stopping on it
    local h = FG.manaAnchor.handle
    STATE.shift = true
    h.dragged = nil
    h.__scripts.OnMouseUp(h, "LeftButton")
    STATE.shift = false
    ok(d.manaAt ~= d.targetAt and d.manaAt ~= d.petAt,
       "shift-clicking round the ring skips the sides in use",
       ("mana %s, target %s, pets %s"):format(tostring(d.manaAt), tostring(d.targetAt), tostring(d.petAt)))

    -- "FREE" IS NOT A SIDE, it is wherever a drag put it - so any number of blocks can be free at
    -- once and none of them is ever in another's way.
    NS.DO.mana(false)
    NS.DO.pets("off")
    NS.DO.target("top")                              -- one block in play, so the answer is its own
    ok(FG.SpotTaken("top", FG.PET_KEYS) == true, "a block ON a side is in the way")
    ok(FG.SpotTaken("free", FG.PET_KEYS) == false, "but nothing is ever in the way of a drag")
    d.targetAt, d.targetPos = "free", { x = 10, y = 10 }
    ok(FG.SpotTaken("top", FG.PET_KEYS) == false, "and one that was dragged away leaves its side")
    ok(FG.SpotTaken("free", FG.PET_KEYS) == false, "even to another block being dragged")

    d.target, d.mana, d.tot, d.pets = false, false, false, "off"
    d.targetAt, d.manaAt, d.petAt, d.manaPos, d.targetPos = "top", "left", "under", nil, nil
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
    ok(found and found.kind == "step" and found.min == 0.5 and found.max == 2 and found.label == "size",
       "the options window has a stepper for it (50-200%: the radar's range; the cells' setter keeps theirs)")
    local keepS = d.scale
    found.set(d, 2)
    ok(d.scale == FG.SCALE_MAX, "the cells never go past their own limit, whatever the stepper asks", d.scale)
    d.scale = keepS
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
    -- TALL like every other cell (Arn, 18 Oct: "still not on the target and tot")
    ok(t and t.__tall and t:GetHeight() == FG.CELL_H + FG.NAME_BAND,
       "tall like the grid: the name on top, the cure boxes under it", t and tostring(t:GetHeight()))
    ok(t and t.__nameAt and t.__nameAt:find("t", 1, true) ~= nil, "the name placed across the top", t and tostring(t.__nameAt))
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
    -- 3 (the cells' own gap) + 2 (a bar floats above its cell) + 16 (the bar). Was 3 + 1 + 14
    -- until 1 Oct, when a block's bar grew to match the grid's own - they sat side by side at
    -- different heights and read as a mistake.
    ok(dropOf() == -21, "and it drops by exactly its bar plus the grid's own gap", dropOf())
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

    -- A FIGHT MID-DRAG (8 Nov 2026, the drag audit after BiS Tools' boss window held Arn's mouse until he killed the
    -- game). The target block is a SECURE frame: inside the lockdown the client will not let go of it, so a mouse-up
    -- that comes in the fight is refused and the block rides the cursor all fight. The drag must END at
    -- PLAYER_REGEN_DISABLED - the moment before the lockdown - and where it was dropped is kept.
    STATE.strandedDrag = nil
    d.targetPos = nil
    h.__scripts.OnDragStart(h)
    ok(t.__moving, "the target block is being dragged when the pull comes")
    fire(FG.unitEvents, "PLAYER_REGEN_DISABLED")
    STATE.inCombat = true
    h.__scripts.OnDragStop(h)                                      -- the button comes up inside the fight
    STATE.inCombat = false
    ok(not t.__moving and not STATE.strandedDrag, "the pull ENDS the drag: the block is not left on the cursor",
       tostring(STATE.strandedDrag))
    ok(d.targetPos and d.targetPos.x == -300 and d.targetPos.y == -100,
       "and where it was dropped is kept, written before the lockdown",
       d.targetPos and ("%s,%s"):format(d.targetPos.x, d.targetPos.y))
    -- the grid's own header: the anchor holds every secure cell, so it is protected too
    local gh = FG.header
    local gx3, gy3 = anchorScreenXY()
    gh.__scripts.OnDragStart(gh)
    ok(FG.anchor.__moving, "the whole grid is being dragged when the pull comes")
    fire(FG.unitEvents, "PLAYER_REGEN_DISABLED")
    STATE.inCombat = true
    gh.__scripts.OnDragStop(gh)
    STATE.inCombat = false
    ok(not FG.anchor.__moving and not STATE.strandedDrag, "and the grid's drag ends at the pull too",
       tostring(STATE.strandedDrag))
    local gx4, gy4 = anchorScreenXY()
    ok(math.abs(gx4 - gx3) < 1 and math.abs(gy4 - gy3) < 1, "and the grid stays where it was dropped",
       ("%s,%s -> %s,%s"):format(gx3, gy3, gx4, gy4))
    -- a fight that starts with nothing dragged touches nothing
    fire(FG.unitEvents, "PLAYER_REGEN_DISABLED")
    ok(not STATE.strandedDrag and not t.__moving and not FG.anchor.__moving, "a pull with no drag on: nothing to end")

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
        ok(tt.__tall and tt:GetHeight() == FG.target:GetHeight(), "tall, the same as the target cell beside it",
           tostring(tt:GetHeight()))
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
        bookSaid()

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
        bookSaid()
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
        bookSaid()

        -- a secret ANSWER to "is it secret?" is itself an unknown, not a no
        _G.C_Secrets.ShouldSpellAuraBeSecret = function() return secret() end
        ok(FS.Present("Water Shield") == nil,
           "a secret answer about secrecy is unknown, not permission")
        _G.C_Secrets.ShouldSpellAuraBeSecret = function() error("no such call", 2) end
        ok(FS.Present("Water Shield") == nil, "and so is an error")

        -- THE SHIELD BUTTON (12 Oct 2026): Fojji's "combat back door". A container slot filtered to
        -- Water Shield is drawn by the client while it is up; a red square underneath shows when it
        -- is not. Nothing is read, so it holds in a fight. It was a badge on the grid header first;
        -- Arn: "header too crowded" - so it is the face of a BiS> now button that casts the buff.
        -- What can be tested is what is DECLARED and the order things sit in; whether the client
        -- covers the red is for Arn's screen (it did, on the header).
        do
            local Cost = dofile("../_bisdev/dev/cost.lua")
            local FA, FN = NS.FA, NS.FN
            local d = NS.DB()
            local keepNow, keepShown = d.now, d.shown
            d.now, d.shown = true, true
            STATE.lazyAuras = true
            -- the client answers again (the checks above left it refusing every question)
            _G.C_Secrets.ShouldSpellAuraBeSecret = function(id) return hidden[id] and true or false end
            -- THE CLIENT'S NUMERIC FORMATTER, in its real shape: breakpoints of { threshold, format },
            -- refused when a point is malformed. `__pick` is the mock's stand-in for the client
            -- choosing a format for a number nobody else may see.
            local keepSU = _G.C_StringUtil
            _G.C_StringUtil = setmetatable({ CreateNumericRuleFormatter = function()
                local f = {}
                function f:SetBreakpoints(points)
                    for _, p in ipairs(points) do
                        if type(p.threshold) ~= "number" or type(p.format) ~= "string" then
                            error("bad breakpoint", 2)
                        end
                    end
                    self.points = points
                end
                function f:__pick(n)
                    local out
                    for _, p in ipairs(self.points or {}) do if n >= p.threshold then out = p.format end end
                    return out
                end
                return f
            end }, { __index = keepSU })
            FN.Reset()
            FN.DropShield()
            FS.badgeSig = nil
            local before = #CONTAINERS
            FS.Badge()                                   -- what the buff list says -> BiS> now laid out
            local sb = FN.buttons and FN.buttons.shield
            ok(sb and sb:IsShown(), "BiS> now has a shield button")
            ok(#CONTAINERS == before + 1, "with one container", #CONTAINERS - before)
            ok(sb and sb:GetAttribute("*type1") == "macro" and sb:GetAttribute("*macrotext1") == "/cast Water Shield",
               "a click casts Water Shield", sb and sb:GetAttribute("*macrotext1"))
            ok(sb and sb.art and not sb.art:IsShown(), "the static icon is hidden: the badge is the face")
            local b = sb and sb.badge
            local c = b and b.container
            local slot = c and c.slots and c.slots.BiSHealSelf
            ok(b and b.under:GetParent() == sb and c.__parent == sb, "red and container sit on the button")
            ok(c and c.unit == "player" and c.enabled, "the container watches YOU, and is switched on")
            ok(slot and slot.filter == "HELPFUL" and slot.opts.candidateFilters.includeSpellIDs[24398],
               "its slot is filtered to every Water Shield id the book has")
            local red = b and b.under.red
            ok(b and b.under:IsShown() and red and red.__texture == _G.C_Spell.GetSpellTexture(24398)
               and red.__desat == true and red.__vertex and red.__vertex[1] > 0.8 and red.__vertex[2] < 0.4,
               "underneath: the Water Shield icon itself, greyed and tinted red",
               red and (tostring(red.__texture) .. " " .. tostring(red.__desat)))
            ok(b and b.under:GetFrameLevel() < c:GetFrameLevel(),
               "and sits BELOW the container, so the client's icon covers it while the shield is up",
               b and (b.under:GetFrameLevel() .. " vs " .. c:GetFrameLevel()))
            -- IT BREATHES (Arn: "lets not make it a red static thing can we show like a pulsing
            -- thing?"): the client's animation, looping, never down to nothing
            local p = b and b.under.pulse
            local fade = p and p.anims[1]
            ok(p and p:IsPlaying() and p.looping == "BOUNCE", "the red pulses, on the client's own loop")
            ok(fade and fade.kind == "Alpha" and fade.from == 1 and fade.to >= 0.3 and fade.to < 1
               and fade.duration and fade.duration > 0,
               "from full to a dim that is still plainly there, and back",
               fade and (tostring(fade.from) .. " -> " .. tostring(fade.to)))
            -- /bish buff SAYS which half failed (Arn, 12 Oct: "water shield on did not turn it on")
            local rep = table.concat(FS.BadgeReport(), "\n")
            ok(rep:find("filter 24398", 1, true) and rep:find("has not drawn it yet", 1, true),
               "the report names the filter ids, and that no button has come", rep)
            mine[1] = { name = "Water Shield", spellId = 52127 }
            rep = table.concat(FS.BadgeReport(), "\n")
            ok(rep:find("id 52127 - NOT in the filter", 1, true),
               "a buff whose id is not the book's is named as the reason", rep)
            mine[1] = { name = "Water Shield", spellId = 24398, applications = 3 }
            rep = table.concat(FS.BadgeReport(), "\n")
            ok(rep:find("in the filter", 1, true) and not rep:find("NOT in", 1, true), "and a match says so", rep)
            ok(rep:find("3 charges (full counts as 3)", 1, true),
               "and out of combat it says the charges, so 'full' can be checked against the game", rep)
            mine[1] = nil
            ok(slot and slot.__init and pcall(slot.__init, slot),
               "nothing waited for the button: the client hands it over when the buff appears")
            -- THE BUTTON COMES BLANK (Arn, 12 Oct: shield up, badge still red, the button made):
            -- the icon is ours to paint, the spell's own
            local icon = b and b.icon
            ok(icon and icon.__texture ~= nil and icon.__texture == _G.C_Spell.GetSpellTexture(24398),
               "our own icon is painted on the client's button, from the spell", icon and tostring(icon.__texture))
            -- CHARGES AS A COLOUR (Arn: "normal icon and its down to 2 or 1 charge we change to
            -- orange yellow etc"): the client picks the wash, we never read the count
            local fmt = slot.countOpts and slot.countOpts.formatter
            ok(slot.countText and b.wash == slot.countText and fmt, "the client is handed a font string and a formatter")
            local function rgbOf(s) local r, g, bl = (s or ""):match(":(%d+):(%d+):(%d+)|t$") return tonumber(r), tonumber(g), tonumber(bl) end
            ok(fmt and fmt:__pick(3) == "" and fmt:__pick(5) == "", "full charges: no wash, the plain icon")
            local y1, y2, y3 = rgbOf(fmt and fmt:__pick(2))
            ok(y1 == 255 and y2 and y2 > 180 and y3 < 60, "2 charges: yellow", fmt and fmt:__pick(2))
            local o1, o2, o3 = rgbOf(fmt and fmt:__pick(1))
            ok(o1 == 255 and o2 and o2 < 160 and o2 > 60 and o3 < 60, "1 charge: orange", fmt and fmt:__pick(1))
            ok(fmt and fmt:__pick(0) == "", "none: no wash (the buff is gone, the red shows)")
            -- TOO BIG ON PURPOSE, CUT TO THE ICON (Arn's screenshots: the wash hung half again past
            -- the button). A frame on the client's button, its size, clipping
            local big = b.px * FS.WASH_OVER
            ok(fmt and (fmt:__pick(2) or ""):find(":" .. big .. ":" .. big .. ":", 1, true) and big > b.px,
               "the square is drawn bigger than the icon", fmt and fmt:__pick(2))
            local clip = b.washClip
            ok(clip and clip.__clips == true and clip.__parent == slot and clip.__allpoints == slot,
               "and cut to exactly the icon by a clipping frame on the client's button")
            ok(slot.clicks == false, "the client's button lets clicks through to ours")
            -- and THAT BUTTON REFUSES QUESTIONS from our code (Arn's client: "calling '?' on bad
            -- self ... self:IsVisible()"); the report must survive it
            for _, m in ipairs({ "IsVisible", "IsShown", "GetWidth", "GetFrameLevel" }) do
                slot[m] = function() error("Attempt to access forbidden object from code tainted by an AddOn", 2) end
            end
            local okR, lines = pcall(FS.BadgeReport)
            rep = okR and table.concat(lines, "\n") or tostring(lines)
            ok(okR and rep:find("made its button (visible refused)", 1, true) and rep:find("our icon on it: made", 1, true),
               "a forbidden button is reported as refused, never thrown", rep)
            ok(FS.badgeFor["Water Shield"], "the badge stands for Water Shield")

            -- THE WORDS GO IN THE TOOLTIP (one bar, one label)
            sb.__scripts.OnEnter(sb)
            ok(TIP.lines[1] == "Water Shield" and table.concat(TIP.lines, "|"):find("click to cast", 1, true),
               "hovering says what it is and that a click casts it", table.concat(TIP.lines, "|"))
            ok(sb.__wasMouseover, "and the secure template's own OnEnter still ran")

            -- ONE LABEL: the header word does not say what the button already shows
            up[24398] = nil
            FS.state, FS.known = {}, nil
            FS.Check()
            ok(FS.known and FS.known[1] == "Water Shield", "the shield IS missing (so the next check bites)")
            ok(FS.Word() == nil, "with a live button the header word stays quiet", tostring(FS.Word()))

            -- built once: a relayout for anything else (an oil, a new member) rebuilds nothing
            local n = #CONTAINERS
            FN.Layout(); FN.Layout(); FS.Badge()
            ok(#CONTAINERS == n, "laid out again, nothing is rebuilt", #CONTAINERS - n)

            -- IN A FIGHT, never built - asked again when it ends
            FN.DropShield()
            FS.badgeSig = nil
            STATE.inCombat = true
            FS.Badge()
            ok(#CONTAINERS == n and FS.badgeLater, "in a fight no container is made; it waits")
            STATE.inCombat = false
            FS.frame.__scripts.OnEvent(FS.frame, "PLAYER_REGEN_ENABLED")
            ok(#CONTAINERS == n + 1 and not FS.badgeLater and FN.buttons.shield.badge,
               "and is built the moment the fight ends")

            -- LEAN: your auras change many times a second in a fight; the badge hears none of it
            local calls, realBadge = 0, FS.Badge
            FS.Badge = function(...) calls = calls + 1 return realBadge(...) end
            STATE.inCombat = true
            local cost = Cost.Count(function()
                for _ = 1, 300 do FS.frame.__scripts.OnEvent(FS.frame, "UNIT_AURA", "player") end
            end)
            STATE.inCombat = false
            FS.Badge = realBadge
            ok(calls == 0, "300 aura changes on you in a fight never touch the badge", calls)
            -- and the no-change answer it gives at every SPELLS_CHANGED is a short one
            local idle = Cost.Count(function() for _ = 1, 100 do FS.Badge() end end)
            ok(idle <= 800, "100 'anything changed?' asks cost at most 8 client calls each: " .. idle)
            print(("   cost: badge, unchanged x100 = %d calls; 300 combat auras = %d"):format(idle, cost))

            -- AT LOGIN, with nobody touching anything: the button wears its badge (cold start law)
            FN.DropShield()
            FS.badgeSig = nil
            FS.frame.__scripts.OnEvent(FS.frame, "PLAYER_ENTERING_WORLD")
            ok(FN.buttons.shield.badge and FN.buttons.shield:IsShown(),
               "a fresh login puts the badge on the shield button by itself")

            -- BiS> now SWITCHED OFF: no button, and the header word speaks again
            d.now = false
            FN.Layout()
            ok(#FS.badges == 0 and not FS.badgeFor["Water Shield"], "BiS> now off: no badge stands")
            FS.state, FS.known = {}, nil
            FS.Check()
            ok(FS.Word() == "no Water Shield", "and the header word takes over", tostring(FS.Word()))
            d.now = true

            -- A CLIENT THAT WILL NOT DRAW FOR US: no shield button at all - a face that is red for
            -- ever would be a lie - and the word speaks
            containersExist = false
            FA.available = nil
            FN.Layout()
            ok(not FN.buttons.shield:IsShown() and #FS.badges == 0, "no containers, no shield button")
            ok(FS.Word() == "no Water Shield", "and the header word speaks", tostring(FS.Word()))
            containersExist = true
            FA.available = nil

            -- THE CLIENT REFUSES THE BADGE AFTER THE BUTTON EXISTS (14 Oct, Arn in a battleground:
            -- an empty slot that still cast). The button keeps the spell's own picture.
            FN.Layout()
            local sb = FN.buttons.shield
            local keepMake = FS.MakeBadge
            FS.MakeBadge = function() return nil, "the client would not let the marker be placed" end
            FN.DropShield(sb)
            sb.shieldSig = nil
            if sb.art.Hide then sb.art:Hide() end
            FN.ArmShield(sb)
            ok(sb:IsShown() and sb.badge == nil and sb.art.__shown ~= false,
               "a refused badge: the button keeps its picture, never an empty slot")
            FS.MakeBadge = keepMake

            FN.DropShield()
            FS.badges, FS.badgeFor, FS.badgeSig = {}, {}, nil
            d.now, d.shown = keepNow, keepShown
            FN.Layout()
            FN.Reset()
            STATE.lazyAuras = nil
            _G.C_StringUtil = keepSU
        end

        _G.C_Secrets = realSecrets
        _G.C_SpellBook.GetSpellBookItemInfo = realInfo
        bookSaid()
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
    bookSaid()

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
    bookSaid()
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
    -- MEASURED 11 Nov 2026 (Arn's BiS? probe, out of a fight): an EMPTY slot answers true, "", 0, 0 - never false.
    -- A down totem: true, its name, the GetTime() it went down, its length (300 s).
    if TOTEMS[slot] then return true, "Totem", CLOCK, 300 end
    return true, "", 0, 0
end
-- GetTotemDuration (in the 16001 census): the client's duration object for a slot, fight or not - an opaque thing to
-- hand to a cooldown, never a number (ForeverAuras 1.3.9 drives its in-fight totem timers with it)
_G.GetTotemDuration = function(slot) return { __totemDuration = slot } end
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
    ok(not anyHot, "no heal-over-time slot for a spell this character has not trained")

    -- RIPTIDE: a shaman HAS a heal over time in this game mode, and the spellbook is what decides.
    -- Found in the Fojji shaman pack (3 Oct): this mode is a kit, not an era - Water Shield and
    -- Lava Burst from TBC, Riptide and Maelstrom from Wrath, Totemic Projection from Cata, and no
    -- Earth Shield. Nobody here knows its spell id, so the family is named and the book answers.
    do
        local keep = BOOK[30]
        BOOK[30] = { name = "Riptide", rank = "Rank 1" }
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "party1")
        local riptide = nil
        for k in pairs(cell.auras.slots) do if k == "BiSHealHotRiptide" then riptide = k end end
        ok(riptide ~= nil, "a shaman who has trained Riptide gets a marker for it", tostring(riptide))

        -- and the ids come from the BOOK, not from a list written on a TBC client
        local fam
        for _, f in ipairs(FA.Hots()) do if f.key == "Riptide" then fam = f end end
        ok(fam ~= nil and fam.ids == nil, "the family carries a name and no ids at all")
        local ids = FA.HotIds(fam)
        ok(ids[1030] == true, "and its id is read out of the spellbook", tostring(next(ids)))

        BOOK[30] = keep
        FA.sig = nil
        cell.auras = nil
    end

    -- CURE BOXES (Arn, 16 Oct 2026): "where we draw the markers right now we pre put tiny cells there
    -- for that raider with that cleanse ... always clickable ... when they get poison Blizz draws the
    -- icon we de alpha the button outline". One secure box per cure; one marker per box, narrowed to
    -- the types that spell removes; the bright outline made INSIDE the client's own marker.
    do
        local k29, k31 = BOOK[29], BOOK[31]
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "party1")
        ok(cell.auras.slots.BiSHealDispel ~= nil and not (cell.cureBoxes and cell.cureBoxes[1] and cell.cureBoxes[1]:IsShown()),
           "no cure in the book: the old dispel pip, no boxes")

        BOOK[29] = { name = "Cure Poison", rank = "" }
        BOOK[31] = { name = "Cure Disease", rank = "" }
        bookSaid()
        local cures = FA.Cures()
        ok(#cures == 2 and cures[1].name == "Cure Poison" and cures[2].name == "Cure Disease",
           "a shaman with both: two cures, poison first", #cures)
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "party1")
        local s1, s2 = cell.auras.slots.BiSHealCure1, cell.auras.slots.BiSHealCure2
        ok(s1 and s2 and cell.auras.slots.BiSHealDispel == nil, "one marker per cure, and no catch-all pip")
        ok(s1 and s1.filter == "HARMFUL|RAID_PLAYER_DISPELLABLE", "still only what YOU can dispel")
        local t1 = s1 and s1.opts.candidateFilters.includeDispelTypes or {}
        local t2 = s2 and s2.opts.candidateFilters.includeDispelTypes or {}
        ok(t1.Poison and not t1.Disease and t2.Disease and not t2.Poison,
           "the poison box lights for poison only, the disease box for disease only")
        ok(s1 and s1.cureGlow and s1.cureGlow.TOP, "the bright outline is made inside the client's marker - shown only when it is")
        -- LOUDER (Arn, 17 Oct: "hard to see with our cross hairs ... make the little boxes flash more")
        local glow = s1 and s1.cureGlowFrame
        ok(glow and glow.wash, "a teal wash behind the icon, not just an edge")
        -- Arn, 17 Oct: "cant really see it" - the box's own dim outline painted the bright one out
        local box1 = cell.cureBoxes and cell.cureBoxes[1]
        ok(glow and box1 and glow:GetFrameLevel() > box1:GetFrameLevel(),
           "the pulsing outline is drawn OVER the box, not under it",
           glow and box1 and (glow:GetFrameLevel() .. " vs " .. box1:GetFrameLevel()))
        local pulse = glow and glow.pulse
        ok(pulse and pulse.playing and pulse.looping == "BOUNCE", "and it pulses - the client runs it, no Lua per frame")
        -- the stack count, written by the client (Arn: "shows how many it is so i know i have to click")
        ok(s1 and s1.cureCount and s1.countText == s1.cureCount, "the client is handed a label for the stack count")
        ok(s1 and s1.cureCount and s1.cureCount:GetParent() ~= glow, "and it is not on the pulsing frame - it does not fade")
        local fade = pulse and pulse.anims[1]
        ok(fade and fade.to >= 0.2 and fade.to < 1, "bright to dim, never to nothing", fade and fade.to)
        ok(s1 and s1.clicks == false, "and the marker takes no clicks: they go to the box under it")

        local b1, b2 = cell.cureBoxes and cell.cureBoxes[1], cell.cureBoxes and cell.cureBoxes[2]
        ok(b1 and b2 and b1:IsShown() and b2:IsShown(), "two boxes on the cell")
        ok(b1 and b1:GetAttribute("type") == "spell" and b1:GetAttribute("spell") == "Cure Poison",
           "box one casts Cure Poison", b1 and b1:GetAttribute("spell"))
        ok(b2 and b2:GetAttribute("spell") == "Cure Disease", "box two casts Cure Disease")
        ok(b1 and b1:GetAttribute("useparent-unit") == true, "on whoever the cell holds - a rebind never touches it")
        ok(b1 and b1.dim and b1.dim.LEFT, "a dim outline says the corner cures, always")
        -- A COLUMN DOWN THE LEFT EDGE (Arn, 17 Oct: "use the left side as the debuff window")
        local size, x2, y2 = FA.CureBox(2)
        local _, x1, y1 = FA.CureBox(1)
        ok(x1 == x2 and y2 >= y1 + size, "the boxes stack, one under the other, never on each other")
        ok(y2 + size <= 34, "and two fit the 34 px cell top to bottom", y2 + size)
        ok(cell.cureLeft and cell.cureLeft >= x1 + size, "the name starts past the column", cell.cureLeft)
        local nameLeft
        for _, p in ipairs(cell.name and cell.name.points or {}) do
            if p[1] == "TOPLEFT" then nameLeft = p[2] end
        end
        -- a grid cell is TALL since 17 Oct ("do the same for the regular grid too"): its name has
        -- the top line, over the column; a short cell (target, your own) still starts past it
        ok(nameLeft == (cell.__tall and 3 or cell.cureLeft),
           cell.__tall and "a tall cell's name runs over the column" or "the cell's name is anchored there",
           tostring(nameLeft))
        ok(cell.name and cell.name.__justify == "CENTER", "and centred in the room left", cell.name and cell.name.__justify)
        local hot = cell.auras.slots.BiSHealHotRiptide
        if hot then ok(hot:OffsetFor("BOTTOMLEFT") >= cell.cureLeft, "heals over time sit beside the column too") end

        -- THE COCKPIT: A ROW, ABOVE THE TAPE (Arn, 8 Nov, Wailing Caverns: "the top debuff is fine but the bottom
        -- blocks the health grid"). The column's second box sat on the tape along the bottom; in the cockpit the boxes
        -- go side by side in the band between the name and the tape, and your heals over time beside them
        do
            local K, FGx = NS.FG.COCKPIT, NS.FG
            local keepLook = cell.__look
            local cellH = FGx.NAME_BAND + 34                     -- a grid cell is tall: the name band + 34
            local tapeTop = cellH - K.tapeIn - K.tapeH            -- from the cell's top
            local function at(b)
                for _, p in ipairs(b.points or {}) do
                    if p[1] == "TOPLEFT" then return p[4], -p[5] end
                end
            end
            cell.__look = "cockpit"
            FA.sig, cell.aurasSig = nil, nil
            FA.Attach(cell, "party1")
            local size = select(1, FA.CureBox(1))
            local x1, y1 = at(b1)
            local x2, y2 = at(b2)
            ok(y1 and y2 and y1 == y2 and x2 >= x1 + size, "cockpit: the two boxes side by side, not stacked",
               tostring(x1) .. "," .. tostring(y1) .. " / " .. tostring(x2) .. "," .. tostring(y2))
            ok(y2 and y2 + size <= tapeTop, "and both clear of the health tape",
               tostring(y2 and y2 + size) .. " <= " .. tapeTop)
            ok(cell.cureLeft and x2 and cell.cureLeft >= x2 + size, "whatever sits beside them starts past the row",
               tostring(cell.cureLeft))
            ok(FA.HotY(cell) >= K.tapeIn + K.tapeH, "your heals over time sit above the tape, not on it", FA.HotY(cell))
            ok(FA.HotY(cell) + FA.MarkerSize() <= cellH - FGx.NAME_BAND, "and under the name", FA.HotY(cell))
            -- back to classic: the column, as before
            cell.__look = "classic"
            FA.sig, cell.aurasSig = nil, nil
            FA.Attach(cell, "party1")
            x1, y1 = at(b1)
            x2, y2 = at(b2)
            ok(x1 == x2 and y2 >= y1 + size and FA.HotY(cell) == 3, "classic: the column down the left edge, as before")
            -- A LOOK SWITCH MOVES THEM (out of a fight): the redress rebuilds the markers
            local keepD = NS.DB().look
            NS.FG.frames = NS.FG.frames or {}
            local had = false
            for _, f in ipairs(NS.FG.frames) do if f == cell then had = true end end
            if not had then table.insert(NS.FG.frames, cell) end
            cell.unit = cell.unit or "party1"
            NS.DO.look("cockpit")
            x1, y1 = at(b1)
            x2, y2 = at(b2)
            ok(y1 == y2 and x2 > x1, "switching to the cockpit moves the boxes into the row at once")
            NS.DO.look(keepLook == "cockpit" and "cockpit" or "classic")   -- every cell dressed as it was
            NS.DB().look = keepD
            if not had then table.remove(NS.FG.frames) end
            cell.__look = keepLook
            FA.sig, cell.aurasSig = nil, nil
            FA.Attach(cell, "party1")
        end

        -- THE TARGET CELLS: BOXES ON A FRIEND, NEVER ON A FOE (Arn, 17 Oct: "its coming up on the
        -- enemy bars too"; 18 Oct: "im targeting my self im a friendly player and it no show the cure
        -- thing"). Whoever is targeted may be a foe and an addon may not show or hide a secure box in a
        -- fight - so the client does, by a state driver
        local tcell = { GetFrameLevel = function() return 5 end }
        for _, u in ipairs({ "pet", "partypet1", "raidpet3", "focus" }) do
            ok(not FA.CureUnit(u), u .. ": no cure boxes")
        end
        for _, u in ipairs({ "player", "party2", "raid17", "target", "targettarget" }) do
            ok(FA.CureUnit(u), u .. ": cure boxes")
        end
        FA.sig = nil
        local keepAuras = cell.auras
        cell.auras = nil
        FA.Attach(cell, "target")
        ok(cell.auras.slots.BiSHealCure1 ~= nil, "a target cell gets the cure markers")
        ok(DRIVEN[b1] == "[@target,help] show; hide" and DRIVEN[b2] == DRIVEN[b1],
           "and its boxes are the client's to show: only on someone you can help", tostring(DRIVEN[b1]))
        local hadTarget = STATE.units.target
        STATE.units.target = true
        HOSTILE.target = true
        DRIVE_TICK()
        ok(not b1:IsShown() and not b2:IsShown(), "targeting a foe: no boxes")
        HOSTILE.target = nil
        DRIVE_TICK()
        ok(b1:IsShown() and b2:IsShown(), "targeting a friend - yourself too: the boxes")
        STATE.units.target = hadTarget
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "targettarget")
        ok(DRIVEN[b1] == "[@targettarget,help] show; hide", "the target-of-target cell: its own unit's condition",
           tostring(DRIVEN[b1]))
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "party1")
        ok(DRIVEN[b1] == nil and b1:IsShown(), "back on a party cell: no driver, the boxes ours again")
        cell.auras = cell.auras or keepAuras
        tcell = nil

        -- A REUSED CELL (Arn, 17 Oct raid: "some boxes for debuffs not drawing"): the grid hands a
        -- cell that showed a pet to a raider without clearing it; the boxes must still come
        FA.Attach(cell, "raidpet1")
        ok(cell.auras.slots.BiSHealCure1 == nil and not b1:IsShown(), "a pet cell: no boxes")
        FA.Attach(cell, "raid3")
        ok(cell.auras.slots.BiSHealCure1 ~= nil and b1:IsShown(),
           "the same cell given to a raider: the boxes come back")
        ok(b1.dimDark ~= nil, "a dark edge under the purple one, seen on a light class colour")
        -- A TALL (pyramid tail) CELL: the name has the top, the column starts under it
        local w0 = cell.__w
        FG.FitCell(cell, 41, true)
        FA.Attach(cell, "raid3")
        local p1 = b1.points[#b1.points]
        ok(p1 and -p1[5] >= FG.NAME_BAND, "on a tall cell the first box starts under the name", p1 and tostring(p1[5]))
        local nl
        for _, pt in ipairs(cell.name.points) do if pt[1] == "TOPLEFT" then nl = pt[2] end end
        ok(nl == 3, "and the name is not pushed past the boxes", tostring(nl))
        FG.FitCell(cell, w0 or 84, false)
        FA.Attach(cell, "raid3")
        p1 = b1.points[#b1.points]
        ok(p1 and -p1[5] < FG.NAME_BAND, "back to an ordinary cell: the column goes back to the top")
        FA.Attach(cell, "party1")

        -- a fight: the boxes are not touched (secure), and the switch waits
        STATE.inCombat = true
        ok(FA.Boxes(cell, {}) == false, "in a fight the boxes are left as they are")
        STATE.inCombat = false

        -- switched off: the pip is back, the boxes go
        NS.DO.cures(false)
        ok(not b1:IsShown() and not b2:IsShown(), "/bish cures off: the boxes go")
        FA.sig = nil
        cell.auras = nil
        FA.Attach(cell, "party1")
        ok(cell.auras.slots.BiSHealDispel ~= nil and cell.auras.slots.BiSHealCure1 == nil, "and the old pip is back")
        NS.DO.cures(true)
        ok(b1:IsShown() and b1:GetAttribute("spell") == "Cure Poison", "/bish cures on: back")

        BOOK[29], BOOK[31] = k29, k31
        bookSaid()
        FA.sig = nil
        cell.auras = nil
    end

    -- A PRIEST: Renew, every rank, only the priest's own, with the client's countdown
    local realClass, realInfo, realName = _G.UnitClass, C_SpellBook.GetSpellBookItemInfo, C_Spell.GetSpellName
    _G.UnitClass = function() return "Priest", "PRIEST" end
    _G.C_Spell.GetSpellName = function(id) return id == 139 and "Renew" or nil end
    BOOK[6] = { name = "Renew", rank = "Rank 11" }
    _G.C_SpellBook.GetSpellBookItemInfo = function(n, bank)
        if type(bank) ~= "number" then error("bad argument", 2) end
        return n == 6 and { spellID = 99011 } or nil
    end
    bookSaid()
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
    bookSaid()
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
    -- A FULL SAVE MACRO SAYS SO (14 Oct 2026): binds that do not fit used to vanish at the next load
    -- with no word (Arn's cousin, a Nature's Swiftness bind "not saving")
    do
        local keepSave, from = NS.FK.Save, #SAID
        NS.FK.Save = function() return true, 2 end
        FM.Set("alt-", "button5", "Healing Wave")
        local said = table.concat(SAID, " / ", from + 1)
        ok(said:find("2 bind(s) did not fit in the save macro", 1, true), "binds that did not fit: said, with /bish keep to see which", said)
        from = #SAID
        NS.FK.Save = function() return true, 0 end
        FM.Set("alt-", "button5", "Healing Wave")
        ok(#SAID == from, "everything fits: nothing said")
        NS.FK.Save = keepSave
        FM.Clear("alt-", "button5")
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

    -- A CLICK ON THE DEAD RESES (Arn, 17 Oct 2026: "when someone is dead and out of combat if we
    -- click the cell does it default to res?" - it did not). The client decides, at the click.
    do
        ok(FM.ResSpell() == nil, "no res in the book: the heal binds stay plain spells")
        local k28 = BOOK[28]
        BOOK[28] = { name = "Ancestral Spirit", rank = "" }
        bookSaid()
        ok(FM.ResSpell() == "Ancestral Spirit", "a shaman who has trained it: Ancestral Spirit")
        FM.ApplyTo(cell)
        local m1 = cell.__attrs["*macrotext1"] or ""
        ok(cell.__attrs["*type1"] == "macro", "the left click becomes one macro")
        ok(m1:find("^/cast %[@mouseover,dead,nocombat%] Ancestral Spirit\n"),
           "dead and out of combat - the client's test, at the click - casts the res first", m1)
        ok(m1:find("\n/cast %[@mouseover%] Spell331$"), "anything else: the heal on the button, as before", m1)
        local m2 = cell.__attrs["*macrotext2"] or ""
        ok(m2:find("Lesser Healing Wave%(Rank 1%)$") and m2:find("Ancestral Spirit", 1, true),
           "every heal button, rank and all", m2)
        -- nocombat: a druid's Rebirth is never spent on a misclick mid-pull
        ok(m1:find("nocombat", 1, true) ~= nil, "never in a fight")
        -- a res on the button already: no res line in front of itself
        FM.Set("ctrl-", "left", "Ancestral Spirit")
        FM.ApplyTo(cell)
        ok(cell.__attrs["ctrl-type1"] == "spell" and cell.__attrs["ctrl-spell1"] == "Ancestral Spirit",
           "a res bound by hand stays exactly that")
        FM.Clear("ctrl-", "left")
        -- off
        NS.DO.res(false)
        ok(cell.__attrs["*type1"] == "spell" and cell.__attrs["*spell1"] == "Spell331", "/bish res off: plain heals again")
        NS.DO.res(true)
        ok(cell.__attrs["*type1"] == "macro", "/bish res on: back")
        -- DEAD, OUT OF COMBAT: EVERY CLICK RESES (Arn, 20 Oct 2026, his cousin: "when he clicked the frame of
        -- someone that had died, it did not res that person ... no matter what is binded") - an empty button
        -- targets, a ping pings: neither carried the res line
        do
            local keepUIP = _G.UnitIsPlayer
            _G.UnitIsPlayer = function() return true end
            local unit = cell.unit
            STATE.dead[unit] = true
            FG.Paint(cell)
            ok(cell.__res and cell.__attrs["*type1"] == "spell" and cell.__attrs["*spell1"] == "Ancestral Spirit",
               "dead, out of combat: the left click is the res itself", tostring(cell.__attrs["*spell1"]))
            ok(cell.__attrs["*type4"] == "spell" and cell.__attrs["*spell4"] == "Ancestral Spirit"
               and cell.__attrs["alt-type5"] == "spell" and cell.__attrs["alt-spell5"] == "Ancestral Spirit"
               and cell.__attrs["ctrl-macrotext3"] == nil,
               "every button, every modifier - the empty ones too")
            -- a fight starts: the binds come back before the lockdown (PLAYER_REGEN_DISABLED is the last chance)
            ok(fire(FM.resEvents, "PLAYER_REGEN_DISABLED"), "the fight's start reaches the res watcher")
            ok(not cell.__res and cell.__attrs["*type1"] == "macro", "a fight starts: your binds again, at once")
            STATE.inCombat = true
            FG.Paint(cell)
            ok(not cell.__res, "in the fight a dead cell stays as you bound it")
            STATE.inCombat = false
            fire(FM.resEvents, "PLAYER_REGEN_ENABLED")
            ok(cell.__res and cell.__attrs["*spell1"] == "Ancestral Spirit", "the fight over, still dead: all res again")
            -- they stand up
            STATE.dead[unit] = nil
            FG.Paint(cell)
            ok(not cell.__res and cell.__attrs["*type1"] == "macro" and cell.__attrs["*macrotext1"]:find("Spell331", 1, true),
               "up again: the binds come back")
            -- an enemy or a pet: never
            _G.UnitIsPlayer = function() return false end
            STATE.dead[unit] = true
            FG.Paint(cell)
            ok(not cell.__res, "not a player: no res")
            STATE.dead[unit] = nil
            _G.UnitIsPlayer = keepUIP
            FG.Paint(cell)
            -- DRUIDS GOT REVIVE ON FOREVER (Arn: "I think druids got a resurrection spell")
            local keepUC = _G.UnitClass
            _G.UnitClass = function() return "Druid", "DRUID" end
            BOOK[28] = { name = "Rebirth", rank = "" }
            bookSaid()
            -- Arn: "Let's not do rebirth unless they bind it ... that super long cooldown is ... for in combat battle rez"
            ok(FM.ResSpell() == nil, "a druid with only Rebirth: no res click - its long cooldown is never spent for you")
            BOOK[29] = { name = "Revive", rank = "" }
            bookSaid()
            ok(FM.ResSpell() == "Revive", "with Revive trained: Revive, the out-of-combat one")
            BOOK[29] = nil
            BOOK[28] = { name = "Ancestral Spirit", rank = "" }
            _G.UnitClass = keepUC
            bookSaid()
        end
        BOOK[28] = k28
        bookSaid()
        FM.ApplyTo(cell)
    end

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

        -- NATURE'S SWIFTNESS IN FRONT OF THE HEAL (Arn, 8 Oct: "finally got nature's swiftness ...
        -- when i press down a button it pops it before my big heal"). Dropped onto a slot that holds
        -- a heal, it rides in front of it; one press casts both.
        do
            local realInfo = _G.C_Spell.GetSpellInfo
            _G.C_Spell.GetSpellInfo = function(id)
                if id == 16188 then return { name = "Nature's Swiftness" } end
                return realInfo(id)
            end
            CURSOR = { kind = "spell", a = 40, b = "spell", c = 16188 }
            slot.__scripts.OnReceiveDrag(slot)
            ok(FM.Get("", "left") == "Nature's Swiftness+Spell331(Rank 4)",
               "Nature's Swiftness dropped on a heal goes IN FRONT of it, the heal and its rank kept",
               tostring(FM.Get("", "left")))
            local boost, heal = FM.Boost(FM.Get("", "left"))
            ok(boost == "Nature's Swiftness" and heal == "Spell331(Rank 4)", "and splits back into the two")
            local nm, rk = FM.Split(FM.Get("", "left"))
            ok(nm == "Spell331" and rk == "Rank 4", "the slot's NAME is still the heal's - its icon, ranks and range")
            w:Refresh()
            -- HALF AND HALF (Arn: the 10 px corner badge was "super tiny, maybe we make it like half
            -- ns/half the other spell"): the booster's left half over the heal, full height, a seam
            local bc = slot.boost.__coords
            ok(slot.boost.__shown and slot.seam.__shown and slot.boost.__w * 2 == slot.icon.__w
               and slot.boost.__h == slot.icon.__h and bc and bc[1] == 0 and bc[2] == 0.5,
               "the slot shows the booster as the LEFT HALF of the icon, the heal the right, a seam between")
            TIP.lines = {}
            slot.__scripts.OnEnter(slot)
            local tip = table.concat(TIP.lines, "|")
            ok(tip:find("Nature's Swiftness first", 1, true), "and its tooltip says it goes first", tip)

            -- IT SURVIVES A RESTART: the macro that keeps the binds carries it as one name
            local body = NS.FK.Encode({ left = FM.Get("", "left") }, {})
            local back = NS.FK.Decode(body)
            ok(back and back.left == "Nature's Swiftness+Spell331(Rank 4)",
               "written into the macro and read back whole", body)

            -- ONE PRESS, TWO CASTS: the guard, the booster, then the heal on whoever was clicked
            local cell = CreateFrame("Button", "BoostCell", UIParent, "SecureUnitButtonTemplate")
            FM.ApplyTo(cell)
            local mt = cell.__attrs["*macrotext1"] or ""
            ok(cell.__attrs["*type1"] == "macro"
               and mt == "/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]\n"
                      .. "/cast Nature's Swiftness\n/cast [@mouseover] Spell331(Rank 4)",
               "a click casts Nature's Swiftness, then the heal on that cell - never on a dead or hostile one", mt)
            ok(cell.__attrs["*spell1"] == nil, "and no stray spell attribute fights the macro")

            -- THE WHEEL, where Arn's heals live: guard, booster, heal - in that order
            FM.Set("", "wheelup", "Nature's Swiftness+Healing Wave(Rank 3)")
            FM.ApplyWheel(FG.anchor)
            local wb = _G["BiSHealWheelwheelup"]
            local wt = wb and wb.__attrs and wb.__attrs["macrotext"] or ""
            local g, b2, h = wt:find("/stopmacro", 1, true), wt:find("/cast Nature's Swiftness", 1, true),
                             wt:find("/cast [@mouseover] Healing Wave(Rank 3)", 1, true)
            ok(g and b2 and h and g < b2 and b2 < h, "on the wheel: the guard, then the booster, then the heal", wt)

            -- STEPPING THE RANK KEEPS IT IN FRONT
            FM.Set("", "right", "Nature's Swiftness+Healing Wave(Rank 1)")
            ok(FM.CycleRank("", "right") == "Nature's Swiftness+Healing Wave(Rank 2)",
               "the rank button steps the heal and keeps Nature's Swiftness", tostring(FM.Get("", "right")))
            -- AND RANGE IS STILL THE HEAL'S
            ok(FM.RangeSpell() ~= "Nature's Swiftness", "range is never measured with the booster")

            -- THE WAYS BACK: the heal dropped again is a plain heal; a booster on an empty slot is
            -- just the booster
            RANKS[331] = "Rank 4"
            CURSOR = { kind = "spell", a = 12, b = "spell", c = 331 }
            slot.__scripts.OnReceiveDrag(slot)
            ok(FM.Get("", "left") == "Spell331(Rank 4)", "dropping the heal again takes the booster off")
            FM.Clear("", "button4")
            CURSOR = { kind = "spell", a = 40, b = "spell", c = 16188 }
            w.slots["button4"].__scripts.OnReceiveDrag(w.slots["button4"])
            ok(FM.Get("", "button4") == "Nature's Swiftness", "on an empty slot it is just itself")

            -- TRINKETS FIRST (Arn, 10 Oct: "the old bis healing had ... popping trinkets before big
            -- heals"). A trinket you WEAR dropped on a heal: its slot rides in front, by slot number.
            FM.Set("", "left", "Nature's Swiftness+Healing Wave(Rank 3)")
            CURSOR = { kind = "item", a = 19950 }
            slot.__scripts.OnReceiveDrag(slot)
            ok(FM.Get("", "left") == "!use:13+Nature's Swiftness+Healing Wave(Rank 3)",
               "a worn trinket dropped on a heal goes first, by SLOT, the booster kept behind it",
               tostring(FM.Get("", "left")))
            CURSOR = { kind = "item", a = 11832 }
            slot.__scripts.OnReceiveDrag(slot)
            ok(FM.Get("", "left") == "!use:13+!use:14+Nature's Swiftness+Healing Wave(Rank 3)",
               "and the other trinket too, in slot order")
            -- an item you do not wear is not a trinket bind
            CURSOR = { kind = "item", a = 4242 }
            ok(not slot.__scripts.OnReceiveDrag(slot) and FM.Get("", "left"):find("^!use:13"),
               "an item you are not wearing is refused")
            CURSOR = {}
            local cell2 = CreateFrame("Button", "TrinketCell", UIParent, "SecureUnitButtonTemplate")
            FM.ApplyTo(cell2)
            ok(cell2.__attrs["*macrotext1"] == "/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]\n"
               .. "/use 13\n/use 14\n/cast Nature's Swiftness\n/cast [@mouseover] Healing Wave(Rank 3)",
               "one press: the guard, both trinkets, the booster, the heal", cell2.__attrs["*macrotext1"])
            ok(FM.CycleRank("", "left") == "!use:13+!use:14+Nature's Swiftness+Healing Wave(Rank 1)",
               "the rank button keeps everything in front", tostring(FM.Get("", "left")))
            local nm2 = FM.Split(FM.Get("", "left"))
            ok(nm2 == "Healing Wave", "and the slot's name is still the heal")
            local back2 = NS.FK.Decode(NS.FK.Encode({ left = FM.Get("", "left") }, {}))
            ok(back2 and back2.left == FM.Get("", "left"), "it survives a restart in the macro")

            -- PER MODIFIER TAB (Arn: "each tab ... has a check ... pop trinket 1 - 2 ... maybe even
            -- different for each modifier")
            FM.Set("", "left", "Healing Wave(Rank 3)")
            FM.Set("shift-", "left", "Healing Wave(Rank 3)")
            w.mod = "shift-"
            w:Refresh()
            ok(w.trinketTicks and #w.trinketTicks == 2 and not w.trinketTicks[1].tick.__shown,
               "the mouse window has a trinket 1 and a trinket 2 tick, both off")
            w.trinketTicks[1].__scripts.OnClick(w.trinketTicks[1])
            w.trinketTicks[2].__scripts.OnClick(w.trinketTicks[2])
            ok(w.trinketTicks[1].tick.__shown and w.trinketTicks[2].tick.__shown, "tick both on the shift tab")
            FM.ApplyTo(cell2)
            local sh = cell2.__attrs["shift-macrotext1"] or ""
            ok(sh:find("/use 13\n/use 14\n/cast [@mouseover] Healing Wave(Rank 3)", 1, true),
               "every shift bind now uses both trinkets first", sh)
            ok(cell2.__attrs["*type1"] == "spell" and cell2.__attrs["*macrotext1"] == nil,
               "and the no-modifier tab is untouched - a plain spell", tostring(cell2.__attrs["*type1"]))
            w.mod = "alt-"
            w:Refresh()
            ok(not w.trinketTicks[1].tick.__shown, "each tab keeps its own ticks (alt: none)")
            w.trinketTicks[2].__scripts.OnClick(w.trinketTicks[2])
            -- the macro row: four digits, zeros kept - none 0, shift 3, ctrl 0, alt 2
            local tb = NS.FK.Encode({}, { trinketTabs = NS.DB().trinketTabs })
            ok(tb:find("F=0302", 1, true), "written as F=0302 in the macro", tb)
            local _, st = NS.FK.Decode(tb)
            ok(st and st.trinketTabs and st.trinketTabs["shift-"][13] and st.trinketTabs["shift-"][14]
               and st.trinketTabs["alt-"][14] and not st.trinketTabs["alt-"][13] and not st.trinketTabs[""],
               "and read back exactly")
            ok(not NS.FK.Encode({}, {}):find("F="), "nothing ticked writes nothing")
            -- /bish trinkets says it, and sets it
            local keptChat = _G.DEFAULT_CHAT_FRAME
            local heard = {}
            _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
            NS.DO.trinkets("ctrl", "1")
            _G.DEFAULT_CHAT_FRAME = keptChat
            local said3 = table.concat(heard, "|")
            ok(#FM.TabTrinkets("ctrl-") == 1 and FM.TabTrinkets("ctrl-")[1] == 13
               and said3:find("ctrl: trinket 1 first", 1, true), "/bish trinkets ctrl 1", said3)
            NS.DO.trinkets("shift", "off") NS.DO.trinkets("alt", "off") NS.DO.trinkets("ctrl", "off")
            ok(NS.DB().trinketTabs == nil, "off everywhere stores nothing")
            w.mod = ""
            FM.Set("", "left", "Spell331(Rank 4)") FM.Clear("shift-", "left")    -- as the tests below expect

            -- 20% BIGGER, NOTHING OUT OF PLACE (Arn, 10 Oct): one scale on the whole window, and a
            -- remembered spot lands where it was ON SCREEN whatever scale it was saved at
            ok(w:GetScale() == FM.SCALE and FM.SCALE == 1.2, "the bind window is drawn 20% bigger")
            local dbm = NS.DB()
            local keptPos = dbm.mousePos
            dbm.mousePos = { point = "CENTER", rel = "CENTER", x = 120, y = -60 }      -- saved before (scale 1)
            FM.Restore(w)
            local p = w.points and w.points[#w.points]
            ok(p and math.abs(p[4] * 1.2 - 120) < 0.01 and math.abs(p[5] * 1.2 + 60) < 0.01,
               "an old spot (saved at scale 1) lands in the same place on screen at 1.2",
               p and (tostring(p[4]) .. "," .. tostring(p[5])))
            local realGetPoint = w.GetPoint
            w.GetPoint = function() return "CENTER", UIParent, "CENTER", 100, -50 end
            FM.SavePos(w)
            ok(dbm.mousePos.scale == 1.2, "a spot is saved with the scale it was saved at")
            FM.Restore(w)
            p = w.points and w.points[#w.points]
            ok(p and p[4] == 100 and p[5] == -50, "and comes back unchanged at the same scale")
            w.GetPoint = realGetPoint
            dbm.mousePos = keptPos
            FM.Clear("", "button4") FM.Clear("", "wheelup") FM.Clear("", "right")
            FM.ApplyWheel(FG.anchor)
            _G.C_Spell.GetSpellInfo = realInfo
        end

        -- YOUR HEALS AT THEIR TOP RANK, READY TO DRAG (Arn, 8 Oct: "look at how fojjicore made a
        -- little box ... show all the healing spells max rank dragable to the binds")
        do
            local pal = FM.Palette()
            local names = {}
            for i, s in ipairs(pal) do names[i] = s.name end
            ok(table.concat(names, ",") == "Healing Wave,Lesser Healing Wave,Chain Heal",
               "the palette is this shaman's trained heals, in reaching order - nothing untrained",
               table.concat(names, ","))
            ok(pal[1].id == 1003 and pal[1].rank == "Rank 3",
               "each at its HIGHEST trained rank (Healing Wave: rank 3 of 3)", tostring(pal[1].id))
            w:Refresh()
            local b1 = w.palette[1]
            ok(b1.__shown and b1.spell and b1.spell.name == "Healing Wave", "the first icon is Healing Wave")
            ok(not w.palette[4].__shown, "and an icon with nothing to carry is hidden")
            -- DRAG IT ONTO A BUTTON: the spell goes on the cursor by id, and the slot binds that rank
            FM.Clear("", "button5")
            STATE.pickedUp = nil
            b1.__scripts.OnDragStart(b1)
            ok(STATE.pickedUp == 1003, "dragging the icon picks up the top rank's spell id")
            local s5 = w.slots["button5"]
            s5.__scripts.OnReceiveDrag(s5)
            ok(FM.Get("", "button5") == "Healing Wave(Rank 3)",
               "dropped on a button, it binds the heal at its top rank", tostring(FM.Get("", "button5")))
            -- and a click does the same as a drag, for a mouse that is easier to click than drag
            CURSOR = {}
            w.palette[2].__scripts.OnClick(w.palette[2])
            ok(CURSOR.kind == "spell" and CURSOR.c == 1004, "clicking an icon also puts it on the cursor")
            CURSOR = {}
            -- not in a fight: binds are written out of combat anyway
            STATE.inCombat = true
            STATE.pickedUp = nil
            b1.__scripts.OnDragStart(b1)
            ok(STATE.pickedUp == nil, "nothing is picked up in combat")
            STATE.inCombat = false
            -- INSIDE THE WINDOW: the last icon ends before the window's right edge
            local lastB = w.palette[FM.PALETTE_MAX]
            local p1 = lastB.points and lastB.points[1]
            local x = p1 and (type(p1[2]) == "number" and p1[2] or p1[4])
            ok(x and x + lastB.__w <= w.__w - 4, "eleven icons fit across the window",
               tostring(x) .. "+" .. tostring(lastB.__w) .. " in " .. tostring(w.__w))
            FM.Clear("", "button5")

            -- TELLING A NEW PLAYER (Arn: "how do we let the new people know that they can drop ns
            -- ... on top of other spells"): in the window, only while it is news
            BOOK[30] = { name = "Nature's Swiftness", rank = "" }          -- learned: the book says so
            local kept = {}
            for k, v in pairs(NS.DB().binds) do kept[k] = v end
            for k in pairs(NS.DB().binds) do
                if FM.Boost(NS.DB().binds[k]) then NS.DB().binds[k] = nil end
            end
            ok(FM.BoostTip() == "drop NS on a heal: it goes first", "trained and unused: the tip is said",
               tostring(FM.BoostTip()))
            w:Refresh()
            ok(w.hint.__text == "drop NS on a heal: it goes first",
               "on the hint line under the tabs, always there", tostring(w.hint.__text))
            ok(w.hint:GetStringWidth() <= 234, "and it fits the window", w.hint:GetStringWidth())
            -- the longest booster name fits that line too
            local realShort = FM.BOOST_SHORT["Nature's Swiftness"]
            FM.BOOST_SHORT["Nature's Swiftness"] = "Divine Favor"
            w:Refresh()
            ok(w.hint:GetStringWidth() <= 234, "the longest booster tip fits too", w.hint:GetStringWidth())
            FM.BOOST_SHORT["Nature's Swiftness"] = realShort
            local nsIcon
            for _, pb in ipairs(w.palette) do if pb.spell and pb.spell.name == "Nature's Swiftness" then nsIcon = pb end end
            TIP.lines = {}
            if nsIcon then nsIcon.__scripts.OnEnter(nsIcon) end
            local nsTip = table.concat(TIP.lines, "|")
            ok(nsIcon and nsTip:find("drop it on a heal's button", 1, true) and nsTip:find("then the heal", 1, true),
               "hovering Nature's Swiftness in the row explains the trick", nsTip)
            FM.Set("shift-", "wheelup", "Nature's Swiftness+Healing Wave(Rank 3)")
            ok(FM.BoostTip() == nil, "once a bind carries it, the tip is gone for good")
            w:Refresh()
            ok(w.hint.__text == "drop a spell, macro or ping on a button", "and the hint line is the usual one again")
            BOOK[30] = nil
            ok(FM.BoostTip() == nil, "and a class with no booster never sees it")
            for k in pairs(NS.DB().binds) do NS.DB().binds[k] = nil end
            for k, v in pairs(kept) do NS.DB().binds[k] = v end
        end

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

        -- and when BOTH came back, the account-wide one is left alone - when it is this character's
        local me = NS.Me()
        ok(type(me) == "string", "the character's own name-realm", me)
        _G.BiSHealingDB = { dbver = 1, owner = me, binds = { left = "Chain Heal" } }
        _G.BiSHealingCharDB = keep
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(NS.loaded.rescued == false and NS.FM.Get("", "left") == "Chain Heal",
           "a client that keeps both changes nothing")

        -- ANOTHER CHARACTER'S TABLE (Arn, 15 Oct: his alt's bind window showed his main's heals).
        -- The account table is shared; the alt takes its own copy, never the main's binds.
        _G.BiSHealingDB = { dbver = 1, owner = "Mainchar-Realm", binds = { left = "Chain Heal", wheelup = "Healing Wave(Rank 9)" }, tank = "Tankmain" }
        _G.BiSHealingCharDB = { binds = { left = "Auto Shot" } }
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(_G.BiSHealingDB.binds.left == "Auto Shot" and _G.BiSHealingDB.binds.wheelup == nil and _G.BiSHealingDB.tank == nil,
           "logging into an alt: the alt's own binds and tank, nothing of the main's")
        ok(_G.BiSHealingDB.owner == me and NS.claimed and NS.claimed.from == "Mainchar-Realm", "and the table is the alt's now")
        -- an alt with no copy of its own: no binds at all, so its macro is asked (FK.Load)
        _G.BiSHealingDB = { dbver = 1, owner = "Mainchar-Realm", binds = { left = "Chain Heal" } }
        _G.BiSHealingCharDB = nil
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(_G.BiSHealingDB.binds == nil, "an alt with no copy: the main's binds go, and its own macro answers")
        -- a table from before the stamp is nobody's: the character's own copy wins
        _G.BiSHealingDB = { dbver = 1, binds = { left = "Chain Heal" } }
        _G.BiSHealingCharDB = { binds = { left = "Healing Wave(Rank 2)" } }
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        ok(_G.BiSHealingDB.binds.left == "Healing Wave(Rank 2)" and _G.BiSHealingDB.owner == me,
           "a table from before 0.9.2 (no owner): this character's own copy, and the stamp")

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
        -- ONE STANDARD FOR THE FAMILY (Forever 1.0, Arn 7 Nov: "sometimes left click does one thing, sometimes
        -- right click does another ... we gotta get everything on the same page"): the shared button's own
        -- click, left = the main window (the mouse binds), right = the options. This SWAPS the 6 Nov order
        -- ("right click opens binds window pls").
        ok(NS.MM.Click == nil, "the click is the shared button's own, not one of ours")
        local realOptions, realMouse, opened, binds = NS.DO.options, NS.DO.mouse, 0, 0
        NS.DO.options = function() opened = opened + 1 end
        NS.DO.mouse = function() binds = binds + 1 end
        click(b, "LeftButton")
        ok(binds == 1 and opened == 0, "left click: the mouse binds window", binds)
        click(b, "RightButton")
        NS.DO.options, NS.DO.mouse = realOptions, realMouse
        ok(opened == 1 and binds == 1, "right click (no BiS> page on this client): the options window", opened)
        local lines = {}
        local keepTT = _G.GameTooltip
        _G.GameTooltip = { SetOwner = function() end, Show = function() end,
                           AddLine = function(_, s) lines[#lines + 1] = tostring(s) end }
        b:GetScript("OnEnter")(b)
        _G.GameTooltip = keepTT
        local tip = table.concat(lines, "|")
        ok(tip:find("left%-click  mouse binds") and tip:find("right%-click  options"), "the tooltip says which is which", tip)
        ok(not (b.menuFrame and b.menuFrame:IsShown()), "and no menu opens instead")
        -- OUR click replaces the shared one, so it must ask for the shared unbury itself (Arn,
        -- 14 Oct: "bis healing stay dark after click" - EllesmereUI's backing over the icon)
        local unburied = 0
        local keepU = b.Unbury
        b.Unbury = function() unburied = unburied + 1 return true end
        NS.DO.options = function() end
        click(b, "LeftButton")
        NS.DO.options = realOptions
        b.Unbury = keepU
        ok(unburied == 1, "a click puts a collector's backing back under the icon")
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
        for _, want in ipairs({ "target", "tot", "mana" }) do       -- "me" retired 8 Nov 2026
            ok(parts[want], ("the cells row lost %q"):format(want))
        end
        ok(parts.me == nil, "and the retired \"me\" is gone from it")
        ok(keys.pets and keys.pets.kind == "seg",
           "and pets is a row of its own, because it has three answers",
           keys.pets and keys.pets.kind)
        -- AND EACH SWITCH READS ITS OWN SETTING. Four buttons side by side in one row is four
        -- chances to wire one to its neighbour's key, and the window would look perfectly
        -- sensible: the wrong button simply lights up.
        local db, was = NS.DB(), {}
        for _, k in ipairs({ "target", "tot", "me", "mana" }) do was[k] = db[k] end
        for _, k in ipairs({ "target", "tot", "mana" }) do db[k] = false end
        for _, k in ipairs({ "target", "tot", "mana" }) do
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
        -- ONE LOOK FOR EVERY BiS> BAR (Arn, 12 Oct: "the bis headers are all different fonts some
        -- different color some blinking _ some static lets get them all the same"). The prompt lib is one
        -- the TOC loop skips, so every bar took the plain-label road here and the prompt was never
        -- tested; it is loaded now, and a block's bar is built with it.
        if not (BiSTheme and BiSTheme.Console) then
            local lib = assert(loadfile("Libs/BiSTheme/Console.lua"))
            ok(pcall(lib), "the shared prompt lib loads headless")
        end
        do
            local blk = CreateFrame("Frame", nil, UIParent)
            blk:SetSize(200, 34)
            local h = FG.CellHeader(blk, "probe", blk)
            -- the words fade in, as on the client: a moment passes, two paints
            CLOCK = CLOCK + 0.3 FG.PaintHeaders() CLOCK = CLOCK + 0.3 FG.PaintHeaders()
            local plainText = h and h.con and (h.con:Text():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
            ok(plainText and plainText:find("BiS> probe", 1, true),
               "a block's bar wears the family prompt: BiS> and the word", plainText)
            local listed = false
            for _, x in ipairs(FG.cellCons) do if x == h then listed = true end end
            ok(listed, "and is on the grid header's one paint list")
            -- a NARROW block still has room for the word and its "_" (Arn's cousin, 14 Oct: "his bis
            -- now does not have a blinking _" - BiS> now with two buttons)
            local thin = CreateFrame("Frame", nil, UIParent)
            thin:SetSize(68, 34)
            local th = FG.CellHeader(thin, "now", thin)
            ok(th and th.con and th.con.width >= FG.HEADER_MIN_W, "a 68 px block's prompt still gets the room for 'BiS> now_'",
               th and th.con and th.con.width)
            local painted = 0
            local real = h.con.Paint
            h.con.Paint = function(self, ...) painted = painted + 1 return real(self, ...) end
            FG.PaintHeaders()
            ok(painted == 1, "one paint of the grid's prompts paints it - no ticker of its own", painted)
            blk:Hide() h:Hide()
            FG.PaintHeaders()
            ok(painted == 1, "a hidden bar is not painted", painted)
            h.con.Paint = real
        end
        -- the window has to be BUILT for there to be a button to press, and the shared lib it is
        -- built from is one the TOC loop above skips
        if not (BiSTheme and BiSTheme.Options) then
            local lib = assert(loadfile("Libs/BiSTheme/Options.lua"))
            ok(pcall(lib), "the shared options lib loads headless")
        end
        NS.CFG.Build()
        local row = NS.CFG and NS.CFG.cells
        ok(row and row.ctl and #row.ctl == 3, "the row has its three buttons (\"me\" retired 8 Nov)", row and #(row.ctl or {}))
        if row and row.ctl then
            for i, part in ipairs(keys.cells.parts) do
                for _, k in ipairs({ "target", "tot", "mana" }) do db[k] = false end
                local click = row.ctl[i].__scripts and row.ctl[i].__scripts.OnClick
                if click then click(row.ctl[i], "LeftButton") end
                ok(db[part.key] == true,
                   ("pressing %q switches %q on"):format(part.label, part.key),
                   tostring(db[part.key]))
            end
            for _, k in ipairs({ "target", "tot", "mana" }) do db[k] = was[k] end
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
    --
    -- ON 7 OCT IT GREW SIDEWAYS. A player asked for two more (the gold ring on your target, and
    -- how far out-of-range cells dim) with the window at its cap, and Arn: "can we make two
    -- colums". So the rule is now per COLUMN: each column, section bars included, stays as short
    -- as one column ever was - fourteen rows - and there are two of them.
    do
        local tall = { 0, 0 }
        for _, sec in ipairs(NS.UI.Sections()) do
            local c = sec.column or 1
            tall[c] = tall[c] + 1 + #sec.options
        end
        -- FIFTEEN ON THE RIGHT (8 Nov 2026, PvP mode, which Arn asked for in 1.0): one seg row, three
        -- answers (off / bg / on), under "groups" where the grid's shape is chosen. Column 2 was at 14.
        -- SIXTEEN (8 Nov 2026, same night): the PvP cast alert - glow, bounce or both - which Arn asked to be a
        -- player's pick ("lets make it an option for them glow or bounce"), under PvP mode
        -- SEVENTEEN (8 Nov 2026, later): the look - cockpit or classic - Arn's cockpit redesign, one switch to go back
        -- SIXTEEN ON THE LEFT (12 Nov 2026): the radar's overheal word - what decides it (off / any / half / 75%) and which
        -- button's heal a hover judges; Arn: "add to options ... if they want to change what determines it". Still shorter
        -- than the right column, so the window does not grow
        ok(tall[1] <= 16 and tall[2] <= 17, ("each column stays short: %d and %d"):format(tall[1], tall[2]))
        -- TWENTY-ONE (19 Oct): Arn asked for the mana-for-mana window "in the option", by name - a
        -- door, not a setting, under the mouse binds where a healer's first look already goes
        -- TWENTY-THREE (7 Nov, Forever 1.0): a new install starts with the crosshair, the LOS flash, the
        -- buff sound and the buff reminder OFF, and Arn's rule is that whatever starts off has a switch a
        -- player can find - so the LOS flash and the buff reminder got rows
        -- TWENTY-FOUR (8 Nov 2026): the PvP mode row, above; TWENTY-FIVE: its cast alert; TWENTY-SIX: the look
        -- TWENTY-EIGHT (12 Nov 2026): the overheal word and its hover heal, above
        ok(#NS.UI.Rows() <= 28, "and the whole window has no more than twenty-eight rows: " .. #NS.UI.Rows())
        -- THE HELP STRIP (Arn, 14 Oct: "yes do the help strip"): every setting says what it does
        local undocumented = {}
        for _, o in ipairs(NS.UI.Rows()) do if not o.help then undocumented[#undocumented + 1] = o.label end end
        ok(#undocumented == 0, "every BiS Healing setting has its help written", table.concat(undocumented, ", "))
    end

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
        return { { rank = "Rank 1", index = 20, spell = 974 },
                 { rank = "Rank 2", index = 21, spell = 32593 } }
    end
    local realDB = NS.DB()
    realDB.groupBuff = "Lightning Shield"
    FG.Roster = function() return { "player", "party1" } end

    -- ---------------------------------------------------------------- NS.AuraById
    -- YOUR OWN AURAS COME FROM THE PLAYER CALL. Measured 1 Oct: with Water Shield visibly on him,
    -- the watch said "not up on you" - the unit call does not answer about the player. So the mock
    -- behaves the way the client did, and the suite would have caught it: GetUnitAuraBySpellID
    -- knows nothing about "player", and only GetPlayerAuraBySpellID does.
    local ownAuras = {}
    _G.C_UnitAuras.GetPlayerAuraBySpellID = function(id) return ownAuras[id] end
    local realIsPlayer = NS.IsPlayer
    NS.IsPlayer = function(u) return u == "player" end

    ownAuras[24398] = { name = "Water Shield", spellId = 24398 }
    local own, ownWhy = NS.AuraById("player", 24398)
    ok(type(own) == "table" and ownWhy == nil,
       "a buff on YOU is found, through the player call the unit call cannot answer",
       tostring(ownWhy))
    ok(NS.AnyAuraById("player", { 24398 }) == true, "and the watch sees it")
    ownAuras[24398] = nil
    ok(NS.AnyAuraById("player", { 24398 }) == false, "and sees it go")
    NS.IsPlayer = realIsPlayer

    up.party1[32593] = { name = "Earth Shield", spellId = 32593 }
    local a, why = NS.AuraById("party1", 32593)
    ok(type(a) == "table" and why == nil, "an aura the client hands over is read")
    ok(NS.auraSeen == "read", "and it says so", tostring(NS.auraSeen))

    a, why = NS.AuraById("player", 974)
    ok(a == nil and why == "none", "an aura that is not there is 'none', not a refusal", tostring(why))

    mode = "secret"
    a, why = NS.AuraById("party1", 32593)
    ok(a == nil and why == "secret", "a secret answer is never read", tostring(why))

    -- A NIL AURA IS NOT PROOF OF ABSENCE. Arn, in a dungeon in combat, with Water Shield plainly
    -- up: "about player, id 408510: none". A hidden aura answers exactly like a missing one, so
    -- nil is only a NO where the client would have shown it.
    mode = "answer"
    local realSecrets3 = _G.C_Secrets
    _G.C_Secrets = { HasSecretRestrictions = function() return true end,
                     ShouldSpellAuraBeSecret = function() return true end }
    a, why = NS.AuraById("player", 974)
    ok(a == nil and why == "hidden",
       "a buff the client is hiding is 'hidden', never 'none'", tostring(why))
    ok(NS.AnyAuraById("player", { 974, 32593 }) == nil,
       "so the watch says 'could not tell' rather than a confident no")

    -- and a spell the client calls never-secret is still a real answer
    _G.C_Secrets.ShouldSpellAuraBeSecret = function() return false end
    a, why = NS.AuraById("player", 974)
    ok(a == nil and why == "none",
       "a spell it says is readable gives a real no", tostring(why))
    ok(NS.AnyAuraById("player", { 974 }) == false, "and the watch believes that one")

    -- the answer about secrecy being itself secret, or refused, counts as hidden
    _G.C_Secrets.ShouldSpellAuraBeSecret = function() return secret() end
    ok(select(2, NS.AuraById("player", 974)) == "hidden", "a secret answer about secrecy is hidden")
    _G.C_Secrets.ShouldSpellAuraBeSecret = function() error("nope", 2) end
    ok(select(2, NS.AuraById("player", 974)) == "hidden", "so is a refusal to answer it")
    _G.C_Secrets = realSecrets3

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

    -- NOT ping-receiver: setting it stopped the ping happening at all (1 Oct). A cell must NOT
    -- claim to be one on this client, so the suite holds the line the other way round.
    ok(FG.frames[1].__attrs["ping-receiver"] == nil,
       "a cell does not claim to be a ping receiver - it swallows the click on this client",
       tostring(FG.frames[1].__attrs["ping-receiver"]))

    ok(FM.PingOf("!ping:assist") == "assist", "a ping bind is recognised")
    ok(FM.PingOf("!ping:nonsense") == nil, "a ping type we do not offer is not one")
    ok(FM.PingOf("Healing Wave(Rank 3)") == nil, "a spell is not a ping")
    ok(FM.PingOf(nil) == nil, "and nothing is not a ping")
    ok(FM.PingBind("assist") == "!ping:assist", "a ping is stored under a mark no spell can wear")
    ok(FM.PingWord("onmyway") == "On My Way", "and shown by its own name")

    -- THE CLIENT'S OWN PING ART. The kit is a bare word ("Assist") and the atlas is
    -- "Ping_Chat_<kit>", found on 1 Oct by listing every atlas with "ping" in its name rather than
    -- by guessing a suffix - five guesses had already missed.
    local realPing2, realTex, realEnum2 = _G.C_Ping, _G.C_Texture, _G.Enum
    _G.Enum = _G.Enum or {}
    _G.Enum.PingSubjectType = { Attack = 0, Warning = 1, Assist = 2, OnMyWay = 3, ActionNotReady = 9 }
    _G.C_Ping = { GetTextureKitForType = function(t) return t == 2 and "Assist" or (t == 0 and "Attack" or nil) end }
    _G.C_Texture = { GetAtlasExists = function(n) return n == "Ping_Chat_Assist" end }

    ok(FM.PingAtlas("assist") == "Ping_Chat_Assist", "a ping finds the client's own icon",
       tostring(FM.PingAtlas("assist")))
    ok(FM.PingAtlas("attack") == nil,
       "an atlas the client does not have is nil, not a broken texture name",
       tostring(FM.PingAtlas("attack")))
    ok(FM.PingAtlas("warning") == nil, "and a type with no kit at all is nil")
    ok(FM.PingAtlas("nonsense") == nil, "and a ping we do not offer has no icon")

    -- no art on this client at all: the chips must still work, in words
    _G.C_Ping = nil
    ok(FM.PingAtlas("assist") == nil, "with no C_Ping, there is no icon and no error")
    _G.C_Ping, _G.C_Texture, _G.Enum = realPing2, realTex, realEnum2

    local keepLeft, keepAlt = FM.Get("", "left"), FM.Get("alt-", "left")

    -- IT BECOMES A MACRO, NOT A SPELL. If it ever went in as a spell the cell would try to cast
    -- something called "!ping:assist", which is a visible error in the middle of a fight.
    FM.Set("alt-", "left", FM.PingBind("assist"))
    FM.Apply()
    local cell = FG.frames[1]
    ok(cell.__attrs["alt-type1"] == "macro", "a ping binds as a macro", tostring(cell.__attrs["alt-type1"]))
    -- THE CONDITION IS THE FEATURE, not decoration: without [@mouseover] the ping lands on the
    -- floor at your feet instead of on the person whose cell you clicked (measured 1 Oct).
    ok(cell.__attrs["alt-macrotext1"] == "/ping [@mouseover] assist",
       "running Blizzard's own command, aimed at the unit under the cursor",
       tostring(cell.__attrs["alt-macrotext1"]))
    ok(cell.__attrs["alt-spell1"] == nil, "and never as a spell", tostring(cell.__attrs["alt-spell1"]))

    -- THE WHEEL IS NOT A CLICK, and that is why pings did not work there for a build. Wheel binds
    -- never reach ApplyTo; they are override bindings onto hidden secure buttons, built in
    -- ApplyWheel, and a ping bind arrived there as "/cast !ping:assist".
    FM.Set("", "wheelup", FM.PingBind("attack"))
    FM.ApplyWheel(FG.anchor)
    local wheel = _G["BiSHealWheelwheelup"]
    ok(wheel ~= nil, "the wheel has a secure button behind it")
    if wheel then
        local text = wheel.__attrs and wheel.__attrs.macrotext or ""
        ok(text:find("/ping %[@mouseover%] attack") ~= nil,
           "and a ping on the wheel pings rather than casting", text)
        ok(text:find("/cast") == nil, "with no /cast left in it", text)
        -- a ping may go at an enemy, so the cast guard would have blocked the Attack ping
        ok(text:find("nohelp") == nil,
           "and it is not filtered to friendly targets, which would kill the attack ping", text)
    end
    FM.Clear("", "wheelup")
    FM.ApplyWheel(FG.anchor)

    -- THE REGRESSION THAT MATTERS. The range check takes "whatever you have bound", and a ping is
    -- not a spell: handing it one answers "don't know", which reads as "in range", which is the
    -- whole raid staying bright. That bug cost 0.7.2 and 0.7.5; it is not coming back this way.
    FM.Clear("", "left")
    FM.Clear("", "right")
    for _, slot in ipairs(FM.SLOTS) do
        for _, m in ipairs(FM.MODS) do FM.Clear(m.key, slot.key) end
    end
    FM.Set("alt-", "left", FM.PingBind("assist"))
    -- since 7 Oct a trained class heal counts even unbound, so the answer is that heal - and
    -- never, ever the ping
    ok(FM.RangeSpell() ~= nil and not FM.PingOf(FM.RangeSpell()),
       "with only a ping bound, range is measured with a trained heal - never with the ping",
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

------------------------------------------ BiS> now: the order that learns (0.8.x) --
--
-- Arn's rule, in his words: "if a party member is feared after combat the button moves up one
-- space... if 2 combats happen and people are poison more often the poison cleanse totem moves up
-- more spaces than the fear". One swap per occurrence, settled when the fight ends - which is also
-- the only legal moment, since a secure button cannot be moved in combat.
do
    local FN = NS.FN
    FN.Reset()

    -- THE CURVES, AND THE ONE BRANCH THAT READS ANYTHING. Arn watched the first version appear at
    -- 30% and said what that is worth: "at 30% a healer is already 1 hit from dying most of the
    -- time". So the thresholds matter enough to pin down, and so does dead-is-not-hurt.
    do
        local realCU, realHP, realDead = _G.C_CurveUtil, _G.UnitHealthPercent, _G.UnitIsDeadOrGhost
        local points = {}
        local curveObj = { AddPoint = function(_, at, col) points[#points + 1] = at end,
                           SetType = function() end }
        _G.C_CurveUtil = { CreateColorCurve = function() return curveObj end }
        _G.CreateColor = _G.CreateColor or function(r, g, b, a)
            return { GetRGBA = function() return r, g, b, a end }
        end
        FN.helpCurve, FN.glowCurve = nil, nil
        ok(FN.HelpCurve() ~= nil, "the help curve is built")
        local top, bottom = nil, nil
        for _, at in ipairs(points) do
            top = (top == nil or at > top) and at or top
            bottom = (bottom == nil or at < bottom) and at or bottom
        end
        ok(bottom == 0 and top == 1, "and it covers the whole range", tostring(bottom) .. ".." .. tostring(top))
        local appears = nil
        for _, at in ipairs(points) do
            if at < 1 and (appears == nil or at > appears) then appears = at end
        end
        ok(appears and appears >= 0.65,
           "it starts warning well above 30%, which is already too late",
           tostring(appears))

        -- DEAD: still visible, still clickable, plainly duller than a dying player. Arn's call -
        -- a combat res has to be able to find the corpse.
        local painted = {}
        local btn = { art = { SetVertexColor = function(_, r) painted.art = r end } }
        local edges = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            edges[side] = { SetColorTexture = function(_, r, g, b, a) painted.edge = { r, g, b, a } end }
        end
        local realBlock = FN.block
        FN.block = { edge = edges }

        _G.UnitIsDeadOrGhost = function() return true end
        FN.PaintHelp(btn)
        ok(FN.seen == "dead - a dimmer beacon", "a corpse still glows, for the res", tostring(FN.seen))
        ok(painted.edge and painted.edge[1] == FN.EDGE_DEAD[1],
           "and its outline is the corpse's red", tostring(painted.edge and painted.edge[1]))

        -- THE TWO MUST NOT READ ALIKE, however either is tuned later: a corpse is duller than the
        -- ordinary outline is bright, and nowhere near the red a dying player gets.
        ok(FN.EDGE_DEAD[1] < 1.0, "the corpse's red is not the dying player's red")
        ok(FN.EDGE_DEAD[1] > FN.EDGE_WELL[1], "but it is redder than the ordinary outline")

        -- EVERY SIDE IS PAINTED, not just the one that happened to be last
        local n = 0
        for _ in pairs(edges) do n = n + 1 end
        ok(n == 4, "all four sides exist to be painted", tostring(n))
        ok(FN.PaintEdge(1, 0, 0, 1) == true, "and PaintEdge reports that it painted them")

        FN.block = realBlock
        _G.C_CurveUtil, _G.UnitHealthPercent, _G.UnitIsDeadOrGhost = realCU, realHP, realDead
        FN.helpCurve, FN.glowCurve = nil, nil
    end

    -- THE TREMOR BUTTON: dim until somebody in the party is held by something a Tremor Totem
    -- actually answers. Arn: "dimmed until somone in the party is feared charmed or sleep" - and
    -- that list matters, because a button that lights for every root is one you learn to ignore.
    do
        local realLC, realRoster = _G.C_LossOfControl, NS.FG.Roster
        local held = {}
        _G.C_LossOfControl = {
            GetActiveLossOfControlDataCountByUnit = function(u) return held[u] and 1 or 0 end,
            GetActiveLossOfControlDataByUnit = function(u)
                return held[u] and { lossOfControlType = held[u] } or nil
            end,
        }
        NS.FG.Roster = function() return { "player", "party1" } end

        local painted = {}
        local btn = { art = { SetVertexColor = function(_, r, g, b, a) painted.a = a end,
                              SetDesaturated = function(_, on) painted.grey = on end },
                      IsShown = function() return true end }

        ok(FN.PaintNeed(btn, "tremor") == false, "nothing holding anyone: the button is dim")
        ok(painted.grey == true, "and greyed out")

        held.party1 = "ROOT"
        ok(FN.PaintNeed(btn, "tremor") == false,
           "a ROOT does not light it - a totem does not break roots")

        held.party1 = "FEAR"
        ok(FN.PaintNeed(btn, "tremor") == true, "a FEAR does")
        ok(painted.a == 1 and painted.grey == false, "bright and in colour")
        ok(FN.needSeen == "FEAR on party1", "and it says who", tostring(FN.needSeen))

        held.party1 = "CHARM"
        ok(FN.PaintNeed(btn, "tremor") == true, "so does a CHARM")
        held.party1 = "SLEEP"
        ok(FN.PaintNeed(btn, "tremor") == true, "and a SLEEP")

        -- A CONFUSE IS A CHARM OR A SHEEP (Arn, 17 Oct: "my pal got charmed and no tremor button
        -- light up" - /bish holds had read CONFUSE, never CHARM). Only the spell tells them apart.
        local heldSpell = {}
        _G.C_LossOfControl.GetActiveLossOfControlDataByUnit = function(u)
            return held[u] and { lossOfControlType = held[u], spellID = heldSpell[u] } or nil
        end
        held.party1, heldSpell.party1 = "CONFUSE", 118          -- Polymorph
        ok(FN.PaintNeed(btn, "tremor") == false, "a CONFUSE from a Polymorph: no totem breaks that")
        heldSpell.party1 = 6358                                 -- Seduction
        ok(FN.PaintNeed(btn, "tremor") == true, "a CONFUSE from Seduction lights Tremor")
        heldSpell.party1 = secret and secret() or nil
        ok(FN.PaintNeed(btn, "tremor") == false, "a hidden spell id: no guess, the button stays dim")
        local rec = FN.seenHolds.CONFUSE
        local named = false
        for s in pairs(rec and rec.spells or {}) do if tostring(s):find("6358", 1, true) then named = true end end
        ok(named, "and /bish holds keeps which spell it was")
        local kept = NS.DB().holds and NS.DB().holds.CONFUSE
        ok(kept and type(kept.spells) == "table" and #kept.spells >= 1, "kept across logins too")
        ok(pcall(NS.DO.holds), "/bish holds prints the spells without trouble")
        heldSpell.party1 = nil

        -- COUNTED ONCE PER HOLD, not once per frame: the paint runs several times a second and the
        -- order would be nonsense if every frame of one fear counted as another fear.
        FN.Reset()
        btn.__held = nil
        held.party1 = "FEAR"
        for _ = 1, 20 do FN.PaintNeed(btn, "tremor") end
        ok((FN.noted.tremor or 0) == 1, "twenty frames of one fear is one note",
           tostring(FN.noted.tremor))
        held.party1 = nil
        FN.PaintNeed(btn, "tremor")
        held.party1 = "FEAR"
        FN.PaintNeed(btn, "tremor")
        ok((FN.noted.tremor or 0) == 2, "and a second fear is a second note",
           tostring(FN.noted.tremor))

        -- an unknown spelling is recorded rather than guessed at
        held.party1 = "SOMETHING_NEW"
        FN.PaintNeed(btn, "tremor")
        ok(FN.seenHolds and FN.seenHolds.SOMETHING_NEW, "an unseen hold type is written down")

        -- IT WRITES DOWN WHO, NOT JUST WHAT (3 Oct 2026). The open question is not whether loss of
        -- control reads - a root on Arn answered that on 1 Oct - but whether it reads for SOMEBODY
        -- ELSE, which is what lets the shaman alone install the addon. A type with no unit beside
        -- it cannot answer that, and the addon was collecting exactly that useless shape.
        ok(FN.seenHolds.SOMETHING_NEW.units.party1 ~= nil,
           "and the unit it was on is written down with it")
        ok(FN.seenHolds.SOMETHING_NEW.other == true,
           "a hold on party1 is marked as read on somebody OTHER than the player")

        FN.seenHolds = {}
        held.party1 = nil
        NS.FG.Roster = function() return { "player" } end
        held.player = "FEAR"
        FN.PaintNeed(btn, "tremor")
        ok(FN.seenHolds.FEAR and FN.seenHolds.FEAR.other == false,
           "a hold on the player alone is NOT - it proves nothing about other units")
        ok(FN.seenHolds.FEAR.units.player == 1, "counted against the player")
        held.player = nil
        NS.FG.Roster = function() return { "player", "party1" } end

        -- THE ONE BIT SURVIVES A LOGIN (6 Oct 2026). On 5 Oct the button lit after a party fear and
        -- the proof died at the next reload, because seenHolds is one session. The first sighting
        -- on somebody else goes into the saved variables, which this client hands back again.
        do
            local db = NS.DB()
            db.holds = nil
            FN.seenHolds = {}
            held.player = "FEAR"
            NS.FG.Roster = function() return { "player" } end
            FN.PaintNeed(btn, "tremor")
            ok(db.holds and db.holds.FEAR and db.holds.FEAR.firstAt ~= nil,
               "the first fear is kept in the saved table")
            ok(db.holds.FEAR.otherAt == nil, "but on the player alone it proves nothing, and says so")
            held.player = nil
            NS.FG.Roster = function() return { "player", "party1" } end
            held.party1 = "FEAR"
            FN.PaintNeed(btn, "tremor")
            ok(db.holds.FEAR.otherAt ~= nil and db.holds.FEAR.otherUnit == "party1",
               "a fear on party1 is kept as the sighting on somebody else, with who")
            local first = db.holds.FEAR.otherAt
            held.party1 = nil
            FN.PaintNeed(btn, "tremor")
            held.party2 = "FEAR"
            NS.FG.Roster = function() return { "player", "party1", "party2" } end
            FN.PaintNeed(btn, "tremor")
            ok(db.holds.FEAR.otherAt == first and db.holds.FEAR.otherUnit == "party1",
               "the FIRST sighting is the one kept - a later one does not move it")
            held.party2 = nil
            NS.FG.Roster = function() return { "player", "party1" } end

            -- logout, then a login: the table comes back, the session record does not
            local fireEv = NS.events.__scripts.OnEvent
            fireEv(NS.events, "PLAYER_LOGOUT")
            ok(type(_G.BiSHealingCharDB) == "table" and type(_G.BiSHealingCharDB.holds) == "table"
               and _G.BiSHealingCharDB.holds.FEAR.otherUnit == "party1",
               "the per-character copy carries it too")
            FN.seenHolds = {}
            fireEv(NS.events, "ADDON_LOADED", "BiSHealing")
            local heard = {}
            local realChat = _G.DEFAULT_CHAT_FRAME
            _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
            NS.DO.holds()
            _G.DEFAULT_CHAT_FRAME = realChat
            local all = table.concat(heard, "\n")
            ok(all:find("kept across logins") and all:find("READ ON SOMEBODY ELSE"),
               "after the login, with nothing held this session, /bish holds still says it was seen", all)
            ok(not all:find("did not come back"), "and does not cry wolf when the file DID come back")

            -- a login where the client omitted the file: say the record started fresh
            local realLoaded = NS.loaded
            NS.loaded = { found = false }
            heard = {}
            _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
            NS.DO.holds()
            _G.DEFAULT_CHAT_FRAME = realChat
            ok(table.concat(heard, "\n"):find("did not come back"),
               "a login that got no saved file says the kept record started fresh")
            NS.loaded = realLoaded
            db.holds = nil
            FN.seenHolds = {}
        end

        -- THE FIGHT ENDING IS WHAT MAKES THE BUTTON (3 Oct 2026). Arn: "people have been slept and
        -- the tremor button has not popped up". It was seeing them - Watch asked, Note counted -
        -- and FN.Settle, the one thing that turns a count into a button, WAS CALLED BY NOTHING BUT
        -- THIS SUITE. Every test above drove Settle by hand, so the engine was proved and the wire
        -- to it was never looked at once.
        --
        -- This test fires the real event at the real frame, through `fire`, which refuses to
        -- deliver an event the addon never registered. Calling the handler directly would pass
        -- with the fix taken straight back out again.
        do
            local realKnows = NS.FB and NS.FB.Knows
            if NS.FB then NS.FB.Knows = function() return true end end
            FN.Reset()
            held.party1 = "FEAR"

            FN.Watch()
            ok((FN.noted.tremor or 0) >= 1, "a sleep in the fight is noticed while it happens",
               tostring(FN.noted.tremor))
            ok(FN.Earned("tremor") == false, "but the button is NOT born mid-fight")

            ok(fire(FG.events, "PLAYER_REGEN_ENABLED"),
               "the grid asked for PLAYER_REGEN_ENABLED in the first place")
            ok(FN.Earned("tremor") == true,
               "and the moment the fight ends the button is earned - the wire that was missing")

            -- and a quiet fight must not conjure one out of nothing
            FN.Reset()
            held.party1 = nil
            FN.Watch()
            fire(FG.events, "PLAYER_REGEN_ENABLED")
            ok(FN.Earned("tremor") == false, "a fight where nobody was held earns nothing")

            if NS.FB then NS.FB.Knows = realKnows end
        end

        _G.C_LossOfControl, NS.FG.Roster = realLC, realRoster
        FN.Reset()
    end

    -- A BUTTON IS EARNED, NOT ISSUED. Arn, looking at a Tremor button he had never needed: "it
    -- should be smarter always the assist there, after combat if anyone get feared we add the
    -- tremor button." Knowing the spell means the button CAN exist; somebody being feared is what
    -- makes it exist.
    do
        FN.Reset()
        local realKnows = NS.FB.Knows
        NS.FB.Knows = function() return true end          -- a shaman with every totem trained
        -- this block counts EARNED buttons; the shield button (12 Oct) is always there for a
        -- character with a watched buff, and has its own checks in the self-buff section
        local realShield = FN.ShieldReady
        FN.ShieldReady = function() return false end
        local keepTank = FN.TankReady
        FN.TankReady = function() return false end

        -- IN A GROUP TREMOR IS THERE FROM THE START (Arn, 8 Nov, Wailing Caverns: a teammate slept, no button, a
        -- wipe). Earning it meant the first sleep was always a wipe. Solo it still waits to be earned
        local keepIG = _G.IsInGroup
        _G.IsInGroup = function() return true end
        local inGroup = FN.Mine()
        ok(#inGroup == 2 and inGroup[2] == "tremor" and not FN.Earned("tremor"),
           "in a group: help AND Tremor from the start, nothing earned", table.concat(inGroup, " "))
        _G.IsInGroup = function() return false end
        local mine = FN.Mine()
        ok(#mine == 1 and mine[1] == "help",
           "a fresh install, alone: the help button and nothing else",
           table.concat(mine, " "))

        -- a fight where somebody was feared, and the fight ending
        FN.Note("tremor")
        local _, won = FN.Settle()
        ok(won == true, "the fight that needed it says so")
        mine = FN.Mine()
        ok(#mine == 2, "and afterwards the Tremor button is there", table.concat(mine, " "))

        -- IT STAYS. Earning it is a fact about this character, not about that fight.
        FN.Settle()
        ok(#FN.Mine() == 2, "a quiet fight does not take it away again")

        -- AND IT SURVIVES A RESTART, in the same row as the order
        local digits = FN.Encode()
        FN.Reset()
        ok(#FN.Mine() == 1, "a reset forgets it")
        FN.Decode(digits)
        ok(#FN.Mine() == 2, "and the macro remembers it", table.concat(FN.Mine(), " "))

        -- THE CIRCLE THAT HAD TO BE BROKEN: nothing watches a button that is not there, so it
        -- could never be earned. FN.Watch looks for the ones with something to prove.
        FN.Reset()
        local realLC, realRoster = _G.C_LossOfControl, NS.FG.Roster
        _G.C_LossOfControl = {
            GetActiveLossOfControlDataCountByUnit = function() return 1 end,
            GetActiveLossOfControlDataByUnit = function() return { lossOfControlType = "FEAR" } end,
        }
        NS.FG.Roster = function() return { "party1" } end
        ok(#FN.Mine() == 1, "the Tremor button is not there to do the watching")
        FN.Watch()
        FN.Settle()
        ok(#FN.Mine() == 2, "but the fear was still noticed, and earned it")

        -- A HIDDEN ANSWER IS COUNTED, NOT TAKEN FOR "NOBODY" (8 Nov: on Forever nothing was ever kept)
        FN.hidHolds = { count = 0, type = 0, fight = 0 }
        _G.C_LossOfControl = {
            GetActiveLossOfControlDataCountByUnit = function() return secret() end,
            GetActiveLossOfControlDataByUnit = function() return nil end,
        }
        STATE.inCombat = true
        local kind, why = FN.HoldOn("party1")
        STATE.inCombat = false
        ok(kind == nil and why == "hidden" and FN.hidHolds.count == 1 and FN.hidHolds.fight == 1,
           "a secret count: nothing read, and the hiding counted (in a fight)", tostring(why))
        _G.C_LossOfControl = {
            GetActiveLossOfControlDataCountByUnit = function() return 1 end,
            GetActiveLossOfControlDataByUnit = function() return { lossOfControlType = secretString() } end,
        }
        FN.HoldOn("party1")
        ok(FN.hidHolds.type == 1, "a secret type is counted too", FN.hidHolds.type)
        local said = {}
        local keepChat = _G.DEFAULT_CHAT_FRAME
        _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) said[#said + 1] = t end }
        local okH = pcall(NS.DO.holds)
        _G.DEFAULT_CHAT_FRAME = keepChat
        local told = false
        for _, l in ipairs(said) do if l:find("HID the answer 2") then told = true end end
        ok(okH and told, "/bish holds says the client hid it", table.concat(said, " / "))
        FN.hidHolds = { count = 0, type = 0, fight = 0 }
        _G.IsInGroup = keepIG

        _G.C_LossOfControl, NS.FG.Roster, NS.FB.Knows = realLC, realRoster, realKnows
        FN.ShieldReady = realShield
        FN.TankReady = keepTank
        -- and with it back: a character with a watched buff has help AND the shield from the start
        local watchedOne = NS.FS.Target() ~= nil
        local has = false
        for _, k in ipairs(FN.Mine()) do if k == "shield" then has = true end end
        ok(has == (watchedOne and NS.FA.Available()), "the shield button is there exactly when a watched buff is",
           table.concat(FN.Mine(), " "))
        FN.Reset()
    end

    -- MY TANK (14 Oct 2026). Arn: "when im clicking on a friendly target and i click the button it
    -- becomes my personal tank ... puts a teal small sabers so i know where they are going ... and if
    -- i click on it it targets them"
    do
        local FN = NS.FN
        local d = NS.DB()
        local keep = { now = d.now, shown = d.shown, tank = d.tank, UnitExists = _G.UnitExists,
            UnitIsPlayer = _G.UnitIsPlayer, UnitIsFriend = _G.UnitIsFriend, UnitIsUnit = _G.UnitIsUnit,
            GetUnitName = _G.GetUnitName, UnitName = _G.UnitName, NP = _G.C_NamePlate, CF = _G.CreateFrame }
        -- the client draws Lines; this mock's frames get them here
        _G.CreateFrame = function(...)
            local f = keep.CF(...)
            if f then
                function f:CreateLine()
                    local l = self:CreateTexture()
                    function l:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
                    function l:SetThickness(w) self.w = w end
                    function l:SetStartPoint(_, _, x, y) self.from = { x, y } end
                    function l:SetEndPoint(_, _, x, y) self.to = { x, y } end
                    return l
                end
            end
            return f
        end
        local who = { target = { name = "Tobi Three", friend = true } }
        _G.UnitExists = function(u) return who[u] ~= nil end
        _G.UnitIsPlayer = function(u) return who[u] ~= nil end
        _G.UnitIsFriend = function(_, u) return who[u] ~= nil and who[u].friend == true end
        _G.UnitIsUnit = function(a, b) return a == b or (who[b] and who[b].me) or false end
        _G.GetUnitName = function(u) return who[u] and who[u].full end
        _G.UnitName = function(u) return who[u] and who[u].name end
        local plates = {}
        _G.C_NamePlate = { GetNamePlateForUnit = function(u) return plates[u] end }
        d.now, d.shown, d.tank = true, true, nil
        FN.Layout()
        local b = FN.buttons.tank
        ok(b and b:IsShown(), "BiS> now carries a Tank button from the start")
        ok(b:GetAttribute("*type1") == "macro" and (b:GetAttribute("*macrotext1") or "") == "",
           "nobody chosen: its click targets nobody")
        -- no tank yet: a left-click on a friendly target chooses them
        b.__scripts.OnClick(b, "LeftButton")
        ok(FN.Tank() == "Tobi Three" and b:GetAttribute("*macrotext1") == "/target Tobi Three",
           "a friendly target + the button: your tank, and the click now targets them")
        -- the teal X on their plate - a plate that says only "Tobi"
        who.nameplate3 = { name = "Tobi", friend = true }
        plates.nameplate3 = CreateFrame("Frame")
        who.nameplate4 = { name = "Tobi" }               -- an enemy Tobi: never
        plates.nameplate4 = CreateFrame("Frame")
        local tf = FN.tankFrame
        tf.__scripts.OnEvent(tf, "NAME_PLATE_UNIT_ADDED", "nameplate3")
        tf.__scripts.OnEvent(tf, "NAME_PLATE_UNIT_ADDED", "nameplate4")
        local x = FN.tankMarks.nameplate3
        ok(x and x:IsShown() and #x.parts == 6 and x.parts[3].color and x.parts[3].color[2] > 0.8 and x.parts[3].color[1] < 0.3,
           "a small teal X on them - their plate's first word is enough")
        ok(FN.tankMarks.nameplate4 == nil, "an enemy of the same name: no X")
        -- A PLATE ALREADY ON SCREEN when the tank is chosen (Arn's cousin, 14 Oct: "target the tank
        -- right click the shield and no crosshairs"): no NAME_PLATE_UNIT_ADDED ever came for it
        who.nameplate7 = { name = "Rocky", full = "Rocky Road", friend = true }
        plates.nameplate7 = CreateFrame("Frame")
        plates.nameplate7.namePlateUnitToken = "nameplate7"
        _G.C_NamePlate.GetNamePlates = function() return { plates.nameplate7 } end
        local keepTarget = who.target
        who.target = { name = "Rocky", full = "Rocky Road", friend = true }
        b.__scripts.OnClick(b, "RightButton")             -- choose Rocky (a new target: chosen at once)
        ok(FN.Tank() and FN.Tank():find("Rocky", 1, true) and FN.tankMarks.nameplate7 and FN.tankMarks.nameplate7:IsShown(),
           "a plate already on screen when the tank is chosen gets the X at once", FN.Tank())
        b.__scripts.OnClick(b, "RightButton")             -- let go of Rocky
        who.target = keepTarget
        b.__scripts.OnClick(b, "RightButton")             -- Tobi again, as the rest expects
        _G.C_NamePlate.GetNamePlates = nil
        who.nameplate7, plates.nameplate7, FN.tankPlates.nameplate7 = nil, nil, nil
        -- THE TANK'S CELL (Arn, 14 Oct): inside a dungeon no plate is handed over, so the tank's cell in
        -- the grid wears a teal frame - always, there or anywhere
        if NS.FG and NS.FG.Make and NS.FG.anchor then
            who.party1 = { name = "Tobi", full = "Tobi Three", friend = true }
            who.party2 = { name = "Other", full = "Other Guy", friend = true }
            local c1 = NS.FG.Make("TankCell1", NS.FG.anchor) c1.unit = "party1"
            local c2 = NS.FG.Make("TankCell2", NS.FG.anchor) c2.unit = "party2"
            local n0 = #NS.FG.frames
            NS.FG.frames[n0 + 1], NS.FG.frames[n0 + 2] = c1, c2   -- the grid's own list, as a real cell is
            NS.FG.PaintTank(c1) NS.FG.PaintTank(c2)
            ok(c1.tankRing and c1.tankRing:IsShown() and not c2.tankRing:IsShown(),
               "the tank's cell wears the teal frame; nobody else's does")
            b.__scripts.OnClick(b, "RightButton")         -- let go of the tank
            ok(not c1.tankRing:IsShown(), "no tank: no frame (choosing or letting go repaints the grid)")
            b.__scripts.OnClick(b, "RightButton")         -- Tobi again
            ok(c1.tankRing:IsShown(), "and back")
            NS.FG.frames[n0 + 2], NS.FG.frames[n0 + 1] = nil, nil
            who.party1, who.party2 = nil, nil
        end
        -- a plate whose NAME IS SECRET (14 Oct, Arn's BugGrabber in a battleground: "attempt to
        -- compare local 'n' (a secret string value)")
        local keepGUN, keepUN = _G.GetUnitName, _G.UnitName
        _G.GetUnitName = function(u) if u == "nameplate6" then return secretString() end return keepGUN(u) end
        _G.UnitName = function(u) if u == "nameplate6" then return secretString() end return keepUN(u) end
        who.nameplate6 = { friend = true }
        plates.nameplate6 = CreateFrame("Frame")
        local okS, errS = pcall(tf.__scripts.OnEvent, tf, "NAME_PLATE_UNIT_ADDED", "nameplate6")
        ok(okS and FN.tankMarks.nameplate6 == nil, "a plate with a hidden name: no error, no X", errS)
        _G.GetUnitName, _G.UnitName = keepGUN, keepUN
        who.nameplate6, plates.nameplate6 = nil, nil
        FN.tankPlates.nameplate6 = nil
        tf.__scripts.OnEvent(tf, "NAME_PLATE_UNIT_REMOVED", "nameplate3")
        ok(FN.tankMarks.nameplate3 == nil, "their plate goes: the X with it")
        tf.__scripts.OnEvent(tf, "NAME_PLATE_UNIT_ADDED", "nameplate3")
        -- a left-click with a tank chosen: ours does nothing, the macro targets them
        who.target = { name = "Somebody Else", friend = true }
        b.__scripts.OnClick(b, "LeftButton")
        ok(FN.Tank() == "Tobi Three", "left-click with a tank: targets them, chooses nobody new")
        -- mid-fight, a new tank: the X moves now, the click when the fight ends
        STATE.inCombat = true
        who.target = { name = "Bigtank", friend = true }
        who.nameplate5 = { name = "Bigtank", friend = true }
        plates.nameplate5 = CreateFrame("Frame")
        tf.__scripts.OnEvent(tf, "NAME_PLATE_UNIT_ADDED", "nameplate5")
        b.__scripts.OnClick(b, "RightButton")
        ok(FN.Tank() == "Bigtank" and FN.tankMarks.nameplate5 and FN.tankMarks.nameplate3 == nil,
           "right-click mid-fight: the new tank, the X moves at once")
        ok(b:GetAttribute("*macrotext1") == "/target Tobi Three" and FN.tankDirty, "but the secure click waits")
        STATE.inCombat = false
        tf.__scripts.OnEvent(tf, "PLAYER_REGEN_ENABLED")
        ok(b:GetAttribute("*macrotext1") == "/target Bigtank" and not FN.tankDirty, "the fight over: it targets the new one")
        -- the steppers (Arn: "add the steppers to the tank x too")
        d.tankSize, d.tankLift = 200, 10
        FN.RedrawTank()
        local big = FN.tankMarks.nameplate5
        local tip = big and big.parts[3].to
        local _, _, _, _, y = big:GetPoint(1)
        ok(tip and math.abs(tip[1] - (FN.TANK_W * 2 / 2 - 2)) < 0.01 and y == -FN.TANK_DROP + 10,
           "tank X size 200%, height 10 up: redrawn at once")
        -- SAID PLAINLY: no mark inside dungeons or raids, yes in battlegrounds (Arn's cousin, 14 Oct,
        -- Ragefire: the friendly plate was never handed over; Arn: "weirdly yes inside battlegrounds")
        local keepII = _G.IsInInstance
        local from = #SAID
        _G.IsInInstance = function() return true, "party" end
        ok(FN.MarkLocked() == true, "inside a dungeon: the mark is locked")
        FN.TankWhy()
        local said = table.concat(SAID, " / ", from + 1)
        ok(said:find("inside dungeons and raids the game keeps friendly nameplates", 1, true),
           "/bish tank says so in plain words")
        _G.IsInInstance = function() return true, "raid" end
        ok(FN.MarkLocked() == true, "inside a raid: locked too")
        _G.IsInInstance = function() return true, "pvp" end
        ok(FN.MarkLocked() == false, "in a battleground: not locked - the mark works there")
        _G.IsInInstance = function() return false, "none" end
        ok(FN.MarkLocked() == false, "in the open world: not locked")
        -- NO TANK BUTTON IN A DUNGEON (Arn, 14 Oct: "in dungeon get rid of tank button")
        local function hasTank() for _, k in ipairs(FN.Mine()) do if k == "tank" then return true end end return false end
        local outside = hasTank()
        _G.IsInInstance = function() return true, "party" end
        ok(outside and not hasTank(), "a dungeon: the Tank button leaves BiS> now")
        _G.IsInInstance = function() return true, "raid" end
        ok(hasTank(), "a raid keeps it (the click still targets them)")
        _G.IsInInstance = function() return true, "pvp" end
        ok(hasTank(), "a battleground keeps it")
        _G.IsInInstance = keepII
        -- NO TANK BUTTON ALONE (Arn, 6 Nov: "if im not in a party dont show this button")
        local keepIG = _G.IsInGroup
        _G.IsInGroup = function() return false end
        ok(not hasTank(), "not in a group: no Tank button")
        _G.IsInGroup = function() return true end
        ok(hasTank(), "in a party or a raid: back")
        _G.IsInGroup = keepIG
        d.tankSize, d.tankLift = 999, -999
        ok(FN.TankSize(d) == 200 and FN.TankLift(d) == -40, "out-of-range settings are held to the stepper's ends")
        local keys = {}
        for _, o in ipairs(NS.UI.Rows()) do keys[o.key] = true end
        ok(keys.tanksize and keys.tanklift and keys.tanklook, "the steppers are in the options window")
        -- the looks (Arn: "not all want x"): each its own strokes, three glow layers a stroke
        d.tankSize, d.tankLift = nil, nil
        for i, look in ipairs(FN.LOOKS) do
            d.tankLook = i
            FN.RedrawTank()
            local m = FN.tankMarks.nameplate5
            ok(m and m.look == i and #m.parts == #look.strokes * 3 and m:IsShown(),
               "tank mark look " .. look.word .. ": " .. #look.strokes .. " strokes")
        end
        d.tankLook = 99
        ok(FN.TankLook(d) == 1, "an unknown look falls back to the X")
        d.tankLook = nil
        d.tankSize, d.tankLift = nil, nil
        FN.RedrawTank()
        -- right-click on them again: let go; and an enemy or yourself is never a tank
        b.__scripts.OnClick(b, "RightButton")
        ok(FN.Tank() == nil and FN.tankMarks.nameplate5 == nil and b:GetAttribute("*macrotext1") == "",
           "right-click on your tank again: let go, the X gone")
        who.target = { name = "Enemy Guy" }
        b.__scripts.OnClick(b, "RightButton")
        ok(FN.Tank() == nil, "an enemy is never your tank")
        who.target = { name = "Me", friend = true, me = true }
        b.__scripts.OnClick(b, "RightButton")
        ok(FN.Tank() == nil, "nor are you")
        for u in pairs(FN.tankMarks) do FN.UnmarkTank(u) end
        FN.tankPlates = {}
        d.now, d.shown, d.tank = keep.now, keep.shown, keep.tank
        _G.UnitExists, _G.UnitIsPlayer, _G.UnitIsFriend, _G.UnitIsUnit = keep.UnitExists, keep.UnitIsPlayer, keep.UnitIsFriend, keep.UnitIsUnit
        _G.GetUnitName, _G.UnitName, _G.C_NamePlate, _G.CreateFrame = keep.GetUnitName, keep.UnitName, keep.NP, keep.CF
        FN.Layout()
    end

    -- THE BLOCK LINES UP; THE BUTTONS DO NOT PRETEND TO BE CELLS. A button 84 wide gives an icon
    -- a cell of clickable area, which is how two buttons read as three and most of the block was
    -- invisible help button (Arn, 1 Oct).
    do
        local FG = NS.FG
        local cellW, cellH, pad = FG.CELL_W, FG.CELL_H, FG.CELL_PAD
        ok(cellW == 84 and cellH == 34, "the grid still publishes its cell size", cellW .. "x" .. cellH)
        -- one and two buttons both fit inside a single cell's width, so the block stays one column
        ok(2 * cellH + pad <= cellW,
           "two square buttons fit in one cell column, so the block does not grow for them",
           (2 * cellH + pad) .. " vs " .. cellW)
        -- EXACTLY ITS BUTTONS. A block padded out to a whole cell column left one button sitting
        -- in 84 pixels of nothing, which Arn objected to twice.
        -- wide enough for the bar's own label: at one button the body is 34 and "BiS> now" is not
        ok(FN.BlockWidth(1) == FN.HEADER_MIN, "one button is as wide as its own name",
           tostring(FN.BlockWidth(1)))
        ok(FN.HEADER_MIN < cellW, "but still narrower than a cell", tostring(FN.HEADER_MIN))
        ok(FN.BlockWidth(2) == 2 * cellH + pad, "two is two, with the grid's gap between",
           tostring(FN.BlockWidth(2)))
        for _, n in ipairs({ 2, 3, 5 }) do
            ok(FN.BlockWidth(n) == n * cellH + (n - 1) * pad,
               ("%d buttons take exactly the room %d buttons need"):format(n, n),
               tostring(FN.BlockWidth(n)))
        end
        -- ROWS OF FIVE (Arn, 17 Oct: "okay at 4-5 buttons a row then we should make another row")
        local c5, r5 = FN.Grid(5)
        local c6, r6 = FN.Grid(6)
        local c11, r11 = FN.Grid(11)
        ok(c5 == 5 and r5 == 1, "five: one row")
        ok(c6 == 5 and r6 == 2, "six: five, and a second row", c6 .. "x" .. r6)
        ok(c11 == 5 and r11 == 3, "eleven: three rows of five at most")
    end

    ok(FN.Place("help") == 1, "the help button starts first")
    ok(#FN.Order() == #FN.BUTTONS, "and every button is in the order")

    -- NOTHING MOVES WHILE THE FIGHT IS ON
    FN.Note("poison")
    FN.Note("poison")
    ok(FN.Place("poison") == 3, "noting something mid-fight moves nothing yet", tostring(FN.Place("poison")))

    -- ONE SWAP PER OCCURRENCE: two poisons in one fight walks it up two places - except it cannot
    -- pass the help button, so it lands second
    ok(FN.Settle() == true, "the fight ending settles the order")
    ok(FN.Place("poison") == 2, "poison moved up", tostring(FN.Place("poison")))
    ok(FN.Place("help") == 1, "and the help button did not move")

    -- ARN'S EXACT EXAMPLE: poison in two fights passes fear in one
    FN.Reset()
    FN.Note("tremor") FN.Settle()
    ok(FN.Place("tremor") == 2, "one fear, one place up", tostring(FN.Place("tremor")))
    FN.Note("poison") FN.Settle()
    FN.Note("poison") FN.Settle()
    ok(FN.Place("poison") == 2 and FN.Place("tremor") == 3,
       "poison in two fights passes fear in one",
       tostring(FN.Place("poison")) .. "/" .. tostring(FN.Place("tremor")))

    -- ONE SWAP PER OCCURRENCE, PROVEN. With three buttons and help pinned, the furthest anything
    -- can travel is one place - so "twice in a fight moves it twice" was not actually being tested,
    -- and a mutation that moved things once per FIGHT passed the whole suite. Caught by mutating
    -- it (M16, 1 Oct). A fourth button is added here to give the order room to show the difference.
    FN.BUTTONS[#FN.BUTTONS + 1] = { id = 9, key = "testonly", word = "Test" }
    FN.Reset()
    -- (counted from the end, so a new button - the oil, 11 Oct - does not break the arithmetic)
    local last = #FN.BUTTONS
    ok(FN.Place("testonly") == last, "the extra button starts last")
    FN.Note("testonly") FN.Note("testonly")
    FN.Settle()
    ok(FN.Place("testonly") == last - 2,
       "twice in one fight moves it TWO places, not one",
       tostring(FN.Place("testonly")))
    FN.BUTTONS[#FN.BUTTONS] = nil
    FN.Reset()

    -- and Arn's example again, now that the order has room
    FN.Note("tremor") FN.Settle()
    FN.Note("poison") FN.Settle()
    FN.Note("poison") FN.Settle()
    ok(FN.Place("poison") == 2 and FN.Place("tremor") == 3,
       "poison in two fights still passes fear in one with the extra room gone")

    -- NOTHING PASSES A PINNED BUTTON, however bad the night
    for _ = 1, 20 do FN.Note("poison") end
    FN.Settle()
    ok(FN.Place("help") == 1, "twenty poisons still do not move the help button")

    ok(FN.Settle() == false, "a quiet fight changes nothing, so nothing is written")

    -- THE ORDER IS THE MEMORY, and it has to survive a restart in a handful of characters
    local digits = FN.Encode()
    ok(digits:find("%d"), "the order writes down as digits", digits)
    FN.Reset()
    ok(FN.Place("poison") == 3, "reset puts it back")
    ok(FN.Decode(digits) == true, "and the digits are read back")
    ok(FN.Place("poison") == 2, "with the learned order intact", tostring(FN.Place("poison")))

    -- AN OLDER MACRO KNOWS ABOUT FEWER BUTTONS, and must not drop the ones it never heard of
    FN.Reset()
    ok(FN.Decode("1") == true, "a macro from a version with one button still reads")
    ok(#FN.Order() == #FN.BUTTONS, "and the buttons it never heard of keep their places")
    ok(FN.Place("help") == 1, "with help still first")

    ok(FN.Decode("") == false, "nothing is not an order")
    ok(FN.Decode(nil) == false, "and neither is nil")
    ok(FN.Note("nosuchbutton") == false, "a button we do not have is not noted")

    FN.Reset()

    -- WEAPON OIL (Arn, 11 Oct: "got the mana oil how do i bring it up in bis now, does it scan my
    -- bags for oils?"). The client's shape: C_Item.GetItemCount(id) -> a count;
    -- GetWeaponEnchantInfo() -> hasMainHandEnchant first.
    local bags, oiled, asked = {}, false, 0
    local keep = { count = C_Item and C_Item.GetItemCount, ench = _G.GetWeaponEnchantInfo,
                   icon = C_Item and C_Item.GetItemIconByID }
    _G.C_Item = _G.C_Item or {}
    _G.C_Item.GetItemCount = function(id) asked = asked + 1 return bags[id] or 0 end
    _G.C_Item.GetItemIconByID = function(id) return "Interface\\Icons\\Oil" .. id end
    _G.GetWeaponEnchantInfo = function() return oiled end
    ok(FN.Oil() == nil, "no oil in your bags: no oil")
    local function mineHas(k) for _, x in ipairs(FN.Mine()) do if x == k then return true end end end
    ok(not mineHas("oil"), "and no oil button")
    bags[20747] = 3                                   -- Lesser Mana Oil
    bags[20749] = 1                                   -- Brilliant Wizard Oil
    ok(FN.Oil() and FN.Oil().id == 20747, "the best oil for a healer is chosen: mana before wizard")
    bags[20748] = 2                                   -- Brilliant Mana Oil
    ok(FN.Oil().id == 20748, "and Brilliant before Lesser")
    ok(mineHas("oil"), "with an oil in your bags, the oil button is yours")
    local b = { art = CreateFrame("Frame"):CreateTexture(), attrs = {} }
    function b:SetAttribute(k, v) self.attrs[k] = v end
    FN.ArmOil(b)
    ok(b.attrs["*type1"] == "macro" and b.attrs["*macrotext1"] == "/use item:20748\n/use 16",
       "one click: the oil, then the main hand (the macro Arn saw, without the stone)", b.attrs["*macrotext1"])
    ok(b.art.__texture == "Interface\\Icons\\Oil20748", "wearing the oil's own icon")
    oiled = false
    ok(FN.PaintOil(b) == true, "the weapon has no oil: lit")
    oiled = true
    ok(FN.PaintOil(b) == false, "oiled: dimmed")
    _G.GetWeaponEnchantInfo = function() return secret() end
    ok(FN.PaintOil(b) == false, "a client that will not say: dimmed, never a guess")
    _G.GetWeaponEnchantInfo = function() return oiled end
    -- THE BUFF ON A HOVER (Arn: "a small tooltip so we can see what oil it is maybe not the name but
    -- the buff"): the game's own item tooltip - never numbers typed in - then where it stands
    local realEnch = _G.GetWeaponEnchantInfo
    _G.GetWeaponEnchantInfo = function() return true, 23 * 60000 end
    -- CONCISE (Arn: "dont need to repeat while applied to target weapon it ... restores 5 mana ... every
    -- 5 seconds ... increases healing ... up to 10 ... lasts 30"): the numbers out of the client's own
    -- text - his screenshot's wording, Forever's values
    local MINOR = "When applied to target weapon it restores 5 mana to the caster every 5 seconds and "
        .. "increases healing done by up to 10. Lasts for 30 minutes."
    ok(FN.OilEffect(MINOR) == "+5 mana / 5 sec · +10 healing · 30 min",
       "the effect, short: just the numbers", tostring(FN.OilEffect(MINOR)))
    ok(FN.OilEffect("When applied to target weapon it increases spell damage and healing by up to 36 "
        .. "and spell critical strike chance by 1%. Lasts for 30 minutes.")
       == "+36 spell damage & healing · +1% spell crit · 30 min", "a wizard oil reads right too")
    ok(FN.OilEffect("Dieses Öl ...") == nil and FN.OilEffect(nil) == nil,
       "text that does not read as an oil gives nothing - the name is said instead")
    local keepSpell = { gis = C_Item.GetItemSpell, desc = C_Spell.GetSpellDescription }
    _G.C_Item.GetItemSpell = function(id) return "Mana Oil", 25117 end
    _G.C_Spell.GetSpellDescription = function(id) return id == 25117 and MINOR or "" end
    TIP.item = nil
    ok(FN.OilTip(b) and TIP.lines[1] == "+5 mana / 5 sec · +10 healing · 30 min" and TIP.item == nil,
       "the hover's first line is the short effect - not the whole item tooltip", TIP.lines[1])
    _G.C_Item.GetItemSpell, _G.C_Spell.GetSpellDescription = keepSpell.gis, keepSpell.desc
    local tipText = table.concat(TIP.lines, "|")
    ok(tipText:find("on your main hand: 23 min left", 1, true) and tipText:find("2 left in your bags", 1, true),
       "then how long it has left on the weapon, and how many are in the bags", tipText)
    _G.GetWeaponEnchantInfo = function() return false end
    FN.OilTip(b)
    ok(table.concat(TIP.lines, "|"):find("not on your weapon - click to apply", 1, true),
       "and says so when the weapon has none")
    _G.GetWeaponEnchantInfo = function() return secret(), secret() end
    ok(pcall(FN.OilTip, b), "a hidden answer does not break the tooltip")
    _G.GetWeaponEnchantInfo = realEnch
    STATE.inCombat = true
    bags[20748] = nil
    ok(FN.ArmOil(b) == nil and b.attrs["*macrotext1"] == "/use item:20748\n/use 16",
       "in a fight nothing secure is rewritten")
    STATE.inCombat = false
    ok(FN.ArmOil(b).id == 20747, "after it, the button follows the bags: Lesser Mana Oil now")
    -- LEAN: a bag storm costs seven counts a burst, and a relayout only when the answer moved
    asked = 0
    ok(FN.Oil() ~= nil and asked <= #FN.OILS, "asking costs at most one count per oil kind", asked)
    _G.C_Item.GetItemCount, _G.C_Item.GetItemIconByID, _G.GetWeaponEnchantInfo = keep.count, keep.icon, keep.ench
    FN.Reset()
end

----------------------------------------- does anything say somebody was hit (0.8.x) --
do
    ok(pcall(NS.DO.hits), "the hit counter runs before anything has arrived")
    ok(pcall(SlashCmdList.BISHEALING, "hits"), "/bish hits threw")

    -- it must count what arrives, per unit, without reading anything
    local frames, realCreate = {}, _G.CreateFrame
    _G.CreateFrame = function(...) local f = realCreate(...) frames[#frames + 1] = f return f end
    NS.DO.hits("reset")
    _G.CreateFrame = realCreate
    local fired = false
    for _, f in ipairs(frames) do
        local on = f.__scripts and f.__scripts.OnEvent
        if on then
            on(f, "UNIT_COMBAT", "party1")
            on(f, "UNIT_COMBAT", "party1")
            on(f, "UNIT_COMBAT", "party2")
            fired = true
        end
    end
    if fired then ok(pcall(NS.DO.hits), "and after events arrive it still runs") end

    -- A SECRET UNIT TOKEN MUST NOT BECOME A TABLE KEY. A secret string refuses to be one, which is
    -- the whole reason NS.Plain exists - and an event handler is exactly where an unguarded one
    -- would arrive.
    for _, f in ipairs(frames) do
        local on = f.__scripts and f.__scripts.OnEvent
        if on then ok(pcall(on, f, "UNIT_COMBAT", secret()),
                      "a secret unit token is not used as a key") end
    end
end

--------------------------------------------- who is feared, and may I tell anyone --
do
    local realLC, realCI = _G.C_LossOfControl, _G.C_ChatInfo

    _G.C_LossOfControl = nil
    ok(NS.DO.control() == false, "with no C_LossOfControl it says so rather than throwing")
    ok(pcall(SlashCmdList.BISHEALING, "control"), "/bish control threw with no loss-of-control")

    -- the shape that makes this ONE addon instead of two: readable for another unit
    _G.C_LossOfControl = {
        GetActiveLossOfControlDataCount = function() return 1 end,
        GetActiveLossOfControlData = function() return { lossOfControlType = "FEAR" } end,
        GetActiveLossOfControlDataCountByUnit = function() return 1 end,
        GetActiveLossOfControlDataByUnit = function() return { lossOfControlType = "FEAR" } end,
    }
    ok(NS.DO.control() == true, "a client that answers about other units is walked without error")

    -- A SECRET ANSWER IS THE CASE THAT KILLS THE FEATURE, so it must not throw on the way past:
    -- a secret table cannot even be indexed, which is how the totem bug of 21 Sep started.
    _G.C_LossOfControl.GetActiveLossOfControlDataByUnit = function() return secret() end
    _G.C_LossOfControl.GetActiveLossOfControlData = function() return secret() end
    ok(pcall(NS.DO.control), "a secret loss-of-control answer is reported, not indexed")

    -- and one that refuses outright
    _G.C_LossOfControl.GetActiveLossOfControlDataByUnit = function() error("nope", 2) end
    ok(pcall(NS.DO.control), "a refusal is reported too")

    _G.C_ChatInfo = { InChatMessagingLockdown = function() return true end,
                      AreOutgoingAddonChatMessagesRestricted = function() return secret() end }
    ok(pcall(NS.DO.control), "a secret answer about messaging does not throw either")

    _G.C_LossOfControl, _G.C_ChatInfo = realLC, realCI
end

------------------------------------- will the client pick a brightness (BiS> now) --
--
-- A measurement again, so what is tested is that it survives every client it might meet: one with
-- no C_CurveUtil, one whose makers refuse, and one that answers. It must never throw, because a
-- diagnostic that falls over is one nobody runs twice.
do
    local realCU = _G.C_CurveUtil

    _G.C_CurveUtil = nil
    ok(NS.DO.curve() == false, "with no C_CurveUtil it says so rather than throwing")
    ok(pcall(SlashCmdList.BISHEALING, "curve"), "/bish curve threw with no curves")

    -- a maker that refuses bare, which is likely: these usually want points up front
    _G.C_CurveUtil = { CreateCurve = function() error("Usage: CreateCurve(points)", 2) end }
    ok(pcall(NS.DO.curve), "a maker that refuses with no arguments is reported, not raised")

    -- one that answers, with its methods behind a metatable the way a real object would be
    local obj = setmetatable({}, { __index = { AddPoint = function() end,
                                               Evaluate = function() return 0.5 end } })
    _G.C_CurveUtil = {
        CreateCurve = function() return obj end,
        CreateColorCurve = function() return obj end,
        EvaluateColorValueFromBoolean = function(_, a) return a end,
    }
    ok(NS.DO.curve() == true, "and a client that answers is walked without error")
    ok(pcall(SlashCmdList.BISHEALING, "curve"), "/bish curve threw on a client that answers")

    _G.C_CurveUtil = realCU
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

------------------------------------------- a totem slot, asked about first (3 Oct) --
--
-- ForeverAuras 0.44 added C_Secrets.ShouldTotemSlotBeSecret and asks it BEFORE reading. A refusal
-- we are told about in advance is an answer; a refusal discovered by reading is only a shrug.
do
    local FB = NS.FB
    local realSecrets, realTotem = _G.C_Secrets, _G.GetTotemInfo
    local down, mode = {}, "plain"
    _G.GetTotemInfo = function(slot)
        if mode == "secret" then return secret() end
        if mode == "throw" then error("cannot be accessed", 2) end
        if down[slot] then return true, "Totem", 100, 300 end
        return true, "", 0, 0                      -- an empty slot, as the client answers (measured 11 Nov)
    end

    -- no such question on this client: read and guard, the way it always did
    _G.C_Secrets = { HasSecretRestrictions = function() return true end }
    down[1] = true
    ok(FB.TotemSlot(1) == true, "a totem that is down reads as down")
    ok(FB.TotemSlot(2) == false, "an empty slot reads as empty - though the client answers it TRUE with no name and 0 s (11 Nov)")

    -- the client says this slot is secret: do not even read it
    local asked = {}
    _G.C_Secrets.ShouldTotemSlotBeSecret = function(slot) asked[slot] = true return slot == 2 end
    ok(FB.TotemSlot(1) == true, "a slot the client says is readable is read")
    ok(FB.TotemSlot(2) == nil, "a slot it says is secret is not read at all")
    ok(asked[2] == true, "and it was asked before the read, not after")

    -- THE GUARD AFTER THE READ STAYS. Being told a slot is readable and having it come back
    -- readable are two different claims, and on 21 Sep one came back secret out of combat.
    _G.C_Secrets.ShouldTotemSlotBeSecret = function() return false end
    mode = "secret"
    ok(FB.TotemSlot(1) == nil, "a slot that answers secret anyway is still not trusted")
    mode = "throw"
    ok(FB.TotemSlot(1) == nil, "and one that throws is not an empty slot")
    mode = "plain"

    -- a secret ANSWER to the question itself is a no
    _G.C_Secrets.ShouldTotemSlotBeSecret = function() return secret() end
    ok(FB.TotemSlot(1) == nil, "a secret answer about secrecy is treated as secret")
    _G.C_Secrets.ShouldTotemSlotBeSecret = function() error("nope", 2) end
    ok(FB.TotemSlot(1) == nil, "so is a refusal to answer it")

    _G.C_Secrets, _G.GetTotemInfo = realSecrets, realTotem
end

-- ---------------------------------------------------------------- does every label FIT its window
-- (6 Oct 2026, ported from BiSTools) Arn, on BiSTools' Spawns window: "make a check for cut offs or
-- overflows that happens often". Every shown label inside a window is measured where it actually
-- starts - following what it is pinned to, through buttons, icons and other labels - and must end
-- inside the window.
--
-- WIDTH, CALIBRATED ON THE CLIENT, NOT GUESSED: capitals and digits 0.75 px per point ("NEED MATS",
-- BiSCraft, 11 Sep), lowercase 0.55, spaces and punctuation 0.3 (Arn's screenshot: "click a mob to
-- see its spawns" at 9 pt ran ~10 px past a 124 px window). The mock's own GetStringWidth stays as
-- it is: addon code trims by it, and changing it changes what the addon draws.
--
-- A label pinned on BOTH sides (the cell's name, LEFT and RIGHT) is a box: the client cuts the text
-- at the box with "..." - which the cell name does on purpose, up to the role icon - so its BOX is
-- what must fit. A label given a width is a box too, and text wider than it WRAPS onto a line
-- nobody drew room for: that is a failure.
local FIT = {}
function FIT.textW(fs)
    local t, tex = tostring(fs.__text or ""), 0
    t = t:gsub("|T[^|]-:(%d+):%d+[^|]*|t", function(w) tex = tex + tonumber(w) return "" end)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local px = 0
    for ch in t:gmatch(".") do
        if ch:match("[%u%d]") then px = px + 0.75 elseif ch:match("%l") then px = px + 0.55 else px = px + 0.3 end
    end
    return px * (fs.__size or 12) + tex
end
function FIT.isLabel(r) return r.__size ~= nil end
-- one anchor as { point, rel, relPoint, x }: the short form SetPoint("LEFT", 4, 0) is the parent
function FIT.norm(r, p)
    if type(p[2]) == "table" then return p[1], p[2], p[3] or p[1], p[4] or 0 end
    if type(p[2]) == "number" then return p[1], r.__parent, p[1], p[2] end
    return p[1], r.__parent, p[1], 0
end
function FIT.ax(relL, relW, rp)
    if rp:find("LEFT") then return relL elseif rp:find("RIGHT") then return relL + relW end
    return relL + relW / 2
end
-- left edge and width, in px from the window's left; nil when the chain cannot be followed honestly
function FIT.box(r, root, rootW, depth)
    if r == root then return 0, rootW end
    if (depth or 0) > 12 or r == nil then return nil end
    local d = (depth or 0) + 1
    if r.__allpoints then return FIT.box(type(r.__allpoints) == "table" and r.__allpoints or r.__parent, root, rootW, d) end
    local pts = r.points or {}
    local lp, rpnt                       -- the point holding the left edge, the one holding the right
    for _, p in ipairs(pts) do
        if p[1]:find("LEFT") then lp = p elseif p[1]:find("RIGHT") then rpnt = p end
    end
    if lp and rpnt then                  -- pinned on both sides: a box between them
        local a, rel, rp, x = FIT.norm(r, lp)
        local l1, w1 = FIT.box(rel, root, rootW, d)
        local _, rel2, rp2, x2 = FIT.norm(r, rpnt)
        local l2, w2 = FIT.box(rel2, root, rootW, d)
        if not (l1 and l2) then return nil end
        local left = FIT.ax(l1, w1, rp) + x
        return left, FIT.ax(l2, w2, rp2) + x2 - left
    end
    local p = lp or rpnt or pts[#pts]
    if not p then return nil end
    local w
    if FIT.isLabel(r) then w = r.__w or FIT.textW(r) else w = r.__w end
    if not w then return nil end
    local point, rel, rp, x = FIT.norm(r, p)
    local relL, relW = FIT.box(rel, root, rootW, d)
    if not relL then return nil end
    local a = FIT.ax(relL, relW, rp) + x
    if point:find("LEFT") then return a, w elseif point:find("RIGHT") then return a - w, w end
    return a - w / 2, w
end
function FIT.shownIn(r, root)
    if r.__shown == false then return false end
    local p = r.__parent
    while p do
        if p.__shown == false then return false end
        if p == root then return true end
        p = p.__parent
    end
    return false
end
-- the window's own width: SetWidth, or what its two anchors span
function FIT.width(root, depth)
    if root.__w then return root.__w end
    if (depth or 0) > 8 then return nil end
    local lp, rpnt
    for _, p in ipairs(root.points or {}) do
        if p[1]:find("LEFT") then lp = p elseif p[1]:find("RIGHT") then rpnt = p end
    end
    if not (lp and rpnt) then return nil end
    local _, rel, rp, x = FIT.norm(root, lp)
    local _, rel2, rp2, x2 = FIT.norm(root, rpnt)
    if rel ~= rel2 or not rel then return nil end
    local rw = FIT.width(rel, (depth or 0) + 1)
    return rw and (FIT.ax(0, rw, rp2) + x2 - FIT.ax(0, rw, rp) - x)
end
local function plainText(t) return (tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function fitsIn(root, what)
    local width, bad, measured = FIT.width(root), {}, 0
    ok(type(width) == "number", what .. ": the window has a width to measure against", tostring(width))
    if type(width) ~= "number" then return end
    for _, fs in ipairs(LABELS) do
        if type(fs.__text) == "string" and fs.__text ~= "" and FIT.shownIn(fs, root) then
            local l, w = FIT.box(fs, root, width)
            if l then
                measured = measured + 1
                local tw = FIT.textW(fs)
                if l < -1 or l + w > width + 1 then
                    bad[#bad + 1] = ("%q needs %d px from %d, the window is %d"):format(plainText(fs.__text), w, l, width)
                elseif fs.__w and tw > fs.__w + 1 then
                    bad[#bad + 1] = ("%q needs %d px in a %d px line - it wraps"):format(plainText(fs.__text), tw, fs.__w)
                end
            end
        end
    end
    ok(measured > 0, what .. ": the fit check measured something (a check that sees nothing proves nothing)")
    ok(#bad == 0, what .. ": every label fits - " .. table.concat(bad, "; "))
    if os.getenv("FIT_SAY") then print(("fit: %-45s %2d label(s) in %d px"):format(what, measured, width)) end
    return measured
end

do
    local FM = NS.FM
    local d = NS.DB()

    -- THE MOUSE WINDOW, empty and then with the longest names it can hold: every tab, every ping
    FM.win = nil
    local w = FM.Window()
    w:Show()
    for i, m in ipairs(FM.MODS) do
        w.mod = m.key
        w:Refresh()
        fitsIn(w, "the mouse window, " .. m.label .. " tab")
    end
    -- and IN A FIGHT, when the foot line changes its words
    STATE.inCombat = true
    w:Refresh()
    fitsIn(w, "the mouse window, in combat")
    STATE.inCombat = false
    w:Refresh()
    for _, t in ipairs(w.tabs) do fitsIn(t, "the " .. tostring(t.text.__text) .. " tab's own button") end
    for _, b in ipairs(w.pings or {}) do
        if b.text.__shown ~= false then fitsIn(b, "the " .. tostring(b.text.__text) .. " ping button") end
    end

    -- A PING, DRAGGED (16 Oct 2026, Arn on a hunter: "why are these not draggable" - "I'm dragging
    -- the assist button"). The cursor cannot carry a ping, so the drag is ours: a ghost follows the
    -- mouse, and letting go over a mouse button drops it there.
    w.mod = ""
    w:Refresh()
    local ping = w.pings[1]
    local target = w.slots.right
    FM.Clear("", "right")
    ping.__scripts.OnDragStart(ping)
    ok(FM.held == ping.ping, "pressing and dragging a ping picks it up")
    ok(FM.ghost and FM.ghost:IsShown(), "a ghost of it follows the mouse")
    target.__mouseOver = true
    ping.__scripts.OnDragStop(ping)
    target.__mouseOver = false
    ok(FM.Get("", "right") == FM.PingBind(ping.ping), "let go over the right button: it is bound there")
    ok(FM.held == nil and not FM.ghost:IsShown(), "nothing left held, the ghost gone")
    -- let go over nothing: it stays held, lit, for the click way
    ping.__scripts.OnDragStart(ping)
    ping.__scripts.OnDragStop(ping)
    ok(FM.held == ping.ping and not FM.ghost:IsShown(), "dropped on nothing: still held, for click-then-click")
    FM.held = nil
    FM.Clear("", "right")
    w:Refresh()
    w:Hide()

    -- THE GRID'S HEADER and the cell headers, with the longest words they carry
    -- the grid header is one group wide for a party (84) and two for a small raid: measured at
    -- both, saying the longest things it says - a missing shield, and the mana in a fight
    local h = FG.header
    if h then
        local keepW, keepKnown = h.__w, NS.FS and NS.FS.known
        for _, width in ipairs({ 84, 168, 200 }) do
            h.__w = width
            if NS.FS then NS.FS.known = { "Lightning Shield" } end
            h.__word = nil
            FG.PaintRegen(h)
            fitsIn(h, ("the grid header at %d px, %s"):format(width, tostring(h.title.__text)))
            STATE.inCombat = true
            NS.FR.spentAt = nil
            h.__word = nil
            FG.PaintRegen(h)
            fitsIn(h, ("the grid header at %d px in a fight, %s"):format(width, tostring(h.title.__text)))
            STATE.inCombat = false
        end
        h.__w = keepW
        if NS.FS then NS.FS.known = keepKnown end
        h.__word = nil
        FG.PaintRegen(h)
    end
    local was = { me = d.me, target = d.target, tot = d.tot, pets = d.pets }
    NS.DO.target(true) NS.DO.tot(true) NS.DO.pets("solo")
    local headers = 0
    for _, cell in ipairs({ FG.target, FG.tot, FG.petAnchor }) do
        if cell and cell.handle then
            cell:Show() cell.handle:Show()
            fitsIn(cell.handle, "the " .. tostring(cell.handle.word) .. " cell's header")
            headers = headers + 1
        end
    end
    ok(headers >= 3, "the cell headers were there to measure", headers)

    -- A CELL, with a Forever name - a surname and all - and its number
    local realName = _G.UnitName
    _G.UnitName = function() return "Kumlustandrew Surname" end
    local cell = FG.frames and FG.frames[1]
    if cell then
        cell:Show()
        FG.Bind(cell, "party1")
        FG.Paint(cell)
        cell.htext:SetText("100%")
        fitsIn(cell, "a raid cell, with the longest name")
    end

    -- THE MANA ROWS, with a long first name and a full percentage
    STATE.roles = { player = "HEALER", party1 = "HEALER" }
    NS.DO.mana(true)
    STATE.power.player = 100
    for _, row in ipairs(FG.manaRows or {}) do
        if row:IsShown() then
            FG.PaintMana(row, row.unit)
            row.pct:SetText("100%")
            fitsIn(row, "a mana row, " .. tostring(row.who.__text))
        end
    end
    NS.DO.mana(false)
    _G.UnitName = realName
    NS.DO.me(was.me == true) NS.DO.target(was.target == true) NS.DO.tot(was.tot == true)
    d.pets = was.pets
    FG.Layout(FG.anchor)

    -- THE /bish text PANEL, asked about the longest unit word it is given
    STATE.units.focustarget = true
    NS.DO.text("focustarget")
    if NS.textPanel then fitsIn(NS.textPanel, "the /bish text panel") NS.textPanel:Hide() end
    STATE.units.focustarget = nil

    -- THE OPTIONS WINDOW, every row
    if NS.CFG and NS.CFG.Build then
        local win = NS.CFG.Build() or NS.CFG.frame
        ok(win ~= nil, "the options window is there to measure")
        if win then win:Show() fitsIn(win, "the options window") end
    end
end

-- ---------------------------------------------------------------- a slot the client will not let us touch
-- (6 Oct 2026) 0.8.1 on a player's own PC: "Auras.lua:317: calling 'SetSize' on bad self (Attempt
-- to access forbidden object from code tainted by an AddOn)", Count 442 - every frame, because the
-- layout's retry ran it again, and the grid stopped at the first cell each time.
do
    local FA = NS.FA
    local d = NS.DB()
    local wasShown = d.shown
    d.shown = true                       -- the grid ON: a hidden grid lays out no cell at all
    STATE.slotForbidden, STATE.slotTouched = true, 0
    FA.slotRefused, FA.sig = nil, nil
    for _, f in ipairs(FG.frames or {}) do f.auras = nil end
    local laid, why = pcall(FG.Layout, FG.anchor)
    ok(laid, "a slot the client refuses does not stop the layout", tostring(why))
    local shown = 0
    for _, f in ipairs(FG.frames or {}) do if f.unit and f:IsShown() then shown = shown + 1 end end
    ok(shown >= 2, "every cell is laid out, not only the first", shown)
    -- 14 Oct: SIZED AND PLACED IN THEIR CREATION (EllesmereUI's way), so a slot forbidden everywhere
    -- else is never refused at all - the markers stay ON (Arn: "aura markers are off", while "the
    -- target and tot show the poisons")
    ok(FA.slotRefused == nil, "nothing is refused: every marker is placed inside its creation", tostring(FA.slotRefused))
    ok((STATE.slotPlacedInInit or 0) > 0, "the size and anchor went in through the client's hand-over", STATE.slotPlacedInInit)
    local touched = STATE.slotTouched
    ok(touched == 0, "and no slot was touched outside it", touched)
    FA.sig = nil
    for _, f in ipairs(FG.frames or {}) do f.auras = nil end
    ok(pcall(FG.Layout, FG.anchor), "and the next layout is clean")
    ok(STATE.slotTouched == touched, "without touching a slot again", STATE.slotTouched)
    STATE.slotForbidden = false
    FA.slotRefused, FA.sig = nil, nil

    -- AND WHATEVER BREAKS IN THERE NEXT costs the markers, never the grid
    local realSize = FA.MarkerSize
    FA.MarkerSize = function() error("something new the client refuses", 2) end
    FA.attachError = nil
    for _, f in ipairs(FG.frames or {}) do f.auras = nil end
    ok(pcall(FG.Layout, FG.anchor), "an error inside a marker does not stop the layout")
    ok(type(FA.attachError) == "string" and FA.attachError:find("something new", 1, true) ~= nil,
       "and it is kept, to be said", tostring(FA.attachError))
    FA.MarkerSize, FA.attachError, FA.sig = realSize, nil, nil

    for _, f in ipairs(FG.frames or {}) do f.auras = nil end
    d.shown = wasShown
    FG.Layout(FG.anchor)
end

-- ---------------------------------------------------------------- the gold ring, the dim, two columns
-- (7 Oct 2026) A player's two asks: "a toggle highlight self or highlight target" and "a slider
-- for how much it dims out of range". Arn, with the options window at its cap: "can we make two
-- colums".
do
    local d = NS.DB()
    local was = { ring = d.ring, dim = d.dim }
    local cell, other = FG.frames[1], FG.frames[2]
    local realIsUnit = _G.UnitIsUnit
    local targetIs = "party1"
    local targetSecret = false
    _G.UnitIsUnit = function(a, b)
        if b == "target" then
            if targetSecret then return secret() end
            -- "target" IS the target, as the client says: answering false here let a mutant that
            -- ringed the target's own cell pass
            return a == targetIs or a == "target"
        end
        return a == b
    end
    -- gold on the EDGE (the "me" ring) or the TARGET RING drawn at full alpha
    local function gold(c)
        local t = c.edge and c.edge.top
        local col = t and t.__shown and t.__color
        local edge = col and math.abs(col[1] - FG.EDGE.me[1]) < 0.01 and math.abs(col[2] - FG.EDGE.me[2]) < 0.01
        local r = c.targetRing
        local ring = r and r.__shown and r.__alpha == 1
        return (edge or ring) and true or false
    end

    -- ON YOU, the way it always was
    d.ring = nil
    cell.__me, cell.__role, other.__me, other.__role = nil, nil, nil, nil
    FG.PaintEdge(cell, "player")
    FG.PaintEdge(other, "party1")
    ok(gold(cell) and not gold(other), "by default the gold ring is on your own cell")

    -- ON YOUR TARGET
    ok(NS.DO.ring("target") == "target", "/bish ring target")
    FG.PaintEdge(cell, "player")
    FG.PaintEdge(other, "party1")
    ok(gold(other) and not gold(cell), "the ring moves to whoever you have targeted, and off you")
    targetIs = "party2"
    FG.PaintEdge(other, "party1")
    ok(not gold(other), "target someone else and it leaves - asked fresh, never kept")
    -- THE TARGET'S OWN CELL WEARS IT TOO (Arn, 7 Oct: "it should be 3 on the cells on the target
    -- window and tot because its all the same people"), and it is RED ("lets do it red")
    ok(FG.PaintTarget(other, "target", true) == true and other.targetRing.__shown,
       "the target window's own cell wears the target crosshair")
    local stroke = other.targetRing.cross and other.targetRing.cross[1] and other.targetRing.cross[1].__color
    ok(stroke and math.abs(stroke[1] - FG.TARGET[1]) < 0.01 and math.abs(stroke[2] - FG.TARGET[2]) < 0.01
       and FG.TARGET[1] > 0.9 and FG.TARGET[2] < 0.3 and FG.TARGET[3] < 0.3,
       "the target crosshair is red", stroke and table.concat(stroke, ","))
    -- A SECRET ANSWER IS HANDED TO THE CLIENT, which picks the alpha (ClickMend's way) - so the
    -- ring still works inside an instance, and nothing here ever tests who it is
    targetIs, targetSecret = "party1", true
    ok(FG.PaintEdge(other, "party1") and other.targetRing.__shown and other.targetRing.__alphaFromSecret,
       "a secret answer is shown, its alpha chosen by the client from that answer")
    targetSecret = false
    -- NO ANSWER AT ALL (an identity restriction says nil for every pair but "is this me"): hidden
    local keepIsUnit = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) if b == "target" then return nil end return a == b end
    FG.PaintEdge(other, "party1")
    ok(not other.targetRing.__shown, "a client that will not answer gets no ring, never a guessed one")
    _G.UnitIsUnit = keepIsUnit
    -- the role ring underneath is left alone: a healer target is gold on top of yellow
    STATE.roles = { player = "HEALER", party1 = "HEALER" }
    other.__role = nil
    FG.PaintEdge(other, "party1")
    local e = other.edge.top.__color
    ok(e and math.abs(e[1] - FG.EDGE.healer[1]) < 0.01 and other.targetRing.__shown,
       "a targeted healer keeps the yellow ring under the gold one")
    ok(NS.DO.ring() == "me", "/bish ring with nothing after it flips it back")

    -- A CROSSHAIR, NOT A HAIRLINE (Arn, 7 Oct: "this gold ring is honestly too small can we make it
    -- like a cross hair looking thing?"): four corner brackets and four side ticks, every stroke
    -- at least 2 px
    local bars = other.targetRing.cross or {}
    ok(#bars == 12, "the gold mark is a crosshair: 8 corner strokes and 4 side ticks", #bars)
    local thin = 0
    for _, t in ipairs(bars) do if math.min(t.__w or 0, t.__h or 0) < 2 then thin = thin + 1 end end
    ok(thin == 0, "no stroke of it is a 1 px hairline")
    -- AND IT READS ON ANY CLASS COLOUR (Arn, 7 Oct: "yellow cross hairs too blended on warriors"):
    -- every stroke has a dark outline behind it, a pixel bigger on each side
    local outl = other.targetRing.outline or {}
    ok(#outl == #bars, "every stroke has an outline", #outl)
    local dark, bigger = true, true
    for i, o in ipairs(outl) do
        local col = o.__color
        if not (col and col[1] < 0.2 and col[2] < 0.2 and col[3] < 0.2 and (col[4] or 1) >= 0.8) then dark = false end
        local t = bars[i]
        if not (t and o.__w == t.__w + 2 and o.__h == t.__h + 2) then bigger = false end
    end
    ok(dark, "the outline is near-black and solid, so gold reads on a warrior's tan")
    ok(bigger, "and one pixel bigger than its stroke on every side")
    ok(#(other.hoverMark.outline or {}) == 12, "the white mouseover crosshair is outlined too (a priest's cell is white)")
    -- and on YOU too, in the "me" mode: the thin gold edge alone was the complaint
    cell.__me = nil
    FG.PaintEdge(cell, "player")
    ok(cell.targetRing.__shown and cell.targetRing.__alpha == 1, "in 'me' mode your own cell wears the gold crosshair")
    local meStroke = cell.targetRing.cross[1].__color
    ok(meStroke and math.abs(meStroke[1] - FG.EDGE.me[1]) < 0.01 and math.abs(meStroke[2] - FG.EDGE.me[2]) < 0.01,
       "and it is GOLD there - red is for a target, gold is you")
    FG.PaintEdge(other, "party1")
    ok(not other.targetRing.__shown, "and nobody else does")

    -- WHO YOUR MOUSE IS ON (Arn's cousin: "when he mouse hovers over someone's character ... light up
    -- their frame with an indicator ... this is who it is on the frames"). Asked like the target:
    -- plain yes/no, a secret handed to the client, no answer hidden.
    local hoverIs, hoverSecret, hoverNil = nil, false, false
    local keepUE = _G.UnitExists
    _G.UnitExists = function(u) if u == "mouseover" then return hoverIs ~= nil end return keepUE(u) end
    _G.UnitIsUnit = function(a, b)
        if b == "mouseover" then
            if hoverNil then return nil end
            if hoverSecret then return secret() end
            return a == hoverIs
        end
        if b == "target" then return a == targetIs or a == "target" end
        return a == b
    end
    ok(other.hoverMark and #(other.hoverMark.cross or {}) == 12, "every cell carries a white crosshair for the mouse")
    hoverIs = "party1"
    ok(FG.PaintHover(other, "party1") == true and other.hoverMark.__shown, "mouse on party1: party1's cell lights up")
    ok(FG.PaintHover(cell, "player") == false and not cell.hoverMark.__shown, "and nobody else's")
    hoverSecret = true
    ok(FG.PaintHover(other, "party1") == "secret" and other.hoverMark.__shown and other.hoverMark.__alphaFromSecret,
       "a secret answer (inside an instance) is handed to the client, which picks the alpha")
    hoverSecret, hoverNil = false, true
    ok(FG.PaintHover(other, "party1") == false and not other.hoverMark.__shown,
       "no answer at all: no crosshair, never a guessed one")
    hoverNil = false
    hoverIs = nil
    FG.PaintHover(other, "party1")
    ok(not other.hoverMark.__shown, "the mouse leaves everyone: the crosshair goes")

    -- "LoS" ON THE CELL YOUR HEAL COULD NOT SEE (Arn, 18 Oct; line of sight only - "do we really need
    -- range flash logic if we are already dimming?"). The cell under the mouse is known from its own
    -- OnEnter, hooked onto the template's - chained, never replacing it
    do
        local LOS = "Target not in line of sight"
        local realLoS = _G.SPELL_FAILED_LINE_OF_SIGHT
        _G.SPELL_FAILED_LINE_OF_SIGHT = LOS
        local keepUnit, keepShown = other.unit, other.__shown
        other.unit, other.__shown = "party1", true
        FG.over = nil
        ok(FG.HeardError(nil, LOS) == nil, "the mouse on no cell: nothing to flash")
        other:GetScript("OnEnter")(other)
        ok(FG.over == other, "the mouse on a cell: it is the one a click would heal")
        ok(FG.HeardError(nil, LOS) == "LOS", "a heal blocked by line of sight marks it")
        ok(other.flash and other.flash.__shown and other.flash.word:GetText() == "LOS",
           "LOS in the middle of the cell (Arn: \"someting in the middle of the cell LOS\")",
           other.flash and tostring(other.flash.word:GetText()))
        local fade = other.flash and other.flash.fade
        ok(fade and fade.playing and fade.anims[1].to == 0 and fade.anims[1].duration == FG.FLASH_FOR,
           "and it fades by itself - the client's animation, nothing ticking")
        if fade then fade:FINISH() end
        ok(other.flash and not other.flash.__shown, "and is gone when the fade ends")
        ok(FG.HeardError(nil, "Out of range.") == nil, "out of range does NOT flash: the cell already dims for that")
        ok(FG.HeardError(nil, "Not enough mana") == nil, "nor any other error")
        ok(FG.HeardError(nil, secretString()) == nil, "a secret error text is never read")
        NS.DB().flash = false
        ok(FG.HeardError(nil, LOS) == nil, "/bish flash off: no flash")
        NS.DB().flash = nil
        other:GetScript("OnLeave")(other)
        ok(FG.over == nil, "the mouse leaves: no cell under it")
        _G.SPELL_FAILED_LINE_OF_SIGHT = realLoS
        other.unit, other.__shown = keepUnit, keepShown
    end

    -- TARGET AND MOUSE ON THE SAME PERSON (Arn, 7 Oct, second look: "can we make it white takes the
    -- empty space of the red part? if both target and mouse over are the same person and if its
    -- different people it white should look like red"). What is SEEN: shown all the way up, and
    -- an effective alpha above nothing - the frame tree, not a flag, decides it.
    -- (up to the cell: whether the cell itself is on screen is a different test's business)
    local function seen(fr)
        local p = fr
        while p and p ~= other do
            if p.__shown == false then return false end
            p = p.__parent
        end
        local a = fr:GetEffectiveAlpha()
        return type(a) == "number" and a > 0
    end
    -- (third look, same evening: white in every gap was "a little bit to noise ... what if we just
    -- make the 4 little stubs not in the corners white if its the same person instead")
    ok(other.tickMark and #(other.tickMark.tick or {}) == 4 and #(other.tickMark.tickOutline or {}) == 4,
       "same person: four outlined white ticks - the corners are left alone")
    local g1 = other.tickMark.tick[1].__color
    ok(g1 and g1[1] > 0.9 and g1[2] > 0.9 and g1[3] > 0.9, "and they are white")
    -- EXACTLY over the red ticks: the crosshair's last four strokes are its ticks
    local exact = true
    for i = 1, 4 do
        local w, r = other.tickMark.tick[i], other.targetRing.cross[8 + i]
        local wp, rp = w.points and w.points[1], r.points and r.points[1]
        if not (w.__w == r.__w and w.__h == r.__h and wp and rp and wp[1] == rp[1]) then exact = false end
    end
    ok(exact, "each white tick sits exactly on a red one - same size, same anchor")
    ok(other.tickMark.__parent == other.targetRing, "the white ticks are a child of the red crosshair")
    ok(other.hoverMark.__parent == other.notTarget, "the white crosshair sits in the not-target frame")
    local tl
    for _, p in ipairs(other.hoverMark.points or {}) do if p[1] == "TOPLEFT" then tl = p end end
    ok(not tl or ((tl[4] or 0) == 0 and (tl[5] or 0) == 0),
       "and fills the cell like the red one - same shape, same place")

    NS.DO.ring("target")
    local function paint(targeted, moused)
        targetIs = targeted and "party1" or "party2"
        hoverIs = moused and "party1" or "party3"
        FG.PaintEdge(other, "party1")
        FG.PaintHover(other, "party1")
    end
    paint(true, false)
    ok(seen(other.targetRing) and not seen(other.hoverMark) and not seen(other.tickMark),
       "target only: the red crosshair alone")
    paint(false, true)
    ok(not seen(other.targetRing) and seen(other.hoverMark) and not seen(other.tickMark),
       "mouse only (a different person from the target): the white crosshair, like the red")
    paint(true, true)
    ok(seen(other.targetRing) and seen(other.tickMark) and not seen(other.hoverMark),
       "target AND mouse: red corners, white ticks - the white crosshair steps aside")
    paint(false, false)
    ok(not seen(other.targetRing) and not seen(other.hoverMark) and not seen(other.tickMark), "neither: nothing")
    -- AND WITH SECRET ANSWERS, which is the point of doing it with frames: both handed to the client
    targetSecret = true
    hoverSecret = true
    FG.PaintEdge(other, "party1")
    FG.PaintHover(other, "party1")
    ok(other.notTarget.__alphaFromSecret and other.targetRing.__alphaFromSecret
       and other.hoverMark.__alphaFromSecret and other.tickMark.__alphaFromSecret,
       "secret answers: all four alphas are the client's to pick, nothing here tests who it is")
    targetSecret, hoverSecret = false, false
    targetIs, hoverIs = "party1", nil          -- as the tests below expect to find them
    NS.DO.ring("me")

    -- ON ALL THREE (Arn: "if i hover the white should be on all 3"): the target and tot cells are
    -- not in the roster table, and the mouse never lit them
    local fakeT = FG.Make("HoverT", FG.anchor) fakeT.unit = "target"
    local fakeTT = FG.Make("HoverTT", FG.anchor) fakeTT.unit = "targettarget"
    local keptT, keptTT = FG.target, FG.tot
    FG.target, FG.tot = fakeT, fakeTT
    local keepIU = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b)
        if b == "mouseover" then return a == "party1" or a == "target" or a == "targettarget" end
        return keepIU(a, b)
    end
    hoverIs = "party1"
    FG.byUnit = FG.byUnit or {}
    local keptP1 = FG.byUnit.party1
    FG.byUnit.party1 = other
    FG.HoverAll()
    ok(other.hoverMark.__shown and fakeT.hoverMark.__shown and fakeTT.hoverMark.__shown,
       "the mouse on someone who is also your target and tot lights all three cells")
    FG.byUnit.party1 = keptP1
    _G.UnitIsUnit = keepIU
    FG.target, FG.tot = keptT, keptTT
    fakeT:Hide() fakeTT:Hide()
    hoverIs = nil
    -- the mouse has a frame of its own: the grid's frame relays out on EVERY event it hears
    ok(FG.hoverEvents and FG.hoverEvents.__events and FG.hoverEvents.__events.UPDATE_MOUSEOVER_UNIT,
       "UPDATE_MOUSEOVER_UNIT is heard")
    ok(not (FG.events.__events and FG.events.__events.UPDATE_MOUSEOVER_UNIT),
       "and NOT by the frame that relays the whole grid out on every event")
    -- off, and it stays off across a login (the macro, row J)
    hoverIs = "party1"
    ok(NS.DO.hover("off") == false and d.hover == false, "/bish hover off")
    ok(FG.PaintHover(other, "party1") == false and not other.hoverMark.__shown, "then no crosshair at all")
    local body = NS.FK.Encode({}, { hover = false })
    local _, back = NS.FK.Decode(body)
    ok(body:find("J=0") and type(back) == "table" and back.hover == false,
       "off is written into the macro and read back - it survives a login", body)
    ok(not NS.FK.Encode({}, {}):find("J="), "on is the default and writes nothing")
    ok(NS.DO.hover("on") == true and d.hover == true, "/bish hover on (stored as true since 1.0: nil never means on)")
    hoverIs = nil
    _G.UnitExists = keepUE
    _G.UnitIsUnit = keepIsUnit

    -- THE DIM: the plain answer and the fight's ternary both take the player's number
    NS.DO.dim(30)
    ok(math.abs(d.dim - 0.30) < 0.001, "/bish dim 30 keeps 0.30", d.dim)
    ok(NS.DO.dim(5) == 0.2 and NS.DO.dim(95) == 0.9, "and it stays between 20 and 90")
    NS.DO.dim(30)
    STATE.range.party1 = 0
    other.unit = "party1"
    FG.PaintRange(other, "party1")
    ok(math.abs(other:GetAlpha() - 0.30) < 0.001, "out of range is drawn at the player's 30%", other:GetAlpha())
    -- WHO IS NEVER DIMMED (Arn, 7 Oct, with a mob right next to him: "i target these and they are
    -- right next to me why are they dimmed" - his target a hostile Thistlefur, his tot himself)
    do
        -- a HOSTILE target: a heal's range means nothing for an enemy (the client answers nil)
        STATE.hostile.target = true
        FG.PaintRange(other, "target")
        ok(other:GetAlpha() == 1, "a hostile target is not dimmed by the range of a heal", other:GetAlpha())
        STATE.hostile.target = nil
        -- the TOT, when the spell gives no answer: UnitInRange only checks party and raid, and for
        -- "targettarget" says false-but-did-not-check - which is no answer, not "out of range"
        STATE.rangeNil = true
        FG.PaintRange(other, "targettarget")
        ok(other:GetAlpha() == 1, "a unit UnitInRange did not check is not dimmed (Arn's tot was himself)", other:GetAlpha())
        STATE.rangeNil = false
        -- IN COMBAT BOTH OF UnitInRange's ANSWERS ARE SECRET, and `checked == false` on a secret
        -- threw (BugGrabber, 7 Oct). Lua 5.1 cannot make a table == false throw, so the promise is
        -- tested: `checked` is ASKED ABOUT before anything compares it. In the wrong order the
        -- comparison is just false here, short-circuits, and the question is never asked.
        STATE.rangeNil, STATE.unitRangeBothSecret = true, true
        local askedAbout = false
        local realSecret = NS.Secret
        NS.Secret = function(v) if v == STATE.lastChecked and v ~= nil then askedAbout = true end return realSecret(v) end
        ok(pcall(FG.PaintRange, other, "party1"), "both answers secret: the range paint does not throw")
        NS.Secret = realSecret
        ok(askedAbout, "and the 'did it check' answer was asked about before it was compared")
        STATE.rangeNil, STATE.unitRangeBothSecret, STATE.lastChecked = false, false, nil
        -- and YOU, always: nobody is out of range of themselves
        STATE.range.player = 0
        FG.PaintRange(other, "player")
        ok(other:GetAlpha() == 1, "your own cell is never dimmed", other:GetAlpha())
        STATE.range.player = nil
        FG.PaintRange(other, "party1")
    end
    -- THE HEADER ON A CELL IS NOT DIMMED WITH IT (Arn, 7 Oct, at 20%: "it also dimmed the header
    -- of target and tot"). The header is the cell's child - so it shows and hides with the cell -
    -- but it ignores the cell's alpha: "BiS> target" says which cell this is, and that does not
    -- fade because the person did.
    do
        local hadHandle = other.handle
        other.handle = nil
        local h = FG.CellHeader(other, "dimtest", other)
        ok(h and h.__parent == other, "the header is still the cell's child (shows and hides with it)")
        ok(math.abs(h:GetEffectiveAlpha() - 1) < 0.001,
           "and draws at full strength while its cell is dimmed to 30%", h:GetEffectiveAlpha())
        if h then h:Hide() end
        other.handle = hadHandle
    end
    local realCurve, handed = C_CurveUtil.EvaluateColorValueFromBoolean, nil
    C_CurveUtil.EvaluateColorValueFromBoolean = function(b, t, f) handed = f return realCurve(b, t, f) end
    STATE.rangeSecret = true
    FG.PaintRange(other, "party1")
    STATE.rangeSecret = false
    C_CurveUtil.EvaluateColorValueFromBoolean = realCurve
    ok(handed and math.abs(handed - 0.30) < 0.001,
       "and in a fight the client is handed the same number to choose between", tostring(handed))
    STATE.range.party1 = nil

    -- IN THE MACRO, because this client hands back no saved variables: written only when not the
    -- default, read back through the newline the client adds
    local FK = NS.FK
    local body = FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)" }, { ring = "target", dim = 0.35 })
    ok(body:find("E=1", 1, true) and body:find("D=35", 1, true), "both ride in the macro", body)
    local _, back = FK.Decode(body .. "\n")
    ok(back.ring == "target" and math.abs((back.dim or 0) - 0.35) < 0.001, "and come back out of it",
       tostring(back.ring) .. " / " .. tostring(back.dim))
    -- the default is 30% since 7 Oct (Arn: "for fresh installs we set the default dim to 30% grey
    -- them out almost") - so 30 writes nothing, and a player's 45 (the old default) is a choice now
    local plain = FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)" }, { ring = "me", dim = 0.30 })
    ok(not plain:find("E=", 1, true) and not plain:find("D=", 1, true), "the defaults write nothing", plain)
    local old = FK.Encode({ ["wheelup"] = "Healing Wave(Rank 2)" }, { ring = "me", dim = 0.45 })
    ok(old:find("D=45", 1, true), "a player who has 45% (the old default) keeps it: it is written now", old)

    -- THE COLD START: a login with no clicks has the ring where it was left, and the dim
    local FM = NS.FM
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = { ["wheelup"] = "Healing Wave(Rank 2)" }, true, false, nil
    NS.DO.ring("target")
    NS.DO.dim(35)
    d.binds, d.bindsSeeded, FM.asked = {}, nil, false                       -- the restart
    d.ring, d.dim = nil, nil
    FM.Get("", "wheelup")
    ok(d.ring == "target" and math.abs((d.dim or 0) - 0.35) < 0.001,
       "after a restart the ring and the dim are what the macro said",
       tostring(d.ring) .. " / " .. tostring(d.dim))
    FG.PaintEdge(other, "party1")
    ok(gold(other), "and live: the target is ringed with nothing clicked")
    MACROS = {}
    d.binds, d.bindsSeeded, FM.asked, FM.touched = {}, nil, false, nil
    FM.Get("", "left")

    -- TWO COLUMNS: the window is two of the old width, and the look / cells half sits on the right
    if not (BiSTheme and BiSTheme.Options) then
        assert(loadfile("Libs/BiSTheme/Options.lua"))()
    end
    NS.CFG.built, NS.CFG.frame = nil, nil
    local win = NS.CFG.Build()
    local W = BiSTheme.OPTIONS.W
    ok(win and win.__w == 2 * W, "the options window is two columns wide", win and win.__w)
    -- 25% bigger (Arn, 7 Oct: "too small ... too hard to read"): the whole window scales, so the
    -- layout - and the fit check, which measures in the window's own units - is unchanged
    ok(win and win:GetScale() == 1.25, "the options window is drawn 25% larger", win and win:GetScale())
    local left, right = 0, 0
    for _, r in ipairs(win and win.rows or {}) do
        local p = r.points and r.points[#r.points]
        if p and p[4] == 0 then left = left + 1 elseif p and p[4] == W then right = right + 1 end
        ok(r.__w == W, "every row is one column wide, not the whole window")
    end
    ok(left >= 8 and right >= 8, ("the rows are shared out: %d left, %d right"):format(left, right))
    ok(left + right == #(win and win.rows or {}), "and every row is in one column or the other")
    ok(NS.UI.Rows()[1].key == "mouse", "the binds are still the first thing in it")
    local keys = {}
    for _, o in ipairs(NS.UI.Rows()) do keys[o.key] = o end
    ok(keys.ring and keys.dim, "both new settings have a row")
    keys.ring.set(nil, "target")
    ok(d.ring == "target", "pressing 'target' on the row moves the ring")
    keys.dim.set(nil, 0.6)
    ok(math.abs(d.dim - 0.6) < 0.001 and keys.dim.show(d) == "60%", "the dim row sets it and says it")

    -- THE TANK MARK PREVIEW (Arn, 14 Oct: "bis healing needs a preview like bis tools"): hover a tank
    -- mark row and a 1.43:1 panel rolls out beside the window - you, a plate, the mark on you
    local pv = NS.FN.preview
    ok(pv and not pv:IsShown(), "the preview is built with the window, hidden")
    local tankRow, otherRow
    for _, r in ipairs(win.rows or {}) do
        if r.opt and r.opt.key == "tanksize" then tankRow = r end
        if r.opt and r.opt.key == "dim" then otherRow = r end
    end
    ok(tankRow and tankRow.__scripts and tankRow.__scripts.OnEnter, "the tank mark row has a hover")
    tankRow.__scripts.OnEnter(tankRow)
    ok(pv:IsShown() and pv.mark and pv.mark:IsShown(), "hovering 'tank mark size': the panel, and the mark on you")
    ok(math.abs(pv.__w / pv.__h - 1.43) < 0.01, "1.43:1, the BiSTheme shape", pv.__w .. "x" .. pv.__h)
    local w0 = pv.mark.__w
    d.tankSize = 200
    NS.FN.RedrawTank()
    ok(pv.mark.__w == NS.FN.TANK_W * 2 and pv.mark.__w > w0, "a step redraws it at once: 200%")
    d.tankLook = 5
    NS.FN.RedrawTank()
    ok(pv.mark.look == 5, "and the look follows")
    d.tankSize, d.tankLook = nil, nil
    otherRow.__scripts.OnEnter(otherRow)
    ok(not pv:IsShown(), "hovering any other setting: it rolls back in")

    _G.UnitIsUnit = realIsUnit
    d.ring, d.dim = was.ring, was.dim
end

-- THE BOOK IS READ WHEN IT CHANGES, NOT TEN TIMES A SECOND FOR EVERY CELL (8 Oct 2026).
--
-- Arn, with his addon list open: "Current CPU 6%" with BiS Healing off, "63%" with it on, and 6%
-- again with it loaded and the cells hidden. So the cost was the paint - and the paint asks
-- FM.RangeSpell for every cell, which since 7 Oct asks FM.Ranks about every spell on the mouse,
-- which walked all 500 book slots each time. BiS> now did the same once a tick on its own
-- (FN.Watch -> FB.Knows), and had since 3 Oct.
--
-- This is HIS mouse, read off his saved variables that evening, in a 25-man. One second of a
-- quiet raid - nothing learned, nothing bound, nobody moving - is ten ticks.
do
    local d = NS.DB()
    local was = { binds = d.binds, now = d.now, shown = d.shown }
    -- SHOWN, AND CHECKED TO BE. Whatever ran before this left the grid hidden, and a hidden grid
    -- paints nothing: the first draft of this test passed with zero questions asked and no fix
    -- written. A cost test with nothing on screen is a test of an empty room.
    d.shown = true
    d.binds = { wheelup = "Healing Wave(Rank 3)", ["shift-wheelup"] = "Healing Wave(Rank 5)",
                wheeldown = "Lesser Healing Wave(Rank 1)", ["shift-wheeldown"] = "Lesser Healing Wave(Rank 1)",
                button4 = "Cure Poison", button5 = "Cure Disease",
                ["alt-left"] = "!ping:attack", ["alt-right"] = "!ping:warning" }
    d.now = true
    for i = 1, 25 do STATE.units["raid" .. i] = true end
    local realRaid, realHP = _G.IsInRaid, _G.UnitHealthPercent
    _G.IsInRaid = function() return true end
    -- handed a curve, the client answers with a COLOUR; the help button paints from it every tick
    _G.UnitHealthPercent = function()
        return { GetRGB = function() return 1, 1, 1 end, GetRGBA = function() return 1, 1, 1, 1 end }
    end
    FG.Layout(FG.anchor)
    local tick = function() TICK(0.1) FG.anchor.__scripts.OnUpdate(FG.anchor, 10) end
    tick()                                              -- settle: any pending layout is done
    local painted = 0
    for _, f in ipairs(FG.frames) do if f.unit and f:IsShown() then painted = painted + 1 end end
    ok(painted == 25, "the raid is on screen, so the ticks below have cells to paint", painted)

    STATE.bookAsks, STATE.spellAsks = 0, 0
    for _ = 1, 10 do tick() end
    local quiet = STATE.bookAsks
    -- it was 630,000: 25 cells x 5 spells x 500 slots, and one more walk for BiS> now, ten times
    ok(quiet <= 500, "a quiet second in a 25-man reads the spellbook at most once, not once per"
       .. " cell per spell per tick: " .. quiet .. " questions in ten ticks")
    -- AND THE RANGE SPELL IS CHOSEN ONCE A TICK, NOT ONCE A CELL. Five spells to ask about (four
    -- on the mouse and Chain Heal, the class's own), each asked its reach once: 5 a tick, 50 in
    -- ten. Per cell it was 1,250.
    ok(STATE.spellAsks <= 100, "and which spell measures the range is worked out once a tick,"
       .. " not once for every cell: " .. STATE.spellAsks .. " questions in ten ticks")
    ok(FG.tickRange == nil, "the tick's answer is taken away when the tick is over, so a paint"
       .. " outside the loop asks for itself")

    -- THE SAME ANSWERS AS BEFORE, which is the half a cost test forgets. Kept or not, the book
    -- says what it said: three ranks of Healing Wave, in order, with real spell ids.
    local hw = NS.FM.Ranks("Healing Wave")
    ok(#hw == 3 and hw[1].rank == "Rank 1" and hw[3].rank == "Rank 3" and hw[1].spell == 1001
       and hw[1].index == 1, "the kept book still answers every rank, slot and id")
    ok(#NS.FM.Ranks("Tremor Totem") == 0, "and a spell that is not in it is still not in it")
    -- A FRESH LIST EVERY TIME. A caller that emptied its copy must not have emptied the memory.
    for i = #hw, 1, -1 do hw[i] = nil end
    ok(#NS.FM.Ranks("Healing Wave") == 3, "a caller that empties its list has not emptied the book")
    local ids = NS.FM.BookIds("Healing Wave")
    ok(#ids == 3 and ids[1] == 1001 and ids[3] == 1003, "every id under a name, one per rank")

    -- A BOOK THAT CHANGED AND DID NOT SAY SO IS NOT RE-READ... The client does say so; this is
    -- what proves the addon is LISTENING rather than walking the book anyway and calling it kept.
    rawset(PAGES, 40, { name = "Tremor Totem", rank = "" })
    ok(#NS.FM.Ranks("Tremor Totem") == 0, "a silent change is not seen: the book really is kept")
    -- ...UNTIL THE CLIENT SAYS SO, through a frame that asked to be told
    ok(NS.FM.bookEvents and NS.FM.bookEvents.__events and NS.FM.bookEvents.__events.SPELLS_CHANGED,
       "the book's listener registered for SPELLS_CHANGED")
    ok(fire(NS.FM.bookEvents, "SPELLS_CHANGED") and #NS.FM.Ranks("Tremor Totem") == 1,
       "and SPELLS_CHANGED has it read again: a spell learned mid-session is known at once")
    ok(NS.FM.bookEvents.__events.PLAYER_ENTERING_WORLD, "it asked for PLAYER_ENTERING_WORLD too")

    -- OR UNTIL IT IS OLD. If there is a way to learn a spell that fires neither event, the book
    -- is wrong for FM.BOOK_TTL seconds and not for the rest of the session.
    rawset(PAGES, 40, nil)
    ok(#NS.FM.Ranks("Tremor Totem") == 1, "silently forgotten, it is still believed for a moment")
    TICK(NS.FM.BOOK_TTL + 0.1)
    ok(#NS.FM.Ranks("Tremor Totem") == 0, "and not once the kept book has aged out")
    -- A QUIET MINUTE READS IT AT MOST ONCE (8 Oct: Arn's /bish range said 70 reads since login on
    -- a 5 s net). Ten minutes of asking every second, nothing learned: ten reads at most.
    local reads0 = NS.FM.bookReads
    for _ = 1, 600 do TICK(1) NS.FM.Ranks("Healing Wave") end
    ok(NS.FM.BOOK_TTL >= 60 and NS.FM.bookReads - reads0 <= 10,
       "ten quiet minutes read the spellbook at most ten times: " .. (NS.FM.bookReads - reads0))

    -- WHOEVER THE CLIENT TELLS FIRST. The self-buff watch checks the book inside its own handler
    -- for the same event; told before the book's listener, it would check a book that is about to
    -- be thrown away. So it throws it away itself.
    rawset(PAGES, 41, { name = "Tremor Totem", rank = "" })
    ok(not NS.FS.Knows("Tremor Totem"), "(not known yet: the change was silent)")
    ok(fire(NS.FS.frame, "SPELLS_CHANGED") and NS.FS.Knows("Tremor Totem"),
       "the self-buff watch, told first and alone, still reads the new book")
    rawset(PAGES, 41, nil)
    bookSaid()

    -- AN EMPTY BOOK IS NEVER KEPT. At login the client has not filled it in; remembering that
    -- answer would be a mouse with no defaults until the event - or for good, if it never came.
    -- EVERY page, not the first five: an earlier block leaves a spell in slot 20, and a book
    -- with one spell in it is not an empty book - it is kept, and this would test nothing.
    local stash = {}
    for slot, page in pairs(PAGES) do stash[slot] = page end
    for slot in pairs(stash) do rawset(PAGES, slot, nil) end
    bookSaid()                                          -- a fresh login: nothing kept, book empty
    ok(#NS.FM.Ranks("Healing Wave") == 0, "an empty book answers nothing")
    for slot, page in pairs(stash) do rawset(PAGES, slot, page) end   -- it fills in, and nobody says
    ok(#NS.FM.Ranks("Healing Wave") == 3, "and is asked again the very next time, event or no event")

    -- BUT A KEPT BOOK IS NOT THROWN AWAY FOR AN EMPTY ONE NOBODY ANNOUNCED. The kept book ages,
    -- the re-read comes back with nothing, and no event said a thing: that is a client that has
    -- gone quiet, not a shaman who forgot every spell at once. What was known stays known - and
    -- it is not asked again on every call, which would be the old cost back mid-fight.
    for slot in pairs(stash) do rawset(PAGES, slot, nil) end
    TICK(NS.FM.BOOK_TTL + 0.1)
    ok(#NS.FM.Ranks("Healing Wave") == 3, "a book that only aged, re-read as empty, keeps what it knew")
    STATE.bookAsks = 0
    for _ = 1, 20 do NS.FM.Ranks("Healing Wave") end
    ok(STATE.bookAsks == 0, "and a quiet client is not asked again on every call: " .. STATE.bookAsks)
    ok(bookSaid() and #NS.FM.Ranks("Healing Wave") == 0,
       "the client SAYING the book changed is different: then empty is believed")
    for slot, page in pairs(stash) do rawset(PAGES, slot, page) end
    bookSaid()

    _G.IsInRaid, _G.UnitHealthPercent = realRaid, realHP
    for i = 1, 25 do STATE.units["raid" .. i] = nil end
    d.binds, d.now, d.shown = was.binds, was.now, was.shown
    FG.Layout(FG.anchor)
end

-- WHAT A QUIET SECOND COSTS, IN CLIENT CALLS (7 Oct 2026). Arn: "make sure stuff like this does
-- not happen, this goes live and we have a lot of angry users". The block above counts the book;
-- this one counts EVERYTHING the client is asked, with the family's own counter
-- (_bisdev/dev/cost.lua), so a hog anywhere in the paint shows up here before it ships.
-- check.sh holds every Forever addon with a timer to having one of these.
do
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local d = NS.DB()
    local was = { binds = d.binds, now = d.now, shown = d.shown }
    d.shown, d.now = true, true
    d.binds = { wheelup = "Healing Wave(Rank 3)", wheeldown = "Lesser Healing Wave(Rank 1)",
                button4 = "Cure Poison", ["alt-left"] = "!ping:attack" }
    for i = 1, 25 do STATE.units["raid" .. i] = true end
    local realRaid, realHP = _G.IsInRaid, _G.UnitHealthPercent
    _G.IsInRaid = function() return true end
    _G.UnitHealthPercent = function()
        return { GetRGB = function() return 1, 1, 1 end, GetRGBA = function() return 1, 1, 1, 1 end }
    end
    FG.Layout(FG.anchor)
    -- REAL time: ten steps of 0.1 s (a 10 s step would trigger the 1 s safety sweep on every tick)
    local tick = function() TICK(0.1) FG.anchor.__scripts.OnUpdate(FG.anchor, 0.1) end
    tick() tick()

    local n, by = Cost.Count(function() for _ = 1, 10 do tick() end end)
    STATE.costQuiet = n
    -- THE BUDGETS, set a little above what was measured on 7 Oct after the cost pass (8,300 and
    -- 600; it was 9,530 and 1,800 before it, and ~630,000 with the book walk). Raising one is
    -- allowed - with a line here saying what bought it. The book walk would read 600,000+.
    -- 8 Oct: 9000 -> 8500, after a crosshair crept 500 in unnoticed. 10 Oct: -> 1600 - the grid
    -- paints what the client says CHANGED (events), range on its own 0.25 s beat, a 1 s sweep; a
    -- quiet second measured 1,450 (Arn: "like Apple super optimized, not power hungry android").
    -- 9 Nov: -> 1250 - range waits for the game's UNIT_IN_RANGE_UPDATE instead of a 0.25 s beat over every cell
    -- (Arn: "we wait for the game to tell us there is a change, we want to make this lean and fast"); measured 1,100.
    local QUIET, AURAS = 1250, 650
    ok(n <= QUIET, "a quiet second in a 25-man asks the client at most " .. QUIET .. " things: " .. n,
       Cost.Top(by, 6))
    ok((by.IsSpellInRange or 0) <= 30, "range in a quiet second: only the 1 s sweep asks it, about once a cell - no beat",
       by.IsSpellInRange or 0)

    -- THE RANGE SIGNAL (9 Nov 2026): the game says who crossed the line; only they are asked
    do
        ok(FG.rangeByEvent and FG.unitEvents.__events.UNIT_IN_RANGE_UPDATE, "the grid listens for the game's range signal")
        local asked, whole = {}, {}
        local realPR, realP = FG.PaintRange, FG.Paint
        FG.PaintRange = function(f, ...) asked[#asked + 1] = f return realPR(f, ...) end
        FG.Paint = function(f, ...) whole[f] = true return realP(f, ...) end   -- a whole repaint asks range too
        local cell = FG.byUnit.raid7
        tick()
        for i = #asked, 1, -1 do asked[i] = nil end
        FG.sweepAt = 0
        local keepSweep = FG.SWEEP
        FG.SWEEP = 1e9                                   -- no sweep slice this tick: only the signal may ask
        fire(FG.unitEvents, "UNIT_IN_RANGE_UPDATE", "raid7")
        tick()
        local only7, got7 = true, false
        for _, f in ipairs(asked) do
            if f == cell then got7 = true
            elseif not whole[f] and f ~= FG.me and f ~= FG.target and f ~= FG.tot then only7 = false end
        end
        ok(got7 and only7, "raid7 crossed the line: raid7's range is asked, nobody else's (beyond the sweep's one cell)", #asked)
        for k in pairs(whole) do whole[k] = nil end
        for i = #asked, 1, -1 do asked[i] = nil end
        tick()
        local again = false
        for _, f in ipairs(asked) do if f == cell and not whole[f] then again = true end end
        ok(not again, "and once asked, not again until the game says so")
        fire(FG.unitEvents, "UNIT_IN_RANGE_UPDATE", secret())
        tick()
        local n7 = 0
        for _, f in ipairs(asked) do if FG.byUnit and f ~= FG.me then n7 = n7 + 1 end end
        ok(n7 >= 25, "a unit the client hides: everyone's range asked, never a guess", n7)
        FG.SWEEP = keepSweep
        FG.PaintRange, FG.Paint = realPR, realP
        -- A CLIENT WITHOUT THE EVENT: the registration is refused, the 0.25 s beat goes on asking
        STATE.unknownEvents = { UNIT_IN_RANGE_UPDATE = true }
        local probe = CreateFrame("Frame")
        ok(FG.ArmRange(probe) == false and not FG.rangeByEvent, "no range signal on this client: the old beat asks instead")
        local nb, byb = Cost.Count(function() for _ = 1, 10 do tick() end end)
        ok((byb.IsSpellInRange or 0) >= 4 * 20, "the beat: every cell's range, four times a second", byb.IsSpellInRange or 0)
        STATE.unknownEvents = nil
        FG.ArmRange(FG.unitEvents)
    end

    -- WHAT MARKS A CELL, and that ONLY it is repainted (10 Oct 2026)
    local painted = {}
    local realPaint = FG.Paint
    FG.Paint = function(f, ...) painted[#painted + 1] = f return realPaint(f, ...) end
    local function count() local c = #painted for i = #painted, 1, -1 do painted[i] = nil end return c end
    tick() count()                                        -- whatever was pending, gone
    local cellR1 = FG.byUnit and FG.byUnit.raid1
    ok(FG.unitEvents and FG.unitEvents.__events and FG.unitEvents.__events.UNIT_HEALTH
       and FG.unitEvents.__events.UNIT_HEAL_PREDICTION and FG.unitEvents.__events.PLAYER_TARGET_CHANGED,
       "the grid listens for health, heals on the way, and target changes")
    -- a tick with nothing said repaints only its SLICE of the rolling sweep (a tenth of the cells,
    -- spares included) plus target/tot - never the raid
    local slice = math.ceil(#FG.frames * 0.1 / FG.SWEEP)
    tick()
    local quietPaints = count()
    ok(quietPaints <= slice + 2, "a quiet tick repaints only its slice of the rolling sweep", quietPaints)
    fire(FG.unitEvents, "UNIT_HEALTH", "raid1")
    tick()
    local after = {}
    for _, f in ipairs(painted) do after[f] = true end
    ok(cellR1 and after[cellR1] and count() <= slice + 3,
       "raid1's health changed: raid1's cell is repainted, not the raid")
    -- ENTERING A FIGHT IS SPREAD, NOT DUMPED (Arn: "do the rolling sweep"): no single tick repaints
    -- everyone, and within FG.SPREAD_TICKS ticks everyone has been repainted
    fire(FG.unitEvents, "PLAYER_REGEN_DISABLED")
    local peak, spread = 0, {}
    for _ = 1, FG.SPREAD_TICKS do
        tick()
        local c = #painted
        for _, f in ipairs(painted) do spread[f] = true end
        count()
        if c > peak then peak = c end
    end
    local covered = 0
    for i = 1, 25 do if FG.byUnit["raid" .. i] and spread[FG.byUnit["raid" .. i]] then covered = covered + 1 end end
    ok(peak < 25 and covered == 25, "the combat flip repaints all 25 over " .. FG.SPREAD_TICKS
       .. " ticks, never in one frame (peak " .. peak .. ")")
    fire(FG.unitEvents, "PLAYER_TARGET_CHANGED")
    tick()
    ok(count() >= 25, "a new target repaints everyone (the crosshair moves)")
    fire(FG.unitEvents, "UNIT_HEALTH", secret())
    tick()
    ok(count() >= 25, "a unit the client hides cannot be looked up, so everyone is repainted, never a guess")
    -- the sweep: within a second everything is repainted anyway, event or no event
    local swept = 0
    for _ = 1, 10 do tick() swept = swept + count() end
    ok(swept >= 25, "and the 1 s sweep repaints every cell even if no event came", swept)
    FG.Paint = realPaint

    -- A RAID'S AURAS. UNIT_AURA fires for every buff, debuff and tick on every member - hundreds a
    -- second in a fight. Only YOURS mean anything to the regen pair and the self-buff watch.
    local a, aby = Cost.Count(function()
        for i = 1, 300 do
            local u = "raid" .. ((i % 25) + 1)
            if NS.FR and NS.FR.frame then fire(NS.FR.frame, "UNIT_AURA", u) end
            if NS.FS and NS.FS.frame then fire(NS.FS.frame, "UNIT_AURA", u) end
        end
    end)
    STATE.costAuras = a
    ok(a <= AURAS, "300 aura changes on OTHER people ask the client at most " .. AURAS .. " things: "
       .. a, Cost.Top(aby, 6))
    print(("   cost: quiet 25-man second = %d calls (%s)"):format(n, Cost.Top(by, 4)))
    print(("   cost: 300 raid auras      = %d calls (%s)"):format(a, Cost.Top(aby, 4)))

    _G.IsInRaid, _G.UnitHealthPercent = realRaid, realHP
    for i = 1, 25 do STATE.units["raid" .. i] = nil end
    d.binds, d.now, d.shown = was.binds, was.now, was.shown
    FG.Layout(FG.anchor)
end

-- BiSHealingAPI AFTER LOGIN (16 Oct 2026, playbook 5a). Every function, ready and not; every answer
-- a copy (edit it, ask again, unchanged - and the addon's own table unchanged too); every action a
-- click the player could make; every event fired by the real road, not by calling Announce.
do
    local A = _G.BiSHealingAPI
    local FM, FN = NS.FM, NS.FN
    local d = NS.DB()
    local was = { binds = d.binds, trinketTabs = d.trinketTabs, tank = d.tank, shown = d.shown,
                  clique = d.clique, now = d.now }
    ok(FG.anchor ~= nil and A.Ready() == true, "after login the API is ready")

    d.shown = false
    ok(A.Shown() == false, "Shown() reads the hide switch")
    d.shown = true
    ok(A.Shown() == true, "and the show switch")
    d.clique = true
    ok(A.CliqueOn() == true, "CliqueOn() says when Clique owns the clicks")
    d.clique = false
    ok(A.CliqueOn() == false, "and when it does not")

    local slots = A.Slots()
    ok(type(slots) == "table" and #slots == #FM.SLOTS and slots[1].key == "left"
       and slots[1].wheel == false and slots[3].key == "wheelup" and slots[3].wheel == true,
       "Slots() lists every mouse slot, the wheel marked as such")
    slots[1].key, slots[2] = "edited", nil
    local again = A.Slots()
    ok(again[1].key == "left" and again[2] and FM.SLOTS[1].key == "left",
       "Slots() answers a copy: editing it changes neither the next answer nor the addon")

    d.binds = { left = "Healing Wave(Rank 3)",
                ["shift-left"] = "!use:13+Nature's Swiftness+Healing Wave(Rank 10)",
                ["ctrl-right"] = FM.PingBind("assist"),
                ["alt-wheelup"] = "Chain Heal" }
    d.trinketTabs = { ["alt-"] = { [14] = true } }
    local b = A.Binds()
    ok(b and b.left and b.left.spell == "Healing Wave" and b.left.rank == "Rank 3" and b.left.mod == ""
       and b.left.slot == "left" and b.left.cast == "Healing Wave(Rank 3)" and #b.left.trinkets == 0,
       "Binds(): a plain bind, its spell and rank apart")
    local s = b and b["shift-left"]
    ok(s and s.mod == "shift-" and s.slot == "left" and s.spell == "Healing Wave" and s.rank == "Rank 10"
       and s.boost == "Nature's Swiftness" and s.trinkets[1] == 13 and #s.trinkets == 1,
       "a bind with a trinket and a booster in front says both")
    local p = b and b["ctrl-right"]
    ok(p and p.ping == "assist" and p.spell == nil and p.mod == "ctrl-" and p.slot == "right",
       "a ping bind says which ping, and no spell")
    local w = b and b["alt-wheelup"]
    ok(w and w.spell == "Chain Heal" and w.rank == nil and w.trinkets[1] == 14,
       "a bare name has no rank, and its modifier tab's trinket is counted")
    b.left.spell, b.left.trinkets[1], b["shift-left"].trinkets[1], b.extra = "edited", 99, 99, {}
    local b2 = A.Binds()
    ok(b2.left.spell == "Healing Wave" and #b2.left.trinkets == 0 and b2["shift-left"].trinkets[1] == 13
       and b2.extra == nil and d.binds.left == "Healing Wave(Rank 3)" and d.binds.extra == nil,
       "Binds() answers a copy: editing it changes neither the next answer nor the saved binds")

    local one = A.Bind("left", "shift")
    ok(one and one.key == "shift-left" and one.boost == "Nature's Swiftness", "Bind(slot, \"shift\")")
    ok(A.Bind("left", "shift-").key == "shift-left" and A.Bind("left").key == "left"
       and A.Bind("left", "").key == "left", "Bind() takes \"shift-\", \"\" or nothing for the modifier")
    one.cast = "edited"
    ok(A.Bind("left", "shift").cast ~= "edited", "Bind() answers a copy")
    local n1, w1 = A.Bind("nose")
    ok(n1 == nil and w1 == "no such slot", "a slot that is not on the mouse: no such slot")
    local n2, w2 = A.Bind("left", "hyper")
    ok(n2 == nil and w2 == "no such modifier", "a modifier that is not one: no such modifier")
    local n3, w3 = A.Bind("middle")
    ok(n3 == nil and w3 == "nothing bound", "an empty slot: nothing bound")
    local n4, w4 = A.Bind(7)
    ok(n4 == nil and w4 == "no such slot", "junk is refused, not thrown on")
    d.binds = {}
    ok(next(A.Binds()) == nil, "nothing bound: Binds() is an empty table, not nil")

    d.tank = nil
    local t0, tw = A.Tank()
    ok(t0 == nil and tw == "no tank", "Tank(): nobody chosen says no tank")
    d.tank = "Tobi Three"
    ok(A.Tank() == "Tobi Three", "and the chosen tank by the name the client wrote")

    local nw = A.Now()
    ok(type(nw) == "table" and type(nw.on) == "boolean" and type(nw.shown) == "boolean"
       and type(nw.buttons) == "table" and nw.tank == "Tobi Three", "Now(): the switch, the block, its buttons, the tank")
    d.now = true
    FG.Layout(FG.anchor)
    local on = A.Now()
    ok(on.on == true and on.shown == true and on.buttons[1] == "help",
       "with BiS> now on, the block is shown and the help button is first")
    on.buttons[1], on.tank = "edited", "edited"
    local on2 = A.Now()
    ok(on2.buttons[1] == "help" and on2.tank == "Tobi Three" and d.tank == "Tobi Three",
       "Now() answers a copy")
    d.now = false
    FG.Layout(FG.anchor)
    ok(A.Now().on == false and A.Now().shown == false and #A.Now().buttons == 0, "and off is off")

    -- the two windows: OPENED, never toggled shut by a second ask
    local win = FM.Window()
    win:Hide()
    ok(A.OpenBinds() == true and win:IsShown(), "OpenBinds() opens the bind window")
    ok(A.OpenBinds() == true and win:IsShown(), "and asked again it stays open")
    win:Hide()
    local opt = NS.CFG.Build()
    if opt then opt:Hide() end
    ok(A.OpenOptions() == true and opt and opt:IsShown(), "OpenOptions() opens the options window")
    ok(A.OpenOptions() == true and opt:IsShown(), "and asked again it stays open")
    if opt then opt:Hide() end

    -- events, by the roads the player takes
    local heard = {}
    ok(A.RegisterCallback("suite", "BiSHealing_BindsChanged", function(e) heard[#heard + 1] = e end) == true,
       "RegisterCallback takes an owner, an event and a function")
    ok(A.RegisterCallback("broken", "BiSHealing_BindsChanged", function() error("a listener's own bug") end),
       "a second owner on the same event")
    local r1, rw1 = A.RegisterCallback(nil, "BiSHealing_BindsChanged", print)
    local r2, rw2 = A.RegisterCallback("suite", "BiSHealing_Nonsense", print)
    local r3, rw3 = A.RegisterCallback("suite", "BiSHealing_Shown", "not a function")
    ok(r1 == nil and rw1 == "bad owner" and r2 == nil and rw2 == "no such event"
       and r3 == nil and rw3 == "not a function", "and refuses a bad owner, event or function with why")
    local set = pcall(FM.Set, "", "middle", "Heal(Rank 2)")
    ok(set and heard[1] == "BiSHealing_BindsChanged",
       "dropping a spell on the mouse announces BiSHealing_BindsChanged - past a listener that throws")
    FM.Clear("", "middle")
    ok(#heard == 2, "and so does clearing one")
    FM.SetTabTrinket("", 13, true)
    FM.SetTabTrinket("", 13, false)
    ok(#heard == 4, "and ticking a trinket tab")
    ok(A.UnregisterCallback("suite", "BiSHealing_BindsChanged") == true, "UnregisterCallback lets go")
    FM.Set("", "middle", "Heal(Rank 2)")
    FM.Clear("", "middle")
    ok(#heard == 4, "and a let-go listener hears nothing more")
    local u1, uw1 = A.UnregisterCallback("suite", "BiSHealing_BindsChanged")
    ok(u1 == nil and uw1 == "not registered", "letting go twice says not registered")
    A.UnregisterCallback("broken", "BiSHealing_BindsChanged")

    local shownHeard = {}
    A.RegisterCallback("suite", "BiSHealing_Shown", function(e, v) shownHeard[#shownHeard + 1] = v end)
    NS.DO.show(false)
    NS.DO.show(true)
    ok(shownHeard[1] == false and shownHeard[2] == true, "/bish hide and show announce BiSHealing_Shown")
    A.UnregisterCallback("suite", "BiSHealing_Shown")

    local tankHeard = { n = 0 }
    A.RegisterCallback("suite", "BiSHealing_TankChanged", function(e, v) tankHeard.n = tankHeard.n + 1 tankHeard.v = v end)
    d.tank = "Tobi Three"
    FN.SetTank()                 -- nobody targeted: lets go
    ok(tankHeard.n == 1 and tankHeard.v == nil and A.Tank() == nil,
       "letting go of the tank announces BiSHealing_TankChanged with no name")
    A.UnregisterCallback("suite", "BiSHealing_TankChanged")

    -- THE ANSWERS NEVER THROW, even when the addon's insides do
    local realSplit = FM.Split
    FM.Split = function() error("an inside that changed") end
    d.binds = { left = "Healing Wave(Rank 3)" }
    local okB, bb = pcall(A.Binds)
    ok(okB and bb and bb.left and bb.left.cast == "Healing Wave(Rank 3)",
       "a throwing inside is pcalled: the answer is poorer, never an error")
    FM.Split = realSplit

    for k, v in pairs(was) do d[k] = v end
    FG.Layout(FG.anchor)
end

print("BiS> now: the next res (17 Oct 2026)")
do
    -- Arn: "if out of combat bis now gets a res button already targeting the best next target to res
    -- other healers first mana users next warriors rogues hunters last"
    local FN, FM, FZ = NS.FN, NS.FM, NS.FZ
    local d = NS.DB()
    local keep = { units = STATE.units, dead = STATE.dead, roles = STATE.roles, classes = STATE.classes,
                   name = _G.UnitName, b28 = BOOK[28], now = d.now, shown = d.shown }
    STATE.units = { player = true, party1 = true, party2 = true, party3 = true, party4 = true }
    STATE.classes = { party1 = "WARRIOR", party2 = "MAGE", party3 = "PRIEST", party4 = "HUNTER" }
    STATE.dead, STATE.ghost, STATE.resComing, STATE.roles = {}, {}, {}, {}
    _G.UnitName = function(u) return "P" .. tostring(u) end          -- a different name each, for the claims
    ok(FN.ResTarget() == nil, "no res in the spellbook: no button")
    BOOK[28] = { name = "Ancestral Spirit", rank = "" }
    bookSaid()
    ok(FN.ResTarget() == nil, "nobody dead: no button")
    STATE.dead.party1, STATE.dead.party2, STATE.dead.party4 = true, true, true
    local u = FN.ResTarget()
    ok(u == "party2", "warrior, mage, hunter down: the mage first", u)
    STATE.dead.party3 = true
    STATE.roles = { party3 = "HEALER" }
    u = FN.ResTarget()
    ok(u == "party3", "a healer down: the healer before anyone", u)
    FZ.claims["Pparty3"] = { by = "Arn", at = GetTime() }
    u = FN.ResTarget()
    ok(u == "party2", "another BiS healer is on the healer: skipped, the mage next", u)
    STATE.resComing.party2 = true
    u = FN.ResTarget()
    ok(u == "party4", "a res already coming to the mage: the hunter before the warrior (Arn's order)", u)
    STATE.ghost.party4 = true
    u = FN.ResTarget()
    ok(u == "party4", "the hunter released: still res'd, in the same order (Arn, 10 Nov: healers release too)", u)
    STATE.classes.party1 = "ROGUE"
    STATE.ghost.party4 = nil
    ok(FN.ResTarget() == "party4", "hunter before rogue")
    STATE.classes.party1 = "WARRIOR"
    STATE.inCombat = true
    ok(FN.ResTarget() == nil, "in a fight: no res button at all")
    STATE.inCombat = false

    -- on the bar, aimed, and gone when nobody is left
    FZ.claims["Pparty3"] = nil
    STATE.resComing, STATE.ghost = {}, {}
    d.now, d.shown = true, true
    FN.Layout()
    local b = FN.buttons and FN.buttons.res
    ok(b and b:IsShown(), "BiS> now shows the res button")
    ok(b and b:GetAttribute("*macrotext1") == "/cast [@party3] Ancestral Spirit", "aimed at the healer",
       b and b:GetAttribute("*macrotext1"))
    ok(b and b.word and b.word:GetText() == "Pparty3", "with their name on it")
    STATE.dead.party3 = nil                                           -- the priest is up
    FN.ResSoon()
    ok(b:GetAttribute("*macrotext1") == "/cast [@party2] Ancestral Spirit", "up: the button moves on to the mage")
    STATE.dead = {}
    FN.ResSoon()
    ok(not b:IsShown(), "everyone up: the button goes")

    -- LEAN: a 40-person raid looked at once costs a few calls a person, and only out of combat
    local Cost = dofile("../_bisdev/dev/cost.lua")
    for i = 1, 40 do STATE.units["raid" .. i] = true STATE.dead["raid" .. i] = (i % 3 == 0) end
    local n, by = Cost.Count(function() FN.ResTarget() end)
    print(("   cost: next res over a 40-raid roster = %d calls (%s)"):format(n, Cost.Top(by, 3)))
    ok(n <= 40 * 10, "the res scan stays a few calls a person: " .. n, Cost.Top(by, 4))

    STATE.units, STATE.dead, STATE.roles, STATE.classes = keep.units, keep.dead, keep.roles, keep.classes
    STATE.ghost, STATE.resComing = nil, nil
    _G.UnitName, BOOK[28], d.now, d.shown = keep.name, keep.b28, keep.now, keep.shown
    bookSaid()
    FN.Layout()
end

print("BiS> now: the buff buttons (4 Nov 2026)")
do
    -- Arn: "a button in bis now that chooses the best target to buff" ... "make it smart for classes each get
    -- their buff buttons". The client as probe round 1 measured it (dev/BUFFS.md section 7): out of combat a buff
    -- answers with a plain expirationTime, duration and sourceUnit; in a fight it is secret. Range is a plain
    -- BOOLEAN from C_Spell.IsSpellInRange (false for party1 far away), never 1/0.
    local FN, FU, FK = NS.FN, NS.FU, NS.FK
    local d = NS.DB()
    local keep = { units = STATE.units, roles = STATE.roles, dead = STATE.dead, afk = STATE.afk,
                   offline = STATE.offline, auras = _G.C_UnitAuras, range = _G.C_Spell.IsSpellInRange,
                   level = _G.UnitLevel, power = _G.UnitPowerType, raid = _G.IsInRaid,
                   now = d.now, shown = d.shown, buffs = d.buffs, fam = d.buffFam, tank = d.tank, me = d.me }
    local SLOTS = { 40, 41, 42, 43, 44 }
    local keptPages = {}
    for _, s in ipairs(SLOTS) do keptPages[s] = BOOK[s] end
    STATE.units = { player = true, party1 = true, party2 = true, party3 = true }
    STATE.roles, STATE.dead, STATE.afk, STATE.offline = { party2 = "TANK" }, {}, {}, {}
    local WEAR, HIDDEN = {}, {}              -- WEAR[unit][spellId] = expirationTime; HIDDEN[unit] = a secret answer
    _G.C_UnitAuras = setmetatable({ GetUnitAuraBySpellID = function(unit, id)
        if type(id) ~= "number" then error("bad argument #2", 2) end
        if STATE.inCombat or HIDDEN[unit] then return secret() end
        local e = WEAR[unit] and WEAR[unit][id]
        if not e then return nil end
        return { spellId = id, expirationTime = e, duration = 3600, sourceUnit = "player" }
    end }, { __index = keep.auras })
    local FAR, rangeAsked = {}, {}
    _G.C_Spell.IsSpellInRange = function(spell, unit)
        if type(spell) ~= "string" and type(spell) ~= "number" then error("bad argument #1", 2) end
        rangeAsked[#rangeAsked + 1] = unit
        if STATE.inCombat then return secret() end
        return not FAR[unit]
    end
    local LEVEL = { player = 40, party1 = 40, party2 = 40, party3 = 40 }
    _G.UnitLevel = function(u) return LEVEL[u] or 1 end
    local POWER = { player = 0, party1 = 0, party2 = 1, party3 = 3 }     -- party2 a warrior, party3 a rogue
    _G.UnitPowerType = function(u) return POWER[u] or 0 end
    d.now, d.shown, d.buffs, d.buffFam, d.tank, d.me = true, true, nil, nil, nil, nil
    FU.Forget()
    local now = GetTime()

    ok(not FU.Show("fort"), "off by default: no buff button")
    d.buffs = true
    ok(not FU.Show("fort"), "on, but Fortitude not in the book: no button - the spellbook decides, never the class")
    BOOK[40] = { name = "Power Word: Fortitude", rank = "Rank 1" }
    BOOK[41] = { name = "Power Word: Fortitude", rank = "Rank 2" }
    bookSaid()
    FU.Forget()
    ok(FU.Show("fort"), "Fortitude trained, nobody wearing it: the button comes")
    local u, rank, near, far = FU.Target("fort")
    ok(u == "party2", "the tank first", u)
    ok(rank == "Rank 2" and near == 4 and far == 0, "the highest rank fitting them, four in reach need it",
       tostring(rank) .. " " .. tostring(near))

    -- THE PROBE'S TRAP: out of reach, a [@party1] cast landed on the priest. Never aimed at.
    FAR.party2 = true
    u, rank, near, far = FU.Target("fort")
    ok(u ~= "party2" and far == 1 and near == 3, "the tank out of reach: skipped, counted as out of reach", u)
    FAR.party2 = nil

    -- wearing it, any rank, from anyone - the raid version counts too
    WEAR.party2 = { [1244] = now + 3000 }
    WEAR.player = { [21562] = now + 3000 }                              -- Prayer of Fortitude
    FU.Forget()
    ok(FU.Target("fort") == "party1", "the tank and I have it (the group one counts): party1 next")

    -- A MACRO CAST DOES NOT DOWNRANK: a level 1 gets the rank it may wear
    LEVEL.party1 = 1
    u, rank = FU.Target("fort")
    ok(u == "party1" and rank == "Rank 1", "a level 1: rank 1 (rank 2 is learned at 12)", tostring(rank))
    LEVEL.party1 = 40

    -- missing beats running low; under five minutes left is running low
    WEAR.party1 = { [1243] = now + 100 }
    FU.Forget()
    ok(FU.Target("fort") == "party3", "missing beats running low")
    WEAR.party3 = { [1243] = now + 2000 }
    FU.Forget()
    ok(FU.Target("fort") == "party1", "and then under five minutes left")
    WEAR.party1 = { [1243] = now + 2000 }
    FU.Forget()
    ok(not FU.Show("fort"), "everyone has it: the button goes")

    -- an unreadable answer is "don't know", never "missing"
    WEAR.party1, HIDDEN.party1 = nil, true
    FU.Forget()
    ok(FU.Target("fort") == nil, "a secret answer is never taken for a missing buff")
    HIDDEN.party1 = nil
    FU.Forget()
    ok(FU.Target("fort") == "party1", "readable again: party1 needs it")
    -- AFK: LAST, NOT SKIPPED (Arn, 5 Nov: "buff afk people last ... group buffs will get them either way")
    STATE.afk.party1 = true
    ok(FU.Target("fort") == "party1", "AFK and the only one left: still buffed")
    WEAR.party3 = { [1243] = now + 100 }
    FU.Forget()
    ok(FU.Target("fort") == "party3", "AFK and missing it comes after someone here who is only running low")
    local _, _, nearAfk = FU.Target("fort")
    ok(nearAfk == 2, "the AFK one still counts as needing it", tostring(nearAfk))
    STATE.afkSecret = true
    ok(FU.Target("fort") == "party1", "a hidden AFK counts as here: missing beats low again")
    STATE.afkSecret = false
    WEAR.party3 = { [1243] = now + 2000 }
    FU.Forget()
    STATE.afk.party1, STATE.dead.party1 = nil, true
    ok(FU.Target("fort") == nil, "dead: skipped")
    STATE.dead.party1, STATE.offline.party1 = nil, true
    ok(FU.Target("fort") == nil, "offline: skipped")
    STATE.offline.party1 = nil
    STATE.inCombat = true
    ok(FU.Target("fort") == nil and not FU.Show("fort"), "in a fight: nothing (auras are secret there)")
    STATE.inCombat = false

    -- THE BUTTON, aimed, re-aimed at the click, and nothing changes in a fight
    FU.Forget()
    FN.Layout()
    local b = FN.buttons and FN.buttons.fort
    ok(b and b:IsShown(), "BiS> now shows the Fortitude button")
    ok(b and b:GetAttribute("*macrotext1") == "/cast [@party1] Power Word: Fortitude(Rank 2)",
       "aimed at party1 with the rank", b and b:GetAttribute("*macrotext1"))
    ok(b and b.__hooked and b.__hooked.OnEnter, "hooked, never set: the secure template keeps its own scripts")
    WEAR.party3 = { [1243] = now + 100 }                    -- running low: second in line, after missing party1
    fire(FU.watcher, "UNIT_AURA", "party3")
    ok(b:GetAttribute("*macrotext1") == "/cast [@party1] Power Word: Fortitude(Rank 2)", "a buff event re-aims: missing still first")
    -- RANGE FIRES NO EVENT: party1 walks off. The click itself must look again (PreClick).
    local pre = b:GetScript("PreClick")
    ok(pre ~= nil, "it aims in PreClick")
    FAR.party1 = true
    STATE.inCombat = true
    pre(b, "LeftButton")
    ok(b:GetAttribute("*macrotext1") == "/cast [@party1] Power Word: Fortitude(Rank 2)", "in a fight the aim is left alone")
    STATE.inCombat = false
    pre(b, "LeftButton")
    ok(b:GetAttribute("*macrotext1") == "/cast [@party3] Power Word: Fortitude(Rank 2)",
       "out of it the click goes to whoever is in reach and needs it now", b:GetAttribute("*macrotext1"))
    FAR.party1 = nil
    WEAR.party1 = { [1243] = now + 3000 }
    WEAR.party3 = { [1243] = now + 3000 }
    fire(FU.watcher, "UNIT_AURA", "party1")
    fire(FU.watcher, "UNIT_AURA", "party3")
    ok(not b:IsShown(), "the last one buffed: the button goes")

    -- EACH CLASS ITS OWN: Intellect for mana users, Thorns for tanks, Shadow Protection off until asked
    BOOK[42] = { name = "Arcane Intellect", rank = "Rank 1" }
    BOOK[43] = { name = "Thorns", rank = "Rank 1" }
    BOOK[44] = { name = "Shadow Protection", rank = "Rank 1" }
    bookSaid()
    FU.Forget()
    u, rank, near = FU.Target("int")
    ok(near == 2, "Arcane Intellect: only the two mana users (the warrior and the rogue are left out)", near)
    u, rank, near = FU.Target("thorns")
    ok(u == "party2" and near == 1, "Thorns: the tank only", u)
    ok(not FU.Show("shadow"), "Shadow Protection is off until asked for")
    NS.DO.buffs("shadow", "on")
    ok(FU.Show("shadow"), "/bish buffs shadow on: there")
    NS.DO.buffs("int", "off")
    ok(not FU.Show("int"), "/bish buffs int off: gone")
    ok(FU.EncodeFams() == "12345", "the switches as macro digits (int off)", FU.EncodeFams())

    -- REMEMBERED IN THE MACRO (SavedVariables did not come back on this client): row I
    local body = FK.Encode({}, { buffs = true, buffFams = "13" })
    local _, settings = FK.Decode(body)
    ok(body and body:find("I=1:13", 1, true) and settings and settings.buffs == true and settings.buffFams == "13",
       "the macro carries the buff switches and gives them back", body)
    local t = FU.DecodeFams("13")
    ok(t.fort == true and t.shadow == true and t.spirit == false and t.int == false, "digits back to switches")
    local off = FK.Encode({}, { buffs = false })
    ok(not (off or ""):find("I=", 1, true), "off writes nothing")

    -- LEAN: a fully buffed 40-raid looked at again costs about a call a person - the answers are kept
    local Cost = dofile("../_bisdev/dev/cost.lua")
    _G.IsInRaid = function() return true end
    for i = 1, 40 do
        local r = "raid" .. i
        STATE.units[r] = true
        WEAR[r] = { [1244] = now + 3000 }
    end
    WEAR.player = { [1244] = now + 3000 }
    FU.Forget()
    local first = Cost.Count(function() FU.Target("fort") end)
    local n, by = Cost.Count(function() FU.Target("fort") end)
    print(("   cost: Fortitude over a buffed 40-raid = %d calls first, %d after (%s)"):format(first, n, Cost.Top(by, 3)))
    ok(n <= 41 * 2 + 4, "looked at again, a buffed raid costs about two calls a person (the roster and us): " .. n, Cost.Top(by, 4))
    ok(first <= 40 * 12, "and the first look a few a person: " .. first)

    for i = 1, 40 do STATE.units["raid" .. i] = nil end
    _G.IsInRaid = keep.raid
    STATE.units, STATE.roles, STATE.dead, STATE.afk, STATE.offline = keep.units, keep.roles, keep.dead, keep.afk, keep.offline
    _G.C_UnitAuras, _G.C_Spell.IsSpellInRange, _G.UnitLevel, _G.UnitPowerType = keep.auras, keep.range, keep.level, keep.power
    for _, s in ipairs(SLOTS) do BOOK[s] = keptPages[s] end
    d.now, d.shown, d.buffs, d.buffFam, d.tank, d.me = keep.now, keep.shown, keep.buffs, keep.fam, keep.tank, keep.me
    bookSaid()
    FU.Forget()
    FN.Layout()
end

-- THE GROUP CHANGES MID-FIGHT (Arn, 19 Oct 2026: "shaman are suppose to be blue but some are priest
-- white might be bug when they leave during combat" - and a poison box lit on his own cell for someone
-- else's poison). The client moves everyone up a slot; the cells may not be re-pointed in a fight, so
-- their bar, colour, markers and click follow the slot - and the name must too.
do
    local keepName, keepUnits = _G.UnitName, STATE.units
    local NAMES = { player = "Arn", party1 = "Chain", party2 = "Tor" }
    _G.UnitName = function(u) return NAMES[u], nil end
    STATE.units = { player = true, party1 = true, party2 = true }
    STATE.inCombat = false
    local dd = NS.DB()
    local keepShown = dd.shown
    dd.shown = true                                   -- an earlier test left the grid hidden
    FG.Layout()
    local cell
    for _, f in ipairs(FG.frames or {}) do if f.unit == "party1" then cell = f end end
    ok(cell and cell.name.__text == "Chain", "party1's cell says Chain", cell and tostring(cell.name.__text))
    -- Chain leaves mid-fight: Tor moves up to party1
    STATE.inCombat = true
    NAMES.party1, NAMES.party2 = "Tor", nil
    STATE.units.party2 = nil
    FG.dirtyAll = false
    fire(FG.events, "GROUP_ROSTER_UPDATE")
    ok(cell.unit == "party1", "in a fight the cell keeps its slot (it may not be re-pointed)")
    ok(cell.name.__text == "Tor", "but its name now says who that slot holds - who a click heals",
       tostring(cell.name.__text))
    ok(FG.dirtyAll == true, "and every cell is repainted at once: bar, colour, markers")
    STATE.inCombat = false
    _G.UnitName, STATE.units, dd.shown = keepName, keepUnits, keepShown
    fire(FG.events, "PLAYER_REGEN_ENABLED")
    FG.Layout()
end

-- THE HEALS PROBE (Arn, 19 Oct 2026: "a window ... that breaks down the mana efficiency of my healing
-- spells ... all my talents my +healing ... using all ranks"). Step 0: `/bish heals` shows what the
-- client says about every rank, to copy out - the window is built on that.
do
    local FE = NS.FE
    local keep = { ids = NS.FM.BookIds, ranks = NS.FM.Ranks, cost = C_Spell.GetSpellPowerCost,
                   info = C_Spell.GetSpellInfo, desc = C_Spell.GetSpellDescription, bonus = _G.GetSpellBonusHealing,
                   tabs = _G.GetNumTalentTabs, n = _G.GetNumTalents, talent = _G.GetTalentInfo, tab = _G.GetTalentTabInfo }
    NS.FM.BookIds = function(name) if name == "Healing Wave" then return { 331, 332 } end return {} end
    NS.FM.Ranks = function(name) if name == "Healing Wave" then return { { rank = "Rank 1" }, { rank = "Rank 2" } } end return {} end
    C_Spell.GetSpellPowerCost = function(id) return { { type = 0, name = "MANA", cost = id == 331 and 25 or 45 } } end
    C_Spell.GetSpellInfo = function(id) return { name = "Healing Wave", castTime = id == 331 and 1500 or 2000 } end
    C_Spell.GetSpellDescription = function(id) return id == 331 and "Heals a friendly target for 34 to 44." or secret() end
    _G.GetSpellBonusHealing = function() return 212 end
    _G.GetNumTalentTabs = function() return 3 end
    _G.GetTalentTabInfo = function(t) return ({ "Elemental", "Enhancement", "Restoration" })[t] end
    _G.GetNumTalents = function(t) return t == 3 and 2 or 0 end
    _G.GetTalentInfo = function(t, i)
        if t == 3 and i == 1 then return "Tidal Focus", 0, 1, 1, 5, 5 end
        if t == 3 and i == 2 then return "Healing Grace", 0, 1, 2, 0, 3 end
    end
    local text = table.concat(FE.Probe(), "\n")
    ok(text:find("+healing 212", 1, true), "the probe reads your +healing")
    ok(text:find("== Healing Wave: 2 ranks", 1, true), "every rank of every heal you have")
    ok(text:find("Rank 1 [-] id 331  cost 25  cast 1500 ms", 1, true), "a rank's cost and cast time, as the client says",
       text:match("Rank 1[^\n]*"))
    ok(text:find("Heals a friendly target for 34 to 44.", 1, true), "and its tooltip's own words")
    ok(text:find("   secret", 1, true), "a secret tooltip says so - never an error")
    ok(text:find("Restoration: Tidal Focus 5/5", 1, true) and not text:find("Healing Grace", 1, true),
       "the talents you spent points in, by tree", text:match("Restoration[^\n]*"))
    ok(NS.DO.heals() == text and FE.box and FE.box:IsShown(), "/bish heals opens it in a box to copy")
    NS.FM.BookIds, NS.FM.Ranks = keep.ids, keep.ranks
    C_Spell.GetSpellPowerCost, C_Spell.GetSpellInfo, C_Spell.GetSpellDescription = keep.cost, keep.info, keep.desc
    _G.GetSpellBonusHealing, _G.GetNumTalentTabs, _G.GetNumTalents = keep.bonus, keep.tabs, keep.n
    _G.GetTalentInfo, _G.GetTalentTabInfo = keep.talent, keep.tab
    FE.box:Hide()

    -- THE WINDOW, on Arn's own level-30 shaman (his probe, gear on, 19 Oct): the tooltips hold the
    -- +healing already, so the window only does the arithmetic on what the client says
    local HW = { [331] = { 25, 1000, 60, 71 }, [332] = { 45, 1500, 127, 142 }, [547] = { 80, 2000, 232, 258 },
                 [913] = { 155, 2500, 382, 426 }, [939] = { 200, 2500, 466, 522 },
                 [8004] = { 105, 1500, 219, 242 }, [8008] = { 145, 1500, 284, 313 } }
    NS.FM.BookIds = function(name)
        if name == "Healing Wave" then return { 331, 332, 547, 913, 939 } end
        if name == "Lesser Healing Wave" then return { 8004, 8008 } end
        return {}
    end
    C_Spell.GetSpellPowerCost = function(id) return { { type = 0, name = "MANA", cost = HW[id][1] } } end
    C_Spell.GetSpellInfo = function(id) return { name = "x", castTime = HW[id][2] } end
    C_Spell.GetSpellDescription = function(id) return ("Heals a friendly target for %d to %d."):format(HW[id][3], HW[id][4]) end
    local keepPow, keepRegen, keepCrit = _G.UnitPowerMax, _G.GetManaRegen, _G.GetSpellCritChance
    _G.UnitPowerMax = function() return 1375 end
    _G.GetManaRegen = function() return 16.276, 8.3385 end
    _G.GetSpellCritChance = function() return 4.643 end
    _G.GetSpellBonusHealing = function() return 150 end
    local d = FE.Data()
    ok(#d.rows == 7, "every rank of Healing Wave and Lesser Healing Wave", #d.rows)
    local byLabel = {}
    for _, r in ipairs(d.rows) do byLabel[r.label] = r end
    local hw3 = byLabel["Healing Wave 3"]
    ok(math.abs(hw3.heal - 245 * (1 + 0.04643 * 0.5)) < 0.01, "a heal: the tooltip's middle, with crit",
       hw3.heal)
    ok(math.abs(hw3.hpm - hw3.heal / 80) < 1e-9 and math.abs(hw3.hps - hw3.heal / 2) < 1e-9, "per mana, per second")
    ok(math.abs(hw3.dry - 1375 / (40 - 8.3385)) < 0.01, "dry in: a full bar, with the mana back while casting",
       hw3.dry)
    local function first(t) return FE.Best(d, t)[1].label end
    local bestHpm, bestHps = d.rows[1], d.rows[1]
    for _, r in ipairs(d.rows) do
        if r.hpm > bestHpm.hpm then bestHpm = r end
        if r.hps > bestHps.hps then bestHps = r end
    end
    ok(bestHpm.label == "Healing Wave 3", "mana for mana: Healing Wave 3", bestHpm.label)
    ok(bestHps.label == "Lesser Healing Wave 2", "the fastest: Lesser Healing Wave 2", bestHps.label)
    ok(first(15) == "Lesser Healing Wave 2", "a 15 s burst: Lesser Healing Wave 2", first(15))
    ok(first(30) == "Healing Wave 4", "half a minute: Healing Wave 4", first(30))
    ok(first(60) == "Healing Wave 3", "a minute: Healing Wave 3", first(60))
    ok(first(300) == "Healing Wave 3" or first(300) == "Healing Wave 2", "a long fight: the cheap ranks win", first(300))
    -- the window paints it
    FE.fight = 60
    NS.DO.efficiency()
    local w = FE.win
    ok(w and w:IsShown() and w.answer:GetText():find("Spam Healing Wave 3 for 1 min", 1, true),
       "the window says which to spam", w and w.answer:GetText())
    local lit = 0
    for i = 1, 7 do if w.rows[i].lit:IsShown() then lit = lit + 1 end end
    ok(lit == 1, "and lights that one row")
    w.buttons[2]:Click()
    ok(FE.fight == 30 and w.answer:GetText():find("Healing Wave 4", 1, true), "30 s: it says Healing Wave 4")
    -- THE ANSWER TO TAKE AWAY (Arn, 19 Oct: "i want it to make a draggable button"): that rank's icon
    ok(w.pick:IsShown() and w.pick.id == 913, "the recommended rank's button: Healing Wave 4 (913)", w.pick.id)
    local picked
    local keepPick = C_Spell.PickupSpell
    C_Spell.PickupSpell = function(id) picked = id end
    w.pick.__scripts.OnDragStart(w.pick)
    ok(picked == 913, "dragging it picks up that rank", picked)
    STATE.inCombat = true
    picked = nil
    w.pick.__scripts.OnDragStart(w.pick)
    ok(picked == nil, "not in a fight (the cursor is the client's then)")
    STATE.inCombat = false
    C_Spell.PickupSpell = keepPick
    w.buttons[3]:Click()
    ok(w.pick.id == 547, "a minute: the button becomes Healing Wave 3", w.pick.id)
    -- and the mouse binds, a click away
    local opened = 0
    local keepMouse = NS.DO.mouse
    NS.DO.mouse = function() opened = opened + 1 end
    w.binds:Click()
    NS.DO.mouse = keepMouse
    ok(opened == 1, "the window's 'mouse binds' opens the bind window")
    -- DOCKED BESIDE THE OPTIONS (Arn, 19 Oct: "a button that i click and the window pops up where the
    -- 3d model is at"): the options' row hangs it off their right edge, as the tank preview
    w:Hide()
    local opt = NS.CFG.Build()
    local row
    for _, sec in ipairs(NS.CFG.Sections()) do
        for _, o in ipairs(sec.options) do if o.key == "efficiency" then row = o end end
    end
    row.action()
    local p, rel, rp = w:GetPoint(1)
    ok(w:IsShown() and w:GetParent() == opt and p == "TOPLEFT" and rel == opt and rp == "TOPRIGHT",
       "from the options: hung off their right edge", tostring(p) .. " " .. tostring(rp))
    ok(math.abs(w:GetWidth() / w:GetHeight() - 1.43) < 0.01, "1.43:1, the preview's shape")
    -- ITS OWN SIZE, SCALED (Arn's screenshot, 19 Oct: "some words get cutoff" - it had taken the
    -- options' height in their units and came out narrower than its columns)
    local _, oh = pcall(opt.GetHeight, opt)
    ok(w:GetWidth() == NS.FE.W and w:GetHeight() == NS.FE.H, "docked, it keeps the size its columns are laid out for")
    ok(type(oh) ~= "number" or oh < 200 or math.abs(w:GetScale() * NS.FE.H - oh) < 0.5,
       "and scales as a whole to the options' height", tostring(oh) .. " " .. tostring(w:GetScale()))
    local colEnd = 0
    for _, c in ipairs(NS.FE.COLS) do colEnd = colEnd + c[2] + 6 end
    ok(12 + colEnd <= NS.FE.W - 24, "every column, 'dry in' too, inside the window", 12 + colEnd)
    -- THE MOUSE BINDS DOCK TO ITS RIGHT (Arn: "when i click the mouse bind button it should dock it to
    -- the right of the window"), as they dock to the spellbook - and go back when it closes
    local keepBook = NS.FM.Book
    NS.FM.Book = function() return nil end
    w.binds:Click()
    local mw = NS.FM.win
    local mp, mrel, mrp = mw:GetPoint(1)
    ok(mw:IsShown() and mp == "TOPLEFT" and mrel == w and mrp == "TOPRIGHT", "the mouse binds open docked to its right",
       tostring(mp) .. " " .. tostring(mrp))
    w:Hide()
    NS.FM.Place(mw)
    ok(mw.dockedTo == nil and select(2, mw:GetPoint(1)) ~= w, "the mana window shut: the binds go back where they were")
    mw:Hide()
    NS.FM.Book = keepBook
    row.action()
    ok(NS.FE.Docked() and not (NS.FN.preview and NS.FN.preview:IsShown()), "the tank preview stands aside")
    row.action()
    ok(not w:IsShown(), "a second press closes it")
    NS.DO.efficiency()
    p = w:GetPoint(1)
    ok(w:IsShown() and w:GetParent() == UIParent and p == "CENTER", "/bish efficiency alone: free, in the middle")
    -- NOT WORKED OUT YET, SO NOT RANKED (Arn, 19 Oct: "does this work for all the healers? does it do
    -- hots and shields? ... chain heal bounces and priest aoe heals"): a party heal and a heal-then-HoT
    -- would read as one target's direct part. They show with a `*` and are never the pick. The words are
    -- Classic's - Forever's own wording is UNVERIFIED until a priest and a druid run /bish heals.
    local poh = FE.Parse("Heals all party members within 30 yards for 312 to 333.")
    local regrowth = FE.Parse("Heals a friendly target for 93 to 107 and another 98 over 21 sec.")
    local renew = FE.Parse("Heals the target for 45 damage over 15 sec.")
    local rejuv = FE.Parse("Heals the target for 32 over 12 sec.")
    ok(poh and poh.partial and regrowth and regrowth.partial, "a party heal and a heal-then-HoT are marked partial")
    ok(renew and not renew.partial and renew.lo == 45 and renew.hot == 15, "a plain HoT reads whole (Renew)")
    ok(rejuv and not rejuv.partial and rejuv.lo == 32 and rejuv.hot == 12, "and the other wording (Rejuvenation)")
    local bigPoh = { label = "Prayer of Healing 1", partial = true, hpm = 99, hps = 999, heal = 9999, cost = 1, dry = nil }
    local dd = { rows = { bigPoh, hw3 }, regen = 8, mana = 1000 }
    ok(FE.Best(dd, 60)[1] == hw3 and #FE.Best(dd, 60) == 1, "a `*` row is never the pick, however big it looks")
    -- a secret tooltip (mid-fight) is a rank left out, never an error
    C_Spell.GetSpellDescription = function() return secret() end
    ok(#FE.Data().rows == 0, "secret tooltips: nothing to show, no error")
    w:Hide()
    _G.UnitPowerMax, _G.GetManaRegen, _G.GetSpellCritChance = keepPow, keepRegen, keepCrit
    NS.FM.BookIds = keep.ids
    C_Spell.GetSpellPowerCost, C_Spell.GetSpellInfo, C_Spell.GetSpellDescription = keep.cost, keep.info, keep.desc
    _G.GetSpellBonusHealing = keep.bonus
end

----------------------------------------------------------- the UI rules (6 Nov 2026) --
--
-- Arn, 6 Nov, for every BiS addon (BiSTools is the reference): short words, a hover you can see,
-- Escape, and the version on the window.

-- 1. SHORT WORDS: every /bish word longer than 4 letters answers to one of 4 or fewer, and the long
-- one keeps working. "The same action" is measured, not assumed: every NS.DO is swapped for a
-- recorder, and the long and the short must reach the same one with the same arguments.
do
    local real = {}
    for k, fn in pairs(NS.DO) do real[k] = fn end
    local seen
    for k in pairs(real) do NS.DO[k] = function(...) seen = { k, ... } end end
    local function call(cmd)
        seen = nil
        local okC = pcall(SlashCmdList.BISHEALING, cmd)
        return okC and seen or nil
    end
    local function say(t)
        if not t then return "nothing" end
        local out = {}
        for i = 1, 4 do out[i] = tostring(t[i]) end
        return table.concat(out, " ")
    end
    -- every long word the parser takes, with the short word it answers to as well. A word that was
    -- already short (fear, tot, hpm, db, keep, %) is listed too: the help says it beside the long one.
    local PAIRS = {
        { "config", "opt" }, { "options", "opt" }, { "settings", "opt" },
        { "mouse", "bind" }, { "binds", "bind" },
        { "center", "ctr" }, { "centre", "ctr" },
        { "rescan", "rsc" }, { "auras", "aura" }, { "minimap", "mini" },
        { "scale", "scl" }, { "scale 90", "scl 90" },
        { "missing", "miss" }, { "deficit", "miss" },
        { "percent", "%" }, { "number", "num" }, { "number off", "num off" },
        { "colour", "clr" }, { "color", "clr" },
        { "target", "tgt" }, { "targetcell", "tgt" }, { "target left", "tgt left" },
        { "targetoftarget", "tot" }, { "totcell", "tot" },
        { "heals", "heal" }, { "range", "rng" },
        { "overheal", "over" }, { "overheal test", "over test" },
        { "curve", "curv" }, { "holds", "hold" },
        { "control", "fear" }, { "efficiency", "hpm" }, { "saved", "db" }, { "macro", "keep" },
        { "hits reset", "hits rst" },
        { "watch", "wtch" }, { "watch Lightning Shield", "wtch Lightning Shield" },
        { "between", "btw" }, { "reminders", "btw" },
        { "buffsound", "bsnd" }, { "buffsound off", "bsnd off" },
        { "buffs", "bufs" }, { "buffs fort on", "bufs fort on" },
        { "markers", "mark" }, { "markers 12", "mark 12" },
        { "cures", "cure" }, { "cures on", "cure on" },
        { "trinkets", "trin" }, { "trinkets shift both", "trin shift both" },
        { "hover", "hov" }, { "hover off", "hov off" },
        { "flash", "flsh" }, { "flash on", "flsh on" },
        { "clique", "clq" },
        { "layout", "lay" }, { "layout pyramid", "lay pyr" }, { "pyramid", "pyr" },
        { "columns", "cols" }, { "across", "rows" },
    }
    for _, p in ipairs(PAIRS) do
        local long, short = p[1], p[2]
        ok(#(short:match("^(%S+)") or short) <= 4, ("/bish %s: the short word %q is 4 letters or fewer"):format(long, short))
        local a, b = call(long), call(short)
        ok(a ~= nil and a[1] ~= "help", ("/bish %s still works (it reached %s)"):format(long, say(a)))
        -- `layout pyramid` and `pyr` both reach layout; the word it is handed is read by DO.layout,
        -- so for those the test is where the real one lands, below
        if not long:match("^layout") and long ~= "pyramid" then
            ok(b ~= nil and say(a) == say(b),
               ("/bish %s answers like /bish %s: %s vs %s"):format(short, long, say(b), say(a)))
        else
            ok(b ~= nil and b[1] == "layout", ("/bish %s reaches the layout: %s"):format(short, say(b)))
        end
    end
    -- the words are a table a test and the help can both read, every one of them short and none of
    -- them a word the parser already takes for something else
    ok(type(NS.SHORT) == "table", "the short words are one table (NS.SHORT)")
    local TAKEN = { show = 1, hide = 1, scan = 1, see = 1, pets = 1, pet = 1, me = 1, self = 1, mana = 1,
                    cpu = 1, byid = 1, tank = 1, now = 1, buff = 1, hits = 1, ping = 1, hots = 1, hot = 1,
                    res = 1, ring = 1, dim = 1, text = 1, grid = 1 }
    for long, short in pairs(NS.SHORT or {}) do
        ok(#short <= 4, ("%s -> %q is short"):format(long, short))
        ok(not TAKEN[short], ("%s -> %q is not a word already taken"):format(long, short))
    end
    for k, fn in pairs(real) do NS.DO[k] = fn end

    -- and the help says them: "mouse" in the help carries "bind" beside it
    local from = #SAID + 1          -- the suite's own NS.Print (above) keeps every line said
    NS.DO.help()
    local said = {}
    for i = from, #SAID do said[#said + 1] = SAID[i] end
    local all = (table.concat(said, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    ok(all:find("mouse/bind", 1, true) and all:find("minimap/mini", 1, true) and all:find("markers/mark 12", 1, true)
       and all:find("target/tgt left", 1, true),
       "/bish help shows the short word beside the long one: " .. all:sub(1, 160))
    -- every one of them, bar the three the help says by their short word alone (tot, db, keep)
    local unsaid = {}
    for long, short in pairs(NS.SHORT or {}) do
        if long ~= "targetoftarget" and long ~= "saved" and long ~= "macro"
           and not all:find(long .. "/" .. short, 1, true) then unsaid[#unsaid + 1] = long end
    end
    table.sort(unsaid)
    ok(#unsaid == 0, "every short word is in the help: " .. table.concat(unsaid, ", "))
    ok(all:find("hits reset/rst", 1, true), "and hits reset's")

    -- the layout's own short words land where the long ones do
    local keepLayout = NS.DB().layout
    local keepFG = NS.FG.Layout
    NS.FG.Layout = function() end
    ok(NS.DO.layout("pyr") == "pyramid", "layout pyr is the pyramid")
    ok(NS.DO.layout("cols") == "columns", "layout cols is the columns")
    NS.FG.Layout = keepFG
    NS.DB().layout = keepLayout
end

-- 2. HOVER POP: every button in the bind window and the mana window lights under the mouse - an accent
-- wash at 0.3-0.35, an accent bar, the label at full brightness - and goes back when the mouse leaves.
do
    local FM, FE = NS.FM, NS.FE
    FM.win = nil
    local w = FM.Window()
    w:Show()
    w:Refresh()
    local function bright(fs)
        local c = fs and fs.__color
        return type(c) == "table" and type(c[1]) == "number" and math.min(c[1], c[2], c[3]) >= 0.85
    end
    local function pops(b, label, what)
        local enter, leave = b and b.__scripts.OnEnter, b and b.__scripts.OnLeave
        ok(enter and leave, what .. ": it reacts to the mouse at all")
        if not (enter and leave) then return end
        enter(b)
        local a = b.wash and b.wash:GetAlpha()
        ok(type(a) == "number" and a >= 0.3 and a <= 0.35, what .. ": an accent wash under the mouse, 0.3-0.35",
           tostring(a))
        ok(b.bar and b.bar:IsShown(), what .. ": and an accent bar")
        if label then ok(bright(label), what .. ": the label goes to full brightness") end
        leave(b)
        ok(b.wash and b.wash:GetAlpha() == 0 and b.bar and not b.bar:IsShown(), what .. ": gone when the mouse leaves")
        if label then ok(not bright(label), what .. ": the label back to how it was") end
    end
    pops(w.tabs[2], w.tabs[2].text, "a modifier tab")
    FM.Set("", "left", "Healing Wave(Rank 3)")
    w:Refresh()
    pops(w.slots.left.rankBtn, w.slots.left.rank, "a slot's rank button")
    FM.Clear("", "left")
    pops(w.trinketTicks[1], w.trinketTicks[1].text, "a trinket tick")
    pops(w.pings[1], w.pings[1].text, "a ping")
    pops(w.palette[1], nil, "a heal on the palette")
    w:Hide()
    local m = FE.Win()
    pops(m.pick, nil, "the mana window's spell to drag")

    -- 3. ESCAPE: the two Heals.lua windows have names and close on Escape - handled HERE, as the bind window
    -- does, never through UISpecialFrames: that list is also emptied when a panel like the spellbook opens
    -- (CloseAllWindows), and Arn has met that surprise once already ("if the bind window is open and i open the
    -- spell book it closes the bind window"). Review, 6 Nov.
    local box = FE.Box()
    ok(box.__name == "BiSHealingProbe" and m.__name == "BiSHealingHeals",
       "the probe box and the mana window have names", tostring(box.__name) .. " " .. tostring(m.__name))
    local listed = {}
    for _, n in ipairs(_G.UISpecialFrames) do listed[n] = true end
    ok(not listed.BiSHealingProbe and not listed.BiSHealingHeals and not listed.BiSHealingMouse,
       "none of them on the list the spellbook empties")
    for _, w in ipairs({ box, m }) do
        w:Show()
        local key = w:GetScript("OnKeyDown")
        ok(key ~= nil, "it listens for Escape itself: " .. tostring(w.__name))
        if key then key(w, "ENTER") end
        ok(w:IsShown(), "another key leaves it open (and passes on to chat)")
        if key then key(w, "ESCAPE") end
        ok(not w:IsShown(), "Escape closes it: " .. tostring(w.__name))
    end
end

-- 4. THE VERSION MARK: the bind window says which build it is, faintly, in its own line at the foot -
-- the version, and the deploy stamp when the copy in the game has one.
do
    local FM = NS.FM
    ok(NS.VERSION ~= "0.0.0" and NS.VERSION:match("^%d+%.%d+%.%d+$"), "the version comes from the TOC", NS.VERSION)
    ok(NS.Mark and NS.Mark() == NS.VERSION, "no stamp: the mark is the version alone", NS.Mark and NS.Mark())
    ok(NS.Mark and NS.Mark("feat/ui-rules@9e52109+ 1106-1841") == NS.VERSION .. "  9e52109+ 1106-1841",
       "a stamp: the version, the commit and when, not the branch", NS.Mark and NS.Mark("feat/ui-rules@9e52109+ 1106-1841"))
    FM.win = nil
    local w = FM.Window()
    ok(w.mark and w.mark.__text == NS.VERSION, "the bind window shows the version", w.mark and w.mark.__text)
    _G.__BUILD = "main@abc1234 1106-2215"
    w:Refresh()
    ok(w.mark and w.mark.__text == NS.VERSION .. "  abc1234 1106-2215",
       "and the deploy stamp, read from the TOC copy", w.mark and w.mark.__text)
    _G.__BUILD = nil
    w:Refresh()
    ok(w.mark and w.mark.__text == NS.VERSION, "a released zip has no stamp: the version alone again")
    -- ONE BAR, ONE LABEL: it is not in the header. The header holds the title; the mark sits at the foot.
    local p = w.mark and w.mark.points and w.mark.points[1]
    ok(p and tostring(p[1]):match("^BOTTOM"), "the mark sits at the foot, not in the header bar", p and tostring(p[1]))
    w:Show()
    _G.__BUILD = "feat/ui-rules@9e52109+ 1106-1841"
    w:Refresh()
    fitsIn(w, "the mouse window, with a stamp")
    _G.__BUILD = nil
    w:Refresh()
    w:Hide()
end

-- ============================================================== FOREVER 1.0 (7 Nov 2026)
-- Arn: "every new user that we get will have every module turned off ... that includes like sounds,
-- crosshairs" - BUT "all the main functionalities start on". And: "everybody that already has the addons
-- installed, I don't wanna change default settings that they have on".
--
-- Driven through the REAL event handler, as a login is: ADDON_LOADED (the raw table, before anything
-- merges defaults), then PLAYER_LOGIN with no user action. The server macro is the third witness: a
-- client that hands back no saved file still has it.
do
    local FS, FG, FK = NS.FS, NS.FG, NS.FK
    local realChat = _G.DEFAULT_CHAT_FRAME
    local heard = {}
    local function said(p)
        for _, l in ipairs(heard) do if l:find(p, 1, true) then return true end end
        return false
    end
    local keptMacros = {}
    for i, m in pairs(MACROS) do keptMacros[i] = m end
    local function noMacro() for i in pairs(MACROS) do MACROS[i] = nil end end
    local function ourMacro()
        noMacro()
        MACROS[121] = { name = "BiSHealing", icon = 134400,
                        body = asTheClientStoresIt(FK.Encode({ left = "Healing Wave(Rank 2)" }, {})) }
    end
    local keepDB, keepChar, keepRead = _G.BiSHealingDB, _G.BiSHealingCharDB, FK.read
    local keepUE, keepIU = _G.UnitExists, _G.UnitIsUnit
    -- the mouse is on party1: a crosshair, if it is on, is drawn on their cell
    _G.UnitExists = function(u) if u == "mouseover" then return true end return keepUE(u) end
    _G.UnitIsUnit = function(a, b)
        if b == "mouseover" then return a == "party1" end
        return keepIU(a, b)
    end
    local cell
    for _, f in ipairs(FG.frames or {}) do if f.unit == "party1" and f.hoverMark then cell = f end end
    local function login(db, char)
        _G.BiSHealingDB, _G.BiSHealingCharDB = db, char
        heard = {}
        _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = tostring(t) end }
        fire(NS.events, "ADDON_LOADED", "BiSHealing")
        fire(NS.events, "PLAYER_LOGIN")
        _G.DEFAULT_CHAT_FRAME = realChat
        return NS.DB()
    end

    -- (a) A NEW INSTALL: no account file, no per-character copy, no macro - and the list is in, so
    -- "no macro" is an answer
    noMacro()
    FK.read = true
    local d = login(nil, nil)
    ok(d.forever10 == true, "a new install is stamped, once")
    ok(d.hover == false and d.flash == false and d.buffQuiet == true,
       "a new install starts quiet: no crosshair, no LOS flash, no buff-drop sound",
       tostring(d.hover) .. " " .. tostring(d.flash) .. " " .. tostring(d.buffQuiet))
    ok(FS.Watching() == false and #FS.List() == 0 and FS.Word() == nil,
       "and no buff reminder in the header")
    ok(FS.Quiet() and select(2, FS.Sounds()) == "off", "the sound is not registered at all")
    ok(cell and FG.PaintHover(cell, "party1") == false and not cell.hoverMark.__shown,
       "LIVE after the login: the mouse on a cell draws no crosshair")
    ok(d.shown == true and d.hots == true and d.ring == "me" and d.cures ~= false and d.resClick ~= false,
       "the core is on: the cells, your HoTs, the gold ring, cure boxes, click-a-dead-friend res")
    ok(NS.FM.Get("", "left") ~= nil, "and the mouse is seeded with the class's heals", tostring(NS.FM.Get("", "left")))
    ok(d.between == false and d.now == false and d.buffs ~= true and d.target == false and d.tot == false
       and d.me == false and d.mana == false and d.pets == "off",
       "every other extra is off: reminders in chat, BiS> now, buff buttons, target/tot/me/mana, pets")
    ok(not said("did not hand back"), "and no red warning: a new install had no file to lose")
    -- (c) a second load changes nothing - and what the player switched on since stays on
    NS.DO.hover("on")
    d = login(_G.BiSHealingDB, _G.BiSHealingCharDB)
    ok(d.hover == true and d.flash == false and d.buffQuiet == true and d.forever10 == true,
       "the next login changes nothing: the crosshair the player turned on stays on, the rest stays quiet",
       tostring(d.hover) .. " " .. tostring(d.flash) .. " " .. tostring(d.buffQuiet) .. " " .. tostring(d.forever10))
    -- AN ALT THAT HAS NEVER LOGGED OUT (no per-character copy): it takes its own per-character things
    -- (NS.Claim) - and the account's SETTINGS stay. Claim used to copy the copy's `dbver` too, which an
    -- alt without one handed back as nil: the next DB() ran the migration again, dropped every setting
    -- and moved the stamp to the attic, so the quiet new install came back loud on its first alt.
    d.owner = "Mainchar-Realm"
    d.hover, d.flash = false, false
    d = login(_G.BiSHealingDB, nil)
    ok(d.owner == NS.Me() and d.forever10 == true and d.hover == false and d.flash == false and d.buffQuiet == true,
       "logging into a new alt keeps the account's quiet settings and its stamp",
       tostring(d.forever10) .. " " .. tostring(d.hover) .. " " .. tostring(d.flash) .. " " .. tostring(d.buffQuiet))
    ok(d.dbver == NS.DBVER, "and the table's version", tostring(d.dbver))

    -- (b) AN EXISTING SAVE, from before 1.0: nil meant ON for the crosshair and the LOS flash. They are
    -- written down as on, so a nil can never be read any other way again
    local old = { dbver = 1, owner = NS.Me(), savedAt = 1700000000, saves = 12, shown = true,
                  binds = { left = "Chain Heal" }, bindsSeeded = true, buffQuiet = false }
    d = login(old, nil)
    ok(d.forever10 == true and d.hover == true and d.flash == true,
       "an existing save keeps the crosshair and the LOS flash on - frozen as true",
       tostring(d.hover) .. " " .. tostring(d.flash))
    ok(d.buffQuiet == false and FS.Watching() and FS.List()[1] == "Water Shield",
       "its buff sound and its header reminder stay exactly as they were")
    ok(d.binds.left == "Chain Heal", "and its binds")
    ok(cell and FG.PaintHover(cell, "party1") == true, "LIVE: its crosshair still draws after the login")
    ok(not said("did not hand back"), "a file that came back: no warning")
    -- an existing save that had things OFF keeps them off
    d = login({ dbver = 1, owner = NS.Me(), savedAt = 1, hover = false, flash = false, buffQuiet = true,
                selfBuffs = { "Inner Fire" } }, nil)
    ok(d.hover == false and d.flash == false and d.buffQuiet == true and FS.List()[1] == "Inner Fire",
       "an existing save with things switched off keeps them off, and its own buff list")
    local snap = { d.hover, d.flash, d.buffQuiet, d.selfBuffs and d.selfBuffs[1] }
    d = login(_G.BiSHealingDB, nil)
    ok(d.hover == snap[1] and d.flash == snap[2] and d.buffQuiet == snap[3] and d.selfBuffs[1] == snap[4],
       "(c) and its second 1.0 login changes nothing either")

    -- (d) THE CLIENT LOST THE ACCOUNT FILE but the per-character copy came back: an existing user
    d = login(nil, { binds = { left = "Healing Wave(Rank 2)" }, bindsSeeded = true, savedAt = 5, saves = 2 })
    ok(d.hover == true and d.flash == true and d.buffQuiet == false,
       "a per-character copy and no account file = an EXISTING user, never quietened")
    ok(said("did not hand back"), "and the red warning says the file was lost")

    -- (e) BOTH FILES LOST, the macro still on the server: an existing user too
    ourMacro()
    d = login(nil, nil)
    ok(d.forever10 == true and d.hover == true and d.flash == true and d.buffQuiet == false,
       "only the server macro left = an EXISTING user")
    ok(said("did not hand back"), "and the warning fires for them")

    -- (f) THE MACRO LIST NOT IN YET at login: "no macro" is not an answer, so nothing is decided -
    -- the old behaviour stands until the client says the list is in
    noMacro()
    FK.read = false
    d = login(nil, nil)
    ok(d.forever10 == nil and d.hover == nil, "the macro list not in yet: nothing decided, nothing written",
       tostring(d.forever10))
    ok(not said("did not hand back"), "and no warning on a guess")
    ourMacro()
    heard = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = tostring(t) end }
    fire(NS.events, "UPDATE_MACROS")
    _G.DEFAULT_CHAT_FRAME = realChat
    ok(d.forever10 == true and d.hover == true, "the list arrives holding our macro: existing, frozen on")
    ok(said("did not hand back"), "and only now the warning")
    noMacro()
    FK.read = false
    d = login(nil, nil)
    fire(NS.events, "UPDATE_MACROS")
    ok(d.forever10 == true and d.hover == false and d.buffQuiet == true,
       "the list arrives with no macro of ours: a new install, quiet")

    -- THE LOOK KEEPS WHAT THEY HAD (Arn, 8 Nov 2026: the cousin updated to 1.0.3 and woke up in the
    -- cockpit). The cockpit is for NEW installs; everyone who already had the addon keeps classic until
    -- they pick the cockpit themselves - the Forever 1.0 freeze rule, and 1.0.3 broke it.
    do
        local function look(f) return f and f.__look end
        local anyCell = FG.frames and FG.frames[1]
        noMacro()
        FK.read = true
        d = login(nil, nil)
        ok(d.look == "classic" and FG.Look() == "classic", "a new install starts in classic, nothing on (Arn, 11 Nov 2026)", tostring(d.look))
        d = login({ dbver = 1, owner = NS.Me(), savedAt = 1, shown = true }, nil)
        ok(d.look == "classic", "an existing save from before 1.0 keeps classic", tostring(d.look))
        -- THE COUSIN: stamped at 1.0.0, never picked a look, 1.0.3 read his nil as the cockpit
        d = login({ dbver = 1, owner = NS.Me(), savedAt = 1, shown = true, forever10 = true }, nil)
        ok(d.look == "classic" and FG.Look() == "classic" and d.look103 == true,
           "a save stamped at 1.0 that never picked a look goes back to classic, once", tostring(d.look))
        ok(look(anyCell) == "classic", "and the cells are dressed classic", tostring(look(anyCell)))
        NS.DO.look("cockpit")
        d = login(_G.BiSHealingDB, nil)
        ok(d.look == "cockpit", "then picking the cockpit sticks: the next login leaves it", tostring(d.look))
        d = login({ dbver = 1, owner = NS.Me(), savedAt = 1, forever10 = true, look = "cockpit" }, nil)
        ok(d.look == "cockpit", "a save that already picked the cockpit keeps it", tostring(d.look))
        -- the macro list late: decided on UPDATE_MACROS, the cells dressed again then
        noMacro()
        FK.read = false
        d = login(nil, nil)
        ok(d.look == nil, "the macro list not in yet: no look written", tostring(d.look))
        ourMacro()
        fire(NS.events, "UPDATE_MACROS")
        ok(d.look == "classic" and look(anyCell) == "classic",
           "the list arrives holding our macro: existing, classic, cells dressed again",
           tostring(d.look) .. " " .. tostring(look(anyCell)))
        noMacro()
        FK.read = true
    end

    -- THE SWITCHES STORE WHAT THEY SAY: nil never means "on" again
    ok(NS.DO.hover("on") == true and d.hover == true, "/bish hover on stores true", tostring(d.hover))
    ok(NS.DO.hover("off") == false and d.hover == false, "/bish hover off stores false")
    ok(NS.DO.flash("on") == true and d.flash == true, "/bish flash on stores true", tostring(d.flash))
    ok(NS.DO.flash("off") == false and d.flash == false, "/bish flash off stores false")

    -- EVERY QUIETED THING HAS A SWITCH IN THE OPTIONS WINDOW, so a new player can turn it on
    local keys = {}
    for _, o in ipairs(NS.UI.Rows()) do keys[o.key] = o end
    ok(keys.hover and keys.flash and keys.buffsound and keys.buffwatch,
       "the options window has the crosshair, the LOS flash, the buff sound and the buff reminder")
    if keys.flash and keys.buffwatch then
        keys.flash.set(d, true)
        ok(keys.flash.get(NS.DB()) == true and d.flash == true, "the LOS flash row turns it on")
        d.selfBuffs = { "Inner Fire" }
        keys.buffwatch.set(d, false)
        ok(keys.buffwatch.get(NS.DB()) == false and #FS.List() == 0 and d.selfBuffs[1] == "Inner Fire",
           "the reminder row turns it off - and keeps the player's own list for later")
        keys.buffwatch.set(d, true)
        ok(keys.buffwatch.get(NS.DB()) == true and FS.List()[1] == "Inner Fire", "and on again: the same list")
        NS.DO.buff("off")
        ok(FS.Watching() == false, "/bish buff off")
        NS.DO.buff("on")
        ok(FS.Watching() == true and FS.List()[1] == "Inner Fire", "/bish buff on")
        d.selfBuffs = { none = true }
        keys.buffwatch.set(d, true)
        ok(d.selfBuffs == nil and FS.List()[1] == "Water Shield", "on with no list of its own: the class's usual")
    end

    -- THE BiS> PAGE in the game's options (Esc > Options > AddOns > BiS> > BiS> Healing). The game's
    -- Settings stands in the way BiSTheme's own suite stands it in: a subcategory needs a registered
    -- parent, and every category answers GetID.
    local T = BiSTheme
    local reg, opened, nextId = {}, {}, 0
    local function Category(name)
        nextId = nextId + 1
        local c = { name = name, id = nextId }
        function c:GetID() return self.id end
        reg[c.id] = c
        return c
    end
    _G.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name) local c = Category(name) c.frame = frame return c, {} end,
        RegisterAddOnCategory = function(c) c.addon = true end,
        RegisterCanvasLayoutSubcategory = function(parent, frame, name)
            if not (parent and parent.addon) then error("parent category is not registered") end
            local c = Category(name) c.frame, c.parentCat = frame, parent
            return c, {}
        end,
        OpenToCategory = function(id) if not reg[id] then return false end opened[#opened + 1] = reg[id].name return true end,
    }
    if not (T and T.SettingsPage) then
        local loaded, why = pcall(function() assert(loadfile("Libs/BiSTheme/Settings.lua"))() end)
        ok(loaded, "the shared Settings kit loads headless", tostring(why))
        T = BiSTheme
    end
    T.settingsRoot, T.settingsPages, T.settingsOrder = nil, {}, {}
    ok(NS.CFG.events and NS.CFG.events.__events and NS.CFG.events.__events.PLAYER_LOGIN,
       "the page is registered at PLAYER_LOGIN")
    fire(NS.CFG.events, "PLAYER_LOGIN")
    local page = T.settingsPages.BiSHealing
    local spec = page and page.spec
    ok(page and page.category and page.category.name == "BiS> Healing", "BiS> Healing is a page under BiS>")
    ok(spec and spec.title == "Healing" and spec.open and spec.open.label == "mouse binds"
       and spec.api and spec.api.name == "BiSHealingAPI", "its title, its big button (mouse binds) and its API")
    d.shown, d.hover, d.flash, d.buffQuiet = true, false, false, true
    local status = spec and spec.status and spec.status()
    ok(type(status) == "string" and status:find("frames on", 1, true) and status:find("crosshair off", 1, true),
       "status says what is on, in a few words", tostring(status))
    local opened0 = 0
    local realMouse = NS.DO.mouse
    NS.DO.mouse = function() opened0 = opened0 + 1 end
    if spec and spec.open then spec.open.func() end
    NS.DO.mouse = realMouse
    ok(opened0 == 1, "its big button opens the mouse binds")
    -- THE PAGE NEVER TAKES THE WINDOW (kit minor 2, Arn 7 Nov: "dont just shrink remake them all"): the
    -- options window stays where it is, its own size, hidden - the page offers a button to it instead
    local win = NS.CFG.Build()
    ok(win ~= nil, "the options window builds")
    if win then
        win:Hide()
        local parent0, scale0, points0 = win:GetParent(), win:GetScale(), win:GetNumPoints()
        T.ShowSettingsPage("BiSHealing")
        ok(win:GetParent() == parent0 and win:GetScale() == scale0 and win:GetNumPoints() == points0,
           "showing the page leaves the options window's parent, scale and place alone",
           tostring(win:GetScale()) .. " was " .. tostring(scale0))
        ok(not win:IsShown(), "and leaves it hidden")
        -- THE DASHBOARD (kit minor 3, the family rule - Arn, 8 Nov: "it looks way way better do it for the
        -- other ones"): every section down the left, the picked one's settings big on the right
        ok(spec and type(spec.build) == "function" and type(spec.refresh) == "function",
           "the page draws the kit's dashboard: build and refresh")
        local body = page and page.frame and page.frame.body
        local dash = body and body.dash
        local entries = (NS.CFG.Entries and NS.CFG.Entries()) or {}
        ok(dash ~= nil and #dash.rows == #entries and #entries >= 4 and #entries <= 12,
           "showing the page builds the dashboard: one row per section", dash and #dash.rows)
        ok(not (page.frame.optBtn and page.frame.optBtn:IsShown()), "no stand-in button to the window any more")
        if dash then
            local function entryRow(key)
                for _, r in ipairs(dash.rows) do if r.entry.key == key then return r end end
            end
            local function dashRow(key, opt)
                for _, r in ipairs(dash.pages[key] or {}) do if r.opt.key == opt then return r end end
            end
            local titles = {}
            for i, r in ipairs(dash.rows) do titles[i] = r.entry.title end
            local all = table.concat(titles, " | ")
            ok(all:find("frames", 1, true) and all:find("binds & clicks", 1, true) and all:find("layout", 1, true)
               and all:find("BiS> now", 1, true), "the sections: " .. all)
            local hears, ownSize = true, true
            for _, r in ipairs(dash.rows) do
                local right = false
                for _, c in ipairs(r.__clicks or {}) do if c == "RightButtonUp" then right = true end end
                if not right then hears = false end
                if r.lamp.__allpoints or r.bar.__allpoints then ownSize = false end
            end
            ok(hears and ownSize, "every list row hears a right-click; its lamp and bar are their own size")
            -- EVERY SECTION BUILDS: the kit has four kinds, and the window's `cells` row arrives as four toggles
            for _, e in ipairs(dash.entries) do
                local okP, why = pcall(dash.Select, dash, e.key)
                ok(okP and #(dash.pages[e.key] or {}) == #(e.options or {}) and type(e.desc) == "string" and e.desc ~= "",
                   "a section builds, with its words: " .. tostring(e.title), tostring(why))
            end
            -- PICKING ONE shows its rows, and only its rows
            dash:Select("layout")
            local labels, shown = {}, true
            for i, r in ipairs(dash.pages.layout or {}) do labels[i] = r.opt.label if not r:IsShown() then shown = false end end
            ok(shown and table.concat(labels, "|"):find("PvP mode", 1, true), "layout shows its rows, PvP mode among them",
               table.concat(labels, "|"))
            ok(dash.pages.frames and not dash.pages.frames[1]:IsShown(), "the section picked before puts its rows away")
            -- A SETTING FLIPPED ON THE PAGE is the window's own setting: the same table, the same saved value
            local pvp = dashRow("layout", "pvp")
            local winRow
            for _, r in ipairs(win.rows or {}) do if r.opt and r.opt.key == "pvp" then winRow = r end end
            ok(pvp and winRow and pvp.opt == winRow.opt, "the page's PvP row is the window's row")
            if pvp and winRow then
                local keepPvP = NS.FG.PvPMode()
                pvp.segs[2]:Click()                                  -- "bg"
                ok(NS.FG.PvPMode() == "bg" and NS.UI.Get("pvp") == "bg", "PvP mode set to bg from the page",
                   tostring(NS.FG.PvPMode()))
                win:Paint()
                ok(winRow.ctl[2].edge.name == "accent" and winRow.ctl[1].edge.name ~= "accent",
                   "and the window's row says bg after its paint")
                winRow.ctl[1]:Click()                                -- "off", from the window
                dash:Paint()
                ok(NS.FG.PvPMode() == "off" and pvp.segs[1].on and not pvp.segs[2].on, "set back in the window: the page follows")
                NS.DO.pvp(keepPvP)
            end
            -- the window's `colour` setting from the page: the saved value the window reads
            dash:Select("look")
            local colour = dashRow("look", "colour")
            local was = NS.DB().color
            if colour then colour.sw:Click() end
            ok(colour and NS.UI.Get("colour") == (was ~= "health") and colour.sw.on == (was ~= "health"),
               "bar colour by health flipped on the page: saved, and the switch says so")
            if colour then colour.sw:Click() end
            -- A SECTION SWITCH goes through the slash command's own door (NS.DO.show)
            local calls = {}
            local realShow = NS.DO.show
            NS.DO.show = function(on) calls[#calls + 1] = on return realShow(on) end
            dash:Select("frames")
            dash.detail.switch:Click()
            local fr = entryRow("frames")
            ok(#calls == 1 and calls[1] == false and NS.DB().shown == false and fr and fr.state:GetText() == "off",
               "the frames switch: NS.DO.show(false), saved, the list says off", #calls)
            ok(dash.pages.frames[1].dim == true, "its settings grey while the cells are hidden")
            SlashCmdList.BISHEALING("show")
            T.ShowSettingsPage("BiSHealing")                         -- the page shown again: refresh paints it
            ok(#calls == 2 and calls[2] == true and NS.DB().shown == true and fr.state:GetText() == "ON"
               and dash.detail.switch.on == true, "/bish show goes through the same door, and the page follows")
            NS.DO.show = realShow
            -- RIGHT-CLICK in the list switches BiS> now, through NS.DO.now
            local nowCalls = {}
            local realNow = NS.DO.now
            NS.DO.now = function(a) nowCalls[#nowCalls + 1] = a return realNow(a) end
            local nowWas = NS.DB().now == true
            local nr = entryRow("now")
            if nr then nr:Click("RightButton") end
            ok(nr and nowCalls[1] == (nowWas and "off" or "on") and (NS.DB().now == true) == not nowWas,
               "right-click on BiS> now switches it through /bish now", tostring(nowCalls[1]))
            if nr then nr:Click("RightButton") end
            ok((NS.DB().now == true) == nowWas, "and back")
            NS.DO.now = realNow
            -- binds & clicks: its window button is the mouse binds; a button row that opens a window puts the
            -- game's options away first, and the mana window opens free, not hung off a hidden options window
            dash:Select("clicks")
            local binds = 0
            NS.DO.mouse = function() binds = binds + 1 end
            local panelUp = true
            _G.SettingsPanel = { IsShown = function() return panelUp end, Hide = function() panelUp = false end }
            dash.detail.open:Click()
            ok(binds == 1 and panelUp == false and dash.detail.open:IsShown(), "its window button: the mouse binds, game options away")
            NS.DO.mouse = realMouse
            local eff = dashRow("clicks", "efficiency")
            panelUp = true
            if eff then eff.btn:Click() end
            local fw = NS.FE and NS.FE.win
            ok(eff and panelUp == false and fw and fw:IsShown() and fw:GetParent() == UIParent,
               "which heal, from the page: game options away, the mana window free in the middle")
            if fw then fw:Hide() end
            _G.SettingsPanel = nil
        end
        ok(not win:IsShown() and win:GetParent() == parent0 and win:GetScale() == scale0 and win:GetNumPoints() == points0,
           "after all of it the options window is where it was, its own size, hidden")
        win:Show()
        T.HideSettingsPage("BiSHealing")
        ok(win:IsShown() and win:GetParent() == parent0, "leaving the page does not touch the window")
        win:Hide()
    end

    -- THE MINIMAP, ONE STANDARD: left = the mouse binds, right = the addon's OWN options window, a toggle
    -- (Arn 7 Nov: "when i right click the minimap again it should close that option window"). The game's
    -- options are never opened by it, even with the BiS> page registered.
    local b = NS.MM.Build()
    ok(b ~= nil, "the minimap button builds")
    if b and win then
        local click = b:GetScript("OnClick")
        local binds = 0
        NS.DO.mouse = function() binds = binds + 1 end
        local n0 = #opened
        click(b, "RightButton")
        ok(win:IsShown() and #opened == n0 and binds == 0,
           "right-click: the options window shows - the game's options do not open", #opened - n0)
        click(b, "RightButton")
        ok(not win:IsShown() and #opened == n0, "right-click again: it closes")
        click(b, "LeftButton")
        ok(binds == 1 and not win:IsShown() and #opened == n0, "left-click: the mouse binds")
        NS.DO.mouse = realMouse
    end

    _G.Settings = nil
    T.settingsRoot, T.settingsPages, T.settingsOrder = nil, {}, {}
    _G.UnitExists, _G.UnitIsUnit = keepUE, keepIU
    noMacro()
    for i, m in pairs(keptMacros) do MACROS[i] = m end
    FK.read = keepRead
    _G.BiSHealingDB, _G.BiSHealingCharDB = keepDB, keepChar
    fire(NS.events, "ADDON_LOADED", "BiSHealing")
end

-- BUGS FROM THE 7 NOV SWEEP
do
    -- (1) A REFUSED AURA BUTTON. FA.Placed noticed a refusal and then ran the marker's styling anyway -
    -- outside any pcall - on a button the client had just refused. The styling (GetRegions,
    -- CreateTexture, SetMouseMotionEnabled) is the same client's object: a refusal there threw out of
    -- the client's own hand-over, every time an aura arrived.
    local FA = NS.FA
    local styled = 0
    local forbidden = setmetatable({}, { __index = function(_, k)
        error("Attempt to access forbidden object from code tainted by an AddOn (" .. tostring(k) .. ")", 2)
    end })
    FA.initRefused = nil
    local init = FA.Placed(function(btn) styled = styled + 1 return btn:CreateTexture() end, 10, "LEFT", UIParent, 2, 0)
    local ran, why = pcall(init, forbidden)
    ok(ran, "a refused aura button never throws out of the client's hand-over", tostring(why))
    ok(FA.initRefused and styled == 0, "the refusal is kept, and the styling is not run on it", styled)
    -- a button that takes the size but refuses its art: the styling's throw stays inside
    FA.initRefused = nil
    local half = newFrame("Button")
    half.CreateTexture = function() error("Attempt to access forbidden object from code tainted by an AddOn", 2) end
    ran, why = pcall(init, half)
    ok(ran and FA.initRefused, "a refusal inside the styling is caught and kept", tostring(why))
    -- and a plain button is styled as always
    FA.initRefused, styled = nil, 0
    ran = pcall(init, newFrame("Button"))
    ok(ran and styled == 1 and not FA.initRefused, "an ordinary button is sized, placed and styled")
    FA.initRefused = nil

    -- (2) THE HIDDEN CHECK FIRST. A secret string refuses a comparison on the client (`n == ""`); Lua 5.1
    -- cannot make a table refuse `==` against a string, so the mock cannot be that client here. The
    -- order is read from the source instead: the secret test before any comparison.
    local function body(file, startPat)
        local fh = assert(io.open(file))
        local src = fh:read("*a")
        fh:close()
        local s = src:find(startPat)
        return s and src:sub(s, s + 600) or ""
    end
    local me = body("Core.lua", "local function me%(%)")
    local sec, cmp = me:find("issecretvalue", 1, true) or me:find("NS.Secret", 1, true), me:find('n == ""', 1, true)
    ok(sec and cmp and sec < cmp, "me(): the name's hidden check comes before n == \"\"", tostring(sec) .. " " .. tostring(cmp))
    local oil = body("Now.lua", "function FN%.OilEffect")
    local osec, ocmp = oil:find("NS.Secret", 1, true), oil:find('text == ""', 1, true)
    ok(osec and ocmp and osec < ocmp, "FN.OilEffect: the hidden check comes before text == \"\"",
       tostring(osec) .. " " .. tostring(ocmp))
    local realName = _G.UnitName
    _G.UnitName = function(u) if u == "player" then return secretString() end return realName(u) end
    local okMe, who = pcall(NS.Me)
    _G.UnitName = realName
    ok(okMe and who == nil, "a hidden name: me() answers nobody, never throws", tostring(who))
end

-- ============================================================== THE COCKPIT LOOK (8 Nov 2026)
-- Arn: "reimage the cells and frames as if its on a cockpit, rearragne where the names goes what color they are where
-- the buttons sit on the frames etc". A glass cockpit's colour rule: green normal, amber caution, red warning, cyan
-- information, magenta selected, white words. The default; "classic" one switch away.
do
    local d = NS.DB()
    local keepLook = d.look
    local function near(c, want) return c and math.abs(c[1] - want[1]) < 0.01 and math.abs(c[2] - want[2]) < 0.01
                                      and math.abs(c[3] - want[3]) < 0.01 end
    d.look = nil
    ok(FG.Look() == "classic", "nothing written reads as classic (Arn, 11 Nov 2026: \"new installs start in classic\")")
    ok(NS.DO.look("cockpit") == "cockpit" and d.look == "cockpit", "/bish look cockpit")
    local K = FG.COCKPIT
    local f
    for _, x in ipairs(FG.frames) do if x.unit and x:IsShown() then f = x break end end
    ok(f and f.__look == "cockpit", "every cell is dressed again at once", f and tostring(f.__look))
    ok(near(f.bg.__color, K.tile), "the tile is near-black, a display")
    ok(f.bezel.top.__shown and near(f.bezel.left.__color, K.bezel), "with a thin steel bezel")
    -- DESIGN B, THE TAPE (Arn, 8 Nov, of three drawn: "Go with cockpit design B, the tape"): a dark screen, the
    -- name big on top behind its class lamp, the missing health an amber readout on the right, and the health a gauge
    -- tape along the bottom with quarter marks. No strip, no black boxes.
    local function pt(x, name) for _, p in ipairs(x.points or {}) do if p[1] == name then return p end end end
    local bl, br = pt(f.bar, "BOTTOMLEFT"), pt(f.bar, "BOTTOMRIGHT")
    ok(bl and br and f.bar.__h == K.tapeH and not pt(f.bar, "TOPLEFT"),
       "the health is a tape along the bottom, " .. K.tapeH .. " px tall", tostring(f.bar.__h))
    local tw = (f.__w or 84) - 2 * K.tapeIn
    ok(f.incoming.__w == tw and f.incoming.__h == K.tapeH and f.overheal.__w == tw and f.absorb.__h == K.tapeH,
       "the heals, shield and overheal are the tape's own size (the overheal's geometry needs it exact)",
       ("%s x %s vs %s x %s"):format(tostring(f.incoming.__w), tostring(f.incoming.__h), tw, K.tapeH))
    ok(f.track and f.track.__shown, "the tape sits in a dark track")
    ok(#f.ticks == 3, "with three quarter marks")
    local q = pt(f.ticks[2], "BOTTOMLEFT")
    ok(q and math.abs(q[4] - tw * 0.5) < 0.6, "the middle mark at half the tape", q and tostring(q[4]))
    ok(not f.band.__shown and not f.readoutBox.__shown, "no black strip, no black readout box")
    local ip = f.ink.__allpoints
    ok(ip == f, "the words ride the whole cell, not the tape")
    local hp = pt(f.htext, "BOTTOMRIGHT")
    ok(hp and hp[2] == f.bar and hp[3] == "TOPRIGHT", "the readout sits on the right, just above the tape")
    -- THE MARKS ARE NEVER COVERED: the quarter marks' layer is over the heal bands and under the words, and the
    -- target / mouse / tank marks are drawn above them all (a frame draws over a lower one, whatever the texture layer)
    local function lvl(x) return x and x.GetFrameLevel and x:GetFrameLevel() or -1 end
    local stripLvl = lvl(f.bandFrame)
    ok(stripLvl > lvl(f.overheal) and stripLvl > lvl(f.incoming) and stripLvl > lvl(f.absorb) and stripLvl < lvl(f.ink),
       "the quarter marks are over the heal bands and under the words", stripLvl .. " vs ink " .. lvl(f.ink))
    ok(lvl(f.targetRing) > stripLvl and lvl(f.notTarget) > stripLvl and lvl(f.tankRing) > stripLvl,
       "the target, mouse and tank marks are drawn over them",
       ("%d %d %d over %d"):format(lvl(f.targetRing), lvl(f.notTarget), lvl(f.tankRing), stripLvl))
    -- THE NAME: white, narrow type, left-aligned after the class lamp
    FG.Paint(f)
    ok(near(f.name.__tc or f.name.__color, K.name), "the name is white - the class is not the name's job here")
    ok(f.name.__fontFile == K.font, "in narrow instrument type", tostring(f.name.__fontFile))
    ok(f.name.__justify == "LEFT", "left-aligned like a label", tostring(f.name.__justify))
    ok(f.lamp.__shown and f.lamp.__color, "and the class shows as a lamp in the strip")
    -- THE TAPE: by state, never by class
    local _, cls = UnitClass(f.unit)
    local bc = f.bar.__color
    ok(bc and not (cls and near(bc, ({ SHAMAN = { 0.0, 0.44, 0.87 } })[cls] or { -1, -1, -1 })),
       "the health tape is coloured by state, not by class", bc and table.concat(bc, ","))
    -- THE READOUT: a black window bottom right, amber digits
    ok(not f.readoutBox.__shown, "the readout has no black box behind it (B: the digits alone)")
    ok(near(f.htext.__tc or f.htext.__color, K.readout), "missing health in amber")
    ok(near(f.incoming.__color or f.incoming.__statusColor, K.incoming), "heals on their way in cyan")
    ok(near(f.overheal.__color or f.overheal.__statusColor, K.overheal), "overheal in orange - a caution")
    -- YOUR TARGET: magenta
    local keepIsUnit = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) return b == "target" end
    FG.PaintTarget(f, f.unit, true)
    _G.UnitIsUnit = keepIsUnit
    local stroke = f.targetRing.cross[1].__color
    ok(near(stroke, K.target), "your target wears a magenta crosshair", stroke and table.concat(stroke, ","))
    -- DEAD: a red annunciator
    STATE.dead[f.unit] = true
    FG.Paint(f)
    ok(f.htext.__text == "DEAD" and near(f.htext.__tc or f.htext.__color, K.dead), "DEAD in warning red")
    STATE.dead[f.unit] = nil
    FG.Paint(f)
    ok(near(f.htext.__tc or f.htext.__color, K.readout), "and back to the amber readout when they stand up")
    -- ONE SWITCH BACK
    local row
    for _, o in ipairs(NS.UI.Rows()) do if o.key == "look" then row = o end end
    ok(row and row.kind == "seg" and table.concat(row.values, ",") == "classic,cockpit,radar" and row.help
       and row.help:find("radar - ", 1, true),
       "the options window has a look row: classic, cockpit, radar (Arn, 11 Nov 2026: \"can you not make it cut off\")")
    local keepL = NS.DB().look
    for _, v in ipairs(row.values) do
        ok(#v <= 7, "the button word fits the kit's segment: " .. v)
    end
    row.set(nil, "radar")
    ok(NS.DB().look == "radar" and row.get() == "radar", "the radar button sets the radar look, and shows it picked")
    ok(NS.DO.look("dashboard") == "radar" and NS.DO.look("dash") == "radar", "its one-evening name still answers")
    NS.DB().look = "dashboard"
    ok(FG.Look() == "radar" and NS.DB().look == "radar", "a save holding \"dashboard\" reads as radar, and is written so")
    NS.DO.look(keepL)
    row.set(d, "classic")
    ok(d.look == "classic" and f.__look == "classic", "classic picked: every cell back at once")
    ok(not f.band.__shown and not f.bezel.top.__shown and not f.lamp.__shown and not f.readoutBox.__shown,
       "no strip, no bezel, no lamp, no readout window")
    ok(f.targetRing:GetFrameLevel() == f:GetFrameLevel() + 2 and f.notTarget:GetFrameLevel() == f:GetFrameLevel() + 3
       and f.tankRing:GetFrameLevel() == f:GetFrameLevel() + 1, "and the marks back at their classic levels")
    ok(near(f.bg.__color, FG.CLASSIC.tile) and near(f.incoming.__color or f.incoming.__statusColor, FG.CLASSIC.incoming),
       "the tile and the heals as they were")
    ok(pt(f.bar, "TOPLEFT") and f.ink.__allpoints == f.bar and not f.track.__shown and not f.ticks[1].__shown
       and f.incoming.__h == (f:GetHeight() or 0) - 2,
       "the health fills the cell again, the words on it, no track or marks, the bands the cell's size")
    SlashCmdList.BISHEALING("look cockpit")
    ok(d.look == "cockpit" and f.__look == "cockpit", "/bish look cockpit puts it back")
    d.look = keepLook
    FG.RedressAll()
end

-- ============================================================== HOSTILE BINDS AND MACROS (8 Nov 2026)
-- Arn: "hostile mode > can drag harmful spells and if a cell is a hostile target use the hostile binds on them.
-- can drag macros also on the binds." The hostile set is a second mouse; the client's own secure click code
-- switches to it on an enemy (harmbutton), so nothing of ours runs at the click.
do
    local FM, FK, FG = NS.FM, NS.FK, NS.FG
    -- A CLICK RESOLVED THE WAY BLIZZARD'S SecureActionButton DOES IT: the button number, remapped through
    -- `harmbutton` when the unit is an enemy; then each attribute looked up with the held modifier's prefix, the
    -- "*" wildcard, then bare. A remapped button is no number, so its suffix is "-" .. the new name.
    local function resolve(cell, button, mod, hostile)
        local function get(name, suffix)
            for _, p in ipairs({ mod, "*", "" }) do
                local v = cell.__attrs[p .. name .. suffix]
                if v ~= nil then return v end
            end
        end
        local b = button
        if hostile then b = get("harmbutton", button) or button end
        local suffix = tonumber(b) and b or ("-" .. b)
        return get("type", suffix), get("spell", suffix), get("macro", suffix), get("macrotext", suffix)
    end
    local wasLeft = FM.Get("", "left")
    FM.Set("", "left", "Healing Wave(Rank 3)")
    FM.Set("harm:", "left", "Lightning Bolt(Rank 2)")
    FM.Set("harm:shift-", "right", "Earth Shock(Rank 1)")
    FM.Apply()
    local cell = FG.frames[1]
    local ty, sp = resolve(cell, "1", "", true)
    ok(ty == "spell" and sp == "Lightning Bolt(Rank 2)", "a left click on an ENEMY casts the hostile bind", tostring(sp))
    ty, sp = resolve(cell, "1", "", false)
    ok(sp == "Healing Wave(Rank 3)", "on a friend: the heal, as before", tostring(sp))
    ty, sp = resolve(cell, "2", "shift-", true)
    ok(sp == "Earth Shock(Rank 1)", "shift-right on an enemy: its own hostile bind", tostring(sp))
    ty, sp = resolve(cell, "2", "", true)
    ok(cell.__attrs["*harmbutton2"] == nil, "a button with no hostile bind is not switched on an enemy")
    FM.Clear("harm:", "left")
    FM.Apply()
    ok(cell.__attrs["*harmbutton1"] == nil and cell.__attrs["*type-harm1"] == nil and cell.__attrs["*spell-harm1"] == nil,
       "a cleared hostile bind leaves nothing behind on the cell")
    ok(FM.Get("", "left") == "Healing Wave(Rank 3)", "and the heal set never noticed")
    -- the binds are their own: the range check and the heal palette read the heal set only
    ok(FM.RangeSpell() ~= "Earth Shock" and FM.RangeSpell() ~= "Earth Shock(Rank 1)", "the range check never asks a hostile bind")

    -- MACROS ON A BIND. The cursor carries ("macro", index) - the client's shape for a macro off the macro window.
    MACROS[7] = { name = "Purge it", icon = 136075, body = "/cast [@mouseover] Purge" }
    MACROS[8] = { name = "a;b", icon = 1, body = "/say hi" }
    CURSOR = { kind = "macro", a = 7 }
    local cast = FM.CursorSpell()
    ok(cast == "macro:Purge it", "a macro picked up from the macro window is a bind: by its name", tostring(cast))
    CURSOR = { kind = "macro", a = 8 }
    ok(FM.CursorSpell() == nil, "a macro whose name would break the save is refused, not mangled")
    CURSOR = { kind = "macro", a = 99 }
    ok(FM.CursorSpell() == nil, "a macro index the client does not know: nothing")
    CURSOR = {}
    FM.Set("harm:", "middle", "macro:Purge it")
    FM.Set("", "button4", "macro:Purge it")
    FM.Apply()
    local mty, msp, mmac, mtext = resolve(cell, "3", "", true)
    ok(mty == "macro" and mmac == "Purge it" and msp == nil and mtext == nil,
       "a hostile macro: the cell runs that macro on an enemy", tostring(mty) .. " " .. tostring(mmac))
    mty, msp, mmac, mtext = resolve(cell, "4", "", false)
    ok(mty == "macro" and mmac == "Purge it" and mtext == nil, "a macro on a heal bind runs on a friend too")
    local rs = FM.RangeSpell()
    ok(type(rs) ~= "string" or not rs:find("macro:", 1, true), "the range check never asks a macro its range", tostring(rs))
    -- the save macro: hostile rows and macros survive the client's round trip (it adds a newline)
    local binds = { left = "Healing Wave(Rank 3)", ["harm:left"] = "Lightning Bolt(Rank 2)",
                    ["harm:shift-right"] = "macro:Purge it", ["shift-left"] = "macro:Purge it" }
    local body = FK.Encode(binds)
    local back = FK.Decode(body .. "\n")
    ok(back and back["harm:left"] == "Lightning Bolt(Rank 2)" and back["harm:shift-right"] == "macro:Purge it"
       and back.left == "Healing Wave(Rank 3)" and back["shift-left"] == "macro:Purge it",
       "hostile binds and macros come back from the save macro", tostring(body))
    -- AN OLDER COPY (1.0 before this, or 0.x) reading the new macro must see the heal binds and nothing else:
    -- its row reader, verbatim - a one-letter modifier it knows (s c a) and a slot letter
    local OLDSLOT = { l = "left", r = "right", u = "wheelup", d = "wheeldown", m = "middle", ["4"] = "button4", ["5"] = "button5" }
    local OLDMOD = { s = "shift-", c = "ctrl-", a = "alt-" }
    local old, n = {}, 0
    local rest = body:match("#(.*)$") or ""
    for row in rest:gmatch("[^;]+") do
        local code = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code and not code:match("^%u$") then
            local slot = OLDSLOT[code:sub(-1)]
            local mod = #code > 1 and OLDMOD[code:sub(1, 1)] or ""
            if slot and mod then old[mod .. slot] = true n = n + 1 end
        end
    end
    ok(n == 2 and old.left and old["shift-left"], "an older copy reading it sees only the heal binds - never a bolt on its left click", n)
    -- a full macro sheds the hostile set before any heal (rows go from the end)
    local fat = {}
    local nth = 0
    for _, m in ipairs(FM.MODS) do for _, s in ipairs(FM.SLOTS) do
        nth = nth + 1
        fat[m.key .. s.key] = "Lesser Healing Wave Number " .. nth .. "(Rank 6)"
    end end
    fat["harm:left"] = "Lightning Bolt(Rank 9)"
    local fatBody, dropped = FK.Encode(fat)
    local fatBack = FK.Decode(fatBody)
    ok(dropped > 0 and fatBack["harm:left"] == nil, "a full macro drops a hostile bind before a heal", dropped)

    -- THE WHEEL has no unit to switch on, so its one macro asks: an enemy under the cursor gets the hostile spell
    FM.Set("", "wheelup", "Healing Wave(Rank 1)")
    FM.Set("harm:", "wheelup", "Lightning Bolt(Rank 2)")
    FM.Apply()
    local wb = _G["BiSHealWheelwheelup"]
    local text = wb and wb:GetAttribute("macrotext") or ""
    local hpos, gpos = text:find("/cast [@mouseover,harm,nodead] Lightning Bolt(Rank 2)", 1, true), text:find("nohelp", 1, true)
    ok(hpos and gpos and hpos < gpos and text:find("Healing Wave(Rank 1)", 1, true),
       "the wheel: the hostile spell on an enemy first, then the heal's guard and the heal", text)
    FM.Clear("", "wheelup")
    FM.Apply()
    text = wb:GetAttribute("macrotext") or ""
    ok(text:find("Lightning Bolt", 1, true) and not text:find("nohelp", 1, true), "a hostile wheel with no heal: just the bolt")
    FM.Clear("harm:", "wheelup")
    FM.Set("", "wheeldown", "macro:Purge it")
    FM.Apply()
    local wd = _G["BiSHealWheelwheeldown"]
    ok(wd and wd:GetAttribute("type") == "macro" and wd:GetAttribute("macro") == "Purge it" and wd:GetAttribute("macrotext") == nil,
       "a macro on the wheel: the wheel runs that macro")
    FM.Clear("", "wheeldown")

    -- CLIQUE OWNS THE CLICKS: nothing hostile of ours left on the cell either
    local d = NS.DB()
    d.clique = true
    FM.Apply()
    ok(cell.__attrs["*harmbutton3"] == nil and cell.__attrs["*type-harm3"] == nil and cell.__attrs["*macro4"] == nil,
       "Clique on: our hostile and macro attributes are gone too")
    d.clique = nil
    FM.Apply()
    ok(resolve(cell, "3", "", true) == "macro", "Clique off: they come back")

    -- THE WINDOW: a HEAL / HOSTILE switch; the hostile mouse is its own, tinted, and takes drops
    local w = FM.Window()
    ok(w.sets and #w.sets == 2, "the bind window has a heal / hostile switch")
    w.sets[2]:Click()
    ok(w.set == "harm:" and w:Key() == "harm:", "the hostile side picked")
    CURSOR = { kind = "macro", a = 7 }
    w.slots.right.take()
    ok(FM.Get("harm:", "right") == "macro:Purge it" and FM.Get("", "right") ~= "macro:Purge it",
       "a drop on the hostile mouse is a hostile bind; the heal under it untouched")
    -- THE HOSTILE PALETTE (Arn, 8 Nov live: "maybe we put the hostile spells at the bottom of the window like how we
    -- put healing spells so they can drag and not have to open spellbook"): your trained damage and control spells,
    -- top rank, along the bottom - on the hostile side only
    local keepB1, keepB2 = BOOK[41], BOOK[42]
    BOOK[41] = { name = "Lightning Bolt", rank = "Rank 1" }
    BOOK[42] = { name = "Lightning Bolt", rank = "Rank 2" }
    w:Refresh()
    local shown = {}
    for _, b in ipairs(w.palette) do if b:IsShown() and b.spell then shown[b.spell.name] = b.spell.rank end end
    ok(shown["Lightning Bolt"] == "Rank 2", "the hostile side's palette: your damage spells, at the top rank you have",
       tostring(shown["Lightning Bolt"]))
    ok(not shown["Healing Wave"], "and no heals on it")
    local function bodyRed()
        local v = w.mouseParts[1].t.__vertex
        return v and v[1] > v[3] * 2
    end
    ok(bodyRed(), "the whole mouse drawing is red on the hostile side, not only its little slots")
    BOOK[41], BOOK[42] = keepB1, keepB2
    w.tabs[2]:Click()
    ok(w:Key() == "harm:shift-", "a modifier tab on the hostile side is a hostile modifier")
    w.tabs[1]:Click()
    w:Refresh()
    ok(w.slots.right.empty:GetText() == "Purg" or w.slots.right.icon:IsShown(), "the hostile mouse shows what is on it")
    ok(not w.trinketTicks[1]:IsShown(), "no trinket ticks on the hostile side (they are a heal's)")
    w.sets[1]:Click()
    ok(w.set == "" and w.trinketTicks[1]:IsShown(), "back to the heal side: the ticks again")
    ok(not bodyRed(), "and the mouse is its own purple again")
    for _, s in ipairs(w.sets) do
        s:GetScript("OnEnter")(s)
        ok(s.lit == true and s.wash:GetAlpha() > 0, "the switch lights under the mouse")
        s:GetScript("OnLeave")(s)
        ok(not s.lit, "and goes out")
    end
    -- PVP TARGET CELLS get every bind too, when a bind changes (Grid.lua keeps them in FG.pvpCells)
    local extra = CreateFrame("Button", nil, UIParent, "SecureUnitButtonTemplate")
    extra:SetAttribute("unit", "party1target")
    local keepCells = FG.pvpCells
    FG.pvpCells = { extra }
    FM.Apply()
    ok(extra.__attrs["*spell1"] == "Healing Wave(Rank 3)" and extra.__attrs["*macro-harm2"] == "Purge it",
       "a PvP target cell carries the heal and hostile binds after a change")
    FG.pvpCells = keepCells
    -- A TEAM-TARGET CELL NEVER TURNS INTO "EVERY CLICK RESURRECTS" (the PvP helper's catch, 8 Nov): its token is
    -- whoever a teammate has targeted - a dead enemy player now, someone else in a second - so the dead-friend
    -- res, which is written once out of combat, has no place on it
    local keepUIP, keepBook = _G.UnitIsPlayer, BOOK[28]
    _G.UnitIsPlayer = function() return true end
    BOOK[28] = { name = "Ancestral Spirit", rank = "" }
    STATE.dead.party1 = true
    local control = CreateFrame("Button", nil, UIParent, "SecureUnitButtonTemplate")
    control:SetAttribute("unit", "party1")
    ok(FM.ResNow(control) == "Ancestral Spirit", "(control: an ordinary cell over a dead friend IS all-res)")
    local tc = FG.MakePvP(99, UIParent)
    tc:SetAttribute("unit", "party1")
    ok(FM.ResNow(tc) == nil, "a PvP target cell over a dead player is not made all-res")
    FM.ApplyTo(tc)
    ok(not tc.__res and tc.__attrs["*spell1"] ~= "Ancestral Spirit" and tc.__attrs["*type1"] ~= nil,
       "it keeps the binds", tostring(tc.__attrs["*spell1"]))
    STATE.dead.party1 = nil
    _G.UnitIsPlayer, BOOK[28] = keepUIP, keepBook
    for _, k in ipairs({ "harm:shift-right", "harm:middle", "harm:right", "button4" }) do NS.DB().binds[k] = nil end
    NS.DB().binds.left = wasLeft
    MACROS[7], MACROS[8] = nil, nil
    CURSOR = {}
    FM.Apply()
end

-- ============================================================== PVP MODE (8 Nov 2026)
-- Arn: "pvp mode, collums of 5 and you can see all of your teams targets in a small 1/4 side frame next
-- to your team so you can see what your whole team is targeting and can click them to cast harmful
-- spells" - the target cell NEXT TO EACH PERSON, same row. "put it in 1.0".
do
    local FG, FK = NS.FG, NS.FK
    local d = NS.DB()
    local keep = { raid = _G.IsInRaid, info = _G.GetRaidRosterInfo, gun = _G.GetUnitName, apply = NS.FM.ApplyTo,
                   un = _G.UnitName,
                   layout = d.layout, me = d.me, pvp = d.pvp, target = d.target, shown = d.shown }
    -- STATE.names[unit] answers when a test needs a real-looking name (the target cells' four letters)
    _G.UnitName = function(u)
        if STATE.names and u and STATE.names[u] ~= nil then return STATE.names[u] end
        return keep.un(u)
    end
    local function tick(s) s = s or 0.1 TICK(s) FG.anchor.__scripts.OnUpdate(FG.anchor, s) end
    local function at(f) local p = f and f.points[1] return p and p[4], p and p[5] end
    local function isSecret(v) return getmetatable(v) == secretMeta end
    d.layout, d.me, d.target, d.shown = "columns", false, false, true
    STATE.instance = nil

    -- THE SETTING: off for everyone - a new feature starts off, and nil reads off
    ok(d.pvp == "off", "pvp mode starts off, new install or old save", tostring(d.pvp))
    d.pvp = nil
    ok(FG.PvPMode and FG.PvPMode() == "off", "nil reads off")
    d.pvp = "off"

    -- (1) OFF = THE GRID EXACTLY AS IT WAS
    FG.Layout(FG.anchor)
    local function snap()
        local s = {}
        for i, f in ipairs(FG.frames) do
            if f.unit then local x, y = at(f) s[#s + 1] = f.unit .. "@" .. tostring(x) .. "," .. tostring(y) .. ":" .. tostring(f.__w) end
        end
        return table.concat(s, " ") .. " anchor " .. tostring(FG.anchor.__w) .. "x" .. tostring(FG.anchor.__h)
    end
    local before = snap()
    ok(FG.pvpCells and #FG.pvpCells == 0, "off: no target cells at all", FG.pvpCells and #FG.pvpCells)

    -- (2) "bg": only in a battleground or an arena
    ok(NS.DO.pvp and NS.DO.pvp("bg") == "bg" and d.pvp == "bg", "/bish pvp bg stores bg", tostring(d.pvp))
    ok(FG.PvPActive() == false, "bg in the open world: not active")
    ok(snap() == before and #FG.pvpCells == 0, "and the grid is laid out exactly as with pvp off", snap())
    STATE.instance = "party"
    ok(FG.PvPActive() == false, "bg in a dungeon: not active")
    STATE.instance = "raid"
    ok(FG.PvPActive() == false, "bg in a raid: not active")
    STATE.instance = "arena"
    ok(FG.PvPActive() == true, "bg in an arena: active")
    STATE.instance = "pvp"
    ok(FG.PvPActive() == true, "bg in a battleground: active")
    -- the client says so at PLAYER_ENTERING_WORLD; the grid lays out on its next tick
    fire(FG.events, "PLAYER_ENTERING_WORLD")
    tick()
    ok(#FG.pvpCells == 3, "inside the battleground, after the zone-in: one target cell per member", #FG.pvpCells)
    STATE.instance = nil
    fire(FG.events, "PLAYER_ENTERING_WORLD")
    tick()
    ok(#FG.pvpCells == 0 and snap() == before, "out again: gone, the grid as before")

    -- (3) "on" in a party: ONE COLUMN, a target cell beside each member, ApplyTo on every one
    local applied = {}
    NS.FM.ApplyTo = function(c, ...) applied[c] = (applied[c] or 0) + 1 return keep.apply(c, ...) end
    NS.DO.pvp("on")
    NS.FM.ApplyTo = keep.apply
    local W, PAD, H = FG.CELL_W, FG.CELL_PAD, FG.CELL_H + FG.NAME_BAND
    local SW = FG.PVP_W
    -- MORE SQUARE (Arn, 8 Nov: "double the size of it more square less rectagle"): half a member cell wide, so with
    -- the cell's height (the name band and all) it is about as wide as it is tall
    ok(SW == math.floor(W / 2), "a target cell is half a member cell's width", SW)
    ok(math.abs(SW - H) <= 6, "and close to square: " .. SW .. " x " .. H)
    ok(#FG.pvpCells == 3, "three members, three target cells", #FG.pvpCells)
    local want = { player = "target", party1 = "party1target", party2 = "party2target" }
    local allRight, allApplied, allWatched = true, true, true
    for _, f in ipairs(FG.frames) do
        if f.unit then
            local c = FG.pvpByUnit[f.unit]
            local fx, fy = at(f)
            local cx, cy = at(c)
            if not (c and c:GetAttribute("unit") == want[f.unit] and c.unit == want[f.unit]
                    and fx == 0 and cx == W + PAD and cy == fy and c.__w == SW and c.__h == f.__h) then
                allRight = false
            end
            if not (c and applied[c]) then allApplied = false end
            if not (c and WATCHED[c]) then allWatched = false end
        end
    end
    ok(allRight, "each target cell sits on its member's right, same row, same height, unit <member>target")
    -- THE WHOLE CELL IS THE HEALTH (Arn, 8 Nov live: "make the small window next to the friendly target be full red
    -- not just a small sliver at the bottom"): the bar runs from the cell's top-left to its bottom-right
    local tcell = FG.pvpCells[1]
    local corners = {}
    for _, p in ipairs(tcell.bar.points or {}) do corners[p[1]] = true end
    ok(corners.TOPLEFT and corners.BOTTOMRIGHT and tcell.bar.__h == nil,
       "a target cell's health fills the whole cell, not a sliver along its foot")
    ok(allApplied, "and every one was handed to FM.ApplyTo - the grid's own binds, hostile ones included")
    ok(allWatched, "and every one is under the client's unit watch")
    ok(FG.pvpCells[1] and FG.pvpCells[1].__kind == "Button" and FG.pvpCells[1].__scripts.OnEnter
       and FG.pvpCells[1].__scripts.OnEnter ~= nil, "a secure unit button, like the grid's cells")
    ok(FG.anchor.__w == W + PAD + SW, "the grid is one column of member + target wide", FG.anchor.__w)
    -- THE HEADER STOPS AT THE LAST PERSON (Arn, 8 Nov: "header is extra long" - it ran over the empty target room):
    -- the grid keeps the room (blocks beside it dock past it), the header bar does not
    local hp = FG.header and FG.header.points
    local right
    for _, p in ipairs(hp or {}) do if p[1] == "BOTTOMRIGHT" then right = p end end
    ok(right and right[4] == -(SW + PAD), "the header bar stops at the last cell, not over the target room",
       right and tostring(right[4]))

    -- the unit watch: an empty target hides by itself, even in a fight
    STATE.units.party1target = true
    STATE.inCombat = true
    WATCH_TICK()
    ok(FG.pvpByUnit.party1:IsShown() and not FG.pvpByUnit.party2:IsShown() and not FG.pvpByUnit.player:IsShown(),
       "in a fight the client shows party1's target cell (they have one) and hides the empty ones")
    STATE.inCombat = false

    -- (4) A RAID: COLUMNS OF 5, one per subgroup present, in group order
    local groupOf = {}
    for i = 1, 3 do groupOf[i] = 2 end          -- raid1-3 joined first, in group 2
    for i = 4, 8 do groupOf[i] = 1 end          -- raid4-8, group 1
    for i = 9, 12 do groupOf[i] = 4 end         -- raid9-12, group 4 (no group 3)
    for i = 1, 12 do STATE.units["raid" .. i] = true end
    _G.IsInRaid = function() return true end
    _G.GetRaidRosterInfo = function(i) return "n" .. i, 0, groupOf[i] end
    d.layout = "columns"                         -- "down", the default: columns of 5
    FG.Layout(FG.anchor)
    local stride = W + PAD + SW + PAD
    local colOK, rowsOK = true, true
    local colOf = { [1] = 0, [2] = 1, [4] = 2 }
    local deep = {}
    for i = 1, 12 do
        local f = FG.byUnit["raid" .. i]
        local c = FG.pvpByUnit["raid" .. i]
        local fx, fy = at(f)
        local cx, cy = at(c)
        local col = colOf[groupOf[i]]
        deep[col] = (deep[col] or 0) + 1
        if not (f and fx == col * stride and c and cx == col * stride + W + PAD and cy == fy
                and c:GetAttribute("unit") == "raid" .. i .. "target") then colOK = false end
    end
    for _, n in pairs(deep) do if n > 5 then rowsOK = false end end
    ok(colOK, "three groups, three columns in group order (1, 2, 4), each member's target cell on its right")
    ok(rowsOK and #FG.pvpCells == 12, "no column deeper than 5, twelve target cells", #FG.pvpCells)
    ok(FG.anchor.__w == 3 * stride - PAD and FG.anchor.__h == 5 * (H + PAD) - PAD,
       "the grid is three columns wide and five deep", tostring(FG.anchor.__w) .. "x" .. tostring(FG.anchor.__h))
    -- PVP MODE FOLLOWS YOUR LAYOUT (Arn, 8 Nov: forcing columns was "a little confusing ... what happens when people
    -- select down or tank"). Tanks (the pyramid) and across keep their shape; a target cell sits beside every
    -- person, and no target cell lies over the next person's cell
    local function besideAll(label)
        local okB, clear = true, true
        local spots = {}
        for i = 1, 12 do
            local f, c = FG.byUnit["raid" .. i], FG.pvpByUnit["raid" .. i]
            local fx, fy = at(f)
            local cx, cy = at(c)
            if not (f and c and cx == fx + f.__w + PAD and cy == fy and c.__h == f.__h) then okB = false end
            spots[#spots + 1] = { x = fx, y = fy, w = f.__w, h = f.__h }
            spots[#spots + 1] = { x = cx, y = cy, w = c.__w, h = c.__h }
        end
        for a = 1, #spots do for b = a + 1, #spots do
            local p, q = spots[a], spots[b]
            if p.x < q.x + q.w and q.x < p.x + p.w and p.y > q.y - q.h and q.y > p.y - p.h then clear = false end
        end end
        ok(okB, label .. ": every person's target cell on their right, as tall as them")
        ok(clear, label .. ": nothing lies over anything else")
    end
    d.layout = "pyramid"
    FG.Layout(FG.anchor)
    ok(FG.frames[1].__w == 2 * W + PAD and #FG.pvpCells == 12, "tanks with PvP on: still the pyramid (its apex two cells wide)",
       FG.frames[1].__w)
    besideAll("tanks")
    d.layout = "rows"
    FG.Layout(FG.anchor)
    local r1x, r1y = at(FG.byUnit["raid4"])
    local r2x, r2y = at(FG.byUnit["raid5"])
    ok(r1y == r2y and r2x == r1x + stride, "across with PvP on: a group is a row, each step leaves room for the target cell")
    besideAll("across")
    ok(FG.anchor.__w == 5 * stride - PAD, "and the grid is five people (and their targets) wide", FG.anchor.__w)
    d.layout = "pyramid"
    FG.Layout(FG.anchor)
    -- and off again, the pyramid is still the pyramid - with no room left for target cells
    NS.DO.pvp("off")
    ok(#FG.pvpCells == 0 and FG.pvpByUnit["raid1"] == nil, "off: the list is emptied")
    local hidden = true
    for _, c in ipairs(FG.pvpPool or {}) do if c:IsShown() or WATCHED[c] then hidden = false end end
    ok(hidden, "and every target cell is hidden and off the unit watch")
    ok(FG.frames[1].__w == 2 * W + PAD, "off again: the saved pyramid is back (its apex is two cells wide)",
       FG.frames[1].__w)
    d.layout = "columns"
    FG.Layout(FG.anchor)

    -- (5) IN A FIGHT A TARGET CELL'S UNIT IS NEVER RE-SET
    NS.DO.pvp("on")
    local sets, realSet = 0, {}
    for _, c in ipairs(FG.pvpCells) do
        local real = c.SetAttribute
        realSet[c] = real
        c.SetAttribute = function(self, k, v) if k == "unit" then sets = sets + 1 end return real(self, k, v) end
    end
    STATE.inCombat = true
    groupOf[1] = 3                               -- someone moves group mid-fight
    fire(FG.events, "GROUP_ROSTER_UPDATE")
    fire(FG.pvpEvents, "UNIT_TARGET", "raid2")
    for _ = 1, 5 do tick() end
    ok(FG.Layout(FG.anchor) == false, "layout is refused in a fight")
    ok(sets == 0, "and no target cell's unit attribute was touched in the fight", sets)
    STATE.inCombat = false
    groupOf[1] = 2
    for c, real in pairs(realSet) do c.SetAttribute = real end   -- back to the frame's own method
    FG.Layout(FG.anchor)

    -- (6) THE PAINT: secret health handed on untouched, red for a foe, green for a friend, a short name
    local c1 = FG.pvpByUnit.raid1
    STATE.units.raid1target = true
    STATE.hostile.raid1target = true
    STATE.names = { raid1target = "Gorehowl Bloodfist" }
    local painted, why = pcall(FG.PaintPvPCell, c1)
    ok(painted, "painting a target cell with secret health never throws", tostring(why))
    ok(isSecret(c1.bar.__value), "the health went to the bar untouched (a secret, as the client gave it)")
    ok(isSecret(c1.bar.__max), "and the max too")
    ok(c1.bar.__color and c1.bar.__color[1] == FG.HOSTILE[1] and c1.bar.__color[2] == FG.HOSTILE[2],
       "red for something you can attack")
    ok(c1.label and c1.label.__text == "Goreho", "six letters of the name, now the cell is wider: Goreho",
       c1.label and tostring(c1.label.__text))
    ok(c1.kickFx.__w == FG.KICK_SIZE and FG.KICK_SIZE == 20, "and a bigger interrupt icon to go with it", FG.KICK_SIZE)
    STATE.hostile.raid1target = nil
    FG.PaintPvPCell(c1)
    ok(c1.bar.__color and c1.bar.__color[1] == FG.PVP_FRIEND[1] and c1.bar.__color[2] == FG.PVP_FRIEND[2],
       "green for a friend")
    STATE.hostileSecret = true
    painted, why = pcall(FG.PaintPvPCell, c1)
    ok(painted and c1.bar.__color and isSecret(c1.bar.__color[1]),
       "in a fight 'can I attack it' is secret: the client picks the colour", tostring(why))
    STATE.hostileSecret = false
    local hidden1 = secretString()
    STATE.names.raid1target = hidden1
    painted = pcall(FG.PaintPvPCell, c1)
    ok(painted and c1.label.__text == hidden1, "a hidden name is handed to the label whole, never cut")
    -- NO "..." ON A HIDDEN NAME (Arn, 8 Nov, Wailing Caverns: "Deviat..."). A label pinned on both sides gets the
    -- client's dots when the text is wider; pinned on ONE side it is as wide as its text and the cell's own clip cuts
    -- it clean at the edge
    local lp = c1.label.__parent
    ok(lp and lp.__clips == true, "the name sits in a frame that clips at the cell's edge")
    ok(#(c1.label.points or {}) == 1 and c1.label.__justify == "LEFT",
       "a hidden name: pinned on one side only, so the client adds no dots", #(c1.label.points or {}))
    STATE.names.raid1target = "Gorehowl Bloodfist"
    FG.PaintPvPCell(c1)
    ok(#(c1.label.points or {}) == 2 and c1.label.__justify == "CENTER" and c1.label.__text == "Goreho",
       "a plain name again: six letters, centred as before", #(c1.label.points or {}))

    -- the hover POPS (wash + left bar) and the tooltip has the whole name
    _G.GetUnitName = function(u) return STATE.names and STATE.names[u] or "Name-" .. tostring(u) end
    c1.__scripts.OnEnter(c1)
    ok(c1.wash and c1.wash:IsShown() and c1.lbar and c1.lbar:IsShown(), "under the mouse the target cell pops")
    ok(c1.__wasMouseover, "and the secure template's own OnEnter still ran (hooked, not replaced)")
    local tipHas = false
    for _, l in ipairs(TIP.lines) do if l == "Gorehowl Bloodfist" then tipHas = true end end
    ok(tipHas, "the tooltip says the whole name", table.concat(TIP.lines, " / "))
    c1.__scripts.OnLeave(c1)
    ok(not c1.wash:IsShown() and not c1.lbar:IsShown(), "and goes back when the mouse leaves")
    _G.GetUnitName = keep.gun

    -- (7) THE TEAM'S FOCUS: the same enemy on 2+ target cells, and the most of any -> gold on each
    for i = 1, 12 do STATE.units["raid" .. i .. "target"] = true STATE.hostile["raid" .. i .. "target"] = true end
    for i = 1, 12 do STATE.guids["raid" .. i .. "target"] = "Player-9-" .. i end   -- everyone on someone else
    STATE.guids.raid1target, STATE.guids.raid5target, STATE.guids.raid9target = "Player-9-A", "Player-9-A", "Player-9-A"
    STATE.guids.raid2target, STATE.guids.raid6target = "Player-9-B", "Player-9-B"
    WATCH_TICK()
    FG.PaintPvP()
    local function gold(u) local c = FG.pvpByUnit[u] return c and c.focus and c.focus:IsShown() end
    ok(gold("raid1") and gold("raid5") and gold("raid9"), "three on the same enemy: gold on all three of its cells")
    ok(not gold("raid2") and not gold("raid6") and not gold("raid3"), "two on another: no gold - three is the most")
    ok(FG.pvpFocus == "Player-9-A", "the focus is that enemy", tostring(FG.pvpFocus))
    -- a SECRET GUID simply does not count
    STATE.guidSecret.raid9target, STATE.guidSecret.raid5target = true, true
    painted, why = pcall(FG.PaintPvP)
    ok(painted, "a secret GUID never throws", tostring(why))
    ok(gold("raid2") and gold("raid6") and not gold("raid1") and not gold("raid5") and not gold("raid9")
       and FG.pvpFocus == "Player-9-B",
       "two of A's three hidden: only one readable on A, two on B - B is the focus, the hidden ones count for nothing")
    STATE.guidSecret.raid9target, STATE.guidSecret.raid5target = nil, nil
    -- a tie is no focus, and a friend is never one
    STATE.guids.raid1target, STATE.guids.raid5target, STATE.guids.raid9target = "Player-9-C", "Player-9-C", "Player-9-X"
    FG.PaintPvP()
    ok(not gold("raid2") and not gold("raid1") and FG.pvpFocus == nil, "two on B, two on C: a tie, no gold")
    STATE.guids.raid1target, STATE.guids.raid5target = nil, nil
    STATE.hostile.raid2target, STATE.hostile.raid6target = nil, nil
    FG.PaintPvP()
    ok(not gold("raid2") and FG.pvpFocus == nil, "two healing the same friend: no gold, a friend is not a focus")
    STATE.hostile.raid2target, STATE.hostile.raid6target = true, true

    -- (8) UPDATES: UNIT_TARGET repaints that one cell; the 4-a-second repaint only while pvp is showing
    local hits = {}
    local realCell = FG.PaintPvPCell
    FG.PaintPvPCell = function(c, ...) hits[#hits + 1] = c return realCell(c, ...) end
    local function clear() local n = #hits for i = n, 1, -1 do hits[i] = nil end return n end
    ok(FG.pvpEvents and FG.pvpEvents.__events and FG.pvpEvents.__events.UNIT_TARGET
       and FG.pvpEvents.__events.PLAYER_TARGET_CHANGED, "while pvp mode shows, it listens for UNIT_TARGET")
    clear()
    fire(FG.pvpEvents, "UNIT_TARGET", "raid3")
    ok(#hits == 1 and hits[1] == FG.pvpByUnit.raid3, "raid3 changed target: raid3's target cell is repainted, alone", #hits)
    clear()
    fire(FG.pvpEvents, "UNIT_TARGET", secret())
    ok(#hits == 12, "a unit the client hides: every target cell, never a guess", #hits)
    clear()
    for _ = 1, 10 do tick() end
    local passes = clear() / 12
    ok(passes >= 3 and passes <= 5, "a second of ticks repaints the target cells about 4 times", passes)
    NS.DO.pvp("off")
    clear()
    for _ = 1, 10 do tick() end
    ok(#hits == 0, "pvp off: nothing repaints them, nothing ticks for them", #hits)
    ok(not (FG.pvpEvents.__events and FG.pvpEvents.__events.UNIT_TARGET), "and UNIT_TARGET is not even heard")
    FG.PaintPvPCell = realCell

    -- (8b) IS THEIR TARGET CASTING? (Arn, 8 Nov: "class appropriate interrupt icon and un alpha it when they are
    -- casting or channeling"). Forever hides WHAT another unit casts, not THAT it casts: the client hands a duration
    -- object for a cast in progress (UnitCastingDuration / UnitChannelDuration), nil for none - and that answer may
    -- itself come back secret, which still means "something is there". The stand-in: STATE.casting[token] = "cast" |
    -- "channel" | "secret".
    STATE.casting = {}
    _G.UnitCastingDuration = function(u)
        local c = STATE.casting[u]
        if c == "secret" then return secretString() end
        return c == "cast" and { duration = 1.5 } or nil
    end
    _G.UnitChannelDuration = function(u) return STATE.casting[u] == "channel" and { duration = 3 } or nil end
    local keepBook = BOOK[43]
    BOOK[43] = { name = "Earth Shock", rank = "Rank 1" }
    NS.FM.BookChanged()                         -- the client's SPELLS_CHANGED, as a trained spell brings it
    NS.DO.pvp("on")
    WATCH_TICK()
    local kc = FG.pvpByUnit.raid1 or FG.pvpCells[1]
    ok(kc and kc.kick, "a target cell carries an interrupt icon")
    ok(FG.KickSpell() == "Earth Shock", "a shaman's is Earth Shock (trained)", tostring(FG.KickSpell()))
    local tok = kc.unit
    STATE.hostile[tok] = true                       -- an enemy: the icon's work (a friend: below)
    -- CLICK IT TO INTERRUPT (Arn, 8 Nov: "yes make it clickable"): the icon is a secure button that casts your
    -- interrupt - its LOWEST trained rank, the cheapest, the interrupt is the same - at that teammate's target. The
    -- spell and the unit are written at layout, out of combat; in a fight the client does the casting.
    -- ENEMIES ONLY (Arn, 8 Nov: "show them but dont show the interrupt icon" on a friendly target): the cast rides the
    -- client's own hostile switch - harmbutton1 -> "kick" - so a click on a friend's cell casts nothing.
    local kb = kc.kickFx
    ok(kb.__template == "SecureActionButtonTemplate", "the icon is a secure button", tostring(kb.__template))
    ok(kb:GetAttribute("type") == nil and kb:GetAttribute("*harmbutton1") == "kick"
       and kb:GetAttribute("*type-kick") == "spell" and kb:GetAttribute("*spell-kick") == "Earth Shock(Rank 1)",
       "it casts Earth Shock, rank 1 - on an enemy only, through the client's hostile switch",
       tostring(kb:GetAttribute("*spell-kick")))
    ok(kb:GetAttribute("unit") == tok, "at that teammate's target", tostring(kb:GetAttribute("unit")))
    ok(kb.__mouse ~= false, "and it takes the click")
    -- THE BACKUP (Arn, 8 Nov: "if my earth shock is on cool down i can always click my grounding totem"): no Grounding
    -- Totem trained yet - no second icon, the interrupt alone in the middle
    ok(FG.BackupSpell() == nil and kc.kick2Fx and kc.kick2Fx:IsShown() == false, "no backup trained: no second icon")
    local keepBook44 = BOOK[44]
    BOOK[44] = { name = "Grounding Totem", rank = "" }
    NS.FM.BookChanged()
    FG.Layout(FG.anchor)
    kc = FG.pvpByUnit.raid1 or FG.pvpCells[1]
    tok = kc.unit
    kb = kc.kickFx
    local k2 = kc.kick2Fx
    ok(FG.BackupSpell() == "Grounding Totem", "a shaman's backup is Grounding Totem (trained)", tostring(FG.BackupSpell()))
    ok(k2:IsShown() ~= false and k2.__template == "SecureActionButtonTemplate" and k2:GetAttribute("*harmbutton1") == "kick2"
       and k2:GetAttribute("*type-kick2") == "spell" and k2:GetAttribute("*spell-kick2") == "Grounding Totem"
       and k2:GetAttribute("unit") == tok,
       "a second secure icon beside it casts Grounding Totem - an enemy's cell only, like the first",
       tostring(k2:GetAttribute("*spell-kick2")))
    ok(k2:GetParent() == kb, "it rides the first icon's frame: shown, hidden and bounced with it")
    local mainOff
    for _, p in ipairs(kb.points or {}) do if p[1] == "BOTTOM" then mainOff = p[4] end end
    ok(mainOff and mainOff < 0, "the pair is centred: the interrupt steps left to make room", tostring(mainOff))
    ok(kc.kick2Cd and kc.kick2Cd.__kind == "Cooldown", "the backup carries its own cooldown sweep")
    -- ITS COOLDOWN SHOWS (Arn, 8 Nov: "right now i interuppt bit it still looks like i can click it again ... no cooldown
    -- indicator"): a sweep over the icon, run by the client from a duration object it hands us for our own spell -
    -- never a number read. Asked when the client says a cooldown changed (SPELL_UPDATE_COOLDOWN), only while PvP shows.
    local durAsked, durObj = {}, { duration = 12 }
    local keepDur = _G.C_Spell.GetSpellCooldownDuration
    _G.C_Spell.GetSpellCooldownDuration = function(s) durAsked[#durAsked + 1] = s return durObj end
    ok(kc.kickCd and kc.kickCd.__kind == "Cooldown", "the icon carries a cooldown sweep")
    local ev = FG.pvpEvents
    ok(ev and ev.__events and ev.__events.SPELL_UPDATE_COOLDOWN, "PvP mode listens for cooldown changes while it shows")
    ev.__scripts.OnEvent(ev, "SPELL_UPDATE_COOLDOWN")
    ok(durAsked[1] == "Earth Shock" and kc.kickCd.__durObj == durObj,
       "your interrupt's cooldown handed to the sweep as the client gave it", tostring(durAsked[1]))
    ok(durAsked[2] == "Grounding Totem" and kc.kick2Cd.__durObj == durObj,
       "and the backup's to its own sweep - which one is ready is the client's to show", tostring(durAsked[2]))
    local hiddenObj = secretString()
    _G.C_Spell.GetSpellCooldownDuration = function() return hiddenObj end
    ok(pcall(ev.__scripts.OnEvent, ev, "SPELL_UPDATE_COOLDOWN") and kc.kickCd.__durObj == hiddenObj,
       "a hidden answer is handed on untouched, never tested")
    _G.C_Spell.GetSpellCooldownDuration = keepDur
    STATE.casting[tok] = "cast"
    FG.PaintPvPCell(kc)
    kc.kickGlow:Hide()
    kb.__scripts.OnEnter(kb)
    ok(kc.kickGlow:IsShown(), "shown (a cast), under the mouse it lights (the family rule)")
    kb.__scripts.OnLeave(kb)
    STATE.casting[tok] = nil
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha == 0 and kc.kickFx.__alpha == 0,
       "their target not casting: the icons are HIDDEN (Arn, 8 Nov: 'hidden till needed')", tostring(kc.kickFx.__alpha))
    kb.__scripts.OnEnter(kb)
    ok(not kc.kickGlow:IsShown(), "and the mouse over the hidden spot lights nothing")
    kb.__scripts.OnLeave(kb)
    ok(kc.kickFx and not kc.kickGlow:IsShown() and not (kc.kickBounce and kc.kickBounce:IsPlaying()),
       "at rest: no glow, no bounce")
    STATE.casting[tok] = "cast"
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha == 1 and kc.kickFx.__alpha == 1, "casting: the icons show, at full strength")
    -- AND IT MOVES (Arn, 8 Nov: "can it also add a glow or bounce animation"): a gold glow behind it, and the icon
    -- bouncing - the client runs the bounce itself; nothing of ours ticks for it
    ok(kc.kickGlow:IsShown(), "casting: a glow behind the icon")
    local bounce = kc.kickBounce
    local grows = bounce and bounce.anims[1] and bounce.anims[1].kind == "Scale" and bounce.anims[1].scaleTo
                  and bounce.anims[1].scaleTo[1] > 1
    ok(bounce and bounce:IsPlaying() and bounce.looping == "REPEAT" and grows, "and it bounces, over and over")
    FG.PaintPvPCell(kc)
    ok(bounce:IsPlaying(), "a repaint mid-cast leaves the bounce going (it is not restarted every quarter second)")
    STATE.casting[tok] = "channel"
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha == 1, "channelling: full strength too")
    STATE.casting[tok] = "secret"
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha == 1, "a hidden answer still means a cast is there: full strength")
    STATE.casting[tok] = nil
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha < 0.5, "the cast over: dim again")
    ok(not kc.kickGlow:IsShown() and not kc.kickBounce:IsPlaying(), "and the glow and the bounce stop")
    -- A FRIEND: the cell stays (heal who they are on), the icon goes - and their casts do not light it
    STATE.hostile[tok] = nil
    STATE.casting[tok] = "cast"
    local castAsks = 0
    local realCD = _G.UnitCastingDuration
    _G.UnitCastingDuration = function(...) castAsks = castAsks + 1 return realCD(...) end
    FG.PaintPvPCell(kc)
    _G.UnitCastingDuration = realCD
    ok(kc:IsShown() ~= false and kc.kick.__alpha == 0 and not kc.kickGlow:IsShown() and not kc.kickBounce:IsPlaying(),
       "a friendly target: the cell stays, no interrupt icon, and their cast lights nothing", tostring(kc.kick.__alpha))
    ok(castAsks == 0, "and a friend's casting is not even asked")
    kc.kickFx.__scripts.OnEnter(kc.kickFx)
    ok(not kc.kickGlow:IsShown(), "the mouse over a friend's cell lights no icon")
    kc.kickFx.__scripts.OnLeave(kc.kickFx)
    STATE.hostile[tok] = true
    FG.PaintPvPCell(kc)
    ok(kc.kick.__alpha == 1 and kc.kickGlow:IsShown(), "an enemy again, casting: the icon is back and lit")
    STATE.casting[tok] = nil
    FG.PaintPvPCell(kc)
    -- GLOW, BOUNCE OR BOTH - THE PLAYER'S PICK (Arn, 8 Nov: "lets make it an option for them glow or bounce").
    -- "both" by default (what it did first); a pick applies at once, mid-cast too.
    ok(FG.KickFx() == "both", "the cast alert is glow and bounce by default", FG.KickFx())
    local fxRow
    for _, o in ipairs(NS.UI.Rows()) do if o.key == "kickfx" then fxRow = o end end
    ok(fxRow and fxRow.kind == "seg" and table.concat(fxRow.values, ",") == "glow,bounce,both" and fxRow.help,
       "the options window has a cast alert row: glow, bounce, both")
    STATE.casting[tok] = "cast"
    fxRow.set(NS.DB(), "glow")
    FG.PaintPvPCell(kc)
    ok(kc.kickGlow:IsShown() and not kc.kickBounce:IsPlaying(), "glow: the glow alone")
    fxRow.set(NS.DB(), "bounce")
    ok(not kc.kickGlow:IsShown() and kc.kickBounce:IsPlaying(), "bounce, picked mid-cast: the bounce alone, at once")
    kc.kickFx.__scripts.OnEnter(kc.kickFx)
    kc.kickFx.__scripts.OnLeave(kc.kickFx)
    ok(not kc.kickGlow:IsShown() and kc.kickBounce:IsPlaying(), "the mouse passing over it leaves no glow behind in bounce")
    fxRow.set(NS.DB(), "both")
    ok(kc.kickGlow:IsShown() and kc.kickBounce:IsPlaying() and fxRow.get(NS.DB()) == "both", "both: the two together")
    STATE.casting[tok] = nil
    FG.PaintPvPCell(kc)
    BOOK[43] = keepBook
    NS.FM.BookChanged()
    FG.kickSpell = nil
    ok(FG.KickSpell() == nil and FG.KickIcon() == FG.KICK_FALLBACK, "no interrupt trained: the plain kick icon")
    FG.Layout(FG.anchor)
    local kc2 = FG.pvpCells[1]
    ok(kc2 and kc2.kickFx:GetAttribute("*type-kick") == nil and kc2.kickFx.__mouse == false,
       "and nothing to cast: the icon lets the click through to the cell's own binds")
    ok(kc2.kick2Fx:IsShown() == false and kc2.kick2Fx:GetAttribute("*type-kick2") == nil,
       "and no backup beside an interrupt you do not have")
    BOOK[44] = keepBook44
    NS.FM.BookChanged()
    FG.backupSpell = nil
    NS.DO.pvp("off")

    -- (9) THE COST of one repaint pass over a 40-man where everyone has a target
    local Cost = dofile("../_bisdev/dev/cost.lua")
    for i = 1, 40 do
        STATE.units["raid" .. i] = true
        STATE.units["raid" .. i .. "target"] = true
        STATE.hostile["raid" .. i .. "target"] = true
        groupOf[i] = math.floor((i - 1) / 5) + 1
    end
    NS.DO.pvp("on")
    WATCH_TICK()
    ok(#FG.pvpCells == 40, "40 in the raid, 40 target cells", #FG.pvpCells)
    local n, by = Cost.Count(function() FG.PaintPvP() end)
    STATE.costPvP = n
    -- THE BUDGET, a little above what was measured on 8 Nov: 320 for one pass over 40 shown target cells
    -- (8 a cell: max, health, can-attack, name, GUID and three hidden-checks). Four a second while pvp
    -- mode shows - about 1,300 a second in a full 40 - and nothing at all when it does not.
    -- 8 Nov (the interrupt icon): +2 a cell - "is their target casting / channelling" (FG.Casting, no hidden-check:
    -- type() reads nothing) - 400 measured, so 440. About 1,600 a second in a full 40 while it shows.
    local PVP = 440
    ok(n <= PVP, "one repaint pass of a 40-man's target cells asks the client at most " .. PVP .. " things: " .. n,
       Cost.Top(by, 6))
    print(("   cost: pvp target cells, 40-man pass = %d calls (%s)"):format(n, Cost.Top(by, 4)))

    -- (10) THE OPTIONS ROW and the words
    local row
    for _, o in ipairs(NS.UI.Rows()) do if o.key == "pvp" then row = o end end
    ok(row and row.kind == "seg" and table.concat(row.values, ",") == "off,bg,on" and row.help,
       "the options window has a PvP row: off, bg, on - with its help")
    if row then
        row.set(d, "bg")
        ok(d.pvp == "bg" and row.get(d) == "bg", "picking bg stores bg")
        row.set(d, "off")
        ok(d.pvp == "off" and row.get(d) == "off", "and off")
    end
    SlashCmdList.BISHEALING("pvp on")
    ok(d.pvp == "on", "/bish pvp on", tostring(d.pvp))
    SlashCmdList.BISHEALING("pvpmode bg")
    ok(d.pvp == "bg", "/bish pvpmode bg (the long word)", tostring(d.pvp))
    SlashCmdList.BISHEALING("pvp off")
    ok(d.pvp == "off", "/bish pvp off")
    ok(NS.SHORT.pvpmode == "pvp", "the short word is pvp")
    local status = NS.CFG.Status()
    ok(status:find("PvP off", 1, true), "the BiS> page's status line says PvP off", status)

    -- (11) IT RIDES THE MACRO, the one thing this client always hands back
    local body = FK.Encode({ left = "Healing Wave(Rank 2)" }, { pvp = "on" })
    local _, back = FK.Decode(asTheClientStoresIt(body))
    ok(back and back.pvp == "on", "pvp on rides the macro and reads back", body)
    _, back = FK.Decode(asTheClientStoresIt(FK.Encode({ left = "Healing Wave(Rank 2)" }, { pvp = "bg" })))
    ok(back and back.pvp == "bg", "and bg")
    ok(not FK.Encode({}, { pvp = "off" }):find("PV=", 1, true), "off, the default, writes nothing")

    -- (12) THE COLD START: a login with pvp = "on" saved, no user action -> the target cells are there
    NS.DO.pvp("off")
    ok(#FG.pvpCells == 0, "(nothing laid out before the login)")
    local keepDB, keepChar = _G.BiSHealingDB, _G.BiSHealingCharDB
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
    _G.BiSHealingDB = { dbver = NS.DBVER, owner = NS.Me(), savedAt = 1, forever10 = true, shown = true,
                        pvp = "on", binds = { left = "Healing Wave(Rank 2)" }, bindsSeeded = true }
    _G.BiSHealingCharDB = nil
    fire(NS.events, "ADDON_LOADED", "BiSHealing")
    fire(NS.events, "PLAYER_LOGIN")
    fire(FG.events, "PLAYER_ENTERING_WORLD")     -- what the client always says after the login
    tick()
    _G.DEFAULT_CHAT_FRAME = realChat
    ok(NS.DB().pvp == "on" and #FG.pvpCells == 40 and FG.pvpByUnit.raid7
       and FG.pvpByUnit.raid7:GetAttribute("unit") == "raid7target",
       "LIVE after a login with pvp on saved: 40 target cells laid out, nobody clicked anything", #FG.pvpCells)
    ok(FG.pvpEvents.__events and FG.pvpEvents.__events.UNIT_TARGET, "and listening")
    -- the client lost the file: the macro brings it back (Keep, the road the mouse already takes)
    NS.DB().pvp = "off"
    FG.Layout(FG.anchor)
    local keptMacros = {}
    for i, m in pairs(MACROS) do keptMacros[i] = m end
    for i in pairs(MACROS) do MACROS[i] = nil end
    MACROS[121] = { name = "BiSHealing", icon = 134400,
                    body = asTheClientStoresIt(FK.Encode({ left = "Healing Wave(Rank 2)" }, { pvp = "on" })) }
    FK.Load()
    ok(NS.DB().pvp == "on" and #FG.pvpCells == 40, "a macro that says pvp on: restored and laid out", #FG.pvpCells)
    for i in pairs(MACROS) do MACROS[i] = nil end
    for i, m in pairs(keptMacros) do MACROS[i] = m end
    _G.BiSHealingDB, _G.BiSHealingCharDB = keepDB, keepChar
    fire(NS.events, "ADDON_LOADED", "BiSHealing")

    -- put the world back
    d = NS.DB()
    d.pvp, d.layout, d.me, d.target, d.shown = "off", keep.layout, keep.me, keep.target, keep.shown
    for i = 1, 40 do
        STATE.units["raid" .. i] = nil
        STATE.units["raid" .. i .. "target"] = nil
        STATE.hostile["raid" .. i .. "target"] = nil
        STATE.guids["raid" .. i .. "target"] = nil
    end
    STATE.units.party1target, STATE.names, STATE.instance = nil, nil, nil
    _G.IsInRaid, _G.GetRaidRosterInfo, _G.UnitName = keep.raid, keep.info, keep.un
    FG.Layout(FG.anchor)
end

-- THE SECRET ALPHA (Arn 8 Nov: "want to work on a secret alpha testing on bis healing" - a hidden switch in the
-- release): off for everyone, never in /bish help or the options, on for a tester who types it; features one by one
do
    local d = NS.DB()
    local heard = {}
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    local function said(word) for _, t in ipairs(heard) do if tostring(t):find(word, 1, true) then return true end end end
    ok(d.alpha == nil and NS.AlphaOn() == false, "the alpha starts off - the release as everyone has it")
    NS.DO.help()
    ok(not said("alpha"), "/bish help never mentions it")
    local inRows = false
    for _, o in ipairs(NS.UI.Rows()) do if tostring(o.key):find("alpha") or tostring(o.label or ""):lower():find("alpha") then inRows = true end end
    ok(not inRows, "and neither does the options window")
    heard = {}
    ok(NS.AlphaHello() == false and #heard == 0, "off: nothing at login")

    local f1 = NS.AlphaFeature{ key = "Probe", name = "the probe", desc = "try it" }
    ok(f1 and f1.key == "probe" and NS.ALPHA.probe and not NS.AlphaOn("probe"), "a test feature registers, off with the switch")
    SlashCmdList.BISHEALING("alpha")
    ok(said("alpha testing: off") and said("the probe"), "/bish alpha: the state and what is in it")
    heard = {}
    SlashCmdList.BISHEALING("alpha on")
    ok(d.alpha == true and NS.AlphaOn() and NS.AlphaOn("probe") and said("thank you for testing"), "/bish alpha on: on, every feature with it")
    heard = {}
    ok(NS.AlphaHello() and said("alpha testing is on") and said(#NS.ALPHA_ORDER .. " test feature"), "on: one line at login, so a tester never forgets")
    SlashCmdList.BISHEALING("alpha probe off")
    ok(NS.AlphaOn() and not NS.AlphaOn("probe") and d.alphaOff.probe == true, "/bish alpha probe off: that one back, the switch still on")
    SlashCmdList.BISHEALING("alpha probe on")
    ok(NS.AlphaOn("probe") and d.alphaOff.probe == nil, "and on again")
    ok(not NS.AlphaOn("nothing"), "a feature that does not exist is never on")
    heard = {}
    SlashCmdList.BISHEALING("alpha nothing on")
    ok(said("no test feature called nothing"), "a wrong name says so")
    SlashCmdList.BISHEALING("alpha off")
    ok(d.alpha == nil and not NS.AlphaOn("probe"), "/bish alpha off: the release again")
    NS.ALPHA.probe = nil
    for i, k in ipairs(NS.ALPHA_ORDER) do if k == "probe" then table.remove(NS.ALPHA_ORDER, i) break end end
    d.alphaOff = nil
    _G.DEFAULT_CHAT_FRAME = realChat
end

-- THE RADAR (Arn 8 Nov: "make a radar that hides everything and only lights up when it needs to be clicked" ...
-- "Build it"; then "raid sectors next"). The secret alpha's first feature.
do
    local RD = NS.RD
    local d = NS.DB()
    local keep = { CU = _G.C_CurveUtil, CC = _G.CreateColor, E = _G.Enum, HP = _G.UnitHealthPercent, PP = _G.UnitPowerPercent,
                   raid = _G.IsInRaid, num = _G.GetNumGroupMembers, info = _G.GetRaidRosterInfo, isu = _G.UnitIsUnit,
                   cast = _G.UnitCastingDuration, chan = _G.UnitChannelDuration, b43 = BOOK[43], b44 = BOOK[44], b45 = BOOK[45] }
    -- THE CLIENT'S CURVES, as it evaluates them: a colour curve is points; the health fraction is the client's alone
    -- (STATE.hp, never handed to the addon); the answer is a colour object whose numbers only a texture takes
    STATE.hp = {}
    _G.Enum = { LuaCurveType = { Step = "step", Linear = "linear" } }
    _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    _G.C_CurveUtil = { EvaluateColorValueFromBoolean = keep.CU.EvaluateColorValueFromBoolean, CreateColorCurve = function()
        local c = { points = {} }
        function c:SetType(t) self.type = t end
        function c:AddPoint(x, col) self.points[#self.points + 1] = { x = x, col = col } end
        return c
    end }
    local function evaluate(curve, x)
        local p = curve.points
        table.sort(p, function(a, b) return a.x < b.x end)
        if x <= p[1].x then return p[1].col end
        for i = 2, #p do
            if x <= p[i].x then
                local a, b = p[i - 1], p[i]
                local t = (x - a.x) / math.max(1e-9, b.x - a.x)
                local function mix(k) return a.col[k] + (b.col[k] - a.col[k]) * t end
                return { r = mix("r"), g = mix("g"), b = mix("b"), a = mix("a") }
            end
        end
        return p[#p].col
    end
    local function colourOut(c) return { GetRGBA = function() return c.r, c.g, c.b, c.a end } end
    _G.UnitHealthPercent = function(u, predicted, curve)
        if type(curve) ~= "table" or not curve.points then return secret() end
        return colourOut(evaluate(curve, STATE.hp[u] or 1))
    end
    STATE.mana = 1
    _G.UnitPowerPercent = function(u, p, predicted, curve)
        if type(curve) == "table" and curve.points then return colourOut(evaluate(curve, STATE.mana)) end
        return secret()
    end
    STATE.casting = {}
    _G.UnitCastingDuration = function(u) return STATE.casting[u] and { duration = 1 } or nil end
    _G.UnitChannelDuration = function() return nil end
    BOOK[43] = { name = "Earth Shock", rank = "Rank 1" }
    BOOK[44] = { name = "Cure Poison", rank = "" }
    BOOK[45] = { name = "Cure Disease", rank = "" }
    NS.FM.BookChanged()
    if NS.FG then NS.FG.kickSpell = nil end
    STATE.inCombat = false
    STATE.units.party1, STATE.units.party2 = true, true

    local keepShown = d.shown
    d.shown = true                                   -- the grid ON, so its giving way is seen
    local shownBefore = d.shown
    -- THE LOOK ALONE DECIDES (11 Nov 2026): classic = no radar; the old alpha switch moves a player to the dashboard ONCE
    SlashCmdList.BISHEALING("alpha off")
    d.look, d.dash1 = "classic", nil
    RD.Apply()
    ok(RD and not RD.Active() and NS.ALPHA.radar, "the classic look: no radar")
    SlashCmdList.BISHEALING("alpha on")
    local f = _G.BiSHealingRadar
    ok(RD.Active() and f and f:IsShown() and d.look == "radar" and d.dash1 == true,
       "the old alpha radar switch, the first time: moved to the radar look once - the radar comes up")
    -- THE WHEEL STAYS ARMED WITH THE GRID HIDDEN (Arn 8 Nov, radar on: "when i tried to do my heals on the ellesmere
    -- frames my binds used to work on that"): the wheel is a mouseover BINDING over any addon's frames; a layout with the
    -- grid hidden used to return before arming it, so a reload left it dead
    local keepBinds = d.binds
    d.binds = { ["wheelup"] = "Healing Wave(Rank 1)" }
    BOUND = {}
    NS.FG.Layout(NS.FG.anchor)
    ok(NS.FG.Hidden() and BOUND.MOUSEWHEELUP ~= nil, "the grid hidden behind the radar, a fresh layout: the wheel bind is armed",
       tostring(BOUND.MOUSEWHEELUP))
    d.binds = keepBinds
    NS.FG.Layout(NS.FG.anchor)
    ok(NS.FG.Hidden() and d.shown == shownBefore, "and the grid gives way - its own `shown` switch untouched", tostring(d.shown))
    local sp1, sp2 = RD.spokes[1], RD.spokes[2]
    ok(#RD.slots == 5 and sp1.unit == "player" and sp2.unit == "party1" and RD.spokes[3].unit == "party2" and RD.spokes[4].unit == nil,
       "a party: five spokes - you, party1, party2, and two empty")
    -- THE PETS (Arn 9 Nov: "lets add pets small too to rader"): a small pip beside each owner, the client's watch on it
    do
        local p1, p2, p4 = sp1.pet, sp2.pet, RD.spokes[4].pet
        ok(p1 and p2 and p1:GetAttribute("unit") == "pet" and p2:GetAttribute("unit") == "partypet1",
           "each teammate's pet on its own small pip: yours is 'pet', party1's 'partypet1'", p2 and p2:GetAttribute("unit"))
        ok(WATCHED[p1] and WATCHED[p2], "the client's unit watch shows them only while the pet is there (mid-fight too)")
        ok(p4 and not WATCHED[p4] and p4:GetAttribute("unit") == nil and not p4:IsShown(),
           "an empty spot has no pet pip: off the watch, hidden")
        ok(p2:GetAttribute("type1") == nil and p2.__guard == true and p2:GetAttribute("*type1") == sp2.heal:GetAttribute("*type1")
           and p2:GetAttribute("*macrotext1") == sp2.heal:GetAttribute("*macrotext1"),
           "a pet's clicks are your binds, like on its owner (guarded)", p2:GetAttribute("*macrotext1"))
        ok(p2.__w == RD.PET.px and p2.__w < sp2.slot.ph, "small: smaller than its owner's pip", p2.__w)
        local pp = p2.points and p2.points[1]
        local hx, hy = RD.Point(sp2.slot, sp2.slot.rh)
        local d2 = pp and math.sqrt((pp[4] - hx) ^ 2 + (pp[5] - hy) ^ 2)
        ok(d2 and d2 >= (sp2.slot.ph + RD.PET.px) / 2 and d2 < 40, "beside its owner, never on top of it", d2)
        local mp = p1.points and p1.points[1]
        ok(mp and math.abs(mp[4]) < 0.01 and mp[5] < 0, "your own pet just below you in the middle", mp and mp[5])
        -- no pet pip on top of any person's, cure or bogey
        local clash = 0
        for _, sp in ipairs(RD.spokes) do
            local q = sp.pet.points and sp.pet.points[1]
            if sp.petUnit and q then
                for _, other in ipairs(RD.spokes) do
                    local s = other.slot
                    for _, spot in ipairs({ { s.rh, s.ph }, { s.rc, s.pc }, { s.rb, s.pb } }) do
                        if spot[1] then
                            local x, y = RD.Point(s, spot[1])
                            if math.abs(q[4] - x) < (RD.PET.px + spot[2]) / 2 - 1 and math.abs(q[5] - y) < (RD.PET.px + spot[2]) / 2 - 1 then clash = clash + 1 end
                        end
                    end
                end
            end
        end
        ok(clash == 0, "no pet pip sits on a person, a cure or a bogey", clash)
        -- lit like a person: the pet's health, through the curve; nothing there = nothing drawn
        STATE.units.partypet1 = true
        ok(pcall(fire, RD.events, "UNIT_HEALTH", "partypet1") and p2.face:GetAlpha() == 1 and RD.PaintPet(sp2),
           "the pet's health changed: its pip is painted by the client's curve")
        STATE.units.partypet1 = false
        ok(pcall(fire, RD.events, "UNIT_PET", "party1") and p2.face:GetAlpha() == 0, "the pet sent away: nothing at its spot")
        STATE.units.partypet1 = nil
        ok(#sp2.petTex == 5, "its sign: a paw - a pad and four toes, our own shape")
    end
    -- YOUR BINDS ARE THE CLICKS (Arn, 10 Nov: "did we set a heal to left click? if we did get rid of it and lets whatever
    -- binds set as the heal"): no plain type1 of the radar's own; the bind window's left button is the left click
    do
    ok(sp2.heal:GetAttribute("unit") == "party1" and sp2.heal:GetAttribute("type1") == nil and sp2.heal:GetAttribute("macrotext1") == nil
       and sp2.heal:GetAttribute("spell1") == nil, "no left-click heal of the radar's own any more")
    -- NEVER A HEAL ON YOU BY ACCIDENT (Arn, 10 Nov: a dead man's red sword healed him): a bound spell on a pip is guarded -
    -- help,nodead - so a dead or hostile target casts nothing instead of the client's self-cast; a dead man's pip is dark
    local keepL = d.binds
    d.binds = { ["left"] = "Healing Wave(Rank 1)" }
    NS.FM.Apply()
    ok(sp2.heal:GetAttribute("*type1") == "macro" and sp2.heal:GetAttribute("type1") == nil
       and sp2.heal:GetAttribute("*macrotext1") == "/cast [@mouseover,help,nodead] Healing Wave(Rank 1)" and sp2.heal:GetAttribute("*spell1") == nil,
       "the left bind is the left click, guarded: only on the living and friendly", sp2.heal:GetAttribute("*macrotext1"))
    d.binds = keepL
    NS.FM.Apply()
    end
    ok(NS.FG.frames[1] and NS.FG.frames[1].__guard == nil, "the grid's cells keep their plain spells (only the radar is guarded)")
    do
        local keepB = d.binds
        d.binds = { ["shift-left"] = "Lesser Healing Wave(Rank 2)" }
        NS.FM.Apply()
        ok(sp2.heal:GetAttribute("shift-macrotext1") == "/cast [@mouseover,help,nodead] Lesser Healing Wave(Rank 2)"
           and sp2.heal:GetAttribute("*type1") == "target", "a bind changed: the pips take it at once (FM.Apply), an empty left button targets",
           sp2.heal:GetAttribute("shift-macrotext1"))
        d.binds = keepB
        NS.FM.Apply()
    end
    do
        local realDead = _G.UnitIsDeadOrGhost
        _G.UnitIsDeadOrGhost = function(u) return u == "party1" end
        ok(RD.PaintHeal(sp2) == false and sp2.heal.face:GetAlpha() == 0, "party1 dead: the pip goes dark")
        _G.UnitIsDeadOrGhost = function() return secret() end
        RD.PaintHeal(sp2)
        ok(sp2.heal.face.__alphaFromSecret == true,
           "in a fight the answer is a secret: it goes to the client, never into an if")
        _G.UnitIsDeadOrGhost = realDead
        RD.PaintHeal(sp2)
    end
    -- THE RES on the right rail (Arn, 10 Nov: "Out of combat right rail let's put the resurrection module where it chooses
    -- the best person to res always lights up when someone is dead if they are out of range it'll say so or los it'll say
    -- so"): BiS> now's pick, a click on the dead only, RANGE asked of the client, LOS from a failed cast; dark in a fight
    do
        local b = RD.res
        local keep = { spell = NS.FM.ResSpell, target = NS.FN.ResTarget, range = C_Spell.IsSpellInRange, name = _G.GetUnitName }
        local who, inRange = nil, true
        NS.FM.ResSpell = function() return "Ancestral Spirit" end
        NS.FN.ResTarget = function() return who end
        C_Spell.IsSpellInRange = function() return inRange end
        _G.GetUnitName = function(u) return u == "party1" and "Legaian Stormhoof" or keep.name(u) end
        ok(b and b.rail == RD.defRail and b.word, "the res sits on the right rail, a word under it")
        ok(RD.ArmRes() == nil and b.face:GetAlpha() == 0 and b:GetAttribute("*macrotext1") == nil,
           "nobody dead: dark, no click armed")
        RD.ArmChaff()
        ok(RD.defRail:IsShown(), "the right rail shows while you know a res")
        who = "party1"
        ok(RD.ArmRes() == "party1" and b.face:GetAlpha() == 1, "someone dead: it lights")
        ok(b:GetAttribute("*type1") == "macro" and b:GetAttribute("*macrotext1") == "/cast [@party1,help] Ancestral Spirit",
           "the click: the res on that friend, released or not", b:GetAttribute("*macrotext1"))
        ok(b.tip and b.tip[1] == "RES: Legaian Stormhoof", "the name under the mouse only (no words on the scope)", b.tip and b.tip[1])
        ok(b.word.__res == "", "in range: no word")
        inRange = false
        ok(RD.PaintResWord() == "RANGE", "too far: RANGE, from the client")
        local okC, Cost = pcall(dofile, "../_bisdev/dev/cost.lua")
        if not okC then okC, Cost = pcall(dofile, "../../_bisdev/dev/cost.lua") end
        if okC then
            local n = Cost.Count(function() for _ = 1, 10 do RD.PaintResWord() end end)
            print(("   cost: res word, 10 ticks with someone dead = %d calls"):format(n))
            ok(n <= 30, "a tick with someone dead: a range question and the clock, nothing more", n)
        end
        local losMsg
        for k, v in pairs(RD.ClickWords()) do if v == "LOS" then losMsg = k break end end
        RD.overRes = true
        ok(RD.HeardError(losMsg) == "LOS" and b.word.__res == "LOS", "a res that fails on line of sight: LOS")
        TICK(RD.RES_LOS + 0.5)
        ok(RD.PaintResWord() == "RANGE", "and after a while back to what the client says")
        RD.overRes = nil
        inRange = true
        fire(RD.events, "PLAYER_REGEN_DISABLED")
        ok(b.face:GetAlpha() == 0 and b:GetAttribute("*macrotext1") == nil and b.word.__res == "",
           "a fight: dark, no click left armed")
        fire(RD.events, "PLAYER_REGEN_ENABLED")
        ok(RD.resDirty == true, "the fight's end: asked again at the next tick")
        RD.ArmRes()
        ok(b.face:GetAlpha() == 1, "and lit again for whoever died in it")
        who = nil
        RD.ArmRes()
        ok(b.face:GetAlpha() == 0 and b:GetAttribute("*macrotext1") == nil, "they stood up: dark again")
        NS.FM.ResSpell, NS.FN.ResTarget, C_Spell.IsSpellInRange, _G.GetUnitName = keep.spell, keep.target, keep.range, keep.name
        RD.ArmRes()
        RD.ArmChaff()
    end
    -- THE ENGINEER'S CONSOLE (Arn, 10 Nov: "we just show empty squares top row party. next row dispels, next row interrupts,
    -- next row pets, next row everything else ... all they do is the smart light up"): the same secure buttons on a grid
    do
        local d = NS.DB()
        local f, b = RD.frame, RD.viewBtn
        local keepView = d.radar.view
        local W0 = f:GetWidth()
        ok(b and b:GetParent() == f and not RD.Console(), "a view button, the radar to start with")
        local bp = b.points[1]
        ok(bp and bp[2] == RD.defRail and bp[1] == "BOTTOM", "on the radar it sits at the right rail's foot")
        ok(b.ring[1].__alpha == 0 and b.grid[1].__alpha == 1, "its sign: four small squares (the console is where it goes)")
        STATE.inCombat = true
        ok(RD.ToggleView() == nil and not RD.Console(), "in a fight: refused (secure buttons)")
        STATE.inCombat = false
        ok(RD.ToggleView() == "console" and RD.Console() and d.radar.view == "console" and RD.ConsoleTier().name == "FIGHTER",
           "a click: the engineer's view, the fighter (a party)")
        local G = RD.conGrid
        ok(G and f:GetWidth() == G.W and f:GetHeight() == G.H and G.W < W0, "the square shrinks to the console's grid", G and G.W)
        local function c(fr) local p = fr.points[1] return p and p[2] == f and p[3] == "TOPLEFT" and p[4], p and -p[5] end
        local x1, y1 = c(RD.spokes[1].heal)
        local x2, y2 = c(RD.spokes[2].heal)
        ok(x1 == G.cols[3] and y1 == G.rows[1] and x2 == G.cols[2] and y2 == G.rows[1],
           "row 1: the party's heal pips, you in the middle, the party outward (Arn, 11 Nov: \"build from the center out\")")
        local cb = RD.spokes[2].cures[1] and RD.spokes[2].cures[1].box
        local cx, cy = c(cb)
        ok(cb and cy == G.rows[2] and math.abs(cx - G.cols[2]) < RD.CON.colW / 2, "row 2: their cures under them")
        -- THE DIAMOND GOES WITH ITS BOX (Arn, 11 Nov: "when my cousin tries to click this on the engineer view to dispel
        -- the poison it does not dispel"): the marker hangs off its container, the container off the clickable box
        local cc = RD.spokes[2].cures[1].container
        local mark
        for _, sl in pairs(cc and cc.slots or {}) do mark = sl end
        local mp = mark and mark.points[1]
        ok(cc and cc.points[1] and cc.points[1][2] == cb and mp and mp[2] == cc and mp[4] == 0 and mp[5] == 0,
           "the dispel diamond sits on its clickable box in the engineer's view (it stayed at the radar spot before)",
           mp and tostring(mp[2]))
        local bx, by = c(RD.spokes[2].bogey)
        ok(bx == G.cols[2] and by == G.rows[3], "row 3: the kick on their target")
        local px, py = c(RD.spokes[2].pet)
        ok(px == G.cols[2] and py == G.rows[4], "row 4: their pet")
        local tx1, ty1 = c(RD.shield)
        local tx8, ty8 = c(RD.res)
        ok(ty1 == G.rows[5] and ty8 == G.rows[5] and tx1 < tx8, "row 5: the tools of both rails, the stabilizer to the res")
        ok(RD.spokes[2].heal:GetAttribute("unit") == "party1", "the same buttons: party1's pip still heals party1")
        -- THE BOXES ARE HEALTH BARS (Arn, 12 Nov 2026: "get rid of the icons inside the box and make them actual health
        -- bars class coded and figure out a over heal los range indicator")
        do
            local EN = NS.EN
            local sp = RD.spokes[2]
            local e = sp.en
            ok(e and e.box.__shown and e.box:DoesClipChildren() and e.box:GetParent() == sp.heal,
               "party1's box: a plain frame inside the pip (never the secure pip itself), clipping its bars")
            local lo, hi = e.bar:GetMinMaxValues()
            ok(lo == 0 and hi ~= nil and e.bar:GetValue() ~= nil, "a health bar, handed their max and health untouched")
            local _, cls = UnitClass("party1")
            local want = NS.FG.CLASS_COLOR[cls or ""] or EN.FALLBACK
            local bc = e.bar.__color or {}
            ok(bc[1] == want[1] and bc[2] == want[2] and bc[3] == want[3], "in the grid's class colour (" .. tostring(cls) .. ")")
            ok(not sp.heal.beat.__shown and not sp.heal.redFace.__shown and not sp.heal.amberFace.__shown,
               "the role glyphs inside the box are gone in the engineer's view")
            local lp = sp.los.points[1]
            -- ONE PLACE FOR EVERY ALERT (Arn, 12 Nov: "move all the alerts for all players to the same space in the header" -
            -- "so all stacked in the header LOS RANGE OVERHEAL" - "we light it up when any square is clicked")
            local lp2 = RD.spokes[3].los and RD.spokes[3].los.points[1]
            local HY = -((RD.CON.pad + RD.CON.head) / 2)
            ok(lp and lp[1] == "CENTER" and lp[2] == RD.frame and lp[3] == "TOPLEFT" and lp[4] == RD.CON.pad + 17
               and lp[5] == HY and lp2 and lp2[2] == RD.frame and lp2[4] == lp[4],
               "a click word: in the console's header, the same spot for every player (the LOS box)")
            -- THREE BOXES (Arn: "oh thats right we can have 3 boxes" - "a hover can show a los and overheal at the same time")
            local H = EN.heads or {}
            ok(H.los and H.range and H.over and H.los.__shown and H.range.__shown and H.over.__shown and #H.los.edges == 4,
               "three dim empty boxes in the header: LOS, RANGE, OVER/H")
            local hl, hr, ho = H.los.points[1], H.range.points[1], H.over.points[1]
            ok(hl[4] + H.los:GetWidth() / 2 < hr[4] - H.range:GetWidth() / 2 and hr[4] + H.range:GetWidth() / 2 < ho[4] - H.over:GetWidth() / 2
               and ho[4] + H.over:GetWidth() / 2 < RD.frame:GetWidth() - 30,
               "side by side, never touching, clear of the class and view buttons", ho[4] + H.over:GetWidth() / 2)
            EN.PlaceWord(sp, "RANGE")
            local rp = sp.los.points[1]
            ok(rp[4] == hr[4] and rp[5] == HY, "RANGE lights its own box")
            EN.PlaceWord(sp, "LOS")
            ok(sp.los.points[1][4] == hl[4], "LOS its own")
            ok(EN.Range() >= 1, "range: the grid's own dimming, on the box")
            -- the ghost: your heal after their health, cut at the box's edge
            ok(EN.Ghost(sp, 500) and e.ghost.__shown and e.ghost:GetValue() == 500 and select(2, e.ghost:GetMinMaxValues()) ~= nil,
               "hovering: your heal as a pale ghost, handed against their max")
            local gp = e.ghost.points[1]
            ok(gp and gp[2] == e.inc:GetStatusBarTexture() and gp[3] == "TOPRIGHT" and e.ghost:GetParent() == e.box,
               "the ghost starts where the heals on their way end, inside the box that clips it")
            ok(EN.Ghost(sp, nil) == false and not e.ghost.__shown, "the mouse leaves: the ghost goes")
            -- HEALS ON THEIR WAY (Arn, 12 Nov: "engineer still missing the incoming heal mechanic")
            local ip = e.inc.points[1]
            ok(ip and ip[2] == e.bar:GetStatusBarTexture() and ip[3] == "TOPRIGHT" and e.inc:GetParent() == e.box,
               "an incoming bar starts where their health ends, inside the box")
            local keepInc = _G.UnitGetIncomingHeals
            local INC = secret()
            _G.UnitGetIncomingHeals = function(u) return u == "party1" and INC or 0 end
            ok(EN.Incoming(sp) and e.inc:GetValue() == INC and select(2, e.inc:GetMinMaxValues()) ~= nil,
               "heals on their way handed to it untouched (a secret), on their max")
            ok(EN.events.__events and EN.events.__events.UNIT_HEAL_PREDICTION, "it listens for heal predictions while the console shows")
            local INC2 = secret()
            INC = INC2
            fire(EN.events, "UNIT_HEAL_PREDICTION", "party1")
            ok(e.inc:GetValue() == INC2, "a heal starts on party1: the bar moves")
            -- THE OVERHEAL IN THE BOX (Arn, 12 Nov, the grid's magenta: "can we show that and the overheal word on the
            -- engineer?"): the grid's band - from the box's right edge leftwards by the incoming, masked to their health
            local op = e.over.points[1]
            local oft = e.over:GetStatusBarTexture()
            ok(op and op[1] == "TOPRIGHT" and op[2] == e.box and op[3] == "TOPRIGHT" and e.over:GetReverseFill()
               and e.over:GetValue() == INC2 and select(2, e.over:GetMinMaxValues()) ~= nil,
               "an overheal band: the incoming again, filling leftwards from the box's right edge, on their max", tostring(op and op[2]))
            local masked = false
            for _, m in ipairs(oft.__masks or {}) do if m == e.mask then masked = true end end
            local cp = e.cur.points
            ok(masked and e.mask and cp[2] and cp[2][2] == e.bar:GetStatusBarTexture(),
               "masked to their filled health (a MASK - a clip on a secret-sized fill draws nothing): only the waste shows")
            local oc = e.over.__color or {}
            ok(oc[1] == EN.OVER[1] and oc[2] == EN.OVER[2] and oc[3] == EN.OVER[3], "in the grid's overheal magenta")
            ok(e.overTick and e.overTick.points[1][2] == oft, "a white tick where the waste begins")
            ok(EN.Ghost(sp, 500) and e.overHover.__shown and e.overHover:GetValue() == 500 and e.overHover:GetReverseFill()
               and e.overHover.points[1][2] == oft and e.overHover.points[1][3] == "TOPLEFT",
               "hovering: what YOUR heal would waste on top, a fainter band on from the incoming's")
            EN.Ghost(sp, nil)
            ok(not e.overHover.__shown, "the mouse leaves: that band goes too")
            -- the OVER/H word: IN the box in the console (under it, the dispel row sat right below)
            local o = NS.OV.Build(sp)
            NS.OV.Anchor(sp)
            local wp = o.win.points[1]
            local ho2 = EN.heads.over.points[1]
            ok(wp and wp[1] == "LEFT" and wp[2] == RD.frame and wp[4] == ho2[4] - EN.heads.over:GetWidth() / 2
               and wp[5] == ho2[5] and o.win:GetFrameLevel() > e.over:GetFrameLevel(),
               "OVER/H in its own header box (the word hangs 4 px in from its left edge)", tostring(wp and wp[4]))
            -- THE FUEL STRIP ON TOP (Arn, 12 Nov: "all engineering can get a barebones mana guage on top from the rader
            -- its own version" - "with the bingo and mana regen 5 second rule but much smaller")
            RD.ApplyView()
            local g, r = RD.gauge, EN.rail
            local rp = r and r.points or {}
            ok(r and r.__shown and rp[1] and rp[1][1] == "BOTTOMLEFT" and rp[1][2] == RD.frame and rp[1][3] == "TOPLEFT"
               and r:GetHeight() == EN.GAUGE.h and r:GetHeight() < RD.GAUGE_RAIL_H,
               "a thin plate over the console (" .. EN.GAUGE.h .. " px; the radar's rail is " .. RD.GAUGE_RAIL_H .. ")")
            local gp = g.points[1]
            local want = RD.frame:GetWidth() - EN.GAUGE.pad - EN.GAUGE.right
            ok(g.__shown and gp and gp[2] == r and g.len == want and g:GetWidth() == want,
               "the radar's OWN tape on it, shaped to the console's width (the same bars, BINGO, ticks)", g.len)
            local hp = g.hotClip.points
            local roof
            for _, pt in ipairs(hp) do if pt[1] == "TOPRIGHT" then roof = pt end end
            ok(roof and roof[4] == RD.BINGO * want + 2, "BINGO's window sized to the short tape")
            ok(not g.hud.__shown and not g.readout.__shown and not g.chev.__shown,
               "barebones: no scale numbers, no readout box, no chevron")
            ok(g.regen.__shown and g.regen.__size == EN.GAUGE.font and g.regen.points[1][2] == r and g.fsr.__shown,
               "the regen % small at its right end, the five second rule's dashes under it")
            ok(EN.GaugeTop() == EN.GAUGE.h + RD.RAIL_GAP, "the clamp keeps the strip on the screen")
            ok(RD.PaintMana() ~= false, "painted by the radar's own functions")
            local keepCon = RD.Console
            RD.Console = function() return false end          -- the view really back on the radar, as the switch leaves it
            EN.Gauge(false)
            RD.Console = keepCon
            ok(not r.__shown and g.hud.__shown and g.readout.__shown and g.points[1][2] == RD.gaugeRail and g.regen.__size == 10,
               "back on the radar: the tape home on its rail, its scale and readout back")
            EN.Gauge(true)
            o.word:SetText("")                -- built only for this check: the scope's no-words count comes later
            o.win:Hide()
            sp.over = nil
            _G.UnitGetIncomingHeals = keepInc
            local okC, Cost = pcall(dofile, "../_bisdev/dev/cost.lua")
            if not okC then okC, Cost = pcall(dofile, "../../_bisdev/dev/cost.lua") end
            if okC then
                local n, by = Cost.Count(function() for _ = 1, 10 do EN.Range() end end)
                print(("   cost: engineer boxes' range, 10 ticks = %d calls (%s)"):format(n, Cost.Top(by, 3)))
                ok(n <= 300, "ten ticks of the boxes' range stay in budget", n)
            end
            -- back on the radar: nothing of this shows; the glyphs and the word under the pip come back
            local keepConL = RD.Console
            RD.Console = function() return false end          -- the view really on the radar, as the switch leaves it
            EN.Layout(false)
            RD.Console = keepConL
            ok(not e.box.__shown and sp.heal.beat.__shown and sp.los.points[1][2] == NS.BB.rail.row,
               "the radar: glyphs back, no bars, LOS in the black box's bottom row (12 Nov)")
            ok(not EN.events.__events.UNIT_HEAL_PREDICTION, "back on the radar: heal predictions no longer heard")
            EN.Layout(true)
        end
        local e4 = RD.spokes[4]
        ok(e4.unit == nil and e4.heal:GetAttribute("unit") == RD.EMPTY_UNIT and e4.heal:IsMouseEnabled() ~= false
           and e4.heal:GetAttribute("type1") == nil and f:GetAttribute("unit") == RD.EMPTY_UNIT,
           "an empty square and the background name nobody: the wheel over them heals no one (Arn, 10 Nov)")
        ok(not RD.scope:IsShown() and not RD.toolRail:IsShown() and not RD.gaugeRail:IsShown() and not RD.defRail:IsShown()
           and not (RD.bbRail and RD.bbRail:IsShown()), "the scope, the rails and the black box step aside")
        ok(RD.gauge:IsShown() and NS.EN.rail and NS.EN.rail:IsShown() and RD.gauge.points[1][2] == NS.EN.rail,
           "the tape moves to the engineer's own small strip on top (Arn, 12 Nov) - never left floating")
        -- the tools re-armed on their own (max mana changed, a fight ended): the right rail stays away (Arn, 11 Nov:
        -- "why does his engineer 2 have a right rail")
        local wConsole = f:GetWidth()
        RD.ArmTools()
        ok(not RD.defRail:IsShown() and f:GetWidth() == wConsole and RD.hull.points[2][2] == f,
           "the tools re-armed in the console: no right rail beside it, the hull still the console's square")
        ok(RD.conSquares.heal1 and RD.conSquares.heal1:IsShown() and RD.conSquares.tool8:IsShown(), "an empty square where each one lives")
        ok(not RD.gauge.chev:IsShown() and RD.gauge.regen.points[1][2] == NS.EN.rail and RD.gauge.fsr.points[1][2] == RD.gauge.regen,
           "the tape's pieces go WITH it: the regen % and the dashes on the strip (never the 100% Arn saw floating over the console), no chevron")
        local hp = RD.hull.points
        ok(hp[1][2] == f and hp[2][2] == f, "the hull is the console's own square")
        bp = b.points[1]
        ok(bp and bp[1] == "TOPRIGHT" and bp[2] == f and b.ring[1].__alpha == 1, "the view button in the console's corner, its sign the ring (back to the radar)")
        local cbp = RD.classBtn.points[1]
        ok(cbp and cbp[2] == b, "the class button beside it")
        -- THE SHIPS (Arn, 11 Nov: "upgrading ships to the next class ... let me click them even if i am not in that size
        -- party or raid, only go bigger 5-10%"): each class a hull only a little wider, rows folded, from the centre out
        local widths = { f:GetWidth() }
        for _, want in ipairs({ "GUNSHIP", "CRUISER", "CAPITAL" }) do
            ok(RD.NextClass() == want and RD.ship == RD.SHIPS[RD.ConsoleTier().ship], "the class button: the " .. want .. ", in its colours")
            widths[#widths + 1] = f:GetWidth()
            local grow = widths[#widths] / widths[#widths - 1]
            ok(grow > 1.0 and grow <= 1.10, want .. ": only a little wider than the last (5-10%)", grow)
            local T = RD.ConsoleTier()
            ok(#RD.slots == T.n and RD.spokes[T.n] and RD.spokes[T.n].heal:IsShown(), want .. ": a place for all " .. T.n)
            ok(RD.spokes[2].heal:GetAttribute("unit") == "party1" and RD.spokes[T.n].heal:GetAttribute("unit") == RD.EMPTY_UNIT,
               want .. ": your party where it was, the empty places empty (a preview)")
            local hx = RD.spokes[1].heal.points[1][4]
            ok(math.abs(hx - f:GetWidth() / 2) < T.colW, want .. ": you in the middle of your row", hx)
            local cb2 = RD.spokes[2].cures[1] and RD.spokes[2].cures[1].box
            ok(cb2 and cb2.__w == T.chip, want .. ": the dispels are chips in the corners", cb2 and cb2.__w)
            ok(RD.spokes[6].bogey and not RD.spokes[6].bogey:IsShown(), want .. ": interrupts for your own group only")
        end
        -- THE FLEET (Arn, 11 Nov: "top 5 with me in the center ... outer edges people that arent really taking any damage"
        -- ... "we are the star destroyer, our best ships are around us"): rank, not group; the core big, the screen small
        local G4 = RD.conGrid
        ok(G4.placed[1] == G4.cells[1], "the capital: you in the very middle place")
        local c1 = G4.cells[1]
        local far = G4.cells[#G4.cells]
        -- TIDY (Arn, 11 Nov: "lets clean it up at least"): one size a class, the bands told by brightness
        ok(c1.d < far.d and RD.spokes[1].heal.__w == RD.spokes[40].heal.__w
           and RD.conSquares.heal1.col == RD.BAND_COL.core and RD.conSquares.heal40.col == RD.BAND_COL.screen,
           "one square size; the core bright, the outer screen faint", RD.spokes[40].heal.__w)
        local vb, top1 = RD.viewBtn, RD.conSquares.heal1
        ok(G4.cells[1].y - RD.CON.sq / 2 >= RD.CON.pad + RD.CON.head - 1, "the crew starts under the buttons' strip (no overlap)")
        local keepBrains, keepGUN = _G.BiSBrains, _G.GetUnitName
        _G.GetUnitName = function(u) return "Name-" .. tostring(u) end   -- whole names, as Forever gives them
        _G.BiSBrains = { order = { "Name-party2", "Name-party1" } }
        RD.Arm()
        G4 = RD.conGrid
        ok(RD.conOrder[1] == 1 and RD.conOrder[2] == 3 and RD.conOrder[3] == 2 and G4.placed[3] == G4.cells[2],
           "the brains' order: party2 first after you, next to you, any group", table.concat(RD.conOrder, ",", 1, 4))
        ok(RD.spokes[3].bogey:IsShown() and RD.slots[3].rb, "the top five carry the interrupts")
        _G.BiSBrains, _G.GetUnitName = keepBrains, keepGUN
        RD.Arm()
        -- THE FLEET'S ORDERS (Arn, 11 Nov: "they take out your communicatiion ship ... you will still have your tanks close
        -- to screen you ... melee dps classes near by too ... the other layers are small agile ships"): without the brains,
        -- you, tanks, melee, healers, ranged; with them, the log's order by GUID
        do
            local keepC, keepR, keepT = STATE.classes, STATE.roles, d.radar.tier
            local keepU = {}
            for k = 1, 4 do keepU[k] = STATE.units["party" .. k] end
            STATE.classes = { party1 = "MAGE", party2 = "PRIEST", party3 = "ROGUE", party4 = "WARRIOR" }
            STATE.roles = { party4 = "TANK" }
            for k = 1, 4 do STATE.units["party" .. k] = true end
            _G.BiSBrains = nil
            local units = { "player", "party1", "party2", "party3", "party4" }
            local o = RD.ConsoleOrder(units, 5)
            ok(table.concat(o, ",") == "1,5,4,2,3", "no brains: you, the tank, the melee, the mage, the healer furthest out",
               table.concat(o, ","))
            _G.BiSBrains = { order = { "Player-0-party1", "Player-0-party3" },
                             names = { ["Player-0-party1"] = "Mage-One-PvP-US", ["Player-0-party3"] = "Rogue-Two-PvP-US" } }
            o = RD.ConsoleOrder(units, 5)
            ok(table.concat(o, ",") == "1,2,4,5,3", "the brains online: their order by GUID first, the rest by logic after",
               table.concat(o, ","))
            ok(RD.BrainsName("Holy-Haven-PvP-US") == "Holy Haven", "the log's name read as Forever's Name Surname")
            local said = {}
            RD.BrainsSay(function(fmt, ...) said[#said + 1] = string.format(fmt, ...) end)
            ok(said[1] and said[1]:find("online", 1, true) and said[1]:find("Mage One", 1, true), "/bish alpha radar brains: online, who", said[1])
            _G.BiSBrains = nil
            said = {}
            RD.BrainsSay(function(fmt, ...) said[#said + 1] = string.format(fmt, ...) end)
            ok(said[1] and said[1]:find("offline", 1, true) and said[1]:find("tanks, melee, ranged", 1, true), "and offline: by logic", said[1])
            -- TANKS NORTH (Arn, 11 Nov, a standing rule: "keep tank north of us, can be spread but in the top half")
            _G.BiSBrains = nil
            STATE.roles = { party2 = "TANK" }            -- party2 is slot 3: the party radar puts slot 3 south-east
            local keepView = d.radar.view
            d.radar.view, d.radar.tier = nil, nil
            RD.Arm()
            local s3 = RD.slots[3]
            ok(s3 and math.cos(s3.b) > 0 and s3.rh > 0, "the party radar: the tank moved into the top half", s3 and math.deg(s3.b))
            ok(RD.spokes[3].heal:GetAttribute("unit") == "party2", "and their pip is still theirs")
            for _, tier in ipairs({ 2, 3, 4 }) do
                d.radar.tier = tier
                RD.Arm()
                local st = RD.slots[3]
                ok(st and math.cos(st.b) > 0 and st.rh > 0, RD.CON_TIERS[tier].name .. ": the tank north of you", st and math.deg(st.b))
            end
            STATE.roles = { party1 = "TANK", party2 = "TANK", party3 = "TANK" }
            d.radar.tier = 4
            RD.Arm()
            local allNorth = true
            for k = 2, 4 do if not (math.cos(RD.slots[k].b) > 0) then allNorth = false end end
            ok(allNorth, "three tanks on the capital: all in the top half, spread")
            -- THE MAIN TANK DIRECTLY ON TOP (Arn, 11 Nov: "Main tank taking the most damage always directly on top of us")
            local mt = RD.mainTank
            ok(mt and RD.slots[mt].b == 0 and RD.slots[mt].rh > 0, "the main tank due north", mt)
            local meS
            for _, sl in pairs(RD.slots) do if sl.self then meS = sl end end
            ok(meS and meS.b == RD.SELF_ASIDE.b and meS.rb == RD.SELF_ASIDE.rb, "your target's bogey steps to your left, off the main tank's")
            local clashN = 0
            for k, sl in pairs(RD.slots) do if k ~= mt and not sl.self and math.abs(sl.b) < 0.01 then clashN = clashN + 1 end end
            ok(clashN == 0, "nobody else due north (the rings leave it free)", clashN)
            -- with the brains: the tank that takes the most is the one on top
            _G.BiSBrains = { order = { "Player-0-party3", "Player-0-party1" } }
            RD.Arm()
            ok(RD.mainTank == 4 and RD.slots[4].b == 0, "the brains say party3 takes the most: party3 on top", RD.mainTank)
            _G.BiSBrains = nil
            d.radar.tier = nil
            STATE.roles = { party2 = "TANK" }
            RD.Arm()
            ok(RD.mainTank == 3 and RD.slots[3].b == 0, "the party radar too: the tank straight above you")
            -- NOBODY NAMED THE TANK (Arn, 11 Nov: "the tank is not north of me" - a group made by hand has no roles)
            STATE.roles = {}
            RD.Arm()
            ok(RD.tankGuessed == 5 and RD.mainTank == 5 and RD.slots[5].b == 0,
               "no roles from the game: the warrior is guessed and goes straight above you", RD.mainTank)
            STATE.classes = { party1 = "PALADIN", party2 = "PRIEST", party3 = "DRUID", party4 = "WARRIOR" }
            RD.Arm()
            ok(RD.mainTank == 5, "a paladin, a druid and a warrior: the warrior first", RD.mainTank)
            _G.BiSBrains = { order = { "Player-0-party1", "Player-0-party4" } }
            RD.Arm()
            ok(RD.mainTank == 2 and RD.slots[2].b == 0, "the brains say the paladin takes the most: the paladin on top", RD.mainTank)
            _G.BiSBrains = nil
            STATE.classes = { party1 = "MAGE", party2 = "PRIEST", party3 = "ROGUE", party4 = "HUNTER" }
            RD.Arm()
            ok(RD.mainTank == nil and RD.tankGuessed == nil, "nobody who can tank: nobody guessed", RD.mainTank)
            -- the faint dots say it too (Arn, 11 Nov: "the faint dots should reflect that")
            local tp = RD.tankSeat and RD.tankSeat.points and RD.tankSeat.points[1]
            ok(RD.tankSeat and RD.tankSeat:IsShown() and tp and tp[4] == 0 and tp[5] == RD.PARTY.rh,
               "no tank: a faint dot of its own straight above you, where the tank will sit", tp and tp[5])
            -- BiS> now's tank names one: it wins over the guess, realm or not
            local keepTank, keepGUN2 = d.tank, _G.GetUnitName
            _G.GetUnitName = function(u) return "Name " .. tostring(u) end
            d.tank = "Name party2-Realm"
            RD.Arm()
            ok(RD.mainTank == 3 and RD.tankGuessed == nil and RD.slots[3].b == 0,
               "BiS> now's tank (kept with its realm): due north, no guess", RD.mainTank)
            local onTop = 0
            for _, t in ipairs(RD.seats) do
                local p = t:IsShown() and t.points and t.points[1]
                if p and p[4] == 0 and p[5] == RD.PARTY.rh then onTop = onTop + 1 end
            end
            ok(not RD.tankSeat:IsShown() and onTop == 1, "a tank there: their own dot on top, the spare one away", onTop)
            d.tank, _G.GetUnitName = keepTank, keepGUN2
            d.radar.view = keepView
            STATE.classes, STATE.roles, d.radar.tier = keepC, keepR, keepT
            for k = 1, 4 do STATE.units["party" .. k] = keepU[k] end
            _G.BiSBrains = keepBrains
            RD.Arm()
        end
        ok(RD.classBtn.dots[4].__alpha == 1, "on the capital all four of the class button's dots are lit")
        ok(RD.NextClass() == "FIGHTER" and RD.ConsoleTier().n == 5, "and round again to the fighter (a party fits it)")
        ok(RD.ToggleView() == "radar" and not RD.Console(), "the view button again: the radar")
        local hx = RD.shield.points[1]
        ok(hx and hx[2] == RD.toolRail and RD.toolRail:IsShown() and RD.scope:IsShown() and not RD.conLayer:IsShown(),
           "the tools back on their rails, the scope back, the squares away")
        ok(f:GetWidth() == W0, "and the square its own size", f:GetWidth())
        ok(RD.gauge.regen:IsShown(), "the regen readout back with the tape")
        -- THE RADAR'S SHIPS (Arn, 11 Nov: "reimage the radar screen, for 10 20 40"): previewed from a party with the class
        -- button - rings by rank round you, the scope only 7-8% bigger a class
        do
            local sizes = { W0 }
            for _, want in ipairs({ "GUNSHIP", "CRUISER", "CAPITAL" }) do
                ok(RD.NextClass() == want and not RD.Console(), "the class button on the radar: the " .. want)
                local T = RD.ConsoleTier()
                sizes[#sizes + 1] = f:GetWidth()
                local grow = sizes[#sizes] / sizes[#sizes - 1]
                ok(#RD.slots == T.n and f:GetWidth() == RD.FLEET[T.n].size and grow > 1.05 and grow <= 1.10,
                   want .. ": " .. T.n .. " places, the scope a little bigger", grow)
                local me1 = RD.slots[1]
                ok(me1.band == "you" and RD.spokes[2].slot.band == "core" and RD.spokes[2].heal:GetAttribute("unit") == "party1",
                   want .. ": you in the middle, your party the core round you")
                ok(RD.slots[T.n].band ~= "core" and not RD.slots[T.n].rb and RD.spokes[T.n].heal:GetAttribute("unit") == RD.EMPTY_UNIT,
                   want .. ": the empty places on the outer rings, no interrupts there")
                -- THE FLEET MADE VISIBLE (Arn, 11 Nov: "yes do both")
                local shown = 0
                for _, l in ipairs(RD.fleetLines) do if l:IsShown() then shown = shown + 1 end end
                ok(shown == (1 + #RD.FLEET[T.n].rings) * RD.RING_SEG and not RD.innerRings[1]:IsShown()
                   and RD.fleetRadii[1] == RD.FLEET[T.n].core.rh, want .. ": its own rings where its ships sit, the party's away", shown)
                local seats = 0
                for _, t in ipairs(RD.seats) do if t:IsShown() then seats = seats + 1 end end
                ok(seats == T.n and RD.seatFrame:GetAlpha() == 1, want .. ": a faint dot at every place, out of a fight", seats)
            end
            ok(RD.NextClass() == "FIGHTER" and f:GetWidth() == W0 and #RD.slots == 5, "round again: the party radar as it was")
            ok(RD.innerRings[1]:IsShown() and not RD.ringFrame:IsShown(), "the party's own rings back")
            STATE.inCombat = true
            fire(RD.events, "PLAYER_REGEN_DISABLED")
            ok(RD.seatFrame:GetAlpha() == 0, "a fight: the seats go")
            STATE.inCombat = false
            fire(RD.events, "PLAYER_REGEN_ENABLED")
            ok(RD.seatFrame:GetAlpha() == 1, "and come back after it")
        end
        d.radar.view = keepView
        RD.Arm()
        -- ENEMIES ONLY (Arn, 10 Nov: "when im healing myself and targeting myself it shows the interuppt?")
        local sp1 = RD.spokes[1]
        local keepCast, keepAtk, keepKick, keepT = NS.FG.Casting, _G.UnitCanAttack, sp1.kick, STATE.units[sp1.tok]
        sp1.kick = sp1.kick or "Earth Shock"
        STATE.units[sp1.tok] = true
        NS.FG.Casting = function(u) return u == sp1.tok end
        _G.UnitCanAttack = function() return false end
        RD.Look()
        ok(sp1.bogey.face:GetAlpha() == 0, "you casting on yourself (your target): no interrupt lit")
        _G.UnitCanAttack = function() return true end
        RD.Look()
        ok(sp1.bogey.face:GetAlpha() == 1, "an enemy target casting: lit")
        NS.FG.Casting, _G.UnitCanAttack, sp1.kick = keepCast, keepAtk, keepKick
        STATE.units[sp1.tok] = keepT
        RD.Look()
    end
    ok(sp2.bogey:GetAttribute("unit") == "party1target" and sp2.bogey:GetAttribute("*harmbutton1") == "kick"
       and sp1.bogey:GetAttribute("unit") == "target", "the bogey is their target (yours on your own spoke), your interrupt on enemies only")
    ok(sp2.cures[1] and sp2.cures[1].box:GetAttribute("spell") == "Cure Poison" and sp2.cures[2].box:GetAttribute("spell") == "Cure Disease"
       and sp2.cures[1].container and sp2.cures[1].container.unit == "party1", "two cure pips on the spoke: the client's markers, your cures")
    local names = 0
    local placard = { [RD.gauge.role] = true, [RD.gauge.ship] = true, [RD.gauge.fuelWord] = true }
    for _, fs in ipairs(LABELS) do
        local p = fs.__parent
        -- the HUD tape's numbers are allowed (Arn's HUD picture), and the regen readout's "100%" / "?": digits, a % sign,
        -- a question mark - never a word or a name. The one exception is the top rail's placard (the ship, FUEL).
        local t = fs.__text
        -- and the black box's bottom rail (BlackBox.lua): its keys and its screen are words, outside the square
        local q, onBox = fs.__parent, false
        while q do if q == NS.BB.rail then onBox = true break end q = q.__parent end
        if not placard[fs] and not onBox then
            while p do if p == f then if t and t ~= "" and not t:match("^%d+%%?$") and t ~= "?" and t ~= "(secret)" then names = names + 1 end break end p = p.__parent end
        end
    end
    ok(names == 0, "no names, no words on the scope (digits only: the HUD tape's numbers, the regen %)", names)
    -- THE PLACARD (Arn 9 Nov: "lets not do rpm"): the ship and FUEL, on the top rail - never on the scope
    ok(RD.gauge.ship.__parent == RD.gaugeRail and RD.gauge.fuelWord.__parent == RD.gaugeRail
       and RD.gauge.ship.__text == "FIGHTER" and RD.gauge.fuelWord.__text == "FUEL",
       "the top rail's placard: FIGHTER over FUEL (a party flies the fighter)", RD.gauge.ship.__text)
    -- YOUR ROLE ON IT (Arn 9 Nov: "lets add our role here Healer, DPS, Tank"): over the ship, from the group's role
    do
        local gr = RD.gauge.role
        local rp = gr.points and gr.points[1]
        local sp = RD.gauge.ship.points and RD.gauge.ship.points[1]
        local fp = RD.gauge.fuelWord.points and RD.gauge.fuelWord.points[1]
        ok(gr.__parent == RD.gaugeRail and rp and rp[2] == RD.gaugeRail and sp and sp[2] == RD.gaugeRail and fp
           and rp[5] > sp[5] and sp[5] > fp[5], "the role at the top of the placard, the ship under it, FUEL under that - each at its own spot")
        local keepRole, keepPA = _G.UnitGroupRolesAssigned, _G.GetPartyAssignment
        -- ONLY WHAT THE GAME SAYS (Arn 9 Nov: "we take the role from what the games tell us, the frames already tell us")
        _G.UnitGroupRolesAssigned = function() return "NONE" end
        _G.GetPartyAssignment = function() return false end
        fire(RD.events, "PLAYER_ROLES_ASSIGNED")
        ok(gr.__text == "", "no role from the game: the line is empty - a shaman is never guessed a HEALER", gr.__text)
        for want, role in pairs({ TANK = "TANK", DPS = "DAMAGER", HEALER = "HEALER" }) do
            _G.UnitGroupRolesAssigned = function(u) if u == "player" then return role end return "NONE" end
            fire(RD.events, "PLAYER_ROLES_ASSIGNED")
            ok(gr.__text == want, "the group says " .. role .. ": the placard says " .. want, gr.__text)
        end
        _G.UnitGroupRolesAssigned = function() return "NONE" end
        _G.GetPartyAssignment = function(what, u) return what == "MAINTANK" and u == "player" end
        fire(RD.events, "PLAYER_ROLES_ASSIGNED")
        ok(gr.__text == "TANK", "the raid's main tank assignment (the game's own): TANK", gr.__text)
        _G.UnitGroupRolesAssigned, _G.GetPartyAssignment = keepRole, keepPA
        fire(RD.events, "PLAYER_ROLES_ASSIGNED")
        -- three lines fit the rail: 9 pt each, 2 px apart, from 5 px down
        ok(5 + 3 * 10 + 2 * 2 <= RD.GAUGE_RAIL_H, "role, ship and FUEL fit inside the rail")
    end

    -- THE SHIPS (Arn 9 Nov: "imperial purple and white accents like a fighter and the more the group gets we change the
    -- color to finally ending in star destroyer"): the chrome follows the group's size; warnings never change
    do
        local want = { [1] = "fighter", [5] = "fighter", [6] = "gunship", [10] = "gunship", [11] = "cruiser",
                       [20] = "cruiser", [21] = "capital", [40] = "capital", [41] = "capital" }
        local right = true
        for n, key in pairs(want) do if RD.ShipFor(n).key ~= key then right = false end end
        ok(right, "the ship by group size: 1-5 fighter, 6-10 gunship, 11-20 cruiser, 21-40 capital")
        local red, amber, boss = { unpack(RD.COL.red) }, { unpack(RD.COL.amber) }, { unpack(RD.BOSS_COL) }
        local plateTable = RD.PLATE
        local cap = RD.SHIPS[4]
        RD.ApplyShip(cap)
        local function same(c, w) return c and math.abs(c[1] - w[1]) < 1e-9 and math.abs(c[2] - w[2]) < 1e-9 and math.abs(c[3] - w[3]) < 1e-9 end
        ok(RD.PLATE == plateTable and same(RD.PLATE, cap.plate), "the hull IS RD.PLATE, changed in place (covers made later match)")
        ok(same(RD.fade.__vertex, cap.plate) and same(RD.toolRail.bg.__vertex, cap.plate) and same(RD.gaugeRail.bg.__vertex, cap.plate)
           and same(RD.defRail.bg.__vertex, cap.plate) and same(RD.gauge.readout.fill.__vertex, cap.plate),
           "the disc, all three rails and the readout box: the capital ship's grey hull")
        local k = RD.SCOPE_DIM
        local ring = RD.scopeLines[1].color
        ok(#RD.scopeLines > 100 and math.abs(ring[1] - cap.line[1] * k) < 1e-9 and math.abs(ring[3] - cap.line[3] * k) < 1e-9,
           "the scope's rings, cross and ticks in its white-grey line", #RD.scopeLines)
        local br = RD.brackets[1]
        ok(#RD.brackets == 8 and br.thick == cap.bw and same(br.color, cap.bracket)
           and math.abs(math.abs(br.from[1] - br.to[1]) - cap.be) < 1e-9, "the corner brackets: white, longer and heavier", br.thick)
        local me = RD.meLines[1]
        ok(#RD.meLines >= 2 and RD.meRole == RD.Role("player") and me and me.__kind ~= "Line"
           and me.__vertex and math.abs(me.__vertex[1] - cap.accent[1]) < 1e-9 and me.__vertex[4] == 0 and RD.ME_ALPHA == 0,
           "you in the middle: no standing sign (Arn, 10 Nov: only your heal pip, lit when you need it)", #RD.meLines)
        ok(same(RD.gauge.mana.__color, cap.fuel) and RD.gauge.ship.__text == "CAPITAL", "your fuel in its colour, CAPITAL on the placard")
        ok(same(RD.COL.red, red) and same(RD.COL.amber, amber) and same(RD.BOSS_COL, boss) and same(RD.gauge.boss.__color, boss),
           "warnings keep their colours in every ship: red, amber, the boss's red")
        -- the knobs (Arn's 9 Nov screenshot: green dots on the purple fighter): "on" in the ship's line, "off" still red
        local keepMacro, keepOff = RD.tide.macro, RD.KnobOff("tide")
        RD.tide.macro = keepMacro or "/cast Mana Tide Totem"
        RD.SetKnob("tide", false)
        RD.ApplyShip(cap)
        local dv = RD.tide.knob.dot.__vertex
        ok(same(dv, cap.line) and dv[4] == RD.KNOB_ON[4], "a knob that is on: a faint dot in the ship's own line", dv and dv[1])
        RD.SetKnob("tide", true)
        ok(same(RD.tide.knob.dot.__vertex, RD.KNOB_OFF), "a knob switched off: red in every ship")
        RD.SetKnob("tide", keepOff)
        RD.tide.macro = keepMacro
        RD.ApplyShip(RD.SHIPS[1])
        ok(same(RD.PLATE, RD.SHIPS[1].plate) and RD.gauge.ship.__text == "FIGHTER" and RD.brackets[1].thick == RD.SHIPS[1].bw,
           "and back to the fighter: its hull, its name, its brackets")
    end

    -- THE DARK DISC (Arn, 9 Nov: "a dark background instead of see through so things pop more like the rail ... the edge
    -- fade instead on the edges like the screen shot")
    do
        local fd = RD.fade
        ok(fd and tostring(fd.__texture):find("Art\\scopefade", 1, true), "the scope sits on a dark disc with a soft edge (our art)")
        local v = fd and fd.__vertex
        ok(v and v[1] == RD.PLATE[1] and v[2] == RD.PLATE[2] and v[3] == RD.PLATE[3] and v[4] == 1,
           "the rail's own plate, solid - not see-through")
        ok(fd and fd.__parent == f and fd.__layer == "BACKGROUND" and fd.__sublevel == -8,
           "on the radar's own lowest layer, so the rails beside it draw over its fading edge")
        ok(fd and fd.__w == RD.FADE_PX and fd.__w > RD.SIZE, "bigger than the square: the fade runs past its edge, the corners clear")
        local seeThrough = false
        for _, r in ipairs({ RD.scope:GetRegions() }) do
            local c = rawget(r, "__colorTexture") or rawget(r, "__color")
            if c and c[4] and c[4] < 1 then seeThrough = true end
        end
        ok(not seeThrough, "the old see-through square is gone")
    end

    -- THE CLICK'S WORD (Arn, 9 Nov: "LOS for line of sight, range for out of range, red letter under the teammate ... only
    -- when i click them ... like the bis grid in normal view")
    do
        local keepFlash = d.flash
        d.flash = true
        local LOSMSG = "Target not in line of sight"
        ok(RD.PaintRange == nil, "no standing range mark any more: nothing asks every spoke's range on a look")
        RD.over = nil
        fire(RD.events, "UI_ERROR_MESSAGE", 50, LOSMSG)
        ok(sp2.los:GetAlpha() == 0, "a failed click with the mouse on no pip: nothing")
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(RD.over == sp2, "the mouse on party1's pip")
        fire(RD.events, "UI_ERROR_MESSAGE", 50, LOSMSG)
        ok(sp2.los:GetAlpha() == 1 and sp2.los.word.__text == "LOS" and sp2.losFade and sp2.losFade.playing,
           "line of sight: LOS under that pip, fading by itself", sp2.los.word.__text)
        local pt, rel, rp = sp2.los:GetPoint(1)
        -- since 12 Nov (Arn: "the black box has a huge chat bot for the code mayeb we can use that space"): the LOS box in
        -- the black box's bottom row
        ok(pt == "CENTER" and rel == NS.BB.rail.row and rp == "TOPLEFT", "in the LOS box in the black box's bottom row", tostring(pt) .. " " .. tostring(rp))
        local c = sp2.los.word.__color
        ok(c and c[1] == NS.FG.FLASH_RED[1] and c[2] == NS.FG.FLASH_RED[2] and c[3] == NS.FG.FLASH_RED[3],
           "in the grid's flash red")
        ok(sp1.los:GetAlpha() == 0, "and only there")
        fire(RD.events, "UI_ERROR_MESSAGE", 51, "Out of range.")
        ok(sp2.los.word.__text == "RANGE" and sp2.los:GetAlpha() == 1, "out of range: RANGE", sp2.los.word.__text)
        ok(RD.HeardError("Not enough mana") == nil and sp2.los.word.__text == "RANGE", "any other error: nothing new")
        ok(RD.HeardError(secretString()) == nil, "a secret error text is never read")
        d.flash = false
        ok(RD.HeardError(LOSMSG) == nil, "the grid's LOS flash switched off: off here too")
        d.flash = true
        sp2.heal.__scripts.OnLeave(sp2.heal)
        ok(RD.over == nil and RD.HeardError(LOSMSG) == nil, "the mouse gone: nothing")
        RD.spokes[4].heal.__scripts.OnEnter(RD.spokes[4].heal)
        ok(RD.HeardError(LOSMSG) == nil, "an empty spot: nothing")
        RD.spokes[4].heal.__scripts.OnLeave(RD.spokes[4].heal)
        sp2.los:SetAlpha(0)
        d.flash = keepFlash
    end

    -- THE RADAR UP TO SPEED (Arn, 12 Nov 2026: "we made engineer better than radar now i find my self using engineer more
    -- how can we bring radar up to speed" - "all three"; then "i dont like it, i think go mini heal bars to make it easier,
    -- and lets not do like engineer up and down lets go left and right ... the black box has a huge chat bot for the code
    -- mayeb we can use that space")
    do
        local MB, EN, KG = NS.MB, NS.EN, NS.KG
        local keepInc = _G.UnitGetIncomingHeals
        local INC = secret()
        _G.UnitGetIncomingHeals = function(u) return u == "party1" and INC or 0 end
        RD.PaintHeal(sp2)
        local m = sp2.mini
        -- 1. A MINI HEALTH BAR UNDER EVERY PIP, LEFT TO RIGHT
        local bp = m and m.box.points[1]
        ok(m and m.box.__shown and m.box:GetParent() == sp2.heal and m.box:DoesClipChildren()
           and bp[1] == "TOP" and bp[2] == sp2.heal and bp[3] == "BOTTOM",
           "party1's pip has a mini bar hung UNDER it (its child: it hides with the pip)")
        ok(m.bar:GetOrientation() == "HORIZONTAL" and m.box:GetHeight() == MB.H and m.box:GetWidth() == sp2.heal:GetWidth() + MB.WIDER,
           "left to right, " .. MB.H .. " px tall, a little wider than the pip")
        ok(select(2, m.bar:GetMinMaxValues()) ~= nil and m.bar:GetValue() ~= nil, "their health, handed untouched")
        local ip = m.inc.points[1]
        ok(ip and ip[1] == "TOPLEFT" and ip[2] == m.bar:GetStatusBarTexture() and ip[3] == "TOPRIGHT" and m.inc:GetValue() == INC,
           "heals on their way after the fill (a secret, untouched)")
        local masked = false
        for _, mk in ipairs(m.over:GetStatusBarTexture().__masks or {}) do if mk == m.mask then masked = true end end
        ok(m.over:GetReverseFill() and m.over:GetValue() == INC and masked and m.over.points[1][1] == "TOPRIGHT",
           "the overheal from the right edge leftwards, masked to their health: only the waste shows (magenta)")
        ok(m.bar:GetStatusBarTexture().__vertex and m.inc:GetStatusBarTexture().__vertex and m.track.__vertex
           and m.over:GetStatusBarTexture().__vertex,
           "every band and the track coloured by the client from their health (gone at 90%, like the pip)")
        ok(MB.Gate(MB.INCOMING) and MB.FillCurve(sp2.amber), "the curves exist (the client evaluates them)")
        ok(MB.events.__events and MB.events.__events.UNIT_HEAL_PREDICTION, "heal predictions heard while the radar shows")
        local INC2 = secret()
        INC = INC2
        fire(MB.events, "UNIT_HEAL_PREDICTION", "party1")
        ok(m.inc:GetValue() == INC2, "a heal starts on party1: the bar's cyan moves")
        EN.Ghost(sp2, 400)
        ok(m.prev.__shown and m.prev:GetValue() == 400 and m.overPrev.__shown and m.prev.points[1][2] == m.inc:GetStatusBarTexture(),
           "hovering: your heal fainter on from the incoming, and its waste in fainter magenta")
        EN.Ghost(sp2, nil)
        ok(not m.prev.__shown and not m.overPrev.__shown, "the mouse leaves: gone")
        STATE.dead.party1 = true
        ok(MB.Paint(sp2) == false and not m.box.__shown, "dead: no bar")
        STATE.dead.party1 = nil
        MB.Paint(sp2)
        _G.UnitGetIncomingHeals = keepInc
        -- 2. THE ALERTS IN THE BLACK BOX'S BOTTOM ROW (where the code screen sat)
        local BB = NS.BB
        local row = BB.rail.row
        local H = EN.radarHeads or {}
        ok(H.los and H.range and H.over and H.los:GetParent() == BB.rail and H.los.points[1][2] == row,
           "three boxes in the black box's bottom row: LOS, RANGE, OVER/H")
        ok(RD.GAUGE_RAIL_H == 44 and RD.gauge.role.points[1][5] == -5, "the top rail back as it was (no extra row)")
        -- the row runs from the lamp (4 + 24 + 2) to the keypad (6 + its width + 6) on a party's rail
        local avail = (RD.TOOL_RAIL_W + RD.RAIL_GAP + RD.PARTY.size) - (4 + 24 + 2) - (6 + BB.rail.pad:GetWidth() + 6)
        local last = H.over.points[1][4] + H.over:GetWidth() / 2
        ok(last <= avail, "all three fit the row on a party's rail", last .. " of " .. avail)
        local A = RD.ship and RD.ship.accent
        local ec = H.los.edges[1].__color or H.los.edges[1].__vertex or {}
        ok(A and ec[1] == A[1] and ec[3] == A[3] and ec[4] == EN.RADAR_HEAD_A, "edged in the ship's accent (Arn: \"same color theme\")")
        EN.PlaceWord(sp2, "RANGE")
        ok(sp2.los.points[1][2] == row and sp2.los.points[1][4] == H.range.points[1][4], "RANGE lights its own box")
        local o = NS.OV.Build(sp2)
        NS.OV.Anchor(sp2)
        ok(o.win.points[1][2] == row and o.win.points[1][1] == "LEFT", "OVER/H in its box")
        -- the screen takes the row only while a code is typed or a reply shows
        BB.pad, BB.sayUntil = "", nil
        BB.Paint()
        ok(H.los.__shown and BB.rail.scr:GetAlpha() == 0, "nothing typed: the boxes show, the screen is down")
        BB.Press("1")
        ok(not H.los.__shown and BB.rail.scr:GetAlpha() == 1, "a key pressed: the screen comes up over the row")
        BB.pad, BB.sayUntil = "", nil
        BB.Paint()
        ok(H.los.__shown, "and goes back down")
        -- 3. THE KICK SHIELD
        local keepCI, keepCH = _G.UnitCastingInfo, _G.UnitChannelInfo
        local NI
        _G.UnitCastingInfo = function(u) if u == "party1target" and NI ~= "none" then return "Fireball", "", 0, 0, 1, false, "x", NI, 133 end end
        _G.UnitChannelInfo = function() return nil end
        local face = sp2.bogey.face
        NI = true
        ok(KG.Paint(face, "party1target") == true and face.guard:GetAlpha() == 1 and #face.guard.lines == 5,
           "a cast the game marks not interruptible: a grey shield over the interrupt")
        NI = false
        ok(KG.Paint(face, "party1target") == false and face.guard:GetAlpha() == 0, "an interruptible cast: no shield")
        NI = secret()
        ok(KG.Paint(face, "party1target") == "secret" and face.guard.__alphaFromSecret,
           "in a fight the flag is secret: handed to SetAlphaFromBoolean, never tested")
        NI = "none"
        ok(KG.Paint(face, "party1target") == nil and face.guard:GetAlpha() == 0, "no cast: nothing")
        _G.UnitCastingInfo = function() return nil end
        _G.UnitChannelInfo = function(u) if u == "party1target" then return "Drain", "", 0, 0, 1, false, true end end
        ok(KG.Paint(face, "party1target") == true, "a channel: its seventh answer")
        ok(face.guard:GetParent() == face, "a child of the face lit only while a cast is on")
        -- through the radar's own look, and the game's mid-cast signal
        local keepCast, keepAtk, keepKick, keepT = NS.FG.Casting, _G.UnitCanAttack, sp2.kick, STATE.units[sp2.tok]
        STATE.units[sp2.tok] = true
        NS.FG.Casting = function() return true end
        _G.UnitCanAttack = function() return true end
        sp2.kick = sp2.kick or "Earth Shock"
        _G.UnitChannelInfo = function() return nil end
        NI = true
        _G.UnitCastingInfo = function(u) if u == sp2.tok then return "Fireball", "", 0, 0, 1, false, "x", NI, 133 end end
        face.guard:SetAlpha(0)
        RD.Look()
        ok(face:GetAlpha() == 1 and face.guard:GetAlpha() == 1, "the radar's look lights the bogey and its shield")
        NI = false
        fire(KG.events, "UNIT_SPELLCAST_INTERRUPTIBLE", sp2.tok)
        ok(face.guard:GetAlpha() == 0, "the game says it can be interrupted now: the shield goes")
        NS.FG.Casting, _G.UnitCanAttack, sp2.kick, STATE.units[sp2.tok] = keepCast, keepAtk, keepKick, keepT
        _G.UnitCastingInfo, _G.UnitChannelInfo = keepCI, keepCH
        RD.Look()
    end

    -- THE OVER WORD (Arn, 12 Nov 2026: "an overheal for the radar like the los and range" - "more than half, both"):
    -- the client compares, through a bar: max = what they miss (secret), value = half the heal. Full = OVER.
    do
        local OV = NS.OV
        local FM = NS.FM
        local keep = { ranks = FM.Ranks, desc = C_Spell.GetSpellDescription, name = C_Spell.GetSpellName,
                       miss = _G.UnitHealthMissing, flash = d.flash, over = d.overWord,
                       left = FM.Get("", "left"), sleft = FM.Get("shift-", "left"), right = FM.Get("", "right") }
        FM.Ranks = function(n)
            if n == "Healing Wave" then return { { rank = "Rank 1", spell = 331 }, { rank = "Rank 7", spell = 8005 } } end
            if n == "Renew" then return { { rank = "Rank 1", spell = 139 } } end
            return keep.ranks(n)
        end
        local TEXT = { [8005] = "Heals a friendly target for 1,000 to 1,200.", [331] = "Heals a friendly target for 36 to 47.",
                       [139] = "Heals the target for 45 over 15 sec." }
        C_Spell.GetSpellDescription = function(id) return TEXT[id] end
        C_Spell.GetSpellName = function(id) return (id == 8005 or id == 331) and "Healing Wave" or "Lightning Bolt" end
        local MISS = secret()
        local asked = {}
        _G.UnitHealthMissing = function(u, predicted) asked[#asked + 1] = { u, predicted } return MISS end
        d.flash, d.overWord = true, nil
        FM.Set("", "left", "Healing Wave(Rank 7)")
        FM.Set("shift-", "left", "Healing Wave(Rank 1)")
        FM.Set("", "right", "Renew")
        OV.Forget()
        ok(OV.HealOf("Healing Wave(Rank 7)") == 1100 and OV.HealOf("Healing Wave(Rank 1)") == 41.5
           and OV.HealOf("Healing Wave") == 1100 and OV.HealOf("Renew") == nil,
           "a heal's size: the middle of its tooltip's range, by the bind's rank (bare = the highest); a HoT is not judged")
        -- HOVER: your left-click heal
        sp2.heal.__scripts.OnEnter(sp2.heal)
        local o = sp2.over
        ok(o and o.win.__shown and o.bar.__shown, "the mouse on party1's pip: the word is armed under it")
        local lo, hi = o.bar:GetMinMaxValues()
        ok(lo == -1 and hi == MISS and o.bar:GetValue() == 550,
           "the bar: max = what they miss (handed SECRET, never read), value = half your left-click heal (550)")
        ok(asked[#asked][1] == "party1" and asked[#asked][2] == true, "missing health with incoming heals taken off")
        local wpt = o.word.points and o.word.points[1] or {}      -- a mock font string keeps its anchors in `points`
        local wp, wrel, wrp = wpt[1], wpt[2], wpt[3]
        local bp, brel, brp = o.bar:GetPoint(1)
        ok(wp == "LEFT" and wrel == o.bar:GetStatusBarTexture() and wrp == "RIGHT" and bp == "RIGHT" and brel == o.win
           and brp == "LEFT" and o.win:DoesClipChildren() and o.bar:GetWidth() == OV.SPAN and o.bar:GetAlpha() == 0,
           "OVER hangs off the fill's end; the bar (never seen, " .. OV.SPAN .. " px) ends at a CLIPPING window: only a full bar shows it")
        local wc = o.word.__color or {}
        ok(o.word.__text == "OVER/H" and wc[1] == 1.00 and wc[2] == 0.24 and wc[3] == 0.92,
           "the word: OVER/H, in the cockpit's magenta (Arn: \"magenta\", \"Over/H\")", tostring(o.word.__text))
        ok(OV.listening == "party1", "only the hovered unit is listened to")
        STATE.shift = true
        fire(OV.events, "MODIFIER_STATE_CHANGED")
        ok(o.bar:GetValue() == 20.75, "holding shift: shift-left's heal instead (Rank 1, half of 41.5)")
        STATE.shift = false
        fire(OV.events, "MODIFIER_STATE_CHANGED")
        local MISS2 = secret()
        MISS = MISS2
        fire(OV.events, "UNIT_HEALTH", "party1")
        ok(select(2, o.bar:GetMinMaxValues()) == MISS2, "their health moves while you hover: handed again")
        sp2.heal.__scripts.OnLeave(sp2.heal)
        ok(not o.win.__shown and OV.listening == nil, "the mouse leaves: the word goes, nobody listened to")
        -- THE CLICK: measured at the click, shown when the cast starts, held still
        sp2.heal.__scripts.OnEnter(sp2.heal)
        local CLICKED = secret()
        MISS = CLICKED
        sp2.heal.__scripts.PostClick(sp2.heal, "LeftButton", true)
        ok(OV.pending and OV.pending.sp == sp2 and select(2, o.bar:GetMinMaxValues()) == CLICKED,
           "a click: measured NOW, before the cast starts (once it does, your own heal counts as incoming)")
        MISS = secret()                                      -- the client now counts your cast as incoming
        fire(OV.events, "UNIT_SPELLCAST_START", "player", "cast-1", 8005)
        ok(o.flashUntil and o.fade and o.fade.playing and o.win.__shown and OV.casting,
           "the cast starts: the word shows, fading by itself (the grid's flash length)")
        fire(OV.events, "UNIT_HEALTH", "party1")
        ok(select(2, o.bar:GetMinMaxValues()) == CLICKED, "held still while it flashes: the heal landing never flips it")
        fire(OV.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 8005)
        ok(OV.casting == nil and OV.pending == nil, "the cast lands: nothing left waiting")
        o.flashUntil = nil
        sp2.heal.__scripts.OnLeave(sp2.heal)
        -- a click whose cast never comes, or comes late, or is another spell: no flash
        sp2.heal.__scripts.PostClick(sp2.heal, "LeftButton", true)
        TICK(OV.MATCH_FOR + 0.2)
        ok(OV.CastBegan(8005) == false, "a cast long after the click is not the click's")
        sp2.heal.__scripts.PostClick(sp2.heal, "LeftButton", true)
        ok(OV.CastBegan(403) == false, "another spell started (a key, a macro): not the click's")
        ok(sp2.heal.__scripts.PostClick(sp2.heal, "RightButton", true) == nil and OV.pending == nil,
           "a right-click on Renew (a heal over time): not judged, no word")
        -- switches
        ok(NS.DO.overword("off") == "off" and d.overWord == false, "/bish overword off is saved")
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(not o.win.__shown, "/bish overword off: no word")
        sp2.heal.__scripts.OnLeave(sp2.heal)
        -- ITS OWN SETTING (Arn, 12 Nov: "add to options ... if they want to change what determines it"): the grid's LOS
        -- flash no longer switches it
        ok(NS.DO.overword("half") == "half" and d.overWord == nil and d.overMode == "half", "back on: half")
        d.flash = false
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(o.win.__shown, "the grid's LOS flash off: the overheal word has its own setting, still on")
        sp2.heal.__scripts.OnLeave(sp2.heal)
        d.flash = true
        -- WHAT DECIDES IT, CHANGEABLE: any = the whole heal, half, 75% = a quarter of it against what they miss
        NS.DO.overword("any")
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(o.bar:GetValue() == 1100, "any overheal: the whole heal against what they miss", o.bar:GetValue())
        sp2.heal.__scripts.OnLeave(sp2.heal)
        NS.DO.overword("75%")
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(o.bar:GetValue() == 275, "75%: a quarter of the heal against what they miss", o.bar:GetValue())
        sp2.heal.__scripts.OnLeave(sp2.heal)
        NS.DO.overword("half")
        local row
        for _, r in ipairs(NS.UI.Rows()) do if r.key == "overword" then row = r end end
        ok(row and row.kind == "step" and row.min == 1 and row.max == 4 and row.show() == "half" and row.help == OV.HELP
           and row.help:find("tooltip", 1, true) and row.help:find("heals on their way", 1, true),
           "the options: an 'overheal word' row, < half > arrows over off / any / half / 75%, its help saying what decides it")
        -- the box shows three lines of about 125 letters (Arn's screenshot, 12 Nov); the long help (560) ran off it
        ok(#row.help <= 300, "its help fits the box (Arn's screenshot: the long one ran off the bottom): " .. #row.help)
        local O = _G.BiSTheme and _G.BiSTheme.OPTIONS
        ok(O and 2 * O.STEP_W + O.STEP_V + 6 <= O.CTL, "arrows fit the kit's control space (four or five buttons ran into the label)")
        if row then row.set(nil, 2) end
        ok(d.overMode == "any" and row.show() == "any", "the arrows set it")
        NS.DO.overword("half")
        -- WHICH BUTTON A HOVER JUDGES (Arn: "some people might want something else other than left click")
        FM.Set("", "middle", "Healing Wave(Rank 1)")
        local brow
        for _, r in ipairs(NS.UI.Rows()) do if r.key == "overbutton" then brow = r end end
        ok(brow and brow.kind == "step" and brow.max == 5 and brow.show() == "left", "a 'hover heal' row: < left > to start")
        brow.set(nil, 3)
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(d.overButton == "middle" and o.bar:GetValue() == 20.75, "wheel: a hover judges the wheel click's heal", o.bar:GetValue())
        sp2.heal.__scripts.OnLeave(sp2.heal)
        ok(NS.DO.overbutton("left") == "left" and d.overButton == "left", "/bish overbutton left")
        -- NATURE'S SWIFTNESS ON THE LEFT (Arn, 12 Nov: "my cousin has nature swiftness over his heal on his left so its not
        -- showing overheal"): the hover button holds no heal -> the next button that does
        local ranksNoNS = FM.Ranks
        FM.Ranks = function(n)
            if n == "Nature's Swiftness" then return { { rank = "", spell = 16188 } } end
            return ranksNoNS(n)
        end
        TEXT[16188] = "When activated, your next Nature spell with a casting time less than 10 sec. becomes an instant cast spell."
        FM.Set("", "left", "Nature's Swiftness")
        OV.Forget()
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(o.win.__shown and o.bar:GetValue() == 20.75,
           "Nature's Swiftness on the left: a hover judges the next button with a heal (right = Renew, a HoT, skipped; the wheel's Rank 1)",
           o.bar:GetValue())
        sp2.heal.__scripts.OnLeave(sp2.heal)
        FM.Clear("", "middle")
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(not o.win.__shown, "no button holds a heal we can judge: no word")
        sp2.heal.__scripts.OnLeave(sp2.heal)
        -- A MACRO: "/cast Nature's Swiftness" then "/cast Healing Wave" = the Healing Wave; the cast that comes first (NS,
        -- instant) does not cancel the click
        local mi = CreateMacro("NSWave", 134400,
            "#showtooltip\n/cast [@mouseover,help] Nature's Swiftness\n/cast [@mouseover,help][] !Healing Wave(Rank 7)", false)
        FM.Set("", "left", "macro:NSWave")
        local mh, mn = OV.Judge("macro:NSWave")
        ok(mh == 1100 and mn == "Healing Wave" and OV.HealOf("macro:NSWave") == 1100,
           "a macro bind: the first heal its /cast lines name (conditions and ! read past)", tostring(mh) .. " " .. tostring(mn))
        sp2.heal.__scripts.OnEnter(sp2.heal)
        ok(o.win.__shown and o.bar:GetValue() == 550, "hovering with the macro on the left: the Healing Wave's half", o.bar:GetValue())
        local nsName = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) if id == 16188 then return "Nature's Swiftness" end return nsName(id) end
        sp2.heal.__scripts.PostClick(sp2.heal, "LeftButton", true)
        fire(OV.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-ns", 16188)
        ok(OV.pending and not o.flashUntil, "the macro's Nature's Swiftness goes off first: the click still waits for its heal")
        fire(OV.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-hw", 8005)
        ok(o.flashUntil and OV.pending == nil, "then the instant Healing Wave: the click's word flashes")
        o.flashUntil = nil
        sp2.heal.__scripts.OnLeave(sp2.heal)
        C_Spell.GetSpellName = nsName
        EditMacro(mi, "NSWave", 134400, "/cast Nature's Swiftness")
        ok(OV.Judge("macro:NSWave") == nil, "a macro with no heal in it: nothing judged (its body is read again each time)")
        MACROS[mi] = nil
        ok(OV.Judge("macro:NSWave") == nil, "a macro that is gone: nothing")
        FM.Ranks = ranksNoNS
        FM.Set("", "left", "Healing Wave(Rank 7)")
        OV.Forget()
        -- THE GRID'S HOVER PREVIEW (Arn, 12 Nov: "when we send a heal it shows the incoming heal so we can guage how much
        -- its going to heal, can we add that to hover as well"): your hover heal after the incoming band, fainter
        do
            local FG = NS.FG
            local cell
            for _, c in ipairs(FG.frames) do if c.unit == "party1" then cell = c end end
            cell = cell or FG.frames[2]
            local keepUnit = cell.unit
            cell.unit = cell.unit or "party1"
            ok(cell.preview and not cell.preview.__shown, "a grid cell has a hover preview band, hidden")
            local pp = cell.preview.points[1]
            ok(pp and pp[2] == cell.incoming:GetStatusBarTexture() and pp[3] == "TOPRIGHT" and cell.preview:GetParent() == cell.healClip,
               "it starts where the heals on their way end, in the same clip (stops at the cell's edge)")
            cell.__scripts.OnEnter(cell)
            ok(cell.preview.__shown and cell.preview:GetValue() == 1100 and select(2, cell.preview:GetMinMaxValues()) ~= nil,
               "the mouse on a cell: your hover heal (Healing Wave Rank 7, 1100) against their max", cell.preview:GetValue())
            local pc, ic = cell.preview.__color or {}, cell.incoming.__color or {}
            ok(pc[1] == ic[1] and pc[2] == ic[2] and pc[3] == ic[3] and pc[4] == FG.PREVIEW_ALPHA and (ic[4] or 1) > pc[4],
               "the incoming band's colour, fainter")
            STATE.shift = true
            fire(OV.events, "MODIFIER_STATE_CHANGED")
            ok(cell.preview:GetValue() == 41.5, "holding shift: shift-left's heal", cell.preview:GetValue())
            STATE.shift = false
            fire(OV.events, "MODIFIER_STATE_CHANGED")
            fire(OV.events, "UNIT_SPELLCAST_START", "player", "cast-g", 8005)
            ok(not cell.preview.__shown, "your cast starts: the preview steps aside (the incoming band carries it now)")
            fire(OV.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-g", 8005)
            ok(cell.preview.__shown, "it lands: the preview is back while you still hover")
            cell.__scripts.OnLeave(cell)
            ok(not cell.preview.__shown and OV.cell == nil, "the mouse leaves: gone")
            NS.DO.overword("off")
            cell.__scripts.OnEnter(cell)
            ok(cell.preview.__shown, "the OVER/H word switched off: the preview still shows (its own thing)")
            cell.__scripts.OnLeave(cell)
            NS.DO.overword("half")
            cell.unit = keepUnit
        end
        TEXT[8005] = secretString()
        OV.Forget()
        ok(OV.HealOf("Healing Wave(Rank 7)") == nil, "a secret tooltip is never read: no size, no word")
        TEXT[8005] = "Heals a friendly target for 1,000 to 1,200."
        OV.Forget()
        -- LEAN: hovering, ten health changes on that unit; nothing at all for anyone else
        local okC, Cost = pcall(dofile, "../_bisdev/dev/cost.lua")
        if not okC then okC, Cost = pcall(dofile, "../../_bisdev/dev/cost.lua") end
        if okC then
            sp2.heal.__scripts.OnEnter(sp2.heal)
            local n, by = Cost.Count(function() for _ = 1, 10 do fire(OV.events, "UNIT_HEALTH", "party1") end end)
            print(("   cost: OVER word, hovering, 10 health changes = %d calls (%s)"):format(n, Cost.Top(by, 3)))
            ok(n <= 60, "hovering a pip through 10 health changes: a few calls each", n)
            sp2.heal.__scripts.OnLeave(sp2.heal)
            local n2 = Cost.Count(function() for _ = 1, 10 do fire(OV.events, "UNIT_HEALTH", "party2") end end)
            ok(n2 == 0, "nobody hovered: other units' health costs nothing", n2)
        end
        FM.Ranks, C_Spell.GetSpellDescription, C_Spell.GetSpellName, _G.UnitHealthMissing = keep.ranks, keep.desc, keep.name, keep.miss
        d.flash, d.overWord = keep.flash, keep.over
        for _, b in ipairs({ { "", "left", keep.left }, { "shift-", "left", keep.sleft }, { "", "right", keep.right } }) do
            if b[3] then FM.Set(b[1], b[2], b[3]) else FM.Clear(b[1], b[2]) end
        end
        OV.Forget()
    end

    -- the pip's colour: the client's, from their health through our curve - hidden full, green, amber, red
    local function shade(sp)
        RD.PaintHeal(sp)
        local c = sp.paintTex[1].__vertex or sp.paintTex[1].vertex or sp.paintTex[1].__color
        return c
    end
    local function alphaOf(sp) local c = shade(sp) return c and c[4] end
    local function colourOf(sp) local c = shade(sp) return c and c[1], c and c[2] end
    STATE.hp.party1 = 0.97
    ok(alphaOf(sp2) == 0, "nearly full: invisible", tostring(alphaOf(sp2)))
    STATE.hp.party1 = 0.85
    local r, g = colourOf(sp2)
    ok(alphaOf(sp2) == 1 and g and g > 0.9 and r < 0.5, "below 90%: green - hurt, can wait")
    STATE.hp.party1 = 0.6
    r, g = colourOf(sp2)
    ok(r == 1 and g and g > 0.6 and g < 0.8, "below your heal's size (unknown here: 80%): amber - click now")
    STATE.hp.party1 = 0.2
    r, g = colourOf(sp2)
    ok(r == 1 and g and g < 0.3, "under 35%: red - drop everything")
    local rg = sp2.redGlyph and sp2.redGlyph[1]
    ok(rg and (rg.__vertex or rg.vertex or {})[4] ~= 0 and sp2.pulse, "and the red glyph's own layer pulses (the client's animation)")
    STATE.hp.party1 = 0.6
    RD.PaintHeal(sp2)
    ok(((rg.__vertex or rg.vertex or {})[4] or 0) == 0, "amber: the red layer is invisible - only red blinks")
    -- ARN'S WHITE BLADE (8 Nov: "this white pip showed up and nothing when i click it and not going away"): the signs are
    -- plain textures (never Lines), born invisible; no colour back, or nobody there, means nothing at that spot
    local lines = 0
    for _, t in ipairs(sp2.glyph) do if rawget(t, "SetStartPoint") then lines = lines + 1 end end
    ok(lines == 0, "every role sign is plain textures - the colour lands on them", lines)
    local born = RD.Spoke(9)
    ok(born and born.heal.face, "a spoke made fresh")
    local keepHP = _G.UnitHealthPercent
    _G.UnitHealthPercent = function() return nil end
    sp2.heal.face:SetAlpha(1)
    RD.PaintHeal(sp2)
    ok(sp2.heal.face:GetAlpha() == 0, "no colour back from the client: the pip hides, never a stale white sign")
    _G.UnitHealthPercent = keepHP
    STATE.units.party1 = nil
    RD.PaintHeal(sp2)
    ok(sp2.heal.face:GetAlpha() == 0, "they left the party (the re-layout waits): nothing at their spot")
    -- ARN'S AMBER SWORD (11 Nov: "left group still icons remain ... during combat"): the red and amber copies are their
    -- own layers - they go dark with the face
    ok(sp2.heal.amberFace:GetAlpha() == 0 and sp2.heal.redFace:GetAlpha() == 0,
       "and their amber and red copies too - no stale sword")
    STATE.units.party1 = true
    STATE.hp.party1 = 0.6
    RD.PaintHeal(sp2)
    ok(sp2.heal.face:GetAlpha() == 1 and sp2.heal.amberFace:GetAlpha() == 1, "back: their pip again")
    -- a roster change IN a fight: the layout waits, but the pip of whoever left goes dark at once
    STATE.inCombat = true
    STATE.units.party1 = nil
    fire(RD.events, "GROUP_ROSTER_UPDATE")
    ok(RD.pending and sp2.heal.face:GetAlpha() == 0 and sp2.heal.amberFace:GetAlpha() == 0,
       "left mid-fight: the re-layout waits, their pip goes dark now")
    STATE.inCombat = nil
    STATE.units.party1 = true
    fire(RD.events, "PLAYER_REGEN_ENABLED")
    -- dead: every face dark (the red copy would light at 0%)
    STATE.dead.party1 = true
    RD.PaintHeal(sp2)
    ok(sp2.heal.face:GetAlpha() == 0 and sp2.heal.redFace:GetAlpha() == 0 and sp2.heal.amberFace:GetAlpha() == 0,
       "dead: the face and both copies dark")
    STATE.dead.party1 = nil
    RD.PaintHeal(sp2)
    ok(sp2.heal.face:GetAlpha() == 1, "alive again: lit")

    -- NO BOXES, AND YOU IN THE MIDDLE (Arn 8 Nov: "the box outlines are not needed if we want to heal ourselves we are in
    -- the middle and stuff build out from us")
    ok(sp2.heal.edges == nil and #sp2.paintTex == #sp2.glyph, "a pip is its role glyph alone - no box round it")
    -- THE GAME'S ROLE FIRST (Arn 8 Nov: "tank shows up as a sword instead of a shield")
    local keepRoles = STATE.roles
    STATE.roles = { party1 = "TANK" }
    ok(RD.Role("party1") == "tank", "the game says party1 tanks: a tank")
    fire(RD.events, "PLAYER_ROLES_ASSIGNED")
    ok(sp2.role == "tank" and #sp2.glyph == 4, "a role set: their pip's sign becomes the tank's diamond", tostring(sp2.role))
    STATE.roles = { party1 = "HEALER" }
    ok(RD.Role("party1") == "heal", "HEALER: the cross")
    STATE.roleSecret = true
    ok(pcall(RD.Role, "party1"), "a secret role (a fight) is never read - the old rules answer")
    STATE.roleSecret, STATE.roles = nil, keepRoles
    fire(RD.events, "PLAYER_ROLES_ASSIGNED")
    ok(RD.dims:GetAlpha() == 0, "and no dim slot outlines, in or out of a fight")
    local mx, my = RD.Point(sp1.slot, sp1.slot.rh)
    ok(sp1.slot.self and math.abs(mx) < 0.01 and math.abs(my) < 0.01, "your heal pip is the centre")
    local cx, cy = RD.Point(sp1.slot, sp1.slot.rc)
    ok(math.abs(cx) < 0.01 and cy > 0 and cy < RD.PARTY.rh, "your cure just above you")
    local diag = true
    for i = 2, 5 do
        local b = RD.slots[i].b % (math.pi / 2)
        if math.abs(b - math.pi / 4) > 0.01 then diag = false end
    end
    ok(diag, "your party builds out from you on the four diagonals")

    -- RATIONS: the tools box's food (Arn 8 Nov: "bis tool still shows the eat food icon in the toolbox but its not in the
    -- radar"): BiSToolsAPI.FoodNow first, the radar's own rule only without it
    local keepAPI = _G.BiSToolsAPI
    _G.BiSToolsAPI = { major = 1, version = 7, FoodNow = function() return 5477 end }
    ok(RD.FoodWanted() == 5477, "BiS Tools says eat the stew: the radar offers the stew")
    _G.BiSToolsAPI.FoodNow = function() return nil, "not now" end
    ok(RD.FoodWanted() == nil, "BiS Tools says not now: neither does the radar")
    _G.BiSToolsAPI.FoodNow = function() return 5477 end
    RD.Arm()
    ok(RD.rations.item == 5477 and RD.rations:GetAttribute("*macrotext1") == "/use item:5477", "armed: a click eats it")
    -- A KNOWN HEAL SIZE AGAINST A HIDDEN MAX HEALTH (Arn's BugSack 8 Nov: "attempt to compare local 'mx' (a secret
    -- number value)" at Radar.lua's armHeal - his heal read 182.5, so the compare ran; ours read nothing and skipped it)
    local keepDesc = C_Spell.GetSpellDescription
    C_Spell.GetSpellDescription = function() return "Heals a friendly target for 170 to 195." end
    RD.healAmount = nil
    ok(RD.HealAmount() == 182.5, "the heal's size read off its own words", tostring(RD.HealAmount()))
    local okHide, whyHide = pcall(RD.Arm)
    ok(okHide and sp2.amber == RD.AMBER, "party1's max health is secret: amber falls back to 80%, nothing compared",
       tostring(whyHide))
    C_Spell.GetSpellDescription = keepDesc
    RD.healAmount = nil
    -- THE SHIELD PIP IS NOT THE REMINDER'S SWITCH (Arn 8 Nov: "i dont have water shield where is the button on my radar" -
    -- his buff reminder was off): the class's shield is watched either way, once it is trained
    local keepSB, keepBook = d.selfBuffs, BOOK[21]
    BOOK[21] = { name = "Water Shield", rank = "Rank 1" }
    if NS.FM and NS.FM.Invalidate then pcall(NS.FM.Invalidate) end
    d.selfBuffs = { none = true }
    ok(#NS.FS.List() == 0, "the buff reminder is off")
    ok(RD.ShieldTarget() == "Water Shield", "the radar still watches Water Shield", tostring(RD.ShieldTarget()))
    RD.Arm()
    ok(RD.shield.shieldName == "Water Shield" and RD.shield:GetAttribute("*macrotext1") == "/cast Water Shield",
       "the refuel pip is armed: a click casts it")
    -- ASKED DIRECTLY (Arn 8 Nov: "water shield missing again" - the container's hook alone was missed): FS.Present decides
    local keepPresent = NS.FS.Present
    NS.FS.Present = function() return false end
    fire(RD.events, "UNIT_AURA", "player")
    ok(RD.shield.face:GetAlpha() == 1, "Water Shield gone: the refuel pip lights at the next aura change")
    -- THE REMINDER'S ROAD (Arn 8 Nov: "watershield reminder used to work in combat"): the red is ALWAYS under, and the
    -- client's own button covers it while the shield is up - nothing of ours decides "missing", so a fight cannot fool it
    NS.FS.Present = function() return true end
    fire(RD.events, "UNIT_AURA", "player")
    ok(RD.shield.face:GetAlpha() == 1, "the shield up: the red stays drawn underneath (the client's cover hides it)")
    NS.FS.Present = function() return nil end
    fire(RD.events, "UNIT_AURA", "player")
    ok(RD.shield.face:GetAlpha() == 1, "the client will not say (a fight): the red still under, never switched off")
    NS.FS.Present = keepPresent
    local slot = RD.shield.container and RD.shield.container.slots and RD.shield.container.slots["BiSRadarShield"]
    ok(slot and slot.opts.candidateFilters.includeSpellIDs and next(slot.opts.candidateFilters.includeSpellIDs),
       "the client's aura slot, filtered to the shield's own spell ids")
    local cov = RD.shield.cover
    -- THE STABILIZER (Arn 8 Nov: "i dont want a shield icon i want an icon that a jet pilot would see ... call it
    -- stabilizer"): one cockpit symbol, red under, a green copy over it piece for piece
    local red = RD.shield.gyroRed
    ok(red and #red == RD.GYRO_SEG + 4, "the red stabilizer symbol under the pip")
    -- NOTHING TO CLICK WHILE IT IS UP (Arn 8 Nov: "this stabilizer is 3/3 it needs to go away or ill keep trying to click
    -- it"): the client's button is one plain square in the plate's dark, over a plate of the same dark
    local c1 = type(cov) == "table" and cov[1]
    local cc = c1 and (c1.__vertex or {}) or {}
    local pc = RD.shield.plate and (RD.shield.plate.__vertex or {}) or {}
    ok(c1 and #cov == 1 and c1.__allpoints and cc[1] == RD.PLATE[1] and cc[2] == RD.PLATE[2] and cc[4] == 1,
       "the cover: one square the whole pip, opaque, in the plate's dark - it hides the red whole")
    ok(pc[1] == RD.PLATE[1] and pc[2] == RD.PLATE[2], "and the plate under it the same dark: up, you see no symbol at all")
    -- THE RAILS, OUTSIDE THE SQUARE (Arn 8 Nov: "pop out the rail to the left of the radar square and the gauge too in
    -- its own rail"): solid strips in the cover's own dark, so the covered stabilizer is part of its rail
    local tr, gr = RD.toolRail, RD.gaugeRail
    local function dark(r) local c = r and r.bg and (r.bg.__vertex or {}) or {} return c[1] == RD.PLATE[1] and c[2] == RD.PLATE[2] and c[4] == 1 end
    ok(tr and gr and dark(tr) and dark(gr), "two solid rails in the cover's own dark")
    local tp = tr.__points and tr.__points[1] or (tr.points and tr.points[1])
    local gp = gr.__points and gr.__points[1] or (gr.points and gr.points[1])
    ok(tp and tp[1] == "TOPRIGHT" and tp[3] == "TOPLEFT" and gp and gp[2] == tr and gp[3] == "TOPLEFT",
       "outside the square on its left: the tool rail beside it, the gauge's rail beyond that")
    ok(RD.shield.tip and RD.shield.tip[1] == "STABILIZER" and RD.shield.tip[2]:find("Water Shield", 1, true),
       "under the mouse: STABILIZER, and which spell it casts")
    ok(not RD.shield.icon:IsShown(), "no spell picture")
    -- THE POP UNDER THE MOUSE (Arn 8 Nov: "make the icons pop a little so i know im hovering over the right icon"): a
    -- white ring round whatever is under the mouse - a heal pip, a bogey, a cure pip, a corner system
    local function hover(btn)
        local s = btn.__scripts or btn.scripts or {}
        local enter, leave = s.OnEnter, s.OnLeave
        if enter then enter(btn) end
        local on = btn.halo and btn.halo:GetAlpha()
        if leave then leave(btn) end
        local off = btn.halo and btn.halo:GetAlpha()
        return on, off
    end
    -- ...AND THEN TAKEN OFF (Arn 8 Nov: "it kills the immersion when i am moving the mouse over empty spaces and it shows
    -- where something will light up ... might make them want to click that place"): the ring is built but never shown
    ok(RD.HALO_ON == false, "the hover ring is switched off")
    for what, btn in pairs({ heal = sp2.heal, bogey = sp2.bogey, cure = sp2.cures[1] and sp2.cures[1].box,
                             stabilizer = RD.shield, fuel = RD.fuel }) do
        local on, off = hover(btn)
        ok(btn.halo and #btn.halo.ring == RD.HALO_SEG and on == 0 and off == 0,
           "the mouse over the " .. what .. ": no ring - an empty spot never says something lives there", tostring(on) .. "/" .. tostring(off))
    end
    RD.HALO_ON = true
    local on1 = hover(sp2.heal)
    ok(on1 == 1, "switched back on, it would pop again (kept, not deleted)")
    RD.HALO_ON = false
    STATE.inCombat = true
    local okFight = pcall(hover, sp2.heal)
    ok(okFight, "in a fight too: only the ring's alpha changes, nothing secure is touched")
    STATE.inCombat = false
    ok((RD.shield.container:GetFrameLevel() or 0) > (RD.shield:GetFrameLevel() or 0), "drawn over the red")
    d.selfBuffs, BOOK[21] = keepSB, keepBook
    RD.Arm()
    _G.BiSToolsAPI = keepAPI
    RD.Arm()

    -- A FIGHT: everything quiet - the scope, the empty places, the idle bogeys - and nothing secure is touched
    STATE.inCombat = true
    fire(RD.events, "PLAYER_REGEN_DISABLED")
    ok(RD.scope:GetAlpha() == 1 and RD.dims:GetAlpha() == 0, "a fight: the scope stays (Arn: \"i like this green outline in combat too\"), the empty places are not drawn")
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 0, "an idle bogey: invisible, but in its place")
    -- ARN'S FOUR RED TRIANGLES, OUT OF A FIGHT (8 Nov): hidden by the LINES' colour, not only the face's frame alpha
    local function lineAlpha(sp)
        local l = sp.bogey.lines and sp.bogey.lines[1]
        local c = l and (l.color or l.__vertex or l.vertex) or {}
        return c[4]
    end
    for i = 1, 5 do
        local s5 = RD.spokes[i]
        if s5 and s5.bogey.lines then ok(lineAlpha(s5) == 0, "idle bogey " .. i .. ": its lines are see-through too") end
    end
    STATE.casting.party1target = true
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 0 and lineAlpha(sp2) == 0,
       "a 'cast' on a target that does not exist lights nothing (nobody there is never casting)")
    STATE.units.party1target = true
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 0, "their target casts but it is a friend: nothing to kick (enemies only, 10 Nov)")
    STATE.hostile.party1target = true
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 1 and lineAlpha(sp2) == 1, "their target casts: the bogey shows - flare it")
    STATE.hostile.party1target = nil
    STATE.casting.party1target = nil
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 0, "and goes when the cast does")
    -- THEIR TARGET WHERE THE INTERRUPT LIVES (Arn 8 Nov: "a pip for their target where the interrupt button would live"):
    -- a quiet phosphor triangle while they have a hostile target; red when it casts
    STATE.units.party1target, STATE.hostile.party1target = true, true
    RD.Look()
    local tri = sp2.bogey.lines and sp2.bogey.lines[1]
    local tc = tri and (tri.color or tri.__vertex or tri.vertex) or {}
    ok(sp2.bogey.face:GetAlpha() == 0, "a hostile target, not casting: nothing (Arn: \"why is it showing interrupt buttons when its not casting\")",
       tostring(sp2.bogey.face:GetAlpha()))
    RD.CONTACT_SHOWN = true
    RD.Look()
    tc = tri and (tri.color or tri.__vertex or tri.vertex) or {}
    ok(sp2.bogey.face:GetAlpha() == RD.CONTACT[4] and tc[2] and tc[2] > 0.9, "(the quiet green contact, if ever switched back on)")
    RD.CONTACT_SHOWN = false
    STATE.casting.party1target = true
    RD.Look()
    tc = tri and (tri.color or tri.__vertex or tri.vertex) or {}
    ok(sp2.bogey.face:GetAlpha() == 1 and tc[1] == 1 and tc[2] < 0.3, "it casts: red - flare it")
    STATE.casting.party1target = nil
    STATE.hostile.party1target = nil
    RD.Look()
    ok(sp2.bogey.face:GetAlpha() == 0, "a friendly target: nothing")
    STATE.units.party1target = nil
    ok(sp2.bogey:GetAttribute("type2") == "target" and sp2.bogey:GetAttribute("unit") == "party1target",
       "a right-click on it targets their target")

    -- THE RIGHT RAIL: CHAFF (Arn 9 Nov: "an interrupt needs to target the specific unit, if it's on cool down, our
    -- grounding totem lights up on the right rail it needs no target it just needs to know the flare missed - deploy
    -- chaff, last resort catch all") and THE PILOT'S KNOBS ("we can turn off from the rail without having to go into
    -- the setting")
    do
        local keep = { b48 = BOOK[48], b49 = BOOK[49], name = C_Spell.GetSpellName, cd = C_Spell.GetSpellCooldown }
        local c = RD.chaff
        ok(c and c.rail == RD.defRail and RD.defRail and RD.defRail:IsShown() and not c.macro,
           "no Grounding Totem trained: the chaff is in its place on the right rail, the rail still shown (always), nothing armed")
        ok(c.knob and not c.knob:IsShown(), "and no knob on a tool that is not there")
        BOOK[48] = { name = "Grounding Totem", rank = "" }
        BOOK[49] = { name = "Earth Shock", rank = "Rank 1" }
        NS.FM.BookChanged()
        NS.FG.kickSpell, NS.FG.backupSpell = nil, nil
        STATE.inCombat = true
        ok(RD.ArmChaff() == false and not c.macro, "trained mid-fight: nothing secure is written (it waits)")
        STATE.inCombat = false
        RD.ArmTools()
        ok(c.macro == "/cast Grounding Totem" and c:GetAttribute("*macrotext1") == "/cast Grounding Totem"
           and c.tip and c.tip[1] == "CHAFF", "Grounding Totem trained: the chaff casts it, no target", tostring(c.macro))
        ok(RD.defRail:IsShown() and c.knob:IsShown(), "the right rail shows, the knob on its corner")
        STATE.inCombat = true
        C_Spell.GetSpellName = function(id) return ({ [8042] = "Earth Shock", [8050] = "Flame Shock",
                                                      [8177] = "Grounding Totem", [331] = "Healing Wave" })[id] end
        local function chaffLit()
            local v = c.pieces[1].__vertex
            return c.face:GetAlpha() == 1 and v and v[4] == 1 or false
        end
        RD.readyAt.kick, RD.readyAt.chaff = nil, nil
        STATE.units.party1target, STATE.hostile.party1target, STATE.casting.party1target = true, true, true
        RD.Look()
        ok(sp2.bogey.face:GetAlpha() == 1 and not chaffLit(), "an enemy casts, your flare is ready: the bogey lights, the chaff waits")
        ok(RD.OnCast("player", 8042) == "kick" and RD.readyAt.kick == CLOCK + RD.COOLS.kick, "you flare it: our own clock spends the flare 6 s")
        RD.Look()
        ok(chaffLit(), "the flare spent, still casting: the chaff lights - deploy it")
        STATE.casting.party1target = nil
        RD.Look()
        ok(not chaffLit(), "the cast is over: dark")
        STATE.casting.party1target, STATE.hostile.party1target = true, nil
        RD.Look()
        ok(not chaffLit(), "a FRIENDLY target casting: nothing to ground")
        STATE.hostile.party1target = true
        ok(RD.OnCast("player", 8177) == "chaff" and RD.readyAt.chaff == CLOCK + RD.COOLS.chaff and not chaffLit(),
           "you drop Grounding Totem: dark at once, spent 15 s by our clock")
        RD.Look()
        ok(not chaffLit(), "still casting, flare and chaff both spent: nothing to click")
        TICK(16)
        RD.Look()
        ok(not chaffLit(), "16 s on: both ready again - the flare is the answer, not the chaff")
        ok(RD.OnCast("player", 8050) == "kick", "a Flame Shock spends Earth Shock's cooldown too (the shocks share one)")
        RD.Look()
        ok(chaffLit(), "so the chaff lights")
        ok(RD.OnCast("player", 331) == false, "a heal is neither")
        -- THE KNOB: a plain button, so it flips in a fight
        local okClick = pcall(c.knob:GetScript("OnClick"), c.knob)
        ok(okClick and RD.KnobOff("chaff"), "a click on the chaff's knob mid-fight: switched off, nothing secure touched")
        local kv = c.knob.dot.__vertex
        ok(kv and kv[1] == 1 and kv[2] < 0.3 and kv[4] == 1, "the knob shows red: off")
        RD.Look()
        ok(not chaffLit(), "switched off: it never lights, even with a cast on its way")
        c.knob:GetScript("OnClick")(c.knob)
        RD.Look()
        ok(not RD.KnobOff("chaff") and chaffLit(), "clicked again: on, and lit")
        kv = c.knob.dot.__vertex
        ok(kv and kv[4] < 0.5, "a faint dot when on")
        -- every self-lighting tool has one (the stabilizer and the rations: always wanted, no knob)
        ok(RD.tide.knob and RD.potion.knob and RD.reserve.knob and RD.fuel.knob and not RD.shield.knob and not RD.rations.knob,
           "knobs on Mana Tide, the potion, the reserve tank, the drink and the chaff")
        RD.Command("knob reserve off")
        ok(RD.KnobOff("reserve"), "/bish alpha radar knob reserve off: the same switch")
        RD.Command("knob reserve on")
        ok(not RD.KnobOff("reserve"), "and back on")
        -- out of a fight the chaff never lights
        local keepFight = RD.inFight
        RD.inFight, STATE.inCombat = nil, false
        RD.Look()
        ok(not chaffLit(), "out of a fight: dark")
        RD.inFight, STATE.inCombat = keepFight, true
        -- lean: the chaff's questions only while it could light
        local Cost = dofile("../_bisdev/dev/cost.lua")
        local lookC = Cost.Count(function() RD.Look() end)
        print(("   cost: radar, one look with the chaff armed = %d calls"):format(lookC))
        ok(lookC <= 45, "a look with the chaff armed stays in its budget", lookC)
        STATE.casting.party1target, STATE.hostile.party1target, STATE.units.party1target = nil, nil, nil
        RD.readyAt.kick, RD.readyAt.chaff, RD.cdLen = nil, nil, {}
        BOOK[48], BOOK[49], C_Spell.GetSpellName, C_Spell.GetSpellCooldown = keep.b48, keep.b49, keep.name, keep.cd
        NS.FM.BookChanged()
        NS.FG.kickSpell, NS.FG.backupSpell = nil, nil
        STATE.inCombat = false
        RD.ArmTools()
        ok(RD.defRail:IsShown() and not RD.chaff.macro, "Grounding forgotten: the chaff disarmed, the rail stays (always shown)")
        STATE.inCombat = true
        RD.Look()
    end
    -- THE INTERRUPT'S SWEEP (Arn 8 Nov: "cooldown sweep on interrupt icon"): the client's duration object, untouched
    local keepDur2 = _G.C_Spell.GetSpellCooldownDuration
    local durObj2, asked2 = { kick = true }, nil
    -- the GCD sweeps ask for spell 61304 in the same event; the kick's own ask is the one checked here
    _G.C_Spell.GetSpellCooldownDuration = function(s) if s ~= 61304 then asked2 = s end return durObj2 end
    fire(RD.events, "SPELL_UPDATE_COOLDOWN")
    ok(sp2.bogey.cd and sp2.bogey.cd.__durObj == durObj2 and asked2 == NS.FG.KickSpell(),
       "your interrupt's cooldown runs as a sweep on the bogey, from the client's own object", tostring(asked2))
    ok(sp2.bogey.cd:GetParent() == sp2.bogey.face, "on the bogey's face: seen only while it shows")
    _G.C_Spell.GetSpellCooldownDuration = keepDur2
    -- CROSSHAIRS: TAKEN OFF (Arn 8 Nov: "no crosshairs" - "take them off"); the code is kept, checked switched on
    local keepIU0 = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) return b == "target" and a == "party1" end
    RD.PaintCross()
    ok(not RD.CROSSHAIRS and sp2.cross:GetAlpha() == 0, "off by default: no crosshairs on the radar")
    _G.UnitIsUnit = keepIU0
    RD.CROSSHAIRS = true
    -- CROSSHAIRS ON YOUR TARGET (Arn 8 Nov: "need a target pip indicated by crosshairs like on our regular frames")
    local keepIU = _G.UnitIsUnit
    _G.UnitIsUnit = function(a, b) return b == "target" and a == "party1" end
    RD.PaintCross()
    ok(sp2.cross:GetAlpha() == 1 and sp1.cross:GetAlpha() == 0 and sp2.bogeyCross:GetAlpha() == 0,
       "party1 is your target: the crosshair on their pip, nowhere else")
    _G.UnitIsUnit = function(a, b) return b == "target" and a == "party1target" end
    RD.PaintCross()
    ok(sp2.cross:GetAlpha() == 0 and sp2.bogeyCross:GetAlpha() == 1, "their target is yours: the crosshair on their bogey")
    ok(sp2.cross.cross and #sp2.cross.cross == 12, "the regular frames' own reticle: four corners, four ticks")
    -- TARGET OF TARGET (Arn 8 Nov: "target of target?"): you target the enemy, the amber reticle sits on who it is on
    _G.UnitIsUnit = function(a, b) return b == "targettarget" and a == "party1" end
    fire(RD.events, "UNIT_TARGET", "target")
    ok(sp2.totCross:GetAlpha() == 1 and sp2.cross:GetAlpha() == 0 and sp1.totCross:GetAlpha() == 0,
       "your target is on party1: the amber reticle on their pip")
    ok(sp2.totCross.tint and sp2.totCross.tint[2] < 0.8 and sp2.totCross.tint[1] == 1, "amber, apart from your magenta")
    local tw = sp2.totCross.__w or (sp2.totCross.GetWidth and sp2.totCross:GetWidth())
    local cw = sp2.cross.__w or (sp2.cross.GetWidth and sp2.cross:GetWidth())
    ok(tw and cw and tw > cw, "and a size bigger, so the two never cover each other", tostring(tw) .. " " .. tostring(cw))
    _G.UnitIsUnit = function(a, b) return b == "targettarget" and a == "player" end
    fire(RD.events, "UNIT_TARGET", "target")
    ok(sp1.totCross:GetAlpha() == 1 and sp2.totCross:GetAlpha() == 0, "it turns on you: the amber reticle moves to the centre")
    _G.UnitIsUnit = function() return secret() end
    local okS = pcall(RD.PaintCross)
    ok(okS, "a secret answer (inside an instance) goes to the client, never tested")
    _G.UnitIsUnit = keepIU
    RD.CROSSHAIRS = false
    RD.PaintCross()
    local okArm = pcall(RD.Arm)
    ok(okArm and RD.pending, "a re-arm mid-fight touches nothing secure, it waits (the mock refuses secure calls in combat)")
    local okRoster = pcall(fire, RD.events, "GROUP_ROSTER_UPDATE")
    ok(okRoster and RD.pending, "a roster change mid-fight: queued, no error")
    local Cost = dofile("../_bisdev/dev/cost.lua")
    local look = Cost.Count(function() RD.Look() end)
    print(("   cost: radar, one look (5 bogeys) = %d calls"):format(look))
    ok(look <= 40, "a look of a party stays in its budget", look)
    STATE.inCombat = false
    fire(RD.events, "PLAYER_REGEN_ENABLED")
    ok(not RD.pending and RD.scope:GetAlpha() == 1, "the fight ends: the queued re-arm runs, the scope is back")

    -- the drag ends before a fight takes the mouse (BiS Tools' boss window, the same night)
    f.__scripts.OnDragStart(f)
    ok(f.dragging, "dragging the radar")
    STATE.inCombat = true
    fire(RD.events, "PLAYER_REGEN_DISABLED")
    ok(not f.dragging and type(d.radar.pos) == "table", "a pull mid-drag: the drag ends and the spot is kept")
    STATE.inCombat = false
    fire(RD.events, "PLAYER_REGEN_ENABLED")

    -- the hidden setting: another heal, typed with its capitals
    SlashCmdList.BISHEALING("alpha radar heal Lesser Healing Wave")
    ok(RD.heal and RD.heal.cast == "Lesser Healing Wave(Rank 1)" and d.radar.heal == "Lesser Healing Wave",
       "/bish alpha radar heal Lesser Healing Wave: that heal (where amber starts), its top rank minus 2", RD.heal and RD.heal.cast)
    SlashCmdList.BISHEALING("alpha radar heal default")
    ok(RD.heal and RD.heal.cast == "Healing Wave(Rank 1)", "and back to the default")

    -- RAID SECTORS: 40 fixed slots, your own group on top and nearer the middle; a full 40
    _G.IsInRaid = function() return true end
    _G.GetNumGroupMembers = function() return 40 end
    _G.GetRaidRosterInfo = function(i) return "n" .. i, 0, math.ceil(i / 5) end
    _G.UnitIsUnit = function(a, b) return a == "raid12" and b == "player" end
    for i = 1, 40 do STATE.units["raid" .. i] = true end
    fire(RD.events, "GROUP_ROSTER_UPDATE")
    ok(RD.raid and RD.ownGroup == 3 and #RD.slots == 40 and #RD.spokes == 40, "a raid: 40 slots, you in group 3")
    local me = RD.slots[12]
    local mx2, my2 = RD.Point(me, me.rh)
    ok(me.self and math.abs(mx2) < 0.01 and math.abs(my2) < 0.01 and RD.spokes[12].heal:GetAttribute("unit") == "raid12",
       "in a raid too, you are the centre")
    -- THE FLEET (Arn, 11 Nov: "reimage the radar screen, for 10 20 40" - you the star destroyer, the best ships round you,
    -- the screen ships on the edge): rings by rank, not sectors by group
    do
    local band = { you = 0, core = 0, escort = 0, screen = 0 }
    for i = 1, 40 do local b = RD.slots[i].band band[b] = band[b] + 1 end
    ok(band.you == 1 and band.core == 4 and band.escort == 11 and band.screen == 24,
       "a full 40: you, the core four, eleven escorts, the screen of twenty-four", band.core .. "/" .. band.escort .. "/" .. band.screen)
    local core, screen
    for i = 1, 40 do
        if RD.slots[i].band == "core" then core = RD.slots[i] elseif RD.slots[i].band == "screen" then screen = RD.slots[i] end
    end
    ok(core.rb and core.own and core.rh < screen.rh and core.ph > screen.ph and not screen.rb,
       "the core on the inner ring, full size, with interrupts; the screen outermost, smallest, none")
    ok(f.__w == RD.FLEET[40].size or (f.GetWidth and f:GetWidth() == RD.FLEET[40].size),
       "the scope grows only a little: 370 for the capital (the old raid radar was 440)")
    end
    ok(RD.ship and RD.ship.key == "capital" and RD.gauge.ship.__text == "CAPITAL", "a full 40: the capital ship",
       RD.ship and RD.ship.key)
    -- PETS IN A RAID: your own group's only, nearer the middle on their owner's bearing
    do
    local ownPets, otherPets = 0, 0
    for i = 1, 40 do
        local sp = RD.spokes[i]
        if sp.petUnit then if sp.slot.own then ownPets = ownPets + 1 else otherPets = otherPets + 1 end end
    end
    ok(ownPets == 5 and otherPets == 0, "a raid: pets for you and the core only, none for the other 35", ownPets .. " / " .. otherPets)
    ok(RD.spokes[12].pet.__w == RD.PET.raidPx, "and smaller in a raid")
    end
    ok(math.abs((RD.fade.__w or 0) - RD.FADE_PX * RD.FLEET[40].size / RD.PARTY.size) < 0.01
       and RD.fade.__w == RD.fade.__h, "and the dark disc grows with the scope", RD.fade.__w)
    local rw = RD.FLEET[40].size + RD.TOOL_RAIL_W + RD.RAIL_GAP + RD.RightW() - RD.GAUGE.left - RD.GAUGE.right
    ok(RD.gauge:GetWidth() == rw and RD.gauge.lift.points[#RD.gauge.lift.points][4] == RD.BINGO * rw
       and RD.gaugeRail:GetWidth() == RD.FLEET[40].size + RD.TOOL_RAIL_W + RD.RAIL_GAP + RD.RightW(),
       "and the fuel tape with it: the top rail as wide as the raid's square, the BINGO lift still 30% of it", RD.gauge:GetWidth())
    -- every pip in its own place: no two slots on top of each other
    local clash = 0
    for i = 1, 40 do
        for j = i + 1, 40 do
            local a, b = RD.slots[i], RD.slots[j]
            local ax, ay = RD.Point(a, a.rh)
            local bx, by = RD.Point(b, b.rh)
            if math.abs(ax - bx) < (a.ph + b.ph) / 2 and math.abs(ay - by) < (a.ph + b.ph) / 2 then clash = clash + 1 end
        end
    end
    ok(clash == 0, "every heal pip has its own place in a full 40", clash)
    -- a 40-man repaint pass, and a look
    local paint = Cost.Count(function() RD.Paint() end)
    print(("   cost: radar, a 40-man repaint pass = %d calls"):format(paint))
    -- 12 Nov: the pips' tanks (Tanks.lua) add ~8 calls a person (349 -> 669); the budget tightened round that
    ok(paint <= 760, "a 40-man repaint stays in its budget", paint)
    STATE.inCombat = true
    fire(RD.events, "PLAYER_REGEN_DISABLED")
    local look40 = Cost.Count(function() RD.Look() end)
    print(("   cost: radar, one 40-man look (5 bogeys, 40 spokes) = %d calls"):format(look40))
    ok(look40 <= 220, "a 40-man look stays in its budget", look40)
    -- a raid roster change mid-fight: refused and queued
    _G.GetRaidRosterInfo = function(i) return "n" .. i, 0, math.ceil((41 - i) / 5) end     -- the groups turned round
    local okR = pcall(fire, RD.events, "GROUP_ROSTER_UPDATE")
    ok(okR and RD.pending and RD.spokes[1].heal:GetAttribute("unit") == "raid1", "a raid roster change mid-fight: nothing moves, it waits")
    ok(RD.ship.key == "capital", "and the ship never changes mid-fight")
    STATE.inCombat = false
    fire(RD.events, "PLAYER_REGEN_ENABLED")
    ok(not RD.pending and RD.spokes[1].heal:GetAttribute("unit") == "raid36", "after the fight: the new roster in its places",
       RD.spokes[1].heal:GetAttribute("unit"))

    -- back to a party: the raid's extra spokes go away
    _G.IsInRaid, _G.GetNumGroupMembers, _G.GetRaidRosterInfo, _G.UnitIsUnit = keep.raid, keep.num, keep.info, keep.isu
    for i = 1, 40 do STATE.units["raid" .. i] = nil end
    fire(RD.events, "GROUP_ROSTER_UPDATE")
    ok(not RD.raid and #RD.slots == 5 and not RD.spokes[20].heal:IsShown() and RD.spokes[20].heal:GetAttribute("unit") == nil,
       "a party again: five spokes, the rest off")
    ok(RD.ship.key == "fighter" and RD.gauge.ship.__text == "FIGHTER", "and the fighter again")

    -- THE FUEL GAUGE (Arn 8 Nov: "my mana to track the boss health bar, if its at 50% I should be at 50% mana ... the delta
    -- indicates we are keeping pace or bingo fuel"). The GPU compares; Lua never does.
    do
        local g = RD.gauge
        local function sec(v) return getmetatable(v) == secretMeta end
        local function pt(fr, name)
            for _, p in ipairs(fr.points or {}) do if p[1] == name then return p end end
        end
        ok(RD.tape == nil, "the missile tape along the bottom is gone (Arn: \"the guage does the same thing\")")
        -- THE WHOLE RAIL ANSWERS THE MOUSE (Arn 8 Nov: "the tool tip is inconsistent only certain parts of the gauge light it up")
        local rail = RD.gaugeRail
        ok(rail and rail:IsMouseEnabled() and rail:GetScript("OnEnter") and rail:GetScript("OnLeave") and rail:GetScript("OnDragStart"),
           "the gauge's whole rail shows the FUEL card (not just the 7px tape), and still drags the radar")
        ok(g and g.boss and g.mana and g.ruler and g.hot, "the fuel tape: the boss, your mana, the BINGO ruler and its hot copy")
        -- SIDEWAYS ON TOP (Arn 9 Nov: "put it on top side ways that way only one rail per side")
        local railW = RD.SIZE + RD.TOOL_RAIL_W + RD.RAIL_GAP + RD.RightW()   -- over the right rail too (always shown)
        local rp0 = pt(rail, "BOTTOMLEFT")
        ok(rp0 and rp0[2] == RD.toolRail and rp0[3] == "TOPLEFT" and rp0[5] == RD.RAIL_GAP and rail:GetWidth() == railW
           and rail:GetHeight() == RD.GAUGE_RAIL_H, "the gauge's rail sits on top: over the tool rail and the square, as wide as both",
           rail:GetWidth())
        local p = pt(g, "BOTTOMLEFT")
        local W = railW - RD.GAUGE.left - RD.GAUGE.right
        ok(p and p[2] == RD.gaugeRail and p[4] == RD.GAUGE.left and p[5] == RD.GAUGE.base and g:GetWidth() == W
           and g:GetHeight() == RD.GAUGE.w, "the tape runs along it, between the placard and the ramjet", g:GetWidth())
        local G, H = RD.GAUGE, RD.HUD
        ok(G.base + G.w + 3 + H.boxH <= RD.GAUGE_RAIL_H - 1 and G.base - 1 - H.major - 1 - H.label >= 1,
           "the readout box above and the numbers under the tape both fit inside the rail")
        local allSide = true
        for _, s in ipairs({ g.boss, g.mana, g.ruler, g.hot }) do if s:GetOrientation() ~= "HORIZONTAL" then allSide = false end end
        ok(allSide, "every bar fills from the left")
        local tr0 = RD.toolRail
        local gaugeRails = 0
        for _, r in ipairs({ RD.toolRail, RD.defRail }) do if r == rail then gaugeRails = gaugeRails + 1 end end
        ok(gaugeRails == 0 and pt(tr0, "TOPRIGHT") and pt(RD.defRail, "TOPLEFT"), "one rail a side: tools on the left, defence on the right")
        local cl = RD.frame.__clamp
        ok(cl and cl[1] == -(RD.TOOL_RAIL_W + RD.RAIL_GAP) and cl[3] == RD.GAUGE_RAIL_H + RD.RAIL_GAP
           and cl[4] == -(NS.BB.RAIL_H + RD.RAIL_GAP),
           "the clamp keeps the left rail, the top rail and the black box's bottom rail on the screen", cl and table.concat(cl, " "))
        -- ONE HULL, SOFT EDGES (Arn, 10 Nov: "complete the rails so there are no gaps and alpha the edges"), and THE SQUARE
        -- CLOSED ("once its closed like a square rail recenter all the stuff"): the top and bottom rails over the right rail
        do
            local h = RD.hull
            ok(h and #RD.edges == RD.EDGE_N and RD.edges[1].a > RD.edges[RD.EDGE_N].a and RD.edges[RD.EDGE_N].a > 0,
               "one plate behind every rail and the square, and rings fading outward", RD.edges and #RD.edges)
            local keepShown = RD.defRail:IsShown()
            RD.defRail:Show() RD.ClampRails()
            local wide = RD.gaugeRail:GetWidth()
            RD.defRail:Hide() RD.ClampRails()
            local narrow = RD.gaugeRail:GetWidth()
            ok(math.abs(wide - narrow - (RD.RAIL_GAP + RD.TOOL_RAIL_W)) < 1e-9, "the right rail shown: the top rail runs over it",
               wide .. " / " .. narrow)
            RD.defRail:Show() RD.ClampRails()
            local bp = RD.bbRail.points and RD.bbRail.points[2]
            ok(bp and bp[1] == "TOPRIGHT" and bp[4] == RD.RightW(), "and the black box's rail too", bp and tostring(bp[4]))
            local hp = h.points and h.points[2]
            ok(hp and hp[1] == "BOTTOMRIGHT" and hp[2] == RD.bbRail, "the hull reaches the bottom rail's far corner")
            if keepShown then RD.defRail:Show() else RD.defRail:Hide() end
            RD.ClampRails()
        end
        -- the layering: boss under mana, ticks over both, the caret over all three, the BINGO window over that
        local L = function(x) return x:GetFrameLevel() end
        ok(L(g.boss) < L(g.mana) and L(g.mana) < L(g.tickFrame) and L(g.tickFrame) < L(g.caretFrame) and L(g.caretFrame) < L(g.hotClip),
           "boss < mana < ticks < caret < BINGO", L(g.boss) .. " " .. L(g.mana) .. " " .. L(g.tickFrame) .. " " .. L(g.caretFrame) .. " " .. L(g.hotClip))
        local cp = g.caret.points and g.caret.points[1]
        ok(cp and cp[2] == g.boss:GetStatusBarTexture() and cp[3] == "BOTTOMRIGHT" and rawget(g.caret, "__parent") == g.caretFrame
           and g.caret.__w == 3 and g.caret.__h > g:GetHeight(),
           "the magenta caret stands on the boss bar's FILL end, on its own layer over your mana")
        local Wt = g:GetWidth()
        ok(#g.ticks == 3 and g.ticks[2].from[1] == 0 and math.abs(g.ticks[1].from[1] + Wt / 4) < 0.01
           and g.ticks[1].from[1] == g.ticks[1].to[1], "ticks at 25 / 50 / 75, across the tape", g.ticks[1].from[1])
        -- BINGO: the ruler lifted 30% to the right and clipped to the tape; the window's floor on the ruler's fill end
        local lp = pt(g.lift, "BOTTOMLEFT")
        ok(lp and lp[2] == g and lp[4] == RD.BINGO * Wt and lp[5] == 0 and g.lift:GetWidth() == Wt
           and g.lift:GetParent() == g.rulerClip and g.rulerClip:DoesClipChildren() and g.rulerClip.__allpoints == g,
           "the BINGO ruler: your mana in a frame moved 30% of the tape along, clipped to the tape", lp and lp[4])
        local hp = pt(g.hotClip, "BOTTOMLEFT")
        local rp = pt(g.hotClip, "TOPRIGHT")
        ok(hp and hp[2] == g.ruler:GetStatusBarTexture() and hp[3] == "BOTTOMRIGHT" and g.hotClip:DoesClipChildren()
           and rp and rp[2] == g and rp[4] > RD.BINGO * Wt and rp[5] >= RD.GAUGE.flag,
           "the hot window's floor IS the ruler's fill end (mana + 30%), its roof past the tape's end")
        ok(g.hot.__allpoints == g and g.hot:GetParent() == g.hotClip and rawget(g.flag, "__parent") == g.flagFrame
           and g.flagFrame:GetParent() == g.hotClip, "the hot boss copy and its flag live inside that window - seen only above mana + 30%")
        -- the arithmetic the GPU does, from the recorded anchors: hot shows where boss > floor
        local h = g:GetWidth()
        local function hotBand(boss, mana) return boss * h - (lp[4] + mana * h) end
        ok(hotBand(0.70, 0.20) > 0 and hotBand(0.50, 0.50) < 0 and hotBand(0.70, 0.45) < 0,
           "Arn's numbers: boss 70% / you 20% = BINGO; 50 / 50 and 70 / 45 = keeping pace")
        local gp = g.pulse
        ok(gp and gp.playing and gp.looping == "BOUNCE" and gp.anims[1].kind == "Alpha" and gp.anims[1].to == RD.FADE_HARD[1],
           "BINGO pulses (a fade: its band is a clipped window, nothing in it is hidden by alpha)")

        -- WHO IT RACES: out of a fight with nothing targeted, nothing - just the mana tape, calm
        STATE.units.target, STATE.hostile.target = nil, nil
        fire(RD.events, "PLAYER_TARGET_CHANGED")
        ok(RD.fuelUnit == nil and g.bossLayer:GetAlpha() == 0 and g.chev:GetAlpha() == 0, "no boss, no fight: the mana tape alone, calm")
        STATE.units.target, STATE.hostile.target = true, true
        fire(RD.events, "PLAYER_TARGET_CHANGED")
        ok(RD.fuelUnit == "target" and g.bossLayer:GetAlpha() == 0, "a hostile target out of a fight: still calm")
        -- A FIGHT, every number secret: nothing compared, nothing worked out - only handed on
        STATE.inCombat = true
        local okPull = pcall(fire, RD.events, "PLAYER_REGEN_DISABLED")
        ok(okPull and g.bossLayer:GetAlpha() == 1, "the pull: the boss's red comes up on the tape")
        ok(sec(g.mana.__value) and sec(g.mana.__max) and sec(g.ruler.__value) and sec(g.boss.__value) and sec(g.boss.__max)
           and sec(g.hot.__value), "mana, boss and both copies: the client's secrets, handed untouched")
        ok(pcall(fire, RD.events, "UNIT_HEALTH", "target") and pcall(fire, RD.events, "UNIT_POWER_UPDATE", "player")
           and pcall(fire, RD.events, "UNIT_MAXPOWER", "player"), "health and mana ticks mid-fight: no error")
        STATE.hostileSecret = true
        ok(pcall(fire, RD.events, "PLAYER_TARGET_CHANGED") and g.bossLayer.__alphaFromSecret,
           "a secret \"hostile?\": the client picks the boss layer's alpha")
        STATE.hostileSecret = false
        STATE.hostile.target = false
        fire(RD.events, "PLAYER_TARGET_CHANGED")
        ok(g.bossLayer:GetAlpha() == 0, "a friendly target: no boss on the tape")
        STATE.units.boss1 = true
        fire(RD.events, "INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        ok(RD.fuelUnit == "boss1" and g.bossLayer:GetAlpha() == 1, "an encounter's boss1: the tape races the boss, whoever you target")
        local okTick = pcall(fire, RD.events, "UNIT_HEALTH", "boss1")
        ok(okTick and sec(g.boss.__value), "the boss's health tick: handed on")
        -- GENERATING FUEL: the chevron, from Regen.lua's own clock (your casts) - nothing secret asked
        local FR = NS.FR
        local keepSpent, keepKnown, keepMR = FR.spentAt, FR.known, _G.GetManaRegen
        _G.GetManaRegen = function() return secretNumber(), secretNumber() end
        FR.spentAt = nil
        ok(RD.PaintRegen() == 1 and g.chev:GetAlpha() == 1 and g.regen:GetText() == "100%",
           "out of the five second rule in a fight: the chevron lit, the readout 100%", g.regen:GetText())
        FR.known = { base = 10, casting = 3 }
        FR.Spend(GetTime())
        ok(math.abs(RD.PaintRegen() - 0.3) < 1e-9 and g.regen:GetText() == "30%",
           "inside it: dimmed to your while-casting share, and the readout says it (30%, the header's number)", g.regen:GetText())
        FR.known = nil
        ok(RD.PaintRegen() == 0 and g.regen:GetText() == "?", "inside it, nothing known: dark, the readout '?' (never a made-up number)")
        TICK(6)
        ok(RD.PaintRegen() == 1, "the five seconds run out: lit again (the ticker asks)")
        FR.known = { base = 10, casting = 3 }
        FR.Spend(GetTime())
        local keepFight, keepCombat = RD.inFight, STATE.inCombat
        RD.inFight = false
        STATE.inCombat = false
        ok(RD.PaintRegen() == 0 and g.regen:GetText() == "100%", "out of a fight the readout says 100%, even just after a cast", g.regen:GetText())
        STATE.inCombat, RD.inFight = keepCombat, keepFight
        TICK(6)
        local Cost = dofile("../_bisdev/dev/cost.lua")
        local rc, rby = Cost.Count(function() RD.PaintRegen() end)
        ok(rc <= 2 and not (rby or {}).GetManaRegen, "the chevron costs a clock read, and never asks the hidden regen", rc)
        local fc = Cost.Count(function() RD.PaintFuel() end)
        local bc = Cost.Count(function() fire(RD.events, "UNIT_HEALTH", "boss1") end)
        print(("   cost: radar fuel, a full repaint = %d calls, a boss health tick = %d"):format(fc, bc))
        ok(fc <= 14 and bc <= 8, "the fuel gauge stays in its budget (lean)", fc .. " / " .. bc)
        _G.GetManaRegen, FR.spentAt, FR.known = keepMR, keepSpent, keepKnown
        STATE.units.boss1, STATE.units.target, STATE.hostile.target = nil, nil, nil
        STATE.inCombat = false
        fire(RD.events, "PLAYER_REGEN_ENABLED")
        ok(RD.fuelUnit == nil and g.bossLayer:GetAlpha() == 0 and g.chev:GetAlpha() == 0, "the fight ends: calm again")
        local okTip = pcall(g.__scripts.OnEnter, g)
        local words = 0
        local digits = 0
        for _, fs in ipairs(LABELS) do
            local q = fs.__parent
            local t = fs.__text or ""
            while q do
                if q == g then
                    if t:match("^%d+$") or t == "(secret)" then digits = digits + 1 elseif t ~= "" then words = words + 1 end
                    break
                end
                q = q.__parent
            end
        end
        ok(okTip and #RD.FuelTip() >= 3 and words == 0, "its words live in the tooltip, none on the tape")
        -- THE HUD TAPE (Arn 8 Nov, a fighter HUD's speed tape: "the picture is an idea of how the guage should look")
        local hud, box = g.hud, g.readout
        local labs = {}
        for q2 = 0, 4 do labs[#labs + 1] = hud and hud.labels[q2] and hud.labels[q2].__text end
        ok(hud and #hud.ticks == 10 and table.concat(labs, ",") == "0,25,50,75,100", "the scale: a tick every 10%, numbers at 0/25/50/75/100")
        local bp = box and box.points and box.points[1]
        ok(bp and bp[1] == "BOTTOM" and bp[2] == g.mana:GetStatusBarTexture() and bp[3] == "TOPRIGHT" and bp[5] > 0,
           "the readout box rides the end of your fuel, above the tape")
        local tk5 = hud.ticks[5] and hud.ticks[5].points and hud.ticks[5].points[1]
        local lb2 = hud.labels[2] and hud.labels[2].points and hud.labels[2].points[1]
        ok(tk5 and tk5[1] == "TOP" and math.abs(tk5[4] - g:GetWidth() / 2) < 0.01 and lb2 and lb2[5] < 0
           and math.abs(lb2[4] - g:GetWidth() / 2) < 0.01, "the scale hangs under the tape: 50 sits under its middle")
        RD.PaintMana()
        local fmt = box.num.__formatted
        ok(fmt and fmt[1] == "%d", "and the client writes your mana % into it", fmt and tostring(fmt[2]))
    end

    -- THE MANA COLUMN (Arn 8 Nov: "the fuel button trick is that they are always there and we use ingame calculations out
    -- of fight, if my mana tide tool tip i regenereates 1000 mana ... when it tells us a certain shade we light up the
    -- button"). Each tool learns what it restores out of a fight; its curve lights it once you miss that much.
    do
        local keep = { bag = _G.C_Container, gis = C_Item.GetItemSpell, info = C_Item.GetItemInfo,
                       desc = C_Spell.GetSpellDescription, b46 = BOOK[46], dur = C_Spell.GetSpellCooldownDuration }
        local BAG = { 3385, 6149, 1205 }                       -- lesser and greater mana potion, melon juice
        local ITEM = { [3385] = { "Restore Mana", 437, 14 }, [6149] = { "Restore Mana", 2023, 31 }, [1205] = { "Drink", 1135, 15 } }
        local WORDS = { [437] = "Restores 280 to 360 mana.", [2023] = "Restores 700 to 900 mana.",
                        [1135] = "Restores 835.2 mana over 24 sec.  Must remain seated while drinking.",
                        ["Mana Tide Totem"] = "Summons a Mana Tide Totem with 5 health at the feet of the caster for 12 sec that restores 170 mana every 3 seconds to group members within 20 yards." }
        local itemCd = {}
        _G.C_Container = { GetContainerNumSlots = function(bag) return bag == 0 and #BAG or 0 end,
                           GetContainerItemID = function(bag, slot) return bag == 0 and BAG[slot] or nil end,
                           GetItemCooldown = function(id) itemCd[#itemCd + 1] = id return 100, 120, 1 end }
        C_Item.GetItemSpell = function(id) local i = ITEM[id] if i then return i[1], i[2] end end
        C_Item.GetItemInfo = function(id) local i = ITEM[id] if i then return "item" .. id, "link", 1, 1, i[3] end end
        C_Spell.GetSpellDescription = function(s) return WORDS[s] end
        BOOK[46] = { name = "Mana Tide Totem", rank = "Rank 1" }
        NS.FM.BookChanged()
        STATE.powerMax = 1375
        RD.Arm()
        ok(RD.tide.macro == "/cast Mana Tide Totem" and RD.tide:GetAttribute("*macrotext1") == "/cast Mana Tide Totem",
           "Mana Tide known: its pip casts it")
        ok(RD.potion.item == 6149 and RD.potion:GetAttribute("*macrotext1") == "/use item:6149",
           "the best mana potion in the bags (by the level it needs): a click drinks it", RD.potion.item)
        ok(RD.fuel.item == 1205 and RD.fuel:GetAttribute("*macrotext1") == "/use item:1205", "the best drink: a click drinks it")
        -- MAGE WATER FIRST (Arn, 12 Nov: "can you proioritize mage water first on the drink button too")
        BAG[#BAG + 1] = 5350                                   -- Conjured Water: needs level 5, under the melon juice's 15
        ITEM[5350] = { "Drink", 430, 5 }
        RD.ArmTools()
        ok(RD.fuel.item == 5350 and RD.fuel:GetAttribute("*macrotext1") == "/use item:5350",
           "a mage's water in the bags: the drink button reaches for it first, whatever level the bought one needs", RD.fuel.item)
        ok(RD.IsConjured(99999, "Conjured Glacier Water") and not RD.IsConjured(1205, "Melon Juice"),
           "conjured by id, else by a name starting 'Conjured '")
        BAG[#BAG], ITEM[5350] = nil, nil
        RD.ArmTools()
        ok(RD.fuel.item == 1205, "the mage water drunk up: back to the best bought drink")
        ok(RD.RestoreAmount(WORDS[1135]) == 835.2 and RD.RestoreAmount(WORDS[2023]) == 800
           and RD.RestoreAmount(WORDS["Mana Tide Totem"]) == 680 and RD.RestoreAmount("Heals for 5.") == nil,
           "what each restores, read off its own words (a decimal read whole; a totem's ticks added up)")
        -- each curve's point = restores / your full mana (both plain out of a fight): it lights when it keeps you off empty
        local function point(b)
            local c = RD.ToolCurve(b.at)
            table.sort(c.points, function(a2, b2) return a2.x < b2.x end)
            return c.points[2].x
        end
        local function want(amount) return math.floor((amount / 1375) * 100 + 0.5) / 100 end
        ok(RD.tide.at == want(680) and point(RD.tide) == want(680) and not RD.tide.guess, "Mana Tide lights at 680/1375 (49%), not at 1 - 680/1375", RD.tide.at)
        ok(RD.potion.at == want(800) and point(RD.potion) == want(800), "the potion at 800/1375", RD.potion.at)
        ok(RD.fuel.at == want(835.2) and point(RD.fuel) == want(835.2), "the drink at 835/1375", RD.fuel.at)
        local function lit(b) local v = b.pieces[1].__vertex return b.face:GetAlpha() == 1 and v and v[4] == 1 end
        STATE.mana = 0.70
        RD.PaintQuiet()
        ok(not lit(RD.tide) and not lit(RD.potion) and not lit(RD.fuel) and RD.tide.face:GetAlpha() == 1,
           "70% mana: every tool there and dark (its pieces see-through)")
        STATE.mana = 0.55
        RD.PaintQuiet()
        ok(not lit(RD.tide) and lit(RD.potion) and lit(RD.fuel),
           "55%: the drink's 835 and the potion's 800 are what you have left - they light; Mana Tide's 680 waits")
        STATE.mana = 0.45
        RD.PaintQuiet()
        ok(lit(RD.tide) and lit(RD.potion) and lit(RD.fuel), "45%: Mana Tide's 680 is more than you have left - all three lit")
        -- SPENT = DARK (Arn, 11 Nov, after a dungeon: "mana tide was on cooldown but it showed i can click it")
        RD.readyAt.tide, RD.coolStart.tide = CLOCK + 200, CLOCK - 100
        RD.PaintQuiet()
        ok(not lit(RD.tide) and lit(RD.potion) and lit(RD.fuel), "45%, Mana Tide cooling by our clock: it stays dark, the rest lit")
        RD.readyAt.potion, RD.coolStart.potion = CLOCK + 60, CLOCK - 60
        RD.PaintQuiet()
        ok(not lit(RD.potion) and lit(RD.fuel), "the potion cooling too: dark")
        RD.readyAt.potion, RD.coolStart.potion = nil, nil
        RD.PaintQuiet()
        RD.readyAt.tide = CLOCK + 1                  -- a second of Mana Tide's cooldown left
        RD.PaintQuiet()
        RD.WatchReady()
        ok(not lit(RD.tide) and RD.WatchReady() == false, "a second of cooldown left: still dark, the tick does nothing")
        TICK(2)                                      -- the ticker runs on, nothing else happens (no mana change)
        ok(RD.WatchReady() == true and lit(RD.tide) and lit(RD.potion),
           "the cooldown runs out: the ticker's watch lights it again by itself")
        RD.readyAt, RD.coolStart = {}, {}
        STATE.mana = 0.30
        STATE.inCombat = true
        fire(RD.events, "PLAYER_REGEN_DISABLED")
        local okPaint = pcall(fire, RD.events, "UNIT_POWER_UPDATE", "player")
        ok(okPaint and lit(RD.tide) and lit(RD.potion) and not lit(RD.fuel) and RD.fuel.face:GetAlpha() == 0,
           "30% in a fight: tide and potion lit by the game's shade; the drink waits for the fight's end")
        local seen = 0
        for _, b in ipairs({ RD.tide, RD.potion, RD.fuel }) do if b.pieces[1].__vertex then seen = seen + 1 end end
        ok(seen == 3, "the shade lands on plain textures (never a Line), all three", seen)
        -- re-learnt when the numbers are plain again: a bigger pool after the fight moves the light point
        STATE.inCombat = false
        STATE.powerMax = 2000
        fire(RD.events, "PLAYER_REGEN_ENABLED")
        ok(RD.tide.at == math.floor((680 / 2000) * 100 + 0.5) / 100, "the fight ends: each tool re-learns against your pool", RD.tide.at)
        STATE.powerMax = 1375
        fire(RD.events, "PLAYER_LEVEL_UP")
        ok(RD.tide.at == want(680), "and at a level up")
        -- THE RESERVE TANK (Arn 8 Nov: "add mana spring to the rail and we light it up when everything else is on cooldown
        -- as a scraping the barrel option")
        do
            local keepB47, keepName = BOOK[47], C_Spell.GetSpellName
            local SPRING = "Summons a Mana Spring Totem with 5 health at the feet of the caster for 5 min that restores 4 mana every 2 seconds to group members within 30 yards."
            WORDS["Mana Spring Totem"] = SPRING
            ok(RD.RestoreAmount(SPRING) == 600, "Mana Spring's words: 4 mana every 2 s for 5 MIN = 600", RD.RestoreAmount(SPRING))
            ok(RD.reserve and not RD.reserve.macro and not RD.ReserveOpen(true), "no Mana Spring trained: no reserve, never lit")
            BOOK[47] = { name = "Mana Spring Totem", rank = "Rank 1" }
            NS.FM.BookChanged()
            RD.Arm()
            ok(RD.reserve.macro == "/cast Mana Spring Totem" and RD.reserve.at == math.floor(600 / 1375 * 100 + 0.5) / 100
               and RD.reserve.tip and RD.reserve.tip[1] == "RESERVE TANK", "Mana Spring trained: the reserve tank casts it, lights at 600/1375", RD.reserve.at)
            ok(RD.potion.spellId == 2023, "the potion's use-spell is known, for our own clock", RD.potion.spellId)
            RD.readyAt, RD.waterUntil = {}, 0
            ok(not RD.ReserveOpen(true), "Mana Tide and the potion both ready: the reserve stays dark")
            C_Spell.GetSpellName = function(id) return ({ [16190] = "Mana Tide Totem", [5675] = "Mana Spring Totem" })[id] end
            ok(RD.OnCast("party1", 16190) == false and RD.readyAt.tide == nil, "someone else's Mana Tide is not yours")
            ok(RD.OnCast("player", secretNumber()) == false, "a spell id it will not show: not counted")
            ok(RD.OnCast("player", 16190) == "tide" and RD.readyAt.tide == CLOCK + RD.COOLS.tide and RD.waterUntil == CLOCK + 12,
               "you drop Mana Tide: spent for 5 min by our own clock, your water totem standing 12 s")
            ok(not RD.ReserveOpen(true), "the potion still in hand: dark")
            ok(RD.OnCast("player", 2023) == "potion" and RD.readyAt.potion == CLOCK + RD.COOLS.potion, "a potion drunk: spent 2 min")
            ok(not RD.ReserveOpen(true), "Mana Tide's totem still standing: a Spring would only knock it down - dark")
            TICK(13)
            ok(RD.ReserveOpen(true), "the tide totem gone, tide and potion cooling: the reserve tank opens (in a fight)")
            ok(not RD.ReserveOpen(false), "out of a fight with a drink in the bags: drink instead - dark")
            local function litR() local v = RD.reserve.pieces[1].__vertex return RD.reserve.face:GetAlpha() == 1 and v and v[4] == 1 end
            STATE.mana = 0.30
            RD.PaintTools(true)
            ok(litR(), "open and down to 30% (what it gives back is 44%): lit")
            STATE.mana = 0.60
            RD.PaintTools(true)
            ok(not litR(), "open but at 60%: not yet")
            STATE.mana = 0.30
            ok(RD.OnCast("player", 5675) == "spring" and not RD.ReserveOpen(true), "you drop it: your Spring stands 5 min - dark")
            RD.PaintTools(true)
            ok(not litR(), "and painted dark")
            TICK(301)
            ok(not RD.ReserveOpen(true), "5 min on: Mana Tide is ready again - the reserve is not the answer")
            RD.readyAt.tide, RD.readyAt.potion = CLOCK + 60, CLOCK + 60
            RD.reserveWas = nil
            local keepFight = RD.inFight
            RD.inFight = true
            local Cost = dofile("../_bisdev/dev/cost.lua")
            local rc = Cost.Count(function() RD.ReserveOpen(true) end)
            ok(rc <= 2, "the gate is our own clock: a time read, nothing asked of the client", rc)
            RD.inFight = keepFight
            RD.readyAt, RD.waterUntil = {}, 0
            BOOK[47], C_Spell.GetSpellName = keepB47, keepName
            NS.FM.BookChanged()
            RD.Arm()
        end
        -- THE CORNER GRIP (Arn, 11 Nov: "instead of having a command to set the scale for the radar can we the corner drag
        -- to resize for radar and engineer"). The mock has no screen positions, so this frame is given the client's
        -- GetLeft/GetTop: its top-left in its own units = screen pixels / its effective scale.
        do
            local f, g = RD.frame, RD.grip
            local gp = g and g.points[1]
            ok(g and gp and gp[2] == RD.hull and gp[3] == "BOTTOMRIGHT", "a grip on the hull's bottom-right corner (the radar's and the console's alike)")
            ok(RD.GripScale(1, 100, 900, 400, 600, 460, 540) == 1.2 and RD.GripScale(1, 100, 900, 400, 600, 700, 300) == RD.SCALE_MAX
               and RD.GripScale(1, 100, 900, 400, 600, 250, 750) == RD.SCALE_MIN,
               "the scale follows the cursor's pull from the held top-left corner, 50% to 200%")
            local keep = { cursor = _G.GetCursorPosition, combat = STATE.inCombat }
            local d = NS.DB().radar
            keep.scale, keep.pos, keep.fscale = d.scale, d.pos, f:GetScale()
            f:SetScale(1)
            local LEFT, TOP = 100, 900                     -- where its top-left sits on screen, in pixels
            function f:GetLeft() return LEFT / self:GetEffectiveScale() end
            function f:GetTop() return TOP / self:GetEffectiveScale() end
            local cx, cy = 400, 600
            _G.GetCursorPosition = function() return cx, cy end
            STATE.inCombat = false
            g.__scripts.OnMouseDown(g, "LeftButton")
            ok(g.sizing and g.__scripts.OnUpdate, "pressed on the grip out of a fight: sizing")
            cx, cy = 460, 540
            g.__scripts.OnUpdate(g)
            local p = f.points[1]
            ok(math.abs(f:GetScale() - 1.2) < 1e-9 and p and p[1] == "TOPLEFT" and p[3] == "BOTTOMLEFT"
               and math.abs(p[4] - LEFT / f:GetEffectiveScale()) < 1e-6 and math.abs(p[5] - TOP / f:GetEffectiveScale()) < 1e-6,
               "dragged out: 120%, the top-left corner held where it was", f:GetScale())
            g.__scripts.OnMouseUp(g)
            ok(not g.sizing and math.abs(d.scale - 1.2) < 1e-9 and d.pos and d.pos[1] == "TOPLEFT", "let go: the scale and the corner saved")
            STATE.inCombat = true
            g.__scripts.OnMouseDown(g, "LeftButton")
            ok(not g.sizing, "in a fight: the grip does nothing (the radar is a secure frame)")
            STATE.inCombat = false
            g.__scripts.OnMouseDown(g, "LeftButton")
            STATE.inCombat = true
            fire(RD.events, "PLAYER_REGEN_DISABLED")
            ok(not g.sizing and not g.__scripts.OnUpdate, "a fight starts mid-drag: the drag ends before the lockdown")
            STATE.inCombat, RD.inFight = false, nil
            g.__scripts.OnClick(g, "RightButton")
            ok(f:GetScale() == 1 and d.scale == 1, "right-click: back to 100%")
            f.GetLeft, f.GetTop, _G.GetCursorPosition, STATE.inCombat = nil, nil, keep.cursor, keep.combat
            d.scale, d.pos = keep.scale, keep.pos
            f:SetScale(keep.fscale)
            RD.Place()
        end
        -- A /RELOAD IN A FIGHT (11 Nov): the radar arms inside PLAYER_ENTERING_WORLD while the loading window is open
        do
            local keepArm, keepCombat = RD.Arm, STATE.inCombat
            local armed = 0
            RD.Arm = function() armed = armed + 1 return keepArm() end
            STATE.inCombat = false
            fire(RD.events, "PLAYER_ENTERING_WORLD")
            ok(armed == 1 and not RD.pending, "the loading window: the radar armed right then, nothing left pending")
            STATE.inCombat = true
            fire(RD.events, "PLAYER_ENTERING_WORLD")
            ok(armed == 1, "with the lockdown on, not even tried (it waits for the fight's end)")
            RD.Arm, STATE.inCombat = keepArm, keepCombat
        end
        -- THE DASHBOARD LOOK (Arn, 11 Nov 2026: "take this alpha and add it to the look of bis healing, cockpit classic and
        -- dashboard"): the radar is a public look, black box rail and all ("bottom rail is not hidden everyone sees it")
        do
            local d = NS.DB()
            local keep = { alpha = d.alpha, look = d.look, combat = STATE.inCombat }
            STATE.inCombat = false
            d.alpha, d.look = false, "classic"
            RD.Apply()
            ok(not RD.On() and not RD.Active() and not FG.Hidden(d), "the alpha off, classic: no radar, the grid shows")
            ok(NS.DO.look("radar") == "radar" and RD.On() and RD.Active() and RD.frame:IsShown() and FG.Hidden(d),
               "/bish look radar: the radar takes the grid's place - no alpha switch needed")
            -- API version 2: what another addon (BiS Tools' box) docks against
            local A = _G.BiSHealingAPI
            local edge, margin, rf = A.RadarEdge()
            ok(A.Look() == "radar" and edge == RD.edgeFrame and margin == RD.EDGE_N * RD.EDGE_PX and rf == RD.frame,
               "BiSHealingAPI.RadarEdge: the radar's whole outline, its soft edge, its frame - while it shows")
            -- 12 Nov 2026, Arn's BugSack: "Cannot anchor protected frames to regions" - the edge must be a FRAME
            ok(edge ~= RD.hull and edge.CreateTexture ~= nil, "RadarEdge hands a frame (secure boxes may be pinned to it), not the hull texture")
            -- ...AND NO TEXTURE ANYWHERE DOWN ITS CHAIN (12 Nov, the second BugSack: the frame was SetAllPoints'd to the
            -- hull, and the client refused the box all the same - it walks every anchor). A mock texture says so (`__texture`).
            local function regionFree(fr, depth)
                if type(fr) ~= "table" or depth > 30 then return true end
                if fr.__texture then return false end
                if type(fr.__allpoints) == "table" and not regionFree(fr.__allpoints, depth + 1) then return false end
                for _, q in ipairs(fr.points) do
                    if type(q[2]) == "table" and not regionFree(q[2], depth + 1) then return false end
                end
                return true
            end
            ok(regionFree(edge, 0) and edge:GetNumPoints() == 2, "the dock frame's anchors lead only to frames (the rails, the radar)")
            ok(not regionFree(RD.hull, 0), "(and the walk does catch a texture: the hull itself fails it)")
            -- THE SIZE ROW, while the radar shows (Arn: "only the scale work on the rader and nothing else")
            local row
            for _, o in ipairs(NS.UI.Rows()) do if o.key == "scale" then row = o end end
            local keepGrid, keepRadar = d.scale, NS.DB().radar.scale
            row.set(d, 1.5)
            ok(math.abs(RD.Scale() - 1.5) < 1e-9 and math.abs(RD.frame:GetScale() - 1.5) < 1e-9 and d.scale == keepGrid
               and row.show(d) == "150%", "the size row sizes the radar - the cells' size untouched", row.show(d))
            STATE.inCombat = true
            row.set(d, 1)
            ok(math.abs(RD.Scale() - 1.5) < 1e-9, "in a fight: not touched (the radar is a secure frame)")
            STATE.inCombat = false
            NS.DB().radar.scale = keepRadar
            RD.frame:SetScale(RD.Scale())
            ok(RD.bbRail and RD.bbRail:IsShown() and RD.BBRail() == RD.bbRail and RD.hull.points[2][2] == RD.bbRail,
               "the black box rail along the bottom for everyone, the hull round it")
            ok(NS.DO.look() == "classic" and not RD.Active() and not FG.Hidden(d), "no word walks on: radar -> classic, the grid back")
            local e2, why2 = _G.BiSHealingAPI.RadarEdge()
            ok(e2 == nil and why2 == "not shown" and _G.BiSHealingAPI.Look() == "classic", "classic: RadarEdge says not shown")
            ok(NS.DO.look() == "cockpit" and NS.DO.look() == "radar" and RD.Active(), "classic -> cockpit -> radar")
            STATE.inCombat = true
            ok(NS.DO.look("classic") == "classic" and RD.Active() and RD.pending, "in a fight: the radar stays till the fight's end (pending)")
            STATE.inCombat = false
            fire(RD.events, "PLAYER_REGEN_ENABLED")
            ok(not RD.Active() and not FG.Hidden(d), "the fight over: the grid back")
            d.alpha, d.dash1 = true, true
            d.look = "classic"
            RD.Apply()
            ok(not RD.Active() and not FG.Hidden(d), "once moved, the alpha switch no longer holds the radar up: classic means the grid")
            d.alpha, d.look = keep.alpha, keep.look
            STATE.inCombat = keep.combat
            RD.Apply()
        end
        -- THE TOTEMS (Arn, 11 Nov: "cast them all then you bring them too you and recall to get mana back")
        do
            local keepName, keepFight, keepCombat = C_Spell.GetSpellName, RD.inFight, STATE.inCombat
            local keepTotems = { TOTEMS[1], TOTEMS[2], TOTEMS[3], TOTEMS[4] }
            for i = 1, 4 do TOTEMS[i] = false end
            local function shows(b) return b:IsShown() and b.face:GetAlpha() == 1 end
            ok(RD.call and not RD.call.macro and not RD.call:IsShown() and not RD.tcall:IsShown() and not RD.recall:IsShown(),
               "no totem calls known: the three buttons stay hidden")
            BOOK[48] = { name = "Call of the Elements", rank = "" }
            BOOK[49] = { name = "Totemic Call", rank = "" }
            BOOK[50] = { name = "Totemic Recall", rank = "" }
            NS.FM.BookChanged()
            RD.Arm()
            ok(RD.call:IsShown() and RD.call:GetAttribute("*macrotext1") == "/cast Call of the Elements"
               and RD.call:GetAttribute("*macrotext2") == "/cast Call of the Elements" and RD.call.tip[1] == "CALL",
               "Call of the Elements known: CALL casts it on both clicks")
            BOOK[51] = { name = "Call of the Ancestors", rank = "" }
            NS.FM.BookChanged()
            RD.Arm()
            ok(RD.call:GetAttribute("*macrotext1") == "/cast Call of the Elements"
               and RD.call:GetAttribute("*macrotext2") == "/cast Call of the Ancestors", "and Call of the Ancestors: on the right-click")
            ok(RD.tcall:GetAttribute("*macrotext1") == "/cast Totemic Call" and RD.recall:GetAttribute("*macrotext1") == "/cast Totemic Recall"
               and RD.tcall.rail == RD.defRail and RD.recall.knob, "BRING and RECALL armed, on the right rail, each with its knob")
            RD.readyAt, RD.coolStart, RD.totemsUntil = {}, {}, 0
            RD.ReadTotems()
            RD.inFight, RD.totemsFought = false, false
            C_Spell.GetSpellName = function(id)
                return ({ [66842] = "Call of the Elements", [66843] = "Call of the Ancestors", [437009] = "Totemic Call",
                          [36936] = "Totemic Recall", [8071] = "Stoneskin Totem" })[id]
            end
            -- Arn, 11 Nov: "the call button should be lit if no totem are down, can be turned on before the fight i am not
            -- pressing that during combat i have to heal, in combat bring, after combat if they are down the recall lights
            -- up if recall is pressed call lights up"
            RD.PaintTotems(false)
            ok(shows(RD.call) and not shows(RD.tcall) and not shows(RD.recall), "out of a fight, none down: CALL lights")
            RD.inFight = true
            RD.PaintTotems(true)
            ok(not shows(RD.call) and not shows(RD.tcall) and not shows(RD.recall), "in a fight, none down: CALL stays dark (you are healing)")
            RD.inFight = false
            ok(RD.OnCast("player", 66842) == "call" and RD.totemsUntil == CLOCK + RD.TOTEM_LIFE and not RD.totemsFought,
               "you call them before the pull: they stand, by our clock")
            ok(not shows(RD.call) and not shows(RD.tcall) and not shows(RD.recall),
               "down before the pull: CALL dark, and no RECALL straight after a call")
            STATE.inCombat = true
            fire(RD.events, "PLAYER_REGEN_DISABLED")
            ok(RD.totemsFought and not shows(RD.call) and shows(RD.tcall),
               "the pull with them down: they go through the fight; BRING lights (Arn: \"i can just be lit up during combat\")")
            ok(RD.OnCast("player", 437009) == "tcall" and RD.readyAt.tcall == CLOCK + 30 and not shows(RD.tcall),
               "you bring them: 30 s cooldown, dark")
            ok(RD.tcall.cd.wait and RD.tcall.cd.__start == CLOCK and RD.tcall.cd.__dur == 30,
               "BRING's disc is its OWN 30 s cooldown, from our clock (like Mana Tide's)", RD.tcall.cd.__dur)
            TICK(10)
            ok(RD.WatchTotems() == false and not shows(RD.tcall), "while it cools: still dark")
            TICK(25)
            ok(RD.WatchTotems() == true and shows(RD.tcall), "cooled: BRING again (the ticker's watch), for a long fight's second bring")
            RD.SetKnob("tcall", true)
            ok(not shows(RD.tcall), "its knob off: never lights")
            RD.SetKnob("tcall", false)
            -- OUT OF A FIGHT, BRING OR RECALL (Arn, 11 Nov: "if i just dropped them its cheaper to bring them and if they
            -- are about to run out a recall them to get mana back")
            STATE.inCombat, RD.inFight = false, false
            RD.totemsUntil = CLOCK + 80
            RD.PaintTotems(false)
            ok(shows(RD.tcall) and not shows(RD.recall) and not shows(RD.call),
               "the fight over, 80 s left on them: BRING (cheaper than calling again), not RECALL")
            ok(RD.OnCast("player", 437009) == "tcall" and RD.totemsBrought and not shows(RD.tcall), "brought along: dark")
            TICK(35)
            RD.WatchTotems()
            ok(not shows(RD.tcall) and not shows(RD.recall), "its cooldown over, 45 s left: no second bring before the next fight, no recall yet")
            TICK(20)
            ok(RD.WatchTotems() == true and shows(RD.recall) and not shows(RD.tcall), "25 s left: about to run out - RECALL (the ticker's watch)")
            ok(RD.OnCast("player", 36936) == "recall" and RD.totemsUntil == 0 and not shows(RD.recall) and shows(RD.call),
               "recalled: gone, RECALL dark - and CALL lights again")
            ok(RD.OnCast("player", 66842) == "call" and not RD.totemsBrought and not shows(RD.tcall) and not shows(RD.recall),
               "called before the next pull: no BRING (not through a fight yet), no RECALL")
            TICK(RD.TOTEM_LIFE - RD.TOTEM_LOW + 5)          -- 25 s left
            RD.WatchTotems()
            ok(shows(RD.recall), "no pull came and they are about to run out: RECALL (mana back), fight or not")
            -- the real timers, out of a fight: the earliest end among the long-lived ones (a short fire totem does not decide)
            local keepInfo = _G.GetTotemInfo
            _G.GetTotemInfo = function(slot)
                if slot == 1 then return true, "Stoneskin Totem", CLOCK - 100, 120 end
                if slot == 2 then return true, "Searing Totem", CLOCK - 25, 30 end
                if slot == 3 then return true, "Mana Spring Totem", CLOCK - 10, 300 end
                return false
            end
            for i = 1, 3 do TOTEMS[i] = true end
            ok(RD.ReadTotems() == true and RD.totemsUntil == CLOCK + 20, "out of a fight: the plain timers - Stoneskin ends first (the Searing skipped)", RD.totemsUntil - CLOCK)
            _G.GetTotemInfo = keepInfo
            for i = 1, 4 do TOTEMS[i] = false end
            RD.totemsUntil, RD.totemsFought, RD.totemsBrought = 0, false, false
            ok(RD.OnCast("player", 8071) == false and RD.TotemsUp(), "one totem dropped by hand: they stand too")
            RD.totemsUntil = 0
            TOTEMS[2] = true
            ok(RD.ReadTotems() == true and RD.TotemsUp(), "out of a fight a slot reads down that our clock missed: they stand")
            TOTEMS[2] = false
            ok(RD.ReadTotems() == false and not RD.TotemsUp(), "every slot empty: none stand")
            STATE.inCombat = true
            ok(RD.ReadTotems() == nil, "in a fight the slots are never asked (secret)")
            STATE.inCombat = false
            local Cost = dofile("../_bisdev/dev/cost.lua")
            RD.WatchTotems()                         -- settled first: the count is a quiet tick, nothing changed
            local tc = Cost.Count(function() RD.WatchTotems() end)
            ok(tc <= 3, "the watch is our own clock: a time read and the lockdown question, nothing else", tc)
            -- IN A FIGHT (Arn, 11 Nov: "do the totem timers in combat"): the slot number of PLAYER_TOTEM_UPDATE, the
            -- client's own duration object on the discs
            RD.totemsUntil, RD.totemsFought, RD.totemsBrought, RD.lifeSlot, RD.readyAt = 0, false, false, nil, {}
            RD.slotUp, RD.slotSeen = {}, {}
            STATE.inCombat, RD.inFight = true, true
            ok(RD.OnCast("player", 66842) == "call" and RD.slotUp[1] and RD.slotUp[4] and RD.TotemsUp(),
               "called mid-fight: all four slots down")
            ok(RD.call.life and RD.call.life.__durObj and RD.call.life.__durObj.__totemDuration == RD.EARTH_SLOT
               and RD.recall.life == nil and RD.tcall.life == nil,
               "the time left on CALL (dark while they stand): the game's own timer for the earth slot, handed untouched; none on BRING or RECALL (Arn: \"recall has no cooldown\")")
            local okEv = pcall(fire, RD.events, "PLAYER_TOTEM_UPDATE", 2)
            ok(okEv and RD.slotUp[2] == true and RD.TotemsUp(), "the slot's update right after the cast: it went down (no slot read - that would throw)")
            TICK(10)
            fire(RD.events, "PLAYER_TOTEM_UPDATE", 2)
            ok(RD.slotUp[2] == false and RD.TotemsUp() and RD.call.life.__durObj.__totemDuration == 1,
               "ten seconds on, the earth slot updates on its own: that totem died - the disc follows another slot")
            ok(shows(RD.tcall), "the others still stand: BRING still lit")
            fire(RD.events, "PLAYER_TOTEM_UPDATE", 1)
            fire(RD.events, "PLAYER_TOTEM_UPDATE", 3)
            fire(RD.events, "PLAYER_TOTEM_UPDATE", 4)
            ok(not RD.TotemsUp() and not shows(RD.tcall) and RD.call.life.__durObj == nil,
               "every one dead or run out mid-fight: none stand - BRING dark, the disc cleared")
            fire(RD.events, "PLAYER_TOTEM_UPDATE", 2)
            TICK(0.2)
            ok(RD.OnCast("player", 8071) == false and RD.slotUp[2] == true and RD.TotemsUp(),
               "one dropped by hand, its slot's update a moment BEFORE the cast: that slot is down")
            ok(RD.OnCast("player", 36936) == "recall" and not RD.TotemsUp() and RD.slotUp[2] == false, "recalled mid-fight: every slot empty")
            STATE.inCombat, RD.inFight = false, false
            RD.slotUp, RD.slotSeen, RD.lifeSlot = {}, {}, nil
            -- the engineer's view: their own line under the tools, the console a line taller
            local f = RD.frame
            ok(RD.ToggleView() == "console", "the engineer's view")
            local G = RD.conGrid
            local cy = RD.call.points[1] and -RD.call.points[1][5]
            ok(G and cy and cy > G.rows[5] and f:GetHeight() == G.H and RD.conSquares.totem3:IsShown(),
               "the totems: a line of their own under the tools", cy)
            RD.ToggleView()
            ok(RD.call.points[1][2] == RD.defRail, "back on the radar: under the res on the right rail")
            BOOK[48], BOOK[49], BOOK[50], BOOK[51] = nil, nil, nil, nil
            NS.FM.BookChanged()
            RD.Arm()
            ok(not RD.call:IsShown() and not RD.call.macro, "forgotten: hidden again")
            C_Spell.GetSpellName, RD.inFight, STATE.inCombat = keepName, keepFight, keepCombat
            for i = 1, 4 do TOTEMS[i] = keepTotems[i] end
            RD.readyAt, RD.coolStart, RD.totemsUntil = {}, {}, 0
        end
        -- THE RAMJET'S DASHES (Arn 8 Nov: "somewhere on there the 5 second casting rule for 100% mana regen")
        do
            local g = RD.gauge
            ok(g.fsr and #g.fsrSegs == 5, "five dashes under the regen readout")
            ok(RD.PaintFSR(3.2) == 4 and g.fsr:GetAlpha() == 1 and g.fsrSegs[4]:GetAlpha() == 1 and g.fsrSegs[5]:GetAlpha() == RD.FSR.spent,
               "3.2 s left: four dashes lit, the fifth spent")
            ok(RD.PaintFSR(0.4) == 1 and g.fsrSegs[1]:GetAlpha() == 1 and g.fsrSegs[2]:GetAlpha() == RD.FSR.spent, "a part-second: the last dash")
            ok(RD.PaintFSR(0) == 0 and g.fsr:GetAlpha() == 0, "the rule over: the dashes gone, the ramjet runs (100%)")
            local FR = NS.FR
            local keepSpent, keepFight, keepCombat = FR.spentAt, RD.inFight, STATE.inCombat
            FR.Spend(GetTime())
            RD.inFight, STATE.inCombat = false, false
            RD.PaintRegen()
            ok(g.fsr:GetAlpha() == 0 and g.regen:GetText() == "100%", "out of a fight: no dashes, 100%")
            RD.inFight = true
            RD.PaintRegen()
            ok(g.fsr:GetAlpha() == 1 and g.fsrSegs[5]:GetAlpha() == 1, "a cast in a fight: all five dashes")
            FR.spentAt, RD.inFight, STATE.inCombat = keepSpent, keepFight, keepCombat
            RD.PaintRegen()
        end
        WORDS[1135] = "Must remain seated while drinking."
        RD.Arm()
        ok(RD.fuel.guess and RD.fuel.at == RD.TOOL_GUESS and RD.fuel.tip[2]:find("guess", 1, true),
           "words with no number: lights at half mana, and the tooltip says it is a guess")
        WORDS[1135] = "Restores 835.2 mana over 24 sec."
        RD.Arm()
        ok(RD.tide.tip and RD.tide.tip[1] == "MANA TIDE" and RD.tide.tip[2]:find("680", 1, true), "under the mouse: what it restores")

        -- THE COLUMN'S PLACE (Arn 8 Nov: "put the mana tools close to the fuel tape and the water shield"): beside the
        -- tape, top to bottom stabilizer, tide, potion, the reserve tank, drink, rations; no corner keeps a button
        local col = RD.COLUMN
        local inOrder = col[1] == RD.shield and col[2] == RD.tide and col[3] == RD.potion and col[4] == RD.reserve
                        and col[5] == RD.fuel and col[6] == RD.rations and #col == 6
        local step = RD.SYS_PX + RD.TOOL_GAP
        for k, b in ipairs(col) do
            local q = b.points[#b.points]
            if not (q[1] == "TOPLEFT" and q[2] == RD.toolRail and q[5] == -8 - (k - 1) * step) then inOrder = false end
        end
        ok(inOrder, "the column: stabilizer, Mana Tide, potion, reserve tank, drink, rations - on the tool rail, outside the square")
        -- clear of every pip: party and a full raid, every heal, cure (two cures) and bogey
        local function clash(raid, size)
            local slots = RD.Geometry(raid, 3)
            local n = 0
            local boxes = {}
            -- the rails stand outside the square (x < 0): nothing of theirs can sit on a pip
            local railRight = -RD.RAIL_GAP
            boxes[#boxes + 1] = { -1000, 0, railRight, size }
            for _, s in ipairs(slots) do
                local spots = { { s.rh, s.ph, 0 }, { s.rb, s.pb, 0 } }
                if s.rc then
                    for _, off in ipairs({ -(s.pc + 6) / 2, (s.pc + 6) / 2 }) do spots[#spots + 1] = { s.rc, s.pc + 4, off } end
                end
                for _, sp in ipairs(spots) do
                    if sp[1] then
                        local x, y = RD.Point(s, sp[1])
                        x, y = x + math.cos(s.b) * sp[3], y - math.sin(s.b) * sp[3]
                        local cx, cy, r = size / 2 + x, size / 2 - y, sp[2] / 2
                        for _, bx in ipairs(boxes) do
                            if cx + r > bx[1] and cx - r < bx[3] and cy + r > bx[2] and cy - r < bx[4] then n = n + 1 end
                        end
                    end
                end
            end
            return n
        end
        ok(clash(false, RD.PARTY.size) == 0, "the column and the tape touch no pip in a party", clash(false, RD.PARTY.size))
        ok(clash(true, RD.RAID.size) == 0, "nor in a full 40-man raid", clash(true, RD.RAID.size))
        -- the stabilizer moved, its fight-proof build did not: the client's cover is anchored to the button itself
        local sc = RD.shield.container
        local cpt = sc and sc.points and sc.points[1]
        ok(cpt and cpt[1] == "CENTER" and cpt[2] == RD.shield, "the stabilizer's client cover sits on the button's centre - it moved with it")
        local cv = RD.shield.cover and RD.shield.cover[1]
        ok(cv and cv.__allpoints, "the cover fills the client's button, which sits on the pip - the red is hidden whole")

        -- WHACK-A-MOLE (Arn 8 Nov: "it lights up and pulses a little it grabs more of our attention"): everything lit
        -- pulses; green holds still; red and a bogey pulse hard
        -- A PULSE OF SIZE (Arn's screenshots: an alpha animation brought hidden things back): a Scale bounce; the two fades
        -- left (BINGO's window, the wash) are checked with `fading`
        local function pulsing(gr, kind)
            local a = gr and gr.anims[1]
            -- built, and NOT playing while RD.SIZE_PULSE is off (Arn's screenshot: a pip blown up to the whole screen)
            return gr and (gr.playing == (RD.SIZE_PULSE and true or false)) and gr.looping == "BOUNCE" and a and a.kind == "Scale"
                and a.scaleTo and a.scaleTo[1] == kind[1] and a.duration == kind[2]
        end
        local function fading(gr, kind)
            local a = gr and gr.anims[1]
            return gr and gr.playing and gr.looping == "BOUNCE" and a and a.kind == "Alpha" and a.to == kind[1]
        end
        local alphaAnims = 0
        for _, gname in ipairs({ "beat", "amberPulse", "pulse" }) do
            local g0 = sp2[gname]
            if g0 and g0.anims[1] and g0.anims[1].kind == "Alpha" then alphaAnims = alphaAnims + 1 end
        end
        ok(alphaAnims == 0 and not (sp2.bogey.pulse and sp2.bogey.pulse.anims[1].kind == "Alpha"),
           "nothing hidden by alpha sits under an ALPHA animation: heal pips and bogeys pulse by size")
        local soft = true
        for _, b in ipairs({ RD.tide, RD.potion, RD.fuel, RD.rations }) do
            if not (pulsing(b.pulse, RD.PULSE_SOFT) and b.pulse == b.beat.__animGroups[1] and b.face:GetParent() == b.beat) then soft = false end
        end
        ok(soft, "the tools and rations pulse gently, on a wrapper round the lit face (\"nothing crazy\")")
        ok(RD.shield.breath and RD.shield.breath.playing and RD.shield.breath.looping == "BOUNCE"
           and RD.shield.breath.anims[1].to == RD.FADE_SOFT[1], "the stabilizer's red (buff gone) breathes, moderately")
        -- THE LAST CHARGE PULSES TOO (Arn 8 Nov: "make the stabilizer pulse too"); the green cover holds still
        local keepSU2, keepFmt = _G.C_StringUtil, RD.washFmt
        _G.C_StringUtil = { CreateNumericRuleFormatter = function()
            local fm = {}
            function fm:SetBreakpoints(points)
                for _, q in ipairs(points) do
                    if type(q.threshold) ~= "number" or type(q.format) ~= "string" then error("bad breakpoint", 2) end
                end
                self.points = points
            end
            return fm
        end }
        RD.washFmt = nil
        local auraBtn = CreateFrame("Button")
        function auraBtn:SetApplicationCount(fs, o) self.countText, self.countOpts = fs, o end
        local washed = RD.ShieldWash(auraBtn)
        ok(washed and fading(RD.washPulse, RD.FADE_SOFT) and RD.washClip:GetParent() == auraBtn
           and auraBtn.countText and auraBtn.countText.__parent == RD.washClip,
           "the orange last-charge wash pulses gently, on its own clip inside the client's button")
        local one = RD.washFmt.points and RD.washFmt.points[2]
        -- 9 Nov (Arn's screenshot: the symbol "squished" to a flat bar): a texture escape is sized by its text line, so the
        -- escape must be a shape that survives any size - a SQUARE, oversized and clipped - and the symbol a stencil over it
        ok(one and one.threshold == 1 and one.format:find("|TInterface\\Buttons\\WHITE8X8:66:66:", 1, true)
           and one.format:find(":255:120:0|t", 1, true) and not one.format:find("Art\\gyro", 1, true),
           "the last charge writes an orange SQUARE three pips big (any size it lands at still fills the pip)", one and one.format)
        local hole = RD.washHole
        local holeFrame = hole and rawget(hole, "__parent")
        ok(hole and tostring(hole.__texture or hole.texture or ""):find("Art\\gyrohole", 1, true)
           and holeFrame and holeFrame:GetParent() == auraBtn
           and (holeFrame.__level or 0) > (RD.washClip.__level or 0),
           "over it, inside the client's button: the stencil, the symbol cut out of the plate", hole and tostring(hole.__texture))
        local hv = hole and (hole.__vertex or hole.vertex)
        ok(hv and hv[1] == RD.PLATE[1] and hv[2] == RD.PLATE[2] and hv[3] == RD.PLATE[3],
           "the stencil is the plate's own dark: with no orange under it, nothing shows")
        ok(not RD.washPulse or rawget(holeFrame, "__animGroups") == nil, "only the orange beats - the stencil holds still")
        local f0, f2 = RD.washFmt.points[1], RD.washFmt.points[3]
        ok(f0.format == "" and f2.format == "", "no charge, or more than one: nothing written")
        ok(auraBtn.__animGroups == nil and (RD.shield.cover and RD.shield.cover[1] and rawget(RD.shield.cover[1], "__parent")) ~= RD.washClip,
           "the green cover (buff up, all good) holds still")
        _G.C_StringUtil, RD.washFmt = keepSU2, keepFmt
        -- NO SWEEP WHERE NOBODY IS (Arn 8 Nov: "cool down sweep show up when pips are not there")
        local empty = RD.spokes[4]
        ok(empty and empty.unit == nil and empty.cd and empty.cd.active == false, "an empty slot's sweep is switched off")
        ok(sp2.cd and sp2.cd.active == true, "a teammate's sweep runs")
        ok(sp2.cd.__drawEdge == false or sp2.cd.drawEdge == false or sp2.cd.__edge == false or sp2.cd.SetDrawEdge,
           "and no sweep draws its bright edge (the curve cannot colour it)")
        ok(pulsing(sp2.bogey.pulse, RD.PULSE_HARD) and sp2.bogey.face:GetParent() == sp2.bogey.beat,
           "a bogey pulses HARD - an incoming missile - round its face, seen only while it casts")
        ok(pulsing(sp2.beat, RD.PULSE_SOFT) and sp2.heal.face:GetParent() == sp2.heal.beat and pulsing(sp2.amberPulse, RD.PULSE_MID)
           and pulsing(sp2.pulse, RD.PULSE_HARD) and RD.PULSE_MID[1] > RD.PULSE_SOFT[1] and RD.PULSE_HARD[1] > RD.PULSE_MID[1],
           "every lit heal pip pulses (Arn: \"make the heal pips pulse too\"): green gently, amber a touch stronger, red hard")
        local cure = sp2.cures[1]
        ok(cure and pulsing(cure.pulse, RD.PULSE_SOFT) and cure.container:GetParent() == cure.holder,
           "a cure marker pulses gently, inside its holder (the client's marker itself is never animated)")
        STATE.hp.party1 = 0.6
        RD.PaintHeal(sp2)
        local av, mv = sp2.amberGlyph[1].__vertex, sp2.paintTex[1].__vertex
        ok(av and av[4] == 1 and mv and mv[4] == 0, "amber: the pulsing amber layer shows, the still face is see-through")
        STATE.hp.party1 = 0.85
        RD.PaintHeal(sp2)
        av, mv = sp2.amberGlyph[1].__vertex, sp2.paintTex[1].__vertex
        ok(av and av[4] == 0 and mv and mv[4] == 1, "green: the still face, no amber")

        -- THE GCD SWEEP ON EVERYTHING LIT (Arn 8 Nov: "would be kinda cool to also put the global cooldown sweep on
        -- everything that lit"): one object, every sweep; Mana Tide and the potion their own
        local gcdObj, tideObj, healObj = { gcd = true }, { tide = true }, { heal = true }
        local asked = {}
        C_Spell.GetSpellCooldownDuration = function(s)
            asked[#asked + 1] = s
            if s == 61304 then return gcdObj elseif s == "Mana Tide Totem" then return tideObj end
            return healObj
        end
        fire(RD.events, "SPELL_UPDATE_COOLDOWN")
        local every = #RD.sweeps > 0
        local idle = 0
        for _, cd in ipairs(RD.sweeps) do
            if cd.active == false then idle = idle + 1                -- an empty slot: no sweep at all
            elseif cd.__durObj ~= gcdObj then every = false end
        end
        ok(every, "every GCD sweep in use fed the GCD's own object (spell 61304); " .. idle .. " empty slots run none",
           #RD.sweeps)
        local has = sp2.cd and sp2.cd:GetParent() == sp2.heal.face and RD.shield.cd and RD.fuel.cd and RD.rations.cd
                    and cure.sweep and cure.sweep.__durObj == gcdObj and sp2.cd.__durObj == gcdObj and RD.rations.cd.__durObj == gcdObj
        ok(has, "a sweep on the heal pip, the cure marker, the stabilizer, the drink and rations")
        ok(sp2.cd.__bling == false and sp2.cd.__noNumbers == true, "the bogey's kind: no bling, no numbers")
        -- THE GCD IS NOT A COOLDOWN (Arn 8 Nov: "this mana tide sweep shows up whenever i click anything ... it makes me
        -- want to click it"): the client hands Mana Tide an object even when only the global cooldown runs on it, and in
        -- a fight we cannot tell the two apart - so the cooling disc never takes the client's object; it runs on OUR clock
        ok(RD.tide.cd.__durObj == nil and RD.tide.cd.__start == nil and RD.potion.cd.__start == nil,
           "Mana Tide and the potion both ready, a GCD running: no cooling disc (the client's object is never handed to it)",
           tostring(RD.tide.cd.__durObj) .. " " .. tostring(RD.potion.cd.__start))
        local keepName = C_Spell.GetSpellName
        C_Spell.GetSpellName = function(id) return id == 16190 and "Mana Tide Totem" or nil end
        local cast = CLOCK
        fire(RD.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 16190)
        ok(RD.tide.cd.__start == cast and RD.tide.cd.__dur == RD.COOLS.tide and RD.tide.cd.__durObj == nil,
           "you drop Mana Tide: the disc runs our own 5 minutes from the cast", RD.tide.cd.__start)
        fire(RD.events, "SPELL_UPDATE_COOLDOWN")
        ok(RD.tide.cd.__start == cast and RD.tide.cd.__durObj == nil, "the next GCD does not touch it")
        ok(fire(RD.events, "UNIT_SPELLCAST_SUCCEEDED", "party1", "g2", 16190) == false,
           "a party member's casts never reach the radar (the client filters to you)")
        TICK(RD.COOLS.tide + 1)
        fire(RD.events, "SPELL_UPDATE_COOLDOWN")
        ok(RD.tide.cd.__start == nil, "five minutes on: ready, the disc gone")
        C_Spell.GetSpellName = keepName
        RD.readyAt, RD.coolStart = {}, {}
        -- COOLING, SEEN WHEN DARK (Arn 8 Nov: "put it there but with a cooldown sweep")
        local waits = true
        for _, b in ipairs({ RD.tide, RD.potion }) do
            local cd = b.cd
            if not (cd and cd.wait and cd:GetParent() == b and cd.__swipeTex == RD.ART .. "disc"
                    and cd.__swipe and cd.__swipe[4] == RD.WAIT_SWIPE[4] and cd.__edgeOn == false and cd.__bling == false
                    and cd:GetFrameLevel() < b.beat:GetFrameLevel()) then waits = false end
        end
        ok(waits, "Mana Tide and the potion: their cooldown on the BUTTON (seen while the face is dark), a dim cyan disc under the face")
        local keepMana = STATE.mana
        STATE.mana = 0.05
        RD.PaintQuiet()
        ok(RD.tide.cd.__swipe[4] == RD.WAIT_SWIPE[4] and RD.potion.cd.__swipe[4] == RD.WAIT_SWIPE[4],
           "lit or dark, the cooling disc keeps its own colour (no mana curve on it)")
        STATE.mana = keepMana
        RD.PaintQuiet()
        local inLoop = false
        for _, cd in ipairs(RD.sweeps) do if cd == RD.tide.cd or cd == RD.potion.cd then inLoop = true end end
        ok(not inLoop, "and never fed the GCD")
        ok(RD.ART == "Interface\\AddOns\\BiSHealing\\Art\\", "our art lives in the addon's Art folder", RD.ART)
        local sw = sp2.cd.__swipe
        ok(sw and sw[4] == RD.SWIPE[4], "the heal pip's swipe is dark while it is lit (85%: green)")
        STATE.hp.party1 = 0.97
        RD.PaintHeal(sp2)
        ok(sp2.cd.__swipe[4] == 0, "full health, the pip invisible: the swipe see-through too")
        C_Spell.GetSpellCooldownDuration = function(s) if s == 61304 then return nil end return healObj end
        fire(RD.events, "SPELL_UPDATE_COOLDOWN")
        ok(sp2.cd.__durObj == healObj, "no answer for the GCD: the radar heal's own cooldown, which carries it")
        C_Spell.GetSpellCooldownDuration = function(s) if s == 61304 then return gcdObj end return healObj end
        local Cost = dofile("../_bisdev/dev/cost.lua")
        local sc2, sby = Cost.Count(function() RD.Sweeps() end)
        print(("   cost: radar sweeps, one cooldown event = %d calls for %d sweeps"):format(sc2, #RD.sweeps + 2))
        -- the GCD's object once, the tide's, the potion's, and the secret checks on what came back - never per sweep
        ok(sc2 <= 10, "the sweeps are batched: one object fetched, then a loop (the count does not grow with the raid)", sc2)
        ok(#RD.sweeps <= 5 + 2 * #RD.spokes + 4, "only sweeps of what can be seen are fed (a re-placed marker's goes)", #RD.sweeps)

        _G.C_Container, C_Item.GetItemSpell, C_Item.GetItemInfo = keep.bag, keep.gis, keep.info
        C_Spell.GetSpellDescription, BOOK[46], C_Spell.GetSpellCooldownDuration = keep.desc, keep.b46, keep.dur
        NS.FM.BookChanged()
        STATE.mana = 1
        RD.Arm()
        ok(not RD.tide.macro and not RD.potion.macro and RD.tide.face:GetAlpha() == 0, "no Mana Tide, no potions: their places stay dark")
    end

    -- off: the grid comes back exactly as it was - by the look now (Arn, 11 Nov: "when i toggel between class cockpit and
    -- dash it does nothing"), the alpha switch no longer holds the radar up
    SlashCmdList.BISHEALING("alpha off")
    ok(RD.Active(), "/bish alpha off: the radar stays - it is the radar look now, not the alpha")
    NS.DO.look("classic")
    ok(not RD.Active() and not f:IsShown() and NS.FG.Hidden() == (shownBefore == false), "look: classic - the radar goes, the grid is as it was")

    STATE.units.party1, STATE.units.party2 = true, true
    BOOK[43], BOOK[44], BOOK[45] = keep.b43, keep.b44, keep.b45
    NS.FM.BookChanged()
    if NS.FG then NS.FG.kickSpell = nil end
    _G.C_CurveUtil, _G.CreateColor, _G.Enum, _G.UnitHealthPercent, _G.UnitPowerPercent = keep.CU, keep.CC, keep.E, keep.HP, keep.PP
    _G.UnitCastingDuration, _G.UnitChannelDuration = keep.cast, keep.chan
    d.radar, d.shown = nil, keepShown
end

-- THE TEST CAMERA (9 Nov 2026, Arn: "If this pip ever fires, please take a screenshot ... then we compare with the
-- logs"): armed by hand, shoots at the pull / on a timer / on a tool cast / at the end, writes the stem and the reason
do
    local CAM, RD, d = NS.CAM, NS.RD, NS.DB()
    local heard = {}
    local keep = { chat = _G.DEFAULT_CHAT_FRAME, shot = _G.Screenshot, time = _G.time, date = _G.date,
                   name = C_Spell.GetSpellName, alpha = d.alpha, alphaOff = d.alphaOff, cam = d.cam,
                   cap = CAM.CAP, keepN = CAM.KEEP, tide = RD.readyAt.tide, tideStart = RD.coolStart.tide,
                   water = RD.waterUntil }
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    local function said(word) for _, t in ipairs(heard) do if tostring(t):find(word, 1, true) then return true end end end
    local shots = 0
    _G.Screenshot = function() shots = shots + 1 end
    local WALL = 1800000000
    _G.time = function() return WALL end
    _G.date = function(fmt) return fmt == "%m%d%y_%H%M%S" and ("110926_" .. string.format("%06d", WALL % 1000000)) or "?" end
    local function onUpdate() return CAM.ticker.__scripts.OnUpdate end
    local function frames(n, dt) for _ = 1, n do local u = onUpdate() if u then u(CAM.ticker, dt) end end end
    d.cam, d.alphaOff = nil, nil

    ok(CAM and NS.ALPHA.cam and NS.ALPHA.cam.cmd, "the camera is a secret alpha feature with its own words")
    heard = {}
    NS.DO.help()
    ok(not said("camera"), "/bish help never mentions it")

    d.alpha = nil
    heard = {}
    SlashCmdList.BISHEALING("alpha cam start")
    ok(not CAM.Armed() and said("alpha is off") and CAM.DB().run == nil, "alpha off: start refuses, no run counted")

    d.alpha = true
    -- THE KEY GATE (10 Nov, the black box's): without the private key addon there is no camera at all
    local keepKey = _G.BiSBlackBoxKey
    _G.BiSBlackBoxKey = nil
    heard = {}
    SlashCmdList.BISHEALING("alpha cam start")
    ok(not CAM.Armed() and said("black box key") and CAM.DB().run == nil, "no key addon: start refuses, no run counted")
    _G.BiSBlackBoxKey = { Check = function() return false end }
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    ok(shots == 0 and onUpdate() == nil, "the alpha on is not enough: not started, no shot at the pull and no clock")
    fire(CAM.events, "PLAYER_REGEN_ENABLED")
    ok(shots == 0, "and none at the end")

    heard = {}
    SlashCmdList.BISHEALING("alpha cam start 30")
    local c = CAM.DB()
    ok(CAM.Armed() and c.run == 1 and c.untilAt == WALL + 1800 and said("for 30 min"), "start 30: armed for half an hour, run 1")

    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    local e1 = c.shots[1]
    ok(shots == 1 and e1 and e1.why == "pull" and e1.fight == 1 and e1.run == 1, "the pull: one shot, written down", e1 and e1.why)
    ok(e1 and e1.stem == "WoWScrnShot_110926_" .. string.format("%06d", WALL % 1000000), "named the way the client names it", e1 and e1.stem)
    ok(onUpdate() ~= nil, "and the fight's clock runs")
    fire(CAM.events, "SCREENSHOT_SUCCEEDED")
    ok(e1.ok == true, "the client said it was written: noted on the shot")

    TICK(15) frames(3, 5)
    ok(shots == 1, "15 s in: nothing yet (every 20 s)")
    TICK(5) WALL = WALL + 20 frames(1, 5)
    local e2 = c.shots[2]
    ok(shots == 2 and e2 and e2.why == "timer", "20 s: a timer shot", e2 and e2.why)

    ok(NS.CamShot("tide") == nil and shots == 2 and e2.why == "timer+tide", "a Mana Tide inside 2 s joins the shot just taken", e2.why)
    NS.CamShot("tide")
    ok(e2.why == "timer+tide", "never twice")
    TICK(3) WALL = WALL + 3
    ok(NS.CamShot("spring") == nil and shots == 2, "Mana Spring: too often to be worth a picture")
    local e3 = NS.CamShot("potion")
    ok(shots == 3 and e3 and e3.why == "potion", "a potion 3 s later: its own shot")

    -- the hook: the radar's own cast clock hands the kind over
    C_Spell.GetSpellName = function(id) if id == 16190 then return RD.TIDE end return keep.name and keep.name(id) end
    TICK(3) WALL = WALL + 3
    fire(RD.events, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 16190)
    ok(shots == 4 and c.shots[4].why == "tide", "your Mana Tide cast (UNIT_SPELLCAST_SUCCEEDED): a shot", c.shots[4] and c.shots[4].why)
    C_Spell.GetSpellName = keep.name

    -- THE PROBE: the game refuses a screenshot in a fight
    TICK(3) WALL = WALL + 3
    fire(CAM.events, "ADDON_ACTION_BLOCKED", "SomeOtherAddon", "Screenshot()")
    ok(not c.blocked and onUpdate() ~= nil, "another addon refused: not our answer")
    fire(CAM.events, "ADDON_ACTION_BLOCKED", "BiSHealing", "Screenshot()")
    ok(c.blocked == true and onUpdate() == nil, "refused for us in a fight: remembered, the clock stops")
    ok(NS.CamShot("potion") == nil and shots == 4, "no more shots in a fight")
    heard = {}
    fire(CAM.events, "PLAYER_REGEN_ENABLED")
    ok(shots == 5 and c.shots[5].why == "end" and c.shots[5].fight == nil, "the end: out of the fight, one shot", c.shots[5] and c.shots[5].why)
    ok(said("refused a screenshot in the fight") and onUpdate() == nil, "says so once, and no clock out of a fight")
    TICK(3) WALL = WALL + 3
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    ok(shots == 6 and c.shots[6].why == "pull" and onUpdate() == nil, "blocked: the pull still shoots (out of the lockdown yet), no clock")
    fire(CAM.events, "PLAYER_REGEN_ENABLED")

    -- a fight's cap
    heard = {}
    SlashCmdList.BISHEALING("alpha cam clear")
    ok(#c.shots == 0 and not c.blocked and said("untouched"), "clear: the list goes, the pictures stay, the refusal forgotten")
    CAM.CAP = 3
    TICK(3) WALL = WALL + 3
    local before = shots
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    for _ = 1, 6 do TICK(20) frames(1, 20) end
    ok(shots - before == 3, "at most CAP shots in one fight (the pull is one)", shots - before)
    heard = {}
    TICK(3)
    fire(CAM.events, "PLAYER_REGEN_ENABLED")
    ok(shots - before == 4 and said("shots in that fight"), "the end still shoots, and a line counts the fight")
    CAM.CAP = keep.cap

    -- the timer's words
    SlashCmdList.BISHEALING("alpha cam every 3")
    ok(c.every == 5, "every 3: 5 s is the least", c.every)
    SlashCmdList.BISHEALING("alpha cam every 0")
    TICK(3)
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    ok(onUpdate() == nil, "every 0: the pull shoots, no clock")
    fire(CAM.events, "PLAYER_REGEN_ENABLED")
    c.every = nil

    -- the cost of a fight's frames while armed: arithmetic, nothing asked of the client
    TICK(3)
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    local okCost, Cost = pcall(dofile, "../_bisdev/dev/cost.lua")
    if not okCost then okCost, Cost = pcall(dofile, "../../_bisdev/dev/cost.lua") end
    if okCost then
        local n = Cost.Count(function() frames(100, 0.01) end)
        print(("   cost: test camera, 100 fight frames armed = %d calls"):format(n))
        ok(n == 0, "a second and a half of fight frames asks the client nothing", n)
    end
    fire(CAM.events, "PLAYER_REGEN_ENABLED")

    -- the list keeps KEEP at most
    CAM.KEEP = 4
    for _ = 1, 6 do TICK(3) SlashCmdList.BISHEALING("alpha cam now") end
    ok(#c.shots == 4 and c.shots[4].why == "asked", "the oldest go first", #c.shots)
    CAM.KEEP = keep.keepN

    -- it stops by itself, and on stop
    WALL = c.untilAt + 1
    local n0 = shots
    TICK(3)
    fire(CAM.events, "PLAYER_REGEN_DISABLED")
    ok(not CAM.Armed() and shots == n0 and onUpdate() == nil, "after its time: disarmed by itself, no shot")
    fire(CAM.events, "PLAYER_REGEN_ENABLED")
    SlashCmdList.BISHEALING("alpha cam start")
    ok(CAM.Armed() and c.run == 2 and c.untilAt == WALL + 7200, "start again: run 2, two hours by default")
    heard = {}
    SlashCmdList.BISHEALING("alpha cam status")
    ok(said("armed") and said("Say done to Claude"), "/bish alpha cam status: the state and what to do after")
    SlashCmdList.BISHEALING("alpha cam stop")
    ok(not CAM.Armed() and c.untilAt == nil, "stop: off")
    SlashCmdList.BISHEALING("alpha cam start")
    SlashCmdList.BISHEALING("alpha cam off")
    ok(not CAM.Armed(), "/bish alpha cam off (the switch): off with the feature")

    _G.DEFAULT_CHAT_FRAME, _G.Screenshot, _G.time, _G.date = keep.chat, keep.shot, keep.time, keep.date
    _G.BiSBlackBoxKey = keepKey
    d.alpha, d.alphaOff, d.cam = keep.alpha, keep.alphaOff, keep.cam
    RD.readyAt.tide, RD.coolStart.tide, RD.waterUntil = keep.tide, keep.tideStart, keep.water
    CAM.inFight, CAM.last, CAM.pending = nil, nil, nil
end

-- THE BLACK BOX (10 Nov 2026, Arn: "Build the bottom raid with the squawk box thing"): the radar's bottom rail - a lamp,
-- a status, a scratchpad and a keypad for everyone; only the private key addon makes a code right
do
    local BB, CAM, RD, d = NS.BB, NS.CAM, NS.RD, NS.DB()
    local keep = { key = _G.BiSBlackBoxKey, log = _G.LoggingCombat, reload = _G.ReloadUI, time = _G.time,
                   icl = _G.InCombatLockdown, bb = d.bb, cam = d.cam, alpha = d.alpha, chat = _G.DEFAULT_CHAT_FRAME,
                   rand = math.random }
    local heard = {}
    _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) heard[#heard + 1] = t end }
    local logOn, logSets, reloads = false, 0, 0
    _G.LoggingCombat = function(v) if v ~= nil then logOn = v and true or false logSets = logSets + 1 end return logOn end
    _G.ReloadUI = function() reloads = reloads + 1 end
    local WALL = 1800100000
    _G.time = function() return WALL end
    local fighting = false
    _G.InCombatLockdown = function() return fighting end
    d.bb, d.cam, d.alpha = nil, nil, nil
    _G.BiSBlackBoxKey = nil
    local function press(...) local r for _, k in ipairs({ ... }) do r = BB.Press(k) end return r end
    local function plain(fs) return (tostring(fs.__bbt or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

    ok(BB and BB.Build, "the black box is built into the radar")
    RD.Build()
    local r = BB.rail
    ok(r and RD.bbRail == r, "the radar has a bottom rail (RD.bbRail)")
    local k1 = r and r.keys and r.keys["1"]
    -- 2 x 2 (Arn, 12 Nov: "the 1234567890A lets just do a 2x2 1234" - "to save space")
    ok(k1 and r.keys["2"] and r.keys["3"] and r.keys["4"] and not r.keys["5"] and not r.keys["0"] and not r.keys.A
       and not r.keys.CLR and not r.keys.EXEC and r.pad:GetWidth() == 2 * BB.KW + BB.KGAP,
       "the keypad: 2 x 2, the digits 1-4 - no CLR, no EXEC", r.pad:GetWidth())
    ok(plain(r.status) == "REC OFF" and r.lampState == "off", "at rest: REC OFF, the lamp red", plain(r.status))
    ok(r.__scripts.OnUpdate == nil, "no key, nothing typed: no OnUpdate at all")
    heard = {}
    NS.DO.help()
    local told = false
    for _, t in ipairs(heard) do if tostring(t):lower():find("black box", 1, true) then told = true end end
    ok(not told, "/bish help never mentions it (the Diablo gem: nobody is told)")

    -- typing
    k1.__scripts.OnClick(k1)
    press("2", "3")
    ok(BB.pad == "123" and plain(r.screen) == "[123_]", "keys type into the scratchpad", plain(r.screen))

    -- NO KEY: every code is refused, nothing else happens - and the FOURTH key sends it
    math.random = function(a, b) return a end          -- roll 1: a rare one
    ok(press("4") == "denied" and BB.pad == "" and reloads == 0 and logSets == 0 and not BB.Recording(),
       "the fourth key sends the code; no key: refused, never a reload or the log")
    local rare = plain(r.screen)
    ok(rare == BB.DENY_RARE[1], "a rare refusal on the screen", rare)
    ok(r.__scripts.OnUpdate ~= nil, "a reply clears itself: the tick runs while it shows")
    math.random = function(a, b) return b end          -- roll RARE: a common one
    ok(press("3", "3", "4", "4") == "denied" and plain(r.screen) == BB.DENY[#BB.DENY], "and a common one", plain(r.screen))
    TICK(BB.SAY + 0.5) BB.OnUpdate(r, 1.1)
    ok(plain(r.screen) == "[_]" and r.__scripts.OnUpdate == nil, "the reply goes after a few seconds, and so does the tick", plain(r.screen))
    press("1", "2")
    ok(BB.pad == "12" and reloads == 0, "two keys: nothing sent yet")
    BB.pad = ""

    -- THE KEY: only its code is right
    _G.BiSBlackBoxKey = { Check = function(c) return c == "4321" end }
        ok(press("1", "1", "1", "1") == "denied" and reloads == 0, "the key installed, a wrong code: refused")
    fighting = true
        ok(press("4", "3", "2", "1") == "combat" and reloads == 0 and not BB.Recording(), "the right code in a fight: not now")
    fighting = false
        ok(press("4", "3", "2", "1") == "start", "the right code out of a fight: START")
    local b = BB.DB()
    ok(BB.Recording() and b.run == 1 and b.at == WALL and b.untilAt == WALL + BB.MINUTES * 60, "recording: the run written to the save")
    ok(logOn and b.logOurs == true and reloads == 1, "the combat log on (ours), then the game reloads (the save reaches the disk)")
    ok(CAM.Armed(), "the test camera arms with it - no alpha needed")

    -- after the reload: the log comes back if it fell off
    logOn = false
    heard = {}
    fire(BB.events, "PLAYER_LOGIN")
    ok(logOn and BB.Recording(), "back from the reload: the log on again")
    WALL = WALL + 65
    BB.Paint()
    ok(plain(r.status) == "REC 01:05" and r.lampState == "rec", "REC and the run's clock, the lamp red", plain(r.status))
    ok(r.__scripts.OnUpdate ~= nil, "recording: the one-a-second tick runs")

    -- a fight, then the wait, then safe
    fire(BB.events, "PLAYER_REGEN_DISABLED")
    ok(BB.State() == "rec" and r.lampState == "rec", "in a fight: red")
    fire(BB.events, "PLAYER_REGEN_ENABLED")
    ok(BB.State() == "wait" and r.lampState == "wait" and plain(r.status) == "WAIT " .. BB.WAIT .. "s", "the fight ends: yellow, WAIT", plain(r.status))
    TICK(BB.WAIT - 4) BB.OnUpdate(r, 1.1)
    ok(plain(r.status) == "WAIT 4s", "counting down", plain(r.status))
    TICK(5) BB.OnUpdate(r, 1.1)
    ok(BB.State() == "safe" and r.lampState == "safe" and plain(r.status) == "SAFE TO RELOAD", "then green: SAFE TO RELOAD", plain(r.status))
    fire(BB.events, "PLAYER_REGEN_DISABLED")
    ok(r.lampState == "rec", "the next pull: red again")
    fire(BB.events, "PLAYER_REGEN_ENABLED")

    -- the cost of a recording's frames: a tick a second, words set only when they change
    local okCost, Cost = pcall(dofile, "../_bisdev/dev/cost.lua")
    if not okCost then okCost, Cost = pcall(dofile, "../../_bisdev/dev/cost.lua") end
    if okCost then
        local n = Cost.Count(function() for _ = 1, 100 do BB.OnUpdate(r, 0.01) end end)
        print(("   cost: black box, 100 recording frames = %d calls"):format(n))
        ok(n <= 12, "a second of recording frames: at most one paint", n)
    end

    -- STOP: the code again
        ok(press("4", "3", "2", "1") == "stop" and not BB.Recording() and logOn and reloads == 2,
       "the code again: STOP and a reload - the combat log LEFT ON (Arn, 11 Nov: never turned off by us)")
    ok(b.stopWhy == "code" and b.stoppedAt == WALL and not CAM.Armed(), "the stop written down, the camera disarmed")

    -- NEVER OFF, in any file (Arn, 11 Nov: "our addon should never turn off combat log it can only turn it on")
    do
        local offs = 0
        for _, file in ipairs({ "BlackBox.lua", "TestCam.lua", "Radar.lua", "Core.lua" }) do
            local fh = io.open(file, "r")
            if fh then
                local src = fh:read("*a") fh:close()
                for _ in src:gmatch("LoggingCombat%s*,%s*false") do offs = offs + 1 end
                for _ in src:gmatch("LoggingCombat%s*%(%s*false") do offs = offs + 1 end
            end
        end
        ok(offs == 0, "no file ever turns the combat log off", offs)
    end
    -- courtesy: someone else's log stays on
    logOn = true
    press("4", "3", "2", "1")
    ok(BB.Recording() and not b.logOurs, "the log already on: not ours")
    press("4", "3", "2", "1")
    ok(logOn, "so our stop leaves it on")

    -- it stops by itself; and the key gone stops it at the next login
    press("4", "3", "2", "1")
    WALL = b.untilAt + 1
    BB.Paint()
    ok(not BB.Recording() and b.stopWhy == "time" and r.lampState == "off", "after its time: stopped by itself, red, REC OFF")
    WALL = WALL + 10
    press("4", "3", "2", "1")
    _G.BiSBlackBoxKey = nil
    fire(BB.events, "PLAYER_LOGIN")
    ok(not BB.Recording() and b.stopWhy == "key gone", "the key addon gone: the next login stops it")
    _G.BiSBlackBoxKey = { Check = function() error("boom") end }
        ok(press("4", "3", "2", "1") == "denied", "a key that breaks: refused, never a reload")

    math.random = keep.rand
    _G.BiSBlackBoxKey, _G.LoggingCombat, _G.ReloadUI, _G.time = keep.key, keep.log, keep.reload, keep.time
    _G.InCombatLockdown, _G.DEFAULT_CHAT_FRAME = keep.icl, keep.chat
    d.bb, d.cam, d.alpha = keep.bb, keep.cam, keep.alpha
    BB.pad, BB.sayUntil, BB.waitUntil, BB.inFight = "", nil, nil, nil
    BB.Paint() BB.Wake()
end

print(fail == 0 and ("== BiS Healing ok (" .. checks .. " checks)")
      or ("!! BiS Healing: " .. fail .. " of " .. checks .. " failed"))
os.exit(fail == 0 and 0 or 1)
