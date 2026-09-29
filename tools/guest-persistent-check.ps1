$ErrorActionPreference = 'Stop'
$expectedHash = '3B59BEDBFDA7CC6B3A734D50AAE061CC689A623F730509F0E3146C645D68BB28'
$expectedThumbprint = '1E23EF7DBBD587E79291DF8C75E186C4C110B7F3'
$boot = (& bcdedit.exe /enum '{current}' | Out-String)
if ($boot -notmatch 'testsigning\s+Yes') { throw 'Test signing is not enabled' }
if (Confirm-SecureBootUEFI) { throw 'Secure Boot is still enabled' }
$certificate = Get-ChildItem Cert:\LocalMachine\Root |
    Where-Object Thumbprint -eq $expectedThumbprint
if (!$certificate) { throw 'VirKeyArm64 test certificate missing from LocalMachine Root' }
$publisher = Get-ChildItem Cert:\LocalMachine\TrustedPublisher |
    Where-Object Thumbprint -eq $expectedThumbprint
if (!$publisher) { throw 'VirKeyArm64 test certificate missing from TrustedPublisher' }
$dump = 'HKLM:\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps\4C8F743C'
if (!(Test-Path $dump)) { throw 'SC dump missing from VirKeyArm64 registry path' }
$selection = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\aksusb'
if ($selection.SelectedSerialNumber -ne 0x4F2F4F2D -or
    $selection.SelectedFromNewRoot -ne 1) { throw 'Wrong SC registry dump selected' }
$ids = @('ROOT\VIRKEYARM64\0000',
    'USB\VID_0529&PID_0001\2&3B88D3F4&0&1',
    'USB\HASP\3&12B1D3C7&0&SC00')
foreach ($id in $ids) {
    $device = Get-PnpDevice -InstanceId $id -ErrorAction Stop
    if ($device.Status -ne 'OK' -or $device.Problem -ne 'CM_PROB_NONE') {
        throw "Device not healthy: $id"
    }
    "DEVICE OK: $id"
}
foreach ($service in @('aksusb','akshasp')) {
    $image = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $service)).ImagePath
    $path = $image.Replace('\SystemRoot', $env:SystemRoot)
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash
    if ($hash -ne $expectedHash) { throw "Driver hash mismatch for $service" }
    "DRIVER OK: $service $hash"
}
$packages = @(Get-CimInstance Win32_PnPSignedDriver |
    Where-Object DriverProviderName -eq 'VirKeyArm64')
if ($packages.Count -ne 3 -or
    @($packages | Where-Object DriverVersion -ne '0.1.0.30').Count -ne 0) {
    throw 'Driver package version or count mismatch'
}
if (!(Test-Path 'C:\Program Files\SolidCAM2024\SolidCAMCAD2024\sldworks.exe')) {
    throw 'Installed CAD host is missing'
}
if (!(Test-Path 'C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe')) {
    throw 'Solidcam.exe is missing'
}
"CERTIFICATE OK: $expectedThumbprint"
'REGISTRY OK: SC dump from VirKeyArm64 path'
'PACKAGES OK: 0.1.0.30 root, USB, HASP'
'APPLICATIONS OK: SolidCAM and CAD host present'
'PERSISTENT INSTALLATION PASSED'
