foreach($name in @('devgen-no-cfg-bit.exe','devgen-no-loadconfig.exe')) {
  & "C:\Temp\VirKeyArm64\$name" /? | Out-Null
  "$name exit=$LASTEXITCODE"
}
