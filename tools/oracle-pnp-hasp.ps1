$ErrorActionPreference = 'Stop'
Get-PnpDevice | Where-Object { $_.InstanceId -like 'USB\HASP*' } |
  ForEach-Object {
    Write-Output "DEVICE $($_.InstanceId) $($_.Status) $($_.FriendlyName)"
    $id = $_.InstanceId
    Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_Parent',
        'DEVPKEY_Device_HardwareIds','DEVPKEY_Device_LocationPaths' `
        -ErrorAction SilentlyContinue |
      ForEach-Object { Write-Output "$($_.KeyName)=$($_.Data -join ',')" }
  }
