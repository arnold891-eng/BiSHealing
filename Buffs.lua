--[[
  BiS Healing :: Buffs.lua - BiS> now's buff buttons (4 Nov 2026). Plan: dev/BUFFS.md.

  Arn, 24 Oct: "if a class is capable of buffing like priest fortitude or druid mark of the wild ... a button in bis
  now that chooses the best target to buff". 4 Nov, starting it: "make it smart for classes each get their buff
  buttons". So one button per buff THIS character has trained - the spellbook decides, never a class check: a priest
  gets Fortitude (and Divine Spirit, Shadow Protection once learned), a druid Mark of the Wild and Thorns, a mage
  Arcane Intellect. Paladins get nothing here: Pally Power does blessings.

  OFF BY DEFAULT (`/bish buffs`). Shadow Protection is off inside that too: it is a buff for some fights, not for
  every pull, and a button that is always lit is a button you learn to ignore.

  WHAT IT MAY READ (probe round 1, 4 Nov, BUFFS.md section 7): out of combat a party member's buff answers
  C_UnitAuras.GetUnitAuraBySpellID with a plain expirationTime; UnitLevel, range and "usable" are plain. In combat
  the auras go secret - so this is an out-of-combat job, and in a fight nothing here runs at all.

  THE TRAP THE PROBE FOUND: `/cast [@party1] Power Word: Fortitude` with party1 out of range did not refuse - the buff
  landed on the priest. So nobody is aimed at unless the client says they are in range.

  WHAT IT COSTS: the aura answer is kept per person until that person's UNIT_AURA, so a fully buffed raid looked at
  again costs one UnitExists a person. Range, AFK and the rest are asked only of someone who needs the buff.
]]

local ADDON, NS = ...
NS = NS or {}
local FU = {}
NS.FU = FU

--- THE BUFFS. `ids` are every rank's spell id (classic-era ids; rank 1 of Fortitude, 1243, measured on Forever 4 Nov)
--- and are used only to READ the buff on someone - which rank they wear, from anyone. The cast goes by name and
--- the rank this character has in its own book. `learn` is the level each rank is trained at; `group` the raid
--- version's ids, which count as "has it". `who`: all, mana (mana users only), tank (tanks only).
--- `slot` is the digit the macro row stores this buff's switch under - a promise, never reused.
FU.FAMILIES = {
    { key = "fort", slot = 1, word = "Fortitude", name = "Power Word: Fortitude", who = "all",
      ids = { 1243, 1244, 1245, 2791, 10937, 10938 }, learn = { 1, 12, 24, 36, 48, 60 }, group = { 21562, 21564 } },
    { key = "spirit", slot = 2, word = "Spirit", name = "Divine Spirit", who = "mana",
      ids = { 14752, 14818, 14819, 27841 }, learn = { 30, 40, 50, 60 }, group = { 27681 } },
    { key = "shadow", slot = 3, word = "Shadow Protection", name = "Shadow Protection", who = "all", off = true,
      ids = { 976, 10957, 10958 }, learn = { 30, 42, 56 }, group = { 27683 } },
    { key = "mark", slot = 4, word = "Mark", name = "Mark of the Wild", who = "all",
      ids = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, learn = { 1, 10, 20, 30, 40, 50, 60 }, group = { 21849, 21850 } },
    { key = "thorns", slot = 5, word = "Thorns", name = "Thorns", who = "tank",
      ids = { 467, 782, 1075, 8914, 9756, 9910 }, learn = { 6, 14, 24, 34, 44, 54 } },
    { key = "int", slot = 6, word = "Intellect", name = "Arcane Intellect", who = "mana",
      ids = { 1459, 1460, 1461, 10156, 10157 }, learn = { 1, 14, 28, 42, 56 }, group = { 23028 } },
}

--- Under five minutes left counts as needing it again: a buff that drops mid-pull cannot be put back.
FU.SOON = 300
--- A buff rank may go on a target this many levels under the level it is learned at (the classic rule; the
--- "Target is too low level" a macro cast gets instead of a quiet downrank - forum reports, UNVERIFIED on Forever).
FU.LEVEL_GAP = 10

function FU.Family(key)
    for _, f in ipairs(FU.FAMILIES) do if f.key == key then return f end end
    return nil
end

local function plain(v)
    if NS.Plain then return NS.Plain(v) end
    return v
end

local function ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

------------------------------------------------------------------ switches --

--- Is the whole helper on (off by default)?
function FU.Enabled()
    local d = NS.DB and NS.DB()
    return type(d) == "table" and d.buffs == true
end

--- Is this one buff switched on? Each is on once the helper is, except the ones marked `off`.
function FU.FamilyOn(fam)
    local d = NS.DB and NS.DB()
    local picks = type(d) == "table" and type(d.buffFam) == "table" and d.buffFam or nil
    if picks and picks[fam.key] ~= nil then return picks[fam.key] == true end
    return not fam.off
end

--- Does this character have the spell at all? The book, never the class.
function FU.Knows(fam)
    return NS.FM and NS.FM.Ranks and #NS.FM.Ranks(fam.name) > 0 or false
end

--- The switches as digits for the macro row: the slot of every buff that is on. "" = none.
function FU.EncodeFams()
    local out = {}
    for _, f in ipairs(FU.FAMILIES) do if FU.FamilyOn(f) then out[#out + 1] = tostring(f.slot) end end
    return table.concat(out)
end

--- And back: every buff named is on, every one not named is off.
function FU.DecodeFams(digits)
    if type(digits) ~= "string" then return nil end
    local t = {}
    for _, f in ipairs(FU.FAMILIES) do t[f.key] = digits:find(tostring(f.slot), 1, true) ~= nil end
    return t
end

------------------------------------------------------------- who has it --

--- What we last read about each person, until their next UNIT_AURA: cache[unit][key] = expiration (absolute
--- GetTime, 0 = never runs out), false = not wearing it, nil = never asked or the client would not say.
FU.cache = {}
FU.reads = 0

local function idsOf(fam)
    if fam.__all then return fam.__all end
    local all, seen = {}, {}
    local function add(id) if type(id) == "number" and not seen[id] then seen[id] = true all[#all + 1] = id end end
    for _, id in ipairs(fam.ids) do add(id) end
    for _, id in ipairs(fam.group or {}) do add(id) end
    -- and the ids this character's own book gives, in case Forever numbers a rank differently
    for _, id in ipairs(NS.FM and NS.FM.BookIds and NS.FM.BookIds(fam.name) or {}) do add(id) end
    fam.__all = all
    return all
end

--- Is this person wearing the buff? expiration, false (not wearing it), or nil (unreadable - never "missing").
function FU.Wears(unit, fam)
    local c = FU.cache[unit]
    if c and c[fam.key] ~= nil then return c[fam.key] end
    local get = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not get then return nil end
    FU.reads = FU.reads + 1
    local answer = false
    for _, id in ipairs(idsOf(fam)) do
        local ok, a = pcall(get, unit, id)
        if not ok or (NS.Secret and NS.Secret(a)) then return nil end
        if type(a) == "table" then
            local exp = plain(a.expirationTime)
            if type(exp) ~= "number" then return nil end
            answer = exp                     -- one rank is worn at a time: the first found is the answer
            break
        end
    end
    FU.cache[unit] = c or {}
    FU.cache[unit][fam.key] = answer
    return answer
end

--- Seconds left on them: 0 = missing, a big number for one that never runs out, nil = unknown.
local function leftOn(unit, fam, now)
    local exp = FU.Wears(unit, fam)
    if exp == nil then return nil end
    if exp == false then return 0 end
    if exp == 0 then return math.huge end
    return exp - now
end

local function plainTrue(f, unit)
    if not f then return false end
    local ok, v = pcall(f, unit)
    return ok and plain(v) == true
end

local function isTank(unit)
    local role = ask(UnitGroupRolesAssigned, unit)
    if plain(role) == "TANK" then return true end
    local FN = NS.FN
    local n = FN and FN.NameOf and FN.NameOf(unit)
    return (n and FN.IsTank and FN.IsTank(n)) and true or false
end

local function usesMana(unit)
    local t = ask(UnitPowerType, unit)
    t = plain(t)
    if type(t) ~= "number" then return true end      -- the client would not say: count them in
    return t == 0
end

--- In range, as the client measures it with this very spell. Only a plain yes counts (the probe's trap).
local function inRange(unit, fam)
    if unit == "player" then return true end
    local f = (C_Spell and C_Spell.IsSpellInRange) or IsSpellInRange
    local v = ask(f, fam.name, unit)
    v = plain(v)
    return v == true or v == 1
end

--- The highest rank this character has that may go on this level: "Rank 3", or nil for the plain name.
function FU.RankFor(fam, level)
    local ranks = NS.FM and NS.FM.Ranks and NS.FM.Ranks(fam.name) or {}
    local best, bestN
    for _, r in ipairs(ranks) do
        local n = type(r.rank) == "string" and tonumber(r.rank:match("(%d+)")) or nil
        local learned = n and fam.learn[n]
        local fits = not (type(level) == "number" and learned) or learned <= level + FU.LEVEL_GAP
        if n and fits and (not bestN or n > bestN) then best, bestN = r.rank, n end
    end
    if best then return best end
    -- no rank text at all (one-rank spell, or a client that drops it): the plain name, the client picks
    return nil
end

--- Everyone the buffs are for: the group, you always included (your own cell may be out of the grid).
local function people()
    local out, seen = {}, {}
    local FG = NS.FG
    for _, u in ipairs((FG and FG.Roster and FG.Roster()) or {}) do
        if not (FG.IsPetUnit and FG.IsPetUnit(u)) and not seen[u] then seen[u] = true out[#out + 1] = u end
    end
    if not seen.player then table.insert(out, 1, "player") end
    return out
end

--- THE BEST PERSON TO BUFF NOW, for one buff: unit, rank, and how many still need it (in reach / out of reach).
--- Missing it beats running low; tanks, then healers, then group order; the soonest to run out among the rest.
function FU.Target(fam)
    if InCombatLockdown and InCombatLockdown() then return nil end
    if type(fam) == "string" then fam = FU.Family(fam) end
    if not fam then return nil end
    local now = (GetTime and GetTime()) or 0
    local best, bestKey, near, far = nil, nil, 0, 0
    for i, u in ipairs(people()) do
        if UnitExists and UnitExists(u) then
            local left = leftOn(u, fam, now)                     -- kept: no call for the buffed
            if left and left < FU.SOON then
                local fits = (fam.who ~= "tank" or isTank(u)) and (fam.who ~= "mana" or usesMana(u))
                if fits and (not UnitIsConnected or plainTrue(UnitIsConnected, u))
                   and not plainTrue(UnitIsDeadOrGhost, u) and not plainTrue(UnitIsAFK, u) then
                    if inRange(u, fam) then
                        near = near + 1
                        local role = plain(ask(UnitGroupRolesAssigned, u))
                        local who = isTank(u) and 0 or (role == "HEALER" and 1 or 2)
                        -- missing first, then by role, then the least time left, then group order
                        local key = (left <= 0 and 0 or 1) * 1e9 + who * 1e7 + math.max(0, left) * 10 + i
                        if not bestKey or key < bestKey then best, bestKey = u, key end
                    else
                        far = far + 1
                    end
                end
            end
        end
    end
    if not best then return nil, nil, near, far end
    local level = plain(ask(UnitLevel, best))
    return best, FU.RankFor(fam, type(level) == "number" and level or nil), near, far
end

--- Should this buff's button be in BiS> now? On, trained, out of combat, and somebody in reach needs it.
function FU.Show(key)
    local fam = FU.Family(key)
    if not (fam and FU.Enabled() and FU.FamilyOn(fam) and FU.Knows(fam)) then return false end
    return FU.Target(fam) ~= nil
end

------------------------------------------------------------------ button --

--- Point the button at the best person, with the right rank. At every layout and again in PreClick, so the aim
--- is fresh at the click (solved.md: attributes in PreClick out of combat). In a fight: left as it is.
function FU.Aim(b)
    if not (b and b.SetAttribute and b.buffKey) then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local fam = FU.Family(b.buffKey)
    local unit, rank, near, far = FU.Target(fam)
    local cast = NS.FM and NS.FM.Cast and NS.FM.Cast(fam.name, rank) or fam.name
    b:SetAttribute("*type1", "macro")
    b:SetAttribute("*macrotext1", unit and ("/cast [@" .. unit .. "] " .. cast) or "")
    b.buffUnit, b.buffRank, b.buffNear, b.buffFar = unit, rank, near or 0, far or 0
    if b.word then b.word:SetText((near or 0) > 1 and tostring(near) or "") end
    return true
end

local function nameOf(unit)
    local FN = NS.FN
    local n = FN and FN.NameOf and FN.NameOf(unit)
    return n or unit
end

local function tip(self)
    if not GameTooltip then return end
    local fam = FU.Family(self.buffKey)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local n = self.buffUnit and nameOf(self.buffUnit) or "nobody"
    GameTooltip:AddLine(fam.word .. " on " .. n .. (self.buffRank and (" (" .. self.buffRank .. ")") or ""))
    local extra = self.buffFar > 0 and (" - " .. self.buffFar .. " more out of reach") or ""
    GameTooltip:AddLine(("%d in reach still need it%s."):format(self.buffNear, extra), 1, 1, 1, true)
    GameTooltip:AddLine("Missing it first, then under 5 minutes left; tanks, then healers. /bish buffs to switch off.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

--- Dress a BiS> now button as this buff: the spell's icon, a count, the tooltip, the aim in PreClick.
function FU.Arm(b, key)
    local fam = FU.Family(key)
    if not (b and fam) then return end
    b.buffKey = key
    if b.art and b.art.SetTexture and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, fam.name)
        if ok and tex then pcall(b.art.SetTexture, b.art, tex) end
    end
    if not b.word and b.CreateFontString then
        b.word = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.word:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -2, 2)
        if b.word.SetFont then pcall(b.word.SetFont, b.word, STANDARD_TEXT_FONT, 9, "OUTLINE") end
    end
    if b.HookScript and not b.buffHooked then
        b.buffHooked = true
        b:HookScript("PreClick", function(self) FU.Aim(self) end)
        b:HookScript("OnEnter", tip)
        b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    FU.Aim(b)
end

------------------------------------------------------------------ watching --

--- Something changed - a buff, the group, a level, the fight ended. Looked at once a moment later. A button that
--- should come or go needs a layout (out of combat); one that stays is only re-aimed.
FU.WAIT = 0.5
function FU.Soon()
    if FU.armed or not FU.Enabled() or (InCombatLockdown and InCombatLockdown()) then return false end
    FU.armed = true
    local function go()
        FU.armed = nil
        if InCombatLockdown and InCombatLockdown() then return end
        local FN = NS.FN
        local relayout = false
        for _, fam in ipairs(FU.FAMILIES) do
            local b = FN and FN.buttons and FN.buttons[fam.key]
            local shown = (b and b:IsShown()) and true or false
            if FU.Show(fam.key) ~= shown then relayout = true elseif b and shown then FU.Aim(b) end
        end
        if relayout and FN and FN.Layout then FN.Layout() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(FU.WAIT, go) else go() end
    return true
end

--- Forget what we read: about one person (their UNIT_AURA), or everyone (the group changed, a fight ended).
function FU.Forget(unit)
    if unit then FU.cache[unit] = nil else FU.cache = {} end
end

-- RANGE AND TIME FIRE NO EVENT: someone walks into reach, a buff passes five minutes left. So while the helper is on
-- and you are out of a fight, it looks again every few seconds - from the kept answers, which costs next to nothing.
FU.EVERY = 3
do
    local w = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "UNIT_LEVEL",
                         "PLAYER_FLAGS_CHANGED", "UNIT_CONNECTION", "SPELLS_CHANGED" }) do
        pcall(w.RegisterEvent, w, e)
    end
    w:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" then FU.Forget(unit)
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_REGEN_ENABLED" then FU.Forget()
        elseif event == "SPELLS_CHANGED" then for _, f in ipairs(FU.FAMILIES) do f.__all = nil end end
        FU.Soon()
    end)
    FU.watcher = w
    if C_Timer and C_Timer.NewTicker then
        FU.ticker = C_Timer.NewTicker(FU.EVERY, function() if FU.Enabled() then FU.Soon() end end)
    end
end
