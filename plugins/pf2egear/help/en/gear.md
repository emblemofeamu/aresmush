---
toc: Pathfinder Second Edition
summary: Managing Gear and Inventory
aliases:
- inventory
- inv
- bag
- item
- equip
- unequip
- invest
---

# Pathfinder 2E Inventory - Managing Your Gear

There are six categories of gear in Emblem of Ea's inventory system.

* Weapons (weapons) - Weapons, including any held item that can be used like a wand or a stave.
* Armor (armor) - All types of armor.
* Shields (shields) - All types of shields. Note that a boss or spikes for a shield are considered a weapon linked to the shield.
* Magic Items (magicitem) - Wearable magical items such as boots, cloaks, rings, etc. If it can be invested, it's in this category.
* Bags and Containers (bags) - Backpacks, bags of holding, belt pouches, and similar.
* Consumables (consumables) - Potions, oils, alchemical items, etc.
* Gear (gear) - Adventuring gear such as grappling hooks, ladders, etc.

## Inventory Commands

`gear [<target>]`: See your gear inventory, or if you're a game admin, someone else's gear inventory by supplying an optional <target>. (Aliases: `i`, `inv`, `inventory`)
`gear/rename <category>/<item number> = <nickname>`: Give a weapon, armor, magic item, bag, or shield a nickname. This can be helpful to identify which item is which at a glance.
`gear/equip <category> = <item number>`: Equips the identified item in <category>. (Alias: `unequip`)
`gear/unequip <category> = <item number>`: Unequips the identified item in <category>. (Alias: `equip`)
`invest <list>`: Sets a specified list of items for investment at next daily refresh. <list> should be in the format <category>/<number>. Valid for any weapon, armor, or magic item with the _invested_ trait. Note that some magic items are treated as weapons or armor.
`item/view <category> = <item number>`: See more details about a weapon, armor, shield, or magic item.

Please note that you cannot equip or invest gear that is in a bag, it must be in your main inventory.

## Bag Commands

These commands are specifically related to managing bags. You must buy a bag before you can use it to manage your gear.

`bag <#>`: View the contents of bag <#>.
`bag/store <category>/<item number> = <#>`: Stores <item> in <category> from your inventory in bag number <#>. (Alias: `bag/put`)
`bag/retrieve <category>/<item number> = <#>`: Retrieves <item> in <category> from bag number <#> and places it in your inventory. (Alias: `bag/get`)