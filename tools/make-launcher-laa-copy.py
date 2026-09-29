#!/usr/bin/env python3
"""Make a separate LAA diagnostic copy of the verified SolidCAM 2024 launcher.

This changes the PE header only; it invalidates the copy's vendor signature.
The original and the destination are never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct

SOURCE_SHA256 = "26d72b6c13a5704bf49097eb534d3b86f93f931870744b195373f2b54395dc7b"
COPY_SHA256 = "86dd940519e96d5787282bcc38a56b8462d2f43602db80a9b554f31c97f4c726"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    original = args.source.read_bytes()
    source_hash = hashlib.sha256(original).hexdigest()
    if source_hash != SOURCE_SHA256:
        parser.error("Unknown input SHA256; this diagnostic is for the verified build only")
    if args.source.resolve() == args.destination.resolve():
        parser.error("Destination must be a separate file")
    pe = struct.unpack_from("<I", original, 0x3c)[0]
    if original[:2] != b"MZ" or original[pe:pe + 4] != b"PE\0\0":
        parser.error("Invalid PE")
    if struct.unpack_from("<H", original, pe + 4)[0] != 0x8664:
        parser.error("Expected AMD64 image")
    offset = pe + 22
    flags = struct.unpack_from("<H", original, offset)[0]
    if flags != 0x0002:
        parser.error("Unexpected COFF characteristics")
    patched = bytearray(original)
    struct.pack_into("<H", patched, offset, flags | 0x20)
    changes = [i for i, (a, b) in enumerate(zip(original, patched)) if a != b]
    copy_hash = hashlib.sha256(patched).hexdigest()
    if changes != [offset] or copy_hash != COPY_SHA256:
        parser.error("Unexpected output; refusing to write")
    with args.destination.open("xb") as output:
        output.write(patched)
    print(json.dumps({
        "source_sha256": source_hash, "copy_sha256": copy_hash,
        "changed_offset": hex(offset), "old": hex(original[offset]),
        "new": hex(patched[offset]),
        "only_change": "IMAGE_FILE_LARGE_ADDRESS_AWARE",
    }, indent=2))


if __name__ == "__main__":
    main()
