-- =========================================================================
-- BiS Healing -- UI/options.lua : the window, which is the menu
--
-- The old window had twenty-nine rows because the old addon had twenty-nine
-- opinions: bar colours, corner markers, pulse thresholds, chain-heal bounce
-- lines, an Earth Shield section, a wheel with its own keybinds. Arn, 19 Sep
-- 2026, looking at it on a client where none of that runs: "alot of the stuff
-- in the right click was legacy stuff that does not work."
--
-- This addon mostly asks the CLIENT to draw things, so there is very little to
-- have an opinion about. What is left is four switches and four buttons, and
-- every one of them goes through NS.DO -- the same table the slash command and
-- the minimap menu use, so the three doors cannot drift apart.
--
-- The window itself is BiSTheme's shared kit (Libs\BiSTheme\Options.lua), the
-- 230 px one every BiS addon wears.
-- =========================================================================

local ADDON, NS = ...
ADDON = ADDON or "BiSHealing"
NS = NS or {}

local CFG = {}
NS.CFG = CFG

--- The rows. A function, not a table: `get` is asked every time the window
--- paints, so a switch shows what is true now rather than what was true at
--- login.
function CFG.Sections()
    local DO = NS.DO or {}
    return {
        { title = "frames", options = {
            { key = "shown", kind = "toggle", label = "show the cells",
              get = function(db) return db.shown ~= false end,
              set = function(_, on) if DO.show then DO.show(on) end end },
            { key = "minimap", kind = "toggle", label = "minimap button",
              get = function() return not (NS.MM and NS.MM.Hidden()) end,
              set = function(_, on) if NS.MM then NS.MM.SetHidden(not on) end end },
            { key = "center", kind = "button", label = "centre on screen", button = "centre",
              action = function() if DO.center then DO.center() end end },
            { key = "rescan", kind = "button", label = "look at the group again", button = "rescan",
              action = function() if DO.rescan then DO.rescan() end end },
        } },
        { title = "clicks", options = {
            { key = "mouse", kind = "button", label = "drag spells onto a mouse", button = "binds",
              action = function() if DO.mouse then DO.mouse() end end },
        } },
        { title = "this client", options = {
            { key = "scan", kind = "button", label = "what can I see?", button = "ask",
              action = function() if DO.scan then DO.scan() end end },
            -- a switch, not a command you have to type twice to turn off
            { key = "pipTest", kind = "toggle", label = "test the debuff marker",
              get = function() return (NS.FA and NS.FA.debug) and true or false end,
              set = function(_, on)
                  if NS.FA and NS.FA.Debug and ((NS.FA.debug and true or false) ~= on) then
                      NS.FA.Debug(on)
                  end
              end },
        } },
    }
end

--------------------------------------------------------------- the window --

function CFG.Build()
    if CFG.built then return CFG.frame end
    if not (BiSTheme and BiSTheme.Options) then
        -- Options.lua ships embedded under Libs\, so this only happens when the
        -- TOC line is lost. Say it once rather than throwing on every /bish.
        NS.Print("Libs\\BiSTheme\\Options.lua did not load -- reinstall the addon")
        return nil
    end
    CFG.built = true
    local f = BiSTheme.Options("BiSHealingOptions", BiSTheme.OPTIONS.W, "Heal")
    CFG.frame = f
    f:Recenter(60)
    for _, section in ipairs(CFG.Sections()) do
        f:Section(section.title)
        for _, opt in ipairs(section.options) do
            f:Row(opt, NS.DB())
        end
    end
    f:Fit()
    return f
end

function CFG.Open()
    local f = CFG.Build()
    if f then f:Toggle(true) f:Paint() end
end

function CFG.Toggle()
    local f = CFG.Build()
    if f then
        f:Toggle()
        if f:IsShown() then f:Paint() end
    end
end

-- What a headless suite reads back. A window cannot be looked at, so the rows
-- and what each one says right now are the only honest things to assert on.
NS.UI = {
    Toggle = CFG.Toggle,
    Open   = CFG.Open,
    Rows   = function()
        local out = {}
        for _, sec in ipairs(CFG.Sections()) do
            for _, opt in ipairs(sec.options) do out[#out + 1] = opt end
        end
        return out
    end,
    Get    = function(key)
        for _, opt in ipairs(NS.UI.Rows()) do
            if opt.key == key and opt.get then return opt.get(NS.DB()) end
        end
        return nil
    end,
}
