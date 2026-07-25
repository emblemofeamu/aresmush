---
toc: Pathfinder Second Edition
summary: Starting character generation - basic information.
aliases:
- cg_baseinfo
---
# Pathfinder 2E Chargen - Basic Character Information

The first thing you'll need to do in the Pathfinder 2E part of the character creation process is set your basic character information.

### Ancestry & Heritage
`cg/set ancestry = <ancestry>`: Sets your ancestry, which is broadly what people your character is descended from. Set your ancestry before choosing `heritage`. 
%tSee [Ancestries](/wiki/mechanics:ancestry) for more information about your `<ancestry>` options.
`cg/set heritage = <heritage>`: Sets your heritage, which is a subset of ancestry. Your heritage helps determine what additional ancestry feats are available to your character and may grant you additional bonuses.
%tSee your ancestry's wiki page for more information about your `<heritage>` options.

### Background
`cg/set background = <background>`: Your character's life before they became a Slayer and a member of the Illuminators.
%tSee [Backgrounds](/wiki/mechanics:backgrounds) for more information about your `<background>` options. 
%t **Note:** To page through `cg/info backgrounds`, add the page number you want to read after `cg/info`, such as `cg/info2 backgrounds`.

### Class & Specialty
`cg/set charclass = <charclass>`: Your character's class; their field of expertise.
%tSee [Classes](/wiki/mechanics:classes) for more information about your class options.
`cg/set specialize = <specialize>`: Many classes have specialties. If yours does, choose it using this input.
%tSee your class wiki page for specialties. 
`cg/set specialize_info = <specialize_info>`: A few classes and class specialties need to choose an option for their specialty. You will be prompted if you need to set this command.

### Faith-related Info
`cg/set alignment = <alignment>`: Your character's alignment. `<alignment>` is a two-letter code. For example, Balanced Light is `BL`. 
%tSee [Alignment](/wiki/mechanics:alignment) for more information.
`cg/set deity = <deity>`: (Optional, except for champions and clerics.) The deity your character venerates the most.
%tSee [Faiths and Gods of Ea](/wiki/theme:deity) for more information.
`cg/set sanctification = <sanctification>`: (Only for clerics and champions.) Your character's choice of sanctification.
%t- Champions may choose between Holy and Unsanctified (although some specialties require Holy sanctification). 
%t- Clerics' sanctification choice depend on their deity choice.
%tFor more information, see the [Champion](/wiki/mechanics:class-champion) or [Cleric](/wiki/mechanics:class-cleric) class pages.

