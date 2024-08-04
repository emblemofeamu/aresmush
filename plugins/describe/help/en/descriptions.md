---
toc: Locations and Descriptions
summary: Setting descriptions.
order: 2
aliases:
- describe
- shortdesc
- desc
- adesc
---
# Description Commands

Every character, room and exit has a description that tells you what your character sees when they look around.

> Learn the basics of descriptions in the [Descriptions Tutorial](/help/descriptions_tutorial).

`describe <name>=<description>` - Describes something
`describe/edit <name>` - Grabs the existing description into your input buffer. (See [Edit Feature](/help/edit).)

`shortdesc <name>=<description>` - Sets a short desc.
`shortdesc/edit <name>` - Grabs an existing short desc into your input buffer.

`desc/notify <on or off>` - Notifies you when someone looks at you. (MU client only)

## Outfits and Details

You can store multiple descriptions with the [Outfits](/help/outfits) commands, and have expanded [Details](/help/details) (like jewelry or tattoos).

## Outfit Commands

`outfits`: Lists outfits
`outfit <input>`: Views an outfit. <input> is the name of the outfit.
`outfits/all`: View of all your outfits and descriptions.
`outfit/set <input>=<description>`: Creates a new outfit, or replaces an old one.
`outfit/delete <input>`: Deletes an outfit.

`wear <list of outfits>`: Wear outfits.

## Detail Commands

Details can be set on either a character or a room. Use a character name, room name, 'me', or 'here' for the input.

`detail/set <input>=<detail title>/<description>`: Detail title is the name of the detail you wish to set, the description is what it looks like.
`detail/delete <input>/<detail title>`: Deletes an existing detail.
`detail/edit <input>/<detail title>`: Grabs the existing detail into your input buffer.

You view details using the regular `look` command:

`look <input>/<detail title>`: Looks at a detail on something.
