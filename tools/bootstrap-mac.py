#!/usr/bin/env python3
"""Fetch pinned Microsoft ARM64 SDK/WDK packages and create a local test key."""

import hashlib
import pathlib
import subprocess
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / "vendor"
VERSION = "10.0.26100.6584"
PACKAGES = (
    ("microsoft.windows.sdk.cpp", "5d31b38205bdd9ac761b4cb39fbbc6b7209b01c11194324afc674d7d119483a0", "sdk-common"),
    ("microsoft.windows.sdk.cpp.arm64", "ac06922186fdd75e4ff1033a304ea629d7917bd0ca85e483762f8109584ccfc4", "sdk-arm64"),
    ("microsoft.windows.wdk.arm64", "e705b2a63eab891def8f98087666f93e8f21da8e3b5def81a624b83fef5bdae9", "wdk"),
)


def fetch_package(package: str, digest: str, destination: str) -> None:
    archive = VENDOR / f"{package}.{VERSION}.nupkg"
    target = VENDOR / destination
    if not archive.exists():
        url = f"https://api.nuget.org/v3-flatcontainer/{package}/{VERSION}/{archive.name}"
        with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as out:
            while chunk := response.read(1024 * 1024):
                out.write(chunk)
    actual = hashlib.sha256(archive.read_bytes()).hexdigest()
    if actual != digest:
        raise RuntimeError(f"{archive.name} SHA256 mismatch: {actual}")
    if not target.exists():
        target.mkdir(parents=True)
        with zipfile.ZipFile(archive) as package_file:
            package_file.extractall(target)


def patch_wdk_header() -> None:
    header = VENDOR / "wdk/c/Include/10.0.26100.0/km/wdm.h"
    contents = header.read_bytes()
    original = b"(PVOID const volatile *)&##_variable"
    corrected = b"(PVOID const volatile *)&_variable"
    if original in contents:
        header.write_bytes(contents.replace(original, corrected, 1))
    elif corrected not in contents:
        raise RuntimeError("Unexpected WDK wdm.h macro; inspect before building")


def configure_linker() -> None:
    link = ROOT / "toolchain/lld-link"
    if link.exists():
        return
    sysroot = pathlib.Path(subprocess.check_output(
        ["rustc", "--print", "sysroot"], text=True).strip())
    candidates = list(sysroot.glob("lib/rustlib/*/bin/rust-lld"))
    if len(candidates) != 1:
        raise RuntimeError("Unable to locate rust-lld in the Rust toolchain")
    link.parent.mkdir(exist_ok=True)
    link.symlink_to(candidates[0])


def create_test_certificate() -> None:
    private = ROOT / "build/private/test-key.pem"
    pem = ROOT / "build/test-cert.pem"
    public = ROOT / "package/VirKeyArm64-Test.cer"
    if private.exists() and pem.exists() and public.exists():
        return
    private.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256",
        "-nodes", "-days", "7", "-subj", "/CN=VirKeyArm64 Test",
        "-keyout", str(private), "-out", str(pem),
    ], check=True)
    private.chmod(0o600)
    subprocess.run([
        "openssl", "x509", "-in", str(pem), "-outform", "DER",
        "-out", str(public),
    ], check=True)


def main() -> None:
    VENDOR.mkdir(exist_ok=True)
    for package, digest, destination in PACKAGES:
        fetch_package(package, digest, destination)
    patch_wdk_header()
    configure_linker()
    create_test_certificate()
    print("Mac build dependencies and local test certificate are ready")


if __name__ == "__main__":
    main()
