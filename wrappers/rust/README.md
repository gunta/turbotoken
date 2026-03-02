# turbotoken Rust Wrapper

Experimental Rust crate wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/rust
cargo test
```

Notes:
- Crate manifest: `wrappers/rust/Cargo.toml`.
- Optional `bindgen` feature is available for generated bindings.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
