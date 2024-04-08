---
toc: Pathfinder Second Edition
summary: Admin commands to award players.
aliases:
- admin awards
- award/xp
- award/prp
---

# Admin Commands - Handing Out Awards

`award/xp <player>=<amount>[/<reason>]`: Awards player XP with an optional reason for the listxp function.
`award/prp <prp-type>/<player type> = <player list>`: Automatically awards a PRP. 

* PRP type is one of 'standard' or 'dc'. 
* Player type is one of 'player' or 'runner'. 
* Player list is a space-separated list of names. 

See `help pay` for how to hand out money. 

There is also a small toy that allows admin to acknowledge players for what makes them unique. These are often OOC jokes or actions that deserve to be commemorated. To award these: 

`knownfor <player> = <item>`