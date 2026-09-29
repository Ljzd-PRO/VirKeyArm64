$ErrorActionPreference = 'Stop'
Copy-Item '\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\GuestSuspendedLaunch.exe' `
    'C:\Temp\GuestSuspendedLaunch.exe' -Force
Get-Item 'C:\Temp\GuestSuspendedLaunch.exe' | Select-Object FullName,Length
