# turbotoken Mojo Wrapper

Experimental Mojo wrapper package for turbotoken.

## Local Dev

```bash
zig build
mojo test wrappers/mojo/test
```

Notes:
- Library sources are in `wrappers/mojo/turbotoken`.
- API surface is early and may change.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
