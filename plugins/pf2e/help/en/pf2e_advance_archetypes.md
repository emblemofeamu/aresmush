---
toc: Pathfinder Second Edition
summary: Commands related to advancement and archetypes.
aliases:
- advancearchetypes
- advancededications
---

# Advancement - Archetypes and Dedications

See `help advance` for more information about advancement.

## Selecting Archetypes
Starting at level 2, you can spend a class feat to select a Dedication feat. Selecting a Dedication feat enters you into the Dedication feat's corresponding archetype. After entering an archetype, you must spend a class feat on two more feats from that archetype before you can select another Dedication feat to enter another archetype. See [Archetypes & Dedications](/wiki/mechanics:archetypes-dedications) for more information.

**Commands**:
`advance/feat charclass = <feat name>`: Selects a Dedication or Archetype feat (by its `<feat name>`).
`advance/archetype specialty = <specialty>`: Selects an archetype specialty, if available.
`advance/archetype specialtychoice = <specialtychoice>`: Selects an archetype specialty choice, if available. (Only for Barbarian Archetype's Animal and Dragon instincts and the Sorcerer Archetype's Elemental and Draconic bloodlines.)
`advance/archetype deity = <deity>`: Selects a deity for your archetype. (Only for Cleric and Champion Archetypes.) Deity is automatically assigned for you if you already have a deity set from chargen.
`advance/archetype key ability = <key ability>`: Selects a key ability for your archetype. (Only for some Archetypes.)
`advance/archetype sanctification = <sanctification>`: Selects a sanctification for your archetype. (Only for Cleric and Champion Archetypes.)

Sometimes, archetypes, archetype specialties, and deities chosen for archetypes might give training in skills you're already trained in. Those skills are turned into open slots to train an untrained skill into a trained one. Use the regular `advance/raise skill` command (as outlined in `help advanceskills`) to train those skills.

## Archetype Spells
If your character class is a caster, and you take an archetype that can also learn magic, use the following commands to learn spells for your archetype, depending on caster type. If your main character class doesn't have any casting, you can use the regular spell learning commands.

**Commands**:
`advance/spell repertoire/<archetype name>/<level> = <spell name>`: Selects a spell for your archetype's repertoire.
`advance/spell spellbook/<archetype name>/<level> = <spell name>`: Selects a spell for your archetype's spellbook. 

### Examples
Learning a spell for an archetype's repertoire: `advance/spell repertoire/oracle archetype/cantrip=Stabilize` will set the Stabilize cantrip in the Oracle Archetype's repertoire.
Learning a spell for an archetype's spellbook: `advance/spell spellbook/wizard archetype/cantrip=Light` will set the Light cantrip in the Wizard Archetype's spellbook.