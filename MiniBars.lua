--[[
  BiSHealing :: MiniBars.lua - A MINI HEALTH BAR UNDER EVERY RADAR PIP (12 Nov 2026).

  Arn: "im afraid we made engineer better than radar ... how can we bring radar up to speed". First try: a tank inside
  each pip, filling up and down. Arn: "hmm i dont like it, i think go mini heal bars to make it easier, and lets not do
  like engineer up and down lets go left and right".

  So each pip gets a small bar UNDER it, filling LEFT TO RIGHT - the engineer's box, small:
    * the FILL: their health (UnitHealthMax / UnitHealth handed untouched), red / amber / green by its own curve;
    * a dark TRACK behind it, so how much is missing reads at a glance;
    * HEALS ON THEIR WAY in cyan after the fill (UnitGetIncomingHeals, untouched), and the part that would land on nobody
      in MAGENTA from the right edge leftwards, masked to the filled health (the grid's own trick, Grid.lua f.overheal);
    * YOUR HOVER HEAL: a fainter cyan on from the incoming, and a fainter magenta what it would waste (Overheal.lua hands
      it the heal through EN.Ghost).
  Every band's colour comes from a curve the client evaluates on their health (MB.Gate), gone at RD.GREEN (90%) like the
  pip itself: the radar stays quiet, a bar shows only when its pip does. Nothing here reads or compares a number. In the
  engineer's console the bars hide (its boxes do this job). Cost: the radar's own health events plus
  UNIT_HEAL_PREDICTION, heard only while the radar shows; a 40-man repaint has a budget (dev/tests.lua).
]]
local ADDON, NS = ...
NS = NS or {}

local MB = {}
NS.MB = MB

MB.TEX = "Interface\\Buttons\\WHITE8X8"
MB.H = 4                                    -- the bar's height
MB.WIDER = 8                                -- this much wider than the pip
MB.GAP = 2                                  -- under the pip by this much
MB.TRACK = { 0.03, 0.04, 0.06, 0.85 }       -- the empty part
MB.FILL_A = 1
MB.INCOMING = { 0.22, 0.80, 1.00, 0.85 }    -- the engineer's cyan
MB.PREVIEW = { 0.22, 0.80, 1.00, 0.40 }     -- your hover heal, fainter
MB.OVER = { 1.00, 0.12, 0.85, 1.00 }        -- the grid's overheal magenta
MB.OVER_HOVER = { 1.00, 0.12, 0.85, 0.55 }

local function secret(v) return NS.Secret and NS.Secret(v) or false end
local function plain(v) if v == nil or secret(v) then return nil end return v end

local function radarOn()
    local RD = NS.RD
    if not (RD and RD.On and RD.On()) then return false end
    return not (RD.Console and RD.Console())
end
MB.On = radarOn

-- ------------------------------------------------------------------ the curves (the client decides)

local gates = {}
--- A band's colour by health fraction: `c` below RD.GREEN, see-through above it - the pip's own "gone when fine".
function MB.Gate(c)
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
--- The fill's colour: red under RD.RED, amber under `amber`, green under RD.GREEN, gone above.
function MB.FillCurve(amber)
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
    local R, A, Gc, a = RD.COL.red, RD.COL.amber, RD.COL.green, MB.FILL_A
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

-- ------------------------------------------------------------------ the bar under a pip

local function hbar(parent, level)
    local s = CreateFrame("StatusBar", nil, parent)
    s:SetStatusBarTexture(MB.TEX)
    s:SetMinMaxValues(0, 1)
    s:SetValue(0)
    if level and s.SetFrameLevel then s:SetFrameLevel(level) end
    return s
end

--- A pip's mini bar: a plain frame hung under the secure pip (its child, so it hides with it), clipping its bands.
function MB.Build(sp)
    if sp.mini then return sp.mini end
    local b = sp.heal
    if not b then return nil end
    local m = {}
    local box = CreateFrame("Frame", nil, b)
    box:SetPoint("TOP", b, "BOTTOM", 0, -MB.GAP)
    box:SetHeight(MB.H)
    box:SetClipsChildren(true)
    local lvl = b.GetFrameLevel and b:GetFrameLevel()
    lvl = (type(lvl) == "number" and lvl or 1) + 1
    if box.SetFrameLevel then box:SetFrameLevel(lvl) end
    m.track = box:CreateTexture(nil, "BACKGROUND")
    m.track:SetAllPoints(box)
    m.track:SetTexture(MB.TEX)
    m.bar = hbar(box, lvl)
    m.bar:SetAllPoints(box)
    local fill = m.bar:GetStatusBarTexture()
    -- heals on their way after the fill; your hover heal on from them
    m.inc = hbar(box, lvl)
    m.inc:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
    m.inc:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    local incFill = m.inc:GetStatusBarTexture()
    m.prev = hbar(box, lvl)
    m.prev:SetPoint("TOPLEFT", incFill, "TOPRIGHT", 0, 0)
    m.prev:SetPoint("BOTTOMLEFT", incFill, "BOTTOMRIGHT", 0, 0)
    m.prev:Hide()
    -- the overheal: from the RIGHT edge leftwards, masked to the filled health
    m.cur = CreateFrame("Frame", nil, box)
    m.cur:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    m.cur:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
    m.mask = m.bar.CreateMaskTexture and m.bar:CreateMaskTexture() or nil
    if m.mask then
        m.mask:SetAllPoints(m.cur)
        m.mask:SetTexture(MB.TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
    end
    local function masked(tex) if m.mask and tex and tex.AddMaskTexture then tex:AddMaskTexture(m.mask) end end
    m.over = hbar(m.bar, lvl + 1)
    m.over:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
    m.over:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    if m.over.SetReverseFill then m.over:SetReverseFill(true) end
    local overFill = m.over:GetStatusBarTexture()
    masked(overFill)
    m.overPrev = hbar(m.bar, lvl + 1)
    m.overPrev:SetPoint("TOPRIGHT", overFill, "TOPLEFT", 0, 0)
    m.overPrev:SetPoint("BOTTOMRIGHT", overFill, "BOTTOMLEFT", 0, 0)
    if m.overPrev.SetReverseFill then m.overPrev:SetReverseFill(true) end
    masked(m.overPrev:GetStatusBarTexture())
    m.overPrev:Hide()
    box:Hide()
    m.box = box
    sp.mini = m
    return m
end

--- The bar a little wider than its pip (the pip is resized by the radar's ring and class), its bands as wide.
function MB.Size(sp)
    local m, b = sp.mini, sp.heal
    if not (m and b and b.GetWidth) then return end
    local w = b:GetWidth()
    if type(w) ~= "number" or w <= 0 then return end
    local bw = w + MB.WIDER
    m.box:SetWidth(bw)
    for _, s in ipairs({ m.inc, m.prev, m.over, m.overPrev }) do s:SetWidth(bw) end
end

--- Their health, the heals coming and the overheal into the bar, each band coloured by the client from their health.
--- Answers true when painted.
function MB.Paint(sp)
    local m = sp and sp.mini
    if not radarOn() or not (sp and sp.unit) then
        if m then m.box:Hide() end
        return false
    end
    m = MB.Build(sp)
    if not m then return false end
    local unit = sp.unit
    if UnitIsDeadOrGhost then
        local okD, dead = pcall(UnitIsDeadOrGhost, unit)
        if okD and plain(dead) == true then m.box:Hide() return false end
    end
    local okM, mx = pcall(UnitHealthMax, unit)
    local okV, v = pcall(UnitHealth, unit)
    if not (okM and okV) then m.box:Hide() return false end
    pcall(m.bar.SetMinMaxValues, m.bar, 0, mx)
    pcall(m.bar.SetValue, m.bar, v)
    local inc = 0
    if UnitGetIncomingHeals then
        local okI, iv = pcall(UnitGetIncomingHeals, unit)
        if okI and iv ~= nil then inc = iv end
    end
    for _, s in ipairs({ m.inc, m.over }) do
        pcall(s.SetMinMaxValues, s, 0, mx)
        pcall(s.SetValue, s, inc)
    end
    tint(unit, MB.FillCurve(sp.amber), m.bar:GetStatusBarTexture())
    tint(unit, MB.Gate(MB.TRACK), m.track)
    tint(unit, MB.Gate(MB.INCOMING), m.inc:GetStatusBarTexture())
    tint(unit, MB.Gate(MB.OVER), m.over:GetStatusBarTexture())
    m.box:Show()
    return true
end

--- Your hover heal in the bar (Overheal.lua, through EN.Ghost): a fainter cyan on from the incoming, and a fainter
--- magenta for what it would waste. nil heal = gone.
function MB.Ghost(sp, heal)
    local m = sp and sp.mini
    if not m then return false end
    if not (heal and radarOn() and sp.unit and m.box:IsShown()) then m.prev:Hide() m.overPrev:Hide() return false end
    local okM, mx = pcall(UnitHealthMax, sp.unit)
    if not okM then m.prev:Hide() m.overPrev:Hide() return false end
    for _, s in ipairs({ m.prev, m.overPrev }) do
        pcall(s.SetMinMaxValues, s, 0, mx)
        pcall(s.SetValue, s, heal)
    end
    tint(sp.unit, MB.Gate(MB.PREVIEW), m.prev:GetStatusBarTexture())
    tint(sp.unit, MB.Gate(MB.OVER_HOVER), m.overPrev:GetStatusBarTexture())
    m.prev:Show()
    m.overPrev:Show()
    return true
end

--- On the radar: every bar sized and painted; in the console (or the radar off): every bar away. Out of a fight.
function MB.Layout(on)
    local RD = NS.RD
    for _, sp in ipairs((RD and RD.spokes) or {}) do
        if on and sp.unit then
            MB.Build(sp)
            MB.Size(sp)
            MB.Paint(sp)
        elseif sp.mini then
            sp.mini.box:Hide()
            sp.mini.prev:Hide()
            sp.mini.overPrev:Hide()
        end
    end
    -- heals on their way: heard only while the radar shows its bars
    if MB.events and MB.events.UnregisterEvent then
        if on then pcall(MB.events.RegisterEvent, MB.events, "UNIT_HEAL_PREDICTION")
        else MB.events:UnregisterEvent("UNIT_HEAL_PREDICTION") end
    end
end

-- the radar's own functions, wrapped (called through RD, so the wrap is what runs)
local function wrap()
    local RD = NS.RD
    if not RD or RD.__mbWrapped then return end
    RD.__mbWrapped = true
    local paint, conLayout, radarLayout = RD.PaintHeal, RD.ConsoleLayout, RD.RadarLayout
    if paint then RD.PaintHeal = function(sp, ...) local r = paint(sp, ...) MB.Paint(sp) return r end end
    if radarLayout then
        RD.RadarLayout = function(...)
            local r = radarLayout(...)
            if r then MB.Layout(true) end
            return r
        end
    end
    if conLayout then
        RD.ConsoleLayout = function(...)
            local r = conLayout(...)
            if r then MB.Layout(false) end
            return r
        end
    end
end
wrap()

local ev = CreateFrame("Frame")
MB.events = ev
ev:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_HEAL_PREDICTION" or not radarOn() or secret(unit) then return end
    for _, sp in ipairs((NS.RD and NS.RD.spokes) or {}) do
        if sp.unit == unit and sp.mini and sp.mini.box:IsShown() then MB.Paint(sp) end
    end
end)
