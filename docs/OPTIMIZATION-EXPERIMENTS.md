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
| CPU-001 | Pair-cache hashing | `rapidhash` default with ARM64 `crc32` optional for `slotIndex` | `DONE (second pass)` |
| CPU-002 | Merge algorithm | Replace merge priority queue strategy with strict O(N) structured backtracking | `TODO` |
| CPU-003 | Pretokenizer | NEON/SVE2 boundary classification (`vtbl`/packed masks) | `TODO` |
| GPU-001 | Metal BPE | On-GPU BlockBPE merge in threadgroup memory | `TODO` |
| GPU-002 | Metal dispatch | Indirect Command Buffers for reduced CPU round-trips | `TODO` |
| GPU-003 | Metal memory | Wider `uchar16`/simdgroup loads in byte widen kernels | `TODO` |

## Experiment CPU-001 (2026-02-25)

### Goal

Evaluate pair-cache slot hash choices (`rapidhash`, ARM64 `crc32`) and promote a better default only with measured wins.

### Implementation

- Added ARM64 CRC32 helper: `asm/arm64/hash_crc32.S` (`turbotoken_arm64_hash_crc32_u64`).
- Added runtime hash selector in `src/pair_cache.zig`:
  - `TURBOTOKEN_PAIR_CACHE_HASH=rapidhash` (default)
  - `TURBOTOKEN_PAIR_CACHE_HASH=crc32` (opt-in on AArch64+CRC builds)
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

Decision: `adopt` (`rapidhash` default) and `keep optional` (`crc32`).
Reason: `rapidhash` is now the only generic software hash mode; ARM64 `crc32` remains an architecture-specific optional mode for direct A/B checks.
