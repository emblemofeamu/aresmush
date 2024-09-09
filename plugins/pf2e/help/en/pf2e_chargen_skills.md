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

1. Some backgrounds offer a skill choice instead of a fixed skill. If you chose a background with a skill choice, you may want to make this selection before you assign your free skills, so that you do not duplicate or double-up on skills.

2. If you get the same skill from multiple sources, such as from your background and your class, you must pick another skill.

3. Lore skills count as skills.


## Commands

`cg/review`: Lists the base skills you have available to you.
`sheet`: Shows your sheet so far.

### Skills
`cg/review`: Lists the number of skills you can assign.
`sheet`: Shows your character sheet.

Skills
`skills`: Displays all skills in a paginated format. skills <input> searches skills for your input. For example, skills lore returns all skills with ‘lore’ as part of their name.
`skill/set <input>=<skill>`: Sets a skill. <input> can be free or background. 
`skill/unset <input>=<skill>`: Deletes your selected skill. You cannot delete skills granted by your ancestry, character class, and some background selections. <input> can be free or background.

When you are satisfied with what you have, input `commit skills`. This locks your skills and allows you to choose your feats. If you want to change your base info, ability scores or skills afterwards, you will need to restore to the appropriate checkpoint with cg/restore <checkpoint> where checkpoint is `info`, `abilities`, or `skills`. If you would like to start your character over, please use `cg/reset`.


### Lore Skills

See `help lore` for a list of Lore skills.