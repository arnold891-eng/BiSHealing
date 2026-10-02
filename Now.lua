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

local BTN_W, BTN_H, GAP = 34, 34, 3

--- HOW BRIGHT THE HALO BREATHES. Arn, on the first attempt: "it just looks like a dimmed version
--- overlayed" - which is what the same art at low alpha IS. Brighter, and spilling further past the
--- edge so it reads as light coming off the button rather than a second copy of it.
---
--- `dead` must stay entirely below `alive`: a corpse beacon and a dying player have to be
--- unmistakable at a glance, and the suite asserts the two ranges never overlap rather than
--- checking numbers it would have to be taught again every time these are tuned.
FN.PULSE = {
    alive = { lo = 0.55, hi = 1.00, speed = 4 },
    dead  = { lo = 0.10, hi = 0.34, speed = 2 },
}

local function pulse(p)
    local t = (GetTime and GetTime()) or 0
    return p.lo + (p.hi - p.lo) * (0.5 + 0.5 * math.sin(t * p.speed))
end

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

--- THE GLOW, and the trick that makes it legal (EllesmereUI 9.3.4, measured 1 Oct 2026).
---
--- A pulse is movement, and movement is what the eye actually catches - Arn: "need a glowing effect
--- or flashing to bring attention". But we may not ask whether you are low, so we cannot start or
--- stop a pulse. We do not have to: the pulse runs ALWAYS, and the client decides whether it is
--- visible, by handing back a colour.
---
--- The glow texture is drawn with an ADD blend, where BLACK contributes nothing at all. So above
--- the threshold the curve returns black and the pulse is invisible however bright it gets; below
--- it the curve returns red and the same unchanged pulse becomes a flashing red halo. Alpha stays
--- 1 at every point, because their note says curve alpha interpolation is not to be relied on -
--- the colour does all the work.
local glowCurve
function FN.GlowCurve()
    if glowCurve then return glowCurve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c or not c.AddPoint then return nil end
    if c.SetType and Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear then
        pcall(c.SetType, c, Enum.LuaCurveType.Linear)
    end
    pcall(c.AddPoint, c, 0.00, CreateColor(1, 0.10, 0.10, 1))   -- glowing red
    pcall(c.AddPoint, c, 0.40, CreateColor(1, 0.10, 0.10, 1))
    pcall(c.AddPoint, c, 0.4001, CreateColor(0, 0, 0, 1))       -- black: nothing, under ADD
    pcall(c.AddPoint, c, 1.00, CreateColor(0, 0, 0, 1))
    glowCurve = c
    return c
end

--- Paint the help button from the client's own answer about health. Nothing is read: the curve
--- goes in, a colour comes out, and the colour goes onto the texture.
---
--- The pulse is OURS and runs always - a sine on the clock, nothing to do with your health. What
--- the client decides is whether it can be seen: black under an ADD blend is nothing at all, so
--- above the threshold the same pulse is simply invisible. That is the only way to have a flashing
--- warning on a client that will not tell us when to flash.
function FN.PaintHelp(b)
    b = b or (FN.buttons and FN.buttons.help)
    if not (b and b.art) then return nil end

    -- DEAD IS NOT HURT, BUT IT IS NOT NOTHING EITHER. This blanked the glow at first, on the
    -- grounds that a corpse flashing for help is noise about something the raid can already see.
    -- Arn, who has actually been the corpse: "when dead it can glow but not as bright so if a
    -- combat res is looking for you i can click it and they can find me easier". He is right - it
    -- stops being a cry for healing and becomes a beacon, and the button still pings when clicked.
    --
    -- So: dimmer and slower than the living pulse, which keeps the two unmistakable at a glance.
    -- The only branch in this file that reads anything; UnitIsDeadOrGhost is a clean boolean for
    -- group units on this client, and it is guarded regardless.
    local dead = UnitIsDeadOrGhost and NS.Plain(UnitIsDeadOrGhost("player")) == true
    if dead then
        b.art:SetVertexColor(0.85, 0.15, 0.15, 0.90)
        if b.glow then
            b.glow:SetVertexColor(0.80, 0.10, 0.10, 1)
            b.glow:SetAlpha(pulse(FN.PULSE.dead))
        end
        FN.seen = "dead - a dimmer beacon"
        return true
    end

    local curve = FN.HelpCurve()
    if not (curve and UnitHealthPercent) then
        b.art:SetVertexColor(1, 0.3, 0.3, 0.35)      -- no curves here: a constant, honest dim
        if b.glow then b.glow:SetVertexColor(0, 0, 0, 1) end
        FN.seen = "no curve"
        return false
    end
    local ok, col = pcall(UnitHealthPercent, "player", true, curve)
    if not ok or not col or not col.GetRGBA then
        b.art:SetVertexColor(1, 0.3, 0.3, 0.35)
        if b.glow then b.glow:SetVertexColor(0, 0, 0, 1) end
        FN.seen = ok and "no colour back" or "refused"
        return false
    end
    local drew = pcall(function() b.art:SetVertexColor(col:GetRGBA()) end)

    -- the halo: its colour from the client, its brightness from the clock
    if b.glow then
        local g = FN.GlowCurve()
        local painted = false
        if g then
            local okG, gc = pcall(UnitHealthPercent, "player", true, g)
            if okG and gc and gc.GetRGBA then
                painted = pcall(function() b.glow:SetVertexColor(gc:GetRGBA()) end)
            end
        end
        if not painted then b.glow:SetVertexColor(0, 0, 0, 1) end
        b.glow:SetAlpha(pulse(FN.PULSE.alive))
    end

    FN.seen = drew and "painted by the client" or "colour refused"
    return drew
end

--- One button. A SECURE UNIT BUTTON pointed at you, so that hovering it makes you the mouseover -
--- which is what `/ping [@mouseover] assist` then aims at. Built out of combat, never rewritten.
local function makeButton(parent, key)
    local b = CreateFrame("Button", "BiSHealingNow" .. key, parent, "SecureUnitButtonTemplate")
    b:SetSize(BTN_W, BTN_H)
    b.art = b:CreateTexture(nil, "ARTWORK")
    b.art:SetAllPoints()
    -- ADD blend, and bigger than the button so it reads as a halo rather than a tint. Black under
    -- ADD contributes nothing, which is what keeps it invisible while you are well.
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -11, 11)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 11, -11)
    if b.glow.SetBlendMode then b.glow:SetBlendMode("ADD") end
    b.glow:SetVertexColor(0, 0, 0, 1)
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
        local drew = false
        if atlas and b.art.SetAtlas then drew = pcall(b.art.SetAtlas, b.art, atlas) end
        -- THE HALO IS THE SAME SHAPE, BIGGER. A texture with nothing in it draws nothing, and
        -- picking a soft-glow atlas by name is the guessing that cost five misses this evening -
        -- so the glow reuses art we have already proved exists. Under ADD it reads as the flag
        -- itself catching light rather than a square behind it.
        if drew and b.glow.SetAtlas then
            if not pcall(b.glow.SetAtlas, b.glow, atlas) then b.glow:SetTexture(WHITE8X8 or nil) end
        elseif b.glow.SetColorTexture then
            b.glow:SetColorTexture(1, 1, 1, 1)
        end
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
        a:SetSize(BTN_W, BTN_H)
        FN.block, FN.buttons = a, {}
        if FG.CellHeader then FG.CellHeader(a, "now", a, FN.NOW_KEYS) end
    end
    local a = FN.block
    a:Show()
    if a.handle then a.handle:Show() end
    for i, key in ipairs(mine) do
        local b = FN.buttons[key] or makeButton(a, key)
        FN.buttons[key] = b
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", a, "TOPLEFT", (i - 1) * (BTN_W + GAP), 0)
        b:Show()
    end
    for key, b in pairs(FN.buttons) do
        local still = false
        for _, k in ipairs(mine) do if k == key then still = true end end
        if not still then b:Hide() end
    end
    a:SetSize(#mine * BTN_W + (#mine - 1) * GAP, BTN_H)
    FN.PlaceBlock(a, anchor)
    FN.PaintHelp()
    return true, #mine
end
