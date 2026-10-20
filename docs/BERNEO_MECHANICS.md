# Published Berneo mechanics and evidence boundary

This document describes the public runtime configuration, not a claim that the
original server formulas were recovered. The source and catalogs are the
authoritative implementation. Original client behavior, historical observations
and authored balance must remain distinguishable when continuing development.

## Runtime scope

- Map 19003, Berneo; 955 creatures, 29 NPC definitions, 16 shops, 41 enabled quests.
- Player level cap 45. Original three-class selection; no experimental classes.
- Local demo account and one persisted character; no Internet authentication.
- Public data covers the implemented Berneo route. Disabled unsupported features
  are not acceptance claims. Other maps and research archives are not published.

## Selected balance decisions

| Mechanism | Published configuration |
|---|---|
| Rates | Experience, drop, Fletta and carats independently default to ×1 |
| Monster scaling | Fixed monster level; base combat stats grow 8% per level |
| Base monster model | HP 50, attack 13–17, physical defense 15 |
| Monster attack interval | 140% of the original nominal interval |
| Sword / spear ordinary attack speed | 110% / 90%; weapon subtype affects playback |
| Spear profession identity | Physical attack 120%, physical defense 108% |
| Ordinary PvE MISS+FAIL | Equal level 2%; monster +4 levels 30%; player +3 levels 0%; attack-rating bonus reduces failure |
| Critical damage | 120% total before integer rounding |
| HP / MP potions | Separate family cooldowns of 100 ms |
| Returning Stone | 600 seconds, persisted cooldown |
| Stacks | Equipment individually; ordinary stackable items up to 100 |
| Ground item lifetime | 60 seconds for monster drops and discarded items |
| Fletta combined effects | 12.5% eligible activation; no reroll while active |

At drop rate ×1: one carat bag, one regular bag and a separate 5% equipment
roll. At ×5: one carat bag, five regular bags and a separate 25% equipment roll.
Carat amount uses its own rate. Quest drops have separate rules. Gear-tier
transition weights are in `drop-v1.ini`; do not confuse tier selection with
the probability of receiving an equipment item.

The detailed player thresholds, professions, skills and rewards are shipped in
`ServerEmulator/data/b1008`, not in an external private table. Preserve cross-file
item/quest/NPC references when editing these files.

## Evidence and verification

The developer and player previously checked core Berneo combat, inventory,
shops, storage, return, quests and client patches in interactive sessions.
This does not prove every profession, recipe or quest combination. Automated
tests validate specific packet, state and persistence contracts; they do not
replace an interactive test of a newly packaged client/server pair.

The publication process records fresh automated results separately and requires
a consolidated manual release check before publication. No numeric claim such
as “100% original” or “all mechanics restored” is made.
