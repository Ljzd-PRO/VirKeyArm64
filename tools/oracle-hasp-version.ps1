param([string]$InterfacePattern = '2&2b349487&0&00#')
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HaspVersionNative {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern SafeFileHandle CreateFile(string path, uint access, uint share,
      IntPtr security, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
      byte[] input, uint inputLength, byte[] output, uint outputLength,
      out uint returned, IntPtr overlapped);
}
'@
$root = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{7ab02247-3798-44cd-8472-243564975f04}'
$key = Get-ChildItem $root | Where-Object PSChildName -match $InterfacePattern | Select-Object -First 1
if (!$key) { throw 'SC HASP interface not present' }
$path = $key.PSChildName.Replace('##?#','\\?\')
Write-Output "INTERFACE $path"
$handle = [HaspVersionNative]::CreateFile($path, [uint32]3221225472, 3,
    [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
if ($handle.IsInvalid) { throw "Open failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
try {
  foreach ($input in @([byte[]](0,0,0,0,0,0), [byte[]](1,0,0,0,177,0))) {
    $output = [byte[]]::new(6)
    [uint32]$returned = 0
    $ok = [HaspVersionNative]::DeviceIoControl($handle, [uint32]2621449296,
        $input, [uint32]$input.Length, $output, [uint32]$output.Length,
        [ref]$returned, [IntPtr]::Zero)
    Write-Output ('input={0} ok={1} error={2} returned={3} output={4}' -f
        [BitConverter]::ToString($input), $ok,
        [Runtime.InteropServices.Marshal]::GetLastWin32Error(),
        $returned, [BitConverter]::ToString($output))
  }
} finally { $handle.Dispose() }
