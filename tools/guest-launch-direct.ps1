Get-Process solidcame,solidcam -ErrorAction SilentlyContinue | Stop-Process -Force
$p=Start-Process -FilePath 'C:\Program Files\SolidCAM2024\Solidcam\Solidcam.exe' -PassThru
Start-Sleep -Seconds 5
$p.Refresh()
[pscustomobject]@{Id=$p.Id;HasExited=$p.HasExited;ExitCode=$(if($p.HasExited){$p.ExitCode}else{$null})} | Format-List
Get-Process solidcam,sldworks -ErrorAction SilentlyContinue | Select-Object Name,Id,Path
