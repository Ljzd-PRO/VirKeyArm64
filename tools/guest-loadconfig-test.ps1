foreach($name in @('cookie','cf','eh','dyn','all-except-size')) {
  & "C:\Temp\VirKeyArm64\devgen-z-$name.exe" /? | Out-Null
  "$name exit=$LASTEXITCODE"
}
