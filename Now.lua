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
FN.BUTTONS = {
    { id = 1, key = "help",   word = "Help",   pinned = true },
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
        if b and (not b.needs or (NS.FB and NS.FB.Knows and NS.FB.Knows(b.needs))) then
            out[#out + 1] = k
        end
    end
    return out
end

--- Start again: the registry order, nothing noted.
function FN.Reset()
    FN.order, FN.noted = defaultOrder(), {}
end
