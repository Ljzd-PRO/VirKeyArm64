$ErrorActionPreference='Stop'
$directory='C:\Program Files\SolidCAM2024\Solidcam'
$original=Join-Path $directory 'solidcame.exe'
if ((Get-FileHash $original -Algorithm SHA256).Hash -ne '26D72B6C13A5704BF49097EB534D3B86F93F931870744B195373F2B54395DC7B') { throw 'Unexpected original launcher' }
$source='\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\launcher-study\solidcame-arm64-diagnostic.exe'
if ((Get-FileHash $source -Algorithm SHA256).Hash -ne '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726') { throw 'Unexpected diagnostic copy' }
$target=Join-Path $directory 'solidcame-arm64-diagnostic.exe'
if (Test-Path $target) { throw 'Diagnostic copy already exists; inspect before replacing' }
Copy-Item $source $target
Get-FileHash $original,$target -Algorithm SHA256 | Format-List
