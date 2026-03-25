---
toc: Pathfinder Second Edition
summary: Commands related to advancement, skills, and abilities.
aliases:
- advanceskills
- advanceabilities
---

# Advancement - Raising Skills and Abilities

See `help advance` for more information about advancement.

## Raising Abilities and Skills
At level 5, 10, 15, and 20, you can raise four abilities to the next step up (typically a +2 bonus, unless the ability score is 18 or higher, in which case it's a +1 bonus). At some levels, skills can also be trained to the next proficiency step (or trained from Untrained to Trained).

**Commands**:
`advance/raise ability = <ability1> <ability2> <ability3> <ability4>`: Boosts ability scores to the next step. 
`advance/raise skill = <skill>`: Raises a skill to the next step of proficiency. For example, `advance/raise skill=Nature` raises the Nature skill.
`advance/raise skill choice = <skill>`: If you have a skill training choice, such as from a Dedication feat, this command raises the chosen skill to the next step of proficiency.

### Examples
Raising ability scores: `advance/raise ability=Strength Dexterity Constitution Wisdom` raises Strength, Dexterity, Constitution, and Wisdom.
Resolving a choice of skills: If given the choice of Stealth or Thievery, input `advance/raise skill choice=Stealth` to raise the Stealth skill.