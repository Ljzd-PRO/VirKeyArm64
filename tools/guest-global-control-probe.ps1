$ErrorActionPreference = 'Stop'
$native = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class VirKeyGlobalNative {
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
Add-Type $native
foreach ($name in @('FEnteDev', 'USBPDCOM')) {
  $path = '\\.\' + $name
  $handle = [VirKeyGlobalNative]::CreateFile($path, [uint32]3221225472, 3,
      [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($handle.IsInvalid) {
    Write-Output "$name OPEN_ERROR $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    continue
  }
  foreach ($code in @([uint32]2621515264, [uint32]2621449296, [uint32]2621449384)) {
    $length = switch ($code) { 2621515264 {16} 2621449296 {6} 2621449384 {8192} }
    $input = [byte[]]::new($length)
    $output = [byte[]]::new(64)
    [uint32]$returned = 0
    $ok = [VirKeyGlobalNative]::DeviceIoControl($handle, $code, $input, [uint32]$input.Length,
        $output, [uint32]$output.Length, [ref]$returned, [IntPtr]::Zero)
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    $data = if ($returned -gt 0) { [BitConverter]::ToString($output, 0, [int]$returned) } else { '' }
    Write-Output ('{0} CODE 0x{1:X8} ok={2} error={3} returned={4} data={5}' -f
        $name, $code, $ok, $errorCode, $returned, $data)
  }
  $handle.Dispose()
}
