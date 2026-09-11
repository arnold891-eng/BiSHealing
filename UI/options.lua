-- =========================================================================
-- BiS Healing -- UI/options.lua : the /bish settings window
--
-- Split out of BiSHealing.lua on 9 Sep 2026. Nothing here decides anything: it
-- reads and writes saved variables, paints chrome, and carries the header
-- console. Every judgement -- who to shield, who is losing a heal race, what a
-- rank is worth -- stays in BiSHealing.lua and is only ever READ from here.
--
-- The line between the two is the NS block at the bottom of BiSHealing.lua. If
-- a name is not published there, this file cannot reach it, and that is the
-- point. Anything this file needs that is not in that block is a sign the
-- window is about to start deciding something, which is not its job.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

-- Captured as locals at load, which is safe ONLY because the TOC runs
-- BiSHealing.lua before this file: every one of these is already published by
-- the time this line runs. Load this file first and they are all silently nil,
-- the window builds out of empty tables, and nothing errors until you open it.
local Print, DB, UIX            = NS.Print, NS.DB, NS.UIX
local frames, anchor            = NS.frames, NS.anchor
local WHEEL, SNIPE, COMM        = NS.WHEEL, NS.SNIPE, NS.COMM
local ES_HOLD, demo             = NS.ES_HOLD, NS.demo
local ShortName, Relayout       = NS.ShortName, NS.Relayout
local BuildHealOptions          = NS.BuildHealOptions
local VERSION, PULSE_CAP        = NS.VERSION, NS.PULSE_CAP

-- Anything that MOVES is fetched through a function instead -- see the note on
-- NS.ESTarget in BiSHealing.lua. A local copy of a moving value is a bug that
-- looks like working code.

-- ------------------------------------------------------- options window --
--
-- Flat, layered, FojjiCore-shaped, BiS-coloured: surfaces step a shade lighter
-- as they come forward, borders are four 1px textures, every widget is
-- hand-built. No Blizzard templates -- the old panel used
-- InterfaceOptionsCheckButtonTemplate and inherited its label quirks on three
-- different clients.
--
-- ONE chunk local for the whole window. This file sits a handful of names under
-- Lua 5.1's 200-local ceiling (bislint's local-budget rule), and the reference
-- implementation in BiS Gamba declares about twenty locals for the same job --
-- which here would simply refuse to load. Everything hangs off CFG.
--
-- The rule that keeps this honest: every control reads and writes the SAME
-- saved-variable key the slash commands already use. There is no second copy of
-- the settings, so the window and /bish can never disagree.
local CFG = { built = false, tab = "Frames", controls = {}, tabs = {}, pages = {} }

-- BiSTheme if it is installed (## OptionalDeps), otherwise an inline copy of
-- the same tokens. The addon must not care: an optional dependency that turns
-- into a nil index is just a crash with extra steps.
-- RESOLVED PER CALL, PER COLOUR NAME -- never captured at file load.
--
-- `CFG.T = BiSTheme or {inline}` looked right and was wrong for the life of this
-- addon. That line runs while the file loads, and the client loads addons in
-- alphabetical order: BiSHealing comes before BiSTheme, so _G.BiSTheme is nil
-- at that moment, every session, on every machine. The addon has therefore been
-- running on its own inline copy since the day it was written -- invisible only
-- because the two palettes happen to match. The first time Arn recolours
-- BiSTheme, BiSHealing would ignore him, which is the entire reason BiSTheme
-- exists. BiSJC had the identical bug.
--
-- So nothing is captured. Each lookup asks the live global, per name, and only
-- falls back for a name the shared addon does not define.
CFG.FALLBACK_HEX = {
    ink = "ece8f6", ink2 = "c6bedd", muted = "968ead", dim = "8e86a6",
    accent = "b980ff", good = "4fd0cf", warn = "f08cb0", gold = "e5c04a",
}
CFG.T = {}

function CFG.T.rgb(name)
    local live = _G.BiSTheme
    if live and live.rgb and live.hex and live.hex[name] then
        return live.rgb(name)
    end
    local h = CFG.FALLBACK_HEX[name] or CFG.FALLBACK_HEX.ink
    return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
end

function CFG.T.rgba(name, a)
    local r, g, b = CFG.T.rgb(name)
    return r, g, b, a or 1
end

-- shades, darkest (furthest back) to lightest (most forward)
function CFG.hx(h)
    return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
end
CFG.SH = {
    frame   = { CFG.hx("0d0b18") },
    header  = { CFG.hx("141127") },
    sidebar = { CFG.hx("191531") },
    content = { CFG.hx("1f1a3a") },
    field   = { CFG.hx("17132e") },
    hair    = { CFG.hx("2a2446") },
    edge    = { CFG.hx("3a3260") },
}
function CFG.shade(name, a) local c = CFG.SH[name]; return c[1], c[2], c[3], a or 1 end

function CFG.tex(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer)
    -- Both branches pass a FULL argument list on purpose. Writing this as
    -- `t:SetColorTexture(cond and select(1, T.rgba(n,a)) or CFG.shade(n,a))`
    -- truncates to one value and the client throws, killing the whole window --
    -- the trap the Gamba build hit. The harness now errors on it too.
    if CFG.SH[name] then t:SetColorTexture(CFG.shade(name, a))
    else t:SetColorTexture(CFG.T.rgba(name, a)) end
    return t
end

function CFG.border(f, name, a)
    local col = {}
    local function bar()
        local b = f:CreateTexture(nil, "BORDER")
        b:SetColorTexture(CFG.T.rgba(name, a or 1))
        return b
    end
    col.top = bar();    col.top:SetPoint("TOPLEFT");       col.top:SetPoint("TOPRIGHT");       col.top:SetHeight(1)
    col.bottom = bar(); col.bottom:SetPoint("BOTTOMLEFT"); col.bottom:SetPoint("BOTTOMRIGHT"); col.bottom:SetHeight(1)
    col.left = bar();   col.left:SetPoint("TOPLEFT");      col.left:SetPoint("BOTTOMLEFT");    col.left:SetWidth(1)
    col.right = bar();  col.right:SetPoint("TOPRIGHT");    col.right:SetPoint("BOTTOMRIGHT");  col.right:SetWidth(1)
    function col:set(n, aa)
        for _, b in pairs(self) do
            if type(b) == "table" and b.SetColorTexture then b:SetColorTexture(CFG.T.rgba(n, aa or 1)) end
        end
    end
    return col
end

function CFG.fs(parent, text, size, colorName)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    f:SetText(text or "")
    f:SetTextColor(CFG.T.rgb(colorName or "ink"))
    return f
end

-- Live effects. Anything a setting changes that is not just a colour next tick
-- happens here -- and siblings are reached through the tables they live on
-- (WHEEL, SNIPE, UIX), never a bare name, because half of them are declared
-- lower in the file than this block.
function CFG.Apply()
    local db = DB()
    UIX.NAME_MAX = db.nameLen or UIX.NAME_MAX
    if not InCombatLockdown() then
        NS.ApplyBinds()
        Relayout()
    else
        NS.QueueReorder()
        WHEEL.pending = true
    end
    wipe(SNIPE.cache)
end

CFG.ROW_H = 30

function CFG.Check(page, y, id, label, tip, get, set)
    local row = CreateFrame("Button", nil, page)
    row:SetSize(page.w, CFG.ROW_H); row:SetPoint("TOPLEFT", 0, y)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(18, 18); box:SetPoint("LEFT", 0, 0)
    local bg = CFG.tex(box, "BACKGROUND", "field"); bg:SetAllPoints()
    local bd = CFG.border(box, "edge")
    local fill = CFG.tex(box, "ARTWORK", "accent")
    fill:SetPoint("TOPLEFT", 4, -4); fill:SetPoint("BOTTOMRIGHT", -4, 4)
    local lbl = CFG.fs(row, label, 12, "ink"); lbl:SetPoint("LEFT", box, "RIGHT", 10, 0)
    local function paint()
        if get() then fill:Show(); bd:set("accent", 0.8) else fill:Hide(); bd:set("edge") end
    end
    local ctrl = { paint = paint }
    function ctrl.set(v) set(v and true or false); paint(); CFG.Apply() end
    function ctrl.get() return get() and true or false end
    row:SetScript("OnClick", function() ctrl.set(not get()) end)
    row:SetScript("OnEnter", function()
        bd:set("accent", 0.8)
        if tip and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 0.6, 0.63, 0.67, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() paint(); if not GameTooltip:IsForbidden() then GameTooltip:Hide() end end)
    paint()
    CFG.controls[id] = ctrl
    return y - CFG.ROW_H
end

function CFG.Seg(page, y, id, label, options, get, set)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(page.w, CFG.ROW_H); row:SetPoint("TOPLEFT", 0, y)
    CFG.fs(row, label, 12, "ink"):SetPoint("LEFT", 0, 0)
    local pills, x = {}, 0
    local function paint()
        for v, p in pairs(pills) do
            local on = (get() == v)
            if on then p.bg:SetColorTexture(CFG.T.rgba("accent", 0.18))
            else p.bg:SetColorTexture(CFG.shade("field")) end
            p.bd:set(on and "accent" or "edge", on and 0.8 or 1)
            p.lbl:SetTextColor(CFG.T.rgb(on and "accent" or "muted"))
        end
    end
    local ctrl = { paint = paint }
    function ctrl.set(v) set(v); paint(); CFG.Apply() end
    function ctrl.get() return get() end
    for i = #options, 1, -1 do
        local opt = options[i]
        local w = opt.w or 58
        local p = CreateFrame("Button", nil, row)
        p:SetSize(w, 20); p:SetPoint("RIGHT", -x, 0)
        p.bg = CFG.tex(p, "BACKGROUND", "field"); p.bg:SetAllPoints()
        p.bd = CFG.border(p, "edge")
        p.lbl = CFG.fs(p, opt.label, 11, "muted"); p.lbl:SetPoint("CENTER")
        p:SetScript("OnClick", function() ctrl.set(opt.v) end)
        p:SetScript("OnEnter", function() if get() ~= opt.v then p.bd:set("accent", 0.6) end end)
        p:SetScript("OnLeave", function() paint() end)
        pills[opt.v] = p
        x = x + w + 4
    end
    paint()
    CFG.controls[id] = ctrl
    return y - CFG.ROW_H
end

function CFG.Slider(page, y, id, label, lo, hi, step, fmt, get, set)
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(page.w, CFG.ROW_H + 6); row:SetPoint("TOPLEFT", 0, y)
    CFG.fs(row, label, 12, "ink"):SetPoint("TOPLEFT", 0, 0)
    local val = CFG.fs(row, "", 12, "accent"); val:SetPoint("TOPRIGHT", 0, 0)
    local track = CreateFrame("Frame", nil, row)
    track:SetPoint("TOPLEFT", 0, -18); track:SetPoint("TOPRIGHT", 0, -18); track:SetHeight(6)
    CFG.tex(track, "BACKGROUND", "field"):SetAllPoints()
    CFG.border(track, "edge")
    local sl = CreateFrame("Slider", nil, track)
    sl:SetAllPoints(); sl:SetOrientation("HORIZONTAL")
    sl:SetMinMaxValues(lo, hi); sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    local thumb = sl:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(CFG.T.rgba("accent", 1)); thumb:SetSize(10, 16)
    sl:SetThumbTexture(thumb)
    local guard = false
    local function show(v) val:SetText(fmt and fmt(v) or tostring(v)) end
    local ctrl = {}
    function ctrl.set(v)
        v = math.max(lo, math.min(hi, v))
        -- guard so a programmatic SetValue does not bounce back through
        -- OnValueChanged and write the db a second time
        guard = true; sl:SetValue(v); guard = false
        set(v); show(v); CFG.Apply()
    end
    function ctrl.get() return get() end
    sl:SetScript("OnValueChanged", function(_, v)
        if guard then return end
        if step >= 1 then v = math.floor(v + 0.5) end
        set(v); show(v); CFG.Apply()
    end)
    guard = true; sl:SetValue(get()); guard = false; show(get())
    CFG.controls[id] = ctrl
    return y - (CFG.ROW_H + 12)
end

function CFG.Btn(page, y, id, label, tip, onclick, colorName)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(160, 22); b:SetPoint("TOPLEFT", 0, y)
    CFG.tex(b, "BACKGROUND", "field"):SetAllPoints()
    local bd = CFG.border(b, "edge")
    local lbl = CFG.fs(b, label, 12, colorName or "ink2"); lbl:SetPoint("CENTER")
    b:SetScript("OnClick", function() onclick() end)
    b:SetScript("OnEnter", function()
        bd:set(colorName == "warn" and "warn" or "accent", 0.8)
        if tip and not GameTooltip:IsForbidden() then
            GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(tip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function() bd:set("edge"); if not GameTooltip:IsForbidden() then GameTooltip:Hide() end end)
    if id then CFG.controls[id] = { click = onclick, get = function() return true end } end
    return y - 30
end

function CFG.Caption(page, y, text)
    CFG.fs(page, string.upper(text), 10, "muted"):SetPoint("TOPLEFT", 0, y)
    return y - 20
end

-- pages ---------------------------------------------------------------------

function CFG.BuildFrames(page)
    local db = DB()
    local y = 0
    y = CFG.Caption(page, y, "Bars")
    y = CFG.Seg(page, y, "bars", "Bar colour",
        { { v = "black", label = "black", w = 58 }, { v = "bands", label = "rank bands", w = 76 } },
        function() return DB().plainBars and "black" or "bands" end,
        function(v) DB().plainBars = (v == "black") end)
    y = CFG.Slider(page, y, "redPct", "Red at this much of a downrank", 0.5, 1.5, 0.05,
        function(v) return ("%.0f%%"):format(v * 100) end,
        function() return DB().redPct or 1 end, function(v) DB().redPct = v end)
    y = CFG.Slider(page, y, "nameLen", "Name length", 3, 12, 1,
        function(v) return v .. " letters" end,
        function() return DB().nameLen or UIX.NAME_MAX end,
        function(v) DB().nameLen = v; UIX.NAME_MAX = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Markers")
    y = CFG.Check(page, y, "corners", "Role corner markers",
        "Green for the Chain Heal target, amber for Earth Shield, orange for Gift of the Naaru.",
        function() return DB().corners end, function(v) DB().corners = v end)
    y = CFG.Check(page, y, "pulse", "Pulse under sustained damage",
        "Flashes red over the bar of whoever is still being hit -- different from the steady red that only means the hole is big.",
        function() return DB().pulse end, function(v) DB().pulse = v end)
    y = CFG.Slider(page, y, "pulseCap", "How many may pulse at once", 1, 6, 1,
        function(v) return tostring(v) end,
        function() return DB().pulseCap or PULSE_CAP end, function(v) DB().pulseCap = v end)
    y = CFG.Check(page, y, "totemRange", "Totem reach",
        "Violet right edge on a party member standing outside a buff totem of yours -- judged from the missing buff.",
        function() return DB().totemRange ~= false end, function(v) DB().totemRange = v end)
    y = CFG.Check(page, y, "dispel", "Curable debuffs",
        "A small square low on the right, in the debuff's colour, for anything your class can cure. /bish dispel lists what each zone has thrown.",
        function() return DB().dispel ~= false end, function(v) DB().dispel = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Roster")
    y = CFG.Check(page, y, "shown", "Show the frames",
        "The whole pyramid. Same as /bish show and /bish hide.",
        function() return DB().shown ~= false end, function(v) DB().shown = v end)
    y = CFG.Check(page, y, "locked", "Lock the anchor",
        "Unlocked shows a green drag bar and the settings button above the pyramid.",
        function() return DB().locked end, function(v) DB().locked = v end)
    y = CFG.Check(page, y, "pets", "Show pets",
        "Half-size frames for pets. They often sit between tank and melee and make a good Chain Heal bridge.",
        function() return DB().pets ~= false end, function(v) DB().pets = v end)
end

function CFG.BuildChain(page)
    local y = 0
    y = CFG.Caption(page, y, "Bounce lines")
    y = CFG.Check(page, y, "bounceLines", "Draw the bounces",
        "A fading line from each target to the next as a chain resolves.",
        function() return DB().bounceLines end, function(v) DB().bounceLines = v end)
    y = CFG.Check(page, y, "goldChains", "Gold on a full 3-target chain",
        "Repaints that cast's lines gold once the cluster closes.",
        function() return DB().goldChains end, function(v) DB().goldChains = v end)
    y = CFG.Check(page, y, "celebrate", "Celebrate a full chain",
        "Sparks from the primary target. Three targets AND three crits gets the big gold-white burst.",
        function() return DB().celebrate end, function(v) DB().celebrate = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Bragging")
    y = CFG.Check(page, y, "critBrag", "Announce a triple crit",
        "Three targets and three crits says so in PARTY chat -- your subgroup only, throttled.",
        function() return DB().critBrag end, function(v) DB().critBrag = v end)
    y = CFG.Slider(page, y, "bragGap", "Not more often than", 5, 120, 5,
        function(v) return v .. "s" end,
        function() return DB().bragGap or UIX.BRAG_GAP end, function(v) DB().bragGap = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Other healers")
    y = CFG.Check(page, y, "healRace", "Heal race counter",
        "How many heals are converging on a target, yours included. Red means someone else lands first.",
        function() return DB().healRace ~= false end, function(v) DB().healRace = v end)
    y = CFG.Check(page, y, "incomingFill", "Incoming-heal fill",
        "Shows on the bar where inbound heals will land.",
        function() return DB().incomingFill end, function(v) DB().incomingFill = v end)
    y = CFG.Check(page, y, "castCounter", "Castable-heals counter",
        "The X | Y | +Z readout above the pyramid.",
        function() return DB().castCounter end, function(v) DB().castCounter = v end)
    y = CFG.Check(page, y, "fsr", "Five-second rule",
        "The counter's +Z column counts spirit regen only once five seconds have passed since a cast that cost mana, and shows the seconds until then.",
        function() return DB().fsr ~= false end, function(v) DB().fsr = v end)
    y = CFG.Check(page, y, "rpm", "Mana gauge",
        "Burn against overheal, so you can see when you are spending into a full bar.",
        function() return DB().rpm end, function(v) DB().rpm = v end)
end

function CFG.BuildShield(page)
    local y = 0
    y = CFG.Caption(page, y, "When to say anything")
    y = CFG.Slider(page, y, "esQuiet", "Stay quiet above this many charges", 1, 6, 1,
        function(v) return v .. (v == 1 and " charge" or " charges") end,
        function() return DB().esQuiet or ES_HOLD.quiet end, function(v) DB().esQuiet = v end)
    CFG.fs(page, "A shield with charges left is not a decision. Below this the amber corner comes back and the current holder keeps a 1.5x edge.",
        10, "dim"):SetPoint("TOPLEFT", 0, y + 4)
    y = y - 30
    y = CFG.Caption(page, y, "Markers")
    y = CFG.Check(page, y, "nsPip", "Nature's Swiftness pip",
        "Marks anyone whose hole is past what a max-rank Chain Heal fixes. White when NS is up, grey when it is not.",
        function() return DB().nsPip end, function(v) DB().nsPip = v end)
    y = CFG.Check(page, y, "giftBadge", "Gift of the Naaru badge",
        "Lit icon confirms your HoT is ticking on that target.",
        function() return DB().giftBadge end, function(v) DB().giftBadge = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Advice")
    y = CFG.Btn(page, y, "esplan", "Who should carry it",
        "Prints the Earth Shield plan -- same as /bish esplan.",
        function() SlashCmdList.BISHEALING("esplan") end)
    y = CFG.Btn(page, y, "peers", "Other BiSHealing shamans",
        "Who is answering on the addon comm -- same as /bish peers.",
        function() SlashCmdList.BISHEALING("peers") end)
end

function CFG.BuildWheel(page)
    local y = 0
    y = CFG.Caption(page, y, "Mouse wheel")
    y = CFG.Seg(page, y, "wheelMode", "Wheel heals",
        { { v = "off", label = "off", w = 44 },
          { v = "combo", label = "one press", w = 68 },
          { v = "strict", label = "two press", w = 68 } },
        function()
            local db = DB()
            if not db.wheel then return "off" end
            return db.wheelStrict and "strict" or "combo"
        end,
        function(v)
            local db = DB()
            db.wheel = (v ~= "off")
            db.wheelStrict = (v == "strict")
        end)
    CFG.fs(page, "One press fires Nature's Swiftness and the heal together and never stalls. Two press is the castsequence -- and does nothing at all while NS is on cooldown.",
        10, "dim"):SetPoint("TOPLEFT", 0, y + 4)
    y = y - 30
    y = CFG.Check(page, y, "trinkets", "Trinkets on any shift press",
        "Slots 13 and 14 fire before the heal on shift+click and shift+scroll. Unshifted presses never touch them.",
        function() return DB().trinkets end, function(v) DB().trinkets = v end)
    y = y - 6
    y = CFG.Caption(page, y, "Now")
    y = CFG.Btn(page, y, "reorder", "Reorder now",
        "Re-rank and re-lay the pyramid. Queues if you are in combat.",
        function()
            if InCombatLockdown() then
                NS.QueueReorder(); CFG.Say("queued for combat end", "muted")
            else
                Relayout(); CFG.Say("reordered", "good")
            end
        end)
    y = CFG.Btn(page, y, "center", "Recentre",
        "Bring the pyramid back to the middle of the screen and show it.",
        function()
            DB().pos = nil
            anchor:ClearAllPoints(); anchor:SetPoint("CENTER", 0, -220)
            DB().shown = true
            if not InCombatLockdown() then Relayout() end
        end)
    y = CFG.Btn(page, y, "rescan", "Rescan spellbook",
        "Re-read your ranks and rebuild the heal sizes.",
        function() BuildHealOptions(); CFG.Say("ranks rescanned", "good") end)
    y = CFG.Btn(page, y, "demo", "Demo on / off",
        "Walks every feature across your real group.",
        function() SlashCmdList.BISHEALING(demo.on and "sim off" or "sim on") end)
    y = y - 6
    y = CFG.Caption(page, y, "Start over")
    y = CFG.Btn(page, y, "resetsizes", "Forget measured heal sizes",
        "Back to the coefficient estimate until four clean casts land.",
        function() SlashCmdList.BISHEALING("resetsizes") end, "warn")
    y = CFG.Btn(page, y, "wipe", "Wipe learned history",
        "Throws away every fight this addon has scored. The ordering will be rough for a night.",
        function() BiSHealingDB.players = {}; CFG.Say("history wiped", "warn") end, "warn")
end

CFG.PAGES = {
    { name = "Frames",       build = CFG.BuildFrames },
    { name = "Chain Heal",   build = CFG.BuildChain  },
    { name = "Earth Shield", build = CFG.BuildShield },
    { name = "Wheel & Data", build = CFG.BuildWheel  },
}

function CFG.ShowTab(name)
    CFG.tab = name
    for _, t in ipairs(CFG.tabs) do
        local on = (t.name == name)
        t.indicator:SetShown(on)
        t.glow:SetShown(on)
        t.label:SetTextColor(CFG.T.rgb(on and "ink" or "muted"))
        CFG.pages[t.name]:SetShown(on)
    end
end

function CFG.Build()
    if CFG.built then return end
    CFG.built = true

    local f = CreateFrame("Frame", "BiSHealingConfig", UIParent)
    f:SetSize(700, 500); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:SetFrameLevel(120)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end
    f:Hide()
    CFG.tex(f, "BACKGROUND", "frame", 0.98):SetAllPoints()
    CFG.border(f, "accent", 0.55)
    if UISpecialFrames then tinsert(UISpecialFrames, "BiSHealingConfig") end
    f:SetScript("OnUpdate", CFG.Tick)
    CFG.frame = f

    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 1, -1); head:SetPoint("TOPRIGHT", -1, -1); head:SetHeight(64)
    CFG.tex(head, "BACKGROUND", "header"):SetAllPoints()

    -- THE PROMPT IS THE TITLE. No icon beside it -- "BiS>" is the brand (the
    -- header law, BiSTheme 1.1.0). What used to be a static two-tone name is now
    -- a console: the addon's name, then what it is actually doing, rotating.
    --
    -- Budget (landmine #9), left to right across a 700px window:
    --     1   frame border
    --     18  left inset to the prompt
    --     ?   BiS> + the words + the blinking cursor      <- what must fit
    --     16  right inset from the close button
    --     28  close button
    --     1   frame border
    -- 700 - (1 + 18 + 16 + 28 + 1) = 636 for the whole line. Held at 600 so a
    -- long word has air rather than touching the button; the console trims with
    -- an ellipsis past that, which is the net, not the plan.
    CFG.HEAD_BUDGET = 600
    local title = head:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 15, "")
    title:SetPoint("LEFT", 18, 6)
    local ver = CFG.fs(head, "Settings  -  v" .. tostring(VERSION), 10, "dim")
    ver:SetPoint("LEFT", 18, -11)

    if BiSTheme and BiSTheme.Console then
        CFG.con = BiSTheme.Console(title, { width = CFG.HEAD_BUDGET, size = 13 })
        CFG.con:Set("name", "Heal", "accent")
        CFG.Slots()
    else
        -- Console.lua is embedded under Libs/, so this only happens if the TOC
        -- line was lost. Say so in the header rather than showing nothing.
        title:SetText("|cffb980ffBiS>|r |cff4fd0cfHeal|r")
    end
    local x = CreateFrame("Button", nil, head)
    x:SetSize(28, 28); x:SetPoint("RIGHT", -16, 0)
    CFG.tex(x, "BACKGROUND", "field"):SetAllPoints()
    local xbd = CFG.border(x, "edge")
    local xt = CFG.fs(x, "x", 15, "muted"); xt:SetPoint("CENTER", 0, 1)
    x:SetScript("OnEnter", function() xbd:set("accent", 0.8); xt:SetTextColor(CFG.T.rgb("ink")) end)
    x:SetScript("OnLeave", function() xbd:set("edge"); xt:SetTextColor(CFG.T.rgb("muted")) end)
    x:SetScript("OnClick", function() f:Hide() end)
    local hsep = CFG.tex(f, "ARTWORK", "hair")
    hsep:SetPoint("TOPLEFT", 1, -65); hsep:SetPoint("TOPRIGHT", -1, -65); hsep:SetHeight(1)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 1, -66); body:SetPoint("BOTTOMRIGHT", -1, 1)
    local side = CreateFrame("Frame", nil, body)
    side:SetPoint("TOPLEFT"); side:SetPoint("BOTTOMLEFT"); side:SetWidth(168)
    CFG.tex(side, "BACKGROUND", "sidebar"):SetAllPoints()
    local cont = CreateFrame("Frame", nil, body)
    cont:SetPoint("TOPLEFT", side, "TOPRIGHT"); cont:SetPoint("BOTTOMRIGHT")
    CFG.tex(cont, "BACKGROUND", "content"):SetAllPoints()
    local divide = CFG.tex(body, "ARTWORK", "edge")
    divide:SetPoint("TOPLEFT", side, "TOPRIGHT"); divide:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT")
    divide:SetWidth(1)

    for i, spec in ipairs(CFG.PAGES) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(168, 44); b:SetPoint("TOPLEFT", 0, -14 - (i - 1) * 44)
        b.name = spec.name
        b.glow = CFG.tex(b, "BACKGROUND", "accent", 0.10); b.glow:SetAllPoints(); b.glow:Hide()
        b.indicator = CFG.tex(b, "ARTWORK", "accent", 1)
        b.indicator:SetPoint("TOPLEFT"); b.indicator:SetPoint("BOTTOMLEFT")
        b.indicator:SetWidth(3); b.indicator:Hide()
        b.label = CFG.fs(b, spec.name, 13, "muted"); b.label:SetPoint("LEFT", 24, 0)
        b:SetScript("OnEnter", function()
            if CFG.tab ~= spec.name then
                b.glow:SetColorTexture(1, 1, 1, 0.03); b.glow:Show()
                b.label:SetTextColor(CFG.T.rgb("ink2"))
            end
        end)
        b:SetScript("OnLeave", function()
            if CFG.tab ~= spec.name then
                b.glow:Hide(); b.label:SetTextColor(CFG.T.rgb("muted"))
            end
        end)
        b:SetScript("OnClick", function() CFG.ShowTab(spec.name) end)
        CFG.tabs[i] = b

        local page = CreateFrame("Frame", nil, cont)
        page:SetPoint("TOPLEFT", 30, -26); page:SetPoint("BOTTOMRIGHT", -30, 24)
        page.w = 700 - 168 - 60
        page:Hide()
        spec.build(page)
        CFG.pages[spec.name] = page
    end

    CFG.fs(cont, "Everything here is also a /bish command", 10, "dim")
        :SetPoint("BOTTOMLEFT", 30, 8)
end

-- The standing state this addon has to show, refreshed on the window's own
-- ticker. Slots are for state that LASTS; events go through CFG.Say.
function CFG.Slots()
    local con = CFG.con
    if not con then return end

    -- where my Earth Shield is, and how much of it is left
    local charges, who
    -- read fresh every time: whoever is shielded RIGHT NOW, not at login
    local esTarget = NS.ESTarget()
    if esTarget then
        local u = COMM.Unit and COMM.Unit(esTarget)
        if u then
            charges = COMM.Charges and select(1, COMM.Charges(u)) or nil
            who = UnitName(u)
        end
    end
    if charges and charges > 0 then
        con:Set("shield", ("ES %d %s"):format(charges, ShortName(who) or "?"),
                charges <= 1 and "warn" or "good")
    else
        con:Set("shield", nil)
    end

    -- races being lost right now: somebody else's heal lands before mine would
    local sniped = 0
    for _, fr in ipairs(frames) do
        if fr:IsShown() and fr.raceLost then sniped = sniped + 1 end
    end
    con:Set("race", sniped > 0 and (("%d sniped"):format(sniped)) or nil, "warn")

    -- debuffs on the frames that are mine to cure
    local curable = 0
    for _, fr in ipairs(frames) do
        if fr:IsShown() and fr.dispelName then curable = curable + 1 end
    end
    con:Set("cure", curable > 0 and (("%d to cure"):format(curable)) or nil, "warn")

    con:Set("sim", demo.on and "sim" or nil, "accent")
end

-- An event the WINDOW wants to report. Chat is for slash answers; anything the
-- addon says about what it is doing goes to the header instead -- and only
-- falls back to Print when the window has never been opened.
function CFG.Say(text, colour)
    if CFG.con then CFG.con:Say(text, colour) else Print(text) end
end

function CFG.Open()
    CFG.Build()
    CFG.frame:Show()
    CFG.ShowTab(CFG.tab or "Frames")
end

-- The console blinks at 2 Hz and rotates every 3 s, so it needs a ticker; it
-- only runs while the window is up, and the slots are recomputed a fifth as
-- often as the blink because they read auras and frames.
CFG.PAINT_EVERY, CFG.SLOTS_EVERY = 0.2, 1.0
function CFG.Tick(_, elapsed)
    local self = CFG
    self.paintAt = (self.paintAt or 0) + elapsed
    if self.paintAt < self.PAINT_EVERY then return end
    self.paintAt = 0
    self.slotsAt = (self.slotsAt or 0) + self.PAINT_EVERY
    if self.slotsAt >= self.SLOTS_EVERY then self.slotsAt = 0; self.Slots() end
    if self.con then self.con:Paint() end
end

function CFG.Toggle()
    CFG.Build()
    if CFG.frame:IsShown() then CFG.frame:Hide() else CFG.Open() end
end

-- The handle the harness drives, and the only thing this addon publishes to the
-- global namespace besides its saved variables and its named frames.
-- The drag-bar button is created near the top of the file, long before CFG
-- exists. It calls through this field rather than naming CFG directly -- a bare
-- CFG up there would be a nil global, the trap that has bitten this addon five
-- times (bislint's forward-ref rule), and a new chunk local would eat one of the
-- eleven slots this file has left.
UIX.ToggleConfig = CFG.Toggle

BiSHealingUI = {
    OpenConfig = CFG.Open,
    ToggleConfig = CFG.Toggle,
    ConfigSet = function(id, v)
        CFG.Build()
        local c = CFG.controls[id]
        if c and c.set then c.set(v) elseif c and c.click then c.click() end
    end,
    ConfigGet = function(id)
        CFG.Build()
        local c = CFG.controls[id]
        return c and c.get and c.get()
    end,
    -- tab switching, exposed for the same reason the controls are: a window
    -- that cannot be driven headless gets tested by opening it and squinting
    ConfigTab = function(name)
        CFG.Build()
        CFG.ShowTab(name)
        return CFG.tab
    end,
    ConfigTabs = function()
        local out = {}
        for _, spec in ipairs(CFG.PAGES) do out[#out + 1] = spec.name end
        return out
    end,
    ConfigShownTab = function()
        for name, page in pairs(CFG.pages) do if page:IsShown() then return name end end
    end,
    -- the resolved colour for a palette name, so the suite can prove BiSTheme
    -- wins when it is installed and the inline copy only covers for it
    Colour = function(name) return CFG.T.rgb(name) end,
    -- the header console, its budget, and a hand-crank for the ticker
    Console = function() CFG.Build(); return CFG.con end,
    HeadBudget = function() CFG.Build(); return CFG.HEAD_BUDGET end,
    ConsoleTick = function(elapsed) CFG.Build(); CFG.Tick(nil, elapsed or 0.2) end,
    ConfigIDs = function()
        CFG.Build()
        local out = {}
        for id in pairs(CFG.controls) do out[#out + 1] = id end
        table.sort(out)
        return out
    end,
}

-- The brain talks back to the window through this one field: the version nag in
-- the comm code says things here, and it only ever runs at play time, long after
-- both files have loaded.
NS.CFG = CFG
