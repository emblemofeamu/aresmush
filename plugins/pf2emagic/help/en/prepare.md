---
toc: Magic In Pathfinder Second Edition
summary: Preparing spells.
aliases:
- prepare
- unprepare
- prepared
---

# Preparing Spells in Pathfinder Second Edition

Some classes record spells and cantrips in a spellbook, or otherwise 'prepare' spells for the day.

**Important!** After preparing spells, input `rest` to refresh your spells and make them available for casting. See `help rest` for more information.

**Commands**:
`prepare <caster class>/<level> = <spell name>`: Prepares `<spell name>` at the defined level, optionally at a higher `<level>` than its default level. Preparing at a higher level than a spell's base level heightens the spell to that level. (You can't prepare a spell lower than its default level.) Omitting the `<level>` switch will prepare the spell at its base level.
`unprepare <caster class>/<level> = <spell name>`: Removes `<spell name>` at the defined `<level>` from your prepared list.
`prepare <caster class>/<cantrip> = <spell name>`: Prepares the cantrip `<spell name>`.
`unprepare <caster class>/<cantrip> = <spell name>`: Removes the cantrip `<spell name>` from your prepared list.
`prepared [<caster class>]`: Shows your currently prepared spell list. If `<caster class>` is omitted, it will show you all spell lists. 

## Preparing sets of spells

Prepared casters may also choose to prepare standard sets, or many spells at once.

**Commands**:
`spellset/add <set name> = <spell name>/<level>`: Adds a spell to a set with name `<set name>`. `<set name>` may contain spaces or special characters except for = or /. If `<set name>` does not exist, this command will create it, otherwise it will add that spell to the list.
`spellset/list [<set name>]`: If `<set name>` is provided, shows the prepared spells in set `<set name>`. If not, shows a list of available sets. 
`spellset/clear <set name>`: Deletes the set `<set name>`.
`spellset/rem <set name> = <spell name>/<level>`: Removes `<spell name>` from set `<set name>`.
`spellset/ready <set name>`: Clears all existing prepared spells and replaces it with the contents of `<set name>`.