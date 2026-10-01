# BiS Healing

## 0.7.2

- **Fixed: nobody was ever dimmed for being out of range.** The game was asked with the spell's
  *name*, and for a spell it cannot range-check it answers "don't know" — which was being read as
  "in range", so the whole raid stayed bright. It now asks with the spell's id, falls back to the
  name, and then to asking about the unit instead of the spell. `/bish range` says which of those
  answered.
- **Melee up top, casters at the bottom.** Inside each role, so tanks still hold the apex and
  healers still hold the base — it decides the order of everyone in between, where a raid's melee
  and casters mix. Melee stand in whatever the boss is doing, so they belong where your eye is.
- **A gold frame around you, a yellow one around the other healers.**

## 0.7.1

- **The pyramid has a proper shape.** Rows three and four hold four cells each, and every row below
  them holds eight at half that width — so a 40-man reads as a pyramid instead of six-wide rows
  that overhung the pair above them. Every row now divides exactly the same span.
- **Cells say DEAD and OFFLINE**, where the health number goes. How much health a corpse is missing
  is not a question anybody has.

## 0.7.0

- **Enemies no longer look like friendlies.** The target cell and its tot go red for anything you
  can attack — which matters because those two cells cast on hostile units perfectly well, whether
  or not that was ever the plan. In combat the game keeps "can you attack this" secret, so the
  colour is chosen by the game from an answer the addon never reads.

- **The other healers' mana.** Switch on **mana** in the options window's cells row, or
  `/bish mana`, and a small block appears with one row per healer in your group — name and
  percent, you included. Drag its `BiS> mana` bar anywhere; it takes a side the other blocks are
  not using, and it is remembered.
- This was written off as impossible in this addon's own notes for eleven days: the game keeps
  another player's mana secret, even out of combat. That is true about *reading* it. The game will
  still *draw* it — so the number goes straight from the game to the screen and the addon never
  learns it. Thanks to EllesmereUI, whose party frames do the same thing and proved it could be
  done.

## 0.6.2

- **Out-of-range cells dim during a fight now** — which is when you need to know. The game keeps
  "can you reach them" secret in combat, so the dimming has only ever worked between pulls. It now
  asks the game to pick the brightness from the answer, without ever reading it. If the game
  refuses, cells stay bright, exactly as before.
- **`/bish range`** says what the game answered and what the grid did with it, for when the
  dimming looks wrong.

## 0.6.1

- **Fixed: `/bish scan` could say "Earth Shield is not up on anyone" when the game had simply
  refused to answer.** The aura list can be closed to addons inside instances — even out of
  combat — and a refusal was being read as "there are no buffs on anybody". A question the game
  will not answer is now reported as unknown, never as missing.

## 0.6.0

The last release on CurseForge was 0.5.2, so this one also carries everything in
0.5.3, 0.5.4 and 0.5.5 below: a **cell for yourself** out of the group, the buff
reminder learning to ask the game about **one buff at a time** (which may let it
work during a fight), and a fix for the options window throwing errors.

- **Two blocks never share a side.** Switch on a cell whose place is already taken by another and
  it goes to the next free side instead of drawing over it. Shift-clicking a bar round the grid
  skips the sides in use, too. Whatever was there first keeps its place.
- **Pets have three settings**, in the options window and on `/bish pets`:
  - **grid** — a column of their own inside the main cells, which is what "pets on" always meant.
  - **own** — a block of their own, with a `BiS> pets` bar: drag it anywhere, and nothing but pets
    in it. Asked for by paszczyszyn: "separate pet group ... able to move it alone".
  - **off** — nowhere. Still what a new install gets.
- **Fixed: the pet setting was forgotten at every login.** It has never been kept in your
  `BiSHealing` macro, for as long as the option has existed. It is now, along with where the pet
  block sits.

## 0.5.5

- **Fixed: opening the options window threw five errors** and the cells row came out uncoloured.
  The colour was being read in a way that kept only its red and dropped the green and blue, and
  the game refuses a colour with a hole in it. 0.5.4 only.

## 0.5.4

Asked for by paszczyszyn on CurseForge - thank you.

- **A cell for yourself, out of the group.** "Lock yourself in one spot outside groups ... and have
  it in same spot for solo or raid groups." Switch on **me** in the options window's cells row, or
  `/bish me`. You get a cell with a `BiS> me` bar of its own: drag it anywhere, or shift-click the
  bar to send it round the grid. **Turning it on takes you out of the group grid**, which is the
  whole point - a spot that moves when the group changes is not a spot you can learn. Where you put
  it is remembered, like everything else.
- **The options window has one cells row now**, with four switches on it: target, tot, me and pets.
  It replaces three separate rows, so the window is shorter than it was before any of this.

## 0.5.3

- **The buff reminder asks the game about one buff, by spell id.** It used to read every aura slot
  on you and compare names - and a name is the first thing this client hides, so one hidden buff
  anywhere in your list made the whole answer "cannot say". Now it asks about the buff it is
  watching and nothing else.
- **Which means it can work during a fight.** The old question was "are auras secret right now?",
  and inside a fight the answer is always yes. The new one is asked per spell: where the game will
  still answer about your shield mid-pull, the header is current rather than frozen at the last
  thing it knew. Where it will not, nothing changes - and it never reports a buff as missing on a
  silence.
- **Each watched buff remembers its own last answer** instead of the whole list being kept or
  thrown away together.
- Fixed: a game that refused the aura list outright was read as "you have no buffs at all", which
  would have reported every watched buff missing at once.

## 0.5.2

- **Fixed: the header's word was cut off on a party grid.** One group down is one
  cell wide, and "BiS> regen 62%" came back from the client as "BiS> regen ..." -
  it trims from the right, so the part it threw away was the number. On a bar
  that narrow the header now says `BiS> 62%`, and `BiS> no WS` for a missing
  buff; hovering it spells out the whole thing. A wider grid says it in full, as
  before.

## 0.5.1

The header above the cells does the talking now, and the chat frame stops.

- **The five second rule, on the header.** Spend mana and a bar drains across it
  over the five seconds until your regeneration comes back, with the share you
  are getting meanwhile: `regen 100%` between casts, `regen 62%` while they run.
  The numbers are the character sheet's own, so talents, gear and buffs are
  already in them. This client turns your own regeneration secret the moment a
  fight starts, so the header shows the last thing it was willing to say - and
  `regen ?` when it never has.
- **The buff you keep forgetting.** Out of combat the header says `no Water
  Shield` - one buff per healing class (Water Shield, Inner Fire, Omen of
  Clarity, Blessing of Wisdom), and only if you have trained it. `/bish buff
  <name>` watches another, the same name again stops watching it.
- **And a sound when it drops**, played by the client itself, which is the only
  half that works in a fight: your own buffs are secret there, so nothing can
  look - but the game will still make a noise. **sound when it drops** in the
  options window switches it off, and **sound id -> change** unrolls a drawer to
  put a different one in, with a `hear` button to try it first. `/bish buffsound
  off`, `on`, `default`, `test`, or a number. It rides in your `BiSHealing`
  macro with the other settings, so it survives a restart.
- **The target cell has a header now**, `BiS> target`, instead of a blank little
  bar: drag it to move the cell, shift-click it to send it round the grid.
- **And a cell for your target's target**, beside it, with a `BiS> tot` bar of
  its own — **and their target** in the options window, right under the target
  one, or `/bish tot`. The two are attached: drag either header and the pair
  moves together, and with no target at all both go away.
- **The between-pulls reminders in chat are off.** They were written for a TBC
  shaman with four totems to keep up and say less than that here. `/bish scan`
  still asks outright, and `/bish between` turns them back on.
- The options window lost **look at the group again** to make room: the cells
  rescan whenever the group changes anyway, and `/bish rescan` still presses it.

## 0.5.0

Three of these came from paszczyszyn on CurseForge - thank you.

- **Groups across or down.** A raid group can be a column of names, as before, or a row of them.
  In options: **groups: down / across / tanks**. Or `/bish across`, `/bish grid`, `/bish pyramid`.
- **A cell for whoever you have targeted.** Off by default; switch it on in options or with
  `/bish target`. It sits above the grid, and it has its own small handle: **drag it anywhere on
  screen**, or **shift-click the handle** to send it round the grid - top, right, under, left.
  `/bish target left` (or `right`, `top`, `under`) does the same from the chat box.
- **The markers have a size.** The dispel marker and the heal-over-time icons, 6 to 20 pixels:
  the **marker size** stepper in options, or `/bish markers 14`.
- **The pyramid puts healers at the bottom**: tanks first, then damage, then the healers.
- **Empty mouse buttons all target now.** Left and right click already did; the wheel click and
  the two thumb buttons do as well, with or without a modifier.
- Everything above is kept in your `BiSHealing` macro, so it survives a restart.
- The options window lost its two diagnostic rows to make room. Both are still one word away:
  `/bish scan` and `/bish auras`.

## 0.4.4

- **Wheel click and thumb buttons target when unbound.** Left and right click already selected the
  person when nothing was on them; the wheel click and the two thumb buttons did nothing. Now every
  empty mouse button targets, with or without a modifier.

## 0.4.3

- **Fixed: mouse binds being wiped.** Two bugs, one symptom:
  - The `BiSHealing` macro that keeps your binds was being made in **General Macros**, shared by
    every character on your account - so your druid and your priest overwrote each other's binds.
    It is now made in each character's own tab, so every healer keeps their own.
  - At login the addon could save before it had read your macro back, and write an empty mouse
    over your real binds. It now waits until it has read the macro before it writes anything.
- **Moving over is automatic.** The first time each character logs in, its binds are read from the
  old shared macro and written into its own. The old one in General Macros is left alone - delete
  it whenever you like. `/bish keep` shows which one is in use.

## 0.4.2

- **Clique users: let Clique handle the clicks.** A new switch in options, "let Clique handle
  clicks" (or `/bish clique`), hands every click, key and wheel turn on the cells to Clique, and
  BiS Healing's own mouse binds step aside - one owner, so the two never fight over a click. Switch
  it off and your BiS Healing binds are back. The setting survives a restart.
- **The mouse binds window says it:** "anything not bound targets the unit".
- "Test the debuff marker" left the options window to make room; `/bish auras` still does it.

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
