"""Reversible, exact-byte patch of the LOCAL b1008 test executable (never memory).

RMB event 4: 455331 -> 47926A. After selection at 479286, route to the
existing 50DF6B sale only for visible CGuiShop (16001). Other inventory
actions keep their original path. Shift uses the existing quantity dialog.

CMessageBox.Update vtable slot 66FEA8: Enter release (1C/9C) dispatches the
existing primary-button handler 45C284 for sale A017, purchase A016, or the
backpack's drop confirmation A03D (owner vtable 671DAC, callback 479153).
The GUI
manager's modal branch 43E346..43E376 skips the other controls that frame,
including chat. No keyboard injection, network change, or OS hook is used.
The purchase quantity dialog uses its own existing button handler 48880F.
Ordinary equipment with drop flag 0 is routed through the native A03D prompt;
flag 1 (non-droppable) and the post-confirmation bypass remain unchanged.

v5 also repairs Tornado's two native range reads: skillLevel +54 (maximum
selection distance) and +64 (cast distance) are both zero in b1008. Only
skill 50221 used 12-unit melee reach in v5. v6 permits up to Body Blow's
highest supported rank (130), plus unchanged target radius from 4E9466.
The SERVER restricts each proc to the admitted source hit's actual reach,
target and lifetime; ordinary-triggered procs retain melee reach. Other
skills retain their original table values.

v7 fixes the active-buff tooltip's modifier lookup at 463040: the native
loop tests each skillLevel+F8 modifier, but loads by the buff's UI slot.
Load from the tested loop pointer instead, preserving each modifier's sign.

v8 routes backpack RMB to the existing stash deposit/quantity handlers when
the personal stash is visible. It chooses an empty base cell; drag remains
available for merging stacks. Native stash RMB withdrawal is unchanged.
v9 resolves that grid through the item manager (50B737), not the GUI object.
v10 adds the missing stash-page RMB event, chooses partial stacks before
empty cells, and lets the server distribute deposit overflow atomically.
v11 lets subtype-7 potions use the native backpack/hotbar serializer during
skills. Potion acknowledgements no longer finish the actor's active skill.
v12 extends the same 130-unit proc range gate to Rock Straight (50224).
Fire, Root and Water keep their archived ranges until their server contracts
are implemented. The server still binds each proc to its source hit's reach.
v13 swaps occupied skill hotbar cells through the native grid setter and two
06/0B adds, and remembers visible rows in b1008-ui.ini beside the executable.
The preference is local, bounded to 0..2, and defaults to one visible row.
v14 also accepts the ID/0/0 skill references produced by native hotbar refresh.
v15 clears the local hero's autorun latch and decoder state after appearance,
preserving its six configured movement keys and all ordinary input handling.
v16 scales the two character-window weapon endpoints for profession120 by
1.20 (half-up after native truncation), matching the permanent server balance.
The common attack base, Fletta and temporary additions remain server-owned.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile
from B1008PortablePaths import paths

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = paths.source / 'AMo.exe'
TARGET = paths.client / 'AMo.exe'
MANIFEST = TARGET.parent / 'LOCAL-CLIENT-MANIFEST.json'
ORIGINAL_HASH = '9d0a4ff1cf224e1637be3c0c99ab60eea962928747e0f1f1baad3fca0e082966'
BASE = 0x400000
CAVE = 0x668450
RMB_HOOK = 0x47928B
UPDATE_SLOT = 0x66FEA8
BUY_COUNT_SLOT = 0x6728E8
DROP_FLAG_HOOK = 0x50FE9B
TORNADO_RANGE_HOOKS = (0x500950, 0x50097F)
BUFF_TOOLTIP_HOOK = 0x463040
STASH_RMB_SLOT = 0x67579C
HOTBAR_SWAP_HOOK = 0x512997
HOTBAR_REMOVE_HOOK = 0x512B94
HOTBAR_INIT_SLOT = 0x671818
HOTBAR_ROW_HOOKS = (0x4732B8, 0x473317)
HERO_APPEARANCE_HOOK = 0x4FD567
PROFESSION_ATTACK_HOOKS = (0x46B898, 0x46B8DA)
LATEST_VERSION = 16


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def u32(data, offset):
    return struct.unpack_from('<I', data, offset)[0]


class Code:
    """Small auditable x86 byte emitter; relative branches resolved by labels."""
    def __init__(self, address):
        self.address, self.data, self.labels, self.fixups = address, bytearray(), {}, []

    def emit(self, hex_bytes):
        self.data.extend(bytes.fromhex(hex_bytes))

    def label(self, name):
        require(name not in self.labels, 'Duplicate label')
        self.labels[name] = self.address + len(self.data)

    def branch(self, opcode, target):
        self.emit(opcode)
        self.fixups.append((len(self.data), target))
        self.data.extend(b'\0' * 4)

    def finish(self):
        for offset, target in self.fixups:
            address = self.labels[target] if isinstance(target, str) else target
            struct.pack_into('<i', self.data, offset, address - (self.address + offset + 4))
        return bytes(self.data)


def generate(original, version=LATEST_VERSION):
    require(version in range(1, LATEST_VERSION + 1), 'Unknown patch version')
    require(digest(original) == ORIGINAL_HASH, 'Archived source changed')
    pe = u32(original, 0x3C)
    opt = pe + 24
    section = opt + struct.unpack_from('<H', original, pe + 20)[0]
    require(u32(original, opt + 28) == BASE, 'Unexpected image base')
    require(struct.unpack_from('<H', original, opt + 70)[0] == 0, 'Unexpected ASLR flags')
    require(original[section:section + 8] == b'.text\0\0\0', 'Unexpected section')
    require(tuple(u32(original, section + n) for n in (8, 12, 16, 20, 36)) ==
            (0x26744A, 0x1000, 0x268000, 0x1000, 0x60000020), 'Unexpected code layout')
    # Both hook sites have file offset == RVA in this fixed original image.
    require(original[RMB_HOOK - BASE:RMB_HOOK - BASE + 5] == bytes.fromhex('e8d8500c00'),
            'Unexpected RMB call')
    require(u32(original, UPDATE_SLOT - BASE) == 0x45C135, 'Unexpected modal vtable')
    require(u32(original, BUY_COUNT_SLOT - BASE) == 0x486E2A, 'Unexpected quantity vtable')
    require(original[DROP_FLAG_HOOK - BASE:DROP_FLAG_HOOK - BASE + 6] ==
            bytes.fromhex('8b45ec8b4060'), 'Unexpected native drop flag load')
    code = Code(CAVE)
    code.label('right_click')
    code.emit('9c 60')                            # pushfd; pushad
    code.emit('a1 6c567000 85c0')                  # active modal?
    code.branch('0f84', 'find_shop')
    code.emit('8078 5f 00')
    code.branch('0f85', 'handled')
    code.label('find_shop')
    if version >= 8:
        code.branch('e8', 'stash_rmb')
        code.emit('85c0')
        code.branch('0f85', 'handled')
    code.emit('8b0d 60417000 85c9')
    code.branch('0f84', 'normal')
    code.emit('81c1 ec7c0000 68 813e0000')          # GUI manager, shop 16001
    code.branch('e8', 0x43D14D)
    code.emit('85c0')
    code.branch('0f84', 'normal')
    code.emit('8138 d4296700')                     # exact CGuiShop type
    code.branch('0f85', 'normal')
    code.emit('8078 5f 00')                        # visible
    code.branch('0f84', 'normal')
    code.emit('83b8 a0000000 00')                  # positive NPC handle
    code.branch('0f8e', 'handled')
    code.emit('85ff')                             # nonempty selected slot
    code.branch('0f88', 'handled')
    code.emit('6683be bc000000 01')                # inventory page 1..7
    code.branch('0f82', 'handled')
    code.emit('6683be bc000000 07')
    code.branch('0f87', 'handled')
    code.emit('8bd8 bfffffffFF')                   # ebx=shop; edi=-1
    code.branch('e8', 0x53E368)
    code.emit('6a2a 8bc8')
    code.branch('e8', 0x53E24E)
    code.emit('85c0')
    code.branch('0f85', 'shift')
    code.branch('e8', 0x53E368)
    code.emit('6a36 8bc8')
    code.branch('e8', 0x53E24E)
    code.emit('85c0')
    code.branch('0f84', 'sell')
    code.label('shift')
    code.emit('bf 2a000000')
    code.label('sell')
    code.branch('e8', 0x50CE86)
    code.emit('57 ffb3 a0000000 53 8bc8')          # shift, NPC, dialog, this
    code.branch('e8', 0x50DF6B)
    code.label('handled')
    code.emit('61 9d')
    code.branch('e9', 0x47958E)                    # original OnMessage epilogue
    code.label('normal')
    code.emit('61 9d')
    code.branch('e8', 0x53E368)                    # displaced original call
    code.branch('e9', 0x479290)

    if version >= 8:
        code.label('stash_rmb')
        code.emit('53 56 57 55')                  # preserve callers' context
        if version >= 10:
            code.emit('83ec04 c70424 ffffffff')   # first empty cell, after partials
        code.emit('81fb b7360000')                # only the backpack
        code.branch('0f85', 'stash_not_open')
        code.emit('8b0d 60417000 85c9')
        code.branch('0f84', 'stash_not_open')
        code.emit('81c1 ec7c0000 68 cb360000')
        code.branch('e8', 0x43D14D)
        code.emit('85c0')
        code.branch('0f84', 'stash_not_open')
        code.emit('8138 4c586700')                # CGuiStore, not a lookalike
        code.branch('0f85', 'stash_not_open')
        code.emit('8078 5f 00')
        code.branch('0f84', 'stash_not_open')
        code.emit('83b8 bc000000 00')
        code.branch('0f8e', 'stash_handled')
        code.emit('85ff')
        code.branch('0f88', 'stash_handled')
        code.emit('6683be bc000000 01')
        code.branch('0f82', 'stash_handled')
        code.emit('6683be bc000000 07')
        code.branch('0f87', 'stash_handled')
        code.emit('8bd8')                         # GUI supplies only the NPC handle
        if version >= 10:
            code.emit('0fb7ae bc000000')          # source bag page
            code.branch('e8', 0x50CE86)
            code.emit('8bc8 68b7360000')
            code.branch('e8', 0x50B737)
            code.emit('85c0')
            code.branch('0f84', 'stash_handled')
            code.emit('55 8bc8')
            code.branch('e8', 0x432438)
            code.emit('85c0')
            code.branch('0f84', 'stash_handled')
            code.emit('8bc8 8b5104 85d2')
            code.branch('0f84', 'stash_handled')
            code.emit('0faf11 3bfa')              # source index < rows * columns
            code.branch('0f83', 'stash_handled')
            code.emit('8bc7 33d2 f77104 8b490c 85c9')
            code.branch('0f84', 'stash_handled')
            code.emit('8b0481 85c0')
            code.branch('0f84', 'stash_handled')
            code.emit('6bd270 03c2 83785400')
            code.branch('0f84', 'stash_handled')
            code.emit('8b6806')                   # source item ID
        if version >= 9:
            code.branch('e8', 0x50CE86)
            code.emit('8bc8 68 cb360000')
            code.branch('e8', 0x50B737)           # separate item-container registry
            code.emit('85c0')
            code.branch('0f84', 'stash_handled')
        code.emit('8bc8 6a0d')                    # data grid 13 (32 base cells)
        code.branch('e8', 0x432438)
        code.emit('85c0')
        code.branch('0f84', 'stash_handled')
        code.emit('8338 04')
        code.branch('0f82', 'stash_handled')
        code.emit('8378 04 08')
        code.branch('0f85', 'stash_handled')
        code.emit('8b70 0c 33ff 85f6')             # rows; destination index
        code.branch('0f84', 'stash_handled')
        code.label('stash_cell')
        code.emit('8bc7 c1e803 8b0486 85c0')
        code.branch('0f84', 'stash_handled')
        code.emit('8bd7 83e207 6bd270 03c2')
        if version >= 10:
            code.emit('83786800')
            code.branch('0f85', 'stash_next_cell')
        code.emit('8378 54 00')                   # empty, unlocked cell
        if version >= 10:
            code.branch('0f84', 'stash_empty_cell')
            code.emit('396806')                   # same ID, capacity remaining
            code.branch('0f85', 'stash_next_cell')
            code.emit('83781800')
            code.branch('0f85', 'stash_next_cell')
            code.emit('8b5054 8b5234 3b5014')
            code.branch('0f87', 'stash_destination')
            code.branch('e9', 'stash_next_cell')
            code.label('stash_empty_cell')
            code.emit('833c24ff')
            code.branch('0f85', 'stash_next_cell')
            code.emit('893c24')
        else:
            code.branch('0f85', 'stash_next_cell')
            code.emit('8378 68 00')
            code.branch('0f84', 'stash_destination')
        code.label('stash_next_cell')
        code.emit('47 83ff20')
        code.branch('0f82', 'stash_cell')
        if version >= 10:
            code.emit('8b3c24 83ffff')
            code.branch('0f85', 'stash_destination')
        code.branch('e9', 'stash_handled')         # full stash must not use/equip item
        code.label('stash_destination')
        code.emit('33f6')                         # default: whole stack
        code.branch('e8', 0x53E368)
        code.emit('6a2a 8bc8')
        code.branch('e8', 0x53E24E)
        code.emit('85c0')
        code.branch('0f85', 'stash_shift')
        code.branch('e8', 0x53E368)
        code.emit('6a36 8bc8')
        code.branch('e8', 0x53E24E)
        code.emit('85c0')
        code.branch('0f84', 'stash_deposit')
        code.label('stash_shift')
        code.emit('be 2a000000')
        code.label('stash_deposit')
        code.branch('e8', 0x50CE86)
        code.emit('8be8 837d04 ff')                # don't overwrite an active drag
        code.branch('0f85', 'stash_handled')
        # 479286 stores RMB selection at +8C/+9C/+98. The original deposit
        # expects drag source +4/+8/+C; the native wrapper cleans it afterward.
        code.emit('8b85 8c000000 894504 8b85 9c000000 894508')
        code.emit('8b85 98000000 89450c')
        code.emit('56 ffb3 bc000000 6a0d 57 68cb360000 8bcd')
        code.branch('e8', 0x5127CB)
        code.emit('8bcd')
        code.branch('e8', 0x50B203)                # same RMB cleanup as 479582
        code.label('stash_handled')
        code.emit('b8 01000000')
        code.branch('e9', 'stash_done')
        code.label('stash_not_open')
        code.emit('33c0')
        code.label('stash_done')
        if version >= 10:
            code.emit('83c404')
        code.emit('5d 5f 5e 5b c3')

    if version >= 10:
        code.label('stash_withdraw_rmb')
        code.emit('837c2404 04')                  # original page ignores event 4
        code.branch('0f85', 0x4C1E1B)
        code.emit('53 56 57 8bf1')
        code.emit('807e5f00')
        code.branch('0f84', 'withdraw_done')
        code.emit('a16c567000 85c0')
        code.branch('0f84', 'withdraw_control')
        code.emit('80785f00')
        code.branch('0f85', 'withdraw_done')
        code.label('withdraw_control')
        code.emit('8b442414 85c0')                # event control after 3 saved regs
        code.branch('0f84', 'withdraw_done')
        code.emit('8b4004 85c0')
        code.branch('0f84', 'withdraw_done')
        code.emit('817808 00f00000')
        code.branch('0f85', 'withdraw_done')
        code.emit('8b9ea8000000 85db')
        code.branch('0f8e', 'withdraw_done')
        code.emit('8b8ea0000000 85c9')
        code.branch('0f84', 'withdraw_done')
        code.branch('e8', 0x4B5671)
        code.emit('83f820')
        code.branch('0f83', 'withdraw_done')
        code.emit('8bf8 33f6')                    # selected base cell; Shift flag
        code.branch('e8', 0x53E368)
        code.emit('6a2a 8bc8')
        code.branch('e8', 0x53E24E)
        code.emit('85c0')
        code.branch('0f85', 'withdraw_shift')
        code.branch('e8', 0x53E368)
        code.emit('6a36 8bc8')
        code.branch('e8', 0x53E24E)
        code.emit('85c0')
        code.branch('0f84', 'withdraw_selected')
        code.label('withdraw_shift')
        code.emit('be2a000000')
        code.label('withdraw_selected')
        code.branch('e8', 0x50CE86)
        code.emit('837804ff')
        code.branch('0f85', 'withdraw_done')
        code.emit('c74004 cb360000 c74008 0d000000 89780c')
        code.emit('57 6a0d 68cb360000 8bc8')
        code.branch('e8', 0x50B22C)
        code.branch('e8', 0x50CE86)
        code.emit('56 53 68cb360000 8bc8')
        code.branch('e8', 0x512429)
        code.branch('e8', 0x50CE86)
        code.emit('8bc8')
        code.branch('e8', 0x50B203)
        code.label('withdraw_done')
        code.emit('b801000000 5f5e5b c20800')

    while len(code.data) % 16:
        code.emit('90')
    code.label('modal_update')
    code.emit('56 8bf1 807e 5f 00')                # preserve esi; visible modal
    code.branch('0f84', 'original_update')
    if version >= 3:
        code.emit('81be e4000000 3da00000')         # native drop confirmation
        code.branch('0f84', 'drop_parent')
    if version >= 2:
        code.emit('81be e4000000 16a00000')         # purchase confirmation
        code.branch('0f84', 'modal_parent')
    code.emit('81be e4000000 17a00000')             # sale confirmation
    code.branch('0f85', 'original_update')
    code.label('modal_parent')
    code.emit('8b86 dc000000 85c0')                # owning shop
    code.branch('0f84', 'original_update')
    code.emit('8138 d4296700')
    code.branch('0f85', 'original_update')
    if version >= 3:
        code.branch('e9', 'parent_visible')
        code.label('drop_parent')
        code.emit('8b86 dc000000 85c0')
        code.branch('0f84', 'original_update')
        code.emit('8138 ac1d6700')                 # exact backpack type
        code.branch('0f85', 'original_update')
        code.emit('6683b8 bc000000 01')            # native backpack pages 1..4
        code.branch('0f82', 'original_update')
        code.emit('6683b8 bc000000 04')
        code.branch('0f87', 'original_update')
        code.label('parent_visible')
    code.emit('8078 5f 00')
    code.branch('0f84', 'original_update')
    code.emit('83be a0000000 00')                  # primary button exists
    code.branch('0f84', 'original_update')
    code.branch('e8', 0x53E368)
    code.emit('6a1c 8bc8')
    code.branch('e8', 0x53E1EC)                    # main Enter release edge
    code.emit('85c0')
    code.branch('0f85', 'confirm')
    code.branch('e8', 0x53E368)
    code.emit('68 9c000000 8bc8')
    code.branch('e8', 0x53E1EC)                    # keypad Enter release edge
    code.emit('85c0')
    code.branch('0f84', 'original_update')
    code.label('confirm')
    code.emit('ffb6 a0000000 6a01 8bce')           # existing Yes button event
    code.branch('e8', 0x45C284)
    code.emit('33c0 40 5e c3')
    code.label('original_update')
    code.emit('8bce 5e')
    code.branch('e9', 0x45C135)
    if version >= 2:
        code.label('buy_count_update')
        code.emit('56 8bf1 807e 5f 00')
        code.branch('0f84', 'original_count_update')
        code.emit('807e 5e 00')
        code.branch('0f84', 'original_count_update')
        for offset in ('a0000000', 'a4000000', 'a8000000', 'ac000000'):
            code.emit('83be ' + offset + ' 00')    # item, NPC, edit, primary button
            code.branch('0f84', 'original_count_update')
        code.branch('e8', 0x53E368)
        code.emit('6a1c 8bc8')
        code.branch('e8', 0x53E1EC)
        code.emit('85c0')
        code.branch('0f85', 'confirm_count')
        code.branch('e8', 0x53E368)
        code.emit('68 9c000000 8bc8')
        code.branch('e8', 0x53E1EC)
        code.emit('85c0')
        code.branch('0f84', 'original_count_update')
        code.label('confirm_count')
        # Consume the real release through the client's native input API;
        # other controls must not interpret this same Enter as opening chat.
        for key in ('6a1c', '68 9c000000'):
            code.branch('e8', 0x53E368)
            code.emit('6a00 ' + key + ' 8bc8')
            code.branch('e8', 0x53E188)
        code.emit('ffb6 ac000000 6a01 8bce')
        code.branch('e8', 0x48880F)
        code.emit('33c0 40 5e c3')
        code.label('original_count_update')
        code.emit('8bce 5e')
        code.branch('e9', 0x486E2A)
    if version >= 4:
        code.label('drop_flag')
        code.emit('8b45ec')                        # template from native local
        code.emit('8378 60 00')                    # only ordinary droppable items
        code.branch('0f85', 'native_drop_flag')
        code.emit('8378 20 01')                    # armor slots 1..4, weapon 7
        code.branch('0f82', 'native_drop_flag')
        code.emit('8378 20 07')
        code.branch('0f84', 'confirm_gear_drop')
        code.emit('8378 20 04')
        code.branch('0f87', 'native_drop_flag')
        code.label('confirm_gear_drop')
        code.emit('b8 02000000')
        code.branch('e9', 0x50FEA1)                # existing pending item + prompt
        code.label('native_drop_flag')
        code.emit('8b40 60')                       # displaced original flag load
        code.branch('e9', 0x50FEA1)
    if version >= 5:
        for hook, field in zip(TORNADO_RANGE_HOOKS, (0x54, 0x64)):
            require(original[hook - BASE:hook - BASE + 6] ==
                    bytes.fromhex('8b45f0dc40') + bytes([field]), 'Unexpected skill range read')
            label = 'tornado_range_' + str(field)
            code.label(label)
            code.emit('9c 8b45f0 8138 2dc40000')   # flags; displaced EAX load; skill ID
            if version >= 12:
                code.branch('0f84', label + '_proc')
                code.emit('8138 30c40000')        # Rock Straight 50224 only
            code.branch('0f85', label + '_original')
            if version >= 12:
                code.label(label + '_proc')
            code.emit(('6882000000' if version >= 6 else '6a0c') + ' da0424 8d642404')
            code.branch('e9', label + '_done')
            code.label(label + '_original')
            code.emit('dc40' + format(field, '02x'))
            code.label(label + '_done')
            code.emit('9d')
            code.branch('e9', hook + 6)
    if version >= 11:
        for label, native, allowed in (
                ('potion_hotbar', 0x513878, 0x51392F),
                ('potion_backpack', 0x511769, 0x5117C8)):
            code.label(label)
            code.emit('9c 50 8b46 54 8378 10 07') # preserve flags/EAX; known type-2 entry
            code.branch('0f84', label + '_allow')
            code.emit('58 9d')
            if label == 'potion_hotbar':
                code.branch('e8', 0x4E2149)       # displaced native state lookup
            else:
                code.emit('a1 60417000')          # displaced game pointer load
            code.branch('e9', native)
            code.label(label + '_allow')
            code.emit('58 9d')
            code.branch('e9', allowed)
        code.label('potion_ack')
        code.emit('9c 837b 0c 02')
        code.branch('0f85', 'potion_ack_native')
        code.emit('837b 10 07')
        code.branch('0f85', 'potion_ack_native')
        code.emit('9d')
        code.branch('e9', 0x52601B)
        code.label('potion_ack_native')
        code.emit('9d 8bc8')
        code.branch('e8', 0x4ED2F8)
        code.branch('e9', 0x52601B)
    if version >= 13:
        code.label('hotbar_swap')
        code.emit('8d4748 894548 9c60')           # displaced target triplet; preserve context
        for offset in ('40', '6c'):
            code.emit('837d' + offset + '24')    # unsigned indices 0..35
            code.branch('0f83', 'hotbar_swap_native')
        code.emit('8b4540 3b456c')
        code.branch('0f84', 'hotbar_swap_native')
        for reg in ('7e', '7f'):                 # positive skill references: restored or refreshed
            code.emit('83' + reg + '4800')
            code.branch('0f8e', 'hotbar_swap_native')
            if version >= 14:
                code.emit('83' + reg + '4c00')
                code.branch('0f84', 'hotbar_page_' + reg)
            code.emit('83' + reg + '4c09')
            code.branch('0f85', 'hotbar_swap_native')
            if version >= 14:
                code.label('hotbar_page_' + reg)
        code.emit('8b455c 85c0')
        code.branch('0f84', 'hotbar_swap_native')
        for field in ('6c', '70'):
            code.emit('8378' + field + '00')
            code.branch('0f85', 'hotbar_swap_native')
        code.emit('837b0400')
        code.branch('0f8e', 'hotbar_swap_native')
        code.emit('897550 83ec70 8bf7 8bfc 6a1c59 fc f3a5')  # snapshot target, not live copy
        # Cell+28 owns a std::string-like texture path. A shallow snapshot would
        # retain a buffer that the first native setter can overwrite or free.
        code.emit('8d4c2428')
        code.branch('e8', 0x4041A0)              # fresh snapshot string, thiscall plain ret
        code.emit('8b4548 83e820 6aff 6a00 50 8d4c2434')
        code.branch('e8', 0x404880)              # deep assign original target string; ret 0C
        code.emit('ff7550 8b456c 33d2 f77304 5250 8bcb')
        code.branch('e8', 0x505BB5)              # native source -> target (row,col,cell)
        code.emit('54 8b4540 33d2 f77304 5250 8bcb')
        code.branch('e8', 0x505BB5)              # native snapshot -> source
        code.emit('6a00 6a01 8d4c2430')
        code.branch('e8', 0x404B10)              # destroy only snapshot string; ret 8
        code.emit('83c470 8b4d5c')
        code.branch('e8', 0x50B7B4)              # clear drag without deleting either cell
        code.emit('c74568 03000000 619d')
        code.branch('e9', 0x512B0B)
        code.label('hotbar_swap_native')
        code.emit('619d')
        code.branch('e9', HOTBAR_SWAP_HOOK + 6)

        code.label('hotbar_second_add')
        code.emit('9c 837d6803')
        code.branch('0f85', 'hotbar_remove_native')
        code.emit('9d c645fc02 8b5550 ff7250 ff724c ff7248 ff7540 50 8d452c50')
        code.branch('e8', 0x51280F)              # same native add serializer as first cell
        code.emit('83c40c')                      # only extra triplet; native cleans original 12
        code.branch('e9', 0x512BA5)
        code.label('hotbar_remove_native')
        code.emit('9d ff7540 c645fc02')
        code.branch('e9', HOTBAR_REMOVE_HOOK + 7)

        code.label('hotbar_init')
        code.emit('56 8bf1')
        code.branch('e8', 0x473B21)              # thiscall, no arguments, plain ret
        code.emit('9c60 83c8ff')                 # preserve original return and flags
        code.branch('e8', 'hotbar_preference')
        code.emit('8bd8')
        for field in ('d8', 'dc'):
            code.emit('8bbe' + field + '000000 85ff')
            code.branch('0f84', 'hotbar_init_next_' + field)
            code.emit('53 8bcf')
            code.branch('e8', 0x4516B1)
            code.emit('57 6a13 8bce')
            code.branch('e8', 0x47327D)          # native selector event applies row visibility
            code.label('hotbar_init_next_' + field)
        code.emit('619d 5e c3')
        for hook in HOTBAR_ROW_HOOKS:
            label = 'hotbar_save_' + hex(hook)[2:]
            code.label(label)
            code.emit('8986b8000000 9c60 83f802')
            code.branch('0f87', label + '_done')
            code.branch('e8', 'hotbar_preference')
            code.label(label + '_done')
            code.emit('619d')
            code.branch('e9', hook + 6)

        code.label('hotbar_preference')
        # EAX=-1 reads, 0..2 writes. No writable pointers/buffers in the RX cave.
        # Locals: mode -4, readAPI -8, writeAPI -C, result -14, section -1C,
        # key -20, empty -24, value -28, MAX_PATH buffer -130.
        code.emit('55 8bec 81ec30010000 535657 8945fc 33c0 8945ec 8945dc')
        def stack_string(value):
            raw = value.encode('ascii') + b'\0'
            raw += b'\0' * (-len(raw) % 4)
            for pos in range(len(raw) - 4, -1, -4):
                code.emit('68' + raw[pos:pos + 4].hex())
        stack_string('kernel32.dll')
        code.emit('54 ff15 68926600 85c0')
        code.branch('0f84', 'hotbar_preference_done')
        code.emit('8bd8')
        for name, offset in (('GetPrivateProfileStringA', 'f8'),
                             ('WritePrivateProfileStringA', 'f4')):
            stack_string(name)
            code.emit('54 53 ff15 38926600 8945' + offset)
        code.emit('8dbdd0feffff 6804010000 57 6a00 ff15 34926600 85c0')
        code.branch('0f84', 'hotbar_preference_done')
        code.emit('3d04010000')                   # reject truncated executable path
        code.branch('0f83', 'hotbar_preference_done')
        code.emit('8bf7 8bd7')                    # last path separator, initially buffer start
        code.label('hotbar_path_scan')
        code.emit('8a06 84c0')
        code.branch('0f84', 'hotbar_path_ready')
        code.emit('3c5c')
        code.branch('0f84', 'hotbar_path_separator')
        code.emit('3c2f')
        code.branch('0f85', 'hotbar_path_next')
        code.label('hotbar_path_separator')
        code.emit('8d5601')
        code.label('hotbar_path_next')
        code.emit('46')
        code.branch('e9', 'hotbar_path_scan')
        code.label('hotbar_path_ready')
        code.emit('8bc2 2bc7 3df7000000')          # room for 12-char filename plus NUL
        code.branch('0f87', 'hotbar_preference_done')
        stack_string('b1008-ui.ini')
        code.emit('8bf4 8bfa 6a0d59 fc f3a4')
        stack_string('Hotbar')
        code.emit('8965e4')
        stack_string('VisibleRows')
        code.emit('8965e0 837dfcff')
        code.branch('0f85', 'hotbar_preference_write')
        code.emit('837df800')
        code.branch('0f84', 'hotbar_preference_done')
        code.emit('8d85d0feffff 50 6a04 8d45d850 8d45dc50 ff75e0 ff75e4 ff55f8')
        code.emit('83f801')
        code.branch('0f85', 'hotbar_preference_done')
        code.emit('0fb645d8 83e830 83f802')
        code.branch('0f87', 'hotbar_preference_done')
        code.emit('8945ec')
        code.branch('e9', 'hotbar_preference_done')
        code.label('hotbar_preference_write')
        code.emit('837df400')
        code.branch('0f84', 'hotbar_preference_done')
        code.emit('8b45fc 83f802')
        code.branch('0f87', 'hotbar_preference_done')
        code.emit('83c030 8945d8 8d85d0feffff50 8d45d850 ff75e0 ff75e4 ff55f4')
        code.label('hotbar_preference_done')
        code.emit('8b45ec 8da5c4feffff 5f5e5b c9c3')

    if version >= 15:
        code.label('hero_appearance_input_reset')
        code.emit('c686e704000000')              # replay native hero+4E7 reset
        code.emit('c686e404000000')              # local hero autorun latch
        code.emit('c786a2050000 00000000')        # decoder+6..9; key selectors +0..5 stay intact
        code.emit('c786a6050000 00000000')        # decoder+A..D
        code.emit('66c786aa050000 0000')          # decoder+E..F
        code.emit('c686ac05000000')              # decoder+10
        code.branch('e9', HERO_APPEARANCE_HOOK + 7)

    if version >= 16:
        code.label('profession_weapon_attack')
        code.emit('9c 52 51')                    # preserve flags/EDX/ECX
        code.emit('8b96a8000000 85d2')           # GUI's local character wrapper
        code.branch('0f84', 'profession_attack_replay')
        code.emit('8b5204 85d2')                 # charData
        code.branch('0f84', 'profession_attack_replay')
        code.emit('6681ba0e060000 7800')         # actual profession, both ranks
        code.branch('0f85', 'profession_attack_replay')
        code.emit('85c0')                       # native endpoint must be nonnegative
        code.branch('0f88', 'profession_attack_replay')
        code.emit('6bc006 83c002 31d2 b905000000 f7f1')  # (weapon*6+2)//5
        code.label('profession_attack_replay')
        code.emit('59 5a 9d 894508 db4508 c3')    # replay MOV/FILD then return

    payload = code.finish()
    start, end = CAVE - BASE, CAVE - BASE + len(payload)
    require(end <= 0x269000, 'Code exceeds padding')
    require(original[0x26844A:end] == b'\0' * (end - 0x26844A), 'Code padding occupied')
    generated = bytearray(original)
    generated[start:end] = payload
    generated[RMB_HOOK - BASE] = 0xE9
    struct.pack_into('<i', generated, RMB_HOOK - BASE + 1, CAVE - RMB_HOOK - 5)
    struct.pack_into('<I', generated, UPDATE_SLOT - BASE, code.labels['modal_update'])
    hooks = [RMB_HOOK, UPDATE_SLOT]
    if version >= 2:
        struct.pack_into('<I', generated, BUY_COUNT_SLOT - BASE, code.labels['buy_count_update'])
        hooks.append(BUY_COUNT_SLOT)
    if version >= 4:
        generated[DROP_FLAG_HOOK - BASE] = 0xE9
        struct.pack_into('<i', generated, DROP_FLAG_HOOK - BASE + 1,
                         code.labels['drop_flag'] - DROP_FLAG_HOOK - 5)
        generated[DROP_FLAG_HOOK - BASE + 5] = 0x90
        hooks.append(DROP_FLAG_HOOK)
    if version >= 5:
        for hook, field in zip(TORNADO_RANGE_HOOKS, (0x54, 0x64)):
            generated[hook - BASE] = 0xE9
            struct.pack_into('<i', generated, hook - BASE + 1,
                             code.labels['tornado_range_' + str(field)] - hook - 5)
            generated[hook - BASE + 5] = 0x90
            hooks.append(hook)
    if version >= 7:
        offset = BUFF_TOOLTIP_HOOK - BASE
        require(original[offset:offset + 8] == bytes.fromhex('8b458403c6ff3418'),
                'Unexpected buff tooltip modifier lookup')
        # mov eax,[ebp-68]; push [eax]; nop*3. The pointer advances once
        # per modifier at 463154, independently of the icon's position.
        generated[offset:offset + 8] = bytes.fromhex('8b4598ff30909090')
        hooks.append(BUFF_TOOLTIP_HOOK)
    if version >= 10:
        require(u32(original, STASH_RMB_SLOT - BASE) == 0x4C1E1B, 'Unexpected stash event vtable')
        struct.pack_into('<I', generated, STASH_RMB_SLOT - BASE, code.labels['stash_withdraw_rmb'])
        hooks.append(STASH_RMB_SLOT)
        # Native deposit disallows a spill across cells before sending. Preserve
        # bankability checks; the server now owns atomic capacity/distribution.
        for address, expected, replacement in (
            (0x512260, '7642', 'eb42'),
            (0x47CB89, '75e8', '9090')):
            offset = address - BASE
            require(original[offset:offset + len(bytes.fromhex(expected))] == bytes.fromhex(expected), 'Unexpected stash capacity branch')
            generated[offset:offset + len(bytes.fromhex(expected))] = bytes.fromhex(replacement)
            hooks.append(address)
    if version >= 11:
        for address, expected, label in (
                (0x513873, 'e8d1e8fcff', 'potion_hotbar'),
                (0x511764, 'a160417000', 'potion_backpack'),
                (0x526014, '8bc8e8dd72fcff', 'potion_ack')):
            offset = address - BASE
            raw = bytes.fromhex(expected)
            require(original[offset:offset+len(raw)] == raw, 'Unexpected potion branch')
            generated[offset:offset+len(raw)] = b'\xe9' + struct.pack('<i', code.labels[label]-address-5) + b'\x90'*(len(raw)-5)
            hooks.append(address)
    if version >= 13:
        require(u32(original, HOTBAR_INIT_SLOT - BASE) == 0x473B21,
                'Unexpected hotbar initialization vtable')
        struct.pack_into('<I', generated, HOTBAR_INIT_SLOT - BASE, code.labels['hotbar_init'])
        hooks.append(HOTBAR_INIT_SLOT)
        for address, expected, label in (
                (HOTBAR_SWAP_HOOK, '8d4748894548', 'hotbar_swap'),
                (HOTBAR_REMOVE_HOOK, 'ff7540c645fc02', 'hotbar_second_add'),
                *((hook, '8986b8000000', 'hotbar_save_' + hex(hook)[2:])
                  for hook in HOTBAR_ROW_HOOKS)):
            offset, raw = address - BASE, bytes.fromhex(expected)
            require(original[offset:offset + len(raw)] == raw, 'Unexpected hotbar hook')
            generated[offset:offset + len(raw)] = b'\xe9' + struct.pack(
                '<i', code.labels[label] - address - 5) + b'\x90' * (len(raw) - 5)
            hooks.append(address)
    if version >= 15:
        offset = HERO_APPEARANCE_HOOK - BASE
        require(u32(original, 0x67871C + 0x38 - BASE) == 0x4FD52B,
                'Unexpected local CHero appearance vtable')
        require(original[offset:offset + 7] == bytes.fromhex('c686e704000000'),
                'Unexpected local hero appearance reset')
        generated[offset:offset + 7] = b'\xe9' + struct.pack(
            '<i', code.labels['hero_appearance_input_reset'] - HERO_APPEARANCE_HOOK - 5) + b'\x90\x90'
        hooks.append(HERO_APPEARANCE_HOOK)
    if version >= 16:
        for hook in PROFESSION_ATTACK_HOOKS:
            offset = hook - BASE
            require(original[offset:offset + 6] == bytes.fromhex('894508db4508'),
                    'Unexpected native weapon endpoint renderer')
            generated[offset:offset + 6] = b'\xe8' + struct.pack(
                '<i', code.labels['profession_weapon_attack'] - hook - 5) + b'\x90'
            hooks.append(hook)
    struct.pack_into('<I', generated, section + 8, end - 0x1000)
    return bytes(generated), dict(version=version, sourceSHA256=ORIGINAL_HASH,
        generatedSHA256=digest(generated), codeVA=CAVE, codeBytes=len(payload),
        labels=code.labels, hooks=hooks, textSizeOffset=section + 8)


def detect_version(original, current):
    """Recognize exact generated images only; zero denotes the archived image."""
    require(digest(original) == ORIGINAL_HASH, 'Archived source changed')
    if current == original:
        return 0
    for version in range(LATEST_VERSION, 0, -1):
        if current == generate(original, version)[0]:
            return version
    raise ValueError('Unknown local changes; refusing overwrite')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['apply', 'verify', 'restore'])
    args = parser.parse_args()
    for file in (SOURCE, TARGET, MANIFEST):
        require(str(file.resolve()).lower() == str(file.absolute()).lower(), 'Redirected file')
        require(file.stat().st_nlink == 1, 'Hard-linked file')
    # Patching a running executable or racing client saves is not supported.
    if args.mode != 'verify':
        import subprocess
        processes = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], check=True,
                                   stdout=subprocess.PIPE).stdout.lower()
        require(b'"amo.exe"' not in processes, 'Close the game before patching')
    original = SOURCE.read_bytes()
    generated, info = generate(original)
    current, manifest_bytes = TARGET.read_bytes(), MANIFEST.read_bytes()
    manifest = json.loads(manifest_bytes)
    records = [r for r in manifest['Files'] if r['Path'].replace('\\', '/') == 'AMo.exe']
    require(len(records) == 1, 'Missing/duplicate exe record')
    require(records[0]['SHA256'].lower() == digest(current), 'Manifest hash mismatch')
    if args.mode == 'verify':
        require(current == generated, 'Client differs from exact trade UI patch')
        require(manifest.get('TradeUI') == info, 'Patch manifest mismatch')
    else:
        detect_version(original, current)
        result = generated if args.mode == 'apply' else original
        if current != result:
            backup_root = paths.backups
            backup_root.mkdir(parents=True, exist_ok=True)
            require(backup_root.resolve() == backup_root, 'Redirected backup directory')
            backup = Path(tempfile.mkdtemp(prefix='trade-ui-', dir=backup_root))
            (backup / 'AMo.exe').write_bytes(current)
            (backup / MANIFEST.name).write_bytes(manifest_bytes)
            records[0]['SHA256'] = digest(result)
            if args.mode == 'apply':
                manifest['TradeUI'] = info
                if 'AMo.exe' not in manifest['Changed']:
                    manifest['Changed'].append('AMo.exe')
            else:
                manifest.pop('TradeUI', None)
                manifest['Changed'] = [p for p in manifest['Changed'] if p != 'AMo.exe']
            # Replace only the guarded test executable; original remains read-only.
            pending = TARGET.with_suffix('.trade-ui.tmp')
            with pending.open('xb') as f:
                f.write(result)
            os.replace(pending, TARGET)
            MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
            print('Backup:', backup)
        require(TARGET.read_bytes() == result, 'Write verification failed')
    require(digest(SOURCE.read_bytes()) == ORIGINAL_HASH, 'Archived source was modified')
    print('PASS:', args.mode, 'trade UI;', info['codeBytes'], 'bytes; SHA256', digest(TARGET.read_bytes()))


if __name__ == '__main__':
    main()
