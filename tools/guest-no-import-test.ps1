$p=Start-Process 'C:\Temp\VirKeyArm64\no-import-arm64.exe' -PassThru
Start-Sleep -Seconds 1
$p.Refresh()
[pscustomobject]@{HasExited=$p.HasExited; ExitCode=$(if($p.HasExited){$p.ExitCode}else{$null})} | Format-List
if(-not $p.HasExited){Stop-Process -Id $p.Id -Force}
