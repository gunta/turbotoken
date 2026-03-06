# turbotoken Zig WASM Unified Build

This document tracks the implemented Zig-first WASM path for `turbotoken`.

Current status:
- WASM module build step is wired: `zig build wasm -Doptimize=ReleaseSmall`
- Output artifacts:
  - full: `zig-out/bin/turbotoken.wasm`
  - npm-minimal: `zig-out/bin/turbotoken-npm.wasm`
- JS loader now calls real Zig exports via WebAssembly (no placeholder stub)
- npm auto-load defaults to `turbotoken-npm.wasm` with fallback to full `turbotoken.wasm`
- JS `Encoding` supports async BPE mode backed by WASM + rank payloads, and async factory helpers now default to that mode
- JS exports now include WASM training wrappers (`trainBpeFromChunkCounts`, `trainBpeFromChunks`)
- `scripts/bench-wasm.ts` now reports startup latency, throughput MB/s, and peak RSS rows
- `scripts/bench-wasm.ts` includes browser benchmark rows behind explicit opt-in (`TURBOTOKEN_WASM_BROWSER_ENABLE=1`)
- Browser benchmark rows now run strict parity assertions before timing (UTF-8 identity/roundtrip, plus BPE deterministic+roundtrip when rank payload is present)
- WASM arch helpers in `src/arch/wasm.zig` now use SIMD widening/truncation block copies in byte encode/decode hot loops
- JS WASM bridge now caches rank payload in WASM memory across BPE calls (reduces per-call JS-side rank-copy overhead)
- Browser harness dependency is now included in dev deps (`playwright`); Chromium can be installed via `bunx playwright install chromium`
- `wasm-opt` flow is now scripted (`bun run build:wasm:opt`), and npm wasm size gate is enforced (`TURBOTOKEN_NPM_WASM_MAX_BYTES`, default `150KB`)
- latest optimized npm wasm size: `1170` bytes (`dist/npm/optimize-wasm-1772455008637.json`)
- browser competitor page + headless runner is wired:
  - `bench/browser/wasm-competitors.html`
  - `bun run bench:browser:competitors` -> `bench/results/bench-browser-competitors-*.json`

## Build

```bash
bun run build:wasm
```

This runs `zig build wasm -Doptimize=ReleaseSmall` and then `wasm-opt` on the npm-minimal module.

Comparison size build (Zig vs MoonBit vs Emscripten):

```bash
bun run bench:wasm:comparisons
```

## Exports Used By JS (Full WASM)

- `turbotoken_wasm_alloc`
- `turbotoken_wasm_free`
- `turbotoken_encode_utf8_bytes`
- `turbotoken_decode_utf8_bytes`
- `turbotoken_count_bpe_from_ranks`
- `turbotoken_encode_bpe_from_ranks`
- `turbotoken_decode_bpe_from_ranks`
- `turbotoken_train_bpe_from_chunk_counts`

## Exports In npm-minimal WASM

- `turbotoken_wasm_alloc`
- `turbotoken_wasm_free`
- `turbotoken_encode_utf8_bytes`
- `turbotoken_decode_utf8_bytes`
- `turbotoken_version`

`wrappers/js/src/wasm-loader.ts` treats BPE/training exports as optional and throws a clear error if they are called against the minimal artifact.

## JS usage

```ts
import { getEncodingAsync, trainBpeFromChunks } from "../wrappers/js/src/index";

const enc = await getEncodingAsync("o200k_base", {
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
});

const ids = await enc.encodeAsync("hello world");
const text = await enc.decodeAsync(ids);

const merges = await trainBpeFromChunks({
  chunks: ["ab", "ab"],
  vocabSize: 257,
  minFrequency: 1,
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
});
```

Notes:
- `getEncodingAsync()` now defaults to BPE mode and prefers the full `turbotoken.wasm` artifact when it needs WASM BPE exports.
- Passing `rankPayload` or `rankUrlOverride` also enables BPE mode on the sync constructor, so sync byte-path fallback is not used silently once rank data is configured.
- Sync `encode/decode/count` methods still exist for byte-path use, and they now fail loudly if BPE mode was requested before the backend finished loading.
- Once the bridge is loaded, non-BPE byte-path `encode/decode/count` routes through WASM bridge exports (thin wrapper mode).
- Async methods ensure the WASM module is loaded.
- Repo remains in active optimization/scaffold stage; this is not yet a final production WASM package.
- npm packaging validation:
  - `bun run verify:npm-package`
  - `bun run smoke:npm-install`
  - `npm publish --dry-run --tag dev`
- Browser benchmark rows are executed only when explicitly enabled:

```bash
TURBOTOKEN_WASM_BROWSER_ENABLE=1 bun run scripts/bench-wasm.ts
```

- The browser harness will fail the benchmark row set if parity assertions fail, and the output artifact records `status=not-run` rows with the failure reason.
