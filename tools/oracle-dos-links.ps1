Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class DosLinks {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint QueryDosDevice(string name, StringBuilder target, int maxChars);
}
'@
$names = New-Object System.Text.StringBuilder 262144
$count = [DosLinks]::QueryDosDevice($null, $names, $names.Capacity)
if ($count -eq 0) { throw "QueryDosDevice list: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
foreach ($name in $names.ToString().Split([char]0)) {
    if (!$name) { continue }
    $target = New-Object System.Text.StringBuilder 4096
    if ([DosLinks]::QueryDosDevice($name, $target, $target.Capacity) -eq 0) { continue }
    if ($target.ToString() -match '00000109|0000010a|FNT0|AKS|Sentinel|HASP') {
        [pscustomobject]@{Name=$name;Target=$target.ToString()}
    }
}
