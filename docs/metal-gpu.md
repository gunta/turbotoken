# turbotoken Metal GPU Backend

## Current Status

- `EXPERIMENTAL` and intentionally scoped to UTF-8 byte-path primitives.
- Implemented kernels:
  - `tt_encode_u8_to_u32` (byte -> `uint32_t` token widening)
  - `tt_count_nonzero_segments` (batch non-zero byte counts with offsets)
  - `tt_chunk_owner_flags` (GPU owner-mask stage for experimental chunk stitch)
- Implemented Python APIs:
  - `Encoding.encode_gpu()` / `Encoding.count_gpu()`
  - default `encode_gpu(device="auto")` keeps exact CPU/native rank-BPE path
  - experimental chunked stitch path is opt-in via `encode_gpu(device="metal", strict_verify=False)` and now uses a Metal owner-mask kernel plus boundary-repair/exactness guards before native/Python fallbacks
  - byte-path auto-route helpers in `python/turbotoken/_gpu.py`
- Implemented (experimental, parity-gated):
  - on-device BPE merge loop with rank-table lookup kernels (`find -> mark -> apply`)
  - iterative active-index compaction on GPU (`tt_bpe_compact_active_indices`)
  - optional on-GPU token emission from link state (`tt_bpe_emit_tokens_from_links`, opt-in via `TURBOTOKEN_METAL_BPE_GPU_EMIT_ENABLE=1`)
- Implemented route guards (2026-03-02):
  - full-piece GPU path now has a lower bound (`TURBOTOKEN_METAL_BPE_FULL_MIN_BYTES`, default `4096`) so tiny regex pieces stay on CPU/native.
  - `TURBOTOKEN_METAL_FORCE_ALL_PIECES=1` now has a sub-direct-size safety fallback to regular CPU encode unless `TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT=1`.
- Still pending:
  - reliable crossover wins versus CPU/native on real long-text workloads
  - broader route promotion/auto-route policy changes (currently fallback-first)

This backend should still be treated as experimental and fallback-first. It now has a true on-device merge loop, but route selection remains parity-guarded and conservative.

## Runtime Design

- Host runtime: `gpu/metal/metal_bridge.m` (Objective-C + C ABI).
- Python bridge: `python/turbotoken/_gpu.py`.
- Build model: on-demand compile via `xcrun clang` into `~/.cache/turbotoken/metal/`.
- Pipelines are compiled once and cached per process.
- Shared `MTLBuffer` pools are reused and grown geometrically to avoid per-call allocations.

## Latest Kernel Tuning Pass (2026-02-25, `metal-byte-path-v6`)

Implemented optimizations from the current research backlog:
- Encode kernel now processes `512` bytes per thread (previously `256`) to further reduce dispatch overhead.
- Encode kernel uses a `uchar4 -> uint4` unrolled path in the 64-byte loop (replacing the previous `uchar8` pointer pattern that failed to compile on current toolchains).
- Count kernel keeps SIMD-group reduction (`simd_sum`) and now adds 8x unrolled strided accumulation in the hot loop.
- Count kernel has an early single-simdgroup fast path to skip threadgroup memory/barrier work on small lane counts.
- Host bridge now uses lower-pressure encode occupancy (`threadExecutionWidth * 2`) and segment-size-based lane selection that favors fewer lanes for mid-size segments.
- Host command-buffer creation now prefers `commandBufferWithUnretainedReferences` when available to reduce per-dispatch overhead in synchronous call sites.
- Autoroute cache schema bumped to `v4` so updated kernels trigger fresh crossover calibration.

## Why This Shape on M4 Max

- Apple Silicon unified memory makes shared storage mode efficient for command-buffer workloads.
- Pipeline-state compilation is front-loaded so steady-state calls avoid shader compile overhead.
- Buffer reuse reduces allocator churn and command setup cost for repeated large batch calls.
- Segment-count kernel maps well to large-batch throughput workloads (many strings with precomputed offsets).

## Bench Command

```bash
bun run scripts/bench-gpu.ts
```

Current benchmark compares:
- Metal byte-path encode (`1MB` payload)
- Native NEON byte-path encode baseline (`1MB` payload)
- Metal batch count (`4096 x 1KB` segments)

Results are written to:
- `bench/results/bench-gpu-*.json`
- optional metadata: `bench/results/bench-gpu-*.meta.json`

## Latest Snapshot (2026-02-25, macOS ARM64 M4 Max)

Source artifact:
- `bench/results/bench-gpu-20260225-191259.json`

Measured means:
- Metal encode UTF-8 bytes (`1MB x 128`): `151.0 ms`
- Native NEON encode UTF-8 bytes (`1MB x 128`): `97.5 ms`
- Metal count non-zero batch (`4096 x 1KB`, 512 loops): `205.5 ms`
- Python CPU count non-zero batch (`4096 x 1KB`, 512 loops): `709.4 ms`

Interpretation:
- For this simple byte->u32 widening workload, native NEON remains faster than Metal.
- Metal already provides a clear win for large batch counting versus pure-Python counting logic.
- Full GPU BPE merge support is still needed before making end-to-end tokenizer speed claims for Metal.
- Versus the previous documented snapshot (`bench-gpu-20260225-160631.json`), this v6 pass improved measured Metal means by `~4.49%` (encode) and `~7.06%` (batch count) in this run.

## Crossover + Profiling

- Matrix benchmark script:
  - `bun run scripts/bench-gpu-crossover.ts`
  - default: `TURBOTOKEN_BENCH_LONG=0` (long mode disabled)
  - BPE profile selector: `TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND=low-entropy|normal-text` (default: `low-entropy`)
  - optional long-run row (adds `10,485,760` bytes/chars): `TURBOTOKEN_BENCH_LONG=1 bun run scripts/bench-gpu-crossover.ts`
- Direct-route safety matrix benchmark script:
  - `bun run scripts/bench-gpu-bpe-direct.ts`
  - runs `low-entropy` + `normal-text` workload profiles with direct route disabled/enabled and captures crossover + memory telemetry for each profile.
  - normal-text profile uses an alphabetic stream derived from `bench/fixtures/english-1mb.txt` (keeps natural letter distribution but avoids tiny-piece fragmentation in forced-metal A/B runs).
  - reporting policy: `normal-text` is the primary headline profile for MB/s/latency summaries; `low-entropy` is retained as a stress/safety profile.
  - route memory profile selector: `TURBOTOKEN_GPU_MEMORY_ROUTE_TEXT_KIND=low-entropy|normal-text` (used by `scripts/bench-gpu-memory.ts`)
- Latest matrix artifacts:
  - standard: `bench/results/bench-gpu-crossover-1772046799515.json`
  - optional long mode: `bench/results/bench-gpu-crossover-1772033988163.json`
  - direct safety matrix: `bench/results/bench-gpu-bpe-direct-1772344263726.json`
  - latest routing-fix quick run: `bench/results/bench-gpu-crossover-1772427763887.json`
  - latest direct A/B matrix: `bench/results/bench-gpu-bpe-direct-1772427787190.json`
- Auto-route cache:
  - `~/.cache/turbotoken/metal/autoroute-v1.json` (schema version now `4`)
- Profiling counters exported from C bridge and exposed through Python:
  - encode: CPU ns, GPU ns, bytes, dispatch threads
  - count: CPU ns, GPU ns, bytes, segment count, lanes
  - stitch: CPU ns, GPU ns, token count, chunk bytes, chunk count
- Long-run metadata in benchmark output:
  - `long_mode.enabled` + `long_mode.long_chars`
  - `bench_sizes.encode_bytes` and `bench_sizes.bpe_chars`

Current calibration on this machine prefers:
- native CPU path for byte encode (latest matrix run kept byte-path threshold at sentinel)
- Python baseline for batch non-zero count
- native path for BPE pieces (BPE threshold remains sentinel in latest calibration)

Nuance from latest matrix:
- At `1,048,576` bytes in the standard crossover run, Metal byte-encode is effectively tied with native (`23.79 ms` vs `23.78 ms`), so it still misses the >=5% auto-route win margin.
- For `8192 x 1KB` count batches, Metal now slightly beats Python (`2.48 ms` vs `2.54 ms`) with `64` lanes, but still misses the >=10% auto-route gate.

New BPE crossover rows in the same artifact show:
- `encode_gpu(device="auto", strict_verify=False)` matches baseline token output and tracks CPU/native performance closely.
- `encode_gpu(device="metal", strict_verify=False)` is now token-identical on tested long-piece cases because exactness guards fall back when stitch output is not exact.
- optional long mode (`10,485,760` chars) stays token-identical for both auto and forced-metal routes, but runtime remains CPU-like (`~28.1s` CPU baseline, `~28.2s` auto, `~28.1s` forced metal in latest run).
- despite improved correctness, BPE auto-route remains pinned to native (`2^60` sentinel) because Metal stitch path still does not beat baseline crossover targets.

2026-03-02 routing-fix note:
- `encode_gpu(device="auto", strict_verify=False)` now exits early to regular CPU encode whenever whole-text autoroute is native, avoiding GPU-route bookkeeping overhead on non-Metal rows.
- GPU range-batch fallback now preserves chunked native range batching (instead of per-piece Python fallback) when piece counts exceed batching limits.
- `_gpu._get_route_thresholds()` now uses cached threshold resolution to avoid repeated disk cache reads in per-piece routing loops.

2026-03-02 tiny-piece guard note:
- `_encode_bpe_chunked_stitched_metal_many` now batches single-chunk exact ranges through native range encode instead of per-piece native calls.
- tiny piece full-GPU route is now gated by `TURBOTOKEN_METAL_BPE_FULL_MIN_BYTES` (default `4096`), reducing per-piece command-buffer overhead in force-all runs.
- latest quick artifacts after this pass:
  - `bench/results/bench-gpu-bpe-direct-1772432813845.json`
  - `bench/results/bench-gpu-crossover-1772432841004.json`
  show forced-metal normal-text returning to sub-millisecond parity-safe behavior on the tracked `262,144`-byte profile.

## Next Steps Toward Full GPU BPE

1. Tune/benchmark the on-device merge loop for real crossover wins (normal-text long pieces + large batches).
2. Reduce host synchronization overhead per submit and re-check route-level MB/s + latency deltas.
3. Recalibrate auto-route using full BPE workloads and keep strict parity gates enabled.
4. Benchmark crossover points (batch size, string length) vs NEON CPU path on M4 Max.

## Research-Backed Constraints (2026-02-25)

- BlockBPE-style kernels are promising for high-batch throughput, but not guaranteed wins for low-batch interactive workloads.
- BlockBPE also reports that dropping regex pre-tokenization can reduce downstream quality on some tasks; strict parity mode must stay available.
- RAPIDS/cuDF now exposes GPU `byte_pair_encoding` and `wordpiece_tokenize` APIs, which confirms viability of GPU vocab/merge tables but does not provide `tiktoken`-compatible behavior out of the box.
- Existing `Fast-tokenizers` CUDA code is useful for thread-per-byte neighborhood patterns, but it documents correctness limitations for long repeating sequences and is not a compatibility target.

Primary references:
- https://arxiv.org/html/2507.11941v1
- https://docs.rapids.ai/api/libcudf/stable/group__nvtext__tokenize
- https://raw.githubusercontent.com/rapidsai/cudf/branch-25.08/cpp/include/nvtext/byte_pair_encoding.hpp
- https://github.com/github2015david/Fast-tokenizers

## Metal BPE Kernel Plan (Draft)

```c
// Host-side iterative dispatch (experimental path only).
for each piece in batch:
  load bytes/tokens to work buffers
  do:
    dispatch tt_find_min_pair_rank       // pair-rank lookup + threadgroup min reduction
    dispatch tt_mark_non_overlapping     // deterministic merge ownership mask
    dispatch tt_compact_after_merge      // prefix-sum based compaction
  while (merged_any)
  dispatch tt_emit_token_ids
```

Proposed kernel responsibilities:
- `tt_find_min_pair_rank`: per-token pair rank lookup from rank table + threadgroup min.
- `tt_mark_non_overlapping`: left-to-right tie-break/ownership mask to avoid overlapping merges.
- `tt_compact_after_merge`: move surviving/merged tokens into next buffer via prefix-sum write indices.

## Validation Gates Before Auto-Route

1. Token identity parity against CPU/native for `cl100k_base` + `o200k_base` corpus fixtures.
2. Crossover wins on measured matrix, not synthetic claims:
   - batch: `1, 8, 32, 128, 512, 1024`
   - piece chars: `64, 128, 256, 512, 1024, 4096`
3. Regression guard: if parity fails or crossover regresses, force fallback to native path.
