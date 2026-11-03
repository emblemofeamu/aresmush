---
toc: Pathfinder Second Edition
summary: Effects a character is under for a while - spells, stances, potions.
aliases:
- effect
- effects
---
# Pathfinder 2E - Effects

An effect is a temporary result of a spell, feat, or item, such as *heroism*'s bonus for ten minutes, a barbarian's rage, or a potion's resistance for an hour. The game applies an effect's numbers directly to the sheet and to every roll (a character under *heroism* gets the bonus without anyone adding it), and ends the effect on its own when its duration runs out.

The game uses Foundry VTT's Pathfinder 2e effects, about two thousand of them, so most effects from spells and feats use the names you'd expect.

### Viewing effects
`effects [<name>]`: Shows your effects, or another character's, with how long each has left, plus their conditions.
`effect/view <effect>`: Shows what an effect does, how long it lasts, and what it asks when it's applied.
`effect/search <words>`: Lists the effects whose names contain all of `<words>`.

### Applying and ending effects
`effect/add <names>=<effect>[/<option>...]`: Applies an effect to one or more characters.
%t **Examples**:
%t `effect/add Aria Bram=heroism/rank 6`
%t `effect/add Bram=resist energy/rank 4/fire`
`effect/remove <names>=<effect>`: Ends an effect on one or more characters early.
%t **Note:** These commands are for the GM of the encounter here, and work on anyone in that encounter. Effects apply to a character's encounter copy, never to their own sheet.

Options after an effect's name include details that need to be manually added:

- `rank <n>`: The rank the spell was cast at. For example, *heroism* at 6th rank gives a +2 bonus instead of +1.
- `value <n>`: For an effect that counts something, how many.
- `tradition <name>`: The tradition the spell was cast from, for an effect that depends on it. For example, *dragon form* gives extra resistance when the caster's tradition matches the dragon's.
- Some effects ask you to make a choice. Add your choice as an option. For example, *resist energy* asks which type of energy to resist, so add `fire` to resist fire.

### How long effects last
Effects follow the encounter's clock. A round is one full pass through the initiative order, and a minute is ten rounds. Durations count from the turn the effect was applied, so "until the start of your next turn" means the next turn of whoever applied it, as the rules say. An effect that can't outlast the fight (one measured in rounds or minutes, or one that lasts "until the end of the encounter") ends when the encounter does.

A night's rest ends any effect shorter than a day and takes one night off any effect measured in days.

### Conditions that come with effects
Some effects also give you conditions, such as off-guard, prone, or clumsy, and some conditions give you other conditions: a grabbed character is off-guard, and a dying character is unconscious, blinded, and prone. A condition added this way ends when its source ends, unless the rules say otherwise. For example, you're still prone when you wake up. The sheet shows where each condition came from, as in `Off-Guard (Grabbed)`.
