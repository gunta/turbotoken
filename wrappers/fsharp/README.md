# turbotoken F# Wrapper

Experimental F# wrapper over the turbotoken native library.

## Local Dev

```bash
zig build
dotnet build wrappers/fsharp/TurboToken.FSharp.fsproj
```

Notes:
- The package currently mirrors the C# surface with F# idioms.
- Test coverage is still in progress.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
