# IIS for the legacy Web API 2 application. .NET Framework 4.8 is part of Windows Server 2022; this registers ASP.NET
# 4.8 with IIS (Web-Asp-Net45) and adds the logging the legacy app's operators would expect.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$features = @(
    "Web-Server",
    "Web-Asp-Net45",
    "Web-Net-Ext45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Http-Logging",
    "Web-Request-Monitor",
    "Web-Filtering"
)

$result = Install-WindowsFeature -Name $features
if (-not $result.Success) {
    throw "IIS feature installation failed: $($result.ExitCode)"
}
Write-Host "Installed: $($features -join ', ')"
