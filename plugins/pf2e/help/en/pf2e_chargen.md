---
toc: Pathfinder Second Edition
summary: Starting character generation - basic information.
order: 2
aliases:
- chargen
- cg
---
# Pathfinder 2E Chargen - Character Options

The first thing you'll need to do is set your basic character information. You will only be able to use this command in chargen, and nothing you set here can be changed after approval without staff assistance. 

`cg/info <option>`: This command lists the options available to you, based on either all options available or on the choices you have already made. The list of options follows the inputs for `cg/set`.

`cg/review`: This command is your friend and guidebook through the sheet generation process. Watch especially the warning messages at the bottom - if you see something in red, you are either missing a choice, or you have made an illegal one.  Remember that your prologue should reflect the options chosen here. 

To set an option:

`cg/set <input>=<option>`: Sets basic character information.

<input> may be one of:

* `ancestry`: Genetic racial traits. Choose this before choosing heritage.
* `background`: Your character's life before they became a Slayer.
* `charclass`: Your character's class; their field of expertise.
* `heritage`: A subset of ancestry; helps determine what ancestry feats are available to your character.
* `specialize`: Many classes have specialties. If yours does, choose it using this input.
* `specialize_info`: A few classes need to choose an option for their specialty. If your specialty does, choose it using this input.
* `alignment`: Your character's alignment, expressed as a two-letter code (True Neutral is N). 
* `deity`: Does your character venerate a specific deity above all others? (Optional.)

`ancestry`, `background`, `charclass`, `heritage`, and `alignment` are required for all characters. Please see `cg/review` for other requirements before continuing.

`commit info`: Once you're happy with what you have, input this to finalize it and set up the next phase of chargen. BEWARE: If you change your mind on these later, you'll have to cg/reset and start your sheet over from the beginning.

`cg/restore <checkpoint>`: If you would like to change your base info, ability scores or skills after you have committed them, this command will restore your character to the point just before the section was committed.

`cg/reset`: If you change your mind and want to completely start over, you can do so with this command. This command wipes all options and starts you over at the very beginning.
