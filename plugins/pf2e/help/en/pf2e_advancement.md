---
toc: Pathfinder Second Edition
summary: Commands related to experience and advancement.
aliases:
- advance
- advancement
- xp
- listxp
---

# Experience and Advancement in Pathfinder Second Edition

As in most games, Pathfinder Second Edition uses a system of Experience Points (XP) to track character growth and power increases over time. Unlike in D&D and Pathfinder First Edition, Pathfinder Second Edition does not operate on a sliding scale of increasingly large experience point totals needed to advance. Instead, to gain a level, you spend a flat 1000 XP, whether you are 1st level or 30th, and XP rewards remain the same per encounter or plot no matter your level. 

XP rewards per plot are shared publicly on the wiki and may be reviewed there. Your current XP total is listed at the top of your character sheet. 

Note that you cannot `advance` if you are in an active encounter. Scenes are fine, but you cannot advance in the middle of combat.

## General Advancement Commands
The following commands are broadly useful for the advancement process.

**Commands**:
`listxp`: View a history of your XP rewards and spends.
`advance`: Begins the advancement process. No modification to your sheet is made until you enter `advance/done`.
`advance/review`: Your guidebook for what you get in advancement and the options you need to select. (Alternative alias: `adv/review`)
`advance/done`: Locks your choices, takes you out of advancement mode, and updates your sheet. 
`advance/reset`: Backs out of advancement and discards all changes.

## Raising Abilities and Skills
At level 5, 10, 15, and 20, you can raise four abilities to the next step up (typically a +2 bonus, unless the ability score is 18 or higher, in which case it's a +1 bonus). At some levels, skills can also be trained to the next proficiency step (or trained from Untrained to Trained).

**Commands**:
`advance/raise ability = <ability1> <ability2> <ability3> <ability4>`: Boosts ability scores to the next step. For example, `advance/raise ability=Strength Dexterity Constitution Wisdom` raises Strength, Dexterity, Constitution, and Wisdom.
`advance/raise skill = <skill>`: Raises a skill to the next step of proficiency. For example, `advance/raise skill=Nature` raises the Nature skill.
`advance/raise skill choice = <skill>`: If you have a skill training choice, such as from a Dedication feat, this command raises the chosen skill to the next step of proficiency. For example, if given the choice of Stealth or Thievery, input `advance/raise skill choice=Stealth` to raise the Stealth skill.

## Selecting Feats and Class Features
Most levels have you selecting some type of feat. Some class features gained in advancement may also require you to choose an option.

**Commands**:
`advance/feat <type> = <feat name>`: Select a feat (by its `<feat name>`) that is the specified `<type>`. Dedication feats are selected with class (charclass) feats. `<type>` options: `general`, `skill`, `charclass`, or `ancestry`. Dedication and Archetype feats are `charclass` feats.
`advance/feat special/<type> = <option>`: Some feats, such as Ancestral Paragon, require that an option is selected with this command in `advance/review`. `<type>` is the name of the feat, and `<option>` is your choice. For example, `advance/feat special/ancestral paragon=Unwavering Mien` would satisfy Ancestral Paragon if the player character is a sildanyar or silyara.
`advance/option charclass/<feature> = <option>`: Some class features require that an option selected with this command in `advance/review`. `<feature>` is the name of the class feature, and `<option>` is the option you'd like to choose. For example, `advance/option charclass/weapon mastery=sword` would satisfy the Weapon Mastery class feature for fighters.

## Learning Spells
Repertoire spellcasters learn a handful of spells through advancement and can replace old spells with new ones. Some repertoire spellcasters also gain access to signature spells and can set the spells they know in their repertoire as signature spells.

`advance/spell <type>/<level> = <spell name>`: Selects a new spell (by its `<spell name>`). `<level>` is the level for which you want to learn the spell. `<type>` is either `repertoire` or `spellbook`, depending on what type of caster you are. You must have an open slot to learn a new spell.
`advance/spell innate/<level> = <spell name>`: Selects an open innate spell (by its `<spell name>`), if you have one from a feat. `<level>` is the level for which you want to learn the spell.
`advance/swapspell repertoire/<level> = <old spell>/<spell name>`: Swaps a known repertoire spell for a new spell at the same level. You can do this once per advancement. Bloodline or class-granted spells cannot be swapped. Cantrips can be swapped.
`advance/spell signature/<level>=<spell name>`: Designates a spell (by its `<spell name>`) as a signature spell. `<level>` is the spell's original (base) level.