-- =========================================================================
-- BiS Healing -- pyramid raid frames for a slow-cast healer
--
-- The apex is your Earth Shield target. Below it, rows of players ordered by
-- who actually eats damage -- scored from the combat log, weighted so this
-- raid matters more than history, and biased toward people who take damage
-- CONSISTENTLY rather than someone who ate one spike and died.
--
-- Why it reorders only between pulls: moving or resizing a secure unit frame
-- is blocked in combat (SetPoint / SetSize / Show / Hide all fail once
-- PLAYER_REGEN_DISABLED fires). So layout is decided out of combat, and during
-- the fight only the visuals change -- bar length, color, glow -- which is
-- unrestricted. Nothing here tries to pick your target for you: you hover or
-- click, your hand supplies the input.
--
-- Landmines carried over from BiS Rez (do not "fix" these):
--   * secure attrs MUST use "*type1"/"*spell1" (bare names silently no-op)
--   * RegisterForClicks needs "AnyDown"
--   * SetColorTexture, not SetTexture(r,g,b,a)
--   * unknown events must be registered through pcall or the file aborts
--
-- Slash: /bish            toggle the pyramid
--        /bish score      dump the current ranking and why
--        /bish reorder    force a reorder now (out of combat)
--        /bish reset      wipe learned history
--        /bish lock       lock / unlock dragging
--        /bish wheel      mouse-wheel heals on/off (see the bindings section)
-- =========================================================================

-- Every file the TOC loads is handed (addonName, addonTable) as `...`, and that
-- table is the ONLY thing the files share. A `local` does not cross a chunk
-- boundary: two files that both say `local frames = {}` get two different empty
-- tables and neither ever sees the other's. So anything more than one file needs
-- lives on NS, and anything only one file needs stays a local, where it is
-- cheaper and cannot be reached by accident.
--
-- Nil-safe on purpose: `luac -p` and the headless harness both run this chunk
-- with no varargs, and a nil NS here would be a nil-index crash 4000 lines down
-- rather than an obvious one here.
local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}
local GetAddOnMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local VERSION = (GetAddOnMeta and GetAddOnMeta("BiSHealing", "Version")) or "?"
              -- read from the TOC: a hardcoded copy silently drifts out of date

local EARTH_SHIELD = "Earth Shield"
local CHAIN_HEAL   = "Chain Heal"
local GIFT         = "Gift of the Naaru"   -- instant HoT, ~1085 over 15s, 3min CD

-- ------------------------------------------------- losing the heal race --
-- Being sniped is not bad luck, it is missing information. LibHealComm only
-- sees healers who run a HealComm addon; everyone else is invisible to it, so
-- their cast lands, your 2.5s Chain Heal arrives into a full bar, and the frame
-- never warned you because as far as it knew nothing was inbound.
--
-- The client itself knows better, and has all along:
--   UnitGetIncomingHeals(unit)          -- everything inbound, addon or not
--   UnitGetIncomingHeals(unit, healer)  -- ...broken down per caster
--   UnitCastingInfo(healer)             -- when that caster's spell LANDS
-- Together those answer the only question that matters in a race: does someone
-- else's heal land before mine, and is it big enough that mine is wasted.
-- UNIT_HEAL_PREDICTION fires whenever any of it changes, so none of it needs
-- polling. Table here, methods further down where the roster helpers exist.
local SNIPE = {
    healers = {},     -- unit tokens that can heal
    cache   = {},     -- unit -> { at =, n =, lands =, mineFirst =, who = }
    TTL     = 0.25,   -- seconds; the event refreshes it anyway
    CLASSES = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true },
}

-- Heal sizes: what a rank is really worth on this gear (see the long note above
-- BuildHealOptions). Table up here, methods down there.
local HEALSZ = {
    CAST = { [CHAIN_HEAL] = 2.5, ["Healing Wave"] = 3.0,
             ["Lesser Healing Wave"] = 1.5 },
    MIN_SAMPLES = 4,      -- casts of a rank before its measurement is trusted
    MAX_OVER = 0.5,       -- drop a sample if over half of it was overheal
    MAX_VS_EST = 2.0,     -- and never believe a measurement more than 2x the maths
    EMA = 0.25,           -- how fast the measurement follows a gear change
}

-- Mouse-wheel emergency heal, and everything that hangs off it. All of it lives
-- on ONE table on purpose: this file is a single Lua chunk and Lua 5.1 allows
-- only 200 locals in one -- the last free slots are worth more than the tiny
-- convenience of a dozen bare names. Fields, not upvalues, from here on.
local WHEEL = {
    HW      = "Healing Wave",        -- the single-target panic button
    LHW     = "Lesser Healing Wave", -- the fast one, on scroll DOWN
    NS      = "Nature's Swiftness",  -- 3min CD, next nature cast is instant
    down    = nil,                   -- "Healing Wave(Rank N-2)"  -- scroll up
    max     = nil,                   -- "Healing Wave(Rank N)"    -- shift scroll up
    lDown   = nil,                   -- "Lesser Healing Wave(Rank N-2)" -- scroll dn
    lMax    = nil,                   -- "Lesser Healing Wave(Rank N)" -- shift dn
    maxHeal = 0,                     -- tooltip size of max-rank HW
    known   = nil,                   -- is Nature's Swiftness trained?
    pending = false,                 -- rebind asked for during combat
}

-- A Gift candidate is an ISOLATED target that took a real hit but has since
-- settled: healing them with Chain Heal would waste a hard cast on one person,
-- while Gift's HoT tops them over 15s and frees the chain for a clumped group.
local GIFT_RULE = {}   -- folded from 3 chunk locals (Lua 5.1 budget)
GIFT_RULE.hotTotal   = 1085   -- so we don't flag someone a full HoT would overheal
GIFT_RULE.minDeficit = 700    -- must be down enough for the HoT to mostly land
GIFT_RULE.maxBounce  = 1.4    -- low bounce avg = isolated, not worth a chain

-- Scoring knobs -----------------------------------------------------------
local SCORE = {}   -- folded from 6 chunk locals (Lua 5.1 budget)
SCORE.keep   = 40     -- encounters remembered per player
SCORE.decay = 0.88  -- weight of each older encounter (0.88^n)
SCORE.consistencyW  = 0.45   -- how much "shows up high often" beats raw total
SCORE.bounceW       = 0.20   -- how much Chain Heal bounce quality nudges rank
SCORE.dpsW          = 0.08   -- small: boss-DPS only breaks ties between people
                              -- taking similar damage. Healers do ~0 and are
                              -- unaffected; this never outweighs actual damage taken
SCORE.minFight = 8      -- ignore fights shorter than this (trash pulls)

-- Layout knobs ------------------------------------------------------------
-- The pyramid proper is only four rows deep. Everyone past that is overflow:
-- squeezed into one row, or two if one would make them unreadably thin. In a
-- 25-man that is sixteen people who are, by definition, the ones you are least
-- likely to Chain Heal -- they need to be visible, not big.
-- pyramid: apex, pair, then 6 half-width. Anything past row 3 REPEATS row 3
-- (6 per row at half width) for as many rows as the roster needs -- consistent
-- squares all the way down instead of an ever-smaller quarter row + overflow.
local LAYOUT = {}   -- folded from 4 chunk locals (Lua 5.1 budget)
LAYOUT.rowSizes   = { 1, 2, 6 }
LAYOUT.rowScale   = { 1.0, 1.0, 0.5 }
LAYOUT.tailCount  = 6      -- per-row count for every row after the defined ones
LAYOUT.tailScale  = 0.5    -- and their width scale (matches row 3)
local FRAME_W, FRAME_H = 84, 34
local PAD = 3


local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff44dd88BiS Healing|r: " .. msg)
end

-- ------------------------------------------------------------------ state --

local playerGUID
local frames = {}          -- pool of secure unit buttons
local order = {}           -- unit tokens, apex first -- rebuilt out of combat
local esTarget = nil       -- GUID of current Earth Shield target
local inFight = false
local fightStart = 0

-- RPM gauge: a rolling picture of how hard I'm working the mana bar and how much
-- of that healing is landing versus overhealing. His philosophy: burning mana is
-- GOOD -- mana tide and potions refill it -- so the sweet spot is high spend with
-- low overheal, and the failure mode is cruising and ending the fight at 80%.
-- So the gauge redlines on purpose: center/hot = spending hard, heals landing.
local rpmWindow = {}       -- array of { t =, mana =, raw =, over = } per own heal
local RPM_WINDOW = 10.0    -- seconds of rolling history
local lastManaSample = nil -- { t =, mana = } to catch regen between casts
local rpmSmoothed = 0      -- eased reading, so the bar glides instead of snapping
local rpmState = "cruising"-- current label, changed only past a margin (hysteresis)
local spendWindow = {}     -- array of { t =, amt = } mana DROPS over the window
local fightDmg = {}        -- GUID -> damage taken this fight
local fightDone = {}       -- GUID -> damage DEALT to enemies this fight (for the
                           -- DPS tiebreaker: when two players eat similar damage,
                           -- the one contributing more to the kill ranks slightly
                           -- higher). Healers do no damage and are unaffected.
local pendingReorder = false
-- How many rows the last Relayout actually placed. The demo caption hangs
-- BELOW the pyramid, and the pyramid's depth depends on roster size -- solo it
-- is one row, in a 25-man it is six. Anchoring the caption to the anchor frame
-- instead put it straight through row 1 whenever the group was small.
local layoutRows = 1

-- The comm table moved to Core/comm.lua, which the TOC loads BEFORE this file.
-- Picking it up as a local here means every COMM.* line below reads exactly as
-- it did when this was one file -- and, more to the point, the load-time
-- assignments further down (COMM.Charges, COMM.Unit) still land on the same
-- table the peers are talking through.
local COMM = NS.COMM

-- ------------------------------------- the other shaman's Chain Heal ------
-- Two shamans chain-healing the same clump is the classic wasted GCD: both
-- casts land, one of them was free healing. Knowing where their chain is
-- pointed a second before it lands is enough to send yours somewhere else.
--
-- Three sources, best first, all writing to the same table:
--   1. LibHealComm. Any shaman running a HealComm-aware addon (VuhDo, HealBot,
--      Grid) broadcasts their cast as it STARTS, with every bounce target. This
--      is the one that arrives in time to change your mind.
--   2. A BiSHealing peer. We tell each other directly the moment the cast is
--      sent, so two of these addons do not need a third to talk through.
--   3. The combat log, as a floor. Always available, but it fires when the heal
--      LANDS -- too late to redirect, still useful as "that clump is handled".
COMM.chain = {}          -- target GUID -> { who =, expires = }
COMM.CHAIN_HOLD = 2.0    -- seconds a mark lingers once the cast lands

-- A chain touches up to three people, and those three are not equal news.
-- The PRIMARY is where they aimed -- that target is being properly healed. The
-- BOUNCES are halved and halved again, so a bounce landing on somebody with a
-- real hole has barely dented it, and you may well still need to heal them
-- yourself. Marking all three the same way said "these three are handled",
-- which is only a third true and is exactly what made the marker look wrong.
function COMM.MarkChain(guid, who, duration, primary)
    if not guid or guid == playerGUID then return end
    local prev = COMM.chain[guid]
    -- never let a bounce downgrade a mark that a primary already claimed
    if prev and prev.primary and not primary and GetTime() <= prev.expires then
        prev.expires = math.max(prev.expires, GetTime() + (duration or COMM.CHAIN_HOLD))
        return
    end
    COMM.chain[guid] = { who = who, primary = primary and true or false,
                         expires = GetTime() + (duration or COMM.CHAIN_HOLD) }
end

-- returns: caster name, and whether this frame is the chain's primary target
function COMM.ChainOn(guid)
    local e = guid and COMM.chain[guid]
    if not e then return nil end
    if GetTime() > e.expires then COMM.chain[guid] = nil; return nil end
    return e.who, e.primary
end

-- Grouping foreign chain heals out of the combat log. Each bounce arrives as
-- its own SPELL_HEAL, so without this every jump looked like a fresh cast at a
-- new primary -- three solid marks for one chain.
COMM.foreign = {}
function COMM.ForeignChainRole(casterGUID)
    local now = GetTime()
    local c = COMM.foreign[casterGUID]
    if c and (now - c.at) <= 1.25 then      -- same window the player's own chain uses
        c.at = now
        return false                         -- a bounce of the cast already seen
    end
    COMM.foreign[casterGUID] = { at = now }
    return true                              -- first heal of a new cast: primary
end

-- Earth Shield stickiness. A shield that is already up and still has charges is
-- doing its job; re-recommending every tick just trains you to ignore the amber
-- corner. One table, not five locals -- this chunk is near Lua 5.1's 200-local
-- ceiling (see the WHEEL table for the same reason).
local ES_HOLD = {
    quiet  = 2,     -- charges left on MY shield at which the addon says nothing
    sticky = 1.5,   -- the current holder's edge when it IS time to re-shield
    margin = 1.35,  -- a challenger must beat the standing pick by this to take it
    stale  = 20,    -- seconds; no external hit in this long = not an ES target
    hit    = {},    -- guid -> GetTime() of the last hit from someone ELSE
}

-- rolling Chain Heal cast tracking: first heal is the primary target
local chCast = { guid = nil, at = 0, hits = 0, lastGUID = nil, crits = 0 }
local CH_WINDOW = 1.25     -- seconds; bounces land well inside this

-- Diagnostics. These exist to answer three open questions on live servers:
--   1. does the spellbook expose lower ranks (spellbook filter must be set to
--      "all ranks") -- /bish ranks
--   2. does Chain Heal really log one SPELL_HEAL per bounce -- /bish bounce
--   3. what is Earth Shield's per-charge internal cooldown -- /bish es
local verboseBounce = false
local rawES = false        -- dump every Earth Shield combat log event verbatim
-- One run per shielded target, keyed by target GUID -- there can be two
-- shamans shielding two different people, and only ever one shield per target.
-- Attribution split, confirmed on a live server:
--   SPELL_HEAL              -> src AND dst are the shielded player; the caster
--                              never appears, so the heal alone is anonymous
--   SPELL_AURA_REMOVED_DOSE -> src is the CASTER, dst is the target
-- Because a target can only carry one Earth Shield, every heal on that target
-- belongs to whoever the dose events name. That is what makes the other
-- shaman's shield measurable at all.
local esRuns = {}          -- guid -> run
local esLog  = {}          -- completed applications, newest first
local esCasterHeal = {}    -- caster name -> { n =, sum = }  average charge size

-- Health sampling, so people who have never been shielded can still be judged:
-- a charge landing on a full bar is wasted, so we need to know how deep each
-- candidate typically sits.
local hpSample = {}        -- name -> { n =, deficit =, hits =, combatTime = }

-- Rolling damage window per GUID, used to predict where someone WILL be when a
-- 2.5s cast lands. For a hard caster the health bar is a lagging indicator --
-- the damage rate is the thing that should start your cast.
local dmgWindow = {}       -- guid -> array of { t =, amt = }
local DMG_WINDOW = 5.0     -- seconds of history
-- Cast lead is how far ahead we predict. It is NOT fixed: when Bloodlust or a
-- haste trinket is up, Chain Heal lands in ~2.1s instead of ~2.5s, and the
-- prediction has to shrink to match or it overstates every hole. We read the
-- live cast time off the spell itself and add a small reaction/latency margin.
local CAST_LEAD  = 3.0             -- current value, recomputed below
local CAST_REACTION = 0.5          -- your reaction + travel time on top of cast
local CHAIN_CAST_BASE = 2.5        -- fallback before we've measured

-- Live Chain Heal cast time from the spell's own tooltip/API, which already
-- includes haste from buffs and trinkets.
local function ChainCastTime()
    local ct
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(CHAIN_HEAL)
        ct = info and info.castTime
    end
    if not ct and GetSpellInfo then
        ct = select(4, GetSpellInfo(CHAIN_HEAL))   -- castTime in ms
    end
    if ct and ct > 0 then return ct / 1000 end
    return CHAIN_CAST_BASE
end

local function RefreshCastLead()
    CAST_LEAD = ChainCastTime() + CAST_REACTION
    COMM.CastTime = COMM.CastTime or ChainCastTime
end

-- LibHealComm-4.0, if the Libs folder is present. This is what lets a slow
-- caster stop healing someone three instant-casters already have covered: it
-- reports heals other players have IN THE AIR, keyed by target, so they can be
-- subtracted from the predicted deficit before the bullseye picks a target.
-- Entirely optional -- absent, everything works, it just can't see inbound.
local HealComm = LibStub and LibStub("LibHealComm-4.0", true)
local healCommOn = HealComm ~= nil

-- Heal options, ascending by size: max and max-2 of each of the three spells.
-- Filled in from the spellbook at login, so the colour bands follow your gear.
local healOptions = {}     -- Chain Heal downrank + max, ascending
local esMaxCast = nil      -- "Earth Shield(Rank N)"
local esBaseCharge = 0     -- tooltip healing of ONE charge, before healing power
local esCandidateName = nil  -- best ES candidate, refreshed out of combat
local giftKnown = nil        -- does he actually have Gift of the Naaru? (resolved once)

-- Resolve whether the Gift spell is in the book. Called before binds and by the
-- badge; cheap after the first real answer.
local function ResolveGiftKnown()
    if giftKnown ~= nil then return giftKnown end
    if C_Spell and C_Spell.GetSpellInfo then
        giftKnown = C_Spell.GetSpellInfo(GIFT) ~= nil
    elseif GetSpellInfo then
        giftKnown = GetSpellInfo(GIFT) ~= nil
    else
        giftKnown = false
    end
    return giftKnown
end
-- Same question for Nature's Swiftness. Resto talent, so plenty of shamans do
-- not have it -- when it is absent the wheel binds quietly drop back to a plain
-- Healing Wave instead of printing errors at a spell he never trained.
function WHEEL.ResolveKnown()
    if WHEEL.known ~= nil then return WHEEL.known end
    if C_Spell and C_Spell.GetSpellInfo then
        WHEEL.known = C_Spell.GetSpellInfo(WHEEL.NS) ~= nil
    elseif GetSpellInfo then
        WHEEL.known = GetSpellInfo(WHEEL.NS) ~= nil
    else
        WHEEL.known = false
    end
    return WHEEL.known
end
local TargetProfile          -- defined with the ES planner, used up in Relayout
local chDownCast, chMaxCast = nil, nil
-- WHEEL.Ready and WHEEL.Pips are assigned lower down (with GiftReady and just
-- above UpdateBars). Table fields, so no forward-declaration trap: an early
-- caller reads nil rather than silently binding a second local.
-- forward refs: these are assigned where the functions are defined, but called
-- from handlers written earlier in the file. Declaring them late silently
-- creates a second, always-nil variable.
local ApplyBindsRef
local DrawBounce          -- bounce-line effect, defined lower, called above
local UpdateBounceLines
local Celebrate            -- 3-bounce firework, defined with the line layer
local FinishChain          -- repaints a completed chain's lines gold
local UpdateCornerReticles -- unified role-corner reticle (green/amber/orange)
-- Current mark holders. Declared UP HERE because Relayout clears them and
-- Relayout is defined long before the scoring section -- a `local` down there
-- would leave Relayout writing to a global of the same name while the real
-- upvalue never changed. Same trap that crashed rc6.
local bullTarget, bullScore = nil, 0     -- Chain Heal (green corners)
local esBullTarget = nil                 -- Earth Shield (amber corner + pips)
local giftBullTarget = nil               -- Gift of the Naaru (orange corner)
local ESCharges            -- (fwd-declared: ESStateOf calls it, defined below)
local GiftReady            -- Gift off cooldown? (forward-declared: the corner
                           -- reticle calls it, and it's defined further down)
local GiftActive           -- is my Gift HoT on a unit? (forward-declared, same reason)
local UpdateCastCounter    -- "X | Y" castable-heals readout
local UpdateRPM            -- mana-burn / overheal gauge
local RPMPaint             -- its painter (shared by the live and sim paths)
local UpdateSparks         -- its per-frame animator, same deal
local PULSE_CAP = 3        -- only the worst few pulse, or it is just noise

-- DEMO mode (rc30). The old simulator built a fake roster of invented players
-- with invented health, and every feature grew an "is this a sim frame" branch
-- to cope. That fork was not free: fake frames have no unit token, and the
-- corner reticle's guard assumed every frame had one, so it silently skipped
-- all of them -- the sim quietly lied about the exact feature it existed to
-- preview, for four release candidates.
--
-- So there is no fake roster any more. Demo mode runs on the REAL group and
-- only ever writes to TEXTURES -- corners, pips, lines, the gauge. It never
-- feeds invented numbers into scoring, targeting or bindings, so there is no
-- second code path that can drift out of step with the first. It cycles the
-- features one at a time with a caption saying which you are looking at.
local demo = { on = false, at = 0, step = 0, spot = 0 }
local DEMO_STEP = 4.0     -- seconds per feature
local DemoPaint           -- fwd ref: UpdateBars calls it, defined much later

-- ------------------------------------------------------------------- db --

-- Memoised. DB() walks a dozen default checks, and BullScore calls it once per
-- frame per tick -- 25 frames at 10Hz is 250 needless passes a second. The
-- identity check means /bish reset (which nils BiSHealingDB) still rebuilds.
local dbCache
local function DB()
    if dbCache and BiSHealingDB == dbCache then return dbCache end
    BiSHealingDB = BiSHealingDB or {}
    local db = BiSHealingDB
    db.players  = db.players  or {}   -- name -> { fights = {}, bounce = {n=,sum=} }
    db.healSeen = db.healSeen or {}   -- spellId -> { avg =, n = } measured cast size
    -- rc41: measurements taken before the overheal filter are inflated (a Chain
    -- Heal that lands 2.7k was banked at 4815). They cannot be corrected after
    -- the fact -- the overheal share was never stored -- so they are dropped and
    -- relearned, which takes about four casts.
    if db.healSchema ~= 2 then db.healSeen = {}; db.healSchema = 2 end
    db.locked   = db.locked   ~= false
    db.shown    = db.shown    ~= false
    db.pos      = db.pos
    -- feature toggles, all default ON; the settings panel flips these
    if db.bullseye     == nil then db.bullseye     = true end
    if db.pulse        == nil then db.pulse        = true end
    if db.bounceLines  == nil then db.bounceLines  = true end
    if db.goldChains   == nil then db.goldChains   = true end
    if db.celebrate    == nil then db.celebrate    = true end
    if db.incomingFill == nil then db.incomingFill = true end
    if db.castCounter  == nil then db.castCounter  = true end
    if db.esBadge      == nil then db.esBadge      = true end
    if db.esReticle    == nil then db.esReticle    = true end
    if db.corners      == nil then db.corners      = true end
    if db.trinkets     == nil then db.trinkets     = true end
    if db.giftBadge    == nil then db.giftBadge    = true end
    if db.rpm          == nil then db.rpm          = true end
    if db.pets         == nil then db.pets         = true end
    if db.wheel        == nil then db.wheel        = true end
    if db.wheelStrict  == nil then db.wheelStrict  = false end
    if db.nsPip        == nil then db.nsPip        = true end
    if db.plainBars    == nil then db.plainBars    = true end
    if db.critBrag     == nil then db.critBrag     = true end
    if db.healRace     == nil then db.healRace     = true end
    if db.totemRange   == nil then db.totemRange   = true end
    if db.dispel       == nil then db.dispel       = true end
    if db.fsr          == nil then db.fsr          = true end

    -- One-time history scrub. Up to rc34 the hit counts behind the Earth Shield
    -- plan counted self-inflicted damage (Life Tap, Hellfire), so a warlock read
    -- as the raid's most-hit player forever. The numbers already banked are
    -- poisoned in a way no new fight can dilute quickly, so the depth/hit
    -- history is dropped once. Encounter scores and Earth Shield charge logs are
    -- measured from real events and are kept.
    if db.esSchema ~= 2 then
        for _, rec in pairs(db.players) do
            rec.depth, rec.selfHits, rec.selfDmg = nil, nil, nil
        end
        db.esSchema = 2
    end
    dbCache = db
    return db
end

-- ONE table for every aura scan the addon does and its caches. Four chunk
-- locals used to sit here (two caches, two TTLs); they were folded onto this
-- table when the totem-reach and dispel scans arrived, because the file was at
-- 190 of Lua 5.1's 200 locals and two more scans would have been four more.
-- Declared this early because the demo painter reads AURAS.down long before
-- the scanners themselves are defined, and a local read above its own line is
-- a nil global -- the harness caught exactly that on the first run.
-- Aura scanning is the single most expensive thing this addon does, so every
-- reader here is cached: 25 frames at 10 Hz is 250 sweeps a second uncached.
local AURAS = {
    esCache   = {},  ES_TTL   = 0.3,   -- unit -> { at =, charges =, mine = }
    giftCache = {},  GIFT_TTL = 0.3,   -- unit -> { at =, on = }
    totemCache = {}, TOTEM_TTL = 1.0,  -- unit -> { at =, reach = }
    dispelCache = {}, DISPEL_TTL = 0.5,-- unit -> { at =, name =, kind = }
    down = {},                         -- buff names of my aura totems now down
}

-- Names, cut to fit. Realm suffix off first, then five CHARACTERS -- not five
-- bytes: an accented name is multi-byte in UTF-8 and a blind string.sub can cut
-- a character in half, which the client renders as a black box. Walk the lead
-- bytes instead (0x80..0xBF are continuation bytes and are never counted).
-- One table for the small presentation odds and ends (name length, bar colours,
-- the triple-crit brag), because this chunk is close to Lua 5.1's 200-local cap.
local UIX = {
    NAME_MAX  = 5,
    BAR_IDLE  = { 0.11, 0.11, 0.12, 1 },   -- black-ish: nothing to do here
    BAR_RED   = { 0.85, 0.15, 0.15, 1 },   -- a full downrank Chain Heal fits
    BAR_DEAD  = { 0.18, 0.16, 0.16, 0.95 },
    BAR_GREY  = { 0.35, 0.35, 0.35, 1 },   -- out of range
    PULSE_RED = { 1.00, 0.12, 0.10 },      -- flashing overlay: sustained damage
    PIP_MINE   = { 0.90, 0.72, 0.35, 1 },  -- Earth Shield charges: yours
    PIP_THEIRS = { 0.55, 0.55, 0.58, 0.8 },-- ...and the other shaman's
    CHAIN_IN   = { 0.20, 0.80, 0.85, 0.9 },-- another shaman's chain, inbound
    -- heal-race number, same palette as the bars: neutral grey when nothing is
    -- being taken from you, the bars' red when it is
    RACE_WIN    = { 0.55, 0.55, 0.58 },
    RACE_LOSE   = { 0.85, 0.15, 0.15 },
    RACE_UNSURE = { 0.85, 0.40, 0.30 },
    TOTEM_OUT   = { 0.62, 0.42, 0.95, 0.9 },-- right edge: my totem is not reaching him
    -- five-second rule: mana and the moment the last mana-costing cast landed
    fsr = { mana = nil, at = -100 },
    FSR = 5,
    bragAt    = 0,
    BRAG_GAP  = 15,                        -- seconds between brags, so it is a
                                           -- moment and not a chat log
    BRAG = "Oh Baby, a Triple Chain Heal Crit!",
}

local function ShortName(full)
    local s = (full or ""):match("^[^-]+") or ""
    local chars, i = 0, 1
    while i <= #s do
        local b = s:byte(i)
        if b < 128 or b >= 192 then
            chars = chars + 1
            if chars > (DB().nameLen or UIX.NAME_MAX) then return s:sub(1, i - 1) end
        end
        i = i + 1
    end
    return s
end

local function PlayerRec(name)
    local db = DB()
    db.players[name] = db.players[name] or { fights = {}, bounce = { n = 0, sum = 0 } }
    return db.players[name]
end

-- --------------------------------------------------------------- roster --

-- Players first, then their pets. Pets are returned as a second list so layout
-- can render them at half size in their own strip -- he wants party/hunter pets
-- as small clickable targets (they often sit between tank and melee, a good
-- Chain Heal bridge) without cluttering the player pyramid.
local function PetUnits()
    local pets = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local pu = "raidpet" .. i
            if UnitExists(pu) then pets[#pets + 1] = pu end
        end
    elseif IsInGroup() then
        if UnitExists("pet") then pets[#pets + 1] = "pet" end
        for i = 1, GetNumGroupMembers() - 1 do
            local pu = "partypet" .. i
            if UnitExists(pu) then pets[#pets + 1] = pu end
        end
    else
        if UnitExists("pet") then pets[#pets + 1] = "pet" end
    end
    return pets
end

local function RosterUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units[#units + 1] = "player"
        for i = 1, GetNumGroupMembers() - 1 do units[#units + 1] = "party" .. i end
    else
        units[#units + 1] = "player"
    end
    -- pets are just members of the raid as far as the pyramid cares: if a pet is
    -- genuinely the best Chain Heal target, it earns its spot like anyone else.
    if DB and DB().pets ~= false then
        for _, pu in ipairs(PetUnits()) do units[#units + 1] = pu end
    end
    return units
end


local function UnitKey(unit)
    local name, realm = UnitName(unit)
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- GUID -> unit lookup, rebuilt on roster change and at each pull. The combat
-- log handler runs hundreds of times a second in a 25-man fight, so it must
-- never walk the roster -- that was a real frame-rate problem, not a nitpick.
local guidMap = {}

local function RebuildGuidMap()
    wipe(guidMap)
    for _, u in ipairs(RosterUnits()) do
        local g = UnitGUID(u)
        if g then guidMap[g] = u end
    end
end

local function GuidToUnit(guid)
    return guidMap[guid]
end

-- -------------------------------------------------------------- scoring --
-- Two numbers per player, combined:
--   volume      -- decayed average damage taken per second of fight
--   consistency -- how often they finished a fight in the top third
-- Consistency is what keeps a one-time spike from owning the apex: dying to a
-- single Doom Fire gives one huge fight and nothing else, so it scores low.

local function Score(name)
    local rec = DB().players[name]
    if not rec or #rec.fights == 0 then return 0, 0, 0 end

    local wSum, dpsSum, topSum, doneSum = 0, 0, 0, 0
    -- fights[1] is the most recent
    for i, f in ipairs(rec.fights) do
        local w = SCORE.decay ^ (i - 1)
        wSum    = wSum + w
        dpsSum  = dpsSum + w * (f.dps or 0)
        topSum  = topSum + w * (f.top and 1 or 0)
        doneSum = doneSum + w * (f.done or 0)
    end
    if wSum == 0 then return 0, 0, 0, 0 end

    local volume      = dpsSum / wSum
    local consistency = topSum / wSum
    local dmgDone     = doneSum / wSum   -- avg boss-DPS, for the tiebreaker

    local bounce = 0
    if rec.bounce.n > 0 then bounce = rec.bounce.sum / rec.bounce.n end

    return volume, consistency, bounce, dmgDone
end

-- Rank everyone currently in the group. Returns array of {unit, name, score}.
local function RankRoster()
    local list, maxVol, maxBounce = {}, 0, 0

    local maxDone = 0
    for _, unit in ipairs(RosterUnits()) do
        if UnitExists(unit) then
            local name = UnitKey(unit)
            if name then
                local vol, cons, bounce, dmgDone = Score(name)
                list[#list + 1] = { unit = unit, name = name,
                                    vol = vol, cons = cons, bounce = bounce,
                                    dmgDone = dmgDone or 0 }
                if vol > maxVol then maxVol = vol end
                if bounce > maxBounce then maxBounce = bounce end
                if (dmgDone or 0) > maxDone then maxDone = dmgDone end
            end
        end
    end



    for _, e in ipairs(list) do
        local v = (maxVol > 0) and (e.vol / maxVol) or 0
        local b = (maxBounce > 0) and (e.bounce / maxBounce) or 0
        local d = (maxDone > 0) and (e.dmgDone / maxDone) or 0
        -- keep the weighted pieces so the out-of-combat tooltip can explain
        -- exactly why this person landed where they did in the pyramid
        e.cVol    = v * (1 - SCORE.consistencyW)
        e.cCons   = e.cons * SCORE.consistencyW
        e.cBounce = b * SCORE.bounceW
        e.cDps    = d * SCORE.dpsW          -- small tiebreaker toward boss damage
        e.score = e.cVol + e.cCons + e.cBounce + e.cDps
    end

    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return (a.name or "") < (b.name or "")
    end)

    -- Earth Shield target takes the apex regardless of score: it is where your
    -- attention already lives, and it is a deliberate choice you made.
    if esTarget then
        for i, e in ipairs(list) do
            if UnitGUID(e.unit) == esTarget then
                table.remove(list, i)
                table.insert(list, 1, e)
                e.apex = true
                break
            end
        end
    end

    return list
end

-- ---------------------------------------------------------------- frames --

local anchor = CreateFrame("Frame", "BiSHealingAnchor", UIParent)
anchor:SetSize(200, 24)
anchor:SetPoint("CENTER", 0, -220)
anchor:SetFrameStrata("MEDIUM")
anchor:SetMovable(true)
anchor:EnableMouse(false)     -- only while unlocked; otherwise it ate clicks
                              -- meant for the frames underneath it
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", function(self)
    if not DB().locked and not InCombatLockdown() then self:StartMoving() end
end)
anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB().pos = { p, rp, x, y }
end)

local anchorBG = anchor:CreateTexture(nil, "BACKGROUND")
anchorBG:SetAllPoints()
anchorBG:SetColorTexture(0.2, 0.6, 0.4, 0)   -- only visible while unlocked

-- Settings button on the drag bar. TOGGLES -- the same button opens and closes
-- the window, which is what everyone tries first.
UIX.gear = CreateFrame("Button", "BiSHealingGear", anchor)
UIX.gear:SetSize(20, 20)
UIX.gear:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
UIX.gear.bg = UIX.gear:CreateTexture(nil, "BACKGROUND")
UIX.gear.bg:SetAllPoints()
UIX.gear.bg:SetColorTexture(0.09, 0.07, 0.18, 0.9)
UIX.gear.icon = UIX.gear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
UIX.gear.icon:SetPoint("CENTER")
UIX.gear.icon:SetText("|cffb980ff=|r")
UIX.gear:SetScript("OnClick", function() if UIX.ToggleConfig then UIX.ToggleConfig() end end)
UIX.gear:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.18, 0.13, 0.28, 0.95)
    if not GameTooltip:IsForbidden() then
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("BiS Healing settings")
        GameTooltip:Show()
    end
end)
UIX.gear:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0.09, 0.07, 0.18, 0.9)
    if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end)
UIX.gear:Hide()

local anchorLabel = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchorLabel:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
anchorLabel:SetText("BiS Healing -- drag (unlocked)")

-- ------------------------------------------------------------- tooltip --
-- Out of combat, hovering a frame explains WHY that player sits where they do:
-- the score pieces (damage volume, consistency, Chain Heal bounce quality) that
-- placed them, plus current standing. In combat it shows just the unit, since
-- reasoning matters least mid-fight and the query should stay cheap. Follows the
-- VuhDo pattern: check IsForbidden, SetOwner, AddLine, hide on leave.

local function ShowFrameTooltip(f)
    if not f.unit or not UnitExists(f.unit) then return end
    if GameTooltip:IsForbidden() then return end

    -- No tooltip in combat at all: the popup can cover other frames and the
    -- info matters least mid-fight. The "why here" explanation is for reviewing
    -- placement between pulls.
    if InCombatLockdown() then return end

    GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
    local name = UnitName(f.unit) or "?"
    GameTooltip:AddLine("BiS Healing -- " .. name, 0.4, 0.85, 1)

    local row = f.rowIndex or 0
    local rowName =
        (row == 1 and "Apex (top)") or
        (row <= 3 and ("Row " .. row)) or
        (row <= 6 and "Row 3") or
        "Overflow"
    GameTooltip:AddLine("Placed: " .. rowName, 0.9, 0.9, 0.9)

    local e = f.rankEntry
    local rec = DB().players[f.pname or name]
    local nFights = (rec and rec.fights) and #rec.fights or 0

    if not e or nFights == 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("No fight data yet -- placement is provisional.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Rankings sharpen after a few encounters.", 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Why here (higher = more of your Chain Heal's worth):", 0.8, 0.8, 0.6)
        -- each piece is already weighted; show its share of the total score
        local total = (e.score and e.score > 0) and e.score or 1
        local function pieceLine(label, val, r, g, b)
            local pct = math.floor((val / total) * 100 + 0.5)
            GameTooltip:AddDoubleLine("  " .. label, pct .. "%", r, g, b, 1, 1, 1)
        end
        pieceLine("Chain Heal bounces", e.cBounce or 0, 1, 0.82, 0.2)
        pieceLine("Damage volume",      e.cVol or 0,    0.9, 0.5, 0.4)
        pieceLine("Consistency",        e.cCons or 0,   0.5, 0.8, 1)
        if (e.cDps or 0) > 0 then
            pieceLine("Boss damage (tiebreak)", e.cDps, 0.9, 0.4, 0.4)
        end

        GameTooltip:AddLine(" ")
        if e.bounce and e.bounce > 0 then
            GameTooltip:AddDoubleLine("Avg bounces when healed", ("%.1f"):format(e.bounce), 0.8,0.8,0.8, 1,1,1)
        end
        GameTooltip:AddDoubleLine("Top-third finishes", math.floor((e.cons or 0)*100).."%", 0.8,0.8,0.8, 1,1,1)
        GameTooltip:AddDoubleLine("Fights on record", tostring(nFights), 0.8,0.8,0.8, 1,1,1)

        if f.esCandidate then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Best Earth Shield candidate.", 0.4, 1, 0.6)
        end
        if f.raceWho then
            GameTooltip:AddLine(" ")
            if f.raceUnknown then
                GameTooltip:AddLine(("%s is healing this target -- no cast bar to time, so who lands first is unknown.")
                                    :format(f.raceWho), 1, 0.75, 0.25)
            elseif f.raceLost then
                GameTooltip:AddLine(("%s's heal lands BEFORE yours would."):format(f.raceWho),
                                    1, 0.3, 0.25)
            else
                GameTooltip:AddLine(("%s is also healing this target -- yours lands first.")
                                    :format(f.raceWho), 0.7, 0.7, 0.75)
            end
        end
        if f.chainWho then
            GameTooltip:AddLine(" ")
            if f.chainPrimary then
                GameTooltip:AddLine(("%s is chain healing this target."):format(f.chainWho),
                                    0.2, 0.8, 0.85)
            else
                GameTooltip:AddLine(("Catching a bounce of %s's Chain Heal -- half size or less.")
                                    :format(f.chainWho), 0.2, 0.6, 0.65)
            end
        end
    end
    -- the two WA-library marks explain themselves here, outside the fight-data
    -- branch: they are true whether or not this player has a history yet
    if f.totemOut and f.totemOut:IsShown() then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Outside your totems -- missing " .. table.concat(AURAS.down, ", ") .. ".",
                            0.62, 0.42, 0.95)
    end
    if f.dispelName then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("%s (%s) -- you can cure this."):format(f.dispelName, f.dispelKind or "?"),
                            0.3, 0.9, 0.3)
    end

    GameTooltip:Show()
end

local function HideFrameTooltip()
    if not GameTooltip:IsForbidden() then GameTooltip:Hide() end
end

local function MakeFrame(i)
    local f = CreateFrame("Button", "BiSHealingUnit" .. i, UIParent,
                          "SecureUnitButtonTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("MEDIUM")    -- above the world/default UI, but below
                                 -- bag, loot, and dialog windows so they aren't covered
    f:RegisterForClicks("AnyDown")
    f:HookScript("OnEnter", function(self) ShowFrameTooltip(self) end)
    f:HookScript("OnLeave", function() HideFrameTooltip() end)

    f:SetAttribute("*type1", "spell")
    f:SetAttribute("*spell1", CHAIN_HEAL)   -- replaced by ApplyBinds once ranks load

    -- Bindings are set out of combat and frozen for the fight. Right-click uses
    -- macro text with [nocombat] rather than a plain spell attribute, because
    -- attributes cannot be changed once the pull starts -- the conditional is
    -- evaluated by Blizzard's own secure code at cast time, so it is the only
    -- way to make a click behave differently in combat.
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)

    f.hp = f:CreateTexture(nil, "ARTWORK")
    f.hp:SetPoint("TOPLEFT", 1, -1)
    f.hp:SetPoint("BOTTOMLEFT", 1, 1)
    f.hp:SetWidth(FRAME_W - 2)
    f.hp:SetColorTexture(0.2, 0.7, 0.3, 1)

    -- incoming-heal fill: a translucent segment starting at the current health
    -- edge, showing where the bar lands once inbound heals arrive. Easier to
    -- read at a glance than the +N number, which stays as a precise backup.
    f.incFill = f:CreateTexture(nil, "ARTWORK")
    f.incFill:SetPoint("TOP", f.hp, "TOP")
    f.incFill:SetPoint("BOTTOM", f.hp, "BOTTOM")
    f.incFill:SetColorTexture(0.5, 0.85, 1, 0.45)
    f.incFill:Hide()

    f.glow = f:CreateTexture(nil, "OVERLAY")
    f.glow:SetAllPoints()
    f.glow:SetColorTexture(1, 1, 1, 0)

    -- Layout: name top-LEFT, the deficit/incoming numbers under it on the left,
    -- and both spell-icon badges stacked on the RIGHT edge. Keeps the left as a
    -- text column and the right as an icon column -- no more centre crowding.
    f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.name:SetPoint("TOPLEFT", 3, -2)
    f.name:SetJustifyH("LEFT")

    -- Spell-icon badges, VuhDo-style: the real spell texture as a small square
    -- in a bottom corner, with a count number overlaid. Gift bottom-left, Earth
    -- Shield bottom-right. Cleaner and more recognisable than text labels.
    local ICON = 16

    -- Earth Shield icon: right edge (outermost). KEPT for the code path but no
    -- longer shown -- charges are now the 6 pips below (esBadge default off).
    f.esIcon = f:CreateTexture(nil, "OVERLAY")
    f.esIcon:SetSize(ICON, ICON)
    f.esIcon:SetPoint("RIGHT", -2, 0)
    f.esIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.esIcon:Hide()

    -- Earth Shield CHARGE PIPS: six little "_ _ _ _ _ _" segments along the
    -- bottom inside edge. N lit = N charges of YOUR shield remaining. Replaces
    -- the old ES icon badge entirely.
    f.esPips = {}
    for i = 1, 6 do
        local pip = f:CreateTexture(nil, "OVERLAY")
        pip:SetColorTexture(0.90, 0.72, 0.35, 1.0)  -- amber/tan, matches ES corner
        pip:Hide()
        f.esPips[i] = pip
    end

    -- NATURE'S SWIFTNESS pip: a short bar centred on the TOP edge, lit only on
    -- someone whose hole is deep enough that the wheel emergency (NS + max
    -- Healing Wave) is the correct answer instead of a Chain Heal. White means
    -- NS is off cooldown and the shot is live; dim grey means the hole is that
    -- deep but NS is still down, which is exactly when you want to know early.
    f.nsPip = f:CreateTexture(nil, "OVERLAY")
    f.nsPip:SetDrawLayer("OVERLAY", 6)
    f.nsPip:SetSize(18, 3)
    f.nsPip:SetPoint("TOP", 0, -1)
    f.nsPip:SetColorTexture(1, 1, 1, 1)
    f.nsPip:Hide()

    -- ANOTHER SHAMAN'S CHAIN HEAL, inbound. A teal bar down the LEFT edge --
    -- deliberately nowhere near the four role corners, because it is not advice
    -- about this frame, it is news about somebody else's cast. Reads as "that
    -- one is handled, put yours elsewhere".
    f.chainIn = f:CreateTexture(nil, "OVERLAY")
    f.chainIn:SetDrawLayer("OVERLAY", 6)
    f.chainIn:SetWidth(3)
    f.chainIn:SetPoint("TOPLEFT", 1, -1)
    f.chainIn:SetPoint("BOTTOMLEFT", 1, 1)
    f.chainIn:Hide()

    -- MY TOTEM IS NOT REACHING HIM. A violet bar down the RIGHT edge, the
    -- mirror of the teal chain bar on the left: news, not advice. Lit when a
    -- buff totem of mine is down and this party member does not carry its
    -- buff -- he is standing outside it (ported from the Shaman UI WA).
    f.totemOut = f:CreateTexture(nil, "OVERLAY")
    f.totemOut:SetDrawLayer("OVERLAY", 6)
    f.totemOut:SetWidth(3)
    f.totemOut:SetPoint("TOPRIGHT", -1, -1)
    f.totemOut:SetPoint("BOTTOMRIGHT", -1, 1)
    f.totemOut:Hide()

    -- A DEBUFF I CAN CURE. A small square low on the right, between the race
    -- number and the pips, in the client's colour for the debuff type (green
    -- poison, brown disease). Only types this class can clear ever light it.
    f.dispelMark = f:CreateTexture(nil, "OVERLAY")
    f.dispelMark:SetDrawLayer("OVERLAY", 6)
    f.dispelMark:SetSize(7, 7)
    f.dispelMark:SetPoint("BOTTOMRIGHT", -5, 8)
    f.dispelMark:Hide()

    -- Unified ROLE-CORNER reticle: four corners (TL, TR, BL, BR), each an L of
    -- two textures. Coloured per tick by which "best target" role this frame
    -- holds -- Chain Heal (green) owns TL+BR, Earth Shield (amber) owns TR, Gift
    -- (orange-red) owns BL. A frame best for several roles shows several colours.
    f.corner = {}      -- keys: "TL","TR","BL","BR"; each = {armH, armV}
    for _, ck in ipairs({ "TL", "TR", "BL", "BR" }) do
        local h1 = f:CreateTexture(nil, "OVERLAY")   -- horizontal arm
        local v1 = f:CreateTexture(nil, "OVERLAY")   -- vertical arm
        h1:SetDrawLayer("OVERLAY", 7); v1:SetDrawLayer("OVERLAY", 7)
        h1:Hide(); v1:Hide()
        f.corner[ck] = { h = h1, v = v1 }
    end

    -- Gift of the Naaru icon: just left of the shield
    f.giftIcon = f:CreateTexture(nil, "OVERLAY")
    f.giftIcon:SetSize(ICON, ICON)
    f.giftIcon:SetPoint("RIGHT", f.esIcon, "LEFT", -2, 0)
    f.giftIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.giftIcon:Hide()

    -- resolve the actual spell-icon art (falls back to a generic icon if the
    -- spell isn't known/loaded yet)
    local function spellTex(name, fallback)
        local tex
        if C_Spell and C_Spell.GetSpellTexture then tex = C_Spell.GetSpellTexture(name)
        elseif GetSpellTexture then tex = GetSpellTexture(name) end
        return tex or fallback
    end
    f.giftIcon:SetTexture(spellTex(GIFT, "Interface\\Icons\\Spell_Holy_HolyProtection"))
    f.esIcon:SetTexture(spellTex(EARTH_SHIELD, "Interface\\Icons\\Spell_Nature_SkinofEarth"))

    -- HEAL RACE: how many other healers have a cast in the air at this target.
    -- Red when one of them lands before yours would -- that is the cast you are
    -- about to waste. Sits on the right edge, where the retired shield icon used
    -- to live, so it never crowds the name or the numbers.
    f.race = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.race:SetPoint("RIGHT", -3, 0)
    f.race:SetTextColor(1, 1, 1)
    do local fnt, sz = f.race:GetFont(); if fnt then f.race:SetFont(fnt, math.max(9, (sz or 10)), "OUTLINE") end end

    -- charge count sits on the ES icon
    f.es = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.es:SetPoint("BOTTOMRIGHT", f.esIcon, "BOTTOMRIGHT", 1, -1)
    f.es:SetTextColor(1, 1, 1)
    do local fnt, sz = f.es:GetFont(); if fnt then f.es:SetFont(fnt, math.max(9, (sz or 10)), "OUTLINE") end end



    -- Deficit + incoming: a small number row UNDER the name, left-aligned, so
    -- the whole left side is a text column (name over numbers) and the right
    -- side is the icon column. Small outlined font to fit under the name.
    f.def = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.def:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -1)
    f.def:SetJustifyH("LEFT")
    f.def:SetTextColor(1, 0.7, 0.6)
    do local fnt, sz = f.def:GetFont(); if fnt then f.def:SetFont(fnt, math.max(8, (sz or 10) - 2), "OUTLINE") end end

    f.inc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.inc:SetPoint("LEFT", f.def, "RIGHT", 3, 0)
    f.inc:SetTextColor(0.5, 0.8, 1)
    do local fnt, sz = f.inc:GetFont(); if fnt then f.inc:SetFont(fnt, math.max(8, (sz or 10) - 2), "OUTLINE") end end

    return f
end

-- ------------------------------------------------------------- bindings --
--   left click        Chain Heal, two ranks down
--   shift + left      Chain Heal, max rank
--   right click       Earth Shield, max rank -- works in combat
--
-- Plain spell attributes, no macro conditional: right-click is meant to land
-- Earth Shield on that target mid-fight, whenever you decide to move it.
local function ApplyBinds()
    if InCombatLockdown() then return end
    ResolveGiftKnown()
    for _, f in ipairs(frames) do
        local unit = f.unit
        -- Left click: plain downranked Chain Heal, no trinkets on small heals.
        f:SetAttribute("*type1", "spell")
        f:SetAttribute("*spell1", chDownCast or CHAIN_HEAL)
        f:SetAttribute("*macrotext1", nil)

        -- Shift+left: the big heal. Fire both trinket slots first, then max-rank
        -- Chain Heal on this unit. The /use lines are dumb on purpose -- a slot
        -- that's on cooldown or holds a passive trinket is a harmless no-op, so
        -- whatever is ready pops and nothing is ever held back. Trinket uses are
        -- off the GCD, so the heal casts the same instant.
        if unit and DB().trinkets and (chMaxCast or CHAIN_HEAL) then
            f:SetAttribute("shift-type1", "macro")
            -- slot 13 and 14 are the two trinkets; /use on a slot fires its
            -- on-use, and is a silent no-op on a passive or one on cooldown.
            -- Trinkets are off the GCD so the /cast lands the same press.
            f:SetAttribute("shift-macrotext1",
                ("/use 13\n/use 14\n/cast [@%s] %s"):format(unit, chMaxCast or CHAIN_HEAL))
            f.shiftMacro = ("/use 13 | /use 14 | /cast [@%s] %s"):format(unit, chMaxCast or CHAIN_HEAL)
        else
            -- trinkets off, or sim frame: plain max-rank cast
            f:SetAttribute("shift-type1", "spell")
            f:SetAttribute("shift-spell1", chMaxCast or CHAIN_HEAL)
            f:SetAttribute("shift-macrotext1", nil)
        end

        if unit and esMaxCast then
            f:SetAttribute("*type2", "spell")
            f:SetAttribute("*spell2", esMaxCast)
            f:SetAttribute("*macrotext2", nil)
            f:SetAttribute("unit", unit)
        else
            f:SetAttribute("*type2", nil)
        end

        -- Mouse button 4: Gift of the Naaru on this unit, same click-cast idea
        -- as the others. Only bound if he actually has the spell; otherwise the
        -- button stays free. Instant HoT, so no rank suffix needed.
        if unit and giftKnown then
            f:SetAttribute("*type4", "spell")
            f:SetAttribute("*spell4", GIFT)
            f:SetAttribute("*macrotext4", nil)
        else
            f:SetAttribute("*type4", nil)
        end
    end
    if WHEEL.Apply then WHEEL.Apply() end
end
ApplyBindsRef = ApplyBinds

-- ------------------------------------------------------- wheel bindings --
--   scroll up             Healing Wave, two ranks down
--   shift + scroll up     Nature's Swiftness (if up) + max-rank Healing Wave
--   scroll down           Lesser Healing Wave, two ranks down
--   shift + scroll down   Lesser Healing Wave, max rank
--
-- The rule for trinkets is his, and it is a good one: any SHIFT press is a
-- press that matters, so both shifted wheel directions fire slots 13 and 14
-- exactly like shift+left does. The unshifted directions never do.
--
-- Both are MOUSEOVER ONLY: the macro stops dead unless the cursor is over a
-- living friendly unit, so scrolling anywhere else costs nothing. A wheel
-- "click" is not a real click -- the wheel cannot be handled by a secure frame
-- directly -- so the binding points at this one hidden secure button and the
-- modifier picks which mouse button it pretends was pressed. Left = plain,
-- right = shift.
--
-- Why NS and the heal live on the SAME press instead of two: attributes cannot
-- be rewritten in combat, so the addon has no way to notice mid-fight that NS
-- came off cooldown and re-point the button. A /castsequence would notice, but
-- it also STALLS when NS is down -- the press does nothing at all, which is the
-- one outcome that cannot happen on a tank at 10%. NS is off the GCD, so one
-- press fires it and the instant Healing Wave together; when NS is on cooldown
-- the same press just hard-casts, and nothing is ever swallowed. /bish wheel
-- strict switches to the true two-press castsequence for anyone who wants it.
WHEEL.btn = CreateFrame("Button", "BiSHealingWheel", UIParent,
                        "SecureActionButtonTemplate")
WHEEL.btn:SetSize(1, 1)
WHEEL.btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -100, -100)
WHEEL.btn:SetAlpha(0)
WHEEL.btn:EnableMouse(false)           -- invisible and unclickable by hand;
WHEEL.btn:RegisterForClicks("AnyDown") -- only the binding ever presses it
WHEEL.btn:Show()                       -- a hidden button is not click-routable

-- Stop unless the cursor is on a living friendly. Every wheel macro opens with
-- this, so scrolling over the world stays free for whatever else you bound.
WHEEL.gate = "/stopmacro [@mouseover,noexists][@mouseover,nohelp][@mouseover,dead]"

function WHEEL.Apply()
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return end
    if InCombatLockdown() then WHEEL.pending = true; return end
    ClearOverrideBindings(WHEEL.btn)
    for i = 1, 4 do WHEEL.btn:SetAttribute("*type" .. i, nil) end
    WHEEL.plainMacro, WHEEL.shiftMacro = nil, nil
    WHEEL.dnMacro, WHEEL.dnShiftMacro = nil, nil
    if not DB().wheel then return end

    WHEEL.ResolveKnown()
    local down = WHEEL.down or WHEEL.max or WHEEL.HW
    local big  = WHEEL.max or WHEEL.HW
    -- trinkets ride the emergency press for the same reason they ride
    -- shift+left: a slot on cooldown or holding a passive is a silent no-op.
    local pop  = DB().trinkets and "/use 13\n/use 14\n" or ""

    WHEEL.plainMacro = ("%s\n/cast [@mouseover] %s"):format(WHEEL.gate, down)

    if not WHEEL.known then
        WHEEL.shiftMacro = ("%s\n%s/cast [@mouseover] %s")
                           :format(WHEEL.gate, pop, big)
    elseif DB().wheelStrict then
        -- true two-press: first press NS, second press the heal. Stalls if NS
        -- is on cooldown -- that is the trade, and it is opt-in.
        WHEEL.shiftMacro = ("%s\n%s/castsequence [@mouseover] reset=8/target %s, %s")
                           :format(WHEEL.gate, pop, WHEEL.NS, big)
    else
        WHEEL.shiftMacro = ("%s\n%s/cast %s\n/cast [@mouseover] %s")
                           :format(WHEEL.gate, pop, WHEEL.NS, big)
    end

    -- Scroll DOWN: the fast heal. Same mouseover gate, same trinket rule --
    -- shift pops them, plain does not.
    local lDown = WHEEL.lDown or WHEEL.lMax or WHEEL.LHW
    local lBig  = WHEEL.lMax or WHEEL.LHW
    WHEEL.dnMacro      = ("%s\n/cast [@mouseover] %s"):format(WHEEL.gate, lDown)
    WHEEL.dnShiftMacro = ("%s\n%s/cast [@mouseover] %s"):format(WHEEL.gate, pop, lBig)

    WHEEL.btn:SetAttribute("*type1", "macro")
    WHEEL.btn:SetAttribute("*macrotext1", WHEEL.plainMacro)
    WHEEL.btn:SetAttribute("*type2", "macro")
    WHEEL.btn:SetAttribute("*macrotext2", WHEEL.shiftMacro)
    WHEEL.btn:SetAttribute("*type3", "macro")
    WHEEL.btn:SetAttribute("*macrotext3", WHEEL.dnMacro)
    WHEEL.btn:SetAttribute("*type4", "macro")
    WHEEL.btn:SetAttribute("*macrotext4", WHEEL.dnShiftMacro)

    -- Override bindings, not SetBinding: they never touch his saved keybind
    -- profile, and a /reload clears them if anything here is wrong.
    -- One button, four pretend mouse buttons: the suffix in the attribute name
    -- is what the secure code resolves the click to (1 left, 2 right, 3 middle,
    -- 4 button4), so the direction and the modifier together pick the macro.
    SetOverrideBindingClick(WHEEL.btn, true, "MOUSEWHEELUP",
                            "BiSHealingWheel", "LeftButton")
    SetOverrideBindingClick(WHEEL.btn, true, "SHIFT-MOUSEWHEELUP",
                            "BiSHealingWheel", "RightButton")
    SetOverrideBindingClick(WHEEL.btn, true, "MOUSEWHEELDOWN",
                            "BiSHealingWheel", "MiddleButton")
    SetOverrideBindingClick(WHEEL.btn, true, "SHIFT-MOUSEWHEELDOWN",
                            "BiSHealingWheel", "Button4")
end

-- Lay the pyramid out. OUT OF COMBAT ONLY -- SetPoint on a secure frame is
-- blocked once the pull starts, which is the whole reason this addon reorders
-- between fights instead of during them.
local function Relayout()
    if InCombatLockdown() then pendingReorder = true; return end

    local ranked = RankRoster()
    order = ranked

    local idx, row = 1, 1
    local rowY = 0

    while idx <= #ranked do
        -- rows 1-3 use the defined sizes; every row after repeats row 3
        local n     = LAYOUT.rowSizes[row] or LAYOUT.tailCount
        local scale = LAYOUT.rowScale[row] or LAYOUT.tailScale
        local count = math.min(n, #ranked - idx + 1)
        -- width scales to fit more per row, but HEIGHT stays full so every row
        -- lines up cleanly with the top two instead of looking choppy
        local rw, rh = math.floor(FRAME_W * scale), FRAME_H
        local rowW = count * rw + (count - 1) * PAD
        local startX = -rowW / 2

        for c = 1, count do
            local e = ranked[idx]
            local f = frames[idx] or MakeFrame(idx)
            frames[idx] = f

            f:SetSize(rw, rh)
            f.narrow = (rw < FRAME_W)     -- smaller rows hide the number row
            f.isPet = false
            f.rowIndex = idx              -- 1 = apex; feeds the bullseye's bias
            f.rankEntry = e               -- score breakdown for the tooltip
            f:SetAttribute("unit", e.unit)
            f.unit = e.unit
            f.pname = e.name
            -- stash class for the ES recommendation (never shield a shaman: it
            -- knocks off their Water/Lightning Shield -- that's griefing)
            local _, cls = UnitClass(e.unit)
            f.class = cls
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", anchor, "TOP",
                       startX + (c - 1) * (rw + PAD), rowY - 26)
            f:Show()

            -- half-width still fits a (short) name
            if rw >= FRAME_W * 0.5 then
                local short = ShortName(e.name)
                f.name:SetText(short)
                local _, class = UnitClass(e.unit)
                local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if col then f.name:SetTextColor(col.r, col.g, col.b)
                else f.name:SetTextColor(1, 1, 1) end
            else
                f.name:SetText("")
            end

            idx = idx + 1
        end

        rowY = rowY - (rh + PAD)
        row = row + 1
    end
    layoutRows = math.max(1, row - 1)


    for i = idx, #frames do frames[i]:Hide() end

    if DB().shown == false then
        for _, f in ipairs(frames) do f:Hide() end
    end
    -- flag the best Earth Shield candidate among the top rows, so its badge can
    -- flash SHIELD when it has no shield. Rows 5+ are excluded by design.
    esCandidateName = nil
    do
        local best, bestScore
        local cap = 6   -- rows 1-3
        for i = 1, math.min(cap, #ranked) do
            local e = ranked[i]
            if e.name then
                local prof = TargetProfile and TargetProfile(e.name) or nil
                local sc = prof and prof.cpm and (prof.cpm * (prof.depth or 1)) or 0
                if not best or sc > bestScore then best, bestScore = e.name, sc end
            end
        end
        esCandidateName = best
    end
    for _, f in ipairs(frames) do
        f.esCandidate = (f.pname ~= nil and f.pname == esCandidateName)
    end

    -- Frames are a REUSED POOL: after a reorder, frame #3 is a different person.
    -- Holding on to the old handles meant the Chain Heal hysteresis would defend
    -- a mark that had silently moved to somebody else, and the pip flash would
    -- fire on the wrong frame. Drop them and let the next tick re-pick.
    bullTarget, bullScore = nil, 0
    esBullTarget, giftBullTarget = nil, nil

    ApplyBinds()

    local unlocked = not DB().locked
    anchorLabel:SetText(unlocked and "BiS Healing -- drag me" or "")
    anchorBG:SetColorTexture(0.2, 0.6, 0.4, unlocked and 0.5 or 0)
    -- the settings button rides the drag bar: visible exactly when the anchor
    -- is, so nothing floats over the raid while you are locked and playing
    if UIX.gear then UIX.gear:SetShown(unlocked) end
    anchor:EnableMouse(unlocked)
    anchor:SetFrameStrata(unlocked and "MEDIUM" or "BACKGROUND")
end

-- ---------------------------------------------------------- bounce lines --
-- A fading line is drawn from each Chain Heal target to the next. The lines
-- live on their own full-screen frame -- the earlier version drew them on the
-- 24px anchor, which clipped every endpoint that fell outside those 24px, so
-- nothing showed. Purely cosmetic; non-secure, touches no combat rules.

local lineLayer = CreateFrame("Frame", nil, UIParent)
lineLayer:SetAllPoints(UIParent)
lineLayer:SetFrameStrata("HIGH")   -- above the MEDIUM frames so the
                                   -- gauge/counter/reticles draw on top, not behind

local bounceLines = {}
local activeLines = {}
local castLines  = {}      -- lines belonging to the cast currently resolving
UIX.LINE_LIFE = 1.1   -- lines linger longer (gold gets 1.6x on top)

-- Blue while the chain is still resolving, because we cannot know it is a full
-- 3-target chain until the cluster closes. On close, every line from that cast
-- is repainted gold and thickened, so a great chain reads as one gold event
-- rather than blue lines plus a separate burst.
-- On UIX rather than as chunk locals: this file sits one slot under Lua 5.1's
-- 200-local ceiling for a chunk, and the next `local` anywhere would stop the
-- addon loading with an error that names no useful line. Constants are the
-- cheapest thing to move -- see bislint's local-budget rule.
UIX.LINE_BLUE = { 0.15, 0.55, 0.90, 1.00 }   -- darker, deeper blue
UIX.LINE_GOLD = { 0.85, 0.62, 0.05, 1.00 }   -- darker, richer gold

local function FrameForGUID(guid)
    for _, f in ipairs(frames) do
        if f:IsShown() and f.unit and UnitGUID(f.unit) == guid then return f end
    end
end

-- Lines are painted with a white 8x8 and a vertex colour, NOT SetColorTexture.
-- A Line is a Texture subclass, so SetColorTexture exists and silently succeeds
-- -- but on this client it leaves the line with nothing to draw, which is why
-- the bounce lines went invisible while the celebration sparks (real textures
-- with a real file) kept working. Same trap as the SetTexture(r,g,b,a) one in
-- the header: the call is accepted, the pixels never arrive.
UIX.LINE_TEX = "Interface\\Buttons\\WHITE8X8"
local function PaintLine(l, c, thickness)
    l:SetThickness(thickness or 3)
    if l.SetTexture then l:SetTexture(UIX.LINE_TEX) end
    if l.SetVertexColor then l:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
end

local function GetLine()
    for _, l in ipairs(bounceLines) do
        if not l:IsShown() then return l end
    end
    local l = lineLayer:CreateLine(nil, "OVERLAY")
    l:SetThickness(3)
    bounceLines[#bounceLines + 1] = l
    return l
end

DrawBounce = function(fromGUID, toGUID)
    if not DB().bounceLines then return end
    if not fromGUID or not toGUID or fromGUID == toGUID then return end
    local a, b = FrameForGUID(fromGUID), FrameForGUID(toGUID)
    if not a or not b then return end
    local l = GetLine()
    l:SetStartPoint("CENTER", a)
    l:SetEndPoint("CENTER", b)
    PaintLine(l, UIX.LINE_BLUE, 3)
    l:SetAlpha(1)          -- reused from the pool mid-fade, so reset it
    l:Show()
    local entry = { line = l, born = GetTime() }
    activeLines[#activeLines + 1] = entry
    castLines[#castLines + 1] = entry
end

-- Called when a cluster closes. hits >= 3 means the chain reached everyone it
-- could, so repaint that cast's lines gold and restart their fade so the gold
-- is actually visible rather than arriving as they vanish.
FinishChain = function(hits)
    if hits >= 3 and DB().goldChains then
        for _, e in ipairs(castLines) do
            PaintLine(e.line, UIX.LINE_GOLD, 5)
            e.born = GetTime()          -- give the gold its own full fade
            e.gold = true
            e.line:SetAlpha(1)
            e.line:Show()
            -- The blue fade lasts 1.1s and the cluster does not close for 1.25s,
            -- so by the time gold is decided the line has usually been hidden
            -- and dropped from the active list. Repainting a hidden line is a
            -- no-op you cannot see: put it back on screen and back in the fade
            -- list, or the gold chain never once renders.
            local live = false
            for _, x in ipairs(activeLines) do
                if x == e then live = true; break end
            end
            if not live then activeLines[#activeLines + 1] = e end
        end
    end
    wipe(castLines)
end

UpdateBounceLines = function()
    local now = GetTime()
    for i = #activeLines, 1, -1 do
        local e = activeLines[i]
        local life = e.gold and (UIX.LINE_LIFE * 1.6) or UIX.LINE_LIFE
        local age = now - e.born
        if age >= life then
            e.line:Hide()
            e.gold = nil
            table.remove(activeLines, i)
        else
            e.line:SetAlpha(1 - age / life)
        end
    end
end

local sparks = {}          -- pool of star textures
local activeSparks = {}    -- { tex=, born=, vx=, vy=, x0=, y0= }
UIX.SPARK_LIFE = 0.8
UIX.SPARK_TEX = "Interface\\Cooldown\\star4"

local function GetSpark()
    for _, t in ipairs(sparks) do
        if not t:IsShown() then return t end
    end
    local t = lineLayer:CreateTexture(nil, "OVERLAY")
    t:SetTexture(UIX.SPARK_TEX)
    t:SetBlendMode("ADD")
    t:SetSize(18, 18)
    sparks[#sparks + 1] = t
    return t
end



-- ------------------------------------------------------- cast counter --
-- "X | Y" above the pyramid: how many downranked Chain Heals and how many max
-- rank ones your current mana pays for. Recomputed every tick, so regen and
-- Water Shield ticks are already in the number -- it climbs while you are not
-- casting and drops the moment you spend.
--
-- Colours match the health bands: blue for the downrank, amber for max rank,
-- so the counter reads in the same language as the frames.

local castCounter = lineLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
castCounter:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
castCounter:SetText("")

-- FIVE-SECOND RULE. Technique from the WA library (claude/wa-patterns-05
-- §1.4, the Shaman UI's FSR tick bar): "did that cast cost mana" is answered
-- by comparing mana before and after UNIT_SPELLCAST_SUCCEEDED -- no spell-cost
-- lookup, so a free proc or a totem drop that costs nothing never restarts the
-- clock. The counter's regen column then shows the regen you are ACTUALLY
-- getting: while-casting regen inside the five seconds, full spirit regen once
-- they are up, with the seconds left shown until they are.
function UIX.FSRCast()
    local m = UnitPower("player", 0)
    if UIX.fsr.mana and m < UIX.fsr.mana then UIX.fsr.at = GetTime() end
    UIX.fsr.mana = m
end
-- seconds of the rule still to run; 0 once spirit regen is back
function UIX.FSRLeft()
    local left = UIX.FSR - (GetTime() - UIX.fsr.at)
    return (left > 0) and left or 0
end

UpdateCastCounter = function()
    local mana = UnitPower("player", 0)
    -- the pre-cast sample the five-second rule compares against, kept fresh
    -- at 10 Hz so the next cast's before/after is a tenth of a second apart.
    -- Taken before the early outs: the rule runs whether or not the counter
    -- is showing.
    UIX.fsr.mana = mana
    if not DB().castCounter then castCounter:SetText("") return end
    if #healOptions == 0 then castCounter:SetText("") return end
    local down = healOptions[1]
    local top  = healOptions[#healOptions]

    local dCost = (down and down.cost) or 0
    local mCost = (top and top.cost) or 0
    if dCost <= 0 and mCost <= 0 then castCounter:SetText("") return end

    local x = (dCost > 0) and math.floor(mana / dCost) or 0
    local y = (mCost > 0) and math.floor(mana / mCost) or 0

    -- Third number: how many downrank Chain Heals your REGEN pays for every 5s.
    -- GetPowerRegen returns mana/sec (while-casting and not-casting); we use the
    -- while-casting figure since that's the honest number mid-fight -- spirit
    -- regen mostly stops while you're actively healing, so this is your MP5-gear
    -- and other always-on regen. It answers "am I earning casts back or bleeding
    -- out" -- pairs with the RPM bar.
    local castingRegen = 0
    local fsrLeft = (DB().fsr ~= false) and UIX.FSRLeft() or 0
    if GetPowerRegen then
        local base, whileCasting = GetPowerRegen()
        castingRegen = whileCasting or 0
        -- five seconds after the last mana-costing cast, spirit is back: show
        -- the regen you are really getting, not the mid-fight floor
        if DB().fsr ~= false and fsrLeft <= 0 and base and base > castingRegen then
            castingRegen = base
        end
    end
    local per5 = castingRegen * 5
    local z = (dCost > 0) and (per5 / dCost) or 0

    -- red the count when it hits zero: that is the moment the button you are
    -- about to press stops working, and it should be obvious before you press it
    local xc = (x > 0) and "4da6ff" or "ff4d4d"
    local yc = (y > 0) and "ffd24d" or "ff4d4d"
    -- regen column in green when you're earning at least one back per 5s, grey
    -- when you're not gaining ground
    local zc = (z >= 0.1) and "4dff88" or "888888"
    -- the rule's countdown in orange while it runs; nothing once regen is back
    local fsr = (fsrLeft > 0) and (" |cffff9944%.1fs|r"):format(fsrLeft) or ""
    castCounter:SetText(("|cff%s%d|r |cff888888|||r |cff%s%d|r |cff888888|||r |cff%s+%.1f|r%s")
        :format(xc, x, yc, y, zc, z, fsr))
end


-- ------------------------------------------------------------- rpm gauge --
-- One reading from two facts: how hard I'm spending, and how much is landing.
--   burn   = mana spent per second over the window, as a fraction of a rough
--            "full tilt" spend rate (nonstop max-rank casting)
--   waste  = fraction of my recent healing that overhealed
-- The needle wants to sit HOT: spending hard with heals landing. It's dragged
-- DOWN by cruising (low burn -- ending at 80% mana, the real failure) and
-- dragged toward "wasteful" by overheal (spending, but into full health bars).

local rpmFrame = CreateFrame("Frame", nil, lineLayer)
rpmFrame:SetSize(140, 16)
rpmFrame:SetPoint("BOTTOM", anchor, "TOP", 0, 20)
rpmFrame:Hide()

-- dark track
rpmFrame.track = rpmFrame:CreateTexture(nil, "BACKGROUND")
rpmFrame.track:SetAllPoints()
rpmFrame.track:SetColorTexture(0.08, 0.08, 0.10, 0.85)

-- the fill: grows left-to-right with how hard you're working the mana bar
rpmFrame.fill = rpmFrame:CreateTexture(nil, "ARTWORK")
rpmFrame.fill:SetPoint("TOPLEFT", 1, -1)
rpmFrame.fill:SetPoint("BOTTOMLEFT", 1, 1)
rpmFrame.fill:SetWidth(1)

-- sweet-spot zone marker: a brighter band showing where you WANT to sit (hot).
-- Two thin lines at ~60% and ~100% frame the "running hot is good" region.
rpmFrame.W = 138
rpmFrame.zoneA = rpmFrame:CreateTexture(nil, "OVERLAY")
rpmFrame.zoneA:SetColorTexture(1, 1, 1, 0.35)
rpmFrame.zoneA:SetSize(1, 16)
rpmFrame.zoneA:SetPoint("LEFT", rpmFrame, "LEFT", 1 + rpmFrame.W * 0.55, 0)

rpmFrame.label = rpmFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
rpmFrame.label:SetPoint("BOTTOM", rpmFrame, "TOP", 0, 1)

-- returns needle fraction 0..1 and an overheal fraction 0..1
local function ComputeRPM()
    local now = GetTime()
    -- prune window in place (drop expired entries off the front); mutating the
    -- existing table means a heal appended mid-compute isn't lost to a rebind
    local cutoff = now - RPM_WINDOW
    while rpmWindow[1] and rpmWindow[1].t < cutoff do
        table.remove(rpmWindow, 1)
    end
    local raw, over = 0, 0
    for _, e in ipairs(rpmWindow) do
        raw = raw + e.raw
        over = over + e.over
    end

    -- Mana spend rate, WINDOWED. Reading one tick's mana drop was the source of
    -- the jumpiness: it's a big number the instant a cast lands and zero the rest
    -- of the time. Instead, log each tick's drop into a short window and average
    -- the spend across it, so the rate reflects sustained casting.
    local mana = UnitPower("player", 0)
    if lastManaSample then
        local drop = lastManaSample.mana - mana
        if drop > 0 then
            spendWindow[#spendWindow + 1] = { t = now, amt = drop }
        end
    end
    lastManaSample = { t = now, mana = mana }

    local spendCut = now - 4.0     -- shorter window than heals: pace should feel current
    while spendWindow[1] and spendWindow[1].t < spendCut do
        table.remove(spendWindow, 1)
    end
    local spent = 0
    for _, e in ipairs(spendWindow) do spent = spent + e.amt end
    local spendRate = spent / 4.0

    -- "full tilt" reference: max-rank Chain Heal cost / its cast time = mana/sec
    -- of nonstop casting. Burn is our spend rate against that.
    local ref = 400
    local top = healOptions[#healOptions]
    if top and top.cost and top.cost > 0 then
        ref = top.cost / math.max(1.5, CAST_LEAD - CAST_REACTION)
    end
    local burn = math.min(1, spendRate / ref)

    -- overheal fraction over the window
    local waste = (raw > 0) and (over / raw) or 0

    -- needle: burn is the main driver (are you spending), pulled back by waste
    -- (spending into overheal isn't real work). Sweet spot = high burn, low waste.
    local reading = burn * (1 - waste * 0.6)
    return math.max(0, math.min(1, reading)), waste, burn
end

UpdateRPM = function()
    if not DB().rpm then rpmFrame:Hide(); return end
    if not InCombatLockdown() and #rpmWindow == 0 then rpmFrame:Hide(); return end
    rpmFrame:Show()

    local target, waste, burn = ComputeRPM()

    -- Ease toward the target instead of snapping. A Chain Heal landing spikes the
    -- instantaneous reading; without smoothing the bar shot to red then fell back
    -- to cruising between casts. Exponential glide (~0.15/tick) settles it into a
    -- steady level that reflects sustained pace, not the last single cast.
    rpmSmoothed = rpmSmoothed + (target - rpmSmoothed) * 0.15
    RPMPaint(rpmSmoothed, waste, burn)
end

-- Bar width, colour and label from an already-eased reading. Split out of
-- UpdateRPM so the sim preview can drive exactly the same painting code --
-- a preview that renders through a different path is a preview of nothing.
RPMPaint = function(reading, waste, burn)
    rpmFrame.fill:SetWidth(math.max(1, rpmFrame.W * reading))

    -- Label hysteresis: only change the WORD when the reading crosses a boundary
    -- by a margin, so it doesn't flicker between two states on the edge.
    local newState = rpmState
    if burn < 0.28 then newState = "cruising"
    elseif waste > 0.5 and burn > 0.4 then newState = "overhealing"
    elseif reading > 0.72 then newState = "redline"
    else newState = "sweetspot" end

    -- require a little separation from the current state's threshold to switch
    if rpmState == "cruising"   and newState ~= "cruising"   and burn < 0.33 then newState = "cruising" end
    if rpmState == "redline"    and newState == "sweetspot"  and reading > 0.66 then newState = "redline" end
    if rpmState == "sweetspot"  and newState == "redline"    and reading < 0.78 then newState = "sweetspot" end
    rpmState = newState

    if rpmState == "cruising" then
        rpmFrame.fill:SetColorTexture(0.30, 0.55, 1.00, 0.9)
        rpmFrame.label:SetText("|cff6699ffcruising|r")
    elseif rpmState == "overhealing" then
        rpmFrame.fill:SetColorTexture(1.00, 0.30, 0.30, 0.95)
        rpmFrame.label:SetText("|cffff4d4doverhealing|r")
    elseif rpmState == "redline" then
        rpmFrame.fill:SetColorTexture(0.95, 0.75, 0.20, 0.95)
        rpmFrame.label:SetText("|cffffd24dredline|r")
    else
        rpmFrame.fill:SetColorTexture(0.30, 0.90, 0.40, 0.95)
        rpmFrame.label:SetText("|cff4dff88sweet spot|r")
    end
end

-- ------------------------------------------------------- target scoring --
-- One answer per role: of everyone worth healing right now, THIS is the
-- best target for a max-rank Chain Heal. Pulse says "these people are taking
-- damage" and several frames can show it at once, which is exactly the problem
-- -- three identical glows tell you nothing about which to pick. The bullseye
-- corner marker resolves that into a single answer.
--
-- Score blends four things the addon already tracks:
--   predicted deficit   how big the hole will be when the cast lands
--   sustained damage    still being hit, versus already stabilising
--   bounce potential    historical bounces, since a max rank wants to reach 3
--   position bias       tanks/top rows start ahead, but can lose the mark
--
-- It SNAPS between targets. No gliding: a challenger must beat the current
-- holder by a clear margin before the mark moves, which kills the flicker you
-- would otherwise get between two near-equal targets.

local TUNE = {}   -- folded from 5 chunk locals (Lua 5.1 budget)
TUNE.bullHysteresis = 1.15   -- challenger must be 15% better to steal the mark

-- (rc29) The three old standalone reticle frames -- the gold Chain Heal
-- bullseye, the purple Gift bracket and the pink Earth Shield U -- are GONE.
-- rc25 replaced all three with the per-frame corner marker below, but their
-- frames, 19 textures and three layout functions were left behind: created at
-- load, never shown, and UpdateESBull was still being called ten times a second
-- to hide a frame nobody could see. Only the two target handles survive,
-- because the corner code and /bish bull still read them.


-- Score one frame as a max-rank Chain Heal target. Returns 0 for anyone who
-- should never wear the mark (dead, out of range, not actually hurt).
local function BullScore(f)
    if not f or not f:IsShown() then return 0 end
    if f.outOfRange or f.isDead then return 0 end

    local predicted = f.predicted or 0
    if predicted <= 0 then return 0 end

    local maxHeal = (healOptions[#healOptions] and healOptions[#healOptions].heal) or 1
    -- how much of a max-rank cast this target would actually use, capped at 1:
    -- someone needing three times a max rank is not three times as good a target
    local need = math.min(1, predicted / maxHeal)

    -- sustained damage matters more than a hole that has stopped growing
    local sustain = f.sustained and 1 or 0.45

    -- bounce potential from history; unknown targets sit mid-range so they are
    -- neither favoured nor buried before they have data
    local bounce = 1.0
    if f.pname then
        local rec = DB().players[f.pname]
        if rec and rec.bounce and rec.bounce.n > 0 then
            bounce = rec.bounce.sum / rec.bounce.n     -- average targets hit
        else
            bounce = 1.8
        end
    end
    local bounceFactor = 0.6 + 0.4 * math.min(3, bounce) / 3

    -- position bias: the pyramid already ranked these people, so a top-row
    -- frame starts ahead. A thumb on the scale, not a lock -- stabilise and
    -- the mark moves on.
    local rowBias = 1.0
    if f.rowIndex then
        if f.rowIndex == 1 then rowBias = 1.20
        elseif f.rowIndex <= 3 then rowBias = 1.10
        elseif f.rowIndex <= 6 then rowBias = 1.02 end
    end

    return need * sustain * bounceFactor * rowBias
end

-- Score a frame as a Gift of the Naaru target: the OPPOSITE of the Chain Heal
-- bullseye. Wants an isolated (low-bounce) hurt target who is NOT already
-- covered -- someone a hard single-target HoT suits better than a chain.
local function GiftBullScore(f)
    if not f or not f:IsShown() then return 0 end
    if f.isPet then return 0 end
    if f.outOfRange or f.isDead then return 0 end

    -- Simplified: he wants the purple target on whoever's most hurt whenever Gift
    -- is off cooldown -- no isolation/sustained/bounce gates any more. Just needs
    -- someone actually down enough to be worth the instant HoT.
    local predicted = f.predicted or 0
    if predicted < GIFT_RULE.minDeficit then return 0 end
    return predicted
end

-- Read a frame's Earth Shield state, sim-aware. Returns charges, mine, other:
--   mine  = YOUR shield is on them
--   other = the OTHER shaman's shield is on them (exists but not yours)
local function ESStateOf(f)
    local charges, mine = ESCharges(f.unit)
    if not charges then return nil, false, false end
    return charges, mine, (not mine)   -- a shield exists but isn't yours = other's
end

-- Where SHOULD your Earth Shield go? Default is the tank/apex (durable, always
-- taking hits). But if that target is being OVERHEALED (lots of incoming, small
-- real hole), the shield's mitigation is wasted there -- move it to someone
-- taking damage who ISN'T getting healed. Never recommend a target the OTHER
-- shaman already shields. Returns a score; 0 = never put it here.
TUNE.esOverhealInc = 2000    -- inbound heals above this = "being looked after"
local function ESBullScore(f, other)
    if not f or not f:IsShown() then return 0 end
    if f.isPet or f.isDead or f.outOfRange then return 0 end
    if other then return 0 end                    -- other shaman already shields
    if f.class == "SHAMAN" then return 0 end       -- NEVER shield a shaman: it
                                                   -- knocks off their Water/
                                                   -- Lightning Shield (griefing)

    local rate      = f.rate or 0                 -- how hard they're being hit
    local incoming  = f.incoming or 0             -- inbound heals on them
    local deficit   = f.predicted or 0            -- hole left AFTER others' heals

    -- tank/apex base value: durable front-liners are the default home for ES
    local base = 0
    if f.rowIndex == 1 then base = 100
    elseif f.rowIndex and f.rowIndex <= 3 then base = 60
    elseif f.rowIndex and f.rowIndex <= 9 then base = 20
    else base = 5 end

    -- taking sustained damage makes ES more valuable (it procs on hits)
    local dmgFactor = 1 + math.min(2, rate / 300)

    -- OVERHEAL penalty: if lots of healing is already landing on them and their
    -- real hole is small, they don't need the shield -- knock the tank way down
    -- so a neglected damage-taker can win.
    local overhealed = (incoming >= TUNE.esOverhealInc and deficit < 400)
    if overhealed then base = base * 0.25 end

    -- a neglected damage-taker: real hole open AND little incoming -> boost
    local neglected = (deficit >= 700 and incoming < 500 and rate > 0)
    local neglectBoost = neglected and 1.8 or 1.0

    -- STALE GATE. A charge only fires when someone else hits them, so a deep
    -- health bar with no external damage behind it is worth nothing to a shield
    -- -- that is the life-tapping warlock, and also the melee who stood in fire
    -- once ten seconds ago. Multiplied, not zeroed: at the start of a pull
    -- NOBODY has been hit yet, and scaling everyone equally keeps the ordering
    -- intact instead of blanking the recommendation exactly when you want it.
    local staleFactor = 1
    local guid = f.unit and UnitGUID(f.unit)
    local lastHit = guid and ES_HOLD.hit[guid]
    if not lastHit or (GetTime() - lastHit) > ES_HOLD.stale then staleFactor = 0.15 end

    return base * dmgFactor * neglectBoost * staleFactor
end

-- ===================================================================
-- UNIFIED ROLE-CORNER RETICLE
-- One four-corner marker built from per-frame corner textures. Each corner is
-- coloured by which "best target" ROLE the frame holds:
--   Chain Heal (GREEN, jade healing-wave)  owns TOP-LEFT and BOTTOM-RIGHT
--   Earth Shield (AMBER/tan, totem shield)  owns TOP-RIGHT
--   Gift of the Naaru (ORANGE-RED, Naaru glow) owns BOTTOM-LEFT
-- A frame best for one role shows that role's corner(s); a frame best for
-- several shows several colours at once. Colours pulled from each spell's icon.
-- one table holds the role colours + corner helpers, to spare main-chunk locals
local CornerKit = {
    CHAIN = { 0.20, 0.90, 0.45 },   -- Chain Heal jade green
    ES    = { 0.90, 0.72, 0.35 },   -- Earth Shield amber/tan
    GIFT  = { 1.00, 0.45, 0.12 },   -- Gift of the Naaru orange-red
}
function CornerKit.draw(f, which, col)
    local c = f.corner and f.corner[which]
    if not c then return end
    local w = f:GetWidth() or FRAME_W
    local L = math.max(7, math.min(15, w * 0.26))   -- arm length
    local T = 3                                      -- thickness
    c.h:SetColorTexture(col[1], col[2], col[3], 1)
    c.v:SetColorTexture(col[1], col[2], col[3], 1)
    c.h:ClearAllPoints(); c.v:ClearAllPoints()
    if which == "TL" then
        c.h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0);  c.h:SetSize(L, T)
        c.v:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0);  c.v:SetSize(T, L)
    elseif which == "TR" then
        c.h:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); c.h:SetSize(L, T)
        c.v:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0); c.v:SetSize(T, L)
    elseif which == "BL" then
        c.h:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); c.h:SetSize(L, T)
        c.v:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0); c.v:SetSize(T, L)
    else -- BR
        c.h:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); c.h:SetSize(L, T)
        c.v:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0); c.v:SetSize(T, L)
    end
    c.h:Show(); c.v:Show()
end
function CornerKit.hide(f, which)
    local c = f.corner and f.corner[which]
    if c then c.h:Hide(); c.v:Hide() end
end

-- Does my Gift HoT already sit on this frame's target? Sim-aware, so the sim's
-- pre-Gifted player doesn't also wear the "put Gift here" corner.
local function HasGift(f)
    return (f.unit and GiftActive(f.unit)) and true or false
end

UpdateCornerReticles = function()
    if #frames == 0 then return end
    local DrawCorner, HideCorner = CornerKit.draw, CornerKit.hide
    local COL_CHAIN, COL_ES, COL_GIFT = CornerKit.CHAIN, CornerKit.ES, CornerKit.GIFT

    -- find the single best frame for each role (nil if none qualifies / toggle off)
    local chBest, chScore = nil, 0
    local esBest, esScore = nil, 0
    local gfBest, gfScore = nil, 0
    local esHolder, esHolderCharges = nil, nil   -- where MY shield sits right now

    -- ONE toggle for the whole unified corner reticle (was 3 inherited gates --
    -- bullseye/esReticle/giftBadge -- which meant if you'd turned bullseye or the
    -- gift badge off, those corners silently never showed). Gift still needs to
    -- be off cooldown to have a valid target.
    if not DB().corners then
        for _, f in ipairs(frames) do
            if f.corner then for _, ck in ipairs({ "TL","TR","BL","BR" }) do
                CornerKit.hide(f, ck)
            end end
        end
        return
    end
    local chOn   = true
    local esOn   = true
    local giftOn = (GiftReady() == true)

    for _, f in ipairs(frames) do
        if f:IsShown() and f.unit and not f.isDead then
            if chOn then
                local sc = BullScore(f)
                if sc > chScore then chBest, chScore = f, sc end
            end
            if esOn then
                -- ONE lookup, three answers. This used to call ESStateOf twice
                -- per frame per tick -- a doubled aura sweep for no new info.
                local charges, mine, other = ESStateOf(f)
                -- a peer's announced target counts as covered even before our
                -- own aura sweep catches up to their cast
                if not other and f.unit and COMM.ShieldedByPeer(UnitGUID(f.unit)) then
                    other = true
                end
                if mine then
                    esHolder, esHolderCharges = f, charges or 0
                end
                -- The holder is still scored, with an edge: when the shield does
                -- need renewing, refreshing it on the same tank is almost always
                -- right, and "re-shield who you already shielded" should not lose
                -- to a rounding error on somebody new.
                local sc = ESBullScore(f, other)
                if mine then sc = sc * ES_HOLD.sticky end
                if sc > esScore then esBest, esScore = f, sc end
            end
            if giftOn and not HasGift(f) then
                local sc = GiftBullScore(f)
                if sc > gfScore then gfBest, gfScore = f, sc end
            end
        end
    end

    -- hysteresis for the Chain Heal pick (kept from the old bullseye) so it
    -- doesn't flicker between two near-equal targets
    if chOn and bullTarget and bullTarget ~= chBest and bullTarget:IsShown() then
        local holder = BullScore(bullTarget)
        if holder > 0 and chScore < holder * TUNE.bullHysteresis then
            chBest, chScore = bullTarget, holder
        end
    end
    bullTarget = chBest
    bullScore  = chScore      -- /bish bull reads this; it sat at 0 forever once
                              -- the old UpdateBullseye stopped being called
    giftBullTarget = gfBest

    -- EARTH SHIELD: shut up while the shield is healthy.
    -- The old rule was "the holder can never be the recommendation", so the
    -- amber corner always pointed at SOMEBODY -- the second-best target, every
    -- tick, while your shield sat perfectly placed on the tank with five
    -- charges left. That is how a life-tapping warlock ends up looking like an
    -- instruction. A shield with charges left is not a decision you have to
    -- make, so no corner is drawn at all; the charge pips flashing on the last
    -- one are what should pull your eye, and they already do.
    if esHolder and (esHolderCharges or 0) >= (DB().esQuiet or ES_HOLD.quiet) then
        esBest, esScore = nil, 0
    elseif esBullTarget and esBest and esBullTarget ~= esBest
           and esBullTarget:IsShown() then
        -- down to the last pip (or bare): now it IS a decision, so pick -- but
        -- hold the standing answer unless the challenger clearly beats it,
        -- exactly like the Chain Heal bullseye does.
        local _, _, hOther = ESStateOf(esBullTarget)
        local holderSc = ESBullScore(esBullTarget, hOther)
        if holderSc > 0 and esScore < holderSc * ES_HOLD.margin then
            esBest, esScore = esBullTarget, holderSc
        end
    end
    esBullTarget = esBest      -- so the charge-pip last-charge flash matches the
                               -- amber corner (whichever frame is the ES target)

    -- paint every frame's corners from scratch each tick
    for _, f in ipairs(frames) do
        -- TL and BR = Chain Heal (green)
        if f == chBest then
            DrawCorner(f, "TL", COL_CHAIN)
            DrawCorner(f, "BR", COL_CHAIN)
        else
            HideCorner(f, "TL"); HideCorner(f, "BR")
        end
        -- TR = Earth Shield (amber)
        if f == esBest then DrawCorner(f, "TR", COL_ES) else HideCorner(f, "TR") end
        -- BL = Gift (orange-red)
        if f == gfBest then DrawCorner(f, "BL", COL_GIFT) else HideCorner(f, "BL") end
    end
end

-- ===================================================================
-- DEMO MODE  (/bish sim on)
-- Walks the features one at a time on your REAL group, with a caption saying
-- which one you are looking at. There is no fake roster: this only ever writes
-- to textures -- corners, pips, glow, bounce lines, the gauge -- so it cannot
-- feed made-up numbers into scoring, targeting or bindings the way the old
-- simulator did. Everything here is non-secure, so it also runs in combat,
-- which the old sim could not (it had to rebuild frames).
--
-- ENDS at DemoStart, ~400 lines down. Everything after that is the heal-race
-- engine and the bar painter, which sat under this banner for months with no
-- header of their own -- so the file read as though the demo were 1200 lines
-- and the snipe engine did not exist. Section headers are the map you use when
-- deciding what is safe to move, and a wrong one is worse than none.
local demoCaption = lineLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
demoCaption:Hide()

-- Park the caption clear of the bottom row. Row 1's top sits 26px under the
-- anchor's TOP and each row is FRAME_H + PAD deep, so this lands a few pixels
-- below the last row whether that is row 1 (solo) or row 6 (25-man). Recomputed
-- every paint, so it follows the roster without needing a relayout -- which
-- matters because the demo runs in combat, when relayout is blocked.
local function DemoPlaceCaption()
    demoCaption:ClearAllPoints()
    demoCaption:SetPoint("TOP", anchor, "TOP", 0,
                         -(26 + layoutRows * (FRAME_H + PAD) + 8))
end

local DEMO_STEPS = {
    "Chain Heal target -- green, top-left + bottom-right",
    "Earth Shield target -- amber, top-right",
    "Earth Shield charges -- amber pips, flashing on the last one",
    "Gift of the Naaru target -- orange, bottom-left",
    "All three roles on one frame",
    "Chain Heal bounce lines + full-chain burst",
    "Mana RPM gauge -- cruising through to overhealing",
    "Pulse -- who is under sustained damage",
    "Nature's Swiftness pip -- shift+scroll emergency (white = NS up)",
    "Wheel binds -- what each scroll direction casts",
    "Earth Shield stays put -- no new advice until the last pip",
    "Bar colours -- black, red when a downrank fits, flashing under fire",
    "Heal sizes -- tooltip vs what your casts actually land for",
    "Second shaman -- who is answering on the addon comm",
    "Their Chain Heal -- full bar where they aimed, stub for a bounce",
    "Heal race -- how many others are casting here, and who lands first",
    "Totem reach -- violet right edge: your totem is not reaching him",
    "Five-second rule -- the counter's regen column, and the seconds until spirit is back",
    "Curable debuff -- the square low on the right, in the debuff's colour",
}

-- visible frames, and the full-width ones (pips and numbers only live there)
local function DemoFrames()
    local all, wide = {}, {}
    for _, f in ipairs(frames) do
        if f:IsShown() then
            all[#all + 1] = f
            if not f.narrow and not f.isPet then wide[#wide + 1] = f end
        end
    end
    return all, wide
end

local function DemoClear(all)
    for _, f in ipairs(all) do
        for _, ck in ipairs({ "TL", "TR", "BL", "BR" }) do CornerKit.hide(f, ck) end
        if f.esPips then for i = 1, 6 do f.esPips[i]:Hide() end end
        if f.nsPip then f.nsPip:Hide() end
        if f.totemOut then f.totemOut:Hide() end
        if f.dispelMark then f.dispelMark:Hide() end
    end
end

local demoBounceAt = 0

DemoPaint = function()
    local now = GetTime()
    if now - demo.at >= DEMO_STEP then
        demo.at = now
        demo.step = (demo.step % #DEMO_STEPS) + 1
        demo.spot = demo.spot + 1
    end
    local step = demo.step
    if step < 1 then step = 1 end

    demoCaption:SetText(("|cff44dd88%d/%d|r  %s")
        :format(step, #DEMO_STEPS, DEMO_STEPS[step]))
    DemoPlaceCaption()
    demoCaption:Show()

    local all, wide = DemoFrames()
    if #all == 0 then return end
    DemoClear(all)

    -- the frame the demo is pointing at, hopping every second or so within a
    -- step so you can see the marker MOVE rather than sit still
    local hop = math.floor((now - demo.at) / 1.3)
    local a   = all[((demo.spot + hop) % #all) + 1]
    local w   = (#wide > 0) and wide[((demo.spot + hop) % #wide) + 1] or a

    if step == 1 then
        CornerKit.draw(a, "TL", CornerKit.CHAIN)
        CornerKit.draw(a, "BR", CornerKit.CHAIN)

    elseif step == 2 then
        CornerKit.draw(a, "TR", CornerKit.ES)

    elseif step == 3 then
        -- count 6 down to 1 across the step, flashing the last charge
        local left = 6 - math.floor(((now - demo.at) / DEMO_STEP) * 6)
        if left < 1 then left = 1 end
        CornerKit.draw(w, "TR", CornerKit.ES)
        if w.esPips then
            local fw = w:GetWidth() or FRAME_W
            local margin = math.max(10, math.min(18, fw * 0.26)) + 3
            local avail  = math.max(18, fw - 2 * margin)
            local pipW   = math.max(3, (avail - 5 * 2) / 6)
            local flash  = (math.floor(now * 3) % 2) == 0
            for i = 1, 6 do
                local pip = w.esPips[i]
                pip:ClearAllPoints()
                pip:SetSize(pipW, 3)
                pip:SetPoint("BOTTOMLEFT", margin + (i - 1) * (pipW + 2), 3)
                if i <= left then
                    pip:SetAlpha((left <= 1 and flash) and 0.2 or 1)
                    pip:Show()
                else
                    pip:Hide()
                end
            end
        end

    elseif step == 4 then
        CornerKit.draw(a, "BL", CornerKit.GIFT)

    elseif step == 5 then
        -- the overlap case: one frame that is best for everything at once
        CornerKit.draw(a, "TL", CornerKit.CHAIN)
        CornerKit.draw(a, "BR", CornerKit.CHAIN)
        CornerKit.draw(a, "TR", CornerKit.ES)
        CornerKit.draw(a, "BL", CornerKit.GIFT)

    elseif step == 6 then
        if DB().critBrag then
            demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cff888888three crits on a full chain also says \"%s\" in chat|r")
                :format(step, #DEMO_STEPS, DEMO_STEPS[step], UIX.BRAG))
        end
        if now >= demoBounceAt and #all >= 3 then
            demoBounceAt = now + 1.6
            local i0 = (demo.spot % #all) + 1
            local chain = {}
            for k = 0, 2 do chain[#chain + 1] = all[((i0 + k - 1) % #all) + 1] end
            local gold = (math.random() < 0.5) and DB().goldChains
            for k = 1, 2 do
                local l = GetLine()
                l:SetStartPoint("CENTER", chain[k])
                l:SetEndPoint("CENTER", chain[k + 1])
                -- same painter as the live path: a demo that draws its lines a
                -- different way is a demo that can lie about them, which is
                -- exactly how this bug survived four release candidates
                PaintLine(l, gold and UIX.LINE_GOLD or UIX.LINE_BLUE, gold and 5 or 3)
                l:SetAlpha(1)
                l:Show()
                activeLines[#activeLines + 1] = { line = l, born = now, gold = gold }
            end
            if gold and Celebrate and chain[1].unit then
                -- crits are faked as 0 here on purpose: Celebrate would fire the
                -- real party-chat brag on a triple crit, and a DEMO must never
                -- put words in your mouth in front of the raid
                Celebrate(UnitGUID(chain[1].unit), 0)
            end
        end

    elseif step == 7 then
        if DB().rpm and RPMPaint then
            rpmFrame:Show()
            local ph = ((now - demo.at) / DEMO_STEP)
            local target = 0.5 - 0.48 * math.cos(ph * math.pi * 2)
            local waste  = (ph > 0.62 and ph < 0.82) and 0.75 or 0.1
            rpmSmoothed = rpmSmoothed + (target - rpmSmoothed) * 0.15
            RPMPaint(rpmSmoothed, waste, target)
        end

    elseif step == 8 then
        local phase = 0.5 + 0.5 * math.sin(now * 5)
        local pc = UIX.PULSE_RED
        for k = 1, math.min(DB().pulseCap or PULSE_CAP, #all) do
            local f = all[((demo.spot + k) % #all) + 1]
            f.glow:SetColorTexture(pc[1], pc[2], pc[3], 0.15 + 0.40 * phase)
        end

    elseif step == 9 then
        -- NS pip: show BOTH states in one step, so the difference between
        -- "shot is live" and "still on cooldown" is visible side by side --
        -- the live painter can only ever show you one of them at a time.
        local live = (math.floor((now - demo.at) / 1.2) % 2) == 0
        for k = 0, math.min(1, #all - 1) do
            local f = all[((demo.spot + k) % #all) + 1]
            if f.nsPip then
                f.nsPip:SetWidth(math.max(10, (f:GetWidth() or FRAME_W) * 0.35))
                if (k == 0) == live then f.nsPip:SetColorTexture(1, 1, 1, 0.95)
                else f.nsPip:SetColorTexture(0.45, 0.45, 0.5, 0.6) end
                f.nsPip:Show()
            end
        end

    elseif step == 10 then
        -- The wheel binds have no artwork of their own -- they are four macros.
        -- What the demo CAN show is the one thing worth forgetting: which rank
        -- each direction actually casts on your current gear and training. So
        -- the caption cycles the four of them, read live off the button.
        local lines = {
            ("scroll up  --  %s"):format(WHEEL.down or WHEEL.HW),
            ("shift+scroll up  --  %s%s"):format(
                (WHEEL.ResolveKnown() and not DB().wheelStrict)
                    and (WHEEL.NS .. " + ") or "",
                WHEEL.max or WHEEL.HW),
            ("scroll down  --  %s"):format(WHEEL.lDown or WHEEL.LHW),
            ("shift+scroll down  --  %s"):format(WHEEL.lMax or WHEEL.LHW),
        }
        local which = (math.floor((now - demo.at) / (DEMO_STEP / 4)) % 4) + 1
        local shifted = (which % 2 == 0)
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cffffff00%s|r%s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], lines[which],
                    (shifted and DB().trinkets) and "  |cff888888(+ trinkets 13/14)|r" or ""))
        if DB().wheel == false then
            demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cffff5555wheel heals are OFF -- /bish wheel on|r")
                :format(step, #DEMO_STEPS, DEMO_STEPS[step]))
        end

    elseif step == 11 then
        -- The Earth Shield hand-off, played out: a healthy shield draining its
        -- charges with NO amber corner anywhere (nothing to decide), then the
        -- last pip flashing, and only then the corner appearing -- on the same
        -- target if he is still the right one. Watching it beats reading it.
        local host = w
        local ph = (now - demo.at) / DEMO_STEP          -- 0..1 across the step
        local left = 6 - math.floor(ph * 6)
        if left < 1 then left = 1 end
        if host.esPips then
            local fw = host:GetWidth() or FRAME_W
            local margin = math.max(10, math.min(18, fw * 0.26)) + 3
            local avail  = math.max(18, fw - 2 * margin)
            local pipW   = math.max(3, (avail - 5 * 2) / 6)
            local flash  = (math.floor(now * 3) % 2) == 0
            for i = 1, 6 do
                local pip = host.esPips[i]
                pip:ClearAllPoints()
                pip:SetSize(pipW, 3)
                pip:SetPoint("BOTTOMLEFT", margin + (i - 1) * (pipW + 2), 3)
                if i <= left then
                    pip:SetAlpha((left <= 1 and flash) and 0.2 or 1)
                    pip:Show()
                else
                    pip:Hide()
                end
            end
        end
        -- the corner only shows up once the shield is down to its last charge
        if left <= 1 then CornerKit.draw(host, "TR", CornerKit.ES) end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n%s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step],
                    (left > 1)
                      and ("|cff888888shield healthy (%d charges) -- no advice needed|r"):format(left)
                      or "|cffffff00last charge -- re-shield, same target unless someone clearly beats him|r"))

    elseif step == 12 then
        -- The three bar states, side by side, on real frames: idle black, the
        -- red that means a downranked Chain Heal now lands whole, and the red
        -- flash that means the damage has not stopped. Painted straight onto
        -- the bar textures, so what you are looking at IS the live appearance --
        -- the next live tick repaints them and nothing is left behind.
        local phase = 0.5 + 0.5 * math.sin(now * 5)
        local pc, red, idle = UIX.PULSE_RED, UIX.BAR_RED, UIX.BAR_IDLE
        for k = 1, #all do
            local f = all[k]
            local role = (k + demo.spot) % 3        -- 0 idle, 1 red, 2 flashing
            if role == 0 then
                f.hp:SetColorTexture(idle[1], idle[2], idle[3], idle[4])
                f.glow:SetColorTexture(1, 1, 1, 0)
            else
                f.hp:SetColorTexture(red[1], red[2], red[3], red[4])
                if role == 2 then
                    f.glow:SetColorTexture(pc[1], pc[2], pc[3], 0.15 + 0.40 * phase)
                else
                    f.glow:SetColorTexture(1, 1, 1, 0)
                end
            end
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cff888888black|r = nothing to do   |cffdd2222red|r = %s lands whole   |cffdd2222red flashing|r = still taking hits")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step],
                    (healOptions[1] and healOptions[1].cast) or "your downrank"))

    elseif step == 13 then
        -- Where the numbers come from. The spellbook shows a spell's BASE heal
        -- with no gear in it; everything the addon decides is sized off what the
        -- cast is really worth. Shown side by side so the gap is obvious -- it
        -- is usually a factor of three or four.
        local o = healOptions[#healOptions] or healOptions[1]
        local line
        if not o then
            line = "|cffff5555no heal ranks found -- set the spellbook to show ALL ranks, then /bish rescan|r"
        else
            local seen = o.id and DB().healSeen[o.id]
            line = ("|cff888888%s: spellbook says|r |cffff8844%d|r|cff888888, really lands for|r |cff44dd88%d|r|cff888888  (%s, healing power %d)|r")
                :format(o.cast or o.spell, math.floor(o.base or 0), math.floor(o.heal or 0),
                        o.measured and ("measured over %d casts"):format((seen and seen.n) or 0)
                                    or "estimated until 4 casts are logged",
                        math.floor(HEALSZ.SP()))
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n%s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], line))

    elseif step == 14 then
        -- Who else is out there. Nothing to draw -- the value of the comm is a
        -- fact, not a picture: either another BiSHealing shaman is answering
        -- and the Earth Shield plan is using their real charge size, or nobody
        -- is and it is reading their charges out of the combat log like always.
        local names, n = {}, 0
        for name, p in pairs(COMM.Live()) do
            n = n + 1
            local u = p.guid and GuidToUnit(p.guid)
            names[#names + 1] = ("%s (%d per charge%s)"):format(
                name, math.floor(p.heal or 0),
                u and (", shielding " .. (ShortName(UnitName(u)) or "?")) or "")
        end
        local line
        if not COMM.Channel() then
            line = "|cff888888not in a group -- nothing to coordinate with|r"
        elseif n == 0 then
            line = "|cff888888no other BiSHealing shaman answering; their charge size is being read out of the combat log|r"
        else
            line = "|cff44dd88" .. table.concat(names, "   ") .. "|r"
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n%s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], line))

    elseif step == 15 then
        -- Both halves of "the other shaman exists": a teal edge where their
        -- chain is about to land, and grey pips for charges of a shield that
        -- is not yours. Painted directly, so this is the real appearance.
        local c, pipT = UIX.CHAIN_IN, UIX.PIP_THEIRS
        local phase = 0.55 + 0.45 * math.sin(now * 6)
        -- primary and bounce, side by side: the whole point is that they are
        -- not the same news
        local prim = all[((demo.spot) % #all) + 1]
        local bnc  = all[((demo.spot + 1) % #all) + 1]
        if prim.chainIn then
            prim.chainIn:ClearAllPoints()
            prim.chainIn:SetPoint("TOPLEFT", 1, -1)
            prim.chainIn:SetPoint("BOTTOMLEFT", 1, 1)
            prim.chainIn:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * phase)
            prim.chainIn:Show()
        end
        if bnc.chainIn and bnc ~= prim then
            bnc.chainIn:ClearAllPoints()
            bnc.chainIn:SetPoint("LEFT", bnc, "BOTTOMLEFT", 1, (bnc:GetHeight() or 20) * 0.25)
            bnc.chainIn:SetHeight(math.max(4, (bnc:GetHeight() or 20) * 0.35))
            bnc.chainIn:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * 0.4 * phase)
            bnc.chainIn:Show()
        end
        if w.esPips then
            local fw = w:GetWidth() or FRAME_W
            local margin = math.max(10, math.min(18, fw * 0.26)) + 3
            local avail  = math.max(18, fw - 2 * margin)
            local pipW   = math.max(3, (avail - 5 * 2) / 6)
            for i = 1, 6 do
                local pip = w.esPips[i]
                pip:ClearAllPoints()
                pip:SetSize(pipW, 3)
                pip:SetPoint("BOTTOMLEFT", margin + (i - 1) * (pipW + 2), 3)
                pip:SetColorTexture(pipT[1], pipT[2], pipT[3], pipT[4])
                if i <= 4 then pip:Show() else pip:Hide() end
            end
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cff33ccccfull teal bar|r = they aimed there   |cff2a8a8adim stub|r = only catching a bounce, half size   |cff8888aagrey pips|r = their Earth Shield")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step]))

    elseif step == 17 then
        -- Totem reach: the violet right edge on two frames, painted directly.
        -- The caption names what the live check needs -- a buff totem down and
        -- a party member missing its buff -- because the demo cannot drop a
        -- totem for you and must not pretend to.
        local tc = UIX.TOTEM_OUT
        for k = 0, math.min(1, #all - 1) do
            local f = all[((demo.spot + k) % #all) + 1]
            if f.totemOut then
                f.totemOut:SetColorTexture(tc[1], tc[2], tc[3], tc[4])
                f.totemOut:Show()
            end
        end
        local down = (#AURAS.down > 0) and ("down now: " .. table.concat(AURAS.down, ", "))
                     or "no buff totem down right now"
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cff888888judged from the totem's buff, your own party only  --  %s|r")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], down))

    elseif step == 18 then
        -- Five-second rule: the counter is real, so the demo runs a fake clock
        -- through it -- 5.0 down to 0, then the column turning green as spirit
        -- regen is counted again. Nothing is written to the live clock.
        local ph = (now - demo.at) / DEMO_STEP           -- 0..1 across the step
        local left = 5 - ph * 7                          -- runs out at ~70%
        if left < 0 then left = 0 end
        local line
        if left > 0 then
            line = ("|cffff9944%.1fs|r |cff888888until spirit regen counts again -- the +N column is your while-casting regen|r"):format(left)
        else
            line = "|cff4dff88regen is back|r |cff888888-- the +N column now shows full spirit regen; the next mana-costing cast restarts the five seconds|r"
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n%s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], line))

    elseif step == 19 then
        -- Curable debuff: both colours this class can clear, side by side, so
        -- green-means-poison and brown-means-disease is learnt here and not
        -- during a Vashj pull. Painted directly onto the mark textures.
        local kinds = {}
        for kind in pairs(AURAS.CAN_CURE[select(2, UnitClass("player")) or ""] or { Poison = true }) do
            kinds[#kinds + 1] = kind
        end
        table.sort(kinds)
        local shown = {}
        for k = 1, math.min(#kinds, #all) do
            local f = all[((demo.spot + k) % #all) + 1]
            local kc = AURAS.KIND_COLOUR[kinds[k]] or AURAS.KIND_COLOUR.Poison
            if f.dispelMark then
                f.dispelMark:SetColorTexture(kc[1], kc[2], kc[3], 1)
                f.dispelMark:Show()
            end
            shown[#shown + 1] = ("|cff%02x%02x%02x%s|r"):format(kc[1] * 255, kc[2] * 255, kc[3] * 255, kinds[k])
        end
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n%s  |cff888888-- only the types you can cure ever light it; /bish dispel lists what each zone has thrown|r")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], table.concat(shown, "   ")))

    else
        -- The race counter, both outcomes side by side. A number on the right
        -- edge is how many OTHER healers have a cast in the air at that target;
        -- red means one of them lands before yours would, which is the cast you
        -- were about to waste.
        for k = 1, math.min(2, #all) do
            local f = all[((demo.spot + k) % #all) + 1]
            if f.race then
                f.race:SetText(tostring(k + 1))
                local rc = (k == 1) and UIX.RACE_WIN or UIX.RACE_LOSE
                f.race:SetTextColor(rc[1], rc[2], rc[3])
            end
        end
        local native = UnitGetIncomingHeals and
            "|cff888888reading the client's own heal prediction -- every healer, addon or not|r"
            or "|cffff5555this client has no heal prediction API; only LibHealComm users are visible|r"
        demoCaption:SetText(("|cff44dd88%d/%d|r  %s\n|cff8c8c94grey|r = heals converging here, yours lands first   |cffd92626red|r = someone else lands first   %s")
            :format(step, #DEMO_STEPS, DEMO_STEPS[step], native))
    end
end

local function DemoStop()
    demo.on = false
    demoCaption:Hide()
    local all = DemoFrames()
    DemoClear(all)
    for _, f in ipairs(all) do f.glow:SetColorTexture(1, 1, 1, 0) end
end

local function DemoStart()
    demo.on, demo.at, demo.step, demo.spot = true, GetTime(), 1, 0
end

-- Heals other players already have in the air on this unit, landing within our
-- cast window. Subtracting this is the whole point of HealComm: it stops the
-- bullseye and the colour bands from flagging someone who is about to be topped
-- off by three instant-casters before a 2.5s Chain Heal could ever land.
-- Two flavours of incoming, on purpose:
--   OthersIncoming -- heals from OTHER players, subtracted from the prediction
--     so the bullseye doesn't fight a heal you can't influence. Excludes yours
--     so your own pending cast doesn't cancel the reason you're casting it.
--   TotalIncoming  -- everyone's heals including your own, for the bar fill and
--     +N tag, so your cast shows landing just like everyone else's.
-- One HealComm read gives both figures: total (for the bar) and others-only
-- (for the prediction). The per-frame path calls IncomingBoth once instead of
-- two separate GUID lookups + two library iterations.
-- Which group members can heal at all. Role first where the client sets it,
-- class as the real filter -- on this client most raid members report no role,
-- so trusting UnitGroupRolesAssigned alone (as the popular sniping WeakAura
-- does) finds nobody and the whole thing quietly does nothing.
function SNIPE.Refresh()
    wipe(SNIPE.healers)
    -- YOU, always and explicitly. Relying on your raid token turning up in the
    -- roster scan means your own cast silently drops out of the race whenever
    -- that scan is incomplete -- and the one heal you can be certain about is
    -- your own. UnitIsUnit sorts out the duplicate if the scan finds you too.
    SNIPE.healers[1] = "player"
    for _, u in ipairs(RosterUnits()) do
        local _, class = UnitClass(u)
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        if role == "HEALER" or SNIPE.CLASSES[class] then
            SNIPE.healers[#SNIPE.healers + 1] = u
        end
    end
end

-- The race, for one target: how many other healers have a cast in the air at
-- them, when the first of those lands, and whether ours beats it.
-- Does this LibHealComm honour the per-caster argument? Older builds ignore it
-- and hand back the total for EVERY caster you ask about, which would credit a
-- heal to every healer in the group and make the number climb on its own.
-- Asking about a caster that cannot exist settles it in one call.
function SNIPE.HealCommPerCaster(guid)
    if SNIPE.perCaster ~= nil then return SNIPE.perCaster end
    if not (healCommOn and guid) then return false end
    local bogus = HealComm:GetHealAmount(guid, HealComm.CASTED_HEALS,
                                         GetTime() + 1, "Player-0000-DEADBEEF") or 0
    SNIPE.perCaster = (bogus == 0)
    return SNIPE.perCaster
end

function SNIPE.Read(unit)
    local c = SNIPE.cache[unit]
    local now = GetTime()
    if c and (now - c.at) < SNIPE.TTL then return c end
    c = c or {}
    c.at, c.n, c.lands, c.who, c.mineFirst, c.others = now, 0, nil, nil, false, 0
    c.total, c.mineCasting, c.unnamed = 0, false, nil

    if unit then
        local mineLands, attributed = nil, 0
        local guid = UnitGUID(unit)

        for _, h in ipairs(SNIPE.healers) do
            if UnitExists(h) then
                -- Two independent ways to know this healer is on this target,
                -- and a healer counts if EITHER says so. The native per-caster
                -- prediction misses anyone the client will not break out; the
                -- HealComm query misses anyone without the addon. Relying on
                -- only the first is why a second healer on the same target so
                -- often never made the number go up.
                local amt = UnitGetIncomingHeals and (UnitGetIncomingHeals(unit, h) or 0) or 0
                if amt == 0 and healCommOn and guid and SNIPE.HealCommPerCaster(guid) then
                    local hg = UnitGUID(h)
                    if hg then
                        amt = HealComm:GetHealAmount(guid, HealComm.CASTED_HEALS,
                                                     now + CAST_LEAD, hg) or 0
                    end
                end

                if amt > 0 then
                    local endTime = select(5, UnitCastingInfo(h))
                    local lands = (endTime and endTime > 0) and (endTime / 1000) or nil
                    if UnitIsUnit(h, "player") then
                        mineLands = lands
                        c.mineCasting = true
                    else
                        -- counted even when the cast bar is not readable. It
                        -- used to require a landing time, so a healer whose cast
                        -- we could not see was dropped from the count entirely
                        -- rather than merely being un-rankable.
                        c.n = c.n + 1
                        c.others = c.others + amt
                        attributed = attributed + amt
                        if lands and (not c.lands or lands < c.lands) then
                            c.lands = lands
                            c.who = UnitName(h)
                        end
                        c.who = c.who or UnitName(h)
                    end
                end
            end
        end

        -- Ground truth: the client's total minus our own share. If that is
        -- meaningfully bigger than everything we could put a name to, at least
        -- one more healer is on this target that neither source would attribute
        -- -- so say so rather than under-reporting a race we are losing.
        if UnitGetIncomingHeals then
            local total = UnitGetIncomingHeals(unit) or 0
            local mine  = UnitGetIncomingHeals(unit, "player") or 0
            local others = total - mine
            if others > attributed * 1.15 + 200 then
                c.n = c.n + 1
                c.others = others
                c.unnamed = true
            end
        end

        -- our own cast may not have started yet: fall back to when a Chain Heal
        -- started NOW would land, which is the decision actually being made
        -- The number is how many heals are converging on this target, YOURS
        -- INCLUDED. "One other healer" and "you and another healer" are the same
        -- situation, and showing 1 for it read as though you were not part of
        -- the pile-up you are standing in.
        c.total = c.n + (c.mineCasting and 1 or 0)

        mineLands = mineLands or (now + CAST_LEAD)
        if c.lands then
            c.mineFirst = mineLands <= c.lands
        elseif c.n > 0 then
            -- somebody is healing this target and we cannot time them. Claiming
            -- we win that race would be a guess dressed as information.
            c.mineFirst = nil
        else
            c.mineFirst = true
        end
    end

    SNIPE.cache[unit] = c
    return c
end

-- ===================================================================
-- HEAL RACE ENGINE
-- The other half of the snipe problem, and the half with the real numbers in
-- it. The table and the reasoning are at the top of the file (see SNIPE); these
-- are its methods, kept down here because they need the roster helpers.
--
--   IncomingBoth    one HealComm read, two answers: everyone's heals (for the
--                   bar fill) and other people's only (for the prediction, so
--                   your own pending cast never cancels its own reason)
--   SNIPE.Refresh   who in the group can heal at all -- class, not role: on
--                   this client most raid members report no role, so the
--                   popular WeakAura's role check finds nobody
--   SNIPE.Read      does someone else's heal land before mine, and is mine
--                   then wasted
-- ===================================================================

local function IncomingBoth(unit)
    if not unit then return 0, 0 end
    local others, total = 0, 0

    if healCommOn then
        local guid = UnitGUID(unit)
        if guid then
            local when = GetTime() + CAST_LEAD
            total  = HealComm:GetHealAmount(guid, HealComm.CASTED_HEALS, when) or 0
            others = HealComm:GetOthersHealAmount(guid, HealComm.CASTED_HEALS, when) or 0
        end
    end

    -- The client's own prediction, which covers healers HealComm cannot see.
    -- Taken as a MAXIMUM rather than a sum: the two sources overlap completely
    -- for anyone running a HealComm addon, and adding them would double-count
    -- every heal and talk you out of casts you should make.
    if UnitGetIncomingHeals then
        local nativeTotal = UnitGetIncomingHeals(unit) or 0
        local nativeMine  = UnitGetIncomingHeals(unit, "player") or 0
        local nativeOthers = nativeTotal - nativeMine
        if nativeOthers < 0 then nativeOthers = 0 end
        if nativeTotal  > total  then total  = nativeTotal end
        if nativeOthers > others then others = nativeOthers end
    end

    return others, total
end

-- thin wrappers kept for the /bish inc diagnostic and any single-value callers
local function OthersIncoming(unit) local o = IncomingBoth(unit); return o end
local function TotalIncoming(unit)  local _, t = IncomingBoth(unit); return t end

-- Damage per second over the recent window, plus whether it is SUSTAINED --
-- hits spread across the window rather than one spike that already stopped.
-- Someone who ate a big hit and stabilised should not read as an emergency.
local function DamageRate(guid)
    local w = dmgWindow[guid]
    if not w or #w == 0 then return 0, false end

    local now, cut = GetTime(), GetTime() - DMG_WINDOW
    local i = 1
    while i <= #w and w[i].t < cut do i = i + 1 end
    if i > 1 then
        local keep = {}
        for j = i, #w do keep[#keep + 1] = w[j] end
        dmgWindow[guid] = keep
        w = keep
    end
    if #w == 0 then return 0, false end

    local sum, recent = 0, 0
    for _, e in ipairs(w) do
        sum = sum + e.amt
        if now - e.t <= 2.0 then recent = recent + 1 end
    end

    -- sustained = still being hit in the last couple of seconds, more than once
    return sum / DMG_WINDOW, (recent >= 2)
end

-- Is Gift of the Naaru off cooldown right now? Returns nil if he doesn't have
-- the spell at all (not every race has it), so the badge simply never shows.
-- (assignment, not 'local function' -- it's forward-declared up top)
-- ===================================================================
-- AURAS, RANGE AND THE BAR PAINTER
-- Gift and Earth Shield charge reads (both cached -- aura scanning is the most
-- expensive thing this addon does, ~10k lookups a second across 25 frames if
-- left uncached), the Chain Heal range test, the colour bands, and UpdateBars,
-- which is the hot path everything else feeds.
-- ===================================================================

GiftReady = function()
    if not ResolveGiftKnown() then return nil end

    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ci = C_Spell.GetSpellCooldown(GIFT)
        if ci then start, dur = ci.startTime, ci.duration end
    elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(GIFT)
    end
    if not start then return true end
    -- dur <= 1.5 is the GCD, not the real cooldown
    if dur and dur > 1.5 and start > 0 then return false end
    return true
end

-- Nature's Swiftness off cooldown? Same shape as GiftReady, same GCD guard:
-- a duration at or under 1.5s is the global cooldown showing through, not the
-- real 3 minutes.
function WHEEL.Ready()
    if not WHEEL.ResolveKnown() then return nil end

    local start, dur
    if C_Spell and C_Spell.GetSpellCooldown then
        local ci = C_Spell.GetSpellCooldown(WHEEL.NS)
        if ci then start, dur = ci.startTime, ci.duration end
    elseif GetSpellCooldown then
        start, dur = GetSpellCooldown(WHEEL.NS)
    end
    if not start then return true end
    if dur and dur > 1.5 and start > 0 then return false end
    return true
end

COMM.Charges = nil    -- assigned just below, once ESCharges exists

-- Earth Shield charges remaining on a unit, and whether it's mine. Read live
-- from the aura so the badge is honest even if I lost track of the GUID.
-- (AURAS -- the aura-scan table with these caches -- is declared up by UIX,
-- because the demo reads it 400 lines above this point)

-- Is MY Gift of the Naaru HoT currently on this unit? Cached briefly like the
-- ES scan so it doesn't cost a full aura sweep per frame per tick.
-- (assignment, not 'local function' -- forward-declared up top)
GiftActive = function(unit)
    if not unit or not UnitExists(unit) then return false end
    local c = AURAS.giftCache[unit]
    local now = GetTime()
    if c and (now - c.at) < AURAS.GIFT_TTL then return c.on end
    local on = false
    for i = 1, 40 do
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not a then break end
            if a.name == GIFT and a.sourceUnit == "player" then on = true break end
        elseif UnitAura then
            -- unitCaster is the SEVENTH return in TBC Classic. Reading the
            -- eighth got isStealable (a boolean), so "is it mine" was always
            -- false on any client without C_UnitAuras. Check both slots: a
            -- boolean can never equal "player", so this cannot false-positive.
            local name, _, _, _, _, _, src7, src8 = UnitAura(unit, i, "HELPFUL")
            if not name then break end
            if name == GIFT and (src7 == "player" or src8 == "player") then on = true break end
        else break end
    end
    AURAS.giftCache[unit] = { at = now, on = on }
    return on
end

-- (assignment, not 'local function' -- forward-declared up top)
ESCharges = function(unit)
    if not unit or not UnitExists(unit) then return nil end

    -- Aura scanning is the single most expensive thing this addon does. At 10Hz
    -- across 25 frames it was ~10k lookups a second for a badge that only needs
    -- to be right a few times a second.
    local c = AURAS.esCache[unit]
    local now = GetTime()
    if c and (now - c.at) < AURAS.ES_TTL then return c.charges, c.mine end
    for i = 1, 40 do
        local name, _, count, _, _, _, _, _, _, spellId, _, _, _, _, _, srcUnit, srcAlt
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not a then break end
            if a.name == EARTH_SHIELD then
                local n, mine = a.applications or a.charges or 0, a.sourceUnit == "player"
                AURAS.esCache[unit] = { at = now, charges = n, mine = mine }
                return n, mine
            end
        elseif UnitAura then
            -- same off-by-one as GiftActive: unitCaster is return 7. With the
            -- eighth, `mine` was always false -> the charge pips never lit and
            -- the amber corner kept pointing at someone already shielded.
            name, _, count, _, _, _, srcUnit, srcAlt, _, spellId = UnitAura(unit, i, "HELPFUL")
            if not name then break end
            if name == EARTH_SHIELD then
                local n, mine = count or 0, (srcUnit == "player" or srcAlt == "player")
                AURAS.esCache[unit] = { at = now, charges = n, mine = mine }
                return n, mine
            end
        else
            break
        end
    end
    AURAS.esCache[unit] = { at = now, charges = nil, mine = nil }
    return nil
end
-- Both hung on COMM here, where they exist. COMM.State is defined near the top
-- of the file and needs them; a bare name up there is a nil global, silently.
COMM.Charges = ESCharges
COMM.Unit = GuidToUnit

-- ----------------------------------------------------------- totem reach --
-- Technique from the WA library (claude/wa-patterns-05 §1.2, the Shaman UI's
-- "totem OOR" icons), rebuilt here rather than pasted: a totem that is DOWN
-- whose buff is MISSING from a party member means he is standing outside it.
-- No range API needed -- in TBC every aura totem is a plain party buff, so the
-- buff's absence is the range check. Only totems that grant a buff can be
-- judged (Tremor, Grounding, Searing and friends have no aura to look for),
-- and only on my own party: totems never reach past the subgroup.
--
-- Totem name from the client -> the buff it puts on people. The rank suffix
-- and the word "Totem" come off first, so "Windfury Totem V" reads "Windfury".
AURAS.TOTEM_BUFF = {
    ["Healing Stream"]   = "Healing Stream",
    ["Mana Spring"]      = "Mana Spring",
    ["Mana Tide"]        = "Mana Tide",
    ["Strength of Earth"]= "Strength of Earth",
    ["Stoneskin"]        = "Stoneskin",
    ["Grace of Air"]     = "Grace of Air",
    ["Windfury"]         = "Windfury Totem",
    ["Wrath of Air"]     = "Wrath of Air Totem",
    ["Tranquil Air"]     = "Tranquil Air",
    ["Totem of Wrath"]   = "Totem of Wrath",
    ["Flametongue"]      = "Flametongue Totem",
    ["Fire Resistance"]  = "Fire Resistance",
    ["Frost Resistance"] = "Frost Resistance",
    ["Nature Resistance"]= "Nature Resistance",
}

-- Re-read the four totem slots. Runs on PLAYER_TOTEM_UPDATE and at login; the
-- per-unit cache is dropped so a fresh totem is judged on the next tick.
function AURAS.RefreshTotems()
    wipe(AURAS.down)
    wipe(AURAS.totemCache)
    if not GetTotemInfo then return end
    for slot = 1, 4 do
        local have, name = GetTotemInfo(slot)
        if have and name and name ~= "" then
            local base = name:gsub("%s+[IVX]+$", ""):gsub("%s+Totem$", "")
            local buff = AURAS.TOTEM_BUFF[base]
            if buff then AURAS.down[#AURAS.down + 1] = buff end
        end
    end
end

-- nil = nothing to judge (no aura totem down, not my party, dead)
-- true = every down totem's buff is on him; false = one is missing: out of reach
function AURAS.TotemReach(unit)
    if #AURAS.down == 0 or not unit or not UnitExists(unit) then return nil end
    local c = AURAS.totemCache[unit]
    local now = GetTime()
    if c and (now - c.at) < AURAS.TOTEM_TTL then return c.reach end
    local reach = nil
    local mine = UnitIsUnit(unit, "player") or (UnitInParty and UnitInParty(unit))
    if mine and not UnitIsDeadOrGhost(unit) then
        local has = {}
        for i = 1, 40 do
            local name
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
                name = a and a.name
            elseif UnitAura then
                name = UnitAura(unit, i, "HELPFUL")
            end
            if not name then break end
            has[name] = true
        end
        reach = true
        for _, buff in ipairs(AURAS.down) do
            if not has[buff] then reach = false break end
        end
    end
    AURAS.totemCache[unit] = { at = now, reach = reach }
    return reach
end

-- ---------------------------------------------------------------- dispel --
-- Technique from the WA library (claude/wa-patterns-05 §2.3, the T5/T6/Kara
-- raid-frame packs): the class decides which debuff TYPES are yours to clear,
-- and a frame only lights for those. The client already names every debuff's
-- type, so no list of spell ids is needed to know what you can cure -- what
-- the raid-frame packs add is the per-boss knowledge of what shows up, and
-- that is LEARNED here from what actually lands (db.dispelSeen, per zone)
-- rather than typed in from a third-party pack and trusted.
AURAS.CAN_CURE = {
    SHAMAN  = { Poison = true, Disease = true },
    PALADIN = { Poison = true, Disease = true, Magic = true },
    PRIEST  = { Disease = true, Magic = true },
    DRUID   = { Poison = true, Curse = true },
    MAGE    = { Curse = true },
}
AURAS.KIND_COLOUR = {   -- the client's DebuffTypeColor, with a fallback
    Poison  = { 0.00, 0.60, 0.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
}
function AURAS.CanCure(kind)
    if not AURAS.cure then
        local _, class = UnitClass("player")
        AURAS.cure = AURAS.CAN_CURE[class or ""] or {}
    end
    return kind and AURAS.cure[kind] or false
end

-- The first debuff on this unit that I can cure: name, kind. Cached like the
-- rest. Every hit is also banked per zone, which is how the per-boss list
-- writes itself: after one night in a raid, /bish dispel says what showed up.
function AURAS.Dispel(unit)
    if not unit or not UnitExists(unit) then return nil end
    local c = AURAS.dispelCache[unit]
    local now = GetTime()
    if c and (now - c.at) < AURAS.DISPEL_TTL then return c.name, c.kind end
    local hitName, hitKind
    for i = 1, 40 do
        local name, kind
        if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
            if not a then break end
            name, kind = a.name, a.dispelName
        elseif UnitAura then
            local n, _, _, k = UnitAura(unit, i, "HARMFUL")
            if not n then break end
            name, kind = n, k
        else
            break
        end
        if kind and AURAS.CanCure(kind) then
            hitName, hitKind = name, kind
            break
        end
    end
    -- a new sighting, not every re-read of the same debuff still sitting there
    if hitName and not (c and c.name == hitName) then AURAS.Bank(hitName, hitKind) end
    AURAS.dispelCache[unit] = { at = now, name = hitName, kind = hitKind }
    return hitName, hitKind
end

-- Bank a cured-type debuff under the zone it was met in. Capped so a season
-- of trash cannot grow the saved variables without bound.
AURAS.SEEN_CAP = 40
function AURAS.Bank(name, kind)
    local db = DB()
    db.dispelSeen = db.dispelSeen or {}
    local zone = (GetRealZoneText and GetRealZoneText()) or "?"
    if zone == "" then zone = "?" end
    local z = db.dispelSeen[zone]
    if not z then z = {}; db.dispelSeen[zone] = z end
    local rec = z[name]
    if not rec then
        local n = 0
        for _ in pairs(z) do n = n + 1 end
        if n >= AURAS.SEEN_CAP then return end
        rec = { kind = kind, n = 0 }
        z[name] = rec
    end
    rec.n = rec.n + 1
    rec.last = time and time() or 0
end

-- Range, measured against Chain Heal itself rather than a hardcoded yardage --
-- if the spell can't reach them, clicking is wasted motion. Note the bare
-- spell name: a "(Rank N)" suffix makes the range check return nil.
local function InCHRange(unit)
    if not unit or not UnitExists(unit) then return false end
    if C_Spell and C_Spell.IsSpellInRange then
        local r = C_Spell.IsSpellInRange(CHAIN_HEAL, unit)
        if r ~= nil then return r == true or r == 1 end
    end
    if IsSpellInRange then
        local r = IsSpellInRange(CHAIN_HEAL, unit)
        if r ~= nil then return r == 1 end
    end
    if UnitInRange then return (UnitInRange(unit)) end
    return true    -- can't tell: better to leave it clickable than fake a block
end

-- Which heal covers a hole of this size, and what colour says so.
local function BandFor(deficit)
    if #healOptions == 0 or deficit <= 0 then return nil end
    for _, o in ipairs(healOptions) do
        if o.heal >= deficit then return o end
    end
    return nil    -- nothing covers it: red
end

-- Nature's Swiftness pip. Lights the top edge of anyone whose predicted hole is
-- past what a max-rank Chain Heal fixes -- the case the wheel emergency exists
-- for. White = NS is up and the shot is live; dim grey = the hole is that deep
-- and NS is still down, which is worth knowing a second before you reach for it.
-- Runs off f.predicted, which the main loop has already written this tick.
WHEEL.PIP_FRAC = 0.85     -- of max-rank Healing Wave: below this, chain heal it
function WHEEL.Pips()
    local db = DB()
    if not db.nsPip or not db.wheel then
        for _, f in ipairs(frames) do if f.nsPip then f.nsPip:Hide() end end
        return
    end
    local floor = (WHEEL.maxHeal or 0) * WHEEL.PIP_FRAC
    if floor <= 0 then
        for _, f in ipairs(frames) do if f.nsPip then f.nsPip:Hide() end end
        return
    end
    local up = (WHEEL.Ready() == true)     -- one cooldown read per tick, not per frame
    for _, f in ipairs(frames) do
        if f.nsPip then
            if f:IsShown() and f.unit and (f.predicted or 0) >= floor
               and not f.outOfRange then
                f.nsPip:SetWidth(math.max(10, (f:GetWidth() or FRAME_W) * 0.35))
                if up then f.nsPip:SetColorTexture(1, 1, 1, 0.95)
                else       f.nsPip:SetColorTexture(0.45, 0.45, 0.5, 0.6) end
                f.nsPip:Show()
            else
                f.nsPip:Hide()
            end
        end
    end
end

-- The other shaman's chain, marked on whoever it is about to land on. Pulses
-- gently so it reads as in-flight rather than as another static role marker.
function COMM.PaintChains()
    local any = next(COMM.chain) ~= nil
    local now, c = GetTime(), UIX.CHAIN_IN
    local phase = any and (0.55 + 0.45 * math.sin(now * 6)) or 1
    for _, f in ipairs(frames) do
        if f.chainIn then
            local who, primary
            if any and f:IsShown() and f.unit then
                who, primary = COMM.ChainOn(UnitGUID(f.unit))
            end
            if who then
                f.chainIn:ClearAllPoints()
                if primary then
                    -- aimed here: full-height bar, full colour
                    f.chainIn:SetPoint("TOPLEFT", 1, -1)
                    f.chainIn:SetPoint("BOTTOMLEFT", 1, 1)
                    f.chainIn:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * phase)
                else
                    -- only a bounce: a stub, dimmed. Half a heal at best, so it
                    -- is a hint, not a "handled".
                    f.chainIn:SetPoint("LEFT", f, "BOTTOMLEFT", 1, (f:GetHeight() or 20) * 0.25)
                    f.chainIn:SetHeight(math.max(4, (f:GetHeight() or 20) * 0.35))
                    f.chainIn:SetColorTexture(c[1], c[2], c[3], (c[4] or 1) * 0.4 * phase)
                end
                f.chainIn:Show()
                f.chainWho, f.chainPrimary = who, primary
            else
                f.chainIn:Hide()
                f.chainWho, f.chainPrimary = nil, nil
            end
        end
    end
end

-- Visual update. Safe in combat: bar size, color and glow are not protected.
local elapsed, sampleAt = 0, 0
local healRebuildAt = nil
local BuildHealOptionsRef            -- assigned once the builder is defined

local function UpdateBars(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then return end
    elapsed = 0

    if healRebuildAt and GetTime() >= healRebuildAt then
        healRebuildAt = nil
        if BuildHealOptionsRef then BuildHealOptionsRef() end
    end

    -- During combat, sample how deep everyone sits. This is what says whether a
    -- charge would have landed on a full bar -- the difference between a shield
    -- that heals and one that overheals into nothing.
    if inFight and GetTime() - sampleAt >= 0.5 then
        sampleAt = GetTime()
        for _, u in ipairs(RosterUnits()) do
            if UnitExists(u) and not UnitIsDeadOrGhost(u) then
                local nm = UnitKey(u)
                local hp, hpMax = UnitHealth(u), UnitHealthMax(u)
                if nm and hpMax > 0 then
                    local h = hpSample[nm] or { n = 0, deficit = 0, hits = 0, combatTime = 0 }
                    h.n = h.n + 1
                    h.deficit = h.deficit + (hpMax - hp)
                    hpSample[nm] = h
                end
            end
        end
    end

    -- First pass: work out predicted deficit for everyone, so the pulse can be
    -- rationed to the few who actually need it.
    local pulseRank = {}

    -- Close a finished Chain Heal cluster on the CLOCK, not on your next cast.
    -- The cluster used to stay open until another Chain Heal landed, so the
    -- gold repaint and the celebration were bolted onto whatever you cast next
    -- -- seconds late, attached to the wrong heal, and never at all if that was
    -- your last chain of the pull. Flushing here fires both a beat after the
    -- real cast, which is where the eye expects them.
    if chCast.guid and chCast.Flush and (GetTime() - chCast.at) > CH_WINDOW then
        chCast.Flush()
    end
    COMM.Tick()
    if UpdateBounceLines then UpdateBounceLines() end
    if UpdateSparks then UpdateSparks() end
    if UpdateCastCounter then UpdateCastCounter() end
    if UpdateRPM then UpdateRPM() end

    -- per-tick values (not per-frame): checking Gift's cooldown 25x a tick is
    -- wasteful when the answer is identical for every frame
    local giftBadgeOn = DB().giftBadge
    local giftUp = giftBadgeOn and (GiftReady() == true) or false

    -- The one number the black bars turn on: the size of a downranked Chain
    -- Heal (max rank minus two). healOptions is sorted ascending, so [1] is the
    -- downrank whenever both are known -- and falls back to max rank alone if
    -- the spellbook only gave up one. Read once per tick, not per frame.
    UIX.redAt = 0
    for _, o in ipairs(healOptions) do
        if not o.max then UIX.redAt = o.heal or 0 end     -- the downrank
    end
    if UIX.redAt == 0 and healOptions[1] then UIX.redAt = healOptions[1].heal or 0 end
    UIX.redAt = UIX.redAt * (DB().redPct or 1)

    for i, f in ipairs(frames) do
        if not (f:IsShown() and f.unit and UnitExists(f.unit)) then
            -- not evaluated this pass: wipe the readings so nothing downstream
            -- (the bullseye especially) acts on a stale number
            f.predicted, f.rate, f.sustained = 0, 0, false
            f.outOfRange, f.isDead = true, false
            if f.inc then f.inc:SetText("") end
            if f.def then f.def:SetText("") end
            if f.incFill then f.incFill:Hide() end
            if f.giftIcon then f.giftIcon:Hide() end
            if f.esIcon then f.esIcon:Hide() end
            if f.es then f.es:SetText("") end
            if f.totemOut then f.totemOut:Hide() end
            if f.dispelMark then f.dispelMark:Hide() end
            f.dispelName = nil
        end
        if f:IsShown() and f.unit and UnitExists(f.unit) then
            local guid = UnitGUID(f.unit)
            local hp, hpMax = UnitHealth(f.unit), UnitHealthMax(f.unit)
            local rate, sustained = DamageRate(guid)
            local dead = UnitIsDeadOrGhost(f.unit)

            local barW = f:GetWidth() - 2
            -- dead players used to read as full health (UnitHealth can return a
            -- stale/max value on death). Empty the bar so a corpse never looks
            -- like a healthy target; the DEAD tag + colour are set below.
            -- hpW is declared HERE (outer scope) so the incoming-fill calc below
            -- can read it -- scoping it inside the else was the nil-hpW crash.
            local hpW
            if dead then
                hpW = 1
            else
                local pct = (hpMax > 0) and (hp / hpMax) or 0
                hpW = math.max(1, barW * pct)
            end
            f.hp:SetWidth(hpW)

            local inRange = InCHRange(f.unit)
            f:SetAlpha(inRange and 1 or 0.3)
            -- stashed for the bullseye, which scores frames after this pass
            f.outOfRange = not inRange
            f.isDead = dead
            local deficit = hpMax - hp
            -- where they will be when the cast lands, not where they are now,
            -- minus what other healers already have inbound (LibHealComm). This
            -- subtraction is the anti-snipe fix; without it the frame ignores
            -- heals already flying at the target.
            -- prediction subtracts OTHERS' heals only (don't cancel your own
            -- pending cast); the bar/tag show TOTAL so your cast lands visibly
            local othersInc, totalInc = IncomingBoth(f.unit)
            local predicted = deficit + rate * CAST_LEAD - othersInc
            if predicted < 0 then predicted = 0 end

            f.predicted = predicted
            f.incoming = totalInc
            f.rate = rate
            f.sustained = sustained

            -- who else is casting at this target, and do we beat them
            if f.race then
                local race = (DB().healRace ~= false) and SNIPE.Read(f.unit) or nil
                if race and race.n > 0 and not f.narrow and not f.isPet then
                    f.race:SetText(tostring(race.total or race.n))
                    local rc = (race.mineFirst == true and UIX.RACE_WIN)
                            or (race.mineFirst == false and UIX.RACE_LOSE)
                            or UIX.RACE_UNSURE
                    f.race:SetTextColor(rc[1], rc[2], rc[3])
                    f.raceLost = (race.mineFirst == false)
                    f.raceUnknown = (race.mineFirst == nil)
                    f.raceWho = race.who
                else
                    f.race:SetText("")
                    f.raceLost, f.raceWho, f.raceUnknown = nil, nil, nil
                end
            end

            -- totem reach: the violet right edge, only when a buff totem of
            -- mine is down and this party member is missing its buff
            if f.totemOut then
                -- an if, not `cond and X or nil`: the answer that matters here
                -- IS false, and `and/or` swallows a false into the `or` arm
                local reach = nil
                if DB().totemRange ~= false and not dead and not f.isPet then
                    reach = AURAS.TotemReach(f.unit)
                end
                if reach == false then
                    local tc = UIX.TOTEM_OUT
                    f.totemOut:SetColorTexture(tc[1], tc[2], tc[3], tc[4])
                    f.totemOut:Show()
                else
                    f.totemOut:Hide()
                end
            end

            -- a debuff this class can cure: the square in the client's colour
            if f.dispelMark then
                local dn, dk
                if DB().dispel ~= false and not dead then dn, dk = AURAS.Dispel(f.unit) end
                f.dispelName, f.dispelKind = dn, dk
                if dn then
                    local col = (DebuffTypeColor and DebuffTypeColor[dk]) or nil
                    local kc = AURAS.KIND_COLOUR[dk] or AURAS.KIND_COLOUR.Poison
                    if col and col.r then f.dispelMark:SetColorTexture(col.r, col.g, col.b, 1)
                    else f.dispelMark:SetColorTexture(kc[1], kc[2], kc[3], 1) end
                    f.dispelMark:Show()
                else
                    f.dispelMark:Hide()
                end
            end

            -- Gift of the Naaru badge: an ISOLATED target that took a real hit
            -- but has since settled. Chain Heal would waste a hard cast on one
            -- person; Gift's HoT tops them over 15s and frees the chain for a
            -- clumped group. Conditions: hurt enough for the HoT to land without
            -- big overheal, low bounce potential (isolated), NOT under sustained
            -- damage (safe for now), in range, and Gift off cooldown.
            -- Gift of the Naaru badge, INVERTED like the shield:
            --   faded icon = "put Gift here" (isolated, hurt, stable, Gift ready)
            --   lit icon   = your Gift HoT is already ticking on them
            -- So faded = todo, lit = done -- no more looking-already-applied.
            if f.giftIcon and giftBadgeOn and not f.isPet and not f.narrow
               and not (f.rowIndex and f.rowIndex > 6) then
                local hasGift = GiftActive(f.unit)

                -- icon is now LIT-ONLY: it confirms the HoT is ticking on them.
                -- The "put Gift here" suggestion moved to the big purple reticle
                -- (the small icon was too easy to miss in a 25-man). 'suggest' is
                -- still computed above but drives the reticle, not this icon.
                if hasGift then
                    f.giftIcon:Show()
                    f.giftIcon:SetDesaturated(false)
                    f.giftIcon:SetAlpha(1)
                else
                    f.giftIcon:Hide()
                end
            elseif f.giftIcon then
                f.giftIcon:Hide()
            end   -- Gift badge off / pet / overflow: no aura scan, icon hidden

            if f.inc then
                if f.isPet or f.narrow then
                    f.inc:SetText("")
                elseif totalInc and totalInc > 0 then
                    f.inc:SetText("+" .. (totalInc >= 1000
                        and ("%.1fk"):format(totalInc / 1000) or tostring(math.floor(totalInc))))
                else
                    f.inc:SetText("")
                end
            end

            -- deficit readout: how big the hole is right now, k-formatted. Hidden
            -- when they're near full so a healthy raid isn't a wall of numbers.
            if f.def then
                if not f.isPet and not f.narrow and not dead and deficit >= 400 then
                    f.def:SetText("-" .. (deficit >= 1000
                        and ("%.1fk"):format(deficit / 1000) or tostring(math.floor(deficit))))
                else
                    f.def:SetText("")
                end
            end

            -- incoming fill: from the current health edge up to where the bar
            -- would sit once inbound heals land (capped at full)
            if f.incFill then
                if DB().incomingFill and totalInc and totalInc > 0 and hpMax > 0 and not dead then
                    local healedPct = math.min(1, (hp + totalInc) / hpMax)
                    local healedW = barW * healedPct
                    local w = math.max(1, healedW - hpW)
                    f.incFill:ClearAllPoints()
                    f.incFill:SetPoint("TOP", f.hp, "TOP")
                    f.incFill:SetPoint("BOTTOM", f.hp, "BOTTOM")
                    f.incFill:SetPoint("LEFT", f.hp, "RIGHT")
                    f.incFill:SetWidth(w)
                    f.incFill:Show()
                else
                    f.incFill:Hide()
                end
            end

            if dead then
                f.hp:SetColorTexture(0.18, 0.16, 0.16, 0.95)  -- dark corpse grey
                f.glow:SetColorTexture(0, 0, 0, 0)
                f.name:SetTextColor(0.5, 0.5, 0.5)
                if f.def then f.def:SetText("|cffaa4444DEAD|r") end
                if f.inc then f.inc:SetText("") end
                if f.esIcon then f.esIcon:Hide() end
                if f.giftIcon then f.giftIcon:Hide() end
            elseif not inRange then
                -- grey: you cannot reach them, so which rank would fix it is
                -- not useful information and a pulse would just bait a click
                f.hp:SetColorTexture(0.35, 0.35, 0.35, 1)
                f.glow:SetColorTexture(0, 0, 0, 0.35)
            elseif DB().plainBars then
                -- BLACK UNTIL IT MATTERS. Twenty-five bars in four colours is a
                -- picture you stop reading -- the eye has nothing to lock onto.
                -- So a bar sits near-black and carries exactly one signal: red
                -- means the predicted hole has grown big enough that a
                -- downranked Chain Heal (max rank minus two) lands WHOLE, with
                -- none of it wasted. Because `predicted` already runs the hole
                -- forward by your real cast time, red means "by the time this
                -- lands it will fit", not "he is hurt right now".
                local redAt = UIX.redAt or 0
                local c = (redAt > 0 and predicted >= redAt) and UIX.BAR_RED
                          or UIX.BAR_IDLE
                f.hp:SetColorTexture(c[1], c[2], c[3], c[4])
                f.glow:SetColorTexture(1, 1, 1, 0)
                if DB().pulse and sustained and rate > 0 then
                    pulseRank[#pulseRank + 1] = { f = f, rate = rate }
                end

            else
                -- Legacy colour bands: the smallest heal that covers the
                -- predicted hole. Red means nothing you have covers it.
                local band = BandFor(predicted)
                if not band then
                    if predicted <= 0 then
                        f.hp:SetColorTexture(0.20, 0.55, 0.25, 1)   -- healthy
                    else
                        f.hp:SetColorTexture(0.85, 0.15, 0.15, 1)   -- past max rank
                    end
                else
                    local c = band.color
                    f.hp:SetColorTexture(c[1], c[2], c[3], 1)
                end
                f.glow:SetColorTexture(1, 1, 1, 0)
                if DB().pulse and sustained and rate > 0 then
                    pulseRank[#pulseRank + 1] = { f = f, rate = rate }
                end
            end

            -- Earth Shield CHARGE PIPS: six "_ _ _ _ _ _" segments along the
            -- bottom. N lit = N charges of YOUR shield left. Flash them at the
            -- last charge IF this frame is still the ES recommendation. The old
            -- ES icon badge is retired -- always hide it.
            f.esIcon:Hide(); f.es:SetText("")
            local pips = f.esPips
            local petSkip = f.isPet or f.narrow
            local charges, mine = nil, false
            if not petSkip then charges, mine = ESCharges(f.unit) end
            if pips then
                -- Shows ANY Earth Shield's charges now, not just your own. The
                -- stack count sits in the aura itself, so the other shaman's
                -- charges were being read every tick and thrown away before
                -- drawing -- a leftover from when this addon assumed it was the
                -- only shaman in the group. Yours are amber, theirs are grey.
                if (not petSkip) and charges and charges > 0 then
                    -- lay out and light N pips along the bottom
                    local n = math.min(6, math.floor(charges))
                    local fw = f:GetWidth() or FRAME_W
                    -- keep the pip strip clear of the bottom corners: leave a
                    -- margin ~= the corner arm length (L) at each end.
                    local margin = math.max(10, math.min(18, fw * 0.26)) + 3
                    local avail = math.max(18, fw - 2 * margin)
                    local gap = 2
                    local pipW = math.max(3, (avail - 5 * gap) / 6)
                    local startX = margin
                    local lastCharge = (charges <= 1) and mine
                    local flashOn = (math.floor(GetTime() * 3) % 2) == 0
                    -- amber = yours, grey = somebody else's. The last-charge
                    -- flash stays yours only: their refresh is not your call and
                    -- a flashing frame you cannot act on is just noise.
                    local pc = mine and UIX.PIP_MINE or UIX.PIP_THEIRS
                    for i = 1, 6 do
                        local pip = pips[i]
                        pip:ClearAllPoints()
                        pip:SetSize(pipW, 3)
                        pip:SetPoint("BOTTOMLEFT", startX + (i - 1) * (pipW + gap), 3)
                        pip:SetColorTexture(pc[1], pc[2], pc[3], pc[4])
                        if i <= n then
                            -- Flash on the last charge of MY shield, full stop.
                            -- It used to also require that frame be the current
                            -- recommendation -- but the recommendation is now
                            -- silent while the shield is healthy, and the whole
                            -- point of the flash is to be the thing that tells
                            -- you the shield is about to run out.
                            if lastCharge then
                                pip:SetAlpha(flashOn and 1 or 0.2)
                            else
                                pip:SetAlpha(1)
                            end
                            pip:Show()
                        else
                            pip:Hide()
                        end
                    end
                else
                    for i = 1, 6 do pips[i]:Hide() end
                end
            end
        end
    end

    -- Corners LAST: they score frames on predicted / rate / incoming, all of
    -- which the loop above just wrote. Running them first (as rc28 did) scored
    -- every frame on the PREVIOUS tick's numbers -- and on the tick right after
    -- a relayout, on the numbers of whoever used to occupy that frame slot.
    if UpdateCornerReticles then UpdateCornerReticles() end
    WHEEL.Pips()
    COMM.PaintChains()

    -- Demo paints OVER the live result, so it must run after the corner pass.
    if demo.on and DemoPaint then DemoPaint() end

    -- Pulse only the worst few under sustained damage. Six pulsing frames is
    -- noise you learn to ignore; two is a cue you act on.
    table.sort(pulseRank, function(a, b) return a.rate > b.rate end)
    -- Sustained damage FLASHES RED over the bar. Static red says "a downrank
    -- fits him"; a flashing red says "and it is still happening" -- two states
    -- you have to tell apart at a glance, so they are the same hue and only the
    -- motion differs.
    local phase = 0.5 + 0.5 * math.sin(GetTime() * 5)
    local pc = UIX.PULSE_RED
    for i = 1, math.min(DB().pulseCap or PULSE_CAP, #pulseRank) do
        local e = pulseRank[i]
        e.f.glow:SetColorTexture(pc[1], pc[2], pc[3], 0.15 + 0.40 * phase)
    end
end
anchor:SetScript("OnUpdate", UpdateBars)

-- ------------------------------------------------------- combat log feed --

local DMG_EVENTS = {
    SWING_DAMAGE = true, SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true, SPELL_BUILDING_DAMAGE = true, ENVIRONMENTAL_DAMAGE = true,
}

local function OnCombatLog()
    -- multiple returns, not a table: this fires constantly and a per-event
    -- table allocation would churn the garbage collector all fight
    local _, event, _, sourceGUID, sourceName, _, _, destGUID, destName, _, _, a12, a13, _, a15, a16, a17, a18
        = CombatLogGetCurrentEventInfo()

    if DMG_EVENTS[event] then
        -- decode the amount once; its arg position depends on the event type
        local amount
        if event == "SWING_DAMAGE" then amount = a12
        elseif event == "ENVIRONMENTAL_DAMAGE" then amount = a13
        else amount = a15 end
        if type(amount) ~= "number" then return end

        -- SELF-INFLICTED DAMAGE IS NOT DAMAGE TAKEN. A warlock spamming Life
        -- Tap (or standing in his own Hellfire) logs a stream of damage events
        -- on himself and sits permanently low on health. That used to read as
        -- "hit constantly, deep hole" -- the exact profile Earth Shield hunts
        -- for -- so the shield kept getting recommended onto the warlock while
        -- the paladin ate the boss. Earth Shield does not even proc on it: the
        -- charge fires on damage from an external source. Counting it was wrong
        -- twice over, so it is dropped here, before it can reach the hit rate,
        -- the fight totals, or the pyramid ranking.
        if sourceGUID and sourceGUID == destGUID then
            local u = guidMap[destGUID]
            local nm = u and UnitKey(u)
            if nm then
                local h = hpSample[nm] or { n = 0, deficit = 0, hits = 0, combatTime = 0 }
                h.selfHits = (h.selfHits or 0) + 1
                h.selfDmg  = (h.selfDmg or 0) + amount
                hpSample[nm] = h
            end
            return
        end

        if fightDmg[destGUID] ~= nil then
            ES_HOLD.hit[destGUID] = GetTime()   -- last EXTERNAL hit, for ES gating
            -- incoming: someone in the raid took damage
            local u = guidMap[destGUID]
            if u then
                local nm = UnitKey(u)
                if nm then
                    local h = hpSample[nm] or { n = 0, deficit = 0, hits = 0, combatTime = 0 }
                    h.hits = h.hits + 1
                    hpSample[nm] = h
                end
            end
            fightDmg[destGUID] = fightDmg[destGUID] + amount
            local w = dmgWindow[destGUID]
            if not w then w = {}; dmgWindow[destGUID] = w end
            w[#w + 1] = { t = GetTime(), amt = amount }
        elseif fightDone[sourceGUID] ~= nil then
            -- outgoing: a raid member dealt damage to something NOT in the raid.
            -- elseif (not a second if) makes the incoming/outgoing split explicit
            -- and impossible to double-count -- a raid member hitting another
            -- raid member counts as incoming only, never as boss damage.
            fightDone[sourceGUID] = fightDone[sourceGUID] + amount
        end
        return
    end

    local spellName = a13

    -- RPM: log my own landed heals with their overheal, so the gauge knows both
    -- throughput and waste. Mana spend is sampled separately (below) since the
    -- combat log doesn't carry it.
    if sourceGUID == playerGUID
       and (event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL") then
        local raw  = tonumber(a15) or 0
        local over = tonumber(a16) or 0
        rpmWindow[#rpmWindow + 1] = { t = GetTime(), raw = raw, over = over }

        -- Learn what this rank is really worth. heal + overheal, because a cast
        -- that lands on a nearly-full bar is not a small cast -- it is a big one
        -- that was wasted, and sizing the colour bands off the wasted figure
        -- would teach the addon that its own advice never works.
        -- Chain Heal is handled in the cluster code below instead: only the
        -- FIRST target of a chain is the full-size heal, the jumps are halved,
        -- and averaging those in would undersize the spell by about a third.
        if event == "SPELL_HEAL" and a13 ~= CHAIN_HEAL and a13 ~= EARTH_SHIELD then
            HEALSZ.Learn(a12, raw + over, a18, over)
        end
    end

    -- Earth Shield, handled before the "was it me" filter on purpose: the proc
    -- may be credited to the shielded player, not the caster, so filtering on
    -- source first threw every charge away.
    if spellName == EARTH_SHIELD then
        if rawES then
            Print(("|cffaaaaaa%s|r src=%s dst=%s amt=%s")
                  :format(tostring(event), tostring(sourceName or "?"),
                          tostring(destName or "?"), tostring(a15)))
        end

        local run = esRuns[destGUID]

        if event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
            if run then
                local now = GetTime()
                if run.last then
                    local gap = now - run.last
                    if not run.minGap or gap < run.minGap then run.minGap = gap end
                end
                local raw  = tonumber(a15) or 0
                local over = tonumber(a16) or 0
                run.procs  = run.procs + 1
                run.healed = run.healed + raw
                run.effective = (run.effective or 0) + math.max(0, raw - over)
                run.last   = now

                -- charge size is a property of the CASTER's healing power, and
                -- it decides which shaman should take which target
                if run.caster then
                    local c = esCasterHeal[run.caster] or { n = 0, sum = 0 }
                    c.n, c.sum = c.n + 1, c.sum + raw
                    esCasterHeal[run.caster] = c
                end
            end
            return
        end

        if event == "SPELL_AURA_REMOVED_DOSE" then
            if run then
                run.doses = (run.doses or 0) + 1
                run.caster = run.caster or sourceName    -- dose names the caster
            end
            return
        end

        if event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH" then
            if sourceGUID == playerGUID then esTarget = destGUID end
            local u = GuidToUnit(destGUID)
            esRuns[destGUID] = {
                guid = destGUID, target = (u and UnitName(u)) or destName or "?",
                caster = sourceName, mine = (sourceGUID == playerGUID),
                start = GetTime(), procs = 0, healed = 0, effective = 0,
                doses = 0, minGap = nil, last = nil,
            }
            return
        end

        if event == "SPELL_AURA_REMOVED" and run then
            run.dur = GetTime() - run.start
            table.insert(esLog, 1, run)
            while #esLog > 30 do table.remove(esLog) end

            -- fold into long-term per-target history
            local rec = PlayerRec(run.target)
            rec.es = rec.es or { apps = 0, charges = 0, healed = 0, effective = 0, secs = 0 }
            rec.es.apps      = rec.es.apps + 1
            rec.es.charges   = rec.es.charges + (run.doses or run.procs or 0)
            rec.es.healed    = rec.es.healed + run.healed
            rec.es.effective = rec.es.effective + (run.effective or 0)
            rec.es.secs      = rec.es.secs + run.dur

            if run.guid == esTarget then esTarget = nil end
            esRuns[destGUID] = nil
            return
        end

        return
    end

    -- Another shaman's Chain Heal landing. Late, but free -- and it is the only
    -- source that works when nobody in the group runs a HealComm addon.
    if event == "SPELL_HEAL" and a13 == CHAIN_HEAL and sourceGUID ~= playerGUID then
        COMM.MarkChain(destGUID, sourceName or "another shaman", COMM.CHAIN_HOLD,
                       COMM.ForeignChainRole(sourceGUID))
    end

    if sourceGUID ~= playerGUID then return end

    -- Chain Heal bounces: one cast makes a separate SPELL_HEAL per jump, all
    -- within a fraction of a second. First heal is the primary target; the
    -- rest are bounces credited to them.
    if event == "SPELL_HEAL" and spellName == CHAIN_HEAL then
        local now = GetTime()
        if chCast.guid and (now - chCast.at) <= CH_WINDOW then
            chCast.hits = chCast.hits + 1
            if a18 then chCast.crits = chCast.crits + 1 end
            if DrawBounce then DrawBounce(chCast.lastGUID, destGUID) end
            chCast.lastGUID = destGUID
        else
            if chCast.guid and chCast.hits > 0 then
                local u = GuidToUnit(chCast.guid)
                local nm = u and UnitKey(u)
                if nm then
                    local rec = PlayerRec(nm)
                    rec.bounce.n = rec.bounce.n + 1
                    rec.bounce.sum = rec.bounce.sum + chCast.hits
                end
                if verboseBounce then
                    Print(("chain heal on %s -> %d target(s)")
                          :format((nm or "?"):match("^[^-]+") or "?", chCast.hits))
                end
                if FinishChain then FinishChain(chCast.hits) end
                if chCast.hits >= 3 and Celebrate then Celebrate(chCast.guid, chCast.crits) end
            end
            chCast.guid, chCast.at, chCast.hits, chCast.lastGUID = destGUID, now, 1, destGUID
            chCast.crits = a18 and 1 or 0
            -- this is the primary target: full-size heal, safe to learn from
            HEALSZ.Learn(a12, (tonumber(a15) or 0) + (tonumber(a16) or 0), a18,
                         tonumber(a16) or 0)
        end
    end
end

-- Flush a Chain Heal cluster that ended without a following cast.
local function FlushChainHeal()
    if chCast.guid and chCast.hits > 0 then
        local u = GuidToUnit(chCast.guid)
        local nm = u and UnitKey(u)
        if nm then
            local rec = PlayerRec(nm)
            rec.bounce.n = rec.bounce.n + 1
            rec.bounce.sum = rec.bounce.sum + chCast.hits
        end
        if FinishChain then FinishChain(chCast.hits) end
        if chCast.hits >= 3 and Celebrate then Celebrate(chCast.guid, chCast.crits) end
    end
    chCast.guid, chCast.at, chCast.hits, chCast.lastGUID, chCast.crits = nil, 0, 0, nil, 0
end
-- Hung on the tracking table rather than a new local: this file is one chunk
-- and Lua 5.1 caps a chunk at 200 locals. UpdateBars is defined above this
-- point and needs to reach it, and a field cannot be shadowed by a late local.
chCast.Flush = FlushChainHeal


-- ---------------------------------------------------------- celebration --
-- A little starburst on the primary frame when a Chain Heal reaches all three
-- targets -- the ideal cast, so it is worth a wink of reward. Particles are
-- non-secure textures on the line layer; pure cosmetic.


-- Three targets AND three crits: say it out loud, once. Throttled hard, because
-- the difference between a moment and a nuisance is entirely how often it
-- happens.
--
-- PARTY ONLY, deliberately. In a raid that reaches your subgroup and nobody
-- else, which is the whole point -- twenty-four people who did not cast it do
-- not need to hear about it, and a healer who brags to raid chat once a pull
-- gets muted. Solo, it prints to your own frame instead of erroring at a
-- channel you are not in.
function UIX.Brag()
    if not DB().critBrag then return end
    local now = GetTime()
    if now - (UIX.bragAt or 0) < (DB().bragGap or UIX.BRAG_GAP) then return end
    UIX.bragAt = now
    if SendChatMessage and IsInGroup and IsInGroup() then
        pcall(SendChatMessage, UIX.BRAG, "PARTY")
    else
        Print(UIX.BRAG)
    end
end

Celebrate = function(primaryGUID, crits)
    if (crits or 0) >= 3 then UIX.Brag() end   -- brag even if the fireworks are off
    if not DB().celebrate then return end
    -- find the frame to burst from; fall back to the anchor if it's off-group
    local host
    for _, f in ipairs(frames) do
        if f:IsShown() and f.unit and UnitGUID(f.unit) == primaryGUID then host = f break end
    end
    host = host or anchor
    local cx, cy = host:GetCenter()
    if not cx then return end

    -- ALL THREE CRIT = a big explosion: triple the particles, bigger stars,
    -- faster spread, gold-white sparks. A normal 3-chain stays a modest burst.
    local allCrit = (crits or 0) >= 3
    local n = allCrit and 32 or 10
    local baseSpeed = allCrit and 130 or 60
    local spread = allCrit and 90 or 50
    local sz = allCrit and 34 or 18
    for i = 1, n do
        local ang = (i / n) * math.pi * 2 + math.random() * 0.3
        local speed = baseSpeed + math.random() * spread
        local t = GetSpark()
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        t:SetSize(sz, sz)
        if allCrit then
            -- gold-white for the big one
            t:SetVertexColor(1, 0.9 + 0.1 * math.random(), 0.4 + 0.4 * math.random())
        else
            local hue = math.random()
            t:SetVertexColor(0.6 + 0.4 * math.random(), 0.7 + 0.3 * math.random(), 0.3 + hue * 0.5)
        end
        t:SetAlpha(1)
        t:Show()
        activeSparks[#activeSparks + 1] = {
            tex = t, born = GetTime(),
            x0 = cx, y0 = cy,
            vx = math.cos(ang) * speed, vy = math.sin(ang) * speed,
            big = allCrit,
        }
    end
end

UpdateSparks = function()
    local now = GetTime()
    for i = #activeSparks, 1, -1 do
        local s = activeSparks[i]
        local age = now - s.born
        local life = s.big and (UIX.SPARK_LIFE * 1.5) or UIX.SPARK_LIFE
        if age >= life then
            s.tex:Hide()
            table.remove(activeSparks, i)
        else
            local f = age / life
            local x = s.x0 + s.vx * age
            local y = s.y0 + s.vy * age - 90 * age * age   -- gravity
            s.tex:ClearAllPoints()
            s.tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
            s.tex:SetAlpha(1 - f)
            local base = s.big and 34 or 18
            local sz = base * (1 - 0.4 * f)
            s.tex:SetSize(sz, sz)
            s.tex:SetRotation(age * 6)
        end
    end
end

-- ------------------------------------------------------ fight boundaries --

local function StartFight()
    inFight = true
    wipe(hpSample)
    fightStart = GetTime()
    lastManaSample = nil
    rpmSmoothed = 0
    rpmState = "cruising"
    wipe(rpmWindow)
    wipe(spendWindow)
    RebuildGuidMap()
    wipe(fightDmg)
    wipe(fightDone)
    for _, u in ipairs(RosterUnits()) do
        local g = UnitGUID(u)
        if g then fightDmg[g] = 0; fightDone[g] = 0 end
    end
end

local function EndFight()
    inFight = false
    FlushChainHeal()

    local dur = GetTime() - fightStart
    if dur >= SCORE.minFight then
        -- rank this fight to mark who finished in the top third (by damage TAKEN,
        -- which drives healing priority). Include anyone who took damage OR dealt
        -- boss damage, so a ranged/pet that took nothing still logs its boss-DPS.
        local rows = {}
        local seen = {}
        for guid, dmg in pairs(fightDmg) do
            if dmg > 0 then rows[#rows + 1] = { guid = guid, dmg = dmg }; seen[guid] = true end
        end
        -- the top-third cut is based only on damage-taken rows, computed before we
        -- append the took-no-damage-but-dealt-damage units (they finish bottom)
        table.sort(rows, function(a, b) return a.dmg > b.dmg end)
        local topCut = math.max(1, math.floor(#rows / 3))
        for guid, done in pairs(fightDone) do
            if done > 0 and not seen[guid] then
                rows[#rows + 1] = { guid = guid, dmg = 0, noTaken = true }
            end
        end

        for i, r in ipairs(rows) do
            local u = GuidToUnit(r.guid)
            local nm = u and UnitKey(u)
            if nm then
                local rec = PlayerRec(nm)
                local done = (fightDone[r.guid] or 0) / dur   -- boss-DPS this fight
                -- took-no-damage units are never "top third" for healing purposes
                local top = (not r.noTaken) and (i <= topCut) or false
                table.insert(rec.fights, 1, { dps = r.dmg / dur, done = done, top = top })
                while #rec.fights > SCORE.keep do table.remove(rec.fights) end
            end
        end
    end

    -- fold this fight's health-depth and hit-rate samples into history
    if dur >= SCORE.minFight then
        for nm, h in pairs(hpSample) do
            local rec = PlayerRec(nm)
            rec.depth = rec.depth or { n = 0, deficit = 0, hits = 0, secs = 0 }
            rec.depth.n       = rec.depth.n + h.n
            rec.depth.deficit = rec.depth.deficit + h.deficit
            rec.depth.hits    = rec.depth.hits + h.hits
            rec.depth.secs    = rec.depth.secs + dur
            -- kept only so /bish score can show you WHY someone who looks like
            -- a damage magnet is not ranked as one
            if (h.selfHits or 0) > 0 then
                rec.selfHits = (rec.selfHits or 0) + h.selfHits
                rec.selfDmg  = (rec.selfDmg or 0) + (h.selfDmg or 0)
            end
        end
    end
    wipe(hpSample)
    wipe(dmgWindow)    -- otherwise every GUID ever hit leaks a table

    Relayout()
end

-- ---------------------------------------------------------------- events --

local ev = CreateFrame("Frame")
local EVENTS = {
    "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "GROUP_ROSTER_UPDATE", "COMBAT_LOG_EVENT_UNFILTERED",
    "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    "CHAT_MSG_ADDON", "UNIT_SPELLCAST_SENT", "UNIT_HEAL_PREDICTION",
    "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_TOTEM_UPDATE",
}
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM.PREFIX)
elseif RegisterAddonMessagePrefix then
    pcall(RegisterAddonMessagePrefix, COMM.PREFIX)
end
for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        COMM.OnMessage(...)

    elseif event == "UNIT_HEAL_PREDICTION" then
        -- fires whenever anyone's inbound heals change: drop the cached race so
        -- the next paint reads it fresh, rather than polling every tick
        wipe(SNIPE.cache)

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- the five-second rule clock: did that cast cost mana?
        if (...) == "player" then UIX.FSRCast() end

    elseif event == "PLAYER_TOTEM_UPDATE" then
        AURAS.RefreshTotems()

    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, _, spellID = ...
        if unit == "player" then
            local name = spellID and GetSpellInfo and GetSpellInfo(spellID)
            if name == CHAIN_HEAL then COMM.SendChainCast(target) end
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()

    elseif event == "PLAYER_REGEN_DISABLED" then
        StartFight()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- wheel binds first: a rebind asked for mid-fight (toggle, rescan, rank
        -- change) has been sitting queued, and Relayout below may not run.
        if WHEEL.pending then WHEEL.pending = false; WHEEL.Apply() end
        if inFight then EndFight()
        elseif pendingReorder then pendingReorder = false; Relayout() end

    elseif event == "SPELLS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        healRebuildAt = GetTime() + 1     -- these fire in bursts; settle first
        -- A respec into or out of Nature's Swiftness fires this. The answer was
        -- cached at login, so without dropping it here the wheel keeps casting a
        -- talent he no longer has -- or refuses to use one he just took.
        WHEEL.known = nil

    elseif event == "PLAYER_ENTERING_WORLD" then
        RebuildGuidMap()
        if not InCombatLockdown() then Relayout() end

    elseif event == "GROUP_ROSTER_UPDATE" then
        RebuildGuidMap()
        SNIPE.Refresh()
        COMM.Tick(true)      -- new group: introduce yourself
        if InCombatLockdown() then pendingReorder = true else Relayout() end

    elseif event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        RebuildGuidMap()
        SNIPE.Refresh()
        AURAS.RefreshTotems()      -- a reload mid-fight does not lose the totems
        -- HealComm fires these as heals start/change/land; we don't need the
        -- args, just a nudge that inbound changed. The next visual tick re-reads
        -- the live amounts, so a no-op handler is enough to stay current.
        if HealComm then
            -- Started/updated carry the caster, the spell and every target the
            -- cast is going to touch. That is exactly the other shaman's chain,
            -- announced while it is still in the air.
            local function started(_, casterGUID, spellID, _, endTime, ...)
                if casterGUID == playerGUID then return end
                local name = spellID and GetSpellInfo and GetSpellInfo(spellID)
                if name ~= CHAIN_HEAL then return end
                local who = GuidToUnit(casterGUID)
                who = (who and UnitName(who)) or "another shaman"
                local left = endTime and ((endTime / 1000) - GetTime()) or 0
                if left < 0 then left = 0 end
                -- HealComm lists the targets in cast order, so the first is
                -- where they aimed and the rest are jumps.
                for i = 1, select("#", ...) do
                    COMM.MarkChain(select(i, ...), who, left + COMM.CHAIN_HOLD, i == 1)
                end
            end
            local function stopped(_, casterGUID, _, _, interrupted, ...)
                if casterGUID == playerGUID or not interrupted then return end
                for i = 1, select("#", ...) do
                    COMM.chain[select(i, ...)] = nil   -- they were cut off
                end
            end
            HealComm.RegisterCallback(ADDON, "HealComm_HealStarted", started)
            HealComm.RegisterCallback(ADDON, "HealComm_HealUpdated", started)
            HealComm.RegisterCallback(ADDON, "HealComm_HealDelayed", started)
            HealComm.RegisterCallback(ADDON, "HealComm_HealStopped", stopped)
        end
        -- via the forward reference: the builder is defined further down the
        -- file than this handler, so calling it by name here would be nil
        if BuildHealOptionsRef then BuildHealOptionsRef() end
        local db = DB()
        if db.pos then
            anchor:ClearAllPoints()
            anchor:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
        end
        Relayout()
        COMM.Tick(true)
        local vis = 0
        for _, f in ipairs(frames) do if f:IsShown() then vis = vis + 1 end end
        Print(("v%s loaded -- %d frame(s) up. Ordering is rough until it has a few fights.")
              :format(VERSION, vis))
        if vis == 0 then
            Print("no frames visible: |cffffff00/bish show|r, or |cffffff00/bish center|r if they are off screen")
        end
    end
end)

-- ----------------------------------------------------------------- slash --

-- ---------------------------------------------------------- rank probe --
-- Answers the big open question: with the spellbook set to show ALL ranks,
-- does the API enumerate them? If this lists Rank 1..N per spell, downranking
-- is real and every colour band and bind in the plan is buildable. If it still
-- lists one entry per spell, the filter only changes what the UI draws.

local PROBE_SPELLS = { [CHAIN_HEAL] = true, [EARTH_SHIELD] = true,
                       ["Healing Wave"] = true, ["Lesser Healing Wave"] = true }

local PLAYER_BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local function BookName(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        return C_SpellBook.GetSpellBookItemName(i, PLAYER_BANK)
    end
    if GetSpellBookItemName then return GetSpellBookItemName(i, "spell") end
    return nil
end

local function NumSpells()
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local total = 0
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info then
                total = math.max(total, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0))
            end
        end
        return total
    end
    return 1000
end

local function BookSpellID(i)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(i, PLAYER_BANK)
        return info and (info.spellID or info.actionID)
    end
    if GetSpellBookItemInfo then
        local a, b = GetSpellBookItemInfo(i, "spell")
        if type(a) == "string" then return b end
        return a
    end
end

local function ParseHeal(text)
    if not text then return nil end
    local lo, hi = text:match("(%d+) to (%d+)")
    if lo then return (tonumber(lo) + tonumber(hi)) / 2 end
    local n = text:match("[Hh]eal[^%d]-(%d+)")
    if n then return tonumber(n) end
end

local probeTip
local function TooltipHeal(index)
    if C_TooltipInfo and C_TooltipInfo.GetSpellBookItem then
        local data = C_TooltipInfo.GetSpellBookItem(index, PLAYER_BANK)
        if data then
            if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
            for _, line in ipairs(data.lines or {}) do
                if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
                local n = ParseHeal(line.leftText)
                if n then return n end
            end
        end
    end
    if not probeTip then
        probeTip = CreateFrame("GameTooltip", "BiSHealingProbeTip", nil, "GameTooltipTemplate")
    end
    probeTip:SetOwner(UIParent, "ANCHOR_NONE")
    if probeTip.SetSpellBookItem then
        pcall(probeTip.SetSpellBookItem, probeTip, index, PLAYER_BANK)
        for i = 1, probeTip:NumLines() do
            local fs = _G["BiSHealingProbeTipTextLeft" .. i]
            local n = fs and ParseHeal(fs:GetText())
            if n then return n end
        end
    end
end

local function SpellCost(spell)
    if type(spell) == "string" then spell = spell:gsub("%b()", ""):gsub("%s+$", "") end
    local costs
    if C_Spell and C_Spell.GetSpellPowerCost then costs = C_Spell.GetSpellPowerCost(spell)
    elseif GetSpellPowerCost then costs = GetSpellPowerCost(spell) end
    if costs then
        for _, c in ipairs(costs) do
            if c.type == 0 then return c.cost end
        end
    end
    return 0
end

local function ProbeRanks()
    local found, limit = {}, NumSpells()
    for i = 1, limit do
        local name, rank = BookName(i)
        if not name then
            if limit >= 1000 then break end
        elseif PROBE_SPELLS[name] then
            found[#found + 1] = { name = name, rank = rank or "",
                                  id = BookSpellID(i), heal = TooltipHeal(i) }
        end
    end
    return found
end

-- ------------------------------------------------------- Earth Shield plan --
-- Two shamans, two shields, and only one shield allowed per target. The job is
-- an assignment problem, not a ranking: who should take whom.
--
-- Value of a shield on target T cast by shaman C:
--     charges per minute on T  x  C's charge size  x  fraction of that charge
--     that would NOT be overheal on T
--
-- Charges per minute is capped by the ~4s internal cooldown, so being hit more
-- often than every 4 seconds adds nothing. That is why "the tank who gets hit
-- most" is the wrong answer and depth of health is the right one.

TUNE.esIcd = 4.0            -- measured min gap between charges
TUNE.esMaxCpm = 60 / TUNE.esIcd

local function CasterHeal(name)
    -- A peer running BiSHealing tells us their charge size outright. That beats
    -- our log-derived average of their charges, which needs them to shield
    -- someone in front of us first and is noisy until it has several samples.
    local p = COMM.peers[name]
    if p and (p.heal or 0) > 0 and (GetTime() - (p.at or 0)) <= COMM.TTL then
        return p.heal
    end
    local c = esCasterHeal[name]
    if c and c.n > 0 then return c.sum / c.n end
    -- Nothing measured yet. For YOURSELF that is answerable anyway -- charge
    -- size is the shield's base plus 28.6% of your healing power -- so the plan
    -- works on the pull instead of printing "shield someone and let it tick"
    -- for the first two minutes of every session. Other shamans stay unknown:
    -- their gear is not ours to guess at.
    if name == UnitName("player") and esBaseCharge and esBaseCharge > 0 then
        return HEALSZ.ESCharge(esBaseCharge)
    end
    return nil
end

-- charges/min this target can actually consume, and how deep they sit
TargetProfile = function(name)
    local rec = DB().players[name]
    if not rec then return nil end

    local cpm, depth

    if rec.es and rec.es.secs and rec.es.secs > 10 then
        cpm = (rec.es.charges / rec.es.secs) * 60      -- measured while shielded
    end
    if rec.depth and rec.depth.secs and rec.depth.secs > 10 then
        cpm = cpm or math.min(TUNE.esMaxCpm, (rec.depth.hits / rec.depth.secs) * 60)
        if rec.depth.n > 0 then depth = rec.depth.deficit / rec.depth.n end
    end
    if not cpm then return nil end

    return { cpm = math.min(cpm, TUNE.esMaxCpm), depth = depth or 0,
             measured = (rec.es and rec.es.apps or 0) }
end

-- effective fraction of one charge of size H landing on someone sitting `depth`
-- below full, on average. Crude, but it is the whole point: a charge on a full
-- bar is worth nothing no matter how often it fires.
local function EffectiveFraction(depth, H)
    if not H or H <= 0 then return 0 end
    if depth >= H then return 1 end
    return depth / H
end

-- Hung on COMM, not a global: COMM.MyCharge is defined six hundred lines above
-- this point and needs to reach it, and a bare global here would be exactly the
-- silent leak the harness exists to catch.
COMM.CasterHeal = CasterHeal

local function ESValue(targetName, casterHeal)
    local prof = TargetProfile(targetName)
    if not prof then return nil end
    local frac = EffectiveFraction(prof.depth, casterHeal)
    return prof.cpm * casterHeal * frac, prof
end

-- Who else is shielding? Anyone we have seen cast Earth Shield.
local function OtherShamans()
    local out, seen, me = {}, {}, UnitName("player")
    for name in pairs(COMM.Live()) do          -- answered on the comm: certain
        if name ~= me and not seen[name] then
            seen[name] = true; out[#out + 1] = name
        end
    end
    for name in pairs(esCasterHeal) do         -- inferred from the log: fallback
        if name ~= me and not seen[name] then
            seen[name] = true; out[#out + 1] = name
        end
    end
    return out
end

local function ESPlan()
    local myHeal = CasterHeal(UnitName("player"))
    local others = OtherShamans()
    local otherName = others[1]
    local otherHeal = otherName and CasterHeal(otherName)

    -- candidates: rows 1-3 only. Anyone further down does not take enough
    -- damage to be worth a shield, and if they start to, they climb.
    local ranked = RankRoster()
    local cands = {}
    for i = 1, math.min(6, #ranked) do
        local e = ranked[i]
        cands[#cands + 1] = { name = e.name, unit = e.unit }
    end

    if not myHeal then return nil, "no Earth Shield charges seen yet -- shield someone and let it tick" end
    if #cands == 0 then return nil, "nobody in range" end

    -- score every candidate for each caster
    for _, c in ipairs(cands) do
        c.mine, c.prof = ESValue(c.name, myHeal)
        if otherHeal then c.theirs = ESValue(c.name, otherHeal) end
    end

    local scored = {}
    for _, c in ipairs(cands) do
        if c.mine then scored[#scored + 1] = c end
    end
    if #scored == 0 then return nil, "not enough data yet -- needs a fight or two" end

    table.sort(scored, function(a, b) return a.mine > b.mine end)

    -- One shaman: take the best target, done.
    if not otherHeal then
        return { solo = true, mine = scored[1] }
    end

    -- Two shamans: try both pairings of the top two targets and keep the better
    -- total. When charge sizes differ, the bigger shield belongs on the target
    -- that can absorb more of it.
    local t1, t2 = scored[1], scored[2]
    if not t2 then return { solo = true, mine = t1 } end

    local aTotal = (t1.mine or 0) + (t2.theirs or 0)   -- me on t1, them on t2
    local bTotal = (t2.mine or 0) + (t1.theirs or 0)   -- me on t2, them on t1

    if aTotal >= bTotal then
        return { mine = t1, theirs = t2, gain = aTotal - bTotal,
                 other = otherName, myHeal = myHeal, otherHeal = otherHeal }
    else
        return { mine = t2, theirs = t1, gain = bTotal - aTotal,
                 other = otherName, myHeal = myHeal, otherHeal = otherHeal }
    end
end

-- ---------------------------------------------------- heal option table --
-- Six castable options: max rank and two-below-max for each of the three
-- spells.
--
-- THE TOOLTIP LIES. On this client the spellbook shows a spell's BASE healing
-- with no spell power in it at all -- Chain Heal reading "681 to 775" while the
-- cast actually lands for 2800. Every number downstream of that (the colour
-- bands, the red bar threshold, the Nature's Swiftness pip, the Earth Shield
-- maths) was being decided on roughly a quarter of the truth, which is worse
-- than having no numbers: it consistently said a hole was too big to fix.
--
-- So a heal size is worked out twice, and the better answer wins:
--   ESTIMATE  base + (your healing power x the spell's coefficient). The
--             coefficient is cast time / 3.5s, the standard rule, so Chain Heal
--             gets 0.71, Healing Wave 0.86, Lesser Healing Wave 0.43.
--   MEASURED  what your casts of that exact rank actually healed for, taken
--             from the combat log (heal + overheal, crits divided back down),
--             smoothed, and kept in your saved variables.
-- After a handful of casts the measured figure takes over. It needs no
-- coefficient table, no talent list, no downrank penalty formula and no guess
-- about your gear -- it is what the spell did, on you, this raid.
--
-- Worth knowing: on live gear the MAX ranks are the most mana-efficient per
-- point healed (the low-rank spellpower penalty is brutal in TBC). Downranking
-- does not save mana on its own -- it wins by not dumping 1600 healing into a
-- 700 point hole. That is exactly what these bands pick for you.

TUNE.downrankSteps = 2

-- HEALSZ's methods are defined down with BuildHealOptions, but the TABLE has to
-- exist up here: the combat log handler calls HEALSZ.Learn six hundred lines
-- above that, and a `local` declared below its first use silently reads as a nil
-- global instead -- the exact trap the header warns about, which has crashed
-- this addon twice.

function HEALSZ.SP()
    if GetSpellBonusHealing then
        local ok, v = pcall(GetSpellBonusHealing)
        if ok and type(v) == "number" then return v end
    end
    if C_Spell and C_Spell.GetSpellBonusHealing then
        local ok, v = pcall(C_Spell.GetSpellBonusHealing)
        if ok and type(v) == "number" then return v end
    end
    return 0
end

-- Coefficient = cast time / 3.5s, the standard TBC rule. That gives Healing
-- Wave 85.7%, Chain Heal 71.4%, Lesser Healing Wave 42.9% -- the published
-- numbers, derived rather than copied, which matters because Improved Healing
-- Wave SHORTENS the cast and therefore LOWERS the coefficient. Reading the live
-- cast time picks that up on its own; the table is only a fallback for a client
-- that will not answer.
function HEALSZ.Coef(spellName)
    local cast
    if GetSpellInfo then
        local _, _, _, ms = GetSpellInfo(spellName)
        if type(ms) == "number" and ms > 0 then cast = ms / 1000 end
    end
    cast = cast or HEALSZ.CAST[spellName] or 2.5
    if cast > 3.5 then cast = 3.5 end
    return cast / 3.5
end

-- Talents that multiply healing. Purification is +2% per point on everything;
-- Improved Chain Heal is +10% per point on Chain Heal only. Fully talented that
-- is 0.714 x 1.10 x 1.20 = 0.943 for Chain Heal, which is the ~94% the guides
-- quote. Matched by English name: a non-English client just gets the untalented
-- estimate for its first few casts, and the MEASUREMENT overrides all of this
-- within four casts anyway -- it already contains every talent, buff, trinket
-- and point of Intellect that Nature's Blessing turns into healing.
HEALSZ.talentAt = 0
function HEALSZ.Talents()
    local now = GetTime()
    if HEALSZ.talents and (now - HEALSZ.talentAt) < 30 then return HEALSZ.talents end
    local t = { all = 1, chain = 1 }
    if GetNumTalentTabs and GetTalentInfo then
        for tab = 1, (GetNumTalentTabs() or 0) do
            for i = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
                local name, _, _, _, rank = GetTalentInfo(tab, i)
                if name == "Purification" and rank then
                    t.all = 1 + 0.02 * rank
                elseif name == "Improved Chain Heal" and rank then
                    t.chain = 1 + 0.10 * rank
                end
            end
        end
    end
    HEALSZ.talents, HEALSZ.talentAt = t, now
    return t
end

function HEALSZ.Estimate(spellName, base)
    local t = HEALSZ.Talents()
    local mult = t.all * ((spellName == CHAIN_HEAL) and t.chain or 1)
    return ((base or 0) + HEALSZ.SP() * HEALSZ.Coef(spellName)) * mult
end

-- Earth Shield charges scale at 28.6% of healing power each, and -- unlike
-- every other number here -- the value is SNAPSHOT when the shield is cast, not
-- when a charge fires. Used only until real charges have been seen in the
-- combat log; measured charges are always better, because they already include
-- whatever trinket was up at cast time.
HEALSZ.ES_COEF = 0.2857
function HEALSZ.ESCharge(base)
    local t = HEALSZ.Talents()
    return ((base or 0) + HEALSZ.SP() * HEALSZ.ES_COEF) * t.all
end

-- A landed cast of a known rank. `raw` is heal + overheal: what the spell was
-- worth, not what fitted in the bar.
--
-- CRITS ARE THROWN AWAY, not scaled down. Dividing a crit by 1.5 looks like it
-- recovers the normal size, and it does -- on average, over many samples. On a
-- SMALL sample it does not: one crit early in a session pulled Chain Heal Rank 3
-- up to 5470, which then read as bigger than Rank 5 and made the addon wait for
-- a hole no downrank could ever fill. You crit about one cast in ten, so
-- discarding those ten percent costs almost nothing and removes the entire
-- failure mode. What the bars ask is "will a normal cast cover this", and a
-- normal cast is exactly what is being averaged.
function HEALSZ.Learn(spellId, raw, crit, over)
    if not spellId or not raw or raw <= 0 then return end

    -- ONLY CASTS THAT FILLED A REAL HOLE COUNT.
    --
    -- The sample used to be heal + overheal, on the theory that a cast into a
    -- nearly-full bar is still a big cast that got wasted. In the field that
    -- produced 4815 for a Chain Heal that visibly lands 2.7k -- about 1.6x too
    -- big, which is roughly what a chain is worth across all THREE targets.
    -- Whatever the client is folding into the overheal figure on a topped-off
    -- target, it is not a number the bars can be keyed to: it told the addon a
    -- 3k hole was too small for the downrank that would have filled it exactly.
    --
    -- A cast into a genuine hole has nothing to argue about: the heal landed,
    -- the log says how much, and that is the number the bar question is asking
    -- ("will this cast cover this hole"). So samples where more than half the
    -- cast was overheal are dropped. If every cast this session was into a full
    -- bar, no samples are taken and the coefficient estimate carries the load,
    -- which is exactly right -- an estimate beats a number you cannot trust.
    if over and raw > 0 and (over / raw) > HEALSZ.MAX_OVER then
        local seen = DB().healSeen
        -- create the record even with no usable sample, so /bish bands can say
        -- "I have seen you cast this, I just cannot size it from those casts"
        -- instead of looking like the spell was never cast at all
        seen[spellId] = seen[spellId] or { avg = 0, n = 0, crits = 0 }
        seen[spellId].wasted = (seen[spellId].wasted or 0) + 1
        return
    end

    if crit then
        local seen = DB().healSeen
        local e = seen[spellId]
        if e then e.crits = (e.crits or 0) + 1 end   -- counted, never averaged
        return
    end
    local seen = DB().healSeen
    local e = seen[spellId]
    if not e or (e.n or 0) == 0 then
        seen[spellId] = { avg = raw, n = 1, crits = (e and e.crits) or 0,
                          wasted = (e and e.wasted) or 0 }
    else
        e.avg = e.avg + (raw - e.avg) * HEALSZ.EMA
        e.n = (e.n or 0) + 1
    end
    HEALSZ.Refresh()   -- bars react this fight, not after the next /reload
end

-- A measurement is only believed within reach of the coefficient maths. The
-- maths can be wrong about talents and set bonuses -- it cannot be wrong by a
-- factor of two, so anything past that is a logging artefact, not gear.
function HEALSZ.Measured(spellId, spellName, base)
    local e = spellId and DB().healSeen[spellId]
    if not (e and (e.n or 0) >= HEALSZ.MIN_SAMPLES and (e.avg or 0) > 0) then return nil end
    if spellName then
        local est = HEALSZ.Estimate(spellName, base)
        if est > 0 and e.avg > est * HEALSZ.MAX_VS_EST then
            return est * HEALSZ.MAX_VS_EST, true      -- second return: capped
        end
    end
    return e.avg, false
end

-- Recompute every heal size. Three passes, and the order matters:
--
--  1. Measured ranks take their measured size.
--  2. Ranks you have NOT cast are estimated -- then multiplied by a calibration
--     factor learned from the ranks you HAVE cast (measured / estimated for
--     those). One Chain Heal rank tells you how far the coefficient maths is
--     off for your gear, buffs and talents, and that correction carries to
--     every other rank of the spell instead of leaving them on a raw guess.
--  3. Monotonic clamp. A lower rank must never read as bigger than a higher one
--     -- that is nonsense on its face, and it is what a single lucky sample
--     produces. Bases are ordered, so the estimates are; this only ever fires
--     when a measurement is unlucky, and it keeps the bands in a sane order
--     while more casts settle it.
function HEALSZ.Refresh()
    if not healOptions or #healOptions == 0 then return end

    local cal, calN = {}, {}
    for _, o in ipairs(healOptions) do
        local m = HEALSZ.Measured(o.id, o.spell, o.base)
        if m then
            local est = HEALSZ.Estimate(o.spell, o.base)
            if est > 0 then
                cal[o.spell] = (cal[o.spell] or 0) + (m / est)
                calN[o.spell] = (calN[o.spell] or 0) + 1
            end
        end
    end
    for k, v in pairs(cal) do cal[k] = v / calN[k] end

    for _, o in ipairs(healOptions) do
        local m, capped = HEALSZ.Measured(o.id, o.spell, o.base)
        if m then
            o.heal, o.measured, o.capped = m, true, capped
        else
            o.heal = HEALSZ.Estimate(o.spell, o.base) * (cal[o.spell] or 1)
            o.measured = false
        end
    end

    -- ranks of one spell, ascending: clamp any inversion
    for i = 2, #healOptions do
        local lo, hi = healOptions[i - 1], healOptions[i]
        if lo.spell == hi.spell and lo.rank < hi.rank and lo.heal >= hi.heal then
            lo.heal = hi.heal * 0.95
            lo.clamped = true
        else
            lo.clamped = nil
        end
    end

    if WHEEL.maxId then
        WHEEL.maxHeal = HEALSZ.Measured(WHEEL.maxId, WHEEL.HW, WHEEL.maxBase)
            or HEALSZ.Estimate(WHEEL.HW, WHEEL.maxBase or 0) * (cal[WHEEL.HW] or 1)
    end
end

function HEALSZ.Effective(spellId, spellName, base)
    local m = HEALSZ.Measured(spellId, spellName, base)
    if m then return m, true end
    return HEALSZ.Estimate(spellName, base), false
end

-- Chain Heal only. Healing Wave and Lesser Healing Wave are somebody else's
-- job in this raid, so the bands answer one question: does the downrank cover
-- this, does max rank cover it, or is it past what one cast can fix.
local BAND_COLORS = {
    { 0.25, 0.55, 0.95 },   -- downrank covers it
    { 0.95, 0.70, 0.20 },   -- needs max rank
}

local function BuildHealOptions()
    local found = ProbeRanks()
    if #found == 0 then healOptions = {}; return end

    -- group by spell, keep rank order
    local bySpell = {}
    for _, e in ipairs(found) do
        local rank = tonumber((e.rank or ""):match("(%d+)")) or 0
        bySpell[e.name] = bySpell[e.name] or {}
        table.insert(bySpell[e.name], { rank = rank, id = e.id, heal = e.heal or 0,
                                        name = e.name })
    end

    -- Earth Shield: remember the max rank for the right-click bind
    local esList = bySpell[EARTH_SHIELD]
    if esList and #esList > 0 then
        table.sort(esList, function(a, b) return a.rank < b.rank end)
        esMaxCast = ("%s(Rank %d)"):format(EARTH_SHIELD, esList[#esList].rank)
        esBaseCharge = esList[#esList].heal or 0    -- per-charge tooltip base
    end

    -- Healing Wave: max rank for the shift+wheel emergency, max-2 for the plain
    -- scroll. Deliberately NOT added to healOptions -- the colour bands answer a
    -- Chain Heal question, and a single-target cast in that list would tell you
    -- a hole is "covered" by a spell the bands never intended you to use.
    local hwList = bySpell[WHEEL.HW]
    if hwList and #hwList > 0 then
        table.sort(hwList, function(a, b) return a.rank < b.rank end)
        local hwMax  = hwList[#hwList]
        local hwDown = hwList[math.max(1, #hwList - TUNE.downrankSteps)]
        WHEEL.max     = ("%s(Rank %d)"):format(WHEEL.HW, hwMax.rank)
        WHEEL.maxId   = hwMax.id
        WHEEL.maxBase = hwMax.heal or 0
        WHEEL.maxHeal = HEALSZ.Effective(hwMax.id, WHEEL.HW, WHEEL.maxBase)
        -- refined again by HEALSZ.Refresh() below, once calibration is known
        WHEEL.down    = (hwDown and hwDown ~= hwMax)
                        and ("%s(Rank %d)"):format(WHEEL.HW, hwDown.rank)
                        or WHEEL.max
    end

    -- Lesser Healing Wave, same treatment, for scroll down. Also kept out of
    -- healOptions: it is the fast top-up, not an answer to a Chain Heal band.
    local lhList = bySpell[WHEEL.LHW]
    if lhList and #lhList > 0 then
        table.sort(lhList, function(a, b) return a.rank < b.rank end)
        local lhMax  = lhList[#lhList]
        local lhDown = lhList[math.max(1, #lhList - TUNE.downrankSteps)]
        WHEEL.lMax  = ("%s(Rank %d)"):format(WHEEL.LHW, lhMax.rank)
        WHEEL.lDown = (lhDown and lhDown ~= lhMax)
                      and ("%s(Rank %d)"):format(WHEEL.LHW, lhDown.rank)
                      or WHEEL.lMax
    end

    local opts = {}
    local list = bySpell[CHAIN_HEAL]
    if list and #list > 0 then
        table.sort(list, function(a, b) return a.rank < b.rank end)
        local maxE = list[#list]
        local downE = list[math.max(1, #list - TUNE.downrankSteps)]
        if downE and downE ~= maxE and downE.heal > 0 then
            opts[#opts + 1] = { spell = CHAIN_HEAL, rank = downE.rank, id = downE.id,
                                base = downE.heal, max = false,
                                cost = SpellCost(downE.id) }
        end
        if maxE and maxE.heal > 0 then
            opts[#opts + 1] = { spell = CHAIN_HEAL, rank = maxE.rank, id = maxE.id,
                                base = maxE.heal, max = true,
                                cost = SpellCost(maxE.id) }
        end
    end

    -- Tooltip base -> what the cast is really worth on this gear, measured if
    -- we have enough casts of that rank and estimated from healing power if not.
    for _, o in ipairs(opts) do
        o.heal, o.measured = HEALSZ.Effective(o.id, o.spell, o.base)
    end

    -- SORTED BY RANK, NOT BY SIZE. This list used to be ordered by heal amount,
    -- which was safe only while every size came from a tooltip -- max rank was
    -- always the bigger number. The moment sizes became MEASURED, one crit-
    -- inflated downrank sorted itself above max rank, and since the click binds
    -- were taken from array position, left-click and shift+left silently swapped
    -- spells mid-raid. Rank order cannot lie: rank 3 is below rank 5 whatever
    -- the numbers say this fight.
    table.sort(opts, function(a, b) return a.rank < b.rank end)
    for i, o in ipairs(opts) do
        o.color = BAND_COLORS[math.min(i, #BAND_COLORS)]
        o.cast = ("%s(Rank %d)"):format(o.spell, o.rank)
    end
    healOptions = opts
    HEALSZ.Refresh()          -- calibration + the monotonic clamp, in one place

    -- and the binds come off the explicit max/downrank FLAG, not off a position
    -- in a list somebody might reorder later
    chDownCast, chMaxCast = nil, nil
    for _, o in ipairs(opts) do
        if o.max then chMaxCast = o.cast else chDownCast = o.cast end
    end
    chDownCast = chDownCast or chMaxCast

    -- push the new casts onto the frames; safe here, this only runs out of combat
    if ApplyBindsRef and not InCombatLockdown() then ApplyBindsRef() end
end
BuildHealOptionsRef = BuildHealOptions

-- ------------------------------------------------- what UI/ is handed ----
-- The options window moved to UI/options.lua. A `local` does not cross a file,
-- so everything that window touches is published here, ONCE, in one block --
-- rather than scattered as NS.x = x beside each declaration, where the next
-- reader cannot see the whole surface at a glance. If a name is not in this
-- block, no UI file can reach it, and that is the point: this list is the
-- addon's brain deciding what its shell is allowed to see.
--
-- Load order makes plain references safe: the TOC runs this file first, so
-- UI/options.lua can capture these as its own locals at ITS load time.
NS.Print, NS.DB, NS.UIX      = Print, DB, UIX
NS.frames, NS.anchor         = frames, anchor
NS.WHEEL, NS.SNIPE           = WHEEL, SNIPE
                             -- NS.COMM is published by Core/comm.lua, which owns it
NS.ES_HOLD, NS.demo          = ES_HOLD, demo
NS.ShortName, NS.Relayout    = ShortName, Relayout
NS.BuildHealOptions          = BuildHealOptions
NS.VERSION, NS.PULSE_CAP     = VERSION, PULSE_CAP

-- Three that a plain reference would get WRONG, because they are not values
-- that sit still. Copying `esTarget` onto NS once hands the window whoever was
-- shielded at LOGIN, forever -- the header would show a stale name all night and
-- never look wrong enough to notice. Same trap for the bindings hook, which is
-- filled in later, and for the reorder flag, which the window has to WRITE.
function NS.ESTarget() return esTarget end
function NS.ApplyBinds() if ApplyBindsRef then return ApplyBindsRef() end end
function NS.QueueReorder() pendingReorder = true end

-- /bish opens a window that lives in another file now. If a packaged zip ever
-- ships without UI/, that is a nil index on every single /bish; say it once, in
-- words, instead. dev/tests.lua proves this path by loading without the UI file.
local function Window()
    if not NS.CFG then
        Print("the settings window (UI/options.lua) did not load -- reinstall the addon")
        return nil
    end
    return NS.CFG
end


SLASH_BISHEALING1 = "/bish"

SlashCmdList.BISHEALING = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "ranks" then
        local found = ProbeRanks()
        Print(("spellbook probe: %d entries for the 3 heal spells"):format(#found))
        for _, e in ipairs(found) do
            Print(("  %s %s  id %s  ~%s heal  %d mana"):format(
                e.name, e.rank ~= "" and e.rank or "(no rank)",
                tostring(e.id), e.heal and math.floor(e.heal) or "?",
                SpellCost(e.id or e.name)))
        end
        if #found <= 3 then
            Print("  only max ranks visible -- set the spellbook to show ALL ranks, then rerun")
        else
            Print("  downranking is live: ranks are enumerable")
        end

    elseif msg:match("^sim") or msg:match("^demo") then
        local arg = msg:match("^%a+%s+(%S+)")
        if arg == "off" or (demo.on and not arg) then
            DemoStop()
            Print("demo off")
        else
            if tonumber(arg) then
                -- old habit: "/bish sim 25" built a fake 25-man. There is no
                -- fake roster any more, so the number is meaningless -- say so
                -- rather than silently ignoring it.
                Print("no fake raids any more -- the demo runs on your real group. Starting it.")
            end
            DemoStart()
            local n = 0
            for _, f in ipairs(frames) do if f:IsShown() then n = n + 1 end end
            Print(("demo on -- cycling every feature across your %d visible frame(s). /bish sim off to stop")
                  :format(n))
            if n == 0 then
                Print("  nothing visible: |cffffff00/bish show|r, or |cffffff00/bish center|r")
            end
        end

    elseif msg:match("^wheel") then
        local arg = msg:match("^wheel%s+(%S+)")
        local db = DB()
        if arg == "on" or arg == "off" then
            db.wheel = (arg == "on")
        elseif arg == "strict" then
            db.wheelStrict = not db.wheelStrict
        elseif arg then
            Print("usage: /bish wheel [on|off|strict]")
        else
            db.wheel = not db.wheel
        end
        if InCombatLockdown() then
            WHEEL.pending = true
            Print("in combat -- wheel binds change when the fight ends")
        else
            WHEEL.Apply()
        end
        Print(("wheel heals: %s%s"):format(db.wheel and "ON" or "off",
              db.wheelStrict and " (strict two-press)" or ""))
        if db.wheel then
            Print(("  scroll up        %s -- mouseover only")
                  :format(WHEEL.down or WHEEL.HW))
            Print(("  scroll down      %s"):format(WHEEL.lDown or WHEEL.LHW))
            Print(("  shift+scroll dn  %s + trinkets"):format(WHEEL.lMax or WHEEL.LHW))
            if WHEEL.ResolveKnown() then
                Print(("  shift+scroll up  %s + %s%s"):format(WHEEL.NS,
                      WHEEL.max or WHEEL.HW,
                      db.wheelStrict and " (second press casts the heal)" or " (one press)"))
                if db.wheelStrict then
                    Print("  strict: if NS is on cooldown the press does NOTHING. /bish wheel strict to go back")
                end
            else
                Print(("  shift+scroll up  %s -- %s not trained")
                      :format(WHEEL.max or WHEEL.HW, WHEEL.NS))
            end
        end

    elseif msg == "bind" then
        local shown
        for _, f in ipairs(frames) do
            if f:IsShown() and f.unit and UnitExists(f.unit) then
                shown = f
                local t1 = f:GetAttribute("shift-type1")
                local mt = f:GetAttribute("shift-macrotext1")
                local sp = f:GetAttribute("shift-spell1")
                Print(("%s: shift-type1=%s"):format(UnitName(f.unit) or "?", tostring(t1)))
                if mt then Print("  macro: " .. mt:gsub("\n", " | ")) end
                if sp then Print("  spell: " .. tostring(sp)) end
                local t4 = f:GetAttribute("*type4")
                local s4 = f:GetAttribute("*spell4")
                Print(("  button4: type=%s spell=%s"):format(tostring(t4), tostring(s4)))
                break
            end
        end
        if not shown then Print("no live frame to inspect") end
        Print(("trinkets setting: %s"):format(tostring(DB().trinkets)))
        Print(("wheel: %s | NS known: %s | strict: %s"):format(
              tostring(DB().wheel), tostring(WHEEL.ResolveKnown()),
              tostring(DB().wheelStrict)))
        if WHEEL.plainMacro then Print("  scroll up: " .. WHEEL.plainMacro:gsub("\n", " | ")) end
        if WHEEL.shiftMacro then Print("  shift+scroll up: " .. WHEEL.shiftMacro:gsub("\n", " | ")) end
        if WHEEL.dnMacro then Print("  scroll down: " .. WHEEL.dnMacro:gsub("\n", " | ")) end
        if WHEEL.dnShiftMacro then Print("  shift+scroll down: " .. WHEEL.dnShiftMacro:gsub("\n", " | ")) end

    elseif msg == "inc" then
        if not healCommOn then
            Print("LibHealComm-4.0 not loaded. Add it under BiSHealing\\Libs and it")
            Print("will subtract other healers' incoming heals from the prediction.")
        else
            Print(("cast lead %.2fs (Chain Heal %.2fs + %.1fs reaction) -- haste-aware")
                  :format(CAST_LEAD, ChainCastTime(), CAST_REACTION))
            Print("incoming heals landing within your cast window:")
            local any = false
            for _, f in ipairs(frames) do
                if f:IsShown() and f.unit and UnitExists(f.unit) then
                    local total = TotalIncoming(f.unit)
                    local others = OthersIncoming(f.unit)
                    if total > 0 then
                        any = true
                        local mine = total - others
                        Print(("  %s  <- %d incoming (%d others + %d you)")
                              :format(UnitName(f.unit) or "?",
                                      math.floor(total), math.floor(others), math.floor(mine)))
                    end
                end
            end
            if not any then Print("  none right now (or nobody else is casting)") end
        end

    elseif msg == "bull" then
        if bullTarget and bullTarget.pname then
            Print(("bullseye: %s (score %.2f)")
                  :format((bullTarget.pname):match("^[^-]+") or "?", bullScore or 0))
        elseif bullTarget then
            Print(("bullseye: frame %s (score %.2f)")
                  :format(tostring(bullTarget.rowIndex), bullScore or 0))
        else
            Print("bullseye: nobody needs a max rank chain heal right now")
        end
        Print(("  hysteresis %.0f%% -- a challenger must beat the holder by that much")
              :format((TUNE.bullHysteresis - 1) * 100))

    elseif msg == "bands" then
        if #healOptions == 0 then
            Print("no heal options built -- set the spellbook to show ALL ranks, then /bish rescan")
        else
            Print(("colour bands (smallest first) -- healing power %d:")
                  :format(math.floor(HEALSZ.SP())))
            for _, o in ipairs(healOptions) do
                local seen = o.id and DB().healSeen[o.id]
                Print(("  |cff%02x%02x%02x[]|r %s Rank %d -- covers up to %d  (tooltip says %d; %s%s%s)")
                      :format(math.floor(o.color[1] * 255), math.floor(o.color[2] * 255),
                              math.floor(o.color[3] * 255),
                              o.spell, o.rank, math.floor(o.heal), math.floor(o.base or 0),
                              o.measured
                        and ("measured over %d non-crit casts"):format((seen and seen.n) or 0)
                        or ("estimated, %d/%d non-crit casts logged"):format((seen and seen.n) or 0,
                                                                    HEALSZ.MIN_SAMPLES),
                              (seen and ((seen.crits or 0) + (seen.wasted or 0)) > 0)
                                and (", %d crits + %d overheal-heavy casts ignored")
                                    :format(seen.crits or 0, seen.wasted or 0) or "",
                              (o.capped and ", |cffffff00capped at 2x the maths|r" or "")
                              .. (o.clamped and ", |cffffff00capped below the higher rank|r" or "")))
            end
            if DB().plainBars then
                Print(("  bars are BLACK until the predicted hole reaches %d -- the size of %s")
                      :format(math.floor(UIX.redAt or 0),
                              (healOptions[1] and healOptions[1].cast) or "your downrank"))
                Print("  flashing red = that, and still taking damage")
            else
                Print("  red = more than one Chain Heal can fix")
            end
            Print(("binds: left %s | shift+left %s + both trinkets (/use 13,14)"):format(
                  chDownCast or "?", chMaxCast or "?"))
            Print(("  right %s"):format(esMaxCast or "Earth Shield"))
            if giftKnown then Print("  button4 " .. GIFT) end
            if DB().wheel then
                Print(("  scroll up %s | shift+scroll up %s%s"):format(
                      WHEEL.down or "?", WHEEL.max or "?",
                      WHEEL.ResolveKnown() and (" after " .. WHEEL.NS) or ""))
                Print(("  scroll down %s | shift+scroll down %s"):format(
                      WHEEL.lDown or "?", WHEEL.lMax or "?"))
            end
        end

    elseif msg == "snipe" or msg == "race" then
        Print(("heal race: %s | native prediction: %s | healers watched: %d")
              :format(DB().healRace ~= false and "on" or "off",
                      UnitGetIncomingHeals and "yes" or "NOT AVAILABLE on this client",
                      #SNIPE.healers))
        if not UnitGetIncomingHeals then
            Print("  without it only LibHealComm users are visible, and anyone")
            Print("  else healing your target will keep landing first unseen")
        end
        local any = false
        for _, f in ipairs(frames) do
            if f:IsShown() and f.unit and UnitExists(f.unit) then
                local r = SNIPE.Read(f.unit)
                if r.n > 0 then
                    any = true
                    Print(("  %s <- %d heal(s) converging (%d other%s), first is %s, %s")
                          :format(ShortName(UnitName(f.unit)) or "?",
                                  r.total or r.n, r.n, r.unnamed and " incl. one unattributed" or "",
                                  tostring(r.who or "?"),
                                  (r.mineFirst == true and "|cff00ff00you land first|r")
                                  or (r.mineFirst == false and "|cffff5555they land first|r")
                                  or "|cffffaa55no cast bar to time them|r"))
                end
            end
        end
        if not any then Print("  nobody else is casting on anyone you can see") end

    elseif msg == "peers" then
        local live, any = COMM.Live(), false
        Print(("comm: prefix %s | channel %s | your v%s")
              :format(COMM.PREFIX, tostring(COMM.Channel() or "none -- not grouped"),
                      tostring(VERSION)))
        for name, p in pairs(live) do
            any = true
            local u = p.guid and GuidToUnit(p.guid)
            Print(("  %s (v%s) -- shielding %s, %d charges, %d per charge, heard %.0fs ago")
                  :format(name, tostring(p.version or "?"),
                          (u and UnitName(u)) or (p.guid and "someone out of range") or "nobody",
                          p.charges or 0, math.floor(p.heal or 0),
                          GetTime() - (p.at or 0)))
        end
        if not any then
            Print("  no other BiSHealing shaman answering -- the Earth Shield plan")
            Print("  falls back to reading their charges out of the combat log")
        end

    elseif msg == "resetsizes" then
        BiSHealingDB.healSeen = {}
        BuildHealOptions()
        Print("measured heal sizes wiped -- back to the coefficient estimate until four clean casts land")

    elseif msg == "rescan" then
        BuildHealOptions()
        Print(("rebuilt: %d heal options"):format(#healOptions))

    elseif msg == "bounce" then
        verboseBounce = not verboseBounce
        Print(verboseBounce and "bounce logging ON -- cast Chain Heal a few times"
              or "bounce logging off")

    elseif msg == "esplan" then
        local plan, why = ESPlan()
        if not plan then
            Print(why or "no plan yet")
        elseif plan.solo then
            Print(("Earth Shield -> %s (no other shaman seen)")
                  :format((plan.mine.name or "?"):match("^[^-]+") or "?"))
        else
            local mineNm = (plan.mine.name or "?"):match("^[^-]+") or "?"
            local theirNm = (plan.theirs.name or "?"):match("^[^-]+") or "?"
            Print(("Earth Shield plan -- you: %s | %s: %s")
                  :format(mineNm, plan.other or "other shaman", theirNm))
            Print(("  charge size: you %d, %s %d")
                  :format(math.floor(plan.myHeal or 0), plan.other or "them",
                          math.floor(plan.otherHeal or 0)))
            if (plan.gain or 0) > 0 then
                Print(("  swapping the other way costs about %d healing per minute")
                      :format(math.floor(plan.gain)))
            end
            local cur = esTarget and GuidToUnit(esTarget)
            if cur and UnitName(cur) ~= mineNm then
                Print(("  yours is on %s right now -- move it to %s")
                      :format(UnitName(cur), mineNm))
            end
        end

    elseif msg == "rawes" then
        rawES = not rawES
        Print(rawES and "raw Earth Shield logging ON -- take a few hits, then /bish rawes to stop"
              or "raw Earth Shield logging off")

    elseif msg == "es" then
        for _, r in pairs(esRuns) do
            Print(("ACTIVE: %s's shield on %s -- %d charges, %d healed (%d effective), %.0fs")
                  :format(r.caster or "?", r.target, r.doses or r.procs,
                          math.floor(r.healed or 0), math.floor(r.effective or 0),
                          GetTime() - r.start))
        end
        if #esLog == 0 then
            Print("no completed Earth Shield applications logged yet")
        else
            Print("recent Earth Shield applications:")
            for i, r in ipairs(esLog) do
                local waste = (r.healed > 0)
                    and math.floor((1 - (r.effective or 0) / r.healed) * 100) or 0
                Print(("  %d. %s on %s -- %d charges, %d healed (%d effective, %d%% wasted), %.0fs up%s"):format(
                    i, r.caster or "?", r.target, r.doses or r.procs,
                    math.floor(r.healed or 0), math.floor(r.effective or 0),
                    waste, r.dur or 0,
                    r.minGap and (", min gap %.1fs"):format(r.minGap) or ""))
                if i >= 6 then break end
            end
        end

    elseif msg == "score" then
        local ranked = RankRoster()
        Print("current ranking:")
        for i, e in ipairs(ranked) do
            local rec = DB().players[e.name]
            local n = rec and #rec.fights or 0
            Print(("  %d. %s%s  score %.2f  (dps %.0f, top-third %d%%, %d fights%s%s)")
                  :format(i, (e.name or "?"):match("^[^-]+") or "?",
                          e.apex and " [ES]" or "", e.score or 0, e.vol or 0,
                          math.floor((e.cons or 0) * 100), n,
                          (e.bounce or 0) > 0 and (", bounce %.1f"):format(e.bounce) or "",
                          (rec and (rec.selfHits or 0) > 0)
                            and (", %d self-inflicted hits ignored"):format(rec.selfHits) or ""))
        end
        if #ranked == 0 then Print("  nobody in range") end

    elseif msg == "dispel" then
        -- the per-zone list, written by what actually landed on the raid
        local seen = DB().dispelSeen or {}
        local zones = {}
        for z in pairs(seen) do zones[#zones + 1] = z end
        table.sort(zones)
        if #zones == 0 then
            Print("no curable debuffs met yet -- the list writes itself as they land")
        end
        for _, z in ipairs(zones) do
            local names = {}
            for name in pairs(seen[z]) do names[#names + 1] = name end
            table.sort(names, function(a, b) return seen[z][a].n > seen[z][b].n end)
            Print(("%s:"):format(z))
            for _, name in ipairs(names) do
                local rec = seen[z][name]
                Print(("  %s  (%s, seen %d)"):format(name, rec.kind or "?", rec.n or 0))
            end
        end

    elseif msg == "reorder" then
        if InCombatLockdown() then
            pendingReorder = true
            Print("in combat -- will reorder when it ends")
        else
            Relayout(); Print("reordered")
        end

    elseif msg == "reset" then
        BiSHealingDB = nil
        Print("history wiped")
        if not InCombatLockdown() then Relayout() end

    elseif msg == "lock" then
        DB().locked = not DB().locked
        Print(DB().locked and "locked" or "unlocked -- a green bar appears, drag that")
        if not InCombatLockdown() then Relayout() end

    elseif msg == "frames" then
        local db = DB()
        local vis = 0
        for _, f in ipairs(frames) do if f:IsShown() then vis = vis + 1 end end
        local p, _, rp, x, y = anchor:GetPoint()
        Print(("shown flag: %s | frames built: %d | visible: %d | roster: %d")
              :format(tostring(db.shown ~= false), #frames, vis, #RosterUnits()))
        Print(("anchor: %s / %s at %.0f, %.0f | combat: %s | locked: %s")
              :format(tostring(p), tostring(rp), x or 0, y or 0,
                      tostring(InCombatLockdown()), tostring(db.locked)))
        if vis == 0 then
            Print("nothing visible -- try /bish show, or /bish center to bring it back on screen")
        end

    elseif msg == "center" then
        DB().pos = nil
        anchor:ClearAllPoints()
        anchor:SetPoint("CENTER", 0, -220)
        DB().shown = true
        if not InCombatLockdown() then Relayout() end
        Print("anchor recentred and frames shown")

    elseif msg == "" then
        local W = Window(); if W then W.Toggle() end

    elseif msg == "config" or msg == "options" or msg == "settings" then
        local W = Window(); if W then W.Open() end

    elseif msg == "show" or msg == "hide" then
        local db = DB()
        db.shown = (msg == "show")
        if InCombatLockdown() then
            Print("can't show or hide frames in combat -- will apply after")
            pendingReorder = true
        else
            Relayout()
            local vis = 0
            for _, f in ipairs(frames) do if f:IsShown() then vis = vis + 1 end end
            Print(("%s -- %d frame(s) visible%s"):format(
                db.shown and "shown" or "hidden", vis,
                (db.shown and vis == 0) and " (nobody in range? try /bish frames)" or ""))
        end

    else
        Print("unknown command -- open the settings window with /bish or /bish config, or: show | hide | center | frames | bands | bind | wheel | peers | snipe | resetsizes | bull | inc | sim on/off | score | esplan | dispel")
    end
end
