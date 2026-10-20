"""Execute the patch's x86 instructions against synthetic UI objects, offline.

No game process, input, or game memory is accessed. Test-only dependencies:
capstone and unicorn (Python environment or BERNEO_PATCH_TEST_DEPS).
Set BERNEO_SOURCE_CLIENT to the unchanged original unpacked b1008 directory.
"""
import importlib.util
import os
from pathlib import Path
import struct
import sys

project = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(project / 'tools'))
if os.environ.get('BERNEO_PATCH_TEST_DEPS'):
    sys.path.insert(0, os.environ['BERNEO_PATCH_TEST_DEPS'])
if not os.environ.get('BERNEO_SOURCE_CLIENT'):
    raise RuntimeError('Set BERNEO_SOURCE_CLIENT to the unchanged original b1008 directory')
from capstone import Cs, CS_ARCH_X86, CS_MODE_32
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX,
    UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP,
    UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EFLAGS)

spec = importlib.util.spec_from_file_location('trade_patch', project / 'tools/Patch-B1008TradeUI.py')
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
original = patch.SOURCE.read_bytes()
generated, info = patch.generate(original)
assert patch.digest(patch.generate(original, version=1)[0]) == 'e2c219013cd76c36bd2883680d137f55f1ea3a0133840ee7f679cdd1f9806823'
assert patch.digest(patch.generate(original, version=2)[0]) == '3aefa41cbadb6b7fe87d8def0f2bcda2140c31ca20bdf3f8373e9bcc68e87099'
assert patch.digest(patch.generate(original, version=3)[0]) == '6485c9b80959fb860c74d6cecec957299b996c951aa7e93f03466bb72d57245b'
assert patch.digest(patch.generate(original, version=4)[0]) == 'fb2ad10395ceb89cbb6359eb8997f5c603c6b635c2855725f4c3a0b0f90c75fb'
assert patch.digest(patch.generate(original, version=5)[0]) == '3409e6e046d57b51523a6d8a6b440e8bc7e3daa6034331d4afb241e1fbefe5fc'
assert patch.digest(patch.generate(original, version=6)[0]) == '48dc516d13570983c8ec748825a8e5c6aa5b9e8789f79573baf9743d9e1555f8'
assert patch.digest(patch.generate(original, version=7)[0]) == '506ade40007e8ca09d0daa781dc78f6c268e6af623c398d1a89dae4991953ebe'
assert patch.digest(patch.generate(original, version=8)[0]) == 'a16ac10fd6fcc349d596771811b8b53dd7e1c3ea76360ea61c56d5dde788de21'
assert patch.digest(patch.generate(original, version=9)[0]) == 'bd4e051222f2b6420e3cc81ac8ef90300de6d583ced0fbc306525b928d34535f'
assert patch.digest(patch.generate(original, version=10)[0]) == '8fd0831ff214d7d822e4adf989e6ed182e25686f4c3e03790f06026a0220d3a5'
legacy11, legacy11_info = patch.generate(original, version=11)
assert patch.digest(legacy11) == '4955a1bf7c6d179956ae7c0ec0748d24086e24120a144d952efaf77b92635515'
assert generated == patch.generate(original)[0]
legacy12, legacy12_info = patch.generate(original, version=12)
assert patch.digest(legacy12) == 'ea1812178bd455a6a62d4652396e0638f402a7c9497ef6afb9c48a53e3438d5d'
legacy13, legacy13_info = patch.generate(original, version=13)
assert patch.digest(legacy13) == '2f1ccbd4e83ef6c90669d70a34ea36e68c63bce691860aa60e1532cb1acd243e'
legacy14, legacy14_info = patch.generate(original, version=14)
assert patch.digest(legacy14) == 'c5177a2d6791cf4b83c1573668f5e6c2ab8edd0fecc8c7f492f0b0fbde4216a1'
assert info['version'] == patch.LATEST_VERSION == 16
# Apply/restore use this exact-image detector, including upgrades from v11.
# No fixture writes or applies an executable to the local runtime.
assert patch.detect_version(original, original) == 0
for version in range(1, 17):
    previous, previous_info = patch.generate(original, version=version)
    assert previous_info['version'] == version
    assert patch.detect_version(original, previous) == version
    if version < 16:
        assert previous != generated
changed = bytearray(legacy11)
changed[patch.CAVE - patch.BASE] ^= 1
try:
    patch.detect_version(original, bytes(changed))
except ValueError as error:
    assert 'Unknown local changes' in str(error)
else:
    raise AssertionError('A modified legacy image was admitted for upgrade')
allowed = set()
for offset, size in [(patch.RMB_HOOK - patch.BASE, 5),
                     (patch.UPDATE_SLOT - patch.BASE, 4),
                     (patch.BUY_COUNT_SLOT - patch.BASE, 4),
                     (patch.DROP_FLAG_HOOK - patch.BASE, 6),
                     (patch.BUFF_TOOLTIP_HOOK - patch.BASE, 8),
                     (patch.STASH_RMB_SLOT - patch.BASE, 4),
                     (0x512260 - patch.BASE, 2), (0x47CB89 - patch.BASE, 2),
                     (0x513873 - patch.BASE, 5), (0x511764 - patch.BASE, 5),
                     (0x526014 - patch.BASE, 7),
                     (patch.HOTBAR_SWAP_HOOK - patch.BASE, 6),
                     (patch.HOTBAR_REMOVE_HOOK - patch.BASE, 7),
                     (patch.HOTBAR_INIT_SLOT - patch.BASE, 4),
                     (patch.HERO_APPEARANCE_HOOK - patch.BASE, 7),
                     *((hook - patch.BASE, 6) for hook in patch.HOTBAR_ROW_HOOKS),
                     *((hook - patch.BASE, 6) for hook in patch.TORNADO_RANGE_HOOKS),
                     *((hook - patch.BASE, 6) for hook in patch.PROFESSION_ATTACK_HOOKS),
                     (info['textSizeOffset'], 4),
                     (patch.CAVE - patch.BASE, info['codeBytes'])]:
    allowed.update(range(offset, offset + size))
assert len(original) == len(generated)
assert all(a == b or i in allowed for i, (a, b) in enumerate(zip(original, generated)))
decoded = list(Cs(CS_ARCH_X86, CS_MODE_32).disasm(
    generated[patch.CAVE - patch.BASE:patch.CAVE - patch.BASE + info['codeBytes']], patch.CAVE))
assert sum(i.size for i in decoded) == info['codeBytes']
assert all(i.mnemonic not in ('int', 'int3', 'syscall') for i in decoded)

GAME, SHOP, BAG, MODAL, INPUT, SELECTION, BUTTON = (
    0xA00000, 0xA10000, 0xA11000, 0xA12000, 0xA13000, 0xA14000, 0xA15000)
RETURN, STACK = 0x668440, 0x908000
STASH, GRID, ROWS, CELLS = 0xA16000, 0xA17000, 0xA17100, 0xA18000
STASH_DATA = 0xA17400
BAG_DATA, BAG_GRID, BAG_ROWS, BAG_CELLS, ITEM_DEF = 0xA17500, 0xA17600, 0xA17700, 0xA19000, 0xA1A000


class Machine:
    def __init__(self, keys=None, shop=True, visible=True, message=0xA017,
                 modal_visible=False, parent=True, shop_type=0x6729D4, npc=121,
                 page=1, slot=3, button=True, game=True, item=54005, enabled=True,
                 drop_parent=False, bag_type=0x671DAC, stash=False,
                 stash_visible=True, stash_type=0x67584C, stash_npc=165,
                 occupied=(), locked=(), source=0x36B7, dragging=False, stash_data=True, partials=()):
        self.u = Uc(UC_ARCH_X86, UC_MODE_32)
        self.u.mem_map(0x400000, 0x340000)
        self.u.mem_write(0x400000, generated)
        self.u.mem_map(0x900000, 0x10000)
        self.u.mem_map(0xA00000, 0x20000)
        self.keys, self.shop, self.calls, self.exit = keys or {}, SHOP if shop else 0, [], None
        self.stash = STASH if stash else 0
        self.stash_data = STASH_DATA if stash_data else 0
        self.write32(STASH, stash_type)
        self.write32(STASH + 0xBC, stash_npc)
        self.u.mem_write(STASH + 0x5F, bytes([stash_visible]))
        self.write32(GRID, 4)
        self.write32(GRID + 4, 8)
        self.write32(GRID + 12, ROWS)
        self.write32(BAG_GRID, 5)
        self.write32(BAG_GRID + 4, 4)
        self.write32(BAG_GRID + 12, BAG_ROWS)
        self.write32(ITEM_DEF + 0x34, 100)
        for row in range(5):
            self.write32(BAG_ROWS + row * 4, BAG_CELLS + row * 4 * 0x70)
        if 0 <= slot < 20:
            self.write32(BAG_CELLS + slot * 0x70 + 6, item)
            self.write32(BAG_CELLS + slot * 0x70 + 0x54, ITEM_DEF)
        for row in range(4):
            self.write32(ROWS + row * 4, CELLS + row * 8 * 0x70)
        for cell in occupied:
            self.write32(CELLS + cell * 0x70 + 0x54, 1)
        for cell in locked:
            self.write32(CELLS + cell * 0x70 + 0x68, 1)
        for cell, partial_id, amount in partials:
            self.write32(CELLS + cell * 0x70 + 0x54, ITEM_DEF)
            self.write32(CELLS + cell * 0x70 + 6, partial_id)
            self.write32(CELLS + cell * 0x70 + 0x14, amount)
        self.write32(SELECTION + 4, source if dragging else -1)
        self.write32(SELECTION + 0x8C, source)
        self.write32(SELECTION + 0x9C, page)
        self.write32(SELECTION + 0x98, slot)
        self.write32(0x704160, GAME if game else 0)
        self.write32(0x70566C, MODAL)
        self.write32(SHOP, shop_type)
        self.write32(SHOP + 0xA0, npc)
        self.u.mem_write(SHOP + 0x5F, bytes([visible]))
        self.write32(BAG + 0xBC, page)
        self.write32(BAG, bag_type)
        self.u.mem_write(BAG + 0x5F, bytes([visible]))
        self.write32(MODAL + 0xE4, message)
        self.write32(MODAL + 0xDC, (BAG if drop_parent else SHOP) if parent else 0)
        self.write32(MODAL + 0xA0, BUTTON if button else 0)
        self.write32(MODAL + 0xA4, npc)
        self.write32(MODAL + 0xA8, INPUT + 0x1000)
        self.write32(MODAL + 0xAC, BUTTON if button else 0)
        self.u.mem_write(MODAL + 0x5E, bytes([enabled]))
        self.item = item
        self.u.mem_write(MODAL + 0x5F, bytes([modal_visible]))
        self.initial = {UC_X86_REG_EAX: 0x123, UC_X86_REG_EBX: source,
            UC_X86_REG_ECX: SELECTION, UC_X86_REG_EDX: 0x456,
            UC_X86_REG_ESI: BAG, UC_X86_REG_EDI: slot & 0xFFFFFFFF,
            UC_X86_REG_EBP: STACK + 0x100}
        self.u.hook_add(UC_HOOK_CODE, self.hook)

    def write32(self, address, value):
        self.u.mem_write(address, struct.pack('<I', value & 0xFFFFFFFF))

    def read32(self, address):
        return struct.unpack('<I', self.u.mem_read(address, 4))[0]

    def arg(self, index):
        return self.read32(self.u.reg_read(UC_X86_REG_ESP) + 4 + index * 4)

    def ret(self, result, arguments=0):
        sp = self.u.reg_read(UC_X86_REG_ESP)
        dest = self.read32(sp)
        self.u.reg_write(UC_X86_REG_EAX, result)
        self.u.reg_write(UC_X86_REG_ECX, 0xDEAD)
        self.u.reg_write(UC_X86_REG_EDX, 0xBEEF)
        self.u.reg_write(UC_X86_REG_ESP, sp + 4 + arguments * 4)
        self.u.reg_write(UC_X86_REG_EIP, dest)

    def hook(self, u, address, size, _):
        if address in (0x479290, 0x47958E, 0x50FEAB, 0x50FF02, 0x50FF57, RETURN):
            self.exit = address
            u.emu_stop()
        elif address == 0x43D14D:
            assert u.reg_read(UC_X86_REG_ECX) == GAME + 0x7CEC
            assert self.arg(0) in (16001, 0x36CB)
            self.ret(self.shop if self.arg(0) == 16001 else self.stash, 1)
        elif address == 0x432438:
            window = u.reg_read(UC_X86_REG_ECX)
            assert window in (STASH_DATA, BAG_DATA), 'Grid lookup used GUI instead of item container'
            assert (self.arg(0) == 13 if window == STASH_DATA else 1 <= self.arg(0) <= 7)
            self.ret(GRID if window == STASH_DATA else BAG_GRID, 1)
        elif address == 0x50B737:
            assert u.reg_read(UC_X86_REG_ECX) == SELECTION and self.arg(0) in (0x36CB,0x36B7)
            self.ret(self.stash_data if self.arg(0) == 0x36CB else BAG_DATA, 1)
        elif address == 0x5127CB:
            assert u.reg_read(UC_X86_REG_ECX) == SELECTION
            assert tuple(self.read32(SELECTION + off) for off in (4, 8, 12)) == tuple(
                self.read32(SELECTION + off) for off in (0x8C, 0x9C, 0x98))
            self.calls.append(('deposit', *(self.arg(i) for i in range(5))))
            self.write32(SELECTION + 4, -1)  # native wrapper ends temporary drag
            self.ret(1, 5)
        elif address == 0x53E368:
            self.ret(INPUT)
        elif address in (0x53E24E, 0x53E1EC):
            assert u.reg_read(UC_X86_REG_ECX) == INPUT
            self.ret(int(self.keys.get(self.arg(0), 0) == (4 if address == 0x53E24E else 1)), 1)
        elif address == 0x50CE86:
            self.ret(SELECTION)
        elif address == 0x53E188:
            assert u.reg_read(UC_X86_REG_ECX) == INPUT
            self.keys[self.arg(0)] = self.arg(1)
            self.ret(0, 2)
        elif address == 0x50DF6B:
            assert u.reg_read(UC_X86_REG_ECX) == SELECTION
            self.calls.append(('sell', self.arg(0), self.arg(1), self.arg(2)))
            self.ret(1, 3)
        elif address == 0x45C284:
            assert u.reg_read(UC_X86_REG_ECX) == MODAL
            self.calls.append(('confirm', self.arg(0), self.arg(1)))
            self.u.mem_write(MODAL + 0x5F, b'\0')  # existing primary handler hides modal
            self.ret(1, 2)
        elif address == 0x48880F:
            assert u.reg_read(UC_X86_REG_ECX) == MODAL
            assert self.keys.get(0x1C) == self.keys.get(0x9C) == 0, 'Enter reached other controls'
            self.calls.append(('buy_count', self.arg(0), self.arg(1)))
            self.write32(MODAL + 0xA0, 0)  # existing handler clears the item/NPC
            self.write32(MODAL + 0xA4, 0)
            self.ret(1, 2)
        elif address in (0x45C135, 0x486E2A):
            assert u.reg_read(UC_X86_REG_ECX) == MODAL
            self.calls.append(('original_update',))
            self.ret(1)

    def run_drop(self, flag, slot):
        template = 0xA16000
        for reg, value in self.initial.items():
            self.u.reg_write(reg, value)
        self.u.reg_write(UC_X86_REG_ESP, STACK)
        self.write32(self.initial[UC_X86_REG_EBP] - 0x14, template)
        self.write32(template + 0x60, flag)
        self.write32(template + 0x20, slot)
        self.u.emu_start(patch.DROP_FLAG_HOOK, 0, count=100)
        assert self.exit is not None
        assert self.u.reg_read(UC_X86_REG_ESP) == STACK
        for reg, value in self.initial.items():
            if reg != UC_X86_REG_EAX:
                assert self.u.reg_read(reg) == value, 'Drop context changed'
        return self.exit

    def run(self, modal=False, count=False):
        for reg, value in self.initial.items():
            self.u.reg_write(reg, value)
        self.u.reg_write(UC_X86_REG_ESP, STACK)
        self.write32(STACK, RETURN)
        if modal or count:
            self.u.reg_write(UC_X86_REG_ECX, MODAL)
            start = self.read32(patch.BUY_COUNT_SLOT if count else patch.UPDATE_SLOT)
        else:
            start = patch.RMB_HOOK
        self.u.emu_start(start, 0, count=5000)
        assert self.exit is not None, 'Patch did not reach a valid exit'
        assert self.u.reg_read(UC_X86_REG_ESP) == STACK + (4 if modal or count else 0)
        for reg in (UC_X86_REG_EBX, UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_EBP):
            assert self.u.reg_read(reg) == self.initial[reg], 'Callee-saved register changed'
        if not modal and not count and self.exit == 0x47958E:
            for reg in self.initial:
                assert self.u.reg_read(reg) == self.initial[reg], 'RMB context changed'
        return self.calls


cases = 0
for keys, shift in (({}, 0), ({0x2A: 4}, 0x2A), ({0x36: 4}, 0x2A)):
    for cell in (0, 1, 7, 8, 31):
        m = Machine(stash=True, keys=keys, occupied=range(cell))
        assert m.run() == [('deposit', 0x36CB, cell, 13, 165, shift)]
        assert m.exit == 0x47958E and m.read32(SELECTION + 0x8C) == 0xFFFFFFFF
        cases += 1
for kwargs in ({'stash_npc': 0}, {'stash_npc': -1}, {'page': 0}, {'page': 8},
               {'slot': -1}, {'dragging': True}, {'occupied': range(32)},
               {'locked': range(32)}, {'modal_visible': True}, {'stash_data': False}):
    m = Machine(stash=True, **kwargs)
    assert m.run() == [] and m.exit == 0x47958E
    cases += 1
for kwargs in ({'stash_visible': False}, {'stash_type': 0x675764}):
    m = Machine(stash=True, shop=False, **kwargs)
    assert m.run() == [] and m.exit == 0x479290
    cases += 1
m = Machine(stash=True, occupied=(1, 2), locked=(0,))
assert m.run() == [('deposit', 0x36CB, 3, 13, 165, 0)]
cases += 1
m = Machine(stash=True, shop=False, source=0x36CB)
assert m.run() == [] and m.exit == 0x479290  # native withdrawal path unchanged
cases += 1
for occupied in ((), range(32)):
    m = Machine(stash=True, occupied=occupied, partials=((24,54005,90),))
    assert m.run() == [('deposit',0x36CB,24,13,165,0)]
    cases += 1
m = Machine(stash=True, partials=((1,54005,100),(9,54005,80),(5,54005,90)))
assert m.run() == [('deposit',0x36CB,5,13,165,0)]
cases += 1
for npc in (121, 159, 158):
    for keys, shift in (({}, 0xFFFFFFFF), ({0x2A: 4}, 0x2A), ({0x36: 4}, 0x2A)):
        m = Machine(keys=keys, npc=npc)
        assert m.run() == [('sell', SHOP, npc, shift)] and m.exit == 0x47958E
        cases += 1
for kwargs in ({'shop': False}, {'visible': False}, {'shop_type': 0x67296C}, {'game': False}):
    m = Machine(**kwargs)
    assert m.run() == [] and m.exit == 0x479290
    assert m.u.reg_read(UC_X86_REG_EAX) == INPUT
    cases += 1
for kwargs in ({'npc': 0}, {'npc': -1}, {'page': 0}, {'page': 8}, {'slot': -1},
               {'modal_visible': True}):
    m = Machine(**kwargs)
    assert m.run() == [] and m.exit == 0x47958E
    cases += 1
for message in (0xA017, 0xA016):
    for keys in ({0x1C: 1}, {0x9C: 1}, {0x1C: 1, 0x9C: 1}):
        m = Machine(keys=keys, modal_visible=True, message=message)
        assert m.run(modal=True) == [('confirm', 1, BUTTON)]
        assert m.u.reg_read(UC_X86_REG_EAX) == 1
        m.calls.clear()
        assert m.run(modal=True) == [('original_update',)]  # cannot repeat after hiding
        cases += 2
for kwargs in ({'keys': {}}, {'keys': {0x1C: 2}}, {'keys': {0x1C: 4}},
               {'keys': {0x9C: 4}}, {'message': 0xA015}, {'message': 0xA03D},
               {'parent': False}, {'visible': False}, {'button': False},
               {'shop_type': 0x67296C}, {'modal_visible': False}):
    config = dict(keys={0x1C: 1}, modal_visible=True)
    config.update(kwargs)
    assert Machine(**config).run(modal=True) == [('original_update',)]
    cases += 1
for page in (1, 2, 3, 4):
    for keys in ({0x1C: 1}, {0x9C: 1}, {0x1C: 1, 0x9C: 1}):
        m = Machine(keys=keys, modal_visible=True, message=0xA03D, drop_parent=True, page=page)
        assert m.run(modal=True) == [('confirm', 1, BUTTON)]
        m.calls.clear()
        assert m.run(modal=True) == [('original_update',)]
        cases += 2
for kwargs in ({'keys': {}}, {'keys': {0x1C: 2}}, {'keys': {0x1C: 4}},
               {'keys': {0x9C: 4}}, {'message': 0xA025}, {'message': 0xA016},
               {'message': 0xA017}, {'parent': False}, {'visible': False},
               {'button': False}, {'page': 0}, {'page': 5},
               {'bag_type': 0x6729D4}, {'modal_visible': False}):
    config = dict(keys={0x1C: 1}, modal_visible=True, message=0xA03D, drop_parent=True)
    config.update(kwargs)
    assert Machine(**config).run(modal=True) == [('original_update',)]
    cases += 1
for keys in ({0x1C: 1}, {0x9C: 1}, {0x1C: 1, 0x9C: 1}):
    m = Machine(keys=keys, modal_visible=True)
    m.write32(MODAL + 0xA0, m.item)
    assert m.run(count=True) == [('buy_count', 1, BUTTON)]
    m.calls.clear()
    m.keys[0x1C] = 1
    assert m.run(count=True) == [('original_update',)]
    cases += 2
for kwargs in ({'keys': {}}, {'keys': {0x1C: 2}}, {'keys': {0x1C: 4}},
               {'npc': 0}, {'item': 0}, {'enabled': False}, {'modal_visible': False},
               {'button': False}):
    config = dict(keys={0x1C: 1}, modal_visible=True)
    config.update(kwargs)
    m = Machine(**config)
    m.write32(MODAL + 0xA0, m.item)
    assert m.run(count=True) == [('original_update',)]
    cases += 1
for slot in range(0, 13):
    for flag in (0, 1, 2, 3):
        expected = 0x50FF02 if flag == 1 else (
            0x50FEAB if flag == 2 or (flag == 0 and slot in (1, 2, 3, 4, 7)) else 0x50FF57)
        assert Machine().run_drop(flag, slot) == expected, (flag, slot)
        cases += 1
assert patch.SOURCE.read_bytes() == original
for version, executable in ((11, legacy11), (12, legacy12), (13, legacy13),
                            (14, legacy14), (15, generated)):
    for hook, field in zip(patch.TORNADO_RANGE_HOOKS, (0x54, 0x64)):
        for skill, table_range in ((50221, 0), (50224, 0), (50224, 77),
                                  (1001, 20), (1003, 50), (50220, 11),
                                  (50222, 0), (50223, 19), (50225, 23),
                                  (50211, 31), (5001, 200)):
            for radius in (0, 5, 20):
                u = Uc(UC_ARCH_X86, UC_MODE_32)
                u.mem_map(0x400000, 0x340000); u.mem_write(0x400000, executable)
                u.mem_map(0x900000, 0x10000)
                definition, radius_ptr, output_ptr = 0x901000, 0x902000, 0x902008
                u.mem_write(definition, struct.pack('<I', skill))
                u.mem_write(definition + field, struct.pack('<d', table_range))
                u.mem_write(radius_ptr, struct.pack('<d', radius))
                u.mem_write(STACK + 0x100 - 0x10, struct.pack('<I', definition))
                u.reg_write(UC_X86_REG_EBP, STACK + 0x100)
                u.reg_write(UC_X86_REG_ESP, STACK)
                flags = 0x202 | (0x41 if radius == 5 else 0)
                u.reg_write(UC_X86_REG_EFLAGS, flags)
                # Execute the actual new instructions on an x87 radius value,
                # exactly as both native range checks do after 4E9466.
                bootstrap, save = 0x668300, 0x668320
                u.mem_write(bootstrap, b'\xdd\x05' + struct.pack('<I', radius_ptr) +
                            b'\xe9' + struct.pack('<i', hook - bootstrap - 11))
                u.mem_write(save, b'\xdd\x1d' + struct.pack('<I', output_ptr) + b'\x90')
                def on_range(u, address, size, _):
                    if address == hook + 6: u.reg_write(UC_X86_REG_EIP, save)
                    elif address == save + 6: u.emu_stop()
                u.hook_add(UC_HOOK_CODE, on_range)
                u.emu_start(bootstrap, 0, count=60)
                actual = struct.unpack('<d', u.mem_read(output_ptr, 8))[0]
                repaired = skill == 50221 or (version >= 12 and skill == 50224)
                assert actual == radius + (130 if repaired else table_range), (version, skill, field, actual)
                assert u.reg_read(UC_X86_REG_ESP) == STACK
                assert u.reg_read(UC_X86_REG_EBP) == STACK + 0x100
                assert u.reg_read(UC_X86_REG_EAX) == definition
                assert u.reg_read(UC_X86_REG_EFLAGS) == flags
                assert u.mem_read(definition + field, 8) == struct.pack('<d', table_range)
                cases += 1
print(f'PASS: {cases} offline x86 trade UI scenarios; register/stack contracts; exact patch boundaries')
print('SHA256:', info['generatedSHA256'])
