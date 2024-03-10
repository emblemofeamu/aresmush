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

`feat/info [<character name>]`: Shows details for all feats <character name> currently possesses. If <character name> is omitted, it will show the details for all of your feats.
`feat <name>`: Shows details for the named feat.
`feat/set <type>[/<restriction>] = <feat name>`: Sets a feat. '<type>' is one of: "general", "skill", "dedication", "charclass", "ancestry", or "special". The optional `<restriction>` parameter is only checked if `<type>` is "special", which is used for feats where you're limited in what you can take.
`feat/options <type>`: Usable only in chargen. Shows all feats for which the character qualifies but does not yet have.
`feat/search <search type> = <search term>`: Searches the feat database for feats matching specific parameters. Valid search types: 'name', 'traits', 'feat_type', 'level', 'class', 'classlevel', 'ancestry', 'skill','description','desc'

If you choose to search by 'classlevel', you may specify a class followed by a level.

`feat/search classlevel = Fighter 2`

Note that if you choose to search by 'level', you may specify an operator. The searcher understands `<`, `=`, and `>`, and defaults to `=`. To specify an operator:

`feat/search level = > 5`

The operator will be ignored for any search type other than 'level'.