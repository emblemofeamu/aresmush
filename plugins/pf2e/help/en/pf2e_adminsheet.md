---
toc: Pathfinder Second Edition - Admin
summary: Admin commands to manipulate the character sheet.
aliases:
- pf2estaff_sheet
- pf2eadmin_sheet
---

# Pathfinder 2E -- Admin Commands for Character Sheets

Game admins and those they designate can make some modifications to characters' sheets. 

### Setting ability scores
**Command**:
`admin/set <character>/ability = <ability name> <ability score>`

**Key**:
`<character>`: The character's name.
`<ability name>`: The name of the ability. For example, Charisma.
`<ability score>`: The number to set the score to.

### Setting character features
**Command**:
`admin/set <character>/feature = [add|delete] <feature name>`

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to add a feature; `delete` to delete a feature.
`<feature name>`: The name of the feature.

### Setting skills
**Command**:
`admin/set <character>/skill = <skill name> <proficiency level>`

**Key**:
`<character>`: The character's name.
`<skill name>`: The name of the skill to train.
`<proficiency level>`: `untrained`, `trained`, `expert`, `master`, `legendary`

### Changing feats
Feats cannot be set directly. To change a character's feats, use `admin/rollback` to send them back to the level where the
choice was made and let them redo it, or `admin/respec` to let them rebuild the character from scratch while keeping their XP.

### Setting alignment and deity
**Command**:
`admin/set <character>/alignment = <alignment>`
`admin/set <character>/deity = <deity>`

%xrWARNING%xn: 
- Do not use these commands on a character with the Champion class or a character with the Champion Archetype, due to how their class works. 
- Do not use the deity command to change a Cleric's deity or a character with the Cleric Archetype's deity, due to how their class works. 
Offer respecs to these characters instead if they want to redo their sheet!

**Key**:
`<character>`: The character's name.
`<alignment>`: Alignment code (such as, `LG`, `N`, or `CN`).
`<deity>`: The deity's name.