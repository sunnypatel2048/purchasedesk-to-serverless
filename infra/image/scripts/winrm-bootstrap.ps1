<powershell>
# Packer build only: a WinRM HTTPS listener with a self-signed certificate, so Packer can reach the build instance.
# Packer's temporary security group limits port 5986 to the machine running the build. cleanup.ps1 arranges for the
# listener, certificate and firewall rule to be removed when an instance is first started from the image.
$ErrorActionPreference = "Stop"

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

$cert = New-SelfSignedCertificate -CertStoreLocation "Cert:\LocalMachine\My" -DnsName "packer-build" -FriendlyName "packer-build"

Get-ChildItem -Path WSMan:\localhost\Listener | Remove-Item -Recurse -Force
New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null

Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 1800000

New-NetFirewallRule -Name "packer-winrm-https" -DisplayName "Packer WinRM HTTPS (build only)" `
    -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow | Out-Null

Restart-Service -Name WinRM
</powershell>
