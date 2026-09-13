---
toc: Pathfinder Second Edition
summary: How to use Pathfinder Second Edition dice commands.
aliases:
- roll
- dice
---

# Rolling Dice in Pathfinder Second Edition

The roll commands on this game have been constructed to be reasonably familiar to those familiar with AresMUSH FS3 games, but the mechanics behind them are compliant with Pathfinder Second Edition.

`roll <dice + modifiers>`: The `<dice + modifiers>` string can be any combination of integers, dice to roll, and specific keywords. A keyword that is not recognized will be passed to the roller as 0, so it won't affect the roll.

`roll <dice + modifiers>/<dc>`: As above, except `<dc>` must be an integer between 5 and 50. Guidance on what this integer should be can be found in the Pathfinder 2E rules, or may be provided by the scene runner.
%t **Example**:
%t `roll 1d20+3-1+5+strength` will find the character's Strength modifier, roll 1d20, and add the string of numbers together to get the result.

Public rolls appear in the log and are sent to everyone in the room.

## Other dice commands

`roll/for <character> = <dice + modifiers>[/dc]`: Rolls `<dice + modifiers>` for another PC. Anyone can do this, but the display is not private and shows the name of the roller, as well as the name of the character rolled for. This command is intended to be used to help someone who is AFK or having network issues. (Alias: `rollfor`)

`roll/me <dice + modifiers>`: Send a dice roll only to yourself.

`roll/taketen <skill>[/<dc>]`: Forgo the roll and take a flat 10 instead, for characters with the Assurance feat and the Assured Knowledge feat.
%t **Examples**:
%t`roll/taketen Nature` with expert Nature at level 4 outputs `Cor'lana foregoes a roll to take 10 on Nature and gets: (10) + 8 = 18`.

`roll/taketen Nature/20` does the same and reports the degree of success against DC 20. As with any take 10 result, there is no natural 20 or natural 1, so the degree is never stepped up or down.
