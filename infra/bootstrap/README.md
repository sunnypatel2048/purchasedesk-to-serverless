# Bootstrap layer

Persistent AWS resources that outlive every `make down`: the Terraform state bucket, the release artifact bucket,
the GitHub Actions OIDC roles and the alerts topic. Applied by hand, rarely; CI only plans it.

It reads, but never manages, the account's GitHub OIDC provider, which belongs to another project's bootstrap
layer ([ADR-0007](../../docs/adr/0007-terraform-three-layers.md)).

## First-time setup (the state bucket bootstraps itself)

The state bucket cannot hold its own state before it exists, so it is created with local state first, then the
state is moved into it.

```bash
cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # then set alerts_email
terraform init
terraform apply                                # creates the buckets; state is local for now
```

Write `backend.hcl` before adding `backend.tf`: once a backend block exists, Terraform will not run
`terraform output` until the backend is initialised.

```bash
printf 'bucket = "%s"\nregion = "us-east-1"\n' "$(terraform output -raw state_bucket)" > backend.hcl
```

Then add `backend.tf` (an `s3` backend with `key = "bootstrap/terraform.tfstate"`, `encrypt` and `use_lockfile`):

```bash
cp terraform.tfstate ~/purchasedesk-bootstrap-state-backup.json
terraform init -backend-config=backend.hcl -migrate-state   # answer yes
terraform plan                                              # must say "No changes."
rm terraform.tfstate terraform.tfstate.backup
```

Finally, confirm the subscription email AWS sends to `alerts_email`, and set the two CI role ARNs as GitHub
Actions secrets (`terraform output ci_role_arns`).

## Day to day

```bash
terraform init -backend-config=backend.hcl   # once per clone
terraform plan
terraform apply
```

`backend.hcl` and `terraform.tfvars` are gitignored: one holds the AWS account ID, the other an email address.
