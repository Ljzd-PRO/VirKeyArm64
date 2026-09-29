$root = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses'
Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
  $guid = $_.PSChildName
  Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue |
    Where-Object PSChildName -match 'VID_0529' |
    ForEach-Object { "${guid}: $($_.PSChildName)" }
}
