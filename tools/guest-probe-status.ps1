$p = Get-PnpDevice -InstanceId 'ROOT\DEVGEN\{286AF392-9EBC-5B4C-B92B-EA1B2ABA5B53}' -ErrorAction SilentlyContinue
if ($p) {
  $p | Select-Object InstanceId, Status, Problem, DriverVersion | Format-List
  Get-PnpDeviceProperty -InstanceId $p.InstanceId -KeyName 'DEVPKEY_Device_ProblemStatus','DEVPKEY_Device_DriverInfPath' -ErrorAction SilentlyContinue |
    Select-Object KeyName, Data | Format-List
}
Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\VirKeyArm64' -ErrorAction SilentlyContinue |
  Select-Object ImagePath, BindProbeEntered, BindProbeStatus, DiagnosticStage, DiagnosticStatus | Format-List
