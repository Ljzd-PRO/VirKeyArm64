#!/usr/bin/env python3
"""Replay the observed SC query and dynamic block-decode requests on the Mac-built core."""
import ctypes
import json
import subprocess
from pathlib import Path

from test_sc_dump import ROOT, Dump, Value, parse, sample_values

TRACE = ROOT / 'tests/fixtures/oracle-startup-handle.jsonl'
LIBRARY = ROOT / 'build/libvk_protocol.dylib'


def main():
    subprocess.run(['clang', '-std=c11', '-shared', '-fPIC', '-Wall', '-Wextra',
                    '-Werror', 'src/sc_dump.c', 'src/sc_cipher.c', 'src/protocol.c',
                    '-o', str(LIBRARY)], cwd=ROOT, check=True)
    lib = ctypes.CDLL(str(LIBRARY))
    lib.VkParseScDump.argtypes = [ctypes.POINTER(Value), ctypes.POINTER(Dump)]
    lib.VkParseScDump.restype = ctypes.c_int
    lib.VkProcessScIoctl.argtypes = [ctypes.POINTER(Dump),
        ctypes.POINTER(ctypes.c_uint16), ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t)]
    lib.VkProcessScIoctl.restype = ctypes.c_int
    lib.VkProcessHaspVersion.argtypes = [ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_size_t, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t)]
    lib.VkProcessHaspVersion.restype = ctypes.c_int
    lib.VkProcessScHaspDiscovery.argtypes = [ctypes.POINTER(ctypes.c_uint16),
        ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t)]
    lib.VkProcessScHaspDiscovery.restype = ctypes.c_int
    lib.VkProcessGlobalDiscovery.argtypes = [ctypes.POINTER(ctypes.c_uint16),
        ctypes.c_uint32, ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
        ctypes.POINTER(ctypes.c_size_t)]
    lib.VkProcessGlobalDiscovery.restype = ctypes.c_int
    result, dump = parse(lib, sample_values())
    assert result == 0
    name = (ctypes.c_uint16 * 9)(*[ord(c) for c in '4C8F743C'], 0)

    def call(code, payload):
        inbuf = (ctypes.c_uint8 * len(payload)).from_buffer_copy(payload)
        outbuf = (ctypes.c_uint8 * len(payload))()
        written = ctypes.c_size_t()
        result = lib.VkProcessScIoctl(ctypes.byref(dump), name, code,
                   inbuf, len(payload), outbuf, len(outbuf),
                   ctypes.byref(written))
        return result, bytes(outbuf[:written.value])

    events = [json.loads(line) for line in TRACE.open()]
    for index in (0, 2, 3, 5, 17, 19):
        event = events[index]
        outcome, answer = call(int(event['code'], 16),
                               bytes.fromhex(event['input']))
        assert outcome == 0, (index, outcome)
        assert answer == bytes.fromhex(event['output']), index

    for challenge in events:
        if challenge.get('inLength') in (264, 272):
            outcome, answer = call(0x9c402458, bytes.fromhex(challenge['input']))
            assert outcome == 0 and answer == bytes.fromhex(challenge['output'])
    for filename in ('oracle-solidcam-ui-v28.jsonl',
                     'oracle-solidcam-holdout-v30.jsonl'):
        holdout = [json.loads(line) for line in (ROOT / 'tests/fixtures' / filename).open()]
        count = 0
        for challenge in holdout:
            if challenge.get('kind') == 'ioctl' and challenge.get('inLength') in (264, 272):
                outcome, answer = call(0x9c402458, bytes.fromhex(challenge['input']))
                assert outcome == 0 and answer == bytes.fromhex(challenge['output']), filename
                count += 1
        assert count > 1, filename
    invalid_crypto = bytearray(bytes.fromhex(events[7]['input']))
    invalid_crypto[25] = 0
    assert call(0x9c402458, invalid_crypto)[0] == 2
    bad_name = bytearray(bytes.fromhex(events[5]['input']))
    bad_name[8] ^= 1
    assert call(0x9c402458, bad_name)[0] == 1
    changed = Dump.from_buffer_copy(dump)
    changed.serialNumber = 0x12345678
    status_input = bytes.fromhex(events[17]['input'])
    ib = (ctypes.c_uint8 * len(status_input)).from_buffer_copy(status_input)
    ob = (ctypes.c_uint8 * len(status_input))()
    length = ctypes.c_size_t()
    assert lib.VkProcessScIoctl(ctypes.byref(changed), name, 0x9c402458,
             ib, len(ib), ob, len(ob), ctypes.byref(length)) == 0
    assert bytes(ob[16:18]) == bytes.fromhex('7856')
    assert bytes(ob[130:132]) == bytes.fromhex('3412')
    for request, expected in ((bytes(6), bytes.fromhex('0000fafa1a04')),
                              (bytes.fromhex('01000000b100'),
                               bytes.fromhex('0100fafa5803'))):
        ib = (ctypes.c_uint8 * 6).from_buffer_copy(request)
        ob = (ctypes.c_uint8 * 6)()
        length = ctypes.c_size_t()
        assert lib.VkProcessHaspVersion(ib, 6, ob, 6,
                                        ctypes.byref(length)) == 0
        assert length.value == 6 and bytes(ob) == expected
    discovery = events[1]
    request = bytes.fromhex(discovery['input'])
    # Directly probing the working x64 SC HASP instance with this initial
    # request changed these fields; its other HASP instance returned status 7.
    expected = bytearray(request)
    expected[16] = expected[130] = expected[132] = expected[254] = 1
    expected[70:74] = bytes.fromhex('88f4cca8')
    expected[104:108] = bytes.fromhex('89c5ffff')
    token = int.from_bytes(expected[70:74], 'little')
    buf = (ctypes.c_uint8 * 256).from_buffer_copy(request)
    length = ctypes.c_size_t()
    assert lib.VkProcessScHaspDiscovery(name, token, buf, 256, buf, 256,
                                      ctypes.byref(length)) == 0
    assert length.value == 256 and bytes(buf) == expected
    bad = (ctypes.c_uint8 * 256).from_buffer_copy(request)
    bad[8] ^= 1
    assert lib.VkProcessScHaspDiscovery(name, token, bad, 256, bad, 256,
                                      ctypes.byref(length)) == 1
    guest_trace = ROOT / 'tests/fixtures/guest-solidcam-global-v27.jsonl'
    guest_events = [json.loads(line) for line in guest_trace.open()]
    global_event = next(event for event in guest_events
        if event.get('kind') == 'ioctl' and
           event.get('object') == '\\Device\\VirKeyArm64Control' and
           event.get('code') == '0x9c402458')
    global_request = bytes.fromhex(global_event['input'])
    global_answer = bytearray(global_request)
    global_answer[70:74] = bytes.fromhex('e87161b2')
    global_answer[76] = 0x85
    global_buf = (ctypes.c_uint8 * 256).from_buffer_copy(global_request)
    assert lib.VkProcessGlobalDiscovery(name, 0xb26171e8,
        global_buf, 256, global_buf, 256, ctypes.byref(length)) == 0
    assert length.value == 256 and bytes(global_buf) == global_answer
    global_bad = (ctypes.c_uint8 * 256).from_buffer_copy(global_request)
    global_bad[104] ^= 1
    assert lib.VkProcessGlobalDiscovery(name, 0xb26171e8,
        global_bad, 256, global_bad, 256, ctypes.byref(length)) == 1
    print('x64 SC query and dynamic decode replays, HASP and global discovery, versions, and validation tests passed')


if __name__ == '__main__':
    main()
