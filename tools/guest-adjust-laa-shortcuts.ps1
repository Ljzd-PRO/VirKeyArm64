$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$current = Join-Path $product 'solidcame.exe'
$backup = Join-Path $product 'solidcame-no-laa-unmodified.exe'
$laaHash = '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726'
$originalHash = '26D72B6C13A5704BF49097EB534D3B86F93F931870744B195373F2B54395DC7B'
if ((Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash -ne $laaHash) { throw 'Default launcher is not the verified LAA copy' }
if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $originalHash) { throw 'Original backup is not verified' }
$shell = New-Object -ComObject WScript.Shell
$publicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
$userDesktop = [Environment]::GetFolderPath('DesktopDirectory')
$installedPath = Join-Path $publicDesktop 'SolidCAM2024E.lnk'
$newPath = Join-Path $userDesktop 'SolidCAM2024E 无修改版.lnk'
$oldPath = Join-Path $userDesktop 'SolidCAM2024E ARM64 (LAA).lnk'
if (!(Test-Path -LiteralPath $installedPath)) { throw 'Installed desktop shortcut missing' }
$installed = $shell.CreateShortcut($installedPath)
if ($installed.TargetPath -ne $current -or $installed.Arguments -ne '') { throw 'Installed desktop shortcut differs from expected target or arguments' }
if (Test-Path -LiteralPath $newPath) {
    $existing = $shell.CreateShortcut($newPath)
    if ($existing.TargetPath -ne $backup -or $existing.Arguments -ne '' -or $existing.WorkingDirectory.TrimEnd('\') -ne $installed.WorkingDirectory.TrimEnd('\')) { throw 'Existing unmodified desktop shortcut differs' }
} else {
    $link = $shell.CreateShortcut($newPath)
    $link.TargetPath = $backup
    $link.Arguments = $installed.Arguments
    $link.WorkingDirectory = $installed.WorkingDirectory
    $link.IconLocation = "$backup,0"
    $link.Description = 'SolidCAM Embedded 2024 original launcher without LAA modification'
    $link.Save()
}
$verified = $false
for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $readback = $shell.CreateShortcut($newPath)
    $verified = $readback.TargetPath -eq $backup -and $readback.Arguments -eq '' -and $readback.WorkingDirectory.TrimEnd('\') -eq $installed.WorkingDirectory.TrimEnd('\')
    if ($verified) { break }
    Start-Sleep -Milliseconds 200
}
if (!$verified) { throw 'Desktop shortcut readback failed' }
if (Test-Path -LiteralPath $oldPath) {
    $old = $shell.CreateShortcut($oldPath)
    if ($old.TargetPath -ne (Join-Path $product 'solidcame-arm64-diagnostic.exe')) { throw 'Old LAA desktop shortcut points elsewhere; refusing to remove' }
    Remove-Item -LiteralPath $oldPath
}
[pscustomobject]@{OriginalName=$installedPath;OriginalTarget=$installed.TargetPath;UnmodifiedName=$newPath;UnmodifiedTarget=$readback.TargetPath;OldLaaShortcutRemoved=!(Test-Path -LiteralPath $oldPath)} | ConvertTo-Json -Depth 3
