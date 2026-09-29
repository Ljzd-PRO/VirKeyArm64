$ErrorActionPreference = 'Stop'
$product = 'C:\Program Files\SolidCAM2024\Solidcam'
$paths = @{
    Default = Join-Path $product 'solidcame.exe'
    Unmodified = Join-Path $product 'solidcame-no-laa-unmodified.exe'
    Readme = Join-Path $product 'SOLIDCAME-LAA-README.md'
}
$expected = @{
    Default = '86DD940519E96D5787282BCC38A56B8462D2F43602DB80A9B554F31C97F4C726'
    Unmodified = '26D72B6C13A5704BF49097EB534D3B86F93F931870744B195373F2B54395DC7B'
}
$files = foreach ($name in @('Default','Unmodified')) {
    $path = $paths[$name]
    if (!(Test-Path -LiteralPath $path)) { throw "$name launcher missing" }
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "$name is not MZ" }
    $pe = [BitConverter]::ToInt32($bytes,0x3c)
    if ([BitConverter]::ToUInt16($bytes,$pe+4) -ne 0x8664) { throw "$name is not AMD64" }
    $flags = [BitConverter]::ToUInt16($bytes,$pe+22)
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne $expected[$name]) { throw "$name hash mismatch" }
    $wantLaa = $name -eq 'Default'
    if (([bool]($flags -band 0x20)) -ne $wantLaa) { throw "$name LAA flag mismatch" }
    [pscustomobject]@{Role=$name;Path=$path;SHA256=$hash;Characteristics=('0x{0:X4}' -f $flags);LAA=$wantLaa;SignatureStatus=[string](Get-AuthenticodeSignature -LiteralPath $path).Status}
}
$source='\\Mac\Home\Documents\Codex\2026-09-29\w\work\virkey-arm64\docs\SOLIDCAME-LAA-README.md'
if ((Get-FileHash -LiteralPath $paths.Readme -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash) { throw 'Readme mismatch' }
$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @(
    'C:\Users\Public\Desktop\SolidCAM2024E.lnk',
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SolidCAM2024\SolidCAM2024E.lnk',
    (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'SolidCAM2024E 无修改版.lnk'),
    'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\SolidCAM2024\SolidCAM2024E 无修改版.lnk'
)
$shortcuts = foreach ($path in $shortcutPaths) {
    if (!(Test-Path -LiteralPath $path)) { throw "Shortcut missing: $path" }
    $link = $shell.CreateShortcut($path)
    $want = if ($path -like '*无修改版.lnk') { $paths.Unmodified } else { $paths.Default }
    if ($link.TargetPath -ne $want -or $link.Arguments -ne '' -or $link.WorkingDirectory.TrimEnd('\') -ne $product) { throw "Shortcut mismatch: $path" }
    [pscustomobject]@{Path=$path;Target=$link.TargetPath;WorkingDirectory=$link.WorkingDirectory;Arguments=$link.Arguments}
}
if (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'SolidCAM2024E ARM64 (LAA).lnk')) { throw 'Old LAA shortcut still present' }
[pscustomobject]@{Files=@($files);Shortcuts=@($shortcuts);Readme=$paths.Readme;ReadmeSHA256=(Get-FileHash -LiteralPath $paths.Readme -Algorithm SHA256).Hash} | ConvertTo-Json -Depth 6
