$since = (Get-Date).AddHours(-8)
Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since } -ErrorAction SilentlyContinue |
  Where-Object { $_.ProviderName -match 'Wdf|Kernel-PnP|Service Control' -and $_.Message -match 'VirKey|WDF|framework' } |
  Select-Object -First 50 TimeCreated, ProviderName, Id, Message |
  ConvertTo-Json -Depth 3
