---
toc: Magic In Pathfinder Second Edition
summary: Customizing magic in character generation.
aliases:
- addspell
- dfont
---

# Managing and Customizing Magic in Character Generation or Advancement

For most classes and ancestries, there isn't a lot to do for magic in character generation or advancement. Your class, ancestry, background, and heritage determine your magic stats, so this is a matter of picking spells for full spellcasting classes. If you need to choose spells, you will be told so in `cg/review`.

`addspell <class>/<level> = <spell name>`: Chooses a spell for that character class and level. 
`addspell <class>/<level> = <old spell>/<new spell>`: Swaps `<old spell>` for `<new spell>` in that class and level.

Addspell can take select switches to process some character options. `cg/review` or `advance/review` will tell you what switch to use if you need one.

All spells selected must be common spells to be selected in character generation or advancement. Uncommon and rare spells require a request to the game admins.

Clerics get a divine font, chosen at chargen. This is populated automagically for some deities, but clerics of select deities must choose. `cg/review` will tell you if you need to choose. To do so: 

`dfont <heal or harm>`: Chooses your divine font.

**Once you are done selecting spells**, you will have to input `rest` to see your spells on the magic section of your sheet. You cannot `rest` until your character is approved.

The `spell/search` command provides a robust search function to help you find spells for your character to learn. See `help spell search` for more information.