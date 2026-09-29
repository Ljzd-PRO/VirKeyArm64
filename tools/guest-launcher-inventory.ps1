$ErrorActionPreference = 'Stop'
$root = 'C:\Program Files\SolidCAM2024'
$folders = @('Desktop','CommonDesktopDirectory','Programs','CommonPrograms') |
    ForEach-Object { [Environment]::GetFolderPath($_) } | Select-Object -Unique
$shell = New-Object -ComObject WScript.Shell
$entries = foreach ($folder in $folders) {
    if (!$folder -or !(Test-Path $folder)) { continue }
    Get-ChildItem $folder -Filter '*SolidCAM*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $shortcut = $shell.CreateShortcut($_.FullName)
        [pscustomobject]@{Shortcut=$_.FullName;Target=$shortcut.TargetPath;Arguments=$shortcut.Arguments;WorkingDirectory=$shortcut.WorkingDirectory}
    }
}
$files = foreach ($relative in @('Solidcam\solidcame.exe','Solidcam\Solidcam.exe','SolidCAMCAD2024\sldworks.exe','Solidcam\HostLibSWEM.dll','Solidcam\mfc140.dll')) {
    $path = Join-Path $root $relative
    if (Test-Path $path) {
        $item = Get-Item $path
        [pscustomobject]@{Path=$path;Length=$item.Length;FileVersion=$item.VersionInfo.FileVersion;ProductVersion=$item.VersionInfo.ProductVersion;Hash=(Get-FileHash $path -Algorithm SHA256).Hash}
    }
}
$processes = Get-CimInstance Win32_Process | Where-Object Name -match '^(sldworks|solidcam|solidcame)\.exe$' |
    Select-Object Name,ProcessId,ParentProcessId,ExecutablePath,CommandLine
$registry = @()
foreach ($path in @('Registry::HKEY_CLASSES_ROOT\SolidCAMCAD2024.Application\CLSID','HKLM:\SOFTWARE\SolidCAM\SolidCAMCAD2024')) {
    if (Test-Path $path) {
        $key = Get-Item $path
        $values = @{}
        foreach ($name in $key.GetValueNames()) {
            if ($name -match 'security|oem|license|password') { continue }
            $values[$name] = $key.GetValue($name)
        }
        $registry += [pscustomobject]@{Path=$path;Values=$values}
    }
}
[pscustomobject]@{Entries=@($entries);Files=@($files);Processes=@($processes);Registry=$registry} | ConvertTo-Json -Depth 8
