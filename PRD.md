# turbotoken — Product Requirements Document

> **The ARM64 assembly BPE tokenizer that makes coding agents 20% faster.**
> **First in the turbo-tools family.**

---

## 1. NAMING & IDENTITY

### Package Name: `turbotoken`

**Rationale:** "Turbo" = raw speed, forced induction, more power from the same engine. Mirrors tiktoken's rhythm (tik·token → turbo·token). 10 chars, reads as two obvious words, never mispronounced. Untouched in the ML/tokenizer space. Establishes the **turbo-tools** brand family: turbotoken, turbodiff, turbogrep.

**Tagline options (pick one):**
- "ARM64 assembly BPE tokenizer. 8× faster than tiktoken."
- "The tokenizer that keeps up with 15,000 tok/s inference."
- "Stop waiting for token counts. Start shipping."

### Name Registry

| Platform | Name | Status |
|----------|------|--------|
| **PyPI** | `turbotoken` | **REGISTER IMMEDIATELY** |
| **npm** | `turbotoken` | Register |
| **crates.io** | `turbotoken` | Register |
| **GitHub** | `turbo-tools/turbotoken` | Create org + repo |
| **Domain** | `turbotoken.dev` | Register |
| **Twitter/X** | `@turbotoken_` | Register |

### Brand Family (future)

All shipped under the `turbo-tools` GitHub org:

| Package | Purpose | Timeline |
|---------|---------|----------|
| `turbotoken` | BPE tokenizer (8× tiktoken) | **Phase 1 — NOW** |
| `turbodiff` | NEON/GPU diff engine | Phase 3 |
| `turbogrep` | SIMD-accelerated search | Phase 4 |
| `turbo` | Unified agent acceleration CLI | Phase 5 |

### Visual Identity

- **Logo concept:** A turbocharger/compressor icon formed from NEON register lanes, or a stylized "T" with exhaust speed lines. Orange/amber color palette (heat, speed, energy). Monospace font for "turbotoken".
- **Color:** `#FF6B00` (primary — turbo heat orange), `#1A1A2E` (dark bg), `#E8E8E8` (light text)
- **Font:** JetBrains Mono for code, Inter for copy
- **Motif:** Speed. Every visual asset should feel fast — motion blur, gradient streaks, exhaust trails.

---

## 2. PRODUCT OVERVIEW

### What It Is

turbotoken is a **drop-in replacement for tiktoken** built on hand-optimized ARM64 NEON assembly and Apple Metal / NVIDIA CUDA compute shaders. It provides identical output (byte-perfect compatibility) with 8-16× encoding speedup and 100×+ decoding speedup. First in the **turbo-tools** family of SIMD-accelerated developer utilities.

### Who It's For

1. **Coding agent developers** (Claude Code, Cursor, Aider, Codex, Cline, OpenCode) — saves 3-9 seconds per session on token counting
2. **LLM application developers** — context window management without latency tax
3. **ML pipeline engineers** — batch tokenization for training data at 40+ MB/s
4. **LLM API providers** — tokenize billing at hardware speed

### Why Now

| Fact | Source | Implication |
|------|--------|-------------|
| Taalas HC1 delivers 17K tok/s per user | [taalas.com/the-path-to-ubiquitous-ai](https://taalas.com/the-path-to-ubiquitous-ai/) | LLM inference collapses from 78% to 7.5% of agent time |
| tiktoken encodes 673K tokens in 368ms on M4 | [cotool.ai/blog/context-management](https://cotool.ai/blog/context-management) | Tokenization becomes 21% of non-test agent time |
| tiktoken encodes 678K tokens in 3,300ms on Cloud Run | Same source | Serverless agents spend MORE time tokenizing than on LLM inference |
| 10-turn agent loop spends 9.8s on pure encoding overhead | Same source | That's real user-facing latency |
| TokenDagger at 4× tiktoken earned 281 HN points | [news.ycombinator.com/item?id=41549649](https://news.ycombinator.com/item?id=41549649) | Proven audience for tokenizer speedup |
| No NEON-optimized BPE tokenizer exists publicly | Our research (see prior analysis) | Wide open opportunity |
| GitHub `bpe` crate achieves 4× with algorithmic improvements alone | [github.com/github/bpe](https://github.com/github/bpe) | NEON assembly on top of better algorithm = 8-16× |

---

## 3. TECHNICAL SPECIFICATIONS

### 3.1 Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                   turbotoken (Python)                      │
│                                                            │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  turbotoken.Encoding — tiktoken-compatible API      │  │
│  │  get_encoding() / encoding_for_model()              │  │
│  └──────────────────────┬──────────────────────────────┘  │
│                         │ C ABI (cffi / ctypes)           │
│  ┌──────────────────────┴──────────────────────────────┐  │
│  │              libturbotoken (C + Assembly)              │  │
│  │                                                      │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │  │
│  │  │ NEON BPE     │  │ NEON regex   │  │ Scalar    │  │  │
│  │  │ encoder      │  │ pre-tokenize │  │ fallback  │  │  │
│  │  │ (ARM64 .S)   │  │ (ARM64 .S)   │  │ (C11)     │  │  │
│  │  └──────────────┘  └──────────────┘  └───────────┘  │  │
│  │  ┌──────────────┐  ┌──────────────┐                  │  │
│  │  │ NEON decoder │  │ Flat-array   │                  │  │
│  │  │ (memcpy +    │  │ pair cache   │                  │  │
│  │  │  prefetch)   │  │ (4MB O(1))   │                  │  │
│  │  └──────────────┘  └──────────────┘                  │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              GPU Backends (optional)                  │  │
│  │  ┌───────────────┐  ┌────────────────┐               │  │
│  │  │ Metal compute │  │ CUDA kernels   │               │  │
│  │  │ (Apple M1-M4) │  │ (RTX 3090+)    │               │  │
│  │  └───────────────┘  └────────────────┘               │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### 3.2 Core Algorithm

**Encoding pipeline:**

1. **Pre-tokenization (NEON):** Replace tiktoken's Python regex (75% of CPU time) with NEON byte classification using `vtbl`/`vceq` instructions. Classify 16 bytes/cycle into character classes (letter, digit, whitespace, punctuation). Emit token boundaries without regex engine overhead.

2. **BPE merge (O(n) backtracking):** Adopt GitHub's `bpe` crate algorithm instead of tiktoken's O(n²) greedy merge. Use flat 4MB pair-cache array (inspired by mojo-tokenizer) for O(1) merge lookups, cache-line aligned for NEON `ld1`/`st1`.

3. **Token ID lookup:** Perfect hash or sorted array binary search with NEON-accelerated comparison.

**Decoding pipeline:**

4. **Lookup table decode (NEON):** Each token ID → byte sequence via flat lookup table. NEON `ld1`/`st1` with software prefetching (`prfm pldl1keep`). This is pure memcpy — the easiest path to 100×+ speedup.

**Key references for implementation:**
- GitHub `bpe` crate (O(n) algorithm): [github.com/github/bpe](https://github.com/github/bpe)
- TokenDagger (drop-in tiktoken replacement): [github.com/M4THYOU/TokenDagger](https://github.com/M4THYOU/TokenDagger) — proven `import token_dagger as tiktoken` pattern
- Mojo-based experiments (flat pair cache, 144M tok/s decode): [reddit.com/r/LocalLLaMA/comments/17...](https://www.reddit.com/r/LocalLLaMA/)
- tiktoken core.py (API surface to replicate): [github.com/openai/tiktoken/blob/main/tiktoken/core.py](https://github.com/openai/tiktoken/blob/main/tiktoken/core.py)
- tiktoken Rust core (implementation to beat): [github.com/openai/tiktoken/tree/main/src](https://github.com/openai/tiktoken/tree/main/src)
- ARM NEON intrinsics reference: [developer.arm.com/architectures/instruction-sets/intrinsics](https://developer.arm.com/architectures/instruction-sets/intrinsics/)

### 3.3 Supported Encodings

Ship with byte-perfect compatibility for all tiktoken encodings:

| Encoding | Models | Vocab Size | Priority |
|----------|--------|-----------|----------|
| `o200k_base` | GPT-4o, GPT-4o-mini, GPT-4.1 | 200,019 | **P0** — most used |
| `cl100k_base` | GPT-4, GPT-3.5-turbo, embeddings | 100,256 | **P0** — still widespread |
| `p50k_base` | Codex, text-davinci-002/003 | 50,281 | P1 |
| `r50k_base` (gpt2) | GPT-3, open-source models | 50,257 | P1 |

Merge tables are loaded from tiktoken's published `.tiktoken` rank files (same URLs, cached locally).

### 3.4 Platform Support Matrix

| Platform | CPU Backend | GPU Backend | Priority |
|----------|-------------|-------------|----------|
| macOS ARM64 (M1-M4) | NEON assembly | Metal compute shaders | **P0** |
| Linux ARM64 (Graviton, Ampere) | NEON assembly | — | **P0** |
| Linux x86_64 | SSE4.2/AVX2 C intrinsics | CUDA (sm_80+) | P1 |
| Windows x86_64 | SSE4.2/AVX2 C intrinsics | CUDA (sm_80+) | P2 |
| macOS x86_64 (Intel) | SSE4.2 C intrinsics | — | P2 |

### 3.5 Performance Targets

| Operation | tiktoken (baseline) | turbotoken Target | Speedup |
|-----------|-------------------|-----------------|---------|
| `encode()` — 1KB text | ~0.2ms | **<0.025ms** | **8×** |
| `encode()` — 100KB text | ~20ms | **<2.5ms** | **8×** |
| `encode()` — 673K tokens | 368ms (M4) | **<46ms** | **8×** |
| `encode()` — 678K tokens (Cloud Run) | 3,300ms | **<412ms** | **8×** |
| `decode()` — 1K tokens | ~0.05ms | **<0.0005ms** | **100×** |
| `decode()` — 128K tokens | ~6ms | **<0.06ms** | **100×** |
| `count()` — 673K tokens | 368ms | **<35ms** | **10×** |
| `encode_batch()` — 1K strings | ~200ms | **<25ms (CPU)** | **8×** |
| `encode_batch()` — 1K strings (GPU) | N/A | **<5ms (Metal)** | **40×** |

The `count()` method (returns only token count, no allocation) should be even faster than `encode()` since it avoids building the output list.

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

# Encoding class — FULL method parity
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

New methods that don't exist in tiktoken — the performance differentiators:

```python
class Encoding:
    # --- Fast count (no allocation) ---
    def count(self, text: str) -> int:
        """Return token count without building the token list.
        Avoids all list/array allocation. Fastest path for context window checks.
        Typically 10-30% faster than len(encode()).
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
        """Batch encode on GPU. 40×+ faster for large batches.
        Uses Metal on macOS, CUDA on Linux/Windows.
        Falls back to NEON CPU if GPU unavailable.
        """

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
        """Return active backend: 'neon', 'avx2', 'sse42', 'scalar', 'metal', 'cuda'."""

    @staticmethod
    def benchmark(encoding_name: str = "o200k_base") -> dict:
        """Run built-in benchmark. Returns dict with encode/decode/count MB/s."""
```

### 4.3 CLI Tool

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

# Benchmark
$ turbotoken bench
turbotoken v0.1.0 (backend: neon)
Encoding: o200k_base

encode    1KB:    0.023ms  (43.5 MB/s)    8.7× tiktoken
encode  100KB:    2.1ms    (47.6 MB/s)    9.5× tiktoken
decode    1K:     0.4µs    (512M tok/s)  102× tiktoken
count   673K:    32ms      (54.2 MB/s)   11.5× tiktoken

# Backend info
$ turbotoken info
Platform:  macOS arm64 (Apple M4 Max)
Backend:   ARM64 NEON + Apple Metal
Encodings: o200k_base, cl100k_base, p50k_base, r50k_base
GPU:       Apple M4 Max (40-core, 128GB unified)
```

---

## 5. IMPLEMENTATION PLAN

### Phase 1: NEON Encoder + Python Package (Weeks 1-3) — THE LAUNCH

**Week 1: Core C + Assembly**
- [ ] Scaffold C project: `src/`, `include/`, `asm/`, `python/`, `bench/`
- [ ] Implement flat pair-cache array (4MB, cache-aligned) from merge table files
- [ ] Implement O(n) backtracking BPE encoder in C (reference: GitHub `bpe` crate)
- [ ] Write NEON pre-tokenizer in ARM64 assembly: byte classification via `vtbl`/`vceq`, 16 bytes/cycle
- [ ] Write NEON decoder: `ld1`/`st1` from lookup table with `prfm` prefetch
- [ ] Scalar fallback for x86_64 (plain C, no SIMD — still faster than tiktoken via better algorithm)

**Week 2: Python Wrapper + Compatibility**
- [ ] cffi/ctypes bridge from C to Python
- [ ] Implement full `Encoding` class matching tiktoken API (Section 4.1)
- [ ] Load merge tables from tiktoken's `.tiktoken` rank file URLs (cache in `~/.cache/turbotoken/`)
- [ ] Implement `count()` fast path (no allocation)
- [ ] Write compatibility test suite: encode/decode roundtrip for all 4 encodings, verified byte-perfect against tiktoken
- [ ] Test against tiktoken's own test suite: [github.com/openai/tiktoken/blob/main/tests/test_encoding.py](https://github.com/openai/tiktoken/blob/main/tests/test_encoding.py)

**Week 3: Packaging + Benchmarks + Launch**
- [ ] Build wheels: `manylinux_2_17_aarch64`, `macosx_11_0_arm64`, `manylinux_2_17_x86_64`, `macosx_10_15_x86_64`, `win_amd64`
- [ ] Write benchmark suite (compare against tiktoken on varying input sizes)
- [ ] Write README, blog post, benchmark charts
- [ ] `pip install turbotoken` works on all platforms
- [ ] CLI tool (`turbotoken count`, `turbotoken bench`)
- [ ] **LAUNCH: PyPI + GitHub + HN + Twitter**

### Phase 2: Metal GPU Backend (Weeks 4-5)

- [ ] Metal compute shader for batch pre-tokenization
- [ ] Metal compute shader for batch BPE merge (BlockBPE-style independent chunks)
- [ ] `encode_gpu()` / `count_gpu()` methods
- [ ] Benchmark on M4 Max: target 40× batch speedup over tiktoken
- [ ] Blog post: "GPU tokenization on Apple Silicon — turbotoken goes Metal"

### Phase 3: CUDA Backend (Weeks 6-7)

- [ ] Port Metal shaders to CUDA kernels (sm_80+ for A100/H100/RTX 3090+)
- [ ] Benchmark on RTX 5090
- [ ] Blog post: "Tokenize 10GB/s on RTX 5090"

### Phase 4: AVX2/SSE Optimization (Week 8)

- [ ] x86_64 SIMD intrinsics for pre-tokenizer
- [ ] Benchmark on Intel/AMD
- [ ] Cover the "but I don't have ARM" crowd

### Phase 5: Language Bindings (Weeks 9-10)

- [ ] **npm package** (`turbotoken`): WASM + native NEON for Node.js — critical for Cursor/VS Code extensions
- [ ] **Rust crate** (`turbotoken`): thin wrapper over C core
- [ ] **Go module** (`turbotoken-go`): cgo wrapper

---

## 6. TESTING STRATEGY

### 6.1 Correctness (Non-Negotiable)

```python
# Every single test must pass before any release

# 1. Byte-perfect roundtrip for all encodings
for enc_name in ["o200k_base", "cl100k_base", "p50k_base", "r50k_base"]:
    kt = turbotoken.get_encoding(enc_name)
    tt = tiktoken.get_encoding(enc_name)
    for text in TEST_CORPUS:
        assert kt.encode(text) == tt.encode(text)
        assert kt.decode(kt.encode(text)) == text

# 2. Special token handling matches exactly
assert kt.encode("<|endoftext|>", allowed_special="all") == tt.encode(...)
assert kt.encode("<|endoftext|>", disallowed_special="all")  # raises

# 3. Edge cases
TEST_CORPUS = [
    "",                           # empty string
    " ",                          # single space
    "\n\n\n",                     # newlines
    "hello world",                # basic
    "hello  world",               # double space
    "🎉🔥💻",                    # emoji
    "こんにちは世界",              # Japanese
    "def foo():\n    pass\n",     # Python code
    "a" * 1_000_000,              # 1MB repeated char
    open("/dev/urandom").read(1000),  # random bytes
    LINUX_KERNEL_MAKEFILE,        # real large file
]

# 4. Batch encoding matches single encoding
texts = ["hello", "world", "test"]
assert kt.encode_batch(texts) == [kt.encode(t) for t in texts]
```

### 6.2 Performance (Benchmark CI)

Run on every PR against `main`:
- Encode/decode at 1KB, 10KB, 100KB, 1MB
- Compare against tiktoken (must be ≥4× faster on ARM64)
- Track regressions: fail CI if >5% slower than previous release

### 6.3 Fuzz Testing

```bash
# Use AFL or libFuzzer on the C core
# Must not crash, leak, or produce different output than tiktoken
```

---

## 7. DISTRIBUTION & PACKAGING

### 7.1 Python (PyPI)

```toml
# pyproject.toml
[project]
name = "turbotoken"
version = "0.1.0"
description = "ARM64 assembly BPE tokenizer. 8× faster than tiktoken."
readme = "README.md"
license = {text = "MIT"}
requires-python = ">=3.9"
keywords = ["tokenizer", "bpe", "tiktoken", "llm", "neon", "simd", "gpu"]
classifiers = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: C",
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

### 7.2 Wheel Matrix

Build pre-compiled wheels for every major platform (users should never need a C compiler):

```
turbotoken-0.1.0-cp39-cp39-macosx_11_0_arm64.whl        ← M1/M2/M3/M4
turbotoken-0.1.0-cp39-cp39-manylinux_2_17_aarch64.whl    ← Graviton/Ampere
turbotoken-0.1.0-cp39-cp39-manylinux_2_17_x86_64.whl     ← Intel/AMD Linux
turbotoken-0.1.0-cp39-cp39-macosx_10_15_x86_64.whl       ← Intel Mac
turbotoken-0.1.0-cp39-cp39-win_amd64.whl                 ← Windows# ... repeated for cp310, cp311, cp312, cp313, cp314
```

Use `cibuildwheel` + GitHub Actions for automated wheel building.

### 7.3 Repository Structure

```
turbotoken/
├── README.md
├── LICENSE                    # MIT
├── pyproject.toml
├── Cargo.toml                 # For Rust crate (Phase 5)
├── CMakeLists.txt             # C build system
│
├── include/
│   └── turbotoken.h           # Public C API
│
├── src/
│   ├── encoder.c              # BPE encoder (O(n) backtracking)
│   ├── decoder.c              # BPE decoder (lookup table)
│   ├── pretokenizer.c         # Pre-tokenization (scalar fallback)
│   ├── pair_cache.c           # Flat 4MB pair-cache array
│   ├── rank_loader.c          # Load .tiktoken merge tables
│   └── hash.c                 # Perfect hash for token lookup
│
├── asm/
│   ├── neon_pretokenizer.S    # ARM64 NEON pre-tokenizer
│   ├── neon_decoder.S         # ARM64 NEON decoder (memcpy + prefetch)
│   └── neon_classify.S        # ARM64 NEON byte classifier (vtbl/vceq)
│
├── gpu/
│   ├── metal/
│   │   ├── batch_encode.metal # Metal compute shader
│   │   └── batch_count.metal
│   └── cuda/
│       ├── batch_encode.cu    # CUDA kernel
│       └── batch_count.cu
│
├── python/
│   ├── turbotoken/
│   │   ├── __init__.py        # Public API: get_encoding, encoding_for_model
│   │   ├── core.py            # Encoding class (tiktoken-compatible)
│   │   ├── _native.py         # cffi/ctypes bridge to libturbotoken
│   │   ├── _registry.py       # Encoding name → model mapping
│   │   ├── _gpu.py            # Optional GPU backend
│   │   └── cli.py             # CLI tool
│   └── tests/
│       ├── test_compatibility.py  # Byte-perfect vs tiktoken
│       ├── test_encoding.py       # All methods
│       ├── test_batch.py          # Batch encoding
│       ├── test_edge_cases.py     # Unicode, emoji, empty, huge
│       └── test_benchmark.py      # Performance regression tests
│
├── bench/
│   ├── bench_encode.py        # Encoding benchmarks
│   ├── bench_decode.py        # Decoding benchmarks
│   ├── bench_comparison.py    # Head-to-head vs tiktoken
│   └── generate_charts.py     # Produce benchmark SVGs for README
│
├── docs/
│   ├── blog-post.md           # Launch blog post (Section 8)
│   ├── architecture.md        # Deep dive into NEON implementation
│   └── benchmarks.md          # Full benchmark results
│
└── .github/
    └── workflows/
        ├── ci.yml             # Test on every PR
        ├── wheels.yml         # Build wheels (cibuildwheel)
        └── benchmark.yml      # Performance regression check
```

---

## 8. MARKETING & LAUNCH COPY

### 8.1 README.md (above the fold)

```markdown
# turbotoken

**ARM64 assembly BPE tokenizer. 8× faster than tiktoken.**

When LLM inference hits 15,000 tok/s, tokenization becomes 21% of your agent's
wall-clock time. turbotoken eliminates that bottleneck.

​```python
# Drop-in replacement — zero code changes
import turbotoken as tiktoken

enc = tiktoken.get_encoding("o200k_base")
tokens = enc.encode("hello world")
text = enc.decode(tokens)
count = enc.count("how many tokens?")  # ← new: no-alloc fast path
​```

​```
$ pip install turbotoken
​```

## Benchmarks (Apple M4 Max)

| Operation | tiktoken | turbotoken | Speedup |
|-----------|----------|-----------|---------|
| Encode 1KB | 0.19ms | 0.023ms | **8.3×** |
| Encode 100KB | 19ms | 2.1ms | **9.0×** |
| Decode 128K tokens | 6.1ms | 0.058ms | **105×** |
| Count 673K tokens | 368ms | 32ms | **11.5×** |
| Batch encode 1K strings (GPU) | N/A | 4.8ms | **∞** |

→ Full benchmarks: [turbotoken.dev/benchmarks](https://turbotoken.dev/benchmarks)

## Why?

AI coding agents tokenize your code **10-30 times per session** for context
window management. At 150 tok/s inference, nobody noticed. At 15,000 tok/s,
tokenization is the bottleneck:

| @15K tok/s inference | Time | % of agent loop |
|----------------------|------|----------------|
| LLM inference | 4.7s | 27% |
| **Token counting** | **3.7s** | **21%** |
| Codebase search | 2.0s | 11% |

turbotoken gives you back those seconds. Every session. Every turn.

## Part of turbo-tools

turbotoken is the first in a family of SIMD-accelerated developer tools:
**turbotoken** → **turbodiff** → **turbogrep**
```

### 8.2 Launch Blog Post — Title Options

**Primary:** "The Hidden Tax: Token Counting Costs AI Agents 10 Seconds Per Session"

**Alternatives:**
- "When Inference Hits 15,000 tok/s, Everything Else Becomes the Bottleneck"
- "We Wrote an ARM64 Assembly Tokenizer. It's 8× Faster Than tiktoken."
- "Why Your Coding Agent Spends More Time Counting Tokens Than Thinking"
- "Turbocharged: How NEON Assembly Made Token Counting 8× Faster"

### 8.3 Blog Post Outline

1. **The hook** (2 paragraphs): Taalas ships 17K tok/s. Groq/Cerebras pushing 3K+. When LLM inference goes from minutes to milliseconds, what's left?

2. **The data** (charts): Show the bottleneck inversion. At 150 tok/s: LLM = 78.5%, tokenization = 1%. At 15K tok/s: LLM = 7.5%, tokenization = 21%. Include the Cotool production data (9.8s overhead).

3. **The problem** (3 paragraphs): tiktoken is Rust, which is fast. But its BPE algorithm is O(n²) greedy, its pre-tokenizer is a general-purpose regex, and it has zero SIMD optimization. It was written when tokenization was noise. That era is over.

4. **Our approach** (technical): NEON byte classification, O(n) backtracking, flat pair cache, prefetch-optimized decode. Link to architecture doc.

5. **The benchmarks** (chart): Head-to-head vs tiktoken at 1KB, 10KB, 100KB, 1MB. Show the decode speedup (100×+) separately — it's the attention grabber.

6. **Drop-in usage** (code snippet): Show `import turbotoken as tiktoken` and the `count()` fast path.

7. **What's next**: Metal GPU batch encoding, CUDA, npm package. Open source, MIT licensed, contributions welcome.

### 8.4 HN Submission

**Title:** "Turbotoken: ARM64 assembly BPE tokenizer, 8× faster than tiktoken"

**Show HN comment:**
> At 17K tok/s inference (Taalas HC1), tokenization becomes 21% of your coding agent's wall-clock time. We built turbotoken — a drop-in tiktoken replacement powered by ARM64 NEON assembly. Encodes at 40 MB/s, decodes at 500M+ tok/s. `pip install turbotoken`, then `import turbotoken as tiktoken`. MIT licensed. [link to benchmarks]

### 8.5 Tweet / X Thread

**Launch tweet:**
> tiktoken: 368ms to encode 673K tokens.
> turbotoken: 32ms.
>
> ARM64 NEON assembly. Drop-in replacement.
> pip install turbotoken
>
> When inference hits 15,000 tok/s, the tokenizer IS the bottleneck.
> So we turbocharged it. [chart image] [link]

**Thread:**
1. The hook (above)
2. "Coding agents tokenize your code 10-30× per session. At 15K tok/s inference (Taalas, Cerebras), that's 21% of wall-clock time. More than codebase search. Nearly as much as inference itself."
3. Benchmark chart image (encode + decode + count vs tiktoken)
4. "How: NEON byte classification (16 bytes/cycle), O(n) backtracking BPE, flat pair-cache, prefetch-optimized decode. Hand-written ARM64 assembly."
5. "Drop-in: `import turbotoken as tiktoken`. Zero code changes. Byte-perfect output. MIT licensed."
6. "This is the first turbo-tool. turbodiff and turbogrep are next. Star us: [github link]"

### 8.6 Product Hunt

**Tagline:** "Drop-in tiktoken replacement. 8× faster. ARM64 assembly inside."
**Description:** "When LLM inference hits 15,000 tok/s, your tokenizer becomes the bottleneck. turbotoken is a drop-in tiktoken replacement built on hand-optimized ARM64 NEON assembly. Encodes at 40 MB/s, decodes at 500M+ tok/s. `pip install turbotoken` — zero code changes. First in the turbo-tools family."

---

## 9. SUCCESS METRICS

### Launch Week (Week 3)
- [ ] 500+ GitHub stars
- [ ] 200+ HN points
- [ ] 1,000+ PyPI downloads
- [ ] 5+ community bug reports (means people are using it)

### Month 1
- [ ] 5,000+ GitHub stars
- [ ] 10,000+ PyPI downloads/week
- [ ] 1+ integration PR to a major project (Aider, LiteLLM, LangChain, etc.)
- [ ] 3+ independent benchmark confirmations

### Month 3
- [ ] 20,000+ GitHub stars
- [ ] Mentioned in at least 2 coding agent READMEs
- [ ] npm package live (for Cursor/VS Code ecosystem)
- [ ] GPU batch encoding shipped (Metal + CUDA)

---

## 10. COMPETITIVE LANDSCAPE

| Project | Language | Speed vs tiktoken | Drop-in? | SIMD? | GPU? | Status |
|---------|----------|-------------------|----------|-------|------|--------|
| **tiktoken** | Rust+Python | 1× (baseline) | — | No | No | Production |
| **TokenDagger** | Python/Rust | 2-4× | Yes ✅ | No | No | Active |
| **bpe-openai** | Rust | ~4× | No ❌ | No | No | Crate only |
| **GitHub `bpe`** | Rust | 4× | No ❌ | No | No | Library only |
| **HuggingFace tokenizers** | Rust+Python | 0.3-0.5× | No ❌ | No | No | Production |
| **Mojo Experiments** | Mojo | ~10× decode | No ❌ | Mojo SIMD | No | Experimental |
| **NVIDIA RAPIDS cuDF** | CUDA | 270× (WordPiece only) | No ❌ | N/A | Yes ✅ | No BPE |
| **turbotoken** | **C + ARM64 ASM** | **8-16×** | **Yes ✅** | **Yes ✅** | **Yes ✅** | **Shipping** |

**Our moat:** Only project combining (1) hand-optimized assembly, (2) GPU batch, (3) drop-in tiktoken compatibility, and (4) the O(n) algorithm. TokenDagger has compatibility but not SIMD. GitHub `bpe` has the algorithm but no packaging or Python API. We have all four.

---

## 11. RISK REGISTER

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| tiktoken changes API in new version | Medium | High | Pin compatibility to tiktoken 0.7-0.12. Track releases. |
| OpenAI adds new encoding (o300k?) | Medium | Medium | Architecture supports arbitrary merge tables. Add within days. |
| NEON speedup lower than expected | Low | High | Algorithm improvement alone (O(n) backtrack) gives 4× even without SIMD. |
| GPU batch not useful for interactive agents | Medium | Low | GPU is Phase 2 bonus. Core value is CPU NEON speed. |
| Someone else ships similar first | Low | High | Move fast. Phase 1 in 3 weeks. First-mover with benchmarks wins. |
| Correctness bugs | Medium | Critical | Fuzz testing + byte-perfect comparison against tiktoken on every CI run. |

---

## 12. OPEN QUESTIONS

1. **License:** MIT (maximum adoption) vs Apache 2.0 (patent protection)? Recommendation: **MIT** — tiktoken is MIT, TokenDagger is MIT, minimizes friction.

2. **Build system:** CMake vs Meson vs plain Makefile? Recommendation: **CMake** — best cibuildwheel integration.

3. **Python bridge:** cffi vs ctypes vs pybind11? Recommendation: **cffi** — no compile dependency for users, lighter than pybind11.

4. **Should we vendor merge tables or download on first use?** Recommendation: **Download on first use** (same as tiktoken) with offline fallback. Vendoring 4× ~5MB tables bloats the wheel.

5. **Org name:** `turbo-tools` (brand family org) vs personal GitHub? Recommendation: **`turbo-tools` org** — establishes the brand family for turbotoken, turbodiff, turbogrep. Professional, scalable, allows multiple repos.

---

## 13. REFERENCE LINKS

### Core Implementation References
- tiktoken source (the target to beat): https://github.com/openai/tiktoken
- tiktoken core.py (API to replicate): https://github.com/openai/tiktoken/blob/main/tiktoken/core.py
- tiktoken test suite (correctness oracle): https://github.com/openai/tiktoken/blob/main/tests/test_encoding.py
- GitHub `bpe` crate (O(n) algorithm): https://github.com/github/bpe
- TokenDagger (drop-in pattern proof): https://github.com/SuperpoweredAI/token-dagger
- mojo-tokenizer (flat cache, fast decode): https://github.com/dorjeduck/mojo-tokenizer

### ARM64 NEON References
- ARM NEON intrinsics: https://developer.arm.com/architectures/instruction-sets/intrinsics/
- ARM64 assembly guide: https://developer.arm.com/documentation/102374/latest
- NEON optimization guide: https://developer.arm.com/documentation/den0018/latest

### GPU Compute References
- Metal Shading Language spec: https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf
- Metal compute tutorial: https://developer.apple.com/documentation/metal/performing_calculations_on_a_gpu
- CUDA programming guide: https://docs.nvidia.com/cuda/cuda-c-programming-guide/

### Market / Bottleneck Evidence
- Taalas 17K tok/s announcement: https://taalas.com/the-path-to-ubiquitous-ai/
- Cotool tokenization latency measurements: https://cotool.ai/blog/context-management
- Morph Fast Apply (apply bottleneck): https://www.morphllm.com/blog/morph-breaks-10k-barrier
- Factory.ai context window problem: https://factory.ai/news/context-window-problem
- Agent token consumption research (ICLR 2026): https://openreview.net/forum?id=1bUeVB3fov
- Agent tool output overhead: https://dev.to/teppana88/your-ai-coding-agents-are-slow-because-your-tools-talk-too-much-24h6

### Packaging / Distribution
- cibuildwheel: https://cibuildwheel.readthedocs.io/
- PyPI publishing: https://packaging.python.org/en/latest/guides/publishing-package-distribution-releases-using-github-actions-ci-cd-workflows/
- manylinux: https://github.com/pypa/manylinux
