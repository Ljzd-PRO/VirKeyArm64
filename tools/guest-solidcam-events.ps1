$since=(Get-Date).AddMinutes(-15)
Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$since} -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'Application Error|Windows Error Reporting|SideBySide' -or $_.Message -match 'solidcam|solidcame' } |
  Select-Object -First 25 TimeCreated,ProviderName,Id,Message |
  Format-List | Out-String -Width 200
