# BiS Healing — CurseForge page text (0.8.2)

Paste everything below the line into the project description
(CurseForge → BiS Healing, project 1703250 → Edit → Description).

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

Drag a spell onto a picture of a mouse. Click a name. That's the addon.

## Your mouse, or Clique — your choice

**Use ours:** click the minimap button (mouse binds are the first row) or type `/bish mouse`. You get a drawn mouse: drop a spell on the button you want to press. Left, right, middle, two thumb buttons, wheel up and wheel down, each with no modifier, Shift, Ctrl or Alt: 28 places.

- **Ranks are kept.** Drop Rank 4 and you get Rank 4, not the biggest one you know — the same bar for a third of the mana. Click the little number on a slot to step through your ranks.
- **Anything not bound targets the unit.** Leave a button empty and clicking a name selects them, like Blizzard's own frames.
- **Right-click a slot** to clear it.

**Already use Clique?** Keep it. Tick **"let Clique handle clicks"** (or `/bish clique`) and BiS Healing steps aside entirely. Untick it and your own binds are back.

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
- **Bars in class colour — or coloured by health**: green, amber below 70%, red below 35%.
- **The dispel marker shows what it is**: magic, curse, poison or disease, in the game's own icon, when there's something on them *you* can remove.
- **Your heals over time, with a countdown**: Renew for priests, Rejuvenation and Regrowth for druids, and **Riptide for shamans** — only your own casts, every rank. Each is found by name in your own spellbook, so it appears the day you train it and never before.
- **Marker size**, 6 to 20 pixels.
- **Dimmed when they're out of range** of what your mouse would cast — **including during a fight**, which is when you need it. The game keeps "can you reach them" secret in combat, so it is handed back to the game to pick the brightness from; the addon never learns who is reachable.
- **Role icons**, and the raid's Main Tank counts as a tank.
- **A pyramid** (`/bish pyramid`): tanks on top, then damage, healers at the bottom. Melee sit above casters inside each band, and the bottom rows go half-width so a 40-man still reads as a pyramid.
- **Size**: 60% to 160%. **Put it anywhere** — drag the header above the cells.

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

## The header talks to you

**Out of combat, the buff you keep forgetting.** `no Water Shield`, right there — one per healing class to start with, and only if you have actually trained it. `/bish buff <name>` watches something else.

**And a sound when it drops.** Your own buffs are secret to addons during a fight, so nothing can *look* — but the game will still make a noise for you. Switch it off in the options, or open the **sound id** drawer to put a different one in, with a **hear** button to try it.

**In a fight, the five second rule.** Spend mana and a bar drains across the header over the five seconds until your regeneration comes back: `regen 100%` between casts, `regen 62%` while they're ticking. The numbers come from your own character sheet.

> Honest about what it can't see: this client hides your own regeneration once a fight starts, so the header shows the last figure it was given, and says `regen ?` if it has never had one.

## Quiet by default

Nothing is written to your chat frame during normal play.

One exception, and it is there so you are never left guessing: on some PCs the game will not let an addon place the small aura markers on a cell. BiS Healing then leaves the markers out, draws every cell as normal, and says so **once**. `/bish auras` tells you why.

## Settings

Any click on the minimap button opens one small window with everything in it. Or type:

| command | does |
|---|---|
| `/bish` | the options window |
| `/bish mouse` | the mouse binds, and the ping chips |
| `/bish clique` | let Clique handle the clicks, or take them back |
| `/bish now` | the BiS> now block |
| `/bish watch <spell>` | a buff to watch on the group — `off` stops it |
| `/bish target` · `/bish tot` · `/bish me` · `/bish mana` | the cells you can add |
| `/bish pets grid` · `own` · `off` | where pets go |
| `/bish buff Water Shield` | a buff on yourself the header reminds you about |
| `/bish buffsound` | the sound when it drops — an id, `off`, `on`, `default`, `test` |
| `/bish across` · `/bish grid` · `/bish pyramid` | groups across, down, or by role |
| `/bish missing` · `/bish percent` · `/bish number off` | the number on the cells |
| `/bish colour` · `/bish hots` · `/bish markers 14` · `/bish scale 90` | how it looks |
| `/bish center` · `/bish hide` · `/bish show` | where it is |
| `/bish scan` · `/bish range` · `/bish regen` | what this client will tell me right now |
| `/bish byid` · `/bish ping` · `/bish curve` · `/bish control` · `/bish hits` | the same, in detail — for bug reports |
| `/bish keep` | what's saved in your `BiSHealing` macro |

## Why it works the way it does

On WoW Forever, addons aren't allowed to read other players' health, auras, mana, or even whether you can reach them — and inside a dungeon or raid, not even between pulls. BiS Healing never tries to. It hands the numbers to the game and lets the game draw them: the health bar, the missing-health number, the health colours, the dispel type, the heal-over-time countdown, another healer's mana, the dimming when someone is out of range, the red on an enemy, the sound when your own buff drops, and the colour of the help button.

That's why it keeps working in every fight — and why it doesn't rank people by damage taken: ranking would mean reading what the game keeps hidden.

It is also why, when this addon cannot tell, it says so instead of guessing.

## TBC

This is the Forever edition. In a TBC client it loads one line saying so and does nothing else — on purpose, so it can never touch an older BiS Healing's saved settings.
