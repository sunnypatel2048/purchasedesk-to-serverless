# Packages the legacy release: the IIS site, the nightly export program and the database scripts, plus a manifest
# with each zip's SHA-256 and the result of a vulnerability scan (ADR-0010).
#
#   ./scripts/package-legacy.ps1 -Commit <sha>                 (Windows with Visual Studio Build Tools; CI: release.yml)
#   ./scripts/package-legacy.ps1 -Commit <sha> -OutDir <dir>
#
# Writes legacy-web.zip, legacy-export.zip, legacy-database.zip and manifest.json to -OutDir. Uploading is not done
# here: release.yml uploads to the artifact bucket, so this script never needs AWS credentials.
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$OutDir = 'artifacts/release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$legacy = Join-Path $root 'legacy'
$out = [System.IO.Path]::GetFullPath((Join-Path $root $OutDir))
$staging = Join-Path $out 'staging'

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $staging | Out-Null

function Invoke-Checked([string]$what, [scriptblock]$command) {
    & $command
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)" }
}

# ------------------------------------------------------------------ toolchain: Visual Studio's msbuild.exe
# The .NET SDK's msbuild compiles the web project but cannot produce the IIS layout (legacy/Directory.Build.props).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw "MSBuild.exe not found (Visual Studio or Build Tools with the MSBuild component)" }
Write-Host "MSBuild: $msbuild"

# ------------------------------------------------------------------ vulnerability scan (before anything is built)
# Only the shipped projects; the test project never leaves CI. High or Critical fails the release.
$findings = @()
# A project with no findings has no "frameworks" (or no "vulnerabilities") in the JSON, so every level is optional.
function Get-JsonList($object, [string]$name) {
    $property = $object.PSObject.Properties[$name]
    if ($property -and $null -ne $property.Value) { return @($property.Value) }
    return @()
}

foreach ($project in 'PurchaseDesk.Web/PurchaseDesk.Web.csproj', 'PurchaseDesk.Export/PurchaseDesk.Export.csproj') {
    $path = Join-Path $legacy $project
    Invoke-Checked "Restore of $project" { dotnet restore $path --verbosity quiet }
    $json = dotnet list $path package --vulnerable --include-transitive --format json
    if ($LASTEXITCODE -ne 0) { throw "Vulnerability scan of $project failed (exit $LASTEXITCODE)" }
    $report = $json | Out-String | ConvertFrom-Json
    foreach ($p in Get-JsonList $report 'projects') {
        foreach ($fw in Get-JsonList $p 'frameworks') {
            foreach ($kind in 'topLevelPackages', 'transitivePackages') {
                foreach ($pkg in Get-JsonList $fw $kind) {
                    foreach ($v in Get-JsonList $pkg 'vulnerabilities') {
                        $findings += [ordered]@{
                            project  = $project
                            package  = $pkg.id
                            version  = $pkg.resolvedVersion
                            severity = $v.severity
                            advisory = $v.advisoryurl
                        }
                    }
                }
            }
        }
    }
}
$blocking = @($findings | Where-Object { $_.severity -in 'High', 'Critical' })
Write-Host "RESULT vulnerability-scan findings=$($findings.Count) high_or_critical=$($blocking.Count)"
$findings | ForEach-Object { Write-Host "  $($_.severity) $($_.package) $($_.version) ($($_.project)) $($_.advisory)" }
if ($blocking.Count -gt 0) { throw "High or Critical vulnerabilities in shipped packages; no release" }

# ------------------------------------------------------------------ web: the IIS site folder
$web = Join-Path $staging 'web'
Invoke-Checked 'Web publish' {
    & $msbuild (Join-Path $legacy 'PurchaseDesk.Web/PurchaseDesk.Web.csproj') /restore /nologo /v:minimal `
        /p:Configuration=Release /p:DeployOnBuild=true /p:WebPublishMethod=FileSystem `
        /p:PublishUrl="$web" /p:DeleteExistingFiles=true
}

# The layout IIS needs, and nothing that should not ship.
foreach ($required in 'Web.config', 'Global.asax', 'bin/PurchaseDesk.Web.dll', 'bin/System.Web.Http.dll',
    'bin/System.Web.Http.WebHost.dll', 'bin/Newtonsoft.Json.dll') {
    if (-not (Test-Path (Join-Path $web $required))) { throw "Web package is missing $required" }
}
$unexpected = @(Get-ChildItem $web -Recurse -File | Where-Object { $_.Extension -in '.cs', '.csproj' -or $_.FullName -match '[\\/]obj[\\/]' })
if ($unexpected.Count -gt 0) { throw "Web package contains source or build files: $($unexpected.FullName -join ', ')" }

# ------------------------------------------------------------------ export: the nightly console program
$exportProject = Join-Path $legacy 'PurchaseDesk.Export/PurchaseDesk.Export.csproj'
Invoke-Checked 'Export build' { & $msbuild $exportProject /restore /nologo /v:minimal /p:Configuration=Release }
$exportBin = Join-Path $legacy 'PurchaseDesk.Export/bin/Release/net48'
foreach ($required in 'PurchaseDesk.Export.exe', 'PurchaseDesk.Export.exe.config') {
    if (-not (Test-Path (Join-Path $exportBin $required))) { throw "Export build is missing $required" }
}
$export = Join-Path $staging 'export'
Copy-Item $exportBin $export -Recurse

# ------------------------------------------------------------------ database: exactly what load.ps1 loads
$dbSource = Join-Path $legacy 'database'
$database = Join-Path $staging 'database'
$scripts = @(Get-Content (Join-Path $dbSource 'load-order.txt') | Where-Object { $_.Trim() -and -not $_.StartsWith('#') })
foreach ($file in @('load-order.txt', 'load.ps1', 'seed-expected.txt', 'checks/seed-facts.sql') + $scripts) {
    $source = Join-Path $dbSource $file
    if (-not (Test-Path $source)) { throw "Database package: $file not found" }
    $target = Join-Path $database $file
    New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
    Copy-Item $source $target
}

# ------------------------------------------------------------------ zips and manifest
$files = [ordered]@{}
foreach ($part in 'web', 'export', 'database') {
    $zip = Join-Path $out "legacy-$part.zip"
    Compress-Archive -Path (Join-Path $staging "$part/*") -DestinationPath $zip
    $item = Get-Item $zip
    $files[$item.Name] = [ordered]@{
        sha256 = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes  = $item.Length
    }
    Write-Host "RESULT package $($item.Name) bytes=$($item.Length) sha256=$($files[$item.Name].sha256)"
}
Remove-Item $staging -Recurse -Force

$run = if ($env:GITHUB_RUN_ID) { "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID" } else { $null }
$manifest = [ordered]@{
    commit             = $Commit
    created            = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    workflow_run       = $run
    files              = $files
    vulnerability_scan = [ordered]@{
        tool             = 'dotnet list package --vulnerable --include-transitive'
        high_or_critical = $blocking.Count
        findings         = $findings
    }
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out 'manifest.json') -Encoding utf8NoBOM
Write-Host "RESULT release-package commit=$Commit dir=$out"
