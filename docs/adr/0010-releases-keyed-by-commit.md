# ADR-0010: Releases keyed by commit, with a latest pointer in S3

**Status:** Accepted (Phase 3.4)

## Context

The legacy server installs nothing from GitHub at boot: it fetches the packaged app and database scripts from the
artifact bucket (Phase 4). The plan said the release workflow would also commit a new version number to the
repository. The branch ruleset requires a pull request and three checks for every change to `main`, with no bypass,
so a workflow committing to `main` would need a bypass or a token that defeats the ruleset.

## Decision

`release.yml` publishes each release under the commit it was built from, and keeps a pointer to the newest one.
Nothing is committed back.

```
releases/<commit>/legacy-web.zip        the IIS site folder (Visual Studio MSBuild publish, Release)
releases/<commit>/legacy-export.zip     the nightly export program and its config
releases/<commit>/legacy-database.zip   the scripts in load-order.txt, load.ps1 and the seed check
releases/<commit>/manifest.json         commit, time, workflow run, SHA-256 of each zip, vulnerability scan result
releases/legacy-latest.json             the newest commit and its manifest's SHA-256
```

- **When:** a pull request touching `legacy/`, the packaging script or the workflow packages and scans only, and
  keeps the result as an Actions artifact. A push to `main`, or a manual run on `main`, also publishes.
- **Immutable:** every object under `releases/<commit>/` is written with a conditional put (`If-None-Match: *`).
  A re-run for a published commit changes nothing. Only `legacy-latest.json` is ever replaced. The bucket is
  versioned in any case.
- **Checked:** the publish job verifies each zip against the manifest before uploading; the boot script verifies
  them again before use. The manifest is written last, so its presence means the release is complete.
- **Scanned:** `dotnet list package --vulnerable --include-transitive` over the shipped projects; High or Critical
  stops the release. The result is recorded in the manifest.
- **Choosing a release:** `make up` uses `legacy-latest.json` unless a commit is pinned (Phase 4).

## Consequences

- No ruleset bypass, and no workflow ever has write access to the repository.
- A release is identified by a commit SHA, not a version number. The commit leads straight to the code, the
  workflow run and the pull request.
- `legacy/` is frozen, so after the first release new legacy releases are rare. Later phases add the functions'
  packages under the same commit prefix.
- Packages are not signed. The checksums prove a download matches what CI built, and only CI on `main` can write
  under `releases/`. Production would add signed build provenance (artifact attestations).
- The ruleset does not require a branch to be up to date before merging, so the merged commit is not always the
  exact commit the pull request tested. With `legacy/` frozen this is very unlikely to matter.

## Alternatives considered

- **Commit a version number back to `main`:** needs a ruleset bypass for the workflow, the opposite of "no bypass".
- **Git tags as versions:** the push role trusts only `refs/heads/main`, and tags would add a second release trigger
  for a frozen app.
- **Release only after `legacy.yml` passes on `main` (`workflow_run`):** a stricter gate, but that workflow runs only
  when `legacy/` changes, so the first release would need a manual run, and `workflow_run` adds context to reason
  about for little gain while `legacy/` is frozen.
- **GitHub Releases instead of S3:** the instance would need a GitHub token or a public download at boot; the bucket
  is private and reachable through a gateway endpoint.
