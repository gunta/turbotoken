# turbotoken R Wrapper

Experimental R package wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/r
R CMD check .
```

Notes:
- Package metadata: `wrappers/r/DESCRIPTION`.
- Native sources are in `wrappers/r/src`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
