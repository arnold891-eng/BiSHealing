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
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }

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
        if inRaid and GetRaidRosterInfo then
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
        keyed[i] = { unit = u, rank = ROLE_RANK[role or ""] or 4, at = i }
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
    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) then out[#out + 1] = u end
        end
        return out
    end
    out[1] = "player"
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then out[#out + 1] = u end
    end
    return out
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
    f.name = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.__nameParent = f.bar        -- dev/forever.lua asserts the label belongs to the bar
    f.name:SetPoint("LEFT", 3, 0)
    f.name:SetPoint("RIGHT", -3, 0)      -- clipped to the cell instead of spilling out of it
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

    FG.frames[i] = f
    return f
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
    local name = UnitName and UnitName(unit) or unit
    if type(name) ~= "string" then return tostring(unit) end
    name = name:match("^([^-]+)") or name
    if #name > 9 then name = name:sub(1, 9) end
    return name
end

--------------------------------------------------------------------- layout --

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
    local d = NS.DB and NS.DB()
    if type(d) == "table" and d.shown == false then
        for _, f in ipairs(FG.frames) do f:Hide() end
        return true, 0
    end
    local pyramid = type(d) == "table" and d.layout == "pyramid"
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
            local g = grid[i]
            f:SetPoint("TOPLEFT", anchor, "TOPLEFT",
                       (g.col - 1) * (FRAME_W + PAD), -(g.row - 1) * (FRAME_H + PAD))
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
            f.unit = nil
            f:Hide()
        end
    end

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
            rows = 0
            for _, g in ipairs(grid) do if g.row > rows then rows = g.row end end
            w = groups * (FRAME_W + PAD) - PAD
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

---------------------------------------------------------------------- paint --

local CLASS_COLOR = {
    SHAMAN = { 0.00, 0.44, 0.87 }, PRIEST = { 1.00, 1.00, 1.00 }, DRUID  = { 1.00, 0.49, 0.04 },
    PALADIN = { 0.96, 0.55, 0.73 }, WARRIOR = { 0.78, 0.61, 0.43 }, ROGUE = { 1.00, 0.96, 0.41 },
    MAGE = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 }, HUNTER = { 0.67, 0.83, 0.45 },
}
local DEAD = { 0.35, 0.10, 0.10 }

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
    if UnitIsDeadOrGhost and NS.Plain(UnitIsDeadOrGhost(unit)) then c = DEAD end
    f.bar:SetStatusBarColor(c[1], c[2], c[3])

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
        FG.SavePos()
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
                         "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "UPDATE_MACROS",
                         "PLAYER_ROLES_ASSIGNED", "ROLE_POLL_BEGIN" }) do
        pcall(ev.RegisterEvent, ev, e)      -- an event this client does not know must not abort the file
    end
    ev:SetScript("OnEvent", function(_, event)
        pending = true                      -- the update loop relays out when the lockdown lets it
        -- a bind changed mid-fight is queued, not lost: the moment the lockdown lifts it lands
        if event == "PLAYER_REGEN_ENABLED" and NS.FM and NS.FM.pending then NS.FM.Apply() end
        -- the macro list filling in late: what is on the mouse may be our guess, not their binds
        if event == "UPDATE_MACROS" and NS.FM and NS.FM.Reconsider then NS.FM.Reconsider() end
    end)
    FG.events = ev
    if NS.FB and NS.FB.Start then NS.FB.Start() end   -- the between-pulls brain, step 2
    return true
end

-- Booted by Core.lua at login. This file used to arm itself, because for two days it WAS the
-- addon on this client and there was no core to do it.
