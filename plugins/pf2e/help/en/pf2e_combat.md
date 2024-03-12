---
toc: Pathfinder Second Edition
summary: Encounter-related commands.
aliases:
- initiative
- init
- tinit
- damage
- heal
- encounter
- combat
---
# Pathfinder 2E Encounters

Invoking encounter mode (or, for the grognards out there, initiative rounds) changes the time flow of a scene. It is used when time must be closely tracked in order to understand the outcome.

The following commands are used to manage encounter mode in a scene. Note that in order to participate in an encounter, you must join the scene (not just watch).

For all commands, "initiative" and "init" are aliases for "encounter". 

## For Participants

`encounter/join <encounter ID>[=<stat>]`: Joins an encounter in progress, using the stat specified by the organizer by default. If the organizer tells you that you should use a different stat, specify <stat>. 
`encounter/view [<encounter ID>]`: View the initiative table for the encounter in question. (Alias `tinit <encounter ID>`)

## For Organizers

`encounter [<stat>]`: If an encounter is not active in the scene, this command starts an encounter, with you as the organizer. `<stat>` is optional and will default to Perception if not specified.
`encounter/add [<encounter ID>=]<name>=<init modifier>`: Adds name to initiative, rolling initiative for them with the given modifier. **NOTE**: This command is intended to be used for adversaries and calculates initiative order with that in mind. PC's should join using `encounter/join`. (Alias: `jinit`)
`encounter/mod [<encounter ID>=]<name>=<new init>`: Sets name's initiative to the new initiative.`
`encounter/next`: Moves the initiative forward one turn. (Alias: `ninit`)
`encounter/prev`: Moves the initiative backwards one turn. (Alias: `pinit`)
`encounter/scan`: Allows the organizer to view details on all PC's who have joined the encounter. (Alias: `tscan`)
`encounter/end [<encounter ID>]`: Ends an encounter. 
`encounter/restart [<encounter ID>]`: Restarts an encounter, so long as the scene has not ended.

## Tracking Bonuses and Penalties
`encounter/bonus [<encounter ID> =] <bonus description>/<list of people to whom it applies>`: Records a bonus that is available to players in the list. Helps keep track of buffs. 
`encounter/penalty [<encounter ID> =] <penalty description>/<list of people to whom it applies>`: Records penalties applicable to players in the list. 
`encounter/expire <description>`: Clears all bonuses and penalties whose descriptions match `<description>`.

**TIP** Consider including the name of the spell that invoked the bonus or penalty in the description. That way, `encounter/expire` can clear all bonuses / penalties associated to the spell with one command. 

## Healing and Damage Commands

Any approved player may use a heal command at any time. To damage a player, you must be a DM, game admin, or the organizer of an encounter to which the targets are joined.

`heal <player list> = <amount>`: Heals each character in `<player list>` for `<amount>`, up to their maximum HP.
`damage[/ndc] <player list> = <amount>`: Damages each character in `<player list>` for `<amount>`. The optional `/ndc` is for DM's and admins only, and disables the check to see if a character is dead. It has no effect for organizers without admin or DM roles.
`condition/set <player>=<condition>[/<value>]`: Sets `<condition>` on `<player>`.

