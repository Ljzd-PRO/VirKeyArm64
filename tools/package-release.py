#!/usr/bin/env python3
"""Package the reviewed Windows ARM64 1.0.0 test build for GitHub Releases."""

from __future__ import annotations

import hashlib
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.0.0"
PREFIX = f"VirKeyArm64-{VERSION}"
OUTPUT = ROOT / "build" / "release" / f"{PREFIX}-windows-arm64.zip"
FILES = (
    "README.md",
    "LICENSE",
    "package/VirKeyArm64.sys",
    "package/VirKeyArm64.inf",
    "package/VirKeyArm64.cat",
    "package/VirKeyNode.exe",
    "package/VirKeyArm64-Test.cer",
    "package/VirKeyArm64-SC-Test.reg",
    "package/hasp/VirKeyArm64.sys",
    "package/hasp/VirKeyArm64.inf",
    "package/hasp/VirKeyArm64.cat",
    "tools/guest-enable-test-package.ps1",
    "tools/guest-install-and-probe.ps1",
)
EXPECTED_SYS_SHA256 = "3b59bedbfda7cc6b3a734d50aae061cc689a623f730509f0e3146c645d68bb28"


def sha256(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def main() -> None:
    if OUTPUT.exists():
        raise SystemExit(f"Refusing to overwrite existing release archive: {OUTPUT}")
    files = {name: (ROOT / name).read_bytes() for name in FILES}
    if files["package/VirKeyArm64.sys"] != files["package/hasp/VirKeyArm64.sys"]:
        raise SystemExit("Driver binaries differ between the two INF packages")
    if sha256(files["package/VirKeyArm64.sys"]) != EXPECTED_SYS_SHA256:
        raise SystemExit("Driver binary differs from the tested build")
    for name in ("package/VirKeyArm64.inf", "package/hasp/VirKeyArm64.inf"):
        if b"DriverVer=09/30/2026,1.0.0.0" not in files[name]:
            raise SystemExit(f"Unexpected package version: {name}")
    manifest = "".join(f"{sha256(data)}  {name}\n" for name, data in files.items()).encode()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUTPUT, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files.items():
            archive.writestr(f"{PREFIX}/{name}", data)
        archive.writestr(f"{PREFIX}/SHA256SUMS.txt", manifest)
    with zipfile.ZipFile(OUTPUT) as archive:
        if archive.testzip() is not None:
            raise SystemExit("Release archive CRC check failed")
        for name, data in files.items():
            if archive.read(f"{PREFIX}/{name}") != data:
                raise SystemExit(f"Release archive differs from source: {name}")
    print(f"{OUTPUT}\nSHA256 {sha256(OUTPUT.read_bytes())}\n{len(FILES)} payload files and SHA256SUMS.txt")


if __name__ == "__main__":
    main()
