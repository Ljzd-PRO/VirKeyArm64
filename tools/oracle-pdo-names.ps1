Get-PnpDevice | Where-Object InstanceId -like 'USB\VID_0529&PID_0001*' | ForEach-Object {
  $d=$_
  $p=Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_PDOName' -ErrorAction SilentlyContinue
  [pscustomobject]@{InstanceId=$d.InstanceId;PDOName=$p.Data;FriendlyName=$d.FriendlyName;Status=$d.Status}
} | Format-List
