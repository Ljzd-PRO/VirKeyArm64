$ErrorActionPreference='Continue'
& manage-bde.exe -status C:
& bcdedit.exe /enum '{current}'
try { "SecureBootEnabled=$(Confirm-SecureBootUEFI)" } catch { "SecureBootQuery=$($_.Exception.Message)" }
"DumpOldPresent=$(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\MulttKey\Dumps\4C8F743C')"
"DumpNewPresent=$(Test-Path 'HKLM:\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps\4C8F743C')"
Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -like '*VirKeyArm64*' |
    Select-Object Subject,NotAfter | Format-List
