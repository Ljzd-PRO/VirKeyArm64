$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$names = @('solidcame.exe', 'solidcame-arm64-diagnostic.exe', 'solidcame-no-laa-unmodified.exe', 'SOLIDCAME-LAA-README.md')
$files = foreach ($name in $names) {
    $path = Join-Path $product $name
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path
        [pscustomobject]@{Path=$path;Length=$item.Length;SHA256=if ($item.PSIsContainer) { $null } else { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }}
    }
}
$shell = New-Object -ComObject WScript.Shell
$folders = @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'),[Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('CommonPrograms')) | Select-Object -Unique
$shortcuts = foreach ($folder in $folders) {
    if (!$folder -or !(Test-Path -LiteralPath $folder)) { continue }
    Get-ChildItem -LiteralPath $folder -Filter 'SolidCAM2024E*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $shortcut = $shell.CreateShortcut($_.FullName)
        [pscustomobject]@{Path=$_.FullName;Target=$shortcut.TargetPath;Arguments=$shortcut.Arguments;WorkingDirectory=$shortcut.WorkingDirectory}
    }
}
$processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(solidcame.*|sldworks|solidcam)\.exe$' } | Select-Object Name,ProcessId,ParentProcessId)
[pscustomobject]@{Files=@($files);Shortcuts=@($shortcuts);Processes=$processes} | ConvertTo-Json -Depth 5
