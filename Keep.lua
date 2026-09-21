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
FK.POS_ZERO = 5000     -- added to the grid's position so a negative offset fits a digits-only row

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

--- The settings that ride along with the binds, as rows of their own. Arn, 20 Sep: "put scale in
--- the macro" - it is a saved variable, and on this client a saved variable does not survive a
--- restart, so a size set "once, from the beginning" would reset at every login.
---
--- WRITTEN SO BOTH DIRECTIONS ARE SAFE, because people on 0.1.0 and 0.2.0 already have macros:
---   * an OLD install reading a new body sees `S=90`, looks for a slot called "S", finds none,
---     and skips the row - exactly as it skips any row it cannot read. Bind codes are l r u d m 4 5
---     with an optional lowercase s c a in front; an uppercase S is none of them.
---   * a NEW install reading an old body finds no S row and leaves the scale at 100%.
--- And they go FIRST, because the trimmer drops rows from the END when a full mouse overflows the
--- 255 characters: a setting must never be what gets cut to make room for a bind.
---
--- 21 Sep, the same way: the number on the cells (T) and the bar colour (C). Only written when
--- they differ from the default, so a mouse nobody has styled pays nothing for them. Uppercase
--- again, for the same reason as S.
local TEXTCODE = { off = 0, percent = 2 }             -- 1, "missing", is the default and not written
local CODETEXT = { [0] = "off", [1] = "missing", [2] = "percent" }

local function settingRows(settings)
    local out = {}
    if type(settings) ~= "table" then return out end
    local s = tonumber(settings.scale)
    if s and s ~= 1 then out[#out + 1] = "S=" .. math.floor(s * 100 + 0.5) end
    if TEXTCODE[settings.text or ""] then out[#out + 1] = "T=" .. TEXTCODE[settings.text] end
    if settings.color == "health" then out[#out + 1] = "C=1" end
    -- 21 Sep, the same again: where the grid was dragged (P) and whether it is hidden (H). Arn:
    -- "when i log on it puts the frames back in the center". The position is the grid's offset
    -- from the middle of the screen, which can be negative, and a row only carries digits - so
    -- both numbers ride with POS_ZERO added, "P=4800:5120" for 200 left and 120 up.
    local p = settings.pos
    if type(p) == "table" and tonumber(p.x) and tonumber(p.y) then
        local x = math.floor(tonumber(p.x) + 0.5) + FK.POS_ZERO
        local y = math.floor(tonumber(p.y) + 0.5) + FK.POS_ZERO
        if x >= 0 and y >= 0 and x < 2 * FK.POS_ZERO and y < 2 * FK.POS_ZERO then
            out[#out + 1] = ("P=%d:%d"):format(x, y)
        end
    end
    if settings.hidden then out[#out + 1] = "H=1" end
    return out
end

--- The binds as a macro body, and how many would not fit.
function FK.Encode(binds, settings)
    if type(binds) ~= "table" then return nil, 0 end
    local lead = settingRows(settings)
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
    if #rows == 0 then return FK.TAG .. "#" .. table.concat(lead, ";"), 0 end

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
        for i = 1, #lead do parts[#parts + 1] = lead[i] end
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
    -- THE CLIENT ADDS A NEWLINE when it stores a macro, so what comes back is one character
    -- longer than what went in (31 out, 32 back - measured 19 Sep 2026). Every row here is
    -- matched with an anchored pattern, so the LAST one carried that newline and never matched:
    -- exactly one bind vanished at every reload, the last one written, while sitting in the macro
    -- in plain sight. Arn watched his shift-wheel bind disappear four times before `/bish keep`
    -- printed the character count and gave it away.
    body = body:match("^%s*(.-)%s*$") or body
    local head, rest = body:match("^(.-)#(.*)$")
    if not head then return nil end
    local tag, names = head:match("^([^;]+);?(.*)$")
    if tag ~= FK.TAG then return nil end
    local spells = {}
    for n in (names or ""):gmatch("[^;]+") do spells[#spells + 1] = n end
    local out, n, settings = {}, 0, {}
    for row in (rest or ""):gmatch("[^;]+") do
        row = row:match("^%s*(.-)%s*$") or row      -- and per row, for anything hand-edited
        local code, idx, rank = row:match("^(%a?%w)=(%d+):?(%d*)$")
        if code == "S" then
            -- a setting, not a bind: the scale, as a whole percentage
            settings.scale = tonumber(idx) and (tonumber(idx) / 100) or nil
        elseif code == "T" then
            settings.text = CODETEXT[tonumber(idx)]
        elseif code == "C" then
            settings.color = tonumber(idx) == 1 and "health" or "class"
        elseif code == "P" and tonumber(idx) and tonumber(rank) then
            settings.pos = { x = tonumber(idx) - FK.POS_ZERO, y = tonumber(rank) - FK.POS_ZERO }
        elseif code == "H" then
            settings.hidden = tonumber(idx) == 1
        elseif code then
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
    -- no binds is still an answer about the settings: a macro can hold a size and nothing else
    if n == 0 then return nil, settings end
    return out, settings
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
    local d = NS.DB and NS.DB()
    local t = type(d) == "table" and d or {}
    -- the position only when it is pinned by the centre (FG.Recenter); any other kind of point
    -- is not two numbers, and "back in the middle" is what writing nothing means
    local gp, pos = t.gridPos, nil
    if type(gp) == "table" and gp.point == "CENTER" and (gp.rel == nil or gp.rel == "CENTER") then
        pos = { x = gp.x or 0, y = gp.y or 0 }
    end
    local body, dropped = FK.Encode(binds, { scale = t.scale, text = t.text, color = t.color,
                                             pos = pos, hidden = t.shown == false })
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
