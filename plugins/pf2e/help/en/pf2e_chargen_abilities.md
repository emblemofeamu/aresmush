---
toc: Pathfinder Second Edition
summary: Starting character generation - ability boosts.
order: 3
---

# Pathfinder 2E Chargen - Abilities

Now you can start assigning ability boosts to your ability scores: Strength, Dexterity, Constitution, Wisdom, Intelligence, and Charisma. Some of your stats already have boosts from your Background and Class choices, but you will need to assign other ability boosts before you can move on.

These rules apply to assigning ability boosts:

1. You begin with a score of 10 in each ability, which represents an average competency. Each boost increases the ability score by 2. No score may start play at lower than 10 or higher than 18, and only one score may start play at 18.
2. When you receive multiple ability boosts from a single source, you must assign each boost to a different score. For example, a character assigns one of their two ancestry ability boosts to Dexterity, but they cannot assign their other ancestry boosts to Dexterity. That boost must go into one of the other five ability scores.
3. Many backgrounds offer a boost that offers a choice between two scores in addition to a free boost. If this is true of your background, it is legal to choose one of the score options for your first boost, and make your open boost the other one. The only requirement is that each boost from a given source go to a different stat, when you are done. For example, a character with the Feybound background has a boost that they must take in either Dexterity and Charisma in addition to a free boost. The character can take their first boost in Dexterity and their second boost in Charisma.

When you have a boost that wants you to choose between two scores, such as a Background or a Class boost, we recommend you assign that boost first before you set other free boosts.

## Commands

In the following commands, you must replace the <ability> value with one of the following options: Strength, Dexterity, Constitution, Intelligence, Wisdom, or Charisma. See the Archives of Nethys site on ability scores for more information on what these abilities say about your character, and what they do.

`cg/review`: Displays unassigned boosts, if any. If you see a number, you can assign it to anything. If you see a list, those are your choices.
`sheet`: Review your sheet so far. Not everything will be in place, and that is okay.
`boost/set <type>=<ability>`: Assigns a type of boost to <ability>. <type> can be `ancestry`, `background`, `charclass`, and `free`.
`boost/unset <type>=<ability>`: Unassigns that ability for that type only. Does not affect other boost types you may have assigned.

When you are done, and satisfied with what you have, type `commit abilities`. This locks your ability scores and allows you to choose your skills and languages. If you want to change your ability scores after you do this, you will need to start your sheet over using `cg/reset`.
