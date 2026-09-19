# Karos: Истоки — back to Berneo

[Русский](README.md) · **English** · [Español](README.es.md)

**Exploring old Karos clients and bringing the early game back to life, one mechanic at a time.**

Remember the first spiders outside Berneo, your starter sword, and your first Fletta points? We want to take that journey again — starting with a 2009 client, preserving its atmosphere, and gradually reconstructing how the game played.

> 📣 **Follow development: [t.me/karos_istoki](https://t.me/karos_istoki)**
>
> Project updates, gameplay test results, and discoveries from old builds.

## About the project

Karos: Истоки ("Origins") is an independent fan project researching old Karos versions and developing a server emulator for them.

Our starting point is **NHN EN CBT1, build b1008, from 2009**. We begin with a small, playable slice of the game, test it in the original client, and expand it step by step.

The server is written in **Delphi**. Testing currently takes place locally. This repository is the project's public information page, not a downloadable, ready-to-run server release.

## What works today

- **Getting into the game:** login, character creation and selection, and entering the world.
- **A livelier Berneo:** 101 Little Spiders placed across the map, with independent patrols, pursuit, return to their territory, group combat, and respawning.
- **Combat:** auto-attacks, animations, sounds, damage numbers, weapon-based damage ranges, and critical hits.
- **Character stats and equipment:** starting attributes and gear, equipping and unequipping items, and updated stat displays.
- **Inventory and loot:** drops appear when a monster dies; pickup, moving and dropping items, Shift stack splitting, and merging identical stacks are implemented.
- **Carats:** represented both as an inventory item and as the displayed currency balance, with matching changes when picked up or dropped.
- **Character progression:** experience from kills, leveling up, the first quest and its reward, and beginner potions.
- **Death and recovery:** returning to the Memory Stone, experience penalties, and regeneration while out of combat and out of combat stance.
- **Persistence:** progress, inventory contents and slot positions, and equipped gear survive restarts.

These features work in a local prototype. The complete world, full content, and multiplayer stability are still ahead of us.

## Reconstructing the balance

We compare client resources, archived websites, old guides, screenshots, videos, and players' recollections.

Confirmed values are kept separate from estimates. When the original server formula is unknown, we use a working reconstruction and test it in-game. Some parameters come from later versions and are not presented as verified CBT1 values.

We do not claim a percentage of accuracy against the original balance yet. For example, the current test loot still needs to be replaced with historically supported drop tables.

## Roadmap

1. **Research old builds.** Compare versions, mechanics, lore, and resources; look for traces of unused content.
2. **Expand the playable prototype.** Develop combat, quests, monsters, items, skills, Fletta, and the economy.
3. **Support additional early clients.** Preserve build-specific differences through separate protocol and data profiles.
4. **Prepare a public test.** Gather feedback and test the server and client with multiple players.
5. **Optimize the server.** Test load handling, reliability, and data persistence.
6. **Publish the emulator's source code on GitHub.** Provide detailed instructions for building, configuring, and running your own server.
7. **Lay the groundwork for a future remake.** Bring together research and player feedback, then plan a version on another engine that stays close to the original mechanics while allowing further development.

Progress depends on research and test results. No public launch date has been announced.

## How to help

Materials from early Karos are especially useful:

- screenshots of character stats, items, quest rewards, and the interface;
- videos of combat, leveling, trading, crafting, and other mechanics;
- links to old guides, forums, and archived pages;
- memories tied to a specific version: leveling pace, drops, monster behavior, and class differences.

Where possible, include the year, region, language, or build number. This helps us avoid mixing different versions of the game.

**Follow the [Telegram channel](https://t.me/karos_istoki) for research and project updates.**

## Can I play yet?

Development and testing are currently local. Opportunities to join a public test will be announced on Telegram.

## Will the source code be published?

Yes. Publishing the emulator's source code and setup instructions is part of the roadmap. For now, this repository introduces the project and directs visitors to development updates.

---

This is an unofficial project with no affiliation to the developers or publishers of the original game. Names and original game materials belong to their respective rights holders.

**[Follow development on Telegram →](https://t.me/karos_istoki)**
