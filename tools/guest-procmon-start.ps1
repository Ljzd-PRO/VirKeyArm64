param([string]$TraceName='solidcame-start')
$ErrorActionPreference='Stop'
$source='\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\diagnostics\Procmon64a.exe'
$directory='C:\Temp\VirKeyDiagnostics'
$exe=Join-Path $directory 'Procmon64a.exe'
$log=Join-Path $directory ($TraceName+'.pml')
New-Item -ItemType Directory -Force $directory | Out-Null
Copy-Item $source $exe -Force
$signature=Get-AuthenticodeSignature $exe
if ($signature.Status -ne 'Valid') { throw "ProcMon signature status: $($signature.Status)" }
if (Test-Path $log) { Remove-Item $log -Force }
$process=Start-Process -FilePath $exe -ArgumentList @('/AcceptEula','/Quiet','/Minimized','/BackingFile',$log) -PassThru
Start-Sleep -Seconds 3
$process.Refresh()
[pscustomobject]@{Exe=$exe;Signature=$signature.Status;Pid=$process.Id;
    Exited=$process.HasExited;LogExists=(Test-Path $log)} | Format-List
