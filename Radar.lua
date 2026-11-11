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
  THE FUEL GAUGE across the top, sideways (buildGauge; 9 Nov): your mana racing the boss's health on one tape, the red you are behind
  by, a magenta caret on the boss, a hot pulsing BINGO band when the boss is 30% ahead, a cyan chevron while you are
  generating (out of the five second rule). THE MANA COLUMN beside it, icons only, top to bottom: the STABILIZER (your
  keep-up self buff - Water Shield - red while it is NOT on you: the client's own icon arriving covers the red), MANA
  TIDE, the best MANA POTION, the best DRINK (each lit by its own curve once you miss what it restores - learned out of a
  fight; the drink out of a fight only), RATIONS (out of a fight, Well Fed missing and a well-fed food in your bags).
  A FAILED CLICK says why under the pip, in the grid's red letters: LOS or RANGE (UI_ERROR_MESSAGE, RD.HeardError) -
  only when you click, never standing (9 Nov 2026). Everything lit pulses (RD.Pulse) and carries the GCD sweep.

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
RD.FADE_PX = 380              -- the dark disc's art at party size: solid to r 148 (past the outer ring), gone by r 190
RD.SPOKES = 5                 -- a party's spokes; a raid has 40 fixed slots (RD.Geometry)
RD.SYS_PX = 22                 -- a system pip (Arn, 8 Nov: five in the mana column - 26 reached a raid cure ring)
RD.RINGS = { 40, 80, 120, 142 }
RD.RING_SEG = 40
RD.GREEN, RD.AMBER, RD.RED = 0.90, 0.80, 0.35    -- below: green / amber (when the heal size is unknown) / red
RD.FUEL_LOW = 0.30
-- THE FUEL GAUGE (8 Nov 2026, Arn: "a quasi mana/heal efficiency gauge ... my mana to track the boss health bar ... the
-- delta indicates we are keeping pace or bingo fuel"). SIDEWAYS ALONG THE TOP since 9 Nov (Arn: "mana gauge ... put it on
-- top side ways that way only one rail per side"): `w` = the tape's thickness, `left` / `right` = the room kept at its
-- ends (the ship's placard, then the ramjet), `base` = the tape's bottom above the rail's bottom (the scale hangs under
-- it), `flag` = how far the BINGO window reaches past the tape.
RD.GAUGE = { w = 7, left = 56, right = 64, base = 19, flag = 5 }
-- THE RAILS, OUTSIDE THE SQUARE (Arn, 8 Nov: "pop out the rail to the left of the radar square and the gauge too in its own
-- rail"; 9 Nov: the gauge on top, one rail a side): solid strips in RD.PLATE's dark - the fuel GAUGE's rail across the top
-- (over the tool rail and the square), the TOOL rail on the left (stabilizer, Mana Tide, potion, drink, rations), the
-- DEFENCE rail on the right. Children of the radar, so they move and hide with it; solid, so the stabilizer's cover (the
-- same dark) melts into its rail.
RD.RAIL_GAP = 3                                    -- between the rails, and between the tool rail and the square
RD.TOOL_RAIL_W = 22 + 8                            -- a system pip and a margin
RD.GAUGE_RAIL_H = 44                               -- the readout box, the tape, the scale's ticks and numbers under it
-- THE SHIPS (9 Nov 2026, Arn: "lean to the ryan gosling in the spirit of star wars imperial purple and white accents like
-- a fighter and the more the group gets we change the color to finally ending in star destroyer theam"). The radar's
-- chrome takes the look of a bigger ship as the group grows: night-drive neon on a small fighter, cooling through a
-- gunship and a cruiser to a capital ship's grey hull with white lines. OUR OWN looks and names - the feeling is
-- borrowed, never a film's ship shapes, emblem, names or lettering. Only the chrome changes: the hull (RD.PLATE - the
-- disc, the rails, the stabilizer's cover), the scope's lines, its corner brackets, the centre mark, the fuel tape and its
-- scale. WARNINGS KEEP THEIR COLOURS in every ship (the health pips, the boss's red, BINGO, LOS / RANGE, amber, cyan), so
-- a warning reads the same everywhere. Picked by the group's size in RD.Arm - out of a fight only, never mid-fight.
--   upTo     the biggest group this ship flies with
--   plate    the hull: the disc, the rails, the covers          line     the scope's rings, cross and ticks; the scale
--   bracket  the corner brackets (`be` long, `bw` thick)        accent   the centre mark, the readout, the ship's name
--   fuel     your mana on the tape                              track    the tape's empty groove
RD.SHIPS = {
    { key = "fighter", name = "FIGHTER", upTo = 5,
      plate = { 0.035, 0.015, 0.060 }, line = { 0.82, 0.38, 1.00 }, bracket = { 0.97, 0.93, 1.00 }, be = 18, bw = 2,
      accent = { 1.00, 0.45, 0.92 }, fuel = { 0.88, 0.56, 1.00, 0.95 }, track = { 0.10, 0.04, 0.16, 0.9 } },
    { key = "gunship", name = "GUNSHIP", upTo = 10,
      plate = { 0.035, 0.025, 0.070 }, line = { 0.64, 0.52, 1.00 }, bracket = { 1.00, 1.00, 1.00 }, be = 22, bw = 2,
      accent = { 0.82, 0.64, 1.00 }, fuel = { 0.80, 0.72, 1.00, 0.95 }, track = { 0.08, 0.06, 0.17, 0.9 } },
    { key = "cruiser", name = "CRUISER", upTo = 20,
      plate = { 0.045, 0.045, 0.060 }, line = { 0.60, 0.64, 0.75 }, bracket = { 1.00, 1.00, 1.00 }, be = 28, bw = 2,
      accent = { 0.70, 0.44, 1.00 }, fuel = { 0.88, 0.90, 0.97, 0.95 }, track = { 0.10, 0.10, 0.14, 0.9 } },
    { key = "capital", name = "CAPITAL", upTo = 40,
      plate = { 0.060, 0.062, 0.072 }, line = { 0.84, 0.86, 0.91 }, bracket = { 1.00, 1.00, 1.00 }, be = 34, bw = 3,
      accent = { 0.64, 0.40, 0.96 }, fuel = { 0.96, 0.96, 0.99, 0.95 }, track = { 0.13, 0.13, 0.16, 0.9 } },
}
RD.SCOPE_DIM = 0.55                                -- the rings, cross and ticks: the ship's line at this strength
-- THE HUD TAPE (Arn, 8 Nov, a fighter HUD's speed tape: "the picture is an idea of how the guage should look not just a
-- line"): a spine with a tick every 10%, longer ticks and numbers at 0/25/50/75/100, and a BOXED READOUT riding at the top
-- of your fuel with your mana % in it - the client writes the number (SetFormattedText, UnitPowerPercent ScaleTo100; a
-- secret is handed on, never read) - pointing into the tape. The race (red above green, BINGO) stays, in the slim tape.
RD.HUD = { minor = 3, major = 6, label = 9, boxW = 24, boxH = 13 }
-- THE MANA COLUMN (Arn, 8 Nov: "put the mana tools close to the fuel tape and the water shield ... its essential for a
-- pilot to always click that button when it lights"): right beside the tape, top to bottom the stabilizer, Mana Tide,
-- the potion, the drink. Its x from the radar's left edge; clear of every pip, party and raid (the suite measures it).
RD.COLUMN_X = 12
RD.BINGO = 0.30                                    -- the boss this far ahead of your mana (of the tape) = BINGO
RD.MANA_COL = { 0.22, 1.00, 0.53, 0.95 }           -- your fuel: the scope's phosphor
RD.BOSS_COL = { 1.00, 0.23, 0.30, 0.85 }           -- the boss's health: the red your fuel has to cover
RD.HOT = { 1.00, 0.08, 0.58, 1 }                   -- BINGO: a hot magenta-red, pulsing
RD.CARET = { 1.00, 0.24, 0.92, 1 }                 -- the boss's level: the cockpit's magenta
-- THE REGEN TOOLS (Arn, 8 Nov: "light up the mana regen buttons, mana potions, mana tide"): always in their places down
-- the right edge, each lit by its own curve (RD.ToolCurve) once you are missing what it restores
RD.TIDE = "Mana Tide Totem"
RD.POTION = "Restore Mana"                         -- the use-spell of every mana potion (the drink's is "Drink")
RD.TOOL_GUESS = 0.50                               -- the amount unknown: light at half mana, and say it is a guess
-- THE RESERVE TANK (8 Nov 2026, Arn: "add mana spring to the rail and we light it up when everything else is on cooldown
-- as a scraping the barrel option. reserve reserve tank for a pilot"): Mana Spring, lit only once Mana Tide and the
-- potion are spent (cooling, or not here) and - in a fight, or with no drink - your mana is down to what it gives back.
-- What is spent is OUR OWN CLOCK of OUR OWN casts (UNIT_SPELLCAST_SUCCEEDED for you - plain), seeded out of a fight from
-- the client's cooldowns; nothing secret is read. A water totem of yours already down (the Spring, or Mana Tide for its
-- 12 s) keeps it dark: a second one would only replace it.
RD.FSR = { n = 5, w = 6, h = 3, gap = 2, spent = 0.2 }   -- the five second rule's segments (RD.PaintFSR)
RD.SPRING = "Mana Spring Totem"
RD.COOLS = { tide = 300, potion = 120, kick = 6, chaff = 15 }  -- seconds, when the client gives no cooldown to seed from
RD.cdLen = {}                                      -- kind -> a cooldown's length, learned from the client's plain answer
-- THE RIGHT RAIL: DEFENCE (9 Nov 2026, Arn: "an interrupt needs to target the specific unit, if it's on cool down, our
-- grounding totem lights up on the right rail it needs no target it just needs to know the flare missed - deploy chaff,
-- last resort catch all"). The FLARE is the interrupt on each bogey: it needs the caster, so it lives on the caster's
-- spoke. CHAFF is a TARGETLESS answer on its own rail right of the square, lit only while (a) an enemy on the radar is
-- casting, (b) the flare is spent - our own clock of your interrupt (a shaman's shocks share one cooldown, so any shock
-- spends it), or no interrupt at all - and (c) the chaff itself is ready. Plain booleans from our clock and from
-- FG.Casting (`type()` only); nothing secret is read. Only targetless spells belong here.
RD.CHAFF = { SHAMAN = "Grounding Totem", PRIEST = "Psychic Scream" }
RD.KICK_SHARED = { ["Earth Shock"] = { "Flame Shock", "Frost Shock" } }   -- casts that spend the same cooldown
RD.CHAFF_COL = { 1.00, 0.70, 0.25 }                -- amber: answer this now (a missile on its way)
-- THE PILOT'S KNOBS (Arn, 9 Nov: "these are our knobs can be turned on and off, some fights we need a specific totem all
-- the time so we can't afford for it to be lighting up ... we can turn off from the rail without having to go into the
-- setting"): a small switch on each rail tool's corner, a PLAIN button (never part of the secure cast button), so a click
-- works in a fight - it only changes what we light, and alpha is allowed in combat. Saved in `radar.off[kind]`.
RD.KNOB_PX = 9
RD.KNOB_ON = { 0.22, 1.00, 0.53, 0.35 }            -- lit when it needs you: a faint phosphor dot
RD.KNOB_OFF = { 1.00, 0.23, 0.30, 1 }              -- switched off: red, plain to see
RD.WATER = { tide = 12, spring = 300 }             -- how long each water totem stands
RD.readyAt = {}                                    -- kind -> GetTime() when it is ready again
RD.coolStart = {}                                  -- kind -> GetTime() its cooldown started (the cooling disc's start)
RD.waterUntil = 0
RD.TOOL_GAP = 3
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
RD.CROSSHAIRS = false                              -- Arn, 8 Nov: "no crosshairs" - taken off (the code stays)
RD.TOT_PAD = 22
RD.CONTACT = { 0.22, 1.00, 0.53, 0.75 }            -- their target, quiet: a phosphor triangle (red once it casts)
RD.CONTACT_SHOWN = false                           -- Arn, 8 Nov: a bogey shows only while it casts
RD.PLATE = { 0.02, 0.06, 0.04 }                    -- the stabilizer's backing plate, and the cover's colour over it
RD.SHIELD_OK = { 0.18, 0.62, 0.36 }                -- the cover while your shield is up: its icon, greyed, a dim phosphor
                                                   -- green (Arn, 8 Nov: "no water shield icon" - the first dark one read as nothing)
RD.SHIELD_LAST = { 255, 120, 0 }                   -- the last charge: an orange wash (r, g, b 0-255, a texture escape's)
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
    -- amber: the colour, see-through - the pulsing amber layer (RD.AmberCurve) is what shows there, so green holds still
    at(RD.RED + 0.0001, A, 0) at(amber, A, 0)
    at(amber + 0.0001, G) at(RD.GREEN, G)
    at(RD.GREEN + 0.0001, G, 0) at(1.00, G, 0)
    RD.curves[key] = c
    return c
end

--- The amber layer: solid amber between RD.RED and `amber`, nothing elsewhere (the client pulses that layer gently).
RD.amberCurves = {}
function RD.AmberCurve(amber)
    amber = math.max(RD.RED + 0.02, math.min(amber or RD.AMBER, RD.GREEN - 0.01))
    local key = math.floor(amber * 100 + 0.5)
    if RD.amberCurves[key] then return RD.amberCurves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local A = RD.COL.amber
    local function at(x, a) pcall(c.AddPoint, c, x, CreateColor(A[1], A[2], A[3], a)) end
    at(0.00, 0) at(RD.RED, 0)
    at(RD.RED + 0.0001, 1) at(amber, 1)
    at(amber + 0.0001, 0) at(1.00, 0)
    RD.amberCurves[key] = c
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

--- A REGEN TOOL'S CURVE (8 Nov 2026, Arn: "we change the color of our bar because the game tells us then at when it
--- tells us a certain shade we light up the button" - the heal pips' amber trick): cyan at and below `at` (your mana
--- fraction), nothing above. `at` = 1 - what the tool restores / your full mana, learned out of a fight - so the tool
--- lights the moment you are missing at least what it gives back. The client evaluates it on your mana; Lua never does.
RD.toolCurves = {}
function RD.ToolCurve(at)
    at = math.max(0.02, math.min(tonumber(at) or RD.TOOL_GUESS, 0.98))
    local key = math.floor(at * 100 + 0.5)
    if RD.toolCurves[key] then return RD.toolCurves[key], key / 100 end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local C, x = RD.COL.cyan, key / 100
    pcall(c.AddPoint, c, 0.00, CreateColor(C[1], C[2], C[3], 1))
    pcall(c.AddPoint, c, x, CreateColor(C[1], C[2], C[3], 1))
    pcall(c.AddPoint, c, x + 0.0001, CreateColor(C[1], C[2], C[3], 0))
    pcall(c.AddPoint, c, 1.00, CreateColor(C[1], C[2], C[3], 0))
    RD.toolCurves[key] = c
    return c, x
end

--- The old fuel curve (lit below RD.FUEL_LOW): a tool curve at that point.
function RD.FuelCurve() return (RD.ToolCurve(RD.FUEL_LOW)) end

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

--- THE POP UNDER THE MOUSE (8 Nov 2026, Arn: "need to also make the icons pop a little so i know im hovering over the
--- right icon" - the family rule, rows pop on hover). A bright white RING snaps round whatever clickable thing the mouse
--- is on - a heal pip, a cure pip, a bogey, a corner system - even an invisible one, so you see what a click would do.
--- A ring, not a box (Arn: no boxes). Its own plain frame on the button, only its ALPHA ever changes (in a fight too);
--- remade only when the pip's size changes. Hooked, never Set: a secure button keeps its own scripts.
--- SWITCHED OFF (8 Nov 2026, Arn: "it kills the immersion when i am moving the mouse over empty spaces and it shows where
--- something will light up ... might make them want to click that place"): built, never shown. RD.HALO_ON brings it back.
RD.HALO_ON = false
RD.HALO_PAD, RD.HALO_SEG = 6, 18
RD.HALO_COL = { 1, 1, 1, 0.95 }
function RD.Halo(owner, px)
    local h = owner.halo
    if h and h.px == px then return h end
    if not h then
        h = CreateFrame("Frame", nil, owner)
        h:SetPoint("CENTER", owner, "CENTER", 0, 0)
        h:SetSize(1, 1)
        h:SetFrameLevel(owner:GetFrameLevel() + 30)
        h:SetAlpha(0)
        owner.halo = h
        owner:HookScript("OnEnter", function() if RD.HALO_ON then h:SetAlpha(1) end end)
        owner:HookScript("OnLeave", function() h:SetAlpha(0) end)
    end
    for _, t in ipairs(h.ring or {}) do t:Hide() end
    h.ring = {}
    local r = px / 2 + RD.HALO_PAD
    local seg = 2 * math.pi * r / RD.HALO_SEG + 1
    for k = 0, RD.HALO_SEG - 1 do
        local a = (k + 0.5) * 2 * math.pi / RD.HALO_SEG
        local t = h:CreateTexture(nil, "OVERLAY")
        t:SetTexture(RD.WHITE)
        t:SetVertexColor(RD.HALO_COL[1], RD.HALO_COL[2], RD.HALO_COL[3], RD.HALO_COL[4])
        t:SetSize(seg, 2)
        t:SetPoint("CENTER", h, "CENTER", math.sin(a) * r, math.cos(a) * r)
        if t.SetRotation then t:SetRotation(-a) end
        h.ring[#h.ring + 1] = t
    end
    h.px = px
    return h
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
-- THE PETS (9 Nov 2026, Arn: "lets add pets small too to rader"): a small paw pip beside its owner, lit like a person (the
-- pet's health through the same curve), a left-click the radar heal. The CLIENT shows and hides it as the pet comes and
-- goes (RegisterUnitWatch), so a pet called mid-fight appears. A party: each pet `turn` clockwise of its owner on the
-- owner's ring; your own just below you (`selfB`, `selfR`). A raid: your own group's pets only, `inward` nearer the centre
-- on their owner's bearing (35 more would crowd the scope and cost a second grid). `px` / `raidPx` their sizes.
RD.PET = { px = 14, raidPx = 10, turn = math.rad(26), selfB = math.pi, selfR = 30, inward = 20 }
RD.PET_UNIT = { player = "pet" }                       -- the owner's token -> the pet's (party/raid by pattern, RD.PetOf)
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
    -- A DARK DISC WITH A SOFT EDGE (Arn, 9 Nov: "we dont use the corners of the radar what about if we give it a dark
    -- background instead of see through so things pop more like the rail. and we apply the edge fade instead on the edges
    -- like the screen shot" - a map that fades into the world). The see-through square is gone: the rail's own plate,
    -- solid out past the outer ring, fading to nothing (Art\scopefade.tga), the corners left clear. On the radar's OWN
    -- lowest layer, not the scope's: the fade reaches past the square, and the rails beside it must draw over it.
    -- Sized with the scope (RD.Arm), so a raid's bigger scope gets a bigger disc.
    local fade = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    fade:SetTexture(RD.ART .. "scopefade")
    fade:SetVertexColor(RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1)
    fade:SetSize(RD.FADE_PX, RD.FADE_PX)
    fade:SetPoint("CENTER", s, "CENTER", 0, 0)
    RD.fade = fade
    -- every line kept, so a ship can repaint them (RD.ApplyShip): the rings, cross and ticks; the brackets; the centre
    RD.scopeLines, RD.brackets = {}, {}
    local function keep(l) RD.scopeLines[#RD.scopeLines + 1] = l return l end
    for _, r in ipairs(RD.RINGS) do
        for k = 1, RD.RING_SEG do
            local a0, a1 = (k - 1) * 2 * math.pi / RD.RING_SEG, k * 2 * math.pi / RD.RING_SEG
            keep(line(s, "BORDER", math.sin(a0) * r, math.cos(a0) * r, math.sin(a1) * r, math.cos(a1) * r, g, 1))
        end
    end
    local h = RD.SIZE / 2 - 6
    keep(line(s, "BORDER", -h, 0, h, 0, g, 1))
    keep(line(s, "BORDER", 0, -h, 0, h, g, 1))
    for k = 0, 35 do
        local a = k * math.pi / 18
        local r2 = (k % 3 == 0) and 134 or 138
        keep(line(s, "BORDER", math.sin(a) * 142, math.cos(a) * 142, math.sin(a) * r2, math.cos(a) * r2, g, 1))
    end
    -- the square's corner brackets: two arms a corner, `sx`/`sy` kept so a ship can lengthen them (RD.ShapeBrackets)
    local b, e = RD.SIZE / 2 - 4, 22
    local bc = { RD.PHOS[1] * 0.6, RD.PHOS[2] * 0.6, RD.PHOS[3] * 0.6, 1 }
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            local a1 = line(s, "BORDER", sx * b, sy * b, sx * (b - e), sy * b, bc, 2)
            local a2 = line(s, "BORDER", sx * b, sy * b, sx * b, sy * (b - e), bc, 2)
            a1.sx, a1.sy, a1.across = sx, sy, true
            a2.sx, a2.sy, a2.across = sx, sy, false
            RD.brackets[#RD.brackets + 1] = a1
            RD.brackets[#RD.brackets + 1] = a2
        end
    end
    -- you, in the middle: your role icon alone. The chevron that drew over it is gone (Arn, 10 Nov, on a DPS: "get rid
    -- of the chevron, and keep the role icon" - as a healer the healing icon hid it). The icon itself: RD.PaintMe
    RD.meLines, RD.meRole = {}, nil
    -- the dim places of every slot live on their own layer, unscaled, and go with the scope (RD.PaintQuiet)
    local dims = CreateFrame("Frame", nil, f)
    dims:SetAllPoints(f)
    RD.dims = dims
    return s
end

--- YOU, IN THE MIDDLE, ALWAYS (Arn, 10 Nov, after the chevron went: "my icon is gone"). Your heal pip lights only below
--- 90%, so at full health the middle was empty. Your role's sign now stays on the scope in the ship's accent, dimmed
--- (RD.ME_ALPHA); your heal pip lights over it, and it goes dark with the scope in a fight (RD.PaintQuiet). Rebuilt only
--- when your role changes.
RD.ME_ALPHA = 0.6
function RD.PaintMe()
    local s = RD.scope
    if not s then return end
    local role = RD.Role("player")
    if RD.meRole ~= role then
        for _, t in ipairs(RD.meLines or {}) do t:Hide() end
        RD.meLines = glyph(s, role, RD.SELF.ph * RD.GLYPH)
        RD.meRole = role
    end
    local A = (RD.ship and RD.ship.accent) or RD.PHOS
    for _, t in ipairs(RD.meLines) do t:SetVertexColor(A[1], A[2], A[3], RD.ME_ALPHA) end
end

--- One spoke's pieces: the heal pip (secure), its cure pips (client markers + secure boxes), its bogey, its alert
--- arcs and its dim places. Made once (a pool of 40 at most) and PLACED by RD.PlaceSpoke, out of a fight.
local function buildSpoke(f, i)
    local sp = { i = i }
    -- HEAL: a secure unit button; its face is ours
    local b = CreateFrame("Button", "BiSHealingRadarHeal" .. i, f, "SecureUnitButtonTemplate")
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    -- EVERY LIT PIP PULSES (Arn, 8 Nov: "make the heal pips pulse too"): the face sits in a wrapper with a gentle pulse
    -- (green: hurt, can wait); amber's own layer a touch stronger; red's own layer hard. The pulse multiplies the
    -- curve's colour, so a pip the curve hides stays hidden.
    b.beat = CreateFrame("Frame", nil, b)
    b.beat:SetAllPoints(b)
    sp.beat = RD.Pulse(b.beat, RD.PULSE_SOFT)
    b.face = CreateFrame("Frame", nil, b.beat)
    b.face:SetAllPoints(b)
    -- NO BOX (Arn, 8 Nov: "the box outlines are not needed"): the pip is its role glyph alone, in the game's colour.
    -- Red has its own glyph on its own layer, coloured by the red curve, on its own hard pulse.
    b.redFace = CreateFrame("Frame", nil, b)
    b.redFace:SetAllPoints(b)
    sp.pulse = RD.Pulse(b.redFace, RD.PULSE_HARD)            -- a size pulse: the red curve alone decides it is seen
    -- AMBER PULSES A TOUCH STRONGER (Arn, 8 Nov: whack-a-mole - "it lights up and pulses a little"): its own glyph layer,
    -- lit only between the red and amber points by its own curve (RD.AmberCurve), on its own pulse. The main face goes
    -- see-through over amber, so only the amber layer's beat shows there.
    b.amberFace = CreateFrame("Frame", nil, b)
    b.amberFace:SetAllPoints(b)
    sp.amberPulse = RD.Pulse(b.amberFace, RD.PULSE_MID)
    -- the GCD's sweep, its swipe dark only while the pip is lit (RD.SwipeCurve on their health, RD.PaintHeal)
    sp.cd = RD.Sweep(b.face)
    b:HookScript("OnEnter", function() RD.over = sp end)
    b:HookScript("OnLeave", function() if RD.over == sp then RD.over = nil end end)
    sp.heal = b
    -- BOGEY: their target, a red triangle only while it casts; a click is your interrupt (enemies only)
    local k = CreateFrame("Button", "BiSHealingRadarBogey" .. i, f, "SecureActionButtonTemplate")
    if k.RegisterForClicks then k:RegisterForClicks("AnyDown") end
    -- AN INCOMING MISSILE PULSES HARD (Arn, 8 Nov: "make the bogeys pulse red when they show up"): the red heal pip's
    -- pulse, on a wrapper round the face - the face is alpha 0 unless a cast is on, so the pulse shows only then
    k.beat = CreateFrame("Frame", nil, k)
    k.beat:SetAllPoints(k)
    k.pulse = RD.Pulse(k.beat, RD.PULSE_HARD)
    k.face = CreateFrame("Frame", nil, k.beat)
    k.face:SetAllPoints(k)
    k.face:SetAlpha(0)
    -- YOUR INTERRUPT'S COOLDOWN (Arn, 8 Nov: "cooldown sweep on interrupt icon"): the grid's own sweep (FG.PvPCooldown's
    -- road) - the client runs it from the duration object it hands us for our own spell, no number read. On the face, so
    -- it is seen only while the bogey is (a cast to answer); RD.KickCooldown feeds it.
    local okCd, cd = pcall(CreateFrame, "Cooldown", nil, k.face, "CooldownFrameTemplate")
    if okCd and cd then
        cd:SetAllPoints(k.face)
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        k.cd = cd
    end
    sp.bogey = k
    -- THE CLICK'S WORD, LIKE THE GRID (Arn, 9 Nov: "flash LOS under the teammate im clicking like bis healing" ... "range
    -- for out of range ... only when i click them"): LOS or RANGE in the grid's red and thick outline (FG.Flash), just
    -- UNDER the pip, fading by itself in FG.FLASH_FOR (RD.HeardError). The red rim dashes for range are gone. A plain
    -- frame on the radar anchored to the pip, built here out of a fight; in one only its text, alpha and fade change.
    local los = CreateFrame("Frame", nil, f)
    los:SetPoint("TOP", b, "BOTTOM", 0, -1)
    los:SetSize(40, 16)
    if los.SetFrameLevel and b.GetFrameLevel then
        local lvl = b:GetFrameLevel()
        if type(lvl) == "number" then los:SetFrameLevel(lvl + 25) end
    end
    los.word = los:CreateFontString(nil, "OVERLAY")
    if los.word.SetFont then los.word:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE") end
    los.word:SetPoint("CENTER", los, "CENTER", 0, 0)
    los.word:SetText("")                  -- empty until a click fails: no words stand on the scope
    local red = (NS.FG and NS.FG.FLASH_RED) or { 1.00, 0.25, 0.30 }
    los.word:SetTextColor(red[1], red[2], red[3], 1)
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
            a:SetFromAlpha(1) a:SetToAlpha(0) a:SetDuration((NS.FG and NS.FG.FLASH_FOR) or 1.2)
            if g.SetToFinalAlpha then g:SetToFinalAlpha(true) end
            sp.losFade = g
        end
    end
    sp.los = los
    sp.cures = {}
    -- THE PET: a small secure pip of its own, the client's unit watch showing it only while the pet is there
    local p = CreateFrame("Button", "BiSHealingRadarPet" .. i, f, "SecureUnitButtonTemplate")
    if p.RegisterForClicks then p:RegisterForClicks("AnyDown") end
    p.beat = CreateFrame("Frame", nil, p)
    p.beat:SetAllPoints(p)
    p.pulse = RD.Pulse(p.beat, RD.PULSE_SOFT)
    p.face = CreateFrame("Frame", nil, p.beat)
    p.face:SetAllPoints(p)
    p:Hide()
    sp.pet = p
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
    RD.Halo(b, s.ph)
    if sp.glyphPx ~= s.ph then
        for _, t in ipairs(sp.glyph or {}) do t:Hide() end
        sp.glyph, sp.role, sp.glyphPx = nil, nil, s.ph
    end
    local k = sp.bogey
    if s.rb then
        k:SetSize(s.pb, s.pb)
        RD.Halo(k, s.pb)
        k:ClearAllPoints()
        k:SetPoint("CENTER", f, "CENTER", RD.Point(s, s.rb))
        if not k.lines or k.linesPx ~= s.pb then
            for _, l in ipairs(k.lines or {}) do l:Hide() end
            local h = s.pb * 0.42
            local rc = RD.COL.bogey
            local hid = { rc[1], rc[2], rc[3], 0 }               -- born see-through: only a cast makes it solid
            k.lines = { line(k.face, "OVERLAY", 0, h, h, -h * 0.8, hid, 2), line(k.face, "OVERLAY", h, -h * 0.8, -h, -h * 0.8, hid, 2),
                        line(k.face, "OVERLAY", -h, -h * 0.8, 0, h, hid, 2) }
            k.linesPx = s.pb
        end
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

--[[ WHACK-A-MOLE (8 Nov 2026, Arn: "something lights up we click, it lights up and pulses a little it grabs more of our
  attention"). EVERYTHING THAT LIGHTS ALSO PULSES: a client AnimationGroup, alpha BOUNCE, looping, playing always - no
  OnUpdate, nothing read. It runs on a WRAPPER frame whose alpha we never set (`beat`), with the lit face inside it, so
  the pulse only ever multiplies what the game's curve or boolean decided: an invisible pip stays invisible.
  Gentle (RD.PULSE_SOFT) for a tool, a cure, amber; hard (RD.PULSE_HARD) for red and for a bogey - an incoming missile. ]]
-- A PULSE OF SIZE, NOT OF ALPHA (8 Nov 2026, Arn's screenshots: an amber cross at the centre at 98% health, "center
-- cross still pulsing", and bogeys showing with nothing casting). In the client an ALPHA animation on a frame drove that
-- frame's alpha itself - what we hid by alpha under it came back. A SCALE bounce never touches whether a thing is seen:
-- an invisible pip grows invisibly, a lit one breathes. { grow to, seconds }.
RD.SIZE_PULSE = false                              -- the size pulse is OFF: it blew a pip up to the whole screen
RD.PULSE_SOFT = { 1.08, 0.5 }                      -- grow to, seconds
RD.PULSE_MID = { 1.13, 0.45 }                      -- amber: a touch stronger than soft
RD.PULSE_HARD = { 1.20, 0.35 }
function RD.Pulse(frame, kind)
    if not (frame and frame.CreateAnimationGroup) then return nil end
    local p = kind or RD.PULSE_SOFT
    local ok, g = pcall(frame.CreateAnimationGroup, frame)
    if not (ok and g) then return nil end
    local a = g:CreateAnimation("Scale")
    if a.SetScaleFrom and a.SetScaleTo then
        a:SetScaleFrom(1, 1)
        a:SetScaleTo(p[1], p[1])
    elseif a.SetScale then
        a:SetScale(p[1], p[1])
    end
    if a.SetOrigin then pcall(a.SetOrigin, a, "CENTER", 0, 0) end
    a:SetDuration(p[2])
    g:SetLooping("BOUNCE")
    -- OFF (8 Nov 2026, Arn's screenshot: in a fight his own green heal pip filled the whole screen - the client's SCALE
    -- bounce grew it without bound). Built, never played, until a probe says how this client runs a Scale animation.
    if RD.SIZE_PULSE then g:Play() end
    return g
end

--- The ALPHA pulse, kept only where what is seen is decided by SHAPE, not by alpha: the BINGO band (a clipped window)
--- and the stabilizer's last-charge wash (the client's own text). Never under anything hidden by alpha.
RD.FADE_SOFT, RD.FADE_HARD = { 0.55, 0.5 }, { 0.35, 0.35 }
function RD.PulseAlpha(frame, kind)
    if not (frame and frame.CreateAnimationGroup) then return nil end
    local p = kind or RD.FADE_SOFT
    local ok, g = pcall(frame.CreateAnimationGroup, frame)
    if not (ok and g) then return nil end
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1) a:SetToAlpha(p[1]) a:SetDuration(p[2])
    g:SetLooping("BOUNCE")
    g:Play()
    return g
end

--[[ THE GLOBAL COOLDOWN'S SWEEP ON EVERYTHING LIT (8 Nov 2026, Arn: "would be kinda cool to also put the global cooldown
  sweep on everything that lit"). The bogey's own kind of sweep (no bling, no numbers) on each clickable face, all fed
  ONE duration object per SPELL_UPDATE_COOLDOWN (RD.Sweeps): the GCD's (spell 61304), or the radar heal's own cooldown
  when the client will not answer for it. Mana Tide and the potion show their own cooldown instead. A face that is lit
  by its COLOUR (a heal pip, a tool) has its swipe coloured by a curve too (RD.SwipeCurve), so it is dark only while the
  face is lit and see-through otherwise; a face lit by its alpha (rations, a cure marker) needs nothing more. ]]
RD.GCD = 61304
RD.SWIPE = { 0, 0, 0, 0.6 }
RD.sweeps = {}                                     -- every GCD sweep, fed in one loop
function RD.Sweep(parent, own)
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, parent, "CooldownFrameTemplate")
    if not (ok and cd) then return nil end
    cd:SetAllPoints(parent)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    -- NO EDGE (Arn, 8 Nov: "cool down sweep show up when pips are not there" - the bright edge line is not coloured by
    -- the pip's curve, so it ran over unlit and empty spots). Only the swipe, which the curve makes see-through there.
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if not own then RD.sweeps[#RD.sweeps + 1] = cd end
    return cd
end

--[[ COOLING, SEEN WHEN DARK (8 Nov 2026, Arn, after using Mana Tide: "we should put it there but with a cooldown sweep
  right now i think its ready to go again"). Mana Tide and the potion carry their own cooldown on the BUTTON, not on the
  face - so it shows while the face is dark - as a dim cyan disc (Art\disc.tga) the client eats away as it comes ready:
  there = still cooling, gone = ready. Under the face (a lower level), so a lit sign draws over it. A Cooldown frame
  only draws while it runs, so nothing of ours decides "cooling" - the client's own object, secret or not. ]]
RD.WAIT_SWIPE = { 0.30, 0.90, 1.00, 0.35 }
function RD.WaitSweep(b)
    local cd = RD.Sweep(b, true)
    if not cd then return nil end
    cd.wait = true
    if cd.SetFrameLevel then cd:SetFrameLevel(b:GetFrameLevel()) end    -- under the face's wrapper (b + 1)
    if cd.SetSwipeTexture then pcall(cd.SetSwipeTexture, cd, RD.ART .. "disc") end
    local W = RD.WAIT_SWIPE
    if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, W[1], W[2], W[3], W[4]) end
    return cd
end

--- A sweep back in the loop (its marker switched on again); never twice.
function RD.Resweep(cd)
    if not cd then return false end
    for _, x in ipairs(RD.sweeps) do if x == cd then return false end end
    RD.sweeps[#RD.sweeps + 1] = cd
    return true
end

--- A sweep whose marker was thrown away (a cure re-placed): out of the list, so the loop stays the size of what is seen.
function RD.Unsweep(cd)
    if not cd then return false end
    for i = #RD.sweeps, 1, -1 do if RD.sweeps[i] == cd then table.remove(RD.sweeps, i) return true end end
    return false
end

--- The swipe's shade by a fraction (health or mana): dark at and below `at`, nothing above.
RD.swipeCurves = {}
function RD.SwipeCurve(at)
    local key = math.floor((tonumber(at) or 1) * 100 + 0.5)
    if RD.swipeCurves[key] then return RD.swipeCurves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then pcall(c.SetType, c, Enum.LuaCurveType.Linear) end
    local S, x = RD.SWIPE, key / 100
    pcall(c.AddPoint, c, 0.00, CreateColor(S[1], S[2], S[3], S[4]))
    pcall(c.AddPoint, c, x, CreateColor(S[1], S[2], S[3], S[4]))
    pcall(c.AddPoint, c, x + 0.0001, CreateColor(S[1], S[2], S[3], 0))
    pcall(c.AddPoint, c, 1.00, CreateColor(S[1], S[2], S[3], 0))
    RD.swipeCurves[key] = c
    return c
end

--- A sweep's swipe in the colour the client worked out; no colour back = no swipe (never a dark disc on nothing).
local function swipeTo(cd, col)
    if not cd then return false end
    if type(col) == "table" and col.GetRGBA and cd.SetSwipeColor
       and pcall(function() cd:SetSwipeColor(col:GetRGBA()) end) then return true end
    if cd.SetSwipeColor then pcall(cd.SetSwipeColor, cd, 0, 0, 0, 0) end
    return false
end

--- A system pip in the column: a secure button (for its click) with our own face, inside its pulse wrapper.
local function buildSystem(f, name, point, x, y, rel)
    local b = CreateFrame("Button", "BiSHealingRadar" .. name, f, "SecureActionButtonTemplate")
    b:SetSize(RD.SYS_PX, RD.SYS_PX)
    b:SetPoint(point, rel or f, point, x, y)
    b.rail = rel
    if b.RegisterForClicks then b:RegisterForClicks("AnyDown") end
    b.beat = CreateFrame("Frame", nil, b)
    b.beat:SetAllPoints(b)
    b.face = CreateFrame("Frame", nil, b.beat)
    b.face:SetAllPoints(b)
    b.ring = {}
    local r = RD.SYS_PX / 2 - 1
    for k = 1, 16 do
        local a0, a1 = (k - 1) * math.pi / 8, k * math.pi / 8
        b.ring[k] = line(b.face, "ARTWORK", math.sin(a0) * r, math.cos(a0) * r, math.sin(a1) * r, math.cos(a1) * r, RD.COL.cyan, 2)
    end
    b.icon = b.face:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER") b.icon:SetSize(RD.SYS_PX - 10, RD.SYS_PX - 10)
    RD.Halo(b, RD.SYS_PX)
    -- what it is, under the mouse only (no words on the scope): b.tip = { title, line }
    b:HookScript("OnEnter", function(self)
        local tip = self.tip
        if not (tip and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tip[1])
        if tip[2] then GameTooltip:AddLine(tip[2], 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

--[[ THE FUEL GAUGE (8 Nov 2026). Arn: "I want to end the boss fight at 0% mana ... if its at 50% I should be at 50% mana
  ... if its at 70% and im at 20% thats a warning". THE GPU COMPARES, LUA NEVER DOES. Bottom to top, all on the same tape:
    boss      a StatusBar of the boss's health (boss1, else a hostile target), red, 0..max handed untouched
    mana      your mana over it, the same size and place, green: where you are behind, red shows above your fuel
    ticks     25 / 50 / 75, phosphor
    caret     a magenta mark on the boss bar's FILL TOP (the heal-absorb anchoring), drawn over the mana
    BINGO     a ruler: your mana again, in a frame lifted 30% of the tape and clipped to it (never seen). A window
              whose FLOOR is anchored to that ruler's fill top - so it starts at mana + 30% - clips a copy of the boss
              bar in a pulsing hot magenta and a hot flag under the caret. Boss more than 30% ahead of you: the hot
              band shows from mana + 30% up to the boss, the flag with it. Not that far behind: the window is above the
              boss's fill, and nothing shows. Exact to the pixel: two fill edges and a fixed offset, no number read.
  The boss layer's alpha says whether there is a boss at all (a secret "hostile?" goes to SetAlphaFromBoolean).
  SIDEWAYS SINCE 9 NOV (Arn: "put it on top side ways that way only one rail per side"): the tape runs left to right
  along the top rail, so "above" in the words here is "to the right of" on the screen - the caret on the boss fill's
  RIGHT end, the ruler lifted 30% to the right, the BINGO window's floor its LEFT edge. ]]
local function fuelBar(parent, col, lvl)
    local s = CreateFrame("StatusBar", nil, parent)
    s:SetStatusBarTexture(RD.WHITE)
    s:SetStatusBarColor(col[1], col[2], col[3], col[4] or 1)
    if s.SetOrientation then s:SetOrientation("HORIZONTAL") end        -- fills from the left
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    s:SetFrameLevel(lvl)
    return s
end

local function buildGauge(f)
    local G = RD.GAUGE
    local g = CreateFrame("Frame", nil, f)
    RD.gauge = g
    g:SetFrameLevel(f:GetFrameLevel() + 2)
    local L = g:GetFrameLevel()
    g.track = g:CreateTexture(nil, "BACKGROUND")
    g.track:SetAllPoints(g)
    g.track:SetColorTexture(0.02, 0.09, 0.05, 0.9)
    -- the boss layer: everything that is the boss's, so one alpha says "is there one"
    g.bossLayer = CreateFrame("Frame", nil, g)
    g.bossLayer:SetAllPoints(g)
    g.bossLayer:SetFrameLevel(L + 1)
    g.bossLayer:SetAlpha(0)
    g.boss = fuelBar(g.bossLayer, RD.BOSS_COL, L + 1)
    g.boss:SetAllPoints(g)
    g.mana = fuelBar(g, RD.MANA_COL, L + 2)
    g.mana:SetAllPoints(g)
    g.tickFrame = CreateFrame("Frame", nil, g)
    g.tickFrame:SetAllPoints(g)
    g.tickFrame:SetFrameLevel(L + 3)
    RD.BuildHUD(g, L)
    g.ticks = {}
    for q = 1, 3 do g.ticks[q] = line(g.tickFrame, "OVERLAY", 0, 0, 1, 0, RD.PHOS, 1) end
    -- the boss's level, over your mana
    g.caretFrame = CreateFrame("Frame", nil, g.bossLayer)
    g.caretFrame:SetAllPoints(g)
    g.caretFrame:SetFrameLevel(L + 4)
    g.caret = tex(g.caretFrame, "OVERLAY", RD.CARET)
    g.caret:SetSize(3, G.w + 3)
    g.caret:SetPoint("BOTTOM", g.boss:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    -- BINGO: the lifted ruler (clipped to the tape, its colour see-through - it is only an edge)
    g.rulerClip = CreateFrame("Frame", nil, g)
    g.rulerClip:SetAllPoints(g)
    g.rulerClip:SetClipsChildren(true)
    g.rulerClip:SetFrameLevel(L + 1)
    g.lift = CreateFrame("Frame", nil, g.rulerClip)
    g.ruler = fuelBar(g.lift, { 0, 0, 0, 0 }, L + 1)
    g.ruler:SetAllPoints(g.lift)
    -- the window: floor on the ruler's fill end, roof past the tape's end (mana + 30% can reach 130%), tall enough for
    -- the flag
    g.hotClip = CreateFrame("Frame", nil, g.bossLayer)
    g.hotClip:SetClipsChildren(true)
    g.hotClip:SetFrameLevel(L + 5)
    g.hotClip:SetPoint("BOTTOMLEFT", g.ruler:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    g.hot = fuelBar(g.hotClip, RD.HOT, L + 5)
    g.hot:SetAllPoints(g)
    g.flagFrame = CreateFrame("Frame", nil, g.hotClip)
    g.flagFrame:SetAllPoints(g)
    g.flagFrame:SetFrameLevel(L + 6)
    -- the BINGO flag: a hot bar just behind the magenta caret, as tall - shown only inside the window
    g.flag = tex(g.flagFrame, "OVERLAY", RD.HOT)
    g.flag:SetSize(3, G.w + 3)
    g.flag:SetPoint("BOTTOMRIGHT", g.boss:GetStatusBarTexture(), "BOTTOMRIGHT", -3, 0)
    -- BINGO pulses hard, always playing: it is seen only while the window holds some of the boss's fill
    g.pulse = RD.PulseAlpha(g.hotClip, RD.FADE_HARD)
    -- REGEN, "generating fuel": a cyan inflow chevron at the foot (RD.PaintRegen)
    g.chev = CreateFrame("Frame", nil, f)
    g.chev:SetSize(12, 10)
    g.chev:SetAlpha(0)
    local C = RD.COL.cyan
    g.chevLines = { line(g.chev, "OVERLAY", -5, -1, 0, 4, C, 2), line(g.chev, "OVERLAY", 0, 4, 5, -1, C, 2),
                    line(g.chev, "OVERLAY", -5, -5, 0, 0, C, 2), line(g.chev, "OVERLAY", 0, 0, 5, -5, C, 2) }
    -- the REGEN READOUT at the gauge's foot (Arn, 8 Nov: "bottom of the gauge we should put our mana regen % - 100% out
    -- of combat, in combat reads our talents like the bis healing header"): Regen.lua's own words. CENTRED in the room
    -- kept at the tape's right end (Arn: "more centered in the empty space"), the chevron on its right.
    g.regen = f:CreateFontString(nil, "OVERLAY")
    g.regen:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "")
    g.regen:SetTextColor(C[1], C[2], C[3])
    g.regen:SetPoint("CENTER", RD.gaugeRail or f, "RIGHT", -math.floor(G.right / 2) - 4, 4)   -- the pair centred
    g.regen:SetText("100%")
    g.chev:SetPoint("LEFT", g.regen, "RIGHT", 3, 0)
    -- THE FIVE SECOND RULE, COUNTED DOWN (Arn, 8 Nov: "somewhere on there the 5 second casting rule for 100% mana regen
    -- ... so they know if i wait a little bit i can get full mana regen"): five segments under the readout, one per
    -- second left, draining as you hold your casts; all gone = 100% again. Shown in a fight, inside the rule only.
    g.fsr = CreateFrame("Frame", nil, f)
    g.fsr:SetSize(RD.FSR.n * RD.FSR.w + (RD.FSR.n - 1) * RD.FSR.gap, RD.FSR.h)
    g.fsr:SetPoint("TOP", g.regen, "BOTTOM", 0, -2)
    g.fsr:SetAlpha(0)
    g.fsrSegs = {}
    for k = 1, RD.FSR.n do
        local t = tex(g.fsr, "OVERLAY", C)
        t:SetSize(RD.FSR.w, RD.FSR.h)
        t:SetPoint("LEFT", g.fsr, "LEFT", (k - 1) * (RD.FSR.w + RD.FSR.gap), 0)
        g.fsrSegs[k] = t
    end
    -- what it is, under the mouse only; the radar's own drag goes on through it. THE WHOLE RAIL answers (Arn, 8 Nov: "the
    -- tool tip is inconsistent only certain parts of the gauge light it up" - only the 7px tape did): the tape, the
    -- scale, the readout and the ramjet at the foot all show the same card, anchored to the rail
    local function tipOn(w)
        w:EnableMouse(true)
        w:RegisterForDrag("LeftButton")
        w:SetScript("OnDragStart", function() local s = f:GetScript("OnDragStart") if s then s(f) end end)
        w:SetScript("OnDragStop", function() endDrag(f) end)
        w:SetScript("OnEnter", function()
            if not GameTooltip then return end
            GameTooltip:SetOwner(RD.gaugeRail or g, "ANCHOR_RIGHT")
            GameTooltip:AddLine("FUEL")
            for _, l in ipairs(RD.FuelTip()) do GameTooltip:AddLine(l, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        w:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    tipOn(g)
    if RD.gaugeRail then tipOn(RD.gaugeRail) end
    -- THE PLACARD at the tape's left end, a pilot's seat plate: your ROLE (Arn, 9 Nov: "lets add our role here Healer,
    -- DPS, Tank" - RD.PaintRole), the ship you are flying (RD.ApplyShip), then the word FUEL (Arn: "lets not do rpm" - a
    -- bar across the top reads as an engine gauge without it). The rail's only words; the scope has none.
    local P = RD.gaugeRail or f
    local function word(text)
        local fs = P:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "")
        fs:SetText(text)
        return fs
    end
    -- each line at its own fixed spot, so an empty role (the game said none) leaves the ship and FUEL where they are
    g.role = word("")
    g.role:SetPoint("TOPLEFT", P, "TOPLEFT", 6, -5)
    g.role:SetTextColor(1, 1, 1)
    g.ship = word(RD.SHIPS[1].name)
    g.ship:SetPoint("TOPLEFT", P, "TOPLEFT", 6, -17)
    g.fuelWord = word("FUEL")
    g.fuelWord:SetPoint("TOPLEFT", P, "TOPLEFT", 6, -29)
    RD.SizeGauge(RD.SIZE)
    return g
end

--- The rails, outside the square: the tool rail on its left and the defence rail on its right, the radar's full height;
--- the gauge's rail across the top of both the tool rail and the square. Their own frames under the radar's level so the
--- tape and the tools draw over them; the radar's clamp grows to keep them on the screen.
local function rail(f, w)
    local r = CreateFrame("Frame", nil, f)
    if w then r:SetWidth(w) end
    r:SetFrameLevel(math.max(0, f:GetFrameLevel()))
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints(r)
    r.bg:SetTexture(RD.WHITE)
    r.bg:SetVertexColor(RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1)
    return r
end
function RD.BuildRails(f)
    if RD.toolRail then return RD.toolRail, RD.gaugeRail end
    local gap = RD.RAIL_GAP
    local t = rail(f, RD.TOOL_RAIL_W)
    t:SetPoint("TOPRIGHT", f, "TOPLEFT", -gap, 0)
    t:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", -gap, 0)
    -- THE GAUGE'S RAIL ON TOP (Arn, 9 Nov: "put it on top side ways that way only one rail per side"): from the tool
    -- rail's left edge to the square's right edge; its width follows the square (RD.SizeGauge)
    local g = rail(f)
    g:SetHeight(RD.GAUGE_RAIL_H)
    g:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 0, gap)
    g:SetWidth(RD.SIZE + RD.TOOL_RAIL_W + gap)
    -- THE DEFENCE RAIL on the right (CHAFF): shown only when it holds something (RD.ArmTools, out of a fight)
    local d = rail(f, RD.TOOL_RAIL_W)
    d:SetPoint("TOPLEFT", f, "TOPRIGHT", gap, 0)
    d:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", gap, 0)
    d:Hide()
    RD.toolRail, RD.gaugeRail, RD.defRail = t, g, d
    -- THE BLACK BOX'S RAIL along the bottom (BlackBox.lua, 10 Nov: "Build the bottom raid with the squawk box thing")
    if NS.BB and NS.BB.Build then RD.bbRail = NS.BB.Build(f, t, rail) end
    RD.ClampRails()
    return t, g
end

--- The radar's clamp: the tool rail, the gauge's rail and the black box's always, the right one while it shows.
function RD.ClampRails()
    local f = RD.frame
    if not (f and f.SetClampRectInsets) then return end
    local gap = RD.RAIL_GAP
    local right = (RD.defRail and RD.defRail:IsShown()) and (RD.TOOL_RAIL_W + gap) or 0
    local bottom = (RD.bbRail and NS.BB) and -(NS.BB.RAIL_H + gap) or 0
    pcall(f.SetClampRectInsets, f, -(RD.TOOL_RAIL_W + gap), right, RD.GAUGE_RAIL_H + gap, bottom)
end

--- The HUD scale UNDER the tape: the spine, the ticks hanging from it, the numbers under them, and the readout box
--- riding your fuel's end above the tape, pointing down into it.
function RD.BuildHUD(g, L)
    local H = RD.HUD
    local hud = CreateFrame("Frame", nil, g)
    hud:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -1)
    hud:SetPoint("TOPRIGHT", g, "BOTTOMRIGHT", 0, -1)
    hud:SetHeight(RD.GAUGE.base - 2)
    hud:SetFrameLevel(L + 3)
    g.hud = hud
    hud.spine = tex(hud, "ARTWORK", RD.PHOS)
    hud.spine:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, 0)
    hud.spine:SetPoint("TOPRIGHT", hud, "TOPRIGHT", 0, 0)
    hud.spine:SetHeight(1)
    hud.ticks, hud.labels = {}, {}
    for k = 0, 10 do
        local t = tex(hud, "ARTWORK", RD.PHOS)
        t:SetSize(1, (k % 5 == 0 or k == 10) and H.major or H.minor)
        hud.ticks[k] = t
    end
    for q = 0, 4 do
        local fs = hud:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, H.label, "")
        fs:SetTextColor(RD.PHOS[1], RD.PHOS[2], RD.PHOS[3])
        fs:SetJustifyH("CENTER")
        fs:SetText(tostring(q * 25))
        hud.labels[q] = fs
    end
    -- the readout: a box riding the mana fill's end above the tape, the number inside, a pointer down into the tape
    local box = CreateFrame("Frame", nil, g)
    box:SetSize(H.boxW, H.boxH)
    box:SetPoint("BOTTOM", g.mana:GetStatusBarTexture(), "TOPRIGHT", 0, 3)
    box:SetFrameLevel(L + 6)
    box.fill = tex(box, "BACKGROUND", { RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1 })
    box.fill:SetAllPoints(box)
    box.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
                         { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
        local t = tex(box, "BORDER", RD.PHOS)
        t:SetPoint(e[1]) t:SetPoint(e[2])
        if e[3] then t:SetHeight(1) else t:SetWidth(1) end
        box.edges[#box.edges + 1] = t
    end
    box.tip1 = line(box, "OVERLAY", -3, -H.boxH / 2, 0, -H.boxH / 2 - 3, RD.PHOS, 1)
    box.tip2 = line(box, "OVERLAY", 3, -H.boxH / 2, 0, -H.boxH / 2 - 3, RD.PHOS, 1)
    box.num = box:CreateFontString(nil, "OVERLAY")
    box.num:SetFont(STANDARD_TEXT_FONT, 10, "")
    box.num:SetTextColor(RD.PHOS[1], RD.PHOS[2], RD.PHOS[3])
    box.num:SetPoint("CENTER", box, "CENTER", 0, 0)
    g.readout = box
    return hud
end

--- The HUD scale's places for a tape `w` long: a tick every 10%, numbers every 25%.
function RD.SizeHUD(w)
    local g = RD.gauge
    local hud = g and g.hud
    if not hud then return end
    for k, t in pairs(hud.ticks) do
        t:ClearAllPoints()
        t:SetPoint("TOP", hud, "TOPLEFT", k / 10 * w, 0)
    end
    for q, fs in pairs(hud.labels) do
        fs:ClearAllPoints()
        fs:SetPoint("TOP", hud, "TOPLEFT", q / 4 * w, -(RD.HUD.major + 1))
    end
end

--- The tape's size for a square `size` across: the rail's width (the tool rail + the square), the tape's length between
--- the placard and the ramjet, the ticks, the 30% lift and the window's roof. Answers the tape's length.
function RD.SizeGauge(size)
    local g, G = RD.gauge, RD.GAUGE
    if not g then return nil end
    local railW = size + RD.TOOL_RAIL_W + RD.RAIL_GAP
    if RD.gaugeRail then RD.gaugeRail:SetWidth(railW) end
    local w = railW - G.left - G.right
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", RD.gaugeRail or RD.frame, "BOTTOMLEFT", G.left, G.base)
    g:SetSize(w, G.w)
    RD.SizeHUD(w)
    for q, l in ipairs(g.ticks) do
        local x = (q / 4 - 0.5) * w
        l:SetStartPoint("CENTER", g.tickFrame, x, -G.w / 2 - 2)
        l:SetEndPoint("CENTER", g.tickFrame, x, G.w / 2 + 2)
    end
    g.lift:ClearAllPoints()
    g.lift:SetPoint("BOTTOMLEFT", g, "BOTTOMLEFT", RD.BINGO * w, 0)
    g.lift:SetSize(w, G.w)
    g.hotClip:SetPoint("TOPRIGHT", g, "TOPRIGHT", RD.BINGO * w + 2, G.flag)
    g.len = w
    return w
end

-- ------------------------------------------------------------------ the ships

--- The ship for a group of `n` (you count): the first whose `upTo` holds it; the biggest past 40.
function RD.ShipFor(n)
    n = tonumber(n) or 1
    for _, s in ipairs(RD.SHIPS) do
        if n <= s.upTo then return s end
    end
    return RD.SHIPS[#RD.SHIPS]
end

--- The corner brackets for a ship: `be` long, `bw` thick, from the square's corners.
function RD.ShapeBrackets(ship)
    local b = RD.SIZE / 2 - 4
    local e = ship.be or 22
    local c = ship.bracket
    for _, l in ipairs(RD.brackets or {}) do
        local sx, sy = l.sx, l.sy
        l:SetStartPoint("CENTER", RD.scope, sx * b, sy * b)
        if l.across then l:SetEndPoint("CENTER", RD.scope, sx * (b - e), sy * b)
        else l:SetEndPoint("CENTER", RD.scope, sx * b, sy * (b - e)) end
        l:SetThickness(ship.bw or 2)
        l:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

--- FLY THIS SHIP: repaint the radar's chrome in its colours. Out of a fight (RD.Arm); colours only, nothing secure.
--- RD.PLATE is the hull and is changed IN PLACE, so everything made later from it (a stabilizer cover the client builds
--- at the next aura) comes out in the same dark. Answers the ship.
function RD.ApplyShip(ship)
    ship = ship or RD.SHIPS[1]
    RD.ship = ship
    local P = ship.plate
    RD.PLATE[1], RD.PLATE[2], RD.PLATE[3] = P[1], P[2], P[3]
    local function plate(t) if t then t:SetVertexColor(P[1], P[2], P[3], 1) end end
    plate(RD.fade)
    for _, r in ipairs({ RD.toolRail, RD.gaugeRail, RD.defRail, RD.bbRail }) do plate(r and r.bg) end
    local sh = RD.shield
    if sh then
        plate(sh.plate)
        for _, t in ipairs(sh.cover or {}) do plate(t) end
    end
    plate(RD.washHole)
    -- the scope: rings, cross and ticks at the ship's line, dimmed; the brackets; you in the middle in its accent
    local L, k = ship.line, RD.SCOPE_DIM
    for _, l in ipairs(RD.scopeLines or {}) do l:SetVertexColor(L[1] * k, L[2] * k, L[3] * k, 0.85) end
    RD.ShapeBrackets(ship)
    local A = ship.accent
    RD.PaintMe()
    -- the fuel tape: your mana and the ruler in the ship's fuel colour, the groove, the scale, the readout, the placard
    local g = RD.gauge
    if g then
        local F = ship.fuel
        g.mana:SetStatusBarColor(F[1], F[2], F[3], F[4] or 1)
        g.track:SetColorTexture(ship.track[1], ship.track[2], ship.track[3], ship.track[4] or 1)
        for _, l in ipairs(g.ticks) do l:SetVertexColor(L[1], L[2], L[3], 1) end
        local hud = g.hud
        if hud then
            hud.spine:SetVertexColor(L[1], L[2], L[3], 1)
            for _, t in pairs(hud.ticks) do t:SetVertexColor(L[1], L[2], L[3], 1) end
            for _, fs in pairs(hud.labels) do fs:SetTextColor(L[1], L[2], L[3]) end
        end
        local box = g.readout
        if box then
            plate(box.fill)
            for _, t in ipairs(box.edges or {}) do t:SetVertexColor(A[1], A[2], A[3], 1) end
            box.tip1:SetVertexColor(A[1], A[2], A[3], 1)
            box.tip2:SetVertexColor(A[1], A[2], A[3], 1)
            box.num:SetTextColor(1, 1, 1)
        end
        if g.ship then
            g.ship:SetText(ship.name)
            g.ship:SetTextColor(A[1], A[2], A[3])
        end
        if g.fuelWord then g.fuelWord:SetTextColor(L[1], L[2], L[3]) end
    end
    RD.PaintRole()
    RD.PaintKnobs()                                  -- the knobs' "on" dot is the ship's line too
    return ship
end

--- A regen tool's face: a ring and its sign, PLAIN TEXTURES ONLY (the client's curve colour lands on a texture, never
--- on a Line - Arn's white blade), every piece born invisible so a colour that does not land shows nothing.
local function toolFace(b, kind)
    for _, l in ipairs(b.ring or {}) do l:Hide() end
    b.icon:Hide()
    local out, face = {}, b.face
    local s = 1                                                -- the signs are drawn for a 26px pip, then scaled
    local function bar(w, h, x, y, rot)
        local t = face:CreateTexture(nil, "OVERLAY")
        t:SetTexture(RD.WHITE)
        t:SetVertexColor(1, 1, 1, 0)
        t:SetSize(math.max(1, w * s), math.max(1, h * s))
        t:SetPoint("CENTER", face, "CENTER", x * s, y * s)
        if rot and t.SetRotation then t:SetRotation(rot) end
        out[#out + 1] = t
    end
    local r, n = RD.SYS_PX / 2 - 1, 16
    for k = 0, n - 1 do
        local a = (k + 0.5) * 2 * math.pi / n
        bar(2 * math.pi * r / n + 1, 2, math.sin(a) * r, math.cos(a) * r, -a)
    end
    s = RD.SYS_PX / 26
    if kind == "tide" then                                     -- a totem: the pole, its arms, a wave at its foot
        bar(4, 14, 0, 0) bar(12, 2, 0, 3) bar(10, 2, 0, -6)
    elseif kind == "potion" then                               -- a flask: the neck and the body
        bar(3, 5, 0, 5) bar(6, 2, 0, 3) bar(10, 8, 0, -3)
    elseif kind == "reserve" then                              -- a reserve can: the body, its handle, the spout
        bar(10, 10, -1, -2) bar(6, 2, -2, 5) bar(2, 6, 5, 4, -0.6)
    elseif kind == "chaff" then                                -- the ground sign: a stem into three shrinking bars
        bar(2, 8, 0, 4) bar(12, 2, 0, -1) bar(8, 2, 0, -4) bar(4, 2, 0, -7)
    else                                                       -- a drop
        bar(2, 9, -2.2, 2, -0.45) bar(2, 9, 2.2, 2, 0.45) bar(8, 5, 0, -3.5)
    end
    b.pieces = out
    return out
end

--- Is this tool switched off by its knob?
function RD.KnobOff(kind)
    local off = db().off
    return type(off) == "table" and kind ~= nil and off[kind] == true or false
end

--- Switch a tool's knob (true = off). Works in a fight: it only repaints what we light.
function RD.SetKnob(kind, isOff)
    local d = db()
    d.off = type(d.off) == "table" and d.off or {}
    d.off[kind] = isOff and true or nil
    RD.PaintKnobs()
    if RD.Active() then RD.PaintQuiet() RD.PaintChaff() end
    return RD.KnobOff(kind)
end

--- The knob on a tool's top-left corner: a plain button on the tool's rail, over the pip. A click flips it.
function RD.Knob(b)
    local k = CreateFrame("Button", nil, b.rail or RD.frame)
    k:SetSize(RD.KNOB_PX, RD.KNOB_PX)
    k:SetPoint("CENTER", b, "TOPLEFT", 1, -1)
    k:SetFrameLevel((b:GetFrameLevel() or 0) + 6)
    if k.RegisterForClicks then k:RegisterForClicks("LeftButtonUp") end
    k.dot = k:CreateTexture(nil, "OVERLAY")
    k.dot:SetAllPoints(k)
    k.dot:SetTexture(RD.ART .. "disc")
    k.owner = b
    k:SetScript("OnClick", function(self)
        local kind = self.owner.kind
        RD.SetKnob(kind, not RD.KnobOff(kind))
        if GameTooltip and GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
    end)
    k:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        local tool = self.owner
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine((tool.tip and tool.tip[1] or "TOOL") .. (RD.KnobOff(tool.kind) and "  -  OFF" or "  -  ON"))
        GameTooltip:AddLine(RD.KnobOff(tool.kind) and "Switched off: it never lights.  Click to switch it back on."
                            or "Lights when it needs you.  Click to switch it off (works in a fight).", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    k:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b.knob = k
    return k
end

--- Every knob: shown on an armed tool only; red when off (a warning, every ship), a faint dot in the ship's line when on
--- (Arn's 9 Nov screenshot: the old phosphor green sat wrong on the purple fighter). Plain frames: any time, fight or not.
function RD.KnobOnColour()
    local L = RD.ship and RD.ship.line
    if not L then return RD.KNOB_ON end
    return { L[1], L[2], L[3], RD.KNOB_ON[4] }
end
function RD.PaintKnobs()
    local on = RD.KnobOnColour()
    for _, b in ipairs(RD.knobbed or {}) do
        local k = b.knob
        if k then
            if b.macro then
                local c = RD.KnobOff(b.kind) and RD.KNOB_OFF or on
                k.dot:SetVertexColor(c[1], c[2], c[3], c[4])
                k:Show()
            else
                k:Hide()
            end
        end
    end
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
    -- THE MANA COLUMN on its own rail outside the square (RD.toolRail): the STABILIZER on top (only the button moved - its client
    -- cover is anchored to the button, so it follows), then the regen tools: Mana Tide, the best mana potion, the best
    -- drink (the old FUEL pip, its name kept). Each always in its place, invisible until its own curve lights it.
    RD.BuildRails(f)
    local step, X, rail = RD.SYS_PX + RD.TOOL_GAP, (RD.TOOL_RAIL_W - RD.SYS_PX) / 2, RD.toolRail
    RD.shield = buildSystem(f, "Shield", "TOPLEFT", X, -8, rail)
    RD.tide = buildSystem(f, "Tide", "TOPLEFT", X, -8 - step, rail)
    RD.potion = buildSystem(f, "Potion", "TOPLEFT", X, -8 - 2 * step, rail)
    -- the RESERVE TANK after the fight tools it stands behind (Mana Spring, RD.ReserveOpen)
    RD.reserve = buildSystem(f, "Reserve", "TOPLEFT", X, -8 - 3 * step, rail)
    RD.fuel = buildSystem(f, "Fuel", "TOPLEFT", X, -8 - 4 * step, rail)
    -- RATIONS, last in the column (Arn, 8 Nov: "move the rations next to the drink too")
    RD.rations = buildSystem(f, "Rations", "TOPLEFT", X, -8 - 5 * step, rail)
    RD.COLUMN = { RD.shield, RD.tide, RD.potion, RD.reserve, RD.fuel, RD.rations }
    RD.tide.kind, RD.potion.kind, RD.reserve.kind, RD.fuel.kind = "tide", "potion", "reserve", "drink"
    RD.fuel.restOnly = true                          -- a drink is out of a fight only
    RD.reserve.gate = function(fight) return RD.ReserveOpen(fight) end
    RD.TOOLS = { RD.tide, RD.potion, RD.reserve, RD.fuel }
    for _, b in ipairs(RD.TOOLS) do toolFace(b, b.kind) b.face:SetAlpha(0) end
    RD.fuel.drop = RD.fuel.pieces
    -- every lit thing pulses (gently here; the stabilizer keeps its own breath on its red), and carries a sweep: the
    -- GCD's, or for Mana Tide and the potion their own cooldown (RD.Sweeps)
    for _, b in ipairs({ RD.tide, RD.potion, RD.reserve, RD.fuel, RD.rations }) do b.pulse = RD.Pulse(b.beat, RD.PULSE_SOFT) end
    for _, b in ipairs(RD.COLUMN) do
        if b == RD.tide or b == RD.potion then b.cd = RD.WaitSweep(b) else b.cd = RD.Sweep(b.face) end
    end
    -- THE DEFENCE RAIL (right of the square): CHAFF, the targetless catch-all (RD.ChaffLit)
    RD.chaff = buildSystem(f, "Chaff", "TOPLEFT", X, -8, RD.defRail)
    RD.chaff.kind = "chaff"
    toolFace(RD.chaff, "chaff")
    RD.chaff.face:SetAlpha(0)
    RD.chaff.pulse = RD.Pulse(RD.chaff.beat, RD.PULSE_MID)
    RD.chaff.cd = RD.Sweep(RD.chaff.face)
    RD.DEFENCE = { RD.chaff }
    -- a knob on each tool that lights by itself (the stabilizer and the rations stay: always wanted)
    RD.knobbed = { RD.tide, RD.potion, RD.reserve, RD.fuel, RD.chaff }
    for _, b in ipairs(RD.knobbed) do RD.Knob(b) end
    buildGauge(f)
    RD.ApplyShip(RD.SHIPS[1])                        -- a fighter until the roster says otherwise (RD.Arm)
    -- (the rail drawn inside the scope is gone: the rails stand outside the square now - RD.BuildRails)
    -- rations: a fork
    RD.rations.fork = { line(RD.rations.face, "OVERLAY", -4, 7, -4, -7, RD.COL.cyan, 2), line(RD.rations.face, "OVERLAY", 4, 7, 4, -7, RD.COL.cyan, 2),
                        line(RD.rations.face, "OVERLAY", -4, 0, 4, 0, RD.COL.cyan, 2) }
    -- (the missile tape along the bottom is gone - Arn, 8 Nov: "the guage does the same thing")
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

--- tank, heal or damage. Out of a fight (the only time a role is not a secret). THE GAME'S ROLE FIRST (8 Nov 2026, Arn:
--- "tank shows up as a sword instead of a shield" - his Ellesmere frames showed Legaian's shield from it):
--- UnitGroupRolesAssigned TANK / HEALER / DAMAGER; then BiS> now's tank or a raid main tank; then a healing class.
RD.ROLE_WORD = { TANK = "tank", HEALER = "heal", DAMAGER = "damage" }
function RD.Role(unit)
    if UnitGroupRolesAssigned then
        local okR, r = pcall(UnitGroupRolesAssigned, unit)
        r = okR and plain(r) or nil
        if type(r) == "string" and RD.ROLE_WORD[r] then return RD.ROLE_WORD[r] end
    end
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

--- YOUR ROLE ON THE PLACARD (Arn, 9 Nov: "lets add our role here Healer, DPS, Tank" ... "we take the role from what the
--- games tell us, the frames already tell us"): ONLY the game's own answer, the one its party and raid frames show - the
--- group role set for you (UnitGroupRolesAssigned), else a raid's main tank assignment (GetPartyAssignment). No guess
--- from the class, no tank mark of ours: the game says nothing, the line stays empty. A font string - fine in a fight;
--- asked in RD.Arm (a role set fires PLAYER_ROLES_ASSIGNED, which re-arms). Answers the word ("" for none).
RD.ROLE_PLACARD = { TANK = "TANK", HEALER = "HEALER", DAMAGER = "DPS" }
function RD.GameRole()
    if UnitGroupRolesAssigned then
        local okR, r = pcall(UnitGroupRolesAssigned, "player")
        r = okR and plain(r) or nil
        if type(r) == "string" and RD.ROLE_PLACARD[r] then return RD.ROLE_PLACARD[r] end
    end
    if GetPartyAssignment then
        local ok, mt = pcall(GetPartyAssignment, "MAINTANK", "player")
        if ok and plain(mt) == true then return "TANK" end
    end
    return ""
end
function RD.PaintRole()
    local g = RD.gauge
    local w = RD.GameRole()
    if g and g.role then g.role:SetText(w) end
    return w
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
        for _, t in ipairs(sp.amberGlyph or {}) do t:Hide() end
        local px = ((sp.slot and sp.slot.ph) or RD.PARTY.ph) * RD.GLYPH
        sp.glyph = glyph(b.face, role, px)
        sp.redGlyph = glyph(b.redFace, role, px)
        sp.amberGlyph = glyph(b.amberFace, role, px)
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

--- The pet's token for an owner's: player -> pet, party3 -> partypet3, raid12 -> raidpet12; nil for anything else.
function RD.PetOf(unit)
    if type(unit) ~= "string" then return nil end
    if RD.PET_UNIT[unit] then return RD.PET_UNIT[unit] end
    local kind, n = unit:match("^(%a+)(%d+)$")
    if kind == "party" or kind == "raid" then return kind .. "pet" .. n end
    return nil
end

--- Where a slot's pet sits, and how big: a party's beside its owner (turned clockwise), yours below you, a raid's own
--- group nearer the middle on its owner's bearing. nil = no pet here (a raid's other groups).
function RD.PetSpot(s)
    if not s then return nil end
    local P = RD.PET
    if s.self then
        return math.sin(P.selfB) * P.selfR, math.cos(P.selfB) * P.selfR, RD.raid and P.raidPx or P.px
    end
    if RD.raid then
        if not s.own then return nil end
        local r = s.rh - P.inward
        return math.sin(s.b) * r, math.cos(s.b) * r, P.raidPx
    end
    local b = s.b + P.turn
    return math.sin(b) * s.rh, math.cos(b) * s.rh, P.px
end

--- A paw, our own shape: a pad and four toes, plain textures born invisible (the curve's colour lands on textures).
local function paw(face, px)
    local out = {}
    local function dot(w, h, x, y)
        local t = face:CreateTexture(nil, "OVERLAY")
        t:SetTexture(RD.ART .. "disc")
        t:SetVertexColor(1, 1, 1, 0)
        t:SetSize(w, h)
        t:SetPoint("CENTER", face, "CENTER", x, y)
        out[#out + 1] = t
    end
    local u = px / 14
    dot(7 * u, 6 * u, 0, -2.5 * u)                                   -- the pad
    dot(3 * u, 3 * u, -4.5 * u, 1.5 * u) dot(3 * u, 3.5 * u, -1.6 * u, 4 * u)
    dot(3 * u, 3.5 * u, 1.6 * u, 4 * u) dot(3 * u, 3 * u, 4.5 * u, 1.5 * u)
    return out
end

--- Put a spoke's pet where its slot says, on its owner's pet token, the client watching it. Out of a fight only.
--- No owner, or no place for a pet (a raid's other groups): off the watch and hidden.
local function armPet(sp, unit, s)
    local p = sp.pet
    if not p then return nil end
    local x, y, px = RD.PetSpot(s)
    local pu = unit and x and RD.PetOf(unit) or nil
    if not pu then
        if UnregisterUnitWatch then pcall(UnregisterUnitWatch, p) end
        p:SetAttribute("unit", nil)
        p:SetAttribute("type1", nil)
        p:Hide()
        sp.petUnit, sp.petTex = nil, nil
        return nil
    end
    p:SetSize(px, px)
    p:ClearAllPoints()
    p:SetPoint("CENTER", RD.frame, "CENTER", x, y)
    p:SetAttribute("unit", pu)
    if NS.FM and NS.FM.ApplyTo then pcall(NS.FM.ApplyTo, p) end      -- your binds on every other click
    local h = RD.heal
    p:SetAttribute("type1", h and "spell" or nil)
    p:SetAttribute("spell1", h and h.cast or nil)
    p.unit = pu
    if sp.petPx ~= px then
        for _, t in ipairs(sp.petTex or {}) do t:Hide() end
        sp.petTex, sp.petPx = paw(p.face, px), px
    end
    sp.petUnit = pu
    if RegisterUnitWatch then pcall(RegisterUnitWatch, p) end         -- the client shows it while the pet is there
    return pu
end

--- A pet's pip, coloured by the client from the pet's health through the radar's curve (hidden when healthy).
function RD.PaintPet(sp)
    local p = sp and sp.pet
    if not (p and sp.petUnit and sp.petTex) then return false end
    local okE, there = pcall(UnitExists, sp.petUnit)
    if okE and plain(there) == false then p.face:SetAlpha(0) return false end
    p.face:SetAlpha(1)
    local curve = RD.Curve(RD.AMBER)
    local ok, col = false, nil
    if curve and UnitHealthPercent then ok, col = pcall(UnitHealthPercent, sp.petUnit, true, curve) end  -- an `and` keeps one return
    local drew = ok and paint(sp.petTex, col)
    if not drew then p.face:SetAlpha(0) end                      -- no colour back: nothing, never a stale sign
    return drew
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
            RD.Unsweep(c.sweep)                -- a marker switched off is fed no sweep (kept, for when it comes back)
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
            -- the client's marker lives in a plain holder that pulses gently (whack-a-mole): the marker itself is
            -- never animated, and it draws only while there is something to cure, so the pulse shows only then
            c.holder = CreateFrame("Frame", nil, f)
            c.holder:SetAllPoints(f)
            c.pulse = RD.Pulse(c.holder, RD.PULSE_SOFT)
            sp.cures[n] = c
        end
        c.box:SetSize(px + 4, px + 4)
        RD.Halo(c.box, px + 4)
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
            RD.Resweep(c.sweep)
        else
            if c.container and c.container.SetEnabled then pcall(c.container.SetEnabled, c.container, false) end
            c.container, c.key = nil, nil
            RD.Unsweep(c.sweep)                -- the old marker's sweep is fed no more
            c.sweep = nil
            local ok, container = pcall(CreateFrame, "AuraContainer", nil, c.holder or f, "CustomAuraContainerTemplate")
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
                        -- the GCD sweep on the marker: drawn only while the client draws the marker
                        if not button.bisSweep then button.bisSweep = RD.Sweep(button) c.sweep = button.bisSweep end
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

--- THE LAST CHARGE, AS A COLOUR THE CLIENT CHOOSES (the reminder's road, FS.Wash): the client writes the charge count into
--- a font string through a formatter we hand it; 1 is written as an orange SQUARE, anything else as nothing. Never read.
--- THE SYMBOL IS A STENCIL (9 Nov 2026, Arn's screenshot: "look at the stabaliuzer graphics squished"). The gyro used to
--- be the escape itself (Art\gyro.tga), and came out a flat bar a quarter of its height: a texture escape is sized by
--- the text line it sits in, not by the pixels it asks for (the reminder learned that on 12 Oct - FS.Wash). A square
--- does not mind being any size, so the client paints a square RD.WASH_OVER times the pip, cut to the pip by a clip, and
--- over it lies Art\gyrohole.tga in the plate's dark with the symbol CUT OUT: the orange shows through the symbol only.
--- With no orange under it the stencil is plate on plate - nothing to see.
RD.ART = "Interface\\AddOns\\" .. (ADDON or "BiSHealing") .. "\\Art\\"
RD.WASH_OVER = 3
function RD.WashText(px, rgb)
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(px, px, rgb[1], rgb[2], rgb[3])
end
function RD.ShieldWash(button)
    local make = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    if not (make and button and button.SetApplicationCount) then return false end
    local px = RD.SYS_PX * RD.WASH_OVER
    if not RD.washFmt then
        local ok, f = pcall(make)
        if not ok or not f or not f.SetBreakpoints then return false end
        local points = { { threshold = 0, format = "" }, { threshold = 1, format = RD.WashText(px, RD.SHIELD_LAST) },
                         { threshold = 2, format = "" } }
        if not pcall(f.SetBreakpoints, f, points) then return false end
        RD.washFmt = f
    end
    local clip = CreateFrame("Frame", nil, button)
    clip:SetAllPoints(button)
    if clip.SetClipsChildren then clip:SetClipsChildren(true) end
    -- THE LAST CHARGE ASKS FOR A CLICK, SO IT PULSES (Arn, 8 Nov: "make the stabilizer pulse too"): gently, on this clip
    -- only - the orange the client writes into it beats, the green cover beside it holds still
    RD.washPulse = RD.PulseAlpha(clip, RD.FADE_SOFT)
    RD.washClip = clip
    local fs = clip:CreateFontString(nil, "OVERLAY")
    if fs.SetFont then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", RD.SYS_PX, "") end
    fs:SetPoint("CENTER", clip, "CENTER", 0, 0)
    -- the stencil, over the orange (and still: only the orange under it beats)
    local hole = CreateFrame("Frame", nil, button)
    hole:SetAllPoints(button)
    if hole.SetFrameLevel and clip.GetFrameLevel then
        local lvl = clip:GetFrameLevel()
        if type(lvl) == "number" then hole:SetFrameLevel(lvl + 2) end
    end
    local t = hole:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(hole)
    t:SetTexture(RD.ART .. "gyrohole")
    t:SetVertexColor(RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1)
    RD.washHole = t
    return pcall(button.SetApplicationCount, button, fs, { formatter = RD.washFmt })
end

--[[ THE STABILIZER (8 Nov 2026, Arn: "i dont want a shield icon i want an icon that a jet pilot would see in combat and
  know i need to press this button to fly effectively maybe call it stabilizer ... cause priest would see a inner fire").
  One cockpit symbol for every class's keep-up buff (Water Shield, Inner Fire, Omen of Clarity, Blessing of Wisdom): an
  ATTITUDE INDICATOR - a ring, the horizon across it, the little aircraft's wings and nose. Plain textures only (the
  colour lands on them), every piece turned with SetRotation. Drawn TWICE, identically: red on the pip (under), and a
  dim green copy on the client's own aura button over it - piece for piece on the same spot, so the green hides the red
  exactly while the buff is up, and the red shows the moment the client stops drawing. ]]
RD.GYRO_SEG = 16
function RD.Gyro(parent, px, col, layer)
    local out = {}
    local function bar(w, h, x, y, rot)
        local t = parent:CreateTexture(nil, layer or "OVERLAY")
        t:SetTexture(RD.WHITE)
        t:SetVertexColor(col[1], col[2], col[3], col[4] or 1)
        t:SetSize(w, h)
        t:SetPoint("CENTER", parent, "CENTER", x, y)
        if rot and t.SetRotation then t:SetRotation(rot) end
        out[#out + 1] = t
        return t
    end
    local r = px * 0.44
    local seg = 2 * math.pi * r / RD.GYRO_SEG + 1
    for k = 0, RD.GYRO_SEG - 1 do                              -- the ring
        local a = (k + 0.5) * 2 * math.pi / RD.GYRO_SEG
        bar(seg, 2, math.sin(a) * r, math.cos(a) * r, -a)
    end
    bar(px * 0.80, 1, 0, 0)                                    -- the horizon
    bar(px * 0.24, 2, -px * 0.17, -px * 0.08)                  -- the wings, either side of the nose
    bar(px * 0.24, 2, px * 0.17, -px * 0.08)
    bar(2, px * 0.10, 0, -px * 0.03)                           -- the nose
    return out
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
    -- the red under it: the STABILIZER symbol (RD.Gyro), breathing - not the spell's picture (Arn: a cockpit symbol, the
    -- same for every class)
    b.icon:Hide()
    for _, l in ipairs(b.ring or {}) do l:Hide() end        -- the gyro has its own ring
    if not b.gyroRed then b.gyroRed = RD.Gyro(b.face, RD.SYS_PX, RD.COL.red, "ARTWORK") end
    -- the plate: the dark the cover is painted in, so a covered pip looks like the plate alone
    if not b.plate then
        b.plate = b:CreateTexture(nil, "BACKGROUND")
        b.plate:SetAllPoints(b)
        b.plate:SetTexture(RD.WHITE)
        b.plate:SetVertexColor(RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1)
    end
    b.tip = { "STABILIZER", name .. " - click to cast it.  Dim green: on you.  Orange: the last charge.  Red: gone." }
    b.face:SetAlpha(1)
    if not b.breath and b.face.CreateAnimationGroup then
        local okA, g = pcall(b.face.CreateAnimationGroup, b.face)
        if okA and g then
            local fade = g:CreateAnimation("Alpha")
            -- moderate, as the column's (Arn, 8 Nov: "nothing crazy"): the soft pulse's depth, a breath's pace
            fade:SetFromAlpha(1) fade:SetToAlpha(RD.FADE_SOFT[1]) fade:SetDuration(0.6)
            g:SetLooping("BOUNCE")
            g:Play()
            b.breath = g
        end
    end
    local FA = NS.FA
    if not (FA and FA.Available and FA.Available() and FA.AddSlot and ids and #ids > 0) then return end
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, b, "CustomAuraContainerTemplate")
    if not (ok and container) then return end
    container:SetSize(1, 1)
    container:SetPoint("CENTER", b)
    if container.SetFrameLevel then container:SetFrameLevel(b:GetFrameLevel() + 10) end   -- over the red
    container:SetUnit("player")
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    b.container = container
    b.slot = FA.AddSlot(container, "BiSRadarShield", "HELPFUL", {
        candidateFilters = { includeSpellIDs = want },
        -- THE REMINDER'S OWN ROAD, WHICH WORKS IN A FIGHT (8 Nov 2026, Arn: "watershield reminder used to work in
        -- combat"; SelfBuff.lua's badge, 12 Oct). Nothing of ours decides "missing": the red pip is ALWAYS drawn under
        -- this button, and while the buff is up the CLIENT draws the button over it - our cover, the shield's own icon
        -- greyed into the scope's dark - so the red is hidden. Gone: the client stops drawing it, the red shows. The
        -- old hooks (OnShow/OnHide flipping the red's alpha) missed changes and are gone. The charges are the client's
        -- too: the last one washes the cover orange (RD.ShieldWash), any more write nothing.
        initializeFrame = FA.Placed(function(button)
            if button.GetRegions then for _, r in ipairs({ button:GetRegions() }) do if r.Hide then pcall(r.Hide, r) end end end
            b.handed = true
            pcall(function()
                -- NOTHING TO CLICK WHILE IT IS UP (Arn, 8 Nov: "this stabilizer is 3/3 it needs to go away or ill keep
                -- trying to click it"): the cover is a plain square in the PLATE's own dark (RD.PLATE, drawn under the
                -- pip by armShield), so with the buff up you see only the dark plate - no symbol. It still hides the red
                -- whole. The last charge washes it orange; gone, the client stops drawing it and the red shows.
                local t = button:CreateTexture(nil, "OVERLAY")
                t:SetAllPoints(button)
                t:SetTexture(RD.WHITE)
                t:SetVertexColor(RD.PLATE[1], RD.PLATE[2], RD.PLATE[3], 1)
                b.cover = { t }
            end)
            pcall(RD.ShieldWash, button)
            if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
            if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
            if button.EnableMouse then pcall(button.EnableMouse, button, false) end
        end, RD.SYS_PX, "CENTER", b, 0, 0),
    })
    -- switched on and asked to look now, as the reminder's badge is: a shield already on you is not news to a container
    -- that only listens for changes. No slot placed: the red would never be covered - so no pip at all.
    if not b.slot then b.face:SetAlpha(0) b.shieldName = nil return end
    if container.SetEnabled then pcall(container.SetEnabled, container, true) end
    if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
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

--- HOW MUCH MANA A TOOL GIVES BACK, from its own words (out of a fight, plain): "Restores 1350 to 2250 mana" -> the
--- middle; "Restores 4200 mana over 30 sec" -> 4200; "restores 170 mana every 3 seconds ... for 12 sec" -> 170 x 4.
--- nil when the words say no number.
function RD.RestoreAmount(text)
    if type(text) ~= "string" then return nil end
    local function num(s) return tonumber((tostring(s or ""):gsub(",", ""))) end
    -- a number may carry a decimal ("Restores 835.2 mana"): read whole, never as its last digit
    local N = "(%d[%d,]*%.?%d*)"
    local a, b = text:match(N .. "%s+to%s+" .. N .. "%s+mana")
    local n = (num(a) and num(b)) and (num(a) + num(b)) / 2 or num(text:match(N .. "%s+mana"))
    if not n then return nil end
    local every = num(text:match("every%s+(%d+)%s+sec"))
    local dur = num(text:match("for%s+(%d+)%s+sec"))
    local mins = num(text:match("for%s+(%d+)%s+min"))              -- Mana Spring: "for 5 min ... every 2 seconds"
    if not dur and mins then dur = mins * 60 end
    if every and dur and every > 0 and dur >= every then n = n * math.floor(dur / every) end
    return n
end

local function describe(spell)
    local get = C_Spell and C_Spell.GetSpellDescription
    if not (get and spell) then return nil end
    local ok, text = pcall(get, spell)
    text = ok and plain(text) or nil
    return type(text) == "string" and text or nil
end

--- An item's use, in words: its use-spell's description.
local function itemWords(id)
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not (getSpell and id) then return nil end
    local ok, _, sid = pcall(getSpell, id)
    sid = ok and plain(sid) or nil
    return sid and describe(sid) or nil
end

--- Learn where a tool lights: `at` = restores / your full mana (both plain out of a fight), else RD.TOOL_GUESS and
--- `guess` = true. Kept on the button; its curve is RD.ToolCurve(b.at).
--- KEEP YOU OFF EMPTY, NOT TOP YOU UP (Arn, 8 Nov: "run these backwards we dont want to light them as soon as they will
--- bring us back to 100% we want to use them when they will keep us from reaching 0%"): a tool lights once your mana is
--- down to what it gives back - Mana Tide's 352 of 1,400 lights at 25%, not at 75%.
function RD.LearnTool(b, words)
    local amount = RD.RestoreAmount(words)
    local okM, mx = pcall(UnitPowerMax, "player", 0)
    mx = okM and plain(mx) or nil
    b.amount = amount
    if amount and type(mx) == "number" and mx > 0 then
        b.at, b.guess = math.max(0.02, math.min(amount / mx, 0.98)), false
    else
        b.at, b.guess = RD.TOOL_GUESS, true
    end
    b.at = math.floor(b.at * 100 + 0.5) / 100                     -- the curve's own point (RD.ToolCurve rounds to 1%)
    return b.at, amount
end

local function toolTip(b, title, what)
    local where = b.guess and ("its amount unknown - lights below %d%% mana (a guess)"):format(b.at * 100 + 0.5)
                  or ("restores ~%d mana - lights below %d%% mana, when it keeps you off empty"):format(b.amount, b.at * 100 + 0.5)
    b.tip = { title, what .. ".  " .. where .. "." .. (b.restOnly and "  Out of a fight only." or "") }
end

--- Arm one tool: its click (a macro written out of a fight) and its light point. `macro` nil = this tool is not here.
local function armTool(b, macro, words, title, what)
    b:SetAttribute("*type1", macro and "macro" or nil)
    b:SetAttribute("*macrotext1", macro)
    b:EnableMouse(macro and true or false)
    b.macro = macro
    if not macro then b.tip = nil return end
    RD.LearnTool(b, words)
    toolTip(b, title, what)
end

--- THE REGEN TOOLS, out of a fight (Arn: "they are always there and we use ingame calculations out of fight"): Mana Tide
--- if you know it, the best mana potion, the best drink - each learns its amount and gets its click.
function RD.ArmTools()
    if combat() or not RD.tide then return false end
    local FM = NS.FM
    local tide = FM and FM.Ranks and #FM.Ranks(RD.TIDE) > 0
    armTool(RD.tide, tide and ("/cast " .. RD.TIDE) or nil, tide and describe(RD.TIDE), "MANA TIDE", RD.TIDE)
    local potion = RD.BestItem(RD.POTION)
    RD.potion.item = potion
    armTool(RD.potion, potion and ("/use item:" .. potion) or nil, itemWords(potion), "MANA POTION",
            "the best mana potion in your bags")
    local drink = RD.BestItem("Drink")
    RD.fuel.item = drink
    armTool(RD.fuel, drink and ("/use item:" .. drink) or nil, itemWords(drink), "DRINK", "the best drink in your bags")
    local spring = FM and FM.Ranks and #FM.Ranks(RD.SPRING) > 0
    armTool(RD.reserve, spring and ("/cast " .. RD.SPRING) or nil, spring and describe(RD.SPRING), "RESERVE TANK",
            RD.SPRING .. " - the last resort: lights only when Mana Tide and your potion are spent (or not here)")
    -- the potion's use-spell, so our own clock knows it when you drink one in a fight
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    RD.potion.spellId = nil
    if potion and getSpell then
        local okS, _, sid = pcall(getSpell, potion)
        RD.potion.spellId = okS and plain(sid) or nil
    end
    RD.ArmChaff()
    RD.SeedCooldowns()
    RD.PaintKnobs()
    return true
end

--- Your chaff: RD.CHAFF[class] if trained, and never the same spell as your interrupt (a priest whose only interrupt is
--- Psychic Scream has no second answer). nil = none.
function RD.ChaffSpell()
    local okC, _, class = pcall(UnitClass, "player")
    class = okC and plain(class) or nil
    local name = RD.CHAFF[class or ""]
    local FM, FG = NS.FM, NS.FG
    if not (name and FM and FM.Ranks and #FM.Ranks(name) > 0) then return nil end
    if FG and FG.KickSpell and FG.KickSpell() == name then return nil end
    return name
end

--- Arm the chaff (its click, written out of a fight) and show the defence rail only when it holds it.
function RD.ArmChaff()
    local b = RD.chaff
    if combat() or not b then return false end
    local spell = RD.ChaffSpell()
    local macro = spell and ("/cast " .. spell) or nil
    b:SetAttribute("*type1", macro and "macro" or nil)
    b:SetAttribute("*macrotext1", macro)
    b:EnableMouse(macro and true or false)
    b.macro, b.spell = macro, spell
    b.tip = spell and { "CHAFF", spell .. " - the catch-all: lights when an enemy on the radar casts and your interrupt "
                        .. "(the flare on its bogey) is cooling.  No target needed." } or nil
    if RD.defRail then
        if spell then RD.defRail:Show() else RD.defRail:Hide() end
        RD.ClampRails()
    end
    return spell
end

--- What is still cooling, from the client while it will say (out of a fight): seeds our own clock, so a Mana Tide used
--- before a /reload still counts as spent. Plain numbers only; anything else leaves the clock as it was.
function RD.SeedCooldowns()
    if combat() then return false end
    local now = (GetTime and GetTime()) or 0
    local getCd = C_Spell and C_Spell.GetSpellCooldown
    if RD.tide and RD.tide.macro and getCd then
        local ok, info = pcall(getCd, RD.TIDE)
        local s, d = nil, nil
        if ok and type(info) == "table" then
            s = plain(info.startTime)
            d = plain(info.duration)
        end
        if type(s) == "number" and type(d) == "number" and d > 2 then RD.readyAt.tide, RD.coolStart.tide = s + d, s end
    end
    local itemCd = C_Container and C_Container.GetItemCooldown
    if RD.potion and RD.potion.item and itemCd then
        local ok, s, d = pcall(itemCd, RD.potion.item)
        if ok then
            s = plain(s)
            d = plain(d)
        else
            s, d = nil, nil
        end
        if type(s) == "number" and type(d) == "number" and d > 2 then RD.readyAt.potion, RD.coolStart.potion = s + d, s end
    end
    -- the flare and the chaff: their clocks seeded, and their real length learned (talents can shorten them)
    local FG = NS.FG
    local named = { kick = FG and FG.KickSpell and FG.KickSpell() or nil, chaff = RD.chaff and RD.chaff.spell or nil }
    for kind, name in pairs(named) do
        if name and getCd then
            local ok, info = pcall(getCd, name)
            local s, d = nil, nil
            if ok and type(info) == "table" then
                s = plain(info.startTime)
                d = plain(info.duration)
            end
            if type(s) == "number" and type(d) == "number" and d > 2 then
                RD.readyAt[kind], RD.coolStart[kind], RD.cdLen[kind] = s + d, s, d
            end
        end
    end
    return true
end

--- Is the flare (your interrupt) spent? No interrupt at all counts as spent: the chaff is all you have.
function RD.FlareSpent(now)
    local FG = NS.FG
    if not (FG and FG.KickSpell and FG.KickSpell()) then return true end
    return (RD.readyAt.kick or 0) > (now or (GetTime and GetTime()) or 0)
end

--- THE CHAFF'S LIGHT: armed, knob on, in a fight, something casting, the flare spent and the chaff ready. Plain booleans.
function RD.ChaffLit(fight, casting)
    local b = RD.chaff
    if not (b and b.macro) or RD.KnobOff("chaff") then return false end
    if not (fight and casting) then return false end
    local now = (GetTime and GetTime()) or 0
    if (RD.readyAt.chaff or 0) > now then return false end
    return RD.FlareSpent(now)
end

--- Paint the chaff from the last look (RD.anyCast, set by RD.Look): its sign in amber and its face seen, or dark.
function RD.PaintChaff(casting)
    local b = RD.chaff
    if not b then return false end
    if casting == nil then casting = RD.anyCast end
    local lit = RD.ChaffLit(RD.inFight or combat(), casting)
    local c = RD.CHAFF_COL
    for _, t in ipairs(b.pieces or {}) do t:SetVertexColor(c[1], c[2], c[3], lit and 1 or 0) end
    b.face:SetAlpha(lit and 1 or 0)
    return lit
end

--- THE COOLING DISCS, FROM OUR OWN CLOCK (8 Nov 2026, Arn: "this mana tide sweep shows up whenever i click anything"):
--- the client's Mana Tide cooldown carries the global cooldown too, and in a fight its object is secret - we cannot tell
--- "on the GCD" from "spent". So the disc never takes it: it runs from the cast we saw (or the client's plain answer out
--- of a fight, longer than a GCD), plain numbers handed to SetCooldown; ready = cleared.
function RD.PaintWaits(now)
    now = now or (GetTime and GetTime()) or 0
    local n = 0
    for kind, b in pairs({ tide = RD.tide, potion = RD.potion }) do
        local cd = b and b.cd
        if cd and cd.wait then
            local s, r = RD.coolStart[kind], RD.readyAt[kind]
            if b.macro and type(s) == "number" and type(r) == "number" and r > now then
                if pcall(cd.SetCooldown, cd, s, r - s) then n = n + 1 end
            elseif cd.Clear then
                pcall(cd.Clear, cd)
            end
        end
    end
    return n
end

--- Is a tool spent right now? Not here at all counts as spent (nothing to reach for); else our clock.
local function spent(b, kind, now)
    if not (b and b.macro) then return true end
    return (RD.readyAt[kind] or 0) > now
end

--- THE RESERVE TANK'S GATE: armed, no water totem of yours standing, Mana Tide and the potion both spent, and - out of a
--- fight - no drink to reach for instead. Plain booleans from our own clock; the mana level is the curve's (PaintTools).
function RD.ReserveOpen(fight)
    local b = RD.reserve
    if not (b and b.macro) then return false end
    local now = (GetTime and GetTime()) or 0
    if RD.waterUntil > now then return false end
    if not (spent(RD.tide, "tide", now) and spent(RD.potion, "potion", now)) then return false end
    if not fight and RD.fuel and RD.fuel.macro then return false end
    return true
end

--- One of YOUR casts (UNIT_SPELLCAST_SUCCEEDED, you only): Mana Tide, Mana Spring or a mana potion starts our clock.
--- The spell's name is asked of the client for your own cast; a secret or no answer = not one of ours.
function RD.OnCast(unit, spellID)
    if (NS.IsPlayer and NS.IsPlayer(unit)) ~= true then return false end
    spellID = plain(spellID)
    if type(spellID) ~= "number" then return false end
    local now = (GetTime and GetTime()) or 0
    if RD.potion and RD.potion.spellId and spellID == RD.potion.spellId then
        RD.readyAt.potion, RD.coolStart.potion = now + RD.COOLS.potion, now
        RD.PaintWaits(now)
        return "potion"
    end
    local getName = C_Spell and C_Spell.GetSpellName
    local ok, name = false, nil
    if getName then ok, name = pcall(getName, spellID) end
    name = ok and plain(name) or nil
    if name == RD.TIDE then
        RD.readyAt.tide, RD.coolStart.tide = now + RD.COOLS.tide, now
        RD.PaintWaits(now)
        RD.waterUntil = now + RD.WATER.tide
        return "tide"
    elseif name == RD.SPRING then
        RD.waterUntil = now + RD.WATER.spring
        return "spring"
    end
    -- the flare: your interrupt, or a spell that spends the same cooldown (a shaman's shocks share one)
    local FG = NS.FG
    local kick = FG and FG.KickSpell and FG.KickSpell() or nil
    local shares = name and kick and (name == kick)
    if not shares and name and kick then
        for _, other in ipairs(RD.KICK_SHARED[kick] or {}) do if other == name then shares = true end end
    end
    if shares then
        RD.readyAt.kick, RD.coolStart.kick = now + (RD.cdLen.kick or RD.COOLS.kick), now
        return "kick"
    end
    if name and RD.chaff and name == RD.chaff.spell then
        RD.readyAt.chaff, RD.coolStart.chaff = now + (RD.cdLen.chaff or RD.COOLS.chaff), now
        RD.PaintChaff()
        return "chaff"
    end
    return false
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
    if RD.fade then RD.fade:SetSize(RD.FADE_PX * size / RD.PARTY.size, RD.FADE_PX * size / RD.PARTY.size) end
    RD.SizeGauge(size)                 -- the fuel tape runs the rail over the tool rail and the square
    -- THE SHIP for this many (Arn, 9 Nov: "the more the group gets we change the color"): out of a fight only, here
    local n = 0
    for i = 1, #slots do if units[i] then n = n + 1 end end
    RD.ApplyShip(RD.ShipFor(math.max(1, n)))
    for i, s in ipairs(slots) do
        local sp = RD.Spoke(i)
        local unit = units[i]
        sp.unit = unit
        if sp.cd then
            sp.cd.active = unit and true or false
            if not unit and sp.cd.Clear then pcall(sp.cd.Clear, sp.cd) end
        end
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
        armPet(sp, unit, s)
        if s.rb then sp.bogey:Show() else sp.bogey:Hide() end
    end
    -- spokes beyond this layout (a raid became a party): off, out of the way
    for i = #slots + 1, #RD.spokes do
        local sp = RD.spokes[i]
        sp.unit, sp.kick, sp.paintTex = nil, nil, nil
        sp.heal:SetAttribute("unit", nil) sp.heal:SetAttribute("type1", nil) sp.heal:EnableMouse(false) sp.heal:Hide()
        sp.bogey:SetAttribute("unit", nil) sp.bogey:EnableMouse(false) sp.bogey:Hide()
        armCures(sp, nil)
        armPet(sp, nil, nil)
        for _, fr in ipairs(sp.dims) do fr:Hide() end
        sp.los:SetAlpha(0)
    end
    armShield()
    RD.ArmTools()
    armUse(RD.rations, RD.FoodWanted())
    RD.PickFuel()
    RD.PaintMe()                                     -- your role's sign in the middle (a role change lands here)
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
        if RD.SIZE_PULSE and sp.pulse and not (sp.pulse.IsPlaying and sp.pulse:IsPlaying()) then sp.pulse:Play() end
    end
    local amber = RD.AmberCurve(sp.amber)
    if amber and sp.amberGlyph then
        local okA, ac = pcall(UnitHealthPercent, sp.unit, true, amber)
        if okA then paint(sp.amberGlyph, ac) end
    end
    -- the GCD sweep's swipe: dark while the pip is lit (below RD.GREEN), see-through when it is not
    local sw = sp.cd and RD.SwipeCurve(RD.GREEN)
    if sw then
        local okS, scol = pcall(UnitHealthPercent, sp.unit, true, sw)
        swipeTo(sp.cd, okS and scol or nil)
    end
    return drew
end

--- In a fight the scope, the empty slots and the idle bogeys are see-through; out of one they are drawn dim.
function RD.PaintQuiet()
    -- a fight: the lockdown, or the moment PLAYER_REGEN_DISABLED says one starts (the lockdown begins just after it)
    local fight = RD.inFight or combat()
    -- THE SCOPE STAYS IN A FIGHT (Arn, 8 Nov: "i like this green outline in combat too"): rings, cross and corners are
    -- the instrument; only the pips come and go
    if RD.scope then RD.scope:SetAlpha(1) end
    -- the dim slot outlines are never drawn (Arn, 8 Nov: "the box outlines are not needed"); the scope alone says where
    if RD.dims then RD.dims:SetAlpha(0) end
    if RD.rations then RD.rations.face:SetAlpha((not fight and RD.rations.item) and 1 or 0) end
    RD.PaintTools(fight)
end

--- THE REGEN TOOLS' LIGHTS: each tool's own curve on your mana (lit once you miss what it restores), the client's
--- colour landing on its pieces and its sweep's swipe. Nothing compared. A tool that is not here, or a drink in a fight,
--- is dark; no colour back from the client = dark, never a stale sign.
function RD.PaintTools(fight)
    if not RD.TOOLS then return end
    for _, b in ipairs(RD.TOOLS) do
        local drew = false
        if b.macro and not (b.restOnly and fight) and not (b.gate and not b.gate(fight)) and not RD.KnobOff(b.kind)
           and UnitPowerPercent then
            local c = RD.ToolCurve(b.at)
            if c then
                local ok, col = pcall(UnitPowerPercent, "player", 0, true, c)
                drew = ok and paint(b.pieces, col) or false
            end
            local sw = b.cd and not b.cd.wait and RD.SwipeCurve(b.at)   -- a cooling disc keeps its own colour
            if drew and sw then
                local okS, scol = pcall(UnitPowerPercent, "player", 0, true, sw)
                swipeTo(b.cd, okS and scol or nil)
            end
        end
        b.face:SetAlpha(drew and 1 or 0)
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
    if not RD.CROSSHAIRS then
        -- OFF (Arn, 8 Nov, after trying them: "no crosshairs" - "take them off"); kept behind RD.CROSSHAIRS
        for _, sp in ipairs(RD.spokes or {}) do
            for _, c in ipairs({ sp.cross, sp.bogeyCross, sp.totCross }) do if c then c:SetAlpha(0) end end
        end
        return false
    end
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
--- A bogey seen or not, set ON ITS LINES (their colour's alpha) as well as its face (8 Nov 2026, Arn's screenshot, out of a
--- fight: four red triangles and a green one, nothing casting - the face's frame alpha alone did not hide them in the
--- client, while the heal pips, hidden by their colour's alpha, did). The sweep follows.
local function bogeyAlpha(k, a, col)
    col = col or RD.COL.bogey
    for _, l in ipairs(k.lines or {}) do l:SetVertexColor(col[1], col[2], col[3], a) end
    k.face:SetAlpha(a)
    if k.cd and k.cd.SetAlpha then k.cd:SetAlpha(a) end
end
RD.BogeyAlpha = bogeyAlpha

local function paintContact(sp, lit)
    local k = sp.bogey
    local col = lit and RD.COL.bogey or RD.CONTACT
    if lit then bogeyAlpha(k, 1, col) return true end
    bogeyAlpha(k, 0, col)
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
    local anyCast = false
    -- asked only while the chaff could light (armed, knob on, in a fight): lean when it cannot
    local wantChaff = RD.chaff and RD.chaff.macro and (RD.inFight or combat()) and not RD.KnobOff("chaff") or false
    for _, sp in ipairs(RD.spokes or {}) do
        if sp.unit and sp.tok and sp.slot and sp.slot.rb then
            -- red only when you have an interrupt to answer it with; the quiet pip shows either way
            -- nobody there is never casting (a duration question about an empty token is not trusted to say nil)
            local okE, there = pcall(UnitExists, sp.tok)
            there = okE and there
            if NS.Secret and NS.Secret(there) then there = true end
            local casting = false
            if there and (sp.kick or wantChaff) and FG and FG.Casting then casting = FG.Casting(sp.tok) end
            -- the chaff answers any hostile cast on the radar, interrupt or not (Arn: "it needs no target")
            if casting and wantChaff and not anyCast and UnitCanAttack then
                local okH, hostile = pcall(UnitCanAttack, "player", sp.tok)
                if okH and (hostile == true or (NS.Secret and NS.Secret(hostile))) then anyCast = true end
            end
            local lit = casting and sp.kick and true or false
            paintContact(sp, lit)
        else
            bogeyAlpha(sp.bogey, 0)
        end
    end
    RD.anyCast = anyCast
    RD.PaintChaff(anyCast)
end

-- THE CLICK'S WORD (Arn, 9 Nov: "LOS for line of sight, range for out of range, red letter under the teammate ... only
-- when i click them ... like the bis grid in normal view"). No standing range mark any more (the red rim dashes asked
-- the client about every spoke on every look): a heal that FAILS on the pip under the mouse flashes why, under it.
local clickWords
function RD.ClickWords()
    if clickWords then return clickWords end
    clickWords = {}
    local los = NS.FG and NS.FG.FailWords and NS.FG.FailWords() or { ["Target not in line of sight"] = "LOS" }
    for k, v in pairs(los) do clickWords[k] = v end
    -- the client's own out-of-range strings (any language), with the English as a net
    for _, s in ipairs({ "Out of range.", "Out of range", _G.SPELL_FAILED_OUT_OF_RANGE, _G.ERR_OUT_OF_RANGE,
                         _G.ERR_SPELL_OUT_OF_RANGE }) do
        if type(s) == "string" and s ~= "" and not (NS.Secret and NS.Secret(s)) then clickWords[s] = "RANGE" end
    end
    return clickWords
end

--- A failed click: the word under the pip under the mouse, fading by itself. The grid's switch (`flash`) turns it off
--- here too. Answers the word, or nil.
function RD.HeardError(msg)
    local d = NS.DB()
    if d.flash == false then return nil end
    if type(msg) ~= "string" or (NS.Secret and NS.Secret(msg)) then return nil end
    local word = RD.ClickWords()[msg]
    local sp = RD.over
    if not (word and sp and sp.los and sp.unit) then return nil end
    sp.los.word:SetText(word)
    sp.los:SetAlpha(1)
    if sp.losFade then sp.losFade:Stop() sp.losFade:Play() end
    RD.lastLos = sp.i
    return word
end

-- ------------------------------------------------------------------ the fuel gauge (handed untouched, never read)

--- nil, asked without testing a secret (a secret refuses even `== nil`): a secret is never nil.
local function isNil(v)
    if NS.Secret and NS.Secret(v) then return false end
    return v == nil
end

--- Hand a unit's pair of numbers to bars, untouched: 0..max, then the value. false when the client refused.
local function handTo(bars, getMax, getNow, unit, kind)
    local okM, mx = pcall(getMax, unit, kind)
    local okV, v = pcall(getNow, unit, kind)
    if not (okM and okV) then return false end
    for _, s in ipairs(bars) do
        pcall(s.SetMinMaxValues, s, 0, mx)
        pcall(s.SetValue, s, v)
    end
    return true
end

--- Your fuel: your mana on the tape and on the BINGO ruler, as the client gives it.
function RD.PaintMana()
    local g = RD.gauge
    if not (g and UnitPower and UnitPowerMax) then return false end
    -- the readout's number: the client writes your mana % into it (a secret is handed on, never read)
    local num = g.readout and g.readout.num
    if num and UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
        if not pcall(function() num:SetFormattedText("%d", UnitPowerPercent("player", 0, true, CurveConstants.ScaleTo100)) end) then
            num:SetText("")
        end
    end
    return handTo({ g.mana, g.ruler }, UnitPowerMax, UnitPower, "player", 0)
end

--- WHOSE HEALTH THE TAPE RACES: the boss (boss1) while the client has one, else your target, hostile or not decided by
--- the client (a secret "hostile?" stays the client's: RD.fuelHostile goes to SetAlphaFromBoolean). nil: nothing to race.
--- Asked when the target or the encounter changes, never per health tick.
function RD.PickFuel()
    RD.fuelUnit, RD.fuelHostile = nil, nil
    local okB, b = pcall(UnitExists, "boss1")
    if okB and plain(b) == true then RD.fuelUnit, RD.fuelHostile = "boss1", true return "boss1" end
    local okT, t = pcall(UnitExists, "target")
    if not okT then return nil end
    if not (NS.Secret and NS.Secret(t)) and t ~= true then return nil end
    local okH, h = pcall(UnitCanAttack, "player", "target")
    if not okH or isNil(h) then return nil end
    RD.fuelUnit, RD.fuelHostile = "target", h
    return "target"
end

--- The boss's side of the tape: its health handed to the red bar and the hot copy; the boss layer's alpha says whether
--- there is one. Out of a fight with no boss: nothing, the tape is calm (Arn's brief).
function RD.PaintBoss()
    local g = RD.gauge
    if not g then return nil end
    local unit, h = RD.fuelUnit, RD.fuelHostile
    local show = unit and (unit == "boss1" or RD.inFight or combat())
    if not show then g.bossLayer:SetAlpha(0) return nil end
    handTo({ g.boss, g.hot }, UnitHealthMax, UnitHealth, unit)
    if NS.Secret and NS.Secret(h) then
        if not pcall(function() g.bossLayer:SetAlphaFromBoolean(h, 1, 0) end) then g.bossLayer:SetAlpha(0) end
        return "secret"
    end
    g.bossLayer:SetAlpha(h == true and 1 or 0)
    return h == true
end

--- GENERATING FUEL: the cyan chevron at the tape's foot, in a fight only. Lit while you are out of the five second rule
--- (Regen.lua's own clock - your own casts, plain); inside it, dimmed to the share you keep while casting (the pair
--- Regen.lua remembered out of a fight; nothing asked now). Out of a fight: nothing.
function RD.PaintRegen()
    local g, FR = RD.gauge, NS.FR
    if not g then return nil end
    local fight = RD.inFight or combat()
    -- the readout: 100% out of a fight; in one, the header's own number (your while-casting share inside the five
    -- seconds, 100% once they are up, "?" when the client never said)
    -- THE RAMJET (Arn, 8 Nov: "a fighter pilot able to lay off the thruster for 5 seconds and his ram jet kicks in to
    -- regen his fuel"): the clock is read ONCE - the dashes count it down, the chevron lights when it is out
    local left = (fight and FR and FR.Left) and FR.Left() or 0
    if g.regen then g.regen:SetText((left > 0 and FR.Text) and FR.Text(true) or "100%") end
    RD.PaintFSR(left)
    if not fight or not (FR and FR.Left) then g.chev:SetAlpha(0) return 0 end
    local a = 1
    if left > 0 then
        local k = FR.known
        a = (k and type(k.base) == "number" and k.base > 0 and type(k.casting) == "number") and (k.casting / k.base) or 0
        a = math.max(0, math.min(a, 1))
    end
    g.chev:SetAlpha(a)
    return a
end

--- The five segments: one lit per second the rule still holds (a part-second counts), spent ones dim; nothing left =
--- hidden. `left` = Regen.lua's own clock (plain - your own casts). Answers how many are lit.
function RD.PaintFSR(left)
    local g = RD.gauge
    if not (g and g.fsr) then return nil end
    if type(left) ~= "number" or left <= 0 then g.fsr:SetAlpha(0) return 0 end
    local lit = math.min(RD.FSR.n, math.ceil(left))
    for k, t in ipairs(g.fsrSegs) do t:SetAlpha(k <= lit and 1 or RD.FSR.spent) end
    g.fsr:SetAlpha(1)
    return lit
end

function RD.PaintFuel()
    RD.PaintMana()
    RD.PaintBoss()
    RD.PaintRegen()
end

--- What the tape says, in words, under the mouse only.
function RD.FuelTip()
    local FR = NS.FR
    local who = RD.fuelUnit == "boss1" and "the boss" or (RD.fuelUnit == "target" and "your target, when it is hostile")
                or "nothing - no boss, no hostile target"
    return {
        "The bright bar: your mana, filling left to right.  Red past it: the boss's health you are behind by.  Magenta mark: the boss.",
        ("Hot pulsing band: BINGO - the boss more than %d%% ahead of your mana.  Drink, potion, Mana Tide (the column)."):format(RD.BINGO * 100),
        "RAMJET, at the right end: the % is your mana regen now (100% out of a fight).  The five dashes: seconds left of the five second rule - lay off the throttle (hold your casts) till they are gone and the ramjet kicks in, 100%.  The cyan chevron: the ramjet running (dim: only your while-casting share).",
        "Racing: " .. who .. ".  " .. ((FR and FR.Text) and FR.Text() or ""),
    }
end

--- THE SWEEPS, BATCHED (SPELL_UPDATE_COOLDOWN, a layout): ONE duration object for the GCD - spell 61304, else the radar
--- heal's own cooldown, which carries it - handed untouched to every GCD sweep in one loop; Mana Tide its own spell's
--- object; the potion its item cooldown (plain start + duration, handed on as given). Answers how many were fed.
function RD.Sweeps()
    local get = C_Spell and C_Spell.GetSpellCooldownDuration
    if not get then return 0 end
    local ok, gcd = pcall(get, RD.GCD)
    if not ok or isNil(gcd) then
        local h = RD.heal and (RD.heal.cast or RD.heal.name)
        ok, gcd = false, nil
        if h then ok, gcd = pcall(get, h) end
    end
    local n = 0
    if ok and not isNil(gcd) then
        for _, cd in ipairs(RD.sweeps) do
            -- a slot with nobody in it (cd.active false, set by RD.Arm) runs no sweep at all
            if cd.active ~= false and pcall(cd.SetCooldownFromDurationObject, cd, gcd) then n = n + 1 end
        end
    end
    -- Mana Tide and the potion: their cooling discs run on our own clock (RD.PaintWaits) - never the client's object,
    -- which carries the GCD; out of a fight the client's plain answer re-seeds the clock first
    RD.SeedCooldowns()
    return n + RD.PaintWaits()
end

--- The interrupt's sweep on every bogey (SPELL_UPDATE_COOLDOWN, a layout): your own spell's duration object, handed
--- untouched to each sweep. false when you have no interrupt or the client will not say.
function RD.KickCooldown()
    local FG = NS.FG
    local name = FG and FG.KickSpell and FG.KickSpell()
    local get = C_Spell and C_Spell.GetSpellCooldownDuration
    if not (name and get) then return false end
    local ok, dur = pcall(get, name)
    if not ok then return false end
    for _, sp in ipairs(RD.spokes or {}) do
        local cd = sp.bogey and sp.bogey.cd
        if cd and cd.SetCooldownFromDurationObject then pcall(cd.SetCooldownFromDurationObject, cd, dur) end
    end
    return true
end

--- THE SHIELD, ASKED DIRECTLY (8 Nov 2026, Arn: "water shield missing again" - the pip lit only when the client's aura
--- container took its button away, and when that hook was missed it never lit). The buff reminder's own question,
--- FS.Present (by spell id, the client's readable answer): on you = dark, gone = lit. When the client will not say
--- (nil, inside the lockdown) the container's hooks decide, as before.
function RD.PaintShield()
    local b = RD.shield
    if not b then return nil end
    if not b.shieldName then
        if b.breath and b.breath.Stop then b.breath:Stop() end
        b.face:SetAlpha(0)
        return nil
    end
    if b.breath and b.breath.IsPlaying and not b.breath:IsPlaying() then b.breath:Play() end
    -- the red is ALWAYS under the client's cover (armShield): it never decides anything itself, so nothing here can
    -- leave it dark while the shield is gone - the fight-proof part. The question is only kept for the suite and for
    -- /bish alpha radar, never to hide the red.
    b.face:SetAlpha(1)
    local FS = NS.FS
    if not (FS and FS.Present) then return nil end
    local ok, present = pcall(FS.Present, b.shieldName)
    if not ok then return nil end
    return present
end

function RD.Paint()
    if not RD.frame then return end
    for _, sp in ipairs(RD.spokes or {}) do RD.PaintHeal(sp) RD.PaintPet(sp) end
    RD.PaintShield()
    RD.PaintQuiet()
    RD.PaintFuel()
    RD.PaintCross()
    RD.KickCooldown()
    RD.Sweeps()
    RD.Look()
end

-- ------------------------------------------------------------------ on and off

local function startTicker()
    if RD.ticker or not (C_Timer and C_Timer.NewTicker) then return end
    local n = 0
    RD.ticker = C_Timer.NewTicker(RD.TICK, function()
        if not RD.Active() then return end
        RD.Look()
        RD.PaintRegen()                     -- the five second rule runs out on a clock, not an event
        -- the reserve tank opens on a clock too (a cooldown running out): repainted only when its gate turns
        if RD.reserve and RD.reserve.macro then
            local open = RD.ReserveOpen(RD.inFight or combat())
            if open ~= RD.reserveWas then RD.reserveWas = open RD.PaintQuiet() end
        end
        -- the food goes due on BiS Tools' own clock (Well Fed running low): asked again every RD.FOOD_EVERY ticks, out
        -- of a fight - one API question, and a re-arm only when the answer changed
        n = n + 1
        if n >= RD.FOOD_EVERY and not combat() and RD.rations then
            n = 0
            local want = RD.FoodWanted()
            if want ~= RD.rations.item then armUse(RD.rations, want) RD.PaintQuiet() end
            RD.PaintShield()                -- and the shield, in case an aura change went unheard
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
    elseif word == "knob" then
        -- `knob <tide|potion|reserve|drink|chaff> on|off` - the same switch as the knob on the rail
        local kind, state = arg:lower():match("^(%a+)%s*(%a*)$")
        local known = { tide = true, potion = true, reserve = true, drink = true, chaff = true }
        if kind and known[kind] and (state == "on" or state == "off") then
            RD.SetKnob(kind, state == "off")
        end
        local list = {}
        for _, k in ipairs({ "tide", "potion", "reserve", "drink", "chaff" }) do
            list[#list + 1] = k .. (RD.KnobOff(k) and " |cffff3a4doff|r" or " on")
        end
        P("radar knobs: %s.  |cff968ead/bish alpha radar knob <name> on|off|r", table.concat(list, ", "))
    else
        local h = RD.heal or RD.Heal()
        P("radar: heal %s.  |cff968ead/bish alpha radar heal <spell> | scale <50-200> | center|r", h and h.cast or "none")
        -- THE FUEL GAUGE AND THE MANA COLUMN, SAID PLAINLY: what the tape races, and where each tool lights
        local function tool(b, name)
            if not (b and b.macro) then return name .. " none" end
            return ("%s %s%%%s"):format(name, math.floor((b.at or 0) * 100 + 0.5), b.guess and " (guess)" or "")
        end
        P("radar fuel: racing %s.  lights at: %s, %s, %s", RD.fuelUnit or "nothing", tool(RD.tide, "tide"),
          tool(RD.potion, "potion"), tool(RD.fuel, "drink"))
        -- THE SHIELD PIP, SAID PLAINLY (Arn, 8 Nov: "no water shield icon"): what it watches, whether the client took the
        -- marker, and what it last handed over - so the next screenshot says which part is missing
        local b, FA = RD.shield, NS.FA
        local present = b and b.shieldName and NS.FS and NS.FS.Present and select(2, pcall(NS.FS.Present, b.shieldName))
        P("radar shield: %s - markers %s, slot %s, button %s, cover %s, on you now: %s%s",
          b and b.shieldName or "none trained (or not your class)",
          (FA and FA.Available and FA.Available()) and "yes" or ("no (" .. tostring(FA and FA.refused) .. ")"),
          (b and b.slot) and "placed" or "none", (b and b.handed) and "handed over" or "not yet",
          (b and b.cover) and "on" or "none",
          present == true and "yes" or (present == false and "no" or "the client will not say"),
          (FA and FA.initRefused) and ("  |cfff08cb0refused: " .. tostring(FA.initRefused) .. "|r") or "")
    end
end

-- ------------------------------------------------------------------ events

local ev = CreateFrame("Frame")
RD.events = ev
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE",
                     "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_AURA", "SPELLS_CHANGED",
                     "BAG_UPDATE_DELAYED", "UI_ERROR_MESSAGE", "PLAYER_TARGET_CHANGED", "UNIT_TARGET",
                     "PLAYER_ROLES_ASSIGNED", "SPELL_UPDATE_COOLDOWN", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "UNIT_MAXPOWER",
                     "PLAYER_LEVEL_UP", "UNIT_PET" }) do
    pcall(ev.RegisterEvent, ev, e)
end
-- your own casts only (the reserve tank's clock): the client filters to you, so a raid's casts never reach us
if ev.RegisterUnitEvent then pcall(ev.RegisterUnitEvent, ev, "UNIT_SPELLCAST_SUCCEEDED", "player") end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "PLAYER_LOGIN" then RD.Apply() return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local kind = RD.OnCast(a1, a3)
        if kind and RD.Active() then RD.PaintQuiet() end
        if kind and NS.CamShot then NS.CamShot(kind) end   -- the test camera (TestCam.lua), when armed
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- a fight: the drag ends first (before the lockdown takes the mouse), then everything goes quiet
        if RD.frame then endDrag(RD.frame) end
        RD.inFight = true                  -- the lockdown starts just after this event: the paints ask this too
        if RD.Active() then RD.PaintQuiet() RD.PickFuel() RD.PaintFuel() end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        RD.inFight = nil
        if RD.pending then RD.Apply() if RD.Active() then RD.Arm() end
        elseif RD.Active() then
            RD.ArmTools()                  -- the numbers are plain again: each tool re-learns where it lights
            RD.PaintQuiet() RD.PaintShield() RD.PickFuel() RD.PaintFuel()
        end
        return
    end
    if not RD.Active() then return end
    if event == "GROUP_ROSTER_UPDATE" or event == "SPELLS_CHANGED" or event == "BAG_UPDATE_DELAYED"
       or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_LEVEL_UP" then   -- a role set: the pip's sign follows
        RD.Arm()                           -- in a fight it only marks RD.pending
    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if NS.Secret and NS.Secret(a1) then return end
        for _, sp in ipairs(RD.spokes) do
            if sp.unit == a1 then RD.PaintHeal(sp) elseif sp.petUnit == a1 then RD.PaintPet(sp) end
        end
        if a1 ~= nil and a1 == RD.fuelUnit then RD.PaintBoss() end
    elseif event == "UNIT_PET" then
        -- an owner called or sent away a pet: the client's watch shows or hides the pip; we repaint its colour
        if NS.Secret and NS.Secret(a1) then return end
        for _, sp in ipairs(RD.spokes) do if sp.unit == a1 then RD.PaintPet(sp) end end
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        if a1 == "player" then
            -- a bigger or smaller pool between pulls (gear, a buff): the tools re-learn where they light
            if event == "UNIT_MAXPOWER" and not combat() then RD.ArmTools() end
            RD.PaintMana() RD.PaintQuiet()
        end
    elseif event == "UNIT_AURA" then
        if a1 == "player" then RD.PaintShield() end
        if a1 == "player" and not combat() then
            local want = RD.FoodWanted()
            if want ~= RD.rations.item then armUse(RD.rations, want) RD.PaintQuiet() end
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        RD.KickCooldown()
        RD.Sweeps()
    elseif event == "UNIT_TARGET" then
        if a1 == "target" then RD.PaintCross() end      -- your target picked someone else: the amber mark moves
    elseif event == "PLAYER_TARGET_CHANGED" then
        RD.PaintCross()
        RD.Look()
        RD.PickFuel() RD.PaintBoss()
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        RD.PickFuel() RD.PaintBoss()       -- a boss came (or went): the tape races it
    elseif event == "UI_ERROR_MESSAGE" then
        -- a heal that failed on line of sight or range: the word under the pip under the mouse
        RD.HeardError(a2)
    end
end)

NS.AlphaFeature{ key = RD.KEY, name = "the radar",
                 desc = "the grid as a quiet radar: only what needs a click lights up (in a fight everything else is invisible)",
                 apply = function() RD.Apply() end, cmd = function(rest) return RD.Command(rest) end }
