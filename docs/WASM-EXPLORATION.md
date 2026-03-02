# turbotoken -- WASM Exploration

> Deep comparison of all WebAssembly compilation paths for turbotoken.
> **Decision: Zig unified build is PRIMARY.** MoonBit and Emscripten are comparison builds.
> Goal: find the smallest binary with the best runtime performance.

---

## The Challenge

We need a WASM build that:
1. Runs in all browsers (Chrome, Firefox, Safari, Edge)
2. Runs in Node.js / Bun / Deno
3. Has the smallest possible binary (CDN delivery matters)
4. Is as fast as possible for BPE encoding/decoding
5. Loads and initializes quickly (Time To First Token)

## Implemented Baseline (2026-03-02)

- Zig WASM build step now emits `zig-out/bin/turbotoken.wasm` via `zig build wasm`.
- JS loader (`wrappers/js/src/wasm-loader.ts`) instantiates the module and calls exported Zig C-ABI symbols directly.
- JS `Encoding` now has async WASM+BPE methods (`encodeAsync`, `decodeAsync`, `countAsync`) with rank payload loading.
- JS now also exposes WASM training wrappers (`trainBpeFromChunkCounts`, `trainBpeFromChunks`).
- `scripts/bench-wasm.ts` now reports startup latency, throughput (MB/s), and peak RSS rows.
- npm-minimal WASM target is now emitted from Zig (`zig-out/bin/turbotoken-npm.wasm`) with `wasm-opt` size gating.
- automated cross-toolchain size comparison is now wired:
  - `bun run bench:wasm:comparisons`
  - latest artifact: `bench/results/bench-wasm-comparisons-1772455001727.json`
- browser competitor benchmark page + headless runner are now wired:
  - page: `bench/browser/wasm-competitors.html`
  - runner: `bun run bench:browser:competitors`
  - latest artifact: `bench/results/bench-browser-competitors-1772455163556.json`

This is still an optimization-stage baseline, not a final browser package release.

## The Zig Advantage

With our decision to use Zig as the core language (ADR-001), we get a unique WASM story:
**The same codebase that compiles to native ARM64/x86 also compiles to WASM.**

No separate WASM implementation. No code duplication. One `build.zig`, every target.

---

## Candidates

### 1. Zig -> wasm32-freestanding (PRIMARY)

| Property | Value |
|----------|-------|
| **Language** | Zig (same as native core!) |
| **WASM target** | `wasm32-freestanding` (linear memory, zero runtime) |
| **Expected binary size** | ~80-150KB |
| **Build command** | `zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall` |
| **Homepage** | https://ziglang.org/learn/wasm/ |

**Why this is the winner:**
- **Unified codebase:** Exact same `src/*.zig` files. Zero code duplication.
- **Zero runtime:** No libc, no GC, no allocator overhead. Just our code.
- **Smallest binary:** Zig's `ReleaseSmall` + no runtime = potentially smallest WASM tokenizer ever
- **WASM SIMD:** Zig's `@Vector(16, u8)` can target WASM SIMD (128-bit vectors in browsers)
- **`comptime` tables:** Merge table hash functions computed at compile time, embedded in binary
- **No JS glue:** Unlike Emscripten, no `.js` helper file needed

**Considerations:**
- Need explicit memory management for WASM (Zig's allocators handle this cleanly)
- WASM SIMD support requires relatively recent browsers (2021+)
- No WASM-GC (not needed -- Zig manages memory explicitly)
- May need custom WASM imports for merge table loading (fetch from CDN)

**Build commands:**
```bash
# Smallest binary (optimized for size)
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall

# Fastest binary (optimized for speed)
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseFast

# Optional: further shrink with wasm-opt
wasm-opt -Oz zig-out/lib/turbotoken.wasm -o turbotoken-opt.wasm
```

**WASM SIMD example:**
```zig
// This Zig code compiles to WASM SIMD on wasm32 target:
const input: @Vector(16, u8) = bytes.*;
const spaces = input == @as(@Vector(16, u8), @splat(' '));
// Becomes: i8x16.eq (WASM SIMD instruction)
```

**Evaluation criteria:**
- [ ] Binary size: `ReleaseSmall` vs `ReleaseFast` vs `ReleaseSmall` + `wasm-opt`
- [ ] Encode 100KB text speed vs other approaches
- [ ] Decode 128K tokens speed
- [ ] Startup / instantiation time
- [ ] WASM SIMD perf vs scalar WASM
- [ ] Browser compatibility matrix
- [ ] Memory usage in browser

### 2. MoonBit -> WASM-GC (COMPARISON ONLY)

| Property | Value |
|----------|-------|
| **Language** | MoonBit |
| **WASM target** | WASM-GC (garbage collected) |
| **Expected binary size** | ~150-200KB |
| **Build command** | `moon build --target wasm-gc` |
| **Homepage** | https://www.moonbitlang.com/ |

**Why we still build this (for comparison):**
- MoonBit is designed WASM-first (not a retrofit)
- Whole-program optimization may produce interesting size/perf tradeoffs
- Good for documenting our approach vs the "WASM-native language" approach
- Validates our claim that Zig produces smaller WASM

**Why NOT primary:**
- Separate codebase from Zig core = maintenance burden
- WASM-GC requires recent browser versions (Chrome 119+, Firefox 120+, Safari 17.4+)
- GC pauses could affect tokenization latency
- No code reuse with our native builds

**Evaluation criteria:**
- [ ] Binary size after `moon build --target wasm-gc`
- [ ] Encode 100KB text speed vs Zig WASM
- [ ] GC pause frequency and duration during encoding
- [ ] Browser compatibility matrix (WASM-GC requirement)

### 3. Emscripten (via Zig C ABI Export) (COMPARISON ONLY)

| Property | Value |
|----------|-------|
| **Language** | Zig -> C ABI -> Emscripten |
| **WASM target** | Linear memory WASM |
| **Expected binary size** | ~250-350KB |
| **Build command** | `emcc` on Zig-compiled `.o` files |
| **Homepage** | https://emscripten.org/ |

**Why we still build this (for comparison):**
- Emscripten is the most mature C-to-WASM toolchain
- Zig's `export fn` C ABI works with Emscripten's linker
- Good reference point for "what if we used the standard approach?"

**Why NOT primary:**
- Larger binary (Emscripten runtime overhead + libc shims)
- Requires `.js` glue code (more total package size)
- More complex build pipeline (Zig -> .o -> Emscripten -> .wasm + .js)
- No WASM SIMD via Emscripten's C ABI path

**Evaluation criteria:**
- [ ] Binary size: `.wasm` only vs `.wasm` + `.js` glue
- [ ] Encode 100KB text speed vs Zig native WASM
- [ ] Startup / instantiation time (includes JS glue parsing)

### 4. Rust -> wasm-pack (REFERENCE ONLY)

| Property | Value |
|----------|-------|
| **Language** | Rust |
| **WASM target** | `wasm32-unknown-unknown` |
| **Expected binary size** | ~400-600KB |
| **Build command** | `wasm-pack build --target web` |

**Why we track this:**
- tiktoken npm already uses this approach (tiktoken.js)
- Sets our "smaller than" target -- we MUST beat 500KB
- Useful as performance baseline

### 5. AssemblyScript (NOT BUILDING)

Eliminated from consideration. With Zig as the unified core, AssemblyScript offers no advantage. Larger binaries, slower performance, separate codebase.

---

## Comparison Matrix (Updated for Zig Decision)

| Approach | Expected Binary | Expected Perf vs tiktoken.js | Build Complexity | Code Reuse with Native | Status |
|----------|----------------|------------------------------|-----------------|----------------------|--------|
| **Zig (PRIMARY)** | ~80-150KB | 5-10x | **Zero** (same build.zig) | **100%** | **SHIP** |
| MoonBit | ~150-200KB | 5-10x | Medium (new language) | 0% | Compare |
| Emscripten | ~250-350KB | 3-5x | Low (via Zig C ABI) | ~80% | Compare |
| Rust | ~400-600KB | 2-3x | Medium | 0% | Reference |
| AssemblyScript | ~300-500KB | 1-2x | Low | 0% | Eliminated |

---

## Evaluation Plan

### Phase 3a: Zig WASM Build (Week 6) -- PRIMARY

```
Day 1: Add wasm32-freestanding target to build.zig
Day 2: Test compilation of full src/*.zig for WASM
Day 3: Write WASM-specific arch file (src/arch/wasm.zig)
Day 4: Measure binary size (ReleaseSmall, ReleaseFast, wasm-opt)
Day 5: Write JS/TS wrapper (wrappers/js/wasm-loader.ts)
Day 6: Test WASM SIMD via @Vector(16, u8)
Day 7: Browser benchmark page
```

### Phase 3b: Comparison Builds (Week 7, if time)

```
Day 1: MoonBit WASM build (hello world + BPE)
Day 2: Emscripten build from Zig C ABI exports
Day 3: Measure all binary sizes, compile comparison table
Day 4: Run same benchmark suite on all WASM builds
Day 5: Document results in this file
```

### Decision Framework

```
Zig WASM is PRIMARY because:
  1. Same codebase (100% code reuse)
  2. Smallest expected binary
  3. Zero build complexity (same build.zig)
  4. WASM SIMD via @Vector

Build MoonBit and Emscripten for DOCUMENTATION ONLY:
  - To prove our binary size claims
  - To have comparison numbers for blog posts / HN
  - To validate the unified-codebase approach is actually better
```

---

## Benchmark Results

> Fill as we build each approach.

### Binary Size Comparison

| Approach | .wasm size | .js glue | Total package | Notes |
|----------|-----------|----------|--------------|----------------|
| Zig full (`turbotoken.wasm`) | `1,642,265 B` | None | included in npm tarball | from `bench-wasm-comparisons-1772455001727.json` |
| Zig npm-minimal (`turbotoken-npm.wasm`) | `1,170 B` | None | included in npm tarball | `wasm-opt` result, below `150KB` gate |
| MoonBit (`wasm-gc`) | `59 B` | None | standalone | current benchmark project is intentionally minimal/no-op main |
| Emscripten (C byte-path shim) | `7,182 B` | None | standalone | built from `bench/wasm/emscripten/utf8_tokenizer.c` |
| npm package dry-run (`turbotoken@0.1.0-dev`) | N/A | N/A | `811.5 kB` tarball / `1.7 MB` unpacked | from `npm publish --dry-run --tag dev` |

### Encode Speed (Browser, o200k_base, 1MiB text)

| Approach | Mean | Median | Stddev | vs tiktoken.js |
|----------|------|--------|--------|----------------|
| turbotoken (WASM full BPE, browser) | `106.47 ms` (1MiB) | N/A | N/A | `9.39 MiB/s` (`bench-browser-competitors-1772455163556.json`) |
| gpt-tokenizer (browser) | `11.70 ms` (1MiB) | N/A | N/A | `85.47 MiB/s` (`bench-browser-competitors-1772455163556.json`) |
| js-tiktoken (browser) | `151.80 ms` (1MiB) | N/A | N/A | `6.59 MiB/s` (`bench-browser-competitors-1772455163556.json`) |
| wasm-tokenizer (browser) | N/A | N/A | N/A | module import failed in this run (`esm.sh/wasm-tokenizer@latest`) |

### Startup (Browser, first encode of `"hello"`)

| Approach | Mean |
|----------|------|
| turbotoken (WASM full BPE) | `8.5 ms` |
| gpt-tokenizer | `613.2 ms` |
| js-tiktoken | `1414.2 ms` |

### Decode Speed (o200k_base, 128K tokens, Node.js)

| Approach | Mean | Median | Stddev | vs tiktoken.js |
|----------|------|--------|--------|----------------|
| tiktoken.js | PENDING | PENDING | PENDING | 1x |
| Zig WASM | PENDING | PENDING | PENDING | PENDING |
| MoonBit WASM | PENDING | PENDING | PENDING | PENDING |
| Emscripten WASM | PENDING | PENDING | PENDING | PENDING |

### Startup Time (time to first encode of "hello", Node.js)

| Approach | Mean | Notes |
|----------|------|-------|
| tiktoken.js | PENDING | WASM instantiation + merge table |
| Zig WASM | PENDING | WASM instantiation + merge table |
| MoonBit WASM | PENDING | WASM-GC instantiation + merge table |
| Emscripten WASM | PENDING | WASM + JS glue parsing + merge table |

### Browser Performance (Chrome, encode 10KB)

| Approach | Mean | Notes |
|----------|------|-------|
| tiktoken.js | PENDING | |
| gpt-tokenizer | PENDING | Pure JS |
| wasm-tokenizer | PENDING | |
| Zig WASM (scalar) | PENDING | |
| Zig WASM (SIMD) | PENDING | |
| MoonBit WASM | PENDING | |

---

## WASM SIMD Browser Compatibility

> Zig `@Vector` can target WASM SIMD. Check browser support.

| Browser | WASM SIMD | Version | Notes |
|---------|-----------|---------|-------|
| Chrome | Yes | 91+ (May 2021) | Stable, widely deployed |
| Firefox | Yes | 89+ (May 2021) | Stable |
| Safari | Yes | 16.4+ (Mar 2023) | Stable |
| Edge | Yes | 91+ (May 2021) | Chromium-based |
| Node.js | Yes | 16.4+ | V8-based |
| Bun | Yes | 1.x | JSC-based |
| Deno | Yes | 1.9+ | V8-based |
| Cloudflare Workers | Yes | V8 isolates | WASM SIMD supported |

**Fallback strategy:** If WASM SIMD is not available (very old browser), fall back to scalar WASM path.
Unlike WASM-GC (which MoonBit requires), WASM SIMD has near-universal support.

---

## WASM-GC Browser Compatibility (MoonBit requirement)

> MoonBit targets WASM-GC. Narrower support than WASM SIMD.

| Browser | WASM-GC Support | Version | Notes |
|---------|----------------|---------|-------|
| Chrome | Yes | 119+ (Nov 2023) | Stable |
| Firefox | Yes | 120+ (Nov 2023) | Stable |
| Safari | Yes | 17.4+ (Mar 2024) | Stable |
| Edge | Yes | 119+ (Nov 2023) | Chromium-based |
| Node.js | Yes | 22+ | V8-based |

**Note:** WASM-GC browser support is narrower than WASM SIMD.
This is another reason Zig (linear memory WASM) is preferred over MoonBit (WASM-GC).

---

## References

- Zig WASM guide: https://ziglang.org/learn/wasm/
- Zig @Vector docs: https://ziglang.org/documentation/master/#Vectors
- WASM SIMD proposal: https://github.com/WebAssembly/simd
- MoonBit homepage: https://www.moonbitlang.com/
- MoonBit vs Rust WASM size: https://thenewstack.io/moonbit-wasm-optimized-language-creates-less-code-than-rust/
- Emscripten docs: https://emscripten.org/docs/
- wasm-tokenizer (Emscripten reference): https://github.com/script-heads/wasm-tokenizer
- HuggingFace tokenizers WASM porting: https://blog.mithrilsecurity.io/porting-tokenizers-to-wasm/
- WASM-GC proposal: https://github.com/nicolo-ribaudo/tc39-proposal-structs/blob/main/README.md
- State of WASM 2025-2026: https://platform.uno/blog/the-state-of-webassembly-2025-2026/
