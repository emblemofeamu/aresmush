---
toc: Magic In Pathfinder Second Edition
summary: Customizing magic in character generation.
aliases:
- addspell
- dfont
---

# Managing and Customizing Magic in Character Generation or Advancement

Many classes and ancestries do not have access to magic and magic casting, but many characters either start with magic or gain access to it later depending on what character options are made. `cg/review` will inform you if you need to add any spells to your character sheet.

# Commands

`addspell <class>/<level> = <spell name>`: Chooses a spell for that character class and level. 
`addspell <class>/<level> = <old spell>/<new spell>`: Swaps `<old spell>` for `<new spell>` in that class and level.

The `addspell` command can take selection switches to process some character options. `cg/review` or `advance/review` will tell you what switch to use if you need one.

All spells selected in character generation or advancement must be common spells. (In other words, a spell must not have the Uncommon or Rare tags.) Uncommon and rare spells require a `request` to staff. (See `help requests` for more information.)

Clerics have the divine font class feature. Some deities provide a choice between a Heal divine font or a Harm divine font. `cg/review` will tell you if you need to choose.

`dfont <input>`: Selects your divine font. <input> can be `heal` or `harm`.

Once you are done selecting spells, you will have to input `rest` to see your spells on the magic section of your sheet. You cannot `rest` until your character is approved.

`spell/search` provides a robust search function to help you find spells for your character to learn. For more information on searching through spells, see the `help spell` file. 

**Once you are done selecting spells**, you will have to input `rest` to see your spells on the magic section of your sheet. You cannot `rest` until your character is approved.

`spell/search` provides a robust search function to help you find spells for your character to learn. For more information on searching through spells, see the `help spell` file. 