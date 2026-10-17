--------------------------------------------------------------------------------
-- BiSHealingAPI: for other addons (16 Oct 2026, playbook 5a - shaped like BiSToolsAPI).
--
-- What BiS Healing is best at: what a click on a healing cell casts, and the BiS> now block. So
-- another addon may ASK what the player's mouse is bound to, whether the grid and the block are
-- up, who the player's tank is - and OPEN the bind window or the options, the same as a click on
-- the minimap button. A caller never reaches into NS.FM, NS.FN, BiSHealingDB or a frame name
-- (BiSHealingNowBlock): it asks here, and here stays the same while the insides change.
--
--   * BiSHealingAPI.major = 1. A caller checks api.major == 1 before using it.
--   * BiSHealingAPI.version goes up when something is added; nothing is changed or taken away
--     without a new major.
--   * Nothing here changes BiS Healing's settings: no bind, no switch, no position. Every call is
--     safe at any time: before login (the grid is built at PLAYER_LOGIN) it answers nil,
--     "not ready". It never errors.
--   * Every answer is a COPY - editing one changes nothing in the addon.
--
-- A bind (a table, copied):
--   { key      = "shift-left",            -- modifier .. slot, as the addon stores it
--     mod      = "shift-",                -- "", "shift-", "ctrl-" or "alt-"
--     slot     = "left",                  -- one of Slots()'s keys
--     cast     = "Nature's Swiftness+Healing Wave(Rank 10)",   -- the stored bind, untouched
--     spell    = "Healing Wave",          -- the heal's name, rank left off; nil for a ping
--     rank     = "Rank 10",               -- as the client words it, or nil (no rank / a ping)
--     boost    = "Nature's Swiftness",    -- the spell cast first, or nil
--     trinkets = { 13, 14 },              -- trinket SLOTS used first (the bind's own and its
--                                         --   modifier tab's), sorted; {} for none or a ping
--     ping     = "assist" | nil }         -- a ping bind: the ping's key, and spell is nil
--
-- FUNCTIONS (all since version 1)
--   BiSHealingAPI.Ready()
--       -> true, or nil, "not ready".
--   BiSHealingAPI.Shown()
--       -> true / false: the player's show/hide switch for the grid (/bish show, /bish hide),
--          or nil, "not ready".
--   BiSHealingAPI.CliqueOn()
--       -> true when the player has handed every click on the cells to Clique (then the binds
--          below do nothing on the cells), false otherwise, or nil, "not ready".
--   BiSHealingAPI.Slots()
--       -> a list of { key = "left", label = "Left click", wheel = false } - every mouse slot
--          a bind can sit on, in the bind window's order - or nil, "not ready". The modifiers
--          are always "", "shift-", "ctrl-", "alt-".
--   BiSHealingAPI.Binds()
--       -> a table of binds keyed by their key ({ ["shift-left"] = bind, ... }; {} when nothing
--          is bound), or nil, "not ready".
--   BiSHealingAPI.Bind(slot, mod)
--       slot: one of Slots()'s keys. mod: optional, "", "shift", "ctrl", "alt" (a trailing "-"
--             is fine too); nil = no modifier.
--       -> that bind, or nil and why: "not ready", "no such slot", "no such modifier",
--          "nothing bound".
--   BiSHealingAPI.Now()
--       -> { on = true|false,       -- the player's BiS> now switch
--            shown = true|false,    -- the block is on screen right now
--            buttons = { "help", "shield", ... },   -- the keys it holds now, in its learned order
--            tank = "Name Surname" | nil }          -- see Tank()
--          or nil, "not ready".
--   BiSHealingAPI.Tank()
--       -> the name of the player's chosen tank (BiS> now's Tank button), as the client wrote it,
--          or nil, "not ready" / "no tank".
--   BiSHealingAPI.OpenBinds()
--       -> true once the bind window (the picture of the mouse) is open - opened if it was not,
--          left alone if it was; or nil, "not ready" / "failed".
--   BiSHealingAPI.OpenOptions()
--       -> true once the options window is open; or nil, "not ready" / "failed".
--   BiSHealingAPI.RegisterCallback(owner, event, fn)
--       owner: any non-nil value (your addon's name or table); event: a name below; fn(event, ...).
--       -> true, or nil, "bad owner" / "no such event" / "not a function". One fn per owner+event.
--   BiSHealingAPI.UnregisterCallback(owner, event)
--       -> true, or nil, "not registered".
--
-- EVENTS (since version 1). Each callback is pcalled: a listener's error stays its own.
--   "BiSHealing_BindsChanged"  fn(event) - the player changed a bind (dropped, cleared, stepped a
--                              rank, ticked a trinket tab). Ask Binds() for the new ones.
--   "BiSHealing_TankChanged"   fn(event, name) - the player chose a tank (name) or let go (nil).
--   "BiSHealing_Shown"         fn(event, shown) - the grid's show/hide switch was flipped.
--------------------------------------------------------------------------------
local _, NS = ...
NS = NS or {}

local API = { major = 1, version = 1 }
BiSHealingAPI = API

local EVENTS = { BiSHealing_BindsChanged = true, BiSHealing_TankChanged = true, BiSHealing_Shown = true }
local owners = {}    -- event -> { [owner] = fn }

local MODS = { [""] = "", shift = "shift-", ctrl = "ctrl-", alt = "alt-",
               ["shift-"] = "shift-", ["ctrl-"] = "ctrl-", ["alt-"] = "alt-" }

-- the grid is built at PLAYER_LOGIN (Core's boot -> FG.Start), after the saved table is in
local function ready()
    local FG = NS.FG
    if not (FG and FG.anchor and type(_G.BiSHealingDB) == "table" and NS.DB) then return nil, "not ready" end
    local ok, d = pcall(NS.DB)
    if not ok or type(d) ~= "table" then return nil, "not ready" end
    return d
end

-- a plain string we may hand on, or nil
local function plain(v)
    if type(v) ~= "string" or v == "" then return nil end
    if NS.Secret and NS.Secret(v) then return nil end
    return v
end

-- one call into the addon's insides, which may change: nil when it is missing or throws
local function try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local res = { pcall(fn, ...) }
    if not res[1] then return nil end
    return unpack(res, 2, table.maxn(res))
end

local function slotOf(key)
    for _, s in ipairs((NS.FM and NS.FM.SLOTS) or {}) do
        if s.key == key then return s end
    end
    return nil
end

-- one stored bind, taken apart into fresh plain values
local function entry(key, cast)
    if type(key) ~= "string" or type(cast) ~= "string" then return nil end
    local FM = NS.FM or {}
    local mod, slot = key:match("^(%a+%-)(.+)$")
    if not (mod and MODS[mod]) then mod, slot = "", key end
    local e = { key = key, mod = mod, slot = slot, cast = cast, trinkets = {} }
    local ping = try(FM.PingOf, cast)
    if ping then
        e.ping = ping
        return e
    end
    local spell, rank = try(FM.Split, cast)
    e.spell = plain(spell) or cast
    e.rank = plain(rank)
    local slots, boost = try(FM.Front, cast)
    e.boost = plain(boost)
    local seen = {}
    for _, s in ipairs(type(slots) == "table" and slots or {}) do seen[s] = true end
    local tab = try(FM.TabTrinkets, mod)
    for _, s in ipairs(type(tab) == "table" and tab or {}) do seen[s] = true end
    for _, s in ipairs(FM.TRINKET_SLOTS or { 13, 14 }) do
        if seen[s] then e.trinkets[#e.trinkets + 1] = s end
    end
    return e
end

function API.Ready()
    local d, why = ready()
    if not d then return nil, why end
    return true
end

function API.Shown()
    local d, why = ready()
    if not d then return nil, why end
    return d.shown ~= false
end

function API.CliqueOn()
    local d, why = ready()
    if not d then return nil, why end
    return d.clique == true
end

function API.Slots()
    local d, why = ready()
    if not d then return nil, why end
    local out = {}
    for _, s in ipairs((NS.FM and NS.FM.SLOTS) or {}) do
        out[#out + 1] = { key = s.key, label = s.label, wheel = s.bind ~= nil }
    end
    return out
end

function API.Binds()
    local d, why = ready()
    if not d then return nil, why end
    local out = {}
    for key, cast in pairs(type(d.binds) == "table" and d.binds or {}) do
        local e = entry(key, cast)
        if e then out[key] = e end
    end
    return out
end

function API.Bind(slot, mod)
    local d, why = ready()
    if not d then return nil, why end
    if type(slot) ~= "string" or not slotOf(slot) then return nil, "no such slot" end
    local m = MODS[mod == nil and "" or mod]
    if not m then return nil, "no such modifier" end
    local key = m .. slot
    local cast = type(d.binds) == "table" and d.binds[key] or nil
    local e = entry(key, cast)
    if not e then return nil, "nothing bound" end
    return e
end

local function tank(d)
    local FN = NS.FN
    local t = FN and try(FN.Tank)
    if t == nil and type(d.tank) == "string" then t = d.tank end
    return plain(t)
end

function API.Now()
    local d, why = ready()
    if not d then return nil, why end
    local FN = NS.FN or {}
    local block = FN.block
    local shown = false
    if block and block.IsShown then shown = try(block.IsShown, block) and true or false end
    local buttons = {}
    if shown then
        local mine = try(FN.Mine)
        for _, k in ipairs(type(mine) == "table" and mine or {}) do
            if type(k) == "string" then buttons[#buttons + 1] = k end
        end
    end
    return { on = d.now == true, shown = shown, buttons = buttons, tank = tank(d) }
end

function API.Tank()
    local d, why = ready()
    if not d then return nil, why end
    local t = tank(d)
    if not t then return nil, "no tank" end
    return t
end

function API.OpenBinds()
    local d, why = ready()
    if not d then return nil, why end
    local FM = NS.FM or {}
    local w = try(FM.Window)
    if not (w and w.IsShown) then return nil, "failed" end
    if not try(w.IsShown, w) then
        if NS.DO and NS.DO.mouse then try(NS.DO.mouse) else try(FM.Toggle) end
    end
    if not try(w.IsShown, w) then return nil, "failed" end
    return true
end

function API.OpenOptions()
    local d, why = ready()
    if not d then return nil, why end
    local CFG = NS.CFG or {}
    local f = try(CFG.Build)
    if not (f and f.IsShown) then return nil, "failed" end
    if not try(f.IsShown, f) then try(CFG.Open) end
    if not try(f.IsShown, f) then return nil, "failed" end
    return true
end

function API.RegisterCallback(owner, event, fn)
    if owner == nil then return nil, "bad owner" end
    if not EVENTS[event] then return nil, "no such event" end
    if type(fn) ~= "function" then return nil, "not a function" end
    owners[event] = owners[event] or {}
    owners[event][owner] = fn
    return true
end

function API.UnregisterCallback(owner, event)
    local list = event and owners[event]
    if owner == nil or not (list and list[owner]) then return nil, "not registered" end
    list[owner] = nil
    return true
end

-- Mouse.lua, Now.lua and Core.lua call this when something worth announcing happened. Only plain
-- values are handed on, so a listener cannot reach the addon's tables through them.
function NS.Announce(event, ...)
    local list = owners[event]
    if not list then return end
    for _, fn in pairs(list) do
        pcall(fn, event, ...)
    end
end
