# turbotoken Elixir Wrapper

Experimental Elixir package using a native extension to call turbotoken.

## Local Dev

```bash
zig build
cd wrappers/elixir
mix deps.get
mix test
```

Notes:
- Native source is in `wrappers/elixir/c_src` with shared support in `wrappers/nif`.
- Build is orchestrated by `elixir_make`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
