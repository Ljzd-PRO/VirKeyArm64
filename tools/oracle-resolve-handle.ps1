param([int]$PidToInspect=7080,[int]$HandleValue=0x54)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HandleName {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool DuplicateHandle(IntPtr source,IntPtr handle,IntPtr target,out IntPtr copy,uint access,bool inherit,uint options);
 [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
 [DllImport("ntdll.dll")] public static extern int NtQueryObject(IntPtr handle,int infoClass,IntPtr info,int length,out int returned);
}
'@
$source=[HandleName]::OpenProcess(0x40,$false,$PidToInspect)
if($source -eq [IntPtr]::Zero){throw "OpenProcess $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"}
$copy=[IntPtr]::Zero
try {
 if(-not [HandleName]::DuplicateHandle($source,[IntPtr]$HandleValue,[HandleName]::GetCurrentProcess(),[ref]$copy,0,$false,2)) { throw "DuplicateHandle $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
 $buffer=[Runtime.InteropServices.Marshal]::AllocHGlobal(65536)
 try {
  $used=0
  $status=[HandleName]::NtQueryObject($copy,1,$buffer,65536,[ref]$used)
  "NTSTATUS=0x$($status.ToString('X8')) Bytes=$used"
  if($status -eq 0){
   $length=[Runtime.InteropServices.Marshal]::ReadInt16($buffer,0)
   $ptr=[Runtime.InteropServices.Marshal]::ReadIntPtr($buffer,8)
   [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr,[int]($length/2))
  }
 } finally {[Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)}
} finally {if($copy -ne [IntPtr]::Zero){[void][HandleName]::CloseHandle($copy)}; [void][HandleName]::CloseHandle($source)}
