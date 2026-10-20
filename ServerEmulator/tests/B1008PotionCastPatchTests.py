"""Offline execution of potion hooks; no live process or game input."""
import importlib.util
import os
import struct
import sys
from pathlib import Path

project = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(project / 'tools'))
if os.environ.get('BERNEO_PATCH_TEST_DEPS'):
    sys.path.insert(0, os.environ['BERNEO_PATCH_TEST_DEPS'])
if not os.environ.get('BERNEO_SOURCE_CLIENT'):
    raise RuntimeError('Set BERNEO_SOURCE_CLIENT to the unchanged original b1008 directory')
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import *
spec = importlib.util.spec_from_file_location('patch', project / 'tools/Patch-B1008TradeUI.py')
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
data, info = patch.generate(patch.SOURCE.read_bytes())
assert patch.digest(patch.generate(patch.SOURCE.read_bytes(), 10)[0]) == '8fd0831ff214d7d822e4adf989e6ed182e25686f4c3e03790f06026a0220d3a5'
count = 0
for kind in (1, 2):
    for subtype in (7, 8, 10, 19):
        for label in ('potion_hotbar', 'potion_backpack', 'potion_ack'):
            if label != 'potion_ack' and kind != 2:
                continue  # Both send hooks are reached only through native major-type 2 dispatch.
            u = Uc(UC_ARCH_X86, UC_MODE_32)
            u.mem_map(0x400000, 0x340000)
            u.mem_write(0x400000, data)
            u.mem_map(0x900000, 0x10000)
            def w(a, n): u.mem_write(a, struct.pack('<I', n))
            w(0x901054, 0x902000)
            w(0x90200C, kind)
            w(0x902010, subtype)
            w(0x704160, 0x12345678)
            u.reg_write(UC_X86_REG_ESI, 0x901000)
            u.reg_write(UC_X86_REG_EBX, 0x902000)
            u.reg_write(UC_X86_REG_EAX, 0x903000)
            u.reg_write(UC_X86_REG_ECX, 0x904000)
            u.reg_write(UC_X86_REG_ESP, 0x908000)
            calls, stops = [], []
            def hook(machine, address, size, _):
                if address in (0x4E2149, 0x4ED2F8):
                    calls.append(address)
                    if address == 0x4ED2F8:
                        assert machine.reg_read(UC_X86_REG_ECX) == 0x903000
                    sp = machine.reg_read(UC_X86_REG_ESP)
                    machine.reg_write(UC_X86_REG_EIP, struct.unpack('<I', machine.mem_read(sp, 4))[0])
                    machine.reg_write(UC_X86_REG_ESP, sp + 4)
                elif address in (0x513878, 0x51392F, 0x511769, 0x5117C8, 0x52601B):
                    stops.append(address)
                    machine.emu_stop()
            u.hook_add(UC_HOOK_CODE, hook)
            u.emu_start(info['labels'][label], 0, count=100)
            potion = kind == 2 and subtype == 7
            assert u.reg_read(UC_X86_REG_ESP) == 0x908000
            if label == 'potion_ack':
                assert stops == [0x52601B] and calls == ([] if potion else [0x4ED2F8])
            elif label == 'potion_hotbar':
                assert stops == [0x51392F if potion else 0x513878]
                assert calls == ([] if potion else [0x4E2149])
            else:
                assert stops == [0x5117C8 if potion else 0x511769] and not calls
            count += 1
print(f'PASS: {count} potion/cast native-hook scenarios; other item restrictions preserved; potion ACK retains active skill')
