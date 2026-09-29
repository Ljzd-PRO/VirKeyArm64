Get-PnpDevice -PresentOnly | Where-Object {
  $_.InstanceId -like 'USB\VID_0529*' -or $_.FriendlyName -match 'VirKey|Unknown USB'
} | Select-Object Class, FriendlyName, InstanceId, Status, Problem | Format-List
Get-PnpDevice -InstanceId 'ROOT\DEVGEN\{286AF392-9EBC-5B4C-B92B-EA1B2ABA5B53}' |
  Select-Object InstanceId, Status, Problem | Format-List
