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
local SPOTCODE = { under = 1, right = 2, left = 3, top = 4, free = 5 }
local CODESPOT = { [1] = "under", [2] = "right", [3] = "left", [4] = "top", [5] = "free" }
local LAYOUTCODE = { rows = 1, pyramid = 2 }          -- columns is 0, the default, never written
local CODELAYOUT = { [0] = "columns", [1] = "rows", [2] = "pyramid" }
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
    -- heals over time on the cells are on by default; only "off" is worth a row (O for "over time")
    if settings.hots == false then out[#out + 1] = "O=0" end
    -- clicks handed to Clique (K for clicK); off is the default and is not written
    if settings.clique == true then out[#out + 1] = "K=1" end
    -- 23 Sep, a player's three requests: the layout (L), a cell for your target (G, for tarGet),
    -- and how big the markers are (M). Defaults - columns, no target cell, 10 pixels - write nothing.
    if LAYOUTCODE[settings.layout or ""] then out[#out + 1] = "L=" .. LAYOUTCODE[settings.layout] end
    -- the target cell: G says WHERE as well as whether, and a dragged one writes its place in Q
    -- (the same two-numbers-from-the-middle trick as the grid's P)
    if settings.target == true then
        -- the tot cell rides in the SAME row, after the colon: it only exists hanging off the
        -- target cell, so a row of its own would be a row that can contradict this one
        out[#out + 1] = "G=" .. (SPOTCODE[settings.targetAt or ""] or 1) .. (settings.tot and ":1" or "")
        local q = settings.targetPos
        if (settings.targetAt == "free") and type(q) == "table" and tonumber(q.x) and tonumber(q.y) then
            local x = math.floor(tonumber(q.x) + 0.5) + FK.POS_ZERO
            local y = math.floor(tonumber(q.y) + 0.5) + FK.POS_ZERO
            if x >= 0 and y >= 0 and x < 2 * FK.POS_ZERO and y < 2 * FK.POS_ZERO then
                out[#out + 1] = ("Q=%d:%d"):format(x, y)
            end
        end
    end
    local px = tonumber(settings.markers)
    if px and px ~= 10 then out[#out + 1] = "M=" .. math.floor(px + 0.5) end
    -- THE BUFF-DROP SOUND (N for Noise), both halves in one row: the file id, and a 1 after a
    -- colon when it is switched off. Two numbers rather than two rows because switching the sound
    -- off must not throw away the id the player typed - "N=0:1" is silence with our own sound
    -- behind it, "N=567458:1" is silence with theirs. A file PATH cannot ride here (a row carries
    -- digits only), and a path makes no sound on this client anyway.
    local snd = tonumber(settings.sound)
    if settings.quiet or snd then
        out[#out + 1] = "N=" .. math.floor((snd or 0) + 0.5) .. (settings.quiet and ":1" or "")
    end
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
        elseif code == "K" then
            settings.clique = tonumber(idx) == 1
        elseif code == "L" then
            settings.layout = CODELAYOUT[tonumber(idx)]
        elseif code == "G" then
            settings.target = (tonumber(idx) or 0) > 0
            settings.targetAt = CODESPOT[tonumber(idx)]
            settings.tot = tonumber(rank) == 1
        elseif code == "Q" and tonumber(idx) and tonumber(rank) then
            settings.targetPos = { x = tonumber(idx) - FK.POS_ZERO, y = tonumber(rank) - FK.POS_ZERO }
        elseif code == "M" then
            settings.markers = tonumber(idx)
        elseif code == "N" then
            -- `quiet` is always set when the row is here, and never when it is not: that is what
            -- tells the restore "this macro has an opinion about the sound" apart from "it has
            -- none". An id of 0 means ours.
            settings.sound = (tonumber(idx) or 0) > 0 and tonumber(idx) or nil
            settings.quiet = tonumber(rank) == 1
        elseif code == "O" then
            settings.hots = tonumber(idx) ~= 0
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

--- How many macros each tab holds, from the client. GSE reads the same constants; 120 and 18 are
--- only the fallbacks for a client that does not say.
function FK.Limits()
    local c = Constants and Constants.MacroConsts
    local acc = (c and tonumber(c.MAX_ACCOUNT_MACROS)) or tonumber(MAX_ACCOUNT_MACROS) or 120
    local chr = (c and tonumber(c.MAX_CHARACTER_MACROS)) or tonumber(MAX_CHARACTER_MACROS) or 18
    return acc, chr
end

--- WHERE OURS IS: this character's own BiSHealing macro, and separately any shared one.
---
--- THE SHARED ONE WAS A BUG. Arn, 22 Sep 2026, a screenshot of the macro window: "its saving to
--- general". Every character on the account read and wrote that one macro, so whichever logged in
--- and saved last decided everyone's binds - "it's still wiping the keybinds from time to time".
--- So ours is looked for ONLY in this character's tab (the indices after General's). A shared one
--- is reported, so its binds can be carried over once, and never written to again.
function FK.Find()
    local acc, chr = FK.Limits()
    local mine, shared
    if type(GetMacroInfo) == "function" then
        for i = acc + 1, acc + chr do
            local ok, name = pcall(GetMacroInfo, i)
            if ok and name == FK.MACRO then mine = i break end
        end
        for i = 1, acc do
            local ok, name = pcall(GetMacroInfo, i)
            if ok and name == FK.MACRO then shared = i break end
        end
    else
        local ok, idx = pcall(GetMacroIndexByName, FK.MACRO)
        if ok and type(idx) == "number" and idx > 0 then
            if idx > acc then mine = idx else shared = idx end
        end
    end
    return mine, shared
end

--- HAS THE MACRO LIST ARRIVED? Nothing is written until it has. The other half of the wipe: at login
--- the list can come in late, and a save made before it did (the grid's position, from the look of
--- Arn's macro - "BiSH1#P=5960:5164", no binds at all) wrote an empty mouse over the real one. The
--- list is known to be in when ours is found, when the client counts any macro at all, or when
--- UPDATE_MACROS has fired (FK.MacrosArrived).
FK.read = false
local function listIsIn()
    if FK.read then return true end
    local ok, g, p = pcall(GetNumMacros)
    if ok and ((tonumber(g) or 0) + (tonumber(p) or 0)) > 0 then FK.read = true end
    return FK.read
end

function FK.MacrosArrived()
    FK.read = true
end

--- The binds this character kept, or nil. Its own macro first; failing that, a shared one from
--- before this was fixed, whose binds are carried over ONCE (FK.adopted says so) and then written
--- into this character's own at the next save.
function FK.Load()
    if not FK.Ready() then return nil end
    local mine, shared = FK.Find()
    local idx = mine or shared
    if mine or shared then FK.read = true else listIsIn() end
    FK.shared = shared
    if not idx then return nil end
    local got, body = pcall(GetMacroBody, idx)
    if not got or type(body) ~= "string" then return nil end
    FK.adopted = (not mine and shared) and true or nil
    return FK.Decode(body)
end

--- Write them down. Refuses in combat - the client will not make a macro there - and says why,
--- so the caller can come back when the lockdown lifts instead of losing the change.
function FK.Save(binds)
    if not FK.Ready() or type(CreateMacro) ~= "function" or type(EditMacro) ~= "function" then
        return false, "no macro api"
    end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    -- never before the list is in: a write now would put an empty mouse over the real one
    if not listIsIn() then
        FK.pending = true
        return false, "not read yet"
    end
    FK.pending = nil
    local d = NS.DB and NS.DB()
    local t = type(d) == "table" and d or {}
    -- the position only when it is pinned by the centre (FG.Recenter); any other kind of point
    -- is not two numbers, and "back in the middle" is what writing nothing means
    local gp, pos = t.gridPos, nil
    if type(gp) == "table" and gp.point == "CENTER" and (gp.rel == nil or gp.rel == "CENTER") then
        pos = { x = gp.x or 0, y = gp.y or 0 }
    end
    local body, dropped = FK.Encode(binds, { scale = t.scale, text = t.text, color = t.color,
                                             pos = pos, hidden = t.shown == false, hots = t.hots,
                                             clique = t.clique, layout = t.layout,
                                             target = t.target, markers = t.markers, tot = t.tot,
                                             targetAt = t.targetAt, targetPos = t.targetPos,
                                             sound = tonumber(t.buffSound), quiet = t.buffQuiet == true })
    if not body then return false, "nothing to write" end

    -- only ever THIS character's own: a shared one in General is left exactly as it is
    local mine = FK.Find()
    if mine then
        local done = pcall(EditMacro, mine, FK.MACRO, FK.ICON, body)
        return done and true or false, done and dropped or "the client refused the edit"
    end

    -- no room is a real answer, not a failure to hide: the character tab's slots are the
    -- player's before they are ours, and how many there are is the client's to say
    local _, chrLimit = FK.Limits()
    local gok, _, perChar = pcall(GetNumMacros)
    if gok and type(perChar) == "number" and perChar >= chrLimit then
        return false, "your character macro slots are full"
    end
    -- tried once and the client filed it under General anyway: do not make a second, and a third
    if FK.landedShared then return false, "the client keeps macros in General" end
    -- TRUE, not 1. This was `1` from the start, and this client filed the macro under General
    -- (22 Sep). The flag is a boolean on the modern API; a number is not one.
    local made, at = pcall(CreateMacro, FK.MACRO, FK.ICON, body, true)
    if not made then return false, "the client refused to make the macro" end
    -- and LOOK where it went, rather than trust the flag a second time
    local acc = FK.Limits()
    if type(at) == "number" and at <= acc then
        FK.landedShared = true
        return false, "the client put the macro in General, shared by all your characters"
    end
    return true, dropped
end

NS.FK = FK
