-- BiSHealing -- the loader both harnesses share.
--
-- The addon is not one file any more, and load ORDER is behaviour: the client
-- runs the TOC's lines top to bottom, so the harnesses read the same TOC and do
-- the same. Hardcoding a file list in a harness is how a newly split-out file
-- gets added to the addon, never added to the tests, and ships untested.
--
-- This lives in its own file because BOTH dev/tests.lua and dev/stress.lua need
-- it, and two copies of a loader drift the first time a file is added to one.
--
-- Two things the client does that a naive dofile does not:
--
--   * every file is handed (addonName, addonTable) as `...`. Once the addon is
--     more than one chunk, `local` stops crossing files -- two files that both
--     say `local frames = {}` get two different empty tables and neither ever
--     sees the other's -- so that shared table is the only thing they share.
--
--   * Libs\ load first. LibStub, CallbackHandler and LibHealComm are MOCKED by
--     the harness that dofiles this; loading the real 150 KB LibHealComm would
--     test the library, not the addon. They are skipped by name.
--     Libs\BiSTheme\Console.lua is loaded for real, because the header prompt
--     is ours and has to be tested.
--
-- Note what that Console line means for the palette: with the BiSTheme addon
-- absent, Console.lua installs its OWN fallback into _G.BiSTheme -- which is
-- exactly what happens in game -- so anything testing "no theme installed" must
-- gate on the BISTHEME env var, not on whether _G.BiSTheme merely exists.

local SKIP_LIBS = {
    ["LibStub"] = true, ["CallbackHandler-1.0"] = true, ["LibHealComm-4.0"] = true,
}

local function die(msg)
    print("!! LOAD: " .. msg)
    os.exit(1)
end

--- Read the TOC beside the addon and return its lua lines, in order, as
--- forward-slash relative paths, with the mocked libraries dropped.
local function tocFiles(addonDir)
    local fh = io.open(addonDir .. "BiSHealing.toc", "r")
    if not fh then die("no BiSHealing.toc beside the addon (" .. addonDir .. ")") end
    local out = {}
    for line in fh:lines() do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and line:lower():match("%.lua$") then
            local rel = line:gsub("\\", "/")
            local libDir = rel:match("^Libs/([^/]+)/")
            if not (libDir and SKIP_LIBS[libDir]) then out[#out + 1] = rel end
        end
    end
    fh:close()
    return out
end

--- Load the addon the way the client does. Returns a table describing the run:
---   ns       the shared addon table every file was handed
---   files    the TOC-relative paths loaded, in order
---   sources  the same, as real paths that io.open can read
---   dir      the addon's directory, with its trailing separator
function __loadAddon(addonPath)
    addonPath = addonPath or "BiSHealing.lua"
    local addonDir = addonPath:gsub("[^/\\]*$", "")
    local files = tocFiles(addonDir)
    if #files == 0 then die("the TOC lists no loadable lua files") end

    local ns, loaded, sources = {}, {}, {}
    for _, rel in ipairs(files) do
        -- the target may be a copy somewhere else (mutation runs do exactly
        -- that), so the addon's own file is always the path we were given
        local path = rel:match("BiSHealing%.lua$") and addonPath or (addonDir .. rel)
        local chunk, err = loadfile(path)
        if not chunk then die("cannot read " .. rel .. ": " .. tostring(err)) end
        local ok, e = pcall(chunk, "BiSHealing", ns)
        if not ok then
            print("!! LOAD ERROR (" .. rel .. "): " .. tostring(e))
            os.exit(1)
        end
        loaded[#loaded + 1] = rel
        sources[#sources + 1] = path
    end

    print(("== loaded ok (%d files, TOC order: %s)")
          :format(#loaded, table.concat(loaded, ", ")))
    return { ns = ns, files = loaded, sources = sources, dir = addonDir }
end

--- Every .lua the addon ships must be listed in the TOC. A split-out file that
--- nobody added to the TOC does not error -- it is simply never loaded, and half
--- the addon quietly stops existing. Needs a directory listing, which Lua 5.1
--- does not have, so this is best-effort: it reports what it could not check
--- rather than passing silently.
function __tocCoversDisk(addonDir, files)
    local listed = {}
    for _, rel in ipairs(files) do listed[rel:lower()] = true end
    -- the mocked libraries are in the TOC but dropped from `files`; the dev
    -- harnesses are deliberately NOT in the TOC (they never ship)
    local pipe = io.popen(("cd %q 2>/dev/null && find . -name '*.lua' 2>/dev/null")
                          :format(addonDir ~= "" and addonDir or "."), "r")
    if not pipe then return nil, "no directory listing available" end
    local all = pipe:read("*a")
    pipe:close()
    if not all or all == "" then return nil, "no directory listing available" end

    local missing = {}
    for line in all:gmatch("[^\n]+") do
        local rel = line:gsub("^%./", "")
        local low = rel:lower()
        -- dev/ never ships and is deliberately not in the TOC; everything under
        -- Libs/ is the library author's file list, not ours
        if not low:match("^dev/") and not low:match("^libs/") and not listed[low] then
            missing[#missing + 1] = rel
        end
    end
    return missing
end
