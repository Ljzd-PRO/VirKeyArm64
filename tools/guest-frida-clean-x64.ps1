$ErrorActionPreference = 'Stop'
Get-Process frida-server-x64 -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Id 3228 -ErrorAction SilentlyContinue | Stop-Process -Force
$helper = 'C:\Windows\Temp\re.frida.server\frida-helper-x86_64.exe'
if (Test-Path $helper) { Remove-Item $helper -Force }
Get-Process frida-server-arm64 -ErrorAction SilentlyContinue |
    Select-Object Id, ProcessName, Path
