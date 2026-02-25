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
  - experimental chunked stitch path is opt-in via `encode_gpu(device="metal", strict_verify=False)` and now uses a Metal owner-mask kernel before native/Python fallbacks
  - byte-path auto-route helpers in `python/turbotoken/_gpu.py`
- Not implemented yet:
  - GPU BPE merge logic (BlockBPE-style chunk merge/stitching)
  - fully on-GPU rank-table merge/stitch path (current merge path still uses CPU/native kernels)

This backend should be treated as a high-throughput building block for the future full GPU path, not as final tiktoken-compatible GPU BPE.

## Runtime Design

- Host runtime: `gpu/metal/metal_bridge.m` (Objective-C + C ABI).
- Python bridge: `python/turbotoken/_gpu.py`.
- Build model: on-demand compile via `xcrun clang` into `~/.cache/turbotoken/metal/`.
- Pipelines are compiled once and cached per process.
- Shared `MTLBuffer` pools are reused and grown geometrically to avoid per-call allocations.

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
- `bench/results/bench-gpu-20260225-145052.json`

Measured means:
- Metal encode UTF-8 bytes (`1MB x 128`): `180.9 ms`
- Native NEON encode UTF-8 bytes (`1MB x 128`): `107.3 ms`
- Metal count non-zero batch (`4096 x 1KB`, 512 loops): `277.6 ms`
- Python CPU count non-zero batch (`4096 x 1KB`, 512 loops): `792.6 ms`

Interpretation:
- For this simple byte->u32 widening workload, native NEON remains faster than Metal.
- Metal already provides a clear win for large batch counting versus pure-Python counting logic.
- Full GPU BPE merge support is still needed before making end-to-end tokenizer speed claims for Metal.

## Crossover + Profiling

- Matrix benchmark script:
  - `bun run scripts/bench-gpu-crossover.ts`
- Latest matrix artifact:
  - `bench/results/bench-gpu-crossover-1772030955226.json`
- Auto-route cache:
  - `~/.cache/turbotoken/metal/autoroute-v1.json` (schema version now `2`)
- Profiling counters exported from C bridge and exposed through Python:
  - encode: CPU ns, GPU ns, bytes, dispatch threads
  - count: CPU ns, GPU ns, bytes, segment count, lanes
  - stitch: CPU ns, GPU ns, token count, chunk bytes, chunk count

Current calibration on this machine prefers:
- native CPU path for byte encode (latest matrix run kept byte-path threshold at sentinel)
- Python baseline for batch non-zero count
- native path for BPE pieces (BPE threshold remains sentinel in latest calibration)

New BPE crossover rows in the same artifact show:
- `encode_gpu(device="auto", strict_verify=False)` matches baseline token output and tracks CPU/native performance closely.
- `encode_gpu(device="metal", strict_verify=False)` is much closer to CPU than earlier prototypes after GPU owner-mask stitching, but is still not token-identical on tested long-piece cases.

## Next Steps Toward Full GPU BPE

1. Port piece-level BPE merge candidate generation to Metal chunk kernels.
2. Replace prototype chunked stitch fallback with true on-GPU boundary merge/stitch.
3. Recalibrate auto-route using full BPE workloads (not only byte-path primitives).
4. Benchmark crossover points (batch size, string length) vs NEON CPU path on M4 Max.
