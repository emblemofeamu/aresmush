---
toc: Pathfinder Second Edition
summary: Commands related to experience and advancement.
aliases:
- advance
- advancement
- xp
- listxp
---

# Experience and Advancement in Pathfinder Second Edition

As in most games, Pathfinder Second Edition uses a system of Experience Points (XP) to track character growth and power increases over time. Unlike in D&D and Pathfinder First Edition, Pathfinder Second Edition does not operate on a sliding scale of increasingly large experience point totals needed to advance. Instead, to gain a level, you spend a flat 1000 XP, whether you are 1st level or 30th, and XP rewards remain the same per encounter or plot no matter your level. 

XP rewards per plot are shared publicly on the wiki and may be reviewed there. Your current XP total is listed at the top of your character sheet. 

Note that you cannot `advance` if you are in an active encounter. Scenes are fine, but you cannot advance in the middle of combat.

## General Advancement Commands
The following commands are broadly useful for the advancement process.

**Commands**:
`listxp`: View a history of your XP rewards and spends.
`advance`: Begins the advancement process. No modification to your sheet is made until you enter `advance/done`.
`advance/review`: Your guidebook for what you get in advancement and the options you need to select. (Alternative alias: `adv/review`)
`advance/feats`: What feat slots this level still has open, and how many feats you are eligible for in each. Add a slot type to list them: `advance/feats skill`. See `help advancefeats`.
`advance/info <thing>`: The options behind anything the review screen says is still outstanding. Add `=<text>` to narrow a long list: `advance/info Additional Lore=arch`.
`advance/done`: Locks your choices, takes you out of advancement mode, and updates your sheet. 
`advance/reset`: Backs out of advancement and discards all changes.
`advance/undo`: Takes back your most recent choice this level, one step at a time, newest first. `advance/redo` puts back the last thing you took back. Neither reaches past `advance/done`; once a level is locked in, only staff can change it, with `admin/rollback`.

### Raising Abilities and Skills, and Learning Languages
See `help advanceskills`, `help advanceabilities`, or `help advancelanguages`.

### Selecting Feats and Class Features
See `help advancefeats` or `help advancefeatures`.

### Learning Spells
See `help advancespells`.

### Archetypes and Dedications
See `help advancearchetypes` or `help advancededications`.