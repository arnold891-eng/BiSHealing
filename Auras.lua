--[[
  BiSHealing / Forever :: Forever/Auras.lua - showing what we are not allowed to read.

  THE CORRECTION. On 17 Sep this family concluded that dispel highlighting was impossible during a
  fight, because `C_UnitAuras.GetAuraDataByIndex` errors inside the lockdown and
  `AuraUtil.FindAuraByName` quietly returns nil. That measurement was right and the conclusion was
  wrong: we asked whether an addon can READ an aura, not whether it can SHOW one.

  Blizzard's answer to the lockdown is a widget that draws what you may not know - the same bargain
  as `StatusBar:SetValue(UnitHealth(unit))` for health:

      local c = CreateFrame("AuraContainer", nil, cell, "CustomAuraContainerTemplate")
      c:SetUnit(unit)
      c:AddAuraSlot(key, "HARMFUL|RAID_PLAYER_DISPELLABLE", {
          candidateFilters = { includeDispelTypes = { Poison = true, Disease = true } },
          initializeFrame  = style,
      })

  **The client knows what YOU can dispel** - that is what RAID_PLAYER_DISPELLABLE means - so no
  spell ids are needed and no aura is ever read. We declare the dispel types we care about and how
  the marker looks; the client decides whether anything is there and draws it.

  Confirmed present on 1.60.1.69913 by BiSProbe (`display`): the AuraContainer widget with SetUnit /
  AddAuraGroup / SetEnabled, CustomAuraContainerTemplate, and C_Spell.GetSpellCooldownDuration
  handing back an opaque LuaDurationObject for Cooldown:SetCooldownFromDurationObject.

  Everything here is feature-detected, never version-checked: Forever carries a modern API behind a
  1.60 interface number, so asking "does this client have the widget" is the only honest question.
]]
local ADDON, NS = ...
NS = NS or {}

local FA = {}
NS.FA = FA

-- NOTHING. The filter below already says RAID_PLAYER_DISPELLABLE, which means the CLIENT decides
-- what this character can take off someone - a priest's Magic and Disease, a druid's Curse and
-- Poison, a paladin's three. This used to narrow it further to { Poison, Disease }, which is the
-- list for exactly one class, and on 19 Sep 2026 the addon stopped being for exactly one class.
--
-- Leaving the narrowing out is not laziness: a hard-coded list is a promise about somebody else's
-- spellbook, and the client's own answer is better than ours in every case including the ones
-- nobody here has levelled.

-- BUFFS WORTH A PIP IN THE CORNER, by spell id. Empty on purpose (19 Sep): Earth Shield is a TBC
-- talent and nobody yet knows whether - or at what level - it exists on a 1.60 client. The probe
-- says spell 974 resolves by name there, which is not the same as a shaman being able to cast it.
--
-- Put an id in here and the pip appears; leave it empty and no slot is made at all. That is the
-- difference between a guess in shipped code and a switch waiting for an answer.
--
--   FA.WATCH = { [974] = "Earth Shield" }
FA.WATCH = {}

local DISPEL_TINT = { 0.10, 0.90, 0.35, 0.95 }   -- a green pip: something here you can cure
local ES_TINT     = { 0.95, 0.80, 0.25, 0.90 }

--- Does this client ship the containers, AND will it let us build one? Feature detection, not an
--- interface number: Forever uses 16001 and carries the modern API anyway. Note that "the template
--- exists" and "we may create it" are different questions - the second one only answers itself
--- when we try, and a refusal is remembered in FA.available so we ask exactly once.
function FA.Available()
    if FA.available ~= nil then return FA.available end
    local ok = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
    FA.available = ok and true or false
    return FA.available
end

--- One slot on a container, whichever method this build ships. AddAuraSlot is a single marker
--- (what a dispel highlight wants); AddAuraGroup is the many-buttons form. Older or newer builds
--- may have only one of them, so try both rather than assume.
local function addSlot(container, key, filter, opts)
    if container.AddAuraSlot then
        local ok, slot = pcall(container.AddAuraSlot, container, key, filter, opts)
        if ok and slot then return slot end
    end
    if container.AddAuraGroup then
        opts.maxFrameCount = opts.maxFrameCount or 1
        local ok, slot = pcall(container.AddAuraGroup, container, key, filter, opts)
        if ok and slot then return slot end
    end
    return nil
end
FA.AddSlot = addSlot                    -- SelfBuff's header badge builds its slot the same way

--- A small coloured pip, and NOTHING of the client's own button.
---
--- The first version stretched the marker across the whole health bar, and on the beta that showed
--- as a WHITE BLOCK over the cell: an aura button brings its own icon and border art, and
--- stretched over the bar it simply hid it. A marker should be small enough that being wrong about
--- what the client draws costs a corner rather than the bar.
local function pip(colour)
    return function(auraButton)
        if not auraButton then return end
        -- the button's own art, gone: we want a colour, not Blizzard's icon frame
        if auraButton.GetRegions then
            for _, r in ipairs({ auraButton:GetRegions() }) do
                if r.SetTexture and r.Hide then pcall(r.Hide, r) end
            end
        end
        for _, k in ipairs({ "Icon", "icon", "Border", "border", "Count", "count", "Cooldown" }) do
            local part = auraButton[k]
            if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
        end
        local t = auraButton:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetAllPoints(auraButton)
        t:SetVertexColor(colour[1], colour[2], colour[3], colour[4])
        if auraButton.SetMouseMotionEnabled then auraButton:SetMouseMotionEnabled(false) end
        return t
    end
end

--- THE DISPEL TYPE, drawn by the client. ForeverAuras 0.1.148 (21 Sep) hands an aura button a
--- texture with AddDispelTypeTexture and the client paints the TYPE into it - Magic, Curse, Poison,
--- Disease, in the game's own icon and colour - for an aura we are never allowed to read. So the
--- marker says what it is, not only that it is there.
---
--- The green square is made first and stays the fallback: a client without the call, or one that
--- refuses it, still gets "something here you can cure". Only when the client took the texture is
--- the square hidden.
local function dispelPip(colour)
    local square = pip(colour)
    return function(auraButton)
        local t = square(auraButton)
        if not (auraButton and type(auraButton.AddDispelTypeTexture) == "function") then return end
        local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        local icon = auraButton:CreateTexture(nil, "OVERLAY", nil, 1)
        icon:SetAllPoints(auraButton)
        local ok = pcall(auraButton.AddDispelTypeTexture, auraButton, icon, {
            showWhenHarmful = true, showWhenHelpful = false,
            style = styles and styles.Icon or nil,
        })
        if ok then
            if t and t.Hide then t:Hide() end
            FA.typed = true                      -- /bish scan can say which marker is in use
        elseif icon.Hide then
            icon:Hide()
        end
    end
end

-- CURE BOXES (Arn, 16 Oct 2026): "Decursive draws 20 cells for the raid ... what if where we draw
-- the markers right now we pre put tiny cells there for that raider with that cleanse. So the game
-- draws the poison icon and we draw the cleanse poison in the same place, it's always clickable and
-- we carve out a place that's outlined inside the cell ... when they get poison Blizz draws the icon
-- we de alpha the button outline so it draws attention to cure".
--
-- HOW, WITHOUT READING A THING:
--   * a SECURE button per cure spell, set up out of combat - "cast Cure Poison on this raider" - and
--     never changed in a fight, so it is always clickable. A dim outline says "this corner cures".
--   * its own aura slot, narrowed to the debuff TYPES that spell removes. The client draws its icon
--     there only when such a debuff is on, and the BRIGHT outline is made inside that button - so the
--     client showing its icon IS the outline lighting up. We never learn that anyone is poisoned.
-- One box per spell, each lighting only for its own types: a shaman's poison box lights for poison
-- and nothing else, so the box that lights is the box to click.
--
-- By NAME, first one in the book wins (the stronger rank-up spell before the plain one). Forever's
-- class kits are not TBC's or vanilla's, so the book decides, as it does for the heals over time.
FA.CURES = {
    SHAMAN  = { { names = { "Cure Poison" }, types = { Poison = true } },
                { names = { "Cure Disease" }, types = { Disease = true } } },
    PRIEST  = { { names = { "Dispel Magic" }, types = { Magic = true } },
                { names = { "Abolish Disease", "Cure Disease" }, types = { Disease = true } } },
    DRUID   = { { names = { "Remove Curse" }, types = { Curse = true } },
                { names = { "Abolish Poison", "Cure Poison" }, types = { Poison = true } } },
    PALADIN = { { names = { "Cleanse" }, types = { Magic = true, Poison = true, Disease = true } },
                { names = { "Purify" }, types = { Poison = true, Disease = true }, unless = "Cleanse" } },
    MAGE    = { { names = { "Remove Curse", "Remove Lesser Curse" }, types = { Curse = true } } },
}
FA.CURE_MAX = 2
local CURE_DIM    = { 0.59, 0.56, 0.68, 0.45 }   -- "this corner cures", always
local CURE_BRIGHT = { 0.31, 0.82, 0.81, 1.00 }   -- the family's "good": cure this, now

function FA.CuresOn()
    local d = NS.DB and NS.DB()
    return not (type(d) == "table" and d.cures == false)
end

local function known(name)
    return NS.FM and NS.FM.BookIds and #NS.FM.BookIds(name) > 0
end

--- The cures this character can cast, in box order: { name =, types = } - at most FA.CURE_MAX.
function FA.Cures()
    if not FA.CuresOn() then return {} end
    local class = UnitClass and NS.Plain(select(2, UnitClass("player"))) or nil
    local out = {}
    for _, c in ipairs(FA.CURES[class or ""] or {}) do
        if not (c.unless and known(c.unless)) then
            for _, name in ipairs(c.names) do
                if known(name) then out[#out + 1] = { name = name, types = c.types } break end
            end
        end
        if #out >= FA.CURE_MAX then break end
    end
    return out
end

--- ONLY ON YOUR GROUP'S CELLS (Arn, 17 Oct 2026, a screenshot of the target cell on an enemy:
--- "its coming up on the enemy bars too"). The target and target-of-target cells hold whoever you
--- clicked, friend or foe, and a secure box cannot come and go with them in a fight - so they, and
--- pets, keep the old pip. You, party1-4 and raid1-40 get boxes.
function FA.CureUnit(unit)
    if type(unit) ~= "string" then return false end
    return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

--- Where box `i` sits on a cell, and how big it is: the marker's size plus a 2 px frame for the outline.
--- A COLUMN DOWN THE LEFT EDGE (Arn, 17 Oct: "use the left side as the debuff window"): box 1 at the
--- top, box 2 under it - two 14 px boxes fill a 34 px cell. Answers size, x, and y down from the top.
function FA.CureBox(i)
    local box = FA.MarkerSize() + 4
    return box, 2, 2 + (i - 1) * (box + 2)
end

--- Where the cure column ends, for whatever sits beside it (the name, the heals over time).
function FA.CureLeft(n)
    if not n or n < 1 then return nil end
    local box, x = FA.CureBox(1)
    return x + box + 3
end

local function outline(parent, col, inset, layer, thick)
    local t = {}
    thick = thick or 1
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local e = parent:CreateTexture(nil, layer or "OVERLAY", nil, 2)
        e:SetColorTexture(col[1], col[2], col[3], col[4])
        if side == "TOP" or side == "BOTTOM" then
            e:SetPoint(side .. "LEFT", parent, side .. "LEFT", -inset, side == "TOP" and inset or -inset)
            e:SetPoint(side .. "RIGHT", parent, side .. "RIGHT", inset, side == "TOP" and inset or -inset)
            e:SetHeight(thick)
        else
            e:SetPoint("TOP" .. side, parent, "TOP" .. side, side == "LEFT" and -inset or inset, inset)
            e:SetPoint("BOTTOM" .. side, parent, "BOTTOM" .. side, side == "LEFT" and -inset or inset, -inset)
            e:SetWidth(thick)
        end
        t[side] = e
    end
    return t
end
FA.Outline = outline

--- The client's marker for one cure: the type icon it paints, and around it the bright outline -
--- made here, inside the button the client shows only when there is something to cure.
local function curePip(colour, cell)
    local inner = dispelPip(colour)
    return function(auraButton)
        inner(auraButton)
        if not auraButton then return end
        -- the click belongs to the box underneath, never to the marker
        if auraButton.EnableMouse then pcall(auraButton.EnableMouse, auraButton, false) end
        if auraButton.SetMouseClickEnabled then pcall(auraButton.SetMouseClickEnabled, auraButton, false) end
        -- LOUDER (Arn, 17 Oct: "its a little hard to see with our cross hairs and or maybe make the
        -- little boxes flash more"): a 2 px outline and a teal wash behind the icon, on a frame of
        -- their own that BREATHES - the client runs the pulse, no Lua per frame, and only while it
        -- shows the marker, which is only while there is something to cure.
        -- NOT UNDER THE BOX (Arn, 17 Oct, the first pulse: "cant really see it flashing or pulsing").
        -- The secure box sits ABOVE the client's marker so it takes the click, and its dim outline
        -- landed exactly on the bright one and painted it out. So: the wash on the marker itself,
        -- UNDER the icon, filling the box's empty middle; the outline on a frame raised over the
        -- box and drawn just OUTSIDE it, where nothing of ours can cover it.
        local wash = auraButton:CreateTexture(nil, "BACKGROUND", nil, -1)
        wash:SetPoint("TOPLEFT", auraButton, "TOPLEFT", -2, 2)
        wash:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 2, -2)
        wash:SetColorTexture(CURE_BRIGHT[1], CURE_BRIGHT[2], CURE_BRIGHT[3], 0.55)
        local ok, glow = pcall(CreateFrame, "Frame", nil, auraButton)
        if not ok or not glow then
            auraButton.cureGlow = outline(auraButton, CURE_BRIGHT, 3, "OVERLAY", 2)
            return
        end
        glow:SetAllPoints(auraButton)
        -- measured from the CELL, as the box is (cell + 12): the marker's own level is the client's
        if glow.SetFrameLevel and cell and cell.GetFrameLevel then
            local lvl = cell:GetFrameLevel()
            if type(lvl) == "number" then glow:SetFrameLevel(lvl + 20) end
        end
        glow.wash = wash
        auraButton.cureGlow = outline(glow, CURE_BRIGHT, 3, "OVERLAY", 2)
        if glow.CreateAnimationGroup then
            local okA, pulse = pcall(glow.CreateAnimationGroup, glow)
            if okA and pulse then
                local fade = pulse:CreateAnimation("Alpha")
                fade:SetFromAlpha(1)
                fade:SetToAlpha(FA.CURE_PULSE_LOW)
                fade:SetDuration(FA.CURE_PULSE_SECONDS)
                if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
                pulse:SetLooping("BOUNCE")
                pulse:Play()
                glow.pulse = pulse
            end
        end
        auraButton.cureGlowFrame = glow
        -- HOW MANY (Arn, 17 Oct, the game's own icon reading 3: "this one shows how many it is so i
        -- know i have to click 3 times"). The client writes the stack count into a label we hand it
        -- (SetApplicationCount, as the shield badge's charges) - never read. Its own frame, over the
        -- box and NOT on the pulsing one: a number that fades in and out is a number misread.
        if type(auraButton.SetApplicationCount) == "function" then
            local okN, num = pcall(CreateFrame, "Frame", nil, auraButton)
            if okN and num then
                num:SetAllPoints(auraButton)
                if num.SetFrameLevel and cell and cell.GetFrameLevel then
                    local lvl = cell:GetFrameLevel()
                    if type(lvl) == "number" then num:SetFrameLevel(lvl + 21) end
                end
                local fs = num:CreateFontString(nil, "OVERLAY")
                if fs.SetFont then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE") end
                fs:SetPoint("BOTTOMRIGHT", auraButton, "BOTTOMRIGHT", 4, -3)
                if pcall(auraButton.SetApplicationCount, auraButton, fs) then auraButton.cureCount = fs end
            end
        end
    end
end
FA.CURE_PULSE_LOW, FA.CURE_PULSE_SECONDS = 0.25, 0.4    -- never down to nothing: a box that vanishes is one you look past

--- The secure boxes on a cell, one per cure. Out of combat only (the caller's rule, like the
--- attributes); a box beyond the cures this character has is hidden, not destroyed.
function FA.Boxes(cell, cures)
    if InCombatLockdown and InCombatLockdown() then return false end
    cell.cureBoxes = cell.cureBoxes or {}
    for i = 1, FA.CURE_MAX do
        local c, b = cures[i], cell.cureBoxes[i]
        if c and not b then
            b = CreateFrame("Button", nil, cell, "SecureActionButtonTemplate")
            b:RegisterForClicks("AnyDown")          -- the cell's own rule: bare LeftButtonDown no-ops
            -- the cell's unit, whoever it is now: a rebind never has to touch the box
            b:SetAttribute("useparent-unit", true)
            b:SetAttribute("type", "spell")
            b.dim = outline(b, CURE_DIM, 0, "ARTWORK")
            cell.cureBoxes[i] = b
        end
        if b then
            if c then
                local size, x, y = FA.CureBox(i)
                b:SetSize(size, size)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", cell, "TOPLEFT", x, -y)
                if b.SetFrameLevel and cell.GetFrameLevel then
                    local lvl = cell:GetFrameLevel()
                    if type(lvl) == "number" then b:SetFrameLevel(lvl + 12) end   -- over the markers
                end
                b:SetAttribute("spell", c.name)
                b.cure = c.name
                b:Show()
            else
                b:Hide()
                b.cure = nil
            end
        end
    end
    -- the name moves beside the column, or back to the edge
    cell.cureLeft = FA.CureLeft(#cures)
    if NS.FG and NS.FG.PlaceName then NS.FG.PlaceName(cell) end
    return true
end

-- YOUR HEALS OVER TIME, on the cell, with the client's own countdown. By family: every rank of a
-- spell is its own spell id, and a slot shows whichever rank of the family is on the target. The
-- ids are Classic's - and the book is read too (FA.HotIds), because this client's ids for the
-- higher ranks are not something anyone here has measured, while the ones YOU know are in your
-- spellbook. Only spells you cast ("HELPFUL|PLAYER"): another healer's Renew is not your timer.
FA.HOTS = {
    PRIEST = {
        { key = "Renew", ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },
    },
    DRUID = {
        { key = "Rejuvenation", ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 } },
        { key = "Regrowth", ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 } },
    },
    -- RIPTIDE, WHICH A SHAMAN HAS HERE AND HAD NOT ON TBC (3 Oct 2026). Found in the Fojji shaman
    -- pack Arn installed: this mode's shaman is a kit, not an era - vanilla, plus Water Shield and
    -- Lava Burst from TBC, plus Riptide and Maelstrom Weapon from Wrath, plus Totemic Projection
    -- from Cataclysm, and NO Earth Shield. So the addon's author has been playing the one class
    -- whose heal over time it did not draw.
    --
    -- NAMED, NOT NUMBERED: nobody here knows this client's Riptide ids, and a guess would be the
    -- same mistake as assuming Water Shield could not exist. The spellbook answers, and a shaman
    -- who has not trained it simply has no family.
    SHAMAN = {
        { key = "Riptide", name = "Riptide" },
    },
}
local HOT_GAP = 2

--- HOW BIG THE MARKERS ARE. A player's request (paszczyszyn, 22 Sep): "Is there a possibility of
--- an option to adjust the size of buffs and debuffs?". One number for all of them (the dispel
--- marker, the heal-over-time icons, the watched-buff pip), because three sliders for three dots
--- is three questions where the player had one. 10 is what they have always been.
function FA.MarkerSize()
    local d = NS.DB and NS.DB()
    local n = type(d) == "table" and tonumber(d.markers) or nil
    if not n then return 10 end
    if n < 6 then return 6 elseif n > 20 then return 20 end
    return math.floor(n + 0.5)
end

--- Every spell id for one family: the listed ones, plus every rank of that name in the book.
---
--- A FAMILY MAY CARRY A NAME INSTEAD OF IDS (3 Oct 2026). The id list was written from a TBC
--- client, so it only ever worked for spells that existed there - and the name used to scan the
--- book was derived FROM the first id, which means a spell we hold no id for could not be found at
--- all. Riptide is exactly that spell: shamans have it in this game mode and nobody here knows its
--- id, because it is not a TBC spell and no version number predicts what this client contains.
---
--- Naming the family and letting the spellbook answer is the right way round anyway: the book is
--- the only authority on what a character actually has, and it has been the answer every other
--- time this addon guessed at the game's spell list.
function FA.HotIds(family)
    local ids = {}
    for _, id in ipairs(family.ids or {}) do ids[id] = true end
    local name = family.name
    if not name and C_Spell and C_Spell.GetSpellName and family.ids and family.ids[1] then
        name = select(2, pcall(C_Spell.GetSpellName, family.ids[1]))
    end
    if type(name) ~= "string" or name == "" or NS.Secret(name) then return ids end
    -- FROM THE ONE READ THE MOUSE KEEPS (8 Oct 2026). This walked all 500 book slots itself, for
    -- every family, for every cell, at every layout - a raid filling up relays the grid out once
    -- a join. FM.BookIds answers from a book read once and re-read when the client says it changed.
    -- Mouse.lua loads after this file, so it is looked up here, at the moment of asking.
    if NS.FM and NS.FM.BookIds then
        for _, id in ipairs(NS.FM.BookIds(name)) do ids[id] = true end
    end
    return ids
end

--- The families this character casts, or nothing: a paladin has no heal over time here.
function FA.Hots()
    local d = NS.DB and NS.DB()
    if type(d) == "table" and d.hots == false then return {} end
    local class = UnitClass and NS.Plain(select(2, UnitClass("player"))) or nil
    return FA.HOTS[class or ""] or {}
end

--- A heal-over-time marker: the spell's own icon (the client sets it), its border gone, and a
--- Cooldown the client runs from the aura's duration - SetDurationCooldown, as ForeverAuras does.
--- The swipe IS the time left, and we never read it.
local function hotIcon(auraButton)
    if not auraButton then return end
    for _, k in ipairs({ "Border", "border", "Count", "count" }) do
        local part = auraButton[k]
        if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
    end
    if auraButton.SetMouseMotionEnabled then auraButton:SetMouseMotionEnabled(false) end
    if auraButton.EnableMouse then pcall(auraButton.EnableMouse, auraButton, false) end
    if type(auraButton.SetDurationCooldown) == "function" then
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, auraButton, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints(auraButton)
            if cd.SetDrawBling then cd:SetDrawBling(false) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
            if cd.SetReverse then cd:SetReverse(true) end    -- fills in as it runs out
            pcall(auraButton.SetDurationCooldown, auraButton, cd)
        end
    end
end

--- A fingerprint of what the containers were built for: the debug switch and every heal-over-time
--- id. When it changes - the book filled in after login, a new rank learned, /bish hots - each
--- cell's container is rebuilt; otherwise the one it has is only pointed at its unit.
local function signature()
    -- read the book once per pass, not once per cell: a layout attaches forty cells in one frame
    local now = GetTime and GetTime() or 0
    if FA.sig and FA.sigAt == now then return FA.sig end
    local parts = { FA.debug and "d" or "", "px" .. FA.MarkerSize() }
    for _, c in ipairs(FA.Cures()) do parts[#parts + 1] = "cure:" .. c.name end
    for _, fam in ipairs(FA.Hots()) do
        local ids = {}
        for id in pairs(FA.HotIds(fam)) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = fam.key .. ":" .. table.concat(ids, ",")
    end
    FA.sig, FA.sigAt = table.concat(parts, "|"), now
    return FA.sig
end

--- SIZE AND PLACE A SLOT, OR LEAVE IT BE. On a player's own PC, 6 Oct 2026, 0.8.1 threw 442 times:
--- "calling 'SetSize' on bad self (Attempt to access forbidden object from code tainted by an
--- AddOn)". The container took SetSize; the slot it handed back did not - and because that was a
--- plain Lua error inside the layout, the grid stopped at the first cell, and the layout's retry
--- threw it again every frame. Why that client and not ours is not known. So it is not guessed at:
--- the first refusal is remembered (FA.slotRefused, shown by /bish auras) and no slot is touched
--- again. A marker the client will not let us place is a marker we do without.
local function place(slot, px, point, cell, x, y)
    if not slot or FA.slotRefused then return false end
    -- the LOOKUP inside the pcall too: on a forbidden object even reading a method may refuse
    local ok, why = pcall(function()
        slot:SetSize(px, px)
        slot:SetPoint(point, cell, point, x, y)
    end)
    if not ok then
        FA.slotRefused = tostring(why)
        if NS.Print then NS.Print("aura markers are off: this client will not let them be placed (/bish auras)") end
        return false
    end
    return true
end
FA.Place = place

--- SIZE AND PLACE IT INSIDE ITS CREATION (14 Oct 2026, Arn's own client: "aura markers are off: this
--- client will not let them be placed" - the 6 Oct refusal, now on his PC too; and yet "the target and
--- tot show the poisons"). Read off EllesmereUI's AuraContainers.lua: "SetPoint on the returned
--- button is denied while auras are secret (12.1 button access restriction)" - they anchor it INSIDE
--- initializeFrame, "the creation window", and nowhere else. So do we: the size and the anchor ride
--- the client's own hand-over of the button, then the marker's own styling runs. place() above is
--- kept for anything that still calls it; the grid's markers no longer do.
function FA.Placed(init, px, point, rel, x, y)
    return function(button, ...)
        local ok = pcall(function()
            button:SetSize(px, px)
            button:ClearAllPoints()
            button:SetPoint(point, rel, point, x, y)
        end)
        if not ok then FA.initRefused = true end
        if init then return init(button, ...) end
    end
end

--- Take a cell's container down before a new one is built: the old one would otherwise go on
--- drawing underneath it.
local function release(cell)
    local old = cell.auras
    if not old then return end
    if old.SetEnabled then pcall(old.SetEnabled, old, false) end
    if old.Hide then pcall(old.Hide, old) end
    cell.auras, cell.dispelSlot, cell.watchSlot, cell.anySlot, cell.hotSlots = nil, nil, nil, nil, nil
end

--- Give one grid cell its markers. Returns false when this client has no containers, which is the
--- TBC case and any future client that drops them - the grid then simply has no dispel marker,
--- rather than erroring every frame.
local attach
function FA.Attach(cell, unit)
    -- A MARKER NEVER TAKES THE GRID DOWN. Layout calls this for every cell and re-raises any error,
    -- and its retry runs every frame until a layout succeeds - so one throw in here was a grid
    -- stuck at its first cell and an error 60 times a second (0.8.1, 6 Oct). Whatever fails in
    -- here next costs the markers, said once, and the cells still get laid out.
    local ok, r = pcall(attach, cell, unit)
    if ok then return r end
    if not FA.attachError and NS.Print then
        NS.Print("aura markers stopped on an error: |cfff08cb0%s|r", tostring(r))
    end
    FA.attachError = tostring(r)
    return false
end
function attach(cell, unit)
    if not FA.Available() or not cell or not unit then return false end
    local sig = signature()
    if cell.auras and cell.aurasSig == sig then
        if cell.auras.SetUnit then pcall(cell.auras.SetUnit, cell.auras, unit) end
        return true
    end
    release(cell)

    -- Blizzard's own AuraContainer addon owns this template. Without it the template is still
    -- KNOWN to C_XMLUtil - so feature detection says yes - and building one is refused as a
    -- protected action: "BiSHealing has been blocked from an action only available to the Blizzard
    -- UI", at every layout, forever. Hence `## OptionalDeps: Blizzard_AuraContainer` in the TOC.
    --
    -- And hence this: ONE attempt. A refusal is remembered, not retried, because the dialog is not
    -- a Lua error and pcall cannot see it - the only thing that stops a popup every pull is us
    -- deciding never to ask twice.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, cell, "CustomAuraContainerTemplate")
    if not ok or not container then
        FA.available = false
        FA.refused = "the client refused to build an AuraContainer (protected action?)"
        return false
    end
    container:SetSize(1, 1)
    container:SetPoint("CENTER", cell)
    -- above the bar, when this client will say what level the cell is on. A widget stub that
    -- answers nothing must not take the grid down over a cosmetic detail.
    if container.SetFrameLevel and cell.GetFrameLevel then
        local lvl = cell:GetFrameLevel()
        if type(lvl) == "number" then container:SetFrameLevel(lvl + 10) end
    end
    container:SetUnit(unit)

    -- 1. anything WE can cure. With cure boxes: one marker per cure, narrowed to the types that
    --    spell removes, sitting in its box. Without (switched off, or a class with no cure): the
    --    one pip at the edge, as it always was.
    local dispel
    local cures = FA.CureUnit(unit) and FA.Cures() or {}
    cell.cureSlots = {}
    if #cures > 0 then
        local px = FA.MarkerSize()
        for i, c in ipairs(cures) do
            local _, x, y = FA.CureBox(i)
            cell.cureSlots[i] = addSlot(container, "BiSHealCure" .. i, "HARMFUL|RAID_PLAYER_DISPELLABLE", {
                candidateFilters = { includeDispelTypes = c.types },
                initializeFrame = FA.Placed(curePip(DISPEL_TINT, cell), px, "TOPLEFT", cell, x + 2, -(y + 2)),
            })
        end
        dispel = cell.cureSlots[1]
    else
        dispel = addSlot(container, "BiSHealDispel", "HARMFUL|RAID_PLAYER_DISPELLABLE", {
            -- a pip at the edge, never over the bar - sized and placed in its creation (FA.Placed)
            initializeFrame = FA.Placed(dispelPip(DISPEL_TINT), FA.MarkerSize(), "LEFT", cell, 2, 0),
        })
    end
    FA.Boxes(cell, cures)

    -- 2. a pip for any buff we are watching. Nothing is watched by default, so no slot is built
    --    and the cell stays as clean as the grid was before.
    local watch, any = {}, false
    for id in pairs(FA.WATCH) do
        watch[id] = true
        any = true
    end
    local es
    if any then
        es = addSlot(container, "BiSHealWatch", "HELPFUL", {
            candidateFilters = { includeSpellIDs = watch },
            initializeFrame = FA.Placed(pip(ES_TINT), math.max(6, FA.MarkerSize() - 2), "TOPRIGHT", cell, -2, -2),
        })
    end

    -- the debug marker, when someone is asking "does this draw at all?"
    if FA.debug then
        local any = addSlot(container, "BiSHealAnyDebuff", "HARMFUL", {
            initializeFrame = FA.Placed(pip({ 1.00, 0.45, 0.10, 0.95 }), FA.MarkerSize(), "BOTTOMLEFT", cell, 2, 2),
        })
        cell.anySlot = any
    end

    -- 3. YOUR heals over time, bottom left in a row, each with the client's countdown swipe. The
    --    number owns the bottom right, the name the top line; these sit under the name's start.
    -- A FAMILY WITH NO IDS IS A SPELL THIS CHARACTER HAS NOT TRAINED, and it gets no marker: a
    -- slot filtered to nothing would be a permanently empty icon taking a corner of every cell.
    -- This became reachable on 3 Oct, when SHAMAN gained Riptide by NAME - a shaman below the
    -- level that trains it has the family and none of its ids.
    local hots, shown = {}, 0
    for _, fam in ipairs(FA.Hots()) do
        local ids = FA.HotIds(fam)
        if next(ids) == nil then ids = nil end
        if ids then
        shown = shown + 1
        local i = shown
        local px = FA.MarkerSize()
        local slot = addSlot(container, "BiSHealHot" .. fam.key, "HELPFUL|PLAYER", {
            candidateFilters = { includeSpellIDs = ids },
            -- beside the cure column when there is one (17 Oct), at the edge when not
            initializeFrame = FA.Placed(hotIcon, px, "BOTTOMLEFT", cell,
                (FA.CureLeft(#cures) or 3) + (i - 1) * (px + HOT_GAP), 3),
        })
        hots[fam.key] = slot
        end
    end

    if container.SetEnabled then container:SetEnabled(true) end
    cell.auras, cell.dispelSlot, cell.watchSlot, cell.hotSlots = container, dispel, es, hots
    cell.aurasSig = sig
    return true
end

--- A DEBUG MARKER: any harmful aura at all, dispellable or not.
---
--- The real marker asks for "HARMFUL|RAID_PLAYER_DISPELLABLE", which means the CLIENT decides
--- what this character can cure. A shaman who has not learned Cure Poison yet can cure nothing,
--- so nothing draws - and from the outside that looks exactly like a container that never worked.
--- This tells the two apart: turn it on, take any debuff, and if the cell washes orange the
--- containers are drawing and the dispel filter is simply doing its job.
---
--- Off by default and never shipped on: it marks every debuff, which in a raid is noise.
function FA.Debug(on, frames)
    FA.debug = on and true or false
    FA.sig = nil                            -- the fingerprint changed: every container is rebuilt
    for _, f in ipairs(frames or (NS.FG and NS.FG.frames) or {}) do
        if f.unit then FA.Attach(f, f.unit) end
    end
    return FA.debug
end

--- Your heals over time on the cells, on or off. Out of combat only, like every container change.
--- Cure boxes on or off (`/bish cures`). Out of combat, every cell is rebuilt now; in a fight, after.
function FA.SetCures(on)
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.cures = on and true or false end
    FA.sig = nil
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, f in ipairs((NS.FG and NS.FG.frames) or {}) do
        if f.unit then FA.Attach(f, f.unit) end
        if not on and f.cureBoxes then FA.Boxes(f, {}) end
    end
    return true
end

function FA.SetHots(on)
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.hots = on and true or false end
    FA.sig = nil
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, f in ipairs((NS.FG and NS.FG.frames) or {}) do
        if f.unit then FA.Attach(f, f.unit) end
    end
    return true
end

--- Point every cell's container at whatever unit that cell now holds. Called from the layout, out
--- of combat, exactly like the secure attributes.
function FA.Rebind(frames)
    local n = 0
    for _, f in ipairs(frames or {}) do
        if f.unit and FA.Attach(f, f.unit) then n = n + 1 end
    end
    return n
end
