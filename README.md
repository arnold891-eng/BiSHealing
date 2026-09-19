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

`/bish mouse`, or the minimap button. A drawn mouse, and you drop a spell on the
button you intend to press — left, right, middle, two thumb buttons, wheel up
and wheel down, times no modifier, shift, ctrl and alt. Twenty-eight places.

Ranks are kept. Dropping rank 4 of a heal binds rank 4, because casting by bare
name always throws the biggest one you know, and for a healer that is three
times the mana to move the same bar.

Right-click a slot to clear it. Binds are written out of combat — the client
refuses them during a fight — so a change made mid-pull lands the moment it ends.

## The cells

One per person, in group order. Not ranked: ranking means knowing who is losing
health, and that is exactly what this client will not say.

A name, a bar the client fills, a green pip when there is something on them
**you** can take off, and a dimmed cell when they are out of range of whatever is
on your left button.

## Everything else

`/bish` opens a small window, and the minimap button has the same things behind
it. `/bish` with anything it does not recognise lists the rest.

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
