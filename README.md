# BiS Healing

Click-cast healing cells for any healer, on a client that will not let an addon
read what it is drawing.

Drag a spell onto a picture of a mouse. Click a name. That is the addon.

## The client this is built for

On WoW Forever, an addon may not read a unit's health. The value comes back as a
*secret*: it can be stored, and handed to a status bar or a font string — the
client does the drawing — but arithmetic on it, comparison of it, even printing
it are all refused. Inside combat the same goes for auras, cooldowns and unit
stats. The combat log never fires at all.

So this addon does not measure anything. It hands the client numbers it never
looks at, and asks the client to draw the things it is not allowed to know:

| what you see | who works it out |
|---|---|
| the health bar | the client, from a value passed straight through |
| the green dispel marker | the client, which knows what **you** can cure |
| the click that casts | Blizzard's own secure code, from an attribute set out of combat |

An addon that cannot read the fight cannot rank it. What it *can* do is put
every spell you own under a button your hand already knows, and then get out of
the way.

## The mouse

Click the minimap button (the mouse binds are the first row), or `/bish mouse`.
A drawn mouse, and you drop a spell on the button you intend to press — left,
right, middle, two thumb buttons, wheel up and wheel down, times no modifier,
shift, ctrl and alt. Twenty-eight places.

Ranks are kept. Dropping rank 4 of a heal binds rank 4, because casting by bare
name always throws the biggest one you know, and for a healer that is three
times the mana to move the same bar.

Right-click a slot to clear it. Binds are written out of combat — the client
refuses them during a fight — so a change made mid-pull lands the moment it ends.

They are kept in a per-character macro called `BiSHealing`, because this client
does not hand an addon its saved settings back after a restart. So are the
settings below and where you dragged the grid. Do not rename it.

## The cells

One per person, one column per raid group. Not ranked: ranking means comparing
health, and that is exactly what this client will not allow.

- **The first name on the top line** ("Kumlust", not "Kumlust Surname"), up to
  the role icon in the corner.
- **A number on the bottom line**, on the right: what they still need after the heals already on
  their way, short (`3.2K`), blank at full health. Or a percentage, or nothing
  (`/bish missing`, `/bish percent`, `/bish number off`). The client works the
  number out and draws it; the addon never reads it.
- **Bars in class colour, or by health** (`/bish colour`): green, amber below
  70%, red below 35% — the client picks the colour from a curve we hand it. With
  health colours on, the names wear the class colour instead.
- A green pip when there is something on them **you** can take off, a dimmed
  cell when they are out of range of whatever is on your left button, and a role
  icon (the raid's Main Tank counts as a tank).
- Optional: a pyramid (`/bish pyramid`, tanks on top) and a size from 60% to
  160% (`/bish scale 90`).
- **Pets, three ways** (`/bish pets grid | own | off`): a column inside the main
  cells, a block of their own with a `BiS> pets` bar you can drag anywhere, or
  nowhere at all. Off to begin with.

### A cell for yourself

**`/bish me`**, or **me** in the cells row of the options window. You get one cell of your own
under a `BiS> me` bar — drag it anywhere, or shift-click the bar to send it round the grid — and
**you come out of the group grid**, so that spot is the same whether you are solo, in a party or
in a 40-man. `/bish me left` (or `right`, `top`, `under`) places it from the chat box, and where
you put it is remembered.

### The target block

**A cell for your target** (`/bish target`) gets a small header of its own —
`BiS> target` — which you drag to move it, or shift-click to send it round the
grid (top, right, under, left). **And their target** (`/bish tot`) adds a second
cell to the right of it under a `BiS> tot` bar. The two are attached: drag
either header and the pair moves together, and with no target at all both
disappear.

## The header

The bar above the cells is the handle you drag them by, and it says one thing at
a time.

- **Out of combat** it says what you have forgotten: `no Water Shield`. One buff
  per healing class to begin with — Water Shield, Inner Fire, Omen of Clarity,
  Blessing of Wisdom — and only if you have actually trained it. `/bish buff
  <name>` watches another, the same name again stops, `/bish buff reset` goes
  back to your class's own.
- **In a fight** it says how much mana you are getting: `regen 100%` between
  casts, and your while-casting share for the five seconds after you spend any,
  with a bar draining across the header as those seconds run out. The numbers
  come from the character sheet's own, so your talents and gear are already in
  them. This client hides your regeneration once the fight starts, so what you
  see is the last thing it would tell us; `regen ?` means it never has.
- **A sound when the buff drops**, played by the client itself — the only half
  of the reminder that works mid-fight, where your own buffs are secret. Switch
  it off in the options window, or put a different **sound id** in the drawer
  under it. `/bish buffsound off`, `on`, `default`, `test`, or a number.

## Everything else

`/bish`, or any click on the minimap button, opens one small window with all of
it. `/bish` with anything it does not recognise lists the rest.

Drag the header above the cells to move them; they stay there after a restart.
`/bish center` brings them back to the middle. "Show the cells" in the window
(or `/bish hide`, `/bish show`) takes them off the screen and back.

## What happened to the old addon

Until 19 September 2026 this was 5,000 lines built around one class and one
spell: a shaman's Chain Heal, ranked by who actually took damage, learned out of
the combat log, with heal-size prediction, a heal-race counter and an Earth
Shield tracker.

None of it can run on a client where health is secret and the combat log never
fires — so it was tagged rather than switched off:

```
git checkout tbc-final
```

It is not deleted because it was wrong. It is parked because the game it was
written for is not the game being played.
