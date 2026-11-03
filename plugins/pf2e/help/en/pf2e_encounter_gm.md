---
toc: Pathfinder Second Edition
summary: Acting for creatures and undoing changes in an encounter, for the GM.
aliases:
- encounter_gmactions
- encounter gmactions
---
# Pathfinder 2E Encounters - GM Actions

These commands are for the GM of an encounter. For starting and running the encounter itself, see `help encounter_runner` or [read it on the web](/help/pf2e_encounter_runner). For what each creature's stat block does, see `help encounter_creatures` or [read it on the web](/help/pf2e_encounter_creatures).

## Acting for creatures

`encounter/as <combatant>=<act|strike|cast|enter|leave> <what>`: Acts for a creature, or for anyone else in the encounter, using the same commands players use. See `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions).
%t **Examples**:
%t `encounter/as #3=strike aria`
%t `encounter/as #3=strike aria=shortbow/range 2`
%t `encounter/as #5=act demoralize=aria`
%t `encounter/as #6=cast fear=aria`

Use a creature's abilities by name: `encounter/as #3=act goblin scuttle`. The game applies the rules of a creature's abilities on its own, such as a bonus to its saves, extra damage on a Strike, fast healing, or an aura you place with `encounter/as #3=enter <aura>=<ids>`.

A creature can use the basic actions anyone can (Stride, Trip, Demoralize, Raise a Shield, and so on), its own abilities, and the spells its stat block lists. To have it use another action or cast another spell, add `/force`: `encounter/as #3=cast force barrage=aria/force`. A spell cast this way is cast at the creature's highest rank, which is half its level rounded up, unless you add `/rank <n>`.
%t **Note:** A creature with no spell attack bonus on its stat block can't roll a spell attack, so you roll it. A creature with no spell DC can't set one for a save, so you set it.

A player character in a battle form can't cast spells, use a shield, or use manipulate actions, unless the form has hands. If you rule they can do a specific action regardless of these restrictions, use the action for them with `/force` at the end of the command, such as `encounter/as aria=act interact/force`.

When an ability's text gives its damage and save, such as Constrict or a breath weapon, the game rolls each target's save and deals the damage as a basic save: `encounter/as #6=act magma breath=#1,#2,aria`. You apply anything else in the ability's text.

When a creature's Strike lists Grab, Knockdown, or Push, a hit tells you so and gives you the command to use, such as `encounter/as #3=act knockdown=#1`. Each one is a separate Grapple, Trip, or Shove that doesn't use or add to the multiple attack penalty. The Improved version is a free action.

`encounter/option <combatant>=<option>[/on|off|default]`: Turns a circumstance from a creature's own rules on or off, such as Air Scamp's fast healing that only works in open air. Each circumstance is on until you turn it off. With no option named, this lists the creature's options.

Only you see a creature's turn reminder and its hit points after it takes damage.

## Undo and redo

The game records every change in an encounter in its history, and the GM can undo and redo changes one at a time. Nothing is rerolled: redoing a change brings back exactly what happened.

`encounter/undo`: Undoes the last change in the encounter. Only the GM can use this.
`encounter/redo`: Redoes the last change the GM undid. Any new change clears the changes that can be redone.
`encounter/history [<encounter id>]`: Lists every change in the encounter, and marks the current undo and redo point.
%t **Note:** Once an encounter ends, its history can't be changed.

## Cover and concealment

To set cover and concealment, or to let a player set them with `encounter/trust`, see `help encounter_cover` or [read it on the web](/help/pf2e_encounter_cover).
