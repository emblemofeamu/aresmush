---
toc: Pathfinder Second Edition
summary: Healing and damage-related commands.
aliases:
- damage
- heal
- condition
---
# Pathfinder 2E - Damage and Healing

As part of normal Pathfinder 2e gameplay, Emblem of Ea tracks damage dealt to a character, and healing given to a character, on a dynamic and manual basis.

## Player commands

These commands will only work in the context of a scene, unless you are a game admin.

`heal <player list> = <amount>`: Heals each character in `<player list>` for `<amount>`, up to their maximum HP.

## Organizer Commands

These commands will only work if you are running an encounter inside a scene, or are a DM or game admin. A DM can use these only within context of a scene.

`damage[/ndc] <player list> = <amount>`: Damages each character in `<player list>` for `<amount>`. The optional `/ndc` is for Plotmasters and admins only, and disables the check to see if a character is dead. It has no effect for organizers without admin or Plotmaster roles.
`damage/reset`: Usable in encounter mode only, and only by the organizer. Clears all damage for all participants in the encounter.
`condition/set <player>=<condition>[/<value>]`: Sets <condition> on <player>.
`condition/unset <player>=<condition>`: Removes <condition> from <player>.

## For Game Admins

`condition/clear <player>`: Clears all conditions from a player sheet.
`damage/clear <player list>`: Clears all damage from a player sheet.
