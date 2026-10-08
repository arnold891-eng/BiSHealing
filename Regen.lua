-- BiSHealing / Regen -- the five second rule, drawn where a healer is already looking.
--
-- Arn, 23 Sep 2026: "can we add a the 5 second mana regen rule. and say like regening mana at 100%
-- or in combat regening combat at 50% ... itll be like a bar thats filling backwards in the header
-- or a glow effect that start on one side and it takes 5 seconds to go to the other side".
--
-- THE RULE. Spend mana and your out-of-combat regeneration stops for five seconds. What you get
-- during those five seconds is whatever "mana regeneration while casting" your character has -
-- nothing at all for most, a share of it for a healer who has spent points on it.
--
-- WE DO NOT READ TALENTS FOR THIS, and we do not need to. GetManaRegen() answers with two numbers:
-- what you regenerate standing still, and what you regenerate while casting - the same pair the
-- character sheet shows, already carrying the talents, the gear and the buffs. One call beats a
-- list of talent names that would be wrong for the next class and the next patch.
--
-- WHAT THE CLIENT ALLOWS. This is YOUR character: your own mana, your own regen. None of it is a
-- secret the way another player's health is. Every read is still guarded - a client that refuses
-- answers nothing and the header simply does not draw the bar.
--
-- WHEN THE CLOCK STARTS. UNIT_SPELLCAST_SUCCEEDED for the player, when the spell cost mana. The
-- real rule starts the moment the mana leaves you; for an instant those are the same, and for a
-- cast this is the end of it rather than the start - a fraction of a second late, never early, so
-- the bar never says "regenerating" while you are not.

local ADDON, NS = ...
NS = NS or {}

local FR = {}
NS.FR = FR

FR.WINDOW = 5          -- seconds, the rule itself

--- When mana last left you, by the client's clock.
FR.spentAt = nil

--- Seconds left of the five, or 0 when you are regenerating normally again.
function FR.Left()
    if not FR.spentAt then return 0 end
    local now = (GetTime and GetTime()) or 0
    local left = FR.WINDOW - (now - FR.spentAt)
    if left <= 0 then return 0 end
    return left
end

--- THE TWO NUMBERS, from whichever call this client answers with. Arn, 23 Sep, in a fight: the
--- header fell back to "Healing" while he was casting, which means GetManaRegen said nothing on
--- this character. The client's API list has four ways to ask, so all of them are asked in turn
--- and the first pair of real numbers wins. `/bish regen` prints what each one said.
FR.SOURCES = {
    -- WRITTEN OUT, NOT `f and f()`: that idiom keeps only the FIRST return value, so the second
    -- number - what you regenerate while casting, the whole point of asking - was thrown away
    -- before anything could read it, and the header fell back to "Healing" mid-fight (23 Sep).
    { name = "GetManaRegen", get = function()
        if type(GetManaRegen) ~= "function" then return nil end
        return GetManaRegen()
    end },
    { name = "GetPowerRegen", get = function()
        if type(GetPowerRegen) ~= "function" then return nil end
        return GetPowerRegen()
    end },
    { name = "GetPowerRegenForPowerType", get = function()
        if type(GetPowerRegenForPowerType) ~= "function" then return nil end
        local mana = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
        return GetPowerRegenForPowerType(mana)
    end },
}

--- What the client says RIGHT NOW: standing still, and while casting. Nil when none of them will
--- answer - which in a fight is all of them.
function FR.Live()
    for _, src in ipairs(FR.SOURCES) do
        local ok, base, casting = pcall(src.get)
        base, casting = NS.Plain(base), NS.Plain(casting)
        if ok and type(base) == "number" and type(casting) == "number" and base > 0 then
            return base, casting, src.name
        end
    end
    return nil
end

--- REMEMBERED, BECAUSE IN A FIGHT IT IS A SECRET. Measured in game, 23 Sep 2026: out of combat all
--- three calls answer (16.88 standing, 10.44 casting on Arn's shaman - 62%), and the moment the
--- fight starts every one of them comes back SECRET. Your own regeneration is hidden from you at
--- exactly the moment it matters.
---
--- So the pair is kept whenever it can be read, and that is what the header shows once the client
--- stops talking. It changes with talents, gear and buffs - not mid-pull, for the most part - and
--- a number from thirty seconds ago beats a question mark while you are deciding whether to cast.
FR.known = nil

function FR.Remember()
    local base, casting, from = FR.Live()
    if not base then return nil end
    FR.known = { base = base, casting = casting, from = from, at = (GetTime and GetTime()) or 0 }
    return base, casting, from
end

--- The pair to work from: what the client says now, or the last thing it said.
function FR.Rates()
    local base, casting, from = FR.Live()
    if base then
        FR.known = { base = base, casting = casting, from = from, at = (GetTime and GetTime()) or 0 }
        return base, casting, from, false
    end
    local k = FR.known
    if k then return k.base, k.casting, k.from, true end
    return nil
end

--- What share of your standing-still regeneration you are getting right now: 1 when the five
--- seconds are up, and the character sheet's "while casting" share while they are not. Nil when
--- no call on this client will say, so the header can show that rather than invent a number.
function FR.Fraction()
    if FR.Left() <= 0 then return 1 end
    local base, casting, _, remembered = FR.Rates()
    if not base then return nil end
    local f = casting / base
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return f, remembered
end

--- The words for it: "regen 100%" when the five seconds are up, "regen 30%" while they are not,
--- and "regen ?" when this client will not say what the while-casting share is. It still says
--- "regen", because the five seconds ARE running and that is the thing worth knowing.
--- SHORT, for a header one cell wide. Arn, 23 Sep: "in the regular down toggel the regen gets cut
--- off" - a party grid is 84 pixels across and "BiS> regen 62%" does not fit in it, so the client
--- trimmed it to "BiS> regen ..." and the one thing worth reading was the thing that went. The
--- number is what a healer is deciding on; the word in front of it is the part they can spare, and
--- the bar draining across the bar already says what the number is about.
function FR.Text(short)
    local f = FR.Fraction()
    if not f then return short and "?" or "regen ?" end
    local pct = ("%d%%"):format(math.floor(f * 100 + 0.5))
    return short and pct or ("regen " .. pct)
end

--- Does this spell cost mana? Only then does the clock start. Asked of the client rather than
--- assumed: a shapeshift, a totem recall or a free proc costs nothing and must not stop your regen.
function FR.CostsMana(spellID)
    local get = (C_Spell and C_Spell.GetSpellPowerCost) or GetSpellPowerCost
    if not get or spellID == nil then return true end      -- cannot ask: treat a cast as a spend
    local ok, costs = pcall(get, spellID)
    if not ok or type(costs) ~= "table" then return true end
    for _, c in ipairs(costs) do
        local kind = NS.Plain(c.type) or NS.Plain(c.powerType)
        local amount = NS.Plain(c.cost) or NS.Plain(c.minCost) or 0
        -- 0 is Enum.PowerType.Mana on every client that has the enum, and the plain number on
        -- those that do not
        if (kind == 0 or kind == (Enum and Enum.PowerType and Enum.PowerType.Mana)) and (amount or 0) > 0 then
            return true
        end
    end
    return false
end

function FR.Spend(now)
    FR.spentAt = now or (GetTime and GetTime()) or 0
    return FR.spentAt
end

--- One cast, as the client reports it.
function FR.OnCast(unit, spellID)
    -- was `unit ~= "player"`. A unit token the client hands an event handler can come back secret,
    -- and comparing a secret value is refused outright - so ask NS.IsPlayer, which uses UnitIsUnit
    -- and only falls back to the compare when the client allows it (1 Oct 2026). "Could not tell"
    -- is treated as not-us, which is what a failed compare did before, minus the error.
    if (NS.IsPlayer and NS.IsPlayer(unit)) ~= true then return false end
    if not FR.CostsMana(spellID) then return false end
    FR.Spend()
    return true
end

function FR.Start()
    if FR.frame then return true end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
                         "UNIT_AURA", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        -- ONLY YOUR OWN AURAS (7 Oct 2026). UNIT_AURA fires for every buff, debuff and tick on
        -- every raid member - hundreds a second in a fight - and each one tried four regen sources
        -- here. Your regen moves with YOUR buffs; the client always sends "player" for those.
        -- Asked secret first: a value we may not read refuses the comparison itself.
        if event == "UNIT_AURA" and (NS.Secret(unit) or unit ~= "player") then return end
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            FR.OnCast(unit, spellID)
        else
            -- the moments the pair can change AND can still be read: a fight ending, a buff, a
            -- trinket swapped, a talent spent. In the fight itself the client says nothing.
            FR.Remember()
        end
    end)
    FR.frame = f
    FR.Remember()
    return true
end

NS.FR = FR
