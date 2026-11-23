# ADR-0012: The legacy server is configured by a Systems Manager association

**Status:** Accepted (Phase 4.2)

## Context

Each session launches the legacy server from the Packer image (ADR-0008), which holds Windows, IIS and SQL Server
but no application. Something must fetch the release (ADR-0010), load the database, configure IIS and the nightly
export, and tell `make up` when the server is ready.

The usual mechanism is user data, run by EC2Launch v2 on first boot. EC2Launch records what it has already run, and
that record was saved into the image during the Packer build; the image skips sysprep (ADR-0008), so user data on a
new instance might never run. User data also leaves no easy way to see the script's output or to wait for it.

## Decision

- Terraform creates an **SSM Command document** holding `infra/modules/legacy/boot.ps1.tftpl`, rendered with the
  release commit, the zips' SHA-256 (read by Terraform from the release manifest), the bucket and the API key
  parameter's name, and an **association** that runs it on the instance once Systems Manager can reach it.
- Terraform **waits for the boot script to finish**: a `terraform_data` resource runs
  `scripts/wait-for-legacy-boot.sh`, which waits until this instance reports the association's current version as
  Success or Failed (30 minutes at most), prints the script's `RESULT` lines and fails the apply if the script failed.
  A finished `terraform apply` therefore means the server answers on port 80.
- The script writes one `RESULT` line per step. Systems Manager keeps the output of each run, and the script also
  keeps a transcript on the server.
- A new release changes the document, so the association runs again, and so does the wait. The script is safe to
  repeat: the D: drive, the database and the logins are created only when missing, and the seed-facts check runs only
  right after a fresh load.

**Correction (Phase 4.2 session).** This record first said Terraform's `wait_for_success_timeout_seconds` on the
association would be the wait. In the first session it reported Success 8 seconds after creation, with no targets
run: the instance had not yet registered with Systems Manager. The wait script replaced it.

The script, in order: formats the D: drive (the legacy configs log and export there), downloads and checks the
release, checks `@@SERVERNAME` against the computer name and fixes it if needed, caps SQL Server's memory, loads the
database with the release's own `load.ps1` and checks the seed facts as CI does, configures IIS (site, app pool, the
API key from Parameter Store written into `Web.config`), creates EXECUTE-only SQL logins for the app pool and for
Network Service, registers the nightly export task, and smoke-tests the API (200 with the key, 401 without) and the
export task.

Instance choices: t3.medium with SQL Server capped at 1.5 GB (t3.large is a variable away if memory runs short),
**unlimited CPU credits** (see the correction in ADR-0008), IMDSv2 only, no public address, no key pair, a 5 GB
encrypted D: volume deleted with the instance. The security group admits HTTP only from CloudFront's origin-facing
prefix list and allows HTTPS out only to the VPC and the S3 prefix list. The instance role can read only this
release and the API key parameter; an explicit deny stops `AmazonSSMManagedInstanceCore` reading any other
parameter, including the other project's secrets in the account.

## Consequences

- `make up` needs no separate polling: `terraform apply` ends when the server is ready.
- The wait runs on the machine applying Terraform and needs the AWS CLI there. CI never applies, so it never runs it.
- Measured in the first session: launch to ready in about 9.5 minutes (the script itself 353 s), a re-run in 150 s,
  and the golden `write-01-create` request replayed on the server with identical results
  ([measurements](../measurements.md)).
- The boot script is visible in the plan and versioned with the infrastructure, not baked into the image.
- The association needs Systems Manager to reach the instance first, through the `ssm` and `ssmmessages` endpoints
  (ADR-0011) and the instance profile; a broken endpoint shows up as a timed-out apply.
- The document is limited to 64 KB, ample for the script.
- Changing the script mid-session re-runs it on the same server rather than replacing the server.

## Alternatives considered

- **User data:** may never run on a non-sysprepped image, and gives no wait or output.
- **Resetting EC2Launch's state in the image:** needs an image rebuild and still gives no wait or output.
- **A status parameter written by the script and polled by `make up`:** more moving parts for what the association
  already reports.
- **Baking the application into the image:** every release would need an hour-long image build.
