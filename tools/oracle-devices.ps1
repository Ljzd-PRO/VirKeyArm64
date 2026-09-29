$devices = Get-PnpDevice -PresentOnly | Where-Object InstanceId -like 'USB\VID_0529&PID_0001*'
foreach ($device in $devices) {
  Write-Output "DEVICE $($device.InstanceId)"
  Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction SilentlyContinue |
    Where-Object { $_.KeyName -match 'Parent|Driver|Service|Interface|Location|HardwareIds|CompatibleIds|BusReported|Container|Address' } |
    Select-Object KeyName,Data | Format-List | Out-String -Width 240 | Write-Output
  $enumPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $device.InstanceId
  Get-ItemProperty $enumPath -ErrorAction SilentlyContinue |
    Select-Object Service,ClassGUID,Driver,HardwareID,CompatibleIDs,DeviceDesc,Mfg |
    Format-List | Out-String -Width 240 | Write-Output
}
Write-Output 'INTERFACES'
pnputil /enum-interfaces /enabled | Select-String -Pattern '0529|aksusb|0001' -Context 5,5
