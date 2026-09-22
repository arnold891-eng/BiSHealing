# BiS Healing

## 0.4.1

- **A mouse button with nothing on it targets the person.** Clear a slot in the mouse binds window
  and clicking that button on a cell selects them, the way Blizzard's own frames do - with any
  modifier, and in combat too. Buttons with a spell on them cast as before. The mouse wheel is
  unchanged.

## 0.4.0

- **The dispel marker shows what it is.** When someone has something you can remove, the small
  marker on the left of their cell now shows the kind - magic, curse, poison or disease - as the
  game's own icon, instead of a plain green square. The game draws it, so it works in combat.
- **Your heals over time on each cell.** A small icon for each one you have cast on that person,
  bottom left, with the game's countdown sweep over it: Renew for priests, Rejuvenation and
  Regrowth for druids. Only your own casts, every rank. `/bish hots` turns them off or on, and the
  setting survives a restart.
- **Fixed: an error after pulls in dungeons.** The between-fights check (missing Earth Shield, no
  totems, someone dead) read your totems while the game was still hiding them. It now asks the game
  first, and never says something is missing when it simply cannot tell.
- **Fixed: "BiS Healing tried to call a protected function" when pressing a key** with the mouse
  binds window open during a fight.
- **Fixed: a hidden player name could have broken the grid.** It is shown in full instead.

## 0.3.3

- **Fixed: "show the cells" did nothing.** Switching it off hid the cells for a moment and the
  game put them straight back. Now they stay hidden - header and all - until you switch them on
  again from the minimap button, the options window or `/bish show`.
- **The grid stays where you put it.** It used to go back to the middle of the screen at every
  login, because this client forgets addon settings when it restarts. Where you dragged it, and
  whether the cells are hidden, are now kept in the `BiSHealing` macro with your binds.
  `/bish center` still puts it back in the middle.

## 0.3.2

- **Names and the health number on separate lines.** The name has the top of the cell to itself
  and the number sits bottom-right, so a long name is no longer cut short to make room.
- **First names only.** A character with a surname showed as "Kumlust S"; now it is "Kumlust".
  Names up to 12 letters fit.

## 0.3.1

- **Fixed: "BiS Healing tried to call the protected function TogglePVP()".** Typing `/pvp` - or
  any other game command that needs special permission - could be blocked, with BiS Healing
  named as the culprit. The addon had written to the game's own list of slash commands, which made
  the game treat every command typed in chat as coming from BiS Healing. It no longer touches that
  list.

- **Missing health is shorter, and counts heals already on the way.** `3.2K` instead of `3247`,
  still blank at full health. A heal that is already landing comes off the number, so two healers
  stop filling the same gap.

- **Or a percentage instead**: `87%`. Choose `lost`, `%` or `off` under "number" in options, or
  `/bish missing`, `/bish percent`, `/bish number off`.

- **Bars coloured by health, if you want it** - green, then amber below 70%, red below 35%. The
  names take their class colour instead, so you still know who is who. Class-coloured bars stay the
  default. Options, or `/bish colour`.

- **Both settings survive a restart**, kept in the `BiSHealing` macro beside your binds and the
  size of the cells.

- **One click on the minimap button.** Left and right click both open the options window now - the
  small menu is gone, since everything in it was already in the window. **Mouse binds are the
  first row.**

## 0.3.0

- **Missing health on every cell, blank at full.** How much each person needs, on the right of
  their cell - and nothing at all when they are topped up, so a full raid is quiet and a hurt one
  stands out. Someone else's health is hidden from addons on this client even out of combat, so
  the game works the number out and draws it; the addon never sees it. Switch it off in options or
  with `/bish missing`.

- **The grid really is by group now.** One column per raid group, in group order. It used to fill
  columns in the order people *joined*, which only looked grouped when they had joined in order.

- **A pyramid, if you want one.** Tanks on top, then healers, then damage - an apex, a pair, then
  rows of six. The raid's **Main Tank** counts as a tank even with no role set, which is how most
  Classic raids mark one. It rearranges only between fights; the game will not move the cells
  mid-pull. Off by default - switch it on in options, or `/bish pyramid`.

- **Size of the cells**, 60% to 160%, in options or `/bish scale 90`. The grid stays where you put
  it when you resize it. **It survives a restart** - it is kept in the `BiSHealing` macro beside
  your binds, since this client forgets addon settings at every login. Macros made by 0.1.0 and
  0.2.0 still read exactly as before.

- **Pets, if you want them** - a column of their own, so a raid full of hunters does not push a
  player off the bottom. Off by default; options or `/bish pets`.

- **It does nothing at all in a TBC client**, on purpose. It used to load there, and on 20 Sep it
  emptied an older BiS Healing's saved history in one logout. A TBC client now loads a single line
  saying this is the Forever edition, and nothing else - whether or not "Load out of date AddOns"
  is ticked.

## 0.2.0

- **It will not throw away another addon's saved data.** This addon's TOC claims TBC as well as
  Forever, so it loads in a TBC client - and there it found the old BiS Healing's saved table,
  did not recognise the version, and cleared it: four thousand fight records in one logout. A
  version bump is a promise about the keys THIS addon owns, not a licence to empty a table it
  happens to share. Anything it does not recognise is set aside now, intact, under `attic`.

- **The grid sits above your action bars** instead of among them, so it is not buried by the rest
  of your interface - and the header you drag it by comes with it.

- **`/bish center` actually centres.** It used to put the grid 260 left and 120 down, which on a
  lot of screens is straight into the action bars: the one command you type when you cannot find
  the window put it somewhere you still could not find it.

- It asks the client whether a value is hidden rather than finding out by being refused, and it
  no longer trusts the shape of the answer - on this beta, even "is anything secret?" can come
  back as something you are not allowed to read.

## 0.1.0

Click-cast healing cells for any healer, on a client that will not let an addon read what it is
drawing.

Drag a spell onto a picture of a mouse. Click a name. That is the addon.

- **Tank, healer and damage icons on the cells**, in the top right, so a party frame tells you who
  is holding the thing before you decide where the heal goes. Hidden for anyone with no role set,
  which is most of a levelling group, and hidden rather than guessed at while the client is hiding
  the numbers in combat.

- **Your binds are kept in a macro, because this client loses saved variables.** The Forever beta
  writes every addon's saved file at logout and hands back nothing at the next start - yours,
  ours, and everyone else's. Macros live on the server and do come back, so that is where the
  binds go: one per-character macro called `BiSHealing`, which you can see and should not rename.
  It is inert - clicking it casts nothing - and no other macro is ever touched. If your macro
  list is full it says so rather than failing quietly.

- **A mouse you bind by dragging.** Left, right, middle, two thumb buttons, wheel up and wheel
  down, times no modifier, shift, ctrl and alt — twenty-eight places to put a spell. Ranks are
  kept: dropping rank 4 of a heal binds rank 4, and clicking the little rank number in the corner
  of a slot walks the ranks you have actually trained. Casting by bare name always throws the
  biggest one you know, which for a healer is three times the mana to move the same bar.
- **Cells in group order.** A name, a bar the client fills, and a dimmed cell when someone is out
  of range of whatever is on your left button.
- **A green pip when there is something on them you can cure** — the client decides what that
  means for your class, so it is right for a priest, a paladin and a druid without being told.
- **An incoming-heal bar**, carrying on from where the health fill ends, so you can see a heal
  already on its way before you start your own.
- **A minimap button** with everything behind it, and a small options window with the same things.

**What it does not do: rank anyone.** Ranking means knowing who is losing health, and on this
client health is a secret value — it can be handed to a bar for the client to draw, but never
read, compared or printed. An addon that cannot read the fight should not pretend to judge it.

Works on any healer. Tested on a shaman.
