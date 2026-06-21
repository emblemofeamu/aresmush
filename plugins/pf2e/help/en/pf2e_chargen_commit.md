---
toc: Pathfinder Second Edition
summary: Starting character generation - committing and restoring chargen stages.
aliases:
- commit
- restore
---

# Pathfinder 2E Chargen - Committing and Restoring Chargen Stages

Currently, the Pathfinder 2e sheet sections of chargen is done in stages, as later choices depend on information being written earlier on. The `commit` command records changes and moves on to the next stage, while the `cg/restore` command restores the chargen step to a 'checkpoint' before committing information and proceeding to the next stage. 

## Stages
The stages are as follows: 

`info`: The basic information screen, where you select ancestry, heritage, background, charclass, specializations, and more.
`abilities`: The ability attributes screen, where you select ability boosts to determine your final ability scores.
`skills`: The skills selection screen, where you select skills.

## Commands

`commit <stage>`: If you're satisfied with your selections in a given stage, this command records changes and moves on to the next stage of chargen. 
`cg/restore <stage>`: If you would like to change your base info, ability scores or skills after you have committed them, this command restores your character to the point before you initially committed your choices. **Note:** You will have to input `commit <stage>` again after using `cg/restore` to return to a previous stage. For example, Sandy decides to `cg/restore info` to redo her choice of ancestry and background. Sandy must `commit info` again before proceeding to the next stage.
