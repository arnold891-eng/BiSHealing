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
function FS.Word(short)
    local missing = FS.known
    if type(missing) ~= "table" or #missing == 0 then return nil end
    return "no " .. (short and FS.Initials(missing[1]) or missing[1])
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
            return nil, n                               -- taken off the list
        end
    end
    list[#list + 1] = name
    list.none = nil
    d.selfBuffs = list
    FS.Forget()
    FS.Sounds()                       -- the new list, and nothing left over from the old one
    return name
end

function FS.Reset()
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.selfBuffs = nil end
    FS.Forget()
    FS.Sounds()
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
function FS.SpellIds(name)
    local ids = {}
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if not (C_SpellBook and C_SpellBook.GetSpellBookItemName and C_SpellBook.GetSpellBookItemInfo) then
        return ids
    end
    for i = 1, 500 do
        local got, nm = pcall(C_SpellBook.GetSpellBookItemName, i, bank)
        if got and nm == name then
            local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
            local id = ok and type(info) == "table" and NS.Plain(info.spellID) or nil
            if type(id) == "number" then ids[#ids + 1] = id end
        end
    end
    return ids
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
        if unit ~= nil and unit ~= "player" then return end
        FS.Check()
        -- the book fills in late at login, and a rank learned later is a new spell id
        if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then FS.Sounds() end
    end)
    FS.frame = f
    FS.Check()
    FS.Sounds()
    return true
end

NS.FS = FS
