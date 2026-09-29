$paths = @(
    'C:\Program Files\SolidCAM2024\Solidcam\solidcame.exe',
    'C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe',
    'C:\Program Files\SolidCAM2024\SolidCAMCAD2024\sldworks.exe'
)
foreach ($path in $paths) {
    if (!(Test-Path $path)) { continue }
    $stream = [IO.File]::OpenRead($path)
    try {
        $reader = New-Object IO.BinaryReader($stream)
        $stream.Position = 0x3c
        $pe = $reader.ReadUInt32()
        $stream.Position = $pe + 4
        $machine = $reader.ReadUInt16()
        $sections = $reader.ReadUInt16()
        $stream.Position = $pe + 0x18
        $magic = $reader.ReadUInt16()
        if ($magic -ne 0x20b) { continue }
        $stream.Position = $pe + 0x18 + 16
        $entry = $reader.ReadUInt32()
        $stream.Position = $pe + 0x18 + 56
        $imageSize = $reader.ReadUInt32()
        $stream.Position = $pe + 0x18 + 68
        $subsystem = $reader.ReadUInt16()
        $dllCharacteristics = $reader.ReadUInt16()
        $stackReserve = $reader.ReadUInt64()
        $stackCommit = $reader.ReadUInt64()
        $heapReserve = $reader.ReadUInt64()
        $heapCommit = $reader.ReadUInt64()
        [pscustomobject]@{
            Path=$path;Machine=('0x{0:X4}' -f $machine);Sections=$sections
            Entry=('0x{0:X8}' -f $entry);ImageSize=$imageSize
            Subsystem=$subsystem;DllCharacteristics=('0x{0:X4}' -f $dllCharacteristics)
            StackReserve=$stackReserve;StackCommit=$stackCommit
            HeapReserve=$heapReserve;HeapCommit=$heapCommit
            FileSize=$stream.Length
        } | Format-List
    } finally { $stream.Close() }
}
'=== Current memory ==='
Get-CimInstance Win32_OperatingSystem |
    Select-Object FreePhysicalMemory,TotalVisibleMemorySize,FreeVirtualMemory,TotalVirtualMemorySize | Format-List
'=== Recent application and WER events ==='
$since=(Get-Date).AddMinutes(-30)
Get-WinEvent -FilterHashtable @{LogName='Application';StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'solidcame|solidcam|sldworks|0xc0000017' } |
    Select-Object TimeCreated,ProviderName,Id,Message |
    Format-List | Out-String -Width 240
