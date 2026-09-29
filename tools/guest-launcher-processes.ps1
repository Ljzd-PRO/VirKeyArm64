$ErrorActionPreference='Stop'
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'solidcam|sldworks' } |
 Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Depth 3
