# Last step before the image is saved.
$ErrorActionPreference = "Stop"

# 1. The installers: about 2 GB that would otherwise be stored in every snapshot.
Remove-Item -Path "C:\sqlinstall" -Recurse -Force

# 2. Packer's WinRM listener is only for the build. Removing it now would cut Packer's own connection, so a one-shot
#    task removes the listener, its certificate and its firewall rule when an instance is first started from the
#    image, then deletes itself. Instances are administered through Systems Manager, never WinRM or RDP.
$folder = "C:\ProgramData\purchasedesk"
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$script = Join-Path $folder "remove-packer-winrm.ps1"

Set-Content -Path $script -Encoding UTF8 -Value @'
Get-ChildItem -Path WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTPS" } | Remove-Item -Recurse -Force
Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.FriendlyName -eq "packer-build" } | Remove-Item -Force
Remove-NetFirewallRule -Name "packer-winrm-https" -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "purchasedesk-remove-packer-winrm" -Confirm:$false
Remove-Item -Path $PSCommandPath -Force
'@

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "purchasedesk-remove-packer-winrm" -Action $action -Trigger $trigger `
    -User "SYSTEM" -RunLevel Highest -Force | Out-Null

Write-Host "Removed the installers; registered the first-boot WinRM clean-up task."
