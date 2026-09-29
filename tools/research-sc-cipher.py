"""Compare a candidate HASP4 block transform with captured x64 I/O.

Research harness, not used by the driver. The 32-bit state transform follows
the supplied MulttKey.sys instructions at VA 0x16a70; the reversible block
composition is cross-checked against the public UsbHasp project.
"""
import itertools
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MASK = 0xffffffff


def hash32(value, password, table):
    digits = (password ^ 0x01081000) >> 12
    state = 31
    for bit in range(10, 5, -1):
        digit = digits & 15
        state |= int(0 < digit < 11) << bit
        digits >>= 4
    index = 0
    for _ in range(39):
        selector = (value >> (index * 8)) & 31
        secret = (table[(selector >> 2) & 0xfe] >> (7 - (selector & 7))) & 1
        feedback = selector ^ ((secret ^ 1) & (selector >> 3)) ^ (selector >> 4)
        feedback ^= (state >> 10) ^ (state >> 7)
        if selector & 2:
            feedback ^= state >> 5
        if selector & 4:
            feedback ^= state >> 8
        state = (((state ^ ((selector & 1) << 2)) << 1) | (feedback & 1)) & MASK
        bit = ((state >> 11) ^ secret) & 1
        low = value & 1
        index = low * 2 + bit
        value = (value >> 1) ^ (0x80500062 if low != bit else 0)
    return value


def rotate(value, shift):
    return ((value << shift) | (value >> ((32 - shift) & 31))) & MASK


def block(data, password, table, decode=False, endian='<'):
    left, right = struct.unpack(endian + 'II', data)
    if decode:
        for constant, shifts in ((0x5b2c004a, range(25, -1, -5)),
                                 (0x803425c3, range(10, -1, -2))):
            for shift in shifts:
                left, right = rotate(left ^ constant, shift) ^ right, left
            left, right = hash32(left, password, table) ^ right, left
    else:
        for constant, shifts in ((0x803425c3, range(0, 11, 2)),
                                 (0x5b2c004a, range(0, 26, 5))):
            left, right = right, hash32(right, password, table) ^ left
            for shift in shifts:
                left, right = right, rotate(right ^ constant, shift) ^ left
    return struct.pack(endian + 'II', left, right)


def main():
    reg = (ROOT / 'package/VirKeyArm64-SC-Test.reg').read_text(encoding='utf-16')
    table = bytes.fromhex(re.search(r'"SecTable"=hex:([^\r\n]+)', reg)
                          .group(1).replace(',', ''))
    events = [json.loads(line) for line in
              (ROOT / 'build/oracle-solidcam-ui-v28.jsonl').open()]
    pairs = [(bytes.fromhex(e['input'])[256:], bytes.fromhex(e['output'])[256:])
             for e in events if e.get('kind') == 'ioctl' and
             e.get('inLength') == 264 and e.get('ok')]
    for password, reverse, decode, endian in itertools.product(
            (0x4c8f743c, 0x743c4c8f), (False, True), (False, True), ('<', '>')):
        tab = table[::-1] if reverse else table
        count = sum(block(a, password, tab, decode, endian) == b for a, b in pairs)
        if count:
            print('match', hex(password), reverse, decode, endian, count, '/', len(pairs))
    print('checked', len(pairs), 'independent 8-byte responses')


if __name__ == '__main__':
    main()
