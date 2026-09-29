$ErrorActionPreference='Stop'
Get-Date -Format o
Get-PnpDevice -PresentOnly | Where-Object {
    $_.InstanceId -like 'ROOT\VIRKEYARM64*' -or $_.FriendlyName -like '*VirKeyArm64*'
} | Select-Object FriendlyName,InstanceId,Status,Problem | Format-List
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
 Where-Object DisplayName -match 'SOLIDWORKS|SolidCAM' |
 Select-Object DisplayName,DisplayVersion,InstallLocation | Format-Table -AutoSize
Get-CimInstance Win32_PnPSignedDriver | Where-Object DriverProviderName -eq 'VirKeyArm64' |
 Select-Object DeviceName,DriverVersion,InfName | Format-List
Get-Process frida-server-arm64,Solidcam -ErrorAction SilentlyContinue |
 Select-Object Id,ProcessName | Format-List
Get-ChildItem 'C:\Program Files\SolidCAM2024' -Filter sldworks.exe -Recurse -ErrorAction SilentlyContinue |
 Select-Object FullName,Length | Format-List
