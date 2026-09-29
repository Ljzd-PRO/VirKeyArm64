Rename-Item 'C:\Temp\frida-server' 'frida-server.exe' -ErrorAction SilentlyContinue
$p=Start-Process -FilePath 'C:\Temp\frida-server.exe' -ArgumentList '-l 127.0.0.1:27042' -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2
$p.Refresh()
[pscustomobject]@{Id=$p.Id;HasExited=$p.HasExited;ExitCode=$(if($p.HasExited){$p.ExitCode}else{$null})}
