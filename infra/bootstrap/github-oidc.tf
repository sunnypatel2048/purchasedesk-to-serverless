# GitHub Actions authenticates to AWS with short-lived OIDC credentials instead of stored access keys.
#
# The account's GitHub OIDC provider belongs to another project's bootstrap layer (vibesense-on-eks): an account
# can hold only one provider per URL. This layer reads it and never manages it. If that layer is ever destroyed,
# these roles stop working until the provider exists again (ADR-0007).
locals {
  github_oidc_host = "token.actions.githubusercontent.com"
  repo_owner       = split("/", var.github_repository)[0]
  repo_name        = split("/", var.github_repository)[1]
  # GitHub's subject claim: repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>. IDs cannot be reused, so a
  # look-alike repository created after a rename or deletion can never match.
  repo_sub_prefix = "repo:${local.repo_owner}@${var.github_owner_id}/${local.repo_name}@${var.github_repository_id}"
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.github_oidc_host}"
}

# Trust policy shared by both roles; `subjects` decides where a job may run. Exact matches only, no wildcards.
data "aws_iam_policy_document" "github_trust" {
  for_each = {
    push = ["${local.repo_sub_prefix}:ref:refs/heads/main"]
    plan = [
      "${local.repo_sub_prefix}:pull_request",        # terraform plan on pull requests
      "${local.repo_sub_prefix}:ref:refs/heads/main", # nightly leftovers check
    ]
  }

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = each.value
    }
  }
}

# ---------------------------------------------------------------- push role: merges to main publish releases

resource "aws_iam_role" "ci_push" {
  name                 = "${var.project}-ci-push"
  description          = "GitHub Actions on main: upload release artifacts."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["push"].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ci_push" {
  statement {
    sid       = "UploadReleases"
    actions   = ["s3:PutObject", "s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/releases/*"]
  }

  statement {
    sid       = "ListReleases"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.artifacts.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["releases/*"]
    }
  }
}

resource "aws_iam_role_policy" "ci_push" {
  name   = "upload-releases"
  role   = aws_iam_role.ci_push.id
  policy = data.aws_iam_policy_document.ci_push.json
}

# ---------------------------------------------------------------- plan role: read-only; no apply role exists

resource "aws_iam_role" "ci_plan" {
  name                 = "${var.project}-ci-plan"
  description          = "GitHub Actions on pull requests and nightly: read-only, for terraform plan and the leftovers check."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["plan"].json
  max_session_duration = 3600
}

# Broad read access: terraform plan refreshes every resource type it manages. Trade-off in docs/security.md.
resource "aws_iam_role_policy_attachment" "ci_plan_read_only" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Even `plan` takes the state lock, which writes and deletes a .tflock object.
data "aws_iam_policy_document" "ci_plan_state_lock" {
  statement {
    sid       = "TerraformStateLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "ci_plan_state_lock" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_plan_state_lock.json
}

# ReadOnlyAccess could otherwise read secrets: this project's, and those of every other project in the account.
# Terraform never manages secrets, so denying them breaks no plan. An explicit deny always overrides an allow.
data "aws_iam_policy_document" "ci_plan_deny" {
  statement {
    sid    = "DenySecretParameters"
    effect = "Deny"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParameterHistory", # returns earlier values too
    ]
    resources = [
      for prefix in concat([var.project], var.other_projects) :
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${prefix}/secrets/*"
    ]
  }

  # GetParametersByPath with recursion would read the secrets above; no plan here reads parameters by path.
  statement {
    sid       = "DenyReadByPath"
    effect    = "Deny"
    actions   = ["ssm:GetParametersByPath"]
    resources = ["*"]
  }

  # The RDS-managed Aurora master password, and any other Secrets Manager value.
  statement {
    sid       = "DenySecretValues"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["*"]
  }

  # Other projects' Terraform state: never this project's business.
  statement {
    sid       = "DenyOtherProjectsState"
    effect    = "Deny"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = [for prefix in var.other_projects : "arn:aws:s3:::${prefix}-tfstate-*/*"]
  }
}

resource "aws_iam_role_policy" "ci_plan_deny" {
  name   = "deny-secrets-and-other-projects"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_plan_deny.json
}
