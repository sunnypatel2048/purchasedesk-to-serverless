# ADR-0002: A real .NET Framework 4.8 legacy app, built without a Windows machine

**Status:** Accepted (proven in Phase 0.2 and 0.3)

## Context

The migration is only credible if the "before" system is genuinely legacy: ASP.NET Web API 2 on .NET
Framework 4.8, hosted by IIS through `System.Web`, calling stored procedures with ADO.NET. Development
happens on an Apple Silicon Mac, where .NET Framework cannot run.

## Decision

- Legacy projects use the community `MSBuild.SDK.SystemWeb` SDK (pinned, 4.0.107) with SDK-style project files
  targeting `net48`. The .NET SDK compiles them against Microsoft's reference assemblies.
- When the .NET SDK builds (`dotnet build`, `dotnet test`; `MSBuildRuntimeType == Core`) the project points
  `WebApplicationsTargetPath` at an empty stub and turns off `MvcBuildViews`. Neither Visual Studio's
  `Microsoft.WebApplication.targets` nor the `AspNetCompiler` task exists outside Visual Studio's MSBuild,
  and compiling needs neither.
- Visual Studio's `msbuild.exe` on GitHub's `windows-2022` runners keeps the real targets. It produces the
  IIS layout and packages the app for release.
- Tests run on `windows-2022` runners against SQL Server 2019 Developer, installed per run, using Windows
  authentication so no password is stored.

## Consequences

- The Mac compiles the legacy code in seconds; running it happens only on Windows runners and on EC2.
- Packaging for IIS must happen on Windows, never on the Mac.
- Measured in Phase 0.3: SQL Server installs on the runner in 3-4 minutes; the test job takes about
  5 minutes, the `msbuild.exe` build under a minute.
- The SDK expects a `Web.config`; binding redirects are written into it by the build.

## Alternatives considered

- **A modern .NET app written in the old style, in a container (version B):** runs on a Mac, but is not
  legacy. Kept as the fallback; Phase 0 showed it is not needed.
- **The 2016 `MSBuild.Microsoft.VisualStudio.Web.targets` package** to supply the missing targets on the Mac:
  a third-party copy of Microsoft's files with bundled DLLs. Rejected on supply-chain grounds.
- **LocalDB on the runner instead of SQL Server:** the same engine and about a minute to install. Kept as the
  fallback if CI time becomes a problem.
