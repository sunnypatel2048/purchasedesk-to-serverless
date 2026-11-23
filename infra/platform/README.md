# Platform layer

Everything a session needs, created by `make up` and destroyed by `make down` (Phase 4.4;
[ADR-0007](../../docs/adr/0007-terraform-three-layers.md)). Every resource is tagged `Layer=platform`, so anything
left after `make down` shows up in `make leftovers`.

| Module | Phase | What |
|---|---|---|
| [`network`](../modules/network) | 4.1 | VPC in two zones, private and database subnets, S3 and DynamoDB gateway endpoints, `ssm` and `ssmmessages` interface endpoints, no NAT ([ADR-0011](../../docs/adr/0011-private-network-without-nat.md)) |
| [`legacy`](../modules/legacy) | 4.2 | The Windows server from the image, configured by a Systems Manager association that Terraform waits for ([ADR-0012](../../docs/adr/0012-legacy-server-configured-by-ssm.md)). Off with `legacy_enabled = false` |

Later phases add the front door, Aurora, DMS and the functions.

The legacy server needs the API key parameter first: `make secrets` (once per AWS account). Its boot script's
output, one `RESULT` line per step:

```bash
aws ssm list-command-invocations --details --instance-id "$(terraform output -raw legacy_instance_id)" \
  --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text
```

## By hand

The state lives in the bootstrap layer's bucket under its own key; `backend.hcl` (gitignored) holds the bucket name.

```bash
cd infra/platform
terraform init -backend-config=../bootstrap/backend.hcl   # once per clone
terraform plan
```

Every variable has a default; nothing personal is needed. CI plans this layer on every pull request that touches
`infra/`.
