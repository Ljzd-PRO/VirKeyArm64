$ErrorActionPreference='Stop'
$old='HKLM\SYSTEM\CurrentControlSet\MulttKey\Dumps\4C8F743C'
$new='HKLM\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps\4C8F743C'
$newPS='HKLM:\SYSTEM\CurrentControlSet\VirKeyArm64\Dumps\4C8F743C'
$service='HKLM:\SYSTEM\CurrentControlSet\Services\aksusb'
$root=(Get-PnpDevice | Where-Object FriendlyName -eq 'VirKeyArm64 Virtual USB Controller' | Select-Object -First 1).InstanceId
if (-not $root) { throw 'controller not found' }
if (Test-Path $newPS) { throw 'Existing new-path dump must be preserved; overlay test requires it absent' }
function Restart-And-Check($label, $serial, $fromNew) {
  & pnputil.exe /restart-device $root | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'restart failed' }
  Start-Sleep -Seconds 2
  $v=Get-ItemProperty $service
  if ($v.SelectedSerialNumber -ne $serial -or $v.SelectedFromNewRoot -ne $fromNew) { throw "Wrong selected dump at $label" }
  [pscustomobject]@{Stage=$label;SN=$v.SelectedSerialNumber;FromNew=$v.SelectedFromNewRoot;Name=[Text.Encoding]::Unicode.GetString($v.SelectedDumpName).TrimEnd([char]0)} | Format-List
}
$original=(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\MulttKey\Dumps\4C8F743C').SN
Restart-And-Check 'old only' $original 0
try {
  & reg.exe copy $old $new /s /f | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'copy failed' }
  & reg.exe add $new /v SN /t REG_DWORD /d 0x12345678 /f | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'override failed' }
  Restart-And-Check 'new overrides duplicate' 0x12345678 1
} finally {
  if (Test-Path $newPS) { Remove-Item $newPS -Recurse -Force }
  Restart-And-Check 'old restored' $original 0
}
