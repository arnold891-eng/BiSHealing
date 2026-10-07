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
    { id = 1, key = "help",   word = "Help",   pinned = true, ready = true, always = true },
    { id = 2, key = "tremor", word = "Tremor", needs = "Tremor Totem", ready = true,
      cast = "Tremor Totem", holds = "TREMOR" },
    { id = 3, key = "poison", word = "Poison", needs = "Poison Cleansing Totem" },
}

--- WHAT A TREMOR TOTEM ACTUALLY ANSWERS. Arn: "dimmed until somone in the party is feared charmed
--- or sleep" - and that list is the point. A button that lit for every root and stun would be a
--- button you learn to ignore, and the client hands back the TYPE as a plain string, so there is no
--- reason to be vague about it.
---
--- Kept as a set rather than a list because the client's exact spelling on this build is not fully
--- known: a root reads as "ROOT" (measured 1 Oct), and the rest are the retail names. Anything not
--- in here is recorded by /bish control rather than guessed at, so an unseen spelling shows up as
--- evidence instead of as a button that never lights.
FN.HOLDS = {
    TREMOR = { FEAR = true, FEAR_MECHANIC = true, CHARM = true, SLEEP = true, POSSESS = true },
}

--- WHAT THE ADDON HAS ACTUALLY SEEN A CLIENT DO (3 Oct 2026).
---
--- The hold types were already being written down and there was no way on earth to read them back,
--- so a week of play collected the one piece of evidence this addon is missing and threw it away at
--- every reload. `/bish holds` is the other half.
---
--- It records the UNIT as well as the type, because the open question is not "does loss of control
--- read" - that was answered on 1 Oct with a root on Arn - but "does it read for SOMEBODY ELSE".
--- The whole Tremor design rests on it: if other units read, the shaman alone installs the addon
--- and the person being feared installs nothing. Arn's 3 Oct run in Blackfathom Deeps got `plain
--- (0)` for his target over and over, which proves the call ANSWERS plainly for another unit in an
--- instance - but a zero is not a sighting, and no non-zero reading for another unit has ever been
--- seen.
---
--- The unit is compared as a STRING, which is ours - `unit ~= "player"`. Unit TOKENS may never be
--- compared through the client on Forever (`UnitIsUnit` is refused), and that rule is about asking
--- the client, not about our own table key.
FN.seenHolds = {}

function FN.SawHold(kind, unit)
    FN.seenHolds = FN.seenHolds or {}
    local rec = FN.seenHolds[kind]
    local fresh = not rec
    if not rec then
        rec = { n = 0, units = {}, other = false, fight = false }
        FN.seenHolds[kind] = rec
    end
    local wasOther = rec.other
    rec.n = rec.n + 1
    if type(unit) == "string" then
        rec.units[unit] = (rec.units[unit] or 0) + 1
        if unit ~= "player" then rec.other = true end
    end
    if InCombatLockdown and InCombatLockdown() then rec.fight = true end
    -- only on something NEW: the paint asks several times a second
    if fresh or (rec.other and not wasOther) then FN.KeepHold(kind, unit) end
    return rec
end

--- THE ONE BIT, KEPT (6 Oct 2026). On 5 Oct the Tremor button lit for Arn after a party fear -
--- the first sighting of a hold on SOMEBODY ELSE, the one claim the whole Tremor design rests on -
--- and the record died at the next reload, because FN.seenHolds lives for one session. So the
--- first sighting of each kind, and the first time it is read on somebody other than the player,
--- go into the saved variables, which this client hands back again (`/bish db`, 6 Oct: "saved 112
--- time(s) before"). Only first times, never counts: a count would be frames, not fears.
---
--- Overlord measured that this beta can still OMIT a saved file at login, so `/bish holds` says
--- when the record it shows started fresh this session rather than trusting it blind.
function FN.KeepHold(kind, unit)
    local db = NS.DB and NS.DB()
    if type(db) ~= "table" or type(kind) ~= "string" then return end
    db.holds = type(db.holds) == "table" and db.holds or {}
    local k = db.holds[kind]
    if type(k) ~= "table" then
        k = { firstAt = (time and time()) or 0 }
        db.holds[kind] = k
    end
    if type(unit) == "string" and unit ~= "player" and not k.otherAt then
        k.otherAt    = (time and time()) or 0
        k.otherUnit  = unit
        k.otherFight = (InCombatLockdown and InCombatLockdown()) and true or false
    end
    return k
end

--- What is holding a unit, as a plain string, or nil. Loss of control is NOT secret on this client
--- - count, type and the by-unit call all read plainly (measured 1 Oct with a root on Arn) - so
--- this is an ordinary read and an ordinary test, unlike anything health-shaped.
function FN.HoldOn(unit)
    local LC = C_LossOfControl
    if not (LC and LC.GetActiveLossOfControlDataCountByUnit and LC.GetActiveLossOfControlDataByUnit) then
        return nil, "no api"
    end
    local okN, n = pcall(LC.GetActiveLossOfControlDataCountByUnit, unit)
    n = okN and NS.Plain(n) or nil
    if type(n) ~= "number" or n < 1 then return nil, okN and "none" or "refused" end
    for i = 1, n do
        local okD, d = pcall(LC.GetActiveLossOfControlDataByUnit, unit, i)
        if okD and type(d) == "table" then
            local okT, kind = pcall(function() return d.lossOfControlType or d.locType end)
            kind = okT and NS.Plain(kind) or nil
            if type(kind) == "string" then
                FN.SawHold(kind, unit)
                return kind, nil
            end
        end
    end
    return nil, "unreadable"
end

--- Is anyone in the group held by something this button answers? Returns the unit and the type.
function FN.WhoNeeds(key)
    local want = FN.HOLDS[(FN.Button(key) or {}).holds or ""]
    if not want then return nil end
    local FG = NS.FG
    local roster = (FG and FG.Roster and FG.Roster()) or { "player" }
    for _, unit in ipairs(roster) do
        local kind = FN.HoldOn(unit)
        if kind and want[kind] then return unit, kind end
    end
    return nil
end

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
    local won = false
    for key in pairs(FN.noted) do
        if not FN.earned[key] then FN.earned[key] = true won = true end
    end
    FN.noted = {}
    FN.order = order
    return moved or won, won
end

--- THE ORDER AS DIGITS, for the macro. One digit per button id, in order: "132". A row carries
--- digits and nothing else, which is why the ids exist at all.
function FN.Encode()
    local out = {}
    -- only what has been earned, which makes this one row both the order AND the memory of which
    -- buttons this character has ever needed
    for _, k in ipairs(FN.Order()) do
        local b = FN.Button(k)
        if b and FN.Earned(k) and b.id >= 1 and b.id <= 9 then out[#out + 1] = tostring(b.id) end
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
    for _, k in ipairs(out) do FN.earned[k] = true end
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
        if b and b.ready and FN.Earned(k)
           and (not b.needs or (NS.FB and NS.FB.Knows and NS.FB.Knows(b.needs))) then
            out[#out + 1] = k
        end
    end
    return out
end

--- A BUTTON IS EARNED, NOT ISSUED (1 Oct 2026). Arn, looking at a block holding a Tremor button he
--- had never needed: "it should be smarter always the assist there, after combat if anyone get
--- feared we add the tremor button."
---
--- So capability is not enough. Knowing Tremor Totem means the button CAN exist; somebody actually
--- being feared is what makes it exist. `always` buttons skip this - the help button is there from
--- the first login, because the first time you need it is not the moment to start earning it.
---
--- Earned at the END of the fight, with the reorder, for the same reason the reorder waits: a
--- secure button cannot be built in combat anyway. The fight that teaches it is not the fight that
--- shows it.
FN.earned = {}

function FN.Earned(key)
    local b = FN.Button(key)
    if not b then return false end
    return (b.always or FN.earned[key]) and true or false
end

--- Start again: the registry order, nothing noted, nothing earned.
function FN.Reset()
    FN.order, FN.noted, FN.earned = defaultOrder(), {}, {}
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
--- A BUTTON IS SQUARE; THE BLOCK IS WHAT LINES UP (1 Oct 2026, second attempt). "Same size as the
--- cells" was read as "every button is a cell", which gave each icon 84 pixels of clickable area
--- with a 26-pixel picture adrift in it - Arn: "i click to the left and right of the tremor icon it
--- drops a tremor... almost like 3 button there all assist". Two buttons reading as three, and most
--- of the block being invisible help button.
---
--- So a button is a square the height of a cell, and the BLOCK rounds up to whole cell columns.
--- That keeps it flush with the grid on every side, which was the actual ask, without pretending an
--- icon needs the width of a name and a health number.
local function dims()
    local FG = NS.FG
    return (FG and FG.CELL_H) or 34, (FG and FG.CELL_H) or 34, (FG and FG.CELL_PAD) or 3
end

--- EXACTLY ITS BUTTONS, AND NO MORE. Rounding up to whole cell columns left a one-button block
--- with 50 pixels of nothing beside it, which is the thing Arn has now objected to twice: "the
--- window should only be 1 cell long until a tremor is drawn out of combat". His original ask was
--- plain enough and I over-read it - "showing one button or bigger if there are more".
---
--- Alignment lives in the header and the placement, not in padding the body out to a column.
--- WIDE ENOUGH FOR ITS OWN NAME. The body is exactly its buttons, but the bar above it carries
--- "BiS> now", and at one button (34px) the label ran off the end and the grid's own header drew
--- straight over it - Arn: "little cut off from last time". A block narrower than its label is a
--- block with no name.
---
--- 62 is measured off the drawn bar, not guessed: the other blocks are a cell wide (84) and sit
--- comfortably, this is the smallest that keeps "BiS> now" whole.
FN.HEADER_MIN = 62

function FN.BlockWidth(n)
    local w, _, pad = dims()
    local content = n * w + math.max(0, n - 1) * pad
    return math.max(content, FN.HEADER_MIN), content
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
    -- FAINT, NOT GONE. It was fully transparent above the threshold, which left a square you
    -- could click and could not see - Arn: "give it a faint alpha so i can see it". A panic button
    -- you cannot find when you are well is one you will not find when you are not.
    pcall(c.AddPoint, c, 0.7001, CreateColor(0.75, 0.78, 0.88, 0.22))
    pcall(c.AddPoint, c, 1.00, CreateColor(0.75, 0.78, 0.88, 0.22))
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

--- A BUTTON THAT WAITS FOR SOMEBODY ELSE'S TROUBLE. Dim until it is needed, bright when it is -
--- and this one needs no curve at all, because loss of control is plain on this client. An
--- ordinary read, an ordinary test, the way Innervate watches a party.
---
--- Noted when it fires, which is what teaches the order: a night of fears walks this button up the
--- block past one that only came up once (see FN.Note / FN.Settle).
function FN.PaintNeed(b, key)
    b = b or (FN.buttons and FN.buttons[key])
    if not (b and b.art) then return nil end
    local unit, kind = FN.WhoNeeds(key)
    if unit then
        b.art:SetVertexColor(1, 1, 1, 1)
        b.art:SetDesaturated(false)
        if b.__held ~= true then FN.Note(key) end        -- counted once per hold, not per frame
        b.__held = true
        FN.needSeen = kind .. " on " .. tostring(unit)
        return true
    end
    b.art:SetVertexColor(0.55, 0.55, 0.55, 0.35)
    if b.art.SetDesaturated then b.art:SetDesaturated(true) end
    b.__held = false
    return false
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

    -- IT SHOULD FEEL LIKE A BUTTON (5 Oct 2026). Arn: "they feel 2d id like if you hover over them
    -- it changes a little to give it a feel that its a button".
    --
    -- A SEPARATE TEXTURE, not a tint on the icon. FN.Paint rewrites b.art's vertex colour on every
    -- update - from the client's own answer about a number we may not read - so a hover tint there
    -- would be gone within a frame, and fighting it would mean the hover could lie about health.
    -- This sits above the icon and says nothing about state.
    --
    -- ADD blend so it lifts whatever is underneath: the icon may be bright, dim, greyed or painted
    -- red by a curve, and a flat white overlay would wash out three of those.
    b.hover = b:CreateTexture(nil, "HIGHLIGHT")
    b.hover:SetAllPoints(b)
    b.hover:SetColorTexture(1, 1, 1, 1)
    if b.hover.SetBlendMode then b.hover:SetBlendMode("ADD") end
    b.hover:SetAlpha(0)

    -- HOOKED, NEVER SET. SecureUnitButtonTemplate installs its own OnEnter to make you the
    -- mouseover, and that is precisely what the help button's `/ping [@mouseover] assist` aims at.
    -- Replacing the script would take the aim off the button that exists to be aimed.
    --
    -- Everything here is alpha and a texture's own anchor: both legal in combat, which is the only
    -- time this block really matters.
    if b.HookScript then
        b:HookScript("OnEnter", function(self) if self.hover then self.hover:SetAlpha(0.18) end end)
        b:HookScript("OnLeave", function(self)
            if self.hover then self.hover:SetAlpha(0) end
            if self.art then self.art:SetPoint("CENTER", 0, 0) end     -- a press left mid-drag
        end)
        b:HookScript("OnMouseDown", function(self)
            if self.art then self.art:SetPoint("CENTER", 1, -1) end    -- the icon takes the press
            if self.hover then self.hover:SetAlpha(0.30) end
        end)
        b:HookScript("OnMouseUp", function(self)
            if self.art then self.art:SetPoint("CENTER", 0, 0) end
            if self.hover then self.hover:SetAlpha(self:IsMouseOver() and 0.18 or 0) end
        end)
    end
    -- WHAT THE BUTTON DOES IS PER BUTTON. Everything here used to get the Assist ping, icon and
    -- all, which is how a Tremor button appeared wearing a ping's face (1 Oct).
    if b.SetAttribute then
        b:SetAttribute("unit", "player")
        b:RegisterForClicks("AnyUp")
    end
    local def = FN.Button(key)
    if def and def.cast then
        -- A SPELL, not a ping: written once, out of combat, like everything secure here. The
        -- spellbook already decided this button exists at all (FN.Mine), so the name is one this
        -- character has trained.
        if b.SetAttribute then
            b:SetAttribute("*type1", "macro")
            b:SetAttribute("*macrotext1", "/cast " .. def.cast)
        end
        local okT, icon = pcall(function()
            return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(def.cast)
        end)
        if okT and icon and b.art.SetTexture then pcall(b.art.SetTexture, b.art, icon) end
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

--- WATCH FOR WHAT IS NOT THERE YET. A button is earned by its situation happening - but if the
--- button does not exist, nothing was looking, and it could never be earned. That circle is why
--- this is separate from the paint: every button this character COULD have is watched, shown or
--- not, and the unshown ones are exactly the ones with something to prove.
function FN.Watch()
    for _, b in ipairs(FN.BUTTONS) do
        if b.ready and not FN.Earned(b.key) and b.holds
           and (not b.needs or (NS.FB and NS.FB.Knows and NS.FB.Knows(b.needs))) then
            local unit = FN.WhoNeeds(b.key)
            if unit then FN.Note(b.key) end
        end
    end
end

--- Paint everything the block holds. Help reads a curve; the rest read plain data.
function FN.Paint()
    FN.Watch()
    for key, b in pairs(FN.buttons or {}) do
        if b:IsShown() then
            if key == "help" then FN.PaintHelp(b) else FN.PaintNeed(b, key) end
        end
    end
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
    local width = FN.BlockWidth(#mine)
    a:SetSize(width, h)
    FN.PlaceBlock(a, anchor)
    FN.Paint()
    return true, #mine
end
