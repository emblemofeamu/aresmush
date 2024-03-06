---
toc: Pathfinder Second Edition
summary: Starting character generation - basic information.
order: 2
aliases:
- chargen
- cg
---
# Pathfinder 2E Chargen - Character Options

The first thing you'll need to do is set your basic character information. You will only be able to use this command in chargen, and nothing you set here can be changed after approval without staff assistance. To set a property:

`cg/set <element> = <value>`: Sets basic character information.

<element> may be one of:

* `ancestry`%xy*%xn: Genetic racial traits. Choose this before choosing heritage.
* `background`%xy*%xn: Your character's life before they became an adventurer. (See `help bglist` for a list of Backgrounds.)
* `charclass`%xy*%xn: Your character's class, their field of expertise.
* `heritage`%xy*%xn: A subset of ancestry, determines what ancestry feats are available.
* `lineage`: Some heritages offer optional lineage feats. If yours does and you want one, choose it with this keyword.
* `specialize`: Many classes have specialties. If yours does, choose it using this element.
* `specialize_info`: A few classes need to choose an option for their specialty. Choose it with this keyword.
* `alignment`%xy*%xn: Your character's alignment, expressed as a two-letter code. See [PRD](https://2e.aonprd.com/Rules.aspx?ID=95) for how alignment works in Pathfinder 2e.
* `deity`: Does your character venerate a specific deity above all others?

**An element marked with the * character is a mandatory element.** Note that some other elements may be mandatory depending on game configuration and on the options chosen.

`cg/info <element>`: This command lists the options available to you, based on either all items available or on the choices you have already made. (To see all of the backgrounds in a less spammy format than `cg/info background`, see `help bglist`.)

`cg/review`: This command is your friend and guidebook through the sheet generation process. Watch especially the warning messages at the bottom - if you see something in red, you are either missing a choice, or you have made an illegal one.  Remember that your prologue should reflect the options chosen here.

`commit info`: Once you're happy with what you have, type this to finalize it and set up the next phase of chargen. **BEWARE**: If you change your mind on these later, you'll have to `cg/reset` and start your sheet over from the beginning.

`cg/reset`: If you change your mind and want to completely start over, you can do so with this command. This command wipes all options and starts you over at the very beginning.
