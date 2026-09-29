$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$original = Join-Path $product 'solidcame.exe'
$launcher = Join-Path $product 'solidcame-arm64-diagnostic.exe'
if ((Get-FileHash $original -Algorithm SHA256).Hash -ne '26D72B6C13A5704BF49097EB534D3B86F93F931870744B195373F2B54395DC7B') { throw 'Original launcher version changed; revalidate LAA fix' }
if ((Get-FileHash $launcher -Algorithm SHA256).Hash -ne '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726') { throw 'Verified LAA launcher copy not found' }
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
if (!$desktop -or !(Test-Path $desktop)) { throw 'Current user desktop not found' }
$path = Join-Path $desktop 'SolidCAM2024E ARM64 (LAA).lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($path)
if (Test-Path $path) {
    if ($shortcut.TargetPath -ne $launcher -or $shortcut.Arguments -ne '' -or $shortcut.WorkingDirectory.TrimEnd('\') -ne $product) { throw 'Existing shortcut differs; refusing to overwrite' }
} else {
    $shortcut.TargetPath = $launcher
    $shortcut.Arguments = ''
    $shortcut.WorkingDirectory = $product
    $shortcut.IconLocation = "$original,0"
    $shortcut.Description = 'SolidCAM Embedded 2024 with LAA enabled for Windows ARM64'
    $shortcut.Save()
}
$verified = $false
# The Parallels shared desktop can briefly return stale metadata after Save().
for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $readback = $shell.CreateShortcut($path)
    $verified = $readback.TargetPath -eq $launcher -and $readback.WorkingDirectory.TrimEnd('\') -eq $product -and $readback.Arguments -eq ''
    if ($verified) { break }
    Start-Sleep -Milliseconds 200
}
if (!$verified) {
    [pscustomobject]@{Shortcut=$path;Target=$readback.TargetPath;Arguments=$readback.Arguments;WorkingDirectory=$readback.WorkingDirectory} | ConvertTo-Json
    throw 'Shortcut readback failed'
}
[pscustomobject]@{Shortcut=$path;Target=$readback.TargetPath;Arguments=$readback.Arguments;WorkingDirectory=$readback.WorkingDirectory;Verified=$true} | ConvertTo-Json
