$exe='C:\Temp\VirKeyArm64\VirKeyNode.exe'
& $exe create
"first create exit=$LASTEXITCODE"
& $exe remove
"remove exit=$LASTEXITCODE"
& $exe create
"second create exit=$LASTEXITCODE"
