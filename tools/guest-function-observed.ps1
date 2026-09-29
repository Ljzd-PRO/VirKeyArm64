Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\aksusb' |
  Select-Object *Observed*, Diagnostic* | Format-List
$values = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\aksusb'
foreach ($name in 'ObservedPayload00','ObservedPayload01') {
  if ($null -ne $values.$name) {
    Write-Output "${name}: $([BitConverter]::ToString($values.$name))"
  }
}
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses' |
  Where-Object PSChildName -in @('{29db6d11-bc3c-11d7-b47f-00c0dfee4d8c}',
                                '{bce9d0f1-f7db-11d7-b4bb-00c0dfee4d8c}') |
  ForEach-Object {
    $guid=$_.PSChildName
    Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue |
      Where-Object PSChildName -match 'VID_0529' |
      ForEach-Object { "${guid}: $($_.PSChildName)" }
  }
