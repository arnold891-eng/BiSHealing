# BiS Healing

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
