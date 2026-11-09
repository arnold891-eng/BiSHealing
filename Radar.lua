--[[
  BiSHealing :: Radar.lua - THE RADAR, the secret alpha's first feature (8 Nov 2026).

  Arn: "total complete rewite of the healing concept ... im only clicking on stuff that lights up lets lean into it and
  make a radar that hides everything and only lights up when it needs to be clicked" ... "square and no names on
  anything completly dark i want everything to hide when not needed" ... "we hide stuff like how we hide the interrupt
  button, no casting we turn completly invisible but still in the same place" ... "Build it".
  Mockup (v3): https://claude.ai/artifact/6FVpu5JR4yCyyaHT1VfftP

  Behind the secret alpha only: `NS.AlphaOn("radar")`. On, it takes the grid's place (FG.Hidden, the saved `shown`
  untouched); off, the grid comes back. Out of combat both ways; asked in a fight, it waits for the fight's end.

  A SQUARE SCOPE, ONE SPOKE A TEAMMATE (you and your party, or your own raid group - five; raid sectors are v2).
  From the centre out, on each spoke:
    HEAL pip   a secure button on that unit: a plain left-click casts THE RADAR HEAL (your class's single-target
               heal at its top trained rank minus 2 - RD.Heal; `/bish alpha radar heal <spell>` changes it); every
               other click is your own binds (FM.ApplyTo). Its face is a role glyph (tank / heal / damage) the CLIENT
               colours from their health through a curve (RD.Curve): hidden at RD.GREEN and up, green below it, amber
               where your heal would fill it (1 - heal / max health, learned out of a fight; else RD.AMBER), red
               under RD.RED with a client-run pulse. Nothing is read.
    CURE pip   per cure your class has (Auras.lua's list): the client draws a small diamond only while that unit has
               something you can cure (an AuraContainer slot, HARMFUL|RAID_PLAYER_DISPELLABLE), a secure box under it
               casts the cure. No words.
    BOGEY      their target (yours on your own spoke): a red triangle only while it casts (FG.Casting, `type()` only);
               a click is your interrupt, on an enemy only (the client's own harm switch, as the PvP cells).
  SYSTEMS in the corners, icons only: the REFUEL shield (your watched self buff - Water Shield - lights while it is
  NOT on you: the client's own icon arriving hides the red), FUEL (your mana through a curve, lit low; out of a fight a
  click drinks the best water in your bags), RATIONS (out of a fight, Well Fed missing and a well-fed food in your
  bags: a click eats it). MISSILES: your mana as a tape along the bottom (the value handed untouched), a tick for
  every radar heal it holds (worked out of a fight). ALERTS: a dashed red arc on the rim of the spoke - out of range
  (the client's own answer through its ternary), or a line-of-sight failure on a click there (UI_ERROR_MESSAGE).

  OUT OF A FIGHT everything is drawn dim, so the hand learns the places. IN A FIGHT the scope and every empty slot go
  to alpha 0 - in the same place and still clickable, like the PvP interrupt - and only what needs a click shows.
  Secure attributes are written out of combat only; a roster change mid-fight waits for its end.
  WHAT IT COSTS: no OnUpdate. Health and mana repaint on their events, one unit at a time. While shown, a ticker every
  RD.TICK asks each bogey "casting?" and each spoke's range (Cost budget in the suite); it stops when hidden.
]]
local ADDON, NS = ...
NS = NS or {}

local RD = {}
NS.RD = RD

RD.KEY = "radar"
RD.SIZE = 300                 -- the square, before its scale
RD.SPOKES = 5                 -- a party's spokes; a raid has 40 fixed slots (RD.Geometry)
RD.SYS_PX = 26
RD.RINGS = { 40, 80, 120, 142 }
RD.RING_SEG = 40
RD.GREEN, RD.AMBER, RD.RED = 0.90, 0.80, 0.35    -- below: green / amber (when the heal size is unknown) / red
RD.FUEL_LOW = 0.30
RD.TICK = 0.5
RD.FOOD_EVERY = 10            -- ticks: the food is asked again every 5 s out of a fight
RD.WHITE = "Interface\\Buttons\\WHITE8X8"
RD.PHOS = { 0.22, 1.00, 0.53 }                   -- the scope's green
RD.DIM = { 0.11, 0.36, 0.22, 0.9 }               -- an empty slot out of a fight
RD.COL = { green = { 0.22, 1.00, 0.53, 1 }, amber = { 1.00, 0.70, 0.25, 1 }, red = { 1.00, 0.23, 0.30, 1 },
           cyan = { 0.25, 0.96, 1.00, 1 }, bogey = { 1.00, 0.23, 0.30, 1 } }
RD.CROSS = { 1.00, 0.24, 0.92 }                    -- your target's crosshair: the cockpit's magenta (FG.COCKPIT.target)
RD.CROSS_PAD = 12                                  -- px round a pip
-- TARGET OF TARGET (Arn, 8 Nov: "target of target?"): who your target is on - the same reticle in amber, a size bigger,
-- so it frames the magenta one when you target a friend's attacker and never hides under it
RD.TOT = { 1.00, 0.70, 0.25 }
RD.TOT_PAD = 22
RD.CONTACT = { 0.22, 1.00, 0.53, 0.75 }            -- their target, quiet: a phosphor triangle (red once it casts)
RD.CONTACT_SHOWN = false                           -- Arn, 8 Nov: a bogey shows only while it casts
RD.CURE_COL = { Poison = { 0.49, 1.00, 0.35, 1 }, Disease = { 0.88, 0.69, 0.29, 1 }, Magic = { 0.30, 0.64, 1.00, 1 },
                Curse = { 0.77, 0.35, 1.00, 1 } }
-- your class's single-target heal, the first one trained wins (Arn: "we always use our biggest heal minus 2 ranks")
RD.HEALS = { SHAMAN = { "Healing Wave" }, PRIEST = { "Greater Heal", "Heal", "Lesser Heal" }, DRUID = { "Healing Touch" },
             PALADIN = { "Holy Light" } }
RD.HEALER_CLASS = { PRIEST = true, DRUID = true, SHAMAN = true, PALADIN = true }

local function combat() return (InCombatLockdown and InCombatLockdown()) and true or false end
-- NIL FOR A SECRET, ALWAYS (8 Nov 2026, Arn's BugSack: "attempt to compare local 'mx' (a secret number value)"). This
-- was `NS.Plain and NS.Plain(v) or v`: NS.Plain answers nil for a secret, and `nil or v` handed the secret straight back.
local function plain(v)
    if NS.Plain then return NS.Plain(v) end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function db()
    local d = NS.DB()
    d.radar = type(d.radar) == "table" and d.radar or {}
    return d.radar
end

--- Is the radar on now (the alpha, and this feature)?
function RD.On() return NS.AlphaOn and NS.AlphaOn(RD.KEY) or false end
--- Is it standing in for the grid now? (What the grid asks: FG.Hidden.)
function RD.Active() return RD.shownFor == true end

-- ------------------------------------------------------------------ the heal

local function classFile()
    local ok, _, c = pcall(UnitClass, "player")
    return ok and plain(c) or nil
end

--- "healing wave" -> "Healing Wave" (a typed name is lowercased on its way here).
local function titled(s)
    return (tostring(s or ""):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b:lower() end))
end

--- The radar's heal: { name, rank (nil for a spell without ranks), cast = "Name(Rank n)" } or nil.
--- The saved pick first (db.heal), else the class's list; the top trained rank minus 2 (rank 1 at the least).
function RD.Heal()
    local FM = NS.FM
    if not (FM and FM.Ranks) then return nil end
    local names = {}
    local pick = db().heal
    if type(pick) == "string" and pick ~= "" then names[1] = pick end
    for _, n in ipairs(RD.HEALS[classFile() or ""] or {}) do names[#names + 1] = n end
    for _, n in ipairs(names) do
        local ranks = FM.Ranks(n)
        if #ranks > 0 then
            local r = ranks[math.max(1, #ranks - 2)]
            return { name = n, rank = r and r.rank or nil, cast = FM.Cast(n, r and r.rank), ranks = #ranks }
        end
    end
    return nil
end

--- How much the radar heal heals, from the client's own words out of a fight ("for 300 to 350"): the middle, or nil.
function RD.HealAmount(h)
    h = h or RD.heal
    if not h or combat() then return RD.healAmount end
    local get = C_Spell and C_Spell.GetSpellDescription
    if not get then return nil end
    local ok, text = pcall(get, h.cast or h.name)
    text = ok and plain(text) or nil
    if type(text) ~= "string" then return nil end
    local a, b = text:match("(%d[%d,]*)%s+to%s+(%d[%d,]*)")
    a, b = tonumber(a and a:gsub(",", "")), tonumber(b and b:gsub(",", ""))
    if a and b then RD.healAmount = (a + b) / 2 return RD.healAmount end
    return nil
end

-- ------------------------------------------------------------------ the curves (the client decides)

RD.curves = {}
--- The heal pip's colour by health fraction: red under RD.RED, amber under `amber`, green under RD.GREEN, gone above.
function RD.Curve(amber)
    amber = math.max(RD.RED + 0.02, math.min(amber or RD.AMBER, RD.GREEN - 0.01))
    local key = math.floor(amber * 100 + 0.5)
    if RD.curves[key] then return RD.curves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local R, A, G = RD.COL.red, RD.COL.amber, RD.COL.green
    local function at(x, col, a) pcall(c.AddPoint, c, x, CreateColor(col[1], col[2], col[3], a or col[4])) end
    at(0.00, R) at(RD.RED, R)
    at(RD.RED + 0.0001, A) at(amber, A)
    at(amber + 0.0001, G) at(RD.GREEN, G)
    at(RD.GREEN + 0.0001, G, 0) at(1.00, G, 0)
    RD.curves[key] = c
    return c
end

--- The red pulse layer: solid under RD.RED, nothing above (the client runs the pulse on it).
function RD.RedCurve()
    if RD.redCurve then return RD.redCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local R = RD.COL.red
    pcall(c.AddPoint, c, 0.00, CreateColor(R[1], R[2], R[3], 0.6))
    pcall(c.AddPoint, c, RD.RED, CreateColor(R[1], R[2], R[3], 0.6))
    pcall(c.AddPoint, c, RD.RED + 0.0001, CreateColor(R[1], R[2], R[3], 0))
    pcall(c.AddPoint, c, 1.00, CreateColor(R[1], R[2], R[3], 0))
    RD.redCurve = c
    return c
end

--- Fuel: cyan below RD.FUEL_LOW, nothing above.
function RD.FuelCurve()
    if RD.fuelCurve then return RD.fuelCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local C = RD.COL.cyan
    pcall(c.AddPoint, c, 0.00, CreateColor(C[1], C[2], C[3], 1))
    pcall(c.AddPoint, c, RD.FUEL_LOW, CreateColor(C[1], C[2], C[3], 1))
    pcall(c.AddPoint, c, RD.FUEL_LOW + 0.0001, CreateColor(C[1], C[2], C[3], 0))
    pcall(c.AddPoint, c, 1.00, CreateColor(C[1], C[2], C[3], 0))
    RD.fuelCurve = c
    return c
end

--- A colour the client worked out, onto textures. false when the client handed none back.
local function paint(texs, col)
    if type(col) ~= "table" or not col.GetRGBA then return false end
    local any = false
    for _, t in ipairs(texs) do
        if pcall(function() t:SetVertexColor(col:GetRGBA()) end) then any = true end
    end
    return any                     -- true only if the colour LANDED somewhere (Arn's white blade: it never had)
end

-- ------------------------------------------------------------------ drawing helpers

local function line(parent, layer, x1, y1, x2, y2, col, w)
    local l = parent:CreateLine(nil, layer or "ARTWORK")
    l:SetTexture(RD.WHITE)
    l:SetThickness(w or 1)
    l:SetStartPoint("CENTER", parent, x1, y1)
    l:SetEndPoint("CENTER", parent, x2, y2)
    l:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
    return l
end

local function tex(parent, layer, col)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(RD.WHITE)
    t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
    return t
end

--[[ WHERE EVERY SLOT SITS (the geometry). A slot = { b = bearing (radians, 0 up, clockwise), rh / rc / rb = the heal,
  cure and bogey radii (rb nil: no bogey), ph / pc / pb = their sizes, own = your group }.
  PARTY / SOLO (v1): five spokes, 72 degrees apart, the first straight up.
  RAID (Arn, 8 Nov: "raid sectors next"): 8 groups x 5 = 40 FIXED slots, so each person's pip has its place by their
  group and their place in it. Your own group is the top sector, nearer the centre and bigger (the shortest moves);
  the other seven go round clockwise in group order on the outer ring. Bogeys in a raid: your own group only (40
  cast checks twice a second is a second grid's cost for a picture nobody can watch) - the cures are on everyone. ]]
RD.PARTY = { size = 300, rim = 146, rh = 58, rc = 92, rb = 124, ph = 26, pc = 14, pb = 22 }
-- YOU ARE THE MIDDLE (Arn, 8 Nov: "if we want to heal ourselves we are in the middle and stuff build out from us"): your
-- heal pip sits on the centre, your cure just above it, your target's bogey straight up; everyone else builds out from
-- you - a party's four on the diagonals, a raid's on their sectors (your own slot there moves to the centre).
RD.SELF = { b = 0, rh = 0, rc = 30, rb = 124, ph = 28, pc = 14, pb = 22 }
RD.GLYPH = 1.5                -- no box round a pip any more: its role glyph is drawn this much bigger to read alone
RD.RAID = { size = 440, rim = 212, span = math.rad(72), gap = math.rad(6),
            own = { rh = 100, rc = 126, rb = 150, ph = 22, pc = 12, pb = 18 },
            other = { rh = 172, rc = 196, ph = 16, pc = 10 } }
function RD.Geometry(raid, ownGroup)
    local out = {}
    if not raid then
        local P, S = RD.PARTY, RD.SELF
        -- slot 1 is you (RD.Roster puts "player" first): the centre
        out[1] = { b = S.b, rh = S.rh, rc = S.rc, rb = S.rb, ph = S.ph, pc = S.pc, pb = S.pb, own = true, self = true,
                   group = 1, pos = 1 }
        for i = 2, RD.SPOKES do
            out[i] = { b = math.pi / 4 + (i - 2) * math.pi / 2, rh = P.rh, rc = P.rc, rb = P.rb, ph = P.ph, pc = P.pc,
                       pb = P.pb, own = true, group = 1, pos = i }
        end
        return out, P.size, P.rim
    end
    local R = RD.RAID
    ownGroup = ownGroup or 1
    local rest = 2 * math.pi - R.span - 2 * R.gap
    local k = 0
    for g = 1, 8 do
        for p = 1, 5 do
            local s
            if g == ownGroup then
                local o = R.own
                s = { b = -R.span / 2 + (p - 0.5) * R.span / 5, rh = o.rh, rc = o.rc, rb = o.rb, ph = o.ph, pc = o.pc, pb = o.pb, own = true }
            else
                local o = R.other
                local order = (g - ownGroup) % 8             -- 1..7: clockwise from your own group
                local idx = (order - 1) * 5 + p              -- 1..35
                s = { b = R.span / 2 + R.gap + (idx - 0.5) * rest / 35, rh = o.rh, rc = o.rc, ph = o.ph, pc = o.pc, own = false }
            end
            s.group, s.pos = g, p
            k = k + 1
            out[k] = s
        end
    end
    return out, R.size, R.rim
end

--- A point on a slot's bearing, `r` out from the middle.
function RD.Point(s, r) return math.sin(s.b) * r, math.cos(s.b) * r end

--- A square edge of four strips on a frame, tinted `col`; answers the list.
local function edge(f, col, w)
    local out = {}
    for _, s in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = tex(f, "BORDER", col)
        t:SetPoint(s[1]) t:SetPoint(s[2])
        if s[3] then t:SetHeight(w or 2) else t:SetWidth(w or 2) end
        out[#out + 1] = t
    end
    return out
end

--- The role glyph, our own shapes: "tank" a diamond outline, "heal" a cross, "damage" a blade.
--- PLAIN TEXTURES ONLY, turned with SetRotation (8 Nov 2026, Arn's screenshot: a WHITE blade that never went away). The
--- blade and the diamond were Lines, and the client's curve colour never landed on them - the pip kept its starting
--- white. BiS> now proves the road that works: a texture's SetVertexColor(col:GetRGBA()). Every piece starts INVISIBLE
--- (alpha 0), so a colour that does not land shows nothing rather than a stale white sign.
local function glyph(f, role, px)
    local out = {}
    local c = { 1, 1, 1, 0 }
    local function bar(w, h, x, y, rot)
        local t = tex(f, "OVERLAY", c)
        t:SetSize(w, h)
        t:SetPoint("CENTER", f, "CENTER", x or 0, y or 0)
        if rot and t.SetRotation then t:SetRotation(rot) end
        out[#out + 1] = t
        return t
    end
    if role == "heal" then
        bar(px * 0.22, px * 0.62)
        bar(px * 0.62, px * 0.22)
    elseif role == "tank" then
        -- a diamond: four bars on its edges, each turned 45 degrees
        local s, q = px * 0.30, math.pi / 4
        local len = s * math.sqrt(2)
        bar(len, 2, s / 2, s / 2, -q)
        bar(len, 2, s / 2, -s / 2, q)
        bar(len, 2, -s / 2, -s / 2, -q)
        bar(len, 2, -s / 2, s / 2, q)
    else
        -- a blade: a long bar on the diagonal, a short crossguard across it near the hilt
        local s = px * 0.28
        bar(s * 2 * math.sqrt(2), 3, 0, 0, math.pi / 4)
        bar(s * 0.9, 3, -s * 0.45, -s * 0.45, -math.pi / 4)
    end
    return out
end

-- ------------------------------------------------------------------ the frame

local function endDrag(f)
    if not (f and f.dragging) then return end
    f.dragging = nil
    pcall(f.StopMovingOrSizing, f)
    local ok, p, _, rp, x, y = pcall(f.GetPoint, f)
    p, rp, x, y = plain(p), plain(rp), plain(x), plain(y)
    if ok and type(p) == "string" and type(x) == "number" and type(y) == "number" then
        db().pos = { p, type(rp) == "string" and rp or p, x, y }
    end
end
RD.EndDrag = endDrag

function RD.Place()
    local f = RD.frame
    if not f or combat() then return end
    local pos, d = db().pos, db()
    f:ClearAllPoints()
    if type(pos) == "table" and type(pos[1]) == "string" then
        f:SetPoint(pos[1], UIParent, pos[2] or pos[1], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -260, -40)
    end
    f:SetScale(math.max(0.5, math.min(2, tonumber(d.scale) or 1)))
end

--- The scope is drawn at the party size and scaled up for a raid (RD.Arm), so its rings sit where the slots do.
local function buildScope(f)
    local s = CreateFrame("Frame", nil, f)
    s:SetSize(RD.PARTY.size, RD.PARTY.size)
    s:SetPoint("CENTER", f, "CENTER", 0, 0)
    RD.scope = s
    local g = { RD.PHOS[1] * 0.45, RD.PHOS[2] * 0.45, RD.PHOS[3] * 0.45, 0.85 }
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(s)
    bg:SetColorTexture(0.01, 0.04, 0.02, 0.55)
    for _, r in ipairs(RD.RINGS) do
        for k = 1, RD.RING_SEG do
            local a0, a1 = (k - 1) * 2 * math.pi / RD.RING_SEG, k * 2 * math.pi / RD.RING_SEG
            line(s, "BORDER", math.sin(a0) * r, math.cos(a0) * r, math.sin(a1) * r, math.cos(a1) * r, g, 1)
        end
    end
    local h = RD.SIZE / 2 - 6
    line(s, "BORDER", -h, 0, h, 0, g, 1)
    line(s, "BORDER", 0, -h, 0, h, g, 1)
    for k = 0, 35 do
        local a = k * math.pi / 18
        local r2 = (k % 3 == 0) and 134 or 138
        line(s, "BORDER", math.sin(a) * 142, math.cos(a) * 142, math.sin(a) * r2, math.cos(a) * r2, g, 1)
    end
    -- the square's corner brackets
    local b, e = RD.SIZE / 2 - 4, 22
    local bc = { RD.PHOS[1] * 0.6, RD.PHOS[2] * 0.6, RD.PHOS[3] * 0.6, 1 }
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            line(s, "BORDER", sx * b, sy * b, sx * (b - e), sy * b, bc, 2)
            line(s, "BORDER", sx * b, sy * b, sx * b, sy * (b - e), bc, 2)
        end
    end
    -- you, in the middle
    line(s, "ARTWORK", 0, 8, 6, -6, RD.PHOS, 2) line(s, "ARTWORK", 0, 8, -6, -6, RD.PHOS, 2)
    -- the dim places of every slot live on their own layer, unscaled, and go with the scope (RD.PaintQuiet)
    local dims = CreateFrame("Frame", nil, f)
    dims:SetAllPoints(f)
    RD.dims = dims
    return s
end

--- One spoke's pieces: the heal pip (secure), its cure pips (client markers + secure boxes), its bogey, its alert
--- arcs and its dim places. Made once (a pool of 40 at most) and PLACED by RD.PlaceSpoke, out of a fight.
local function buildSpoke(f, i)
    local sp = { i = i }
    -- HEAL: a secure unit button; its face is ours
    local b = CreateFrame("Button", "BiSHealingRadarHeal" .. i, f, "SecureUnitButtonTemplate")
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    b.face = CreateFrame("Frame", nil, b)
    b.face:SetAllPoints(b)
    -- NO BOX (Arn, 8 Nov: "the box outlines are not needed"): the pip is its role glyph alone, in the game's colour.
    -- Red has its own glyph on its own layer, coloured by the red curve, and only THAT layer pulses (a green or amber
    -- pip holds still).
    b.redFace = CreateFrame("Frame", nil, b)
    b.redFace:SetAllPoints(b)
    if b.redFace.CreateAnimationGroup then
        local ok, pulse = pcall(b.redFace.CreateAnimationGroup, b.redFace)
        if ok and pulse then
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(1) fade:SetToAlpha(0.35) fade:SetDuration(0.35)
            pulse:SetLooping("BOUNCE")
            sp.pulse = pulse
        end
    end
    b:HookScript("OnEnter", function() RD.over = sp end)
    b:HookScript("OnLeave", function() if RD.over == sp then RD.over = nil end end)
    sp.heal = b
    -- BOGEY: their target, a red triangle only while it casts; a click is your interrupt (enemies only)
    local k = CreateFrame("Button", "BiSHealingRadarBogey" .. i, f, "SecureActionButtonTemplate")
    if k.RegisterForClicks then k:RegisterForClicks("AnyDown") end
    k.face = CreateFrame("Frame", nil, k)
    k.face:SetAllPoints(k)
    k.face:SetAlpha(0)
    sp.bogey = k
    -- ALERT: a dashed arc on the rim of this spoke, out of range (steady) or LOS (a flash) - three dashes each,
    -- their ends set by RD.PlaceSpoke
    local arc = CreateFrame("Frame", nil, f)
    arc:SetAllPoints(f)
    sp.arcLines = {}
    for d = 1, 3 do sp.arcLines[d] = line(arc, "OVERLAY", 0, 0, 1, 1, RD.COL.red, 3) end
    arc:SetAlpha(0)
    sp.arc = arc
    local los = CreateFrame("Frame", nil, f)
    los:SetAllPoints(f)
    sp.losLines = {}
    for d = 1, 3 do sp.losLines[d] = line(los, "OVERLAY", 0, 0, 1, 1, RD.COL.amber, 3) end
    los:SetAlpha(0)
    -- the dim places, out of a fight
    sp.dims = {}
    for d = 1, 3 do
        local fr = CreateFrame("Frame", nil, RD.dims)
        edge(fr, RD.DIM, 1)
        sp.dims[d] = fr
    end
    if los.CreateAnimationGroup then
        local ok, g = pcall(los.CreateAnimationGroup, los)
        if ok and g then
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(1) a:SetToAlpha(0) a:SetDuration(1.4)
            if g.SetToFinalAlpha then g:SetToFinalAlpha(true) end
            sp.losFade = g
        end
    end
    sp.los = los
    sp.cures = {}
    -- CROSSHAIRS ON YOUR TARGET (Arn, 8 Nov: "need a target pip indicated by crosshairs like on our regular frames"): the
    -- grid's own reticle (FG.Crosshair), magenta like the cockpit's target, round the heal pip when that person is your
    -- target and round the bogey when THEIR target is yours. Plain frames on the radar (not on the secure pips), so only
    -- their alpha ever changes - in a fight too.
    sp.cross = CreateFrame("Frame", nil, f)
    sp.bogeyCross = CreateFrame("Frame", nil, f)
    sp.totCross = CreateFrame("Frame", nil, f)
    for _, c in ipairs({ sp.cross, sp.bogeyCross, sp.totCross }) do
        if NS.FG and NS.FG.Crosshair then NS.FG.Crosshair(c, c == sp.totCross and RD.TOT or RD.CROSS) end
        c:SetFrameLevel(f:GetFrameLevel() + 20)
        c:SetAlpha(0)
    end
    return sp
end

--- Put a spoke where its slot is: sizes, places, the bogey's triangle, the arcs, the dim places. Out of a fight only
--- (the heal pip and the bogey are secure). A slot with no bogey (a raid's other groups) leaves it off.
function RD.PlaceSpoke(sp, s, rim)
    local f = RD.frame
    sp.slot = s
    local b = sp.heal
    b:SetSize(s.ph, s.ph)
    b:ClearAllPoints()
    b:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rh))
    if sp.glyphPx ~= s.ph then
        for _, t in ipairs(sp.glyph or {}) do t:Hide() end
        sp.glyph, sp.role, sp.glyphPx = nil, nil, s.ph
    end
    local k = sp.bogey
    if s.rb then
        k:SetSize(s.pb, s.pb)
        k:ClearAllPoints()
        k:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rb))
        if not k.lines or k.linesPx ~= s.pb then
            for _, l in ipairs(k.lines or {}) do l:Hide() end
            local h = s.pb * 0.42
            local rc = RD.COL.bogey
            k.lines = { line(k.face, "OVERLAY", 0, h, h, -h * 0.8, rc, 2), line(k.face, "OVERLAY", h, -h * 0.8, -h, -h * 0.8, rc, 2),
                        line(k.face, "OVERLAY", -h, -h * 0.8, 0, h, rc, 2) }
            k.linesPx = s.pb
        end
    end
    -- the arcs: three dashes on the rim, either side of the bearing (a raid's slots are close: shorter dashes)
    local step = (s.own and 0.07) or 0.04
    for d = 1, 3 do
        local c = s.b + (d - 2) * step
        local p0, p1 = c - step * 0.35, c + step * 0.35
        sp.arcLines[d]:SetStartPoint("CENTER", f, math.sin(p0) * rim, math.cos(p0) * rim)
        sp.arcLines[d]:SetEndPoint("CENTER", f, math.sin(p1) * rim, math.cos(p1) * rim)
        sp.losLines[d]:SetStartPoint("CENTER", f, math.sin(p0) * (rim - 6), math.cos(p0) * (rim - 6))
        sp.losLines[d]:SetEndPoint("CENTER", f, math.sin(p1) * (rim - 6), math.cos(p1) * (rim - 6))
    end
    -- the crosshairs sit on the pips they frame
    sp.cross:SetSize(s.ph + RD.CROSS_PAD, s.ph + RD.CROSS_PAD)
    sp.cross:ClearAllPoints()
    sp.cross:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rh))
    sp.totCross:SetSize(s.ph + RD.TOT_PAD, s.ph + RD.TOT_PAD)
    sp.totCross:ClearAllPoints()
    sp.totCross:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rh))
    if s.rb then
        sp.bogeyCross:SetSize(s.pb + RD.CROSS_PAD, s.pb + RD.CROSS_PAD)
        sp.bogeyCross:ClearAllPoints()
        sp.bogeyCross:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rb))
    end
    local spots = { { s.rh, s.ph }, { s.rc, s.pc }, { s.rb, s.pb } }
    for d, fr in ipairs(sp.dims) do
        local r, px = spots[d][1], spots[d][2]
        if r then
            fr:SetSize(px, px)
            fr:ClearAllPoints()
            fr:SetPoint("CENTER", f, "CENTER", RD.Point(s, r))
            fr:Show()
        else
            fr:Hide()
        end
    end
end

--- Spoke i, made the first time it is needed (a party needs 5, a raid 40).
function RD.Spoke(i)
    RD.spokes[i] = RD.spokes[i] or buildSpoke(RD.frame, i)
    return RD.spokes[i]
end

--- A system pip in a corner: a secure button (for its click) with our own face.
local function buildSystem(f, name, point, x, y)
    local b = CreateFrame("Button", "BiSHealingRadar" .. name, f, "SecureActionButtonTemplate")
    b:SetSize(RD.SYS_PX, RD.SYS_PX)
    b:SetPoint(point, f, point, x, y)
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    b.face = CreateFrame("Frame", nil, b)
    b.face:SetAllPoints(b)
    b.ring = {}
    local r = RD.SYS_PX / 2 - 1
    for k = 1, 16 do
        local a0, a1 = (k - 1) * math.pi / 8, k * math.pi / 8
        b.ring[k] = line(b.face, "ARTWORK", math.sin(a0) * r, math.cos(a0) * r, math.sin(a1) * r, math.cos(a1) * r, RD.COL.cyan, 2)
    end
    b.icon = b.face:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER") b.icon:SetSize(RD.SYS_PX - 10, RD.SYS_PX - 10)
    return b
end

function RD.Build()
    if RD.frame then return RD.frame end
    local f = CreateFrame("Frame", "BiSHealingRadar", UIParent)
    RD.frame = f
    f:SetSize(RD.SIZE, RD.SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- dragged by the scope, out of a fight only; the drag ENDS before a fight takes the mouse (BiS Tools' lesson, 8 Nov)
    f:SetScript("OnDragStart", function(self)
        if combat() then return end
        self:StartMoving()
        self.dragging = true
    end)
    f:SetScript("OnDragStop", endDrag)
    f:SetScript("OnHide", endDrag)
    buildScope(f)
    RD.spokes = {}                      -- made as the roster needs them (RD.Spoke)
    RD.shield = buildSystem(f, "Shield", "TOPLEFT", 8, -8)
    RD.fuel = buildSystem(f, "Fuel", "TOPRIGHT", -8, -8)
    RD.rations = buildSystem(f, "Rations", "BOTTOMRIGHT", -8, 8)
    -- the fuel pip's own face: a drop; rations: a fork
    RD.fuel.drop = { line(RD.fuel.face, "OVERLAY", 0, 7, 5, -2, RD.COL.cyan, 2), line(RD.fuel.face, "OVERLAY", 0, 7, -5, -2, RD.COL.cyan, 2),
                     line(RD.fuel.face, "OVERLAY", -5, -2, 5, -2, RD.COL.cyan, 2) }
    RD.rations.fork = { line(RD.rations.face, "OVERLAY", -4, 7, -4, -7, RD.COL.cyan, 2), line(RD.rations.face, "OVERLAY", 4, 7, 4, -7, RD.COL.cyan, 2),
                        line(RD.rations.face, "OVERLAY", -4, 0, 4, 0, RD.COL.cyan, 2) }
    -- missiles: your mana as a tape along the bottom, ticks per heal
    local tape = CreateFrame("StatusBar", nil, f)
    tape:SetSize(RD.SIZE * 0.5, 6)
    tape:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    tape:SetStatusBarTexture(RD.WHITE)
    tape:SetStatusBarColor(RD.PHOS[1], RD.PHOS[2], RD.PHOS[3], 0.85)
    tape.track = tape:CreateTexture(nil, "BACKGROUND")
    tape.track:SetAllPoints(tape)
    tape.track:SetColorTexture(0.04, 0.14, 0.08, 0.9)
    tape.ticks = {}
    RD.tape = tape
    f:Hide()
    RD.Place()
    return f
end

-- ------------------------------------------------------------------ who is on the radar

--- Who sits in which slot: { [slot] = unit } plus raid (true/false) and your own group. A party: you first, then
--- party1-4 (slots 1-5). A raid: slot (group - 1) * 5 + place in the group, places in roster order - FIXED by group.
function RD.Roster()
    local out = {}
    local okR, raid = pcall(IsInRaid)
    if okR and plain(raid) == true then
        local okN, n = pcall(GetNumGroupMembers)
        n = okN and plain(n) or 0
        local filled, mine = {}, nil
        for i = 1, (type(n) == "number" and math.min(n, 40) or 0) do
            local okI, _, _, group = pcall(GetRaidRosterInfo, i)
            group = okI and tonumber(plain(group)) or nil
            if group and group >= 1 and group <= 8 then
                filled[group] = (filled[group] or 0) + 1
                if filled[group] <= 5 then out[(group - 1) * 5 + filled[group]] = "raid" .. i end
                local okU, isMe = pcall(UnitIsUnit, "raid" .. i, "player")
                if okU and plain(isMe) == true then mine = group end
            end
        end
        return out, true, mine or 1
    end
    out[1] = "player"
    for i = 1, RD.SPOKES - 1 do
        local okE, e = pcall(UnitExists, "party" .. i)
        if okE and plain(e) == true then out[i + 1] = "party" .. i end
    end
    return out, false, 1
end

--- tank (BiS> now's tank, or a raid main tank), heal (a healing class), or damage. Out of a fight.
function RD.Role(unit)
    local tank = NS.FN and NS.FN.Tank and NS.FN.Tank()
    local okN, name = pcall(GetUnitName, unit, false)
    name = okN and plain(name) or nil
    if type(tank) == "string" and name == tank then return "tank" end
    if GetPartyAssignment then
        local ok, mt = pcall(GetPartyAssignment, "MAINTANK", unit)
        if ok and plain(mt) == true then return "tank" end
    end
    local ok, _, c = pcall(UnitClass, unit)
    c = ok and plain(c) or nil
    if c and RD.HEALER_CLASS[c] then return "heal" end
    return "damage"
end

-- ------------------------------------------------------------------ arming (out of a fight only)

local function armHeal(sp, unit)
    local b = sp.heal
    b:SetAttribute("unit", unit)
    if NS.FM and NS.FM.ApplyTo then pcall(NS.FM.ApplyTo, b) end      -- your binds on every other click
    local h = RD.heal
    -- a plain left-click is the radar heal (the attribute without a modifier wins over "*type1")
    b:SetAttribute("type1", h and "spell" or nil)
    b:SetAttribute("spell1", h and h.cast or nil)
    b.unit = unit
    -- the face: the role glyph, rebuilt only when the role changed
    local role = RD.Role(unit)
    if sp.role ~= role then
        for _, t in ipairs(sp.glyph or {}) do t:Hide() end
        for _, t in ipairs(sp.redGlyph or {}) do t:Hide() end
        local px = ((sp.slot and sp.slot.ph) or RD.PARTY.ph) * RD.GLYPH
        sp.glyph = glyph(b.face, role, px)
        sp.redGlyph = glyph(b.redFace, role, px)
        sp.role = role
    end
    sp.paintTex = {}
    for _, t in ipairs(sp.glyph) do sp.paintTex[#sp.paintTex + 1] = t end
    -- where amber starts: your heal against their max health, both plain out of a fight
    local amount = RD.HealAmount()
    local okM, mx = pcall(UnitHealthMax, unit)
    mx = okM and plain(mx) or nil
    sp.amber = (amount and type(mx) == "number" and mx > 0) and (1 - amount / mx) or RD.AMBER
end

local function armBogey(sp, unit)
    local k = sp.bogey
    local tok = unit == "player" and "target" or (unit .. "target")
    local cast = NS.FG and NS.FG.KickCast and NS.FG.KickCast() or nil
    k:SetAttribute("*harmbutton1", cast and "kick" or nil)
    k:SetAttribute("*type-kick", cast and "spell" or nil)
    k:SetAttribute("*spell-kick", cast)
    k:SetAttribute("unit", tok)
    -- a right-click targets their target (any time: your crosshairs go on it); a left-click on an enemy is the kick
    k:SetAttribute("type2", "target")
    k:EnableMouse(true)
    sp.tok, sp.kick = tok, cast
end

--- The cure pips of a spoke: one client marker + one secure box per cure your class has.
local function armCures(sp, unit)
    local FA = NS.FA
    local s = sp.slot
    local cures = (unit and s and FA and FA.Cures and FA.Available and FA.Available()) and FA.Cures() or {}
    -- a box beyond what this spoke needs now: off (its marker stops drawing, its click does nothing)
    for n, c in ipairs(sp.cures) do
        if not cures[n] then
            if c.container and c.container.SetEnabled then pcall(c.container.SetEnabled, c.container, false) end
            c.box:SetAttribute("spell", nil)
            c.box:EnableMouse(false)
        end
    end
    local f = RD.frame
    for n, cure in ipairs(cures) do
        local px = s.pc
        local off = (n - (#cures + 1) / 2) * (px + 6)
        local cx, cy = RD.Point(s, s.rc)
        cx, cy = cx + math.cos(s.b) * off, cy - math.sin(s.b) * off
        local c = sp.cures[n]
        if not c then
            c = {}
            c.box = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
            if c.box.RegisterForClicks then c.box:RegisterForClicks("AnyDown") end
            sp.cures[n] = c
        end
        c.box:SetSize(px + 4, px + 4)
        c.box:ClearAllPoints()
        c.box:SetPoint("CENTER", f, "CENTER", cx, cy)
        c.box:SetAttribute("type", "spell")
        c.box:SetAttribute("spell", cure.name)
        c.box:SetAttribute("unit", unit)
        c.box:EnableMouse(true)
        c.cure = cure.name
        -- the client's marker: a diamond in the cure's colour, only while there is something to cure. Built once per
        -- place and cure; a new unit in the same place is only told who to watch.
        local key = cure.name .. ":" .. math.floor(cx + 0.5) .. ":" .. math.floor(cy + 0.5) .. ":" .. px
        if c.key == key and c.container then
            pcall(c.container.SetUnit, c.container, unit)
            if c.container.SetEnabled then pcall(c.container.SetEnabled, c.container, true) end
        else
            if c.container and c.container.SetEnabled then pcall(c.container.SetEnabled, c.container, false) end
            c.container, c.key = nil, nil
            local ok, container = pcall(CreateFrame, "AuraContainer", nil, f, "CustomAuraContainerTemplate")
            if ok and container then
                container:SetSize(1, 1)
                container:SetPoint("CENTER", f, "CENTER", cx, cy)
                container:SetUnit(unit)
                local first
                for t in pairs(cure.types or {}) do first = first or t end
                local col = RD.CURE_COL[first or ""] or RD.COL.green
                c.container, c.key = container, key
                c.slot = FA.AddSlot(container, "BiSRadarCure" .. sp.i .. "_" .. n, "HARMFUL|RAID_PLAYER_DISPELLABLE", {
                    candidateFilters = { includeDispelTypes = cure.types },
                    initializeFrame = FA.Placed(function(button)
                        if button.GetRegions then
                            for _, r in ipairs({ button:GetRegions() }) do if r.Hide then pcall(r.Hide, r) end end
                        end
                        for _, k in ipairs({ "Icon", "icon", "Border", "border", "Count", "count", "Cooldown" }) do
                            local part = button[k]
                            if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
                        end
                        local d = button:CreateTexture(nil, "OVERLAY")
                        d:SetTexture(RD.WHITE)
                        d:SetPoint("CENTER") d:SetSize(px * 0.72, px * 0.72)
                        d:SetVertexColor(col[1], col[2], col[3], col[4])
                        if d.SetRotation then d:SetRotation(math.pi / 4) end
                        if button.EnableMouse then pcall(button.EnableMouse, button, false) end
                        if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
                    end, px, "CENTER", f, cx, cy),
                })
            end
        end
    end
end

--- Your watched self buff (Water Shield): the red lights while it is NOT on you. The client's own icon arriving (its
--- aura button shown) hides the red - so the pip is dark exactly while the buff is up, and nothing is read.
--- The shield the refuel pip watches. NOT the buff reminder's switch (Arn, 8 Nov: "i dont have water shield where is the
--- button on my radar" - his reminder was off, `selfBuffs.none`, so FS.Target answered nothing and the pip never armed):
--- the names the player chose for the reminder if there are any, else the class's own (FS.CLASS: Water Shield for a
--- shaman); the first one this character has trained.
function RD.ShieldTarget()
    local FS = NS.FS
    if not FS then return nil end
    local d = NS.DB()
    local own = type(d.selfBuffs) == "table" and d.selfBuffs or nil
    local list = (own and #own > 0) and own or nil
    if not list then
        local okC, _, class = pcall(UnitClass, "player")
        list = (FS.CLASS and FS.CLASS[(okC and plain(class)) or ""]) or {}
    end
    for _, name in ipairs(list) do
        if FS.Knows and FS.Knows(name) and FS.SpellIds then
            local ids = FS.SpellIds(name)
            if #ids > 0 then return name, ids end
        end
    end
    return nil
end

local function armShield()
    local b = RD.shield
    local name, ids = RD.ShieldTarget()
    b:SetAttribute("*type1", name and "macro" or nil)
    b:SetAttribute("*macrotext1", name and ("/cast " .. name) or nil)
    b:EnableMouse(name and true or false)
    b.shieldName = name
    if not name or b.shieldFor == name then return end
    b.shieldFor = name
    local get = C_Spell and C_Spell.GetSpellTexture
    if get then
        local ok, t = pcall(get, name)
        if ok and t and not (NS.Secret and NS.Secret(t)) then b.icon:SetTexture(t) end
    end
    if b.icon.SetDesaturated then b.icon:SetDesaturated(true) end
    b.icon:SetVertexColor(1, 0.25, 0.3, 1)
    local FA = NS.FA
    if not (FA and FA.Available and FA.Available() and FA.AddSlot and ids and #ids > 0) then return end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not (ok and container) then return end
    container:SetSize(1, 1)
    container:SetPoint("CENTER", b)
    container:SetUnit("player")
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    b.container = container
    b.slot = FA.AddSlot(container, "BiSRadarShield", "HELPFUL", {
        candidateFilters = { includeSpellIDs = want },
        initializeFrame = FA.Placed(function(button)
            if button.GetRegions then for _, r in ipairs({ button:GetRegions() }) do if r.Hide then pcall(r.Hide, r) end end end
            if button.EnableMouse then pcall(button.EnableMouse, button, false) end
            -- the buff is here: the red goes dark; it comes back when the client takes the button away
            b.face:SetAlpha(0)
            button:HookScript("OnShow", function() b.face:SetAlpha(0) end)
            button:HookScript("OnHide", function() b.face:SetAlpha(1) end)
        end, RD.SYS_PX, "CENTER", b, 0, 0),
    })
end

--- The best item in your bags whose use is `spellName` ("Drink" / "Food"; `needWords` in its use text), by the level it
--- needs - out of a fight only. Answers an item id or nil.
function RD.BestItem(spellName, needWords)
    if combat() then return nil end
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local idOf = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not (getSpell and num and idOf) then return nil end
    local okL, lvl = pcall(UnitLevel, "player")
    lvl = okL and plain(lvl) or 60
    local best, bestLvl
    for bag = 0, 4 do
        local okN, n = pcall(num, bag)
        for slot = 1, (okN and type(n) == "number" and n or 0) do
            local okI, id = pcall(idOf, bag, slot)
            id = okI and plain(id) or nil
            if type(id) == "number" then
                local okS, sname, sid = pcall(getSpell, id)
                sname = okS and plain(sname) or nil
                if sname == spellName then
                    local fits = true
                    if needWords then
                        local getDesc = C_Spell and C_Spell.GetSpellDescription
                        local okD, text = false, nil
                        if getDesc and sid then okD, text = pcall(getDesc, sid) end
                        text = okD and plain(text) or nil
                        fits = type(text) == "string" and text:lower():find(needWords, 1, true) ~= nil
                    end
                    local need = 0
                    if fits and info then
                        local okF, _, _, _, _, minLvl = pcall(info, id)
                        need = okF and tonumber(plain(minLvl)) or 0
                    end
                    if fits and need <= (lvl or 60) and (not bestLvl or need > bestLvl) then best, bestLvl = id, need end
                end
            end
        end
    end
    return best
end

local function armUse(b, id)
    b:SetAttribute("*type1", id and "macro" or nil)
    b:SetAttribute("*macrotext1", id and ("/use item:" .. id) or nil)
    b:EnableMouse(id and true or false)
    b.item = id
end

--- The food the rations pip offers now, out of a fight. BiS TOOLS FIRST (Arn, 8 Nov: "bis tool still shows the eat food
--- icon in the toolbox but its not in the radar need it there too"): BiSToolsAPI.FoodNow (v7) is the tools box's own
--- rule and its own food, so both light together. Without BiS Tools: Well Fed missing and a well-fed food in the bags.
function RD.FoodWanted()
    if combat() then return nil end
    local A = _G.BiSToolsAPI
    if type(A) == "table" and A.major == 1 and type(A.FoodNow) == "function" then
        local ok, item, why = pcall(A.FoodNow)
        if ok and type(item) == "number" then return item end
        if ok and why ~= "not ready" and why ~= "xp tool off" then return nil end   -- the box says no: so do we
    end
    local fed = RD.WellFed()
    return (fed == false) and RD.BestItem("Food", "well fed") or nil
end

--- Is Well Fed on you? Out of a fight only (an aura read); nil when it cannot say.
function RD.WellFed()
    if combat() then return nil end
    local find = AuraUtil and AuraUtil.FindAuraByName
    if not find then return nil end
    local ok, name = pcall(find, "Well Fed", "player", "HELPFUL")
    if not ok then return nil end
    return plain(name) ~= nil
end

--- The missile tape's ticks: one per radar heal your full mana holds, worked out of a fight when the numbers are plain.
local function armTape()
    local tape = RD.tape
    for _, t in ipairs(tape.ticks) do t:Hide() end
    if combat() or not RD.heal then return end
    local cost
    local getCost = C_Spell and C_Spell.GetSpellPowerCost
    if getCost then
        local ok, list = pcall(getCost, RD.heal.cast or RD.heal.name)
        list = ok and plain(list) or nil
        if type(list) == "table" and type(list[1]) == "table" then cost = plain(list[1].cost) end
    end
    local okM, mx = pcall(UnitPowerMax, "player", 0)
    mx = okM and plain(mx) or nil
    if not (type(cost) == "number" and cost > 0 and type(mx) == "number" and mx > 0) then return end
    local n = math.min(30, math.floor(mx / cost))
    local w = tape:GetWidth()
    for k = 1, n - 1 do
        local t = tape.ticks[k]
        if not t then
            t = tape:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(0.01, 0.06, 0.03, 1)
            tape.ticks[k] = t
        end
        t:ClearAllPoints()
        t:SetSize(1, 6)
        t:SetPoint("LEFT", tape, "LEFT", w * k * cost / mx, 0)
        t:Show()
    end
    RD.missiles = n
end

--- Everything secure, written once per change - OUT OF A FIGHT ONLY (asked in one, it waits: RD.pending).
function RD.Arm()
    if combat() then RD.pending = true return false end
    RD.pending = nil
    RD.Build()
    RD.heal = RD.Heal()
    RD.HealAmount(RD.heal)
    local units, raid, mine = RD.Roster()
    RD.units, RD.raid, RD.ownGroup = units, raid, mine
    local slots, size, rim = RD.Geometry(raid, mine)
    -- in a raid your own slot (wherever your group put you) moves to the centre; its sector keeps the gap
    if raid then
        for i, s in ipairs(slots) do
            local u = units[i]
            if u then
                local okU, me = pcall(UnitIsUnit, u, "player")
                if okU and plain(me) == true then
                    local S, own = RD.SELF, RD.RAID.own
                    slots[i] = { b = S.b, rh = S.rh, rc = S.rc, rb = S.rb, ph = own.ph + 4, pc = own.pc, pb = own.pb,
                                 own = true, self = true, group = s.group, pos = s.pos }
                end
            end
        end
    end
    RD.slots, RD.rim = slots, rim
    -- the square grows for a raid; the scope's drawing scales with it, so its rings sit where the slots do
    RD.frame:SetSize(size, size)
    RD.scope:SetScale(size / RD.PARTY.size)
    for i, s in ipairs(slots) do
        local sp = RD.Spoke(i)
        local unit = units[i]
        sp.unit = unit
        RD.PlaceSpoke(sp, s, rim)
        sp.heal:Show()
        if unit then
            sp.heal:EnableMouse(true)
            armHeal(sp, unit)
            if s.rb then armBogey(sp, unit) else sp.bogey:SetAttribute("unit", nil) sp.bogey:EnableMouse(false) sp.kick = nil end
        else
            sp.heal:SetAttribute("unit", nil)
            sp.heal:SetAttribute("type1", nil)
            sp.heal:EnableMouse(false)
            sp.bogey:SetAttribute("unit", nil)
            sp.bogey:EnableMouse(false)
            sp.kick, sp.paintTex = nil, nil
        end
        armCures(sp, unit)
        if s.rb then sp.bogey:Show() else sp.bogey:Hide() end
    end
    -- spokes beyond this layout (a raid became a party): off, out of the way
    for i = #slots + 1, #RD.spokes do
        local sp = RD.spokes[i]
        sp.unit, sp.kick, sp.paintTex = nil, nil, nil
        sp.heal:SetAttribute("unit", nil) sp.heal:SetAttribute("type1", nil) sp.heal:EnableMouse(false) sp.heal:Hide()
        sp.bogey:SetAttribute("unit", nil) sp.bogey:EnableMouse(false) sp.bogey:Hide()
        armCures(sp, nil)
        for _, fr in ipairs(sp.dims) do fr:Hide() end
        sp.arc:SetAlpha(0)
    end
    armShield()
    armUse(RD.fuel, RD.BestItem("Drink"))
    armUse(RD.rations, RD.FoodWanted())
    armTape()
    RD.Paint()
    return true
end

-- ------------------------------------------------------------------ painting (any time: colours and alpha only)

--- One spoke's heal pip, coloured by the client from their health.
function RD.PaintHeal(sp)
    if not (sp and sp.unit and sp.paintTex) then
        if sp and sp.heal then sp.heal.face:SetAlpha(0) end
        return false
    end
    -- somebody who left (a slot whose re-layout waits for the fight's end): nothing at their spot, not a stale sign
    local okE, there = pcall(UnitExists, sp.unit)
    if okE and plain(there) == false then sp.heal.face:SetAlpha(0) return false end
    sp.heal.face:SetAlpha(1)
    local curve = RD.Curve(sp.amber)
    if not (curve and UnitHealthPercent) then
        -- no curves on this client: the pip stays at its spot, plainly green, rather than lie about urgency
        for _, t in ipairs(sp.paintTex) do t:SetVertexColor(RD.COL.green[1], RD.COL.green[2], RD.COL.green[3], 0.6) end
        return false
    end
    local ok, col = pcall(UnitHealthPercent, sp.unit, true, curve)
    local drew = ok and paint(sp.paintTex, col)
    if not drew then sp.heal.face:SetAlpha(0) end              -- no colour back: nothing, never a stale sign
    local red = RD.RedCurve()
    if red then
        local okR, rc = pcall(UnitHealthPercent, sp.unit, true, red)
        if okR and sp.redGlyph then paint(sp.redGlyph, rc) end
        if sp.pulse and not (sp.pulse.IsPlaying and sp.pulse:IsPlaying()) then sp.pulse:Play() end
    end
    return drew
end

--- In a fight the scope, the empty slots and the idle bogeys are see-through; out of one they are drawn dim.
function RD.PaintQuiet()
    local fight = combat()
    -- THE SCOPE STAYS IN A FIGHT (Arn, 8 Nov: "i like this green outline in combat too"): rings, cross and corners are
    -- the instrument; only the pips come and go
    if RD.scope then RD.scope:SetAlpha(1) end
    -- the dim slot outlines are never drawn (Arn, 8 Nov: "the box outlines are not needed"); the scope alone says where
    if RD.dims then RD.dims:SetAlpha(0) end
    if RD.tape then RD.tape.track:SetAlpha(fight and 0 or 1) end
    for _, b in ipairs({ RD.fuel, RD.rations }) do
        if b then b.face:SetAlpha((not fight and b.item) and 1 or 0) end
    end
    if RD.fuel and not fight then
        -- out of a fight the fuel pip says "low" from the curve too, and shows only with water to drink
        local c = RD.FuelCurve()
        if c and UnitPowerPercent and RD.fuel.item then
            local ok, col = pcall(UnitPowerPercent, "player", 0, true, c)
            if ok then paint(RD.fuel.drop, col) paint(RD.fuel.ring, col) end
        end
    end
end

--- Bogeys and range arcs: the ticker's work while shown.
--- Is `unit` your target? Onto `frame`'s alpha: plain yes/no, or a SECRET answer handed to the client
--- (SetAlphaFromBoolean, the grid's own road - FG.PaintTarget), so it still works inside an instance. Never tested by us.
local function crossOn(frame, unit, whose)
    if not (frame and unit and UnitIsUnit) then if frame then frame:SetAlpha(0) end return false end
    local ok, same = pcall(UnitIsUnit, unit, whose or "target")
    if not ok or same == nil then frame:SetAlpha(0) return false end
    if NS.Secret and NS.Secret(same) then
        if not pcall(function() frame:SetAlphaFromBoolean(same, 1, 0) end) then frame:SetAlpha(0) end
        return "secret"
    end
    frame:SetAlpha((same == true or same == 1) and 1 or 0)
    return same == true or same == 1
end

--- The crosshairs: on the pip of whoever is your target, and on the bogey of whoever's target is yours. Asked when your
--- target changes (and after a layout), never on the ticker - a 40-man raid is 40 pips.
function RD.PaintCross()
    for _, sp in ipairs(RD.spokes or {}) do
        crossOn(sp.cross, sp.unit)
        crossOn(sp.totCross, sp.unit, "targettarget")       -- who your target is on
        crossOn(sp.bogeyCross, (sp.unit and sp.slot and sp.slot.rb) and sp.tok or nil)
    end
end

--- THEIR TARGET, WHERE THE INTERRUPT LIVES (Arn, 8 Nov: "a pip for their target where the interrupt button would live"):
--- a quiet phosphor triangle while they have a HOSTILE target, red the moment it casts (a click = your interrupt; a
--- right-click targets it, so your crosshairs go on it). Hostile is the client's answer (UnitCanAttack); a secret one
--- goes through its own curve into the alpha. Nothing to show: invisible.
local function paintContact(sp, lit)
    local k = sp.bogey
    local col = lit and RD.COL.bogey or RD.CONTACT
    for _, l in ipairs(k.lines or {}) do l:SetVertexColor(col[1], col[2], col[3], 1) end
    if lit then k.face:SetAlpha(1) return true end
    -- ONLY WHEN IT CASTS (Arn, 8 Nov, four green triangles over a party on one mob: "why is it showing interrupt buttons
    -- when its not casting" - picked "only when casting"). The quiet green contact below is kept, switched off by
    -- RD.CONTACT_SHOWN, should it ever be wanted back.
    if not RD.CONTACT_SHOWN then k.face:SetAlpha(0) return false end
    local okE, there = pcall(UnitExists, sp.tok)
    there = okE and there
    if NS.Secret and NS.Secret(there) then there = true end           -- let the hostile answer decide
    if not there then k.face:SetAlpha(0) return false end
    local okH, hostile = pcall(UnitCanAttack, "player", sp.tok)
    if not okH then k.face:SetAlpha(0) return false end
    if NS.Secret and NS.Secret(hostile) then
        local tern = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
        local made, a = false, 0
        if tern then made, a = pcall(tern, hostile, RD.CONTACT[4], 0) end
        if not (made and pcall(k.face.SetAlpha, k.face, a)) then k.face:SetAlpha(0) end
        return "secret"
    end
    k.face:SetAlpha(hostile == true and RD.CONTACT[4] or 0)
    return hostile == true
end

function RD.Look()
    local FG = NS.FG
    for _, sp in ipairs(RD.spokes or {}) do
        if sp.unit and sp.tok and sp.slot and sp.slot.rb then
            -- red only when you have an interrupt to answer it with; the quiet pip shows either way
            local lit = sp.kick and FG and FG.Casting and FG.Casting(sp.tok) or false
            paintContact(sp, lit)
            RD.PaintRange(sp)
        elseif sp.unit then
            sp.bogey.face:SetAlpha(0)
            RD.PaintRange(sp)
        else
            sp.bogey.face:SetAlpha(0)
            sp.arc:SetAlpha(0)
        end
    end
end

--- The range arc: shown when the client says they are out of reach (a secret answer goes through its own ternary).
function RD.PaintRange(sp)
    local spell = RD.heal and (RD.heal.cast or RD.heal.name)
    local range = C_Spell and C_Spell.IsSpellInRange
    local answer, asked
    if range and spell then asked, answer = pcall(range, spell, sp.unit) end
    local secret = NS.Secret and NS.Secret(answer)
    if asked and not secret and answer == nil and UnitInRange then
        local checked
        asked, answer, checked = pcall(UnitInRange, sp.unit)
        if asked and not (NS.Secret and NS.Secret(checked)) and checked == false then answer = nil end
        secret = NS.Secret and NS.Secret(answer)
    end
    if not asked then sp.arc:SetAlpha(0) return nil end
    if secret then
        local tern = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
        if not tern then sp.arc:SetAlpha(0) return nil end
        local made, a = pcall(tern, answer, 0, 1)
        if not (made and pcall(sp.arc.SetAlpha, sp.arc, a)) then sp.arc:SetAlpha(0) end
        return "secret"
    end
    sp.arc:SetAlpha((answer == false or answer == 0) and 1 or 0)
    return answer
end

--- The fuel tape: the client's numbers, handed on untouched.
function RD.PaintTape()
    local tape = RD.tape
    if not tape then return end
    local okM, mx = pcall(UnitPowerMax, "player", 0)
    local okV, v = pcall(UnitPower, "player", 0)
    if okM and okV then
        pcall(tape.SetMinMaxValues, tape, 0, mx)
        pcall(tape.SetValue, tape, v)
    end
end

function RD.Paint()
    if not RD.frame then return end
    for _, sp in ipairs(RD.spokes or {}) do RD.PaintHeal(sp) end
    RD.PaintQuiet()
    RD.PaintTape()
    RD.PaintCross()
    RD.Look()
end

-- ------------------------------------------------------------------ on and off

local function startTicker()
    if RD.ticker or not (C_Timer and C_Timer.NewTicker) then return end
    local n = 0
    RD.ticker = C_Timer.NewTicker(RD.TICK, function()
        if not RD.Active() then return end
        RD.Look()
        -- the food goes due on BiS Tools' own clock (Well Fed running low): asked again every RD.FOOD_EVERY ticks, out
        -- of a fight - one API question, and a re-arm only when the answer changed
        n = n + 1
        if n >= RD.FOOD_EVERY and not combat() and RD.rations then
            n = 0
            local want = RD.FoodWanted()
            if want ~= RD.rations.item then armUse(RD.rations, want) RD.PaintQuiet() end
        end
    end)
end
local function stopTicker()
    if RD.ticker then RD.ticker:Cancel() RD.ticker = nil end
end

--- Bring the radar in or out to match the switch. Out of a fight only; asked in one, it waits.
function RD.Apply()
    local want = RD.On()
    if combat() then
        if want ~= RD.Active() then RD.pending = true end
        return false
    end
    if want then
        RD.Build()
        RD.shownFor = true
        RD.Place()
        RD.frame:Show()
        RD.Arm()
        startTicker()
    else
        RD.shownFor = nil
        if RD.frame then RD.frame:Hide() end
        stopTicker()
    end
    -- the grid gives way, or comes back (FG.Hidden asks RD.Active; the saved `shown` is never touched)
    if NS.FG and NS.FG.Layout and NS.FG.anchor then pcall(NS.FG.Layout) end
    return true
end

--- The hidden settings: `/bish alpha radar heal <spell>` | `scale <50-200>` | `center`.
function RD.Command(rest)
    local word, arg = tostring(rest or ""):match("^%s*(%S+)%s*(.-)%s*$")
    word = word and word:lower() or ""
    local P = NS.Print or print
    if word == "heal" then
        if arg == "" or arg:lower() == "default" then
            db().heal = nil
        else
            db().heal = titled(arg)
        end
        local was = RD.heal
        RD.Arm()
        local h = RD.heal
        P("radar heal: %s%s", h and h.cast or "none trained",
          (db().heal and not (h and h.name == db().heal)) and ("  (|cfff08cb0" .. db().heal .. "|r is not in your spellbook)") or "")
        return h, was
    elseif word == "scale" then
        local n = tonumber(arg)
        if n then db().scale = math.max(50, math.min(200, n)) / 100 end
        RD.Place()
        P("radar scale: %d%%", math.floor((db().scale or 1) * 100 + 0.5))
    elseif word == "center" or word == "centre" then
        db().pos = nil
        RD.Place()
        P("radar: back in its place")
    else
        local h = RD.heal or RD.Heal()
        P("radar: heal %s, %d missiles a full tank.  |cff968ead/bish alpha radar heal <spell> | scale <50-200> | center|r",
          h and h.cast or "none", RD.missiles or 0)
    end
end

-- ------------------------------------------------------------------ events

local ev = CreateFrame("Frame")
RD.events = ev
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
                     "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA", "SPELLS_CHANGED",
                     "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "PLAYER_TARGET_CHANGED", "UNIT_TARGET" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "PLAYER_LOGIN" then RD.Apply() return end
    if event == "PLAYER_REGEN_DISABLED" then
        -- a fight: the drag ends first (before the lockdown takes the mouse), then everything goes quiet
        if RD.frame then endDrag(RD.frame) end
        if RD.Active() then RD.PaintQuiet() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if RD.pending then RD.Apply() if RD.Active() then RD.Arm() end
        elseif RD.Active() then RD.PaintQuiet() end
        return
    end
    if not RD.Active() then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED" then
        RD.Arm()                           -- in a fight it only marks RD.pending
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        for _, sp in ipairs(RD.spokes) do if sp.unit == a1 then RD.PaintHeal(sp) end end
    elseif event == "UNIT_POWER_UPDATE" then
        if a1 == "player" then RD.PaintTape() RD.PaintQuiet() end
    elseif event == "UNIT_AURA" then
        if a1 == "player" and not combat() then
            local want = RD.FoodWanted()
            if want ~= RD.rations.item then armUse(RD.rations, want) RD.PaintQuiet() end
        end
    elseif event == "UNIT_TARGET" then
        if a1 == "target" then RD.PaintCross() end      -- your target picked someone else: the amber mark moves
    elseif event == "PLAYER_TARGET_CHANGED" then
        RD.PaintCross()
        RD.Look()
    elseif event == "UI_ERROR_MESSAGE" then
        -- a heal that failed on line of sight: the spoke under the mouse flashes amber at its rim
        local text = a2
        if NS.Secret and NS.Secret(text) then return end
        local words = NS.FG and NS.FG.FailWords and NS.FG.FailWords() or {}
        if type(text) == "string" and words[text] == "LOS" and RD.over then
            local sp = RD.over
            sp.los:SetAlpha(1)
            if sp.losFade then sp.losFade:Stop() sp.losFade:Play() end
            RD.lastLos = sp.i
        end
    end
end)

NS.AlphaFeature{ key = RD.KEY, name = "the radar",
                 desc = "the grid as a quiet radar: only what needs a click lights up (in a fight everything else is invisible)",
                 apply = function() RD.Apply() end, cmd = function(rest) return RD.Command(rest) end }
