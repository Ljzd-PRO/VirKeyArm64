$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$path = Join-Path $product 'solidcame-arm64-diagnostic.exe'
if (!(Test-Path -LiteralPath $path)) { 'Diagnostic copy already absent'; exit 0 }
if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726') { throw 'Diagnostic copy differs; refusing to remove' }
if (Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'solidcame-arm64-diagnostic.exe' }) { throw 'Diagnostic launcher is still running' }
$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @('C:\Users\Public\Desktop','C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SolidCAM2024','C:\Mac\Home\Desktop')) {
    if (!(Test-Path -LiteralPath $folder)) { continue }
    foreach ($item in @(Get-ChildItem -LiteralPath $folder -Filter 'SolidCAM2024E*.lnk' -ErrorAction SilentlyContinue)) {
        if ($shell.CreateShortcut($item.FullName).TargetPath -eq $path) { throw "Shortcut still points to diagnostic copy: $($item.FullName)" }
    }
}
Remove-Item -LiteralPath $path
if (Test-Path -LiteralPath $path) { throw 'Diagnostic copy removal failed' }
'Removed obsolete diagnostic launcher copy after validating replacement and shortcuts'
