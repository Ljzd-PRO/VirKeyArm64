$ErrorActionPreference='Stop'
$directory='C:\Program Files\SolidCAM2024\Solidcam'
$processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(solidcam|sldworks|solidcame-arm64-diagnostic)\.exe$' } |
    Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CommandLine)
$modules = foreach ($process in $processes) {
    try {
        (Get-Process -Id $process.ProcessId).Modules |
            Where-Object { $_.ModuleName -match '^(sldworks\.exe|Solidcam\.exe|HostLibSWEM\.dll|sldappu\.dll)$' } |
            ForEach-Object { [pscustomobject]@{ProcessId=$process.ProcessId;Path=$_.FileName;FileVersion=$_.FileVersionInfo.FileVersion} }
    } catch { [pscustomobject]@{ProcessId=$process.ProcessId;ReadError=$_.Exception.Message} }
}
$files = foreach ($name in @('solidcame.exe','solidcame-arm64-diagnostic.exe')) {
    $path=Join-Path $directory $name
    [pscustomobject]@{Path=$path;SHA256=(Get-FileHash $path -Algorithm SHA256).Hash;SignatureStatus=[string](Get-AuthenticodeSignature $path).Status}
}
[pscustomobject]@{CapturedAt=(Get-Date).ToString('o');Processes=$processes;Modules=@($modules);Files=@($files)} | ConvertTo-Json -Depth 5
