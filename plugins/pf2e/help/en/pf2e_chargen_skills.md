---
toc: Pathfinder Second Edition
summary: Starting character generation - choosing skills and lores.
order: 4
aliases:
- skill
- skills
---

# Pathfinder 2E Chargen - Skills

In this step, you will choose your open skills. Your choice of ancestry, heritage, character class, and background have already given you a set of skills, but depending on your Intelligence score modifier, you may get more skills to assign. Here are some helpful tips to keep in mind:

1. Some backgrounds offer a choice of skills. If you chose a background with a choice of skills, you may want to make this selection before you assign your open skills, so that you do not duplicate or double-up on skills.
2. If you get the same skill from multiple sources, such as from your background and your class, you must pick another skill to become trained in. 
3. Lore skills count as skills.

## Commands

`cg/review`: Lists the base skills you have available to you.
`sheet`: Shows your sheet so far.

### Skills
`skill/set <type>=<skill>`: Sets an open skill. Types are **background** or **free**.
`skill/unset <type>=<skill>`: Deletes a skill selected with `skill/set`. You cannot delete skills granted by your base info.

When you are done, and satisfied with what you have, type `commit skills`. This locks your skills and allows you to choose your feats. If you want to change your ability scores or skills after you do this, you will need to start your sheet over using `cg/reset`

### Lore Skills

See `help lore` for a list of Lore skills.