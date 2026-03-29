---
toc: Pathfinder Second Edition
summary: Starting character generation - choosing skills and lores.
order: 4
aliases:
- skill
- skills
---

# Pathfinder 2E Chargen - Skills

In this step, you will choose your free skills. Your choice of ancestry, heritage, character class, and background have already given you a set of skills, but depending on your Intelligence score modifier, you may get more skills to assign. Here are some helpful tips to keep in mind:

- **Some backgrounds offer a skill choice instead of a fixed skill.** If you chose a background with a skill choice, you may want to make this selection before you assign your free skills, so that you do not duplicate or double-up on skills.
- If you get the same skill from multiple sources, such as from your background and your class, you must pick another skill.
- Lore skills count as skills.

### General commands
`cg/review`: Lists the number of skills you can assign.
`sheet`: Shows your character sheet.

### Skill commands
`skills`: Displays all skills in a paginated format. `skills <input>` searches skills for your input. For example, `skills lore` returns all skills with `lore` as part of their name.
`skill/set <input>=<skill>`: Sets a skill. `<input>` can be `free`, `bgchoice`, or `classchoice`. 
`skill/unset <input>=<skill>`: Deletes your selected skill. You cannot delete skills granted by your ancestry, character class, and some background selections. <input> can be free or background.

When you are satisfied with what you have, input `commit skills`. This locks your skills and allows you to choose your feats. 

If you want to change your skills after proceeding from this point, input `cg/restore skills`. If you would like to start your character over, input `cg/reset`.

## List of skills

For a full list of skills, see [Skills](/wiki/mechanics:skills) and the [Lore skill page](/wiki/mechanics:lore) for a list of all lore skills in the game.