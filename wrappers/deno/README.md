# turbotoken Deno Wrapper

Experimental Deno wrapper with FFI bindings to the turbotoken native core.

## Local Dev

```bash
zig build
deno test wrappers/deno/tests
```

Notes:

- Main module entrypoint: `wrappers/deno/mod.ts`.
- Native library discovery is expected to use local build artifacts.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
