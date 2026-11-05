# BiS> buffs - the buff helper (PLAN, nothing built)

Arn, 24 Oct 2026: "if a class is capable of buffing like priest fortitude or druid mark of the wild ... a button in
bis now that chooses the best target to buff, and if more people that can buff have the addon it divides the work
evenly and fairly so they dont buff the same people and waste mana. also on the frames we mark when they are offline
we can also put something if they are afk ... except paladins they use something called pally power." Then: "it's a
feature that runs in the BiS Healing now box but is OFF by default", and "it scans our bags for the waters like the
res feature - if we don't have enough mana for the next cast we drink water".

Facts below are tagged as `_bisdev/docs/forever-lookup.md` wants: CONFIRMED (measured on Forever), BETA, DOC (our
docs/code say so), WEB (a public source), UNVERIFIED (a probe must answer it).

## 1. Who buffs, and with what (Forever: level cap 60, permanent - forever-lookup.md:8)

| Class | Single target | Group (reagent) | Notes |
|---|---|---|---|
| Priest | Power Word: Fortitude (1243 1244 1245 2791 10937 10938) | Prayer of Fortitude 48+ (21562 21564; Sacred Candle) | Divine Spirit (talent: 14752 14818 14819 27841), Shadow Protection (976 10957 10958; group 27683) |
| Druid | Mark of the Wild (1126 5232 5234 6756 8907 9884 9885) | Gift of the Wild 50+ (21849 21850; Wild Berries / Wild Thornroot) | Thorns (467 782 1075 8914 9756 9910) - tanks only |
| Mage | Arcane Intellect (1459 1460 1461 10156 10157) | Arcane Brilliance 56+ (23028; Arcane Powder) | mana users only |
| Paladin | - | - | **left out** - Pally Power does blessings |

Ids: classic-era, read off the Forever spell cache (`_forever-backup/.../ForeverAurasOptions.lua`) - DOC. Shamans,
warriors, rogues, hunters, warlocks: no raid buff to hand out.

## 2. What Forever lets an addon see (DOC: docs/forever-secret-values.md, solved.md, Between.lua)

- **Auras: readable OUT of combat, secret IN combat** - they lock the instant secure frames do. Buffing is an
  out-of-combat job, so this is the easy case. Read **by spell id** (`C_UnitAuras.GetUnitAuraBySpellID`; your own:
  `GetPlayerAuraBySpellID`) - by name is restricted, and the index walk hard-errors in instances even out of combat.
  Between.lua's `FB.Watched` already does exactly this.
- **A nil aura is not an absence** - an unreadable answer counts as "don't know", never "missing".
- **Range:** `C_Spell.IsSpellInRange(spell, unit)`, never `UnitInRange` (a secret boolean).
- **Unit tokens are never compared** - `UnitIsUnit` only.
- **Chat lockdown in fights** (`InChatMessagingLockdown`) - fine: the talking happens out of combat.
- UNVERIFIED: the aura's `expirationTime` and `sourceUnit` plain out of combat; `UnitLevel` plain; `UnitIsAFK`'s secrecy
  (Grid.lua:1541 says "only UnitIsAFK can be secret"; on retail it went secret in 12.0.5 - WEB).

## 3. The button (BiS> now, off by default)

- **Switch:** options row "buff helper" (off), `/bish buffs on|off`, and per buff family (Fortitude, Spirit, Shadow
  Protection, Mark, Thorns, Intellect) - only the families this character knows show.
- **One button per family you can cast**, in the BiS> now block like Tremor and the oil (`FN.BUTTONS`, a new id at the
  end). Earned the same way: shown **out of combat** when at least one of *your* targets needs it; hidden otherwise.
  The icon is the spell; a small number = how many of yours still need it; it glows while any of yours is missing it
  or has under 5 minutes left.
- **One click = one buff on the best target.** The button is a secure unit button re-aimed the way `FN.ApplyRes`
  re-aims res (`/cast [@unit] Spell(Rank N)`), and the aim is chosen in **PreClick** (solved.md:305) so it is fresh
  at the click. Out of combat only; in combat it greys and waits.
- **Group or single:** when 3+ in one of your groups need it and you carry the reagent, the click casts the group
  buff on one of them; else the single buff.
- **The rank (a trap the web found):** a plain action-bar cast lowers a buff's rank for a low-level target by itself,
  but a MACRO cast fails with "Target is too low level" (WEB - Blizzard forums). So the button picks the rank itself:
  the highest rank whose learn level is no more than ~10 above the target's level (Heals.lua's `FE.Rank` already reads
  each rank's learn level). The "10 levels" rule is UNVERIFIED - a probe.
- **The tooltip** (never a second label on the bar): "Next: Arn - group 3 - missing"; "Yours: groups 1, 4, 7 (12
  people, 3 to go)"; "Also buffing: Priestname - groups 2, 5, 8".

### Best target, in order
1. alive, connected, not AFK (plain only), in range (`C_Spell.IsSpellInRange`), level high enough for some rank;
2. **missing the buff** (any rank, single or group, from anyone - a priest without the addon counts too);
3. then **soonest to run out** (under 5 minutes);
4. ties: tanks first (role), then healers, then the rest; then raid order.
Pets: off by default (a hunter's or warlock's pet can wear Fortitude - an option). Thorns: tanks only.

## 4. Sharing the work (when two or more buffers run a BiS addon)

The protocol goes in **LibBiSComm** (MOD "BUFF", lib 18), so a mage with only BiS Tools or BiS Gamba still counts and
still gets told his share - the button itself starts in BiS Healing (BiSTheme's shared Ask piece could carry it to
the other addons later, like BiS> in). Shaped like BiS> in (lib 17, `lib.BISIN`): group channel only, opt-in, off is deaf.

- **`HAVE|family|rank|group|on`** - "I buff Fortitude, rank 6, I can do the group version": said on opt-in, to a new
  group member, and back to anyone new who says it (BiS> in's OPT pattern).
- **Everyone works out the same split - no voting.** Per family, the buffers are sorted by name; the raid's groups 1-8
  are dealt out one at a time, each to whoever has the fewest people so far (ties: name order). Same inputs on every
  PC = the same answer on every PC: no message says "you take group 3". Groups, not loose people, because the group
  buffs hit a whole group - one cast, no overlap.
- **`BUSY|family|why`** - out of mana, out of reagent, AFK, or switched off: the split is dealt again without you.
- **Stragglers:** your groups all done and somebody else's target still bare 30 s later (they're away, dead, out of
  range) - you may take it, but only by **`CLAIM|family|guid|at`**, first claim wins everywhere (BiS> in's `better()`:
  the earliest `at`, the lower name on a tie). Nobody casts on someone just claimed for the next 10 s.
- Fair over a night: the deal starts from a different buffer each pull of the roster (by the raid's server time), so
  nobody always gets the big groups.

## 5. Drink when the mana is short (Arn's addition)

- Your own mana can be secret on Forever (Between.lua: "UnitPower is secret on this client"), so the plan does **not**
  read it. It asks the game "can I cast this?" - `C_Spell.IsSpellUsable(spell)` answers usable / not-enough-mana
  (UNVERIFIED whether that pair is plain).
- Not enough mana for the next buff: the family button becomes **DRINK** - the best water in your bags, by the oil's
  road (`FN.ArmOil` writes `/use item:<id>`; `FN.OilWatch` re-checks on a bag change, out of combat). Best = the most
  mana restored that your level may drink; conjured water first (it's free).
- The water list: classic ids - Conjured Water/Fresh/Purified/Spring/Mineral/Sparkling/Crystal (5350 2288 2136 3772
  8077 8078 8079), vendor Refreshing Spring Water 159, Ice Cold Milk 1179, Melon Juice 1205, Sweet Nectar 1708,
  Moonberry Juice 1645, Morning Glory Dew 8766 - UNVERIFIED on Forever (it renamed some things; probe the bag).
- No water: the button says so in its tooltip and stays a buff button.

## 6. AFK on the cells (most of it is already there)

- **Already built:** `FG.StatusWord` (Grid.lua:1524-1552) writes **AFK** in place of the health number when
  `UnitIsAFK` answers plainly - after OFFLINE and DEAD. PLAYER_FLAGS_CHANGED repaints the cell.
- **The gap:** when `UnitIsAFK` comes back secret, the cell shows the number again and AFK is lost. Fix: a small grey
  **AFK** badge whose alpha the client picks from its own secret answer (`C_CurveUtil.EvaluateColorValueFromBoolean`,
  the range dimming's road) - shown, never tested.
- The buff helper skips AFK people only when the answer is plain.

## 7. Probes before the first line of code (BiS? macro, out of combat, in a group)

1. `GetUnitAuraBySpellID(unit, id)` for a party member's Fortitude: `expirationTime` / `sourceUnit` plain? In a dungeon too?
2. `UnitLevel(unit)` plain for a party member.
3. `/cast [@party1] Power Word: Fortitude(Rank 6)` on a much lower target: the error, or a quiet downrank?
4. `C_Spell.IsSpellInRange` and `C_Spell.IsSpellUsable` (and its no-mana half) plain out of combat?
5. `issecretvalue(UnitIsAFK("party1"))` while they are AFK; and in combat.
6. The water item ids in a real bag (Forever may have new ones).

### Answers, round 1 (4 Nov 2026, Forever 1.60.1.70532, open world, out of combat; Arn's level 4 priest + party1, level 4)

Probe: `_bisdev/audit/BiSProbe/Buffs.lua` (`BiSBuffProbe()`), bisdev branch probe/buffs.

1. **CONFIRMED plain, open world:** `C_UnitAuras.GetUnitAuraBySpellID(party1, 1243)` gave `expirationTime` (a GetTime
   number), `duration` 3600, `sourceUnit` "player" - all plain. Same on "player". **Still open: inside a dungeon.**
2. **CONFIRMED plain:** `UnitLevel` for player and party1; `GetUnitName(party1, false)` the whole name.
3. **Not answerable yet** - only rank 1 is known at level 4. Needs rank 2 (level 12) and a target under ~level 2-3,
   or later ranks. **Found instead:** with party1 out of range (check 4 said false), `/cast [@party1] Power Word:
   Fortitude` succeeded and the buff landed **on the priest** (fresh 3596 s on "player", party1's older buff untouched).
   So the button must test range BEFORE it aims at someone, never trust the cast to refuse. (UNVERIFIED cause: likely
   the client's self-cast fallback.)
4. **CONFIRMED plain:** `C_Spell.IsSpellInRange(1243, party1)` false (plain boolean), `C_Spell.IsSpellUsable(1243)`
   true, noMana false. **Still open:** the noMana half answering true (a Smite earlier gave "Not enough mana" - the
   probe did not read usable at that moment).
5. **Half:** `UnitIsAFK(party1)` plain false - but party1 was not AFK. **Still open:** while AFK, and in combat.
6. **CONFIRMED in a bag:** 159 Refreshing Spring Water, 4540 Tough Hunk of Bread, 11584 Cactus Apple Surprise, 117
   Tough Jerky - classic ids, `classID` 0 subclass 5 (food & drink). **New on Forever:** 247841 "Wild Harvest",
   consumable subclass 8 (what it restores: unknown).

## 8. Cost (lean and mean)

Nothing runs while the switch is off. On: UNIT_AURA for roster units only, out of combat only, each unit's few ids
cached until its next UNIT_AURA; the re-aim in PreClick; a `Cost.Count` budget in the same commit as the code.

## 9. The order to build

1. Probes (section 7).
2. The scan + best target + the button for one family (Fortitude), alone - no sharing.
3. The drink fallback.
4. The secret AFK badge.
5. LibBiSComm 18: HAVE / BUSY / CLAIM and the deterministic split; the tooltip's "who has which groups".
6. The other families; group buffs with reagents.
