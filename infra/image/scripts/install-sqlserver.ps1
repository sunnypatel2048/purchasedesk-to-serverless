# SQL Server 2019 Developer: the database engine and replication (needed by AWS DMS in Phase 5), SQL Server Agent
# starting automatically, TCP enabled. The CU32 GDR security update is applied in the same setup run.
#
# Windows authentication only: no password is baked into the image. SQL logins are created at boot, from Parameter
# Store (Phase 4).
#
# Supply chain: both installers must carry a valid Microsoft Authenticode signature, and the update must also match
# the SHA-256 published on Microsoft's KB page. Any mismatch stops the build.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue" # the progress bar makes Invoke-WebRequest very slow

$work = "C:\sqlinstall"
$media = Join-Path $work "media"
$setupDir = Join-Path $work "setup"
$updates = Join-Path $work "updates"
New-Item -ItemType Directory -Force -Path $media, $setupDir, $updates | Out-Null

function Assert-MicrosoftSigned([string]$Path) {
    $sig = Get-AuthenticodeSignature -FilePath $Path
    if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch "O=Microsoft Corporation") {
        throw "$Path is not validly signed by Microsoft (status $($sig.Status), signer $($sig.SignerCertificate.Subject))"
    }
    Write-Host "Signature OK: $(Split-Path $Path -Leaf)"
}

function Invoke-Checked([string]$File, [string[]]$Arguments, [int[]]$Ok = @(0)) {
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($Ok -notcontains $p.ExitCode) {
        throw "$(Split-Path $File -Leaf) exited with $($p.ExitCode)"
    }
    return $p.ExitCode
}

# 1. Microsoft's SQL Server 2019 Developer installer, which then downloads the full media.
$ssei = Join-Path $work "SQL2019-SSEI-Dev.exe"
Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=866662" -OutFile $ssei -UseBasicParsing
Assert-MicrosoftSigned $ssei
Invoke-Checked $ssei @("/ACTION=Download", "/MEDIAPATH=$media", "/MEDIATYPE=CAB", "/QUIET") | Out-Null

$package = Get-ChildItem -Path $media -Filter "SQLServer2019-DEV-x64-*.exe" | Select-Object -First 1
if (-not $package) {
    throw "The Developer media did not download to $media"
}
Assert-MicrosoftSigned $package.FullName
Invoke-Checked $package.FullName @("/Q", "/X:$setupDir") | Out-Null

# 2. The CU32 GDR security update (KB5132745).
$update = Join-Path $updates "SQLServer2019-KB5132745-x64.exe"
Invoke-WebRequest -Uri $env:SQL_UPDATE_URL -OutFile $update -UseBasicParsing
$hash = (Get-FileHash -Path $update -Algorithm SHA256).Hash
if ($hash -ne $env:SQL_UPDATE_SHA256.ToUpperInvariant()) {
    throw "Update SHA-256 $hash does not match Microsoft's published $($env:SQL_UPDATE_SHA256)"
}
Write-Host "Hash OK: SHA-256 $hash"
Assert-MicrosoftSigned $update

# 3. Setup, applying the update from UpdateSource in the same run.
$arguments = @(
    "/Q",
    "/ACTION=Install",
    "/IACCEPTSQLSERVERLICENSETERMS",
    "/FEATURES=SQLENGINE,REPLICATION",
    "/INSTANCENAME=MSSQLSERVER",
    "/SQLSYSADMINACCOUNTS=BUILTIN\Administrators",
    "/SQLSVCSTARTUPTYPE=Automatic",
    "/AGTSVCSTARTUPTYPE=Automatic",
    "/TCPENABLED=1",
    "/UPDATEENABLED=True",
    "/UPDATESOURCE=$updates",
    "/INDICATEPROGRESS=False"
)

try {
    $code = Invoke-Checked (Join-Path $setupDir "setup.exe") $arguments @(0, 3010)
    Write-Host "SQL Server setup finished (exit $code; 3010 means a restart is needed, which comes next)"
}
catch {
    # Setup's own summary says why; show it in the build log before failing.
    $summary = "C:\Program Files\Microsoft SQL Server\150\Setup Bootstrap\Log\Summary.txt"
    if (Test-Path $summary) {
        Get-Content $summary | Select-Object -First 80 | Write-Host
    }
    throw
}
