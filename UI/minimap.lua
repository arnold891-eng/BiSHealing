-- =========================================================================
-- BiS Healing -- UI/minimap.lua : the button on the minimap, and what is behind it
--
-- Arn, 19 Sep 2026: "lets make a minimap button with the options too many /
-- commands". There are twenty-five of them under /bish and three under /bishf,
-- and a command you have to remember is a feature only its author uses.
--
-- Since 21 Sep 2026 the button has no menu of its own: any click opens the
-- options window, which already held every row the menu did (see MM.Click).
--
-- The button is BiSTheme's (Libs\BiSTheme\Minimap.lua, shared with the rest of
-- the family). This file is only where it sits and what a click does.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

-- Captured at load, which is safe only because the TOC runs BiSHealing.lua and
-- UI\options.lua before this file. See the same note at the top of options.lua.
local DB = NS.DB

local MM = {}
NS.MM = MM

-- Every row is one entry in NS.DO, the table Core.lua keeps of everything this addon can be
-- asked to do. The slash command reads the same table, and so does the options window: three
-- doors, one implementation, and none of them can drift from the others.
local function act(name)
    return function()
        local fn = NS.DO and NS.DO[name]
        if fn then fn() end
    end
end


--- The db bucket for the button itself: the angle it was dragged to, and whether it is hidden.
--- Its own corner, so clearing anything else cannot lose where the button sits.
function MM.DB()
    local db = (NS.DB and NS.DB()) or {}
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    return db.minimap
end

--- ONE CLICK, ONE PLACE. Arn, 21 Sep 2026, asking what left and right click were for: "seems too
--- similar might confuse new players", then "choose one or the other and merge always keep the
--- bind on top". Left opened a menu, right opened the options window, and every row of the menu
--- was already a row of the window. So the menu is gone: any click opens the window, and the mouse
--- binds are its first row.
---
--- Done HERE, not in the shared button (Libs\BiSTheme\Minimap.lua): that file is copied into every
--- BiS addon, and this is one addon's choice. The button is built by the lib as usual and then
--- given this addon's click and tooltip.
function MM.Click(_, click)
    local b = MM.button
    if b and b.CloseMenu then b:CloseMenu() end
    if b and b.dragging then return end
    act("options")()
end

local function tooltip(s)
    if s.edge then s.edge:set("accent", 1) end
    if not GameTooltip then return end
    GameTooltip:SetOwner(s, "ANCHOR_LEFT")
    GameTooltip:AddLine("BiS> Healing")
    GameTooltip:AddLine("click  mouse binds and options", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("drag  move me round the edge", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

--- Build it, once. Returns the button, or nil on a client with no minimap frame (the headless
--- case) or with the shared lib missing from the TOC.
function MM.Build()
    if MM.button then return MM.button end
    if not (BiSTheme and BiSTheme.Minimap) then return nil end
    MM.button = BiSTheme.Minimap("BiSHealing", {
        icon    = "Interface\\Icons\\Spell_Nature_HealingWaveGreater",
        label   = "Healing",
        db      = MM.DB(),
        menu    = function() return {} end,
    })
    if MM.button and MM.button.SetScript then
        MM.button:SetScript("OnClick", MM.Click)
        MM.button:SetScript("OnEnter", tooltip)
    end
    return MM.button
end

--- Put the button back where the db says, and show or hide it to match. Called from the options
--- toggle, so the switch and the button cannot disagree.
function MM.Refresh()
    local b = MM.Build()
    if b then return b:Refresh() end
    return false
end

function MM.SetHidden(hide)
    MM.DB().hide = hide and true or false
    local b = MM.Build()
    if b then b:SetHidden(hide) end
    return not hide
end

function MM.Hidden()
    return MM.DB().hide and true or false
end

-- Built at PLAYER_LOGIN rather than at load: the saved variables are not there yet while the
-- files are running, and the angle this button sits at is one of them.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    MM.Build()
end)
MM.frame = ev
