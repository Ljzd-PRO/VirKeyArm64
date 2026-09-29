$ErrorActionPreference = 'Continue'
'=== OS ==='
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,OSArchitecture,Version,FreePhysicalMemory | Format-List
'=== SOLIDWORKS and SolidCAM locations ==='
Get-ChildItem 'C:\Program Files' -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'Solid|CAM' } | Select-Object FullName
Get-ChildItem 'C:\Program Files\SOLIDWORKS Corp' -Recurse -Filter SLDWORKS.exe -ErrorAction SilentlyContinue |
    Select-Object -First 10 FullName,Length,@{N='Version';E={$_.VersionInfo.FileVersion}}
Get-ChildItem 'C:\Program Files\SolidCAM2024' -Recurse -Filter sldworks.exe -ErrorAction SilentlyContinue |
    Select-Object -First 10 FullName,Length,@{N='Version';E={$_.VersionInfo.FileVersion}}
'=== Boot and BitLocker ==='
& bcdedit.exe /enum '{current}' | Select-String 'testsigning|loadoptions|path|description'
& manage-bde.exe -status C: | Select-String 'Conversion Status|Protection Status|Lock Status'
'=== Driver and dump ==='
Get-PnpDevice | Where-Object {
    $_.FriendlyName -match 'VirKeyArm64' -or $_.InstanceId -like 'USB\VID_0529&PID_0001*'
} | Select-Object FriendlyName,InstanceId,Status,Problem | Format-List
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VirKeyArm64' -ErrorAction SilentlyContinue |
    Select-Object ImagePath,DiagnosticStatus,SelectedSerialNumber | Format-List
Get-Item 'HKLM:\SYSTEM\CurrentControlSet\MulttKey\Dumps\4C8F743C' -ErrorAction SilentlyContinue |
    Select-Object Name
'=== Test certificate and Sentinel service ==='
Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
    Where-Object Subject -like '*VirKeyArm64*' | Select-Object Subject,NotAfter
Get-Service hasplms -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType
