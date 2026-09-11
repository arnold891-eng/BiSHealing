# BiS Healing

Pyramid raid frames that learn who actually takes damage.

Built for a slow-cast healer. Instant-cast healers win races to whoever is
lowest right now; a 2.5 second Chain Heal cannot. So this doesn't try to tell
you who is lowest — it puts the people who *reliably* take damage where your
cursor already is, and gets better at that after every fight.

## Bars and names

Names are cut to five characters (realm suffix dropped first), so a 25-man reads
as a grid instead of a wall of overlapping text.

The bars are black on purpose. Twenty-five bars in four colours is a picture you
stop reading — there is nothing for the eye to lock onto. A bar carries exactly
one signal:

- **black** — nothing to do here
- **red** — the predicted hole has grown big enough that a *downranked* Chain
  Heal (max rank minus two) lands whole, with none of it wasted
- **red, flashing** — that, and the damage has not stopped

The prediction already runs the hole forward by your real cast time, so red
means "by the time this cast lands, it will fit" — not "he is hurt right now".
That is the difference between starting a cast that pays and starting one that
overheals into a bar somebody else already topped off.

`/bish bands` prints the exact number the red is keyed to. The old four-colour
rank bands are still there if you prefer them — turn off "Black bars" in the
settings panel.

## Heal sizes: the tooltip is not the answer

The spellbook shows a spell's **base** healing with no gear in it. Chain Heal
reading "681 to 775" while the cast lands for 2800 is not a bug in your eyes —
that is what the client reports. Every decision this addon makes is sized off
what a cast is *really* worth, worked out two ways:

**Estimate** — base + (healing power x coefficient), then talents. The
coefficient is cast time / 3.5s, the standard TBC rule, read from your live cast
time so Improved Healing Wave correctly *lowers* it:

| Spell | Coefficient | With 5/5 Purification | + 2/2 Improved Chain Heal |
|---|---|---|---|
| Healing Wave | 85.7% | 94.3% | — |
| Chain Heal | 71.4% | 78.6% | 94.3% |
| Lesser Healing Wave | 42.9% | 47.1% | — |
| Earth Shield (per charge) | 28.6% | 31.4% | — |

**Measured** — what your casts of that exact rank actually healed for, taken
from the combat log. Three things are thrown out:

- **Casts that were mostly overheal.** A cast into a topped-off bar is not a
  measurement of anything you can act on — in the field, sizing off heal +
  overheal put Chain Heal Rank 3 at 4815 when the cast visibly lands 2.7k, and
  the bars then refused to go red on a hole that rank would have filled exactly.
  A cast into a real hole has nothing to argue about: the heal landed, the log
  says how much. Samples more than half overheal are dropped.

- **Crits.** Not scaled down — discarded. Dividing a crit by 1.5 is correct on
  average and wrong on a small sample, and one early crit is enough to push a
  downrank above max rank. You crit about one cast in ten, so losing those costs
  nothing. What the bars ask is "will a *normal* cast cover this".
- **Chain Heal bounces.** Only the first target of a chain is full size; the
  jumps are halved and would undersize the spell by about a third.

Smoothed, saved per character, and it takes over after four clean casts. A
measurement is never believed past twice the coefficient estimate — the maths
can be wrong about a set bonus, it cannot be wrong by a factor of two.

`/bish resetsizes` wipes the measurements and falls back to the estimate, which
is the fix if a bad session ever teaches it something silly.

**Ranks you have not cast** are estimated, then multiplied by a calibration
factor learned from the ranks you *have* cast. One measured rank tells the addon
how far the coefficient maths is off for your gear and buffs, and that
correction carries to every other rank of the spell. A lower rank can never read
as larger than a higher one — if a measurement ever puts it there, it is capped
just under and `/bish bands` says so.

The click binds are keyed to the spell **rank**, never to a heal size: left is
always the downrank and shift+left is always max rank, whatever this fight's
numbers happen to say.

The measurement wins because it needs no coefficient table, no talent list and
no guess about your gear: it already contains your trinkets, your buffs, and the
healing Nature's Blessing gives you from Intellect. The estimate exists so the
first pull after a fresh install is still roughly right.

Earth Shield charge size is measured from real charges in the combat log, and
seeded from the 28.6% coefficient until it has seen some — so `/bish esplan`
works on the pull instead of saying "shield someone and let it tick" for two
minutes. Note that Earth Shield snapshots your healing power at *cast* time, so
popping a trinket before shielding is worth doing.

`/bish bands` prints all of it: base, effective, and whether the number is
measured or still estimated.

## Triple-crit brag

Three targets *and* three crits on one Chain Heal announces
`Oh Baby, a Triple Chain Heal Crit!` to **party chat only** — in a raid that is
your subgroup and nobody else. Throttled to once every 15 seconds, and it prints
to yourself when you are solo rather than erroring at a channel you are not in.
Turn it off in the settings panel.

## Layout

Rows of 1, 2, then 6 — and every row after the third repeats that six-across
half-width shape for as long as the roster needs. A 25-man reads 1, 2, 6, 6, 6, 4.
All rows are full height; only the width scales.

- **Apex** — your Earth Shield target. Wherever you last cast it, that frame
  goes on top.
- **Row 2** — full width: name, deficit, incoming, corner markers, charge pips.
- **Row 3 onward** — half width, deliberately plain. Colour-coded bar and a
  short name, nothing else. These are the people you are least likely to Chain
  Heal; they need to be visible, not detailed.

The order is rough on day one and sharpens with every encounter. Run it beside
your usual frames until it earns the switch.

## How the ranking works

Three inputs, read from the combat log:

- **Volume** — damage taken per second of fight, averaged across encounters.
- **Consistency** — how often someone finishes a fight in the top third of
  damage taken. This is what stops a single spike from owning the apex:
  eating one big hit and dying gives you one loud fight and nothing else.
- **Chain Heal bounce quality** — how many targets your Chain Heal reaches when
  cast on that person. Someone who stands in the melee clump is worth more of
  your cast than someone who never bounces.

Recent fights count more: each older encounter is weighted down, so tonight's
raid dominates and history only nudges. Fights shorter than 8 seconds are
ignored so trash pulls don't pollute the data.

## Why it reorders between pulls

Moving or resizing a secure unit frame is blocked once combat starts, so the
layout is decided when combat ends and stays frozen through the fight. During
combat only the visuals change — bar length, colour, glow — which is
unrestricted.

Nothing here picks a target for you. You hover or click; your hand is the
input.

## Settings panel

Type `/bish` with nothing after it to open the settings window. Everything is a
checkbox or a button — no commands to memorise:

- Checkboxes for every feature: frames, lock, role corner markers, pulse,
  incoming fill, cast counter, bounce lines, gold chains, celebration, Gift
  badge, mana RPM gauge, pets, firing trinkets on shift+left, mouse-wheel heals,
  the Nature's Swiftness pip, totem reach, curable debuffs and the five-second
  rule. Toggle any of them off if they get busy.
- Buttons: Reorder now, Recenter, Rescan spells, Wipe history.

The typed commands below still work as shortcuts.

## Commands

| Command | Effect |
|---|---|
| `/bish` | Show or hide the pyramid |
| `/bish score` | Current ranking, with the numbers behind it |
| `/bish reorder` | Force a reorder (applies when combat ends) |
| `/bish lock` | Lock or unlock dragging |
| `/bish reset` | Wipe learned history |
| `/bish ranks` | Probe the spellbook for heal ranks (set it to show ALL ranks first) |
| `/bish bounce` | Toggle live logging of Chain Heal bounce counts |
| `/bish es` | Earth Shield charge procs, healing and gap between charges |
| `/bish rawes` | Dump every Earth Shield combat log event verbatim (debugging) |
| `/bish sim on` | Demo mode — walk every feature across your real group |
| `/bish sim off` | Stop the demo |
| `/bish bands` | Show the colour bands and what each covers |
| `/bish wheel` | Turn mouse-wheel heals on or off (`on` / `off` / `strict`) |
| `/bish bind` | Print every click and wheel binding as it is actually set |
| `/bish esplan` | Who should carry your Earth Shield, and who should carry the other shaman's |
| `/bish dispel` | Every curable debuff met so far, per zone, most seen first |

## First session checklist

Three things this build exists to answer:

1. Set the spellbook to show **all ranks**, then `/bish ranks`. More than three
   entries means downranking is enumerable and the colour bands and bindings in
   the plan are buildable.
2. `/bish bounce`, then cast Chain Heal a few times on a melee clump. Each cast
   should print how many targets it reached — that confirms bounces log as
   separate heal events.
3. Earth Shield someone, let it run out, then `/bish es`. The "min gap" figure
   is Earth Shield's internal cooldown between charges.

## Seeing the other shaman

**Their Earth Shield charges** show as grey pips, yours as amber. The stack count
lives in the aura itself, so any shield's charges are readable no matter who cast
it — this addon was reading them every tick and throwing them away before
drawing, left over from when it assumed you were the only shaman in the group.
The last-charge flash stays yours only: their refresh is not your call, and a
flashing frame you can't act on is noise.

**Their Chain Heal** shows as a teal bar down the left edge of whoever it is
about to land on. A chain touches three people and those three are not equal
news, so the mark says which is which: a **full-height bar** is the target they
aimed at, properly healed; a **dim stub** is a target only catching a bounce,
which is half size and then a quarter, and may well still need you. Marking all
three the same way said "these three are handled", which is a third true — deliberately away from the four role corners, because it is
not advice about that frame, it is news about somebody else's cast. Hovering
names the caster. Three sources feed it, best first:

1. **LibHealComm** — any shaman running a HealComm-aware addon (VuhDo, HealBot,
   Grid) broadcasts the cast as it *starts*, with every bounce target. This is
   the one that arrives in time to change your mind. An interrupted cast clears
   the mark rather than leaving a lie on screen.
2. **A BiSHealing peer** — we tell each other the instant the cast is sent, so
   two of these addons don't need a third to talk through.
3. **The combat log** — fires when the heal *lands*, too late to redirect, but it
   works when nobody in the group runs anything at all. Each bounce arrives as
   its own heal event, so they are grouped by caster within the same 1.25s
   window the addon uses for your own chains — otherwise every jump reads as a
   fresh cast at a new primary.

## Talking to the other shaman

If a second shaman in your group is also running BiSHealing, the two addons talk
to each other over an addon channel (`BISHEAL`, sent through ChatThrottleLib so a
raid full of addons cannot queue each other into a disconnect). Each side sends
one line: who it has shielded, how many charges are left, and what one of its
charges actually heals for.

That replaces guesswork. Their charge size used to be *inferred* — watch their
Earth Shield procs in the combat log, average them, and hope you had seen enough
of them. Now they just say. The plan uses their real number the moment they
answer, and their shield target is treated as covered from the instant they cast
it rather than whenever your next aura sweep notices.

Nobody answering — they run a different addon, or none — changes nothing: the
combat-log inference is still there underneath, exactly as before. `/bish peers`
shows who is talking, what they are shielding, and how long since they were last
heard. Peers go stale after 90 seconds of silence and stop shaping the plan.

## Earth Shield planning

Earth Shield has a roughly 4 second cooldown between charges, so a target hit
every second consumes charges no faster than one hit every four. Getting hit a
lot is therefore not what makes a good shield target — sitting *below full
health* when the charge fires is, because a charge on a full bar heals nothing.

`/bish esplan` scores every candidate on charge consumption rate and how deep
they typically sit, then assigns two shields: yours and the other shaman's. If
you carry a bigger charge than they do, the larger shield goes on whoever can
absorb more of it.

Only rows 1-3 are considered. Anyone below that isn't taking enough damage to
deserve a shield, and if they start to, they climb into contention on their own.

**Self-inflicted damage doesn't count.** A warlock spamming Life Tap logs a
constant stream of damage on himself and sits permanently low — the exact
profile the shield hunts for, except an Earth Shield charge only fires on damage
from an *external* source. Any damage event whose source and target are the same
player is discarded before it reaches the hit rate, the fight totals, or the
pyramid ranking. `/bish score` shows how many hits were thrown away, so you can
see why the warlock isn't ranked where he looks like he should be. Anyone with
no external hit in the last 20 seconds is also heavily discounted as a shield
target.

**It stays put while the shield is healthy.** The amber corner used to point at
somebody every single tick, including while your shield sat perfectly placed on
the tank with five charges left — advice you can't act on is noise, and noise is
what trains you to ignore the marker. Now: shield up with 2+ charges, no corner
at all. Down to the last pip (or gone), the corner comes back — and the current
holder gets a 1.5x edge, so re-shielding the same tank wins unless a challenger
clearly beats him. The last charge flashes the pips regardless of who is
recommended; that flash is the thing meant to catch your eye.

Old saved history counted self-damage, so the depth and hit-rate numbers are
wiped once on first load of rc35. Encounter scores and Earth Shield charge logs
are measured from real events and are kept.

## Trinkets on the big heal

Shift+left (max-rank Chain Heal) fires both trinket slots before the cast:
`/use 13` and `/use 14`, then the heal. Whatever is ready pops — a slot on
cooldown or holding a passive trinket is a harmless no-op, and trinket uses are
off the global cooldown so the heal casts the same instant. Plain left-click
(downrank) never touches trinkets, so small heals don't burn cooldowns.

## Mouse-wheel heals

Scroll-up is a second pair of hands. Both binds are **mouseover only** — the
macro stops dead unless the cursor is over a living friendly, so scrolling
anywhere else costs nothing and does not misfire on the boss.

| Wheel | Casts |
|---|---|
| scroll up | Healing Wave, two ranks down |
| shift + scroll up | Nature's Swiftness + max-rank Healing Wave, trinkets first |
| scroll down | Lesser Healing Wave, two ranks down |
| shift + scroll down | Lesser Healing Wave, max rank, trinkets first |

Scroll up is the slow, heavy heal; scroll down is the fast top-up. Shift always
means "this one matters" — every shifted press fires both trinket slots (`/use
13`, `/use 14`) exactly like shift+left click does, and no unshifted press ever
touches them.

The emergency is one press, not two, and that is deliberate. Secure attributes
cannot be rewritten in combat, so the addon has no way to spot mid-fight that
Nature's Swiftness came off cooldown and re-point the button. A `/castsequence`
would track it — but it also *stalls* when the talent is on cooldown, and a
press that does nothing at all is the one outcome you cannot have on a tank at
10%. Nature's Swiftness is off the global cooldown, so a single press fires it
and the instant Healing Wave together; when it is down, the same press just
hard-casts. Nothing is ever swallowed.

If you want the true two-press version anyway, `/bish wheel strict` switches to
the castsequence: first press pops Nature's Swiftness, second press casts the
heal. Understand the trade — with the talent on cooldown, that press is dead.

Never trained Nature's Swiftness? Shift+scroll up quietly becomes a plain
max-rank Healing Wave. Respec and it re-checks itself; you do not need to
reload.

The bindings are *override* bindings: they never touch your saved keybind
profile, and they clear on `/reload`. All four wheel directions are taken, so
camera zoom needs to live somewhere else — rebind it, or turn this off with
`/bish wheel off`.

### Nature's Swiftness pip

A short bar on the top edge of a frame marks someone whose predicted hole is
past what a max-rank Chain Heal fixes — the case shift+scroll exists for. White
means Nature's Swiftness is up and the shot is live. Dim grey means the hole is
that deep and the talent is still on cooldown, which is exactly when you want to
know early. Toggle it off in the panel if you find it noisy.

## Losing the heal race

Getting sniped is not bad luck, it is missing information. LibHealComm only sees
healers who run a HealComm-aware addon — everyone else is invisible to it, so
their heal lands, your 2.5s Chain Heal arrives into a full bar, and nothing ever
warned you.

The client itself knows better and always has:

| API | What it gives |
|---|---|
| `UnitGetIncomingHeals(unit)` | everything inbound, addon or not |
| `UnitGetIncomingHeals(unit, healer)` | ...broken down per caster |
| `UnitCastingInfo(healer)` | when that caster's spell actually **lands** |
| `UNIT_HEAL_PREDICTION` | fires whenever any of it changes — no polling |

The number on a frame is **how many heals are converging on that target, yours
included** — "one other healer" and "you and another healer" are the same
situation, and showing 1 for it read as though you were not part of the pile-up
you are standing in. It uses the same palette as the bars: neutral grey when
nothing is being taken from you, the bars' red when it is, and a muted red when
somebody is healing that target with no cast bar to time them (an unreadable
race is not a race you should be told you win).

A healer is counted if *either* the client's per-caster prediction or LibHealComm
says they are on that target — and if the client's total for others still exceeds
everything that could be attributed, one more unnamed healer is added, because
under-reporting a race you are losing is the failure that matters. LibHealComm is
only trusted for attribution after a one-time probe proves this build honours the
per-caster argument; older ones return the total for every caster you ask about,
which would credit the heal to every healer in the group.

Two things come out of that. The prediction now takes the **larger** of what
LibHealComm reports and what the client reports — larger, not the sum, because
for anyone running a HealComm addon the two describe the same heal and adding
them would talk you out of casts you should make. And a small number appears on
the right edge of a frame: how many *other* healers have a cast in the air at
that target. Grey means yours lands first. **Red means theirs does** — that is
the cast you were about to waste. Hovering names them.

`/bish snipe` lists every contested target and who wins each race. If the client
has no prediction API it says so plainly, because then only HealComm users are
visible and the rest will keep landing first unseen.

One note on the popular sniping WeakAura this was taken from: it builds its
healer list from `UnitGroupRolesAssigned(unit) == "HEALER"`. On this client most
raid members report no role at all, so that list often comes back empty and the
aura silently does nothing. This uses class as the real filter and treats an
assigned role as a bonus.

## Incoming heals (LibHealComm)

If the bundled LibHealComm-4.0 loads, the predicted deficit subtracts heals that
other players already have in the air on a target — so the green mark and the
colour bands stop flagging someone three instant-casters are about to top off
before your 2.5s Chain Heal could land. This is the real fix for a slow caster
racing fast ones.

It sees any healer also running a HealComm-based addon (VuhDo, Grid, Healbot,
most raid frames), which is usually most of them. `/bish inc` shows what it sees.

Incoming heals show two ways on the frame: a translucent fill extending the
health bar to where it will sit once they land, and a precise `+N` number. The
prediction shrinks by that amount so the green mark avoids already-covered targets.

The prediction window tracks your **live** Chain Heal cast time, so Bloodlust and
haste trinkets are accounted for — at 2.1s the addon predicts less far ahead than
at 2.5s.

## Mana RPM gauge

A horizontal bar for your healing (demo mode sweeps it through all four states
so you can see the colours without a raid), built around the idea that burning mana is fine —
mana tide and potions refill it — so the failure is *under*-spending. A near-empty bar
(cruising, ending the fight at 80% mana) reads blue as the warning; a nearly full
bar with heals landing reads amber "redline" as praise. A tick marks where the
sweet spot begins. The one real red is
"overhealing" — spending hard but into full health bars, the only kind of burn
worth stopping.

It reads your mana spend rate against a full-tilt reference and discounts by how
much of your recent healing overhealed, so the needle rewards spend that lands.

## Cast counter

Above the pyramid sits `X | Y | +Z`:

- **X** (blue) — how many downranked Chain Heals your mana covers right now
- **Y** (amber) — how many max rank Chain Heals your mana covers right now
- **+Z** (green) — how many downranked Chain Heals your regen earns back every 5
  seconds. Green when you're gaining ground, grey at +0 (bleeding out). This is
  your sustain at a glance — pairs with the RPM bar.
- **5.0s … 0.1s** (orange, only sometimes) — the five-second rule. A cast that
  cost mana stops spirit regen for five seconds; this is how long is left. While
  it shows, +Z is your while-casting regen (MP5 gear and the like); once it is
  gone, +Z counts full spirit regen again. Whether a cast cost mana is read off
  the mana bar itself — before and after the cast — so a free proc or a totem
  drop that costs nothing never restarts the clock. Untick "Five-second rule"
  under Chain Heal to get the old always-while-casting number back.

Either number turns red at zero, so you see the button stop working before you
press it. It recalculates every tick, so regen and Water Shield ticks are
already reflected — it climbs while you are not casting and drops the moment
you spend.

## Why-here tooltips

Out of combat, hover any frame to see why that player sits where they do in the
pyramid: the share of their ranking that came from Chain Heal bounces, damage
volume, and consistency, plus their average bounce count and how many fights are
on record. Before there's data it says the placement is provisional. In combat
the hover shows just the standard unit tooltip, to stay cheap.

## Role corner markers

Each frame has four corners. A corner lights up when that frame is the single
best target for one role right now:

| Corner | Colour | Role |
|---|---|---|
| top-left + bottom-right | green | Chain Heal — cast here |
| top-right | amber | Earth Shield — put your shield here |
| bottom-left | orange | Gift of the Naaru — HoT this one |

One frame can wear several at once: green plus amber means the same person is
both your best chain and where your shield belongs.

The Chain Heal pick **snaps** rather than sliding, and a challenger has to beat
the current holder by 15% before the mark moves — so it does not flicker between
two near-equal targets. It blends how big the hole will be when your cast lands,
whether they are still being hit or have stabilised, their historical bounce
count, and their row.

The Earth Shield corner only ever marks somewhere a shield *should go*: it skips
anyone already carrying yours, never points at a shaman (including you — a shield
knocks their Water Shield off), and never at the other shaman's target. It drops
a tank who is being overhealed in favour of a damage-taker nobody is covering.

The Gift corner needs the spell off cooldown, and skips anyone already carrying
your HoT.

One toggle, "Role corner markers", drives all three colours together.

`/bish bull` prints who holds the green mark and why.

## Totem reach

A violet bar down the RIGHT edge of a frame means a buff totem of yours is down
and that party member is not carrying its buff — he is standing outside it. No
range API is involved: in TBC every aura totem is a plain party buff, so the
buff being missing *is* the range check. Only totems that put a buff on people
can be judged (Healing Stream, Mana Spring, Mana Tide, Strength of Earth,
Stoneskin, Grace of Air, Windfury, Wrath of Air, Tranquil Air, Totem of Wrath,
Flametongue, the three resistances); Tremor, Grounding, Searing and friends
have nothing to look for. It is your own party only — totems never reach past
the subgroup — and the tooltip names which buff is missing. The technique is
the Shaman UI WeakAura's "totem out of range" icons, rebuilt.

## Curable debuffs

A small square low on the right of a frame, in the client's own colour for the
debuff type (green poison, brown disease), for anything your class can cure. A
shaman clears Poison and Disease; the mark never lights for a curse or a magic
debuff you cannot touch. The header says `N to cure` while any are up, and the
tooltip names the debuff.

Every curable debuff met is banked under the zone it landed in, one count per
sighting, so after a night in a raid `/bish dispel` prints what each place
throws and how often — the per-boss dispel lists that the raid-frame WeakAuras
carry, except written by what actually hit your raid rather than typed in from
someone else's pack.

## Earth Shield charge pips

Six small amber dashes along the bottom edge of a full-width frame: one lit per
charge of **your** shield remaining. They flash on the last charge when that
frame is still the shield recommendation — the reapply cue. Half-width rows and
pets get no pips, by design.

## Demo mode

`/bish sim on` walks the features one at a time across the group you are
actually in, with a caption naming what you are looking at: the green Chain Heal
corners, the amber Earth Shield corner, the charge pips counting down and
flashing on the last one, the orange Gift corner, all three roles landing on one
frame, bounce lines and the full-chain burst, the mana gauge sweeping from
cruising to overhealing, the damage pulse, the Nature's Swiftness pip in both
states side by side, a readout of what each wheel direction casts on your
current gear and training, the totem-reach edge, the five-second rule running
out, and the curable-debuff mark in both colours. `/bish sim off` stops it.

It runs on your real party or raid — there is no fake roster. Demo mode only
draws; it never feeds invented numbers into ranking, targeting or your click
bindings, so what you see is the same drawing code that runs in a real fight.
Because nothing it touches is protected, it works mid-pull too.

Earlier versions built a fake raid of invented players instead. That turned out
to be worse than useless for the markers: fake frames had no unit token, the
corner code assumed every frame had one, and it quietly skipped all of them — so
the simulator misreported the exact feature it existed to preview.

## Bounce lines

When a Chain Heal bounces, a fading line is drawn from each target to the next.
Blue while the cast is still resolving, because a full three-target chain cannot
be confirmed until the cluster closes — about a second after the last bounce
lands. On close, every line from that cast is repainted gold and thickened, so a
great chain reads as one gold event instead of blue lines plus a separate burst.
Three targets *and* three crits gets the big burst: triple the stars, gold-white,
thrown faster.
Blue while the chain resolves — then if it reached all three targets, the whole
chain repaints **gold** and thickens, alongside the starburst. A great chain
reads as one gold moment instead of a blue line and a separate effect.

In demo mode a bounce chain fires every second or so across your real frames,
and about half are full chains, so both effects are visible outside a fight.

## Full-chain celebration

When a Chain Heal reaches all three targets — the ideal cast — a small starburst
pops on the primary frame. Purely a reward for good positioning. Demo mode
triggers it too, so you can see it outside a fight.

## Gift of the Naaru

If you know Gift of the Naaru, mouse button 4 casts it on the frame under your
cursor, and the orange bottom-left corner tells you where it is worth spending:
someone hurt enough that the 1085 HoT mostly lands, who is not the right answer
for a hard Chain Heal cast. When the HoT is already ticking on someone, that
frame shows the lit Gift icon instead.


## Notes

Click-casting is built in — no Clique, no mouseover macros:

| Click | Casts |
|---|---|
| left | Chain Heal, two ranks down |
| shift + left | Chain Heal max rank, firing both trinket slots first |
| right | Earth Shield, max rank — works in combat |
| button 4 | Gift of the Naaru (only bound if you know it) |
| scroll up | Healing Wave, two ranks down (mouseover only) |
| shift + scroll up | Nature's Swiftness + max-rank Healing Wave (mouseover only) |
| scroll down | Lesser Healing Wave, two ranks down (mouseover only) |
| shift + scroll down | Lesser Healing Wave, max rank (mouseover only) |

Data is stored per character in `BiSHealingDB`. It is only as good as the
fights it has seen — expect the first raid night to look arbitrary.
