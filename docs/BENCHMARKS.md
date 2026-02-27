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
1. **Core local benchmarks are reproducible** via `bun run scripts/bench-all.ts` (`bun run bench`)
   - CUDA rows are opt-in via `bun run bench:cuda`
   - Paid Modal CUDA runs are opt-in via `bun run bench:modal:cuda`
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

## Latest Measured Run (2026-02-27, macOS ARM64)

This is the latest full default `bench-all` pass (`bun run bench`, CUDA skipped by default). Artifacts:

- `bench/results/bench-startup-cold-20260227-145147.json`
- `bench/results/bench-startup-warm-20260227-145218.json`
- `bench/results/bench-count-20260227-145300.json`
- `bench/results/bench-encode-20260227-145305.json`
- `bench/results/bench-decode-20260227-145309.json`
- `bench/results/bench-bigfile-20260227-145324.json`
- `bench/results/bench-parallel-20260227-145329.json`
- `bench/results/bench-comparison-20260227-145334.json`
- `bench/results/bench-competitors-python-encode-20260227-145342.json`
- `bench/results/bench-competitors-python-decode-20260227-145503.json`
- `bench/results/bench-competitors-python-count-20260227-145553.json`
- `bench/results/bench-training-python-20260227-145645.json`

| Workload | Mean |
|---|---:|
| startup cold (import + first encode) | 64.4 ms |
| startup warm | 64.1 ms |
| count 100KB | 44.5 ms |
| encode 100KB | 46.1 ms |
| decode 100KB-equivalent | 59.7 ms |
| encode 1MB | 72.4 ms |
| parallel count (512 items, 4 workers) | 206.0 ms |

Comparison (`bench-comparison-20260227-145334.json`):
- turbotoken encode 100KB: 43.4 ms
- tiktoken encode 100KB: 215.9 ms
- turbotoken ran ~4.98x faster on this workload in this run.

---

## Latest Pair-Cache Hash A/B (2026-02-27, macOS ARM64)

Direct hash strategy comparison from:
- `bench/results/bench-pair-cache-hash-20260227-145710.json`
- run command: `bun run scripts/bench-pair-cache-hash.ts`
- env switch used per row: `TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`

| Operation | `rapidhash` mean | `crc32` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 148.1 ms | 162.6 ms | rapidhash ~8.9% faster in this run |
| native encode BPE 100KB | 158.7 ms | 159.3 ms | rapidhash ~0.4% faster in this run |

Decision for now:
- default remains `crc32` on AArch64+CRC and `rapidhash` on other targets.
- keep both explicit overrides for A/B checks (`TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`).
- this 100KB pass favors `rapidhash`; larger-file A/B still favors the current default policy.

---

## Latest Encoder Queue A/B (2026-02-27, macOS ARM64)

Direct queue strategy comparison from:
- `bench/results/bench-encoder-queue-20260227-145729.json`
- run command: `bun run scripts/bench-encoder-queue.ts`
- env switch used per row: `TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket`

| Operation | `hybrid` mean | `full-bucket` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 146.4 ms | 142.6 ms | full-bucket ~2.6% faster |
| native encode BPE 100KB | 162.0 ms | 152.8 ms | full-bucket ~5.7% faster |

Decision for now:
- switched default queue mode to `full-bucket` (env var unset) in `src/encoder.zig`.
- keep explicit override controls (`TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket`).
- latest full-pass scalar fallback (`bench/results/bench-scalar-fallback-20260227-145659.json`) remains substantially improved vs pre-switch baseline (`bench/results/bench-scalar-fallback-20260227-131921.json`):
  - native count 100KB: `177.1 ms -> 94.5 ms` (~46.6% faster)
  - native encode 100KB: `223.1 ms -> 106.4 ms` (~52.3% faster)

---

## Latest ASCII Boundary Classifier (2026-02-27, macOS ARM64)

Experimental boundary-classification benchmark from:
- `bench/results/bench-boundary-classifier-20260227-145815.json`
- run command: `bun run scripts/bench-boundary-classifier.ts`

| Operation | Auto mean | Scalar mean | Relative (Auto vs Scalar) |
|---|---:|---:|---:|
| boundary-class english-1mb | 283.2 ms | 775.6 ms | auto ~2.74x faster |
| boundary-class unicode-1mb | 301.5 ms | 802.4 ms | auto ~2.66x faster |

Note:
- This is an additive pretokenizer primitive (`count_ascii_class_boundaries`), not a replacement of the core BPE path.
- In this run, `auto` and explicit NEON are near parity.

---

## Latest Native Byte-Path Comparison (2026-02-27, macOS ARM64)

Direct ARM64 byte-kernel comparison from:
- `bench/results/bench-native-byte-path-20260227-145853.json`
- `bench/results/bench-native-byte-path-20260227-145853.meta.json`

Benchmark setup:
- Fixture: `bench/fixtures/english-1mb.txt` (+ generated `english-1mb.u32le.bin` for decode)
- In-process iterations per Hyperfine sample: 128 calls
- Commands compare C ABI NEON path (`turbotoken_encode/decode_utf8_bytes`) vs explicit scalar exports (`turbotoken_encode/decode_utf8_bytes_scalar`)

| Operation | NEON mean | Scalar mean | Speedup |
|---|---:|---:|---:|
| encode UTF-8 bytes (1MB x 128) | 81.0 ms | 109.9 ms | 1.36x |
| decode UTF-8 bytes (1MB x 128) | 80.5 ms | 116.7 ms | 1.45x |

Approx throughput from the same means:
- encode NEON: ~1579.5 MiB/s vs scalar ~1164.2 MiB/s
- decode NEON: ~1589.4 MiB/s vs scalar ~1096.9 MiB/s

---

## Latest Native Pretokenizer Comparison (2026-02-27, macOS ARM64)

Direct non-ASCII byte-count kernel comparison from:
- baseline mode:
  - `bench/results/bench-native-pretokenizer-20260227-145747.json`
  - `bench/results/bench-native-pretokenizer-20260227-145747.meta.json`

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
| count non-ascii unicode-1mb NEON | 97.0 ms | baseline |
| count non-ascii english-1mb NEON | 97.3 ms | 1.00x slower |
| count non-ascii english-1mb auto | 99.1 ms | 1.02x slower |
| count non-ascii unicode-1mb auto | 100.0 ms | 1.03x slower |
| count non-ascii english-1mb DotProd | 110.4 ms | 1.14x slower |
| count non-ascii unicode-1mb DotProd | 111.4 ms | 1.15x slower |
| count non-ascii unicode-1mb scalar | 169.3 ms | 1.75x slower |
| count non-ascii english-1mb scalar | 171.4 ms | 1.77x slower |

SME tuning note:
- The latest SME pass (4x streaming-vector unroll + prefetch in `asm/arm64/sme_pretokenizer.S`) improved micro-kernel throughput, but end-to-end Hyperfine means still vary across runs; treat very small deltas as noise unless repeated.

Runtime dispatch probe (same build):
- `turbotoken_arm64_feature_mask() = 4095` (`NEON/FP16/DotProd/BF16/I8MM/AES+PMULL/SHA3/LSE/LSE2/SME/SME2`)
- `turbotoken_count_non_ascii_kernel_id() = 1` (`NEON` selected by auto-tune)

---

## Latest Metal Byte-Path Comparison (2026-02-27, macOS ARM64)

Experimental Metal backend benchmark from:
- `bench/results/bench-gpu-20260227-150010.json`
- `bench/results/bench-gpu-20260227-150010.meta.json`

Benchmark setup:
- Encode fixture: `bench/fixtures/english-1mb.txt`
- Count fixture: `bench/fixtures/english-1kb.txt` batched to `4096` segments
- In-process iterations per Hyperfine sample:
  - encode path: `128`
  - batch count path: `512`

| Operation | Mean | Relative |
|---|---:|---:|
| Metal encode UTF-8 bytes (1MB x 128) | 193.8 ms | baseline (metal encode) |
| Native NEON encode UTF-8 bytes (1MB x 128) | 73.8 ms | 2.63x faster than metal encode |
| Hybrid NEON+Metal encode UTF-8 bytes (1MB x 128) | 170.6 ms | 1.14x faster than metal encode |
| Metal count non-zero batch (4096 x 1KB, x512 loops) | 261.0 ms | baseline (metal batch count) |
| Python CPU count non-zero batch (4096 x 1KB, x512 loops) | 748.7 ms | 2.87x slower than metal batch count |

Notes:
- This measures experimental Metal kernels and routing only.
- Full-piece GPU BPE merge path is currently capped to small inputs by default (`TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES=16384`) and larger pieces fall back to chunk/native-verified paths.
- Throughput equivalents from the same run:
  - encode: native NEON ~1734.1 MiB/s, metal ~660.5 MiB/s, hybrid ~750.3 MiB/s
  - batch count (aggregate): metal ~7845.9 MiB/s vs Python CPU ~2735.5 MiB/s
- Current conclusion on parallel CPU+GPU split for byte-path: this native-bridge hybrid beats pure metal in this run, but remains much slower than pure NEON on this machine/workload.
- Additional first-pass GPU optimization trials on 2026-02-25 (wide-load encode variants plus BPE loop dispatch/min-rank changes) regressed crossover means and were rolled back as-is:
  - `bench/results/bench-gpu-20260225-182512.json`
  - `bench/results/bench-gpu-crossover-1772043937345.json`
  - `bench/results/bench-gpu-20260225-182816.json`
  - `bench/results/bench-gpu-crossover-1772044096004.json`

---

## Latest Metal Crossover Matrix (2026-02-27, macOS ARM64)

Matrix benchmark from:
- standard: `bench/results/bench-gpu-crossover-1772204438191.json`
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
- bpe auto-route threshold: `1,048,576` bytes (auto-route can pick Metal for long-piece BPE at/above this size in current calibration payload)
- practical implication: current byte/count auto-route still stays on native/Python at these gates; BPE now has calibrated rows and an explicit threshold, but remains experimental and workload-sensitive.

Added BPE crossover rows (`o200k_base`, long `"a"*N` inputs):

| Input Size | CPU encode | `encode_gpu(device="auto", strict_verify=False)` | `encode_gpu(device="metal", strict_verify=False)` | Correctness |
|---|---:|---:|---:|---|
| 65,536 chars | 0.124 ms | 1.153 ms | 29.9 ms | auto matches baseline, metal matches baseline |
| 262,144 chars | 0.479 ms | 4.065 ms | 107.0 ms | auto matches baseline, metal matches baseline |
| 1,048,576 chars | 1.930 ms | 105.0 ms | 167.2 ms | auto matches baseline, metal matches baseline |

---

## Baseline Measurements (Competitors)

> Measured on our M4 Max. These are the numbers to beat.
> Status: `PARTIAL` -- Python competitor + startup + memory rows are now measured; JS/WASM rows remain pending.

Artifacts for this pass:
- `bench/results/bench-competitors-python-encode-20260227-145342.json`
- `bench/results/bench-competitors-python-decode-20260227-145503.json`
- `bench/results/bench-competitors-python-count-20260227-145553.json`
- commands:
  - `bun run scripts/bench-competitors.ts`
Training baseline artifacts:
- `bench/results/bench-training-python-20260227-145645.json` (english-100kb, vocab=320)
- command: `bun run bench:training`
Startup + memory artifacts:
- `bench/results/bench-startup-cold-20260227-145147.json`
- `bench/results/bench-startup-warm-20260227-145218.json`
- `bench/results/bench-ram-1772204354545.json`
WASM + binary artifacts:
- `bench/results/bench-wasm-1772204362471.json`
- `bench/results/bench-binary-size-1772204354576.json`
Wheel build artifact:
- `dist/wheels/build-wheels-1772103454490.json`

### Python Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | 1MB | 1MB Throughput (MiB/s) | Source |
|-----------|-----|------|-------|-----|------------------------|--------|
| tiktoken (latest) | 215.9 ms | 220.6 ms | 226.2 ms | 277.7 ms | 3.60 | `pip install tiktoken` |
| rs-bpe | 74.4 ms | 71.6 ms | 77.1 ms | 93.0 ms | 10.75 | `pip install rs-bpe` |
| TokenDagger (`tokendagger`) | 499.7 ms | 507.4 ms | 493.8 ms | 493.6 ms | 2.03 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| HuggingFace tokenizers | PENDING | PENDING | PENDING | PENDING | PENDING | `tokenizers` package installed, but no stable built-in `o200k_base` entry-point |
| turbotoken (default CPU path) | 68.0 ms | 44.1 ms | 45.9 ms | 76.5 ms | 13.08 | local editable package (`python/`) |
| turbotoken (Metal GPU route) | 98.2 ms | 100.3 ms | 123.6 ms | 182.0 ms | 5.50 | `Encoding.encode_gpu(device="metal", strict_verify=False)` |

### Python Tokenizers (decode, o200k_base)

| Competitor | 1K tok | 10K tok | 128K tok | Source |
|-----------|--------|---------|----------|--------|
| tiktoken | 213.5 ms | 225.9 ms | 222.7 ms | `tiktoken.get_encoding("o200k_base").decode(...)` |
| rs-bpe | 82.2 ms | 85.0 ms | 84.2 ms | `openai.o200k_base().decode(...)` |
| TokenDagger (`tokendagger`) | 493.5 ms | 497.3 ms | 511.0 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken (default CPU path) | 66.1 ms | 69.9 ms | 77.9 ms | `turbotoken.get_encoding("o200k_base").decode(...)` |

### Python Tokenizers (count-only, o200k_base)

| Competitor | 1KB | 100KB | 1MB | 1MB Throughput (MiB/s) | Source |
|-----------|-----|-------|----------------|------------------------|--------|
| tiktoken (via `len(encode())`) | 213.9 ms | 221.4 ms | 280.5 ms | 3.56 | `len(encode())` |
| rs-bpe `count()` | 71.3 ms | 73.9 ms | 87.0 ms | 11.50 | `openai.o200k_base().count(...)` |
| TokenDagger (`tokendagger`, via `len(encode())`) | 486.9 ms | 490.4 ms | 499.3 ms | 2.00 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken `count()` | 67.1 ms | 45.0 ms | 71.0 ms | 14.09 | No-alloc fast path |

### Python BPE Training (regex+BPE trainer, vocab size 320)

| Corpus | turbotoken (Python backend) | turbotoken (Zig native backend prototype) | rustbpe | minbpe |
|---|---:|---:|---:|---:|
| english-100kb | 49.1 ms (1.99 MiB/s) | 49.4 ms (1.98 MiB/s) | 55.7 ms (1.75 MiB/s) | 703.2 ms (0.14 MiB/s) |

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
- In this pass, both turbotoken training backends lead `rustbpe` on the measured 100KB corpus.

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
| tiktoken (Python) | 210.4 ms | 208.5 ms | Rust extension load + merge table |
| rs-bpe (Python) | 68.1 ms | 66.1 ms | `openai.o200k_base().encode("hello")` |
| turbotoken (Python) | 64.4 ms | 64.1 ms | local editable package (`python/`) |
| TokenDagger (`tokendagger`) | 486.3 ms | 489.0 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| tiktoken (npm) | PENDING | PENDING | WASM instantiation |
| turbotoken (npm WASM) | PENDING | PENDING | Zig WASM instantiation |
| turbotoken CLI | 95.2 ms | 98.8 ms | `python -m turbotoken.cli encode hello --encoding o200k_base` |

Notes:
- cold artifact: `bench/results/bench-startup-cold-20260227-145147.json`
- warm artifact: `bench/results/bench-startup-warm-20260227-145218.json`
- warm mode here means same command measured after Hyperfine warmup (`--warmup 10`), not a long-lived daemon process.

### Memory Usage (Peak RSS during o200k_base encode of 1MB)

| Competitor | Peak RSS | Delta over baseline | Notes |
|-----------|----------|-------------------|-------|
| Python baseline (empty) | 14.52 MB | -- | `python3 -c "pass"` |
| tiktoken | 115.14 MB | +100.63 MB | `tiktoken.get_encoding("o200k_base").encode(text)` |
| rs-bpe | 90.28 MB | +75.77 MB | `openai.o200k_base().encode(text)` |
| TokenDagger (`tokendagger`) | 241.52 MB | +227.00 MB | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| turbotoken | 31.23 MB | +16.72 MB | `turbotoken.get_encoding("o200k_base").encode(text)` |
| turbotoken CLI | 40.70 MB | +26.19 MB | `python -m turbotoken.cli encode - --encoding o200k_base` |

Notes:
- artifact: `bench/results/bench-ram-1772204354545.json`
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
| encode 100KB | 215.9 ms | 43.4 ms | 4.98x | 2026-02-27 |
| decode 128K tok | 222.7 ms | 77.9 ms | 2.86x | 2026-02-27 |

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

### NVIDIA GPU (Modal B200, CUDA 13.1.1)

Latest measured remote CUDA run (Modal) from:

- `bench/results/bench-modal-cuda-1772191604329.json`
- command: `bun run bench:modal:cuda --runs 5`
- detected GPU: `NVIDIA B200` (`nvidia-smi`)

CUDA workload rows embedded in the artifact:

| Operation | Workload | Median | Throughput | Median backend peak alloc | Date |
|-----------|----------|-------:|-----------:|--------------------------:|------|
| `cuda-cupy-encode-u8-to-u32-1mb` | 1 MiB encode cast | 0.827 ms | 1208.7 MiB/s | 10 MiB | 2026-02-27 |
| `cuda-cupy-count-nonzero-batch-4096x1kb` | 4 MiB aggregate count | 0.674 ms | 5934.6 MiB/s | 9 MiB | 2026-02-27 |

From the same Modal run summary:
- startup cold winner: `python-startup-rs-bpe` (84.28 ms)
- startup warm winner: `python-startup-rs-bpe` (55.32 ms)
- encode winner: `python-encode-10kb-turbotoken` (36.71 ms)
- decode winner: `python-decode-1000-tok-rs-bpe` (79.42 ms)
- count winner: `python-count-100kb-turbotoken` (40.69 ms)
- training winner: `python-train-english-100kb-turbotoken-py-fallback-v320` (47.96 ms)

Notes:
- This CUDA table currently reflects CUDA memory/throughput microbench rows (`scripts/bench-gpu-memory-cuda.ts`), not full GPU BPE kernel throughput (Phase 5 work remains TODO).
- First-sample CUDA initialization outliers are present in raw samples; medians above are reported for stable comparison.

### NVIDIA GPU (RTX 4090 dedicated host)

| Operation | Batch Size | turbotoken CUDA | Per-string | Date |
|-----------|-----------|-----------------|------------|------|
| encode batch | 1K | PENDING | PENDING | -- |
| encode batch | 10K | PENDING | PENDING | -- |
