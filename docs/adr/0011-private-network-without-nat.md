# ADR-0011: A private network without NAT

**Status:** Accepted (Phase 4.1)

## Context

The legacy server, and later the Lambda functions, Aurora and DMS, run in a VPC that exists only during a session.
Nothing in it should accept traffic from the internet: CloudFront reaches the legacy server through a VPC origin
(ADR-0004). The server still needs a few AWS services: S3 for the release (ADR-0010), Parameter Store for the SQL
logins, and Systems Manager for administration. A NAT gateway costs about $33 a month idle.

## Decision

`infra/modules/network`, called by the platform layer:

| Piece | Choice |
|---|---|
| VPC | `10.60.0.0/16`, DNS hostnames on, distinct from the other project in the account |
| Zones | Two, by zone ID: `use1-az1` and `use1-az2`. Aurora and DMS need two zones; `use1-az3` cannot host CloudFront VPC origins and offers no t3 instances |
| Subnets | Private `10.60.0.0/24` and `10.60.1.0/24` (servers, functions, DMS); database `10.60.10.0/24` and `10.60.11.0/24` (Aurora). No public subnets |
| Internet gateway | Attached, because CloudFront VPC origins require one, but no route table routes to it |
| Gateway endpoints | S3 and DynamoDB, free, on the private route table |
| Interface endpoints | `ssm` and `ssmmessages`, in the first zone only, private DNS on, HTTPS from the VPC only |
| Default security group | Every rule removed |

- **No `ec2messages` endpoint.** SSM Agent 3.3.40.0 and later uses `ssmmessages` instead; the Windows image ships
  3.3.5700. Windows time sync and licence activation use AWS link-local addresses and need no endpoint.
- **One zone for interface endpoints.** Each zone is billed separately (about $0.01 an hour per endpoint per zone).
  Instances in the second zone reach them across zones.
- **Later phases add endpoints only when something needs one**, for example CloudWatch Logs.

## Consequences

- About $0.02 an hour for the network while it exists; nothing when it does not.
- No resource in the VPC can reach the internet: no package downloads, no Windows Update at runtime. Everything the
  server needs is in the image (ADR-0008) or in the release.
- If the endpoints' zone has an outage, Systems Manager is unreachable for the session. Acceptable for a demo;
  production would put the endpoints in both zones.
- No VPC flow logs, matching the buckets' lack of access logs. Production would send flow logs to CloudWatch Logs.
- The S3 endpoint keeps the default policy. A policy limited to this project's buckets would also block the SSM
  agent's downloads from AWS-owned buckets. Access is still governed by each role's IAM policy and each bucket's
  policy.
- Subnets and security groups cannot be deleted while network interfaces remain. The VPC origin, Lambda functions
  and DMS leave interfaces behind for a while; teardown deletes those first and waits (Phase 4.4).

## Alternatives considered

- **NAT gateway:** about $33 a month idle and a route to the internet from every private subnet.
- **Public subnets with public IPs** (as in the other project): simpler, but the legacy server would have an internet
  address, which the security model rules out.
- **Interface endpoints in both zones:** twice the endpoint cost for availability a demo does not need.
- **The terraform-aws-modules VPC module:** it creates an internet gateway only together with public subnets, and the
  network is small enough to read as plain resources.
