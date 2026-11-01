---
toc: Pathfinder Second Edition
summary: Acting in an encounter.
aliases:
- encounter actions
- act
- strike
- cast
- why
- how
---
# Pathfinder 2E - Acting in an Encounter

Encounter commands determine who you're targeting, whether you're flanking, which range increment the target is in, and what cover it has. The game does the math from there: your check against the target's actual defense, your multiple attack penalty, the target's cover and concealment, and the effects of the outcome.

All rolls are public, meaning that everyone in the scene sees each roll and its outcome.

## Command format

`encounter/<verb> <what>=<who>/<circumstance>/<circumstance>`

`<who>` is a combatant's ID from `encounter/view` (such as `#3`) or the combatant's name. Each part after a `/` is a circumstance, such as `flanking` or `range 2`. The "Circumstance bonuses and penalties" section lists them.

`encounter/how <name>`: Shows the commands that do what you name, as you'd type them: an action you can use, a Strike, a spell you can cast, an item you carry, or something the game does, such as spending a Hero Point. If more than one thing goes by that name, or there's more than one way to do it, you get every command. In an encounter, it works from what you carried in.
%t **Examples**:
%t `encounter/how strike` gives a command for each Strike you can make.
%t `encounter/how opportune riposte`, `encounter/how fear`, `encounter/how healing potion`
%t `encounter/how hero point`, or `encounter/how reroll`

## Actions

`encounter/act <action>[=<target>][/<circumstance>...]`: Uses an action. An action that rolls a check (Trip, Demoralize, Grapple, Feint, Escape, Seek, and so on) rolls it against the target's defense and reports the result. An action that puts an effect on you (Rage, Take Cover, a stance) applies that effect to you. The game announces any other action to the room.
%t **Examples**:
%t `encounter/act trip=#3`
%t `encounter/act demoralize=#3/unintelligible`
%t `encounter/act raise a shield`
%t `encounter/act aid=bram/athletics`

### Actions with special handling

- **Battle Medicine** (`encounter/act battle medicine=bram/20`): Rolls Medicine against DC 15, or against a higher Treat Wounds DC (20, 30, or 40) if you name one, for more healing. The GM keeps track of who has been treated today.
- **Reactions that are Strikes** (`encounter/act reactive strike=#3/longsword`): Reactive Strike, Opportune Riposte, and similar reactions Strike with the weapon you name, or with your first weapon that works. They spend your reaction, and they don't use or add to your multiple attack penalty.
- **Actions made of several Strikes**, such as Flurry of Blows, make all of their Strikes against one target. Each Strike counts toward your multiple attack penalty, and you pay the action's cost once.
- **Actions that are a Strike plus something else**, such as Deadly Aim, Combat Assessment, or a finisher, make the Strike with the action's rules applied. You roleplay the rest.
- **Drain Bonded Item** (`encounter/act drain bonded item/<spell>`): Lets a wizard recover a spell they prepared today and have already cast, so they can cast it again with `encounter/cast`.
- **Actions with their own command**, such as Quick Alchemy or Refocus: `encounter/act` refuses them and tells you which command to use instead.
- **Nimble Dodge** and similar reactions that raise your AC against an attack respond to a hit you just took. The game applies the bonus to the attack roll, and undoes the hit if it becomes a miss. When a reaction like this could turn a hit into a miss, the game tells you.
- **Shield Block** (`encounter/act shield block`) responds to a hit you just took while your shield is raised. Your shield's Hardness reduces the hit's physical damage, and you and the shield each take the rest. When you can block a hit, the game tells you.
- **Delay** (`encounter/act delay`): At the start of your turn, lets you wait for a better moment. Your end-of-turn effects happen immediately, and the GM moves on to the next combatant. To come back in, use `encounter/act delay` again after anyone else's turn. You act then, and keep that new place in the initiative order. If a full round passes without you coming back, you lose that turn.
- **Heal and Harm**: Each spell heals one kind of creature and damages the other. A creature being healed doesn't roll; a creature being damaged rolls a basic Fortitude save. The two-action version's extra 8 only applies to healing.
- **Retching** (`encounter/act retch[/<DC>]`): If you're Sickened, spends an action on a Fortitude save against the DC of whatever sickened you. A success reduces the condition by one, and a critical success reduces it by two. If the GM set the condition by hand, add the DC: `encounter/act retch/18`.
- **Disarm, Grapple, Reposition, Shove, and Trip** only work on targets up to one size larger than you: two sizes larger with Titan Wrestler, and three sizes larger if you're also legendary in Athletics.

## Strikes

`encounter/strike <target>[=<weapon>][/<circumstance>...]`: Strikes the target with your first equipped weapon, or with the weapon you name (by name, by nickname, or an unarmed attack like `fist`). On a hit, the game rolls damage and deals it after the target's resistances.
%t **Examples**:
%t `encounter/strike #3`
%t `encounter/strike #3=longsword/flanking`
%t `encounter/strike #4=shortbow/range 2`
%t **Note:** You throw bombs the same way: `encounter/strike #3=alchemist's fire`. The bomb is used up whether or not it hits. Its persistent damage applies on a hit, and its splash damages the target even on a miss (but not on a critical miss). The GM decides who else is in the splash.

### Ammunition and reloading

`encounter/reload [<weapon>]`: Reloads a fired weapon that needs it, such as a crossbow or sling. Reloading takes as many actions as the weapon's reload value, and the weapon can't fire again until you reload it.

Bows, crossbows, and slings always have ordinary ammunition, which the game doesn't track or sell. Ammunition made of a precious material is an item you carry, bought by the piece: `buy consumables=cold iron ammunition/10`. To fire one piece, name the material when you attack, such as `encounter/strike #3=longbow/cold iron`. The piece is used up whether or not it hits, and the attack is refused if you have none.

## Spells

`encounter/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>]`: Casts a spell at one or more targets. It uses up a slot, a Focus Point, or a use the same way `cast` does, and is refused if you have none left. Add `/focus`, `/innate`, or `/signature` to cast that kind of spell. A spell attack rolls against each target's AC. For a spell with a save, each target rolls against your spell DC, and a basic save halves or doubles the damage. The game applies conditions from the outcome, such as frightened from Fear or slowed from Slow, to each target.
%t **Examples**:
%t `encounter/cast fear=#3`
%t `encounter/cast fireball=#3,#4,#5/rank 4`
%t `encounter/cast heal=#2/actions 2`
%t **Note:** For a spell that can be cast more than one way, name the way: `/actions 2` for Heal's two-action version, which heals more at range, or a word from the variant's name, such as `/silver` for silver Needle Darts.
%t **Note:** Force Barrage fires one shard for each action you spend: `encounter/cast force barrage=#3/actions 3`. Every target you name takes all of the shards, so to split them between targets, name one target and the GM settles the rest.
%t **Note:** For a save that isn't basic, the damage for each outcome comes from the spell's text. If the text doesn't say, the game shows the room the damage, and the GM settles it.

## Circumstance bonuses and penalties

`flanking`: The target is off-guard to you (-2 AC).
`range <n>`: Sets the range increment the target is in: -2 to your attack for each increment past the first. Ranged attacks can't reach past the sixth increment.
`<number>`: Sets the DC for an action with no target, such as `encounter/act balance/18`.
`two-handed`: Uses both hands on a weapon that deals more damage that way, such as `encounter/strike #3=bastard sword/two-handed`.
`piercing`, `slashing`, `bludgeoning`: Chooses the damage type a versatile weapon deals this time.
`nonlethal`, `lethal`: Makes a nonlethal attack with a lethal weapon, or a lethal attack with a nonlethal weapon, at -2 to hit. A nonlethal hit that drops someone to 0 HP knocks them out.
`volley`: Marks the target as within a volley weapon's short range (-2 to hit).
`force`: Lets the GM have a creature use an action or cast a spell its stat block doesn't give it. See `help encounter_gm`.
`silver`, `cold iron`, `holy`, `magical`, and so on: Tells the game what your weapon is made of or carries, which it can't see on its own. A creature with a weakness to that material takes more damage, and a resistance that makes an exception for it doesn't apply: `encounter/strike #3=longsword/cold iron`.

Any other circumstance is one the rules can check for, such as `unintelligible`, a skill for Aid, or a variant like `stabilize`.

The game applies a weapon's other traits on its own: sweep and backswing add to your attack roll based on your earlier attacks this turn, forceful adds to damage, and backstabber applies against off-guard targets.

## What happens

When an action's text says what happens, the game applies it: a successful Trip knocks the target prone, and a successful Demoralize makes the target frightened.

%t **Example**:
%t `Aria uses Trip on Goblin Warrior #3: Athletics 23 (15 +8) vs Reflex DC 17 - success.`
%t %t `Goblin Warrior #3 is now Prone.`

A condition with a duration, such as off-guard from Feint or slowed from Slow, ends on its own at the right turn. Frightened goes down by one at the end of each of the frightened creature's turns.

`encounter/why`: Lists every modifier on your last roll, and on the defense it was rolled against.

## Your turn

`encounter/turn [<who>]`: Shows how many actions you've used this turn, whether you've spent your reaction, and your current multiple attack penalty.
%t **Note:** The game never refuses an action for going over your actions, since the GM can always allow it. If you use more actions than you have, the room is told.

At the start of your turn, the game tells you what matters: your actions, your effects and how long they last, persistent damage, and your auras.

`encounter/enter <aura>=<target>,<target>`: Marks which combatants the map shows inside one of your auras. They get the aura's effects, following its rules for allies and enemies.
`encounter/leave <aura>=<target>`: Marks that a combatant has left your aura, which ends the aura's effects on them.

## More encounter help

- `help encounter_cover`: Cover and concealment, and the Seek, Hide, Sneak, and Recall Knowledge actions. [Read it on the web](/help/pf2e_encounter_cover).
- `help encounter_conditions`: Being grabbed or held, other conditions that limit your actions, and afflictions. [Read it on the web](/help/pf2e_encounter_conditions).
- `help encounter_gear`: Using items in your encounter inventory. [Read it on the web](/help/pf2e_encounter_gear).
- `help encounter_gm`: Acting for creatures, and undoing changes, for the GM. [Read it on the web](/help/pf2e_encounter_gm).
