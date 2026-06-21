---
toc: Magic In Pathfinder Second Edition
summary: Customizing magic in character generation.
aliases:
- addspell
- dfont
---

# Managing and Customizing Magic in Character Generation

Many classes and ancestries do not have access to magic and magic casting, but many characters either start with magic or gain access to it later depending on what character options are made. `cg/review` will inform you if you need to add any spells to your character sheet.

After finishing chargen, see `help magic` for more information on using, preparing, and casting spells.

## Adding Spells
The following commands are applicable for adding and reviewing spells.

**Commands**:
`addspell <class>/<level> = <spell name>`: Chooses a spell (by `<spell name>`). `<class>` is your character class, and `<level>` is the spell's level. 
`addspell <class>/<level> = <old spell>/<new spell>`: Swaps `<old spell>` for `<new spell>` in the specified character class (`<class>`) and spell level (`<level>`).
`spellbook`: Shows all the spells you know if you're a prepared caster.
`repertoire`: Shows all the spells you know if you're a spontaneous caster.
`magic`: Shows your magic casting stats, including focus spells and innate spells (if you know any).
`spell/search`: Searches spells in the spell database. (See `help spell search` for more information.)

**Note: All spells selected in character generation must be common spells.** A spell must not have the Uncommon or Rare traits. Uncommon and Rare spells can only be learned after chargen with RPP spends.

%xrImportant!%xn Once you are done selecting spells, you will have to input `rest` to see your spells on the magic section of your sheet. You cannot `rest` until your character is approved.

## Special Spell Cases
Some class specialties or choices grant you extra spells that must be resolved with different syntax. These cases are indicated in the cg/review screen and can be resolved with the following commands:

**Commands**:
`addspell innate/<level> = <spell name>`: Chooses an open innate spell, if you've been given one by a feat.

## Adding Divine Fonts

Clerics have the divine font class feature. Some deities provide a choice between a Heal divine font or a Harm divine font. `cg/review` will tell you if you need to choose.

**Commands**:
`dfont <input>`: Selects your divine font. `<input>` can be `heal` or `harm`.
