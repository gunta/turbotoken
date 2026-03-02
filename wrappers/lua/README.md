# turbotoken Lua Wrapper

Experimental Lua wrapper (LuaJIT FFI / cffi-lua style) for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/lua
busted spec
```

Notes:
- Rockspec: `wrappers/lua/turbotoken-dev-1.rockspec`.
- Modules are under `wrappers/lua/src/turbotoken`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
