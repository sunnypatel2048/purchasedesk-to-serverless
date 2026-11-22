# The legacy server's image (ADR-0008): Windows Server 2022, IIS with ASP.NET 4.8, SQL Server 2019 Developer at the
# newest CU32 security build, the Systems Manager agent. Built rarely, by `make image`, from a person's machine;
# CI only checks the template. The image is persistent (Layer=image); everything else the build creates is not.

packer {
  required_version = ">= 1.16.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.4"
    }
  }
}

locals {
  timestamp = formatdate("YYYYMMDD-hhmm", timestamp())
  tags = {
    Project        = "purchasedesk"
    ManagedBy      = "packer"
    SqlServerBuild = var.sql_build
    GitCommit      = var.git_commit
  }
}

source "amazon-ebs" "legacy" {
  region        = var.region
  instance_type = var.instance_type

  ami_name        = "purchasedesk-legacy-${local.timestamp}"
  ami_description = "PurchaseDesk legacy server: Windows Server 2022, IIS, SQL Server 2019 Developer ${var.sql_build}"

  # AWS's own Windows Server 2022 image, patched monthly by AWS: no slow Windows Update run here.
  source_ami_filter {
    filters = {
      name                = "Windows_Server-2022-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  # WinRM over HTTPS, with a self-signed certificate made by the user data script. Packer's temporary security group
  # admits port 5986 from this machine's public IP only, and is deleted with the build instance. The certificate is not
  # verified (winrm_insecure): the connection is short-lived and limited to one address.
  communicator                              = "winrm"
  winrm_username                            = "Administrator"
  winrm_use_ssl                             = true
  winrm_insecure                            = true
  winrm_timeout                             = "20m"
  user_data_file                            = "${path.root}/scripts/winrm-bootstrap.ps1"
  associate_public_ip_address               = true
  temporary_security_group_source_public_ip = true

  # Instances launched from the image must use IMDSv2.
  imds_support = "v2.0"
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 40
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # The build instance: Layer=image-build, so a crashed build is caught by the leftovers check.
  run_tags        = merge(local.tags, { Name = "purchasedesk-image-build", Layer = "image-build" })
  run_volume_tags = merge(local.tags, { Name = "purchasedesk-image-build", Layer = "image-build" })

  # The image and its snapshot: persistent.
  tags          = merge(local.tags, { Name = "purchasedesk-legacy-${local.timestamp}", Layer = "image", BaseAmi = "{{ .SourceAMIName }}" })
  snapshot_tags = merge(local.tags, { Name = "purchasedesk-legacy-${local.timestamp}", Layer = "image" })
}

build {
  sources = ["source.amazon-ebs.legacy"]

  provisioner "powershell" {
    script = "${path.root}/scripts/install-iis.ps1"
  }

  # SQL Server setup misbehaves in a plain WinRM session; elevated runs it as a scheduled task with full rights.
  provisioner "powershell" {
    script            = "${path.root}/scripts/install-sqlserver.ps1"
    elevated_user     = "Administrator"
    elevated_password = build.Password
    environment_vars = [
      "SQL_UPDATE_URL=${var.sql_update_url}",
      "SQL_UPDATE_SHA256=${var.sql_update_sha256}",
    ]
  }

  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # The image is only saved if every check passes.
  provisioner "powershell" {
    script           = "${path.root}/scripts/verify.ps1"
    environment_vars = ["EXPECTED_SQL_BUILD=${var.sql_build}"]
  }

  provisioner "powershell" {
    script = "${path.root}/scripts/cleanup.ps1"
  }

  post-processor "manifest" {
    output     = "${path.root}/packer-manifest.json"
    strip_path = true
  }
}
