---
toc: Pathfinder Second Edition
summary: Managing Gear and Inventory
aliases:
- invest
- uninvest
- equip
- unequip
---

# Equipping And Investing Items

In order for weapons, armor, shields, and magic items to be useful, they must be equipped, invested, or both, depending on what they are. Weapons, armor, and shields can be equipped; weapons, armor, and magic items with the _invested_ trait can be invested.

Equipping an item takes immediate effect; investing must be done as part of daily preparations, meaning that you must set your list and then `rest` (see: `help rest`) for the investment to take effect.

A few things to be aware of: 
* You cannot equip or invest an item that is in a bag. They must be in your main inventory.
* Most characters can only invest ten items on any given day. The feat Incredible Investiture expands this to 12. 
* Once you invest an item, the code will assume you want to invest that item daily, and will continue to invest that item at daily prep unless you `uninvest` it. This is because most people will invest the same items daily on most days, and change what is invested only occasionally or for a specific purpose. 

## Commands

`gear/equip <category> = <item number>`: Equips the identified item in <category>. (Alias: `unequip`)
`gear/unequip <category> = <item number>`: Unequips the identified item in <category>. (Alias: `equip`)

`invest <list>`: Sets a specified list of items for investment at next daily refresh. <list> should be in the format <category>/<number>. Valid for  Note that some magic items are treated as weapons or armor.
`uninvest <list>`: Uninvest items, syntax is as `invest`. 