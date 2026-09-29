#!/bin/zsh
set -eu
cd "${0:A:h}"

make -C vendor/generate-cat-file >/dev/null
inf_sha1=$(shasum -a1 package/VirKeyArm64.inf | awk '{print toupper($1)}')
inf_sha256=$(shasum -a256 package/VirKeyArm64.inf | awk '{print toupper($1)}')
sys_sha1=$(vendor/generate-cat-file/strip-pe-image package/VirKeyArm64.sys | shasum -a1 | awk '{print toupper($1)}')
sys_sha256=$(vendor/generate-cat-file/strip-pe-image package/VirKeyArm64.sys | shasum -a256 | awk '{print toupper($1)}')

(
  cd package
  ../vendor/generate-cat-file/generate-cat-file \
    -O _v100_ARM64_GE -A 2:10.0 -h 'ROOT\VirKeyArm64' \
    "VirKeyArm64.inf:${inf_sha1}" \
    "VirKeyArm64.inf:${inf_sha256}" \
    "VirKeyArm64.sys:${sys_sha1}:PE" \
    "VirKeyArm64.sys:${sys_sha256}:PE" > VirKeyArm64.unsigned.cat
)
osslsigncode sign \
  -certs build/test-cert.pem -key build/private/test-key.pem -h sha256 \
  -in package/VirKeyArm64.unsigned.cat \
  -out package/VirKeyArm64.new.cat >/dev/null
mv package/VirKeyArm64.new.cat package/VirKeyArm64.cat
