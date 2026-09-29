$destination='\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\build\guest-apps'
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item 'C:\Program Files\SolidCAM2024\Solidcam\solidcame.exe' (Join-Path $destination 'solidcame.exe') -Force
Copy-Item 'C:\Program Files\SolidCAM2024\SolidCAMCAD2024\sldworks.exe' (Join-Path $destination 'sldworks.exe') -Force
Get-ChildItem $destination | Select-Object Name,Length
