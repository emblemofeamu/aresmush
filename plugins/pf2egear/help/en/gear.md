---
toc: Pathfinder Second Edition
summary: Managing Gear and Inventory
aliases:
- inventory
- inv
- bag
- item
- use
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
`item/view <category> = <item number>`: See more details about a weapon, armor, shield, or magic item. (Alias: `gear/view`)

For equipping and investing gear, see `help equip`.

## Bag Commands

These commands are specifically related to managing bags. You must buy a bag before you can use it to manage your gear.

`bag <#>`: View the contents of bag `<#>`.
`bag/store <category>/<item number> = <#>[/<quantity>]`: Store an item from your inventory in bag number `<#>`. Without a quantity, the whole stack goes in. (Alias: `bag/put`)
`bag/retrieve <category>/<item number> = <#>[/<quantity>]`: Take an item out of bag number `<#>` and put it in your inventory. Without a quantity, the whole stack comes out. (Alias: `bag/get`)

%t **Note:** A bag holds only what its limits allow: a total Bulk, a number of items, or a largest item, depending on the bag. Unequip or uninvest an item before you store it. You can't store or retrieve an item you carried into a running encounter.

%t **Note:** A bag's contents count toward your Bulk, except that a backpack doesn't count the first 2 Bulk it holds, and an extradimensional container, such as a spacious pouch, doesn't count its contents at all. The container's own Bulk always counts.

## Using Items

Using items in PF2 is not limited to consumables. Not all items can be used. If you think an item should be usable and is not, bring it to the attention of the game admins. 

`use <category> = <item number>[/<option>]`: Uses an item in your inventory. `<option>` should only be specified if there is more than one possible use for the item, which is true of some weapons and magic items. `item/view` should tell you whether this is the case.
