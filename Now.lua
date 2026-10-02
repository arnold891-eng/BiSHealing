--[[
  BiS Healing :: Now.lua - "BiS> now", the window of buttons that matter right now.

  ARN'S DESIGN (1 Oct 2026), in his words: a breakaway window that starts with the help button and
  grows as we find more things worth a button. Each one is invisible until it is relevant - "alpha
  zero as you get lower in health it gets less opaque and more red at very low health" - and the
  order of them LEARNS: "if a party member is feared after combat the button moves up one space...
  if 2 combats happen and people are poison more often the poison cleanse totem moves up more
  spaces than the fear because people are getting feared more."

  THIS FILE IS THE ORDER ONLY. No frames, no textures, no secrets: it answers "which buttons, in
  what order" and nothing else. That is deliberate - the two questions that decide how the window
  LOOKS (will the client pick a brightness from secret health, can we see who is feared) are still
  being measured, and the order does not depend on either. A button fed by plain data and a button
  fed by a curve queue up the same way.

  WHY A SWAP AND NOT A SCOREBOARD. "Moves up one space" is an algorithm, not just a phrase: swap a
  button with the one above it each time its situation happens, and frequency sorts itself out -
  poison in two fights passes fear in one, with no tally to keep, no weights to tune and no way for
  one wild night to bury something for a week. It is also the only shape that can be WRITTEN DOWN
  cheaply, which matters more here than it would anywhere else (see the macro, below).

  AFTER THE FIGHT, AND THAT IS NOT A COMPROMISE. Moving a secure button is refused in combat, the
  same rule that makes the target cell queue its changes. So the only legal moment to reorder is
  PLAYER_REGEN_ENABLED - which is exactly when Arn asked for it. The client and the design agree.

  WHAT IS KEPT: the ORDER, not the counts. SavedVariables never come back on this client, so
  anything worth keeping rides in the player's own macro - and there is no room there for a tally
  per button. There does not need to be: the order IS the memory. One row, one digit per button
  (see FK, row "R"), and a hundred fights of learning survives in six characters.
]]

local ADDON, NS = ...
NS = NS or {}

local FN = {}
NS.FN = FN

--- EVERY BUTTON THAT CAN LIVE HERE, in a fixed order with fixed ids.
---
--- `id` is what gets written into the macro, so it is a promise: an id never changes meaning and a
--- retired button's id is never reused. A macro written today must still mean the same thing to a
--- version that has gained three more buttons, and the only way to keep that is to never shuffle
--- these numbers. New buttons go on the END.
---
--- `pinned` holds a button still. The help button is yours and always first: a panic button that
--- moves is a panic button you have to look for, which defeats the whole point of it.
---
--- `needs` is the spell this character must actually have trained, asked of the spellbook rather
--- than assumed - the lesson of Earth Shield and Water Shield in one evening. nil means anyone.
--- `ready` is whether the button DOES anything yet. The order engine knows about every button so
--- that a macro written today still reads tomorrow, but a button with no behaviour must never
--- appear: on 1 Oct the Tremor button turned up on Arn's shaman wearing the Assist ping's icon and
--- carrying the Assist ping's macro, because it had an entry here and nothing else. A placeholder
--- that does the wrong thing is worse than an empty window.
FN.BUTTONS = {
    { id = 1, key = "help",   word = "Help",   pinned = true, ready = true },
    { id = 2, key = "tremor", word = "Tremor", needs = "Tremor Totem" },
    { id = 3, key = "poison", word = "Poison", needs = "Poison Cleansing Totem" },
}

--- The button a key names, or nil.
function FN.Button(key)
    for _, b in ipairs(FN.BUTTONS) do if b.key == key then return b end end
    return nil
end

--- The order as a list of keys. Starts as the registry order and is learned from there.
FN.order = nil

local function defaultOrder()
    local out = {}
    for _, b in ipairs(FN.BUTTONS) do out[#out + 1] = b.key end
    return out
end

--- Every key in the current order, pinned ones first and in registry order after that.
--- Never returns the stored table: a caller that sorted it in place would rewrite the memory.
function FN.Order()
    if not FN.order then FN.order = defaultOrder() end
    local out = {}
    for _, k in ipairs(FN.order) do if FN.Button(k) then out[#out + 1] = k end end
    -- a button added by a newer version is not in the stored order yet; it joins at the end rather
    -- than being dropped, which is what happens if you trust a written-down list completely
    for _, b in ipairs(FN.BUTTONS) do
        local seen = false
        for _, k in ipairs(out) do if k == b.key then seen = true end end
        if not seen then out[#out + 1] = b.key end
    end
    return out
end

--- Where a key sits, 1-based, or nil.
function FN.Place(key)
    for i, k in ipairs(FN.Order()) do if k == key then return i end end
    return nil
end

--- THIS HAPPENED. Called while the fight is on; nothing moves until it ends.
---
--- Counted, not flagged: a fight where three people are feared says more about what you need than
--- one where it happened once, and counting here is free. What it buys is the difference between
--- "it came up" and "it kept coming up" - Settle moves a button one place per occurrence, so a bad
--- night with four fears passes a quiet week of one.
FN.noted = {}

function FN.Note(key)
    if not FN.Button(key) then return false end
    FN.noted[key] = (FN.noted[key] or 0) + 1
    return true
end

--- THE FIGHT ENDED: move what mattered. One place per occurrence, pinned buttons immovable, and
--- nothing may pass a pinned button - the help button stays first however bad the night was.
---
--- Returns true when the order actually changed, so a caller only writes the macro when there is
--- something new to write. Writing an unchanged order on every PLAYER_REGEN_ENABLED would be a
--- macro edit after every pull, which is the kind of thing that gets an addon blamed for lag.
function FN.Settle()
    local order, moved = FN.Order(), false
    for key, times in pairs(FN.noted) do
        local b = FN.Button(key)
        if b and not b.pinned then
            for _ = 1, times do
                local at
                for i, k in ipairs(order) do if k == key then at = i end end
                if not at or at <= 1 then break end
                local above = FN.Button(order[at - 1])
                if above and above.pinned then break end        -- nothing passes the help button
                order[at], order[at - 1] = order[at - 1], order[at]
                moved = true
            end
        end
    end
    FN.noted = {}
    FN.order = order
    return moved
end

--- THE ORDER AS DIGITS, for the macro. One digit per button id, in order: "132". A row carries
--- digits and nothing else, which is why the ids exist at all.
function FN.Encode()
    local out = {}
    for _, k in ipairs(FN.Order()) do
        local b = FN.Button(k)
        if b and b.id >= 1 and b.id <= 9 then out[#out + 1] = tostring(b.id) end
    end
    return table.concat(out)
end

--- And back. Unknown digits are skipped rather than guessed at, and anything the digits did not
--- mention keeps its place at the end - an older macro simply knows about fewer buttons.
function FN.Decode(digits)
    if type(digits) ~= "string" then return false end
    local out = {}
    for d in digits:gmatch("%d") do
        local n = tonumber(d)
        for _, b in ipairs(FN.BUTTONS) do
            if b.id == n then
                local seen = false
                for _, k in ipairs(out) do if k == b.key then seen = true end end
                if not seen then out[#out + 1] = b.key end
            end
        end
    end
    if #out == 0 then return false end
    FN.order = out
    return true
end

--- WHICH BUTTONS THIS CHARACTER CAN EVEN HAVE. The spellbook decides, never a class check and
--- never a version guess: a shaman who has not trained Tremor Totem has no Tremor button, and
--- nobody else has one at all. `help` is for everyone, because everyone can be in trouble.
function FN.Mine()
    local out = {}
    for _, k in ipairs(FN.Order()) do
        local b = FN.Button(k)
        if b and b.ready and (not b.needs or (NS.FB and NS.FB.Knows and NS.FB.Knows(b.needs))) then
            out[#out + 1] = k
        end
    end
    return out
end

--- Start again: the registry order, nothing noted.
function FN.Reset()
    FN.order, FN.noted = defaultOrder(), {}
end

--[[---------------------------------------------------------------------------
  THE WINDOW. A block of its own, like the target cell and the mana list: a small
  `BiS> now` bar you can drag, or shift-click to send round the grid.

  WHAT MAKES IT LEGAL. Every button here is built and bound OUT OF COMBAT and then
  never touched again - a secure button cannot be changed mid-fight, and none of
  these needs to be. The only thing that moves while you are fighting is COLOUR,
  which is not protected and which the addon does not decide: the curve goes into
  UnitHealthPercent and the client hands back the result. We never learn a number.
-----------------------------------------------------------------------------]]

-- THE SAME SIZE AS A CELL, and the same gap between them: a button here IS a cell, so the block
-- lines up with the grid on every side instead of sitting near it. Taken from Grid rather than
-- written down again (1 Oct 2026).
local function dims()
    local FG = NS.FG
    return (FG and FG.CELL_W) or 84, (FG and FG.CELL_H) or 34, (FG and FG.CELL_PAD) or 3
end

--- THE BLOCK'S OWN COLOURS. Arn, on the halo that replaced the plain colour change: "the glow is
--- too confusing it just looks like i have an astigmatism." He is right - a soft additive glow on a
--- 34-pixel icon has no shape, it just smears. A BORDER has a shape, so the border does the work
--- instead: crisp, unmistakable, and it pops without blurring anything.
FN.EDGE_WELL = { 0.45, 0.42, 0.52, 0.90 }   -- the ordinary outline, replaced by BiSTheme's accent
FN.EDGE_DEAD = { 0.55, 0.14, 0.14, 0.95 }   -- a corpse: red, and plainly duller than the living

FN.NOW_KEYS = { what = "the now block", at = "nowAt", pos = "nowPos",
                spot = function() return FN.Spot() end,
                place = function(f) return FN.PlaceBlock(f) end }

function FN.Spot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.nowAt or nil
    local FG = NS.FG
    return (FG and FG.TARGET_SPOTS and FG.TARGET_SPOTS[at or ""]) and at or "under"
end

function FN.PlaceBlock(f, anchor)
    local FG = NS.FG
    f = f or FN.block
    anchor = anchor or (FG and FG.anchor)
    local d = NS.DB and NS.DB()
    if not (FG and FG.PlaceAt) then return false end
    return FG.PlaceAt(f, anchor, FN.Spot(), type(d) == "table" and d.nowPos or nil)
end

--- THE HELP BUTTON'S CURVE: invisible while you are well, red and solid when you are not.
---
--- Built once and kept, because building one per frame would be a lot of userdata for a colour.
--- The shape is EllesmereUI's, and so is the caution behind it - their note says curve ALPHA
--- interpolation is not to be relied on, so alpha moves in steps and the smooth work is left to
--- the colours. Four points: gone above the threshold, red below it, deeper red at the bottom.
local helpCurve
function FN.HelpCurve()
    if helpCurve then return helpCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    -- THRESHOLDS, SECOND ATTEMPT (1 Oct 2026). The first appeared below 50% and only looked urgent
    -- under 20%, which Arn tested and rejected in one line: "at 30% a healer is already 1 hit from
    -- dying most of the time". A warning that arrives when it is already too late is decoration.
    --
    -- So it starts at 70% - early enough to be a nudge rather than an obituary - and is fully red
    -- by 40% rather than 20%. Below that it only deepens.
    pcall(c.AddPoint, c, 0.00, CreateColor(1.00, 0.05, 0.05, 1))    -- dying
    pcall(c.AddPoint, c, 0.40, CreateColor(1.00, 0.15, 0.15, 1))    -- red, and solid, well before the end
    pcall(c.AddPoint, c, 0.55, CreateColor(1.00, 0.45, 0.15, 0.95)) -- orange
    pcall(c.AddPoint, c, 0.70, CreateColor(1.00, 0.80, 0.25, 0.80)) -- amber: the first nudge
    pcall(c.AddPoint, c, 0.7001, CreateColor(1, 1, 1, 0))           -- a step, not a fade
    pcall(c.AddPoint, c, 1.00, CreateColor(1, 1, 1, 0))             -- well: not there at all
    helpCurve = c
    return c
end

--- THE OUTLINE'S COLOUR, from the same secret the button's own colour comes from.
---
--- This was a glow: an additive halo, pulsing on a sine, invisible above the threshold because the
--- curve handed back black and black adds nothing. The trick worked exactly as designed and the
--- RESULT was wrong - on an icon that size a soft glow reads as bad eyesight, not as alarm. So the
--- same idea moved to the border, where it has edges.
---
--- Above the threshold the curve returns the ordinary outline colour rather than black, because an
--- outline that vanishes is the empty block Arn already asked to have a body.
local edgeCurve
function FN.EdgeCurve()
    if edgeCurve then return edgeCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    local w = FN.EDGE_WELL
    pcall(c.AddPoint, c, 0.00, CreateColor(1.00, 0.08, 0.08, 1))        -- dying: hot red
    pcall(c.AddPoint, c, 0.40, CreateColor(1.00, 0.18, 0.18, 1))
    pcall(c.AddPoint, c, 0.55, CreateColor(1.00, 0.50, 0.15, 1))        -- orange
    pcall(c.AddPoint, c, 0.70, CreateColor(1.00, 0.80, 0.25, 1))        -- amber
    pcall(c.AddPoint, c, 0.7001, CreateColor(w[1], w[2], w[3], w[4]))   -- a step back to ordinary
    pcall(c.AddPoint, c, 1.00, CreateColor(w[1], w[2], w[3], w[4]))
    edgeCurve = c
    return c
end

--- Paint every side of the outline one colour.
function FN.PaintEdge(r, g, b, a)
    local block = FN.block
    if not (block and block.edge) then return false end
    for _, t in pairs(block.edge) do
        if t.SetColorTexture then t:SetColorTexture(r, g, b, a or 1) end
    end
    return true
end

--- Paint the button and the outline from the client's own answer about health. Nothing is read:
--- the curve goes in, a colour comes out, and the colour goes onto a texture.
function FN.PaintHelp(b)
    b = b or (FN.buttons and FN.buttons.help)
    if not (b and b.art) then return nil end

    -- DEAD IS NOT HURT, BUT IT IS NOT NOTHING EITHER. Arn, who has been the corpse: "if a combat
    -- res is looking for you i can click it and they can find me easier." So it stays visible and
    -- stays clickable - it just stops shouting, and reads plainly duller than a dying player.
    local dead = UnitIsDeadOrGhost and NS.Plain(UnitIsDeadOrGhost("player")) == true
    if dead then
        b.art:SetVertexColor(0.85, 0.15, 0.15, 0.90)
        local e = FN.EDGE_DEAD
        FN.PaintEdge(e[1], e[2], e[3], e[4])
        FN.seen = "dead - a dimmer beacon"
        return true
    end

    local curve = FN.HelpCurve()
    if not (curve and UnitHealthPercent) then
        b.art:SetVertexColor(1, 0.3, 0.3, 0.35)      -- no curves here: a constant, honest dim
        local w = FN.EDGE_WELL
        FN.PaintEdge(w[1], w[2], w[3], w[4])
        FN.seen = "no curve"
        return false
    end
    local ok, col = pcall(UnitHealthPercent, "player", true, curve)
    if not ok or not col or not col.GetRGBA then
        b.art:SetVertexColor(1, 0.3, 0.3, 0.35)
        FN.seen = ok and "no colour back" or "refused"
        return false
    end
    local drew = pcall(function() b.art:SetVertexColor(col:GetRGBA()) end)

    -- the outline, from the same place
    local ec = FN.EdgeCurve()
    if ec then
        local okE, c2 = pcall(UnitHealthPercent, "player", true, ec)
        if okE and c2 and c2.GetRGBA then pcall(function() FN.PaintEdge(c2:GetRGBA()) end) end
    end

    FN.seen = drew and "painted by the client" or "colour refused"
    return drew
end

--- One button. A SECURE UNIT BUTTON pointed at you, so that hovering it makes you the mouseover -
--- which is what `/ping [@mouseover] assist` then aims at. Built out of combat, never rewritten.
local function makeButton(parent, key)
    local b = CreateFrame("Button", "BiSHealingNow" .. key, parent, "SecureUnitButtonTemplate")
    local w, h = dims()
    b:SetSize(w, h)
    b.art = b:CreateTexture(nil, "ARTWORK")
    -- the icon is square and the cell is not: centred at the cell's height rather than stretched
    b.art:SetSize(h - 8, h - 8)
    b.art:SetPoint("CENTER")
    b.key = key
    -- WHAT THE BUTTON DOES IS PER BUTTON. Everything here used to get the Assist ping, icon and
    -- all, which is how a Tremor button appeared wearing a ping's face (1 Oct).
    if b.SetAttribute then
        b:SetAttribute("unit", "player")
        b:RegisterForClicks("AnyUp")
    end
    if key == "help" then
        if b.SetAttribute then
            b:SetAttribute("*type1", "macro")
            b:SetAttribute("*macrotext1", "/ping [@mouseover] assist")
        end
        local atlas = NS.FM and NS.FM.PingAtlas and NS.FM.PingAtlas("assist")
        if atlas and b.art.SetAtlas then pcall(b.art.SetAtlas, b.art, atlas) end
    end
    return b
end

--- Build or refresh the block. OUT OF COMBAT ONLY, like every other secure thing here.
function FN.Layout(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    local FG = NS.FG
    anchor = anchor or (FG and FG.anchor)
    if not anchor then return false end
    local d = NS.DB and NS.DB()
    local want = type(d) == "table" and d.now == true and d.shown ~= false
    local mine = want and FN.Mine() or {}
    if #mine == 0 then
        if FN.block then FN.block:Hide() end
        return true, 0
    end
    if not FN.block then
        local a = CreateFrame("Frame", "BiSHealingNowBlock", anchor)
        a:SetSize(dims())
        FN.block, FN.buttons = a, {}
        -- A BODY, EVEN WHEN EVERY BUTTON IS INVISIBLE. Arn, with the block on the left and himself
        -- at full health: "give it its own outline even when empty". Without one there is nothing
        -- but the bar, which reads as a stray label floating over whatever is behind it - and the
        -- whole point of this block is that its contents are invisible most of the time.
        a.bg = a:CreateTexture(nil, "BACKGROUND")
        a.bg:SetAllPoints()
        a.bg:SetColorTexture(0.07, 0.07, 0.09, 0.55)
        a.edge = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local t = a:CreateTexture(nil, "BORDER")
            t:SetColorTexture(0.45, 0.42, 0.52, 0.9)
            a.edge[side] = t
        end
        local e = a.edge
        e.top:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
        e.top:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
        e.top:SetHeight(1)
        e.bottom:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0)
        e.bottom:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
        e.bottom:SetHeight(1)
        e.left:SetPoint("TOPLEFT", a, "TOPLEFT", 0, 0)
        e.left:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0)
        e.left:SetWidth(1)
        e.right:SetPoint("TOPRIGHT", a, "TOPRIGHT", 0, 0)
        e.right:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
        e.right:SetWidth(1)
        local T = _G.BiSTheme
        if T and T.rgb and a.edge.top.SetColorTexture then
            local r, g, b = T.rgb("accent")
            if r then for _, t in pairs(a.edge) do t:SetColorTexture(r, g, b, 0.55) end end
        end
        FN.buttons = {}
        if FG.CellHeader then FG.CellHeader(a, "now", a, FN.NOW_KEYS) end
    end
    local a = FN.block
    a:Show()
    if a.handle then a.handle:Show() end
    for i, key in ipairs(mine) do
        local b = FN.buttons[key] or makeButton(a, key)
        FN.buttons[key] = b
        b:ClearAllPoints()
        local w, _, pad = dims()
        b:SetPoint("TOPLEFT", a, "TOPLEFT", (i - 1) * (w + pad), 0)
        b:Show()
    end
    for key, b in pairs(FN.buttons) do
        local still = false
        for _, k in ipairs(mine) do if k == key then still = true end end
        if not still then b:Hide() end
    end
    -- sized to what is in it, in whole cells: one cell wide, two when a second button arrives,
    -- with the grid's own gap between them so it reads as part of the grid
    local w, h, pad = dims()
    a:SetSize(#mine * w + (#mine - 1) * pad, h)
    FN.PlaceBlock(a, anchor)
    FN.PaintHelp()
    return true, #mine
end
