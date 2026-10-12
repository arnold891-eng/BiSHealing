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
FS.BADGE_RED = { 0.80, 0.12, 0.16, 0.95 }

-- the client's own icon and charges, its border gone, and no mouse: it sits on a drag handle
local function badgeIcon(button)
    if not button then return end
    for _, k in ipairs({ "Border", "border" }) do
        local part = button[k]
        if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
    end
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
    if button.EnableMouse then pcall(button.EnableMouse, button, false) end
end

--- What the badges would be built for: the buffs this character has, and every id of each.
local function badgeSig(px)
    local parts = { "px" .. px }
    for _, name in ipairs(FS.List()) do
        if FS.Knows(name) then
            local ids = FS.SpellIds(name)
            if #ids > 0 then
                local sorted = {}
                for i, id in ipairs(ids) do sorted[i] = id end
                table.sort(sorted)
                parts[#parts + 1] = name .. ":" .. table.concat(sorted, ",")
            end
        end
    end
    return table.concat(parts, "|")
end

local function badgeDown()
    for _, b in ipairs(FS.badges) do
        if b.container and b.container.SetEnabled then pcall(b.container.SetEnabled, b.container, false) end
        if b.container and b.container.Hide then pcall(b.container.Hide, b.container) end
        if b.under and b.under.Hide then b.under:Hide() end
    end
    FS.badges, FS.badgeFor = {}, {}
end

--- Put a badge on the header's right end for each watched buff this character has. Answers how
--- many stand. In a fight it does nothing and asks again when the fight ends.
function FS.Badge(header)
    header = header or (NS.FG and NS.FG.header)
    if not header then return 0 end
    if InCombatLockdown and InCombatLockdown() then
        FS.badgeLater = true
        return #FS.badges
    end
    FS.badgeLater = nil
    local FA = NS.FA
    if not (FA and FA.Available and FA.Available() and FA.AddSlot) then
        if #FS.badges > 0 then badgeDown() end
        FS.badgeSig = nil
        return 0
    end
    local h = header.GetHeight and header:GetHeight() or 0
    local px = (type(h) == "number" and h > 6) and math.floor(h - 2) or 14
    local sig = badgeSig(px)
    if sig == FS.badgeSig then return #FS.badges end
    badgeDown()
    FS.badgeSig = sig
    local lvl = header.GetFrameLevel and header:GetFrameLevel() or 1
    if type(lvl) ~= "number" then lvl = 1 end
    for _, name in ipairs(FS.List()) do
        local ids = FS.Knows(name) and FS.SpellIds(name) or {}
        if #ids > 0 then
            local x = -1 - #FS.badges * (px + 2)
            -- what shows when the client draws nothing: red, and the buff's initials
            local under = CreateFrame("Frame", nil, header)
            under:SetSize(px, px)
            under:SetPoint("RIGHT", header, "RIGHT", x, 0)
            if under.SetFrameLevel then under:SetFrameLevel(lvl + 2) end
            local red = under:CreateTexture(nil, "ARTWORK")
            red:SetAllPoints(under)
            local c = FS.BADGE_RED
            red:SetColorTexture(c[1], c[2], c[3], c[4])
            local tag = under:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tag:SetPoint("CENTER", under, "CENTER", 0, 0)
            tag:SetText(FS.Initials(name))
            under.red, under.tag = red, tag
            -- and over it, the client's icon while the buff is up. A refusal here is the client
            -- saying no to containers: remembered by FA, and the header word speaks instead.
            local ok, container = pcall(CreateFrame, "AuraContainer", nil, header, "CustomAuraContainerTemplate")
            if not ok or not container then
                FA.available = false
                FA.refused = "the client refused to build an AuraContainer (protected action?)"
                under:Hide()
                badgeDown()
                FS.badgeSig = nil
                return 0
            end
            container:SetSize(1, 1)
            container:SetPoint("CENTER", under, "CENTER")
            if container.SetFrameLevel then container:SetFrameLevel(lvl + 10) end
            container:SetUnit("player")
            local want = {}
            for _, id in ipairs(ids) do want[id] = true end
            local slot = FA.AddSlot(container, "BiSHealSelf" .. #FS.badges, "HELPFUL", {
                candidateFilters = { includeSpellIDs = want },
                initializeFrame = badgeIcon,
            })
            local placed = slot and FA.Place and FA.Place(slot, px, "RIGHT", header, x, 0)
            if container.SetEnabled then container:SetEnabled(true) end
            local b = { name = name, under = under, container = container, slot = slot }
            FS.badges[#FS.badges + 1] = b
            -- a slot that could not be placed draws nowhere useful: the red would never be
            -- covered, so it would cry "missing" for ever. The word speaks for that buff instead.
            if placed then
                FS.badgeFor[name] = true
            else
                under:Hide()
            end
        end
    end
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
