---
toc: Pathfinder Second Edition - Admin
summary: Admin commands for other inventory and gear functions.
aliases:
- pf2estaff_inv
- pf2eadmin_gear
- pf2eadmin_inventory
---

# Pathfinder 2E -- Admin Commands for Inventory and Gear
Game admins and those they designate can make some modifications to characters' inventories. 

### Etching runes
**Commands**:
`etch/potency <character>=<category>/<item number>/<potency level>`
`etch/striking <character>=weapons/<item number>/<striking level>`
`etch/resilient <character>=armor/<item number>/<resilient level>`
`etch/property <character>=<category>/<item number>/<rune name>`

**Key**:
`<character>`: The character's name.
`<category>`: `weapons` or `armor`. Case-sensitive.
`<item number>`: The number of the item in the character's inventory.
`<potency level>`: The level of the Potency rune, as a number. Acceptable values: 0-3
`<striking level>`: The level of the Striking rune, as a number. Acceptable values: 0-3
`<resilient level>`: The level of the Resilient rune, as a number. Acceptable values: 0-3
`<rune name>`: The name of the rune; can be any string of words (for now). 

To remove the name of a Property rune from an item, repeat the command that added the rune name.