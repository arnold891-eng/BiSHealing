--[[
  BiSHealing / Forever :: Forever/Auras.lua - showing what we are not allowed to read.

  THE CORRECTION. On 17 Sep this family concluded that dispel highlighting was impossible during a
  fight, because `C_UnitAuras.GetAuraDataByIndex` errors inside the lockdown and
  `AuraUtil.FindAuraByName` quietly returns nil. That measurement was right and the conclusion was
  wrong: we asked whether an addon can READ an aura, not whether it can SHOW one.

  Blizzard's answer to the lockdown is a widget that draws what you may not know - the same bargain
  as `StatusBar:SetValue(UnitHealth(unit))` for health:

      local c = CreateFrame("AuraContainer", nil, cell, "CustomAuraContainerTemplate")
      c:SetUnit(unit)
      c:AddAuraSlot(key, "HARMFUL|RAID_PLAYER_DISPELLABLE", {
          candidateFilters = { includeDispelTypes = { Poison = true, Disease = true } },
          initializeFrame  = style,
      })

  **The client knows what YOU can dispel** - that is what RAID_PLAYER_DISPELLABLE means - so no
  spell ids are needed and no aura is ever read. We declare the dispel types we care about and how
  the marker looks; the client decides whether anything is there and draws it.

  Confirmed present on 1.60.1.69913 by BiSProbe (`display`): the AuraContainer widget with SetUnit /
  AddAuraGroup / SetEnabled, CustomAuraContainerTemplate, and C_Spell.GetSpellCooldownDuration
  handing back an opaque LuaDurationObject for Cooldown:SetCooldownFromDurationObject.

  Everything here is feature-detected, never version-checked: Forever carries a modern API behind a
  1.60 interface number, so asking "does this client have the widget" is the only honest question.
]]
local ADDON, NS = ...
NS = NS or {}

local FA = {}
NS.FA = FA

-- NOTHING. The filter below already says RAID_PLAYER_DISPELLABLE, which means the CLIENT decides
-- what this character can take off someone - a priest's Magic and Disease, a druid's Curse and
-- Poison, a paladin's three. This used to narrow it further to { Poison, Disease }, which is the
-- list for exactly one class, and on 19 Sep 2026 the addon stopped being for exactly one class.
--
-- Leaving the narrowing out is not laziness: a hard-coded list is a promise about somebody else's
-- spellbook, and the client's own answer is better than ours in every case including the ones
-- nobody here has levelled.

-- BUFFS WORTH A PIP IN THE CORNER, by spell id. Empty on purpose (19 Sep): Earth Shield is a TBC
-- talent and nobody yet knows whether - or at what level - it exists on a 1.60 client. The probe
-- says spell 974 resolves by name there, which is not the same as a shaman being able to cast it.
--
-- Put an id in here and the pip appears; leave it empty and no slot is made at all. That is the
-- difference between a guess in shipped code and a switch waiting for an answer.
--
--   FA.WATCH = { [974] = "Earth Shield" }
FA.WATCH = {}

local DISPEL_TINT = { 0.10, 0.90, 0.35, 0.95 }   -- a green pip: something here you can cure
local ES_TINT     = { 0.95, 0.80, 0.25, 0.90 }

--- Does this client ship the containers, AND will it let us build one? Feature detection, not an
--- interface number: Forever uses 16001 and carries the modern API anyway. Note that "the template
--- exists" and "we may create it" are different questions - the second one only answers itself
--- when we try, and a refusal is remembered in FA.available so we ask exactly once.
function FA.Available()
    if FA.available ~= nil then return FA.available end
    local ok = C_XMLUtil and C_XMLUtil.GetTemplateInfo
        and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") ~= nil
    FA.available = ok and true or false
    return FA.available
end

--- One slot on a container, whichever method this build ships. AddAuraSlot is a single marker
--- (what a dispel highlight wants); AddAuraGroup is the many-buttons form. Older or newer builds
--- may have only one of them, so try both rather than assume.
local function addSlot(container, key, filter, opts)
    if container.AddAuraSlot then
        local ok, slot = pcall(container.AddAuraSlot, container, key, filter, opts)
        if ok and slot then return slot end
    end
    if container.AddAuraGroup then
        opts.maxFrameCount = opts.maxFrameCount or 1
        local ok, slot = pcall(container.AddAuraGroup, container, key, filter, opts)
        if ok and slot then return slot end
    end
    return nil
end

--- A small coloured pip, and NOTHING of the client's own button.
---
--- The first version stretched the marker across the whole health bar, and on the beta that showed
--- as a WHITE BLOCK over the cell: an aura button brings its own icon and border art, and
--- stretched over the bar it simply hid it. A marker should be small enough that being wrong about
--- what the client draws costs a corner rather than the bar.
local function pip(colour)
    return function(auraButton)
        if not auraButton then return end
        -- the button's own art, gone: we want a colour, not Blizzard's icon frame
        if auraButton.GetRegions then
            for _, r in ipairs({ auraButton:GetRegions() }) do
                if r.SetTexture and r.Hide then pcall(r.Hide, r) end
            end
        end
        for _, k in ipairs({ "Icon", "icon", "Border", "border", "Count", "count", "Cooldown" }) do
            local part = auraButton[k]
            if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
        end
        local t = auraButton:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetAllPoints(auraButton)
        t:SetVertexColor(colour[1], colour[2], colour[3], colour[4])
        if auraButton.SetMouseMotionEnabled then auraButton:SetMouseMotionEnabled(false) end
        return t
    end
end

--- THE DISPEL TYPE, drawn by the client. ForeverAuras 0.1.148 (21 Sep) hands an aura button a
--- texture with AddDispelTypeTexture and the client paints the TYPE into it - Magic, Curse, Poison,
--- Disease, in the game's own icon and colour - for an aura we are never allowed to read. So the
--- marker says what it is, not only that it is there.
---
--- The green square is made first and stays the fallback: a client without the call, or one that
--- refuses it, still gets "something here you can cure". Only when the client took the texture is
--- the square hidden.
local function dispelPip(colour)
    local square = pip(colour)
    return function(auraButton)
        local t = square(auraButton)
        if not (auraButton and type(auraButton.AddDispelTypeTexture) == "function") then return end
        local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
        local icon = auraButton:CreateTexture(nil, "OVERLAY", nil, 1)
        icon:SetAllPoints(auraButton)
        local ok = pcall(auraButton.AddDispelTypeTexture, auraButton, icon, {
            showWhenHarmful = true, showWhenHelpful = false,
            style = styles and styles.Icon or nil,
        })
        if ok then
            if t and t.Hide then t:Hide() end
            FA.typed = true                      -- /bish scan can say which marker is in use
        elseif icon.Hide then
            icon:Hide()
        end
    end
end

-- YOUR HEALS OVER TIME, on the cell, with the client's own countdown. By family: every rank of a
-- spell is its own spell id, and a slot shows whichever rank of the family is on the target. The
-- ids are Classic's - and the book is read too (FA.HotIds), because this client's ids for the
-- higher ranks are not something anyone here has measured, while the ones YOU know are in your
-- spellbook. Only spells you cast ("HELPFUL|PLAYER"): another healer's Renew is not your timer.
FA.HOTS = {
    PRIEST = {
        { key = "Renew", ids = { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 } },
    },
    DRUID = {
        { key = "Rejuvenation", ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 } },
        { key = "Regrowth", ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 } },
    },
}
local HOT_GAP = 2

--- HOW BIG THE MARKERS ARE. A player's request (paszczyszyn, 22 Sep): "Is there a possibility of
--- an option to adjust the size of buffs and debuffs?". One number for all of them (the dispel
--- marker, the heal-over-time icons, the watched-buff pip), because three sliders for three dots
--- is three questions where the player had one. 10 is what they have always been.
function FA.MarkerSize()
    local d = NS.DB and NS.DB()
    local n = type(d) == "table" and tonumber(d.markers) or nil
    if not n then return 10 end
    if n < 6 then return 6 elseif n > 20 then return 20 end
    return math.floor(n + 0.5)
end

--- Every spell id for one family: the listed ones, plus every rank of that name in the book.
function FA.HotIds(family)
    local ids = {}
    for _, id in ipairs(family.ids) do ids[id] = true end
    local name = C_Spell and C_Spell.GetSpellName and family.ids[1]
        and select(2, pcall(C_Spell.GetSpellName, family.ids[1])) or nil
    if type(name) ~= "string" or name == "" or NS.Secret(name) then return ids end
    local bank = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if C_SpellBook and C_SpellBook.GetSpellBookItemName and C_SpellBook.GetSpellBookItemInfo then
        for i = 1, 500 do
            local got, nm = pcall(C_SpellBook.GetSpellBookItemName, i, bank)
            if got and nm == name then
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                local id = ok and type(info) == "table" and NS.Plain(info.spellID) or nil
                if type(id) == "number" then ids[id] = true end
            end
        end
    end
    return ids
end

--- The families this character casts, or nothing: a paladin has no heal over time here.
function FA.Hots()
    local d = NS.DB and NS.DB()
    if type(d) == "table" and d.hots == false then return {} end
    local class = UnitClass and NS.Plain(select(2, UnitClass("player"))) or nil
    return FA.HOTS[class or ""] or {}
end

--- A heal-over-time marker: the spell's own icon (the client sets it), its border gone, and a
--- Cooldown the client runs from the aura's duration - SetDurationCooldown, as ForeverAuras does.
--- The swipe IS the time left, and we never read it.
local function hotIcon(auraButton)
    if not auraButton then return end
    for _, k in ipairs({ "Border", "border", "Count", "count" }) do
        local part = auraButton[k]
        if type(part) == "table" and part.Hide then pcall(part.Hide, part) end
    end
    if auraButton.SetMouseMotionEnabled then auraButton:SetMouseMotionEnabled(false) end
    if auraButton.EnableMouse then pcall(auraButton.EnableMouse, auraButton, false) end
    if type(auraButton.SetDurationCooldown) == "function" then
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, auraButton, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints(auraButton)
            if cd.SetDrawBling then cd:SetDrawBling(false) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
            if cd.SetReverse then cd:SetReverse(true) end    -- fills in as it runs out
            pcall(auraButton.SetDurationCooldown, auraButton, cd)
        end
    end
end

--- A fingerprint of what the containers were built for: the debug switch and every heal-over-time
--- id. When it changes - the book filled in after login, a new rank learned, /bish hots - each
--- cell's container is rebuilt; otherwise the one it has is only pointed at its unit.
local function signature()
    -- read the book once per pass, not once per cell: a layout attaches forty cells in one frame
    local now = GetTime and GetTime() or 0
    if FA.sig and FA.sigAt == now then return FA.sig end
    local parts = { FA.debug and "d" or "", "px" .. FA.MarkerSize() }
    for _, fam in ipairs(FA.Hots()) do
        local ids = {}
        for id in pairs(FA.HotIds(fam)) do ids[#ids + 1] = id end
        table.sort(ids)
        parts[#parts + 1] = fam.key .. ":" .. table.concat(ids, ",")
    end
    FA.sig, FA.sigAt = table.concat(parts, "|"), now
    return FA.sig
end

--- Take a cell's container down before a new one is built: the old one would otherwise go on
--- drawing underneath it.
local function release(cell)
    local old = cell.auras
    if not old then return end
    if old.SetEnabled then pcall(old.SetEnabled, old, false) end
    if old.Hide then pcall(old.Hide, old) end
    cell.auras, cell.dispelSlot, cell.watchSlot, cell.anySlot, cell.hotSlots = nil, nil, nil, nil, nil
end

--- Give one grid cell its markers. Returns false when this client has no containers, which is the
--- TBC case and any future client that drops them - the grid then simply has no dispel marker,
--- rather than erroring every frame.
function FA.Attach(cell, unit)
    if not FA.Available() or not cell or not unit then return false end
    local sig = signature()
    if cell.auras and cell.aurasSig == sig then
        if cell.auras.SetUnit then pcall(cell.auras.SetUnit, cell.auras, unit) end
        return true
    end
    release(cell)

    -- Blizzard's own AuraContainer addon owns this template. Without it the template is still
    -- KNOWN to C_XMLUtil - so feature detection says yes - and building one is refused as a
    -- protected action: "BiSHealing has been blocked from an action only available to the Blizzard
    -- UI", at every layout, forever. Hence `## OptionalDeps: Blizzard_AuraContainer` in the TOC.
    --
    -- And hence this: ONE attempt. A refusal is remembered, not retried, because the dialog is not
    -- a Lua error and pcall cannot see it - the only thing that stops a popup every pull is us
    -- deciding never to ask twice.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, cell, "CustomAuraContainerTemplate")
    if not ok or not container then
        FA.available = false
        FA.refused = "the client refused to build an AuraContainer (protected action?)"
        return false
    end
    container:SetSize(1, 1)
    container:SetPoint("CENTER", cell)
    -- above the bar, when this client will say what level the cell is on. A widget stub that
    -- answers nothing must not take the grid down over a cosmetic detail.
    if container.SetFrameLevel and cell.GetFrameLevel then
        local lvl = cell:GetFrameLevel()
        if type(lvl) == "number" then container:SetFrameLevel(lvl + 10) end
    end
    container:SetUnit(unit)

    -- 1. anything WE can cure, washed over the health bar
    local dispel = addSlot(container, "BiSHealDispel", "HARMFUL|RAID_PLAYER_DISPELLABLE", {
        initializeFrame = dispelPip(DISPEL_TINT),
    })
    if dispel and dispel.SetPoint then
        local px = FA.MarkerSize()
        dispel:SetSize(px, px)
        dispel:SetPoint("LEFT", cell, "LEFT", 2, 0)      -- a pip at the edge, never over the bar
    end

    -- 2. a pip for any buff we are watching. Nothing is watched by default, so no slot is built
    --    and the cell stays as clean as the grid was before.
    local watch, any = {}, false
    for id in pairs(FA.WATCH) do
        watch[id] = true
        any = true
    end
    local es
    if any then
        es = addSlot(container, "BiSHealWatch", "HELPFUL", {
            candidateFilters = { includeSpellIDs = watch },
            initializeFrame = pip(ES_TINT),
        })
        if es and es.SetPoint then
            local px = math.max(6, FA.MarkerSize() - 2)
            es:SetSize(px, px)
            es:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -2)
        end
    end

    -- the debug marker, when someone is asking "does this draw at all?"
    if FA.debug then
        local any = addSlot(container, "BiSHealAnyDebuff", "HARMFUL", {
            initializeFrame = pip({ 1.00, 0.45, 0.10, 0.95 }),
        })
        if any and any.SetPoint then
            local px = FA.MarkerSize()
            any:SetSize(px, px)
            any:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 2, 2)
        end
        cell.anySlot = any
    end

    -- 3. YOUR heals over time, bottom left in a row, each with the client's countdown swipe. The
    --    number owns the bottom right, the name the top line; these sit under the name's start.
    local hots = {}
    for i, fam in ipairs(FA.Hots()) do
        local slot = addSlot(container, "BiSHealHot" .. fam.key, "HELPFUL|PLAYER", {
            candidateFilters = { includeSpellIDs = FA.HotIds(fam) },
            initializeFrame = hotIcon,
        })
        if slot and slot.SetPoint then
            local px = FA.MarkerSize()
            slot:SetSize(px, px)
            slot:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 3 + (i - 1) * (px + HOT_GAP), 3)
        end
        hots[fam.key] = slot
    end

    if container.SetEnabled then container:SetEnabled(true) end
    cell.auras, cell.dispelSlot, cell.watchSlot, cell.hotSlots = container, dispel, es, hots
    cell.aurasSig = sig
    return true
end

--- A DEBUG MARKER: any harmful aura at all, dispellable or not.
---
--- The real marker asks for "HARMFUL|RAID_PLAYER_DISPELLABLE", which means the CLIENT decides
--- what this character can cure. A shaman who has not learned Cure Poison yet can cure nothing,
--- so nothing draws - and from the outside that looks exactly like a container that never worked.
--- This tells the two apart: turn it on, take any debuff, and if the cell washes orange the
--- containers are drawing and the dispel filter is simply doing its job.
---
--- Off by default and never shipped on: it marks every debuff, which in a raid is noise.
function FA.Debug(on, frames)
    FA.debug = on and true or false
    FA.sig = nil                            -- the fingerprint changed: every container is rebuilt
    for _, f in ipairs(frames or (NS.FG and NS.FG.frames) or {}) do
        if f.unit then FA.Attach(f, f.unit) end
    end
    return FA.debug
end

--- Your heals over time on the cells, on or off. Out of combat only, like every container change.
function FA.SetHots(on)
    local d = NS.DB and NS.DB()
    if type(d) == "table" then d.hots = on and true or false end
    FA.sig = nil
    if InCombatLockdown and InCombatLockdown() then return false end
    for _, f in ipairs((NS.FG and NS.FG.frames) or {}) do
        if f.unit then FA.Attach(f, f.unit) end
    end
    return true
end

--- Point every cell's container at whatever unit that cell now holds. Called from the layout, out
--- of combat, exactly like the secure attributes.
function FA.Rebind(frames)
    local n = 0
    for _, f in ipairs(frames or {}) do
        if f.unit and FA.Attach(f, f.unit) then n = n + 1 end
    end
    return n
end
