---
toc: Magic In Pathfinder Second Edition
summary: Searching the spell database. 
aliases:
- spellsearch
- search spells
- searching spells
---

# Searching Spells 

There are many spells in Pathfinder 2e that a character can learn, and it can be hard for a player to know where to start in finding and selecting spells. The `spell/search` function can find spells fitting the criteria that you specify with attributes and terms. 

Here's the generic syntax for `spell/search`:
`spell/search <attribute1>=<term1>, <attribute2>=<term2>, ... , <attributeN>=<termN>`

An attribute can be any of the following words: `name`, `traits`, `level`, `tradition`, `school`, `bloodline`, `description` OR `desc`, `effect`, and `cast`.

`name`: the name of a spell. 
`traits`: the trait(s) of a spell.
`level`: the base level of a spell.
`tradition`: the tradition of a spell.
`school`: the school of a spell.
`bloodline`: the bloodline of a spell.
`description` OR `desc`: the description of a spell.
`effect`: the effect of a spell.
`cast`: the spell components of a spell, such as material, somatic, verbal, and focus.

For most terms, you input a string, such as 'electric' for `name` (resulting in `spell/search name=electric`). However, the 'level' term is unique: it requires a number input (ranging from 0 to 10), and you can specify an optional operator, '<' or '>', to limit it to spells whose base level is lower than that number ('<') or higher than that number ('>'). **NOTE**: The search will behave in unexpected ways if there is no space between the operator and the number on the level command, i.e. level=> 1 is correct, but level=>1 will not give you the results you expect.

The search function is a Boolean AND, meaning that a spell must meet all of your specified criteria to be included in the list. 

## Examples 

`spell/search level=> 1`: Returns all spells of level 2 and higher. 
`spell/search tradition=arcane, level=1`: Returns all level 1 spells of the arcane tradition. 
`spell/search bloodline=draconic`: Returns all of the Draconic bloodline's bloodline spells.
`spell/search name=Electric`: Returns all spells that have 'Electric' in their names.
`spell/search traits=electricity`: Returns all spells that have the trait Electricity.
`spell/search school=evocation`: Returns all Evocation school spells.
`spell/search description=fey`: Returns all spells that have the word 'fey' in their spell descriptions.
`spell/search effect=acid`: Returns all spells that have the word 'acid' in their spell effects.
`spell/search cast=somatic`: Returns all spells that have a Somatic spell component.