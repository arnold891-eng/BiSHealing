-- =========================================================================
-- BiS Healing -- UI/options.lua : the /bish settings window, and the Keybinds
--
-- Two windows since 11 Sep 2026:
--
--   * OPTIONS -- BiSTheme's shared kit (Libs\BiSTheme\Options.lua, the 230 px
--     window every BiS addon wears; [[bis-options]] is the law). Every setting
--     that is a switch, a stepper, a seg or a button lives here. The old
--     700x500 four-tab panel is gone; what used to be a slider is a stepper
--     (exact, and it clamps), and the six action buttons are the slash commands
--     they always were (/bish reorder, center, rescan, resetsizes, esplan, peers).
--
--   * KEYBINDS -- the one thing the four kinds cannot do: click a key, press the
--     new one. Ten actions from the bind engine (NS.BINDS in BiSHealing.lua),
--     each on a mouse button, a wheel direction or a keyboard key. Own chrome,
--     same shades as the kit, opened from the options window's "keybinds" row.
--
-- Nothing here decides anything: it reads and writes saved variables, paints
-- chrome, and carries the header console. Every judgement -- who to shield,
-- who is losing a heal race, what a rank is worth -- stays in BiSHealing.lua
-- and is only ever READ from here. The line between the two is the NS block at
-- the bottom of BiSHealing.lua. If a name is not published there, this file
-- cannot reach it, and that is the point.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

-- Captured as locals at load, which is safe ONLY because the TOC runs
-- BiSHealing.lua before this file: every one of these is already published by
-- the time this line runs. Load this file first and they are all silently nil.
local Print, DB, UIX            = NS.Print, NS.DB, NS.UIX
local frames, anchor            = NS.frames, NS.anchor
local WHEEL, SNIPE, COMM        = NS.WHEEL, NS.SNIPE, NS.COMM
local ES_HOLD, demo             = NS.ES_HOLD, NS.demo
local ShortName, Relayout       = NS.ShortName, NS.Relayout
local BuildHealOptions          = NS.BuildHealOptions
local VERSION, PULSE_CAP        = NS.VERSION, NS.PULSE_CAP
local BINDS                     = NS.BINDS

-- Anything that MOVES is fetched through a function instead -- see the note on
-- NS.ESTarget in BiSHealing.lua. A local copy of a moving value is a bug that
-- looks like working code.

-- ONE chunk local for the whole file, as before: everything hangs off CFG.
local CFG = { built = false, byKey = {} }

-- ------------------------------------------------------------ palette --
-- BiSTheme if it is installed, otherwise an inline copy of the same tokens.
-- RESOLVED PER CALL, PER COLOUR NAME -- never captured at file load: the client
-- loads addons alphabetically, BiSHealing before BiSTheme, so _G.BiSTheme is
-- nil while this file runs, every session, on every machine.
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

-- the five chrome shades, the same values the kit carries
function CFG.hx(h)
    return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
end
CFG.SH = {
    frame   = { CFG.hx("0d0b18") },
    header  = { CFG.hx("141127") },
    field   = { CFG.hx("17132e") },
    hair    = { CFG.hx("2a2446") },
    edge    = { CFG.hx("3a3260") },
}
function CFG.shade(name, a) local c = CFG.SH[name]; return c[1], c[2], c[3], a or 1 end

function CFG.tex(parent, layer, name, a)
    local t = parent:CreateTexture(nil, layer)
    -- Both branches pass a FULL argument list on purpose: `cond and select(1,
    -- T.rgba(n,a)) or CFG.shade(n,a)` truncates to one value and the client
    -- throws, killing the whole window. The harness errors on it too.
    if CFG.SH[name] then t:SetColorTexture(CFG.shade(name, a))
    else t:SetColorTexture(CFG.T.rgba(name, a)) end
    return t
end

function CFG.fs(parent, text, size, colorName)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size or 12, "")
    f:SetText(text or "")
    f:SetTextColor(CFG.T.rgb(colorName or "ink"))
    return f
end

-- ----------------------------------------------------------- effects --
-- Live effects. Anything a setting changes that is not just a colour next tick
-- happens here -- and siblings are reached through the tables they live on
-- (WHEEL, SNIPE, UIX), never a bare name.
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

-- An event the WINDOW wants to report. Chat is for slash answers; anything the
-- addon says about what it is doing goes to the header instead -- and only
-- falls back to Print when the window has never been opened.
function CFG.Say(text, colour)
    if CFG.con then CFG.con:Say(text, colour) else Print(text) end
end

-- ------------------------------------------------------- the option list --
-- Labels are plain words under ~24 characters: the kit's budget is W - 12 - 110
-- and BiSTheme.Fit is the net, not the plan. `key` is what ConfigSet / ConfigGet
-- address; every toggle's `set` writes the same saved-variable key the slash
-- commands read, then CFG.Apply for the side effects.
local function tog(key, label, dbKey, default)
    return { key = key, kind = "toggle", label = label,
        get = function(db) local v = db[dbKey]; if v == nil then return default end; return v end,
        set = function(db, on) db[dbKey] = on and true or false; CFG.Apply() end }
end

function CFG.OptionSections()
    return {
        { title = "frames", options = {
            tog("shown", "show the frames", "shown", true),
            tog("locked", "lock the anchor", "locked", true),
            tog("pets", "show pets", "pets", true),
            { key = "nameLen", kind = "step", label = "name length", min = 3, max = 12, step = 1,
              get = function(db) return db.nameLen or UIX.NAME_MAX end,
              set = function(db, v) db.nameLen = v; CFG.Apply() end,
              show = function(db) return (db.nameLen or UIX.NAME_MAX) .. " letters" end },
            { key = "bars", kind = "seg", label = "bar colour", values = { "black", "bands" },
              get = function(db) return db.plainBars and "black" or "bands" end,
              set = function(db, v) db.plainBars = (v == "black"); CFG.Apply() end },
            { key = "redPct", kind = "step", label = "red at this much of a downrank", min = 0.5, max = 1.5, step = 0.05,
              get = function(db) return db.redPct or 1 end,
              set = function(db, v) db.redPct = v end,
              show = function(db) return ("%.0f%%"):format((db.redPct or 1) * 100) end },
            tog("corners", "role corner markers", "corners", true),
            tog("pulse", "pulse under damage", "pulse", true),
            { key = "pulseCap", kind = "step", label = "how many may pulse", min = 1, max = 6, step = 1,
              get = function(db) return db.pulseCap or PULSE_CAP end,
              set = function(db, v) db.pulseCap = v end,
              show = function(db) return tostring(db.pulseCap or PULSE_CAP) end },
            tog("totemRange", "totem reach", "totemRange", true),
            tog("dispel", "curable debuffs", "dispel", true),
            -- The minimap button does not live in the saved-variable table the
            -- other toggles read: it keeps its own corner (angle and hidden),
            -- so /bish reset can clear the frames without losing where the
            -- button sits. Hence its own get/set rather than tog().
            { key = "minimap", kind = "toggle", label = "minimap button",
              get = function() return not (NS.MM and NS.MM.Hidden()) end,
              set = function(_, on) if NS.MM then NS.MM.SetHidden(not on) end end },
        } },
        { title = "chain heal", options = {
            tog("bounceLines", "bounce lines", "bounceLines", true),
            tog("goldChains", "gold on a full chain", "goldChains", true),
            tog("celebrate", "celebrate a full chain", "celebrate", true),
            tog("critBrag", "announce a triple crit", "critBrag", true),
            { key = "bragGap", kind = "step", label = "not more often than", min = 5, max = 120, step = 5,
              get = function(db) return db.bragGap or UIX.BRAG_GAP end,
              set = function(db, v) db.bragGap = v end,
              show = function(db) return (db.bragGap or UIX.BRAG_GAP) .. " s" end },
            tog("healRace", "heal race counter", "healRace", true),
            tog("incomingFill", "incoming-heal fill", "incomingFill", true),
            tog("castCounter", "castable-heals counter", "castCounter", true),
            tog("fsr", "five-second rule", "fsr", true),
            tog("rpm", "mana gauge", "rpm", true),
        } },
        { title = "earth shield", options = {
            { key = "esQuiet", kind = "step", label = "quiet above", min = 1, max = 6, step = 1,
              get = function(db) return db.esQuiet or ES_HOLD.quiet end,
              set = function(db, v) db.esQuiet = v end,
              show = function(db) local v = db.esQuiet or ES_HOLD.quiet; return v .. (v == 1 and " charge" or " charges") end },
            tog("nsPip", "Nature's Swiftness pip", "nsPip", true),
            tog("giftBadge", "Gift badge", "giftBadge", true),
        } },
        { title = "wheel and keys", options = {
            { key = "wheelMode", kind = "seg", label = "wheel heals", values = { "off", "one", "two" },
              get = function(db)
                  if not db.wheel then return "off" end
                  return db.wheelStrict and "two" or "one"
              end,
              set = function(db, v)
                  db.wheel = (v ~= "off"); db.wheelStrict = (v == "two"); CFG.Apply()
              end },
            tog("trinkets", "trinkets on shift", "trinkets", true),
            { key = "keybinds", kind = "button", label = "click a key, press a new one", button = "keybinds",
              action = function() CFG.ToggleBinds(true) end },
            { key = "demo", kind = "button", label = "walk every feature", button = "demo",
              action = function() SlashCmdList.BISHEALING(demo.on and "sim off" or "sim on") end },
        } },
    }
end

-- ---------------------------------------------------- the options window --
function CFG.Build()
    if CFG.built then return CFG.frame end
    if not (BiSTheme and BiSTheme.Options) then
        -- Options.lua is embedded under Libs/, so this only happens if the TOC
        -- line was lost. Say so once rather than throwing on every /bish.
        Print("Libs\\BiSTheme\\Options.lua did not load -- reinstall the addon")
        return nil
    end
    CFG.built = true
    local f = BiSTheme.Options("BiSHealingOptions", BiSTheme.OPTIONS.W, "Heal")
    CFG.frame = f
    f:Recenter(60)
    for _, section in ipairs(CFG.OptionSections()) do
        f:Section(section.title)
        for _, opt in ipairs(section.options) do
            f:Row(opt, DB())
            CFG.byKey[opt.key] = opt
        end
    end
    f:Fit()
    CFG.con = f.con
    CFG.HEAD_BUDGET = BiSTheme.OPTIONS.W - 15 - 8
    -- The standing state rides the header prompt, as it did on the old window:
    -- the kit paints its console at 10 Hz on its own ticker; the slots are read
    -- off frames and auras, so they refresh a fifth as often, here.
    f:HookScript("OnUpdate", function(_, dt) CFG.Tick(nil, dt) end)
    -- a repaint elsewhere when a row changes: the Keybinds window shows the
    -- trinket rule in its hint line, and the wheel seg gates four of its rows
    f.onChange = function() if CFG.binds and CFG.binds:IsShown() then CFG.PaintBinds() end end
    return f
end

-- The standing state this addon has to show, refreshed once a second. Slots
-- are for state that LASTS; events go through CFG.Say.
function CFG.Slots()
    -- the same standing state on both prompts: the options window's and the
    -- psi plate's above the pyramid. One tiny console object that fans out.
    local con = CFG.fan
    if not con then
        con = {}
        -- the plate does not carry the Earth Shield slot: Arn wants the HUD
        -- for glaring issues, and the pips already show the shield
        CFG.PLATE_SKIP = { shield = true }
        function con:Set(k, v, c)
            if CFG.con then CFG.con:Set(k, v, c) end
            if UIX.plateCon and not CFG.PLATE_SKIP[k] then UIX.plateCon:Set(k, v, c) end
        end
        function con:Say(t, c, plateToo)
            if CFG.con then CFG.con:Say(t, c) end
            if UIX.plateCon and plateToo ~= false then UIX.plateCon:Say(t, c) end
        end
        CFG.fan = con
    end
    if not (CFG.con or UIX.plateCon) then return end

    -- where my Earth Shield is, and how much of it is left
    local charges, who
    local esTarget = NS.ESTarget()      -- read fresh: whoever is shielded NOW
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
        CFG.shieldOn = who
    else
        con:Set("shield", nil)
        -- the moment it runs out is said on the options window only; the
        -- plate stays out of shield tracking (the pips carry it)
        if CFG.shieldOn then
            con:Say(("shield gone on %s"):format(ShortName(CFG.shieldOn) or "?"), "warn", false)
            CFG.shieldOn = nil
        end
    end

    -- Nature's Swiftness: up, or how long until it is. Said once when it
    -- comes back, because that is the second you reach for it.
    local ready = WHEEL.Ready()
    if ready == nil then
        con:Set("ns", nil)
    elseif ready then
        con:Set("ns", "NS up", "good")
        if CFG.nsDown then con:Say("Nature's Swiftness up", "good") end
        CFG.nsDown = false
    else
        local left = ""
        -- Not on a client that hides its numbers: a cooldown there is a SECRET, and "st > 0" is
        -- refused before the format string ever runs. See the mana block below for what that
        -- costs when it is missed.
        if GetSpellCooldown and not (NS.SECRET or (NS.Blind and NS.Blind())) then
            local st, dur = GetSpellCooldown(WHEEL.NS)
            if st and dur and st > 0 then left = (" %ds"):format(math.max(0, st + dur - GetTime())) end
        end
        con:Set("ns", "NS" .. left, "muted")
        CFG.nsDown = true
    end

    -- Mana, as a fraction: the counter says casts, this says how deep.
    --
    -- NOT ON FOREVER. Arn, 19 Sep, 27 copies of the same error: "attempt to perform arithmetic on
    -- local 'm' (a secret number value, while execution tainted by 'BiSHealing')". The maximum
    -- came back as a plain 505 and the CURRENT mana came back secret, which is the whole shape of
    -- that client: a number you may hand to a bar, never one you may divide. A percentage is
    -- arithmetic and then a format string, so there is nothing to salvage here - the slot simply
    -- does not exist on a client that hides the number.
    if UnitPower and UnitPowerMax and not NS.SECRET then
        local m, mx = UnitPower("player", 0), UnitPowerMax("player", 0)
        if mx and mx > 0 then
            local pct = math.floor(m / mx * 100 + 0.5)
            con:Set("mana", ("mana %d%%"):format(pct), pct < 30 and "warn" or "muted")
        end
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

CFG.SLOTS_EVERY = 0.5      -- Arn: "updating every 0.5 seconds"
-- ticked by the options window's OnUpdate while it is up, and by the brain's
-- bar tick for the plate (NS.CFG.Tick), so the plate's slots move with the
-- options window closed
-- THE NET. This is a cosmetic header on a half-second ticker: whatever it gets wrong, it must
-- not be twenty-seven copies of the same red line in the error frame, which is what a secret
-- value cost on 19 Sep. A secret-value error stops the slots for the session and says so ONCE;
-- anything else is a real bug and is raised exactly as it was, because a ticker that swallows
-- everything is a ticker nobody can debug.
function CFG.Tick(_, elapsed)
    CFG.slotsAt = (CFG.slotsAt or 0) + (elapsed or 0)
    if CFG.slotsAt < CFG.SLOTS_EVERY then return end
    CFG.slotsAt = 0
    if CFG.slotsOff then return end
    local ok, err = pcall(CFG.Slots)
    if ok then return end
    if tostring(err):find("secret", 1, true) then
        CFG.slotsOff = true
        Print("the header's live numbers are off: this client keeps them secret")
        return
    end
    error(err, 0)
end

function CFG.Open()
    local f = CFG.Build()
    if f then f:Toggle(true); f:Paint() end
end

function CFG.Toggle()
    local f = CFG.Build()
    if f then f:Toggle() if f:IsShown() then f:Paint() end end
end

-- ---------------------------------------------------- the Keybinds window --
-- One row per action: its name, and the key it sits on as a flat button.
-- Click the key and the window listens: the next key, mouse button or wheel
-- turn becomes the bind; Escape cancels; Backspace or Delete unbinds. A key
-- another action held moves here and the header says whose it was.
--
-- Keyboard capture is the window's own OnKeyDown, turned on only while a row
-- is listening, with propagation off so the key does not also move him.
-- Mouse buttons and the wheel are caught by a full-window overlay that only
-- exists while listening, so the rows underneath cannot be clicked meanwhile.
CFG.BINDS_W, CFG.BINDS_ROW, CFG.BINDS_KEY_W = 300, 16, 118

CFG.MOUSE = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }
CFG.IGNORE_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
    UNKNOWN = true,
}

-- the modifier keys held right now, in the client's ALT-CTRL-SHIFT order
function CFG.Mods()
    local m = ""
    if IsAltKeyDown and IsAltKeyDown() then m = m .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then m = m .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then m = m .. "SHIFT-" end
    return m
end

function CFG.BuildBinds()
    if CFG.binds then return CFG.binds end
    local W, ROW = CFG.BINDS_W, CFG.BINDS_ROW
    local f = CreateFrame("Frame", "BiSHealingKeybinds", UIParent)
    f:SetSize(W, ROW)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    CFG.tex(f, "BACKGROUND", "frame", 0.45):SetAllPoints()
    CFG.binds = f

    -- header: the prompt, one x -- the header law, same 16 px bar as the kit
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(ROW)
    CFG.tex(head, "BACKGROUND", "header", 0.5):SetAllPoints()
    local hair = CFG.tex(head, "BORDER", "edge")
    hair:SetPoint("BOTTOMLEFT"); hair:SetPoint("BOTTOMRIGHT"); hair:SetHeight(1)
    local title = CFG.fs(head, "", 8, "ink")
    title:SetPoint("LEFT", head, "LEFT", 4, 0)
    if BiSTheme and BiSTheme.Console then
        f.con = BiSTheme.Console(title, { width = W - 15 - 8 })
        f.con:Set("name", "Keybinds", "accent")
    else
        title:SetText("|cffb980ffBiS>|r Keybinds")
    end
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local x = CreateFrame("Button", nil, head)
    x:SetSize(12, 12); x:SetPoint("RIGHT", head, "RIGHT", -3, 0)
    CFG.tex(x, "BACKGROUND", "field"):SetAllPoints()
    local xt = CFG.fs(x, "x", 8, "warn"); xt:SetPoint("CENTER", 0, 0)
    x:SetScript("OnClick", function() CFG.ToggleBinds(false) end)

    -- one row per action
    f.rows = {}
    local y = -ROW
    for i, a in ipairs(BINDS.ACTIONS) do
        local row = CreateFrame("Frame", nil, f)
        row:SetPoint("TOPLEFT", 0, y); row:SetPoint("TOPRIGHT", 0, y); row:SetHeight(ROW)
        if i % 2 == 0 then CFG.tex(row, "BACKGROUND", "field", 0.35):SetAllPoints() end
        row.name = CFG.fs(row, a.label, 8, "ink2")
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name:SetJustifyH("LEFT")
        local kb = CreateFrame("Button", nil, row)
        kb:SetSize(CFG.BINDS_KEY_W, 12); kb:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        CFG.tex(kb, "BACKGROUND", "field"):SetAllPoints()
        kb.label = CFG.fs(kb, "", 8, "ink"); kb.label:SetPoint("CENTER", 0, 0)
        kb:SetScript("OnClick", function() CFG.Capture(a.key) end)
        kb:SetScript("OnEnter", function() if not CFG.capturing then kb.label:SetTextColor(CFG.T.rgb("accent")) end end)
        kb:SetScript("OnLeave", function() CFG.PaintBinds() end)
        row.key, row.action = kb, a
        f.rows[i] = row
        y = y - ROW
    end

    -- foot: the hint line, and reset
    local foot = CreateFrame("Frame", nil, f)
    foot:SetPoint("TOPLEFT", 0, y); foot:SetPoint("TOPRIGHT", 0, y); foot:SetHeight(ROW)
    f.hint = CFG.fs(foot, "", 8, "dim")
    f.hint:SetPoint("LEFT", foot, "LEFT", 6, 0)
    local reset = CreateFrame("Button", nil, foot)
    reset:SetSize(60, 12); reset:SetPoint("RIGHT", foot, "RIGHT", -6, 0)
    CFG.tex(reset, "BACKGROUND", "field"):SetAllPoints()
    local rt = CFG.fs(reset, "reset all", 8, "warn"); rt:SetPoint("CENTER", 0, 0)
    reset:SetScript("OnClick", function()
        CFG.StopCapture()
        BINDS.ResetAll()
        CFG.PaintBinds()
        CFG.BindsSay("every key back to its default", "warn")
    end)
    f.resetBtn = reset
    f:SetHeight(ROW + #BINDS.ACTIONS * ROW + ROW + 4)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

    -- the listener: keyboard on the window itself, mouse on an overlay that
    -- only shows while a row is listening
    f:EnableKeyboard(false)
    f:SetScript("OnKeyDown", function(_, key) CFG.Heard(key) end)
    local cover = CreateFrame("Frame", nil, f)
    cover:SetAllPoints()
    cover:SetFrameLevel((f:GetFrameLevel() or 1) + 20)
    cover:EnableMouse(true)
    cover:EnableMouseWheel(true)
    cover:SetScript("OnMouseDown", function(_, button) CFG.HeardMouse(button) end)
    cover:SetScript("OnMouseWheel", function(_, delta) CFG.HeardWheel(delta) end)
    cover:Hide()
    f.cover = cover

    if UISpecialFrames then
        local listed = false
        for _, n in ipairs(UISpecialFrames) do if n == "BiSHealingKeybinds" then listed = true end end
        if not listed then table.insert(UISpecialFrames, "BiSHealingKeybinds") end
    end
    if f.con then
        f:SetScript("OnUpdate", function(_, dt)
            f.elapsed = (f.elapsed or 0) + dt
            if f.elapsed >= 0.1 then f.elapsed = 0; f.con:Paint() end
        end)
    end
    f:Hide()
    CFG.PaintBinds()
    return f
end

function CFG.BindsSay(text, tone)
    local f = CFG.binds
    if f and f.con then f.con:Say(text, tone) else Print(text) end
end

-- every row from the engine: the key it has, dimmed when the wheel switch has
-- that family off, "listening..." on the one being set
function CFG.PaintBinds()
    local f = CFG.binds
    if not f then return end
    local db = DB()
    for _, row in ipairs(f.rows) do
        local a = row.action
        local keystr = BINDS.Get(a.key)
        local off = BINDS.WHEEL_KEYS[a.key] and not db.wheel
        if CFG.capturing == a.key then
            row.key.label:SetText("listening...")
            row.key.label:SetTextColor(CFG.T.rgb("accent"))
        else
            row.key.label:SetText(BINDS.Pretty(keystr))
            row.key.label:SetTextColor(CFG.T.rgb(
                (not keystr) and "dim" or (off and "muted" or "ink")))
        end
        row.name:SetTextColor(CFG.T.rgb(off and "dim" or "ink2"))
    end
    f.hint:SetText(CFG.capturing
        and "press a key, a mouse button or the wheel -- Esc cancels, Backspace unbinds"
        or ("click a key to change it" .. (db.trinkets and " -- shift presses fire trinkets" or "")))
end

function CFG.Capture(key)
    local f = CFG.BuildBinds()
    if not f then return end
    CFG.capturing = key
    f:EnableKeyboard(true)
    if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(false) end
    f.cover:Show()
    CFG.PaintBinds()
end

function CFG.StopCapture()
    local f = CFG.binds
    CFG.capturing = nil
    if not f then return end
    f:EnableKeyboard(false)
    if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
    f.cover:Hide()
    CFG.PaintBinds()
end

-- the one place a heard key becomes a bind
function CFG.Bind(keystr)
    local key = CFG.capturing
    if not key then return end
    local a = BINDS.Action(key)
    local ok, stolen = BINDS.Set(key, keystr)
    CFG.StopCapture()
    if not ok then return end
    local shown = keystr and BINDS.Pretty(BINDS.Get(key)) or "unbound"
    if stolen then
        CFG.BindsSay(("%s = %s, taken off %s"):format(a.label, shown, stolen), "warn")
    elseif InCombatLockdown() then
        CFG.BindsSay(("%s = %s -- lands when the fight ends"):format(a.label, shown), "gold")
    else
        CFG.BindsSay(("%s = %s"):format(a.label, shown), "good")
    end
end

function CFG.Heard(key)
    if not CFG.capturing then return end
    if key == "ESCAPE" then CFG.StopCapture(); CFG.BindsSay("kept as it was", "muted"); return end
    if key == "BACKSPACE" or key == "DELETE" then CFG.Bind(false); return end
    if CFG.IGNORE_KEYS[key] then return end       -- a modifier alone is not a key
    CFG.Bind(CFG.Mods() .. key)
end

function CFG.HeardMouse(button)
    if not CFG.capturing then return end
    local n = CFG.MOUSE[button]
    if not n then return end
    CFG.Bind(CFG.Mods() .. "BUTTON" .. n)
end

function CFG.HeardWheel(delta)
    if not CFG.capturing then return end
    CFG.Bind(CFG.Mods() .. ((delta or 0) > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
end

function CFG.ToggleBinds(want)
    local f = CFG.BuildBinds()
    if not f then return end
    if want == nil then want = not f:IsShown() end
    if want then CFG.PaintBinds(); f:Show() else CFG.StopCapture(); f:Hide() end
end

-- ------------------------------------------------------------ the seam --
-- The drag-bar button is created near the top of the brain, long before CFG
-- exists. It calls through this field rather than naming CFG directly.
UIX.ToggleConfig = CFG.Toggle

-- The handle the harness drives, and the only thing this addon publishes to the
-- global namespace besides its saved variables and its named frames.
BiSHealingUI = {
    OpenConfig = CFG.Open,
    ToggleConfig = CFG.Toggle,
    -- the same rows by key: each goes through the row's own setter, never the
    -- saved variable, so the tests and the window cannot disagree
    ConfigSet = function(key, v)
        CFG.Build()
        local opt = CFG.byKey[key]
        if not opt then return false end
        if opt.action then opt.action(DB()); return true end
        if opt.kind == "step" then
            v = tonumber(v) or opt.min
            if v < opt.min then v = opt.min elseif v > opt.max then v = opt.max end
        end
        opt.set(DB(), v)
        if CFG.frame and CFG.frame:IsShown() then CFG.frame:Paint() end
        return true
    end,
    ConfigGet = function(key)
        CFG.Build()
        local opt = CFG.byKey[key]
        return opt and opt.get and opt.get(DB())
    end,
    ConfigIDs = function()
        CFG.Build()
        local out = {}
        for key in pairs(CFG.byKey) do out[#out + 1] = key end
        table.sort(out)
        return out
    end,
    -- the resolved colour for a palette name, so the suite can prove BiSTheme
    -- wins when it is installed and the inline copy only covers for it
    Colour = function(name) return CFG.T.rgb(name) end,
    -- the header console, its budget, and a hand-crank for the slot ticker
    Console = function() CFG.Build(); return CFG.con end,
    HeadBudget = function() CFG.Build(); return CFG.HEAD_BUDGET end,
    ConsoleTick = function(elapsed) CFG.Build(); CFG.Tick(nil, elapsed or 0.2) end,
    -- the Keybinds window, driven headless: open it, start listening on a row,
    -- and feed it what the client would
    Keybinds = function(want) CFG.ToggleBinds(want); return CFG.binds end,
    Capture = CFG.Capture,
    Heard = CFG.Heard,
    HeardMouse = CFG.HeardMouse,
    HeardWheel = CFG.HeardWheel,
    Capturing = function() return CFG.capturing end,
    BindRows = function() CFG.BuildBinds(); return CFG.binds.rows end,
}

-- The brain talks back to the window through this one field: the version nag in
-- the comm code says things here, and it only ever runs at play time.
NS.CFG = CFG
