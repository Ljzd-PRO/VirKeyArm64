$ErrorActionPreference = 'Stop'
$devices = Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB\HASP*' }
foreach ($device in $devices) {
    & pnputil.exe /restart-device $device.InstanceId
    if ($LASTEXITCODE -ne 0) { throw "Failed to restart $($device.InstanceId)" }
}
Get-PnpDevice | Where-Object {
    $_.InstanceId -like 'USB\HASP*' -or $_.InstanceId -like 'USB\VID_0529&PID_0001*'
} | Select-Object InstanceId, Status, Problem | Format-List
