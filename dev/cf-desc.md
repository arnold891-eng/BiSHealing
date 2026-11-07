# BiS Healing — CurseForge page text (1.0.0)

Paste everything below the line into the project description
(CurseForge → BiS Healing, project 1703250 → Edit → Description).

Changed since the 0.16.0 text (7 Nov, 1.0.0 - Forever 1.0): the mouse section says LEFT-click for
the binds; "Settings" says right-click for the options, names the BiS> home in the game's options,
and says a new install starts quiet (crosshair, LOS flash, buff sound and reminder off).

Changed since the 0.11.0 text (5 Nov, 0.16.0): the buff buttons in BiS> now (after Weapon oil);
`/bish buffs` in the command table; "Click a corpse to res it" brought up to 0.15.0 (any click, Revive
for druids, never Rebirth - the old line still listed Rebirth). 0.14.0's "Mana for mana" was already on
the page; the rest of 0.12.0-0.15.x were fixes and the shared lib.

Changed since the 0.8.5 text (17 Oct, 0.11.0 - big features only, Arn: "only for the big things"):
the cure boxes replace the dispel-marker line in "The cells"; click a corpse to res joins "No double
res"; the res button in BiS> now; `/bish cures` and `/bish res` in the command table.

Changed since the 0.8.4 text (12 Oct): the shield button in BiS> now (live in a fight, charge
colours, click to cast); "The header talks to you" says the button takes over the reminder; the
`/bish buff` row says so too.

Changed since the 0.8.3 text (11 Oct): the opener and "Why it works" in the house voice
(`_bisdev/docs/voice.md`); trinkets first in the mouse section; "rez: Name" on a corpse someone is
ressing; the oil button in BiS> now; `/bish trinkets` and `/bish cpu` in the command table.

Changed since the 0.8.3-beta4 text (8 Oct): the mouse section gains the heal row and "Nature's
Swiftness first"; the overheal line says what to DO with the band (cancel until it is gone);
`/bish overheal` in the command table.

Changed since the 0.8.2 text (7 Oct): a new "Who is who" section (the crosshairs: gold you, red
target, white mouse, white ticks for both); the heals-on-their-way line now says the heal stops at
the cell's edge and the overheal is a band over their health; the dimming line says it uses your
longest-reaching heal, never dims you or your target, and how far it dims is yours; the options
window line; four new command rows; one line on being light on your computer.

Changed since the 0.8.1 text: "Quiet by default" names its one exception - on a PC where the game
will not let the aura markers be placed, 0.8.2 leaves them out and says so once.

Changed since the 0.7.0 text: Riptide in the heal-over-time line; new sections for the group buff
watch, `BiS> now` and the pings; the command table has eight new rows; the "why it works this way"
section now says what the dungeon run proved.

**Deliberately NOT mentioned: the Tremor button.** It ships, but nobody has watched it light in a
real fight (Arn, 3 Oct: "hard to find stuff that fears"). It is earned-only, so a player meets it
the first time it matters rather than in a list. Add it to the page once it has been seen working.

---

# BiS Healing

**Click-cast healing frames for any healer on WoW Forever.**

Forty names on the screen and one of them is about to die. You do not want a spellbook. You want your mouse on their name and a heal on the button. Drag a spell onto a picture of a mouse. Click a name. That's the addon.

## Your mouse, or Clique — your choice

**Use ours:** left-click the minimap button or type `/bish mouse`. You get a drawn mouse: drop a spell on the button you want to press. Left, right, middle, two thumb buttons, wheel up and wheel down, each with no modifier, Shift, Ctrl or Alt: 28 places.

- **Your heals, ready to drag.** A row of your trained healing spells sits in the window, each at your highest rank — drag one onto a button.
- **Ranks are kept.** Drop Rank 4 and you get Rank 4, not the biggest one you know — the same bar for a third of the mana. Click the little number on a slot to step through your ranks.
- **Nature's Swiftness first, in one press.** Drop Nature's Swiftness onto a button that already holds a heal: that button pops it, then casts the heal on whoever you clicked. The slot shows half of each icon. On cooldown you simply get the normal heal; drop the heal again to take it off. Inner Focus (priest) and Divine Favor (paladin) work the same way.
- **Trinkets first, in one press.** Each tab (no modifier, Shift, Ctrl, Alt) has two ticks: **trinket 1** and **trinket 2**. Tick them and every button on that tab uses those trinkets, then the heal. Or drag a trinket you wear onto one heal's button. It stacks with Nature's Swiftness. A trinket with nothing to use, or on cooldown, is skipped.
- **Anything not bound targets the unit.** Leave a button empty and clicking a name selects them, like Blizzard's own frames.
- **Right-click a slot** to clear it.

**Already use Clique?** Keep it. Tick **"let Clique handle clicks"** (or `/bish clique`) and BiS Healing steps aside entirely. Untick it and your own binds are back.

## Mana for mana: which heal to spam

Should you spam your biggest Healing Wave, or a smaller rank that costs half? Press **open** on "which heal, mana for mana" in the options (or `/bish efficiency`). A window opens beside them with every rank of every heal you know, read from your spells as they are right now — your gear, +healing and talents are already in the game's numbers:

- **heal, mana, per mana, per second** for each rank, with your crit included. The best per mana and the fastest are lit.
- **dry in:** how long you can spam that rank from a full mana bar, counting the mana you get back while casting.
- **Pick a fight length — 15 s, 30 s, 1 min, 2 min or 5 min** — and it tells you the rank that heals the most in that time: full speed until you run dry, then what your regen pays for. A short burst wants a fast heal, a long fight a cheap one, and it shows you where that switch is for your character.
- **Drag the answer.** The recommended rank's icon sits beside it — drag it onto an action bar or one of your mouse buttons. **mouse binds** opens the mouse right beside it.
- **Group heals and heal-then-HoT spells** (Prayer of Healing, Holy Nova, Regrowth, Tranquility) show with a `*` and aren't ranked yet - they heal more than one number can say.

## Pings, on any button you like

The game's ping wheel is good and slow — you hold a key, move the mouse, pick. In a fight you want one press.

Open `/bish mouse` and there are four chips along the bottom: **Assist**, **Attack**, **Warning**, **On My Way**, wearing the game's own icons. Click one, then click any mouse button — including the **wheel** — and it lives there.

**The cell you click is who it pings.** Alt-click your own cell to ping Assist on yourself; put Attack on a button and click the target cell with a mob in it. Same gesture as healing, no radial menu, no mouse travel.

## Every healer keeps their own binds

This client forgets addon settings at every restart, so BiS Healing keeps your binds and settings in a macro called `BiSHealing` in **each character's own macro tab**. Your druid and your priest never share, and everything comes back at login. Please don't rename it. (`/bish keep` shows what's in it.)

## The cells

One per person, and the groups can run **down or across**. Options: **groups: down / across / tanks**.

- **The first name on the top line** — "Kumlust", not "Kumlust Surname".
- **A number on the bottom line: what they still need.** It counts heals already on their way, so two healers stop filling the same gap. Shortened (`3.2K`), and **blank at full health**. Prefer a **percentage**? Or nothing? Your choice.
- **Heals on their way, and the overheal.** Incoming heals fill the missing health in green and stop at the cell's edge. The part of a heal that would land on nobody shows as a bold magenta band over the end of their health, with a white tick where it starts — that is how much damage they can take before your heal stops being wasted. Mid-cast, cancel and re-cast until there is no magenta left - then every point of it lands.
- **Bars in class colour — or coloured by health**: green, amber below 70%, red below 35%.
- **Cure boxes, down the left edge.** One small box per cure you know: Cure Poison and Cure Disease for a shaman, Dispel Magic and Cure Disease for a priest, Remove Curse and Cure Poison for a druid, Cleanse for a paladin. Click the box to cure that person, mid-fight too. When they pick up something that box can remove, the game draws its icon in the box and the box pulses teal, with the stack count in the corner. On Forever a cure takes one stack off, so the number is how many clicks are left. Each box lights only for its own kind, so the one lit is the one to click. Your mouse buttons stay free for heals. `/bish cures off` puts back a single marker instead.
- **Your heals over time, with a countdown**: Renew for priests, Rejuvenation and Regrowth for druids, and **Riptide for shamans** — only your own casts, every rank. Each is found by name in your own spellbook, so it appears the day you train it and never before.
- **Marker size**, 6 to 20 pixels.
- **Dimmed when they're out of range** of your longest-reaching heal — every heal you have bound, plus your class's own — **including during a fight**, which is when you need it. The game keeps "can you reach them" secret in combat, so it is handed back to the game to pick the brightness from; the addon never learns who is reachable. You and your target are never dimmed. **How far it dims is yours**: `out of range` in the options, 20% to 90% (30% on a fresh install).
- **Click a corpse to res it.** Out of combat, every click on a dead player's cell (any button, any modifier, even one with nothing bound) casts your res: Ancestral Spirit, Resurrection, Redemption, and for druids **Revive**, Forever's out-of-combat res. Rebirth is never cast for you; its long cooldown stays yours for a battle res. The moment they're up, or a fight starts, the cell is your binds again. `/bish res off` turns it off.
- **No double res.** When another BiS healer starts a res, the corpse's cell says who: `rez: Chain`, until it lands or fails. Your own res casts are told to them the same way. Inside an instance fight the game hides these messages, and the cell just says DEAD.
- **Role icons**, and the raid's Main Tank counts as a tank.
- **A pyramid** (`/bish pyramid`): tanks on top, then damage, healers at the bottom. Melee sit above casters inside each band, and the bottom rows go half-width so a 40-man still reads as a pyramid.
- **Size**: 60% to 160%. **Put it anywhere** — drag the header above the cells.

## Who is who: the crosshairs

Thick corner brackets with a tick in from each side, outlined so they read on any class colour.

- **Gold on you** — or, with `/bish ring target` (**gold ring: me / target** in the options), **red on whoever you have targeted**: their raid cell, the target cell and the tot cell when they are the same person.
- **White on whoever your mouse is on** — hover a party or raid member's character in the world and their cell lights up, so you can see who that is on your frames.
- **Target and mouse on the same person**: the corners stay red and the four ticks turn white.

All of it keeps working inside dungeons and raids, where the game will not tell an addon who anyone is: the question is handed to the game and the game draws the mark. The mouse crosshair starts off on a new install: "mouse crosshair" in the options, or `/bish hover on`.

## Cells you can add

Each is a block of its own with a small `BiS>` bar: **drag it anywhere**, or **shift-click the bar** to send it round the grid. Two blocks never share a side. In the options window they are one row of switches — **cells: target · tot · me · mana**.

- **target** — a cell for whoever you have targeted, taking your mouse binds like any other.
- **tot** — and one beside it for *their* target. Useful for watching a tank's target.
- **me** — a cell for yourself, **out of the group grid**, so you are the same place solo, in a party and in a 40-man.
- **mana** — one short row per healer in the group, name and percent, you included.

> The game keeps another player's mana secret from addons, even out of combat. This addon never learns the number — it asks the game for the percentage and hands it straight to the screen.

## A buff to watch on the whole group

`/bish watch Lightning Shield` names a spell **you have trained**, and between pulls the header tells you when it is not up on anyone. `/bish watch off` stops it. Nothing is watched until you ask, and it never nags about a spell you do not have.

**It works in a dungeon, which is the point.** The buff is asked for by spell id rather than by reading a unit's whole list of auras — and by id is the one aura question this client still answers inside an instance, where listing auras is refused outright even between pulls.

**And it never reports a guess as a fact.** If the game is hiding a buff, that is "we cannot tell", not "it is not up". A hidden buff and a missing one look identical from here, and the difference matters when the addon is about to tell your raid something.

## BiS> now — the button for the moment you are in

A small block you can drag anywhere. Switch it on with `/bish now`.

It starts with one button: **help**. It is faint while you are well, warms to amber as your health drops, and goes solid red low down, with its outline following — and **the colour is chosen by the game**, from health this addon is never allowed to read. Click it to ping for help at yourself. On your corpse it keeps a dimmer, slower glow, so somebody looking to res you can find you.

More buttons arrive as you need them. Each earns its place the first time its moment happens, and the order learns: what keeps coming up drifts to the front, and help stays first.

**Your shield, live in a fight.** A shaman gets a **Water Shield** button (a priest Inner Fire, and so on: whatever `/bish buff` watches). Full charges: the plain icon. Two left: it washes **yellow**. One: **orange**. Gone: the icon pulses **red**. Click it to put the shield back, mid-fight too. Your own buffs are secret to addons in a fight, so the addon never looks — the game draws the icon and picks the colour.

**The next res, already aimed.** After a wipe, BiS> now carries your res with a name on it: the best person to get up next. Healers first, then priest, paladin, shaman, druid, mage, warlock, hunter, warrior, rogue. It skips anyone another healer is already ressing, anyone with a res on the way, and anyone who released. Click, and it moves on to the next. It is only there out of combat, while someone is down.

**Weapon oil.** With a mana or wizard oil in your bags, an **Oil** button appears wearing its icon. One click puts your best oil on your main hand. It is lit while the weapon has none and dims once it does. Hover it for what the oil gives, read from the game itself, and how long it has left.

**Buff buttons, for the group's buffs.** Type `/bish buffs` and BiS> now gets a button for each group buff you have trained: Power Word: Fortitude, Divine Spirit and Shadow Protection for a priest, Mark of the Wild and Thorns for a druid, Arcane Intellect for a mage. Your spellbook decides which, never your class, so a button turns up the day you train the spell.

- **Only when it is needed.** A button shows out of combat, while someone in reach is missing that buff or has under 5 minutes of it left. Everyone covered: it goes.
- **One click, the right person.** Missing it before running low, then tanks, then healers. Hover it to see who it is aimed at. Anyone AFK still gets the buff, but last.
- **The rank they can take**, so a low-level player doesn't get "Target is too low level".
- **Only in reach.** The game casts a buff on *you* when the person it was aimed at is out of range, and says nothing. So a button only aims at someone the game says you can reach, and looks again as people move.
- **Thorns on tanks, Intellect and Spirit on mana users.** Shadow Protection is off until you want it (`/bish buffs shadow on`); any of them can be switched off the same way.
- **Never a guess.** If the game is hiding someone's buffs, they count as "we cannot tell", not "missing". No button for a buff that might already be up.

Off by default. Paladins are left out on purpose: Pally Power does blessings.

## The header talks to you

**Out of combat, the buff you keep forgetting.** `no Water Shield`, right there — one per healing class to start with, and only if you have actually trained it. `/bish buff <name>` watches something else. With BiS> now switched on, its shield button shows this instead, live, so the header stays quiet about it.

**And a sound when it drops.** Your own buffs are secret to addons during a fight, so nothing can *look* — but the game will still make a noise for you. Switch it off in the options, or open the **sound id** drawer to put a different one in, with a **hear** button to try it.

**In a fight, the five second rule.** Spend mana and a bar drains across the header over the five seconds until your regeneration comes back: `regen 100%` between casts, `regen 62%` while they're ticking. The numbers come from your own character sheet.

> Honest about what it can't see: this client hides your own regeneration once a fight starts, so the header shows the last figure it was given, and says `regen ?` if it has never had one.

## Quiet by default

Nothing is written to your chat frame during normal play.

One exception, and it is there so you are never left guessing: on some PCs the game will not let an addon place the small aura markers on a cell. BiS Healing then leaves the markers out, draws every cell as normal, and says so **once**. `/bish auras` tells you why.

## Settings

Left-click the minimap button for your mouse binds, right-click it for the options — two columns, everything in it, also under **Esc > Options > AddOns > BiS> > BiS> Healing**, beside every other BiS addon you have.

**A new install starts quiet:** only the main job is on — the cells, your binds, cure boxes, your heals over time, click-a-dead-friend res and the gold ring. The mouse crosshair, the LOS flash, the buff-drop sound and the buff reminder start off, each one a switch away in the options. Already using it? Everything you had stays as it was.

Or type:

| command | does |
|---|---|
| `/bish` | the options window |
| `/bish mouse` | the mouse binds, and the ping chips |
| `/bish efficiency` | mana for mana: every rank of your heals, and which one to spam |
| `/bish clique` | let Clique handle the clicks, or take them back |
| `/bish trinkets shift both` | trinkets first on a modifier tab — `1`, `2`, `both`, `off` |
| `/bish now` | the BiS> now block |
| `/bish buffs` | the buff buttons in BiS> now — `on`, `off`, or one buff: `fort`, `spirit`, `shadow`, `mark`, `thorns`, `int` with `on` or `off` |
| `/bish cures` · `/bish res` | the cure boxes, and click-a-corpse-to-res: `on` or `off` |
| `/bish watch <spell>` | a buff to watch on the group — `off` stops it |
| `/bish target` · `/bish tot` · `/bish me` · `/bish mana` | the cells you can add |
| `/bish pets grid` · `own` · `off` | where pets go |
| `/bish buff Water Shield` | a buff on yourself: the shield button in BiS> now, or the header when that is off |
| `/bish buffsound` | the sound when it drops — an id, `off`, `on`, `default`, `test` |
| `/bish across` · `/bish grid` · `/bish pyramid` | groups across, down, or by role |
| `/bish missing` · `/bish percent` · `/bish number off` | the number on the cells |
| `/bish colour` · `/bish hots` · `/bish markers 14` · `/bish scale 90` | how it looks |
| `/bish ring me` · `/bish ring target` | the crosshair on you, or red on your target |
| `/bish hover on` · `off` | the white crosshair on whoever your mouse is on |
| `/bish dim 40` | how far out-of-range cells dim, 20 to 90 |
| `/bish center` · `/bish hide` · `/bish show` | where it is |
| `/bish scan` · `/bish range` · `/bish regen` · `/bish overheal` | what this client will tell me right now |
| `/bish byid` · `/bish ping` · `/bish curve` · `/bish control` · `/bish hits` | the same, in detail — for bug reports |
| `/bish keep` | what's saved in your `BiSHealing` macro |
| `/bish cpu` | which addons make your game hitch, and whether it is us |

## Why it works the way it does

Forever will not let an addon read another player's health. Or their auras, their mana, whether you can reach them. Inside a dungeon, not even between pulls. So BiS Healing never asks. It hands each number to the game, and the game draws it.

The bar, the missing number, the dimming, the dispel marker, the magenta overheal, all drawn by the game from numbers this addon never sees. That is why it keeps working in every fight. And why it will not rank people by damage taken. It cannot see it.

When it cannot tell, it says so. It does not guess.

It is also built to sit still. A cell is redrawn when the game says that person changed, not ten times a second for nothing. A quiet raid second used to cost 8,300 questions to the game. Now about 1,400.

## TBC

This is the Forever edition. In a TBC client it loads one line saying so and does nothing else — on purpose, so it can never touch an older BiS Healing's saved settings.
