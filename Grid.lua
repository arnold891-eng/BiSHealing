-- BiSHealing / Forever -- the grid.
--
-- Shape B, decided 17 Sep 2026: frames and click-casting during the fight, a real brain between
-- pulls (that half lives elsewhere). This file is the fight half, and it obeys one rule:
--
--        THE CLIENT OWNS THE NUMBERS. WE HAND THEM OVER AND NEVER LOOK.
--
-- Concretely: `bar:SetValue(UnitHealth(unit))`. No division to work out a width, no `hp < hpMax`
-- to pick a colour, no `tostring(hp)` in a label. The TBC pyramid paints a Texture whose WIDTH it
-- calculates -- `hpW = barW * hp / hpMax` -- and on Forever that line is a hard error, which is
-- why this grid uses a StatusBar instead and lets the client do the arithmetic it will not show us.
--
-- What it may still read inside the lockdown (all measured, see _bisdev/docs/forever-secret-values.md):
-- who is in the group, their name, class and role, whether they are dead, threat, which totem
-- slots are filled, and the addon channel. That is enough for a grid; it is not enough for a brain.
--
-- Layout runs OUT OF COMBAT only -- moving or sizing a secure frame is blocked once the pull
-- starts, exactly as on TBC. During the fight only colours, alpha and bar values change.
--
-- Testable on purpose: every piece is a function on NS.FG that takes the frame it works on, so
-- dev/forever.lua can drive them against a client that lies the way Forever does, with the game
-- shut. See also `lua5.1 _bisdev/dev/lockdown.lua BiSHealing`.

local ADDON, NS = ...
NS = NS or {}

local FG = {}
NS.FG = FG

local FRAME_W, FRAME_H, PAD = 84, 34, 3
local PER_COL = 5                       -- one column per party, the way a raid reads

-- THE PYRAMID (Arn, 20 Sep, mid-raid with the TBC frames up: "this is how we make forever
-- eventually pyramid tanks on top people out of range dimmmed").
--
-- The SHAPE is the TBC addon's, copied as arithmetic - BiSHealingTBC/BiSHealing.lua:126, rowSizes
-- {1, 2, 6} with the first two rows full width and every row after that six cells at half width.
-- An apex, a pair, then a wide base: the people you are most likely to be healing are the
-- biggest and nearest the top.
--
-- The ORDER is not the TBC addon's, and cannot be. That one ranked people by healing volume,
-- Chain Heal bounce and damage done - all out of the combat log, which is a PROTECTED call on
-- Forever. So the body ports and the brain does not. What stands in for it is the role: tank,
-- then healer, then damage. A cruder sort, and the only one this client will allow.
local SHAPE = { 1, 2, 6 }               -- cells in each row; rows past the last repeat TAIL
local WIDE  = { true, true }            -- which rows are full width
local TAIL  = 6
local HALF_W = FRAME_W                  -- the ordinary cell
local FULL_W = 2 * FRAME_W + PAD        -- exactly two ordinary cells and the gap between them,
                                        -- so the rows line up on one grid instead of drifting
-- TANKS, THEN DAMAGE, THEN THE HEALERS AT THE BOTTOM. Arn, 23 Sep: "when we arrange by tanks.
-- lets do tanks dps and healers at the bottom". The healers were second when the pyramid was
-- built; in a fight the people you watch hardest are the tank and whoever is standing in the
-- fire, and your fellow healers are the ones you glance at last.
local ROLE_RANK = { TANK = 1, DAMAGER = 2, HEALER = 3 }

--- Where each of `n` cells goes: its row, its place in the row, how many share the row, and
--- whether the row is full width. Pure - no frames - so it can be asked without a client.
function FG.Pyramid(n)
    local out, r, i = {}, 1, 1
    while i <= n do
        local cap = SHAPE[r] or TAIL
        local count = math.min(cap, n - i + 1)
        for c = 1, count do
            out[i] = { row = r, col = c, count = count, wide = WIDE[r] and true or false }
            i = i + 1
        end
        r = r + 1
    end
    return out
end

--- The roster by RAID GROUP: one column per group, in group order. Arn asked for "regular grid
--- by group", and the old grid was not quite that - it filled columns of five in raid1, raid2
--- order, and raid index is the order people JOINED, not their group. It only looked grouped when
--- people happened to join in group order.
---
--- Returns the units in order and, beside them, the column each belongs in and its row within it.
--- Outside a raid it is one column: you, then your party.
function FG.ByGroup(roster)
    local inRaid = IsInRaid and IsInRaid()
    local keyed = {}
    for i, u in ipairs(roster) do
        local sub = 1
        -- a PET gets a column of its own, after every group: in with its owner's group it would
        -- make one column taller than the rest and push a real player off the bottom of the view
        if FG.IsPetUnit(u) then
            sub = 99
        elseif inRaid and GetRaidRosterInfo then
            local idx = tonumber(tostring(u):match("^raid(%d+)$"))
            if idx then
                local ok, _, _, g = pcall(GetRaidRosterInfo, idx)
                g = ok and tonumber(NS.Plain(g)) or nil
                sub = g or 9                      -- unknown groups go last, not first
            end
        end
        keyed[i] = { unit = u, sub = sub, at = i }
    end
    table.sort(keyed, function(a, b)
        if a.sub ~= b.sub then return a.sub < b.sub end
        return a.at < b.at
    end)
    local units, cols, rows, colOf, n = {}, {}, {}, {}, 0
    for i, k in ipairs(keyed) do
        if not colOf[k.sub] then n = n + 1; colOf[k.sub] = n; rows[n] = 0 end
        local c = colOf[k.sub]
        units[i] = k.unit
        cols[i], rows[c] = c, rows[c] + 1
        keyed[i].row = rows[c]
    end
    local place = {}
    for i, k in ipairs(keyed) do place[i] = { col = cols[i], row = k.row } end
    return units, place, n
end

--- The roster, tanks first. Read OUT OF COMBAT only - Layout refuses in combat - which is also
--- the only time a role is not a secret. Stable: within a role, raid order is kept, so nobody
--- shuffles about between two layouts just because the sort had nothing to say about them.
function FG.ByRole(roster)
    local keyed = {}
    for i, u in ipairs(roster) do
        local role
        if UnitGroupRolesAssigned then
            local ok, r = pcall(UnitGroupRolesAssigned, u)
            role = ok and NS.Plain(r) or nil
        end
        local rank = ROLE_RANK[role or ""] or 4
        -- THE RAID'S OWN WORD FOR IT. Classic raids rarely set LFG roles - the leader right-clicks
        -- someone and makes them Main Tank instead - so with roles alone a real raid night sorts
        -- everyone as the same thing and the pyramid is just join order (Arn's party, 20 Sep: four
        -- identical badges, and himself on the apex). A main tank is a tank, whatever the LFG
        -- role says.
        if rank ~= 1 and GetPartyAssignment then
            local ok, mt = pcall(GetPartyAssignment, "MAINTANK", u)
            if ok and NS.Plain(mt) then rank = 1 end
        end
        keyed[i] = { unit = u, rank = rank, at = i }
    end
    table.sort(keyed, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.at < b.at
    end)
    local out = {}
    for i, k in ipairs(keyed) do out[i] = k.unit end
    return out
end
-- No spell names live here any more. Three did - Healing Wave, Lesser Healing Wave, Chain Heal -
-- back when this grid was the Forever half of a shaman addon. "Can I reach them" is answered with
-- the spell on your LEFT BUTTON, which is both class-agnostic and more honest than a constant:
-- the range that matters is the range of the thing the click would actually cast.

FG.frames, FG.byUnit = {}, {}
FG.maxOK = true                         -- set false if the client refuses a secret max (see Paint)

--------------------------------------------------------------------- roster --

--- The unit tokens to show, in raid reading order. No sorting by health -- that is the one thing
--- Forever makes impossible, so the order is group order and the player's eyes do the rest.
function FG.Roster()
    local out = {}
    local d = NS.DB and NS.DB()
    -- PETS, when asked for (Arn: "toggel to see pets"). Off by default: a raid with five hunters
    -- and three warlocks is eight more cells, and most healers heal pets by exception.
    local pets = type(d) == "table" and d.pets == true
    local function add(u) if UnitExists(u) then out[#out + 1] = u end end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
        if pets then for i = 1, 40 do add("raidpet" .. i) end end
        return out
    end
    out[1] = "player"
    for i = 1, 4 do add("party" .. i) end
    if pets then
        add("pet")
        for i = 1, 4 do add("partypet" .. i) end
    end
    return out
end

--- Is this unit token a pet? pet, partypet3, raidpet12.
function FG.IsPetUnit(u)
    return type(u) == "string" and u:match("pet%d*$") ~= nil
end

--------------------------------------------------------------------- frames --

--- One cell. A secure button so the click reaches Blizzard's own code (an addon may not cast),
--- with a StatusBar for health because the client has to do the maths.
function FG.Make(i, parent)
    local f = CreateFrame("Button", "BiSHealingForeverUnit" .. i, parent or UIParent,
                          "SecureUnitButtonTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:RegisterForClicks("AnyDown")      -- bare "LeftButtonDown" silently no-ops on secure buttons

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("TOPLEFT", 1, -1)
    f.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    f.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(1)

    -- WHAT IS ALREADY ON ITS WAY. A second bar, starting where the health fill ends and running
    -- on in a paler green: that much more is coming, from you or from anyone else.
    --
    -- Arn, 19 Sep: "the frame is not showing how much an incomming heal is going to do like
    -- healium does". It can, and the way is the display bargain again - UnitGetIncomingHeals
    -- hands back a number that may be secret, and a secret may be given to a StatusBar. So the
    -- addon never learns the size of the heal; the client draws it.
    --
    -- Anchored to the health bar's TEXTURE rather than the bar frame, which is what makes it
    -- start at the end of the fill and move with it. (Read off Healium's own Forever build,
    -- which does exactly this and was right to.)
    f.incoming = CreateFrame("StatusBar", nil, f)
    f.incoming:SetPoint("TOPLEFT", f.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2)
    f.incoming:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.incoming:SetStatusBarColor(0.30, 0.85, 0.45, 0.55)
    f.incoming:SetMinMaxValues(0, 1)
    f.incoming:SetValue(0)
    if f.incoming.SetFrameLevel and f.GetFrameLevel then
        local lvl = f:GetFrameLevel()
        if type(lvl) == "number" then f.incoming:SetFrameLevel(lvl + 1) end
    end

    -- On the BAR, not on the button: a child frame draws above its parent, and a name created on
    -- the button sits UNDER the health bar -- which looks like "the names are missing" with only
    -- the overflowing tail of a long one visible past the cell's edge (seen on the beta, 17 Sep).
    -- MISSING HEALTH, on the right: how much this person needs. Arn: "any other information we can
    -- put on frames like missing health or %". Health is a secret for everyone but you, always -
    -- not just in combat - so the subtraction cannot be ours. UnitHealthMissing does it client-
    -- side, and C_StringUtil.TruncateWhenZero turns a 0 into nothing at all, which is "hide it at
    -- full health" with no `> 0` for us to be refused. /bish text measured both painting in a
    -- fight (20 Sep). (And since 21 Sep, a percentage instead if the player would rather:
    -- FG.PaintText.)
    --
    -- TWO LINES, NOT ONE. Arn, 21 Sep, looking at "Kumlust S 38": "names and health are sharing
    -- the same line maybe we put them in different lines". They shared one line and the name was
    -- cut short to make room for the number. Now the name has the top line to itself (up to the
    -- role icon), and the number sits on the bottom line, right-aligned.
    f.htext = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.htext:SetPoint("BOTTOMRIGHT", -3, 4)
    f.htext:SetJustifyH("RIGHT")
    if f.htext.SetTextColor then f.htext:SetTextColor(1, 0.55, 0.55) end

    f.name = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.__nameParent = f.bar        -- dev/forever.lua asserts the label belongs to the bar
    f.name:SetPoint("TOPLEFT", 3, -4)
    f.name:SetPoint("TOPRIGHT", -14, -4)    -- stops short of the role icon in the corner
    f.name:SetJustifyH("LEFT")
    if f.name.SetWordWrap then f.name:SetWordWrap(false) end

    -- THE ROLE, top right, small. Learned from Healium's Forever build (19 Sep 2026) - Arn saw
    -- the icons on its frames and asked for them here. Two things worth copying from it: the
    -- role comes back as a SECRET VALUE like everything else on this client, and the atlas is
    -- fetched through a second call that can be secret too. Both are guarded.
    f.role = f.bar:CreateTexture(nil, "OVERLAY")
    f.role:SetSize(11, 11)
    f.role:SetPoint("TOPRIGHT", -1, -1)
    f.role:Hide()

    if i then FG.frames[i] = f end
    return f
end

--- A CELL FOR WHOEVER YOU HAVE TARGETED, under the grid. A player's request (paszczyszyn, 22 Sep):
--- "Any chance to a separate cell appear for your current target?".
---
--- It is an ordinary cell with the unit token "target", which the client re-points by itself every
--- time you target someone - so it follows along mid-fight, where nothing of ours may move. The
--- client's own unit watch shows it when you have a target and hides it when you do not, which is
--- why there is nothing here that asks whether you have one.
---
--- Built and bound OUT OF COMBAT with everything else; off by default, since a healer watching the
--- grid did not ask for another frame.
function FG.LayoutTarget(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    anchor = anchor or FG.anchor
    if not anchor then return false end
    local d = NS.DB and NS.DB()
    local want = type(d) == "table" and d.target == true and d.shown ~= false
    if not want then
        if FG.target then
            FG.Unwatch(FG.target)
            FG.target.unit = nil
            FG.target:Hide()
        end
        return true, false
    end
    local f = FG.target
    if not f then
        f = FG.Make("Target", anchor)
        FG.target = f
        FG.TargetHandle(f)
    end
    FG.PlaceTarget(f, anchor)
    f:SetSize(FRAME_W, FRAME_H)
    if f.incoming and f.incoming.SetSize then f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2) end
    FG.Bind(f, "target")            -- which arms the mouse binds on it, like any other cell
    if NS.FA and NS.FA.Attach then NS.FA.Attach(f, "target") end
    f:Show()
    return true, true
end

-- WHERE THE TARGET'S CELL SITS. Arn, 23 Sep: "lets do a toggle under grid to the right left or
-- top. and we can give it its own little header where they can drag it where ever they want on
-- screen". So four places against the grid, and a fifth - "free" - the moment you drag it.
FG.TARGET_SPOTS = { under = true, right = true, left = true, top = true, free = true }

function FG.TargetSpot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.targetAt or nil
    return FG.TARGET_SPOTS[at or ""] and at or "under"
end

--- Put it where the player asked. Against the grid, the anchor moves it along with the cells; set
--- free, it is pinned to the screen's centre like the grid itself (FG.Recenter), so it stays where
--- it was dragged whatever the grid does afterwards.
function FG.PlaceTarget(f, anchor)
    f = f or FG.target
    anchor = anchor or FG.anchor
    if not (f and anchor) then return false end
    local at = FG.TargetSpot()
    local d = NS.DB and NS.DB()
    local pos = type(d) == "table" and d.targetPos or nil
    f:ClearAllPoints()
    if at == "free" and type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    elseif at == "right" then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PAD * 2, 0)
    elseif at == "left" then
        f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -(PAD * 2), 0)
    elseif at == "top" then
        -- above the grid's own header, so the two do not sit on each other
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 20)
    else
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(PAD * 2))
    end
    return true, at
end

--- Its own little handle, above the cell: a thin bar you can take hold of. Dragging it sets the
--- spot to "free" and writes where it landed into the macro, the way the grid's header does.
function FG.TargetHandle(f)
    if not f or f.handle then return f and f.handle end
    local h = CreateFrame("Frame", "BiSHealingForeverTargetHandle", f)
    h:SetHeight(8)
    h:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 1)
    h:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 1)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.12, 0.75)

    f:SetMovable(true)
    h:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        f:StartMoving()
        h.moving = true
    end)
    h:SetScript("OnDragStop", function()
        if not h.moving then return end
        h.moving = false
        f:StopMovingOrSizing()
        local d = NS.DB and NS.DB()
        local ok, x, y = FG.CenterOffsetOf(f)
        if ok and type(d) == "table" then
            d.targetAt, d.targetPos = "free", { x = x, y = y }
            FG.PlaceTarget(f)
            if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
        end
    end)
    h:SetScript("OnEnter", function()
        bg:SetColorTexture(0.13, 0.10, 0.19, 0.95)
        if not GameTooltip then return end
        GameTooltip:SetOwner(h, "ANCHOR_TOP")
        GameTooltip:AddLine("drag to move the target cell")
        GameTooltip:AddLine("/bish target under | left | right | top", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function()
        bg:SetColorTexture(0.08, 0.06, 0.12, 0.75)
        if GameTooltip then GameTooltip:Hide() end
    end)
    f.handle = h
    return h
end

-- Tank, healer or damage, as this client will say it. `role` and the enum behind it are both
-- secret values in combat, and asking for an atlas with a secret is an error rather than a blank
-- icon - so each step is checked before the next one is taken.
--
-- The fallback is the old LFG roles sheet, which every client since has carried: an atlas name is
-- a modern thing, and this addon still loads on TBC where GetMicroIconForRoleEnum does not exist.
local ROLE_COORDS = {
    TANK    = { 0,       19 / 64, 22 / 64, 41 / 64 },
    HEALER  = { 20 / 64, 39 / 64,  1 / 64, 20 / 64 },
    DAMAGER = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}

--- The number on the right. Three ways to have it, and every step of each is guarded: nothing
--- here reads the value. It goes from one client call to the next and then to the label, which is
--- the only thing the client allows done with somebody else's health.
---
---   missing  what this person still needs AFTER the heals already on their way, short (3.2K),
---            and nothing at all at full health
---   percent  87%
---   off      nothing
---
--- WHAT WE LEARNED FROM THE FIELD (study, 21 Sep 2026 - EllesmereUI's raid frames, Plater):
---   * UnitHealthMissing(unit, true): the second argument takes off what is already incoming. Two
---     healers looking at one gap stop both filling it.
---   * short AND blank. The two helpers do not compose - each takes a number and returns text, so
---     neither accepts the other's output (/bish text, 20 Sep). The trick is to let the LABEL be the
---     test: paint TruncateWhenZero's answer, and only if the label now holds something, paint the
---     short form over it. A secret may be tested for truthiness - that is the one thing besides
---     painting it that the client allows - and a label given nothing holds nothing.
---   * UnitHealthPercent answers a FRACTION (1 at full) unless given CurveConstants.ScaleTo100.
---   * the % sign is string.format's, which hands a secret number back as secret text - Plater
---     puts its power percent on the screen exactly this way.
--- Each of the three falls back rather than failing: no short form means the number in full, no
--- % sign means the bare number, and no client support at all means a blank.
local function paintMissing(label, unit)
    local asked, deficit = pcall(UnitHealthMissing, unit, true)
    if not asked then asked, deficit = pcall(UnitHealthMissing, unit) end
    if not asked then return false end
    local shaped, text = pcall(C_StringUtil.TruncateWhenZero, deficit)
    if not (shaped and pcall(label.SetText, label, text)) then return false end
    -- BOTH must say "something is there": what the helper gave, and what the label now holds. A
    -- plain "" is nothing (a plain value may be compared); a secret is only ever tested for truth.
    -- If either says nothing, the label keeps what TruncateWhenZero gave it - blank, or in full.
    local function holds(v)
        if v == nil then return false end
        if NS.Secret and NS.Secret(v) then
            local tested, yes = pcall(function() return v and true or false end)
            return (tested and yes) and true or false
        end
        return v ~= "" and v ~= false
    end
    if AbbreviateNumbers and label.GetText and holds(text) then
        local read, held = pcall(label.GetText, label)
        if read and holds(held) then
            local short, s = pcall(AbbreviateNumbers, deficit)
            if short then pcall(label.SetText, label, s) end
        end
    end
    return true
end

local function paintPercent(label, unit)
    if not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100) then return false end
    local asked, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
    if not asked then return false end
    local signed, text = pcall(string.format, "%.0f%%", pct)
    if signed and pcall(label.SetText, label, text) then return true end
    return pcall(label.SetText, label, pct) and true or false
end

--- Which text the cells carry: "missing", "percent" or "off".
function FG.TextMode()
    local d = NS.DB and NS.DB()
    local m = type(d) == "table" and d.text or nil
    if m == "percent" or m == "off" then return m end
    return "missing"
end

function FG.PaintText(f)
    local label, unit = f.htext, f.unit
    if not label then return false end
    local mode = FG.TextMode()
    local done = false
    if unit and mode == "missing" and UnitHealthMissing and C_StringUtil and C_StringUtil.TruncateWhenZero then
        done = paintMissing(label, unit)
    elseif unit and mode == "percent" then
        done = paintPercent(label, unit)
    end
    if not done then label:SetText("") end
    return done
end

function FG.PaintRole(f)
    local icon, unit = f.role, f.unit
    if not icon then return false end
    if not (unit and UnitGroupRolesAssigned) then icon:Hide() return false end

    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    role = ok and NS.Plain(role) or nil
    if not (role and ROLE_COORDS[role]) then icon:Hide() return false end

    if icon.SetAtlas and GetMicroIconForRoleEnum and UnitGroupRolesAssignedEnum then
        local gotEnum, enum = pcall(UnitGroupRolesAssignedEnum, unit)
        enum = gotEnum and NS.Plain(enum) or nil
        if enum then
            local gotAtlas, atlas = pcall(GetMicroIconForRoleEnum, enum)
            if gotAtlas and type(atlas) == "string" and atlas ~= "" then
                local drew = pcall(icon.SetAtlas, icon, atlas)
                if drew then icon:Show() return true, role end
            end
        end
    end

    -- NOTE THE DOUBLED BACKSLASHES. Lua 5.1 drops an escape it does not recognise instead of
    -- complaining, so "Interface\LFGFrame\..." loads perfectly and asks the client for
    -- "InterfaceLFGFrameUI-LFG-ICON-ROLES" - a path that does not exist, and an icon that never
    -- appears, with nothing anywhere saying why. (Written wrong here first, 19 Sep 2026.)
    icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
    icon:SetTexCoord(unpack(ROLE_COORDS[role]))
    icon:Show()
    return true, role
end

--- Point a cell at a unit: the secure attributes and the click-casts. OUT OF COMBAT ONLY -- every
--- SetAttribute here is refused once the lockdown is on, so this is called from the roster events
--- and never from the update loop.
function FG.Bind(f, unit)
    if InCombatLockdown and InCombatLockdown() then return false end
    f.unit = unit
    f:SetAttribute("unit", unit)
    -- What a click MEANS belongs to Forever/Mouse.lua - every button, every modifier, in one
    -- place the player can see and change. The grid used to set three of them here, and then the
    -- mouse's own pass wiped whatever it did not know about. One owner.
    if NS.FM and NS.FM.ApplyTo then NS.FM.ApplyTo(f) end
    if RegisterUnitWatch then RegisterUnitWatch(f) end
    if f.name then f.name:SetText(FG.ShortName(unit)) end
    return true
end

--- A cell is 84 wide: "Longnamedhealer-Realmone" does not fit and the realm never matters in a group.
--- Realm off, then cut to what the cell holds.
function FG.ShortName(unit)
    local name = UnitName and UnitName(unit)
    -- A HIDDEN NAME IS PAINTED WHOLE. It still answers type() == "string", so the cut below would
    -- index it and throw - taking the layout down with it. A label may be handed a secret; a
    -- pattern may not. So it goes to the cell as it came, surname and all.
    if NS.Secret(name) then return name end
    if name == nil then name = unit end
    if type(name) ~= "string" then return tostring(unit) end
    name = name:match("^([^-]+)") or name
    -- FIRST NAME ONLY. Forever characters can have a surname ("Kumlust Surname"), and cutting at
    -- nine letters left "Kumlust S" - a stray initial nobody reads. Arn: "get rid of last names".
    name = name:match("^%s*(%S+)") or name
    if #name > 12 then name = name:sub(1, 12) end
    return name
end

--------------------------------------------------------------------- layout --

--- Take a cell off the client's unit watch (RegisterUnitWatch), so a Hide() stays hidden.
function FG.Unwatch(f)
    if f and UnregisterUnitWatch then pcall(UnregisterUnitWatch, f) end
end

--- Where the cells sit. Blocked in combat by the client, so it answers false there and the caller
--- tries again when the fight ends.
function FG.Layout(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    -- The anchor is optional now: the pyramid's Relayout hands this grid the job on a Forever
    -- client and has no idea what our anchor is called.
    anchor = anchor or FG.anchor
    if not anchor then return false end
    local roster = FG.Roster()
    -- "the frames" is one switch on both clients: /bish hide means this grid too
    --
    -- HIDDEN MEANS THE WATCH STOPS TOO. Each cell is under RegisterUnitWatch, which is the
    -- client showing the cell whenever its unit exists - so f:Hide() lasted until the next tick
    -- and the cell came straight back. Arn, 21 Sep: "show the cells does nothing, it just keep
    -- showing up". The watch is lifted, the cells hidden, and the anchor with them (the header
    -- lives on it), so nothing is left on screen but the minimap button to bring it back.
    local d = NS.DB and NS.DB()
    if type(d) == "table" and d.shown == false then
        for _, f in ipairs(FG.frames) do FG.Unwatch(f); f:Hide() end
        if anchor.Hide then anchor:Hide() end
        return true, 0
    end
    if anchor.Show then anchor:Show() end
    local pyramid = type(d) == "table" and d.layout == "pyramid"
    local across = type(d) == "table" and d.layout == "rows"      -- groups across, not down
    local place, span, grid, groups = nil, 0, nil, 0
    if not pyramid then
        roster, grid, groups = FG.ByGroup(roster)
    end
    if pyramid then
        roster = FG.ByRole(roster)
        place = FG.Pyramid(#roster)
        -- the widest row sets the width, and every other row is centred in it
        for _, p in ipairs(place) do
            local w = p.wide and FULL_W or HALF_W
            local rowW = p.count * w + (p.count - 1) * PAD
            if rowW > span then span = rowW end
        end
    end
    for i, unit in ipairs(roster) do
        local f = FG.frames[i] or FG.Make(i, anchor)
        f:ClearAllPoints()
        local w = FRAME_W
        if pyramid then
            local p = place[i]
            w = p.wide and FULL_W or HALF_W
            local rowW = p.count * w + (p.count - 1) * PAD
            local x = (span - rowW) / 2 + (p.col - 1) * (w + PAD)
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, -(p.row - 1) * (FRAME_H + PAD))
        else
            -- ACROSS, OR DOWN. A player's request (paszczyszyn, 22 Sep): "Can we have an option to
            -- setup cells? vertically and horizontally?". A group is a COLUMN by default - five
            -- names down, groups side by side. Turned, the same group is a ROW: five names across,
            -- groups stacked. Nothing else changes, so the sorting, the pets column and the spare
            -- cells are all still the ones ByGroup worked out - only where they are put.
            local g = grid[i]
            local col, row = g.col, g.row
            if across then col, row = row, col end
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT",
                       (col - 1) * (FRAME_W + PAD), -(row - 1) * (FRAME_H + PAD))
        end
        f:SetSize(w, FRAME_H)
        -- THE INCOMING BAR FOLLOWS THE CELL. It was sized once, at birth, to one ordinary cell -
        -- so on a full-width apex cell the pale "heal on its way" stripe would have stopped dead
        -- halfway across, which reads as "only half of this is coming".
        if f.incoming and f.incoming.SetSize then f.incoming:SetSize(w - 2, FRAME_H - 2) end
        FG.Bind(f, unit)
        -- the aura markers ride the same out-of-combat moment as the secure attributes: the
        -- container is told its unit here and then draws by itself for the whole fight
        if NS.FA and NS.FA.Attach then NS.FA.Attach(f, unit) end
        -- the mouse binds, if the player has set any: they replace the defaults above
        if NS.FM and NS.FM.ApplyTo then NS.FM.ApplyTo(f) end
        FG.byUnit[unit] = f
        f:Show()
    end
    for i = #roster + 1, #FG.frames do
        local f = FG.frames[i]
        if f then
            -- a spare cell keeps its old unit attribute; under the watch it would reappear the
            -- moment that unit existed again, so the watch goes with the unit
            f.unit = nil
            FG.Unwatch(f)
            f:Hide()
        end
    end

    FG.LayoutTarget(anchor)         -- the target's own cell, under the grid, when it is wanted

    -- AND THE WHEEL, which is not a cell attribute and so was never armed here.
    --
    -- Arn, 19 Sep 2026: "the binds saved and the window where the bind saved but they dont do
    -- anything on the frame, last time i had to drag the same spell again to the bind and then it
    -- worked". His one saved bind was `wheelup`. Buttons 1-5 are secure attributes written onto
    -- each cell by ApplyTo above, so those came back with the layout - but the wheel is a
    -- BINDING, armed by FM.ApplyWheel, and the only thing that called it was dropping a spell.
    -- So a bind that survived the reload perfectly did nothing until it was dragged again.
    if NS.FM and NS.FM.ApplyWheel then NS.FM.ApplyWheel(anchor) end

    -- The anchor becomes the size of the grid it holds, so the header on top of it spans the
    -- cells rather than the 84 pixels of one. Out of combat only, like everything else here.
    local n = #roster
    if n > 0 then
        local w, rows
        if pyramid then
            w, rows = span, place[n].row
        else
            local deep = 0            -- the longest group
            for _, g in ipairs(grid) do if g.row > deep then deep = g.row end end
            -- turned on its side, the longest group is the WIDTH and the groups are the rows
            if across then
                rows, w = groups, deep * (FRAME_W + PAD) - PAD
            else
                rows, w = deep, groups * (FRAME_W + PAD) - PAD
            end
        end
        anchor:SetSize(w, rows * (FRAME_H + PAD) - PAD)
        -- and the prompt is trimmed to the header it now sits in: one cell wide is 84 pixels, and
        -- a word that does not fit is a word printed over whatever is beside it
        local h = FG.header
        if h and h.con then h.con.width = math.max(40, w - 10) end
        if h and h.title and not h.con then
            local T = _G.BiSTheme
            if T and T.Fit then T.Fit(h.title, "BiS> Healing", math.max(40, w - 10)) end
        end
    end
    return true, #roster
end

--- ONE LAYOUT AT A TIME. Laying the cells out arms the mouse on them, and the mouse's first read
--- of the macro happens right there - at login, INSIDE the first layout. The macro can say "hidden"
--- (Keep.lua, H=1), which asks for a layout of its own: that inner one hid every cell, and then
--- the outer one carried on and showed them all again. So a layout asked for mid-layout waits, and
--- runs once the first has finished - with the setting it asked for already in place.
local layoutOnce = FG.Layout
function FG.Layout(anchor)
    if FG.laying then
        FG.layAgain = true
        return false
    end
    FG.laying = true
    local ok, done, n = pcall(layoutOnce, anchor)
    FG.laying = false
    if FG.layAgain then
        FG.layAgain = false
        return FG.Layout(anchor)
    end
    if not ok then error(done, 0) end
    return done, n
end

---------------------------------------------------------------------- paint --

local CLASS_COLOR = {
    SHAMAN = { 0.00, 0.44, 0.87 }, PRIEST = { 1.00, 1.00, 1.00 }, DRUID  = { 1.00, 0.49, 0.04 },
    PALADIN = { 0.96, 0.55, 0.73 }, WARRIOR = { 0.78, 0.61, 0.43 }, ROGUE = { 1.00, 0.96, 0.41 },
    MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, HUNTER = { 0.67, 0.83, 0.45 },
}
local DEAD = { 0.35, 0.10, 0.10 }

-- COLOUR BY HEALTH, when the player picks it over class colour. We may not compare someone's
-- health to anything, so we cannot say "below 35%, go red" ourselves. The client can: handed a
-- colour curve, UnitHealthPercent answers with the COLOUR at that point on it instead of a number
-- (EllesmereUI's raid frames and Plater both do this; Plater builds its curves exactly like this).
-- A step curve on the 0-to-1 fraction: red from empty, amber from 35%, green from 70%.
-- The red, green and blue that come back may be secret; they go straight to the bar.
local HEALTH_STEPS = { { 0, 0.85, 0.15, 0.15 }, { 0.35, 0.95, 0.70, 0.15 }, { 0.70, 0.20, 0.75, 0.30 } }
local healthCurve
local function curve()
    if healthCurve ~= nil then return healthCurve or nil end
    healthCurve = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and Enum and Enum.LuaCurveType) then
        return nil
    end
    local ok, c = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not c then return nil end
    local built = pcall(function()
        c:SetType(Enum.LuaCurveType.Step)
        for _, p in ipairs(HEALTH_STEPS) do c:AddPoint(p[1], CreateColor(p[2], p[3], p[4], 1)) end
    end)
    if built then healthCurve = c end
    return healthCurve or nil
end

--- Paint the bar by how much health is left. False if the client could not, so the caller can
--- fall back to the class colour rather than leave the bar whatever it was.
function FG.PaintByHealth(f)
    local c = UnitHealthPercent and curve()
    if not c then return false end
    local asked, col = pcall(UnitHealthPercent, f.unit, true, c)
    if not asked or not col then return false end
    local ok = pcall(function() f.bar:SetStatusBarColor(col:GetRGB()) end)
    return ok and true or false
end

--- Everything a cell may change DURING a fight. Nothing here reads a number back: the health
--- value goes from the client into the bar and is never touched on the way.
function FG.Paint(f)
    local unit = f.unit
    if not unit then return end

    -- max first. The player's own max is readable; everyone else's is secret, and whether a
    -- StatusBar accepts a secret max is not yet measured -- so ask once, and if the client
    -- refuses, leave the bar on 0..1 and let SetValue place it as best it can.
    -- ASK, DO NOT LEARN BY FAILING. This used to find out whether a secret max was allowed by
    -- handing one over and watching for an error. The client will simply say: C_Secrets has a
    -- question for every kind of secret, and ShouldUnitHealthMaxBeSecret is this one. (Learned
    -- from ForeverAuras 0.1.114, 20 Sep 2026 - though our own BiSProbe census had listed all 27
    -- C_Secrets calls for days. Probing the client and then not reading what came back is a
    -- more embarrassing way to be wrong than not probing at all.)
    --
    -- The pcall stays as the floor: an API that answers "no" and then refuses anyway is still
    -- an error we must not take, and TBC has no C_Secrets to ask.
    if FG.maxOK and C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret then
        local asked, hidden = pcall(C_Secrets.ShouldUnitHealthMaxBeSecret)
        if asked and NS.Plain(hidden) == true then FG.maxOK = false end
    end
    if FG.maxOK then
        local ok = pcall(f.bar.SetMinMaxValues, f.bar, 0, UnitHealthMax(unit))
        if not ok then FG.maxOK = false end
    end
    f.bar:SetValue(UnitHealth(unit))     -- the one legal thing to do with a secret number

    if FG.PaintRole then FG.PaintRole(f) end
    if FG.PaintText then FG.PaintText(f) end

    -- INCOMING HEALS, on the same scale as the health bar so the two read as one line. The value
    -- may be secret and is handed over untouched, exactly like the health above it.
    if f.incoming and UnitGetIncomingHeals then
        local ok, inc = pcall(UnitGetIncomingHeals, unit)
        if ok then
            if FG.maxOK then pcall(f.incoming.SetMinMaxValues, f.incoming, 0, UnitHealthMax(unit)) end
            f.incoming:SetValue(NS.Secret(inc) and inc or (inc or 0))
        end
    end

    -- A CLASS AND A DEAD FLAG CAN BOTH BE SECRET, and both are used in a test below: one indexes
    -- a table, the other sits in an `if`. Either refuses outright when the client is hiding it,
    -- so both are asked about first. NS.Plain answers nil rather than the value when it is secret.
    local class = NS.Plain(select(2, UnitClass(unit)))
    local c = CLASS_COLOR[class or ""] or { 0.2, 0.7, 0.3 }
    local dead = UnitIsDeadOrGhost and NS.Plain(UnitIsDeadOrGhost(unit))
    if dead then c = DEAD end
    local d = NS.DB and NS.DB()
    local byHealth = type(d) == "table" and d.color == "health"
    if dead or not (byHealth and FG.PaintByHealth(f)) then
        f.bar:SetStatusBarColor(c[1], c[2], c[3])
    end

    -- THE CLASS MOVES TO THE NAME when the bar is busy saying how hurt they are. Arn, 21 Sep: "if
    -- they turn on bar color by health lets do names class colors". In class-colour mode the bar
    -- already says it, so the name stays white. A class the client is hiding is white either way:
    -- no colour is better than a guessed one.
    if f.name and f.name.SetTextColor then
        local nc = byHealth and CLASS_COLOR[class or ""] or nil
        if nc then f.name:SetTextColor(nc[1], nc[2], nc[3]) else f.name:SetTextColor(1, 1, 1) end
    end

    -- Range. NOT UnitInRange: on Forever that returns a secret BOOLEAN, which cannot even be
    -- used in an `if` -- the client refuses the boolean test itself. IsSpellInRange answers
    -- plainly, and anything that is not a clear "no" leaves the cell at full alpha rather than
    -- dimming someone who is actually reachable.
    --
    -- AND NOT THE GLOBAL EITHER, on this client. The API fence caught it on 19 Sep 2026: the
    -- 1.60.1 census has C_Spell.IsSpellInRange and no bare IsSpellInRange, so this was guarded by
    -- `if IsSpellInRange then` and quietly never ran - nobody was ever dimmed. The old addon had
    -- a fallback pair elsewhere in its 5,000 lines, which is what kept the fence quiet.
    --
    -- The modern one answers true/false, the old one 1/0. Both are handled, because "which shape
    -- does this client answer in" is not a question worth a version check.
    local reach = 1
    local range = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    local spell = NS.FM and NS.FM.RangeSpell and NS.FM.RangeSpell()
    if range and spell then
        local ok, r = pcall(range, spell, unit)
        if ok and (r == 0 or r == false) then reach = 0.45 end
    end
    f:SetAlpha(reach)
end

--------------------------------------------------------------------- driving --

local THROTTLE = 0.1

--- Build the grid and keep it fed. Called once, from Core.lua, at login.
---
--- It used to begin `if not NS.SECRET then return false end` - stand aside, this client keeps the
--- pyramid. There is no pyramid any more (19 Sep 2026, tag `tbc-final`), so the grid runs on
--- whatever client it finds. On one that answers freely the cells simply get numbers they are
--- allowed to read, and draw the same bars.
--- Where the grid sits, kept in the saved variables. Arn, 19 Sep 2026: "lets add a our header to
--- this so we can drag and move". The anchor had no handle at all - the cells were the only thing
--- on screen, and a secure button cannot be dragged without taking its click away.
-- SCALE (Arn, 20 Sep: "a slider that lets people set the scale of the frames, this is perfect for
-- me but some people like larger smaller"). The anchor is scaled, so the cells, the header and the
-- gaps between them all grow and shrink together.
FG.SCALE_MIN, FG.SCALE_MAX, FG.SCALE_STEP = 0.6, 1.6, 0.05

function FG.ClampScale(v)
    v = tonumber(v) or 1
    if v < FG.SCALE_MIN then v = FG.SCALE_MIN elseif v > FG.SCALE_MAX then v = FG.SCALE_MAX end
    return math.floor(v * 100 + 0.5) / 100          -- 0.8500000001 is not a setting anyone chose
end

--- Set the scale, and KEEP THE GRID WHERE IT IS. A saved offset is measured in the frame's own
--- scaled units, so scaling a frame anchored 192 from the right edge moves it: at 150% it would
--- slide to 288 away. The offset is converted by old/new so the grid stays put on screen.
---
--- Out of combat only - scaling a parent resizes its secure children, which the lockdown refuses.
--- In combat the setting is kept and applied when the fight ends.
function FG.SetScale(v, fromMacro)
    local s = FG.ClampScale(v)
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.scale = s end
    -- KEPT IN THE MACRO, beside the binds - the only thing on this client that survives a restart.
    -- Not when the value CAME from the macro: that is a read, and writing back mid-read would store
    -- a half-restored mouse. The macro refuses in combat anyway; the fight's end re-applies the
    -- scale through here and writes it then.
    local function keep()
        if not fromMacro and NS.FK and NS.FK.Save and type(d) == "table" then NS.FK.Save(d.binds or {}) end
    end
    local a = FG.anchor
    if not (a and a.SetScale) then keep() return true, s end
    if InCombatLockdown and InCombatLockdown() then return false, s end
    local old = (a.GetScale and a:GetScale()) or 1
    if old == s then keep() return true, s end
    local ok, point, rel, relPoint, x, y = pcall(a.GetPoint, a, 1)
    a:SetScale(s)
    if ok and point then
        a:ClearAllPoints()
        a:SetPoint(point, rel, relPoint, (x or 0) * old / s, (y or 0) * old / s)
        FG.SavePos()
    end
    keep()
    return true, s
end

--- Pin the grid by its CENTRE, to the centre of the screen, wherever the drag left it. A drag
--- ends on whatever corner the client chose; one kind of point is what lets the position be
--- written into the macro as two numbers (Keep.lua) - and read back after a restart. SetPoint
--- offsets are in the frame's own scale, so the screen's centre is converted into it first.
--- Where a frame's centre is, measured from the middle of the screen, in that frame's own scale.
--- Shared by the grid and the target cell: both are dragged, and both are written into the macro
--- as two numbers (Keep.lua).
function FG.CenterOffsetOf(f)
    if not (f and f.GetCenter and UIParent and UIParent.GetCenter) then return false end
    local ok, cx, cy = pcall(f.GetCenter, f)
    local uok, ux, uy = pcall(UIParent.GetCenter, UIParent)
    if not (ok and uok and cx and ux) then return false end
    local fs = (f.GetEffectiveScale and f:GetEffectiveScale()) or (f.GetScale and f:GetScale()) or 1
    local us = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local k = us / fs
    return true, math.floor(cx - ux * k + 0.5), math.floor(cy - uy * k + 0.5)
end

function FG.Recenter()
    local a = FG.anchor
    local ok, x, y = FG.CenterOffsetOf(a)
    if not ok then return false end
    a:ClearAllPoints()
    a:SetPoint("CENTER", UIParent, "CENTER", x, y)
    return true, x, y
end

function FG.SavePos()
    local a = FG.anchor
    if not a or not a.GetPoint then return nil end
    local ok, point, _, rel, x, y = pcall(a.GetPoint, a)
    if not ok or not point then return nil end
    local d = NS.DB and NS.DB()
    if type(d) ~= "table" then return nil end
    d.gridPos = { point = point, rel = rel, x = x, y = y }
    return d.gridPos
end

function FG.RestorePos()
    local a = FG.anchor
    if not a then return end
    local d = NS.DB and NS.DB()
    local p = type(d) == "table" and d.gridPos or nil
    a:ClearAllPoints()
    if type(p) == "table" and p.point then
        a:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
    else
        -- CENTRE MEANS CENTRE. This was CENTER,-260,-120 - 260 left and 120 DOWN - so `/bish
        -- center` dropped the grid into the action bars and Arn asked how to get it back:
        -- "center it puts it down there". A command named `center` that does not centre is a
        -- command nobody can use to rescue a window they cannot see, which is the only reason
        -- anyone types it. Over the character is fine; that is what dragging the header is for.
        a:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

--- The handle: the family's header, sitting on top of the first row.
---
--- It moves the ANCHOR, not itself - every cell hangs off the anchor, so the whole grid follows.
--- OUT OF COMBAT ONLY: the cells are secure frames and the client refuses to move their parent
--- once the lockdown is on. Trying anyway is the kind of thing that throws in the middle of a
--- pull, so the drag simply does not start and the header says why.
local function makeHeader(anchor)
    local h = CreateFrame("Frame", "BiSHealingForeverHeader", anchor)
    h:SetHeight(16)
    h:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    h:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 2)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.12, 0.85)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 5, 0)
    -- the prompt every BiS window wears, when BiSTheme is loaded; a plain word when it is not
    local T = _G.BiSTheme
    if T and T.Console then
        h.con = T.Console(title, { width = 120, size = 10 })
        h.con:Set("name", "Healing")
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(0.2, function()
                if h:IsShown() and h.con and h.con.Paint then h.con:Paint() end
            end)
        end
    else
        title:SetText("BiS> Healing")
        if T and T.rgb then title:SetTextColor(T.rgb("accent")) end
    end

    h.title = title

    anchor:SetMovable(true)
    h:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        anchor:StartMoving()
        h.moving = true
    end)
    h:SetScript("OnDragStop", function()
        if not h.moving then return end
        h.moving = false
        anchor:StopMovingOrSizing()
        FG.Recenter()
        FG.SavePos()
        -- AND INTO THE MACRO. A saved variable does not survive a restart on this client, so the
        -- grid came back in the middle at every login (Arn, 21 Sep). Keep.lua writes it beside
        -- the binds; a drag always ends out of combat, which is when the client allows that.
        local d = NS.DB and NS.DB()
        if NS.FK and NS.FK.Save and type(d) == "table" then NS.FK.Save(d.binds or {}) end
    end)
    -- THE HINT IS A TOOLTIP, not a second label. A "drag" caption on the right printed straight
    -- through the prompt's rotating word on a header the width of one cell (seen in game, 19 Sep):
    -- "BiS> Hrsalinge". Two things sharing 84 pixels is not a layout, and a tooltip costs none.
    h:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.13, 0.10, 0.19, 0.95)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if InCombatLockdown and InCombatLockdown() then
            GameTooltip:AddLine("not while the fight is on", 0.94, 0.55, 0.69)
            GameTooltip:AddLine("the cells are secure frames; the client will not move them now",
                                0.59, 0.56, 0.68)
        else
            GameTooltip:AddLine("drag to move the grid", 0.73, 0.50, 1.00)
            GameTooltip:AddLine("/bish center puts it back", 0.59, 0.56, 0.68)
        end
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function()
        bg:SetColorTexture(0.08, 0.06, 0.12, 0.85)
        if GameTooltip then GameTooltip:Hide() end
    end)

    FG.header = h
    return h
end

function FG.Start()
    if FG.anchor then return true end

    local anchor = CreateFrame("Frame", "BiSHealingForeverAnchor", UIParent)
    -- ABOVE THE ACTION BARS. No strata was ever set, so the grid sat at the default and drew in
    -- among the bars - Arn, with a raid up: "its behind all this junk". A healing grid you cannot
    -- see is not a healing grid, and the header you would drag to move it was buried with it.
    -- HIGH is above the bars and bags and below DIALOG and tooltips, so nothing it needs to sit
    -- under is covered.
    if anchor.SetFrameStrata then anchor:SetFrameStrata("HIGH") end
    anchor:SetSize(FRAME_W, FRAME_H)
    FG.anchor = anchor
    local ds = NS.DB and NS.DB()
    if anchor.SetScale then anchor:SetScale(FG.ClampScale(type(ds) == "table" and ds.scale or 1)) end
    FG.RestorePos()
    makeHeader(anchor)

    local since, pending = 0, true
    anchor:SetScript("OnUpdate", function(_, dt)
        since = since + dt
        if since < THROTTLE then return end
        since = 0
        if pending and FG.Layout(anchor) then pending = false end   -- retried until out of combat
        for _, f in ipairs(FG.frames) do
            if f.unit and f:IsShown() then FG.Paint(f) end
        end
        -- the target's cell is not in that list (it belongs to no group), and its NAME changes
        -- under it every time you target someone else, so it is repainted here by name as well
        local t = FG.target
        if t and t.unit and t:IsShown() then
            if t.name then t.name:SetText(FG.ShortName("target")) end
            FG.Paint(t)
        end
    end)

    local ev = CreateFrame("Frame")
    -- SPELLS_CHANGED sits in a list of roster events because of WHEN the book fills in. At login
    -- the client has not answered the spellbook yet, so the seeding finds nothing to seed, the
    -- cells are built with no spell on them, and the book arriving moments later used to change
    -- nothing: the mouse stayed dead until the player dragged a spell in by hand. Arn, twice -
    -- "the binds saved but they dont do anything on the frame, last time i had to drag the same
    -- spell again", and then "reloaded no binds". Asking again when the book answers is the whole
    -- fix; a relayout re-seeds and re-applies every cell on its way through.
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
                         "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "UPDATE_MACROS", "UNIT_PET",
                         "PLAYER_ROLES_ASSIGNED", "ROLE_POLL_BEGIN" }) do
        pcall(ev.RegisterEvent, ev, e)      -- an event this client does not know must not abort the file
    end
    ev:SetScript("OnEvent", function(_, event)
        pending = true                      -- the update loop relays out when the lockdown lets it
        -- a bind changed mid-fight is queued, not lost: the moment the lockdown lifts it lands
        if event == "PLAYER_REGEN_ENABLED" and NS.FM and NS.FM.pending then NS.FM.Apply() end
        -- a scale changed mid-fight waits for this moment
        if event == "PLAYER_REGEN_ENABLED" then
            local dd = NS.DB and NS.DB()
            if type(dd) == "table" and dd.scale then FG.SetScale(dd.scale) end
        end
        -- the macro list filling in late: what is on the mouse may be our guess, not their binds
        if event == "UPDATE_MACROS" and NS.FM and NS.FM.Reconsider then NS.FM.Reconsider() end
    end)
    FG.events = ev
    if NS.FB and NS.FB.Start then NS.FB.Start() end   -- the between-pulls brain, step 2
    return true
end

-- Booted by Core.lua at login. This file used to arm itself, because for two days it WAS the
-- addon on this client and there was no core to do it.
