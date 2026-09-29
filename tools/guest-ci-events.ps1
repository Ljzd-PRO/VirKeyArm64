$since=(Get-Date).AddMinutes(-30)
foreach($log in @('Microsoft-Windows-CodeIntegrity/Operational','Microsoft-Windows-AppLocker/EXE and DLL','System')) {
  "LOG $log"
  Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=$since} -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match 'VirKeyNode|no-import-arm64|hello-arm64|Code Integrity|image' } |
    Select-Object -First 20 TimeCreated,Id,ProviderName,Message | Format-List
}
