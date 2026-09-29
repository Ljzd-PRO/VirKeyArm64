#!/usr/bin/env python3
"""Rebuild the unsigned ARM64 catalog on macOS from an Inf2Cat layout template.

The template is an unsigned Microsoft WDK catalog generated for the same two
file names. Only the embedded file digests change; its ASN.1 structure and
target OS metadata stay fixed. Signing is a separate Mac step.
"""

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "reference/inf2cat-arm64-diagnostic.cat"


def pe_authenticode_content(path: Path) -> bytes:
    data = path.read_bytes()
    pe = int.from_bytes(data[0x3C:0x40], "little")
    optional = pe + 0x18
    assert data[:2] == b"MZ" and data[pe:pe + 4] == b"PE\0\0"
    assert data[optional:optional + 2] == b"\x0b\x02"  # PE32+
    checksum = optional + 64
    cert_directory = optional + 144
    cert_offset = int.from_bytes(data[cert_directory:cert_directory + 4], "little")
    cert_size = int.from_bytes(data[cert_directory + 4:cert_directory + 8], "little")
    before_certificate = cert_offset or len(data)
    return (
        data[:checksum]
        + data[checksum + 4:cert_directory]
        + data[cert_directory + 8:before_certificate]
        + data[before_certificate + cert_size:]
    )


def read_tlv(data: bytes, offset: int) -> tuple[int, int, int]:
    tag = data[offset]
    initial = data[offset + 1]
    if initial < 0x80:
        header = 2
        length = initial
    else:
        width = initial & 0x7F
        header = 2 + width
        length = int.from_bytes(data[offset + 2:offset + header], "big")
    return tag, offset + header, offset + header + length


def sort_catalog_members(data: bytes) -> bytes:
    # The WDK template has a four-entry CTL SEQUENCE at this fixed offset.
    # CryptCATAdmin uses the sorted subject identifiers when looking up a file.
    members_offset = 114
    tag, contents_start, contents_end = read_tlv(data, members_offset)
    if tag != 0x30:
        raise ValueError("catalog template layout changed")
    members = []
    cursor = contents_start
    while cursor < contents_end:
        tag, entry_start, entry_end = read_tlv(data, cursor)
        if tag != 0x30:
            raise ValueError("invalid catalog member")
        digest_tag, digest_start, digest_end = read_tlv(data, entry_start)
        if digest_tag != 0x04:
            raise ValueError("catalog member lacks digest")
        digest = data[digest_start:digest_end]
        members.append((digest, data[cursor:entry_end]))
        cursor = entry_end
    if len(members) != 4 or cursor != contents_end:
        raise ValueError("unexpected catalog member count")
    ordered = sorted(members, key=lambda member: (-len(member[0]), member[0]))
    return data[:contents_start] + b"".join(member[1] for member in ordered) + data[contents_end:]


def main() -> None:
    package = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "package"
    output = package / "VirKeyArm64.unsigned.cat"
    inf = package / "VirKeyArm64.inf"
    sys_file = package / "VirKeyArm64.sys"
    baseline = {
        ("inf", "sha1"): "F0E2D1B0D76C293249032D2ED9C65D151FD3766A",
        ("inf", "sha256"): "D44102234739C5F16D77B4CD4083F3AE9E5F335D4D3FA2B47F6514574353858F",
        ("sys", "sha1"): "E5649ED1D5833F092743E655E6D95CA1AC269589",
        ("sys", "sha256"): "0EA8210FE44E38EA1D051A74E439A6C8AAE656C2B034111C0D5B33C72207E42C",
    }
    content = {"inf": inf.read_bytes(), "sys": pe_authenticode_content(sys_file)}
    catalog = TEMPLATE.read_bytes()
    for (kind, algorithm), old_hex in baseline.items():
        old = bytes.fromhex(old_hex)
        new = hashlib.new(algorithm, content[kind]).digest()
        count = catalog.count(old)
        expected = 1 if algorithm == "sha1" else 2
        if count != expected:
            raise ValueError(f"template has {count} copies of {kind} {algorithm}, expected {expected}")
        catalog = catalog.replace(old, new)
    catalog = sort_catalog_members(catalog)
    output.write_bytes(catalog)
    print(f"wrote {output}")


if __name__ == "__main__":
    main()
