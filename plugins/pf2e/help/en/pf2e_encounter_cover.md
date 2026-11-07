---
toc: Pathfinder Second Edition
summary: Cover, concealment, and finding hidden creatures in an encounter.
aliases:
- encounter_cover
- encounter cover
- cover
- conceal
- trust
---
# Pathfinder 2E Encounters - Cover and Concealment

The GM, or a player the GM trusts for this encounter, sets cover and concealment on a target. Every attack and check against the target uses them until someone changes them.

## Setting cover and concealment

`encounter/cover <target>=<none|lesser|standard|greater>`: Gives the target lesser, standard, or greater cover: +1, +2, or +4 to AC. Standard and greater cover also apply to Reflex saves against area effects.
`encounter/conceal <target>=<none|concealed|hidden|undetected>`: Makes the target concealed, hidden, or undetected. Attacks against the target need a flat check first: DC 5 if it's concealed, or DC 11 if it's hidden or undetected. Against an undetected target, the GM also decides whether the attacker guessed the right square.
`encounter/trust <name>`: Lets a player set cover and concealment for the rest of the encounter. Only the GM can use this. `encounter/untrust <name>` takes that back.

A creature that is hidden from or undetected by its targets treats them as off-guard, and is no longer hidden once it attacks.

Concealment applies to everyone, even though the rules sometimes depend on who is looking: a creature hidden from one character might be in plain sight of another who has darkvision. When that matters, leave the target's concealment unset, and have the GM or a trusted player add `/hidden` to the individual attack instead.

## Finding and hiding

`encounter/act seek=<targets>`: Rolls your Perception once against the Stealth DC of each target (`<targets>`, separated by commas). A success makes an undetected target hidden, and a hidden target seen. A critical success makes either one seen.
`encounter/act hide=<targets>` and `encounter/act sneak=<targets>`: Roll your Stealth once against the Perception DC of each target (`<targets>`, separated by commas), and make you hidden or undetected, depending on the result.
%t **Note:** Against several targets, your worst result decides how well hidden you are, because concealment applies to everyone. The GM can change the result with `encounter/conceal`.
`encounter/act create a diversion=<targets>/<traits>`: Rolls your Deception once against the Perception DC of each target (`<targets>`, separated by commas), and shows the result against each. You must name the traits your diversion gains from how you do it (`<traits>`): `manipulate` for a gesture or trick, `auditory linguistic` for distracting words, or all three for both.
%t **Note:** The traits you name count for the action. If you're grabbed, for example, a `manipulate` diversion needs a flat check.
%t **Examples**:
%t `encounter/act create a diversion=#2,#3/manipulate`
%t `encounter/act create a diversion=#2,#3/auditory linguistic manipulate`
%t **Note:** The game doesn't make you hidden when a diversion succeeds, because the rules leave some of how long that lasts to the GM. The GM sets your concealment with `encounter/conceal`.
`encounter/act recall knowledge=<creature>`: Rolls against a DC based on the creature's level and rarity, using a skill that covers the creature's type unless you name one, such as `/religion`. The GM tells you what you learn; the game doesn't show you the creature's stat block.

For other actions, see `help encounter actions` or [read it on the web](/help/pf2e_encounter_actions).
