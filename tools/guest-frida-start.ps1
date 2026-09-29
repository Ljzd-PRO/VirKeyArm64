$ErrorActionPreference = 'Stop'
$source = '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\frida-server.exe'
$target = 'C:\Temp\frida-server-x64.exe'
Copy-Item $source $target -Force
Get-Process frida-server-x64 -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process -FilePath $target -ArgumentList '-l 10.211.55.4:27043' -PassThru |
    Select-Object Id, ProcessName, Path
New-NetFirewallRule -DisplayName 'VirKey temporary Frida' -Direction Inbound `
    -LocalPort 27043 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Enabled
