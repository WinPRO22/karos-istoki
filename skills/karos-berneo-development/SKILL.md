---
name: karos-berneo-development
description: Extend or debug the public Karos Istoki b1008 Berneo emulator, including Delphi protocol handlers, gameplay catalogs, persistence and compatibility patches. Use for this original-client emulator, not unrelated engines or clients.
---

# Karos Berneo development

Locate the repository root through its README and ServerEmulator directory;
never assume an author-specific absolute path. Read AGENTS.md and the relevant
runtime catalog before editing. The scope is b1008, map 19003, level 45; an
unimplemented mechanic is not established by the presence of a packet constant.

## Find the owning mechanism

- Wire/session lifecycle: `Emulator.Protocol.B1008.pas`, `Emulator.Session.pas`
  and its mechanism-specific include files.
- Inventory and transactional state: `Emulator.LootStore.B1008.pas` and its
  include files; inventory, equipment, quest and profession units define rules.
- World and economy: `data/b1008/berneo-v1.json`, NPC/shop/quest/item catalogs;
  `balance-v2.ini`, `rates-v1.ini`, `drop-v1.ini`, `potions-v1.ini`.
- Client compatibility: explicitly shipped scripts under `ServerEmulator/tools`.
  A binary patch must reject unknown input bytes and preserve an original copy.

Read only the mechanism's sources and tests first. Establish the request,
response and persisted state transition before changing an unknown packet.
Do not invent packet fields from a similar build. Keep intentional balance
changes distinct from recovered client facts.

## Implement and verify

Use a disposable directory and new character/database paths for tests. Preserve
the fixed local demo login and loopback binding unless the task explicitly
replaces their design. Do not use production saves as fixtures.

Keep update operations atomic: validate ownership, quantities, slots and funds;
persist the accepted transaction; then emit success and absolute state updates.
Test rejection paths and replay/reconnect where the operation can duplicate or
lose an item or reward. Avoid parallel compilers sharing DCU/output folders.

Use the exported `ServerEmulator/Build.ps1` test selection described by the
README. Do not restore private archive dependencies to satisfy a test. If a
needed original client is absent, report that prerequisite; do not silently
substitute another build. Public portable tests and optional original-client
comparisons must remain distinguishable.

After a coherent batch, prepare one short manual route covering the changed
transitions. The player performs game input. If it fails, diagnose that exact
transition and repeat only the affected segment. Report compiled, automated
tests, manual observations and unverified behavior separately.

Do not publish saves, logs, credentials or original assets as source fixtures.
Preserve the WinPRO22 attribution and the separate third-party notices. A task
to edit code does not itself request a release or external publication.
