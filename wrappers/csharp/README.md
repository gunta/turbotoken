# turbotoken C# Wrapper

Experimental .NET/C# wrapper over the shared turbotoken native library.

## Local Dev

```bash
zig build
dotnet test wrappers/csharp/Tests/TurboToken.Tests.csproj
```

Notes:
- Package project: `wrappers/csharp/TurboToken.csproj`.
- Tests currently focus on API shape and smoke behavior.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
