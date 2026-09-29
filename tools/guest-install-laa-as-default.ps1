$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$original = Join-Path $product 'solidcame.exe'
$diagnostic = Join-Path $product 'solidcame-arm64-diagnostic.exe'
$backup = Join-Path $product 'solidcame-no-laa-unmodified.exe'
$readme = Join-Path $product 'SOLIDCAME-LAA-README.md'
$readmeSource = '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\docs\SOLIDCAME-LAA-README.md'
$originalHash = '26D72B6C13A5704BF49097EB534D3B86F93F931870744B195373F2B54395DC7B'
$laaHash = '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726'
function Get-Sha($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

if (!(Test-Path -LiteralPath $original)) { throw 'Original launcher path missing' }
$current = Get-Sha $original
if ($current -ne $originalHash -and $current -ne $laaHash) { throw 'Unknown installed launcher version' }
if ($current -eq $originalHash) {
    if (Test-Path -LiteralPath $backup) {
        if ((Get-Sha $backup) -ne $originalHash) { throw 'Existing backup has unexpected content' }
    } else {
        Copy-Item -LiteralPath $original -Destination $backup
        if ((Get-Sha $backup) -ne $originalHash) { throw 'Backup verification failed' }
    }
    if (!(Test-Path -LiteralPath $diagnostic) -or (Get-Sha $diagnostic) -ne $laaHash) { throw 'Verified LAA copy missing' }
    try {
        Copy-Item -LiteralPath $diagnostic -Destination $original -Force
        if ((Get-Sha $original) -ne $laaHash) { throw 'Replacement verification failed' }
    } catch {
        Copy-Item -LiteralPath $backup -Destination $original -Force
        throw
    }
} elseif (!(Test-Path -LiteralPath $backup) -or (Get-Sha $backup) -ne $originalHash) {
    throw 'LAA launcher installed but verified original backup missing'
}

if (!(Test-Path -LiteralPath $readmeSource)) { throw 'Documentation source missing' }
if (Test-Path -LiteralPath $readme) {
    if ((Get-Sha $readme) -ne (Get-Sha $readmeSource)) { throw 'Existing documentation differs; refusing to overwrite' }
} else {
    Copy-Item -LiteralPath $readmeSource -Destination $readme
}

$startMenu = 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SolidCAM2024'
$installedLink = Join-Path $startMenu 'SolidCAM2024E.lnk'
$backupLink = Join-Path $startMenu 'SolidCAM2024E 无修改版.lnk'
$shell = New-Object -ComObject WScript.Shell
if (!(Test-Path -LiteralPath $installedLink)) { throw 'Installed Start Menu shortcut missing' }
$installed = $shell.CreateShortcut($installedLink)
if ($installed.TargetPath -ne $original -or $installed.Arguments -ne '') { throw 'Installed shortcut differs from expected target or arguments' }
if (Test-Path -LiteralPath $backupLink) {
    $old = $shell.CreateShortcut($backupLink)
    if ($old.TargetPath -ne $backup -or $old.Arguments -ne '' -or $old.WorkingDirectory.TrimEnd('\') -ne $installed.WorkingDirectory.TrimEnd('\')) { throw 'Existing unmodified shortcut differs' }
} else {
    $link = $shell.CreateShortcut($backupLink)
    $link.TargetPath = $backup
    $link.Arguments = $installed.Arguments
    $link.WorkingDirectory = $installed.WorkingDirectory
    $link.IconLocation = "$backup,0"
    $link.Description = 'SolidCAM Embedded 2024 original launcher without LAA modification'
    $link.Save()
}
$check = $shell.CreateShortcut($backupLink)
if ($check.TargetPath -ne $backup -or $check.Arguments -ne '' -or $check.WorkingDirectory.TrimEnd('\') -ne $installed.WorkingDirectory.TrimEnd('\')) { throw 'Start Menu shortcut readback failed' }
[pscustomobject]@{Launcher=$original;LauncherSHA256=(Get-Sha $original);Backup=$backup;BackupSHA256=(Get-Sha $backup);Readme=$readme;ReadmeSHA256=(Get-Sha $readme);StartMenuOriginal=$installedLink;StartMenuUnmodified=$backupLink} | ConvertTo-Json -Depth 3
