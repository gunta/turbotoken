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
| CPU-006 | Python startup + decode | persistent decoder/piece caches for short-lived process benchmarks | `DONE (first pass)` |
| CPU-007 | ARM64 non-ascii kernel | lower reduction frequency + DotProd accumulator batching | `DONE (first pass)` |
| CPU-005 | BPE training | Incremental pair-count trainer with lazy heap refresh for Python training API | `DONE (first pass)` |
| CPU-008 | Rank loader | pre-size rank table/hash maps before decode/insert to reduce cold parse overhead | `DONE (first pass)` |
| CPU-009 | Native rank payload | binary rank payload cache for native bridge cold-start paths | `DONE (first pass)` |
| CPU-010 | Native range encode/count | parallel two-pass range executor for batch/range C ABI + optional Python range-batch path | `DONE (first pass, keep optional at Python layer)` |
| GPU-001 | Metal BPE | SIMD-group min-rank reduction in BPE merge loop | `DONE (first pass, reverted)` |
| GPU-002 | Metal dispatch | Lower per-round dispatch overhead in BPE loop | `DONE (first pass, reverted)` |
| GPU-003 | Metal memory | Wider byte-path loads in UTF-8 widen kernel | `DONE (first pass, reverted)` |
| GPU-005 | Metal byte/count kernels | larger encode chunk and deeper count unroll in `metal-byte-path-v7` | `DONE (first pass)` |
| GPU-006 | Metal BPE dispatch | batch multiple BPE rounds per submit with single-encoder path | `DONE (first pass, keep optional)` |
| GPU-007 | Metal stitch host path | move keep-flag token compaction from Python loop to Zig export | `DONE (first pass)` |

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

## Experiment CPU-004 (2026-02-25)

### Goal

Reduce overhead in the ARM64 NEON non-ASCII byte counter without changing correctness.

### Implementation

- Updated `asm/arm64/neon_pretokenizer.S` in `turbotoken_arm64_count_non_ascii`:
  - increased accumulator flush interval from every 4x64B blocks to every 256x64B blocks (`#3` -> `#255` loop mask).
  - kept the same vector math and final tail behavior.

### Commands

```bash
bun run bench:native-pretokenizer
```

### Artifacts

- pre-change reference: `bench/results/bench-native-pretokenizer-20260225-185042.json`
- post-change run: `bench/results/bench-native-pretokenizer-20260225-190912.json`

### Result Summary

Representative means:

| Command | Before | After | Delta |
|---|---:|---:|---:|
| `english-1mb-neon` | `124.6 ms` | `118.1 ms` | `~5.2% faster` |
| `unicode-1mb-neon` | `126.4 ms` | `121.3 ms` | `~4.0% faster` |
| `english-1mb-auto` | `126.2 ms` | `118.9 ms` | `~5.8% faster` |
| `unicode-1mb-auto` | `125.7 ms` | `115.6 ms` | `~8.0% faster` |

Decision: `adopt`.

## Experiment CPU-005 (2026-02-25)

### Goal

Add a real training path (not inference-only) and optimize first-pass training throughput against `minbpe` / `rustbpe`.

### Implementation

- Added new training module: `python/turbotoken/training.py`
  - `train_mergeable_ranks_from_iterator(...)`
  - `train_encoding_from_iterator(...)`
- Algorithm:
  - regex chunk counting over input iterator
  - unique-chunk weighted corpus (`chunk -> count`)
  - incremental pair-count updates with lazy heap refresh in merge loop
- Added Zig trainer prototype in `src/trainer.zig` and C ABI export `turbotoken_train_bpe_from_chunk_counts(...)`, wired via `python/turbotoken/_native.py`
- Added backend routing control: `TURBOTOKEN_TRAINING_BACKEND=auto|native|python`
- Added allocator and heap-path tuning in Zig trainer:
  - arena-backed scratch allocation in `trainMergesFromChunkCounts`
  - octonary heap fanout for merge job priority queue
- Added native ASCII O200K pretokenization and direct-training experiments:
  - `splitAsciiO200kRanges` in `src/pretokenizer.zig`
  - `turbotoken_pretokenize_ascii_o200k_ranges(...)`
  - `turbotoken_train_bpe_ascii_o200k(...)` (single-text direct native path, experimental)
  - `turbotoken_train_bpe_ascii_o200k_multi(...)` (multi-text direct native path, experimental)
- Python bridge wrappers + route gates:
  - `TURBOTOKEN_TRAIN_NATIVE_PRETOKENIZE=1`
  - `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1`
- Training module import/route cleanup:
  - removed eager registry pattern dependency from training path by inlining default O200K training pattern
  - lazy import of native bridge in training route
  - lazy package exports in `python/turbotoken/__init__.py` to avoid eager `core` import on `turbotoken.training` import path
  - added ASCII fast chunking path in `training.py` using stdlib `re` for default/GPT4-known patterns
  - delayed `regex` import to non-ASCII/custom-pattern fallback paths
- Added tests: `python/tests/test_training.py`.
- Added benchmark runner: `scripts/bench-training.ts` (+ `bench:training` script entry).

### Commands

```bash
bun run test:python
bun run bench:training
TURBOTOKEN_TRAIN_FIXTURE=bench/fixtures/english-1mb.txt TURBOTOKEN_TRAIN_VOCAB_SIZE=320 bun run bench:training
```

### Artifacts

- `bench/results/bench-training-python-20260226-001016.json` (english-100kb, vocab=320)
- `bench/results/bench-training-python-20260226-000533.json` (english-1mb, vocab=320)
- optional direct-native experiment rows:
  - `bench/results/bench-training-python-20260225-233812.json` (english-100kb, `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1`)
  - `bench/results/bench-training-python-20260225-234514.json` (english-1mb, `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1`)

### Result Summary

| Corpus | turbotoken (python backend) | turbotoken (zig native backend prototype) | rustbpe | minbpe |
|---|---:|---:|---:|---:|
| english-100kb | `46.4 ms` | `64.4 ms` | `52.6 ms` | `682.7 ms` |
| english-1mb | `69.2 ms` | `84.6 ms` | `82.2 ms` | `6.497 s` |

Decision: `adopt` for default training route (`TURBOTOKEN_TRAINING_BACKEND=auto` => Python path on this host), keep native direct paths opt-in.
Reason: training support now exists in both Python and Zig-native prototype paths; Python route now beats both `rustbpe` and `minbpe` on tracked 100KB/1MB fixtures, while direct native ASCII routes remain behind and stay opt-in.

## Experiment GPU-004 (2026-02-25)

### Goal

Restore Metal bridge compile reliability on current toolchains and reduce command-buffer overhead in byte-path kernels.

### Implementation

- Updated `gpu/metal/metal_bridge.m`:
  - replaced the failing `uchar8*` encode-kernel pointer pattern with a `uchar4 -> uint4` unrolled path.
  - added `create_command_buffer_locked()` and routed dispatches through `commandBufferWithUnretainedReferences` when available.
  - bumped reported bridge version string to `metal-byte-path-v6`.

### Commands

```bash
bun run scripts/bench-gpu.ts
bun run scripts/bench-gpu-crossover.ts
```

### Artifacts

- reference snapshot: `bench/results/bench-gpu-20260225-174823.json`
- post-change snapshot: `bench/results/bench-gpu-20260225-191259.json`
- post-change crossover: `bench/results/bench-gpu-crossover-1772046799515.json`

### Result Summary

Representative means:

| Command | Before | After | Delta |
|---|---:|---:|---:|
| `metal-encode-utf8-bytes-1mb` | `168.6 ms` | `151.0 ms` | `~10.4% faster` |
| `metal-count-nonzero-batch-4096x1kb` | `222.5 ms` | `205.5 ms` | `~7.6% faster` |
| `python-cpu-count-nonzero-batch-4096x1kb` | `736.2 ms` | `709.4 ms` | baseline moved with run noise |

Crossover/autoroute note:
- BPE exactness remained intact in sampled rows.
- Autoroute thresholds still calibrate to sentinel (`2^60`) for encode/count/BPE in this environment, so auto stays CPU-first.

Decision: `adopt` for compile reliability + measured byte-path wins; keep autoroute conservative.

## Experiment CPU-006 (2026-02-26)

### Goal

Close remaining competitor gaps in short-lived Python process benchmarks (especially decode and 1MB encode/count rows) without changing tokenization behavior.

### Implementation

- Added persistent decoder cache in `python/turbotoken/_rank_files.py`:
  - `load_decoder_only(...)`
  - metadata validation (`size`, `mtime_ns`, cache version) before reuse
- Added persistent piece-token cache in `python/turbotoken/_rank_files.py`:
  - `load_piece_bpe_cache(...)`
  - `save_piece_bpe_cache(...)`
  - metadata validation and bounded cache growth guard
- Wired core to use these caches in `python/turbotoken/core.py`:
  - `_ensure_decoder()` now loads decoder cache directly (when mergeable ranks are not already in-memory)
  - large ASCII encode/count paths seed from persisted piece cache and persist newly learned short ASCII piece entries
  - optimized decode hot loop in `decode_bytes(...)` to reduce Python overhead
  - optimized repeated-piece count branch with frequency aggregation
- Added tests:
  - `python/tests/test_rank_files.py` now covers decoder cache build/load and piece-cache roundtrip.

### Commands

```bash
bun run test:python
bun run bench:competitors:stable
```

### Artifacts

- `bench/results/bench-competitors-stable-20260226-062057.json`
- `bench/results/bench-competitors-python-encode-20260226-061439.json`
- `bench/results/bench-competitors-python-decode-20260226-061559.json`
- `bench/results/bench-competitors-python-count-20260226-061649.json`
- `bench/results/bench-competitors-python-encode-20260226-061740.json`
- `bench/results/bench-competitors-python-decode-20260226-061859.json`
- `bench/results/bench-competitors-python-count-20260226-061949.json`
- `bench/results/bench-competitors-python-encode-20260226-062040.json`
- `bench/results/bench-competitors-python-decode-20260226-062200.json`
- `bench/results/bench-competitors-python-count-20260226-062250.json`

### Result Summary

3-pass median head-to-head (`turbotoken` vs `rs-bpe`) from `bench-competitors-stable-20260226-062057.json`:

| Scenario | turbotoken | rs-bpe | Winner |
|---|---:|---:|---|
| encode 1kb | `67.643 ms` | `71.826 ms` | turbotoken |
| encode 10kb | `41.086 ms` | `70.990 ms` | turbotoken |
| encode 100kb | `44.227 ms` | `72.715 ms` | turbotoken |
| encode 1mb | `76.777 ms` | `91.883 ms` | turbotoken |
| decode 1k tok | `68.409 ms` | `81.864 ms` | turbotoken |
| decode 10k tok | `67.396 ms` | `82.297 ms` | turbotoken |
| decode 128k tok | `73.562 ms` | `81.842 ms` | turbotoken |
| count 1kb | `64.594 ms` | `70.963 ms` | turbotoken |
| count 100kb | `43.933 ms` | `72.647 ms` | turbotoken |
| count 1mb | `73.003 ms` | `85.563 ms` | turbotoken |

Decision: `adopt`.
Reason: stable medians now show wins across all tracked Python competitor rows while preserving existing tests.

## Experiment CPU-007 (2026-02-26)

### Goal

Push ARM64 non-ASCII counting further with lower reduction overhead in NEON/DotProd paths.

### Implementation

- Updated `asm/arm64/neon_pretokenizer.S`:
  - NEON path: increased reduction flush interval (`#255` -> `#4095` mask cadence).
  - DotProd path: switched to batched vector accumulation in `v31.4s` with periodic horizontal reduction.

### Commands

```bash
zig build
zig build test
bun run bench:native-pretokenizer
```

### Artifacts

- reference run before this pass: `bench/results/bench-native-pretokenizer-20260226-064853.json`
- post-change run: `bench/results/bench-native-pretokenizer-20260226-065703.json`

### Result Summary

Representative means (before -> after):

| Command | Before | After | Delta |
|---|---:|---:|---:|
| `english-1mb-auto` | `98.1 ms` | `92.6 ms` | `~5.6% faster` |
| `english-1mb-neon` | `97.2 ms` | `93.5 ms` | `~3.8% faster` |
| `unicode-1mb-neon` | `100.9 ms` | `93.4 ms` | `~7.4% faster` |
| `english-1mb-dotprod` | `108.9 ms` | `106.2 ms` | `~2.5% faster` |
| `unicode-1mb-dotprod` | `107.9 ms` | `104.4 ms` | `~3.2% faster` |

Decision: `adopt`.

## Experiment GPU-005 (2026-02-26)

### Goal

Increase Metal byte/count throughput and narrow the gap vs CPU baselines for larger batches.

### Implementation

- Updated Metal kernels and bridge in:
  - `gpu/metal/metal_bridge.m`
  - `gpu/metal/batch_encode.metal`
  - `gpu/metal/batch_count.metal`
- Changes:
  - increased encode bytes-per-thread (`512` -> `2048`)
  - deeper non-zero count unroll (`8` -> `16` stride steps)
  - bumped bridge version to `metal-byte-path-v7`

### Commands

```bash
bun run scripts/bench-gpu.ts
bun run bench:gpu-crossover
```

### Artifacts

- reference snapshot: `bench/results/bench-gpu-20260226-062600.json`
- post-change snapshot: `bench/results/bench-gpu-20260226-065413.json`
- crossover snapshot: `bench/results/bench-gpu-crossover-1772088879390.json`

### Result Summary

Representative means (before -> after):

| Command | Before | After | Delta |
|---|---:|---:|---:|
| `metal-encode-utf8-bytes-1mb` | `161.7 ms` | `153.1 ms` | `~5.3% faster` |
| `metal-count-nonzero-batch-4096x1kb` | `225.1 ms` | `216.4 ms` | `~3.9% faster` |

Crossover note (`bench-gpu-crossover-1772088879390.json`):
- encode 1MB row: Metal `24.261 ms` vs native `24.523 ms` (near parity on this micro-row).
- count 8MB row improved strongly vs prior calibration (`~5.041 ms` -> `~2.863 ms`) but remains above Python (`~2.532 ms`), so auto-thresholds remain conservative (`2^60` sentinel).

Decision: `adopt` (keep CPU-first autoroute).

## Experiment GPU-006 (2026-02-26)

### Goal

Reduce Metal BPE host dispatch overhead by amortizing per-round command-buffer/encoder setup.

### Implementation

- Updated `gpu/metal/metal_bridge.m`:
  - Added `tt_bpe_reset_counters` kernel.
  - Added optional batched BPE round submit path with a single compute encoder.
  - Added tunable env var: `TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT` (clamped to `1..32`).
  - Kept baseline per-round path as default (`TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT=1`) to preserve behavior when batching is not explicitly requested.

### Commands

```bash
bun run scripts/bench-gpu-crossover.ts
TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT=4 bun run scripts/bench-gpu-crossover.ts
```

### Artifacts

- reference before this pass: `bench/results/bench-gpu-crossover-1772103430630.json`
- default path after this pass (`rounds_per_submit=1`): `bench/results/bench-gpu-crossover-1772105472061.json`
- batched path sample (`rounds_per_submit=4`): `bench/results/bench-gpu-crossover-1772105829211.json`

### Result Summary

Representative BPE rows (`a*N`, `device='metal'`):

| Input | Before | Default=1 | Batched=4 |
|---|---:|---:|---:|
| 65,536 chars | `93.649 ms` | `98.700 ms` | `461.335 ms` |
| 262,144 chars | `369.766 ms` | `396.339 ms` | `1898.269 ms` |
| 1,048,576 chars | `1493.094 ms` | `1558.807 ms` | `7683.656 ms` |

Decision: `keep optional` (do not promote batching to default yet).

Notes:
- Batched submit (`4`) was unstable/regressive in crossover runs, so it remains an experiment-only knob.
- Keep knob for targeted follow-up tuning while baseline remains conservative.

## Experiment GPU-007 (2026-02-26)

### Goal

Reduce Python overhead in the Metal stitched BPE path by removing per-token Python filtering work.

### Implementation

- Added new Zig C-ABI helper in `src/exports.zig`:
  - `turbotoken_filter_tokens_by_keep_flags(...)`
- Wired symbol in `src/main.zig`.
- Added Python native bridge wrapper:
  - `NativeBridge.filter_tokens_by_keep_flags(...)` in `python/turbotoken/_native.py`
- Updated Metal stitched route in `python/turbotoken/_gpu.py`:
  - after `chunk_owner_flags(...)`, use native filter helper first
  - keep existing Python loop fallback when symbol/path unavailable
- Added tests:
  - `src/exports.zig` (`filter tokens export compacts by keep flags`)
  - `python/tests/test_native_bridge.py` (`test_native_bridge_filter_tokens_wrapper_when_available`)

### Commands

```bash
zig build test
zig build
.venv/bin/python -m pytest -q
bun run scripts/bench-gpu-crossover.ts
```

### Artifacts

- reference (before GPU-007): `bench/results/bench-gpu-crossover-1772108075453.json`
- verification run: `bench/results/bench-gpu-crossover-1772109204736.json`
- verification run (with MiB/s fields): `bench/results/bench-gpu-crossover-1772109303258.json`

### Result Summary

Representative BPE rows (`a*N`, `device='metal'`):

| Input | Before | After |
|---|---:|---:|
| 65,536 chars | `107.413 ms` | `25.533 ms` |
| 262,144 chars | `421.689 ms` | `89.893 ms` |
| 1,048,576 chars | `1704.252 ms` | `346.615 ms` |

Auto-route rows also improved in the same run while still routing to native:
- 1,048,576 chars: `23.419 ms` -> `15.985 ms`

Decision: `adopt` (safe fallback retained; measured wins are large and repeatable in this environment).

## Experiment CPU-008 (2026-02-26)

### Goal

Reduce first-call native rank-BPE overhead by cutting rank table construction costs.

### Implementation

- Updated `src/rank_loader.zig`:
  - added `scanRankPayloadStats(...)` pre-pass (line count + max rank)
  - pre-sized containers before decode/insert:
    - `entries`
    - `by_token`
    - `by_rank`
    - `by_rank_dense`
- Updated `src/exports.zig`:
  - switched `rank_cache_allocator` from `std.heap.page_allocator` to `std.heap.c_allocator`.

### Commands

```bash
zig build test
zig build
.venv/bin/python -m pytest -q
bun run scripts/bench-scalar-fallback.ts
```

### Artifacts

- reference before pass: `bench/results/bench-scalar-fallback-20260226-122556.json`
- post-pass: `bench/results/bench-scalar-fallback-20260226-124936.json`
- post-pass + lean benchmark setup: `bench/results/bench-scalar-fallback-20260226-125607.json`

### Result Summary

Representative means:

| Command | Before | After |
|---|---:|---:|
| `turbotoken-native-count-bpe-100kb` | `839.4 ms` | `390.9 ms` |
| `turbotoken-native-encode-bpe-100kb` | `894.3 ms` | `434.9 ms` |

Benchmark harness note:
- `scripts/bench-scalar-fallback.ts` reads fixture bytes directly and avoids unnecessary `get_encoding(...).load_mergeable_ranks()` setup in each process run.

Decision: `adopt` (large cold-path win; still trailing `tiktoken` on this specific scalar-fallback benchmark).

## Experiment CPU-009 (2026-02-26)

### Goal

Remove text/base64 rank parsing overhead from cold native BPE calls by feeding a compact binary rank payload to the Zig loader.

### Implementation

- Added binary rank payload support in `src/rank_loader.zig`:
  - magic: `TTKRBIN1`
  - header with version/flags/source file metadata/counts
  - dense rank stream with missing-rank sentinel (`0xFFFFFFFF`)
  - `loadFromBytes(...)` now auto-detects binary payloads and loads via `loadFromBinaryPayload(...)`
- Added Python native payload cache in `python/turbotoken/_rank_files.py`:
  - `read_rank_file_native_payload(...)`
  - emits `*.tiktoken.native.bin` alongside the text rank file
  - validates cache via header metadata (`size`, `mtime_ns`) and rebuilds when stale
- Updated scalar benchmark harness in `scripts/bench-scalar-fallback.ts`:
  - switched to `read_rank_file_native_payload('o200k_base')`
- Added tests:
  - `src/rank_loader.zig`: binary payload format decode test
  - `python/tests/test_rank_files.py`: native payload cache build/reuse test

### Commands

```bash
zig build test
zig build
.venv/bin/python -m pytest -q
bun run scripts/bench-scalar-fallback.ts
```

### Artifacts

- reference before binary payload path: `bench/results/bench-scalar-fallback-20260226-125607.json`
- post-pass: `bench/results/bench-scalar-fallback-20260226-132256.json`

### Result Summary

Representative means:

| Command | Before | After |
|---|---:|---:|
| `turbotoken-native-count-bpe-100kb` | `390.9 ms` | `171.9 ms` |
| `turbotoken-native-encode-bpe-100kb` | `434.9 ms` | `210.4 ms` |
| `tiktoken-encode-100kb` | `209.4 ms` | `203.5 ms` |

Decision: `adopt`.
Reason: large additional cold-path win; native count row now exceeds tiktoken encode row in this benchmark, and native encode reaches near-parity.

## Experiment CPU-010 (2026-02-26)

### Goal

Speed up native batch/range BPE encode/count paths by parallelizing independent range work on CPU cores.

### Implementation

- Updated `src/exports.zig`:
  - added two-pass range engine used by both:
    - `turbotoken_encode_bpe_batch_from_ranks(...)`
    - `turbotoken_encode_bpe_ranges_from_ranks(...)`
  - pass 1: per-range token counts (parallel worker shards)
  - pass 2: per-range encode into precomputed output offsets (parallel worker shards)
  - added runtime parallel mode envs:
    - `TURBOTOKEN_NATIVE_BPE_PARALLEL_ENABLE=1` (force on)
    - `TURBOTOKEN_NATIVE_BPE_PARALLEL_DISABLE=1` (force off)
  - auto mode remains default with conservative thresholds.
- Updated `python/turbotoken/_native.py`:
  - added `NativeBridge.count_bpe_ranges_from_ranks(...)` using `out_tokens=NULL` range export path.
- Updated `python/turbotoken/core.py`:
  - added optional native range-batch encode/count route (guarded):
    - `TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE=1` to enable
    - `TURBOTOKEN_NATIVE_RANGE_BATCH_DISABLE=1` to force disable
  - left default behavior unchanged after regression checks (route is opt-in only).
- Added tests:
  - `src/exports.zig`: range count-only mode test
  - `python/tests/test_native_bridge.py`: range count wrapper test

### Commands

```bash
zig build test
zig build
.venv/bin/python -m pytest -q
bun run scripts/bench-competitors.ts
bun run scripts/bench-scalar-fallback.ts
bun run scripts/bench-gpu-crossover.ts
```

### Artifacts

- competitor rerun (final):
  - `bench/results/bench-competitors-python-encode-20260226-135430.json`
  - `bench/results/bench-competitors-python-decode-20260226-135548.json`
  - `bench/results/bench-competitors-python-count-20260226-135636.json`
- scalar fallback:
  - `bench/results/bench-scalar-fallback-20260226-135205.json`
- gpu crossover:
  - `bench/results/bench-gpu-crossover-1772113943845.json`

### Result Summary

Relative to the prior competitor snapshot (`132320/132438/132527`), final results were near-parity with small variance:

| Command | Before | After |
|---|---:|---:|
| `python-encode-1mb-turbotoken` | `72.6 ms` | `74.1 ms` |
| `python-count-1mb-turbotoken` | `67.2 ms` | `68.9 ms` |
| `python-decode-128000-tok-turbotoken` | `72.3 ms` | `66.3 ms` |

Scalar fallback stayed in the same winning zone for count:

| Command | Mean |
|---|---:|
| `turbotoken-native-count-bpe-100kb` | `166.2 ms` |
| `turbotoken-native-encode-bpe-100kb` | `213.6 ms` |
| `tiktoken-encode-100kb` | `202.1 ms` |

Decision: `adopt` for native range parallel engine and bridge API; `keep optional` for Python default route (opt-in only) to avoid regressions on tiny-piece corpora.
