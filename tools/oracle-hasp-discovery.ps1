param([string]$InterfacePattern = '2&2b349487&0&00#')
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HaspDiscoveryNative {
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
for ($attempt = 1; $attempt -le 3; ++$attempt) {
  $handle = [HaspDiscoveryNative]::CreateFile($path, [uint32]3221225472, 3,
      [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($handle.IsInvalid) { throw "Open failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  try {
    $input = [byte[]]::new(256)
    foreach ($entry in @(@(0,3), @(1,0x58), @(6,4), @(8,0x8f), @(9,0x4c),
                        @(12,0x3c), @(13,0x74), @(28,1), @(76,1))) {
      $input[$entry[0]] = [byte]$entry[1]
    }
    $output = [byte[]]::new(256)
    [uint32]$returned = 0
    $ok = [HaspDiscoveryNative]::DeviceIoControl($handle, [uint32]2621449304,
        $input, 256, $output, 256, [ref]$returned, [IntPtr]::Zero)
    Write-Output ('attempt={0} ok={1} error={2} returned={3} status={4} token={5} cookie={6}' -f
        $attempt,$ok,[Runtime.InteropServices.Marshal]::GetLastWin32Error(),
        $returned,[BitConverter]::ToString($output,26,1),
        [BitConverter]::ToString($output,70,4),
        [BitConverter]::ToString($output,104,4))
    if ($ok) {
      $differences = for ($i=0; $i -lt 256; ++$i) {
        if ($input[$i] -ne $output[$i]) {
          '{0}:{1:X2}>{2:X2}' -f $i,$input[$i],$output[$i]
        }
      }
      Write-Output ('diff=' + ($differences -join ','))
    }
  } finally { $handle.Dispose() }
}
