#!/usr/bin/env python3
"""Exercise the exact portable parser linked into the ARM64 driver."""

import ctypes
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / 'package/VirKeyArm64-SC-Test.reg'
LIBRARY = ROOT / 'build/libvk_sc_dump.dylib'


class Value(ctypes.Structure):
    _fields_ = [('type', ctypes.c_uint32), ('length', ctypes.c_uint32),
                ('data', ctypes.POINTER(ctypes.c_uint8))]


class Dump(ctypes.Structure):
    _fields_ = [('serialNumber', ctypes.c_uint32),
                ('dongleType', ctypes.c_uint32), ('memory', ctypes.c_uint32),
                ('data', ctypes.c_uint8 * 112),
                ('license', ctypes.c_uint8 * 16),
                ('secTable', ctypes.c_uint8 * 8),
                ('netMemory', ctypes.c_uint8 * 12),
                ('option', ctypes.c_uint8 * 13)]


NAMES = ('Type', 'SN', 'DongleType', 'Memory', 'Data', 'License',
         'SecTable', 'NetMemory', 'Option')


def sample_values():
    contents = SAMPLE.read_text(encoding='utf-16')
    heading = r'[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps\4C8F743C]'
    block = contents.split(heading, 1)[1].split('\n[', 1)[0]
    block = re.sub(r'\\\s*\n\s*', '', block)
    values = {}
    for name, kind, text in re.findall(r'^"([^"]+)"=(dword|hex):([^\r\n]+)', block, re.M):
        if kind == 'dword':
            values[name] = (4, int(text, 16).to_bytes(4, 'little'))
        else:
            values[name] = (3, bytes.fromhex(text.replace(',', '')))
    return values


def parse(lib, entries):
    fields = (Value * len(NAMES))()
    buffers = []
    for i, name in enumerate(NAMES):
        if name not in entries:
            continue
        kind, data = entries[name]
        buffer = (ctypes.c_uint8 * len(data)).from_buffer_copy(data)
        buffers.append(buffer)
        fields[i] = Value(kind, len(data), buffer)
    dump = Dump()
    result = lib.VkParseScDump(fields, ctypes.byref(dump))
    return result, dump


def main():
    subprocess.run(['clang', '-std=c11', '-shared', '-fPIC', '-Wall', '-Wextra',
                    '-Werror', 'src/sc_dump.c', '-o', str(LIBRARY)],
                   cwd=ROOT, check=True)
    lib = ctypes.CDLL(str(LIBRARY))
    lib.VkParseScDump.argtypes = [ctypes.POINTER(Value), ctypes.POINTER(Dump)]
    lib.VkParseScDump.restype = ctypes.c_int
    valid = sample_values()
    result, dump = parse(lib, valid)
    assert result == 0, result
    assert dump.serialNumber == 0x4F2F4F2D
    assert bytes(dump.data[:4]) == bytes.fromhex('ca0e0000')
    assert bytes(dump.license) == valid['License'][1]

    missing = dict(valid)
    del missing['License']
    assert parse(lib, missing)[0] == 1
    wrong_type = dict(valid)
    wrong_type['License'] = (4, valid['License'][1])
    assert parse(lib, wrong_type)[0] == 2
    truncated = dict(valid)
    truncated['Data'] = (3, valid['Data'][1][:-1])
    assert parse(lib, truncated)[0] == 3
    mc = dict(valid)
    mc['Type'] = (4, (10).to_bytes(4, 'little'))
    assert parse(lib, mc)[0] == 4
    print('SC sample and four invalid cases passed')


if __name__ == '__main__':
    main()
