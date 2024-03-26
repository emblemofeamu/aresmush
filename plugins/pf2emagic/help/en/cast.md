---
toc: Magic In Pathfinder Second Edition
summary: Commands used to actually cast spells.
aliases:
- cast
- refocus
---

# Casting Spells in Pathfinder Second Edition

Casting a spell in Pathfinder 2E depends on what type of spell it is. Spellcasters, both prepared and spontaneous, cast spells from their daily allotment of spells, and even those who are not technically spellcasters may have certain spells available to them as innate spells granted by a feat or by ancestry, and/or may have focus spells granted by their class or by a feat.

Commands for casting:

`cast[/<type>] <casting class>[/<level>] = <spell name>[]/<target list>]`: Casts a spell from a spellcaster's daily spell allotment. If `at <target>` is included, `<target>` is a string, a character or NPC name. It may be a list of names, separated by commas. 

* `<casting class>` is the class from which the spell comes. For innate spells, `<casting class>` should be the word 'innate' with no level.
* `<type>` is specified if this is a focus spell, focus cantrip, or signature spell, and have the values 'focus', 'focusc', and 'signature' respectively. 
* `<level>`, if present, is an integer, or the word _cantrip_. If the spell is to be cast at its base level, you may omit this term. 

**TIP**: For lazy typers, a '0' for level will be interpreted as a cantrip.

`refocus`: Runs the code for the Refocus activity. This may be done only if your focus pool is zero, and then only once an hour in OOC time. 

Admins can run this command as `refocus <character>`, to reset another character's focus pool. Admins may do this at any time, without time or pool size restrictions. 
