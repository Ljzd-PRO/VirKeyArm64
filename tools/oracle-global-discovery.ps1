param([Parameter(Mandatory=$true)][string]$InputHex)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class GlobalDiscoveryNative {
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
$inputBytes = [byte[]]::new([int]($InputHex.Length / 2))
for ($i=0; $i -lt $inputBytes.Length; ++$i) {
  $inputBytes[$i] = [Convert]::ToByte($InputHex.Substring($i*2, 2), 16)
}
if ($inputBytes.Length -ne 256) { throw "Expected 256 bytes; got $($inputBytes.Length)" }
foreach ($name in @('FEnteDev', 'USBPDCOM')) {
  $handle = [GlobalDiscoveryNative]::CreateFile('\\.\' + $name,
      [uint32]3221225472, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($handle.IsInvalid) {
    Write-Output "$name OPEN_ERROR $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    continue
  }
  try {
    $output = [byte[]]::new(256)
    [uint32]$returned = 0
    $ok = [GlobalDiscoveryNative]::DeviceIoControl($handle,
        [uint32]2621449304, $inputBytes, 256, $output, 256,
        [ref]$returned, [IntPtr]::Zero)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Write-Output ('{0} ok={1} error={2} returned={3}' -f $name, $ok, $errorCode, $returned)
    if ($ok) {
      Write-Output ('output=' + [BitConverter]::ToString($output).Replace('-',''))
      $differences = for ($i=0; $i -lt 256; ++$i) {
        if ($inputBytes[$i] -ne $output[$i]) {
          '{0}:{1:X2}>{2:X2}' -f $i,$inputBytes[$i],$output[$i]
        }
      }
      Write-Output ('diff=' + ($differences -join ','))
    }
  } finally { $handle.Dispose() }
}
