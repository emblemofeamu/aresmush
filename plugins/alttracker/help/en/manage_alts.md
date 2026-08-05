---
toc: Alt Tracking
summary: Admin commands for managing alts.
---

# Managing Alts

All commands in this section may only be performed by those with the manage_alts permission.

`alts <name or email>`: View all alts of `<name>` or all alts associated to `<email>`.
`alt/add <name to add>=<existing alt>`: Establishes `<name to add>` as an alt of `<existing alt>`. Note that this will overwrite any existing alt assignment.

This normally only needs to be done if a player decides to retire an alt from play. Idle sweeps will normally catch this.

`alt/remove <name>`: Dissociates `<name>` from existing email address and unapproves `<name>`.

If you need to ban a player, this command will remove and unapprove all their alts and mark the email address as banned. If the player has simply idled out, the player object will be destroyed in an idle sweep and their alts disassociated.

`alt/ban <email> = <reason>` Bans the player identified by `<email>` for `<reason>`. `<reason>` is not visible to the player.
