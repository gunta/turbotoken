# turbotoken -- Optimization Experiments

This file tracks optimization ideas as isolated experiments.
Each experiment must be benchmarked and documented before defaults change.

Current project status reminder: scalar rank-BPE is implemented, but the repository is still in active optimization/scaffold stage and not production-tuned yet.

## Protocol

1. Keep baseline behavior unchanged by default.
2. Implement new path behind a clear switch/guard.
3. Run reproducible benchmark commands.
4. Record artifact paths and decision (`adopt`, `keep optional`, `revert`).
5. Only promote to default after repeated wins.

## Backlog

| ID | Area | Idea | Status |
|---|---|---|---|
| CPU-001 | Pair-cache hashing | `crc32` default on AArch64+CRC with `rapidhash` fallback elsewhere | `DONE (second pass)` |
| CPU-002 | Merge algorithm | Queue strategy experiment toward O(N)-leaning merge scheduling | `DONE (first pass)` |
| CPU-003 | Pretokenizer | NEON-like ASCII boundary classification (`packed classes`) | `DONE (first pass)` |
| GPU-001 | Metal BPE | SIMD-group min-rank reduction in BPE merge loop | `DONE (first pass, reverted)` |
| GPU-002 | Metal dispatch | Lower per-round dispatch overhead in BPE loop | `DONE (first pass, reverted)` |
| GPU-003 | Metal memory | Wider byte-path loads in UTF-8 widen kernel | `DONE (first pass, reverted)` |

## Experiment CPU-001 (2026-02-25)

### Goal

Evaluate pair-cache slot hash choices (`rapidhash`, ARM64 `crc32`) and promote a better default only with measured wins.

### Implementation

- Added ARM64 CRC32 helper: `asm/arm64/hash_crc32.S` (`turbotoken_arm64_hash_crc32_u64`).
- Added runtime hash selector in `src/pair_cache.zig`:
  - default: `crc32` on AArch64+CRC, `rapidhash` otherwise
  - `TURBOTOKEN_PAIR_CACHE_HASH=rapidhash` (force software hash)
  - `TURBOTOKEN_PAIR_CACHE_HASH=crc32` (force CRC32 on supported AArch64; falls back to `rapidhash` elsewhere)
- Ported `rapidhash` v3 into `src/hash.zig` and switched rank-payload cache hashing in `src/exports.zig` to the same function.
- Added dedicated benchmark runner: `scripts/bench-pair-cache-hash.ts`.

### Commands

```bash
bun run scripts/bench-scalar-fallback.ts
bun run scripts/bench-pair-cache-hash.ts
```

### Artifacts

- `bench/results/bench-scalar-fallback-20260225-175550.json`
- `bench/results/bench-pair-cache-hash-20260225-175906.json`
- `bench/results/bench-pair-cache-hash-20260225-181644.json`
- `bench/results/bench-pair-cache-hash-20260225-182315.json`

### Result Summary

| Command | Mean |
|---|---:|
| `rapidhash-count-bpe-100kb` | `1.147 s` |
| `crc32-count-bpe-100kb` | `1.104 s` |
| `rapidhash-encode-bpe-100kb` | `1.463 s` |
| `crc32-encode-bpe-100kb` | `1.429 s` |

Decision: `adopt` (`crc32` default on supported AArch64; `rapidhash` otherwise).
Reason: larger-file A/B runs showed repeatable wins for ARM64 `crc32` in this environment while preserving `rapidhash` as the portable fallback.

## Experiment CPU-002 (2026-02-25)

### Goal

Test an alternate queue mode for rank-BPE merges to reduce overflow-heap pressure on high-rank merges.

### Implementation

- Added queue mode selector in `src/encoder.zig`:
  - `TURBOTOKEN_ENCODER_QUEUE=hybrid` (default)
  - `TURBOTOKEN_ENCODER_QUEUE=full-bucket` (optional experiment)
- Added rank-table helper `RankTable.maxRankPlusOne()` in `src/rank_loader.zig`.
- Added benchmark runner: `scripts/bench-encoder-queue.ts`.

### Commands

```bash
bun run scripts/bench-encoder-queue.ts
```

### Artifacts

- `bench/results/bench-encoder-queue-20260225-180932.json`
- `bench/results/bench-encoder-queue-20260225-181051.json`

### Result Summary

Mixed/near-noise:
- encode row showed small `full-bucket` edge in one pass (~1%).
- count row showed no stable win across reruns.

Decision: `keep optional`.

## Experiment CPU-003 (2026-02-25)

### Goal

Prototype NEON-like ASCII boundary classification for pretokenizer chunk planning.

### Implementation

- Added new boundary classifier in `src/pretokenizer.zig`:
  - scalar reference
  - AArch64 vectorized path (`countAsciiClassBoundariesNeonLike`)
- Added C ABI exports in `src/exports.zig`:
  - `turbotoken_count_ascii_class_boundaries_utf8`
  - `turbotoken_count_ascii_class_boundaries_utf8_scalar`
  - `turbotoken_count_ascii_class_boundaries_utf8_neon`
- Added Python bridge wrappers and tests (`python/turbotoken/_native.py`, `python/tests/test_native_bridge.py`).
- Added benchmark runner: `scripts/bench-boundary-classifier.ts`.

### Commands

```bash
bun run scripts/bench-boundary-classifier.ts
```

### Artifacts

- `bench/results/bench-boundary-classifier-20260225-181603.json`
- `bench/results/bench-boundary-classifier-20260225-181856.json`

### Result Summary

On this M4 Max run:
- auto/neon path was roughly `~1.8x` to `~2.35x` faster than scalar on 1MB fixtures.

Decision: `adopt` (new additive API path; no default routing regression introduced).

## Experiments GPU-001 / GPU-002 / GPU-003 (2026-02-25 first pass)

### Goal

Test practical GPU-side merge and dispatch/memory optimizations without changing correctness guarantees.

### Implementation Attempts

- GPU-003: wider byte-path load experiments in Metal encode kernel (including failed `uchar16/uchar8` variants and a compiling `uint4` unpack variant).
- GPU-001: `simd_min` reduction in `tt_bpe_find_min_rank`.
- GPU-002: single compute-encoder-per-round dispatch in Metal BPE loop (reducing per-round encoder setup overhead).

### Artifacts

- `bench/results/bench-gpu-20260225-182512.json`
- `bench/results/bench-gpu-crossover-1772043937345.json`
- `bench/results/bench-gpu-20260225-182816.json`
- `bench/results/bench-gpu-crossover-1772044096004.json`

### Result Summary

- Byte-path and crossover means regressed vs the previous stable baseline in this environment.
- BPE autoroute threshold regressed back to "never Metal" in the combined GPU-001/002/003 pass.

Decision: `revert` all three GPU trials as-is for now; keep benchmark evidence and revisit with tighter isolated kernels.
