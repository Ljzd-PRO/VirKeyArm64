$ErrorActionPreference = 'Stop'
$source = (Join-Path (Split-Path $PSScriptRoot -Parent) 'package')
$destination = 'C:\Temp\VirKeyArm64'
New-Item -ItemType Directory -Force $destination | Out-Null
if (Test-Path $source) {
    foreach ($name in @('VirKeyArm64.sys', 'VirKeyArm64.inf',
                        'VirKeyArm64.cat', 'VirKeyNode.exe')) {
        Copy-Item (Join-Path $source $name) (Join-Path $destination $name) -Force
    }
    $haspDestination = Join-Path $destination 'hasp'
    New-Item -ItemType Directory -Force $haspDestination | Out-Null
    foreach ($name in @('VirKeyArm64.sys', 'VirKeyArm64.inf',
                        'VirKeyArm64.cat')) {
        Copy-Item (Join-Path (Join-Path $source 'hasp') $name) (Join-Path $haspDestination $name) -Force
    }
    $localScript = Join-Path $destination 'guest-install-and-probe.ps1'
    if ($PSCommandPath -ne $localScript) {
        Copy-Item $PSCommandPath $localScript -Force
    }
}
$node = Join-Path $destination 'VirKeyNode.exe'
& pnputil.exe /add-driver (Join-Path $destination 'hasp\VirKeyArm64.inf') /install
if ($LASTEXITCODE -eq 3010) {
    Write-Output 'HASP package staged; reboot and rerun this script'
    exit 3010
}
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 259) {
    throw "Failed to install HASP child driver package: $LASTEXITCODE"
}
& $node create
if ($LASTEXITCODE -ne 0) { throw 'Failed to create VirKeyArm64 root node' }
& pnputil.exe /add-driver (Join-Path $destination 'VirKeyArm64.inf') /install
if ($LASTEXITCODE -eq 3010) {
    Write-Output 'Driver package staged; guest reboot required before probe'
    exit 3010
}
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 259) {
    throw "Failed to install VirKeyArm64 package: $LASTEXITCODE"
}
$root = (Get-PnpDevice | Where-Object { $_.FriendlyName -eq 'VirKeyArm64 Virtual USB Controller' } | Select-Object -First 1).InstanceId
if (!$root) { throw 'VirKeyArm64 root device missing' }
& pnputil.exe /restart-device $root
if ($LASTEXITCODE -ne 0) { throw 'Failed to restart VirKeyArm64 root node' }
Start-Sleep -Seconds 2
& $node probe
Write-Output "ProbeExitCode=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw 'VirKeyArm64 interface probe failed' }
Get-PnpDevice | Where-Object {
    $_.InstanceId -eq $root -or $_.InstanceId -like 'USB\VID_0529&PID_0001*' -or
    $_.InstanceId -like 'USB\HASP*'
} | Select-Object FriendlyName, InstanceId, Status, Problem | Format-List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\aksusb' |
    Select-Object SelectedSerialNumber, SelectedDumpName,
                  UnsupportedChallengeCount | Format-List
