# The legacy server (ADR-0012): one Windows instance from the Packer image (ADR-0008), configured by a Systems Manager
# association that runs boot.ps1. Terraform waits for that script to succeed, so `terraform apply` finishing means the
# server answers on port 80. No public address, no RDP or WinRM: administration is through Systems Manager.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The newest image this project built (`make image` keeps only one).
data "aws_ami" "legacy" {
  owners      = ["self"]
  most_recent = true

  filter {
    name   = "tag:Project"
    values = [var.name]
  }

  filter {
    name   = "tag:Layer"
    values = ["image"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# CloudFront's origin-facing addresses: the only source the VPC origin (4.3) uses.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  api_key_parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.api_key_parameter}"

  boot_script = templatefile("${path.module}/boot.ps1.tftpl", {
    region            = var.region
    bucket            = var.artifact_bucket
    commit            = var.release_commit
    files_json        = jsonencode(var.release_files)
    api_key_parameter = var.api_key_parameter
    sql_max_memory_mb = var.sql_max_memory_mb
  })
}

# ---------------------------------------------------------------- network access

resource "aws_security_group" "legacy" {
  name        = "${var.name}-legacy"
  description = "Legacy server: HTTP from CloudFront only; HTTPS out to the VPC endpoints"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-legacy" }
}

resource "aws_vpc_security_group_ingress_rule" "http_from_cloudfront" {
  #checkov:skip=CKV_AWS_260:The source is CloudFront's managed prefix list, not 0.0.0.0/0; the check cannot see prefix lists
  security_group_id = aws_security_group.legacy.id
  description       = "HTTP from CloudFront's origin-facing servers (the VPC origin)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

resource "aws_vpc_security_group_egress_rule" "https_to_endpoints" {
  security_group_id = aws_security_group.legacy.id
  description       = "HTTPS to the interface endpoints (Systems Manager)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "https_to_s3" {
  security_group_id = aws_security_group.legacy.id
  description       = "HTTPS to S3 through the gateway endpoint (the release)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = var.s3_prefix_list_id
}

# ---------------------------------------------------------------- identity

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "legacy" {
  name                 = "${var.name}-legacy"
  description          = "Legacy server: Systems Manager, its release, and the API key parameter"
  assume_role_policy   = data.aws_iam_policy_document.assume_ec2.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.legacy.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "legacy" {
  statement {
    sid       = "ReadThisRelease"
    actions   = ["s3:GetObject"]
    resources = ["arn:${data.aws_partition.current.partition}:s3:::${var.artifact_bucket}/releases/${var.release_commit}/*"]
  }

  statement {
    sid       = "ReadTheApiKey"
    actions   = ["ssm:GetParameter"]
    resources = [local.api_key_parameter_arn]
  }

  # AmazonSSMManagedInstanceCore allows ssm:GetParameter(s) on every parameter, which would include the other
  # project's secrets in this account. An explicit deny overrides it for everything but the API key.
  statement {
    sid    = "NoOtherParameters"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
      "ssm:GetParameterHistory",
    ]
    not_resources = [local.api_key_parameter_arn]
  }
}

resource "aws_iam_role_policy" "legacy" {
  name   = "release-and-api-key"
  role   = aws_iam_role.legacy.id
  policy = data.aws_iam_policy_document.legacy.json
}

resource "aws_iam_instance_profile" "legacy" {
  name = "${var.name}-legacy"
  role = aws_iam_role.legacy.name
}

# ---------------------------------------------------------------- the server

resource "aws_instance" "legacy" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring costs extra; five-minute metrics are enough for a demo
  ami                         = data.aws_ami.legacy.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.legacy.id]
  iam_instance_profile        = aws_iam_instance_profile.legacy.name
  associate_public_ip_address = false
  ebs_optimized               = true
  monitoring                  = false

  # A new T3 in standard mode starts with no CPU credits and would boot at baseline speed. Unlimited bursts the boot
  # and repays it from credits earned while idle; any surplus costs cents (ADR-0008, correction in Phase 4.2).
  credit_specification {
    cpu_credits = "unlimited"
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name}-legacy-c" }
  }

  # D:, where the legacy configs put logs and exports. boot.ps1 formats it.
  ebs_block_device {
    device_name           = "xvdf"
    volume_size           = var.data_volume_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
    tags                  = { Name = "${var.name}-legacy-d" }
  }

  tags = { Name = "${var.name}-legacy" }

  # Systems Manager must be able to reach the instance before the association can run.
  depends_on = [aws_iam_role_policy_attachment.ssm_core, aws_iam_role_policy.legacy]
}

# ---------------------------------------------------------------- configuration: boot.ps1 through Systems Manager

resource "aws_ssm_document" "boot" {
  name            = "${var.name}-legacy-boot"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure the PurchaseDesk legacy server from release ${var.release_commit}"
    mainSteps = [{
      action = "aws:runPowerShellScript"
      name   = "boot"
      inputs = {
        timeoutSeconds = tostring(var.boot_timeout_seconds)
        runCommand     = [local.boot_script]
      }
    }]
  })
}

# Runs boot.ps1 once the instance is online, and again whenever the document changes (a new release). Terraform
# waits for success: a failed or slow boot fails the apply, and the script's output is kept by Systems Manager.
resource "aws_ssm_association" "boot" {
  name                             = aws_ssm_document.boot.name
  document_version                 = aws_ssm_document.boot.latest_version
  association_name                 = "${var.name}-legacy-boot"
  wait_for_success_timeout_seconds = var.boot_timeout_seconds

  targets {
    key    = "InstanceIds"
    values = [aws_instance.legacy.id]
  }
}
