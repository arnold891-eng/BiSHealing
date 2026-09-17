Read ../_bisdev/CLAUDE.md first.

## Layout (BiSHealing only)

- `BiSHealing.toc`: sets `## Interface: 20506`, `## Version` (currently `1.0-rc52`), `## SavedVariables: BiSHealingDB` and `## OptionalDeps: BiSTheme`. It is the only place the version lives: `BiSHealing.lua` reads it at runtime with `GetAddOnMetadata`. The load order is:
  - Libs first
  - then `Core\comm.lua`
  - then `BiSHealing.lua`
  - then `UI\options.lua`

  Load order changes behaviour, and the harness reads this file to get it.
- `BiSHealing.lua`: the addon's logic, about 5.4k lines (5368). All files share one addon table, `NS` (`local ADDON, NS = ...`, nil-safe so `luac -p` and the harness can run the file bare). The header comment lists behaviours carried over from BiS Rez that look wrong but must not be "fixed" (`"*type1"`/`"*spell1"`, `"AnyDown"`, `SetColorTexture`, pcall'd event registration). The file is split by `-- ---- name --` and `-- ====` banners:
  - `losing the heal race` / `SNIPE`, scoring knobs, layout knobs, state, `the other shaman's Chain Heal`
  - `db`: `DB()` is memoised and fills in defaults for `BiSHealingDB`. There is no single `dbver`. Instead there are per-table schema flags: `healSchema` and `esSchema`, both currently 2. A mismatch wipes and relearns that data.
  - roster, scoring, frames, tooltip, `bindings` (`BINDS`), bounce lines, cast counter, rpm gauge, target scoring
  - `UNIFIED ROLE-CORNER RETICLE`, `DEMO MODE (/bish sim on)`, `HEAL RACE ENGINE`, `AURAS, RANGE AND THE BAR PAINTER`
  - totem reach, dispel, combat log feed, celebration, fight boundaries, events
  - slash, rank probe, Earth Shield plan, heal option table
  - `what UI/ is handed`: the one block that publishes names onto `NS` for `UI/options.lua`. It includes getters (`NS.ESTarget`, `NS.ApplyBinds`, `NS.QueueReorder`, `NS.InFight`) for values that change after load. If a name is not published here, UI files cannot reach it.
  - `/bish` (`SLASH_BISHEALING1`, `SlashCmdList.BISHEALING`) with subcommands such as `score`, `reorder`, `reset`, `lock`, `sim`/`demo`, `ranks`, `esplan`, `peers`, `rescan`, `resetsizes`, `center` and `keybinds`. If `NS.CFG` is missing (no UI file), it prints a "reinstall" message instead of crashing.
- `Core/comm.lua` (197 lines): addon comm, using prefix `BISHEAL`. It handles the ES state line, the version nag, the peer TTL and the chain-cast announce, and it owns `NS.COMM`. It loads before `BiSHealing.lua` on purpose, so `BiSHealing.lua` can assign into `COMM`. Because of that, anything it needs from `BiSHealing.lua` must be looked up through `NS` when called, never captured at load.
- `UI/options.lua` (637 lines): two windows.
  - The `/bish` options window, built on the shared kit `Libs\BiSTheme\Options.lua` (230 px wide).
  - A separate Keybinds window driven by `NS.BINDS`.

  It only reads and writes settings. Every decision stays in `BiSHealing.lua`.
- `Libs/`: embedded BiSTheme (`Console.lua`, `Options.lua`), LibStub, CallbackHandler-1.0 and LibHealComm-4.0 (with ChatThrottleLib).
- `dev/load.lua`: the shared loader for `tests.lua` and `stress.lua`.
  - It reads the `.lua` lines from `BiSHealing.toc` in order and hands each file `("BiSHealing", ns)`.
  - It skips the mocked LibStub, CallbackHandler and LibHealComm, but loads `Libs\BiSTheme\Console.lua` for real.
  - `__tocCoversDisk` fails the run if any shipped `.lua` file outside `dev/` and `Libs/` is missing from the TOC.
- `dev/tests.lua` (2716 lines): the main mock-WoW suite (`lua5.1 dev/tests.lua [path/to/BiSHealing.lua]`). It exposes the addon table as `ADDON_NS`, plus `LOADED_FILES` and `ADDON_SOURCES`. If `BISTHEME=<path>` is set, it loads that file after the addon, the same order the client uses. The mocks are strict on purpose (e.g. `SetColorTexture`).
- `dev/stress.lua` (766 lines): turns every toggle on and off, runs a full fight of combat log, demo mode and the combat-lockdown paths. It only checks that nothing crashes, not behaviour. It uses the same `load.lua`.
- `dev/theme.lua` (61 lines): runs `tests.lua` twice, once with `BISTHEME=` empty and once with a deliberately wrong-coloured BiSTheme. It writes that fake theme to `$TMPDIR/bish-theme-probe.lua` (or `/tmp`) and deletes it afterwards.
- `dev/options.lua` (210 lines) with `dev/kit.lua` (478 lines): tests the shared `Libs/BiSTheme/Options.lua` kit on its own, using the Nebbinator harness copied in unchanged as `kit.lua`. The `OPT` env var points it at a different root.
- `dev/` has no release script, `harness.lua` or `.toc` file for this addon.
- `.github/workflows/check.yml`: calls `arnold891-eng/bisdev/.github/workflows/check.yml@main` with `addon: BiSHealing`.
- `.gitattributes`: forces LF line endings, except CRLF for `*.ps1`. `.gitignore` excludes `*.zip`, `release/` and `*.bak`.
