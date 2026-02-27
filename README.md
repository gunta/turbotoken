# turbotoken

The fastest BPE tokenizer on every platform.

`turbotoken` is a drop-in replacement for `tiktoken` with a Zig core, architecture-specific
SIMD backends, and a compatibility-focused Python API.

## Status

- Early implementation, actively under development.
- Python `Encoding` now uses real regex+BPE merge logic loaded from `.tiktoken` rank files.
- Native Zig CPU acceleration is available for key byte-path primitives; broader backend work (AVX/GPU full BPE) is still in progress.
- Apple Metal backend is now wired as an experimental UTF-8 byte-path accelerator (full GPU BPE merge path is still pending).
- Modal NVIDIA remote benchmark runner is available via `scripts/modal/bench_cuda_modal.py` for CUDA-hosted baseline runs (`L40S`/`A100`/`H100` class on Modal).
- First-pass Python training APIs are available (`train_mergeable_ranks_from_iterator`, `train_encoding_from_iterator`) for custom regex+BPE vocab training (CPU path only).
- Public parity checks currently pass for `o200k_base`, `cl100k_base`, `p50k_base`, `r50k_base`
  on the tracked compatibility corpus.

## Training API (First Pass)

```python
from turbotoken import train_encoding_from_iterator

with open("corpus.txt", "r", encoding="utf-8") as handle:
    enc = train_encoding_from_iterator(
        handle,
        vocab_size=4096,
        name="custom_bpe",
    )

ids = enc.encode("hello world")
text = enc.decode(ids)
```

Notes:
- This path is currently CPU-only.
- Backend routing:
  - `TURBOTOKEN_TRAINING_BACKEND=auto` (default, currently prefers Python training loop for throughput in this environment)
  - `TURBOTOKEN_TRAINING_BACKEND=native` (Zig training backend prototype via C ABI)
  - `TURBOTOKEN_TRAINING_BACKEND=python` (force Python training loop)
- Optional native experiments (off by default):
  - `TURBOTOKEN_TRAIN_NATIVE_PRETOKENIZE=1` enables native ASCII O200K pretokenization before chunk counting
  - `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1` enables direct native ASCII O200K single-text training route
- Latest local training benchmarks show the Python training path beating both `rustbpe` and `minbpe` on the tracked 100KB/1MB fixtures; the Zig-native training prototype still trails the Python fallback path in this environment.

## JS + WASM (First Pass)

```ts
import { getEncodingAsync, trainBpeFromChunks } from "./js/src/index";

const enc = await getEncodingAsync("o200k_base", {
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
  enableWasmBpe: true, // experimental
});

const ids = await enc.encodeAsync("hello world");
const text = await enc.decodeAsync(ids);

const merges = await trainBpeFromChunks({
  chunks: ["ab", "ab", "ab"],
  vocabSize: 257,
  minFrequency: 1,
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
});
```

Build WASM artifact:

```bash
zig build wasm -Doptimize=ReleaseSmall
# or
bun run build:wasm
```

Notes:
- `enableWasmBpe` is currently experimental and off by default.
- Without it, JS methods fall back to UTF-8 byte behavior while still using the real WASM loader for byte-path primitives.
- WASM training helpers are available via `trainBpeFromChunkCounts` and `trainBpeFromChunks`.

## Quick Start

```bash
bun install
python3 -m pip install -e ".[dev]"

zig build
zig build test
bun run test:python
bun run test
bun run test:upstream-alias
bun run build:wheels
```

## Latest Benchmark Snapshot (2026-02-24, macOS ARM64)

All numbers below come from Hyperfine output in `bench/results/`.

| Workload | Mean time |
|---|---:|
| startup (`bench-startup`) | 139.3 ms |
| count 100KB (`bench-count`) | 144.3 ms |
| encode 100KB (`bench-encode`) | 148.7 ms |
| decode 100KB-equivalent (`bench-decode`) | 181.9 ms |
| encode 1MB (`bench-bigfile`) | 198.8 ms |
| parallel count (512 items, 4 workers) (`bench-parallel`) | 1.570 s |

Comparison snapshot (`bench-comparison`):
- `turbotoken-encode-100kb`: 147.1 ms
- `tiktoken-encode-100kb`: 195.0 ms
- Speedup in this run: ~1.33x for turbotoken on the measured workload.

## Planned Backends

- ARM64 NEON
- Apple Metal
- WebAssembly
- x86_64 AVX2/AVX-512
- NVIDIA CUDA
- RISC-V Vector

## Repository Layout

See [docs/PRD.md](./docs/PRD.md), [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md),
[docs/BENCHMARKS.md](./docs/BENCHMARKS.md), and
[docs/OPTIMIZATION-EXPERIMENTS.md](./docs/OPTIMIZATION-EXPERIMENTS.md) for details.
