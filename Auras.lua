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
    end
end

--- Give one grid cell its markers. Returns false when this client has no containers, which is the
--- TBC case and any future client that drops them - the grid then simply has no dispel marker,
--- rather than erroring every frame.
function FA.Attach(cell, unit)
    if not FA.Available() or not cell or not unit then return false end
    if cell.auras then
        if cell.auras.SetUnit then pcall(cell.auras.SetUnit, cell.auras, unit) end
        return true
    end

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
        initializeFrame = pip(DISPEL_TINT),
    })
    if dispel and dispel.SetPoint then
        dispel:SetSize(10, 10)
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
            es:SetSize(8, 8)
            es:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -2, -2)
        end
    end

    -- the debug marker, when someone is asking "does this draw at all?"
    if FA.debug then
        local any = addSlot(container, "BiSHealAnyDebuff", "HARMFUL", {
            initializeFrame = pip({ 1.00, 0.45, 0.10, 0.95 }),
        })
        if any and any.SetPoint then
            any:SetSize(10, 10)
            any:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 2, 2)
        end
        cell.anySlot = any
    end

    if container.SetEnabled then container:SetEnabled(true) end
    cell.auras, cell.dispelSlot, cell.watchSlot = container, dispel, es
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
    for _, f in ipairs(frames or (NS.FG and NS.FG.frames) or {}) do
        f.auras = nil                       -- rebuilt with (or without) the extra slot
        if f.unit then FA.Attach(f, f.unit) end
    end
    return FA.debug
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
