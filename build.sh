#!/bin/zsh
set -eu
cd "${0:A:h}"

# The Apple Clang frontend needs one WDK header typo corrected before this
# build: in km/wdm.h, ARM64_PREVENT_REGISTER_WRITEBACK must use &_variable.
# This checkout carries that one-line change in vendor/wdk.
for source in driver registry sc_dump sc_cipher protocol; do
clang -target aarch64-pc-windows-msvc \
  -fms-extensions -fms-compatibility -ffreestanding -fno-builtin \
  -fno-stack-protector -w \
  -D_ARM64_=1 -DARM64 -DWINVER=0x0A00 -D_WIN32_WINNT=0x0A00 \
  -DNTDDI_VERSION=0x0A00000B -DKMDF_VERSION_MINOR=33 \
  -I vendor/wdk/c/Include/10.0.26100.0/km/crt \
  -I vendor/sdk-common/c/Include/10.0.26100.0/shared \
  -I vendor/wdk/c/Include/10.0.26100.0/km \
  -I vendor/wdk/c/Include/10.0.26100.0/km/ude/1.1 \
  -I vendor/wdk/c/Include/wdf/kmdf/1.33 \
  -I vendor/sdk-common/c/Include/10.0.26100.0/um \
  -c "src/${source}.c" -o "build/${source}.obj"
done

# /tsaware:no is essential: lld-link's default TS-aware flag caused
# STATUS_CONFLICTING_ADDRESSES on Windows ARM64 before DriverEntry ran.
toolchain/lld-link /nologo /machine:arm64 /subsystem:native,10.0 \
  /osversion:10.0 /base:0x1c0000000 /driver /release /tsaware:no \
  /entry:FxDriverEntry /out:build/VirKeyArm64.sys \
  build/driver.obj build/registry.obj build/sc_dump.obj build/sc_cipher.obj build/protocol.obj \
  /libpath:vendor/wdk/c/Lib/10.0.26100.0/km/ARM64 \
  /libpath:vendor/wdk/c/Lib/10.0.26100.0/km/ARM64/ude/1.1 \
  /libpath:vendor/wdk/c/Lib/wdf/kmdf/ARM64/1.33 \
  wdfdriverentry.lib wdfldr.lib udecxstub.lib ntoskrnl.lib \
  bufferoverflowfastfailk.lib

cp build/VirKeyArm64.sys package/VirKeyArm64.sys
cp build/VirKeyArm64.sys package/hasp/VirKeyArm64.sys
clang -target aarch64-pc-windows-msvc -fms-extensions -fms-compatibility \
  -ffreestanding -fno-builtin -funwind-tables -w -D_ARM64_=1 -DARM64 \
  -I vendor/wdk/c/Include/10.0.26100.0/km/crt \
  -I vendor/sdk-common/c/Include/10.0.26100.0/shared \
  -I vendor/sdk-common/c/Include/10.0.26100.0/um \
  -I vendor/sdk-common/c/Include/10.0.26100.0/ucrt \
  -c src/node-tool.c -o build/node-tool.obj
toolchain/lld-link /nologo /machine:arm64 /subsystem:console,10.0 \
  /osversion:10.0 /entry:mainCRTStartup /nodefaultlib \
  /tsaware:no /release \
  /out:package/VirKeyNode.exe build/node-tool.obj \
  /libpath:vendor/sdk-arm64/c/um/arm64 \
  kernel32.Lib shell32.lib SetupAPI.Lib
for package_dir in package package/hasp; do
  python3 tools/cat-from-template.py "$package_dir"
  osslsigncode sign -certs build/test-cert.pem -key build/private/test-key.pem \
    -h sha256 -in "$package_dir/VirKeyArm64.unsigned.cat" \
    -out "$package_dir/VirKeyArm64.new.cat" >/dev/null
  mv "$package_dir/VirKeyArm64.new.cat" "$package_dir/VirKeyArm64.cat"
done
