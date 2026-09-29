param([ValidateSet('aksusb','akshasp')][string]$ServiceName = 'akshasp')
$ErrorActionPreference = 'Stop'
$path = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
$key = Get-Item $path
foreach ($name in $key.GetValueNames()) {
    if ($name -like 'Observed*' -or $name -eq 'UnsupportedChallengeCount') {
        Remove-ItemProperty -Path $path -Name $name
    }
}
