# turbotoken Zig WASM Unified Build

This document tracks the implemented Zig-first WASM path for `turbotoken`.

Current status:
- WASM module build step is wired: `zig build wasm -Doptimize=ReleaseSmall`
- Output artifact: `zig-out/bin/turbotoken.wasm`
- JS loader now calls real Zig exports via WebAssembly (no placeholder stub)
- JS `Encoding` supports async BPE mode backed by WASM + rank payloads
- JS exports now include WASM training wrappers (`trainBpeFromChunkCounts`, `trainBpeFromChunks`)
- `scripts/bench-wasm.ts` now reports startup latency, throughput MB/s, and peak RSS rows

## Build

```bash
zig build wasm -Doptimize=ReleaseSmall
```

Or via package script:

```bash
bun run build:wasm
```

## Exports used by JS

- `turbotoken_wasm_alloc`
- `turbotoken_wasm_free`
- `turbotoken_encode_utf8_bytes`
- `turbotoken_decode_utf8_bytes`
- `turbotoken_count_bpe_from_ranks`
- `turbotoken_encode_bpe_from_ranks`
- `turbotoken_decode_bpe_from_ranks`
- `turbotoken_train_bpe_from_chunk_counts`

## JS usage

```ts
import { getEncodingAsync, trainBpeFromChunks } from "../js/src/index";

const enc = await getEncodingAsync("o200k_base", {
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
  enableWasmBpe: true, // experimental
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
- Sync `encode/decode/count` methods still exist and fall back to UTF-8 byte behavior when WASM/ranks are not loaded.
- Async methods ensure the WASM module is loaded.
- WASM BPE route is currently opt-in (`enableWasmBpe: true`) and still experimental.
- Repo remains in active optimization/scaffold stage; this is not yet a final production WASM package.
