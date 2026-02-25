# turbotoken -- Benchmark Tracker

> All benchmark results, methodology, and comparison data.
> Every number in this file comes from Hyperfine or documented tooling.
> No hand-waving. No "approximately". Measured or marked as TARGET.

---

## Methodology

### Tools
- **Hyperfine** v1.19+ -- CLI benchmark with statistical analysis
- **Bun Shell TypeScript** -- all benchmark orchestration scripts
- **Python `timeit`** -- in-process micro-benchmarks (supplement to Hyperfine)
- **`/usr/bin/time -l`** (macOS) / `/usr/bin/time -v` (Linux) -- peak RSS memory
- **`wc -c`** -- binary/wheel size comparison

### Principles
1. **All benchmarks are reproducible** via `bun run scripts/bench-all.ts`
2. **Hyperfine runs minimum 10 iterations** with 3 warmup runs
3. **Shell overhead correction** enabled (Hyperfine's `--shell=none` for fast commands)
4. **Same input data** for all competitors (fixtures in `bench/fixtures/`)
5. **Same machine** for any comparison table (noted in header)
6. **JSON export** for every run (`bench/results/*.json`)
7. **Charts auto-generated** from JSON via `bun run scripts/generate-charts.ts`

### Test Machine

| Property | Value |
|----------|-------|
| Machine | MacBook Pro (2024) |
| Chip | Apple M4 Max |
| CPU Cores | 16 (12P + 4E) |
| GPU Cores | 40 |
| RAM | 128GB Unified |
| OS | macOS Sequoia 15.x |
| Python | 3.12.x |
| Node.js | 22.x LTS |
| Bun | 1.x |

Local benchmark host details (from `sysctl` / `uname`):
- model identifier: `Mac16,5`
- kernel / arch: `Darwin 25.3.0` / `arm64` (`AArch64`)
- ISA features detected: NEON/AdvSIMD, FP16, DotProd, BF16, I8MM, SHA3/AES/PMULL, LSE/LSE2, SME/SME2 (current hot path uses AdvSIMD/NEON instructions)

> Additional machines will be added as we benchmark on Graviton, x86, RISC-V, etc.

---

## Latest Measured Run (2026-02-25, macOS ARM64)

This is the latest focused post-optimization benchmark pass. Artifacts:

- `bench/results/bench-count-20260225-174903.json`
- `bench/results/bench-encode-20260225-174903.json`
- `bench/results/bench-comparison-20260225-174847.json`
- `bench/results/bench-native-byte-path-20260225-174725.json`
- `bench/results/bench-native-pretokenizer-20260225-174747.json`
- `bench/results/bench-native-pretokenizer-sme-auto-20260225-174915.json`
- `bench/results/bench-gpu-20260225-174823.json`
- `bench/results/bench-gpu-crossover-1772041537394.json`

| Workload | Mean |
|---|---:|
| count 100KB | 160.6 ms |
| encode 100KB | 158.5 ms |

Comparison (`bench-comparison`):
- turbotoken encode 100KB: 158.5 ms
- tiktoken encode 100KB: 202.7 ms
- turbotoken ran ~1.28x faster on this workload in this run.

---

## Latest Pair-Cache Hash A/B (2026-02-25, macOS ARM64)

Direct hash strategy comparison from:
- `bench/results/bench-pair-cache-hash-20260225-182315.json`
- run command: `bun run scripts/bench-pair-cache-hash.ts`
- env switch used per row: `TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`

| Operation | `rapidhash` mean | `crc32` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 1.147 s | 1.104 s | crc32 ~3.8% faster in this run |
| native encode BPE 100KB | 1.463 s | 1.429 s | crc32 ~2.3% faster in this run |

Decision for now:
- default to `crc32` on AArch64+CRC and `rapidhash` on other targets.
- keep both explicit overrides for A/B checks (`TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`).

---

## Latest Encoder Queue A/B (2026-02-25, macOS ARM64)

Direct queue strategy comparison from:
- `bench/results/bench-encoder-queue-20260225-180932.json`
- `bench/results/bench-encoder-queue-20260225-181051.json`
- run command: `bun run scripts/bench-encoder-queue.ts`
- env switch used per row: `TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket`

Representative rerun (`...181051.json`):

| Operation | `hybrid` mean | `full-bucket` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 1.110 s | 1.113 s | full-bucket ~0.3% slower |
| native encode BPE 100KB | 1.478 s | 1.465 s | full-bucket ~0.9% faster |

Decision for now:
- keep `hybrid` as default.
- keep `full-bucket` as opt-in experiment only (`TURBOTOKEN_ENCODER_QUEUE=full-bucket`).

---

## Latest ASCII Boundary Classifier (2026-02-25, macOS ARM64)

Experimental boundary-classification benchmark from:
- `bench/results/bench-boundary-classifier-20260225-181856.json`
- run command: `bun run scripts/bench-boundary-classifier.ts`

| Operation | Auto mean | Scalar mean | Relative |
|---|---:|---:|---:|
| boundary-class english-1mb | 1.604 s | 2.979 s | auto ~1.86x faster |
| boundary-class unicode-1mb | 1.667 s | 3.773 s | auto ~2.26x faster |

Note:
- This is a new additive pretokenizer primitive (`count_ascii_class_boundaries`), not a replacement of the core BPE path.

---

## Latest Native Byte-Path Comparison (2026-02-25, macOS ARM64)

Direct ARM64 byte-kernel comparison from:
- `bench/results/bench-native-byte-path-20260225-174725.json`
- `bench/results/bench-native-byte-path-20260225-174725.meta.json`

Benchmark setup:
- Fixture: `bench/fixtures/english-1mb.txt` (+ generated `english-1mb.u32le.bin` for decode)
- In-process iterations per Hyperfine sample: 128 calls
- Commands compare C ABI NEON path (`turbotoken_encode/decode_utf8_bytes`) vs explicit scalar exports (`turbotoken_encode/decode_utf8_bytes_scalar`)

| Operation | NEON mean | Scalar mean | Speedup |
|---|---:|---:|---:|
| encode UTF-8 bytes (1MB x 128) | 101.2 ms | 414.6 ms | 4.10x |
| decode UTF-8 bytes (1MB x 128) | 102.2 ms | 420.8 ms | 4.12x |

Approx throughput from the same means:
- encode NEON: ~1265.2 MB/s vs scalar ~308.8 MB/s
- decode NEON: ~1251.8 MB/s vs scalar ~304.2 MB/s

---

## Latest Native Pretokenizer Comparison (2026-02-25, macOS ARM64)

Direct non-ASCII byte-count kernel comparison from:
- baseline mode:
  - `bench/results/bench-native-pretokenizer-20260225-174747.json`
  - `bench/results/bench-native-pretokenizer-20260225-174747.meta.json`
- SME auto opt-in mode:
  - `bench/results/bench-native-pretokenizer-sme-auto-20260225-174915.json`
  - `bench/results/bench-native-pretokenizer-sme-auto-20260225-174915.meta.json`

Benchmark setup:
- Fixtures:
  - `bench/fixtures/english-1mb.txt` (`mixed-ascii`)
  - `bench/fixtures/unicode-1mb.txt` (`non-ascii-heavy`)
- In-process iterations per Hyperfine sample: 256 calls
- Commands compare scalar vs explicit NEON vs explicit DotProd kernel and `auto` runtime kernel selection (plus explicit SME when built with `-Dexperimental-sme=true` on SME-capable hardware)
- Runtime auto-selection note: SME is excluded from auto unless `TURBOTOKEN_EXPERIMENTAL_SME_AUTO` is set.
- Current build note: explicit SME kernel was unavailable in this run, so SME rows were skipped.
- Modes are intentionally separate:
  - baseline: `bun run bench:native-pretokenizer`
  - SME auto opt-in: `bun run bench:native-pretokenizer:sme-auto`
  - each mode writes a separate artifact (`bench-native-pretokenizer-*.json` vs `bench-native-pretokenizer-sme-auto-*.json`)

| Operation | Mean | Relative |
|---|---:|---:|
| count non-ascii unicode-1mb NEON | 119.1 ms | baseline |
| count non-ascii unicode-1mb auto | 120.8 ms | 1.01x slower |
| count non-ascii english-1mb NEON | 122.5 ms | 1.03x slower |
| count non-ascii english-1mb auto | 123.8 ms | 1.04x slower |
| count non-ascii english-1mb DotProd | 134.7 ms | 1.13x slower |
| count non-ascii unicode-1mb DotProd | 136.1 ms | 1.14x slower |
| count non-ascii english-1mb scalar | 418.5 ms | 3.51x slower |
| count non-ascii unicode-1mb scalar | 418.7 ms | 3.52x slower |

SME tuning note:
- The latest SME pass (4x streaming-vector unroll + prefetch in `asm/arm64/sme_pretokenizer.S`) improved micro-kernel throughput, but end-to-end Hyperfine means still vary across runs by roughly `~7-11 ms`; treat sub-2% deltas as noise unless confirmed by repeated quiet-system runs.
- In the separate `sme-auto` artifact above, auto-dispatch remained NEON-leaning and did not show a stable auto-route win.

Runtime dispatch probe (same build):
- `turbotoken_arm64_feature_mask() = 4095` (`NEON/FP16/DotProd/BF16/I8MM/AES+PMULL/SHA3/LSE/LSE2/SME/SME2`)
- `turbotoken_count_non_ascii_kernel_id() = 1` (`NEON` selected by auto-tune)

---

## Latest Metal Byte-Path Comparison (2026-02-25, macOS ARM64)

Experimental Metal backend benchmark from:
- `bench/results/bench-gpu-20260225-174823.json`
- `bench/results/bench-gpu-20260225-174823.meta.json`

Benchmark setup:
- Encode fixture: `bench/fixtures/english-1mb.txt`
- Count fixture: `bench/fixtures/english-1kb.txt` batched to `4096` segments
- In-process iterations per Hyperfine sample:
  - encode path: `128`
  - batch count path: `512`

| Operation | Mean | Relative |
|---|---:|---:|
| Metal encode UTF-8 bytes (1MB x 128) | 168.6 ms | baseline (metal encode) |
| Native NEON encode UTF-8 bytes (1MB x 128) | 102.1 ms | 1.65x faster than metal encode |
| Metal count non-zero batch (4096 x 1KB, x512 loops) | 222.5 ms | baseline (metal batch count) |
| Python CPU count non-zero batch (4096 x 1KB, x512 loops) | 736.2 ms | 3.31x slower than metal batch count |

Notes:
- This measures experimental Metal kernels and routing only.
- Full-piece GPU BPE merge path is currently capped to small inputs by default (`TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES=16384`) and larger pieces fall back to chunk/native-verified paths.
- Additional first-pass GPU optimization trials on 2026-02-25 (wide-load encode variants plus BPE loop dispatch/min-rank changes) regressed crossover means and were rolled back as-is:
  - `bench/results/bench-gpu-20260225-182512.json`
  - `bench/results/bench-gpu-crossover-1772043937345.json`
  - `bench/results/bench-gpu-20260225-182816.json`
  - `bench/results/bench-gpu-crossover-1772044096004.json`

---

## Latest Metal Crossover Matrix (2026-02-25, macOS ARM64)

Matrix benchmark from:
- standard: `bench/results/bench-gpu-crossover-1772041537394.json`
- run command: `bun run scripts/bench-gpu-crossover.ts`
- default: `TURBOTOKEN_BENCH_LONG=0` (long mode disabled)
- optional long-run row (adds `10,485,760` bytes/chars): `TURBOTOKEN_BENCH_LONG=1 bun run scripts/bench-gpu-crossover.ts` (not run in this pass)

Outputs include:
- size/batch crossover rows for Metal vs native/Python baselines
- auto-route backend decisions
- per-run low-level profile counters (CPU ns + GPU ns + dispatch geometry)
- persisted auto-route thresholds in `~/.cache/turbotoken/metal/autoroute-v1.json`
  - cache payload schema version: `4`
- long-mode metadata (`long_mode.enabled`, `bench_sizes`) for reproducible optional heavy runs

Current calibration summary on this machine:
- encode auto-route threshold: effectively "never Metal" for byte encode (`2^60` bytes sentinel)
- count auto-route threshold: effectively "never Metal" for current non-zero count benchmark (`2^60` bytes sentinel)
- bpe auto-route threshold: effectively "never Metal" for current long-piece BPE benchmark (`2^60` bytes sentinel)
- practical implication: current byte-path Metal kernels are useful infrastructure, but auto-route still stays on native/Python paths at current calibration gates.

Added BPE crossover rows (`o200k_base`, long `"a"*N` inputs):

| Input Size | CPU encode | `encode_gpu(device="auto", strict_verify=False)` | `encode_gpu(device="metal", strict_verify=False)` | Correctness |
|---|---:|---:|---:|---|
| 65,536 chars | 147.7 ms | 147.0 ms | 152.1 ms | auto matches baseline, metal matches baseline |
| 262,144 chars | 582.0 ms | 583.5 ms | 596.7 ms | auto matches baseline, metal matches baseline |
| 1,048,576 chars | 2470.3 ms | 2483.9 ms | 2474.2 ms | auto matches baseline, metal matches baseline |

---

## Baseline Measurements (Competitors)

> Measured on our M4 Max. These are the numbers to beat.
> Status: `PENDING` -- will be filled when we run initial baselines.

### Python Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | 1MB | Source |
|-----------|-----|------|-------|-----|--------|
| tiktoken (latest) | PENDING | PENDING | PENDING | PENDING | `pip install tiktoken` |
| rs-bpe | PENDING | PENDING | PENDING | PENDING | `pip install rs-bpe` |
| TokenDagger | PENDING | PENDING | PENDING | PENDING | `pip install token-dagger` |
| HuggingFace tokenizers | PENDING | PENDING | PENDING | PENDING | `pip install tokenizers` |
| turbotoken (scalar) | PENDING | PENDING | PENDING | PENDING | Our Zig scalar fallback |
| turbotoken (NEON) | PENDING | PENDING | PENDING | PENDING | Our ARM64 NEON |
| turbotoken (Metal GPU) | PENDING | PENDING | PENDING | PENDING | Phase 2 |

### Python Tokenizers (decode, o200k_base)

| Competitor | 1K tok | 10K tok | 128K tok | Source |
|-----------|--------|---------|----------|--------|
| tiktoken | PENDING | PENDING | PENDING | |
| rs-bpe | PENDING | PENDING | PENDING | |
| TokenDagger | PENDING | PENDING | PENDING | |
| turbotoken (NEON) | PENDING | PENDING | PENDING | |

### Python Tokenizers (count-only, o200k_base)

| Competitor | 1KB | 100KB | 673K tok equiv | Source |
|-----------|-----|-------|----------------|--------|
| tiktoken (via `len(encode())`) | PENDING | PENDING | PENDING | |
| turbotoken `count()` | PENDING | PENDING | PENDING | No-alloc fast path |

### JavaScript/WASM Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | Runtime | WASM Size | Source |
|-----------|-----|------|-------|---------|-----------|--------|
| tiktoken (npm, WASM) | PENDING | PENDING | PENDING | Node.js | PENDING | `npm install tiktoken` |
| gpt-tokenizer | PENDING | PENDING | PENDING | Node.js | N/A (pure JS) | `npm install gpt-tokenizer` |
| wasm-tokenizer | PENDING | PENDING | PENDING | Node.js | PENDING | `npm install wasm-tokenizer` |
| turbotoken (Zig WASM scalar) | PENDING | PENDING | PENDING | Node.js | PENDING | Phase 3 |
| turbotoken (Zig WASM SIMD) | PENDING | PENDING | PENDING | Node.js | PENDING | Phase 3 |
| turbotoken (N-API native) | PENDING | PENDING | PENDING | Node.js | N/A | Phase 3 |

### Startup Latency (time to first encode of "hello")

| Competitor | Cold Start | Warm Start | Notes |
|-----------|-----------|-----------|-------|
| tiktoken (Python) | PENDING | PENDING | Rust extension load + merge table |
| turbotoken (Python) | PENDING | PENDING | Zig library load + merge table |
| tiktoken (npm) | PENDING | PENDING | WASM instantiation |
| turbotoken (npm WASM) | PENDING | PENDING | Zig WASM instantiation |
| turbotoken CLI | PENDING | PENDING | Native binary startup |

### Memory Usage (Peak RSS during o200k_base encode of 1MB)

| Competitor | Peak RSS | Delta over baseline | Notes |
|-----------|----------|-------------------|-------|
| Python baseline (empty) | PENDING | -- | `python3 -c "pass"` |
| tiktoken | PENDING | PENDING | |
| turbotoken | PENDING | PENDING | Target: <12MB for o200k_base |

### Binary / Package Size

| Artifact | tiktoken | turbotoken | Notes |
|----------|----------|-----------|-------|
| Python wheel (macOS ARM64) | PENDING | PENDING | Target: <500KB |
| Python wheel (Linux x86_64) | PENDING | PENDING | |
| npm package (WASM) | PENDING | PENDING | Target: <200KB WASM |
| npm package (total) | PENDING | PENDING | |
| CLI binary (macOS ARM64) | N/A | PENDING | |

---

## Benchmark Dimensions Checklist

Track which benchmarks have been run. Each cell = `PENDING` | `DONE` | `N/A`.

### By Input Size

| Size | tiktoken | rs-bpe | TokenDagger | HF tokenizers | turbotoken scalar | turbotoken NEON | turbotoken Metal | turbotoken WASM |
|------|----------|--------|-------------|---------------|-------------------|-----------------|------------------|-----------------|
| 1KB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| 10KB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| 100KB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| 1MB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |
| 10MB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### By Input Type

| Type | tiktoken | turbotoken NEON | Notes |
|------|----------|-----------------|-------|
| English prose | PENDING | PENDING | Wikipedia article |
| Python code | PENDING | PENDING | Real source file |
| JavaScript code | PENDING | PENDING | Real source file |
| Rust code | PENDING | PENDING | Real source file |
| CJK text | PENDING | PENDING | Japanese + Chinese mixed |
| Emoji-heavy | PENDING | PENDING | Slack/Discord messages |
| Random bytes | PENDING | PENDING | Adversarial / worst case |
| Repeated chars | PENDING | PENDING | `"a" * 1_000_000` |

### By Concurrency (batch encode, 1K strings of 1KB each)

| Threads | tiktoken | turbotoken CPU | turbotoken Metal GPU |
|---------|----------|---------------|---------------------|
| 1 | PENDING | PENDING | N/A |
| 2 | PENDING | PENDING | N/A |
| 4 | PENDING | PENDING | N/A |
| 8 | PENDING | PENDING | N/A |
| 16 | PENDING | PENDING | N/A |
| GPU | N/A | N/A | PENDING |

### By Encoding

| Encoding | tiktoken encode 100KB | turbotoken encode 100KB | Speedup |
|----------|----------------------|------------------------|---------|
| o200k_base | PENDING | PENDING | PENDING |
| cl100k_base | PENDING | PENDING | PENDING |
| p50k_base | PENDING | PENDING | PENDING |
| r50k_base | PENDING | PENDING | PENDING |

---

## Benchmark Results History

> Append new results here as they're generated. Each entry includes date, git SHA, and machine.

### [Template -- copy for each benchmark run]

```
Date: YYYY-MM-DD
Git SHA: xxxxxxx
Machine: Apple M4 Max / 128GB
Backend: neon | scalar | metal | wasm | avx2 | cuda
Script: scripts/bench-encode.ts

[Paste Hyperfine markdown table output here]

Notes:
- Any relevant observations
```

---

## Performance Targets vs Actuals

| Operation | Target | Actual | Met? | Date | Git SHA |
|-----------|--------|--------|------|------|---------|
| encode 1KB (NEON) | <0.025ms | -- | -- | -- | -- |
| encode 100KB (NEON) | <2.5ms | -- | -- | -- | -- |
| encode 673K tok (NEON) | <46ms | -- | -- | -- | -- |
| decode 1K tok (NEON) | <0.0005ms | -- | -- | -- | -- |
| decode 128K tok (NEON) | <0.06ms | -- | -- | -- | -- |
| count 673K tok (NEON) | <35ms | -- | -- | -- | -- |
| batch 1K strings CPU (NEON) | <25ms | -- | -- | -- | -- |
| batch 1K strings Metal GPU | <5ms | -- | -- | -- | -- |
| binary size wheel | <500KB | -- | -- | -- | -- |
| WASM binary size | <200KB | -- | -- | -- | -- |
| startup to first encode | <5ms | -- | -- | -- | -- |
| peak RAM o200k_base | <12MB | -- | -- | -- | -- |

---

## Cross-Platform Results

> Filled as we test on different hardware.

### macOS ARM64 (M4 Max) -- Primary

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | PENDING | PENDING | PENDING | -- |
| decode 128K tok | PENDING | PENDING | PENDING | -- |

### Linux ARM64 (Graviton3)

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | PENDING | PENDING | PENDING | -- |
| decode 128K tok | PENDING | PENDING | PENDING | -- |

### Linux x86_64 (AVX2)

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | PENDING | PENDING | PENDING | -- |
| decode 128K tok | PENDING | PENDING | PENDING | -- |

### WASM (Chrome V8 / Node.js)

| Operation | tiktoken.js | gpt-tokenizer | wasm-tokenizer | turbotoken WASM | Date |
|-----------|------------|---------------|----------------|-----------------|------|
| encode 100KB | PENDING | PENDING | PENDING | PENDING | -- |

### NVIDIA GPU (RTX 4090)

| Operation | Batch Size | turbotoken CUDA | Per-string | Date |
|-----------|-----------|-----------------|------------|------|
| encode batch | 1K | PENDING | PENDING | -- |
| encode batch | 10K | PENDING | PENDING | -- |
