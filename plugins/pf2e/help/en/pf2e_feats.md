---
toc: Pathfinder Second Edition
summary: Searching for and reviewing details of feats.
order: 4
aliases:
- feat
- feats
---

# Feats

Feats in Pathfinder are special abilities that are tied to a character's development and offer customization of a character's abilities. They can be gained as a character gains levels, and a few are available at chargen. There are a _lot_ of them, and no character will qualify for every feat available.

These commands can be used to review the feats you have or determine which ones you qualify for.

`feat/info [<character name>]`: Shows details for all feats `<character name>` currently possesses. If `<character name>` is omitted, it will show the details for all of your feats.
`feat <name>`: Shows details for the named feat.
`cg/feat <type>[/<restriction>] = <feat name>`: Sets a feat in chargen. `<type>` can be `general`, `skill`, `dedication`, `charclass`, `ancestry`, or `special`. The optional `<restriction>` parameter is only checked if `<type>` is "special", which is used for feats where you're limited in what you can take.
`feat/options <type>`: Shows all feats for which the character qualifies but does not yet have.

## Searching for feats
Search through the feats in the database with the following command:
`feat/search <search type> = <search term>`: Searches the feat database for feats matching specific parameters. Valid search term types: `name`, `traits`, `feat_type`, `level`, `class`, `classlevel`, `ancestry`, `skill`, `description` (or `desc`), and `archetype`.

Feat search is paginated. To access pages beyond the first page, add the page number after `feat/search`. For example, `feat/search2 name=familiar`.

When searching by `skill` or `archetype`, we recommend searching with the first word or two of the skill or archetype in question. For example, `feat/search skill=Cooking` will return results with Cooking Lore, and `feat/search archetype=Fighter` will return results with the Fighter Archetype.

**NOTE**: If you search by `classlevel`, you may specify a class followed by a level. For example, `feat/search classlevel = Fighter 2`.

If you search by `level`, you may specify an operator. The searcher understands `<`, `=`, and `>`, and defaults to `=`. For example: `feat/search level = > 5` The operator will be ignored for any search type other than `level`.