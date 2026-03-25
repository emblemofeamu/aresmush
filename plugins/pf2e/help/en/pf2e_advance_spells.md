---
toc: Pathfinder Second Edition
summary: Commands related to advancement and spells.
aliases:
- advancespells
---

# Advancement - Spells and Magic

See `help advance` for more information about advancement.

## Learning Spells
Repertoire spellcasters learn a handful of spells through advancement and can replace old spells with new ones. Some repertoire spellcasters also gain access to signature spells and can set the spells they know in their repertoire as signature spells.

`advance/spell <type>/<level> = <spell name>`: Selects a new spell (by its `<spell name>`). `<level>` is the level for which you want to learn the spell. `<type>` is either `repertoire` or `spellbook`, depending on what type of caster you are. You must have an open slot to learn a new spell.
`advance/spell innate/<level> = <spell name>`: Selects an open innate spell (by its `<spell name>`), if you have one from a feat. `<level>` is the level for which you want to learn the spell.
`advance/swapspell repertoire/<level> = <old spell>/<spell name>`: Swaps a known repertoire spell for a new spell at the same level. You can do this once per advancement. Bloodline or class-granted spells cannot be swapped. Cantrips can be swapped.
`advance/spell signature/<level>=<spell name>`: Designates a spell (by its `<spell name>`) as a signature spell. `<level>` is the spell's original (base) level.

## Archetype Spells
If your character class is a caster, and you take an archetype that can also learn magic, use the following commands to learn spells for your archetype, depending on caster type. If your main character class doesn't have any casting, you can use the regular spell learning commands.

**Commands:**
`advance/spell repertoire/<archetype name>/<level> = <spell name>`: Selects a spell for your archetype's repertoire. For example, `advance/spell repertoire/oracle archetype/cantrip=Stabilize` will set the Stabilize cantrip in the Oracle Archetype's repertoire.
`advance/spell spellbook/<archetype name>/<level> = <spell name>`: Selects a spell for your archetype's spellbook. For example, `advance/spell spellbook/wizard archetype/cantrip=Light` will set the Light cantrip in the Wizard Archetype's spellbook. 