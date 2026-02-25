# turbotoken

The fastest BPE tokenizer on every platform.

`turbotoken` is a drop-in replacement for `tiktoken` with a Zig core, architecture-specific
SIMD backends, and a compatibility-focused Python API.

## Status

- Early implementation, actively under development.
- Python `Encoding` now uses real regex+BPE merge logic loaded from `.tiktoken` rank files.
- Native Zig CPU acceleration is available for key byte-path primitives; broader backend work (AVX/GPU full BPE) is still in progress.
- Apple Metal backend is now wired as an experimental UTF-8 byte-path accelerator (full GPU BPE merge path is still pending).
- Public parity checks currently pass for `o200k_base`, `cl100k_base`, `p50k_base`, `r50k_base`
  on the tracked compatibility corpus.

## Quick Start

```bash
bun install
python3 -m pip install -e ".[dev]"

zig build
zig build test
python3 -m pytest -q
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
and [docs/BENCHMARKS.md](./docs/BENCHMARKS.md) for details.
