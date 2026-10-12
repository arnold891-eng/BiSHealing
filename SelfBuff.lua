-- BiSHealing / SelfBuff -- the buff you keep forgetting about.
--
-- Arn, 23 Sep 2026: "for our healers can we add to the header their main healing buffs on
-- themselves. like i am always forgetting about watershield ... can the header say in and out of
-- combat. missing water shield".
--
-- WHAT THE CLIENT ALLOWS. Your own buffs read normally out of combat. Inside the lockdown they are
-- secret like everybody else's - so "is it up?" has no answer during the pull, and the honest
-- thing is to keep the last answer rather than invent a new one. The header says what it knew.
--
-- SPELLS BY NAME, THEN BY THE BOOK. A name is what a player types and what a tooltip shows; the
-- ids differ per rank and per client. Every rank the character has trained is looked up in the
-- spellbook (the same trick as the heal-over-time icons), so "Water Shield" means whichever rank
-- this shaman actually has.
--
-- ONE BUFF PER CLASS TO BEGIN WITH, the one people forget: the shaman's Water Shield, the
-- priest's Inner Fire, the druid's Omen of Clarity, the paladin's Blessing of Wisdom. Anything
-- else is a `/bish buff <name>` away, and the list is per character.

local ADDON, NS = ...
NS = NS or {}

local FS = {}
NS.FS = FS

-- WATER SHIELD IS CORRECT HERE, and the reasoning that said otherwise was wrong (1 Oct 2026).
--
-- Earth Shield does not exist in this game mode (Arn), and Water Shield is a Burning Crusade spell
-- too, so this default looked like the same bug and was changed to Lightning Shield. Arn: "i do
-- have water shield." Forever has one and not the other.
--
-- THE REAL LESSON, now measured twice in one evening from both directions: THE CLIENT'S BUILD
-- NUMBER DOES NOT PREDICT ITS SPELL LIST. 1.60.1 does not mean "vanilla spells", and a spell being
-- TBC-era says nothing about whether this mode has it. The only authority is the spellbook, which
-- is what FS.Knows asks before the header says a word - so a wrong name here is quiet rather than
-- harmful, and a right one cannot be deduced from the version string. Guess nothing; ask Arn or
-- ask the book.
FS.CLASS = {
    SHAMAN  = { "Water Shield" },
    PRIEST  = { "Inner Fire" },
    DRUID   = { "Omen of Clarity" },
    PALADIN = { "Blessing of Wisdom" },
}

--- The list this character watches: whatever the player set, or their class's one.
function FS.List()
    local d = NS.DB and NS.DB()
    local own = type(d) == "table" and d.selfBuffs or nil
    if type(own) == "table" and #own > 0 then return own end
    if type(own) == "table" and own.none then return {} end
    local class = UnitClass and NS.Plain(select(2, UnitClass("player"))) or nil
    return FS.CLASS[class or ""] or {}
end

--- Does this character know the spell at all? A level 20 shaman has no Water Shield, and being
--- told about it after every pull is the Earth Shield mistake again (19 Sep).
function FS.Knows(name)
    if NS.FM and NS.FM.Ranks then return #NS.FM.Ranks(name) > 0 end
    return false
end

--- ASKED ABOUT ONE AURA, BY ID. Read off Overlord 1.0.16 on 24 Sep 2026, which asks these two
--- questions before every lookup it makes:
---
---   C_Secrets.ShouldSpellAuraBeSecret(spellID)   is THIS aura hidden right now?
---   C_UnitAuras.GetPlayerAuraBySpellID(spellID)  then fetch just that one
---
--- Both beat what was here. The old walk read forty slots and compared their NAMES, and a name is
--- the first thing this client hides - so one secret name in a raid buff bar made the whole answer
--- "cannot say". And `ShouldAurasBeSecret` (our NS.Blind) answers for auras as a WHOLE: inside a
--- fight it says no to everything, which is why this reminder has only ever worked between pulls.
--- Per spell, the client may still answer during one. It may also not - that is measured in game,
--- not here, and either way the answer is honest.
---
--- THREE STATES, PER BUFF: on you, not on you, or the client will not say. "Will not say" is never
--- folded into "not on you" - telling a healer their shield has dropped when the truth is that
--- nobody knows is the one failure that makes a reminder worth switching off.
local UNKNOWN = nil

function FS.Present(name)
    local ids = FS.SpellIds(name)
    local byID = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    -- NO IDS, OR NO CALL: the old walk, which is the only answer a TBC client can give. A
    -- spellbook that names a spell but will not hand over its id is a real state at login, and
    -- "the client has gone quiet" would be a lie about it.
    if #ids == 0 or not byID then return FS.PresentByWalk(name) end
    local sawUnknown = false
    for _, spellID in ipairs(ids) do
        if FS.AuraSecret(spellID) then
            sawUnknown = true
        else
            local ok, aura = pcall(byID, spellID)
            if not ok then
                sawUnknown = true
            elseif not FS.Readable(aura) then
                sawUnknown = true
            elseif aura ~= nil then
                return true                  -- any rank of it, up: that is the whole question
            end
        end
    end
    if sawUnknown then return UNKNOWN end
    return false
end

--- Is this one aura a secret right now? An error, or an answer we may not read, is "yes" - the
--- lookup is then not made at all, which is Overlord's rule and the right way round: a refused
--- read is a thrown error in the middle of a pull.
function FS.AuraSecret(spellID)
    local ask = C_Secrets and C_Secrets.ShouldSpellAuraBeSecret
    if not ask then return false end
    local ok, secret = pcall(ask, spellID)
    if not ok then return true end
    local plain = NS.Plain(secret)
    if plain == nil then return true end     -- the ANSWER itself was secret
    return plain and true or false
end

--- May this value be looked at? `canaccessvalue` answers for a whole table, which `issecretvalue`
--- is not for - and what comes back here is an aura table. Overlord asks it 36 times to
--- issecretvalue's one.
function FS.Readable(v)
    if v == nil then return true end         -- "no such aura" is an answer, not a refusal
    if canaccessvalue then
        local ok, yes = pcall(canaccessvalue, v)
        return ok and yes and true or false
    end
    return NS.Plain(v) ~= nil
end

--- The old way, kept for a client without the by-id call: forty slots, compared by name.
function FS.PresentByWalk(name)
    if NS.Blind and NS.Blind() then return UNKNOWN end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return UNKNOWN end
    for i = 1, 40 do
        local ok, a = pcall(get, "player", i, "HELPFUL")
        -- A REFUSAL IS NOT AN EMPTY AURA BAR. These two were one line - `if not ok or not a then
        -- break end` - so a client that threw on the first slot walked out of the loop and said
        -- "nothing on you", which reads as every watched buff missing. Nil is the end of the
        -- list; an error is the client declining to say.
        if not ok then return UNKNOWN end
        if not a then break end
        local got = pcall(function() return a.name end) and NS.Plain(a.name) or nil
        if got == nil then return UNKNOWN end
        if got == name then return true end
    end
    return false
end

--- Which of them are not on you right now, and whether the client answered about all of them.
--- The second value is false when ANY watched buff came back unknown - the caller keeps what it
--- knew for those, and takes the news for the rest.
function FS.Missing()
    local missing, whole = {}, true
    for _, name in ipairs(FS.List()) do
        if FS.Knows(name) then
            local present = FS.Present(name)
            if present == nil then whole = false
            elseif present == false then missing[#missing + 1] = name end
        end
    end
    return missing, whole
end

--- What the header should say about it, or nil. Kept from the last readable moment, because in a
--- fight the client says nothing: a shield that fell off mid-pull is news the moment it ends.
--- REMEMBERED PER BUFF, not in one lump. It used to keep the whole list only when the client had
--- answered about all of it, so one unreadable buff threw away the news about every other. Now
--- each one keeps its own last answer: the shield the client will still talk about mid-fight is
--- current, and the one it has gone quiet on shows what it last was.
FS.known = nil
FS.state = {}          -- name -> true (on you) / false (not), only ever set from a real answer

--- WHAT A BUFF LAST WAS IS NOT NEWS ABOUT THE LIST IT IS ON. Every change to the watched list
--- comes through here, so a name that goes and comes back arrives with nothing already decided
--- about it - rather than the verdict from ten minutes ago, before the client had been asked once.
function FS.Forget()
    FS.state, FS.known = {}, nil
end

function FS.Check()
    for _, name in ipairs(FS.List()) do
        if FS.Knows(name) then
            local present = FS.Present(name)
            if present ~= nil then FS.state[name] = present and true or false end
        end
    end
    if next(FS.state) == nil then return FS.known end     -- nothing has ever been answered
    local missing = {}
    for _, name in ipairs(FS.List()) do
        if not FS.Knows(name) then
            -- A SPELL YOU DO NOT HAVE IS NOT A SPELL YOU FORGOT. The memory is per name and
            -- outlives the answer that filled it, so an untrained spell - or one whose book has
            -- not arrived yet at login - would otherwise keep reporting what it last was. That is
            -- the Earth Shield mistake again: a level 15 shaman told about a spell learned at 50.
            FS.state[name] = nil
        elseif FS.state[name] == false then
            missing[#missing + 1] = name
        end
    end
    FS.known = missing
    return FS.known
end

--- "no Water Shield", or nil when nothing is missing or nothing is known yet. Short on purpose:
--- it shares the header with the prompt, and a header is one cell wide on a party grid.
--- A BUFF WITH A BADGE IS NOT SAID TWICE: the badge is live and the word is only the last answer,
--- so the word speaks for the buffs the client would not give a badge to.
function FS.Word(short)
    local missing = FS.known
    if type(missing) ~= "table" then return nil end
    for _, name in ipairs(missing) do
        if not FS.badgeFor[name] then
            return "no " .. (short and FS.Initials(name) or name)
        end
    end
    return nil
end

-- THE BADGE: YOUR BUFF, LIVE, IN A FIGHT (12 Oct 2026). Arn, after reading the consume bar Fojji
-- shipped for Forever: "they said they found some combat back door stuff" ... "try the shield
-- marker".
--
-- The back door is the aura container (Auras.lua): the CLIENT draws a buff we may not read. A slot
-- filtered to Water Shield shows its icon - and its charges - while it is up, and nothing at all
-- when it is gone. So a red square goes UNDER it: up, the client's icon covers the red; down, the
-- red shows through. "Missing" is never asked, never read, never computed - it is what is left
-- when the client stops drawing. Fojji's bar does the same with a stack of them, nesting a
-- container in another's icon to get "this AND that"; one buff per badge needs no nesting.
--
-- Built out of combat only, like every container, and rebuilt only when what it would be built
-- for changes: after that it costs this addon nothing - no event, no tick, no question.
FS.badgeFor = {}       -- name -> true while a live badge stands for it
FS.badges = {}
FS.BADGE_RED = { 1.00, 0.22, 0.22, 1.00 }       -- a tint on a greyed icon, so brighter than a fill
FS.PULSE_LOW, FS.PULSE_SECONDS = 0.35, 0.6       -- the red breathes from full to this, and back

-- OUR OWN PICTURE ON THE CLIENT'S BUTTON. Arn, 12 Oct, Water Shield up and the badge still red:
-- the client HAD made the button (the filter id was right) and it drew nothing. A custom
-- container's button comes blank - Fojji's bar paints every one itself (`chain.icon`), as our
-- dispel pip does. So the spell's icon goes on it here; the icon of a spell in your own book is
-- not a secret. No mouse: it sits on a drag handle.
local function spellIcon(ids, name)
    local get = C_Spell and C_Spell.GetSpellTexture
    if get then
        for _, q in ipairs({ ids and ids[1], name }) do
            if q then
                local ok, tex = pcall(get, q)
                if ok and tex and not NS.Secret(tex) then return tex end
            end
        end
    end
    return 136048                             -- a plain blue orb, if the client will not say
end

-- CHARGES, AS A COLOUR, CHOSEN BY THE CLIENT (12 Oct 2026). Arn: "can we make it progress by
-- charges?" ... "right now its normal icon and its down to 2 or 1 charge we change to orange
-- yellow etc". The count is secret in a fight, so it is never read. The client's button takes a
-- font string (SetApplicationCount) and writes the count into it THROUGH A FORMATTER we hand it -
-- and a formatter's "format" may be any text at all, a texture escape included. So 2 is written
-- as one yellow square the size of the icon, 1 as an orange one, and the font string's own alpha
-- turns the square into a wash over the icon. Full charges write nothing: the plain icon.
-- EllesmereUI's warrior charges and ForeverAuras' gates use the same pair; C_StringUtil's
-- formatter is in the census. Without one, no wash - the icon and the red still tell the truth.
FS.CHARGE_FULL = 3                             -- Water Shield's globes; at this many or more, no wash
FS.CHARGE_TINT = {                             -- charges left -> r, g, b (0-255, a texture escape's)
    [2] = { 255, 215, 0 },                     -- yellow
    [1] = { 255, 120, 0 },                     -- orange
}
FS.WASH_ALPHA = 0.55
local function wash(px, rgb)
    return ("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t"):format(px, px, rgb[1], rgb[2], rgb[3])
end
local washes = {}
function FS.WashFormatter(px)
    if washes[px] then return washes[px] end
    local make = C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
    if not make then return nil end
    local ok, f = pcall(make)
    if not ok or not f or not f.SetBreakpoints then return nil end
    local points = { { threshold = 0, format = "" } }
    for n = 1, FS.CHARGE_FULL - 1 do
        local rgb = FS.CHARGE_TINT[n]
        points[#points + 1] = { threshold = n, format = rgb and wash(px, rgb) or "" }
    end
    points[#points + 1] = { threshold = FS.CHARGE_FULL, format = "" }
    if not pcall(f.SetBreakpoints, f, points) then return nil end
    washes[px] = f
    return f
end

--- INSIDE A FRAME THAT CUTS IT TO THE ICON (12 Oct 2026). Arn's screenshots, orange then yellow:
--- the wash came out half again the icon's size, hanging off the button down and to the right. A
--- texture escape is sized against the text it sits in, not in the pixels it was asked for, so its
--- size is not ours to trust. So the square is drawn deliberately too big, and a frame the icon's
--- size with SetClipsChildren cuts it to exactly the icon, wherever the text put it. The frame is
--- the client's button's child, so it goes when the buff goes - no wash left over the red.
FS.WASH_OVER = 3                               -- the square, this many times the icon: always covers
function FS.Wash(button, b)
    local px = (b and b.px) or 26
    local f = FS.WashFormatter(px * FS.WASH_OVER)
    if not f then return false end
    local clip = CreateFrame("Frame", nil, button)
    clip:SetAllPoints(button)
    clip:SetClipsChildren(true)
    local fs = clip:CreateFontString(nil, "OVERLAY")
    if fs.SetFont then fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", px, "") end
    fs:SetPoint("CENTER", clip, "CENTER", 0, 0)
    fs:SetAlpha(FS.WASH_ALPHA)
    local ok = pcall(button.SetApplicationCount, button, fs, { formatter = f })
    if b then b.wash, b.washClip = ok and fs or nil, ok and clip or nil end
    return ok
end

local function badgeIcon(button, b)
    if not button then return end
    pcall(function()
        local t = button:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints(button)
        t:SetTexture(spellIcon(b and b.ids, b and b.name))
        if t.SetTexCoord then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        if b then b.icon = t end
    end)
    pcall(FS.Wash, button, b)
    -- clicks go through to the BiS> now button underneath, which casts the buff (EllesmereUI's
    -- AuraKit turns clicks off on the client's buttons the same way)
    if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
    for _, k in ipairs({ "Border", "border" }) do
        local part = button[k]
        if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
    end
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
    if button.EnableMouse then pcall(button.EnableMouse, button, false) end
end

--- The buff the BiS> now shield button stands for: the first watched one this character has
--- trained, and every spell id the book has for it. nil when there is none.
function FS.Target()
    for _, name in ipairs(FS.List()) do
        if FS.Knows(name) then
            local ids = FS.SpellIds(name)
            if #ids > 0 then return name, ids end
        end
    end
    return nil
end

--- What a badge would be built for, as one string: a new rank or a new watched buff changes it.
function FS.TargetSig()
    local name, ids = FS.Target()
    if not name then return "" end
    local sorted = {}
    for i, id in ipairs(ids) do sorted[i] = id end
    table.sort(sorted)
    return name .. ":" .. table.concat(sorted, ",")
end

--- Take one badge down: the container stops, the red goes, and the header word speaks again.
function FS.DropBadge(b)
    if not b then return end
    if b.container and b.container.SetEnabled then pcall(b.container.SetEnabled, b.container, false) end
    if b.container and b.container.Hide then pcall(b.container.Hide, b.container) end
    if b.under and b.under.Hide then b.under:Hide() end
    for i, x in ipairs(FS.badges) do
        if x == b then table.remove(FS.badges, i) break end
    end
    FS.badgeFor[b.name] = nil
end

--- The spell id of the aura called `name` on you right now, read by walking your buffs: nil when it
--- is not on you, false when the client would not say. The book's id and the BUFF's id need not be
--- the same number, and the badge is filtered by the book's.
function FS.AuraIdByName(name)
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return false end
    for i = 1, 40 do
        local ok, a = pcall(get, "player", i, "HELPFUL")
        if not ok then return false end
        if not a then return nil end
        local okN, n = pcall(function() return a.name end)
        n = okN and NS.Plain(n) or nil
        if n == nil then return false end
        if n == name then
            local okI, id = pcall(function() return a.spellId end)
            -- and its charges, out of combat: the wash assumes FS.CHARGE_FULL, and this checks it
            local okC, stacks = pcall(function() return a.applications end)
            return okI and NS.Plain(id) or false, okC and NS.Plain(stacks) or nil
        end
    end
    return nil
end

--- What /bish buff says about each badge, a line each: the ids it is filtered to, the id of the
--- buff actually on you, and whether the client has ever handed it a button to draw.
function FS.BadgeReport()
    local lines = {}
    for _, b in ipairs(FS.badges) do
        local on, charges = FS.AuraIdByName(b.name)
        local match = "not on you now"
        if on == false then match = "the client will not say now"
        elseif on then
            local hit = false
            for _, id in ipairs(b.ids or {}) do if id == on then hit = true end end
            match = ("on you as id %s - %s; %s charges (full counts as %d)"):format(tostring(on),
                hit and "in the filter" or "NOT in the filter", tostring(charges or "?"), FS.CHARGE_FULL)
        end
        lines[#lines + 1] = ("  badge %s: filter %s; %s"):format(b.name, table.concat(b.ids or {}, ","), match)
        local btn = b.button
        if not btn then
            lines[#lines + 1] = "    the game has not drawn it yet"
        else
            -- THE CLIENT'S BUTTON MAY NOT BE ASKED ANYTHING. Arn's client, 12 Oct: "calling '?' on
            -- bad self (Attempt to access forbidden object ...) self:IsVisible()" - the slot rule
            -- in solved.md, again. Every question goes in a pcall; a refusal is an answer.
            local function ask(o, m)
                if not o then return "?" end
                local ok, v = pcall(function() return o[m](o) end)
                if not ok then return "refused" end
                -- a SECRET answer printed as "nil" read like a fault (Arn's paste, 12 Oct)
                if NS.Secret(v) then return "hidden" end
                return tostring(v)
            end
            lines[#lines + 1] = ("    the game made its button (visible %s); our icon on it: %s, visible %s"):format(
                ask(btn, "IsVisible"), b.icon and "made" or "NOT made", ask(b.icon, "IsVisible"))
        end
    end
    return lines
end

--- ONE BADGE, centred on `parent`, `px` square: red with the buff's initials, and the client's
--- button over it while the buff is on you. Answers the badge, or nil and why. OUT OF COMBAT.
---
--- It lived on the grid header first; Arn, seeing it work: "header too crowded" - so it is the
--- face of a BiS> now button now (Now.lua, FN.ArmShield), where a click also recasts the buff.
function FS.MakeBadge(parent, name, ids, px)
    local FA = NS.FA
    if not (parent and name and ids and #ids > 0) then return nil, "nothing to stand for" end
    if not (FA and FA.Available and FA.Available() and FA.AddSlot) then
        return nil, FA and FA.refused or "this client draws no auras for addons"
    end
    local lvl = parent.GetFrameLevel and parent:GetFrameLevel() or 1
    if type(lvl) ~= "number" then lvl = 1 end
    -- what shows when the client draws nothing: red, and the buff's initials
    local under = CreateFrame("Frame", nil, parent)
    under:SetSize(px, px)
    under:SetPoint("CENTER", parent, "CENTER", 0, 0)
    if under.SetFrameLevel then under:SetFrameLevel(lvl + 2) end
    -- THE BUFF'S OWN ICON, WASHED RED (12 Oct 2026). Arn, looking at a red square saying "WS":
    -- "can we make it a red watershield icon?" Greyed, then tinted, so any icon reads as the same
    -- red - and up, the client's icon in full colour covers it: your shield, or your shield gone.
    local red = under:CreateTexture(nil, "ARTWORK")
    red:SetAllPoints(under)
    red:SetTexture(spellIcon(ids, name))
    if red.SetTexCoord then red:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    if red.SetDesaturated then red:SetDesaturated(true) end
    local c = FS.BADGE_RED
    red:SetVertexColor(c[1], c[2], c[3], c[4])
    under.red = red
    -- A PULSE, NOT A STATIC BLOCK (12 Oct 2026). Arn: "lets not make it a red static thing can we
    -- show like a pulsing thing?" It never had to be solid: the client's icon covers whatever is
    -- under it, so the red may breathe. The CLIENT runs the animation - no OnUpdate, no Lua at
    -- all per frame - and it runs under the icon too, unseen, because whether the buff is up is
    -- exactly what we may not know. Alpha in steps a healer reads as "do this", never down to
    -- nothing: a square that vanishes half the time is one you look straight past.
    if under.CreateAnimationGroup then
        local ok, pulse = pcall(under.CreateAnimationGroup, under)
        if ok and pulse then
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(FS.PULSE_LOW)
            fade:SetDuration(FS.PULSE_SECONDS)
            if fade.SetSmoothing then fade:SetSmoothing("IN_OUT") end
            pulse:SetLooping("BOUNCE")
            pulse:Play()
            under.pulse = pulse
        end
    end
    -- and over it, the client's icon while the buff is up. A refusal here is the client saying no
    -- to containers: remembered by FA, and the header word speaks instead.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    if not ok or not container then
        FA.available = false
        FA.refused = "the client refused to build an AuraContainer (protected action?)"
        under:Hide()
        return nil, FA.refused
    end
    container:SetSize(1, 1)
    container:SetPoint("CENTER", under, "CENTER")
    if container.SetFrameLevel then container:SetFrameLevel(lvl + 10) end
    container:SetUnit("player")
    local want = {}
    for _, id in ipairs(ids) do want[id] = true end
    local b = { name = name, under = under, container = container, ids = ids, px = px }
    local slot = FA.AddSlot(container, "BiSHealSelf", "HELPFUL", {
        candidateFilters = { includeSpellIDs = want },
        -- the client hands a button over when the buff appears; noted, so /bish buff can say
        -- whether it ever did (12 Oct, Arn: "water shield on did not turn it on")
        initializeFrame = function(button)
            b.button = button
            badgeIcon(button, b)
        end,
    })
    b.slot = slot
    local placed = slot and FA.Place and FA.Place(slot, px, "CENTER", parent, 0, 0)
    if container.SetEnabled then container:SetEnabled(true) end
    -- and asked to look now, as Fojji's bar does after enabling: a buff already on you is not news
    -- to a container that only starts listening for changes
    if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
    -- a slot that could not be placed draws nowhere useful: the red would never be covered, so it
    -- would cry "missing" for ever. Nothing stands for the buff then, and the word speaks.
    if not placed then
        pcall(container.SetEnabled, container, false)
        under:Hide()
        return nil, "the client would not let the marker be placed"
    end
    FS.badges[#FS.badges + 1] = b
    FS.badgeFor[name] = true
    return b
end

--- THE BUFF LIST OR THE BOOK MAY HAVE CHANGED: if what the badge stands for did, BiS> now is laid
--- out again, which rebuilds its button. Nothing at all when it did not - this runs at every
--- SPELLS_CHANGED. In a fight it waits for the fight to end. Answers how many badges stand.
function FS.Badge()
    local sig = FS.TargetSig()
    if sig == FS.badgeSig then return #FS.badges end
    if InCombatLockdown and InCombatLockdown() then
        FS.badgeLater = true
        return #FS.badges
    end
    FS.badgeLater = nil
    FS.badgeSig = sig
    if NS.FN and NS.FN.Layout then NS.FN.Layout() end
    return #FS.badges
end

--- "Water Shield" -> "WS", for a header one cell wide, where the full name is trimmed to
--- "no Water Shi..." and says less than two letters would. The header's tooltip has the whole of
--- it, which is where a hint belongs: two things sharing 84 pixels is not a layout.
function FS.Initials(name)
    if type(name) ~= "string" then return tostring(name) end
    local out = ""
    for word in name:gmatch("%S+") do out = out .. word:sub(1, 1) end
    return out ~= "" and out or name
end

--- The player's own list: add one, take one away, or go back to the class default.
function FS.Add(name)
    local d = NS.DB and NS.DB()
    if type(d) ~= "table" or type(name) ~= "string" or name == "" then return nil end
    local list = type(d.selfBuffs) == "table" and d.selfBuffs or {}
    for i, n in ipairs(list) do
        if n:lower() == name:lower() then
            table.remove(list, i)
            d.selfBuffs = list
            if #list == 0 then d.selfBuffs = { none = true } end
            FS.Forget()                                 -- and forget what it last was
            FS.Sounds()
            FS.Badge()
            return nil, n                               -- taken off the list
        end
    end
    list[#list + 1] = name
    list.none = nil
    d.selfBuffs = list
    FS.Forget()
    FS.Sounds()                       -- the new list, and nothing left over from the old one
    FS.Badge()
    return name
end

function FS.Reset()
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.selfBuffs = nil end
    FS.Forget()
    FS.Sounds()
    FS.Badge()
    return FS.List()
end

-- A SOUND WHEN IT DROPS, PLAYED BY THE CLIENT. The header cannot tell you mid-fight, because your
-- own buffs are secret there - but the client will make a noise for you without an addon reading
-- anything: C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Removed, { unitToken, spellID, ... }).
-- ForeverAuras 0.1.148 ships exactly this call, which is where the shape came from.
--
-- Registered per SPELL ID, so every rank of the buff this character has trained is covered, and
-- taken down again whenever the list changes - a registration nobody removes is a sound that keeps
-- playing for a buff you stopped watching.
--
-- TWO SETTINGS, NOT ONE. `buffSound` is WHICH sound - a file id, or nothing for ours. `buffQuiet`
-- is WHETHER. They were one field to begin with, where `false` meant silence, and switching the
-- sound off and on again threw away the number the player had typed. A switch and a number are
-- two questions, and the options window asks them in two places.
-- Arn picked it by ear, 23 Sep, after hearing 567458: "567474 make this the default sound".
FS.SOUND = 567474          -- a file id out of the game's own files. /bish buffsound sets another
FS.soundIDs = {}

--- The sound that would play: the player's number, or ours.
function FS.File()
    local d = NS.DB and NS.DB()
    local own = type(d) == "table" and d.buffSound or nil
    if type(own) == "number" or (type(own) == "string" and own ~= "") then return own end
    return FS.SOUND
end

--- Is it switched off?
function FS.Quiet()
    local d = NS.DB and NS.DB()
    return type(d) == "table" and d.buffQuiet == true
end

--- Play it once, right now, so a number typed into the options window can be HEARD before it is
--- kept. Answers true when the client played it.
---
--- A NUMBER, NOT A PATH. BiSGamba passed the whole Forever fence with every cue silent: the modern
--- engine will not play a game file by path any more, and says it succeeded (`_bisdev/CLAUDE.md`,
--- "green fence not mean work"). So a path is handed over as asked and reported as a maybe; a file
--- id is the thing that actually makes a noise.
function FS.Play(file)
    file = file or FS.File()
    if type(file) == "number" then
        if type(PlaySoundFile) ~= "function" then return false, "this client cannot play a file" end
        local ok, played = pcall(PlaySoundFile, file, "Master")
        if ok and played ~= false then return true end
        -- a file id the client does not have: PlaySound takes the sound-kit ids instead
        if type(PlaySound) == "function" and pcall(PlaySound, file, "Master") then return true end
        return false, "no sound with that id"
    end
    if type(file) == "string" and file ~= "" and type(PlaySoundFile) == "function" then
        pcall(PlaySoundFile, file, "Master")
        return false, "a file path is silent on this client - use a sound id"
    end
    return false, "nothing to play"
end

--- Every spell id this character has for a name: a buff is a different id at every rank.
---
--- FROM THE ONE READ THE MOUSE KEEPS (8 Oct 2026). This walked all 500 book slots itself, and
--- FS.Check asks it for every watched buff on every UNIT_AURA about you - which in a fight is
--- every proc, every debuff and every tick of anything. Mouse.lua loads after this file, so the
--- book is looked up here, when asked, and a fresh list comes back each time as it always did.
function FS.SpellIds(name)
    if NS.FM and NS.FM.BookIds then return NS.FM.BookIds(name) end
    return {}
end

--- Ask the client to make a noise when one of these leaves you. Answers how many it registered,
--- or false and why - a client without the call is not an error, it is a client without the call.
function FS.Sounds()
    for _, id in ipairs(FS.soundIDs) do
        if C_UnitAuras and C_UnitAuras.RemoveAuraSound then pcall(C_UnitAuras.RemoveAuraSound, id) end
    end
    FS.soundIDs = {}
    if FS.Quiet() then return false, "off" end
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger
            and Enum.UnitAuraSoundTrigger.Removed) then
        return false, "this client has no aura sounds"
    end
    local file = FS.File()
    local n = 0
    for _, name in ipairs(FS.List()) do
        for _, spellID in ipairs(FS.SpellIds(name)) do
            local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Removed, {
                unitToken = "player", spellID = spellID,
                soundFileID = type(file) == "number" and file or nil,
                soundFileName = type(file) == "string" and file or nil,
                outputChannel = "Master",
            })
            if ok and id then
                FS.soundIDs[#FS.soundIDs + 1] = id
                n = n + 1
            end
        end
    end
    return n
end

function FS.Start()
    if FS.frame then return true end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UNIT_AURA",
                         "SPELLS_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, unit)
        -- nil unit = an event about nobody in particular (SPELLS_CHANGED), which we want. A unit
        -- that is somebody, or that the client will not let us identify, is not our business.
        -- (7 Oct 2026) a raid aura is answered with ONE question, not IsPlayer's two-plus: the
        -- client always sends "player" for your own auras, so anything else is somebody else's
        if event == "UNIT_AURA" and (NS.Secret(unit) or unit ~= "player") then return end
        if unit ~= nil and (NS.IsPlayer and NS.IsPlayer(unit)) ~= true then return end
        -- THE BOOK IS KEPT NOW (Mouse.lua), and its own listener hears these two events too - but
        -- which frame the client tells FIRST is not ours to say. If it were this one, the check
        -- below would be about the book as it was, and nothing would ask again. So the kept book
        -- is dropped here before it is read, whoever was told first.
        if (event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD") and NS.FM and NS.FM.BookChanged then
            NS.FM.BookChanged()
        end
        FS.Check()
        -- the book fills in late at login, and a rank learned later is a new spell id
        if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
            FS.Sounds()
            FS.Badge()                -- a no-op unless what it stands for changed
        elseif event == "PLAYER_REGEN_ENABLED" and FS.badgeLater then
            FS.Badge()                -- asked for during a fight; now the client allows it
        end
    end)
    FS.frame = f
    FS.Check()
    FS.Sounds()
    FS.Badge()
    return true
end

NS.FS = FS
