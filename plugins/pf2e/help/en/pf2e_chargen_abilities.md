---
toc: Pathfinder Second Edition
summary: Starting character generation - ability boosts.
order: 3
---

# Pathfinder 2E Chargen - Abilities

Now you can start assigning ability boosts to your ability scores. Some of your stats already have boosts from your Background and Class choices, but you will need to assign other ability boosts before you can move on. Your ability options are: Strength, Dexterity, Constitution, Wisdom, Intelligence, and Charisma.

These rules apply to assigning ability boosts:

1. You begin with a score of 10 in each ability, which represents an average competency. Each boost increases the ability score by 2. No score may start play at lower than 10 or higher than 18, and only one score may start play at 18.

2. When you receive multiple ability boosts from a single source, you must assign each boost to a different score. For example: a character assigns one of their two ancestry ability boosts to Dexterity, but cannot assign their other ancestry boosts to Dexterity. That boost must go into one of the other five ability scores.

3. Many backgrounds offer a boost that offers a choice between two scores in addition to a free boost. If this is true of your background, it is legal to choose one of the score options for your first boost, and make your open boost the other one. The only requirement is that each boost from a given source go to a different stat. For example: a character with the Feybound background has a boost that they can take in either Dexterity and Charisma in addition to a free boost. The character can take their first boost in Dexterity and their second boost in Charisma.

When you have a boost that wants you to choose between two scores, such as a Background or a Class boost, we recommend you assign that boost first before you set other free boosts. 

## Commands

`cg/review`: Lists your free boosts, ancestry boosts, background boosts, and your character class’s key ability boost. After you assign a boost to an ability score, `cg/review` shows a list of what boosts you have assigned and have not assigned.

`sheet`: Shows your character sheet.

In the following commands, you must replace the <ability> value with one of the following options: Strength, Dexterity, Constitution, Intelligence, Wisdom, or Charisma.

`boost/set <input>=<ability>`: A <input> can be an `ancestry`, `background`, `charclass`, or `free`. Assigns a type of boost to <ability>.

`boost/unset <input>=<ability>`: Unassigns that ability for that boost type only. Does not affect other boosts you may have assigned.

When you are satisfied with what you have, input `commit abilities`. This locks your ability scores and allows you to choose your skills and languages. If you want to change your ability scores after you do this, you will need to start your sheet over using `cg/reset`.
