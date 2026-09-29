param([string]$Destination =
    '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\guest-evidence')
$ErrorActionPreference = 'Stop'
$destination = $Destination
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item 'C:\Windows\inf\setupapi.dev.log' (Join-Path $destination 'setupapi.dev.log') -Force
& bcdedit.exe /enum '{current}' | Out-File (Join-Path $destination 'bcdedit.txt') -Encoding utf8
& manage-bde.exe -status C: | Out-File (Join-Path $destination 'bitlocker.txt') -Encoding utf8
Get-PnpDevice | Where-Object {
    $_.FriendlyName -match 'VirKeyArm64' -or
    $_.InstanceId -like 'USB\VID_0529&PID_0001*' -or
    $_.InstanceId -like 'USB\HASP*'
} | Select-Object Class,FriendlyName,InstanceId,Status,Problem |
    Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'devices.txt') -Encoding utf8
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\aksusb' |
    Select-Object Global*,Diagnostic*,Selected*,Observed*,UnsupportedChallengeCount,
                  LastChallenge*,ImagePath |
    Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'driver-status.txt') -Encoding utf8
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\akshasp' |
    Select-Object Diagnostic*,Observed*,UnsupportedChallengeCount,
                  LastChallenge*,ImagePath |
    Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'hasp-driver-status.txt') -Encoding utf8
Get-Service hasplms -ErrorAction SilentlyContinue |
    Select-Object Name,Status,StartType | Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'hasplms-service.txt') -Encoding utf8
$since = (Get-Date).AddHours(-3)
Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'solidcam|solidcame|0xc0000017' } |
    Select-Object TimeCreated,ProviderName,Id,Message |
    Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'application-events.txt') -Encoding utf8
Get-WinEvent -FilterHashtable @{LogName='System';StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'VirKeyArm64|aksusb|akshasp|VID_0529|USB\\HASP|ROOT\\VIRKEYARM64' } |
    Select-Object TimeCreated,ProviderName,Id,Message |
    Format-List | Out-String -Width 240 |
    Out-File (Join-Path $destination 'system-events.txt') -Encoding utf8
Get-ChildItem $destination | Select-Object Name,Length | Format-Table -AutoSize

$driverPaths = foreach ($service in @('aksusb','akshasp')) {
    $image = (Get-ItemProperty ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $service)).ImagePath
    $image.Replace('\SystemRoot', $env:SystemRoot)
}
Get-FileHash ($driverPaths + @('C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe')) -Algorithm SHA256 |
    Format-List | Out-File (Join-Path $destination 'loaded-file-hashes.txt') -Encoding utf8
Get-CimInstance Win32_PnPSignedDriver | Where-Object DriverProviderName -eq 'VirKeyArm64' |
    Select-Object DeviceName,DriverVersion,InfName,IsSigned |
    Format-List | Out-File (Join-Path $destination 'driver-packages.txt') -Encoding utf8
Get-Process Solidcam -ErrorAction SilentlyContinue |
    Select-Object Id,Path,StartTime |
    Format-List | Out-File (Join-Path $destination 'solidcam-process.txt') -Encoding utf8
