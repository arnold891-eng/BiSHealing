--[[
  BiSHealing :: Heals.lua - MANA FOR MANA, WHICH HEAL? (the probe, step 0)

  Arn, 19 Oct 2026: "i want a window in the option that breaks down the mana efficiency of my healing
  spells taken everything into account break it down phd level. i want you to see all my talents my
  +healing. mana for mana what is the best healing spell i can spam to heal the most at the least
  amount of mana using all ranks and everything".

  The breakdown is only as good as the numbers under it, and Forever is a modern client wearing a 1.x
  game: whether a rank's mana cost already has the talents taken off, whether its tooltip numbers
  include +healing, whether any of it is secret - none of that is known. So first the PROBE:
  `/bish heals` reads, for every rank of every heal this character has, what the client will say -
  cost, cast time, the tooltip's own words - plus +healing, crit, mana, regen and every talent point,
  and puts it in a box to copy out (Forever will not let an addon write the clipboard: select, Ctrl+C).
  The window with the answer is built on what this readout shows.

  Read only. Out of combat or in, it changes nothing; it asks the client a few hundred questions once,
  when typed, and never on a timer.
]]
local ADDON, NS = ...
NS = NS or {}

local FE = {}
NS.FE = FE

-- the heals by class, by NAME (the book decides which ranks this character has - FM.Ranks / BookIds)
FE.HEALS = {
    SHAMAN  = { "Healing Wave", "Lesser Healing Wave", "Chain Heal" },
    PRIEST  = { "Lesser Heal", "Heal", "Greater Heal", "Flash Heal", "Renew", "Prayer of Healing", "Holy Nova" },
    DRUID   = { "Healing Touch", "Regrowth", "Rejuvenation", "Tranquility" },
    PALADIN = { "Holy Light", "Flash of Light", "Holy Shock" },
}
-- the spell schools GetSpellCritChance numbers: 2 holy, 4 nature
FE.SCHOOL = { SHAMAN = 4, DRUID = 4, PRIEST = 2, PALADIN = 2 }

local function plain(v)
    if NS.Plain then return NS.Plain(v) end
    return v
end
local function show(v)
    local p = plain(v)
    if p == nil and v ~= nil then return "secret" end
    if p == nil then return "-" end
    return tostring(p)
end
local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

--- One rank: id, cost, cast time, level learned, and the tooltip's own words.
function FE.Rank(id)
    local r = { id = id }
    local S = C_Spell
    local costs = S and ask(S.GetSpellPowerCost, id)
    if type(costs) == "table" then
        for _, c in ipairs(costs) do
            local t = plain(c.type)
            if t == 0 or plain(c.name) == "MANA" or #costs == 1 then r.cost = c.cost break end
        end
    end
    local info = S and ask(S.GetSpellInfo, id)
    if type(info) == "table" then r.cast, r.name = info.castTime, info.name end
    r.learned = S and ask(S.GetSpellLevelLearned, id)
    r.sub = S and ask(S.GetSpellSubtext, id)
    r.desc = S and ask(S.GetSpellDescription, id)
    return r
end

--- One talent: its name, points spent, and its most.
function FE.Talent(tab, i)
    if type(GetTalentInfo) ~= "function" then return nil end
    local ok, name, _, _, _, rank, max = pcall(GetTalentInfo, tab, i)
    if not ok then return nil end
    return name, rank, max
end

--- The readout, as lines of text.
function FE.Probe()
    local out = {}
    local function line(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
    local _, class = ask(UnitClass, "player")
    class = plain(class)
    local level = ask(UnitLevel, "player")
    line("BiS Healing heals probe - %s level %s, %s", show(class), show(level),
         date and date("%Y-%m-%d %H:%M") or "")
    line("+healing %s   crit %s%%   mana %s   regen (not casting / casting) %s / %s per s",
         show(ask(GetSpellBonusHealing)), show(ask(GetSpellCritChance, FE.SCHOOL[class or ""] or 2)),
         show(ask(UnitPowerMax, "player", 0)), show((ask(GetManaRegen))), show(select(2, ask(GetManaRegen))))
    local stats = {}
    for i, nm in ipairs({ "Str", "Agi", "Sta", "Int", "Spi" }) do
        stats[#stats + 1] = nm .. " " .. show(select(2, ask(UnitStat, "player", i)))
    end
    line("%s", table.concat(stats, "   "))
    local FM = NS.FM
    for _, name in ipairs(FE.HEALS[class or ""] or {}) do
        local ids = FM and FM.BookIds and FM.BookIds(name) or {}
        local ranks = FM and FM.Ranks and FM.Ranks(name) or {}
        line("")
        line("== %s: %d rank%s", name, #ids, #ids == 1 and "" or "s")
        for i, id in ipairs(ids) do
            local r = FE.Rank(id)
            line("%s [%s] id %s  cost %s  cast %s ms  learned %s", tostring(ranks[i] and ranks[i].rank or r.sub or "?"),
                 show(r.sub), tostring(id), show(r.cost), show(r.cast), show(r.learned))
            line("   %s", show(r.desc))
        end
    end
    line("")
    line("== talents (points spent)")
    local tabs = ask(GetNumTalentTabs) or 0
    for t = 1, plain(tabs) or 0 do
        local tabName = ask(GetTalentTabInfo, t)
        local n = ask(GetNumTalents, t) or 0
        local spent = {}
        for i = 1, plain(n) or 0 do
            -- GetTalentInfo answers name, icon, tier, column, rank, max (and more)
            local tn, rank, max = FE.Talent(t, i)
            if plain(rank) and plain(rank) > 0 then
                spent[#spent + 1] = ("%s %s/%s"):format(show(tn), show(rank), show(max))
            end
        end
        line("%s: %s", show(type(tabName) == "table" and tabName.name or tabName),
             #spent > 0 and table.concat(spent, ", ") or "-")
    end
    return out
end

--------------------------------------------------------------------
-- the answer: mana for mana, which heal
--------------------------------------------------------------------
-- WHAT THE PROBE SHOWED (Arn's level-30 shaman, 19 Oct, gear on and off): the tooltip's numbers ALREADY
-- hold your +healing, at Forever's own share per rank (Healing Wave 1 got 15% of it, 3 got 69%, 4 and 5
-- 87%, Lesser Healing Wave 44%) - not Classic's formula, so it is never recomputed here. The cast times
-- already hold the talents (every Healing Wave rank 0.5 s faster: Improved Healing Wave). The costs are
-- the client's. And the talent list is EMPTY to an addon on Forever, even with the talent window open -
-- so nothing here reads talents: what they do is already inside the client's numbers.
-- So the window READS each rank as it is right now, with your gear, and only does the arithmetic:
--   heal      the tooltip's middle, times crit (a heal crits for 150%)
--   per mana  heal / cost              per sec  heal / cast time (an instant: the 1.5 s global cooldown)
--   dry in    how long spamming it lasts on a full bar, with the mana you get back while casting
--   a fight   the most healing in a fight of N seconds: full speed until dry, then what regen pays for
FE.GCD = 1.5
FE.CRIT_HEAL = 0.5                        -- a crit heals 150%: half again
FE.CHAIN = 1.75                           -- Chain Heal on three targets: 1 + 1/2 + 1/4 (UNVERIFIED on Forever)
FE.FIGHTS = { 15, 30, 60, 120, 300 }

local function num(s) return tonumber((tostring(s or ""):gsub(",", ""))) end

--- A tooltip's heal: its low and high, or the whole of a heal over time and its seconds. Nil for a
--- tooltip that is secret or says neither.
function FE.Parse(desc)
    if type(desc) ~= "string" or (NS.Secret and NS.Secret(desc)) then return nil end
    -- NOT WORKED OUT YET (Arn, 19 Oct: "does this work for all the healers? does it do hots and shields?
    -- ... chain heal bounces and priest aoe heals"): a heal on the whole party (Prayer of Healing, Holy
    -- Nova, Tranquility) and a heal with a HoT after it (Regrowth) would be counted as one target's
    -- direct part - far too low. They show, marked, and are left out of "spam this" until each is
    -- read off a real tooltip on Forever.
    local low = desc:lower()
    local partial = low:find("party", 1, true) or low:find("members", 1, true) or low:find("within %d+ yards")
    local lo, hi = desc:match("for ([%d,]+) to ([%d,]+)")
    if lo then
        if low:find("over [%d,]+ sec") then partial = true end            -- direct, then a HoT
        return { lo = num(lo), hi = num(hi), chain = desc:find("jump", 1, true) ~= nil, partial = partial and true or nil }
    end
    local total, secs = desc:match("([%d,]+) damage over ([%d,]+) sec")
    if not total then total, secs = desc:match("for ([%d,]+) over ([%d,]+) sec") end
    if total then return { lo = num(total), hi = num(total), hot = num(secs), partial = partial and true or nil } end
    return nil
end

--- Everything the window shows, read now: { mana, regen, crit, bonus, rows = { ... } }.
function FE.Data()
    local _, class = ask(UnitClass, "player")
    class = plain(class)
    local d = {
        mana = plain(ask(UnitPowerMax, "player", 0)) or 0,
        regen = plain(select(2, ask(GetManaRegen))) or 0,       -- while casting: you are, the whole fight
        crit = plain(ask(GetSpellCritChance, FE.SCHOOL[class or ""] or 2)) or 0,
        bonus = plain(ask(GetSpellBonusHealing)) or 0,
        rows = {},
    }
    local FM = NS.FM
    for _, name in ipairs(FE.HEALS[class or ""] or {}) do
        local ids = FM and FM.BookIds and FM.BookIds(name) or {}
        for i, id in ipairs(ids) do
            local r = FE.Rank(id)
            local h = FE.Parse(plain(r.desc))
            local cost, cast = plain(r.cost), plain(r.cast)
            if h and type(cost) == "number" and cost > 0 then
                local avg = (h.lo + h.hi) / 2 * (h.chain and FE.CHAIN or 1) * (1 + d.crit / 100 * FE.CRIT_HEAL)
                local secs = math.max(FE.GCD, (type(cast) == "number" and cast or 0) / 1000)
                local row = { name = name, rank = i, label = ("%s %d"):format(name, i), id = id,
                              heal = avg, cost = cost, cast = secs, hpm = avg / cost, hps = avg / secs,
                              chain = h.chain, hot = h.hot, partial = h.partial }
                local burn = cost / secs - d.regen
                row.dry = burn > 0 and d.mana / burn or nil       -- nil: it never runs you dry
                d.rows[#d.rows + 1] = row
            end
        end
    end
    return d
end

--- The healing a row does in a fight of `t` seconds, spammed from a full bar: full speed until dry, then
--- only what the mana coming back pays for.
function FE.Total(row, t, d)
    if not row.dry or row.dry >= t then return row.hps * t end
    return row.hps * row.dry + row.hpm * d.regen * (t - row.dry)
end

--- The rows best first for a fight of `t` seconds.
function FE.Best(d, t)
    local list = {}
    for _, r in ipairs(d.rows) do if not r.partial then list[#list + 1] = r end end   -- `*` rows: not ranked
    table.sort(list, function(a, b) return FE.Total(a, t, d) > FE.Total(b, t, d) end)
    return list
end

--------------------------------------------------------------------
-- the copy box
--------------------------------------------------------------------
-- 1.43:1, the family's window shape (standing order, 14 Oct)
FE.W, FE.H = 572, 400

--- ESCAPE CLOSES THEM (Arn, 6 Nov 2026, every BiS window). The client closes the frames NAMED in
--- UISpecialFrames on Escape - and also when a panel such as the spellbook opens (CloseAllWindows). That
--- second part is why the bind window handles Escape itself (MouseUI.lua: it sits BESIDE the spellbook on
--- purpose). These two do not: the probe box is a copy-and-go, and the mana window gives its spell by drag.
--- Neither holds a secure child (plain buttons, a scroll, an edit box), so the client may hide them at
--- any time, in a fight too. Listed once, when built.
local function escapes(name)
    if not (UISpecialFrames and name) then return end
    for _, n in ipairs(UISpecialFrames) do if n == name then return end end
    table.insert(UISpecialFrames, name)
end

function FE.Box()
    if FE.box then return FE.box end
    local f = CreateFrame("Frame", "BiSHealingProbe", UIParent)
    escapes("BiSHealingProbe")
    f:SetSize(FE.W, FE.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetText("BiS> heals probe - Ctrl+A, Ctrl+C, paste it to Claude")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -30)
    scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(FE.W - 50)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    f.edit = edit
    FE.box = f
    return f
end

--------------------------------------------------------------------
-- the window: every rank, and the one to spam
--------------------------------------------------------------------
FE.COLS = { { "spell", 170, "LEFT" }, { "heal", 62 }, { "mana", 50 }, { "per mana", 70 }, { "per sec", 62 }, { "dry in", 62 } }
FE.ROW_H = 16
FE.fight = 60

local function comma(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    while true do
        local k
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then return s end
    end
end
function FE.Clock(secs)
    if not secs then return "never" end
    return ("%d:%02d"):format(math.floor(secs / 60), math.floor(secs % 60))
end
local function fightWord(t) return t < 60 and (t .. " s") or (t / 60 .. " min") end

local function cell(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", size or "GameFontHighlightSmall")
    fs:SetJustifyH("RIGHT")
    return fs
end

function FE.Win()
    if FE.win then return FE.win end
    local f = CreateFrame("Frame", "BiSHealingHeals", UIParent)
    escapes("BiSHealingHeals")
    f:SetSize(FE.W, FE.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText("BiS> mana for mana - which heal")
    f.sub = cell(f)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetPoint("TOPLEFT", 12, -28)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    -- the column heads
    local x = 12
    f.heads = {}
    for i, c in ipairs(FE.COLS) do
        local h = cell(f, "GameFontNormalSmall")
        h:SetJustifyH(c[3] or "RIGHT")
        h:SetWidth(c[2])
        h:SetPoint("TOPLEFT", x, -48)
        h:SetText(c[1])
        f.heads[i] = h
        x = x + c[2] + 6
    end
    -- the ranks, in a scroll (a priest at 60 has forty)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -64)
    scroll:SetPoint("BOTTOMRIGHT", -30, 88)
    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(FE.W - 50, 10)
    scroll:SetScrollChild(list)
    f.list, f.rows = list, {}
    -- the fight: how long you spam
    f.fightWord = cell(f, "GameFontNormalSmall")
    f.fightWord:SetJustifyH("LEFT")
    f.fightWord:SetPoint("BOTTOMLEFT", 12, 66)
    f.fightWord:SetText("a fight of")
    f.buttons = {}
    for i, t in ipairs(FE.FIGHTS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(52, 20)
        b:SetPoint("BOTTOMLEFT", 80 + (i - 1) * 56, 62)
        b:SetText(fightWord(t))
        b:SetScript("OnClick", function() FE.fight = t FE.Paint() end)
        f.buttons[i] = b
    end
    -- THE ANSWER, TO TAKE AWAY (Arn, 19 Oct: "when i select a fight time and it recommends a spell i want
    -- it to make a draggable button"): the recommended rank's icon - drag it (or click it) onto an action
    -- bar or the mouse binds; it is that RANK, as the mouse window's rank rows (FM.PickUp)
    local pick = CreateFrame("Button", nil, f)
    pick:SetSize(28, 28)
    pick:SetPoint("BOTTOMLEFT", 12, 30)
    pick.icon = pick:CreateTexture(nil, "ARTWORK")
    pick.icon:SetAllPoints()
    -- it lights under the mouse, as every button of ours does (FM.Pop, MouseUI.lua; Arn, 6 Nov)
    local FM = NS.FM
    if FM and FM.Pop then FM.Pop(pick, nil, "OVERLAY") end
    pick:RegisterForDrag("LeftButton")
    local function take(self) if self.id and NS.FM and NS.FM.PickUp then NS.FM.PickUp(self.id) end end
    pick:SetScript("OnDragStart", take)
    pick:SetScript("OnClick", take)
    pick:SetScript("OnEnter", function(self)
        if FM and FM.Lit then FM.Lit(self, true) end
        local tip = _G.GameTooltip
        if not (tip and self.id) then return end
        tip:SetOwner(self, "ANCHOR_TOP")
        if tip.SetSpellByID then pcall(tip.SetSpellByID, tip, self.id) end
        tip:AddLine("Drag me onto an action bar or a mouse button.", 0.31, 0.82, 0.81, true)
        tip:Show()
    end)
    pick:SetScript("OnLeave", function(self)
        if FM and FM.Lit then FM.Lit(self, false) end
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    pick:Hide()
    f.pick = pick
    -- the mouse binds, a click away (Arn: "and also in the window i want a open the mouse bind window")
    local binds = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    binds:SetSize(96, 20)
    binds:SetPoint("TOPRIGHT", -28, -6)
    binds:SetText("mouse binds")
    binds:SetScript("OnClick", function() if NS.DO and NS.DO.mouse then NS.DO.mouse() end end)
    f.binds = binds
    -- the answer on one line and its detail on the next - one long line wrapped into the note (19 Oct)
    f.answer = cell(f, "GameFontNormal")
    f.answer:SetJustifyH("LEFT")
    f.answer:SetPoint("BOTTOMLEFT", 46, 46)
    f.answer:SetWidth(FE.W - 58)
    f.next = cell(f)
    f.next:SetJustifyH("LEFT")
    f.next:SetPoint("BOTTOMLEFT", 46, 32)
    f.next:SetWidth(FE.W - 58)
    f.note = cell(f)
    f.note:SetJustifyH("LEFT")
    f.note:SetPoint("BOTTOMLEFT", 12, 12)
    f.note:SetWidth(FE.W - 24)
    f.note:SetText("Your gear, +healing and talents are already in these numbers.")
    FE.win = f
    return f
end

local function row(f, i)
    local r = f.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, f.list)
    r:SetSize(FE.W - 50, FE.ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * FE.ROW_H)
    r.lit = r:CreateTexture(nil, "BACKGROUND")
    r.lit:SetAllPoints()
    r.lit:SetColorTexture(0.31, 0.82, 0.81, 0.18)          -- the family's "good": the one to spam
    r.cells = {}
    local x = 0
    for c, col in ipairs(FE.COLS) do
        local fs = cell(r)
        fs:SetJustifyH(col[3] or "RIGHT")
        fs:SetWidth(col[2])
        fs:SetPoint("LEFT", x, 0)
        r.cells[c] = fs
        x = x + col[2] + 6
    end
    f.rows[i] = r
    return r
end

--- Paint the window from what the client says now, for a fight of FE.fight seconds.
function FE.Paint()
    local f = FE.Win()
    local d = FE.Data()
    FE.data = d
    f.sub:SetText(("+%d healing   %.1f%% crit   %s mana   %.1f mana a second back while casting"):format(
        d.bonus, d.crit, comma(d.mana), d.regen))
    local bestHpm, bestHps, partial
    for _, r in ipairs(d.rows) do
        if r.partial then
            partial = true
        else
            if not bestHpm or r.hpm > bestHpm.hpm then bestHpm = r end
            if not bestHps or r.hps > bestHps.hps then bestHps = r end
        end
    end
    f.note:SetText(partial and "* group heals and heal-then-HoT spells: shown, not worked out yet - not ranked."
        or "Your gear, +healing and talents are already in these numbers.")
    local best = FE.Best(d, FE.fight)
    for i, r in ipairs(d.rows) do
        local w = row(f, i)
        local c = w.cells
        c[1]:SetText(r.label .. (r.chain and " (3 targets)" or "") .. (r.partial and " *" or ""))
        c[2]:SetText(comma(r.heal))
        c[3]:SetText(comma(r.cost))
        c[4]:SetText(("%.2f"):format(r.hpm))
        c[5]:SetText(comma(r.hps))
        c[6]:SetText(FE.Clock(r.dry))
        for k = 1, #c do c[k]:SetTextColor(1, 1, 1) end
        if r == bestHpm then c[4]:SetTextColor(1, 0.82, 0) end
        if r == bestHps then c[5]:SetTextColor(1, 0.82, 0) end
        w.lit:SetShown(r == best[1])
        w:Show()
    end
    for i = #d.rows + 1, #f.rows do f.rows[i]:Hide() end
    f.list:SetHeight(math.max(10, #d.rows * FE.ROW_H))
    for i, t in ipairs(FE.FIGHTS) do
        local b = f.buttons[i]
        if b.LockHighlight then if t == FE.fight then b:LockHighlight() else b:UnlockHighlight() end end
    end
    local top, second = best[1], best[2]
    f.pick.id = top and top.id or nil
    if top then
        local tex = C_Spell and ask(C_Spell.GetSpellTexture, top.id)
        f.pick.icon:SetTexture(plain(tex) or "Interface\\Icons\\INV_Misc_QuestionMark")
        f.pick:Show()
    else
        f.pick:Hide()
    end
    if not top then
        f.answer:SetText("No heals of yours could be read - out of combat, the tooltips say more.")
        f.next:SetText("")
    else
        f.answer:SetText(("Spam %s for %s: %s healing"):format(top.label, fightWord(FE.fight),
            comma(FE.Total(top, FE.fight, d))))
        local bits = {}
        if top.dry and top.dry < FE.fight then bits[#bits + 1] = "dry at " .. FE.Clock(top.dry) .. ", then regen" end
        if second then bits[#bits + 1] = "next: " .. second.label .. " " .. comma(FE.Total(second, FE.fight, d)) end
        f.next:SetText(table.concat(bits, "   -   "))
    end
    f:Show()
    return d, best
end

--- DOCKED BESIDE THE OPTIONS (Arn, 19 Oct: "in the options i also want just a button that i click and the
--- window pops up where the 3d model is at"): from the options' row the window hangs off their right
--- edge, as the tank mark's preview does - the options' height, 1.43:1 - and closes with them. The
--- preview stands aside while it is up (Now.lua's hover asks FE.Docked). `/bish efficiency` alone still
--- opens it free, in the middle of the screen.
function FE.Dock(opt)
    local f = FE.Win()
    f:SetParent(opt or UIParent)
    f:ClearAllPoints()
    -- ITS OWN SIZE, SCALED TO THE OPTIONS' HEIGHT (Arn's screenshot, 19 Oct: "some words get cutoff"):
    -- it took the options' height in THEIR units, and his options are scaled up - so it came out
    -- narrower than its columns, and "per sec" and "dry in" fell off its edge. Now it keeps the size it
    -- is laid out for and scales as a whole, so every column fits at any scale.
    f:SetSize(FE.W, FE.H)
    if opt then
        local okH, oh = pcall(opt.GetHeight, opt)
        local s = (okH and type(oh) == "number" and oh >= 200) and oh / FE.H or 1
        f:SetScale(s)
        f:SetPoint("TOPLEFT", opt, "TOPRIGHT", 4 / s, 0)
        f:SetMovable(false)
        if NS.FN and NS.FN.preview then NS.FN.preview:Hide() end
    else
        f:SetScale(1)
        f:SetPoint("CENTER")
        f:SetMovable(true)
    end
    FE.dockedTo = opt
    return FE.Paint()
end

--- Is it hanging off the options right now? (the tank preview then keeps out of its way)
function FE.Docked()
    return FE.dockedTo ~= nil and FE.win ~= nil and FE.win:IsShown() and true or false
end

--- `/bish heals`: the readout, selected, ready to copy.
function FE.Show()
    local f = FE.Box()
    local text = table.concat(FE.Probe(), "\n")
    f.edit:SetText(text)
    f:Show()
    f.edit:SetFocus()
    f.edit:HighlightText()
    return text
end
