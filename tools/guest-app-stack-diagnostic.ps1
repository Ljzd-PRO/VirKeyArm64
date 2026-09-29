$ErrorActionPreference = 'Continue'
function Get-PeMachine($path) {
    if (!(Test-Path $path)) { return }
    $f = [IO.File]::OpenRead($path)
    try {
        $reader = New-Object IO.BinaryReader($f)
        $f.Position = 0x3c
        $pe = $reader.ReadInt32()
        $f.Position = $pe + 4
        $machine = $reader.ReadUInt16()
        $f.Position = $pe + 0x18
        $magic = $reader.ReadUInt16()
        [pscustomobject]@{Path=$path;Machine=('0x{0:X4}' -f $machine);Magic=('0x{0:X4}' -f $magic);
            Length=$f.Length;Version=(Get-Item $path).VersionInfo.FileVersion}
    } finally { $f.Close() }
}
'=== EXE architectures ==='
@('C:\Program Files\SolidCAM2024\Solidcam\solidcame.exe',
  'C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe',
  'C:\Program Files\SolidCAM2024\SolidCAMCAD2024\sldworks.exe') |
    ForEach-Object { Get-PeMachine $_ } | Format-List
'=== Sentinel services/processes ==='
Get-Service | Where-Object { $_.Name -match 'hasp|aks|sentinel' -or
                             $_.DisplayName -match 'hasp|aks|sentinel' } |
    Select-Object Name,DisplayName,Status,StartType | Format-List
Get-Process | Where-Object { $_.Name -match 'hasp|aks|sentinel' } |
    Select-Object Name,Id,Path | Format-List
'=== Available installers ==='
Get-ChildItem 'C:\Program Files\SolidCAM2024' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'hasp|sentinel|license|licence|aksusb' -and
                   $_.Extension -match '\.exe|\.msi|\.sys' } |
    Select-Object -First 40 FullName,Length | Format-List
'=== Boot state ==='
& bcdedit.exe /enum '{current}'
