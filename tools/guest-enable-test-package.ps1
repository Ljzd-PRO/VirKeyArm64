$ErrorActionPreference='Stop'
$cert=(Join-Path (Split-Path $PSScriptRoot -Parent) 'package\VirKeyArm64-Test.cer')
if (!(Test-Path $cert)) { throw 'Mac-generated public test certificate not found' }
& bcdedit.exe /set '{current}' testsigning on
if ($LASTEXITCODE -ne 0) { throw 'Unable to enable test signing' }
$root=Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\Root
$publisher=Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
[pscustomobject]@{RootThumbprint=$root.Thumbprint;PublisherThumbprint=$publisher.Thumbprint} | Format-List
& bcdedit.exe /enum '{current}'
