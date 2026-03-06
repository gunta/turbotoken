# turbotoken

An experimental high-performance BPE tokenizer project.

`turbotoken` aims to be a drop-in replacement for `tiktoken` with a Zig core, architecture-specific
SIMD backends, and compatibility-focused Python and JS wrapper paths. The repository is still in
active scaffold-to-implementation transition and should not be treated as production-ready yet.

## Status

- Early implementation, actively under development.
- Language bindings are organized under `wrappers/` (see `wrappers/README.md`).
- Each wrapper package has its own `README.md` with language-specific setup/usage notes.
- Release/publish governance is tracked in `wrappers/release-matrix.json` and `docs/PUBLISHING.md`.
- Python `Encoding` now uses real regex+BPE merge logic loaded from `.tiktoken` rank files.
- JS async encoding now defaults to real BPE when a native or full WASM backend is available; sync JS construction remains byte-path-first unless explicitly readied for BPE.
- Native Zig CPU acceleration is available for key byte-path primitives, with x86 runtime dispatch (AVX-512/AVX2/SSE4.2/scalar) now wired in `src/arch/x86_64.zig`.
- Apple Metal backend now includes an experimental on-device BPE merge loop (`find -> mark -> apply` + active compaction + GPU emit), but remains parity-guarded/experimental and is not the default route.
- Modal NVIDIA remote benchmark runner is available via `scripts/modal/bench_cuda_modal.py` for CUDA-hosted baseline runs (`B200` default; also supports `B200+`/`H200`/`H100`/`A100`/`L40S` on Modal). Paid Modal CUDA runs are explicit opt-in (`--confirm-paid`).
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
import { getEncodingAsync, trainBpeFromChunks } from "./wrappers/js/src/index";

const enc = await getEncodingAsync("o200k_base", {
  wasm: { wasmPath: "zig-out/bin/turbotoken.wasm" },
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
- JS backend routing now supports `backend: "auto" | "native" | "wasm" | "js"` (default `auto`).
- In Bun runtime, `auto` now prefers optional native packages (`@turbotoken/native-*`) and falls back to WASM when native is unavailable.
- You can force backend globally with `TURBOTOKEN_BACKEND=native|wasm|js|auto`.
- `getEncodingAsync()` and `encodingForModelAsync()` now default to real BPE mode when a native or full WASM backend is available.
- Passing `rankPayload` or `rankUrlOverride` also counts as an explicit BPE request, even on `getEncoding()`.
- Sync `getEncoding()` remains a byte-path-first thin wrapper unless you opt into BPE mode and call `await enc.ready()` first.
- WASM training helpers are available via `trainBpeFromChunkCounts` and `trainBpeFromChunks`.

Build host native package artifact (Bun native backend):

```bash
bun run build:native:host
```

Build/pack optional multi-platform native packages:

```bash
bun run build:native:packages
bun run pack:native:packages
# dry-run publish
TURBOTOKEN_NATIVE_PUBLISH_DRY_RUN=1 bun run publish:native:packages
```

Publish order recommendation:
1. publish `@turbotoken/native-*` packages
2. publish root `turbotoken` package

## Quick Start

```bash
bun install
# fastest Python path (recommended if uv is installed)
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -e ".[dev]"
# fallback:
# python3 -m pip install -e ".[dev]"

zig build
zig build test
bun run test:python
bun run test
bun run test:upstream-alias
bun run build:wheels
```

Cross-ecosystem publish readiness:

```bash
bun run release:check
bun run release:dry-run
```

Benchmark entrypoints:

```bash
bun run bench       # default local suite (CUDA excluded)
bun run bench:js-backends  # Bun native vs WASM backend comparison
bun run bench:gpu-host-overhead  # Metal route host-overhead microbench (hash/rank-init/wall-vs-GPU)
bun run bench:gpu-sweep  # staged Metal knob sweep (threads/rounds/compaction)
bun run bench:gpu-direct-sweep  # direct-objective sweep on bench-gpu-bpe-direct artifacts
bun run bench:gpu-direct-stability  # repeated direct A/B with median+p95 summary
bun run bench:cuda  # include local CUDA rows explicitly
bun run bench:scorecard  # consolidate latest artifacts into a canonical scorecard
bun run bench:modal:cuda  # paid remote Modal CUDA run (explicitly confirmed)
```

## Latest Benchmark Snapshot (2026-02-27, macOS ARM64)

All numbers below come from Hyperfine output in `bench/results/`.

| Workload | Mean time |
|---|---:|
| startup (`bench-startup-cold`, first encode) | 64.4 ms |
| count 100KB (`bench-count`) | 44.5 ms |
| encode 100KB (`bench-encode`) | 46.1 ms |
| decode 100KB-equivalent (`bench-decode`) | 59.7 ms |
| encode 1MB (`bench-bigfile`) | 72.4 ms |
| parallel count (512 items, 4 workers) (`bench-parallel`) | 206.0 ms |

Comparison snapshot (`bench-comparison-20260227-145334.json`):
- `turbotoken-encode-100kb`: 43.4 ms
- `tiktoken-encode-100kb`: 215.9 ms
- Speedup in this run: ~4.98x for turbotoken on the measured workload.

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
