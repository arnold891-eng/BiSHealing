-- BiSHealing -- the theme runs BOTH ways
--
--     cd BiSHealing && lua5.1 dev/theme.lua
--
-- Runs dev/tests.lua twice:
--
--   1. with no BiSTheme at all           -> the inline fallback palette carries
--                                           the options window
--   2. with a DELIBERATELY WRONG BiSTheme -> the shared addon wins, per colour
--                                           name, and reaches real pixels
--
-- The second run is the point. A synthetic BiSTheme is written with an accent
-- no BiS palette would ever contain (#ff0000), and it is loaded AFTER the addon
-- file has run -- the order the client actually uses, since BiSHealing sorts
-- before BiSTheme alphabetically. If the addon captured `BiSTheme or {inline}`
-- at file load, it captured nil, the window stays violet, and this run fails.
-- That is exactly how the bug lived here undetected: the two palettes match, so
-- only a wrong-on-purpose one can tell them apart.

local addon = arg[1] or "BiSHealing.lua"
-- Windows has no /tmp and Git Bash sets TMP/TEMP, not TMPDIR; "." is the last resort so the
-- harness never fails for want of a scratch file (the file is written, loaded and removed).
local synth = os.getenv("TMPDIR") or os.getenv("TMP") or os.getenv("TEMP") or "/tmp"
if not io.open(synth, "r") and not os.rename(synth, synth) then synth = "." end
synth = synth .. "/bish-theme-probe.lua"

local f = assert(io.open(synth, "w"))
f:write([[
-- synthetic BiSTheme: same shape, deliberately wrong colours
BiSTheme = BiSTheme or {}
local T = BiSTheme
T.hex = {
  ink = "ff0001", ink2 = "ff0002", muted = "ff0003", dim = "ff0004",
  accent = "ff0000", good = "ff0005", warn = "ff0006", gold = "ff0007",
}
local function hexToRGB(h)
  return tonumber(h:sub(1,2),16)/255, tonumber(h:sub(3,4),16)/255, tonumber(h:sub(5,6),16)/255
end
function T.rgb(name) return hexToRGB(T.hex[name] or T.hex.ink) end
function T.rgba(name, a) local r,g,b = T.rgb(name); return r, g, b, a or 1 end
function T.text(name, s) return "|cff" .. (T.hex[name] or T.hex.ink) .. tostring(s) .. "|r" end
]])
f:close()

local function run(label, env)
    local cmd = ("%s QUIET=1 lua5.1 dev/tests.lua %q"):format(env, addon)
    local pipe = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = pipe:read("*a")
    local ok = pipe:close()
    local themeLine = out:match("== theme ok[^\n]*")
    local failure = out:match("!![^\n]*")
    if not ok or failure then
        print(("!! %s: %s"):format(label, failure or "suite did not finish"))
        print(out:sub(-800))
        os.exit(1)
    end
    print(("== %s -- %s"):format(label, themeLine or "suite green"))
end

run("without BiSTheme", "BISTHEME=")
run("with BiSTheme (wrong on purpose)", ("BISTHEME=%q"):format(synth))

os.remove(synth)
print("== theme ok both ways")
