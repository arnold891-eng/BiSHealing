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

--- Which of them are not on you right now. Returns the list, and false when the client would not
--- say - which is the whole of a fight, and is not the same as "none missing".
function FS.Missing()
    if NS.Blind and NS.Blind() then return nil, false end
    local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    if not get then return nil, false end
    local up, readable = {}, true
    for i = 1, 40 do
        local ok, a = pcall(get, "player", i, "HELPFUL")
        if not ok or not a then break end
        local name = pcall(function() return a.name end) and NS.Plain(a.name) or nil
        if name == nil then readable = false else up[name] = true end
    end
    if not readable then return nil, false end
    local missing = {}
    for _, name in ipairs(FS.List()) do
        if FS.Knows(name) and not up[name] then missing[#missing + 1] = name end
    end
    return missing, true
end

--- What the header should say about it, or nil. Kept from the last readable moment, because in a
--- fight the client says nothing: a shield that fell off mid-pull is news the moment it ends.
FS.known = nil

function FS.Check()
    local missing, readable = FS.Missing()
    if readable then FS.known = missing end
    return FS.known
end

--- "no Water Shield", or nil when nothing is missing or nothing is known yet. Short on purpose:
--- it shares the header with the prompt, and a header is one cell wide on a party grid.
function FS.Word()
    local missing = FS.known
    if type(missing) ~= "table" or #missing == 0 then return nil end
    return "no " .. missing[1]
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
            return nil, n                               -- taken off the list
        end
    end
    list[#list + 1] = name
    list.none = nil
    d.selfBuffs = list
    FS.Sounds()                       -- the new list, and nothing left over from the old one
    return name
end

function FS.Reset()
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.selfBuffs = nil end
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
FS.SOUND = 567458          -- a file id: the client's own alarm. /bish buffsound sets another
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
