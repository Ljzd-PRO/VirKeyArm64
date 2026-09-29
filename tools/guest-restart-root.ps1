$ErrorActionPreference = 'Stop'
$root = Get-PnpDevice | Where-Object {
    $_.FriendlyName -eq 'VirKeyArm64 Virtual USB Controller'
} | Select-Object -First 1
if (!$root) { throw 'VirKeyArm64 root node missing' }
& pnputil.exe /restart-device $root.InstanceId
if ($LASTEXITCODE -ne 0) { throw "Failed to restart $($root.InstanceId)" }
Start-Sleep -Seconds 2
Get-PnpDevice | Where-Object {
    $_.InstanceId -eq $root.InstanceId -or
    $_.InstanceId -like 'USB\VID_0529&PID_0001*' -or
    $_.InstanceId -like 'USB\HASP*'
} | Select-Object InstanceId, Status, Problem | Format-List
