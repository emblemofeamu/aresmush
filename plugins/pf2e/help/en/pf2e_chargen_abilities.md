---
toc: Pathfinder Second Edition
summary: Starting character generation - attribute boosts.
aliases:
- cg_attributes
---

# Pathfinder 2E Chargen - Attributes

Now you can start assigning attribute boosts to your attributes. Some of your stats already have boosts from your Background and Class choices, but you will need to assign other attribute boosts before you can move on. Your attribute options are **Strength, Dexterity, Constitution, Wisdom, Intelligence, and Charisma**. For more information about attributes, see [Archives of Nethys's page on character creation](https://2e.aonprd.com/Rules.aspx?ID=2027).

## Setting attribute boost commands
`boost/set ancestry=<attribute>`: Sets one of your two ancestry boosts to `<attribute>`.
%t On Emblem of Ea MUSH, **ancestry attributes are open.**
`boost/set background=<attribute>`: Sets one of your background boosts to `<attribute>`.
%t If your background gives you a choice between two attributes for one of your background boosts, **we recommend you assign the choice boost first before you set the other background boost.**
`boost/set charclass=<attribute>`: Sets your class boost to `<attribute>` and determines your class's Key Attribute, which is the attribute that your class uses to calculate class and spellcasting DC.
%t **Not all classes have a charclass boost choice.** See your class's wiki page for details.
`boost/set free=<attribute>`: Sets one of your free boosts to `<attribute>`.

## Unsetting attribute boost commands
If you make a mistake, you can unset a boost that you set.

`boost/unset ancestry=<attribute>`: Unassigns your ancestry `<attribute>` boost.
`boost/unset background=<attribute>`: Unassigns your background `<attribute>` boost.
`boost/unset charclass=<attribute>`: Unassigns your class `<attribute>` boost.
`boost/unset free=<attribute>`: Unassigns your free `<attribute>` boost.

**NOTE:** `boost/unset` is currently unavailable. Please use `cg/restore info` followed by `commit info` to reset boosts.
