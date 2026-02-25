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

## Latest Measured Run (2026-02-24, macOS ARM64)

These values are from the latest `bun run bench` execution and corresponding JSON artifacts:

- `bench/results/bench-startup-20260224-150737.json`
- `bench/results/bench-count-20260224-150741.json`
- `bench/results/bench-encode-20260224-150745.json`
- `bench/results/bench-decode-20260224-150749.json`
- `bench/results/bench-throughput-20260224-150753.json`
- `bench/results/bench-bigfile-20260224-150803.json`
- `bench/results/bench-parallel-20260224-150808.json`
- `bench/results/bench-comparison-20260224-150829.json`
- `bench/results/bench-ram-1771945717135.json`
- `bench/results/bench-binary-size-1771945717172.json`
- `bench/results/bench-wasm-1771945718011.json`

| Workload | Mean |
|---|---:|
| startup (`python-import-and-first-encode`) | 139.3 ms |
| count 100KB | 144.3 ms |
| encode 100KB | 148.7 ms |
| decode 100KB-equivalent token list | 181.9 ms |
| encode 1MB | 198.8 ms |
| parallel count (512 items, 4 workers) | 1.570 s |

Comparison (`bench-comparison`):
- turbotoken encode 100KB: 147.1 ms
- tiktoken encode 100KB: 195.0 ms
- turbotoken ran ~1.33x faster on this workload in this run.

Other measured artifacts from the same run:
- peak RSS for 1MB encode (`bench-ram`): 91,840 KB
- cross-target static library size (`bench-binary-size`):
  - `aarch64-macos`: 1,412 bytes
  - `aarch64-linux`: 1,922 bytes
  - `x86_64-linux`: 1,890 bytes
  - `wasm32-freestanding`: 1,030 bytes
- wasm build artifact (`bench-wasm`): 1,030 bytes (`exitCode=0`)

---

## Latest Native Byte-Path Comparison (2026-02-25, macOS ARM64)

Direct ARM64 byte-kernel comparison from:
- `bench/results/bench-native-byte-path-20260225-133026.json`
- `bench/results/bench-native-byte-path-20260225-133026.meta.json`

Benchmark setup:
- Fixture: `bench/fixtures/english-1mb.txt` (+ generated `english-1mb.u32le.bin` for decode)
- In-process iterations per Hyperfine sample: 128 calls
- Commands compare C ABI NEON path (`turbotoken_encode/decode_utf8_bytes`) vs explicit scalar exports (`turbotoken_encode/decode_utf8_bytes_scalar`)

| Operation | NEON mean | Scalar mean | Speedup |
|---|---:|---:|---:|
| encode UTF-8 bytes (1MB x 128) | 104.2 ms | 423.2 ms | 4.06x |
| decode UTF-8 bytes (1MB x 128) | 103.7 ms | 454.7 ms | 4.38x |

Approx throughput from the same means:
- encode NEON: ~1228.4 MB/s vs scalar ~302.5 MB/s
- decode NEON: ~1234.3 MB/s vs scalar ~281.5 MB/s

Supplemental in-process microbenchmark (single Python process, warmed, 1MB payload):
- encode NEON: 0.0604 ms vs scalar 2.5200 ms (~41.7x)
- decode NEON: 0.0514 ms vs scalar 2.5160 ms (~48.9x)

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
