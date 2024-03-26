---
toc: Magic In Pathfinder Second Edition
summary: Preparing spells.
aliases:
- prepare
- unprepare
- prepared
---

# Preparing Spells in Pathfinder Second Edition

Some classes are required to, or may wish to, record spells in a spellbook.

`prepare <caster class>[/<level>] = <spell name>`: Prepares `<spell name>` at `<level>`. Preparing at a higher level than a spell's base level heightens the spell to that level. See the PRD rules on heightening for how this works.
`unprepare <caster class>[/<level>] = <spell name>`: Removes `<spell name>` from your prepared list.
`prepare <caster class>/<cantrip> = <spell name>`: Prepares the cantrip `<spell name>`.
`unprepare <caster class>/<cantrip> = <spell name>`: Removes the cantrip `<spell name>` from your prepared list.
`prepared [<caster class>]`: Shows your currently prepared spell list. If `<caster class>` is omitted, it will show you all spell lists. 

Prepared casters may also choose to prepare standard sets, or many spells at once.

`spellset/add <set name> = <spell name>/<level>`: Adds a spell to a set with name <set name>. <set name> may contain spaces or special characters except for = or /. If <set name> does not exist, this command will create it, otherwise it will add that spell to the list.
`spellset/list [<set name>]`: If <set name> is provided, shows the prepared spells in set <set name>. If not, shows a list of available sets. 
`spellset/clear <set name>`: Deletes the set <set name>.
`spellset/rem <set name> = <spell name>/<level>`: Removes <spell name> from set <set name>.
`spellset/ready <set name>`: Clears all existing prepared spells and replaces it with the contents of <set name>.

Note that this does not load these spells into your spells for the day, it merely makes the list available to the `daily` command. The `daily` command, when run, will load the given prepared list into your spells available to cast that day.