---
toc: Magic In Pathfinder 2e
summary: Commands used to cast spells.
aliases:
- cast
- casting
- spellcasting
---

# Casting Spells in Pathfinder 2e

You cast spells in an encounter, using what your last rest there gave you: the day's spell slots, your Focus Points, and your innate spells' uses. You can't cast spells outside an encounter. See "Spells" in `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions) for how the game resolves a spell.

`encounter/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>][/<how>]`: Casts a spell in the encounter.
%t **Examples**:
%t `encounter/cast fear=#3`
%t `encounter/cast glitterdust=#3,#4/rank 2`
%t `encounter/cast lay on hands=Bram/focus`
%t `encounter/cast daze=#2/innate`

**Key**:
`<spell>`: The spell's name.
`<target>`: The combatant you're casting the spell at, by ID or name. Separate several targets with commas.
`rank <n>`: The rank to cast the spell at, if it can be heightened. Without a rank, the game casts the spell at its base rank.
`class <class>`: Which of your casting classes casts the spell, if you have more than one.
`<how>`: The kind of casting: `focus` for a focus spell, `focusc` for a focus cantrip, `signature` for a signature spell at a higher rank, or `innate` for an innate spell.

## Casting spells on items

`encounter/cast <spell>=<target>/<item>`: Casts a spell, such as Runic Weapon or Shillelagh, on one of the target's items (`<item>`), by the item's name or nickname.
%t **Examples**:
%t `encounter/cast runic weapon=Bram/longsword`
%t `encounter/cast runic weapon=Bram/longsword/rank 6`
%t **Note:** You can leave the item out if the target has exactly one equipped item the spell can affect.

## Casting spells with choices

Some spells ask for choices, such as which damage type Resist Energy resists. Specify your choice after the target you're specifying, such as `encounter/cast resist energy=Bram/fire`.

## Untamed Form

`encounter/cast untamed form/focus/<shape>`: Turns you into a shape on your *untamed form* list, and only changes you.
%t **Examples**:
%t `encounter/cast untamed form/focus/bear`
%t `encounter/cast untamed form/focus/air`
%t `encounter/cast untamed form/focus/forest dragon`

Omit the shape after `/focus/` to see the shapes you can select with Untamed Form. The spell isn't deducted from your focus points unless you specify a shape you can take at the spell's rank. Pest shapes last 10 minutes, and all others last 1 minute.

With Dragon Shape, add the resistance you want for any shape but a dragon: `encounter/cast untamed form/focus/bear/poison`.

You can't cast spells in a battle form, so the game refuses casting spells while you're in any form, including a shape from an earlier *untamed form*. To end your shape, use `encounter/act dismiss/untamed form`. To end a form from something else, use `encounter/act dismiss/<effect>` if that form allows it, or ask your GM to get rid of the effect.

## Slots for Certain Spells

Divine Evolution, Primal Evolution, and Gifted Power each give you one extra slot a day at your highest rank, which can only cast certain spells, even ones not in your repertoire. `magic` lists the slot and its spells.

If you cast one of those spells at your highest rank, the game uses the feat's slot first. If you leave the rank off, a spell you couldn't otherwise cast uses the feat's slot at your highest rank, while a spell in your repertoire is cast at its own rank from a normal slot.

## Refocusing

`encounter/refocus`: Performs the Refocus activity in the encounter. See `help rest` or [read it on the web](/help/pf2e_daily).
