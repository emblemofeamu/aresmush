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
`advance/option <feature> = <option>`: Some class features and feats require that an option selected with this command in `advance/review`. `<feature>` is the name of the class feature or feat, and `<option>` is the option you'd like to choose. 

Sometimes, feats might give training in skills you're already trained in. Those skills are turned into open slots to train an untrained skill into a trained one. Use the regular `advance/raise skill` command (as outlined in `help advanceskills`) to train those skills.

### Examples
Ancestral Paragon: `advance/feat special/ancestral paragon=Unwavering Mien` would satisfy Ancestral Paragon if the player character is a sildanyar or silyara.
Fighter Weapon Mastery: `advance/option Fighter Weapon Mastery=sword` would satisfy the Fighter Weapon Mastery class feature for fighters.

## What can I actually take?

`advance/feats`: Lists every feat slot this level still has open, and how many feats you are
eligible for in each.
`advance/feats <slot type>`: Lists those feats. The slot types are the ones the summary names -
general, skill, ancestry, charclass, archetype, dedication.
`advance/feats <slot type>=<text>`: The same list, narrowed to names containing that text.

The same narrowing works on `advance/info` and `cg/info`, which matters for choices with hundreds
of options: `advance/info Additional Lore=arch` lists only the Lores containing 'arch' rather than
paging through every one of them.
