---
toc: Magic In Pathfinder Second Edition
summary: Spellbook Command
aliases:
- spellbook
- spellbooks
- repertoire
- repertoires
---

# Spellbooks and Repertoires in PF2e

The spellbook command allows you to see which spells you have in your spellbook for a particular class, and optionally, for a particular level.

## Spellbooks
Wizards and witches prepare their spells from a list of spells known that is called a `spellbook`. Technically, witches' spells are stored in their familiar, but for the ease of centralizing code, `spellbook` is the command to use.

**Commands**:
`spellbook`: See your spellbook, if you have one.
`spellbook <character>`: See someone else's spellbook, if they have one.
`spellbook <class>/<level>`: See a specific caster class and level view of your spellbook. The `/<level>` switch is optional if you don't want to see just one level.
`spellbook <character>=<class>/<level>`: View the spellbook for that particular caster class and level. The `/<level>` switch is optional if you don't want to see just one level.

## Repertoires
Spontaneous casters (bards, oracles, sorcerers) don't prepare their spells, instead casting them from a `repertoire` that is added to during chargen and advancement.

**Commands**:
`repertoire [character]`: See your repertoire, if you have one. 
`repertoire <character>`: See someone else's repertoire, if they have one.
`repertoire <class>/<level>`: See a specific caster class and level view of your repertoire. The `/<level>` switch is optional if you don't want to see just one level.
`repertoire <character> = <class>/<level>`: See a specific caster class and level view of someone else's repertoire. The `/<level>` switch is optional if you don't want to see just one level.