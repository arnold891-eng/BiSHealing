--[[
  BiSHealing :: Engineer.lua - THE ENGINEER'S BOXES ARE HEALTH BARS (12 Nov 2026).

  Arn: "engineer view for friendly boxes can we get rid of the icons inside the box and make them actual health bars class
  coded and figure out a over heal los range indicator?"

  The engineer's console (Radar.lua, RD.Console) places the radar's own secure heal pips on a grid. In the console only,
  each pip shows a HEALTH BAR instead of its role glyph:
    * the bar: a plain StatusBar inside the pip (never the secure pip itself), handed UnitHealthMax / UnitHealth untouched
      - the client scales it, the addon never learns either number (the grid's own bargain) - in the grid's class colour
      (FG.CLASS_COLOR), the grid's dead red when dead; the glyph faces hide (RD.PaintHeal still colours them, unseen);
    * RANGE: the grid's own dimming (FG.PaintRange on the box - a plain answer, else the client's ternary on a secret one),
      every radar tick while the console shows (RD.Look), and when a unit crosses the line (UNIT_IN_RANGE_UPDATE);
    * LOS / RANGE on a failed click: the click word (RD.HeardError) in the MIDDLE of the box, as on the grid;
    * INCOMING (Arn, 12 Nov: "engineer still missing the incoming heal mechanic"): heals on their way, as on the grid -
      UnitGetIncomingHeals handed untouched to a bar that starts where their health ends, in the cockpit's incoming cyan,
      on the health events and UNIT_HEAL_PREDICTION (heard only while the console shows);
    * OVERHEAL: while you hover, your hover heal as a paler GHOST right after the incoming - as long as the heal is,
      cut off at the box's edge (the client draws the heal against their max, a secret) - and OVER/H under the box when
      more than half would be wasted (Overheal.lua). Gone while your own cast is in the air (it is incoming then).
  On the radar nothing changes: the bars hide, the glyphs come back, the click word goes back under the pip.
  Cost: health on its events (one unit), range on the radar's half-second tick while the console shows.
]]
local ADDON, NS = ...
NS = NS or {}

local EN = {}
NS.EN = EN

EN.BG = { 0.04, 0.05, 0.06, 0.92 }       -- the empty part of a box
EN.INCOMING = { 0.22, 0.80, 1.00, 0.60 } -- heals on their way: the cockpit grid's own cyan (FG.COCKPIT.incoming)
EN.GHOST = { 0.22, 0.80, 1.00, 0.28 }    -- your hover heal: the same cyan, fainter - "this is what it would add"
-- THE OVERHEAL IN THE BOX (Arn, 12 Nov, with a screenshot of the grid's magenta: "in this grid this is the overheal can we
-- show that and the overheal word on the engineer?"): the grid's own band (Grid.lua, f.overheal) - a bar as wide as the
-- box filling LEFTWARDS from its right edge by the heals on their way, masked to their filled health, so only the part
-- over their health shows: the heal that lands on nobody. A second, fainter one carries on leftwards from it by your
-- hover heal: what YOUR heal would waste on top. Nothing compared; the client does the geometry. A MASK, not a clip:
-- a clip anchored to a secret-sized fill draws nothing (the grid's 8 Oct lesson).
EN.OVER = { 1.00, 0.12, 0.85, 0.95 }      -- the grid's classic overheal magenta (FG.OVERHEAL), the colour Arn showed
EN.OVER_HOVER = { 1.00, 0.12, 0.85, 0.45 }
EN.FALLBACK = { 0.20, 0.70, 0.30 }       -- a class the client will not say
EN.TEX = "Interface\\Buttons\\WHITE8X8"

-- ONE PLACE FOR EVERY ALERT (Arn, 12 Nov: "for the engineering since we are cramped for space, we can move all the alerts
-- for all players to the same space in the header?" - "so all stacked in the header LOS RANGE OVERHEAL"): whoever they are
-- about, they show in the console's top strip (RD.CON.pad + head, where only the class and view buttons sit, at the
-- right), in THREE BOXES (Arn: "oh thats right we can have 3 boxes" - "because a hover can show a los and overheal at
-- the same time"): LOS, RANGE, OVER/H, each its own dim empty box (the console's own look), lit by its word. Only one box
-- is under the mouse at a time, so the box you are on is whose it is.
EN.HEAD = { { key = "los", x = 0, w = 34 }, { key = "range", x = 38, w = 58 }, { key = "over", x = 100, w = 62 } }
EN.HEAD_H = 16

local function headSlot(kind)
    for _, h in ipairs(EN.HEAD) do if h.key == kind then return h end end
    return EN.HEAD[1]
end

--- Where the alerts live now: the console's top strip, or (the radar, 12 Nov: "bring radar up to speed") the alert row
--- along the top of the gauge's rail (RD.ALERT_H). Answers the frame, the boxes' left edge and their middle's y.
function EN.Where()
    local RD = NS.RD
    if not RD then return UIParent, 8, -11 end
    if RD.Console and RD.Console() then
        local C = RD.CON or {}
        local pad = C.pad or 8
        return RD.frame or UIParent, pad, -((pad + (C.head or 14)) / 2)
    end
    return RD.gaugeRail or RD.frame or UIParent, (RD.GAUGE and RD.GAUGE.left) or 56, -(((RD.ALERT_H or 18)) / 2 + 1)
end

--- An alert's spot ("los", "range" or "over"): point, relative frame, relative point, x, y. LOS and RANGE are centred in
--- their box; OVER/H's clipping window starts at its box's left edge (the word hangs 4 px in).
function EN.HeadSpot(kind)
    local f, x0, y = EN.Where()
    local h = headSlot(kind)
    if kind == "over" then return "LEFT", f, "TOPLEFT", x0 + h.x, y end
    return "CENTER", f, "TOPLEFT", x0 + h.x + h.w / 2, y
end

--- The three empty boxes, on the surface showing now: the console's own layer, or the radar's gauge rail (each hides
--- with its surface). Answers that surface's boxes.
function EN.HeadBoxes()
    local RD = NS.RD
    if not RD then return nil end
    local con = RD.Console and RD.Console()
    local parent = con and RD.conLayer or (not con and RD.gaugeRail) or nil
    if not parent then return nil end
    local key = con and "heads" or "radarHeads"
    EN[key] = EN[key] or {}
    local set = EN[key]
    local f, x0, y = EN.Where()
    local dim = RD.DIM or { 0.22, 1.00, 0.53, 0.4 }
    for _, h in ipairs(EN.HEAD) do
        local q = set[h.key]
        if not q then
            q = CreateFrame("Frame", nil, parent)
            q.edges = {}
            for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                local t = q:CreateTexture(nil, "BORDER")
                t:SetColorTexture(dim[1], dim[2], dim[3], dim[4] or 1)
                if side == "TOP" or side == "BOTTOM" then
                    t:SetPoint(side .. "LEFT", q, side .. "LEFT") t:SetPoint(side .. "RIGHT", q, side .. "RIGHT") t:SetHeight(1)
                else
                    t:SetPoint("TOP" .. side, q, "TOP" .. side) t:SetPoint("BOTTOM" .. side, q, "BOTTOM" .. side) t:SetWidth(1)
                end
                q.edges[#q.edges + 1] = t
            end
            set[h.key] = q
        end
        q:SetSize(h.w, EN.HEAD_H)
        q:ClearAllPoints()
        q:SetPoint("CENTER", f, "TOPLEFT", x0 + h.x + h.w / 2, y)
        q:Show()
    end
    return set
end

--- A click word on a pip (RD.HeardError): into its own box - LOS or RANGE - on whichever surface shows.
function EN.PlaceWord(sp, word)
    local RD = NS.RD
    if not (RD and RD.On and RD.On() and sp and sp.los) then return false end
    sp.los:ClearAllPoints()
    sp.los:SetPoint(EN.HeadSpot(word == "RANGE" and "range" or "los"))
    return true
end

local function secret(v) return NS.Secret and NS.Secret(v) or false end
local function plain(v) if v == nil or secret(v) then return nil end return v end
local function console()
    local RD = NS.RD
    return RD and RD.On and RD.On() and RD.Console and RD.Console() or false
end
EN.Console = console

--- A pip's box: a plain frame over the pip (inset a pixel, so the console's square edge shows), clipping its own bars.
function EN.Box(sp)
    if sp.en then return sp.en end
    local b = sp.heal
    if not b then return nil end
    local e = {}
    local box = CreateFrame("Frame", nil, b)
    box:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    box:SetClipsChildren(true)
    if box.SetFrameLevel and b.GetFrameLevel then
        local lvl = b:GetFrameLevel()
        if type(lvl) == "number" then box:SetFrameLevel(lvl + 1) end   -- under the dispel chips (pip + 3)
    end
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(box)
    bg:SetColorTexture(EN.BG[1], EN.BG[2], EN.BG[3], EN.BG[4])
    local bar = CreateFrame("StatusBar", nil, box)
    bar:SetAllPoints(box)
    bar:SetStatusBarTexture(EN.TEX)
    -- heals on their way: as wide as the box, starting where their health ends; the box clips what runs past its edge
    local inc = CreateFrame("StatusBar", nil, box)
    local fill = bar:GetStatusBarTexture()
    inc:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    inc:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    inc:SetStatusBarTexture(EN.TEX)
    inc:SetStatusBarColor(EN.INCOMING[1], EN.INCOMING[2], EN.INCOMING[3], EN.INCOMING[4])
    inc:SetMinMaxValues(0, 1)
    inc:SetValue(0)
    -- the ghost: the same, starting where the heals on their way end
    local ghost = CreateFrame("StatusBar", nil, box)
    local incFill = inc:GetStatusBarTexture()
    ghost:SetPoint("TOPLEFT", incFill, "TOPRIGHT", 0, 0)
    ghost:SetPoint("BOTTOMLEFT", incFill, "BOTTOMRIGHT", 0, 0)
    ghost:SetStatusBarTexture(EN.TEX)
    ghost:SetStatusBarColor(EN.GHOST[1], EN.GHOST[2], EN.GHOST[3], EN.GHOST[4])
    ghost:Hide()
    box:Hide()
    -- the overheal: the filled health is a mask's shape; the bands fill leftwards from the box's right edge
    local cur = CreateFrame("Frame", nil, box)
    cur:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    cur:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    local mask = bar.CreateMaskTexture and bar:CreateMaskTexture() or nil
    if mask then
        mask:SetAllPoints(cur)
        mask:SetTexture(EN.TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    end
    local function band(c, anchor, point)
        local o = CreateFrame("StatusBar", nil, bar)
        o:SetPoint("TOPRIGHT", anchor, point, 0, 0)
        o:SetStatusBarTexture(EN.TEX)
        o:SetStatusBarColor(c[1], c[2], c[3], c[4])
        if o.SetReverseFill then o:SetReverseFill(true) end
        o:SetMinMaxValues(0, 1)
        o:SetValue(0)
        if o.SetFrameLevel and bar.GetFrameLevel then
            local lvl = bar:GetFrameLevel()
            if type(lvl) == "number" then o:SetFrameLevel(lvl + 3) end
        end
        local t = o.GetStatusBarTexture and o:GetStatusBarTexture()
        if mask and t and t.AddMaskTexture then t:AddMaskTexture(mask) end
        return o
    end
    local over = band(EN.OVER, box, "TOPRIGHT")
    -- a white tick where the waste begins (the grid's overTick), masked the same way: drawn only when there IS an overheal
    local overFill = over:GetStatusBarTexture()
    local tick = over:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(1, 1, 1, 0.95)
    tick:SetWidth(2)
    tick:SetPoint("TOPLEFT", overFill, "TOPLEFT", 0, 0)
    tick:SetPoint("BOTTOMLEFT", overFill, "BOTTOMLEFT", 0, 0)
    if mask and tick.AddMaskTexture then tick:AddMaskTexture(mask) end
    local overHover = band(EN.OVER_HOVER, overFill, "TOPLEFT")
    overHover:Hide()
    e.box, e.bar, e.inc, e.ghost = box, bar, inc, ghost
    e.cur, e.mask, e.over, e.overTick, e.overHover = cur, mask, over, tick, overHover
    sp.en = e
    return e
end

--- A box's width, for the ghost to match (the pip is resized by the console's class).
function EN.Size(sp)
    local e, b = sp.en, sp.heal
    if not (e and b and b.GetWidth) then return end
    local w = b:GetWidth()
    if type(w) == "number" and w > 2 then e.inc:SetWidth(w - 2) e.ghost:SetWidth(w - 2) end
    local h = b.GetHeight and b:GetHeight()
    if type(w) == "number" and w > 2 and type(h) == "number" and h > 2 then
        e.over:SetSize(w - 2, h - 2)
        e.overHover:SetSize(w - 2, h - 2)
    end
end

--- Their health into the bar, untouched, in their class colour. Answers true when painted.
function EN.Paint(sp)
    if not console() or not (sp and sp.unit) then
        if sp and sp.en then sp.en.box:Hide() end
        return false
    end
    local e = EN.Box(sp)
    if not e then return false end
    local unit = sp.unit
    local okM, mx = pcall(UnitHealthMax, unit)
    local okV, v = pcall(UnitHealth, unit)
    if okM and okV then
        pcall(e.bar.SetMinMaxValues, e.bar, 0, mx)
        pcall(e.bar.SetValue, e.bar, v)
    end
    EN.Incoming(sp, okM and mx or nil)
    local FG = NS.FG
    local cls
    if UnitClass then
        local ok, _, token = pcall(UnitClass, unit)
        if ok then cls = plain(token) end
    end
    local c = (FG and FG.CLASS_COLOR and FG.CLASS_COLOR[cls or ""]) or EN.FALLBACK
    if UnitIsDeadOrGhost then
        local okD, dead = pcall(UnitIsDeadOrGhost, unit)
        if okD and plain(dead) == true then c = (FG and FG.DEAD_COLOR) or { 0.35, 0.10, 0.10 } end
    end
    e.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    e.box:Show()
    return true
end

--- Heals on their way into the box's incoming bar, untouched, on their max (asked here when not handed). True = drawn.
function EN.Incoming(sp, mx)
    local e = sp and sp.en
    if not (e and sp.unit and UnitGetIncomingHeals) then return false end
    if mx == nil then
        local okM, m = pcall(UnitHealthMax, sp.unit)
        if not okM then return false end
        mx = m
    end
    local ok, v = pcall(UnitGetIncomingHeals, sp.unit)
    if not ok then return false end
    if v == nil then v = 0 end
    pcall(e.inc.SetMinMaxValues, e.inc, 0, mx)
    pcall(e.inc.SetValue, e.inc, v)
    -- the overheal is the SAME value on the same scale, filling from the other end (the grid's bargain)
    pcall(e.over.SetMinMaxValues, e.over, 0, mx)
    pcall(e.over.SetValue, e.over, v)
    return true
end

--- Range: the grid's own dimming on each box (the box, never the secure pip). While the console shows.
function EN.Range()
    if not console() then return 0 end
    local FG, n = NS.FG, 0
    if not (FG and FG.PaintRange) then return 0 end
    -- which spell measures range is the same for every box: asked ONCE a tick, the grid's own way (FG.tickRange)
    local mine = FG.tickRange == nil and NS.FM and NS.FM.RangeSpell
    if mine then
        local ok, spell, id = pcall(NS.FM.RangeSpell)
        FG.tickRange = ok and { spell, id } or nil
    end
    for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
        if sp.en and sp.unit and sp.en.box:IsShown() then
            pcall(FG.PaintRange, sp.en.box, sp.unit)
            n = n + 1
        end
    end
    if mine then FG.tickRange = nil end
    return n
end

--- The ghost: your heal after the heals on their way, as long as the heal is against their max (a secret, the client's sum).
--- nil heal = gone.
function EN.Ghost(sp, heal)
    -- the radar's tanks take the same heal (Tanks.lua): one road from Overheal.lua for both views
    if NS.TK and NS.TK.Ghost then NS.TK.Ghost(sp, heal) end
    local e = sp and sp.en
    if not e then return false end
    if not (heal and console() and sp.unit and e.box:IsShown()) then e.ghost:Hide() e.overHover:Hide() return false end
    local okM, mx = pcall(UnitHealthMax, sp.unit)
    if not okM or not pcall(e.ghost.SetMinMaxValues, e.ghost, 0, mx) then e.ghost:Hide() e.overHover:Hide() return false end
    pcall(e.ghost.SetValue, e.ghost, heal)
    e.ghost:Show()
    -- what your heal would waste on top of the heals already coming: the fainter band, on from the first one's end
    pcall(e.overHover.SetMinMaxValues, e.overHover, 0, mx)
    pcall(e.overHover.SetValue, e.overHover, heal)
    e.overHover:Show()
    return true
end

--- Into the console or back to the radar: bars or glyphs, and where the click word sits. Out of a fight (the layouts).
function EN.Layout(con)
    local RD = NS.RD
    for _, sp in ipairs((RD and RD.spokes) or {}) do
        local b = sp.heal
        if b then
            for _, face in ipairs({ b.beat, b.redFace, b.amberFace }) do
                if face then if con then face:Hide() else face:Show() end end
            end
            if sp.los then
                sp.los:ClearAllPoints()
                sp.los:SetPoint(EN.HeadSpot("los"))    -- the header's LOS box, the console's or the radar's alert row
            end
            if NS.OV and NS.OV.Anchor and sp.over then NS.OV.Anchor(sp) end
            if con then
                EN.Box(sp)
                EN.Size(sp)
                EN.Paint(sp)
            elseif sp.en then
                sp.en.box:Hide()
                sp.en.ghost:Hide()
                sp.en.overHover:Hide()
            end
        end
    end
    if con then EN.Range() end
    EN.HeadBoxes()                                                      -- the three boxes on the surface showing now
    -- heals on their way: heard only while the console shows (a raid's predictions cost nothing on the radar)
    if EN.events and EN.events.UnregisterEvent then
        if con then pcall(EN.events.RegisterEvent, EN.events, "UNIT_HEAL_PREDICTION")
        else EN.events:UnregisterEvent("UNIT_HEAL_PREDICTION") end
    end
end

--[[ THE FUEL STRIP ON TOP (Arn, 12 Nov: "all engineering can get a barebones mana guage on top from the rader its own
  version" - "with the bingo and mana regen 5 second rule but much smaller"). Not a second gauge: the radar's own tape
  (RD.gauge - your mana, the boss's red past it, BINGO's hot band, the magenta caret, the quarter ticks), moved onto a
  thin plate over the console and shaped to its width (RD.ShapeTape). Barebones: no placard, no scale numbers, no
  readout box riding the fill, no chevron - the regen % small at the right end with the five second rule's dashes under
  it. Every number is still painted by the radar's own functions (RD.PaintFuel); this only moves pieces, out of a fight
  (the view switch). Back on the radar everything goes home (RD.SizeGauge). ]]
EN.GAUGE = { h = 20, pad = 6, right = 44, font = 8 }

--- How far the strip reaches over the console's top (the clamp keeps it on the screen); 0 when it is not there.
function EN.GaugeTop()
    local RD = NS.RD
    if not (EN.rail and EN.rail:IsShown()) then return 0 end
    return EN.GAUGE.h + ((RD and RD.RAIL_GAP) or 2)
end

--- Into the console (true) or back to the radar: the tape moves, its extras hide or come back. Out of a fight.
function EN.Gauge(con)
    local RD = NS.RD
    local g, f = RD and RD.gauge, RD and RD.frame
    if not (g and f) then return false end
    local E, gap = EN.GAUGE, RD.RAIL_GAP or 2
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if con then
        if not EN.rail then
            local r = CreateFrame("Frame", nil, f)
            r:SetFrameLevel(math.max(0, f:GetFrameLevel()))
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetAllPoints(r)
            local P = RD.PLATE or { 0.05, 0.04, 0.09 }
            r.bg:SetColorTexture(P[1], P[2], P[3], 1)
            EN.rail = r
        end
        local r = EN.rail
        r:ClearAllPoints()
        r:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, gap)
        r:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, gap)
        r:SetHeight(E.h)
        r:Show()
        local fw = f:GetWidth()
        local w = (type(fw) == "number" and fw or 200) - E.pad - E.right
        g:ClearAllPoints()
        g:SetPoint("LEFT", r, "LEFT", E.pad, 0)
        RD.ShapeTape(w)
        g:Show()
        if g.hud then g.hud:Hide() end
        if g.readout then g.readout:Hide() end
        if g.chev then g.chev:Hide() end
        if g.regen then
            if g.regen.SetFont then g.regen:SetFont(font, E.font, "") end
            g.regen:ClearAllPoints()
            g.regen:SetPoint("CENTER", r, "RIGHT", -E.right / 2, 3)
            g.regen:Show()
        end
        if g.fsr then g.fsr:Show() end                       -- it hangs under the regen %, wherever that goes
    else
        -- only when coming back from the console: the radar's own sizing is left alone otherwise
        if not (EN.rail and EN.rail:IsShown()) then return false end
        EN.rail:Hide()
        if g.hud then g.hud:Show() end
        if g.readout then g.readout:Show() end
        if g.regen then
            if g.regen.SetFont then g.regen:SetFont(font, 10, "") end
            g.regen:ClearAllPoints()
            g.regen:SetPoint("CENTER", RD.gaugeRail or f, "RIGHT", -math.floor(RD.GAUGE.right / 2) - 4, 4)
        end
        -- the tape home, on the radar's rail, as wide as the radar is now (a raid's square is bigger)
        if RD.FitWide then RD.FitWide() elseif RD.SizeGauge then RD.SizeGauge(RD.SIZE) end
    end
    return true
end

-- the radar's own functions, wrapped (they are called through RD, so the wrap is what runs)
local function wrap()
    local RD = NS.RD
    if not RD or RD.__enWrapped then return end
    RD.__enWrapped = true
    local paint, conLayout, radarLayout, look = RD.PaintHeal, RD.ConsoleLayout, RD.RadarLayout, RD.Look
    if paint then RD.PaintHeal = function(sp, ...) local r = paint(sp, ...) EN.Paint(sp) return r end end
    if conLayout then
        RD.ConsoleLayout = function(...)
            local r = conLayout(...)
            if r then EN.Layout(true) end
            return r
        end
    end
    if radarLayout then
        RD.RadarLayout = function(...)
            local r = radarLayout(...)
            if r then EN.Layout(false) end
            return r
        end
    end
    if look then RD.Look = function(...) local r = look(...) EN.Range() return r end end
    -- the view switch: after it has hidden or shown the radar's pieces, the fuel strip moves (and the clamp follows)
    local apply = RD.ApplyView
    if apply then
        RD.ApplyView = function(...)
            local r = apply(...)
            local con = console()
            EN.Gauge(con)
            if con and RD.ClampRails then RD.ClampRails() end
            return r
        end
    end
end
wrap()

local ev = CreateFrame("Frame")
EN.events = ev
pcall(ev.RegisterEvent, ev, "UNIT_IN_RANGE_UPDATE")
ev:SetScript("OnEvent", function(_, event, unit)
    if not console() or secret(unit) then return end
    if event == "UNIT_HEAL_PREDICTION" then
        for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
            if sp.unit == unit and sp.en and sp.en.box:IsShown() then EN.Incoming(sp) end
        end
        return
    end
    if event ~= "UNIT_IN_RANGE_UPDATE" then return end
    local FG = NS.FG
    for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
        if sp.unit == unit and sp.en and FG and FG.PaintRange then pcall(FG.PaintRange, sp.en.box, unit) end
    end
end)
