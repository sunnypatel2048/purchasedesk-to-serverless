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
- **The push role** can only write and read under `releases/` in the artifact bucket, and only jobs on `main` can
  assume it.
- **Releases** (`release.yml`, ADR-0010) are immutable: every object is created with a conditional put, so a
  published release is never overwritten. Each zip's SHA-256 is in the release manifest and checked before upload
  and before use. Shipped packages are scanned for known vulnerabilities; High or Critical stops the release.
  Packages are not signed; production would add signed build provenance.
- **The GitHub OIDC provider is shared** with another project in the same AWS account, which owns it. This project
  only reads it.
- **Branch ruleset** (`.github/rulesets/main.json`, `make ruleset`): every change reaches `main` through a pull request;
  "infra passed", "legacy passed" and "legacy/ and golden/ are frozen" must succeed, reported by GitHub Actions itself;
  no force pushes or deletion of `main`; no bypass.
- **Workflows**: every action pinned to a commit SHA and kept current by Dependabot; least-privilege `permissions`
  per job; `pull_request`, never `pull_request_target`; fork and Dependabot pull requests are validated and linted but
  never get AWS credentials. Plan comments list resource addresses and actions only, never values.
- **Nightly leftovers check**: anything tagged `Project=purchasedesk` outside the bootstrap and image layers fails the
  run, using the read-only role.

## Buckets

- State and artifact buckets: SSE-S3 encryption, versioning with 90 days of history, Block Public Access, object
  ACLs disabled, TLS-only bucket policies, `prevent_destroy`.
- Accepted: no customer-managed KMS key (about $1/month each) and no access-log bucket. CloudTrail records
  configuration changes. Production would add both.

## Network

- No public subnets and no NAT gateway (ADR-0011): nothing in the VPC has an internet address or a route to the
  internet. The internet gateway exists only because CloudFront VPC origins require one; no route uses it.
- AWS services are reached through endpoints: S3 and DynamoDB gateway endpoints, and `ssm` and `ssmmessages`
  interface endpoints that admit HTTPS from the VPC only. The VPC's default security group has no rules.
- Accepted: no VPC flow logs, the default S3 endpoint policy, and interface endpoints in one zone. Production would
  turn on flow logs, scope the endpoint policies and use both zones.

## Legacy server

- Private subnet, no public address, no key pair, IMDSv2 only, encrypted disks. No RDP or WinRM: the build's WinRM
  listener is removed on first start, and administration is through Systems Manager.
- Its security group admits HTTP only from CloudFront's origin-facing prefix list, and allows HTTPS out only to the
  VPC (the endpoints) and the S3 prefix list.
- Its role can read only its own release and the API key parameter. An explicit deny stops the AWS-managed
  `AmazonSSMManagedInstanceCore` policy reading any other parameter, including another project's secrets.
- SQL logins for the IIS app pool and the export task (Network Service) have EXECUTE on the procedures only; neither
  is a sysadmin. SQL Server accepts Windows authentication only.
- Application secrets come from `make secrets`: SecureString parameters, created once, never in Terraform or its
  state, never printed. The other project's CI plan role should deny `/purchasedesk/secrets/*` as this project's
  denies its secrets (a change in that repository).

## Known limitations

- The alerts SNS topic is not KMS-encrypted: CloudWatch alarms cannot publish to a topic using the AWS-managed
  `aws/sns` key. Alarm messages contain nothing sensitive.
- The legacy app's shared API key and secrets in `Web.config` are legacy traits by design; committed values are
  placeholders only. They are retired by the migration.
