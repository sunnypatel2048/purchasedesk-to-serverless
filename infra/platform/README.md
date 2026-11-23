# Platform layer

Everything a session needs, created by `make up` and destroyed by `make down` (Phase 4.4;
[ADR-0007](../../docs/adr/0007-terraform-three-layers.md)). Every resource is tagged `Layer=platform`, so anything
left after `make down` shows up in `make leftovers`.

| Module | Phase | What |
|---|---|---|
| [`network`](../modules/network) | 4.1 | VPC in two zones, private and database subnets, S3 and DynamoDB gateway endpoints, `ssm` and `ssmmessages` interface endpoints, no NAT ([ADR-0011](../../docs/adr/0011-private-network-without-nat.md)) |

Later phases add the legacy server, the front door, Aurora, DMS and the functions.

## By hand

The state lives in the bootstrap layer's bucket under its own key; `backend.hcl` (gitignored) holds the bucket name.

```bash
cd infra/platform
terraform init -backend-config=../bootstrap/backend.hcl   # once per clone
terraform plan
```

Every variable has a default; nothing personal is needed. CI plans this layer on every pull request that touches
`infra/`.
