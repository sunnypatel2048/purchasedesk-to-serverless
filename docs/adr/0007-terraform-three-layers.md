# ADR-0007: Terraform in three layers: bootstrap, image and platform

**Status:** Accepted

## Context

The project is brought up and torn down every session, but some things must outlive a session: the Terraform
state itself, release artifacts, CI roles, and the Windows image, which takes a long time to build. Project 1
used two layers with separate state, and its lifecycle scripts carry over.

## Decision

| Layer | Lifetime | Contains |
|---|---|---|
| `bootstrap` | Persistent | State bucket with native locking, artifact bucket, GitHub OIDC roles (read-only plan, artifact push), alerts topic |
| `image` | Persistent, built rarely | The Windows image, built by Packer and referenced by tag |
| `platform` | Created by `make up`, destroyed by `make down` | Network, legacy server, Aurora, DMS, functions, API, Cognito, front door, dashboard, alarms |

The platform layer has two switches, `legacy_enabled` and `replication_enabled`. Decommissioning is an apply with
both set to false. Traffic weights live in the KeyValueStore, outside Terraform (ADR-0004). Application secrets
are never managed by Terraform, because it would copy them into state.

## Consequences

- Teardown cannot delete the state it depends on, or the image that makes `make up` fast.
- The end state after decommissioning is the same code with less in it.
- The AWS account ID stays out of the repo: `backend.hcl` is gitignored and only an example is committed.
- The bootstrap layer must exist before CI can plan.

## Alternatives considered

- **One layer:** `make down` would destroy the state bucket and the image.
- **AWS CDK or SAM for the serverless half:** two tools for one platform, and Terraform is the more widely
  asked-for skill.
