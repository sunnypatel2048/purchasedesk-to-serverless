# Two persistent buckets: Terraform state for every layer, and the release artifacts the legacy server and the
# functions are deployed from. Both outlive every `make down`.
#
# Written out per bucket rather than with for_each: every resource stays visible to Checkov and to a reviewer
# (Checkov does not follow for_each connections reliably, and reported false failures).
#
# The state bucket is bootstrapped in two steps (README.md): created with local state, then the state is moved
# into it with `terraform init -migrate-state`.
locals {
  # Globally unique: include the account ID and region.
  state_bucket    = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
  artifact_bucket = "${var.project}-artifacts-${data.aws_caller_identity.current.account_id}-${var.region}"
}

# ================================================================ Terraform state

resource "aws_s3_bucket" "tfstate" {
  # Accepted for a single-user, single-region project; production alternatives in docs/security.md.
  #checkov:skip=CKV_AWS_145:SSE-S3 at no cost instead of a customer-managed KMS key
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; CloudTrail records configuration changes
  #checkov:skip=CKV_AWS_144:Versioning covers corruption and deletion; the project runs in one region
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to state writes
  bucket = local.state_bucket

  # The platform layer is destroyed often; this bucket never should be.
  lifecycle {
    prevent_destroy = true
  }
}

# Every state write keeps the previous version, so a bad state can be restored.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3: encrypted at rest at no cost. Production would use a customer-managed KMS key (about $1/month).
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No object ACLs: access is controlled only by IAM and the bucket policy.
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Keep 90 days of state history, not forever.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Lifecycle rules on noncurrent versions need versioning in place first.
  depends_on = [aws_s3_bucket_versioning.tfstate]
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  policy = data.aws_iam_policy_document.tls_only_tfstate.json

  # Avoid a race where the policy is applied before Block Public Access.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

# ================================================================ Release artifacts

resource "aws_s3_bucket" "artifacts" {
  #checkov:skip=CKV_AWS_145:SSE-S3 at no cost instead of a customer-managed KMS key
  #checkov:skip=CKV_AWS_18:Access logs need a second bucket; CloudTrail records configuration changes
  #checkov:skip=CKV_AWS_144:Versioning covers deletion; the project runs in one region
  #checkov:skip=CKV2_AWS_62:Nothing needs to react to uploads
  bucket = local.artifact_bucket

  # legacy-v1's release must stay deployable for the whole project.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  # Releases are keyed by commit and never overwritten in normal use; current versions never expire.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.tls_only_artifacts.json

  depends_on = [aws_s3_bucket_public_access_block.artifacts]
}

# ================================================================ Nothing travels unencrypted

data "aws_iam_policy_document" "tls_only_tfstate" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

data "aws_iam_policy_document" "tls_only_artifacts" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
