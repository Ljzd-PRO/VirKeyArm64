$ErrorActionPreference = 'Continue'
Get-ChildItem 'C:\Program Files\SOLIDWORKS Corp' -ErrorAction SilentlyContinue | Select-Object FullName
Get-ChildItem 'C:\Program Files\SolidCAM2024\Solidcam\solidcam*.exe' | ForEach-Object {
  [pscustomobject]@{ Path=$_.FullName; Version=$_.VersionInfo.FileVersion; Length=$_.Length }
}
Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory,FreeVirtualMemory,TotalVirtualMemorySize
Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'solidcam|solidcame|0xc0000017' } | Select-Object TimeCreated,ProviderName,Id,Message | Format-List
