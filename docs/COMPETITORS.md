# turbotoken -- Competitive Analysis

> Deep analysis of every BPE tokenizer we compete with.
> Updated as competitors release new versions or new entrants appear.

---

## Landscape Overview

```
                        Speed (faster ->)
                        |
  HuggingFace           |   tiktoken      TokenDagger    GitHub bpe    rs-bpe     turbotoken
  tokenizers            |                                                          (target)
  0.3-0.5x              |   1x baseline   2-4x           4x            2-15x      8-16x
  |                     |   |             |              |             |           |
  +---------------------+---+-------------+--------------+-------------+-----------+-->
                        |
                        |   WASM space:
                        |   tiktoken.js   gpt-tokenizer  wasm-tokenizer  turbotoken WASM
                        |   0.3x          0.5x           1.5x            3-5x (target)
```

---

## Competitor #1: tiktoken (OpenAI)

> **The baseline. The target to beat. The API to replicate.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/openai/tiktoken |
| **Language** | Rust core + Python bindings (PyO3) |
| **License** | MIT |
| **PyPI** | `tiktoken` |
| **npm** | `tiktoken` (JS/WASM bindings via `tiktoken/js`) |
| **Stars** | ~12K+ |
| **Last Release** | Track at https://pypi.org/project/tiktoken/#history |

### Strengths
- **De facto standard** -- used by OpenAI, LangChain, LlamaIndex, nearly every LLM tool
- Rust core is fast for a non-SIMD implementation
- Well-tested, production-hardened
- Defines the encoding formats (`.tiktoken` rank files)
- `encoding_for_model()` maps model names to encodings

### Weaknesses We Exploit
- **O(n^2) greedy BPE algorithm** -- quadratic scaling on adversarial input
- **No SIMD optimization** -- leaves 8-16x on the table
- **Python regex pre-tokenizer** -- 75% of CPU time in the hot path
- **No GPU batch encoding** -- CPU only
- **No `count()` fast path** -- must allocate full token list even for counting
- **~50ms cold startup** -- Rust extension + merge table loading
- **~2MB wheel size** -- Rust binary bloat

### API Surface (what we replicate)
- `get_encoding(name) -> Encoding`
- `encoding_for_model(model) -> Encoding`
- `list_encoding_names() -> list[str]`
- `Encoding.encode()`, `.encode_ordinary()`, `.encode_batch()`, etc.
- `Encoding.decode()`, `.decode_bytes()`, `.decode_batch()`, etc.
- Full special token handling (`allowed_special`, `disallowed_special`)

### Version Tracking
| Version | Date | Notable Changes | Compat Impact |
|---------|------|----------------|---------------|
| | | | |
> Fill as we track releases.

---

## Competitor #2: rs-bpe

> **Closest algorithmic competitor. Linear scaling. Python bindings.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/gweidart/rs-bpe |
| **Language** | Rust + Python bindings |
| **License** | MIT |
| **PyPI** | `rs-bpe` |
| **Key claim** | 15x faster on small text, linear scaling vs tiktoken's quadratic |

### Strengths
- Linear-time BPE algorithm (similar to GitHub `bpe` crate approach)
- Python bindings available
- Excellent on small inputs where startup amortization matters

### Weaknesses We Exploit
- **No SIMD optimization** -- pure Rust, no hand-tuned assembly
- **No GPU batch encoding**
- **No `count()` fast path**
- **Not a drop-in tiktoken replacement** -- different API
- **No WASM build**
- **Smaller community** -- fewer eyes, less testing

### Our Advantage
Take their algorithmic insight (O(n) backtracking) and add NEON/AVX/Metal/CUDA on top.
Algorithm alone = 4x. Algorithm + SIMD = 8-16x.

---

## Competitor #3: GitHub `bpe` Crate

> **The algorithm reference. We adopt their approach.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/github/bpe |
| **Blog** | https://github.blog/ai-and-ml/llms/so-many-tokens-so-little-time-introducing-a-faster-more-flexible-byte-pair-tokenizer/ |
| **Language** | Rust |
| **License** | MIT |
| **crates.io** | `bpe` |
| **Key claim** | 4x faster via O(n) backtracking algorithm |

### Strengths
- Well-documented algorithm with blog post
- Proven 4x improvement over tiktoken
- Clean Rust implementation, good reference code
- GitHub's engineering stamp of quality

### Weaknesses We Exploit
- **Rust crate only** -- no Python package, no npm, no CLI
- **No SIMD optimization**
- **No GPU batch**
- **Not a drop-in replacement** -- different API entirely
- **Library only** -- must integrate into your own code

### Our Relationship
We adopt their algorithmic approach (O(n) backtracking) as our core algorithm,
then add platform-specific SIMD, GPU, and WASM on top. We cite them in our docs.

---

## Competitor #4: TokenDagger

> **Closest in positioning -- drop-in tiktoken replacement.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/SuperpoweredAI/token-dagger |
| **Language** | Python + Rust |
| **License** | MIT |
| **PyPI** | `tokendagger` (repo name: token-dagger) |
| **Key claim** | Drop-in tiktoken replacement, 2-4x faster |

### Strengths
- **Drop-in compatible** -- `import token_dagger as tiktoken` works
- Proven pattern for tiktoken replacement
- Earned 281 HN points -- validated community interest

### Weaknesses We Exploit
- **Only 2-4x faster** -- we target 8-16x
- **No SIMD optimization**
- **No GPU batch encoding**
- **No WASM build**
- **No `count()` fast path**
- Algorithmically limited (still relatively standard BPE)

### Our Advantage
Same drop-in story but 4x faster than them (8x vs 2x over tiktoken).
Plus GPU, WASM, multi-platform SIMD.

---

## Competitor #5: HuggingFace `tokenizers`

> **The "enterprise" tokenizer. Feature-rich but slower.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/huggingface/tokenizers |
| **Language** | Rust + Python bindings |
| **License** | Apache 2.0 |
| **PyPI** | `tokenizers` |
| **Stars** | ~9K+ |

### Strengths
- Supports many tokenizer types beyond BPE (WordPiece, Unigram, etc.)
- Deep HuggingFace ecosystem integration
- Training API (can train new tokenizers)
- Well-maintained by large company

### Weaknesses We Exploit
- **0.3-0.5x tiktoken speed for BPE** -- significantly slower
- General-purpose design sacrifices BPE-specific optimization
- Heavy dependency chain
- Not a tiktoken drop-in replacement

### Our Positioning
We don't compete on features. We compete on raw BPE speed.
If you need to train tokenizers or use WordPiece, use HuggingFace.
If you need the fastest possible BPE for tiktoken-compatible encodings, use turbotoken.

---

## Competitor #6: gpt-tokenizer (JavaScript)

> **Fastest pure JS tokenizer. Our main JS competitor.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/niieani/gpt-tokenizer |
| **Language** | TypeScript |
| **License** | MIT |
| **npm** | `gpt-tokenizer` |
| **Key claim** | Fastest JavaScript BPE tokenizer on npm (since v2.4.0) |

### Strengths
- Pure JavaScript -- no WASM, no native deps
- Works everywhere JS runs (browser, Node, Bun, Deno, Cloudflare Workers)
- Good TypeScript types
- Active maintenance

### Weaknesses We Exploit
- **Pure JS** -- can't match WASM performance for compute-heavy work
- Limited by V8's JIT for byte-level operations
- No SIMD of any kind

### Our WASM Advantage
Zig WASM (unified codebase, same src/*.zig) should be 3-10x faster than pure JS for BPE encoding.
Our npm package includes Zig WASM binary + JS fallback.

---

## Competitor #7: wasm-tokenizer (Script-Heads)

> **C++ compiled to WASM. Current WASM speed champion.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/script-heads/wasm-tokenizer |
| **Language** | C++ -> WASM (Emscripten) |
| **License** | MIT |
| **npm** | `wasm-tokenizer` |
| **Key claim** | Most performant tokenizer in its class |

### Strengths
- C++ core compiled to WASM -- faster than pure JS
- Optimized binary format (60% smaller token database)
- Works in browser and Node.js

### Weaknesses We Exploit
- **Emscripten WASM binary is larger** than Zig's zero-runtime freestanding output
- **No native backend** -- WASM only, even on Node.js where native would be faster
- **Not a tiktoken drop-in** -- different API

### Our Advantage
We provide native (NEON/AVX) for Node.js + WASM for browser.
Our Zig WASM (wasm32-freestanding, zero runtime) should have a smaller binary than their Emscripten build.

---

## Competitor #8: tiktoken npm (JS/WASM)

> **Official tiktoken WASM bindings for JavaScript.**

| Property | Value |
|----------|-------|
| **npm** | `tiktoken` |
| **Language** | Rust -> WASM |
| **Key claim** | Official tiktoken for JS |

### Strengths
- Official -- same Rust core as Python tiktoken
- Same encoding files and behavior

### Weaknesses We Exploit
- **Slow** -- ~0.3x the speed of Python tiktoken (WASM overhead)
- **Large WASM binary** -- Rust -> WASM produces 500KB+ binaries
- **Slow startup** -- WASM instantiation + merge table loading

---

## Competitor #9: BlockBPE (Research)

> **GPU parallel BPE. Research paper, not a product.**

| Property | Value |
|----------|-------|
| **Paper** | https://arxiv.org/html/2507.11941v1 |
| **Language** | CUDA |
| **Status** | Research (2025) |
| **Key contribution** | Demonstrates parallel BPE on GPU is feasible with near-linear time |

### Relevance to Us
BlockBPE proves our GPU approach is sound. We implement a production version
of their ideas in our Metal and CUDA backends.

---

## Competitor #10: mojo-tokenizer

> **Mojo SIMD experiments. Incredible decode speed.**

| Property | Value |
|----------|-------|
| **Repo** | https://github.com/dorjeduck/mojo-tokenizer |
| **Language** | Mojo |
| **Key claim** | 144M tok/s decode on M3 Ultra |

### Relevance to Us
- Proves 144M tok/s decode is achievable on Apple Silicon
- Flat pair-cache array design inspired our approach
- Mojo's SIMD is nice but ecosystem is too immature
- We achieve similar speeds via Zig @Vector(16, u8) + hand-tuned NEON assembly

---

## Feature Comparison Matrix

| Feature | tiktoken | rs-bpe | TokenDagger | GH bpe | HF tokenizers | gpt-tokenizer | wasm-tokenizer | turbotoken |
|---------|----------|--------|-------------|--------|---------------|---------------|----------------|------------|
| Drop-in tiktoken API | -- | No | **Yes** | No | No | Partial | No | **Yes** |
| O(n) algorithm | No (O(n^2)) | **Yes** | No | **Yes** | No | No | No | **Yes** |
| ARM64 NEON SIMD | No | No | No | No | No | No | No | **Yes** |
| x86 AVX2/512 SIMD | No | No | No | No | No | No | No | **Yes** |
| Apple Metal GPU | No | No | No | No | No | No | No | **Yes** |
| NVIDIA CUDA GPU | No | No | No | No | No | No | No | **Yes** |
| WASM (browser) | Yes (slow) | No | No | No | No | -- (pure JS) | **Yes** | **Yes** |
| `count()` fast path | No | No | No | No | No | No | No | **Yes** |
| RISC-V support | No | No | No | No | No | No | No | **Yes** (Phase 6) |
| CLI tool | No | No | No | No | No | No | No | **Yes** |
| Zero dependencies | Yes | Yes | No | N/A | No | Yes | Yes | **Yes** |
| Hyperfine benchmarks | No | No | No | No | No | No | No | **Yes** |

---

## Version Tracking Dashboard

> Track latest versions of all competitors. Check weekly.

| Package | Latest Version | Date Checked | PyPI/npm Link |
|---------|---------------|-------------|---------------|
| tiktoken | | | https://pypi.org/project/tiktoken/ |
| rs-bpe | | | https://pypi.org/project/rs-bpe/ |
| tokendagger | | | https://pypi.org/project/tokendagger/ |
| tokenizers (HF) | | | https://pypi.org/project/tokenizers/ |
| gpt-tokenizer | | | https://www.npmjs.com/package/gpt-tokenizer |
| wasm-tokenizer | | | https://www.npmjs.com/package/wasm-tokenizer |
| tiktoken (npm) | | | https://www.npmjs.com/package/tiktoken |

---

## Threat Watch

> New entrants or significant updates that could affect our positioning.

| Date | Threat | Assessment | Action Needed |
|------|--------|-----------|---------------|
| -- | -- | -- | -- |

---

## Sources

- tiktoken: https://github.com/openai/tiktoken
- rs-bpe: https://github.com/gweidart/rs-bpe
- GitHub bpe: https://github.com/github/bpe
- GitHub bpe blog: https://github.blog/ai-and-ml/llms/so-many-tokens-so-little-time-introducing-a-faster-more-flexible-byte-pair-tokenizer/
- TokenDagger: https://github.com/SuperpoweredAI/token-dagger
- HuggingFace tokenizers: https://github.com/huggingface/tokenizers
- gpt-tokenizer: https://github.com/niieani/gpt-tokenizer
- wasm-tokenizer: https://github.com/script-heads/wasm-tokenizer
- compare-tokenizers: https://github.com/transitive-bullshit/compare-tokenizers
- tiktoken npm: https://www.npmjs.com/package/tiktoken
- BlockBPE paper: https://arxiv.org/html/2507.11941v1
- mojo-tokenizer: https://github.com/dorjeduck/mojo-tokenizer
