--[[
  BiSHealing :: Tanks.lua - EVERY RADAR PIP IS A SMALL TANK (12 Nov 2026).

  Arn: "im afraid we made engineer better than radar now i find my self using engineer more how can we bring radar up to
  speed" - then "all three" (the tanks, the alerts on the top rail, the kick shield).

  The engineer's boxes show health, heals on their way, the overheal and your hover's heal; the radar's pips only changed
  colour. Now each pip carries the same inside it, filling from the bottom, behind its role glyph:
    * the FILL: their health (UnitHealthMax / UnitHealth handed untouched to a vertical StatusBar), coloured by its own
      curve - red, amber, green, and gone at RD.GREEN (90%) like the pip itself: the radar stays quiet, a tank shows only
      when the pip does;
    * HEALS ON THEIR WAY in cyan on top of it (UnitGetIncomingHeals, untouched), and the part that would land on nobody in
      MAGENTA from the top down, masked to their filled health (the grid's own trick, Grid.lua f.overheal);
    * YOUR HOVER HEAL: a fainter cyan on from the incoming, and a fainter magenta what it would waste (Overheal.lua hands
      it the heal through EN.Ghost).
  Every band's colour comes from a curve evaluated by the client on their health (TK.Gate), so a band never shows on a
  pip that is hidden - nothing here ever reads or compares a number. In the engineer's console the tanks hide (its boxes
  do this job). No dark track and no white tick (Arn, 8 Nov: "the box outlines are not needed" - an empty track reads
  as one; and every band is one more colour asked per health change - a 40-man repaint has a budget). Cost: the radar's
  own health events plus UNIT_HEAL_PREDICTION, heard only while the radar shows.
]]
local ADDON, NS = ...
NS = NS or {}

local TK = {}
NS.TK = TK

TK.TEX = "Interface\\Buttons\\WHITE8X8"
TK.INSET = 2                                -- the tank sits this far inside the pip
TK.FILL_A = 0.45                            -- the fill under the glyph: see-through, so the glyph reads on it
TK.INCOMING = { 0.22, 0.80, 1.00, 0.60 }    -- the engineer's cyan (EN.INCOMING)
TK.PREVIEW = { 0.22, 0.80, 1.00, 0.28 }     -- your hover heal, fainter
TK.OVER = { 1.00, 0.12, 0.85, 0.95 }        -- the grid's overheal magenta
TK.OVER_HOVER = { 1.00, 0.12, 0.85, 0.45 }

local function secret(v) return NS.Secret and NS.Secret(v) or false end
local function plain(v) if v == nil or secret(v) then return nil end return v end

local function radarOn()
    local RD = NS.RD
    if not (RD and RD.On and RD.On()) then return false end
    return not (RD.Console and RD.Console())
end
TK.On = radarOn

-- ------------------------------------------------------------------ the curves (the client decides)

local gates = {}
--- A band's colour by health fraction: `c` below RD.GREEN, see-through above it - the pip's own "gone when fine".
function TK.Gate(c)
    local RD = NS.RD
    local key = table.concat(c, ",")
    if gates[key] then return gates[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and RD) then return nil end
    local ok, cv = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not cv or not cv.AddPoint then return nil end
    if cv.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(cv.SetType, cv, Enum.LuaCurveType.Linear)
    end
    local G = RD.GREEN or 0.9
    pcall(cv.AddPoint, cv, 0.00, CreateColor(c[1], c[2], c[3], c[4] or 1))
    pcall(cv.AddPoint, cv, G, CreateColor(c[1], c[2], c[3], c[4] or 1))
    pcall(cv.AddPoint, cv, G + 0.0001, CreateColor(c[1], c[2], c[3], 0))
    pcall(cv.AddPoint, cv, 1.00, CreateColor(c[1], c[2], c[3], 0))
    gates[key] = cv
    return cv
end

local fills = {}
--- The fill's colour: red under RD.RED, amber under `amber`, green under RD.GREEN, gone above (TK.FILL_A see-through).
function TK.FillCurve(amber)
    local RD = NS.RD
    if not RD then return nil end
    amber = math.max(RD.RED + 0.02, math.min(amber or RD.AMBER, RD.GREEN - 0.01))
    local key = math.floor(amber * 100 + 0.5)
    if fills[key] then return fills[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, cv = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not cv or not cv.AddPoint then return nil end
    if cv.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(cv.SetType, cv, Enum.LuaCurveType.Linear)
    end
    local R, A, Gc, a = RD.COL.red, RD.COL.amber, RD.COL.green, TK.FILL_A
    local function at(x, col, al) pcall(cv.AddPoint, cv, x, CreateColor(col[1], col[2], col[3], al)) end
    at(0.00, R, a) at(RD.RED, R, a)
    at(RD.RED + 0.0001, A, a) at(amber, A, a)
    at(amber + 0.0001, Gc, a) at(RD.GREEN, Gc, a)
    at(RD.GREEN + 0.0001, Gc, 0) at(1.00, Gc, 0)
    fills[key] = cv
    return cv
end

--- The client's colour for `unit` through `curve` onto each texture. True when one landed.
local function tint(unit, curve, ...)
    if not (curve and UnitHealthPercent) then return false end
    local ok, col = pcall(UnitHealthPercent, unit, true, curve)
    if not ok or type(col) ~= "table" or not col.GetRGBA then return false end
    local any = false
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if t and pcall(function() t:SetVertexColor(col:GetRGBA()) end) then any = true end
    end
    return any
end

-- ------------------------------------------------------------------ the tank inside a pip

local function vbar(parent, level)
    local s = CreateFrame("StatusBar", nil, parent)
    s:SetOrientation("VERTICAL")
    s:SetStatusBarTexture(TK.TEX)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    if level and s.SetFrameLevel then s:SetFrameLevel(level) end
    return s
end

--- A pip's tank: a plain frame inside the secure pip, clipping its bands, under the glyph's faces. Built on first need.
function TK.Build(sp)
    if sp.tank then return sp.tank end
    local b = sp.heal
    if not b then return nil end
    local t = {}
    local box = CreateFrame("Frame", nil, b)
    box:SetPoint("TOPLEFT", b, "TOPLEFT", TK.INSET, -TK.INSET)
    box:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -TK.INSET, TK.INSET)
    box:SetClipsChildren(true)
    local lvl = b.GetFrameLevel and b:GetFrameLevel()
    lvl = type(lvl) == "number" and lvl or 1
    if box.SetFrameLevel then box:SetFrameLevel(lvl) end          -- the glyph's faces are the pip's children, above it
    -- and lifted clear of the tank's bands, so the role glyph always reads on top
    for _, face in ipairs({ b.beat, b.redFace, b.amberFace }) do
        if face and face.SetFrameLevel then face:SetFrameLevel(lvl + 3) end
    end
    t.bar = vbar(box, lvl)
    t.bar:SetAllPoints(box)
    local fill = t.bar:GetStatusBarTexture()
    -- heals on their way: from the top of the fill up; your hover heal on from them
    t.inc = vbar(box, lvl)
    t.inc:SetPoint("BOTTOMLEFT", fill, "TOPLEFT", 0, 0)
    t.inc:SetPoint("BOTTOMRIGHT", fill, "TOPRIGHT", 0, 0)
    local incFill = t.inc:GetStatusBarTexture()
    t.prev = vbar(box, lvl)
    t.prev:SetPoint("BOTTOMLEFT", incFill, "TOPLEFT", 0, 0)
    t.prev:SetPoint("BOTTOMRIGHT", incFill, "TOPRIGHT", 0, 0)
    t.prev:Hide()
    -- the overheal: from the TOP down, masked to the filled health
    t.cur = CreateFrame("Frame", nil, box)
    t.cur:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    t.cur:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    t.mask = t.bar.CreateMaskTexture and t.bar:CreateMaskTexture() or nil
    if t.mask then
        t.mask:SetAllPoints(t.cur)
        t.mask:SetTexture(TK.TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    end
    local function masked(tex) if t.mask and tex and tex.AddMaskTexture then tex:AddMaskTexture(t.mask) end end
    t.over = vbar(t.bar, lvl + 1)
    t.over:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    t.over:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    if t.over.SetReverseFill then t.over:SetReverseFill(true) end
    local overFill = t.over:GetStatusBarTexture()
    masked(overFill)
    t.overPrev = vbar(t.bar, lvl + 1)
    t.overPrev:SetPoint("TOPLEFT", overFill, "BOTTOMLEFT", 0, 0)
    t.overPrev:SetPoint("TOPRIGHT", overFill, "BOTTOMRIGHT", 0, 0)
    if t.overPrev.SetReverseFill then t.overPrev:SetReverseFill(true) end
    masked(t.overPrev:GetStatusBarTexture())
    t.overPrev:Hide()
    box:Hide()
    t.box = box
    sp.tank = t
    return t
end

--- The bands as tall as the pip's inside (the pip is resized by the radar's ring and class).
function TK.Size(sp)
    local t, b = sp.tank, sp.heal
    if not (t and b and b.GetHeight) then return end
    local h, w = b:GetHeight(), b:GetWidth()
    if type(h) ~= "number" or h <= 2 * TK.INSET then return end
    local ih = h - 2 * TK.INSET
    for _, s in ipairs({ t.inc, t.prev, t.over, t.overPrev }) do s:SetHeight(ih) end
    if type(w) == "number" and w > 2 * TK.INSET then
        for _, s in ipairs({ t.inc, t.prev, t.over, t.overPrev }) do s:SetWidth(w - 2 * TK.INSET) end
    end
end

--- Their health, the heals coming and the overheal into the tank, each band coloured by the client from their health.
--- Answers true when painted.
function TK.Paint(sp)
    local t = sp and sp.tank
    if not radarOn() or not (sp and sp.unit) then
        if t then t.box:Hide() end
        return false
    end
    t = TK.Build(sp)
    if not t then return false end
    local unit = sp.unit
    if UnitIsDeadOrGhost then
        local okD, dead = pcall(UnitIsDeadOrGhost, unit)
        if okD and plain(dead) == true then t.box:Hide() return false end
    end
    local okM, mx = pcall(UnitHealthMax, unit)
    local okV, v = pcall(UnitHealth, unit)
    if not (okM and okV) then t.box:Hide() return false end
    pcall(t.bar.SetMinMaxValues, t.bar, 0, mx)
    pcall(t.bar.SetValue, t.bar, v)
    local inc = 0
    if UnitGetIncomingHeals then
        local okI, iv = pcall(UnitGetIncomingHeals, unit)
        if okI and iv ~= nil then inc = iv end
    end
    for _, s in ipairs({ t.inc, t.over }) do
        pcall(s.SetMinMaxValues, s, 0, mx)
        pcall(s.SetValue, s, inc)
    end
    tint(unit, TK.FillCurve(sp.amber), t.bar:GetStatusBarTexture())
    tint(unit, TK.Gate(TK.INCOMING), t.inc:GetStatusBarTexture())
    tint(unit, TK.Gate(TK.OVER), t.over:GetStatusBarTexture())
    t.box:Show()
    return true
end

--- Your hover heal in the tank (Overheal.lua, through EN.Ghost): a fainter cyan on from the incoming, and a fainter
--- magenta for what it would waste. nil heal = gone.
function TK.Ghost(sp, heal)
    local t = sp and sp.tank
    if not t then return false end
    if not (heal and radarOn() and sp.unit and t.box:IsShown()) then t.prev:Hide() t.overPrev:Hide() return false end
    local okM, mx = pcall(UnitHealthMax, sp.unit)
    if not okM then t.prev:Hide() t.overPrev:Hide() return false end
    for _, s in ipairs({ t.prev, t.overPrev }) do
        pcall(s.SetMinMaxValues, s, 0, mx)
        pcall(s.SetValue, s, heal)
    end
    tint(sp.unit, TK.Gate(TK.PREVIEW), t.prev:GetStatusBarTexture())
    tint(sp.unit, TK.Gate(TK.OVER_HOVER), t.overPrev:GetStatusBarTexture())
    t.prev:Show()
    t.overPrev:Show()
    return true
end

--- On the radar: every tank sized and painted; in the console (or the radar off): every tank away. Out of a fight.
function TK.Layout(on)
    local RD = NS.RD
    for _, sp in ipairs((RD and RD.spokes) or {}) do
        if on and sp.unit then
            TK.Build(sp)
            TK.Size(sp)
            TK.Paint(sp)
        elseif sp.tank then
            sp.tank.box:Hide()
            sp.tank.prev:Hide()
            sp.tank.overPrev:Hide()
        end
    end
    -- heals on their way: heard only while the radar shows its tanks
    if TK.events and TK.events.UnregisterEvent then
        if on then pcall(TK.events.RegisterEvent, TK.events, "UNIT_HEAL_PREDICTION")
        else TK.events:UnregisterEvent("UNIT_HEAL_PREDICTION") end
    end
end

-- the radar's own functions, wrapped (called through RD, so the wrap is what runs)
local function wrap()
    local RD = NS.RD
    if not RD or RD.__tkWrapped then return end
    RD.__tkWrapped = true
    local paint, conLayout, radarLayout = RD.PaintHeal, RD.ConsoleLayout, RD.RadarLayout
    if paint then RD.PaintHeal = function(sp, ...) local r = paint(sp, ...) TK.Paint(sp) return r end end
    if radarLayout then
        RD.RadarLayout = function(...)
            local r = radarLayout(...)
            if r then TK.Layout(true) end
            return r
        end
    end
    if conLayout then
        RD.ConsoleLayout = function(...)
            local r = conLayout(...)
            if r then TK.Layout(false) end
            return r
        end
    end
end
wrap()

local ev = CreateFrame("Frame")
TK.events = ev
ev:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_HEAL_PREDICTION" or not radarOn() or secret(unit) then return end
    for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
        if sp.unit == unit and sp.tank and sp.tank.box:IsShown() then TK.Paint(sp) end
    end
end)
