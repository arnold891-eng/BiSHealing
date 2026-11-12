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
    * OVERHEAL: while you hover, your left-click heal as a pale GHOST right after their health - as long as the heal is,
      cut off at the box's edge (the client draws the heal against their max, a secret) - and OVER/H under the box when
      more than half would be wasted (Overheal.lua).
  On the radar nothing changes: the bars hide, the glyphs come back, the click word goes back under the pip.
  Cost: health on its events (one unit), range on the radar's half-second tick while the console shows.
]]
local ADDON, NS = ...
NS = NS or {}

local EN = {}
NS.EN = EN

EN.BG = { 0.04, 0.05, 0.06, 0.92 }       -- the empty part of a box
EN.GHOST = { 0.62, 0.88, 1.00, 0.55 }    -- your heal, pale, after their health
EN.FALLBACK = { 0.20, 0.70, 0.30 }       -- a class the client will not say
EN.TEX = "Interface\\Buttons\\WHITE8X8"

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
    -- the ghost: as wide as the box, starting where their health ends; the box clips what runs past its edge
    local ghost = CreateFrame("StatusBar", nil, box)
    local fill = bar:GetStatusBarTexture()
    ghost:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    ghost:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    ghost:SetStatusBarTexture(EN.TEX)
    ghost:SetStatusBarColor(EN.GHOST[1], EN.GHOST[2], EN.GHOST[3], EN.GHOST[4])
    ghost:Hide()
    box:Hide()
    e.box, e.bar, e.ghost = box, bar, ghost
    sp.en = e
    return e
end

--- A box's width, for the ghost to match (the pip is resized by the console's class).
function EN.Size(sp)
    local e, b = sp.en, sp.heal
    if not (e and b and b.GetWidth) then return end
    local w = b:GetWidth()
    if type(w) == "number" and w > 2 then e.ghost:SetWidth(w - 2) end
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

--- The ghost: your heal after their health, as long as the heal is against their max (a secret, the client's sum).
--- nil heal = gone.
function EN.Ghost(sp, heal)
    local e = sp and sp.en
    if not e then return false end
    if not (heal and console() and sp.unit and e.box:IsShown()) then e.ghost:Hide() return false end
    local okM, mx = pcall(UnitHealthMax, sp.unit)
    if not okM or not pcall(e.ghost.SetMinMaxValues, e.ghost, 0, mx) then e.ghost:Hide() return false end
    pcall(e.ghost.SetValue, e.ghost, heal)
    e.ghost:Show()
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
                if con then sp.los:SetPoint("CENTER", b, "CENTER", 0, 0)       -- in the box, as on the grid
                else sp.los:SetPoint("TOP", b, "BOTTOM", 0, -1) end            -- under the pip, as the radar had it
            end
            if NS.OV and NS.OV.Anchor and sp.over then NS.OV.Anchor(sp) end
            if con then
                EN.Box(sp)
                EN.Size(sp)
                EN.Paint(sp)
            elseif sp.en then
                sp.en.box:Hide()
                sp.en.ghost:Hide()
            end
        end
    end
    if con then EN.Range() end
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
end
wrap()

local ev = CreateFrame("Frame")
EN.events = ev
pcall(ev.RegisterEvent, ev, "UNIT_IN_RANGE_UPDATE")
ev:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_IN_RANGE_UPDATE" or not console() or secret(unit) then return end
    local FG = NS.FG
    for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
        if sp.unit == unit and sp.en and FG and FG.PaintRange then pcall(FG.PaintRange, sp.en.box, unit) end
    end
end)
