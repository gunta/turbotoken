# turbotoken C++ Wrapper

Experimental C++ wrapper over the turbotoken C ABI.

## Local Dev

```bash
zig build
cmake -S wrappers/cpp -B wrappers/cpp/build
cmake --build wrappers/cpp/build
ctest --test-dir wrappers/cpp/build --output-on-failure
```

Notes:
- Public headers are in `wrappers/cpp/include/turbotoken/`.
- Link against `zig-out/lib` artifacts from the repo root build.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
