#!/usr/bin/env python3
"""Extract only the SC dump from the supplied registry export.

The source export also contains a ROOT certificate. This extractor never
copies that certificate into the guest import file.
"""
from pathlib import Path

source = Path('/Users/ljzd/Downloads/SC_IM.reg')
destination = Path(__file__).resolve().parents[1] / 'package/VirKeyArm64-SC-Test.reg'
contents = source.read_text(encoding='utf-16')
header = ('[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\MulttKey'
          '\\Dumps\\4C8F743C]')
if contents.count(header) != 1:
    raise SystemExit('Expected one current-control-set SC dump')
block = contents.split(header, 1)[1].split('\n[', 1)[0].strip()
target = ('[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\VirKeyArm64'
          '\\Dumps\\4C8F743C]')
output = 'Windows Registry Editor Version 5.00\r\n\r\n' + target + '\r\n' + block + '\r\n'
if output.count('\n[') != 1 or 'SystemCertificates' in output:
    raise SystemExit('Unexpected extra registry section')
destination.write_text(output, encoding='utf-16')
print(destination)
