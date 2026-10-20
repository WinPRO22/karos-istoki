# Continuing the Berneo emulator

This repository is the public, original-client b1008 emulator snapshot for
Berneo, map 19003. Level 45 and the included profession mechanics are in scope.
Other maps and private research are not required dependencies. Read README.md
and skills/karos-berneo-development/SKILL.md before changing gameplay or patches.

Build and test this repository on its own. Do not assume the author's workstation,
private archives, tools or paths exist. Keep generated saves, SQLite databases,
logs, runtime clients and build outputs out of Git. A fresh installation creates
its own character and content database; never overwrite a player's save to make
a test pass.

Separate protocol facts, user-observed behavior and authored balance. The JSON
and INI files under ServerEmulator/data/b1008 are the published runtime source of
truth. Keep inventory/rewards/profession updates atomic and commit before sending
success. Preserve per-session ownership and exact packet lengths/byte order.

One process owns Delphi build output directories at a time. Run affected tests
first, then the public full suite for shared protocol/persistence changes. Build
success is not an in-game compatibility claim. Never automate in-game input or
launch interactive clients as part of an ordinary build/test operation.

Keep the server local to 127.0.0.1. Network hosting/authentication/multiplayer
require a separate design and explicit task; do not expose this demo's test login
to the Internet. Preserve MIT attribution to WinPRO22; do not apply that license
to original client assets.
