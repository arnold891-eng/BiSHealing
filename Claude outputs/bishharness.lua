-- MOVED 9 Sep 2026 -- this suite now lives at dev/tests.lua
--
--     cd BiSHealing && lua5.1 dev/tests.lua
--
-- The folder this file sits in ("Claude outputs") was never a home, it was
-- a drop box. Nothing loads this stub in game; it exists so an old command
-- fails loudly instead of running a suite that stopped being updated.
io.stderr:write("BiSHealing: bishharness.lua has moved.\n"
             .. "  run:  cd BiSHealing && lua5.1 dev/tests.lua\n")
os.exit(2)
