# turbotoken JS/TS Wrapper

JavaScript/TypeScript wrapper package for turbotoken.

## Local Dev

```bash
zig build wasm -Doptimize=ReleaseSmall
bun test wrappers/js/tests/smoke.test.ts
```

## Usage

```ts
import { getEncodingAsync } from "turbotoken";

const enc = await getEncodingAsync("o200k_base", {
  backend: "auto",
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
});

const ids = await enc.encodeAsync("hello world");
```

Notes:
- `backend: "auto"` prefers optional native packages, then falls back to WASM.
- `getEncodingAsync()` defaults to real BPE mode; sync `getEncoding()` stays byte-path-first unless you explicitly enable BPE and await `enc.ready()`.
- Source lives in `wrappers/js/src`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
