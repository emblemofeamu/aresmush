---
toc: Magic In Pathfinder 2e
summary: Commands used to cast spells.
aliases:
- cast
- refocus
- casting
---

# Casting Spells in Pathfinder 2e

Casting a spell in Pathfinder 2e depends on what type of spell it is. Spellcasters, both prepared and spontaneous, cast spells from their daily allotment of spells. Some characters who are not technically spellcasters may have certain spells available to them as innate spells granted by a feat or by ancestry, and/or may have focus spells granted by their class or by a feat.

## Casting Spells and Cantrips
**Commands:**
`cast <casting class>/<level> = <spell name>/<target>`

`<casting class>`: The character class associated with the spell.
`<level>`: The level associated with the spell. This switch is optional, although omitting the switch will default the spell's casting to its default level. `0` can be interchanged with `cantrip`.
`<spell name>`: The spell name associated with the spell.
`<target>`: The target(s) of the spell. This switch is optional.

For example, inputting `cast sorcerer/2=Glitterdust/Sandy` will cast a sorcerer's level 2 Glitterdust spell at Sandy.

## Casting Focus Spells and Cantrips
**Commands**:
Focus cantrip: `cast/focusc <casting class> = <spell name>/<target>`
Focus spells: `cast/focus <casting class> = <spell name>/<target>`

`<casting class>`: The character class associated with the spell.
`<spell name>`: The spell name associated with the spell.
`<target>`: The target(s) of the spell. This switch is optional.

## Casting Signature Spells
**Commands:**
`cast/signature <casting class>/<level> = <spell name>/<target>`

`<casting class>`: The character class associated with the spell.
`<level>`: The level associated with the spell. This switch is optional, although omitting the switch will default to casting the signature spell at your highest available spell slot.
`<spell name>`: The spell name associated with the spell.
`<target>`: The target(s) of the spell. This switch is optional.

## Casting Innate Spells and Cantrips
**Commands:**
`cast/innate <tradition>/<level>=<spell name>/<target>`

`<tradition>`: The tradition associated with the spell.
`<level>`: The level associated with the spell. This switch is optional, although omitting the switch will default the spell's casting to its default level. `0` can be interchanged with `cantrip`.
`<spell name>`: The spell name associated with the spell.
`<target>`: The target(s) of the spell. This switch is optional.

For example, inputting `cast/innate primal/2=Glitterdust/Sandy` will cast a level 2 innate spell Glitterdust at Sandy.

## Refocusing
**Commands:**
`refocus`: Runs the code for the Refocus activity. This may be done only if your focus pool is zero, and then only once an hour in OOC time.

Admins can refocus a character by inputting `refocus <character>`. Admins may do this at any time, without time or pool size restrictions. 