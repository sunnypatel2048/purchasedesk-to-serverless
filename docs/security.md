# Security notes

What protects what, the trade-offs accepted for a single-user demo project, and what production would do
instead. Each later phase adds to this file.

## Accounts and CI

- **No long-lived AWS keys.** GitHub Actions uses OIDC: two roles, each trusting only this repository's exact
  subject, including the owner's and repository's numeric IDs. Fork pull requests cannot obtain credentials.
- **No apply role.** CI can plan and upload releases; only a person applies infrastructure.
- **The plan role has `ReadOnlyAccess`**, because `terraform plan` refreshes every resource type it manages. Explicit
  denies stop it reading secrets in Parameter Store (this project's and the other project's in the account), any
  Secrets Manager value, and the other project's Terraform state.
  Production would scope the read permissions to the resource types actually managed.
- **The push role** can only write and read under `releases/` in the artifact bucket.
- **The GitHub OIDC provider is shared** with another project in the same AWS account, which owns it. This project
  only reads it.
- **Branch ruleset** (`.github/rulesets/main.json`, `make ruleset`): every change reaches `main` through a pull request;
  "infra passed", "legacy passed" and "legacy/ and golden/ are frozen" must succeed, reported by GitHub Actions itself;
  no force pushes or deletion of `main`; no bypass.
- **Workflows**: every action pinned to a commit SHA and kept current by Dependabot; least-privilege `permissions`
  per job; `pull_request`, never `pull_request_target`; fork and Dependabot pull requests are validated and linted but
  never get AWS credentials. Plan comments list resource addresses and actions only, never values.
- **Nightly leftovers check**: anything tagged `Project=purchasedesk` outside the bootstrap layer fails the run, using
  the read-only role.

## Buckets

- State and artifact buckets: SSE-S3 encryption, versioning with 90 days of history, Block Public Access, object
  ACLs disabled, TLS-only bucket policies, `prevent_destroy`.
- Accepted: no customer-managed KMS key (about $1/month each) and no access-log bucket. CloudTrail records
  configuration changes. Production would add both.

## Known limitations

- The alerts SNS topic is not KMS-encrypted: CloudWatch alarms cannot publish to a topic using the AWS-managed
  `aws/sns` key. Alarm messages contain nothing sensitive.
- The legacy app's shared API key and secrets in `Web.config` are legacy traits by design; committed values are
  placeholders only. They are retired by the migration.
