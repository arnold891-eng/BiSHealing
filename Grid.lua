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
-- the little bar on top of the target cell and the tot cell (FG.CellHeader). Two pixels shorter
-- than the grid's own 16, so the block reads as hanging off the grid rather than competing with it.
local HEADER_H, HEADER_LIFT = 14, 1
-- the grid's own bar, and how far it floats above the anchor (makeHeader)
local GRID_HEADER_H, GRID_HEADER_LIFT = 16, 2
-- EVERY GAP IN THE BLOCK IS THE GRID'S OWN PAD. Arn, 23 Sep, looking at the two of them lined up:
-- "make sure all the windows line up". The target and tot cells had twice the gap between them
-- that two grid columns have, which made the block three pixels wider than the grid beneath it -
-- and on the pyramid, where one wide cell is exactly two columns and the gap, that mismatch was
-- the whole difference between "lined up" and "nearly".
--- THE WORD AFTER "BiS>". Arn, 23 Sep: "BiS> always stays . we then cycle when nothing is
--- happening keep healing , when combat starts switch to regen mode and the % and the glow".
--- So one word, never two labels fighting over an 84 pixel bar: the addon's name while nothing is
--- happening, and what your mana is doing once the fight starts.
---
--- AND IT FITS THE BAR IT IS IN. Arn, 23 Sep, on a party grid: "in the regular down toggel the
--- regen gets cut off" - the header is as wide as the grid, one group down is 84 pixels, and
--- "BiS> regen 62%" came out as "BiS> regen ...". The client trims from the right, so what it
--- throws away is always the number, which is the only part worth reading.
---
--- So on a narrow bar each word has a short form - "62%" and "no WS" - and the header's tooltip
--- carries the long one. `width` is the bar's, in pixels; nothing passed means plenty of room.
local NARROW = 120                      -- a bar one group wide (84) plus a little; two groups fit

function FG.HeaderWord(width)
    local short = type(width) == "number" and width > 0 and width < NARROW
    local fighting = InCombatLockdown and InCombatLockdown()
    -- IN A FIGHT, THE MANA. Between them, the buff you keep forgetting (Arn, 23 Sep: "like i am
    -- always forgetting about watershield"), which the client will only answer about out of
    -- combat - so what it last said is what is shown, and a shield that fell off mid-pull is the
    -- first thing the header says when the fight ends.
    if fighting then
        local FR = NS.FR
        return (FR and FR.Text and FR.Text(short)) or "Healing"
    end
    local FS = NS.FS
    local word = FS and FS.Word and FS.Word(short)
    return word or "Healing"
end
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
-- FOUR WIDTHS DOWN THE PYRAMID, all of them dividing ONE span, so no row drifts against another.
-- Arn, 30 Sep, looking at a 40-man in tanks mode: "third row max 4 cells, 4th row max 4 cells,
-- 5th row and below 8 cells half size of 3rd and 4th cell".
--
--   row 1      1 cell   at FULL_W    the apex, two ordinary cells wide
--   row 2      2 cells  at FULL_W
--   rows 3-4   4 cells  at MID_W     = an ordinary cell
--   rows 5+    8 cells  at TAIL_W    = half of one, which is what he asked for
--
-- SPAN is the width of row 2 and every row fits inside it: 2 FULL_W and the gap between them.
-- MID_W and TAIL_W are worked out FROM the span rather than guessed, so four mediums and eight
-- smalls both come to exactly the same line as the two cells above them. Before this the shape
-- was {1, 2, 6} and the sixes were ordinary cells, which made every row below the second wider
-- than the pyramid it was supposed to sit in.
local FULL_W = 2 * FRAME_W + PAD        -- exactly two ordinary cells and the gap between them
local SPAN   = 2 * FULL_W + PAD         -- the widest row: what everything else divides
local MID_W  = math.floor((SPAN - 3 * PAD) / 4)
local TAIL_W = math.floor((SPAN - 7 * PAD) / 8)
local SHAPE  = { 1, 2, 4, 4 }           -- cells in each row; rows past the last repeat TAIL
local WIDTH  = { FULL_W, FULL_W, MID_W, MID_W }
local TAIL   = 8
local HALF_W = FRAME_W                  -- the ordinary cell, still what a non-pyramid grid uses
-- TANKS, THEN DAMAGE, THEN THE HEALERS AT THE BOTTOM. Arn, 23 Sep: "when we arrange by tanks.
-- lets do tanks dps and healers at the bottom". The healers were second when the pyramid was
-- built; in a fight the people you watch hardest are the tank and whoever is standing in the
-- fire, and your fellow healers are the ones you glance at last.
local ROLE_RANK = { TANK = 1, DAMAGER = 2, HEALER = 3 }

-- MELEE UP TOP, CASTERS AT THE BOTTOM. Arn, 30 Sep: "favor melee classes up top and caster at the
-- bottom of pyramid". It sorts WITHIN a role, so the tanks keep the apex and the healers keep the
-- base; it only decides the order of the damage between them, which is where a raid's melee and
-- its casters actually mix.
--
-- WHY IT IS WORTH ANYTHING TO A HEALER: melee stand in whatever the boss is doing. The people who
-- take avoidable damage are the people you want nearest the top of the shape, where your eye is.
--
-- CLASS, NOT SPEC, because a spec is not a thing this client will tell you about anybody else.
-- A druid or a shaman in the DAMAGE band is feral or enhancement far more often than not - the
-- caster ones are healing, and the role sort has already taken them to the bottom. A hunter is
-- ranged. A class the client is hiding sorts in the middle: no guess either way.
local MELEE_RANK = {
    WARRIOR = 1, ROGUE = 1, PALADIN = 1, DEATHKNIGHT = 1, MONK = 1, DEMONHUNTER = 1,
    DRUID = 1, SHAMAN = 1,
    HUNTER = 3, MAGE = 3, WARLOCK = 3, PRIEST = 3, EVOKER = 3,
}

--- Where each of `n` cells goes: its row, its place in the row, how many share the row, and
--- whether the row is full width. Pure - no frames - so it can be asked without a client.
function FG.Pyramid(n)
    local out, r, i = {}, 1, 1
    while i <= n do
        local cap = SHAPE[r] or TAIL
        local count = math.min(cap, n - i + 1)
        local w = WIDTH[r] or TAIL_W
        for c = 1, count do
            -- `w` is the width this cell is drawn at; `wide` is kept as the old yes/no for
            -- anything still asking "is this one of the big top rows"
            out[i] = { row = r, col = c, count = count, w = w, wide = w == FULL_W }
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
        -- and melee before casters inside the role. The class can be secret in a fight; this runs
        -- out of combat, and an answer we cannot read sorts in the middle rather than guessing.
        local class = UnitClass and NS.Plain(select(2, UnitClass(u))) or nil
        keyed[i] = { unit = u, rank = rank, reach = MELEE_RANK[class or ""] or 2, at = i }
    end
    table.sort(keyed, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        if a.reach ~= b.reach then return a.reach < b.reach end
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
    local pets = FG.PetsInGrid()          -- "own" builds its own block; "off" is nowhere
    -- YOU COME OUT OF THE GRID when you have a cell of your own (paszczyszyn, 25 Sep: "lock
    -- yourself in one spot outside groups"). Left in, you are first in a party and somewhere in
    -- the middle of a raid, and the grid reshapes around you every time the group changes - which
    -- is the thing that made him ask. Two cells for one person is also just two cells.
    local mine = type(d) == "table" and d.me == true
    local function add(u) if UnitExists(u) then out[#out + 1] = u end end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            -- UnitIsUnit is the client's own answer to "is this me", and identity is a thing this
            -- client can decide to hide - so an unreadable answer leaves the cell in the grid
            -- rather than dropping somebody out of the raid by accident.
            if not (mine and UnitIsUnit and NS.Plain(UnitIsUnit(u, "player")) == true) then add(u) end
        end
        if pets then for i = 1, 40 do add("raidpet" .. i) end end
        return out
    end
    if not mine then out[1] = "player" end
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

    -- THE RING IS FOUR LINES, NOT THE BACKDROP. It was the backdrop for about an hour: the bar is
    -- inset by a pixel, so colouring the background showed as an outline - until somebody's health
    -- dropped. A StatusBar only paints up to its value, so the backdrop shows through everywhere
    -- the health ISN'T, and the gold filled the empty half of the cell. Arn, 30 Sep: "only the
    -- outline not the whole cell".
    --
    -- OVERLAY, so the lines sit above the bar rather than behind it, and hidden until a cell is
    -- told it is somebody worth ringing.
    f.edge = {}
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 1, 1, 1)
        t:Hide()
        f.edge[side] = t
    end
    f.edge.top:SetPoint("TOPLEFT")      f.edge.top:SetPoint("TOPRIGHT")      f.edge.top:SetHeight(1)
    f.edge.bottom:SetPoint("BOTTOMLEFT") f.edge.bottom:SetPoint("BOTTOMRIGHT") f.edge.bottom:SetHeight(1)
    f.edge.left:SetPoint("TOPLEFT")     f.edge.left:SetPoint("BOTTOMLEFT")   f.edge.left:SetWidth(1)
    f.edge.right:SetPoint("TOPRIGHT")   f.edge.right:SetPoint("BOTTOMRIGHT") f.edge.right:SetWidth(1)

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
        -- and the cell hanging off it. Hiding a parent hides a child on screen but leaves its own
        -- shown flag alone, and the client's unit watch will happily keep showing it - an invisible
        -- frame that the client still thinks is up is the "show cells does nothing" bug again.
        FG.LayoutToT(nil)
        return true, false
    end
    local f = FG.target
    if not f then
        f = FG.Make("Target", anchor)
        f.mayBeHostile = true          -- whoever you have targeted is as often a mob as a friend
        FG.target = f
        FG.CellHeader(f, "target", f)
    end
    FG.PlaceTarget(f, anchor)
    f:SetSize(FRAME_W, FRAME_H)
    if f.incoming and f.incoming.SetSize then f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2) end
    FG.Bind(f, "target")            -- which arms the mouse binds on it, like any other cell
    if NS.FA and NS.FA.Attach then NS.FA.Attach(f, "target") end
    f:Show()
    FG.LayoutToT(f)
    return true, true
end

--- AND WHOEVER THEY ARE TARGETING, under it. Arn, 23 Sep: "another option that frame will also
--- have target of target with its on header on top BiS>tot the frames are attached to each other".
---
--- ATTACHED MEANS A CHILD, not a second frame that is placed beside the first. It hangs off the
--- target cell, so dragging any part of the block moves all of it, the scale reaches it without
--- being told, and when you have no target at all the client hides the parent and this goes with
--- it - which is the truth, since a target of no target is nothing.
---
--- Its unit token is "targettarget", which the client re-points by itself exactly like "target".
--- The addon reads neither; it says who to watch and the client does the rest.
function FG.LayoutToT(parent)
    if InCombatLockdown and InCombatLockdown() then return false end
    parent = parent or FG.target
    local d = NS.DB and NS.DB()
    local want = type(d) == "table" and d.tot == true and d.target == true and d.shown ~= false
    if not (want and parent) then
        if FG.tot then
            FG.Unwatch(FG.tot)
            FG.tot.unit = nil
            FG.tot:Hide()
            if FG.tot.handle then FG.tot.handle:Hide() end
        end
        return true, false
    end
    local f = FG.tot
    if not f then
        f = FG.Make("ToT", parent)
        f.mayBeHostile = true          -- and their target even more so
        FG.tot = f
        FG.CellHeader(f, "tot", parent)     -- its own bar, but a drag on it moves the whole block
    end
    FG.PlaceToT(f, parent)
    f:SetSize(FRAME_W, FRAME_H)
    if f.incoming and f.incoming.SetSize then f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2) end
    FG.Bind(f, "targettarget")
    if NS.FA and NS.FA.Attach then NS.FA.Attach(f, "targettarget") end
    if f.handle then f.handle:Show() end
    f:Show()
    return true, true
end

--- SIDE BY SIDE, the tot beside the target. Arn, 23 Sep, looking at it stacked: "i want tot to the
--- right of the target window".
---
--- Both bars then sit on one line with a cell under each - two pairs read left to right, instead
--- of a column four frames deep that hung down across the grid the moment the block was dragged
--- anywhere near it (his second screenshot: the tot's cell over the raid's).
---
--- AND IT GROWS AWAY FROM THE GRID, never into it. Parked on the grid's LEFT, a tot added to the
--- right-hand side sits straight on top of the raid - Arn saw it the minute he moved the block
--- over: "when i move it to the left now it should not overlap the tot". So on that one side the
--- pair mirrors, and the block is the same shape either way: the target cell against the grid,
--- the tot on the outside.
function FG.PlaceToT(f, parent)
    f = f or FG.tot
    parent = parent or FG.target
    if not (f and parent) then return false end
    local mirrored = FG.TargetSpot() == "left"
    f:ClearAllPoints()
    if mirrored then
        f:SetPoint("TOPRIGHT", parent, "TOPLEFT", -PAD, 0)
    else
        f:SetPoint("TOPLEFT", parent, "TOPRIGHT", PAD, 0)
    end
    -- its own bar on top of its own cell, level with the target's
    if f.handle then
        f.handle:ClearAllPoints()
        f.handle:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, HEADER_LIFT)
        f.handle:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, HEADER_LIFT)
    end
    return true, mirrored
end

--- A CELL FOR YOURSELF, OUT OF THE GROUP. A player's request (paszczyszyn on CurseForge,
--- 25 Sep 2026): "optional (like target) self target? It may be nice option to lock yourself in
--- one spot outside groups just to get use to it and have it in same spot for solo/or raid
--- groups?".
---
--- THE POINT IS THE SPOT NEVER MOVES, and that is why switching this on takes you OUT of the
--- group grid (FG.Roster). Left in, you would be first in the party and somewhere in the middle
--- of a raid, and the whole grid reshapes around you every time the group does - which is the
--- thing being asked about. One cell for you, in the same place whatever you are in tonight.
---
--- It is the target cell's machinery with a different unit: its own bar, dragged anywhere,
--- shift-clicked round the grid, remembered in the macro. It defaults to the grid's LEFT, because
--- the target block defaults to the top and two blocks in one place is a worse first impression
--- than either of them being in the wrong one.
function FG.LayoutSelf(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    anchor = anchor or FG.anchor
    if not anchor then return false end
    local d = NS.DB and NS.DB()
    local want = type(d) == "table" and d.me == true and d.shown ~= false
    if not want then
        if FG.me then
            FG.Unwatch(FG.me)
            FG.me.unit = nil
            FG.me:Hide()
            if FG.me.handle then FG.me.handle:Hide() end
        end
        return true, false
    end
    local f = FG.me
    if not f then
        f = FG.Make("Me", anchor)
        FG.me = f
        FG.CellHeader(f, "me", f, FG.SELF_KEYS)
    end
    FG.PlaceSelf(f, anchor)
    f:SetSize(FRAME_W, FRAME_H)
    if f.incoming and f.incoming.SetSize then f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2) end
    FG.Bind(f, "player")
    if NS.FA and NS.FA.Attach then NS.FA.Attach(f, "player") end
    if f.handle then f.handle:Show() end
    f:Show()
    return true, true
end

--- LEFT BY DEFAULT, and anywhere a drag puts it. Its own setting, so it and the target cell can
--- sit in different places - one spot setting for both would mean moving one moves the other.
function FG.SelfSpot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.meAt or nil
    return FG.TARGET_SPOTS[at or ""] and at or "left"
end

function FG.PlaceSelf(f, anchor)
    f = f or FG.me
    anchor = anchor or FG.anchor
    local d = NS.DB and NS.DB()
    return FG.PlaceAt(f, anchor, FG.SelfSpot(), type(d) == "table" and d.mePos or nil)
end

-- PETS: THREE ANSWERS, NOT TWO. Arn, 26 Sep: "pets should have 3 setting default is they show up
-- on the main cells, solo cell only pets and off on all cells" - which is paszczyszyn's second
-- request (25 Sep) in the shape Arn wants it: "separete pet group (being able to have different
-- setup's for it and move it alone ... as pets are not that important as players but still being
-- able to cast on them if you have mana to spare)".
--
--   "grid"  a column of their own inside the main grid, which is what `pets on` has always meant
--   "own"   a block of their own, dragged where you like, with nothing but pets in it
--   "off"   nowhere
--
-- The setting used to be a boolean and is still written as one by any macro made before today,
-- so `true` reads as "grid" and `false` as "off".
FG.PET_MODES = { grid = true, own = true, off = true }

function FG.PetsMode()
    local d = NS.DB and NS.DB()
    local m = type(d) == "table" and d.pets or nil
    if m == true then return "grid" end
    if m == false or m == nil then return "off" end
    return FG.PET_MODES[m] and m or "off"
end

function FG.PetsInGrid() return FG.PetsMode() == "grid" end
function FG.PetsOwnBlock() return FG.PetsMode() == "own" end

FG.PET_KEYS = { what = "the pet block", at = "petAt", pos = "petPos",
                spot = function() return FG.PetSpot() end,
                place = function(f) return FG.PlacePets(f) end }

--- UNDER THE GRID by default: a pet block is a column, and a column hanging off the bottom reads
--- as "more of the same, less important", which is what a pet is.
function FG.PetSpot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.petAt or nil
    return FG.TARGET_SPOTS[at or ""] and at or "under"
end

--- Every pet the client will admit to, in the group's order.
function FG.PetRoster()
    local out = {}
    local function add(u) if UnitExists(u) then out[#out + 1] = u end end
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do add("raidpet" .. i) end
        return out
    end
    add("pet")
    for i = 1, 4 do add("partypet" .. i) end
    return out
end

--- A BLOCK OF THEIR OWN, moved as one thing. The single loose cells hang off nothing, but a pet
--- block is several cells that must travel together - so they hang off a frame of their own, and
--- that frame is what the bar drags. The same trick as the grid's anchor, one size down.
function FG.LayoutPets(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    anchor = anchor or FG.anchor
    if not anchor then return false end
    local d = NS.DB and NS.DB()
    local want = FG.PetsOwnBlock() and type(d) == "table" and d.shown ~= false
    local roster = want and FG.PetRoster() or {}
    if #roster == 0 then
        -- no pets, or not wanted: the block goes away entirely rather than sitting there empty
        for _, f in ipairs(FG.petFrames or {}) do
            FG.Unwatch(f)
            f.unit = nil
            f:Hide()
        end
        if FG.petAnchor then FG.petAnchor:Hide() end
        return true, false
    end
    if not FG.petAnchor then
        local a = CreateFrame("Frame", "BiSHealingForeverPets", anchor)
        a:SetSize(FRAME_W, FRAME_H)
        FG.petAnchor = a
        FG.petFrames = {}
        FG.CellHeader(a, "pets", a, FG.PET_KEYS)
    end
    local a = FG.petAnchor
    a:Show()
    if a.handle then a.handle:Show() end
    for i, unit in ipairs(roster) do
        local f = FG.petFrames[i]
        if not f then
            f = FG.Make("Pet" .. i, a)
            FG.petFrames[i] = f
        end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", a, "TOPLEFT", 0, -(i - 1) * (FRAME_H + PAD))
        f:SetSize(FRAME_W, FRAME_H)
        if f.incoming and f.incoming.SetSize then f.incoming:SetSize(FRAME_W - 2, FRAME_H - 2) end
        FG.Bind(f, unit)
        if NS.FA and NS.FA.Attach then NS.FA.Attach(f, unit) end
        f:Show()
    end
    for i = #roster + 1, #FG.petFrames do
        local f = FG.petFrames[i]
        if f then
            f.unit = nil
            FG.Unwatch(f)
            f:Hide()
        end
    end
    -- the block is the size of what is in it, so its bar spans the cells and a drag grabs all of it
    a:SetSize(FRAME_W, #roster * (FRAME_H + PAD) - PAD)
    FG.PlacePets(a, anchor)
    return true, #roster
end

function FG.PlacePets(f, anchor)
    f = f or FG.petAnchor
    anchor = anchor or FG.anchor
    local d = NS.DB and NS.DB()
    return FG.PlaceAt(f, anchor, FG.PetSpot(), type(d) == "table" and d.petPos or nil)
end

-- THE OTHER HEALERS' MANA. Arn, 28 Sep, with a screenshot of EllesmereUI's party frames: "the top
-- thing is the healer mana".
--
-- THIS FILE'S NEIGHBOUR SAYS IT CANNOT BE DONE. Between.lua, since 17 Sep: "`UnitPower` is secret
-- on this client even out of combat, so 'who is low on mana' cannot be answered at all -- not by
-- this addon, not by any addon." That is true about READING it and wrong about SHOWING it, which
-- is the same mistake this whole addon was built to avoid making. EllesmereUI's raid frames do:
--
--     valFS:SetFormattedText("%d", UnitPowerPercent(unit, 0, true, CurveConstants.ScaleTo100))
--
-- with their own note beside it - "which can be secret in combat: it only ever reaches a format
-- setter". The client works the percentage out and draws it. Nothing here ever learns a number.
--
-- HEALERS ONLY, which is the question a healer actually has: is my co-healer about to go dry.
-- A mage's mana is rarely your problem, and a row per mana user in a raid is a second grid.
FG.MANA_KEYS = { what = "the mana block", at = "manaAt", pos = "manaPos",
                 spot = function() return FG.ManaSpot() end,
                 place = function(f) return FG.PlaceMana(f) end }

local MANA_ROW_H = 13

function FG.ManaSpot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.manaAt or nil
    return FG.TARGET_SPOTS[at or ""] and at or "right"
end

--- Everyone in the group the game calls a healer, you included: your own bar is the one you check
--- most, and leaving it out would make the block lie about the group.
function FG.Healers()
    local out = {}
    if not UnitGroupRolesAssigned then return out end
    for _, unit in ipairs(FG.Roster()) do
        if not FG.IsPetUnit(unit) then
            local ok, role = pcall(UnitGroupRolesAssigned, unit)
            if ok and NS.Plain(role) == "HEALER" then out[#out + 1] = unit end
        end
    end
    -- your own cell may be out of the roster (a cell of your own), and you are still a healer
    local d = NS.DB and NS.DB()
    if type(d) == "table" and d.me == true and UnitExists and UnitExists("player") then
        local ok, role = pcall(UnitGroupRolesAssigned, "player")
        if ok and NS.Plain(role) == "HEALER" then table.insert(out, 1, "player") end
    end
    return out
end

--- One row: a name on the left, a percentage on the right. Not a cell - it is not clickable and
--- carries no bars, because this answers one question and an 84 pixel cell already has a job.
local function manaRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(FRAME_W, MANA_ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * MANA_ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.75)
    r.who = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.who:SetPoint("LEFT", 3, 0)
    r.who:SetJustifyH("LEFT")
    r.pct = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.pct:SetPoint("RIGHT", -3, 0)
    r.pct:SetJustifyH("RIGHT")
    if r.pct.SetTextColor then r.pct:SetTextColor(0.45, 0.62, 1) end
    return r
end

--- THE NUMBER IS NEVER READ. UnitPowerPercent's answer goes straight into SetFormattedText, which
--- is the same bargain the health bars have always had: the client knows, we draw. It can be
--- secret, and that changes nothing here - there is no branch for it to break.
function FG.PaintMana(row, unit)
    if not (row and unit) then return false end
    if row.who then row.who:SetText(FG.ShortName(unit)) end
    local pct = UnitPowerPercent
    if not (pct and row.pct) then return false end
    local scale = CurveConstants and CurveConstants.ScaleTo100
    -- ASKED IN ITS OWN pcall. Written as `pcall(setter, fs, "%d%%", pct(unit, ...))` the call is
    -- evaluated BEFORE pcall ever runs, so a client that refuses it throws straight through the
    -- guard that looks like it is covering it - and takes the whole paint loop with it.
    local got, value = pcall(pct, unit, 0, true, scale)
    local drew = got and pcall(row.pct.SetFormattedText, row.pct, "%d%%", value)
    if not drew then
        -- a client that will not hand the value to a setter says nothing rather than a wrong number
        pcall(row.pct.SetText, row.pct, "")
        FG.manaSeen = "refused"
        return false
    end
    FG.manaSeen = "drawn"
    return true
end

function FG.LayoutMana(anchor)
    if InCombatLockdown and InCombatLockdown() then return false end
    anchor = anchor or FG.anchor
    if not anchor then return false end
    local d = NS.DB and NS.DB()
    local want = type(d) == "table" and d.mana == true and d.shown ~= false
    local healers = want and FG.Healers() or {}
    if #healers == 0 then
        if FG.manaAnchor then FG.manaAnchor:Hide() end
        return true, false
    end
    if not FG.manaAnchor then
        local a = CreateFrame("Frame", "BiSHealingForeverMana", anchor)
        a:SetSize(FRAME_W, MANA_ROW_H)
        FG.manaAnchor = a
        FG.manaRows = {}
        FG.CellHeader(a, "mana", a, FG.MANA_KEYS)
    end
    local a = FG.manaAnchor
    a:Show()
    if a.handle then a.handle:Show() end
    for i, unit in ipairs(healers) do
        local row = FG.manaRows[i] or manaRow(a, i)
        FG.manaRows[i] = row
        row.unit = unit
        row:Show()
        FG.PaintMana(row, unit)
    end
    for i = #healers + 1, #FG.manaRows do
        FG.manaRows[i].unit = nil
        FG.manaRows[i]:Hide()
    end
    a:SetSize(FRAME_W, #healers * MANA_ROW_H)
    FG.PlaceMana(a, anchor)
    return true, #healers
end

function FG.PlaceMana(f, anchor)
    f = f or FG.manaAnchor
    anchor = anchor or FG.anchor
    local d = NS.DB and NS.DB()
    return FG.PlaceAt(f, anchor, FG.ManaSpot(), type(d) == "table" and d.manaPos or nil)
end

-- WHERE THE TARGET'S CELL SITS. Arn, 23 Sep: "lets do a toggle under grid to the right left or
-- top. and we can give it its own little header where they can drag it where ever they want on
-- screen". So four places against the grid, and a fifth - "free" - the moment you drag it.
FG.TARGET_SPOTS = { under = true, right = true, left = true, top = true, free = true }
-- shift-clicking the handle walks them, the way round a clock: top, right, under, left. "free"
-- is not in the ring - it is where a drag put it - so a shift-click on a dragged cell brings it
-- back to the grid, starting at the top.
FG.TARGET_RING = { top = "right", right = "under", under = "left", left = "top", free = "top" }
-- the same ring as a list, for walking it looking for a free side
FG.RING = { "top", "right", "under", "left" }

--- WHO IS ALREADY THERE. Arn, 26 Sep, with "BiS> meget" printed across one bar: "if target is
--- already taking up the top and i also turn on me dont overlap them send them to the next
--- available slot".
---
--- Only blocks that are ON the grid can collide; a dragged one is "free", which is wherever the
--- player put it and none of our business. `mine` is the key table of the block asking, so it
--- never counts itself as being in its own way.
function FG.SpotTaken(at, mine)
    local d = NS.DB and NS.DB()
    if type(d) ~= "table" or at == "free" then return false end
    if mine ~= FG.TARGET_KEYS and d.target == true and FG.TargetSpot() == at then return true end
    if mine ~= FG.SELF_KEYS and d.me == true and FG.SelfSpot() == at then return true end
    if mine ~= FG.PET_KEYS and FG.PetsOwnBlock() and FG.PetSpot() == at then return true end
    if mine ~= FG.MANA_KEYS and d.mana == true and FG.ManaSpot() == at then return true end
    return false
end

--- The spot it asked for, or the next one round the ring that nobody is using. Every side taken
--- means it goes where it asked and the player sorts it out with a drag - four blocks and four
--- sides is not a situation this can fix by moving one more thing.
function FG.FreeSpot(at, mine)
    if not FG.SpotTaken(at, mine) then return at end
    local next_ = FG.TARGET_RING[at] or "top"
    for _ = 1, #FG.RING do
        if not FG.SpotTaken(next_, mine) then return next_, at end
        next_ = FG.TARGET_RING[next_] or "top"
    end
    return at
end

--- TOP BY DEFAULT. Arn, 23 Sep: "make it defaut to the top window when it starts at the bottom you
--- cant see the header to move it" - under the grid, the handle sits in the gap between the two and
--- the grid covers it, so the one thing that moves the cell is the one thing you cannot grab.
function FG.TargetSpot()
    local d = NS.DB and NS.DB()
    local at = type(d) == "table" and d.targetAt or nil
    return FG.TARGET_SPOTS[at or ""] and at or "top"
end

--- WHERE A LOOSE CELL GOES, for any of them: the target's, and since 26 Sep your own. Four places
--- against the grid and a fifth - "free" - the moment one is dragged. Written once because there
--- are three cells hanging off this grid now and each copy of these numbers is a copy that can
--- drift by a pixel and look like a bug in the other one.
---
--- THE HEADER IS ALWAYS ON TOP OF ITS OWN CELL. It used to swap to the underside when the cell
--- hung below the grid, because a bare 8 px handle in that gap was covered by the grid and "you
--- cant see the header to move it" (23 Sep). It carries a NAME now - "BiS> target" - and a named
--- bar under the thing it names reads as the label of whatever is beneath it. So the bar stays
--- put and the whole block is pushed clear instead.
function FG.PlaceAt(f, anchor, at, pos)
    if not (f and anchor) then return false end
    f:ClearAllPoints()
    if f.handle then
        f.handle:ClearAllPoints()
        f.handle:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, HEADER_LIFT)
        f.handle:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, HEADER_LIFT)
    end
    if at == "free" and type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y) then
        -- pos is where it sits ON SCREEN; the point is in the cell's own units, which are the
        -- grid's scale, so it is converted back every time it is placed
        local k = FG.ScaleOf(f)
        f:SetPoint("CENTER", UIParent, "CENTER", pos.x / k, pos.y / k)
    -- THE SAME GAP THE CELLS USE, on every side: a block a different distance away from the grid
    -- than the grid's own columns are from each other reads as "nearly lined up", which is worse
    -- than either lined up or plainly apart.
    elseif at == "right" then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", PAD, 0)
    elseif at == "left" then
        f:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -PAD, 0)
    elseif at == "top" then
        -- clear of the grid's own bar, by that same gap; its own bar is above it and needs nothing
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, GRID_HEADER_LIFT + GRID_HEADER_H + PAD)
    else
        -- under the grid, far enough down that ITS bar clears the last row of cells
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(PAD + HEADER_LIFT + HEADER_H))
    end
    return true, at
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
    FG.PlaceAt(f, anchor, at, type(d) == "table" and d.targetPos or nil)
    -- the cell beside it moves with the spot, not just with the layout: a shift-click on either
    -- bar comes through here and nowhere else, and a tot left on the wrong side of a block that
    -- has just moved to the grid's left is a tot sitting on the raid.
    if FG.tot then FG.PlaceToT(FG.tot, f) end
    return true, at
end

--- A HEADER OF ITS OWN, on top of the cell, wearing the family's prompt. Arn, 23 Sep: "for the
--- target header lets add BiS>target and another option that frame will also have target of target
--- with its on header on top BiS>tot the frames are attached to each other".
---
--- It was a bare 8 px bar you could take hold of and nothing else. Now it says which cell it is -
--- which is the whole point once there are two of them stacked up.
---
--- `moves` is the frame a drag MOVES, which for both bars is the target cell: the tot cell hangs
--- off it, so grabbing either bar picks up the whole block and the two can never come apart.
--- ONE LABEL IN THE BAR, per the header law: an 84 pixel bar has room for "BiS> target" and
--- nothing else, and a second FontString in it would print straight through the first.
-- WHICH CELL'S SETTINGS A BAR EDITS. The target's bar and the tot's bar both move the target
-- cell and write the target's spot; your own bar moves your own. One table each, so a drag can
-- never write the wrong cell's place into the macro.
FG.TARGET_KEYS = { what = "target cell", at = "targetAt", pos = "targetPos",
                   spot = function() return FG.TargetSpot() end,
                   place = function(f) return FG.PlaceTarget(f) end }
FG.SELF_KEYS   = { what = "your own cell", at = "meAt", pos = "mePos",
                   spot = function() return FG.SelfSpot() end,
                   place = function(f) return FG.PlaceSelf(f) end }

function FG.CellHeader(f, word, moves, keys)
    if not f or f.handle then return f and f.handle end
    moves = moves or f
    keys = keys or FG.TARGET_KEYS
    local h = CreateFrame("Frame", "BiSHealingForeverHeader" .. tostring(word), f)
    h:SetHeight(HEADER_H)
    h:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, HEADER_LIFT)
    h:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, HEADER_LIFT)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.12, 0.85)

    local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 4, 0)
    title:SetText("BiS> " .. tostring(word))
    local T = _G.BiSTheme
    if T and T.rgb and title.SetTextColor then title:SetTextColor(T.rgb("accent")) end
    h.title, h.word = title, word

    moves:SetMovable(true)
    h:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then return end
        moves:StartMoving()
        h.moving = true
    end)
    -- SHIFT-CLICK WALKS IT ROUND THE GRID, left-click still drags. Arn, 23 Sep: "how about if we
    -- shift click the header it it toggles between top left right bottom and left click still
    -- drags". A drag ends with a mouse-up too, so a drag that just happened is not a click.
    h:SetScript("OnMouseUp", function(_, button)
        if h.dragged then h.dragged = nil return end
        if button ~= "LeftButton" or not (IsShiftKeyDown and IsShiftKeyDown()) then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local d = NS.DB and NS.DB()
        if type(d) ~= "table" then return end
        -- round the ring, and past any side another block is already using
        d[keys.at] = FG.FreeSpot(FG.TARGET_RING[keys.spot()] or "top", keys)
        d[keys.pos] = nil
        keys.place(moves)
        if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
        if NS.Print then NS.Print(keys.what .. ": " .. d[keys.at]) end
    end)
    h:SetScript("OnDragStop", function()
        if not h.moving then return end
        h.moving, h.dragged = false, true
        moves:StopMovingOrSizing()
        local d = NS.DB and NS.DB()
        -- WHERE THE BLOCK LANDED, measured on the frame that moved. Dragging the tot's bar moves
        -- the target cell, so asking the tot where IT is would write the wrong spot into the macro
        -- and the block would jump a cell's height at the next login.
        local ok, x, y = FG.ScreenOffsetOf(moves)
        if ok and type(d) == "table" then
            d[keys.at], d[keys.pos] = "free", { x = x, y = y }
            keys.place(moves)
            if NS.FK and NS.FK.Save then NS.FK.Save(d.binds or {}) end
        end
    end)
    h:SetScript("OnEnter", function()
        bg:SetColorTexture(0.13, 0.10, 0.19, 0.95)
        if not GameTooltip then return end
        GameTooltip:SetOwner(h, "ANCHOR_TOP")
        GameTooltip:AddLine("drag to move the " .. keys.what)
        GameTooltip:AddLine("shift-click to send it round the grid", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("/bish target under | left | right | top", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function()
        bg:SetColorTexture(0.08, 0.06, 0.12, 0.85)
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

--- DEAD, OR NOT THERE AT ALL. Arn, 30 Sep, with a screenshot of EllesmereUI's raid frames: "it
--- shows when they are dead and offline". Their own note beside the same pair is what made this
--- safe to write: "UnitIsDeadOrGhost / UnitIsConnected return clean booleans for group units
--- (only UnitIsAFK can be secret)" - so unlike health, these two can simply be asked.
---
--- Guarded anyway, because this addon asks before it reads and a measurement is not a promise: a
--- word the client will not confirm is not shown, and the cell falls back to its number.
--- "Offline" wins over "dead": a corpse that logged out is a person who is not coming back to it.
function FG.StatusWord(unit)
    if not unit then return nil end
    if UnitIsConnected then
        local ok, connected = pcall(UnitIsConnected, unit)
        local plain = ok and NS.Plain(connected)
        if plain == false then return "OFFLINE" end
    end
    if UnitIsDeadOrGhost then
        local ok, dead = pcall(UnitIsDeadOrGhost, unit)
        if ok and NS.Plain(dead) == true then return "DEAD" end
    end
    -- AND AFK LAST, because it is the only one of the three you can heal through. EllesmereUI's
    -- frames show it too, and their note draws the line this follows: of these calls "only
    -- UnitIsAFK can be secret". So unlike the other two it can go quiet mid-fight - and when it
    -- does the cell shows the number again rather than a stale word. Someone's health is the more
    -- useful of the two things that line can say, and "AFK" that might be ten minutes old is the
    -- less useful.
    if UnitIsAFK then
        local ok, afk = pcall(UnitIsAFK, unit)
        if ok and NS.Plain(afk) == true then return "AFK" end
    end
    return nil
end

function FG.PaintText(f)
    local label, unit = f.htext, f.unit
    if not label then return false end
    -- THE WORD INSTEAD OF THE NUMBER, which is what EllesmereUI does: how much health a corpse is
    -- missing is not a question anybody has, and the two sharing one line would print through
    -- each other on an 84 pixel cell.
    local word = FG.StatusWord(unit)
    if word then
        label:SetText(word)
        if label.SetTextColor then label:SetTextColor(0.78, 0.78, 0.82) end
        f.__status = word
        return true
    end
    if f.__status then
        f.__status = nil
        if label.SetTextColor then label:SetTextColor(1, 0.55, 0.55) end   -- back to the red number
    end
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
    -- a half-size cell has no room for it, and the pyramid's shape says the role anyway
    if f.__narrow then icon:Hide() return false end
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
    -- A PING AIMS AT A FRAME THAT SAYS IT CAN BE AIMED AT (1 Oct 2026). Arn bound an Assist ping to
    -- a mouse button, clicked his own cell and the ping landed on the GROUND - so Blizzard's /ping
    -- fired (the macro road works) but aimed where the cursor was in the world rather than at the
    -- unit under it. Retail's own unit frames opt in with this attribute; the ping system does not
    -- go looking for frames that never claimed to be one. Harmless where it means nothing: an
    -- attribute no client reads is an attribute no client reads.
    f:SetAttribute("ping-receiver", true)
    -- What a click MEANS belongs to Forever/Mouse.lua - every button, every modifier, in one
    -- place the player can see and change. The grid used to set three of them here, and then the
    -- mouse's own pass wiped whatever it did not know about. One owner.
    if NS.FM and NS.FM.ApplyTo then NS.FM.ApplyTo(f) end
    if RegisterUnitWatch then RegisterUnitWatch(f) end
    if f.name then f.name:SetText(FG.CellName(f, unit)) end
    return true
end

-- A HALF-SIZE CELL HAS TO GIVE SOMETHING UP. Arn, 30 Sep, with a 40 pixel cell reading "Ch...":
-- "lets try and modify the half size ones maybe move stuff around only those so at least the name
-- can show".
--
-- What it gives up is the ROLE ICON, and that is the right thing to lose: these cells only exist
-- in the pyramid, where the shape already says the role - tanks at the apex, healers along the
-- bottom. The icon is repeating in 11 pixels what the position says for free, and those 11 pixels
-- are a third of the line.
--
-- With the icon gone the name takes the whole width, and is cut to what the cell can actually
-- hold rather than to a fixed twelve characters.
local NARROW_W = 60                      -- under this is a pyramid base cell; 84 is ordinary
local CHAR_W = 5.5                       -- the small font, measured by eye at 100%

--- Set a cell up for the width it has just been given. Called from the layout, where the width is
--- known, rather than from the paint - anchors do not change sixty times a second.
function FG.FitCell(f, w)
    local narrow = (tonumber(w) or FRAME_W) < NARROW_W
    f.__chars = math.max(3, math.floor(((tonumber(w) or FRAME_W) - 6) / CHAR_W))
    if f.__narrow == narrow then return narrow end
    f.__narrow = narrow
    if f.name then
        f.name:ClearAllPoints()
        f.name:SetPoint("TOPLEFT", 3, -4)
        -- the corner the role icon was keeping, or all of it
        f.name:SetPoint("TOPRIGHT", narrow and -3 or -14, -4)
    end
    if narrow and f.role then f.role:Hide() end
    return narrow
end

--- The name this particular cell can hold. A secret name is handed over whole - it cannot be cut,
--- and the client clips what will not fit.
function FG.CellName(f, unit)
    local name = FG.ShortName(unit)
    if NS.Secret and NS.Secret(name) then return name end
    local chars = f and f.__chars
    if chars and type(name) == "string" and #name > chars then name = name:sub(1, chars) end
    return name
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
            local w = p.w or (p.wide and FULL_W or HALF_W)
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
            w = p.w or (p.wide and FULL_W or HALF_W)
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
        FG.FitCell(f, w)                -- before Bind, which is what writes the name
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
    FG.LayoutSelf(anchor)           -- and your own, out of the group, when it is wanted
    FG.LayoutPets(anchor)           -- and the pets, when they have a block rather than a column
    FG.LayoutMana(anchor)           -- and the other healers' mana, when it is wanted

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
        -- a word that does not fit is a word printed over whatever is beside it.
        --
        -- THE REGEN NUMBER SHARES THIS BAR (FG.PaintRegen), so it is given room, and on a header
        -- as narrow as one group the addon's own name goes. Arn, 23 Sep, with the two printed
        -- through each other on a party grid: "in default mode keep BiS> but drop the healing and
        -- put it in there". The prompt still blinks; it just stops saying what you already know.
        local h = FG.header
        if h and h.con then h.con.width = math.max(40, w - 10) end
        if h and h.title and not h.con then
            local T = _G.BiSTheme
            if T and T.Fit then T.Fit(h.title, "BiS> " .. FG.HeaderWord(w), math.max(40, w - 10)) end
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
    -- AN ENEMY SHOULD NOT LOOK LIKE A FRIEND. Arn, 28 Sep, on his hunter: the target and tot cells
    -- cast on hostile units perfectly well - "the frames cant distinguish when its an enemy right
    -- now enemies look like friendlies". Hostility beats both the class colour and the health
    -- colour: a red bar on a mob is the point, and "how hurt is it" is the same question either way.
    if not (f.mayBeHostile and FG.PaintHostile(f, unit, c)) then
        if dead or not (byHealth and FG.PaintByHealth(f)) then
            f.bar:SetStatusBarColor(c[1], c[2], c[3])
        end
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
    FG.PaintEdge(f, unit)
    FG.PaintRange(f, unit)
end

-- A FRAME ROUND THE PEOPLE WHO MATTER TO A HEALER. Arn, 30 Sep: "yellow frame around the healers
-- and a gold frame around self".
--
-- IT COSTS NOTHING TO DRAW. The health bar is already inset by a pixel, so the cell's own
-- background shows as a ring around it - colouring that background IS the frame. No extra
-- textures, no second frame per cell, nothing to lay out: forty raid cells cost forty SetColor
-- calls that were happening anyway.
FG.EDGE = {
    me     = { 1.00, 0.78, 0.20 },     -- gold: you
    healer = { 0.93, 0.90, 0.35 },     -- yellow: whoever else is keeping people alive
    -- and no entry for "none": everybody else has no ring, which is what the cell looked like
    -- before any of this
}

--- Which ring this cell wears. Role and identity both go secret in a fight, so each cell keeps
--- the last answer it got rather than flickering between gold and nothing every time the client
--- stops talking - the ring is about who someone IS, and that does not change mid-pull.
function FG.PaintEdge(f, unit)
    if not (f and f.bg and unit) then return nil end
    local kind
    -- UnitIsUnit first, then the string compare, and the string compare only when the client says
    -- unit tokens may be compared at all - NS.IsPlayer is those three steps in one place now
    -- (1 Oct 2026). nil from it means "could not tell", which falls through to f.__edge below and
    -- keeps whatever ring the cell last had, rather than taking one away on a shrug.
    if NS.IsPlayer and NS.IsPlayer(unit) == true then kind = "me" end
    if not kind and UnitGroupRolesAssigned then
        local ok, role = pcall(UnitGroupRolesAssigned, unit)
        local plain = ok and NS.Plain(role)
        if plain == "HEALER" then kind = "healer"
        elseif plain then kind = "none" end            -- a role we CAN read and it is not a healer
    end
    kind = kind or f.__edge                            -- unreadable: keep what it last was
    if not kind then return nil end
    f.__edge = kind
    if not f.edge then return kind end
    local c = FG.EDGE[kind]
    for _, t in pairs(f.edge) do
        if c then
            t:SetColorTexture(c[1], c[2], c[3], 1)
            t:Show()
        else
            t:Hide()                                   -- "none": no ring at all, not a dark one
        end
    end
    return kind
end

-- What a cell wears when the unit in it can be attacked. Not the dead grey and not a class
-- colour: nothing in a healer's group is ever this colour.
FG.HOSTILE = { 0.72, 0.16, 0.16 }
FG.hostileSeen = nil

--- IS THIS SOMETHING I COULD ATTACK? A plain answer paints red. A SECRET one - which is what
--- combat gives, like everything else about somebody else - goes through the client's own
--- ternary, the same call the range dimming uses: it picks each colour channel between hostile
--- and friendly from a boolean nobody here may test.
---
--- Only the target and the tot cells ask. Your party is not hostile, and a question asked of
--- forty raid cells ten times a second for an answer that is always no is forty questions wasted.
function FG.PaintHostile(f, unit, friendly)
    if not (f and f.bar and unit and UnitCanAttack) then return false end
    local asked, hostile = pcall(UnitCanAttack, "player", unit)
    if not asked then return false end
    if NS.Secret and NS.Secret(hostile) then
        local curve = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
        if not curve then FG.hostileSeen = "secret, no curve" return false end
        local ok1, r = pcall(curve, hostile, FG.HOSTILE[1], friendly[1])
        local ok2, g = pcall(curve, hostile, FG.HOSTILE[2], friendly[2])
        local ok3, b = pcall(curve, hostile, FG.HOSTILE[3], friendly[3])
        if not (ok1 and ok2 and ok3) then FG.hostileSeen = "curve refused" return false end
        local drew = pcall(f.bar.SetStatusBarColor, f.bar, r, g, b)
        FG.hostileSeen = drew and "secret" or "colour refused"
        return drew
    end
    FG.hostileSeen = "plain"
    if hostile == true then
        f.bar:SetStatusBarColor(FG.HOSTILE[1], FG.HOSTILE[2], FG.HOSTILE[3])
        return true
    end
    return false
end

-- How far down an unreachable cell goes. Not hidden: out of range is a thing to notice, not a
-- thing to lose.
FG.DIM = 0.45

--- AND IN A FIGHT, WHERE THE ANSWER IS A SECRET. Read off ForeverAuras 0.8.6 (28 Sep 2026):
--- `C_CurveUtil.EvaluateColorValueFromBoolean(bool, whenTrue, whenFalse)` hands back one of two
--- values, chosen by the CLIENT from a boolean the addon may not even test for truth. It is the
--- ternary we have never been allowed to write.
---
--- That is exactly what stood between this and working mid-pull. "Are they in range" goes secret
--- in combat like everything else, `pcall` swallowed the refusal, and the cell stayed at full
--- brightness - so the dimming has only ever worked between pulls, when you least need it.
---
--- The plain answer is still used when there is one: it needs no client call, it works on TBC,
--- and a number we can read is better than a number we cannot. The curve is for the other half
--- of the time.
---
--- WHAT IS NOT KNOWN YET, and is measured rather than assumed: whether SetAlpha will ACCEPT a
--- value derived from a secret. Widgets take secret values by design - that is the whole display
--- bargain - but no census lists which ones, so the call is guarded and what happened is recorded
--- for `/bish range` to report. A refusal leaves the cell bright, which is where it is today.
FG.rangeSeen = nil        -- what the last read was: "plain", "secret", "refused" or "no spell"

function FG.PaintRange(f, unit)
    local spell, spellID
    if NS.FM and NS.FM.RangeSpell then spell, spellID = NS.FM.RangeSpell() end
    local range = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    if not (range and spell) then
        FG.rangeSeen = "no spell"
        f:SetAlpha(1)
        return 1, "no spell"
    end
    -- THE ID FIRST, THE NAME AFTER. EllesmereUI passes ids to this call, and a name it cannot
    -- resolve answers nil - which this code used to read as "not a clear no, so leave them bright".
    -- Arn, 30 Sep: a whole raid at full alpha.
    local asked, answer = pcall(range, spellID or spell, unit)
    if asked and answer == nil and spellID then
        asked, answer = pcall(range, spell, unit)        -- the name, in case the id was wrong
    end
    -- AND IF IT STILL WILL NOT SAY, ASK A DIFFERENT QUESTION. "Is this spell in range" is nil for
    -- a spell the client will not range-check at all (a smart heal, a ground target, anything
    -- odd). UnitInRange answers for the unit rather than the spell - about 40 yards, near enough
    -- for a healer - and on this client it is the SECRET boolean, which is what the ternary below
    -- is for. Their frames fall back the same way.
    if asked and answer == nil and UnitInRange then
        asked, answer = pcall(UnitInRange, unit)
        if asked then FG.rangeSeen = "unit" end
    end
    if not asked then
        FG.rangeSeen = "refused"
        f:SetAlpha(1)
        return 1, "refused"
    end
    -- A SECRET ANSWER NEVER TOUCHES AN `if`. NS.Secret asks the client whether this value may be
    -- read; everything below either hands it straight to the curve or works on a plain value.
    if NS.Secret and NS.Secret(answer) then
        local curve = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
        if not curve then
            FG.rangeSeen = "secret, no curve"
            f:SetAlpha(1)
            return 1, "secret, no curve"
        end
        local made, alpha = pcall(curve, answer, 1, FG.DIM)
        if not made then
            FG.rangeSeen = "curve refused"
            f:SetAlpha(1)
            return 1, "curve refused"
        end
        local drew = pcall(f.SetAlpha, f, alpha)
        FG.rangeSeen = drew and "secret" or "alpha refused"
        if not drew then f:SetAlpha(1) end
        return nil, FG.rangeSeen
    end
    -- the plain answer: the modern call says true/false, the old one 1/0, and anything that is
    -- not a clear "no" leaves the cell bright rather than dimming someone who is reachable
    local reach = (answer == 0 or answer == false) and FG.DIM or 1
    -- nil from everything that could answer: nobody is dimmed, and /bish range says which it was
    if answer == nil then FG.rangeSeen = "no answer" else FG.rangeSeen = FG.rangeSeen == "unit" and "unit" or "plain" end
    f:SetAlpha(reach)
    return reach, FG.rangeSeen
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
    -- and the target cell, which wears this scale but is pinned to the screen when it has been
    -- dragged: its point has to be worked out again at the new scale or it slides away
    if FG.target then FG.PlaceTarget(FG.target, a) end
    if FG.me then FG.PlaceSelf(FG.me, a) end        -- and yours, which is pinned the same way
    if FG.petAnchor then FG.PlacePets(FG.petAnchor, a) end
    if FG.manaAnchor then FG.PlaceMana(FG.manaAnchor, a) end
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
--- The same measurement in SCREEN units, which is what a frame that must not move when its parent
--- is resized has to remember. The grid keeps its own position in its own units (it IS the thing
--- being scaled, and SetScale converts as it goes); a free target cell cannot, because the scale
--- it wears is the grid's.
function FG.ScreenOffsetOf(f)
    local ok, x, y = FG.CenterOffsetOf(f)
    if not ok then return false end
    local k = FG.ScaleOf(f)
    return true, math.floor(x * k + 0.5), math.floor(y * k + 0.5)
end

--- A frame's scale against the screen's: multiply an offset in the frame's own units by this and
--- you have the screen; divide to go the other way.
function FG.ScaleOf(f)
    local fs = (f and f.GetEffectiveScale and f:GetEffectiveScale())
        or (f and f.GetScale and f:GetScale()) or 1
    local us = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if not (type(fs) == "number" and type(us) == "number") or us == 0 or fs == 0 then return 1 end
    return fs / us
end

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
    h:SetHeight(GRID_HEADER_H)
    h:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, GRID_HEADER_LIFT)
    h:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, GRID_HEADER_LIFT)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")

    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.06, 0.12, 0.85)

    -- THE FIVE SECOND RULE, ACROSS THE HEADER. Arn, 23 Sep: "itll be like a bar thats filling
    -- backwards in the header". Spend mana and this fills the header, then drains away over the
    -- five seconds; when it is gone you are regenerating normally again. It is BEHIND the prompt
    -- (BORDER, under the title's OVERLAY) so it colours the bar rather than covering the words.
    h.fsr = h:CreateTexture(nil, "BORDER")
    h.fsr:SetPoint("TOPLEFT")
    h.fsr:SetPoint("BOTTOMLEFT")
    h.fsr:SetColorTexture(0.35, 0.28, 0.10, 0.85)
    h.fsr:Hide()

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

--- Draw the five second rule on the header: the bar drains from full to nothing across those five
--- seconds, and the share you are regenerating while it runs sits on the right. Nothing is drawn
--- when the client will not answer, or when the rule is not running - a healer standing still
--- should see their own prompt, not a number that never changes.
function FG.PaintRegen(header)
    header = header or FG.header
    if not (header and header.fsr) then return false end
    -- the word first: "Healing" while nothing is happening, the regen share once the fight starts,
    -- and the short form of either when the bar is only a cell wide
    local bar = (header.GetWidth and header:GetWidth()) or 0
    local word = FG.HeaderWord(type(bar) == "number" and bar or nil)
    if header.con then
        if header.__word ~= word then header.con:Set("name", word); header.__word = word end
    elseif header.title then
        if header.__word ~= word then header.title:SetText("BiS> " .. word); header.__word = word end
    end
    local FR = NS.FR
    local left = FR and FR.Left and FR.Left() or 0
    if left <= 0 then
        header.fsr:Hide()
        return false, 0
    end
    local w = (header.GetWidth and header:GetWidth()) or 0
    if type(w) ~= "number" or w <= 0 then w = 84 end
    header.fsr:SetWidth(math.max(1, w * (left / (FR.WINDOW or 5))))
    header.fsr:Show()
    return true, left
end

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
        -- THE WHOLE OF WHAT THE BAR ABBREVIATED. On a party grid the bar has room for "no WS" and
        -- "62%"; the tooltip has room for all of it, and costs no pixels.
        local full = FG.HeaderWord()
        if full and full ~= "Healing" then
            GameTooltip:AddLine(full, 0.90, 0.88, 0.96)
        end
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
        FG.PaintRegen(FG.header)        -- the five second rule, draining across the header
        local t = FG.target
        if t and t.unit and t:IsShown() then
            if t.name then t.name:SetText(FG.ShortName("target")) end
            FG.Paint(t)
        end
        -- the mana rows are not cells at all: a name and a percentage the client works out
        for _, row in ipairs(FG.manaRows or {}) do
            if row.unit and row:IsShown() then FG.PaintMana(row, row.unit) end
        end
        -- the pet block's cells are not in FG.frames either
        for _, f in ipairs(FG.petFrames or {}) do
            if f.unit and f:IsShown() then FG.Paint(f) end
        end
        -- your own cell is out of the roster, so the loop above never reaches it
        local me = FG.me
        if me and me.unit and me:IsShown() then
            if me.name then me.name:SetText(FG.ShortName("player")) end
            FG.Paint(me)
        end
        -- and whoever they are targeting, whose name changes under it twice as often
        local tt = FG.tot
        if tt and tt.unit and tt:IsShown() then
            if tt.name then tt.name:SetText(FG.ShortName("targettarget")) end
            FG.Paint(tt)
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
    if NS.FR and NS.FR.Start then NS.FR.Start() end   -- the five second rule, on the header
    if NS.FS and NS.FS.Start then NS.FS.Start() end   -- and the buff you keep forgetting
    return true
end

-- Booted by Core.lua at login. This file used to arm itself, because for two days it WAS the
-- addon on this client and there was no core to do it.
