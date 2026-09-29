param([string]$TraceName='solidcame-start')
$ErrorActionPreference='Stop'
$directory='C:\Temp\VirKeyDiagnostics'
$exe=Join-Path $directory 'Procmon64a.exe'
$log=Join-Path $directory ($TraceName+'.pml')
$csv=Join-Path $directory ($TraceName+'.csv')
& $exe /Terminate
Start-Sleep -Seconds 3
Get-Process Procmon64a -ErrorAction SilentlyContinue | Select-Object Id,ProcessName
Get-Item $log -ErrorAction SilentlyContinue | Select-Object FullName,Length
if (Test-Path $csv) { Remove-Item $csv -Force }
& $exe /OpenLog $log /SaveAs $csv
Get-Item $csv -ErrorAction SilentlyContinue | Select-Object FullName,Length
