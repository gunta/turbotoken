# turbotoken Go Wrapper

Experimental Go wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/go
go test ./...
```

Notes:
- Module path: `github.com/turbotoken/turbotoken-go`.
- Wrapper aims to keep cgo/FFI overhead minimal.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
