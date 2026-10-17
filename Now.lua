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
    -- WEAPON OIL (11 Oct 2026). Arn: "okay got the mana oil how do i bring it up in bis now, does it
    -- scan my bags for oils?" - after a macro he saw (/use the stone, /use 16). Not earned by a
    -- fight: it is there while an oil is in your bags (FN.Oil), bright while the main hand has none.
    { id = 4, key = "oil", word = "Oil", ready = true, always = true, oil = true },
    -- YOUR SHIELD, LIVE, AND ONE CLICK TO PUT IT BACK (12 Oct 2026). Arn, after the badge worked on
    -- the grid header: "what do you think we send it to bis now header too crowded". The face is
    -- SelfBuff's badge - red with the initials, covered by the client's own icon while the buff is
    -- on you, even mid-fight - and the click casts it. Whatever /bish buff watches: Water Shield
    -- for a shaman, Inner Fire for a priest. Always there, like help: a button that is already in
    -- its place is one you can hit without looking for it.
    { id = 5, key = "shield", word = "Shield", ready = true, always = true, selfbuff = true },
    -- MY TANK (14 Oct 2026). Arn: "when im clicking on a friendly target and i click the button it
    -- becomes my personal tank ... puts a teal small sabers so i know where they are going and i dont
    -- lose them in bgs and if i click on it it targets them". Always there, like the shield.
    { id = 6, key = "tank", word = "Tank", ready = true, always = true, tank = true },
}

--- THE OILS, best first for a healer: mana oils (mana back AND healing), then wizard oils.
FN.OILS = {
    { id = 20748, word = "Brilliant Mana Oil" },
    { id = 20747, word = "Lesser Mana Oil" },
    { id = 20745, word = "Minor Mana Oil" },
    { id = 20749, word = "Brilliant Wizard Oil" },
    { id = 20750, word = "Wizard Oil" },
    { id = 20746, word = "Lesser Wizard Oil" },
    { id = 20744, word = "Minor Wizard Oil" },
}

--- The best oil in your bags, or nil. One count per oil kind (seven calls, never a bag walk), and
--- asked only when the bags change (FN.OilWatch) or the block is laid out.
function FN.Oil()
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not count then return nil end
    for _, o in ipairs(FN.OILS) do
        local ok, n = pcall(count, o.id)
        if ok and not (NS.Secret and NS.Secret(n)) and type(n) == "number" and n > 0 then return o end
    end
    return nil
end

--- Is the main hand already oiled? true / false, or nil when the client will not say.
function FN.Oiled()
    if not GetWeaponEnchantInfo then return nil end
    local ok, has = pcall(GetWeaponEnchantInfo)
    if not ok or (NS.Secret and NS.Secret(has)) then return nil end
    if has == true or has == 1 then return true end
    if has == false or has == nil or has == 0 then return false end
    return nil
end

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
           and (not b.needs or (NS.FB and NS.FB.Knows and NS.FB.Knows(b.needs)))
           and (not b.oil or FN.Oil())                     -- the oil button needs an oil in your bags
           and (not b.selfbuff or FN.ShieldReady())        -- and the shield, a buff and containers
           and (not b.tank or (FN.TankReady() and not FN.InDungeon())) then -- the tank: not off, not in a dungeon
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
    -- a colour is a table; anything else (a plain number) is "no colour back", never indexed
    if not ok or type(col) ~= "table" or not col.GetRGBA then
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

--- Point the oil button at the best oil in your bags: the macro Arn saw, without the stone -
--- `/use item:<id>` picks the oil up, `/use 16` puts it on the main hand. OUT OF COMBAT, like every
--- secure write; the icon follows the oil. Returns the oil it armed, or nil.
function FN.ArmOil(b)
    b = b or (FN.buttons and FN.buttons.oil)
    if not b or (InCombatLockdown and InCombatLockdown()) then return nil end
    local o = FN.Oil()
    b.oilItem = o
    if b.SetAttribute then
        b:SetAttribute("*type1", o and "macro" or nil)
        b:SetAttribute("*macrotext1", o and ("/use item:" .. o.id .. "\n/use 16") or nil)
    end
    local iconOf = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    if o and iconOf and b.art and b.art.SetTexture then
        local okI, icon = pcall(iconOf, o.id)
        if okI and icon then pcall(b.art.SetTexture, b.art, icon) end
    end
    return o
end

--- WHAT THE OIL DOES, on a hover (11 Oct 2026). Arn: "maybe a small tooltip so we can see what oil it
--- is maybe not the name but the buff". The game's OWN item tooltip, never numbers typed here - his
--- screenshot showed why: on Forever Minor Mana Oil is "5 mana every 5 seconds ... healing by up to
--- 10 ... 30 minutes", not the classic figures anyone would have remembered. Under it: whether it is
--- on your main hand and for how long, and how many are left in your bags.
--- THE EFFECT, SHORT (11 Oct 2026). Arn, on the full item tooltip: "lets concise dont need to repeat
--- while applied to target weapon it" - just the numbers. Read out of the game's own description
--- (so Forever's values, never ours): "+5 mana / 5 sec · +10 healing · 30 min". nil when the text
--- does not read as an oil (another language, or not loaded yet) - the caller says the name then.
function FN.OilEffect(text)
    if type(text) ~= "string" or text == "" or (NS.Secret and NS.Secret(text)) then return nil end
    local t = text:lower()
    local parts = {}
    local mana, every = t:match("restores (%d+) mana"), t:match("every (%d+) sec")
    if mana then parts[#parts + 1] = "+" .. mana .. " mana / " .. (every or "5") .. " sec" end
    local both = t:match("spell damage and healing[^%d]-(%d+)")
    local heal = not both and t:match("healing[^%d]-(%d+)")
    if both then parts[#parts + 1] = "+" .. both .. " spell damage & healing"
    elseif heal then parts[#parts + 1] = "+" .. heal .. " healing" end
    local crit = t:match("critical strike chance[^%d]-(%d+)%%")
    if crit then parts[#parts + 1] = "+" .. crit .. "% spell crit" end
    local mins = t:match("lasts? for (%d+) min")
    if mins then parts[#parts + 1] = mins .. " min" end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

--- The oil's own description, from its use-spell. nil until the client has it (it can load late).
function FN.OilText(id)
    if not (C_Item and C_Item.GetItemSpell and C_Spell and C_Spell.GetSpellDescription) then return nil end
    local ok, _, spellID = pcall(C_Item.GetItemSpell, id)
    if not ok or type(spellID) ~= "number" then return nil end
    local okD, text = pcall(C_Spell.GetSpellDescription, spellID)
    return okD and text or nil
end

function FN.OilTip(b)
    if not (GameTooltip and b) then return false end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    local o = b.oilItem
    if o then
        GameTooltip:AddLine(FN.OilEffect(FN.OilText(o.id)) or o.word, 0.31, 0.82, 0.81)
    end
    local ok, has, msLeft = false, nil, nil
    if GetWeaponEnchantInfo then ok, has, msLeft = pcall(GetWeaponEnchantInfo) end
    if ok and not (NS.Secret and NS.Secret(has)) and (has == true or has == 1) then
        local mins = (not (NS.Secret and NS.Secret(msLeft)) and type(msLeft) == "number")
            and math.floor(msLeft / 60000 + 0.5) or nil
        GameTooltip:AddLine(mins and ("on your main hand: " .. mins .. " min left") or "on your main hand",
                            0.31, 0.82, 0.81)
    else
        GameTooltip:AddLine("not on your weapon - click to apply", 1, 0.82, 0.2)
    end
    local count = (C_Item and C_Item.GetItemCount) or GetItemCount
    if o and count then
        local okC, n = pcall(count, o.id)
        if okC and not (NS.Secret and NS.Secret(n)) and type(n) == "number" then
            GameTooltip:AddLine(n .. " left in your bags", 0.6, 0.6, 0.65)
        end
    end
    GameTooltip:Show()
    return true
end

--- Bright while the main hand has no oil; dim when it has one, or when the client will not say.
function FN.PaintOil(b)
    b = b or (FN.buttons and FN.buttons.oil)
    if not (b and b.art) then return nil end
    local want = FN.Oiled() == false
    b.art:SetVertexColor(1, 1, 1, want and 1 or 0.35)
    if b.art.SetDesaturated then b.art:SetDesaturated(not want) end
    return want
end

--- BAGS CHANGED: lay the block out again only if "an oil, and which" changed - a loot storm costs
--- seven counts per burst, and a relayout only when the answer moved.
function FN.OilWatch()
    if FN.oilFrame then return end
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
    pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        local o = FN.Oil()
        local now = o and o.id or 0
        if now ~= FN.oilSeen then
            FN.oilSeen = now
            if not (InCombatLockdown and InCombatLockdown()) then FN.Layout() end
        end
    end)
    FN.oilFrame = f
end

--- May this character have the shield button? A watched self buff it has trained, and a client that
--- draws auras for addons - without the containers the face would be red for ever, which is a lie.
function FN.ShieldReady()
    local FS, FA = NS.FS, NS.FA
    if not (FS and FS.Target and FS.Target()) then return false end
    return (FA and FA.Available and FA.Available()) and true or false
end

--- Take the shield button's face down (it is hidden, or what it stood for changed).
function FN.DropShield(b)
    b = b or (FN.buttons and FN.buttons.shield)
    if not b then return end
    if b.badge and NS.FS and NS.FS.DropBadge then NS.FS.DropBadge(b.badge) end
    b.badge, b.shieldSig = nil, nil
end

--- Point the shield button at your watched buff: the click casts it, the badge is its face. OUT OF
--- COMBAT, like every secure write, and only when the buff or its ranks changed - a relayout for
--- an oil must not rebuild a container. Answers the buff's name, or nil.
function FN.ArmShield(b)
    b = b or (FN.buttons and FN.buttons.shield)
    if not b or (InCombatLockdown and InCombatLockdown()) then return nil end
    local FS = NS.FS
    local name, ids
    if FS and FS.Target then name, ids = FS.Target() end
    if not name then FN.DropShield(b) return nil end
    local sig = FS.TargetSig()
    if b.badge and b.shieldSig == sig then return name end
    FN.DropShield(b)
    if b.SetAttribute then
        b:SetAttribute("*type1", "macro")
        b:SetAttribute("*macrotext1", "/cast " .. name)
    end
    b.shieldName = name
    local _, h = dims()
    b.badge = FS.MakeBadge(b, name, ids, h - 8)
    b.shieldSig = b.badge and sig or nil
    if b.badge then
        -- the static picture would say "up" for ever; the badge's red and the client's icon are the face
        if b.art and b.art.Hide then b.art:Hide() end
    else
        -- THE CLIENT REFUSED THE BADGE (14 Oct 2026, Arn in a battleground: "water shield not
        -- showing up" - "aura markers are off: this client will not let them be placed"). The
        -- picture used to be hidden BEFORE asking, so a refusal left an empty, invisible button
        -- that still cast. Now: the spell's own icon, dimmed - a button you can see and click,
        -- which cannot say whether the buff is up, and does not pretend to.
        local okT, icon = pcall(function()
            return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(name)
        end)
        if b.art then
            if okT and icon and b.art.SetTexture then pcall(b.art.SetTexture, b.art, icon) end
            if b.art.SetVertexColor then b.art:SetVertexColor(1, 1, 1, 0.6) end
            if b.art.Show then b.art:Show() end
        end
    end
    return name
end

--- What the shield button does, on a hover: the one bar keeps no words, the tooltip has room.
function FN.ShieldTip(b)
    if not (GameTooltip and b) then return false end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.shieldName or "your buff", 0.31, 0.82, 0.81)
    GameTooltip:AddLine("click to cast it", 0.73, 0.50, 1.00)
    GameTooltip:AddLine("red: it is not on you - the game shows this, even in a fight", 0.59, 0.56, 0.68)
    GameTooltip:Show()
    return true
end

--[[---------------------------------------------------------------------------
  MY TANK. One friendly player you choose; the button targets them, and a small teal X
  stands on them (under their nameplate) so you do not lose them in a battleground.

  LEFT-CLICK targets them: a secure macro, `/target Name`, which reaches a player the
  client knows even out of sight. RIGHT-CLICK makes your current friendly target your
  tank (on yourself, or nobody, it lets go). With no tank yet, a left-click chooses too.

  The macro is a secure attribute: written OUT OF COMBAT ONLY. Chosen mid-fight, the X
  and the tooltip follow at once; the click's target follows when the fight ends.
-----------------------------------------------------------------------------]]
FN.TEAL = { 0.20, 0.90, 0.82 }
FN.TANK_ICON = "Interface\\Icons\\Ability_Defend"

--- The button is there unless switched off (db.tankButton = false).
--- A 5-man dungeon (Arn, 14 Oct: "in dungeon get rid of tank button"): the mark cannot show in there
--- and five players need no finding, so the button leaves the block. Raids and battlegrounds keep it.
--- Asked at every layout, and the grid lays out again on PLAYER_ENTERING_WORLD - i.e. at every zone-in.
function FN.InDungeon()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or NS.Secret and (NS.Secret(inside) or NS.Secret(kind)) then return false end
    return inside == true and kind == "party"
end

function FN.TankReady()
    local d = NS.DB and NS.DB()
    return not (type(d) == "table" and d.tankButton == false)
end

--- The tank's name, or nil. Kept in the db (mirrored per character, see Core's MIRROR).
function FN.Tank()
    local d = NS.DB and NS.DB()
    local t = type(d) == "table" and d.tank or nil
    return type(t) == "string" and t ~= "" and t or nil
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    -- NEVER `Plain(v) or v`: Plain answers nil for a secret, and the `or` handed the secret back
    -- (14 Oct, Arn's BugGrabber: "attempt to compare local 'n' (a secret string value)" - a
    -- nameplate's name, hidden in a battleground)
    if NS.Plain then return NS.Plain(v) end
    return v
end

--- A unit's name the way /target wants it (with the realm when it is not ours), or nil.
local function nameOf(unit)
    local n = ask(GetUnitName, unit, true)
    if type(n) ~= "string" or n == "" then n = ask(UnitName, unit) end
    if type(n) ~= "string" or n == "" or n == (UNKNOWNOBJECT or "Unknown") then return nil end
    return n
end
FN.NameOf = nameOf

--- Is this name the tank? Whole, or a plate's first word against the tank's (Forever's two-part
--- names: "Tobi Three" - a plate may say only "Tobi"), realm left off either side.
function FN.IsTank(name)
    local t = FN.Tank()
    if not (t and type(name) == "string") then return false end
    local function bare(s) return (s:match("^([^%-]+)") or s) end
    local a, b = bare(t), bare(name)
    if a == b then return true end
    return (not b:find(" ", 1, true)) and a:match("^(%S+)") == b
end

--- Your target becomes your tank: a friendly player, not you. Anything else lets go.
function FN.SetTank()
    local d = NS.DB and NS.DB()
    if type(d) ~= "table" then return nil end
    local friend = ask(UnitExists, "target") == true and ask(UnitIsPlayer, "target") == true
        and ask(UnitIsFriend, "player", "target") == true and ask(UnitIsUnit, "player", "target") ~= true
    local name = friend and nameOf("target") or nil
    if name and FN.IsTank(name) then name = nil end              -- them again: let go
    d.tank = name
    if name then
        NS.Print("%s is your tank - left-click the button to target them", name)
        if FN.MarkLocked() then NS.Print("  (the teal mark won't show in here: %s)", FN.LOCKED_WHY) end
    else
        NS.Print("no tank now (right-click the button with a friendly player targeted to choose one)")
    end
    FN.ApplyTank()
    FN.MarkTankPlates()
    if NS.Announce then NS.Announce("BiSHealing_TankChanged", name) end   -- API.lua
    return name
end

--- The secure half: out of combat only; mid-fight, when it ends.
function FN.ApplyTank(b)
    b = b or (FN.buttons and FN.buttons.tank)
    if not b or not b.SetAttribute then return false end
    if InCombatLockdown and InCombatLockdown() then FN.tankDirty = true return false end
    FN.tankDirty = nil
    local t = FN.Tank()
    b:SetAttribute("*macrotext1", t and ("/target " .. t) or "")
    FN.PaintTank(b)
    return true
end

--- Dim with nobody chosen, full with a tank, and a teal edge so it reads as the X's button.
function FN.PaintTank(b)
    if not b then return end
    b:SetAlpha(FN.Tank() and 1 or 0.45)
end

function FN.ArmTank(b)
    if b.SetAttribute then
        b:SetAttribute("*type1", "macro")
        b:SetAttribute("*type2", nil)            -- right-click: ours alone (FN.SetTank), nothing secure
    end
    if b.art and b.art.SetTexture then pcall(b.art.SetTexture, b.art, FN.TANK_ICON) end
    if b.HookScript and not b.tankHooked then
        b.tankHooked = true
        b:HookScript("OnClick", function(_, button)
            if button == "RightButton" or not FN.Tank() then FN.SetTank() end
        end)
        b:HookScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local t = FN.Tank()
            GameTooltip:AddLine(t and ("Your tank: " .. t) or "Your tank: nobody yet")
            GameTooltip:AddLine("Left-click: target them. Right-click: make your friendly target your tank (again on them: let go). A small teal X stands on them.", 1, 1, 1, true)
            GameTooltip:AddLine("The mark shows in the open world and battlegrounds - not inside dungeons or raids, where the game keeps friendly nameplates from addons.", 0.6, 0.6, 0.6, true)
            if FN.tankDirty then GameTooltip:AddLine("The click targets them once this fight ends.", 1, 0.6, 0.2, true) end
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    FN.TankWatch()
    FN.ApplyTank(b)
end

--- THE X: two slim teal blades, crossed, under the tank's nameplate.
FN.TANK_W, FN.TANK_H = 30, 35
-- how far under the plate: ON them, the chest, not just under the name (Arn, 14 Oct, the X
-- floating under "Kai Tu": "def want this on them so lower")
FN.TANK_DROP = 42

--- The X's size (% of TANK_W x TANK_H) and lift (px up from TANK_DROP): the options' steppers
--- (Arn, 14 Oct: "add the steppers to the tank x too" - the same two as BiS Tools' bg marks).
function FN.TankSize(d)
    d = d or (NS.DB and NS.DB())
    local v = type(d) == "table" and tonumber(d.tankSize) or nil
    return v and math.max(50, math.min(200, v)) or 100
end
function FN.TankLift(d)
    d = d or (NS.DB and NS.DB())
    local v = type(d) == "table" and tonumber(d.tankLift) or nil
    return v and math.max(-40, math.min(40, v)) or 0
end
FN.tankMarks, FN.tankPool = {}, {}

--- THE LOOKS (Arn, 14 Oct: "i also wanted different disigns not all want x"). Each a set of
--- glowing strokes in a box from -1 to 1 each way, scaled to the size stepper. The same five, in
--- the same order, as BiS Tools' bg marks (Battleground.lua B.LOOKS).
FN.LOOKS = {
    { key = "x", word = "X", strokes = { { -1, -1, 1, 1 }, { 1, -1, -1, 1 } } },
    { key = "saber", word = "saber", strokes = { { 0, -1, 0, 1 } } },
    { key = "arrow", word = "arrow", strokes = { { -1, 1, 0, -0.3 }, { 1, 1, 0, -0.3 } } },
    { key = "diamond", word = "diamond", strokes = { { 0, 1, 1, 0 }, { 1, 0, 0, -1 }, { 0, -1, -1, 0 }, { -1, 0, 0, 1 } } },
    { key = "corners", word = "corners", strokes = {
        { -1, 1, -0.45, 1 }, { -1, 1, -1, 0.45 }, { 1, 1, 0.45, 1 }, { 1, 1, 1, 0.45 },
        { -1, -1, -0.45, -1 }, { -1, -1, -1, -0.45 }, { 1, -1, 0.45, -1 }, { 1, -1, 1, -0.45 } } },
}

--- The chosen look's place in FN.LOOKS (the stepper's number), 1 = X.
function FN.TankLook(d)
    d = d or (NS.DB and NS.DB())
    local v = type(d) == "table" and tonumber(d.tankLook) or nil
    v = v and math.floor(v) or 1
    return (v >= 1 and v <= #FN.LOOKS) and v or 1
end

local function newX(look)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("BACKGROUND")
    f.parts = {}
    f.look = look
    if not f.CreateLine then return f end
    local c = FN.TEAL
    for _, s in ipairs(FN.LOOKS[look].strokes) do
        for _, layer in ipairs({ { 6, 0.18 }, { 3.5, 0.45 }, { 2, 1 } }) do
            local l = f:CreateLine(nil, "ARTWORK")
            l:SetTexture("Interface\\Buttons\\WHITE8X8")
            l:SetVertexColor(c[1], c[2], c[3], layer[2])
            if layer[2] < 1 and l.SetBlendMode then pcall(l.SetBlendMode, l, "ADD") end
            l:SetThickness(layer[1])
            l.stroke = s
            f.parts[#f.parts + 1] = l
        end
    end
    -- the strokes to the box, whatever its size (the size stepper)
    function f.Fit(w, h)
        local x, y = w / 2 - 2, h / 2 - 2
        for _, l in ipairs(f.parts) do
            local s = l.stroke
            l:SetStartPoint("CENTER", f, s[1] * x, s[2] * y)
            l:SetEndPoint("CENTER", f, s[3] * x, s[4] * y)
        end
    end
    f.Fit(FN.TANK_W, FN.TANK_H)
    return f
end
FN.NewTankMark = newX                     -- the options' preview draws the same mark

-- ---------------------------------------------------------------- the preview
-- Arn, 14 Oct: "bis healing needs a preview like bis tools". Hover "tank mark", "tank mark size" or
-- "tank mark height" in the options and a panel rolls out beside the window: YOU as a 3D model, a
-- nameplate over your head, wearing the tank mark exactly as FN.MarkTankPlate puts it on the tank -
-- redrawn on every step. As tall as the options window, 1.43:1 (the BiSTheme standard).
FN.PREVIEW_H, FN.PREVIEW_HEADROOM = 230, 60
FN.PREVIEW_PLATE = { 120, 8 }

local function pvTex(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

--- (Re)draw the mark in the current look, size and height.
function FN.PaintPreview()
    local pv = FN.preview
    if not (pv and pv:IsShown()) then return end
    if pv.mark then pv.mark:Hide() end
    local look = FN.TankLook()
    pv.made = pv.made or {}
    local f = pv.made[look]
    if not f then
        f = newX(look)
        f:SetParent(pv.cell)
        pv.made[look] = f
    end
    local okS, strata = pcall(pv.GetFrameStrata, pv)
    local okL, level = pcall(pv.GetFrameLevel, pv)
    if okS and strata then f:SetFrameStrata(strata) end
    if okL and type(level) == "number" then f:SetFrameLevel(level + 5) end
    local k = FN.TankSize() / 100
    f:SetSize(FN.TANK_W * k, FN.TANK_H * k)
    if f.Fit then f.Fit(FN.TANK_W * k, FN.TANK_H * k) end
    f:ClearAllPoints()
    f:SetPoint("TOP", pv.plate, "BOTTOM", 0, -FN.TANK_DROP + FN.TankLift())
    f:Show()
    pv.mark = f
end

function FN.DressPreview()
    local pv = FN.preview
    if not pv then return end
    local okN, me = pcall(UnitName, "player")
    pv.plate.name:SetText((okN and type(me) == "string" and not (NS.Secret and NS.Secret(me))) and me or "you")
    if pv.model then
        pcall(pv.model.SetUnit, pv.model, "player")
        pcall(pv.model.SetFacing, pv.model, 0.35)
        if pv.model.SetPortraitZoom then pcall(pv.model.SetPortraitZoom, pv.model, 0) end
    end
end

--- The roll-out, hung off the options window's right edge; shown while a tank mark row is hovered.
function FN.AttachPreview(opt)
    if not opt then return FN.preview end
    if FN.preview and FN.previewFor == opt then return FN.preview end   -- a rebuilt window gets its own
    FN.previewFor = opt
    local pv = CreateFrame("Frame", "BiSHealingTankPreview", opt)
    local okH, oh = pcall(opt.GetHeight, opt)
    local H = (okH and type(oh) == "number" and oh >= FN.PREVIEW_H) and math.floor(oh + 0.5) or FN.PREVIEW_H
    pv:SetSize(math.floor(H * 1.43 + 0.5), H)
    pv:SetPoint("TOPLEFT", opt, "TOPRIGHT", 4, 0)
    pvTex(pv, "BACKGROUND", { 0.05, 0.05, 0.08 }, 0.92):SetAllPoints(pv)
    local title = pv:CreateFontString(nil, "OVERLAY")
    pcall(title.SetFont, title, STANDARD_TEXT_FONT, 9, "")
    title:SetPoint("TOPLEFT", pv, "TOPLEFT", 6, -5)
    title:SetText((NS.T and NS.T.text and NS.T.text("accent", "BiS>") or "BiS>") .. " the tank mark, on you")
    local cell = CreateFrame("Frame", nil, pv)
    cell:SetPoint("TOPLEFT", pv, "TOPLEFT", 6, -18)
    cell:SetPoint("BOTTOMRIGHT", pv, "BOTTOMRIGHT", -6, 4)
    pv.cell = cell
    local okM, m = pcall(CreateFrame, "DressUpModel", nil, cell)
    if okM and m then
        m:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, -(FN.PREVIEW_HEADROOM + 4))
        m:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 14)
        pv.model = m
    end
    -- the plate stands where a nameplate stands: over the head
    local p = CreateFrame("Frame", nil, cell)
    p:SetSize(FN.PREVIEW_PLATE[1], FN.PREVIEW_PLATE[2])
    p:SetPoint("TOP", cell, "TOP", 0, -FN.PREVIEW_HEADROOM)
    pvTex(p, "BACKGROUND", { 0.10, 0.10, 0.12 }, 0.9):SetAllPoints(p)
    local fill = pvTex(p, "ARTWORK", { 0.20, 0.75, 0.25 }, 1)
    fill:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 1)
    p.name = p:CreateFontString(nil, "OVERLAY")
    pcall(p.name.SetFont, p.name, STANDARD_TEXT_FONT, 8, "")
    p.name:SetPoint("BOTTOM", p, "TOP", 0, 1)
    pv.plate = p
    local word = cell:CreateFontString(nil, "OVERLAY")
    pcall(word.SetFont, word, STANDARD_TEXT_FONT, 9, "")
    word:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
    word:SetText("your tank, as you will see them (open world and battlegrounds)")
    pv.word = word
    pv:Hide()
    FN.preview = pv
    local function hover(r)
        if r.opt and r.opt.tankPreview then
            if not pv:IsShown() then pv:Show() FN.DressPreview() end
            FN.PaintPreview()
        elseif pv:IsShown() then
            pv:Hide()
        end
    end
    for _, r in ipairs(opt.rows or {}) do
        if r.HookScript then pcall(r.HookScript, r, "OnEnter", function() hover(r) end) end
        if r.GetChildren then
            for _, c in ipairs({ r:GetChildren() }) do
                if c.HookScript then pcall(c.HookScript, c, "OnEnter", function() hover(r) end) end
            end
        end
    end
    return pv
end

local function plateOf(unit)
    local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
    if not get then return nil end
    local ok, plate = pcall(get, unit)
    if not ok or not plate then return nil end
    local okF, forbidden = pcall(function() return plate.IsForbidden and plate:IsForbidden() end)
    if not okF or forbidden then FN.tankForbidden = true return nil end
    return plate
end

--- A stepper moved: every X drawn again.
function FN.RedrawTank()
    for unit in pairs(FN.tankMarks) do FN.UnmarkTank(unit) end
    FN.MarkTankPlates()
    if FN.PaintPreview then FN.PaintPreview() end
end

function FN.UnmarkTank(unit)
    local f = FN.tankMarks[unit]
    if not f then return end
    f:Hide() f:ClearAllPoints()
    FN.tankMarks[unit] = nil
    local pool = FN.tankPool[f.look or 1] or {}
    FN.tankPool[f.look or 1] = pool
    pool[#pool + 1] = f
end

--- One plate: the X on it when it is the tank, off it when not.
function FN.MarkTankPlate(unit)
    if type(unit) ~= "string" then return end
    local is = FN.Tank() and FN.IsTank(nameOf(unit)) and ask(UnitIsFriend, "player", unit) == true
    if not is then return FN.UnmarkTank(unit) end
    if FN.tankMarks[unit] then return end
    local plate = plateOf(unit)
    if not plate then return end
    local look = FN.TankLook()
    local f = table.remove(FN.tankPool[look] or {}) or newX(look)
    local k = FN.TankSize() / 100
    f:SetSize(FN.TANK_W * k, FN.TANK_H * k)
    if f.Fit then f.Fit(FN.TANK_W * k, FN.TANK_H * k) end
    f:SetPoint("TOP", plate, "BOTTOM", 0, -FN.TANK_DROP + FN.TankLift())
    f:Show()
    FN.tankMarks[unit] = f
end

FN.tankPlates = {}

-- INSIDE A DUNGEON OR RAID THE MARK CANNOT SHOW (Arn's cousin, 14 Oct, Ragefire: friendly plates on
-- and visible, the tank targeted, and C_NamePlate.GetNamePlateForUnit("target") answered nil - the
-- game draws friendly plates there itself and hands addons none). Yet in a BATTLEGROUND it works
-- (Arn, 14 Oct: "weirdly yes inside battlegrounds"). So it is said plainly, in the tooltip, when a
-- tank is chosen in there, in /bish tank and in the options - not guessed at by the player.
FN.LOCKED_WHY = "inside dungeons and raids the game keeps friendly nameplates from addons (battlegrounds and the open world are fine)"
function FN.MarkLocked()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or NS.Secret and (NS.Secret(inside) or NS.Secret(kind)) then return false end
    return inside == true and (kind == "party" or kind == "raid" or kind == "scenario")
end

--- The plates ALREADY on screen (Arn's cousin, 14 Oct: "target the tank right click the shield and
--- no crosshairs"): the list grew only from NAME_PLATE_UNIT_ADDED, so a plate showing before the tank
--- was chosen - or one whose event the client skipped, after a reload - was never in it, and the X
--- waited for that plate to leave and come back. Asked whenever the marks are redrawn.
function FN.SeedTankPlates()
    local all = C_NamePlate and C_NamePlate.GetNamePlates
    if not all then return end
    local ok, list = pcall(all)
    if not ok or type(list) ~= "table" then return end
    for _, p in ipairs(list) do
        local okU, u = pcall(function() return p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit) end)
        if okU and type(u) == "string" and not (NS.Secret and NS.Secret(u)) then FN.tankPlates[u] = true end
    end
end

function FN.MarkTankPlates()
    if FN.Tank() then FN.SeedTankPlates() end
    for unit in pairs(FN.tankPlates) do FN.MarkTankPlate(unit) end
    -- and the tank's cell in the grid (it shows inside dungeons, where the plate cannot)
    if NS.FG and NS.FG.PaintTanks then NS.FG.PaintTanks() end
end

--- Plates come and go; the macro waits for the fight to end. Events only, and with no tank chosen
--- a plate costs one table lookup.
function FN.TankWatch()
    if FN.tankFrame then return end
    local f = CreateFrame("Frame")
    FN.tankFrame = f
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "NAME_PLATE_UNIT_ADDED" then
            if type(unit) == "string" and not (NS.Secret and NS.Secret(unit)) then
                FN.tankPlates[unit] = true
                if FN.Tank() then FN.MarkTankPlate(unit) end
            end
        elseif event == "NAME_PLATE_UNIT_REMOVED" then
            if type(unit) == "string" and not (NS.Secret and NS.Secret(unit)) then
                FN.tankPlates[unit] = nil
                FN.UnmarkTank(unit)
            end
        elseif event == "PLAYER_REGEN_ENABLED" and FN.tankDirty then
            FN.ApplyTank()
        end
    end)
end

--- /bish tank: who, whether the click is written, and whether their plate can carry the X.
function FN.TankWhy()
    local t = FN.Tank()
    NS.Print("tank: %s", t or "nobody (right-click the Tank button in BiS> now with a friendly player targeted)")
    if not t then return end
    local b = FN.buttons and FN.buttons.tank
    NS.Print("  the click: %s", not b and "no Tank button (is BiS> now on? /bish now on)"
        or (FN.tankDirty and "waiting for this fight to end" or ("targets " .. t)))
    local marked = 0
    for _ in pairs(FN.tankMarks) do marked = marked + 1 end
    if FN.MarkLocked() then
        NS.Print("  the teal X: not in here - %s", FN.LOCKED_WHY)
        return
    end
    NS.Print("  the teal X: %s%s", marked > 0 and "on them now" or "not on screen (their nameplate is not shown)",
        FN.tankForbidden and " - the game kept a friendly nameplate from addons here" or "")
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
    if def and def.oil then
        FN.ArmOil(b)
        -- hooked, like the hover lift above: the secure template's own scripts stay intact
        if b.HookScript then
            b:HookScript("OnEnter", function(self) FN.OilTip(self) end)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
    end
    if def and def.selfbuff then
        FN.ArmShield(b)
        if b.HookScript then
            b:HookScript("OnEnter", function(self) FN.ShieldTip(self) end)
            b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        end
    end
    if def and def.tank then FN.ArmTank(b) end
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
            if key == "help" then FN.PaintHelp(b)
            elseif key == "oil" then FN.PaintOil(b)
            elseif key == "shield" then             -- painted by the client, never by us
            elseif key == "tank" then FN.PaintTank(b)
            else FN.PaintNeed(b, key) end
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
        FN.DropShield()                 -- nothing stands for the buff, so the header word speaks
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
    FN.OilWatch()                   -- bags changing can bring the oil button in or take it out
    for i, key in ipairs(mine) do
        local b = FN.buttons[key] or makeButton(a, key)
        FN.buttons[key] = b
        if key == "oil" then FN.ArmOil(b) end      -- the best oil may have changed since it was built
        if key == "shield" then FN.ArmShield(b) end -- a no-op unless the buff or its ranks changed
        b:ClearAllPoints()
        local w, _, pad = dims()
        b:SetPoint("TOPLEFT", a, "TOPLEFT", (i - 1) * (w + pad), 0)
        b:Show()
    end
    for key, b in pairs(FN.buttons) do
        local still = false
        for _, k in ipairs(mine) do if k == key then still = true end end
        if not still then
            b:Hide()
            if key == "shield" then FN.DropShield(b) end
        end
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
