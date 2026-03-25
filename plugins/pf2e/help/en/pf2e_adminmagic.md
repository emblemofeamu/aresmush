---
toc: Pathfinder Second Edition - Admin
summary: Admin commands to edit a character's magic options.
aliases:
- pf2estaff_magic
- pf2eadmin_magic
---

# Pathfinder 2E -- Admin Commands for Magic
Game admins and those they designate can make some modifications to characters' sheets. 

### Setting spellbook or repertoire spells
**Command**:
`admin/set <character>/[spellbook|repertoire] = <charclass> [add|delete] <spell name> <spell level>`

**Key**:
`<character>`: The character's name.
`[spellbook|repertoire]`: Choose `spellbook` for prepared casters; `repertoire` for spontaneous casters.
`[add|delete]`: Choose `add` to add a spell; `delete` to remove a spell.
`<spell level>`: The level of the spell. Needs to be a number from 1-10.

### Setting spellbook or repertoire spells
**Command**:
`admin/set <character>/[spellbook|repertoire] = <charclass> [add|delete] <spell name> <spell level>`

**Key**:
`<character>`: The character's name.
`[spellbook|repertoire]`: Choose `spellbook` for prepared casters; `repertoire` for spontaneous casters.
`<charclass>`: The character's class.
`[add|delete]`: Choose `add` to add a spell; `delete` to remove a spell.
`<spell name>`: The name of the spell.
`<spell level>`: The level of the spell. Needs to be a number from 1-10.

### Setting focus spells and cantrips
**Command**:
`admin/set <character>/focus = [add|delete] <charclass> [cantrip|spell] <spell name>`

**Key**:
`<character>`: The character's name.
`[add|delete]`: Choose `add` to add a focus cantrip/spell; `delete` to remove a focus cantrip/spell.
`<charclass>`: The character's class.
`[cantrip|spell]`: Choose `cantrip` to add a focus cantrip; `spell` to add a focus spell.
`<spell name>`: The name of the spell.

### Setting divine fonts
**Command**:
`admin/set <character>/divine font = [heal|harm]`

**Key**:
`<character>`: The character's name.
`[heal|harm]`: Choose `heal` to set healing font; choose `harm` to set harming font.
