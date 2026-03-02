# turbotoken Julia Wrapper

Experimental Julia wrapper package.

## Local Dev

```bash
zig build
cd wrappers/julia
julia --project=. -e 'using Pkg; Pkg.test()'
```

Notes:
- Package entrypoint is `wrappers/julia/src/TurboToken.jl`.
- Native loading strategy is still being finalized.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
