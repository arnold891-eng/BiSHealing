-- BiSHealing / Keep -- the binds, somewhere this client will actually give them back.
--
-- THE PROBLEM THIS EXISTS FOR (19 Sep 2026, proved six ways). The Forever beta writes
-- SavedVariables perfectly at logout and hands back NOTHING at the next start - account-wide and
-- per-character alike, for every addon, not just ours. !BugGrabber's session counter is stuck at
-- 1, Healium writes byte-identical defaults twice in a row and the player watches its slots empty
-- themselves, and a valid file planted by hand in seven candidate folders was read from none of
-- them. It is not a path fault. The loader does not run. An addon cannot read a file, so no
-- amount of Lua fixes it.
--
-- WHAT DOES COME BACK: macros. They live on the SERVER, not in the WTF folder the loader is
-- ignoring. Arn's macros written on 18 September were still there on the 19th, through every
-- restart in between, and this client has the whole API - CreateMacro, EditMacro, GetMacroBody,
-- GetMacroIndexByName, GetNumMacros. So the binds go in a macro.
--
-- WHAT IT COSTS, because it is not free: one per-character macro slot, called "BiSHealing", which
-- the player can see and must not rename. We touch ONLY a macro with that exact name - never
-- edit, never rename, never delete one of theirs - and if there is no room we do nothing and say
-- so. The body is inert: no slash command, so clicking it casts nothing.
--
--   BiSH1;Healing Wave#u=1:2;su=1:4
--   ^     ^                ^
--   |     |                shift-wheelup = spell 1, Rank 4
--   |     the spell list, written once however many slots use it
--   the format, so a later one can be told apart from this one
--
-- A macro body is 255 characters. Spell names are the long part and repeat across slots, so they
-- are stored once and referenced by number: that fits a wheel-and-click setup many times over.
-- A mouse with all 28 slots full of long names can still overflow, and then the LAST binds are
-- dropped rather than the whole thing failing silently - Keep.Save says how many did not fit.

local ADDON, NS = ...
NS = NS or {}
local FK = {}
NS.FK = FK

FK.MACRO = "BiSHealing"
FK.ICON  = "INV_Misc_QuestionMark"
FK.LIMIT = 255
FK.TAG   = "BiSH1"

-- one letter per slot and per modifier, because the budget is characters
local SLOTCODE = { left = "l", right = "r", wheelup = "u", wheeldown = "d",
                   middle = "m", button4 = "4", button5 = "5" }
local MODCODE  = { [""] = "", ["shift-"] = "s", ["ctrl-"] = "c", ["alt-"] = "a" }
local CODESLOT, CODEMOD = {}, {}
for k, v in pairs(SLOTCODE) do CODESLOT[v] = k end
for k, v in pairs(MODCODE) do if v ~= "" then CODEMOD[v] = k end end

--- Every bind key, in one settled order, so the same mouse always encodes to the same string and
--- "what got dropped" is a question with an answer.
local function eachKey()
    local out, FM = {}, NS.FM
    for _, m in ipairs((FM and FM.MODS) or {}) do
        for _, s in ipairs((FM and FM.SLOTS) or {}) do
            local code = (MODCODE[m.key] or "") .. (SLOTCODE[s.key] or "")
            if code ~= "" then out[#out + 1] = { key = m.key .. s.key, code = code } end
        end
    end
    return out
end

--- "Healing Wave(Rank 4)" -> "Healing Wave", 4. The rank is kept as a NUMBER here; it is the
--- shortest thing that survives the round trip, and FM.Cast puts the client's wording back.
local function split(cast)
    local name, rank = cast:match("^(.-)%((.-)%)%s*$")
    if not name then return cast, nil end
    return (name:gsub("%s+$", "")), tonumber(rank:match("%d+") or "")
end

--- The binds as a macro body, and how many would not fit.
function FK.Encode(binds)
    if type(binds) ~= "table" then return nil, 0 end
    local rows, spells, at = {}, {}, {}
    for _, e in ipairs(eachKey()) do
        local cast = binds[e.key]
        if type(cast) == "string" and cast ~= "" then
            local name, rank = split(cast)
            if not at[name] then
                spells[#spells + 1] = name
                at[name] = #spells
            end
            rows[#rows + 1] = { code = e.code, spell = at[name], rank = rank }
        end
    end
    if #rows == 0 then return FK.TAG .. "#", 0 end

    -- built longest-first, then shortened from the END until it fits: the last binds go, and the
    -- spell list is rebuilt each time so a name nobody references any more stops costing anything
    local dropped = 0
    while true do
        local used, list, seen = {}, {}, {}
        for i = 1, #rows do
            local n = spells[rows[i].spell]
            if not seen[n] then seen[n] = true; list[#list + 1] = n end
        end
        for i = 1, #list do used[list[i]] = i end
        local parts = {}
        for i = 1, #rows do
            local r = rows[i]
            parts[#parts + 1] = r.code .. "=" .. used[spells[r.spell]] .. (r.rank and (":" .. r.rank) or "")
        end
        local body = FK.TAG .. ";" .. table.concat(list, ";") .. "#" .. table.concat(parts, ";")
        if #body <= FK.LIMIT or #rows == 0 then return body, dropped end
        rows[#rows] = nil
        dropped = dropped + 1
    end
end

--- A macro body back into binds. Anything it does not understand is ignored rather than guessed
--- at: a body someone has edited by hand should cost them one bind, not the whole mouse.
function FK.Decode(body)
    if type(body) ~= "string" then return nil end
    local head, rest = body:match("^(.-)#(.*)$")
    if not head then return nil end
    local tag, names = head:match("^([^;]+);?(.*)$")
    if tag ~= FK.TAG then return nil end
    local spells = {}
    for n in (names or ""):gmatch("[^;]+") do spells[#spells + 1] = n end
    local out, n = {}, 0
    for row in (rest or ""):gmatch("[^;]+") do
        local code, idx, rank = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code then
            local slot = CODESLOT[code:sub(-1)]
            local mod  = #code > 1 and CODEMOD[code:sub(1, 1)] or ""
            local name = spells[tonumber(idx)]
            if slot and mod and name then
                out[mod .. slot] = (NS.FM and NS.FM.Cast)
                    and NS.FM.Cast(name, rank ~= "" and ("Rank " .. rank) or nil)
                    or name
                n = n + 1
            end
        end
    end
    if n == 0 then return nil end
    return out
end

--- Is the macro API here and willing to talk? Asked separately so the caller can tell "no macro
--- yet" from "too early to ask", and only stop retrying for the first one.
function FK.Ready()
    return type(GetMacroIndexByName) == "function" and type(GetMacroBody) == "function"
end

--- The binds this character kept, or nil.
function FK.Load()
    if not FK.Ready() then return nil end
    local ok, idx = pcall(GetMacroIndexByName, FK.MACRO)
    if not ok or type(idx) ~= "number" or idx <= 0 then return nil end
    local got, body = pcall(GetMacroBody, idx)
    if not got or type(body) ~= "string" then return nil end
    return FK.Decode(body)
end

--- Write them down. Refuses in combat - the client will not make a macro there - and says why,
--- so the caller can come back when the lockdown lifts instead of losing the change.
function FK.Save(binds)
    if not FK.Ready() or type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" then
        return false, "no macro api"
    end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local body, dropped = FK.Encode(binds)
    if not body then return false, "nothing to write" end

    local ok, idx = pcall(GetMacroIndexByName, FK.MACRO)
    if ok and type(idx) == "number" and idx > 0 then
        local done = pcall(EditMacro, idx, FK.MACRO, FK.ICON, body)
        return done and true or false, done and dropped or "the client refused the edit"
    end

    -- no room is a real answer, not a failure to hide: 18 per-character slots, and they are the
    -- player's before they are ours
    local gok, _, perChar = pcall(GetNumMacros)
    if gok and type(perChar) == "number" and perChar >= 18 then
        return false, "your character macro slots are full"
    end
    local made = pcall(CreateMacro, FK.MACRO, FK.ICON, body, 1)   -- 1 = this character only
    return made and true or false, made and dropped or "the client refused to make the macro"
end

NS.FK = FK
