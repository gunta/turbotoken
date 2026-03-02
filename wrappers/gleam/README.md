# turbotoken Gleam Wrapper

Experimental Gleam wrapper that targets Erlang and calls turbotoken native bindings.

## Local Dev

```bash
zig build
cd wrappers/gleam
gleam test
```

Notes:
- Erlang FFI module is `wrappers/gleam/src/turbotoken_ffi.erl`.
- Native bridge support code is shared with `wrappers/nif`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
