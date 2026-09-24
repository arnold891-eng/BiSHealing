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
    return name
end

function FS.Reset()
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.selfBuffs = nil end
    return FS.List()
end

function FS.Start()
    if FS.frame then return true end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "UNIT_AURA",
                         "SPELLS_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, _, unit)
        if unit ~= nil and unit ~= "player" then return end
        FS.Check()
    end)
    FS.frame = f
    FS.Check()
    return true
end

NS.FS = FS
