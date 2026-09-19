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
local HEAL = "Healing Wave"             -- confirmed present on Forever (probe, 17 Sep)
local HEAL_FAST = "Lesser Healing Wave"
local HEAL_CHAIN = "Chain Heal"
local RANGE_SPELL = HEAL                -- the spell whose range decides "can I reach them"

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

    -- On the BAR, not on the button: a child frame draws above its parent, and a name created on
    -- the button sits UNDER the health bar -- which looks like "the names are missing" with only
    -- the overflowing tail of a long one visible past the cell's edge (seen on the beta, 17 Sep).
    f.name = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.__nameParent = f.bar        -- dev/forever.lua asserts the label belongs to the bar
    f.name:SetPoint("LEFT", 3, 0)
    f.name:SetPoint("RIGHT", -3, 0)      -- clipped to the cell instead of spilling out of it
    f.name:SetJustifyH("LEFT")
    if f.name.SetWordWrap then f.name:SetWordWrap(false) end

    FG.frames[i] = f
    return f
end

--- Point a cell at a unit: the secure attributes and the click-casts. OUT OF COMBAT ONLY -- every
--- SetAttribute here is refused once the lockdown is on, so this is called from the roster events
--- and never from the update loop.
function FG.Bind(f, unit)
    if InCombatLockdown and InCombatLockdown() then return false end
    f.unit = unit
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "spell")
    f:SetAttribute("*spell1", HEAL)
    f:SetAttribute("*type2", "spell")
    f:SetAttribute("*spell2", HEAL_FAST)
    f:SetAttribute("shift-type1", "spell")
    f:SetAttribute("shift-spell1", HEAL_CHAIN)
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
    local roster = FG.Roster()
    for i, unit in ipairs(roster) do
        local f = FG.frames[i] or FG.Make(i, anchor)
        local col, row = math.floor((i - 1) / PER_COL), (i - 1) % PER_COL
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", anchor, "TOPLEFT",
                   col * (FRAME_W + PAD), -row * (FRAME_H + PAD))
        FG.Bind(f, unit)
        -- the aura markers ride the same out-of-combat moment as the secure attributes: the
        -- container is told its unit here and then draws by itself for the whole fight
        if NS.FA and NS.FA.Attach then NS.FA.Attach(f, unit) end
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
    if FG.maxOK then
        local ok = pcall(f.bar.SetMinMaxValues, f.bar, 0, UnitHealthMax(unit))
        if not ok then FG.maxOK = false end
    end
    f.bar:SetValue(UnitHealth(unit))     -- the one legal thing to do with a secret number

    local _, class = UnitClass(unit)
    local c = CLASS_COLOR[class] or { 0.2, 0.7, 0.3 }
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then c = DEAD end
    f.bar:SetStatusBarColor(c[1], c[2], c[3])

    -- Range. NOT UnitInRange: on Forever that returns a secret BOOLEAN, which cannot even be
    -- used in an `if` -- the client refuses the boolean test itself. IsSpellInRange answers
    -- plainly, and anything that is not a clear "no" leaves the cell at full alpha rather than
    -- dimming someone who is actually reachable.
    local reach = 1
    if IsSpellInRange then
        local ok, r = pcall(IsSpellInRange, RANGE_SPELL, unit)
        if ok and (r == 0 or r == false) then reach = 0.45 end
    end
    f:SetAlpha(reach)
end

--------------------------------------------------------------------- driving --

local THROTTLE = 0.1

function FG.Start()
    if not NS.SECRET then return false end          -- TBC keeps the pyramid, untouched
    if FG.anchor then return true end

    -- The pyramid's own anchor is built at file load, before anything knows which client this is,
    -- so on Forever it sits there saying "BiS Healing -- drag (unlocked)" over a pyramid that will
    -- never appear. Its brain is already off; this takes its furniture off the screen too.
    if NS.anchor and NS.anchor.Hide then NS.anchor:Hide() end
    if NS.UIX and NS.UIX.plate and NS.UIX.plate.Hide then NS.UIX.plate:Hide() end

    local anchor = CreateFrame("Frame", "BiSHealingForeverAnchor", UIParent)
    anchor:SetSize(FRAME_W, FRAME_H)
    anchor:SetPoint("CENTER", UIParent, "CENTER", -260, -120)
    FG.anchor = anchor

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
    for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
                         "PLAYER_REGEN_ENABLED" }) do
        pcall(ev.RegisterEvent, ev, e)      -- an event this client does not know must not abort the file
    end
    ev:SetScript("OnEvent", function()
        pending = true                      -- the update loop relays out when the lockdown lets it
    end)
    FG.events = ev
    if NS.FB and NS.FB.Start then NS.FB.Start() end   -- the between-pulls brain, step 2
    return true
end

-- The client hands every file (addonName, addonTable); nothing else calls into here, so the grid
-- arms itself on login. On TBC FG.Start() returns false on its first line and this costs one frame.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    FG.Start()
end)
