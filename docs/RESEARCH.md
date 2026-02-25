# turbotoken -- Research Log

> Ongoing research notes for each backend, algorithm, and technology decision.
> This is the "lab notebook" -- raw findings, links, experiments, observations.

---

## Table of Contents

1. [BPE Algorithm Research](#1-bpe-algorithm-research)
2. [ARM64 NEON Research](#2-arm64-neon-research)
3. [Apple Metal / GPU Research](#3-apple-metal--gpu-research)
4. [WebAssembly / MoonBit Research](#4-webassembly--moonbit-research)
5. [x86 SIMD Research](#5-x86-simd-research)
6. [NVIDIA CUDA Research](#6-nvidia-cuda-research)
7. [RISC-V Vector Research](#7-risc-v-vector-research)
8. [Merge Table / Data Structure Research](#8-merge-table--data-structure-research)
9. [Benchmark Methodology Research](#9-benchmark-methodology-research)
10. [GPU Tokenization Deep Dive (2026-02-25)](#10-gpu-tokenization-deep-dive-2026-02-25)

---

## 1. BPE Algorithm Research

### O(n) Backtracking Algorithm

**Source:** GitHub `bpe` crate -- https://github.com/github/bpe
**Blog:** https://github.blog/ai-and-ml/llms/so-many-tokens-so-little-time-introducing-a-faster-more-flexible-byte-pair-tokenizer/

**Key insight:** tiktoken uses O(n^2) greedy left-to-right merge. GitHub's approach uses backtracking with bitfield tracking to achieve O(n) amortized time.

**How it works:**
- Instead of repeatedly scanning for the highest-priority merge pair
- Track merge candidates in a bitfield
- Process merges in priority order with backtracking
- Each byte is visited a bounded number of times

**rs-bpe variant:** https://github.com/gweidart/rs-bpe
- Claims 15x on small inputs, linear scaling on large
- Worth studying their Rust implementation for optimization ideas
- They may have additional improvements beyond the GitHub approach

**TODO:**
- [ ] Read GitHub bpe crate source code in detail
- [ ] Read rs-bpe source code for any additional optimizations
- [ ] Prototype O(n) algorithm in Zig (`src/encoder.zig`)
- [ ] Use Zig `comptime` to generate lookup tables for merge priority
- [ ] Benchmark Zig prototype vs tiktoken to validate 4x claim
- [ ] Identify `@Vector`-friendly inner loops in the algorithm

### Flat Pair-Cache Array

**Source:** mojo-tokenizer -- https://github.com/dorjeduck/mojo-tokenizer
**Blog:** https://medium.com/@atveit/fastest-ai-token-output-readable-text-on-apple-silicon-144m-tokens-sec-on-m3-ultr-263a6f2f85e0

**Key insight:** Instead of hash table for merge pair lookups, use a flat array indexed by (token_a, token_b). For o200k_base with 200K vocab, this is 200K * 200K = 40 billion entries -- too large. But with pruning and cache-line alignment, a 4MB flat array covers the most common pairs.

**Design considerations:**
- Cache-line aligned (64 bytes on ARM64)
- NEON `ld1`/`st1` for vectorized access
- Fallback to hash table for rare pairs not in flat array
- 4MB fits in L2 cache on M4 Max (48MB L2)

**TODO:**
- [ ] Profile merge pair distribution across all 4 encodings
- [ ] Determine optimal flat array size (4MB? 8MB? 16MB?)
- [ ] Prototype flat array vs hash table in Zig (`src/pair_cache.zig`)
- [ ] Use Zig `comptime` to pre-compute flat array layout at compile time
- [ ] Benchmark cache hit rates on real-world text

---

## 2. ARM64 NEON Research

### Byte Classification via vtbl/vceq

**Target:** Replace tiktoken's Python regex pre-tokenizer with NEON byte classification.

**Approach:** Classify each byte into character classes using SIMD lookup tables.
- `vtbl` (vector table lookup) -- 16 bytes/cycle classification
- `vceq` (vector compare equal) -- character class membership testing
- Emit token boundaries as a bitmask

**Key references:**
- ARM NEON intrinsics: https://developer.arm.com/architectures/instruction-sets/intrinsics/
- NEON optimization guide: https://developer.arm.com/documentation/den0018/latest
- Sep CSV parser (9.5 GB/s on M1 via NEON): https://nietras.com/2025/06/17/sep-0-11-0/
- ARM bitmask porting guide: https://developer.arm.com/community/arm-community-blogs/b/servers-and-cloud-computing-blog/posts/porting-x86-vector-bitmask-optimizations-to-arm-neon
- Cloudflare NEON JPEG optimization: https://blog.cloudflare.com/neon-is-the-new-black/

**The PMOVMSKB problem:**
ARM NEON lacks x86's `PMOVMSKB` (pack most significant bits into a bitmask). This means the standard x86 technique of "classify 16 bytes, extract bitmask, use BSF to find first boundary" doesn't directly translate.

**ARM alternatives:**
1. `vshrn` (shift right narrow) -- pack comparison results into half-width
2. `addv` (add across vector) -- horizontal reduction for popcount-style ops
3. `umaxv` (unsigned max across vector) -- "any match?" test
4. Use `vget_lane` to extract individual results (slower but simple)

**M4 Max specifics:**
- 12 performance cores, 4 efficiency cores
- 48MB shared L2 cache
- NEON pipeline: 4-wide decode, 2 NEON execution units per P-core
- 128-bit NEON registers (v0-v31)
- M4 supports FEAT_DOTPROD, FEAT_FP16, FEAT_SHA3 -- potentially useful

**TODO:**
- [ ] Write prototype NEON pre-tokenizer in Zig `@Vector(16, u8)` first (portable, easier to debug)
- [ ] Benchmark Zig `@Vector` NEON codegen quality vs hand-written assembly
- [ ] Write hand-tuned ARM64 `.S` assembly for hottest inner loop
- [ ] Profile with Instruments.app for pipeline stalls
- [ ] Test NEON decoder: memcpy-style ld1/st1 with prfm prefetch (`.S` assembly)
- [ ] Measure actual bytes/cycle on M4 Max P-core and E-core
- [ ] Compare Zig `@Vector` auto-vectorization vs explicit NEON intrinsics

### NEON Decoder Design

**Goal:** 144M+ tok/s decode (matching mojo-tokenizer claim)

**Approach:**
1. Flat lookup table: `token_id -> (byte_ptr, byte_len)`
2. For each token, NEON `ld1` from lookup table, `st1` to output buffer
3. `prfm pldl1keep` to prefetch next N token lookups
4. This is essentially vectorized memcpy -- should be memory-bandwidth limited

**Expected bottleneck:** Memory bandwidth, not compute. M4 Max has ~400 GB/s.
128K tokens * ~4 bytes/token avg = ~512KB of output. At 400GB/s this is <2us theoretical.
Real-world with prefetch overhead: target <0.06ms.

---

## 3. Apple Metal / GPU Research

### Metal 4 (WWDC25)

**Source:** https://developer.apple.com/videos/play/wwdc2025/262/

**Key Metal 4 features relevant to us:**
- Tensors as first-class shader citizens (not just matrices)
- Improved compute shader dispatch
- Better shared memory management
- M4 Max: 40 GPU cores, 128GB unified memory

### BlockBPE for GPU

**Source:** https://arxiv.org/html/2507.11941v1

**Key insight:** BPE can be parallelized by splitting input into independent chunks, encoding each chunk independently on a GPU thread, then stitching boundaries.

**Challenges:**
- Chunk boundaries may split multi-byte tokens
- Need overlap region at boundaries for correctness
- Merge table must fit in shared memory (or use global with caching)

**Design for Metal:**
1. Pre-tokenize on CPU (NEON) -- split into chunks at whitespace boundaries
2. Upload chunks to GPU shared memory
3. Each threadgroup encodes one chunk independently
4. Download token arrays back to CPU
5. Concatenate results

**TODO:**
- [x] Read BlockBPE paper in detail
- [x] Prototype in Metal compute shader
- [ ] Determine optimal chunk size (threadgroup size)
- [x] Measure GPU dispatch overhead vs encoding time
- [ ] Profile on M4 Max 40-core GPU

---

## 4. WebAssembly / Zig WASM Unified Research

### Zig -> WASM (PRIMARY -- Unified Codebase)

**Key insight:** With Zig as our core language (ADR-001), we get WASM for free. The exact same `src/*.zig` files compile to `wasm32-freestanding`. No separate codebase. No separate language.

**Zig WASM advantages:**
- **Zero runtime:** `wasm32-freestanding` produces a WASM binary with no libc, no GC, no allocator unless explicitly used
- **Smallest possible binary:** Expected ~80-150KB. Zig's design goal is tiny binaries.
- **WASM SIMD:** Zig's `@Vector(16, u8)` can target the WASM SIMD proposal (128-bit vectors in browsers)
- **`comptime` in WASM:** Merge table hash functions computed at compile time, embedded in WASM binary
- **No JS glue required:** Unlike Emscripten, Zig's WASM output doesn't need a `.js` helper file

**Zig WASM build command:**
```bash
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
# Or for speed over size:
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseFast
```

**WASM SIMD via Zig @Vector:**
```zig
// This same code works on NEON, AVX, and WASM SIMD:
const input: @Vector(16, u8) = bytes.*;
const spaces = input == @as(@Vector(16, u8), @splat(' '));
// On wasm32: i8x16.eq WASM SIMD instruction
// On aarch64: vceqq_u8 NEON instruction
// On x86_64: _mm_cmpeq_epi8 SSE2 instruction
```

**Browser WASM SIMD support (as of 2026):**
| Browser | WASM SIMD | Version |
|---------|-----------|---------|
| Chrome | Yes | 91+ (May 2021) |
| Firefox | Yes | 89+ (May 2021) |
| Safari | Yes | 16.4+ (Mar 2023) |
| Edge | Yes | 91+ (Chromium) |
| Node.js | Yes | 16.4+ |

### Comparison WASM Paths (for documentation)

**MoonBit -> WASM-GC (comparison only):**
- MoonBit produces ~150-200KB WASM (50-70% smaller than Rust)
- WASM-GC target: requires recent browser versions
- GC pauses may affect tokenization latency
- Separate codebase from our Zig core = maintenance burden
- **Status:** Build for comparison. Do NOT ship as primary.

**Emscripten (via Zig C ABI export, comparison only):**
- Compile Zig's C ABI exports through Emscripten
- Produces ~250-350KB WASM (includes libc shims)
- Mature toolchain, well-understood
- **Status:** Build for comparison. Do NOT ship as primary.

### WASM Benchmark Plan

| Approach | Binary Size Target | Perf Target vs tiktoken.js | Code Reuse | Build Complexity |
|----------|-------------------|---------------------------|-----------|-----------------|
| **Zig -> wasm32-freestanding** | **<150KB** | **5-10x** | **100%** | **Zero (same build.zig)** |
| MoonBit -> WASM-GC | ~150-200KB | 5-10x | 0% | Medium (new language) |
| Emscripten (via Zig exports) | ~250-350KB | 3-5x | ~80% | Low |
| Rust -> wasm-pack | ~500KB+ | 2-3x | 0% | Medium |

**Decision:** Ship Zig WASM. Build MoonBit and Emscripten for comparison/documentation only.

**TODO:**
- [ ] Add `wasm32-freestanding` target to `build.zig`
- [ ] Build Zig WASM, measure binary size with `ReleaseSmall`
- [ ] Build Zig WASM, measure binary size with `ReleaseFast`
- [ ] Test WASM SIMD via `@Vector(16, u8)` on wasm32 target
- [ ] Write JS/TS wrapper (`js/wasm-loader.ts`) that loads Zig WASM
- [ ] Build browser benchmark page
- [ ] Optionally: build MoonBit WASM for binary size comparison
- [ ] Optionally: build Emscripten WASM for perf comparison
- [ ] Run wasm-opt on Zig output to see if further shrinkage possible

---

## 5. x86 SIMD Research

### AVX2 (256-bit)

**Available on:** Intel Haswell (2013)+, AMD Excavator (2015)+
**Key instructions for text processing:**
- `vpshufb` -- byte shuffle (lookup table, 32 bytes at once)
- `vpcmpeqb` -- byte compare equal
- `vpmovmskb` -- pack MSB of each byte into 32-bit mask (x86 has this! ARM doesn't)
- `vpand`/`vpor` -- bitwise logic on 256-bit vectors
- `tzcnt`/`lzcnt` -- count trailing/leading zeros (for bitmask scanning)

**Pre-tokenizer approach:**
1. Load 32 bytes
2. `vpshufb` to classify each byte (lookup table in YMM register)
3. `vpcmpeqb` to test character class membership
4. `vpmovmskb` to extract boundary bitmask
5. `tzcnt` to find first boundary position
6. Emit token, advance, repeat

This is the classic x86 text scanning approach (used by simdjson, simdutf, etc.)

### AVX-512BW (512-bit)

**Available on:** Intel Ice Lake (2019)+, AMD Zen 4 (2022)+
**Key advantage:** 64 bytes/cycle classification
**Key instructions:**
- `vpermb` -- byte permute (512-bit lookup table)
- `vpcmpb` -- byte compare with mask result in `k` register
- `kmovq` -- move mask register to GPR for bitmask scanning

**Concern:** AVX-512 causes frequency throttling on some Intel CPUs.
Need to benchmark to confirm net improvement vs AVX2.

**TODO:**
- [ ] Prototype AVX2 pre-tokenizer via Zig `@Vector(32, u8)` in `src/arch/x86_64.zig`
- [ ] Prototype AVX-512BW pre-tokenizer via Zig `@Vector(64, u8)`
- [ ] Hand-write `.S` assembly for hottest AVX inner loops
- [ ] Runtime CPUID detection via Zig `std.Target.x86` features
- [ ] Benchmark on Intel Xeon (cloud) and AMD Ryzen (desktop)
- [ ] Test frequency throttling impact of AVX-512
- [ ] Compare Zig `@Vector` codegen quality vs hand-written AVX intrinsics

---

## 6. NVIDIA CUDA Research

### BlockBPE Implementation

**Paper:** https://arxiv.org/html/2507.11941v1

**Design:**
- Each CUDA block processes one text chunk
- Merge table loaded into shared memory (48KB on sm_80+)
- o200k_base has 200K vocab -- merge table doesn't fit in shared memory
- Solution: load most-frequent merges into shared memory, L2 cache for the rest

**NVIDIA cuDF reference:**
- https://developer.nvidia.com/blog/run-state-of-the-art-nlp-workloads-at-scale-with-rapids-huggingface-and-dask/
- cuDF achieves 483x for WordPiece tokenization -- but no BPE
- BPE is harder to parallelize due to merge dependencies

**Target hardware:**
- sm_80: A100 (80GB, 2TB/s bandwidth)
- sm_89: RTX 4090 (24GB, 1TB/s bandwidth)
- sm_90: H100 (80GB, 3.35TB/s bandwidth)

**TODO:**
- [x] Read BlockBPE paper implementation details
- [ ] Prototype CUDA kernel for chunk-parallel BPE
- [ ] Shared memory optimization for merge table
- [ ] Benchmark on RTX 4090 and/or A100
- [ ] Compare GPU dispatch overhead vs actual encoding time
- [ ] Determine minimum batch size where GPU wins over CPU

---

## 7. RISC-V Vector Research

### RVV 1.0 Overview

**Key feature:** Vector-length agnostic (VLA) programming model.
- Code works on any VLEN (128-bit to 2048-bit)
- `vsetvli` instruction sets vector length dynamically
- Software doesn't hardcode vector width (unlike NEON's fixed 128-bit)

**Relevant instructions:**
- `vle8.v` -- vector load bytes
- `vse8.v` -- vector store bytes
- `vmseq.vi` -- set mask where elements equal immediate
- `vrgather.vv` -- vector gather (equivalent to NEON `vtbl`)
- `vcompress.vm` -- compress elements based on mask

**Pre-tokenizer approach:**
```
vsetvli a0, a1, e8, m1    # set vector length for byte elements
vle8.v v1, (input)         # load bytes
vrgather.vv v2, v3, v1    # byte classification lookup
vmseq.vi v0, v2, CLASS_BOUNDARY  # find boundaries
vcompress.vm v4, v1, v0   # extract boundary positions
```

**Hardware availability:**
- SiFive P670 -- RVV 1.0, 256-bit VLEN
- THEAD C910 -- partial RVV support
- StarFive JH7110 -- RISC-V but no RVV
- QEMU -- full RVV emulation for development

**TODO:**
- [ ] Set up QEMU with RVV support for development
- [ ] Write VLA pre-tokenizer prototype
- [ ] Test on QEMU, measure instruction counts
- [ ] Seek real RVV hardware for benchmarking (SiFive P670 dev board?)

---

## 8. Merge Table / Data Structure Research

### tiktoken Rank File Format

**Location:** Downloaded from URLs defined in `tiktoken_ext/openai_public.py`
**Format:** Base64-encoded lines, each line is `base64(token_bytes) rank_number`
**Size:** o200k_base is ~5.4MB, cl100k_base is ~3.3MB

### Loading Strategy

**tiktoken's approach:** Download on first use, cache in `~/.cache/tiktoken/`
**Our approach:** Same, but cache in `~/.cache/turbotoken/`
**Fallback:** If offline, check for vendored copies or error with helpful message

### Hash Table vs Flat Array vs Perfect Hash

| Approach | Lookup Time | Memory | Build Time |
|----------|-------------|--------|-----------|
| std hash table (open addressing) | O(1) avg, cache-unfriendly | ~6MB | ~50ms |
| Flat array (mojo-inspired) | O(1), cache-friendly | ~4-16MB | ~100ms |
| Perfect hash (CHD/MPHF) | O(1), compact | ~2MB | ~500ms (one-time) |
| Sorted array + binary search | O(log n) | ~5MB | ~200ms (sort) |

**Decision:** Start with flat array for most-common pairs + hash table fallback.
Explore perfect hash later if memory is a concern.

**Zig `comptime` advantage:** Merge table layout can be computed at compile time:
```zig
// src/pair_cache.zig
const PairCache = struct {
    // comptime-generated flat array
    flat: [ARRAY_SIZE]u32 = comptime blk: {
        var arr: [ARRAY_SIZE]u32 = [_]u32{EMPTY} ** ARRAY_SIZE;
        for (merge_pairs) |pair| {
            arr[hash(pair.a, pair.b) % ARRAY_SIZE] = pair.merged;
        }
        break :blk arr;
    },
};
```
This means zero runtime initialization cost -- the array is embedded in the binary.

---

## 9. Benchmark Methodology Research

### Hyperfine Best Practices

**Source:** https://github.com/sharkdp/hyperfine

**Key flags we use:**
- `--warmup 3` -- 3 warmup runs before measuring
- `--min-runs 10` -- at least 10 measured runs
- `--shell=none` -- for sub-5ms commands, avoid shell overhead
- `--export-json` -- machine-readable results
- `--export-markdown` -- human-readable tables
- `-n "name"` -- label for each command
- `-P param min max` -- parameterized sweeps

**Pitfalls to avoid:**
1. Don't compare commands with different shell overhead
2. Don't benchmark with background processes running
3. Use `--shell=none` for native binaries, `--shell=default` for Python
4. Always include `--warmup` to fill page caches
5. Run multiple times on different days to catch variance

### Memory Measurement

**macOS:** `/usr/bin/time -l command` -- shows "maximum resident set size"
**Linux:** `/usr/bin/time -v command` -- shows "Maximum resident set size (kbytes)"

**For in-process measurement:**
```python
import resource
peak_kb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
# macOS: bytes, Linux: kilobytes (confusingly different!)
```

### Binary Size Measurement

```bash
# Wheel size
ls -la dist/turbotoken-*.whl

# Zig-compiled shared library size
ls -la zig-out/lib/libturbotoken.dylib  # macOS
ls -la zig-out/lib/libturbotoken.so     # Linux

# WASM size (Zig unified build)
ls -la zig-out/lib/turbotoken.wasm

# Zig ReleaseSmall for minimum size
zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-freestanding
ls -la zig-out/lib/turbotoken.wasm

# Optional: run wasm-opt for further shrinkage
wasm-opt -Oz zig-out/lib/turbotoken.wasm -o turbotoken-opt.wasm
ls -la turbotoken-opt.wasm
```

---

## 10. GPU Tokenization Deep Dive (2026-02-25)

### Primary-source findings

- **BlockBPE (ICML 2025 workshop preprint) is the strongest direct BPE-on-GPU reference so far.**
  - The paper describes a one-block-per-string design, block-wide minimum-pair selection, and compaction with prefix scans.
  - Reported throughput wins are concentrated in high-batch settings; low-batch latency remains a CPU strength.
  - The paper also reports a quality caveat: replacing regex pre-tokenization with byte-level splitting can hurt some workloads (notably math-heavy tasks).
  - Source: https://arxiv.org/html/2507.11941v1

- **RAPIDS/cuDF now exposes both BPE and WordPiece APIs, but with different scope than `tiktoken` compatibility.**
  - `nvtext::byte_pair_encoding(...)` is available and merge-pair-driven.
  - `nvtext::wordpiece_tokenize(...)` is available for WordPiece vocabularies.
  - These APIs are useful engineering references for vocabulary loading, GPU data structures, and tensor output shaping, but they are not drop-in OpenAI `tiktoken` encoders.
  - Sources:
    - https://docs.rapids.ai/api/libcudf/stable/group__nvtext__tokenize
    - https://raw.githubusercontent.com/rapidsai/cudf/branch-25.08/cpp/include/nvtext/byte_pair_encoding.hpp
    - https://raw.githubusercontent.com/rapidsai/cudf/branch-25.08/cpp/include/nvtext/wordpiece_tokenize.hpp

- **Current mainstream production tokenizers are still CPU-first.**
  - `tiktoken` core path is regex + BPE with CPU threading in Python batch helpers.
  - HuggingFace tokenizers are Rust-native and support optional rayon parallelism (`TOKENIZERS_PARALLELISM`) but still CPU execution.
  - Sources:
    - https://raw.githubusercontent.com/openai/tiktoken/main/tiktoken/core.py
    - https://raw.githubusercontent.com/huggingface/tokenizers/main/tokenizers/src/utils/parallelism.rs
    - https://raw.githubusercontent.com/huggingface/tokenizers/main/docs/source-doc-builder/index.mdx

- **Older GPU tokenizer codebases are useful for kernel patterns, but not correctness targets.**
  - `Fast-tokenizers` demonstrates byte-neighborhood rule tokenization with a thread-per-byte pattern plus host-side post-pass cleanup.
  - The repo itself documents fixed-window limitations for long repeating patterns.
  - Source:
    - https://github.com/github2015david/Fast-tokenizers
    - https://raw.githubusercontent.com/github2015david/Fast-tokenizers/master/src_cpp/GpuTokenize.cu

- **CPU algorithm work still matters even with GPU ambitions.**
  - `bpe`/`bpe-openai` and `mojo-tokenizer` show strong gains from linear/backtracking algorithms and cache-aware storage, which should remain the correctness/perf baseline while GPU path matures.
  - Sources:
    - https://raw.githubusercontent.com/github/rust-gems/main/crates/bpe/README.md
    - https://raw.githubusercontent.com/github/rust-gems/main/crates/bpe-openai/README.md
    - https://raw.githubusercontent.com/atsentia/mojo-tokenizer/main/README.md

### Draft GPU merge-pass skeleton (research pseudocode)

```c
// One threadgroup/block handles one string piece.
while (true) {
  rank[i] = lookup_pair_rank(token[i], token[i + 1]); // INF if missing
  min_rank = block_reduce_min(rank);
  if (min_rank == INF) break;

  // Tie-break must be deterministic and match reference semantics.
  merge_flag[i] = (rank[i] == min_rank) && leftmost_non_overlapping(i);

  // Compact surviving tokens after merges.
  keep_flag[i] = !was_consumed_by_left_merge(i);
  out_idx[i] = exclusive_prefix_sum(keep_flag[i]);
  if (keep_flag[i]) next_tokens[out_idx[i]] = merged_or_original(i);

  swap(tokens, next_tokens);
}
```

For CUDA, the closest direct building blocks are:
- `cuCollections::static_map` for GPU-resident pair-rank lookup.
- CCCL/CUB block scans for compaction and write-index assignment.
- Sources:
  - https://github.com/NVIDIA/cuCollections
  - https://nvidia.github.io/cccl/cub/api/classcub_1_1BlockScan.html

### Practical implications for turbotoken

- Keep **strict compatibility mode** anchored to current CPU/native path until GPU merge path is token-identical.
- Treat byte-level pre-tokenization-only paths as **explicitly experimental** (`device="metal"`/future `device="cuda"` opt-in).
- Use batch-size/sequence-length crossover calibration as a hard gate before auto-routing to GPU.
- Keep all benchmark claims scoped to measured artifacts in `bench/results/`.

### Potential upstream / ecosystem contributions

- [ ] Upstream reproducible crossover methodology:
  - Publish the `encode/count/BPE` crossover matrix shape (sizes, loops, win thresholds, JSON schema) so CPU/GPU tokenizer projects can compare apples-to-apples.
- [ ] Upstream parity corpus for GPU stitch paths:
  - Add an open corpus focused on known boundary-risk cases (long repeats, alternating byte classes, mixed UTF-8 punctuation) with strict token-identity checks.
- [ ] Coordinate API hooks for chunk-stitch research:
  - Propose optional low-level APIs in tokenizer runtimes for exposing pre-tokenized piece boundaries and chunk metadata without forcing full regex rework.
- [ ] Share Metal/CUDA kernel micro-pattern findings:
  - Document practical wins from SIMD-group reductions, compaction strategy choices, and launch heuristics so future BlockBPE-like backends start from measured baselines.
