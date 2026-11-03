---
toc: Pathfinder Second Edition
summary: Using the items you carry in an encounter.
aliases:
- encounter_gear
- encounter gear
---
# Pathfinder 2E Encounters - Using Gear

When you join an encounter, the game copies what you carry into it: your gear, what you wear, wield, and have invested, and your money. Everything in the encounter uses that copy, including your encounter sheet, your Strikes and AC, and the items you use. Anything you buy, sell, or equip outside the encounter after you join isn't part of it. The items you brought in belong to the encounter until it ends, so you can't use or sell them on your own sheet in the meantime; otherwise, you'd have them twice.

`encounter/gear [<who>]`: Lists what you, or another combatant, are carrying in the encounter here.
`encounter/use <category>=<number>[/<use>]`: Uses an item you're carrying in the encounter, such as drinking a potion or spending a charge.
`encounter/use consumables=<number>[/<who>]`: Drinks a potion, elixir, or mutagen, or gives it to someone else in the fight. A healing potion heals by its dice (vitality healing works on the living and does nothing for the undead), and an elixir or mutagen applies its effect to whoever takes it.
`encounter/equip <category>=<number>`: Draws a weapon, puts on armor, or straps on a shield.
`encounter/unequip <category>=<number>`: Puts away a weapon, armor, or shield.
`encounter/loot <who>=<consumable>[/<quantity>]`: Gives someone a consumable from the catalog for this encounter.
%t **Note:** Only staff, and trusted GMs named by staff, can hand out items. Being an encounter's GM isn't enough on its own.

A battle form absorbs your gear, so you can't use, equip, or unequip anything until the form ends. The constant abilities of your gear still work.

`encounter/gear` shows item numbers. When the encounter ends, the consumables you used from your own inventory are removed from it. The rest of the copy, including your money and anything the encounter gave you, stays with the encounter. When one encounter continues from another, the copy carries over.

For using ammunition, see "Ammunition and reloading" in `help encounter_actions` or [read it on the web](/help/pf2e_encounter_actions). For buying items, see `help buy` or [read it on the web](/help/vendor).
