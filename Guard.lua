--[[
  BiSHealing :: Guard.lua - A CAST YOU CANNOT INTERRUPT WEARS A SHIELD (12 Nov 2026).

  Arn: "can we detect when a spell cast is protected and cant be interrupted?" - then "all three".

  The game says it: the eighth answer of UnitCastingInfo (the seventh of UnitChannelInfo) is "not interruptible". On
  Forever, in a fight, an enemy's cast is SECRET - the flag cannot be tested, only handed on. So it never goes into an
  `if`: it goes to the shield's SetAlphaFromBoolean, and the client shows or hides it (out of a fight, or for a spell the
  game marks never secret, it is a plain boolean and we set the alpha ourselves). Read off EllesmereUI's Forever nameplates
  and unit frames, which do exactly this (learn only).

  THE SHIELD: a dark plate over the interrupt (so the red triangle under it is covered) with a grey shield drawn on it,
  on the radar's bogey - and so the engineer's view, which places the same buttons - and on the PvP target cell's
  interrupt icon. A child of the face that is already lit only while a cast is on, so it shows only then. The button
  still takes a click (a secure button's mouse cannot change in a fight); the shield says the click would do nothing.
  Asked when the bogey lights (the radar's own look) and when the game says the cast changed (UNIT_SPELLCAST_INTERRUPTIBLE
  / _NOT_INTERRUPTIBLE).
]]
local ADDON, NS = ...
NS = NS or {}

local KG = {}
NS.KG = KG

KG.PLATE = { 0.05, 0.05, 0.07, 0.88 }
KG.SHIELD = { 0.72, 0.74, 0.78, 1 }      -- grey: "nothing to do here"

local function secret(v) return NS.Secret and NS.Secret(v) or false end

--- The cast `tok` is making: answers "none", or the not-interruptible flag as the client gave it (true / false / secret).
function KG.Protected(tok)
    if not tok then return "none" end
    if UnitCastingInfo then
        local ok, name, _, _, _, _, _, _, ni = pcall(UnitCastingInfo, tok)
        if ok and type(name) ~= "nil" then
            if type(ni) == "nil" then return false end
            return ni
        end
    end
    if UnitChannelInfo then
        local ok, name, _, _, _, _, _, ni = pcall(UnitChannelInfo, tok)
        if ok and type(name) ~= "nil" then
            if type(ni) == "nil" then return false end
            return ni
        end
    end
    return "none"
end

local function line(parent, x1, y1, x2, y2, w)
    local l = parent:CreateLine(nil, "OVERLAY")
    l:SetTexture("Interface\\Buttons\\WHITE8X8")
    l:SetThickness(w or 1.5)
    l:SetStartPoint("CENTER", parent, x1, y1)
    l:SetEndPoint("CENTER", parent, x2, y2)
    l:SetVertexColor(KG.SHIELD[1], KG.SHIELD[2], KG.SHIELD[3], KG.SHIELD[4])
    return l
end

--- The shield on a face (the frame lit only while a cast is on): a plate and a drawn shield, see-through to start.
function KG.Build(face, px)
    if not face then return nil end
    if face.guard then return face.guard end
    local g = CreateFrame("Frame", nil, face)
    g:SetAllPoints(face)
    local lvl = face.GetFrameLevel and face:GetFrameLevel()
    if type(lvl) == "number" and g.SetFrameLevel then g:SetFrameLevel(lvl + 5) end
    g.plate = g:CreateTexture(nil, "ARTWORK")
    g.plate:SetAllPoints(g)
    g.plate:SetColorTexture(KG.PLATE[1], KG.PLATE[2], KG.PLATE[3], KG.PLATE[4])
    -- the shield: a flat top, straight sides, then down to a point
    local s = math.max(4, (tonumber(px) or 20) * 0.28)
    g.lines = {
        line(g, -s, s, s, s),
        line(g, -s, s, -s, 0),
        line(g, s, s, s, 0),
        line(g, -s, 0, 0, -s * 1.3),
        line(g, s, 0, 0, -s * 1.3),
    }
    g:SetAlpha(0)
    face.guard = g
    return g
end

--- Show the shield on `face` when `tok`'s cast cannot be interrupted. Answers true / false / "secret" (the client's) /
--- nil (no cast).
function KG.Paint(face, tok, px)
    local g = KG.Build(face, px)
    if not g then return nil end
    local ni = KG.Protected(tok)
    if ni == "none" then g:SetAlpha(0) return nil end
    if secret(ni) then
        if not pcall(g.SetAlphaFromBoolean, g, ni, 1, 0) then g:SetAlpha(0) end
        return "secret"
    end
    g:SetAlpha(ni == true and 1 or 0)
    return ni == true
end

-- the game says a cast changed mid-way: repaint the faces that show that unit's cast
local ev = CreateFrame("Frame")
KG.events = ev
for _, e in ipairs({ "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, _, unit)
    if secret(unit) or not unit then return end
    local RD = NS.RD
    for _, sp in ipairs((RD and RD.spokes) or {}) do
        local k = sp.bogey
        if sp.tok == unit and k and k.face and k.face.guard then KG.Paint(k.face, unit) end
    end
    local FG = NS.FG
    for _, c in ipairs((FG and FG.pvpCells) or {}) do
        local tok = c.unit
        if tok == unit and c.kickFx and c.kickFx.guard then KG.Paint(c.kickFx, unit) end
    end
end)
