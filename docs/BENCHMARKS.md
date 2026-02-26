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
| Python | 3.14.x |
| Node.js | 22.x LTS |
| Bun | 1.x |

Local benchmark host details (from `sysctl` / `uname`):
- model identifier: `Mac16,5`
- kernel / arch: `Darwin 25.3.0` / `arm64` (`AArch64`)
- ISA features detected: NEON/AdvSIMD, FP16, DotProd, BF16, I8MM, SHA3/AES/PMULL, LSE/LSE2, SME/SME2 (current hot path uses AdvSIMD/NEON instructions)

> Additional machines will be added as we benchmark on Graviton, x86, RISC-V, etc.

---

## Latest Measured Run (2026-02-26, macOS ARM64)

This is the latest full `bench-all` pass after decode + ASCII-path optimization loops. Artifacts:

- `bench/results/bench-startup-cold-20260226-104547.json`
- `bench/results/bench-count-20260226-104658.json`
- `bench/results/bench-encode-20260226-104702.json`
- `bench/results/bench-bigfile-20260226-104721.json`
- `bench/results/bench-comparison-20260226-104730.json`
- `bench/results/bench-competitors-python-encode-20260226-104738.json`
- `bench/results/bench-competitors-python-decode-20260226-104857.json`
- `bench/results/bench-competitors-python-count-20260226-104947.json`
- `bench/results/bench-training-python-20260226-105038.json`

| Workload | Mean |
|---|---:|
| startup (import + first encode) | 61.5 ms |
| count 100KB | 44.6 ms |
| encode 100KB | 40.8 ms |
| encode 1MB | 68.4 ms |

Comparison (`bench-comparison-20260226-104730.json`):
- turbotoken encode 100KB: 40.1 ms
- tiktoken encode 100KB: 202.5 ms
- turbotoken ran ~5.05x faster on this workload in this run.

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

## Latest ASCII Boundary Classifier (2026-02-26, macOS ARM64)

Experimental boundary-classification benchmark from:
- `bench/results/bench-boundary-classifier-20260226-105327.json`
- run command: `bun run scripts/bench-boundary-classifier.ts`

| Operation | Auto mean | Scalar mean | Relative |
|---|---:|---:|---:|
| boundary-class english-1mb | 1.586 s | 2.776 s | auto ~1.75x faster |
| boundary-class unicode-1mb | 1.632 s | 3.556 s | auto ~2.18x faster |

Note:
- This is a new additive pretokenizer primitive (`count_ascii_class_boundaries`), not a replacement of the core BPE path.

---

## Latest Native Byte-Path Comparison (2026-02-26, macOS ARM64)

Direct ARM64 byte-kernel comparison from:
- `bench/results/bench-native-byte-path-20260226-105615.json`
- `bench/results/bench-native-byte-path-20260226-105615.meta.json`

Benchmark setup:
- Fixture: `bench/fixtures/english-1mb.txt` (+ generated `english-1mb.u32le.bin` for decode)
- In-process iterations per Hyperfine sample: 128 calls
- Commands compare C ABI NEON path (`turbotoken_encode/decode_utf8_bytes`) vs explicit scalar exports (`turbotoken_encode/decode_utf8_bytes_scalar`)

| Operation | NEON mean | Scalar mean | Speedup |
|---|---:|---:|---:|
| encode UTF-8 bytes (1MB x 128) | 75.5 ms | 376.9 ms | 4.99x |
| decode UTF-8 bytes (1MB x 128) | 72.9 ms | 387.0 ms | 5.31x |

Approx throughput from the same means:
- encode NEON: ~1694.5 MB/s vs scalar ~339.6 MB/s
- decode NEON: ~1756.4 MB/s vs scalar ~331.1 MB/s

---

## Latest Native Pretokenizer Comparison (2026-02-26, macOS ARM64)

Direct non-ASCII byte-count kernel comparison from:
- baseline mode:
  - `bench/results/bench-native-pretokenizer-20260226-105256.json`
  - `bench/results/bench-native-pretokenizer-20260226-105256.meta.json`

Benchmark setup:
- Fixtures:
  - `bench/fixtures/english-1mb.txt` (`mixed-ascii`)
  - `bench/fixtures/unicode-1mb.txt` (`non-ascii-heavy`)
- In-process iterations per Hyperfine sample: 256 calls
- Commands compare scalar vs explicit NEON vs explicit DotProd kernel and `auto` runtime kernel selection (plus explicit SME when built with `-Dexperimental-sme=true` on SME-capable hardware)
- Runtime auto-selection note: SME is excluded from auto unless `TURBOTOKEN_EXPERIMENTAL_SME_AUTO` is set.
- Current build note: explicit SME kernel was unavailable in this run, so SME rows were skipped.

| Operation | Mean | Relative |
|---|---:|---:|
| count non-ascii english-1mb NEON | 94.0 ms | baseline |
| count non-ascii unicode-1mb NEON | 94.7 ms | 1.01x slower |
| count non-ascii english-1mb auto | 95.1 ms | 1.01x slower |
| count non-ascii unicode-1mb auto | 95.2 ms | 1.01x slower |
| count non-ascii english-1mb DotProd | 103.1 ms | 1.10x slower |
| count non-ascii unicode-1mb DotProd | 108.5 ms | 1.15x slower |
| count non-ascii unicode-1mb scalar | 391.8 ms | 4.17x slower |
| count non-ascii english-1mb scalar | 392.5 ms | 4.18x slower |

SME tuning note:
- The latest SME pass (4x streaming-vector unroll + prefetch in `asm/arm64/sme_pretokenizer.S`) improved micro-kernel throughput, but end-to-end Hyperfine means still vary across runs by roughly `~7-11 ms`; treat sub-2% deltas as noise unless confirmed by repeated quiet-system runs.
- In the separate `sme-auto` artifact above, auto-dispatch remained NEON-leaning and did not show a stable auto-route win.

Runtime dispatch probe (same build):
- `turbotoken_arm64_feature_mask() = 4095` (`NEON/FP16/DotProd/BF16/I8MM/AES+PMULL/SHA3/LSE/LSE2/SME/SME2`)
- `turbotoken_count_non_ascii_kernel_id() = 1` (`NEON` selected by auto-tune)

---

## Latest Metal Byte-Path Comparison (2026-02-26, macOS ARM64)

Experimental Metal backend benchmark from:
- `bench/results/bench-gpu-20260226-105646.json`
- `bench/results/bench-gpu-20260226-105646.meta.json`

Benchmark setup:
- Encode fixture: `bench/fixtures/english-1mb.txt`
- Count fixture: `bench/fixtures/english-1kb.txt` batched to `4096` segments
- In-process iterations per Hyperfine sample:
  - encode path: `128`
  - batch count path: `512`

| Operation | Mean | Relative |
|---|---:|---:|
| Metal encode UTF-8 bytes (1MB x 128) | 161.7 ms | baseline (metal encode) |
| Native NEON encode UTF-8 bytes (1MB x 128) | 74.7 ms | 2.16x faster than metal encode |
| Hybrid NEON+Metal encode UTF-8 bytes (1MB x 128) | 165.4 ms | 1.02x slower than metal encode |
| Metal count non-zero batch (4096 x 1KB, x512 loops) | 228.8 ms | baseline (metal batch count) |
| Python CPU count non-zero batch (4096 x 1KB, x512 loops) | 738.9 ms | 3.23x slower than metal batch count |

Notes:
- This measures experimental Metal kernels and routing only.
- Full-piece GPU BPE merge path is currently capped to small inputs by default (`TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES=16384`) and larger pieces fall back to chunk/native-verified paths.
- Throughput equivalents from the same run:
  - encode: native NEON ~1714.1 MiB/s, metal ~792.2 MiB/s, hybrid ~774.8 MiB/s
  - batch count (aggregate): metal ~8952.0 MiB/s vs Python CPU ~2772.9 MiB/s
- Current conclusion on parallel CPU+GPU split for byte-path: this hybrid was slower than pure NEON and pure metal on this machine/workload.
- Additional first-pass GPU optimization trials on 2026-02-25 (wide-load encode variants plus BPE loop dispatch/min-rank changes) regressed crossover means and were rolled back as-is:
  - `bench/results/bench-gpu-20260225-182512.json`
  - `bench/results/bench-gpu-crossover-1772043937345.json`
  - `bench/results/bench-gpu-20260225-182816.json`
  - `bench/results/bench-gpu-crossover-1772044096004.json`

---

## Latest Metal Crossover Matrix (2026-02-26, macOS ARM64)

Matrix benchmark from:
- standard: `bench/results/bench-gpu-crossover-1772103430630.json`
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
| 65,536 chars | 0.126 ms | 133.8 ms | 438.8 ms | auto matches baseline, metal matches baseline |
| 262,144 chars | 0.482 ms | 571.1 ms | 1813.6 ms | auto matches baseline, metal matches baseline |
| 1,048,576 chars | 1.948 ms | 2521.4 ms | 7229.5 ms | auto matches baseline, metal matches baseline |

---

## Baseline Measurements (Competitors)

> Measured on our M4 Max. These are the numbers to beat.
> Status: `PARTIAL` -- Python competitor + startup + memory rows are now measured; JS/WASM rows remain pending.

Artifacts for this pass:
- `bench/results/bench-competitors-stable-20260226-104538.json` (3-pass median summary)
- pass files:
  - `bench/results/bench-competitors-python-encode-20260226-103633.json`
  - `bench/results/bench-competitors-python-decode-20260226-103754.json`
  - `bench/results/bench-competitors-python-count-20260226-103844.json`
  - `bench/results/bench-competitors-python-encode-20260226-103936.json`
  - `bench/results/bench-competitors-python-decode-20260226-104057.json`
  - `bench/results/bench-competitors-python-count-20260226-104146.json`
  - `bench/results/bench-competitors-python-encode-20260226-104238.json`
  - `bench/results/bench-competitors-python-decode-20260226-104357.json`
  - `bench/results/bench-competitors-python-count-20260226-104448.json`
- commands:
  - `bun run scripts/bench-competitors.ts`
  - `bun run bench:competitors:stable`
Training baseline artifacts:
- `bench/results/bench-training-python-20260226-105038.json` (english-100kb, vocab=320)
- command: `bun run bench:training`
Startup + memory artifacts:
- `bench/results/bench-startup-cold-20260226-104547.json`
- `bench/results/bench-startup-warm-20260226-104618.json`
- `bench/results/bench-ram-1772103399585.json`
Encoding matrix artifact:
- `bench/results/bench-encoding-matrix-1772093253.json`
Wheel build artifact:
- `dist/wheels/build-wheels-1772103454490.json`

### Python Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | 1MB | 1MB Throughput (MiB/s) | Source |
|-----------|-----|------|-------|-----|------------------------|--------|
| tiktoken (latest) | 213.9 ms | 211.2 ms | 220.6 ms | 277.6 ms | 3.60 | `pip install tiktoken` |
| rs-bpe | 71.7 ms | 72.1 ms | 71.8 ms | 91.0 ms | 10.99 | `pip install rs-bpe` |
| TokenDagger (`tokendagger`) | 479.6 ms | 470.8 ms | 473.4 ms | 510.1 ms | 1.96 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| HuggingFace tokenizers | PENDING | PENDING | PENDING | PENDING | PENDING | `tokenizers` package installed, but no stable built-in `o200k_base` entry-point |
| turbotoken (default CPU path) | 64.8 ms | 40.4 ms | 43.8 ms | 75.1 ms | 13.32 | local editable package (`python/`) |
| turbotoken (Metal GPU route) | 106.0 ms | 96.0 ms | 118.7 ms | 191.4 ms | 5.22 | `Encoding.encode_gpu(device="metal", strict_verify=False)` |

### Python Tokenizers (decode, o200k_base)

| Competitor | 1K tok | 10K tok | 128K tok | Source |
|-----------|--------|---------|----------|--------|
| tiktoken | 217.3 ms | 219.8 ms | 213.9 ms | `tiktoken.get_encoding("o200k_base").decode(...)` |
| rs-bpe | 82.8 ms | 80.9 ms | 83.2 ms | `openai.o200k_base().decode(...)` |
| TokenDagger (`tokendagger`) | 492.2 ms | 489.4 ms | 500.2 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken (default CPU path) | 68.4 ms | 68.8 ms | 71.6 ms | `turbotoken.get_encoding("o200k_base").decode(...)` |

### Python Tokenizers (count-only, o200k_base)

| Competitor | 1KB | 100KB | 673K tok equiv | 1MB Throughput (MiB/s) | Source |
|-----------|-----|-------|----------------|------------------------|--------|
| tiktoken (via `len(encode())`) | 215.2 ms | 217.1 ms | 277.7 ms | 3.60 | `len(encode())` |
| rs-bpe `count()` | 71.2 ms | 73.7 ms | 85.5 ms | 11.69 | `openai.o200k_base().count(...)` |
| TokenDagger (`tokendagger`, via `len(encode())`) | 478.9 ms | 495.9 ms | 479.5 ms | 2.09 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken `count()` | 65.1 ms | 41.8 ms | 71.4 ms | 14.00 | No-alloc fast path |

### Python BPE Training (regex+BPE trainer, vocab size 320)

| Corpus | turbotoken (Python backend) | turbotoken (Zig native backend prototype) | rustbpe | minbpe |
|---|---:|---:|---:|---:|
| english-100kb | 50.0 ms (1.95 MiB/s) | 47.3 ms (2.06 MiB/s) | 55.4 ms (1.76 MiB/s) | 696.6 ms (0.14 MiB/s) |

Notes:
- `turbotoken` training API is now available via `train_mergeable_ranks_from_iterator(...)` and `train_encoding_from_iterator(...)`.
- backend routing:
  - default: `TURBOTOKEN_TRAINING_BACKEND=auto` (currently prefers Python path for throughput in this environment)
  - force native prototype: `TURBOTOKEN_TRAINING_BACKEND=native`
  - force Python fallback: `TURBOTOKEN_TRAINING_BACKEND=python`
- native-experimental toggles:
  - `TURBOTOKEN_TRAIN_NATIVE_PRETOKENIZE=1` enables native ASCII O200K range splitting before chunk counting
  - `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1` enables direct native ASCII O200K `text -> train` path for single-text list inputs
  - both remain opt-in because current benchmark rows above did not improve with these toggles enabled
  - latest direct-path artifacts:
    - `bench/results/bench-training-python-20260225-233812.json` (100kb)
    - `bench/results/bench-training-python-20260225-234514.json` (1mb)
- `minbpe` was benchmarked from local source checkout (`/tmp/minbpe`) because it is not published on PyPI.
- In this pass, turbotoken training leads `rustbpe` on the measured 100KB corpus (`~1.11x` for native prototype and `~1.06x` for Python fallback).

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
| tiktoken (Python) | 206.1 ms | 204.1 ms | Rust extension load + merge table |
| rs-bpe (Python) | 68.7 ms | 62.9 ms | `openai.o200k_base().encode("hello")` |
| turbotoken (Python) | 61.5 ms | 65.3 ms | local editable package (`python/`) |
| TokenDagger (`tokendagger`) | 480.0 ms | 482.6 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| tiktoken (npm) | PENDING | PENDING | WASM instantiation |
| turbotoken (npm WASM) | PENDING | PENDING | Zig WASM instantiation |
| turbotoken CLI | 94.5 ms | 91.6 ms | `python -m turbotoken.cli encode hello --encoding o200k_base` |

Notes:
- cold artifact: `bench/results/bench-startup-cold-20260226-104547.json`
- warm artifact: `bench/results/bench-startup-warm-20260226-104618.json`
- warm mode here means same command measured after Hyperfine warmup (`--warmup 10`), not a long-lived daemon process.

### Memory Usage (Peak RSS during o200k_base encode of 1MB)

| Competitor | Peak RSS | Delta over baseline | Notes |
|-----------|----------|-------------------|-------|
| Python baseline (empty) | 14.45 MB | -- | `python3 -c "pass"` |
| tiktoken | 114.58 MB | +100.12 MB | `tiktoken.get_encoding("o200k_base").encode(text)` |
| rs-bpe | 90.41 MB | +75.95 MB | `openai.o200k_base().encode(text)` |
| TokenDagger (`tokendagger`) | 241.94 MB | +227.49 MB | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken | 31.22 MB | +16.77 MB | `turbotoken.get_encoding("o200k_base").encode(text)` |
| turbotoken CLI | 39.69 MB | +25.24 MB | `python -m turbotoken.cli encode - --encoding o200k_base` |

Notes:
- artifact: `bench/results/bench-ram-1772103399585.json`
- each row is median peak RSS across 5 runs (`TURBOTOKEN_RAM_RUNS=5` default)

### Binary / Package Size

| Artifact | tiktoken | turbotoken | Notes |
|----------|----------|-----------|-------|
| Python wheel (macOS ARM64) | 993,978 B | 1,331,143 B | tiktoken from `pip download --no-deps tiktoken`; turbotoken from `dist/wheels/turbotoken-0.1.0.dev0-py3-none-macosx_11_0_arm64.whl` |
| Python wheel (Linux x86_64) | 1,183,308 B | 3,234,620 B | tiktoken from `pip download --no-deps --only-binary=:all: --platform manylinux2014_x86_64 --python-version 312 --implementation cp --abi cp312 tiktoken`; turbotoken from `dist/wheels/turbotoken-0.1.0.dev0-py3-none-manylinux_2_17_x86_64.whl` (fixed in `dist/wheels/build-wheels-1772103454490.json`) |
| npm package (WASM) | 5,593,287 B (`package/tiktoken_bg.wasm`) | PENDING | extracted from `npm pack tiktoken@1.0.22`; target: <200KB WASM |
| npm package (total) | 23,587,949 B (unpacked) | PENDING | `npm view tiktoken dist.unpackedSize`; turbotoken npm package pending |
| CLI binary (macOS ARM64) | N/A | PENDING | |

---

## Benchmark Dimensions Checklist

Track which benchmarks have been run. Each cell = `PENDING` | `DONE` | `N/A`.

### By Input Size

| Size | tiktoken | rs-bpe | TokenDagger | HF tokenizers | turbotoken scalar | turbotoken NEON | turbotoken Metal | turbotoken WASM |
|------|----------|--------|-------------|---------------|-------------------|-----------------|------------------|-----------------|
| 1KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 10KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 100KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 1MB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
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

| Encoding | tiktoken encode 100KB | tiktoken MiB/s | turbotoken encode 100KB | turbotoken MiB/s | Speedup |
|----------|----------------------|----------------|------------------------|------------------|---------|
| o200k_base | 200.6 ms | 0.49 | 39.5 ms | 2.47 | 5.08x |
| cl100k_base | 133.1 ms | 0.73 | 40.6 ms | 2.41 | 3.28x |
| p50k_base | 103.8 ms | 0.94 | 55.8 ms | 1.75 | 1.86x |
| r50k_base | 104.9 ms | 0.93 | 56.8 ms | 1.72 | 1.85x |

Encoding matrix artifact:
- `bench/results/bench-encoding-matrix-1772093253.json`

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
