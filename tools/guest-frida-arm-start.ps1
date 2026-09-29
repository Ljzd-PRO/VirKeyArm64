$ErrorActionPreference = 'Stop'
$source = '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\frida-server-arm64.exe'
$target = 'C:\Temp\frida-server-arm64.exe'
Get-Process frida-server-arm64 -ErrorAction SilentlyContinue | Stop-Process -Force
if (!(Test-Path $target)) { Copy-Item $source $target }
$temp = 'C:\Temp\VirKeyFridaArm'
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$launch = New-Object System.Diagnostics.ProcessStartInfo
$launch.FileName = $target
$launch.Arguments = '-l 10.211.55.4:27044'
$launch.UseShellExecute = $false
$launch.CreateNoWindow = $true
$launch.RedirectStandardOutput = $true
$launch.RedirectStandardError = $true
$launch.EnvironmentVariables['TEMP'] = $temp
$launch.EnvironmentVariables['TMP'] = $temp
$process = [System.Diagnostics.Process]::Start($launch)
Get-Process -Id $process.Id | Select-Object Id, ProcessName, Path
New-NetFirewallRule -DisplayName 'VirKey temporary Frida ARM64' -Direction Inbound `
    -LocalPort 27044 -Protocol TCP -Action Allow -Profile Any -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Enabled
