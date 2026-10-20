# Karos: Istoki — Berneo
[Русский](README.md) · **English** · [Español](README.es.md)

A server emulator for the original **Karos NHN EN CBT1 b1008 (14 August 2009)**.
Author: [WinPRO22](https://github.com/WinPRO22). [Project news](https://t.me/karos_istoki).

This is the public snapshot of a closed development milestone: **Berneo only,
with progression up to level 45**. The source is available for further community
development. This is a local single-player build, not a production MMO server.

## Included
- Login, character creation and persistence.
- 955 creatures, 29 NPCs, 16 shops and 41 enabled Berneo quests.
- Combat, aggro, respawn, equipment, progression, professions and skills.
- Inventory, loot, shops, storage, return stone, Fletta, crafting and enhancements.
- Authored client patches for right-click actions, Enter confirmations,
  quickbar swaps and row persistence, buffs and combat-state fixes.

Swordsman and its professions have received the most work. An implemented handler
does not imply every combination was tested. Balance includes authored formulas.
Other maps, private research and the new engine are outside this release.

## Download and run
Download **both ZIP archives** from [Releases](https://github.com/WinPRO22/karos-istoki/releases):
the b1008 client and the Win64 emulator. Prebuilt packages do not require Delphi.

1. Extract the emulator into a writable folder, such as `C:\Games\KarosIstoki`.
2. Extract the client beside it, producing `client\AMo.exe`.
3. Open PowerShell in the emulator folder and run:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-Berneo.ps1 -ClientDirectory .\client`
4. Use the demo login **test**, password **test**, and create a character.
   No developer save is included.
5. After closing the game, stop the server:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-Berneo.ps1`

The server binds only to `127.0.0.1:10001`. Do not open it to the Internet or
change firewall rules. Default rates and movement speed are **×1**.
Do not mix the release client with an updater or another build's resources.

## Build and data
Windows x64 and Delphi with the Win64 compiler, VCL, Indy and FireDAC are required.
The preparation environment uses Delphi 37.0. Put `dcc64.exe` on PATH and run
`.\ServerEmulator\Build.ps1` from the repository root.
This builds programs and runs the public standalone tests without launching the
game. Use `-SkipTests` for a build only.

Runtime catalogs: `ServerEmulator/data/b1008`. New saves are created there as
`test-character.b1008*`; the content database is
`ServerEmulator/data/karos-emulator.sqlite3`. Back up data with the server
stopped before updating. Do not overwrite your saves with release files.

Developer and AI-agent workflow:
[SKILL.md](skills/karos-berneo-development/SKILL.md).
Public tests need no private archives and do not replace gameplay verification.
Publication also requires a separate manual test of the packaged client/server;
its result is recorded in the release description.

## License
Project-authored code and tools use [MIT](LICENSE); retain attribution to **WinPRO22**.
Original client assets are not licensed under MIT. See
[third-party notices](THIRD_PARTY_NOTICES.md). This is an unofficial project.
