# turbotoken — Product Requirements Document

> **The fastest BPE tokenizer on every platform. Period.**
> **Hand-optimized for each target: ARM64 NEON, Apple Metal, WASM, AVX2, CUDA, RISC-V.**
> **First in the turbo-tools family.**

> **Reality check (2026-02-25):** repository implementation is still mixed maturity. CPU BPE compatibility exists, but current GPU kernels are still experimental building blocks and not full on-GPU `tiktoken`-compatible BPE.

---

## 1. NAMING & IDENTITY

### Package Name: `turbotoken`

**Rationale:** "Turbo" = raw speed, forced induction, more power from the same engine. Mirrors tiktoken's rhythm (tik-token / turbo-token). 10 chars, reads as two obvious words, never mispronounced. Untouched in the ML/tokenizer space. Establishes the **turbo-tools** brand family.

**Tagline:** "The fastest BPE tokenizer on every platform you run code on."

**Alternate taglines:**
- "8x faster than tiktoken. On every architecture."
- "Stop waiting for token counts. Start shipping."
- "Zig + ARM64 assembly. Metal shaders. WASM. All one `pip install`."

### Name Registry

| Platform | Name | Status |
|----------|------|--------|
| **PyPI** | `turbotoken` | **REGISTER IMMEDIATELY** |
| **npm** | `turbotoken` | Register |
| **crates.io** | `turbotoken` | Register |
| **GitHub** | `turbo-tools/turbotoken` | Create org + repo |
| **Domain** | `turbotoken.dev` | Register |
| **Twitter/X** | `@turbotoken_` | Register |
| **Zig package** | `turbotoken` | Register on Zig package index |
| **wapm.io** | `turbotoken` | Register for WASM distribution |

### Brand Family (future)

All shipped under the `turbo-tools` GitHub org:

| Package | Purpose | Timeline |
|---------|---------|----------|
| `turbotoken` | BPE tokenizer (8x tiktoken, every platform) | **Phase 1-3 -- NOW** |
| `turbodiff` | NEON/GPU diff engine | Phase 7 |
| `turbogrep` | SIMD-accelerated search | Phase 8 |
| `turbo` | Unified agent acceleration CLI | Phase 9 |

### Visual Identity

- **Logo concept:** A turbocharger/compressor icon formed from NEON register lanes, or a stylized "T" with exhaust speed lines. Orange/amber color palette (heat, speed, energy). Monospace font for "turbotoken".
- **Color:** `#FF6B00` (primary -- turbo heat orange), `#1A1A2E` (dark bg), `#E8E8E8` (light text)
- **Font:** JetBrains Mono for code, Inter for copy
- **Motif:** Speed. Every visual asset should feel fast -- motion blur, gradient streaks, exhaust trails.

---

## 2. PRODUCT OVERVIEW

### What It Is

turbotoken is a **drop-in replacement for tiktoken** that is the **most hyper-optimized BPE tokenizer ever built for each individual platform**. Not a single generic implementation compiled for many targets -- a collection of hand-crafted, platform-specific implementations that each squeeze every last cycle out of the hardware:

- **ARM64 NEON assembly** on Apple Silicon and AWS Graviton
- **Apple Metal 4 compute shaders** for GPU batch encoding on M-series
- **Zig-compiled WebAssembly** for browsers and edge runtimes (unified codebase!)
- **AVX2/AVX-512 via Zig `@Vector`** on x86_64 Intel/AMD
- **NVIDIA CUDA kernels** (BlockBPE) for datacenter batch encoding
- **RISC-V Vector Extension (RVV)** for the emerging RISC-V ecosystem
- **Scalar Zig fallback** for everything else (still 4x tiktoken via O(n) algorithm)

Every backend produces **byte-perfect identical output** to tiktoken. The API is the same. Only the speed changes.

### The Philosophy: Optimize for What You Have

We don't build one implementation and cross-compile. We build **N implementations**, each hand-tuned for a specific target ISA, GPU architecture, or runtime. The M4 Max build uses instructions that don't exist on Graviton. The AVX-512 build uses masks that don't exist on NEON. The WASM build comes from the **same Zig codebase** compiled to `wasm32-freestanding` -- one language, every target.

**Zig is the unifying core.** Its `@Vector` portable SIMD, `comptime` table generation, first-class C ABI export, and built-in `wasm32-freestanding` target let us write the tokenizer once and get near-optimal code for every platform. For the absolute hottest inner loops, hand-written `.S` assembly files squeeze the last few percent.

**Every platform gets its own fastest-possible build.**

### Who It's For

1. **Coding agent developers** (Claude Code, Cursor, Aider, Codex, Cline, OpenCode) -- saves 3-9 seconds per session on token counting
2. **LLM application developers** -- context window management without latency tax
3. **ML pipeline engineers** -- batch tokenization for training data at 40+ MB/s
4. **LLM API providers** -- tokenize billing at hardware speed
5. **Browser/edge developers** -- fast tokenization in the browser via WASM without a server round-trip
6. **RISC-V early adopters** -- vector-optimized tokenizer ready for SiFive, StarFive, THEAD hardware

### Why Now

| Fact | Source | Implication |
|------|--------|-------------|
| Taalas HC1 delivers 17K tok/s per user | [taalas.com](https://taalas.com/the-path-to-ubiquitous-ai/) | LLM inference collapses from 78% to 7.5% of agent time |
| tiktoken encodes 673K tokens in 368ms on M4 | [cotool.ai](https://cotool.ai/blog/context-management) | Tokenization becomes 21% of non-test agent time |
| tiktoken encodes 678K tokens in 3,300ms on Cloud Run | Same source | Serverless agents spend MORE time tokenizing than on LLM inference |
| 10-turn agent loop spends 9.8s on pure encoding overhead | Same source | That's real user-facing latency |
| rs-bpe achieves 15x on small text, linear scaling vs tiktoken's quadratic | [rs-bpe](https://github.com/gweidart/rs-bpe) | Algorithm alone gives massive gains; SIMD on top is unbeatable |
| GitHub `bpe` crate achieves 4x with algorithmic improvements | [GitHub Blog](https://github.blog/ai-and-ml/llms/so-many-tokens-so-little-time-introducing-a-faster-more-flexible-byte-pair-tokenizer/) | NEON assembly on top of better algorithm = 8-16x |
| BlockBPE demonstrates parallel GPU BPE at near-linear time | [arxiv](https://arxiv.org/html/2507.11941v1) | GPU batch tokenization is proven feasible |
| Zig produces tiny WASM binaries via `wasm32-freestanding` with zero runtime | [ziglang.org](https://ziglang.org/learn/wasm/) | Same Zig codebase compiles to native + WASM -- unified architecture |
| mojo-tokenizer decodes at 144M tok/s on M3 Ultra | [medium.com](https://medium.com/@atveit/fastest-ai-token-output-readable-text-on-apple-silicon-144m-tokens-sec-on-m3-ultr-263a6f2f85e0) | 128K context window decoded in <1ms is achievable |
| Metal 4 introduces tensors as first-class shader citizens | [Apple WWDC25](https://developer.apple.com/videos/play/wwdc2025/262/) | GPU tokenization on Apple Silicon gets even faster |
| No project combines all: SIMD + GPU + WASM + drop-in compat | Our research | Wide open opportunity |

---

## 3. TECHNICAL SPECIFICATIONS

### 3.1 Architecture Overview

```
turbotoken
+-- Language Bindings Layer
|   +-- Python (cffi via Zig's C ABI export) -- drop-in tiktoken replacement
|   +-- Node.js/npm (N-API + WASM fallback)
|   +-- Rust crate (thin FFI wrapper)
|   +-- Go module (cgo wrapper via Zig's C ABI export)
|   +-- CLI binary (turbotoken count/encode/decode/bench)
|
+-- libturbotoken (Zig core -- exports C ABI for universal FFI)
|   +-- src/encoder.zig      -- O(n) backtracking BPE
|   +-- src/decoder.zig      -- flat lookup table decode
|   +-- src/pair_cache.zig   -- comptime-generated 4MB cache-aligned merge cache
|   +-- src/rank_loader.zig  -- load .tiktoken merge tables
|   +-- src/pretokenizer.zig -- Zig @Vector portable SIMD (works on all targets)
|
+-- Platform-Specific Backends (compile-time selected via build.zig)
|   |
|   +-- [Phase 1] ARM64 NEON (Apple M1-M4, Graviton, Ampere)
|   |   +-- src/arch/aarch64.zig   -- Zig @Vector(16, u8) NEON path
|   |   +-- asm/arm64/neon_hot.S   -- hand-written assembly for hottest loops
|   |
|   +-- [Phase 2] Apple Metal 4 (M1-M4 GPU)
|   |   +-- gpu/metal/batch_encode.metal  -- parallel chunk BPE (BlockBPE-style)
|   |   +-- gpu/metal/batch_count.metal   -- count-only fast path
|   |
|   +-- [Phase 3] Zig -> WebAssembly (UNIFIED -- same codebase!)
|   |   +-- build.zig target: wasm32-freestanding
|   |   +-- src/arch/wasm.zig       -- WASM-specific optimizations
|   |   +-- js/wasm-loader.ts       -- JS wrapper, ES module
|   |   +-- (MoonBit & Emscripten as comparison builds only)
|   |
|   +-- [Phase 4] x86_64 AVX2/AVX-512
|   |   +-- src/arch/x86_64.zig     -- Zig @Vector(32, u8) AVX2 / @Vector(64, u8) AVX-512
|   |   +-- asm/x86_64/avx_hot.S   -- hand-written assembly for hottest loops
|   |
|   +-- [Phase 5] NVIDIA CUDA (sm_80+: A100/H100/RTX 3090+)
|   |   +-- gpu/cuda/batch_encode.cu  -- BlockBPE CUDA kernel
|   |   +-- gpu/cuda/batch_count.cu   -- count-only kernel
|   |
|   +-- [Phase 6] RISC-V Vector Extension (RVV 1.0)
|   |   +-- src/arch/riscv.zig      -- Zig @Vector VLA-style path
|   |   +-- asm/riscv/rvv_hot.S    -- hand-written RVV assembly
|   |
|   +-- [Fallback] Scalar Zig
|       +-- src/arch/generic.zig    -- no SIMD, still 4x tiktoken via O(n) algo
|
+-- Benchmark Infrastructure
    +-- Hyperfine-based CLI benchmarks
    +-- Bun Shell TypeScript orchestration scripts
    +-- Upstream test sync from tiktoken/rs-bpe/GitHub bpe
```

### 3.2 Core Algorithm

**Encoding pipeline:**

1. **Pre-tokenization (platform SIMD):** Replace tiktoken's Python regex (75% of CPU time) with SIMD byte classification. On NEON: `vtbl`/`vceq` at 16 bytes/cycle. On AVX2: `vpshufb`/`vpcmpeqb` at 32 bytes/cycle. On AVX-512: `vpermb` at 64 bytes/cycle. Classify into character classes (letter, digit, whitespace, punctuation). Emit token boundaries without regex engine overhead.

2. **BPE merge (O(n) backtracking):** Adopt the backtracking algorithm from GitHub's `bpe` crate and rs-bpe. Instead of tiktoken's O(n^2) greedy merge, use O(n) with bitfield tracking. Flat 4MB pair-cache array (inspired by mojo-tokenizer) for O(1) merge lookups, cache-line aligned for SIMD load/store.

3. **Token ID lookup:** Perfect hash or sorted array binary search with SIMD-accelerated comparison.

**Decoding pipeline:**

4. **Lookup table decode (SIMD):** Each token ID -> byte sequence via flat lookup table. NEON `ld1`/`st1` with software prefetching (`prfm pldl1keep`). AVX2 `vmovdqu` + `_mm256_stream_si256`. Pure memcpy -- the easiest path to 100x+ speedup. Target: 144M+ tok/s (matching mojo-tokenizer).

**Key algorithm references:**
- GitHub `bpe` crate (O(n) backtracking): https://github.com/github/bpe
- rs-bpe (Rust, linear scaling): https://github.com/gweidart/rs-bpe
- BlockBPE (parallel GPU BPE): https://arxiv.org/html/2507.11941v1
- mojo-tokenizer (144M tok/s decode): https://github.com/dorjeduck/mojo-tokenizer
- tiktoken (the API and correctness oracle): https://github.com/openai/tiktoken

### 3.3 Supported Encodings

Ship with byte-perfect compatibility for all tiktoken encodings:

| Encoding | Models | Vocab Size | Priority |
|----------|--------|-----------|----------|
| `o200k_base` | GPT-4o, GPT-4o-mini, GPT-4.1 | 200,019 | **P0** -- most used |
| `cl100k_base` | GPT-4, GPT-3.5-turbo, embeddings | 100,256 | **P0** -- still widespread |
| `p50k_base` | Codex, text-davinci-002/003 | 50,281 | P1 |
| `r50k_base` (gpt2) | GPT-3, open-source models | 50,257 | P1 |

Merge tables are loaded from tiktoken's published `.tiktoken` rank files (same URLs, cached locally in `~/.cache/turbotoken/`).

### 3.4 Platform Support Matrix

| Platform | CPU Backend | GPU Backend | WASM | Priority |
|----------|-------------|-------------|------|----------|
| **macOS ARM64 (M1-M4 Max)** | NEON assembly | Metal 4 shaders | -- | **P0** -- dev machine |
| **Linux ARM64 (Graviton, Ampere)** | NEON assembly | -- | -- | **P0** -- cloud |
| **Web browsers** | -- | -- | Zig WASM | **P1** -- huge reach |
| **Node.js / Bun / Deno** | N-API native | -- | WASM fallback | **P1** -- JS ecosystem |
| **Linux x86_64** | AVX2/AVX-512 intrinsics | CUDA (sm_80+) | -- | **P1** -- datacenter |
| **Windows x86_64** | AVX2 intrinsics | CUDA (sm_80+) | -- | P2 |
| **macOS x86_64 (Intel)** | SSE4.2 intrinsics | -- | -- | P2 |
| **Linux RISC-V** | RVV 1.0 assembly | -- | -- | P3 -- future-proof |

### 3.5 Performance Targets (Apple M4 Max -- Primary Dev Target)

| Operation | tiktoken | turbotoken Target | Speedup |
|-----------|----------|-----------------|---------|
| `encode()` -- 1KB text | ~0.2ms | **<0.025ms** | **8x** |
| `encode()` -- 100KB text | ~20ms | **<2.5ms** | **8x** |
| `encode()` -- 673K tokens | 368ms | **<46ms** | **8x** |
| `decode()` -- 1K tokens | ~0.05ms | **<0.0005ms** | **100x** |
| `decode()` -- 128K tokens | ~6ms | **<0.06ms** | **100x** |
| `count()` -- 673K tokens | 368ms | **<35ms** | **10x** |
| `encode_batch()` -- 1K strings (CPU) | ~200ms | **<25ms** | **8x** |
| `encode_batch()` -- 1K strings (Metal GPU) | N/A | **<5ms** | **40x** |
| Binary size (native) | ~2MB | **<500KB** | **4x smaller** |
| Binary size (WASM) | N/A | **<200KB** | -- |
| Startup / first-encode latency | ~50ms | **<5ms** | **10x** |
| Peak RAM (o200k_base loaded) | ~40MB | **<12MB** | **3x less** |

### 3.6 Cross-Platform Performance Targets

| Platform | Encode 100KB | Decode 128K tok | Notes |
|----------|-------------|-----------------|-------|
| M4 Max (NEON) | <2.5ms | <0.06ms | Primary target |
| M4 Max (Metal GPU batch) | <0.5ms/string | <0.01ms/string | 1K string batch |
| Graviton3 (NEON) | <3ms | <0.08ms | AWS cloud |
| Xeon w/ AVX-512 | <2ms | <0.05ms | 64 bytes/cycle classify |
| Ryzen 9 (AVX2) | <3ms | <0.07ms | Desktop x86 |
| WASM (Chrome V8) | <15ms | <0.5ms | 3-5x tiktoken.js |
| WASM (Zig) | <10ms | <0.3ms | Same codebase, smallest binary |
| RTX 4090 (CUDA batch) | <0.2ms/string | <0.005ms/string | 1K string batch |
| RISC-V (RVV) | <20ms | <0.5ms | SiFive P670+ |

---

## 4. API SPECIFICATION

### 4.1 Drop-in Compatibility Layer

**The #1 requirement:** `import turbotoken as tiktoken` must work with zero code changes.

```python
# === EXACT tiktoken API replication ===

import turbotoken

# Module-level functions (match tiktoken exactly)
enc = turbotoken.get_encoding("o200k_base")
enc = turbotoken.encoding_for_model("gpt-4o")
turbotoken.list_encoding_names()  # -> ["o200k_base", "cl100k_base", ...]

# Encoding class -- FULL method parity
class Encoding:
    # --- Properties ---
    name: str                        # "o200k_base"
    n_vocab: int                     # 200019
    eot_token: int                   # end of text token
    special_tokens_set: set[str]     # {"<|endoftext|>", ...}

    # --- Core encoding ---
    def encode(
        self,
        text: str,
        *,
        allowed_special: Literal["all"] | set[str] = set(),
        disallowed_special: Literal["all"] | set[str] = "all",
    ) -> list[int]: ...

    def encode_ordinary(self, text: str) -> list[int]:
        """Encode ignoring special tokens (fastest path)."""

    def encode_single_token(self, text_or_bytes: str | bytes) -> int: ...

    # --- Batch encoding ---
    def encode_ordinary_batch(
        self, text: list[str], *, num_threads: int = 8
    ) -> list[list[int]]: ...

    def encode_batch(
        self,
        text: list[str],
        *,
        num_threads: int = 8,
        allowed_special: Literal["all"] | set[str] = set(),
        disallowed_special: Literal["all"] | set[str] = "all",
    ) -> list[list[int]]: ...

    # --- Decoding ---
    def decode(self, tokens: list[int], errors: str = "replace") -> str: ...
    def decode_bytes(self, tokens: list[int]) -> bytes: ...
    def decode_single_token_bytes(self, token: int) -> bytes: ...
    def decode_batch(
        self, batch: list[list[int]], *, num_threads: int = 8
    ) -> list[str]: ...

    # --- Numpy support ---
    def encode_to_numpy(self, text: str, *, allowed_special=...) -> np.ndarray: ...

    # --- Token set operations ---
    def token_byte_values(self) -> list[bytes]: ...
```

### 4.2 turbotoken-Exclusive Extensions

```python
class Encoding:
    # --- Fast count (no allocation) ---
    def count(self, text: str) -> int:
        """Return token count without building the token list.
        Avoids all list/array allocation. Fastest path for context window checks.
        """

    def count_batch(self, texts: list[str], *, num_threads: int = 8) -> list[int]:
        """Count tokens for multiple strings in parallel."""

    # --- GPU batch encoding ---
    def encode_gpu(
        self,
        texts: list[str],
        *,
        device: str = "auto",  # "metal", "cuda", or "auto"
    ) -> list[list[int]]:
        """Batch encode on GPU. 40x+ faster for large batches."""

    def count_gpu(self, texts: list[str], *, device: str = "auto") -> list[int]:
        """Batch count on GPU. Fastest path for bulk context checks."""

    # --- Streaming encode (for very large texts) ---
    def encode_chunks(
        self, text: str, *, chunk_size: int = 8192
    ) -> Iterator[list[int]]:
        """Yield token chunks for texts that don't fit in memory."""

    # --- Diagnostics ---
    @staticmethod
    def backend() -> str:
        """Return active backend: 'neon', 'avx512', 'avx2', 'sse42',
        'scalar', 'metal', 'cuda', 'wasm', 'rvv'."""

    @staticmethod
    def benchmark(encoding_name: str = "o200k_base") -> dict:
        """Run built-in benchmark. Returns dict with encode/decode/count MB/s."""
```

### 4.3 JavaScript/TypeScript API (npm)

```typescript
import { getEncoding, encodingForModel } from "turbotoken";

const enc = getEncoding("o200k_base");
const tokens: number[] = enc.encode("hello world");
const text: string = enc.decode(tokens);
const count: number = enc.count("how many tokens?");

// Backend detection
enc.backend(); // "wasm" | "neon" (Node.js native) | "avx2" (Node.js native)
```

### 4.4 CLI Tool

```bash
# Token count files (useful for context window budgeting)
$ turbotoken count src/**/*.py
src/main.py          1,234 tokens
src/utils.py           567 tokens
src/models/user.py   2,891 tokens
TOTAL               4,692 tokens

# Encode/decode
$ echo "hello world" | turbotoken encode
[15339, 1917]

$ echo "[15339, 1917]" | turbotoken decode
hello world

# Benchmark (uses Hyperfine internally)
$ turbotoken bench
turbotoken v0.1.0 (backend: neon)
Encoding: o200k_base

encode    1KB:    0.023ms  (43.5 MB/s)    8.7x tiktoken
encode  100KB:    2.1ms    (47.6 MB/s)    9.5x tiktoken
decode    1K:     0.4us    (512M tok/s)  102x tiktoken
count   673K:    32ms      (54.2 MB/s)   11.5x tiktoken

# Backend info
$ turbotoken info
Platform:  macOS arm64 (Apple M4 Max)
Backend:   ARM64 NEON + Apple Metal 4
Encodings: o200k_base, cl100k_base, p50k_base, r50k_base
GPU:       Apple M4 Max (40-core, 128GB unified)
```

---

## 5. IMPLEMENTATION PLAN

### Phase 1: ARM64 NEON + Python Package (Weeks 1-3) -- THE LAUNCH

This is the primary dev target: Apple M4 Max. We optimize for what we have in hand.

**Week 1: Core Zig + ARM64 Assembly**
- [x] Scaffold project: `src/`, `src/arch/`, `asm/arm64/`, `python/`, `bench/`, `scripts/`, `build.zig`
- [x] Implement flat pair-cache array (4MB, cache-aligned, `comptime`-generated) from merge table files
- [x] Implement O(n) backtracking BPE encoder in Zig (reference: GitHub `bpe` crate + rs-bpe)
- [x] Write NEON pre-tokenizer via Zig `@Vector(16, u8)` + hand-written ARM64 `.S` for hottest paths
- [x] Write NEON decoder: `ld1`/`st1` from lookup table with `prfm pldl1keep` prefetch (`.S` assembly)
- [ ] Scalar Zig fallback (no SIMD `@Vector` -- still 4x tiktoken via better algorithm)
- [x] Set up Hyperfine benchmark scripts (Bun Shell TypeScript)
- [x] Clone tiktoken upstream as git submodule for test oracle
- [x] `build.zig` with targets: `aarch64-macos`, `aarch64-linux`, `x86_64-linux` (scalar), `wasm32-freestanding`

**Week 2: Python Wrapper + Compatibility**
- [x] cffi bridge from Zig (Zig exports C ABI via `export fn`) to Python
- [x] Implement full `Encoding` class matching tiktoken API (Section 4.1)
- [x] Load merge tables from tiktoken's `.tiktoken` rank file URLs (cache in `~/.cache/turbotoken/`)
- [x] Implement `count()` fast path (no allocation)
- [x] Sync and adapt tiktoken's own test suite (see Section 6.4)
- [x] Byte-perfect comparison against tiktoken on full test corpus

**Week 3: Packaging + Benchmarks + Launch**
- [x] Build wheels via Zig cross-compilation: `macosx_11_0_arm64`, `manylinux_2_17_aarch64` (NEON), `manylinux_2_17_x86_64` (scalar), `win_amd64` (scalar)
- [x] Run full Hyperfine benchmark suite, generate charts
- [x] Write README, benchmark page, architecture doc
- [x] CLI tool (`turbotoken count`, `turbotoken bench`, `turbotoken info`)
- [ ] **LAUNCH: PyPI + GitHub + HN + Twitter** (`POSTPONED`)

### Phase 2: Apple Metal GPU Backend (Weeks 4-5)

Still M4 Max. GPU batch encoding for when you have many strings.
Current implementation note (2026-02-25): byte-path kernels are now on `metal-byte-path-v4` with `512`-byte encode chunks per thread, unrolled `uchar4 -> uint4` widening stores, and SIMD-group-based count reduction with unrolled accumulation; full on-GPU BPE merge remains pending.

- [x] Metal 4 compute shader for batch pre-tokenization (parallel chunk classification)
- [ ] Metal compute shader for batch BPE merge (BlockBPE-style independent chunks)
- [ ] Add block-level merge loop kernels: min-rank reduction, deterministic non-overlap ownership, prefix-sum compaction
- [x] Keep strict parity mode as default route; GPU path remains opt-in until token-identical
- [x] `encode_gpu()` / `count_gpu()` Python methods
- [x] Hyperfine benchmarks: Metal vs NEON CPU vs tiktoken
- [ ] Blog post: "GPU tokenization on Apple Silicon -- turbotoken goes Metal"

### Phase 3: Zig WebAssembly -- Unified Build (Weeks 6-7)

The browser/edge play. **Zig's killer advantage: same codebase compiles to native AND WASM.**

**3a: Zig -> WASM (primary -- unified codebase)**
- [x] Add `wasm32-freestanding` target to `build.zig`
- [ ] WASM-specific optimizations in `src/arch/wasm.zig` (no SIMD, scalar BPE)
- [ ] Explore WASM SIMD (128-bit) via Zig's `@Vector(16, u8)` on wasm32
- [ ] Target: <150KB WASM binary (Zig's zero-runtime advantage)
- [ ] JS/TS wrapper: `js/wasm-loader.ts` with ES module export
- [ ] npm package: `turbotoken` with WASM auto-loaded
- [ ] Browser benchmark page: turbotoken vs tiktoken.js vs gpt-tokenizer vs wasm-tokenizer

**3b: Comparison builds (for documentation only)**
- [ ] Build MoonBit WASM version for binary size comparison
- [ ] Build Emscripten WASM from Zig's C ABI export for comparison
- [ ] Document all binary sizes and perf numbers in WASM-EXPLORATION.md

**3c: WASM SIMD exploration**
- [ ] Test Zig `@Vector` targeting WASM SIMD proposal (128-bit vectors)
- [ ] Measure perf gain of WASM SIMD vs scalar WASM
- [ ] Browser compatibility matrix for WASM SIMD

### Phase 4: x86_64 AVX2/AVX-512 (Weeks 8-9)

Cover Intel/AMD desktops and cloud instances.

- [ ] AVX2 pre-tokenizer via Zig `@Vector(32, u8)` + hand-written `.S` for hottest paths
- [ ] AVX-512BW pre-tokenizer via Zig `@Vector(64, u8)` + hand-written `.S` (where available)
- [ ] AVX2 decoder: `vmovdqu` + streaming stores (hand-tuned assembly)
- [ ] Hyperfine benchmarks on Intel Xeon and AMD Ryzen
- [ ] Zig `build.zig` CPU feature detection: AVX-512 -> AVX2 -> SSE4.2 -> scalar (compile-time + runtime)

### Phase 5: NVIDIA CUDA Backend (Weeks 10-11)

GPU batch tokenization for datacenter workloads.

- [ ] CUDA BlockBPE kernel (sm_80+ for A100/H100, sm_89 for RTX 4090)
- [ ] Shared memory merge table for coalesced access
- [ ] Evaluate `cuCollections::static_map` + CCCL/CUB `BlockScan` as baseline primitives for rank lookup + compaction
- [ ] Benchmark crossover matrix across batch size and sequence length before enabling any auto-route
- [ ] Hyperfine + custom GPU timing benchmarks on RTX 4090/A100
- [ ] Blog post: "Tokenize 10GB/s on NVIDIA GPUs"

### Phase 6: RISC-V Vector Extension (Weeks 12-13)

Future-proofing for the RISC-V wave.

- [ ] RVV 1.0 pre-tokenizer: vector-length-agnostic byte classification
- [ ] RVV decoder: scalable vector load/store
- [ ] Test on QEMU RVV emulation + SiFive P670 if available
- [ ] Hyperfine benchmarks (even on emulation, establish baseline)

### Phase 7+: Language Bindings & More

- [ ] **Rust crate** (`turbotoken`): thin FFI wrapper over Zig's C ABI export
- [ ] **Go module** (`turbotoken-go`): cgo wrapper over Zig's C ABI export
- [ ] **Swift package**: direct Metal integration for iOS/macOS apps
- [ ] **C# / .NET**: P/Invoke wrapper for Unity/game dev tokenization
- [ ] **turbodiff**, **turbogrep** -- next turbo-tools

---

## 6. TESTING STRATEGY

### 6.1 Correctness (Non-Negotiable)

```python
# Every single test must pass before any release

# 1. Byte-perfect roundtrip for all encodings
for enc_name in ["o200k_base", "cl100k_base", "p50k_base", "r50k_base"]:
    tt = turbotoken.get_encoding(enc_name)
    tk = tiktoken.get_encoding(enc_name)
    for text in TEST_CORPUS:
        assert tt.encode(text) == tk.encode(text)
        assert tt.decode(tt.encode(text)) == text

# 2. Special token handling matches exactly
assert tt.encode("<|endoftext|>", allowed_special="all") == tk.encode(...)
assert tt.encode("<|endoftext|>", disallowed_special="all")  # raises

# 3. Edge cases
TEST_CORPUS = [
    "",                           # empty string
    " ",                          # single space
    "\n\n\n",                     # newlines
    "hello world",                # basic
    "hello  world",               # double space
    "emoji: 🎉🔥💻🚀",          # emoji
    "CJK: こんにちは世界",         # Japanese
    "def foo():\n    pass\n",     # Python code
    "a" * 1_000_000,              # 1MB repeated char
    random_bytes(1000),           # random bytes
    LINUX_KERNEL_MAKEFILE,        # real large file
    ADVERSARIAL_BPE_INPUT,        # worst-case for O(n^2) algorithms
]

# 4. Batch encoding matches single encoding
texts = ["hello", "world", "test"]
assert tt.encode_batch(texts) == [tt.encode(t) for t in texts]
```

### 6.2 Performance (Benchmark CI)

Run on every PR against `main`:
- Encode/decode at 1KB, 10KB, 100KB, 1MB
- Compare against tiktoken (must be >=4x faster on ARM64)
- Track regressions: fail CI if >5% slower than previous release
- All benchmarks run through Hyperfine for statistical rigor

### 6.3 Fuzz Testing

```bash
# Use Zig's built-in fuzz testing (zig test --fuzz) on the Zig core
# Also AFL/libFuzzer via Zig's C ABI export
# Zig's safety checks (bounds, overflow) active in Debug/ReleaseSafe modes
# Must not crash, leak, or produce different output than tiktoken
```

### 6.4 Upstream Test Synchronization

We maintain test parity with upstream projects by syncing their test suites:

```
upstream/                              # git submodules or synced copies
+-- tiktoken/                          # github.com/openai/tiktoken
|   +-- tests/test_encoding.py         # THE correctness oracle
|   +-- tiktoken_ext/openai_public.py  # encoding definitions
+-- rs-bpe/                            # github.com/gweidart/rs-bpe
|   +-- tests/                         # additional edge cases
+-- github-bpe/                        # github.com/github/bpe
|   +-- tests/                         # Rust test cases adapted to Python
+-- compare-tokenizers/                # github.com/transitive-bullshit/compare-tokenizers
    +-- tests/                         # Node.js tokenizer test suite
```

**Sync script** (Bun Shell TypeScript -- see Section 7):

```typescript
// scripts/sync-upstream.ts
import { $ } from "bun";

const upstreams = [
  { name: "tiktoken", repo: "openai/tiktoken", branch: "main" },
  { name: "rs-bpe", repo: "gweidart/rs-bpe", branch: "main" },
  { name: "github-bpe", repo: "github/bpe", branch: "main" },
  { name: "compare-tokenizers", repo: "transitive-bullshit/compare-tokenizers", branch: "main" },
];

for (const { name, repo, branch } of upstreams) {
  const dir = `upstream/${name}`;
  if (await Bun.file(`${dir}/.git`).exists()) {
    await $`cd ${dir} && git fetch origin ${branch} && git reset --hard origin/${branch}`;
    console.log(`Updated ${name}`);
  } else {
    await $`git clone --depth 1 --branch ${branch} https://github.com/${repo}.git ${dir}`;
    console.log(`Cloned ${name}`);
  }
}

// Adapt tiktoken tests
await $`cp upstream/tiktoken/tests/test_encoding.py tests/upstream/test_tiktoken_compat.py`;
console.log("Upstream tests synced.");
```

---

## 7. BENCHMARK INFRASTRUCTURE

### 7.1 Benchmarking Tool: Hyperfine

All benchmarks use [Hyperfine](https://github.com/sharkdp/hyperfine) for statistical rigor:
- Automatic warmup runs
- Shell overhead correction
- Statistical analysis (mean, median, stddev, min, max)
- Export to JSON/CSV/Markdown for chart generation
- Parameterized sweeps (input size, thread count, encoding)

### 7.2 All Scripts in Bun Shell TypeScript

Every script in the repo is Bun Shell TypeScript (`.ts` files run via `bun run`). No raw shell scripts. This gives us:
- Cross-platform compatibility (macOS, Linux, Windows)
- Type safety and IDE autocomplete
- Easy string interpolation and JSON handling
- Built-in glob, fetch, and file I/O
- Shell injection protection via Bun Shell's auto-escaping

```
scripts/
+-- sync-upstream.ts          # Pull latest tiktoken, rs-bpe, github-bpe, compare-tokenizers
+-- bench-all.ts              # Run complete benchmark suite via Hyperfine
+-- bench-encode.ts           # Encoding benchmarks across input sizes
+-- bench-decode.ts           # Decoding benchmarks across token counts
+-- bench-count.ts            # Count-only benchmarks
+-- bench-startup.ts          # Startup/first-encode latency
+-- bench-throughput.ts       # Sustained throughput (MB/s, tok/s)
+-- bench-parallel.ts         # Multi-threaded batch encoding
+-- bench-bigfile.ts          # Large file (1MB, 10MB, 100MB) encoding
+-- bench-ram.ts              # Peak memory usage measurement
+-- bench-binary-size.ts      # Compare binary/wheel sizes
+-- bench-wasm.ts             # WASM benchmarks (browser + Node.js)
+-- bench-gpu.ts              # Metal/CUDA GPU benchmarks
+-- bench-comparison.ts       # Head-to-head: turbotoken vs ALL competitors
+-- generate-charts.ts        # SVG/PNG chart generation from benchmark JSON
+-- ci-benchmark.ts           # CI regression check (fail if >5% slower)
+-- build-all.ts              # Build all backends
+-- test-all.ts               # Run all test suites including upstream
```

### 7.3 What We Benchmark

Every benchmark compares **all available implementations** side by side:

| Competitor | Language | How We Include It |
|-----------|----------|-------------------|
| **tiktoken** (baseline) | Rust+Python | `pip install tiktoken`, Python subprocess |
| **rs-bpe** | Rust+Python | `pip install rs-bpe`, Python subprocess |
| **TokenDagger** | Rust+Python | `pip install token-dagger`, Python subprocess |
| **HuggingFace tokenizers** | Rust+Python | `pip install tokenizers`, Python subprocess |
| **gpt-tokenizer** (JS) | TypeScript | `bun run` / `node` |
| **tiktoken.js** (JS/WASM) | JS+WASM | `bun run` / `node` |
| **wasm-tokenizer** | C++->WASM | `bun run` / `node` |
| **turbotoken** (ours) | Zig+ASM | Native binary + Python + JS/WASM |

### 7.4 Benchmark Dimensions

| Dimension | Values | Why |
|-----------|--------|-----|
| **Input size** | 1KB, 10KB, 100KB, 1MB, 10MB | Throughput scaling |
| **Encoding** | o200k_base, cl100k_base | Most used encodings |
| **Operation** | encode, decode, count | Full API coverage |
| **Concurrency** | 1, 2, 4, 8, 16 threads | Parallel scaling |
| **Startup** | Cold start, warm start | Import/init overhead |
| **Memory** | Peak RSS during encode | Memory efficiency |
| **Binary size** | Wheel size, WASM size, native binary | Distribution overhead |
| **Input type** | English prose, code (Python/JS/Rust), CJK, emoji, random bytes | Real-world diversity |

### 7.5 Example Benchmark Script

```typescript
// scripts/bench-encode.ts
import { $ } from "bun";

const sizes = ["1kb", "10kb", "100kb", "1mb"];
const encodings = ["o200k_base", "cl100k_base"];

for (const encoding of encodings) {
  for (const size of sizes) {
    const inputFile = `bench/fixtures/${size}.txt`;

    // Generate fixture if missing
    if (!(await Bun.file(inputFile).exists())) {
      await $`bun run scripts/generate-fixture.ts ${size}`;
    }

    console.log(`\n--- Encoding: ${encoding}, Input: ${size} ---`);

    await $`hyperfine \
      --warmup 3 \
      --min-runs 10 \
      --export-json bench/results/encode-${encoding}-${size}.json \
      --export-markdown bench/results/encode-${encoding}-${size}.md \
      -n "tiktoken" \
        "python3 -c \"import tiktoken; e=tiktoken.get_encoding('${encoding}'); e.encode(open('${inputFile}').read())\"" \
      -n "turbotoken" \
        "python3 -c \"import turbotoken; e=turbotoken.get_encoding('${encoding}'); e.encode(open('${inputFile}').read())\"" \
      -n "rs-bpe" \
        "python3 -c \"import rs_bpe; e=rs_bpe.get_encoding('${encoding}'); e.encode(open('${inputFile}').read())\"" \
      -n "turbotoken-cli" \
        "turbotoken encode --encoding ${encoding} < ${inputFile}"`;
  }
}

console.log("\nAll encoding benchmarks complete.");
console.log("Results in bench/results/");
```

### 7.6 Startup Benchmark Script

```typescript
// scripts/bench-startup.ts
import { $ } from "bun";

console.log("--- Startup Latency (time to first encode) ---");

await $`hyperfine \
  --warmup 0 \
  --min-runs 50 \
  --shell=none \
  --export-json bench/results/startup.json \
  --export-markdown bench/results/startup.md \
  -n "tiktoken-startup" \
    "python3 -c \"import tiktoken; tiktoken.get_encoding('o200k_base').encode('hello')\"" \
  -n "turbotoken-startup" \
    "python3 -c \"import turbotoken; turbotoken.get_encoding('o200k_base').encode('hello')\"" \
  -n "turbotoken-cli-startup" \
    "echo hello | turbotoken encode"`;
```

### 7.7 Benchmark Output Structure

```
bench/
+-- fixtures/                    # Generated test input files
|   +-- 1kb.txt
|   +-- 10kb.txt
|   +-- 100kb.txt
|   +-- 1mb.txt
|   +-- 10mb.txt
|   +-- code-python.txt          # Real Python source code
|   +-- code-javascript.txt      # Real JavaScript source code
|   +-- cjk-mixed.txt            # CJK + emoji + Latin mixed
|   +-- random-bytes.bin         # Random byte input
+-- results/                     # Hyperfine JSON + Markdown outputs
|   +-- encode-o200k_base-1kb.json
|   +-- encode-o200k_base-1kb.md
|   +-- ...
|   +-- startup.json
|   +-- memory.json
|   +-- binary-size.json
|   +-- summary.md               # Auto-generated summary table
+-- charts/                      # Generated SVG/PNG charts
|   +-- encode-speedup.svg
|   +-- decode-speedup.svg
|   +-- throughput-scaling.svg
|   +-- startup-comparison.svg
|   +-- memory-comparison.svg
```

---

## 8. DISTRIBUTION & PACKAGING

### 8.1 Python (PyPI)

```toml
# pyproject.toml
[project]
name = "turbotoken"
version = "0.1.0"
description = "The fastest BPE tokenizer on every platform. Drop-in tiktoken replacement."
readme = "README.md"
license = {text = "MIT"}
requires-python = ">=3.9"
keywords = ["tokenizer", "bpe", "tiktoken", "llm", "neon", "simd", "gpu", "wasm", "metal", "cuda"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Other",  # Zig (no PyPI classifier yet)
    "Topic :: Scientific/Engineering :: Artificial Intelligence",
    "Topic :: Text Processing",
]
dependencies = []  # ZERO dependencies (no numpy required, optional)

[project.optional-dependencies]
numpy = ["numpy>=1.20"]
gpu = ["pyobjc-framework-Metal>=10.0; sys_platform == 'darwin'"]

[project.scripts]
turbotoken = "turbotoken.cli:main"

[project.urls]
Homepage = "https://turbotoken.dev"
Repository = "https://github.com/turbo-tools/turbotoken"
Documentation = "https://turbotoken.dev/docs"
"Bug Tracker" = "https://github.com/turbo-tools/turbotoken/issues"
```

### 8.2 npm (JavaScript/TypeScript)

```json
{
  "name": "turbotoken",
  "version": "0.1.0",
  "description": "The fastest BPE tokenizer. WASM + native backends. Drop-in tiktoken replacement.",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs",
      "types": "./dist/index.d.ts"
    }
  },
  "files": ["dist/", "wasm/"],
  "keywords": ["tokenizer", "bpe", "tiktoken", "llm", "wasm", "neon", "simd"]
}
```

### 8.3 Wheel Matrix

```
turbotoken-0.1.0-cp39-cp39-macosx_11_0_arm64.whl        <- M1/M2/M3/M4 (NEON)
turbotoken-0.1.0-cp39-cp39-manylinux_2_17_aarch64.whl    <- Graviton/Ampere (NEON)
turbotoken-0.1.0-cp39-cp39-manylinux_2_17_x86_64.whl     <- Intel/AMD Linux (AVX2)
turbotoken-0.1.0-cp39-cp39-macosx_10_15_x86_64.whl       <- Intel Mac (SSE4.2)
turbotoken-0.1.0-cp39-cp39-win_amd64.whl                 <- Windows (AVX2)
# ... repeated for cp310, cp311, cp312, cp313, cp314
```

### 8.4 Repository Structure

```
turbotoken/
+-- README.md
+-- LICENSE                         # MIT
+-- build.zig                       # ZIG BUILD SYSTEM (replaces CMake)
+-- build.zig.zon                   # Zig package manifest
+-- pyproject.toml                  # Python package config
+-- package.json                    # npm package config
+-- Cargo.toml                      # For Rust crate (Phase 7)
|
+-- src/                            # Zig core (platform-agnostic logic)
|   +-- main.zig                    # Library root, public API
|   +-- encoder.zig                 # O(n) backtracking BPE
|   +-- decoder.zig                 # Flat lookup table decode
|   +-- pretokenizer.zig            # Zig @Vector portable SIMD pre-tokenizer
|   +-- pair_cache.zig              # comptime-generated 4MB cache-aligned merge cache
|   +-- rank_loader.zig             # Load .tiktoken merge tables
|   +-- hash.zig                    # Perfect hash for token lookup
|   +-- exports.zig                 # C ABI exports (export fn) for Python cffi / Go cgo
|   |
|   +-- arch/                       # Architecture-specific Zig SIMD paths
|       +-- aarch64.zig             # ARM64 NEON via @Vector(16, u8)
|       +-- x86_64.zig              # AVX2 @Vector(32, u8) / AVX-512 @Vector(64, u8)
|       +-- riscv.zig               # RISC-V vector path
|       +-- wasm.zig                # WASM-specific optimizations + WASM SIMD
|       +-- generic.zig             # Scalar fallback (no SIMD)
|
+-- asm/                            # Hand-written assembly for peak-perf hottest loops
|   +-- arm64/                      # ARM64 NEON (Phase 1)
|   |   +-- neon_pretokenizer.S     # vtbl/vceq byte classify, 16 bytes/cycle
|   |   +-- neon_decoder.S          # ld1/st1 + prfm prefetch memcpy
|   +-- x86_64/                     # x86 SIMD (Phase 4)
|   |   +-- avx2_pretokenizer.S     # vpshufb/vpcmpeqb 32 bytes/cycle
|   |   +-- avx512_pretokenizer.S   # vpermb 64 bytes/cycle
|   +-- riscv/                      # RISC-V Vector (Phase 6)
|       +-- rvv_pretokenizer.S      # VLA byte classification
|       +-- rvv_decoder.S           # Scalable vector decode
|
+-- gpu/                            # GPU compute backends
|   +-- metal/                      # Apple Metal 4 (Phase 2)
|   |   +-- batch_encode.metal
|   |   +-- batch_count.metal
|   +-- cuda/                       # NVIDIA CUDA (Phase 5)
|       +-- batch_encode.cu
|       +-- batch_count.cu
|
+-- python/                         # Python package
|   +-- turbotoken/
|   |   +-- __init__.py
|   |   +-- core.py                 # Encoding class (tiktoken-compatible)
|   |   +-- _native.py              # cffi bridge (loads Zig-compiled .dylib/.so)
|   |   +-- _registry.py            # Encoding name -> model mapping
|   |   +-- _gpu.py                 # Optional GPU backend
|   |   +-- cli.py                  # CLI tool
|   +-- tests/
|       +-- test_compatibility.py   # Byte-perfect vs tiktoken
|       +-- test_encoding.py        # All methods
|       +-- test_batch.py           # Batch encoding
|       +-- test_edge_cases.py      # Unicode, emoji, empty, huge
|       +-- test_benchmark.py       # Performance regression
|
+-- js/                             # JavaScript/TypeScript package
|   +-- src/
|   |   +-- index.ts
|   |   +-- encoding.ts
|   |   +-- wasm-loader.ts          # Loads Zig-compiled WASM binary
|   +-- tests/
|
+-- upstream/                       # Synced upstream repos (git submodules)
|   +-- tiktoken/
|   +-- rs-bpe/
|   +-- github-bpe/
|   +-- compare-tokenizers/
|
+-- scripts/                        # ALL Bun Shell TypeScript
|   +-- sync-upstream.ts
|   +-- bench-all.ts
|   +-- bench-encode.ts
|   +-- bench-decode.ts
|   +-- bench-count.ts
|   +-- bench-startup.ts
|   +-- bench-throughput.ts
|   +-- bench-parallel.ts
|   +-- bench-bigfile.ts
|   +-- bench-ram.ts
|   +-- bench-binary-size.ts
|   +-- bench-wasm.ts
|   +-- bench-gpu.ts
|   +-- bench-comparison.ts
|   +-- generate-charts.ts
|   +-- generate-fixture.ts
|   +-- ci-benchmark.ts
|   +-- build-all.ts                # Calls `zig build` for all targets
|   +-- test-all.ts                 # Calls `zig build test` + Python/JS tests
|
+-- bench/                          # Benchmark data
|   +-- fixtures/                   # Test input files
|   +-- results/                    # Hyperfine JSON/Markdown output
|   +-- charts/                     # Generated SVG/PNG charts
|
+-- docs/                          # All project documentation
|   +-- PRD.md                     # This file -- master product spec
|   +-- ARCHITECTURE.md            # ADRs, backend selection, data flow
|   +-- PROGRESS.md                # Phase-by-phase task tracker
|   +-- RESEARCH.md                # Research log per backend
|   +-- BENCHMARKS.md              # Benchmark results and comparison tables
|   +-- COMPETITORS.md             # Deep competitive analysis
|   +-- CHANGELOG.md               # Keep-a-changelog format
|   +-- WASM-EXPLORATION.md        # Zig WASM vs MoonBit vs Emscripten comparison
|   +-- UPSTREAM-SYNC.md           # Upstream sync strategy
|   +-- blog-post.md
|   +-- metal-gpu.md               # Metal compute shader deep dive
|   +-- zig-wasm.md                # Zig WASM unified build deep dive
|
+-- .github/
    +-- workflows/
        +-- ci.yml                  # `zig build test` on every PR
        +-- wheels.yml              # Build Python wheels (Zig cross-compile)
        +-- benchmark.yml           # Hyperfine regression check
        +-- wasm.yml                # `zig build -Dtarget=wasm32-freestanding` + test
```

---

## 9. MARKETING & LAUNCH COPY

### 9.1 README.md (above the fold)

```markdown
# turbotoken

**The fastest BPE tokenizer on every platform. Drop-in tiktoken replacement.**

Written in Zig. NEON assembly on ARM64. Metal shaders on Apple GPU. Same codebase
compiles to WASM for browsers. AVX-512 on x86. CUDA on NVIDIA. Hand-optimized for each target.

When LLM inference hits 15,000 tok/s, tokenization becomes 21% of your agent's
wall-clock time. turbotoken eliminates that bottleneck. Everywhere.

` ``python
# Drop-in replacement -- zero code changes
import turbotoken as tiktoken

enc = tiktoken.get_encoding("o200k_base")
tokens = enc.encode("hello world")
text = enc.decode(tokens)
count = enc.count("how many tokens?")  # <- new: no-alloc fast path
` ``

` ``
$ pip install turbotoken     # Python
$ npm install turbotoken     # JavaScript/TypeScript
$ cargo add turbotoken       # Rust
` ``

## Benchmarks (Apple M4 Max -- Primary Target)

| Operation | tiktoken | turbotoken | Speedup |
|-----------|----------|-----------|---------|
| Encode 1KB | 0.19ms | 0.023ms | **8.3x** |
| Encode 100KB | 19ms | 2.1ms | **9.0x** |
| Decode 128K tokens | 6.1ms | 0.058ms | **105x** |
| Count 673K tokens | 368ms | 32ms | **11.5x** |
| Batch 1K strings (Metal GPU) | N/A | 4.8ms | -- |
| Startup to first encode | ~50ms | <5ms | **10x** |
| Binary size (wheel) | ~2MB | <500KB | **4x smaller** |

All benchmarks measured with Hyperfine. Reproducible via `bun run scripts/bench-all.ts`.

## Runs Everywhere

| Platform | Backend | Status |
|----------|---------|--------|
| macOS ARM64 (M1-M4) | NEON assembly + Metal GPU | Phase 1-2 |
| Linux ARM64 (Graviton) | NEON assembly | Phase 1 |
| Browsers / Edge | Zig WASM (<150KB) | Phase 3 |
| Linux/Windows x86_64 | AVX2 / AVX-512 | Phase 4 |
| NVIDIA GPU | CUDA BlockBPE | Phase 5 |
| RISC-V | RVV 1.0 vector | Phase 6 |
```

### 9.2 Launch Blog Post -- Title Options

**Primary:** "The Hidden Tax: Token Counting Costs AI Agents 10 Seconds Per Session"

**Alternatives:**
- "We Hand-Optimized a Tokenizer for Every Platform. Here's What We Learned."
- "From ARM64 Assembly to Zig WASM: Building the Fastest Tokenizer on Every Architecture"
- "Why Your Coding Agent Spends More Time Counting Tokens Than Thinking"
- "8x Faster Than tiktoken. On M4 Max. On Graviton. In Your Browser. Everywhere."

### 9.3 HN Submission

**Title:** "Show HN: Turbotoken -- BPE tokenizer in Zig, hand-optimized for every platform (NEON/Metal/WASM/AVX/CUDA)"

**Show HN comment:**
> At 17K tok/s inference (Taalas HC1), tokenization is 21% of your coding agent's wall-clock time. We built turbotoken -- a drop-in tiktoken replacement written in Zig with hand-tuned assembly for each platform: ARM64 NEON, Apple Metal compute shaders, AVX-512 for x86, CUDA for NVIDIA GPUs. The same Zig codebase compiles to WASM for browsers.
>
> Zig's `@Vector` gives us portable SIMD. Hand-written `.S` assembly squeezes the last few percent on each ISA. `comptime` generates perfect hash tables at compile time. One language, every target.
>
> `pip install turbotoken`, then `import turbotoken as tiktoken`. MIT licensed.
>
> All benchmarks via Hyperfine, fully reproducible: [link to benchmarks]

### 9.4 Tweet / X Thread

**Launch tweet:**
> tiktoken: 368ms to encode 673K tokens.
> turbotoken: 32ms. On M4 Max.
>
> Written in Zig. NEON assembly. Metal shaders. WASM. AVX-512. CUDA.
> One codebase, hand-optimized for every platform.
>
> pip install turbotoken
> npm install turbotoken
>
> Drop-in replacement. MIT licensed. [chart image] [link]

**Thread:**
1. The hook (above)
2. "Coding agents tokenize your code 10-30x per session. At 15K tok/s inference, that's 21% of wall-clock time. The tokenizer IS the bottleneck."
3. Benchmark chart: turbotoken vs tiktoken vs rs-bpe vs TokenDagger
4. "One Zig codebase. @Vector portable SIMD. Hand-written assembly for hottest loops. Metal compute shaders. Same code compiles to WASM. AVX-512 for x86."
5. "Drop-in: `import turbotoken as tiktoken`. Byte-perfect output. MIT."
6. "All benchmarks via Hyperfine, all scripts in Bun Shell TypeScript. Fully reproducible."
7. "First turbo-tool. turbodiff and turbogrep are next. Star us."

---

## 10. COMPETITIVE LANDSCAPE

| Project | Language | Speed vs tiktoken | Drop-in? | SIMD? | GPU? | WASM? | Status |
|---------|----------|-------------------|----------|-------|------|-------|--------|
| **tiktoken** | Rust+Python | 1x (baseline) | -- | No | No | No | Production |
| **rs-bpe** | Rust+Python | 2-15x (varies by size) | Partial | No | No | No | Active (2025) |
| **TokenDagger** | Python/Rust | 2-4x | Yes | No | No | No | Active |
| **GitHub `bpe`** | Rust | 4x | No | No | No | No | Library only |
| **HuggingFace tokenizers** | Rust+Python | 0.3-0.5x | No | No | No | No | Production |
| **mojo-tokenizer** | Mojo | ~10x decode (144M tok/s) | No | Mojo SIMD | No | No | Experimental |
| **gpt-tokenizer** | TypeScript | ~0.5x | Partial (JS) | No | No | -- (native JS) | npm leader |
| **wasm-tokenizer** | C++->WASM | ~1.5x (in browser) | No | No | No | Yes | Active |
| **tiktoken.js** | JS+WASM | ~0.3x | Partial (JS) | No | No | Yes | Active |
| **NVIDIA RAPIDS cuDF** | CUDA | 270x (WordPiece only) | No | N/A | Yes | No | No BPE |
| **BlockBPE** | CUDA | Near-linear GPU BPE | No | N/A | Yes | No | Research (2025) |
| **turbotoken** | **Zig+ASM+Metal+WASM+CUDA** | **8-16x** | **Yes** | **Yes** | **Yes** | **Yes** | **Building** |

**Our moat:** The only project combining ALL of:
1. **Unified Zig codebase** with hand-optimized assembly per ISA
2. **Zig `@Vector` portable SIMD** + hand-written `.S` for peak paths
3. **GPU batch encoding** (Metal + CUDA)
4. **Zig -> WASM** (same codebase, smallest binary, zero runtime)
5. **Drop-in tiktoken API** compatibility
6. **O(n) algorithm** (not tiktoken's O(n^2) greedy)
7. **`comptime` table generation** (merge tables built at compile time)
8. **Comprehensive Hyperfine benchmarks** against every competitor

No other project has more than 2 of these 6.

---

## 11. RISK REGISTER

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| tiktoken changes API in new version | Medium | High | Pin compatibility to tiktoken 0.7-0.12. Track releases via upstream sync. |
| OpenAI adds new encoding (o300k?) | Medium | Medium | Architecture supports arbitrary merge tables. Add within days. |
| NEON speedup lower than expected | Low | High | Algorithm improvement alone (O(n) backtrack) gives 4x even without SIMD. rs-bpe proves this. |
| Zig WASM binary larger than expected | Low | Medium | Zig `wasm32-freestanding` has zero runtime. If still large, use `ReleaseSmall` + wasm-opt. |
| Zig pre-1.0 breaking changes | Medium | Medium | Pin to specific Zig version. Zig's stability is improving rapidly. Worst case: fix on upgrade. |
| Zig `@Vector` doesn't match hand-tuned assembly perf | Medium | Low | Hot loops use hand-written `.S` assembly anyway. `@Vector` is for "good enough" portable SIMD. |
| cibuildwheel + Zig cross-compile untested | Medium | Medium | Zig's `zig cc` cross-compiler is proven. May need custom build scripts for wheel building. |
| GPU batch not useful for interactive agents | Medium | Low | GPU is Phase 2/5 bonus. Core value is CPU SIMD speed. |
| Someone else ships similar first | Low | High | Move fast. First-mover with comprehensive benchmarks wins. |
| Correctness bugs | Medium | Critical | Fuzz testing + byte-perfect comparison against tiktoken on every CI run. |
| Hyperfine benchmarks don't reflect real-world perf | Low | Medium | Also benchmark in-process (Python timeit, JS performance.now). Hyperfine for CLI. |
| RISC-V hardware unavailable for testing | High | Low | Test on QEMU RVV emulation. Phase 6 is future-proofing, not launch-critical. |

---

## 12. OPEN QUESTIONS (DECIDED)

| Question | Decision | Rationale |
|----------|----------|-----------|
| License | **MIT** | tiktoken is MIT, TokenDagger is MIT, minimizes friction |
| Core language | **Zig + hand-written Assembly** | Unified codebase for native + WASM. `@Vector` portable SIMD. `comptime` tables. C ABI export. Safety without runtime cost. |
| Build system | **`build.zig`** | Zig's built-in build system. Cross-compilation is first-class. Replaces CMake. |
| Python bridge | **cffi** | Zig exports C ABI via `export fn`. No compile dependency for users. |
| Merge table loading | **Download on first use** | Same as tiktoken, with offline fallback. Vendoring bloats wheel. |
| Org name | **`turbo-tools`** | Brand family for turbotoken, turbodiff, turbogrep |
| Scripting language | **Bun Shell TypeScript** | Cross-platform, type-safe, maintainable. No raw shell. |
| Benchmark tool | **Hyperfine** | Statistical rigor, JSON export, industry standard |
| WASM approach | **Zig unified (same codebase)** | `wasm32-freestanding` target in `build.zig`. Zero runtime. Smallest binary. |
| Primary dev target | **Apple M4 Max** | Optimize for what we have. Other targets follow. |

---

## 13. REFERENCE LINKS

### Core Implementation References
- tiktoken source (the target to beat): https://github.com/openai/tiktoken
- tiktoken core.py (API to replicate): https://github.com/openai/tiktoken/blob/main/tiktoken/core.py
- tiktoken test suite (correctness oracle): https://github.com/openai/tiktoken/blob/main/tests/test_encoding.py
- GitHub Rust Gems `bpe` crate (O(n)/backtracking algorithm details): https://github.com/github/rust-gems/tree/main/crates/bpe
- GitHub Rust Gems `bpe-openai` crate (OpenAI vocab integration): https://github.com/github/rust-gems/tree/main/crates/bpe-openai
- GitHub Blog on `bpe` crate: https://github.blog/ai-and-ml/llms/so-many-tokens-so-little-time-introducing-a-faster-more-flexible-byte-pair-tokenizer/
- rs-bpe (Rust, linear scaling, Python bindings): https://github.com/gweidart/rs-bpe
- TokenDagger (drop-in pattern proof): https://github.com/SuperpoweredAI/token-dagger
- mojo-tokenizer (144M tok/s decode): https://github.com/dorjeduck/mojo-tokenizer
- BlockBPE (parallel GPU BPE): https://arxiv.org/html/2507.11941v1
- wasm-tokenizer (C++->WASM): https://github.com/script-heads/wasm-tokenizer
- compare-tokenizers (Node.js benchmark suite): https://github.com/transitive-bullshit/compare-tokenizers
- gpt-tokenizer (fastest JS tokenizer): https://github.com/niieani/gpt-tokenizer

### ARM64 NEON References
- ARM NEON intrinsics: https://developer.arm.com/architectures/instruction-sets/intrinsics/
- ARM64 assembly guide: https://developer.arm.com/documentation/102374/latest
- NEON optimization guide: https://developer.arm.com/documentation/den0018/latest
- NEON byte classification (Sep CSV parser, 9.5 GB/s on M1): https://nietras.com/2025/06/17/sep-0-11-0/
- ARM NEON bitmask porting guide: https://developer.arm.com/community/arm-community-blogs/b/servers-and-cloud-computing-blog/posts/porting-x86-vector-bitmask-optimizations-to-arm-neon

### x86 SIMD References
- AVX2/AVX-512 intrinsics reference: https://www.officedaytime.com/simd512e/
- Intel AVX-512 documentation: https://www.intel.com/content/www/us/en/developer/articles/technical/intel-avx-512-instructions.html
- Accelerated text processing via AVX2: https://www.klittlepage.com/2013/12/10/accelerated-fix-processing-via-avx2-vector-instructions/

### GPU Compute References
- Apple Metal 4 (WWDC25): https://developer.apple.com/videos/play/wwdc2025/262/
- Metal Shading Language spec: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
- Metal compute tutorial: https://developer.apple.com/documentation/metal/performing_calculations_on_a_gpu
- CUDA programming guide: https://docs.nvidia.com/cuda/cuda-c-programming-guide/
- NVIDIA cuDF GPU tokenization (483x BERT): https://developer.nvidia.com/blog/run-state-of-the-art-nlp-workloads-at-scale-with-rapids-huggingface-and-dask/
- RAPIDS libcudf tokenizer APIs: https://docs.rapids.ai/api/libcudf/stable/group__nvtext__tokenize
- RAPIDS BPE API header (`byte_pair_encoding`): https://github.com/rapidsai/cudf/blob/branch-25.08/cpp/include/nvtext/byte_pair_encoding.hpp
- RAPIDS WordPiece API header (`wordpiece_tokenize`): https://github.com/rapidsai/cudf/blob/branch-25.08/cpp/include/nvtext/wordpiece_tokenize.hpp
- NVIDIA cuCollections (GPU concurrent hash maps): https://github.com/NVIDIA/cuCollections
- NVIDIA CCCL/CUB BlockScan docs: https://nvidia.github.io/cccl/cub/api/classcub_1_1BlockScan.html
- Legacy CUDA tokenizer reference (rule-based PTB): https://github.com/github2015david/Fast-tokenizers
- BlockBPE discussion thread: https://news.ycombinator.com/item?id=44422480
- Practical GPU tokenizer tutorial (non-authoritative, implementation sketch): https://www.digitalocean.com/community/tutorials/run-tokenizer-on-gpu-for-faster-nlp
- NVIDIA Phi-3 model card (example of `tiktoken` tokenizer + 128K context pressure): https://build.nvidia.com/microsoft/phi-3-small-128k-instruct/modelcard

### Zig Language References
- Zig language: https://ziglang.org/
- Zig WASM guide: https://ziglang.org/learn/wasm/
- Zig @Vector SIMD: https://ziglang.org/documentation/master/#Vectors
- Zig comptime: https://ziglang.org/documentation/master/#comptime
- Zig build system: https://ziglang.org/documentation/master/#Build-System
- Zig cross-compilation: https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-for-gcc-clang.html
- Zig SIMD GitHub issue (#7702): https://github.com/ziglang/zig/issues/7702

### WebAssembly References
- Zig wasm32-freestanding target: https://ziglang.org/learn/wasm/
- MoonBit language (comparison): https://www.moonbitlang.com/
- MoonBit vs Rust WASM code size: https://thenewstack.io/moonbit-wasm-optimized-language-creates-less-code-than-rust/
- HuggingFace tokenizers WASM porting insights: https://blog.mithrilsecurity.io/porting-tokenizers-to-wasm/
- State of WebAssembly 2025-2026: https://platform.uno/blog/the-state-of-webassembly-2025-2026/
- WASM SIMD proposal: https://github.com/WebAssembly/simd

### RISC-V Vector References
- RISC-V Vector Extension (RVV) overview: https://riscv.org/blog/risc-v-vector-processing-is-taking-off-sifive/
- Samsung RISC-V vectorization: https://research.samsung.com/blog/RISC-V-and-Vectorization
- RVV in database operations (string processing): https://www.vldb.org/2025/Workshops/VLDB-Workshops-2025/ADMS/ADMS25-06.pdf

### Benchmark & Tooling References
- Hyperfine: https://github.com/sharkdp/hyperfine
- Bun Shell documentation: https://bun.com/docs/runtime/shell
- Bun Shell announcement: https://bun.sh/blog/the-bun-shell
- cibuildwheel: https://cibuildwheel.readthedocs.io/

### Market / Bottleneck Evidence
- Taalas 17K tok/s: https://taalas.com/the-path-to-ubiquitous-ai/
- Cotool tokenization latency: https://cotool.ai/blog/context-management
- Galileo production token accounting guide: https://galileo.ai/blog/tiktoken-guide-production-ai
- Tokenization benchmarks (July 2025): https://llm-calculator.com/blog/tokenization-performance-benchmark/
- mojo-tokenizer 144M tok/s on Apple Silicon: https://medium.com/@atveit/fastest-ai-token-output-readable-text-on-apple-silicon-144m-tokens-sec-on-m3-ultr-263a6f2f85e0
- Agent token consumption (ICLR 2026): https://openreview.net/forum?id=1bUeVB3fov
- Agent tool output overhead: https://dev.to/teppana88/your-ai-coding-agents-are-slow-because-your-tools-talk-too-much-24h6
