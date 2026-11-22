# The image is only saved if all of these pass. One RESULT line per check; a failure fails the Packer build.
$ErrorActionPreference = "Stop"
$failures = 0

function Check([string]$Name, [bool]$Pass, [string]$Actual) {
    $status = if ($Pass) { "PASS" } else { "FAIL" }
    Write-Host "RESULT $Name actual=$Actual status=$status"
    if (-not $Pass) { $script:failures++ }
}

# ---------------------------------------------------------------- SQL Server
Start-Service -Name SQLSERVERAGENT

$connection = New-Object System.Data.SqlClient.SqlConnection "Server=localhost;Database=master;Integrated Security=true;Connect Timeout=60"
$connection.Open()
$command = $connection.CreateCommand()
$command.CommandText = @"
SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(32)),
       CAST(SERVERPROPERTY('Edition') AS nvarchar(64)),
       @@SERVERNAME,
       CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int)
"@
$reader = $command.ExecuteReader()
$null = $reader.Read()
$version = $reader.GetString(0)
$edition = $reader.GetString(1)
$serverName = $reader.GetString(2)
$windowsAuthOnly = $reader.GetInt32(3)
$reader.Close()
$connection.Close()

Check "sql-version" ($version -eq $env:EXPECTED_SQL_BUILD) $version
Check "sql-edition-developer" ($edition -like "Developer Edition*") $edition
# Replication (and so DMS) needs @@SERVERNAME to match the machine name; this is why the image is not sysprepped.
Check "sql-servername-matches-host" ($serverName -eq $env:COMPUTERNAME) "$serverName/$env:COMPUTERNAME"
Check "sql-windows-auth-only" ($windowsAuthOnly -eq 1) $windowsAuthOnly

# The replication feature installs the Log Reader and Distribution agents.
$com = "C:\Program Files\Microsoft SQL Server\150\COM"
Check "sql-replication-installed" ((Test-Path "$com\logread.exe") -and (Test-Path "$com\distrib.exe")) "logread.exe,distrib.exe"

$agent = Get-Service -Name SQLSERVERAGENT
Check "sql-agent-automatic-and-running" (($agent.StartType -eq "Automatic") -and ($agent.Status -eq "Running")) "$($agent.StartType)/$($agent.Status)"

# ---------------------------------------------------------------- IIS and ASP.NET
$w3svc = Get-Service -Name W3SVC
Check "iis-running" ($w3svc.Status -eq "Running") $w3svc.Status

$aspnet = Get-WindowsFeature -Name Web-Asp-Net45
Check "aspnet-4.8-registered-with-iis" $aspnet.Installed $aspnet.InstallState

# .NET Framework 4.8 is release 528040 or later.
$release = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full").Release
Check "dotnet-framework-4.8" ($release -ge 528040) $release

# ---------------------------------------------------------------- Systems Manager
$ssm = Get-Service -Name AmazonSSMAgent
Check "ssm-agent-running" ($ssm.Status -eq "Running") $ssm.Status

Write-Host "RESULT image-verify failed=$failures"
if ($failures -gt 0) {
    exit 1
}
