Get-PnpDevice | Where-Object { $_.FriendlyName -match 'VirKeyArm64' -or $_.InstanceId -like 'USB\VID_0529&PID_0001*' } | Select-Object Class,FriendlyName,InstanceId,Status,Problem | Format-List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VirKeyArm64' | Select-Object Diagnostic*,Selected* | Format-List
