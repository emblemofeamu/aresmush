---
toc: Pathfinder Second Edition
summary: Commands related to advancement, skills, and abilities.
aliases:
- advancefeats
- advancefeatures
---

# Advancement - Selecting Feats and Class Features

See `help advance` for more information about advancement.

## Selecting Feats and Class Features
Most levels have you selecting some type of feat. Some class features gained in advancement may also require you to choose an option.

**Commands**:
`advance/feat <type> = <feat name>`: Select a feat (by its `<feat name>`) that is the specified `<type>`. Dedication feats are selected with class (charclass) feats. `<type>` options: `general`, `skill`, `charclass`, or `ancestry`. Dedication and Archetype feats are `charclass` feats.
`advance/feat special/<type> = <option>`: Some feats, such as Ancestral Paragon, require that an option is selected with this command in `advance/review`. `<type>` is the name of the feat, and `<option>` is your choice. 
`advance/option charclass/<feature> = <option>`: Some class features require that an option selected with this command in `advance/review`. `<feature>` is the name of the class feature, and `<option>` is the option you'd like to choose. 

Sometimes, feats might give training in skills you're already trained in. Those skills are turned into open slots to train an untrained skill into a trained one. Use the regular `advance/raise skill` command (as outlined in `help advanceskills`) to train those skills.

### Examples
Ancestral Paragon: `advance/feat special/ancestral paragon=Unwavering Mien` would satisfy Ancestral Paragon if the player character is a sildanyar or silyara.
Weapon Mastery: `advance/option charclass/weapon mastery=sword` would satisfy the Weapon Mastery class feature for fighters.