$native = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DeviceNative {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern SafeFileHandle CreateFile(string path, uint access, uint share,
      IntPtr security, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool DeviceIoControl(SafeFileHandle handle, uint code,
      byte[] input, uint inputLength, byte[] output, uint outputLength,
      out uint returned, IntPtr overlapped);
  [DllImport("ntdll.dll")]
  public static extern int NtQueryObject(IntPtr handle, int infoClass,
      IntPtr info, int length, out int returned);
}
'@
Add-Type $native
$guids = @('{29db6d11-bc3c-11d7-b47f-00c0dfee4d8c}',
           '{bce9d0f1-f7db-11d7-b4bb-00c0dfee4d8c}')
foreach ($guid in $guids) {
  $root = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\' + $guid
  foreach ($key in Get-ChildItem $root) {
    if ($key.PSChildName -notmatch 'VID_0529.*&a&0[12]#') { continue }
    $path = $key.PSChildName.Replace('##?#','\\?\')
    Write-Output "INTERFACE $path"
    $handle = [DeviceNative]::CreateFile($path, [uint32]3221225472, 3,
                                        [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($handle.IsInvalid) {
      Write-Output "OPEN_ERROR $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
      continue
    }
    $nameBuffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(4096)
    try {
      [int]$nameBytes=0
      $nameStatus=[DeviceNative]::NtQueryObject($handle.DangerousGetHandle(),1,
                                                $nameBuffer,4096,[ref]$nameBytes)
      if($nameStatus -eq 0) {
        $chars=[Runtime.InteropServices.Marshal]::ReadInt16($nameBuffer,0)
        $ptr=[Runtime.InteropServices.Marshal]::ReadIntPtr($nameBuffer,8)
        if($ptr -ne [IntPtr]::Zero) {
          Write-Output "OBJECT $([Runtime.InteropServices.Marshal]::PtrToStringUni($ptr,[int]($chars/2)))"
        }
      }
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($nameBuffer) }
    foreach ($code in @([uint32]2621515264, [uint32]2621515328)) {
      $input = [byte[]]::new(16)
      $output = [byte[]]::new(16)
      [uint32]$returned = 0
      $ok = [DeviceNative]::DeviceIoControl($handle,[uint32]$code,$input,16,
                                           $output,16,[ref]$returned,[IntPtr]::Zero)
      $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      Write-Output ('CODE 0x{0:X8} ok={1} error={2} returned={3} output={4}' -f
                    $code,$ok,$errorCode,$returned,[BitConverter]::ToString($output))
    }
    $handle.Dispose()
  }
}
