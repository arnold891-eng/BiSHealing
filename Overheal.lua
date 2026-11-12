--[[
  BiSHealing :: Overheal.lua - THE OVER WORD on the radar (12 Nov 2026).

  Arn: "can we work on an overheal for the radar like the los and range" - "more than half, both" (on hover AND on the
  click; the word shows when more than half the heal would be wasted).

  Forever never lets an addon know a teammate's health, so the addon never decides. A StatusBar does: its max is how
  much they are missing (UnitHealthMissing(unit, true) - a secret, minus what is already coming in), its value is half
  your heal (a plain number from the spell's own tooltip). Half the heal at or past what they miss = the bar is FULL =
  more than half would be wasted. The bar is OV.SPAN pixels wide, never seen, and ends at a small clipping window under
  the pip; the word OVER hangs off the end of the fill. Full, the word sits in the window. Short of full, even by 1%, it
  is OV.SPAN / 100 pixels to the left - outside, clipped away. The client compares; the addon only hands it two numbers.
  (The trick is DoesItDie's, proven on our cells by the heal ghost probe, 23 Oct - memory: idea-heal-ghost.)

  WHICH HEAL:
    * HOVER - the pip under the mouse: your LEFT-click heal for the modifier held now (shift / ctrl / alt switch it,
      MODIFIER_STATE_CHANGED), followed while you hover (UNIT_HEALTH / UNIT_HEAL_PREDICTION for that one unit only).
    * CLICK - the heal on the button you pressed: measured AT the click (PostClick, before the cast starts - once it does,
      the client counts your own heal as incoming and every heal would look wasted), shown when the cast really starts
      (UNIT_SPELLCAST_START, or _SUCCEEDED for an instant), held still and faded by itself in OV.FLASH_FOR.
  A heal's size: the tooltip's "for X to Y", the middle, per bind (name + rank, the highest when the bind is bare),
  learned out of a fight and remembered (OV.cache); a heal over time or a party heal is not judged. Nothing ticks:
  the word moves on events, and only the hovered unit is listened to.

  Switches: the radar look (RD.On), the grid's click words (`flash`), and its own `overWord` (/bish overword on|off).
]]
local ADDON, NS = ...
NS = NS or {}

local OV = {}
NS.OV = OV

OV.SHARE = 0.5          -- "more than half": OVER when half the heal reaches what they are missing
OV.SPAN = 10000         -- the hidden bar: 1% short of full moves the word 100 px - wholly out of its window, never half
OV.W, OV.H = 68, 14     -- the window under the pip the word shows in (OVER/H and its outline, with room)
OV.FLASH_FOR = 1.2      -- the click's flash, the grid's own length (FG.FLASH_FOR)
OV.MATCH_FOR = 0.6      -- a cast that starts this long after the click is the click's
OV.COLOUR = { 1.00, 0.24, 0.92 }    -- the cockpit's magenta, as your target's crosshair (Arn, 12 Nov: "magenta")
OV.WORD = "OVER/H"                   -- Arn, 12 Nov: "Over/H" - overheal, short
OV.SLOT = { LeftButton = "left", RightButton = "right", MiddleButton = "middle", Button4 = "button4", Button5 = "button5" }

local function secret(v) return NS.Secret and NS.Secret(v) or false end
local function plain(v) if v == nil or secret(v) then return nil end return v end
local function now() return (GetTime and GetTime()) or 0 end

--- On: the radar look is up, the click words are on, and this word is on.
function OV.On()
    local d = NS.DB and NS.DB() or {}
    local RD = NS.RD
    return (RD and RD.On and RD.On()) and d.flash ~= false and d.overWord ~= false or false
end

-- ------------------------------------------------------------------ the heal a click would cast

OV.cache = {}
--- Spells changed or a fight ended: sizes are read again.
function OV.Forget() OV.cache = {} end

--- A bind's spell id: the rank named on it ("Healing Wave(Rank 7)"), else the highest rank you have.
function OV.SpellOf(cast)
    if type(cast) ~= "string" or cast == "" then return nil end
    local FM = NS.FM
    if not (FM and FM.Ranks) then return nil end
    local name, rank = cast:match("^(.-)%((.-)%)$")
    name = name or cast
    local ranks = FM.Ranks(name)
    if #ranks == 0 then return nil end
    local pick = ranks[#ranks]
    if rank then
        for _, r in ipairs(ranks) do if r.rank == rank then pick = r end end
    end
    return type(pick.spell) == "number" and pick.spell or nil
end

--- The middle of a heal's "for X to Y", or nil (not a heal we can judge, or its text is not loaded yet).
function OV.HealOf(cast)
    if type(cast) ~= "string" or cast == "" then return nil end
    local c = OV.cache[cast]
    if c ~= nil then return c or nil end
    local id = OV.SpellOf(cast)
    local S = C_Spell
    local desc
    if id and S and S.GetSpellDescription then
        local ok, t = pcall(S.GetSpellDescription, id)
        if ok then desc = plain(t) end
    end
    local p = desc and NS.FE and NS.FE.Parse and NS.FE.Parse(desc)
    local amount = p and not p.hot and not p.partial and type(p.lo) == "number" and type(p.hi) == "number"
        and (p.lo + p.hi) / 2 or nil
    if amount and amount <= 0 then amount = nil end
    -- remembered, a "no" too (false); a blank text (not loaded yet) is asked again next time
    if amount or (type(desc) == "string" and desc ~= "") then OV.cache[cast] = amount or false end
    return amount
end

--- The modifier held now, as the binds spell it.
function OV.Mod()
    if IsShiftKeyDown and IsShiftKeyDown() then return "shift-" end
    if IsControlKeyDown and IsControlKeyDown() then return "ctrl-" end
    if IsAltKeyDown and IsAltKeyDown() then return "alt-" end
    return ""
end

--- The bind on a button + modifier when it is a spell of ours (never with Clique in charge, never a ping).
function OV.BindFor(slotKey, mod)
    local FM = NS.FM
    if not (FM and FM.Get) or (FM.CliqueOn and FM.CliqueOn()) then return nil end
    local cast = FM.Get(mod or "", slotKey or "left")
    if type(cast) ~= "string" or cast == "" then return nil end
    if FM.PingOf and FM.PingOf(cast) then return nil end
    return cast
end

-- ------------------------------------------------------------------ the word under a pip

--- A pip's word: a clipping window under its click word, the measuring bar ending at it, OVER on the fill's end.
--- Plain frames on the radar (no secure parent, nothing protected), built the first time a pip needs one.
function OV.Build(sp)
    if sp.over then return sp.over end
    local host = (sp.heal and sp.heal.GetParent and sp.heal:GetParent()) or UIParent
    local o = {}
    local win = CreateFrame("Frame", nil, host)
    win:SetSize(OV.W, OV.H)
    win:SetClipsChildren(true)
    OV.Anchor(sp, win)
    if win.SetFrameLevel and sp.los and sp.los.GetFrameLevel then
        local lvl = sp.los:GetFrameLevel()
        if type(lvl) == "number" then win:SetFrameLevel(lvl) end
    end
    local bar = CreateFrame("StatusBar", nil, host)
    bar:SetSize(OV.SPAN, 2)
    bar:SetPoint("RIGHT", win, "LEFT", 0, 0)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetAlpha(0)                                       -- never seen: it only measures
    local word = win:CreateFontString(nil, "OVERLAY")
    if word.SetFont then word:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE") end
    word:SetPoint("LEFT", bar:GetStatusBarTexture(), "RIGHT", 4, 0)
    word:SetText(OV.WORD)
    word:SetTextColor(OV.COLOUR[1], OV.COLOUR[2], OV.COLOUR[3], 1)
    if win.CreateAnimationGroup then
        local ok, g = pcall(win.CreateAnimationGroup, win)
        if ok and g then
            local a = g:CreateAnimation("Alpha")
            a:SetFromAlpha(1) a:SetToAlpha(0) a:SetDuration(OV.FLASH_FOR)
            if g.SetToFinalAlpha then g:SetToFinalAlpha(true) end
            o.fade = g
        end
    end
    win:Hide()
    bar:Hide()
    o.win, o.bar, o.word, o.sp = win, bar, word, sp
    sp.over = o
    return o
end

--- Where the word sits: under the click word on the radar; under the BOX in the engineer's console, where the click word
--- is in the middle of the box (Engineer.lua). Out of a fight (the layouts call it again).
function OV.Anchor(sp, win)
    win = win or (sp.over and sp.over.win)
    if not win then return end
    win:ClearAllPoints()
    local con = NS.EN and NS.EN.Console and NS.EN.Console()
    if con or not sp.los then win:SetPoint("TOP", sp.heal, "BOTTOM", 0, -1)
    else win:SetPoint("TOP", sp.los, "BOTTOM", 0, 3) end
end

--- Hand the bar its two numbers: max = what the unit is missing (secret, incoming heals taken off), value = the share
--- of the heal. False when the client refused either.
function OV.Hand(o, unit, heal)
    if not (unit and type(heal) == "number" and UnitHealthMissing) then return false end
    local okM, miss = pcall(UnitHealthMissing, unit, true)
    if not okM then return false end
    if not secret(miss) and miss == nil then return false end
    -- the low end just under 0: a full-health teammate (missing 0) is a full bar, never an empty range
    if not pcall(o.bar.SetMinMaxValues, o.bar, -1, miss) then return false end
    if not pcall(o.bar.SetValue, o.bar, heal * OV.SHARE) then return false end
    return true
end

local function hide(o)
    if not o then return end
    if o.fade then o.fade:Stop() end
    o.win:Hide()
    o.bar:Hide()
    if o.sp and NS.EN then NS.EN.Ghost(o.sp, nil) end
end
local function show(o)
    o.win:SetAlpha(1)
    o.bar:Show()
    o.win:Show()
end

-- ------------------------------------------------------------------ hover

local ev = CreateFrame("Frame")
OV.events = ev

--- Listen to one unit's health (the hovered one), or to nobody.
function OV.Listen(unit)
    if not ev.UnregisterEvent then return end
    ev:UnregisterEvent("UNIT_HEALTH")
    ev:UnregisterEvent("UNIT_HEAL_PREDICTION")
    OV.listening = nil
    if unit and ev.RegisterUnitEvent then
        pcall(ev.RegisterUnitEvent, ev, "UNIT_HEALTH", unit)
        pcall(ev.RegisterUnitEvent, ev, "UNIT_HEAL_PREDICTION", unit)
        OV.listening = unit
    end
end

local function flashing(o) return o and o.flashUntil and now() < o.flashUntil end

--- The hovered pip's word, for your left-click heal now. Answers true when the word is armed.
function OV.PaintHover()
    local sp = OV.hover
    if not sp then return false end
    local o = sp.over
    if flashing(o) or OV.casting then return false end    -- a flash, or your own cast in the air, holds the word still
    local heal = OV.On() and sp.unit and OV.HealOf(OV.BindFor("left", OV.Mod()))
    if not heal then hide(o) OV.Listen(nil) return false end
    o = OV.Build(sp)
    if not OV.Hand(o, sp.unit, heal) then hide(o) OV.Listen(nil) return false end
    show(o)
    if NS.EN then NS.EN.Ghost(sp, heal) end              -- the engineer's box: your heal as a ghost after their health
    if OV.listening ~= sp.unit then OV.Listen(sp.unit) end
    return true
end

function OV.Enter(sp)
    OV.hover = sp
    return OV.PaintHover()
end

function OV.Leave(sp)
    if OV.hover == sp then OV.hover = nil end
    OV.Listen(nil)
    if not flashing(sp and sp.over) then hide(sp and sp.over) end
    if NS.EN and sp then NS.EN.Ghost(sp, nil) end
end

-- ------------------------------------------------------------------ the click

--- PostClick on a pip: measure NOW (before the cast starts), show when it does.
function OV.Click(sp, button)
    OV.pending = nil
    if not (OV.On() and sp and sp.unit) then return false end
    local cast = OV.BindFor(OV.SLOT[button or "LeftButton"] or "left", OV.Mod())
    local heal = OV.HealOf(cast)
    if not heal then return false end
    local o = OV.Build(sp)
    if not OV.Hand(o, sp.unit, heal) then return false end
    OV.pending = { sp = sp, at = now(), name = (cast:match("^(.-)%(") or cast) }
    return true
end

--- Your cast started (or an instant went off): the click's word, held still, fading by itself.
function OV.CastBegan(spellID)
    local p = OV.pending
    OV.pending = nil
    if not p or now() - p.at > OV.MATCH_FOR then return false end
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        if ok then name = plain(n) end
    end
    if name and name ~= p.name then return false end     -- some other spell (a macro, a key): not this click's
    local sp, o = p.sp, p.sp.over
    if not o then return false end
    o.flashUntil = now() + OV.FLASH_FOR
    show(o)
    if o.fade then o.fade:Stop() o.fade:Play() end
    OV.Listen(nil)                                       -- held: health moving as the heal lands must not flip it
    if C_Timer and C_Timer.After then
        local mark = o.flashUntil
        C_Timer.After(OV.FLASH_FOR, function()
            if o.flashUntil ~= mark then return end
            o.flashUntil = nil
            if OV.hover == sp and not OV.casting then OV.PaintHover() else hide(o) end
        end)
    end
    return true
end

-- ------------------------------------------------------------------ events

for _, e in ipairs({ "MODIFIER_STATE_CHANGED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
if ev.RegisterUnitEvent then
    for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_STOP",
                         "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        pcall(ev.RegisterUnitEvent, ev, e, "player")
    end
end
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "MODIFIER_STATE_CHANGED" then
        if OV.hover then OV.PaintHover() end
    elseif event == "UNIT_HEALTH" or event == "UNIT_HEAL_PREDICTION" then
        if OV.hover and a1 == OV.listening then OV.PaintHover() end
    elseif event == "UNIT_SPELLCAST_START" then
        OV.casting = true
        OV.CastBegan(a3)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local wasCasting = OV.casting
        OV.casting = nil
        if OV.pending then OV.CastBegan(a3) end           -- an instant: no START came first
        if wasCasting and OV.hover then OV.PaintHover() end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        OV.casting = nil
        if event ~= "UNIT_SPELLCAST_STOP" then OV.pending = nil end
        if OV.hover then OV.PaintHover() end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_REGEN_ENABLED" then
        OV.Forget()                                       -- ranks, talents or +healing may have moved: read again
    end
end)
