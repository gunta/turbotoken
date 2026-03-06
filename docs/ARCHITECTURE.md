# turbotoken -- Architecture & Technical Decisions

> Documents every major technical decision, tradeoff, and architectural choice.
> Each entry has context, options considered, decision, and rationale.

---

## Decision Log

| # | Decision | Date | Status |
|---|----------|------|--------|
| ADR-001 | Core language: Zig + hand-written assembly per target | 2026-02-24 | ACCEPTED (revised) |
| ADR-002 | Build system: build.zig (Zig's built-in) | 2026-02-24 | ACCEPTED (revised) |
| ADR-003 | Python bridge: cffi (via Zig C ABI export) | 2026-02-24 | ACCEPTED (revised) |
| ADR-004 | BPE algorithm: O(n) backtracking | 2026-02-24 | ACCEPTED |
| ADR-005 | Merge table storage: flat array + hash fallback | 2026-02-24 | ACCEPTED |
| ADR-006 | WASM strategy: Zig unified (same codebase) | 2026-02-24 | ACCEPTED (revised) |
| ADR-007 | Script language: Bun Shell TypeScript | 2026-02-24 | ACCEPTED |
| ADR-008 | Benchmark tool: Hyperfine | 2026-02-24 | ACCEPTED |
| ADR-009 | Phase ordering: NEON > Metal > WASM > AVX > CUDA > RVV | 2026-02-24 | ACCEPTED |
| ADR-010 | Merge table loading: embedded native core payloads + download fallback | 2026-02-24 | ACCEPTED (revised) |

---

## ADR-001: Core Language -- Zig + Hand-Written Assembly

### Context
Need a language for the core tokenizer that can:
1. Be called from Python, Node.js, Rust, Go, and WASM
2. Allow hand-written assembly for each target ISA
3. Produce small binaries
4. Compile fast
5. Compile to WASM from the same codebase (unified architecture)
6. Provide portable SIMD without sacrificing peak performance

### Options Considered

| Option | Pros | Cons |
|--------|------|------|
| C + Assembly | Universal ABI, hand-tune assembly, tiny binaries, compiles fast | Manual memory management, no safety guarantees, no WASM unification, no portable SIMD |
| Rust | Memory safety, good ecosystem, existing BPE crates | Can't easily mix hand-written assembly, larger binaries, slower compile, WASM binaries are large |
| **Zig + Assembly** | `@Vector` portable SIMD, `comptime` tables, C ABI export, WASM unification, small binaries, safety in debug mode, hand-written `.S` for peak paths | Pre-1.0 language, smaller ecosystem, cibuildwheel uncharted territory |
| C++ | SIMD intrinsics, templates | Larger binaries, complex build, ABI issues |
| Mojo | Built-in SIMD, fast | Immature ecosystem, no stable ABI, not embeddable |

### Decision
**Zig + hand-written assembly files (`.S`) per target ISA.**

### Rationale
- **WASM unification:** Same Zig codebase compiles to `wasm32-freestanding` -- no separate MoonBit/Emscripten build needed
- **`@Vector` portable SIMD:** `@Vector(16, u8)` compiles to NEON on ARM64, SSE/AVX on x86, scalar on WASM -- one source, optimal codegen per target
- **`comptime` table generation:** Merge tables and hash functions computed at compile time -- zero runtime initialization cost
- **C ABI export:** `export fn` makes Zig functions callable from Python cffi, Node N-API, cgo, Rust FFI -- same FFI story as C
- **Safety without runtime cost:** Bounds checking, overflow detection in Debug/ReleaseSafe modes. `ReleaseFast` strips all checks for production.
- **Hand-written `.S` assembly:** Zig's build system supports `.S` files natively. For the hottest 5% of code (NEON pre-tokenizer, AVX inner loops), hand-written assembly squeezes the last few percent.
- **Cross-compilation:** `zig build -Dtarget=aarch64-linux` cross-compiles from any host. No separate toolchain needed.
- **Tiny binaries:** No runtime, no GC, no allocator unless opted-in. WASM binaries as small as Zig's stdlib allows.

### Risks Accepted
- Zig is pre-1.0: breaking changes possible. Mitigated by pinning Zig version.
- Smaller contributor pool than C/Rust. Mitigated by clear architecture docs.
- cibuildwheel integration untested. Mitigated by Zig's `zig cc` which can act as a C compiler drop-in.

---

## ADR-002: Build System -- build.zig

### Context
Need cross-platform build system that works with Zig's native toolchain and can produce Python wheels.

### Options
| Option | Pros | Cons |
|--------|------|------|
| CMake | cibuildwheel native support, widespread | Verbose syntax, external dependency, doesn't understand Zig natively |
| Meson | Clean syntax, fast | Less cibuildwheel documentation, no Zig support |
| Make | Simple, universal | Not cross-platform, no dependency management |
| **build.zig** | Native Zig, built-in cross-compilation, zero external dependencies, handles `.S` assembly | Less cibuildwheel documentation, newer ecosystem |

### Decision
**`build.zig`** (Zig's built-in build system) as the primary build system.

### Rationale
- **Native Zig integration:** `build.zig` understands Zig source, `.S` assembly, and compilation targets natively
- **Cross-compilation is free:** `zig build -Dtarget=aarch64-linux` works from any host without installing cross-toolchains
- **Zero external dependencies:** No CMake, no Make, no autotools. Just `zig build`.
- **Assembly file support:** `build.zig` can add `.S` assembly files to compilation units directly
- **WASM target:** `zig build -Dtarget=wasm32-freestanding` produces WASM from the same `build.zig`
- **Python wheel strategy:** Use `scikit-build-core` with Zig invoked as the compiler, or custom `scripts/build-wheels.ts` that calls `zig build` per target and packages results
- **CI integration:** `zig build test` runs all tests. Simple, fast, reproducible.

---

## ADR-003: Python Bridge -- cffi (via Zig C ABI Export)

### Context
Need Python bindings for the Zig core library.

### Options
| Option | Pros | Cons |
|--------|------|------|
| **cffi** | No compile at install, ABI mode, lightweight | Slightly slower than pybind11 for complex types |
| ctypes | Built into Python | Verbose, manual type declarations |
| pybind11 | C++ wrapper, good ergonomics | Requires C++ compiler at install, heavier |
| PyO3 | Rust-native Python bindings | We're not using Rust |
| SWIG | Multi-language | Complex setup, generates bloated code |

### Decision
**cffi in ABI mode** -- load Zig-compiled `.dylib`/`.so` at runtime.

### How Zig exports C ABI:
```zig
// src/exports.zig
export fn turbotoken_encode(
    enc: *Encoding,
    text: [*]const u8,
    text_len: usize,
    out: [*]u32,
    out_cap: usize,
) usize {
    // Zig implementation called from Python cffi
    return enc.encode(text[0..text_len], out[0..out_cap]);
}
```

### Rationale
- **Zig's `export fn` produces C ABI symbols** -- identical to what a C compiler would produce
- Users never need a compiler installed (pre-compiled wheels)
- ABI mode is simpler than API mode
- cffi handles cross-platform library loading (`.dylib` on macOS, `.so` on Linux, `.dll` on Windows)
- Performance overhead of cffi vs ctypes is negligible for our call patterns (few large calls, not many tiny calls)
- **Zig's C ABI export is zero-cost** -- no wrapper layer, no marshaling

---

## ADR-004: BPE Algorithm -- O(n) Backtracking

### Context
tiktoken uses O(n^2) greedy BPE. Need a faster algorithm that produces identical output.

### Options
| Option | Complexity | Speedup | Same output? |
|--------|-----------|---------|-------------|
| tiktoken's greedy | O(n^2) | 1x (baseline) | Yes (definition) |
| **O(n) backtracking** (GitHub bpe) | O(n) | 4x | Yes (proven) |
| Parallel chunk BPE (BlockBPE) | O(n/p) | GPU: 40x+ | Yes (with boundary stitching) |
| Greedy with caching | O(n^2) worst | 1.5-2x | Yes |

### Decision
**O(n) backtracking** (as described in GitHub bpe crate), with BlockBPE for GPU backends.

### Rationale
- 4x improvement from algorithm alone -- before any SIMD
- Proven to produce identical output (byte-perfect)
- Algorithm + NEON SIMD = 8-16x
- BlockBPE extends naturally for GPU parallel encoding
- rs-bpe independently validates the approach with 2-15x claims

---

## ADR-005: Merge Table Storage -- Flat Array + Hash Fallback

### Context
BPE encoding requires looking up (token_a, token_b) -> merged_token for every merge step. Need fast lookups.

### Options
| Option | Lookup | Memory | Cache Behavior |
|--------|--------|--------|---------------|
| Hash table (open addressing) | O(1) avg | ~6MB | Poor (random access) |
| **Flat array (most common pairs)** | O(1) | ~4MB | Excellent (sequential) |
| Perfect hash (CHD) | O(1) | ~2MB | Good |
| Sorted array + binary search | O(log n) | ~5MB | Moderate |
| Trie | O(k) | ~8MB | Poor |

### Decision
**4MB flat array for the top ~1M most common merge pairs, hash table fallback for rare pairs.**

### Rationale
- Flat array is SIMD-friendly (sequential access pattern, NEON `ld1`/`st1`)
- 4MB fits in L2 cache on all target CPUs
- Covers >99% of merge lookups in practice (real text uses common pairs)
- Hash fallback ensures correctness for edge cases
- Inspired by mojo-tokenizer's approach (proven 144M tok/s decode)

---

## ADR-006: WASM Strategy -- Zig Unified (Same Codebase)

### Context
Need WASM build for browser and edge runtimes. With the Zig decision (ADR-001), we now have a unique advantage: the same codebase can compile to WASM.

### Options
| Option | Binary Size | Runtime Perf | Build Complexity | Code Reuse | Ecosystem Maturity |
|--------|-------------|-------------|------------------|-----------|-------------------|
| **Zig -> wasm32-freestanding** | ~80-150KB | Good | **Zero** (same build.zig) | **100%** (same code!) | Medium |
| MoonBit -> WASM-GC | ~150-200KB | Comparable to Rust | Medium (separate codebase) | 0% | Low (young) |
| Emscripten (via Zig C ABI) | ~250-350KB | Good | Low | ~80% | High |
| Rust -> wasm-pack | ~500KB+ | Good | Medium | 0% | High |
| AssemblyScript | ~400KB | Moderate | Low | 0% | Medium |

### Decision
**Zig -> `wasm32-freestanding` as primary. MoonBit and Emscripten as comparison builds for documentation.**

### Rationale
- **Unified codebase:** The exact same `src/*.zig` files compile to both native and WASM. Zero code duplication.
- **Zero runtime overhead:** `wasm32-freestanding` produces a WASM binary with no libc, no GC, no runtime. Just our code.
- **Smallest possible binary:** Zig's `ReleaseSmall` optimization + no runtime = potentially the smallest WASM tokenizer binary ever
- **WASM SIMD:** Zig's `@Vector` can target the WASM SIMD proposal (128-bit vectors), giving us SIMD in the browser
- **`comptime` works in WASM too:** Merge table hash functions are computed at compile time regardless of target
- **One `build.zig` to rule them all:** `zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall` produces WASM. No new tools.
- **MoonBit kept for comparison:** We still build MoonBit WASM to compare binary sizes and perf. Document results in WASM-EXPLORATION.md.

### WASM SIMD Opportunity
```zig
// This Zig code compiles to WASM SIMD instructions when targeting wasm32:
const v: @Vector(16, u8) = input_bytes.*;
const mask = v == @as(@Vector(16, u8), @splat(' '));
// On wasm32: becomes i8x16.eq instruction
// On aarch64: becomes vceqq_u8 (NEON)
// On x86_64: becomes _mm_cmpeq_epi8 (SSE2)
```

---

## ADR-007: Script Language -- Bun Shell TypeScript

### Context
Need scripting for benchmarks, upstream sync, chart generation, CI orchestration.

### Options
| Option | Cross-platform | Type Safety | Ecosystem | Maintainability |
|--------|---------------|-------------|-----------|-----------------|
| Bash | Poor (Windows) | None | Limited | Low |
| Python | Good | Optional (mypy) | Excellent | Medium |
| **Bun Shell TypeScript** | Good | Yes (TypeScript) | Good (npm) | High |
| Node.js scripts | Good | Optional | Excellent | Medium |
| Make | Moderate | None | Limited | Low |
| Just (justfile) | Good | None | Limited | Medium |

### Decision
**All scripts in Bun Shell TypeScript (`.ts` files).**

### Rationale
- Cross-platform: macOS, Linux, Windows (Bun runs everywhere)
- Type safety and IDE autocomplete (TypeScript)
- Built-in shell execution via `$` tagged template literals
- Shell injection protection via Bun Shell's auto-escaping
- Easy JSON handling for Hyperfine output processing
- Built-in glob, fetch, and file I/O
- One fewer language in the repo (vs separate Bash + Python scripts)
- Bun is fast enough that script startup is negligible

---

## ADR-008: Benchmark Tool -- Hyperfine

### Context
Need rigorous, reproducible benchmarks comparing turbotoken to all competitors.

### Options
| Option | Statistical Rigor | Comparison | Export | CLI Benchmarks |
|--------|------------------|-----------|--------|---------------|
| Python `timeit` | Basic (mean, stddev) | Manual | No | No |
| **Hyperfine** | Excellent (mean, median, stddev, min, max, outlier detection) | Built-in | JSON, MD, CSV | Yes |
| `perf stat` | Excellent | Manual | No | Linux only |
| Google Benchmark | Excellent | Built-in | JSON | C++ only |
| criterion.rs | Excellent | Built-in | HTML | Rust only |

### Decision
**Hyperfine for all CLI benchmarks. Python `timeit` as supplement for in-process micro-benchmarks.**

### Rationale
- Hyperfine handles warmup, shell correction, statistical analysis automatically
- JSON export feeds directly into our chart generation scripts
- Markdown export produces README-ready comparison tables
- Parameterized sweeps (`-P`) for input size scaling tests
- Industry standard -- results are credible to HN/Twitter audience
- Works for any executable (Python scripts, native binaries, Node.js, WASM)

---

## ADR-009: Phase Ordering

### Context
Six backends to build. What order maximizes impact and learning?

### Decision
1. **ARM64 NEON** -- optimize for dev machine (M4 Max), fastest iteration
2. **Apple Metal** -- GPU on same machine, builds on Phase 1 learnings
3. **MoonBit WASM** -- broadest reach (browsers), independent codebase
4. **x86 AVX2/512** -- cover Intel/AMD, apply SIMD learnings from NEON
5. **NVIDIA CUDA** -- requires different hardware, builds on Metal GPU learnings
6. **RISC-V RVV** -- future-proofing, lowest priority, can run on QEMU

### Rationale
- "Optimize for what you have at hand" -- M4 Max is our primary dev machine
- Metal is same machine, so Phases 1+2 need zero hardware changes
- WASM is Phase 3 because it's independent (MoonBit codebase is separate)
- AVX follows NEON because the SIMD concepts transfer (just different instructions)
- CUDA requires dedicated GPU hardware (may need cloud instance)
- RISC-V is lowest priority because real hardware is scarce

---

## ADR-010: Merge Table Loading

### Context
tiktoken encoding definitions include large merge tables (5MB for o200k_base). Where to store them?

### Options
| Option | Wheel Size | First Run | Offline |
|--------|-----------|-----------|---------|
| Vendor every rank file in wheel | +20MB | Instant | Works |
| Download on first use | No change | +2s (one time) | Fails (needs fallback) |
| **Embed native payloads for core encodings; download others** | +~3.3MB (Python wheel) | Instant for `o200k`/`cl100k`; +2s for others | Works for core encodings |
| Download at install time | No change | +2s (one time) | Fails |
| Git LFS | N/A | Depends | Depends |

### Decision
**Embed native rank payloads for `o200k_base`, `o200k_harmony`, and `cl100k_base` in the Python package; keep download-on-first-use fallback for the remaining rank files and cache materialized `.tiktoken` files in `~/.cache/turbotoken/`.**

### Rationale
- Keeps the hottest Python encodings available offline with no first-run network dependency
- Native binary payloads are smaller than vendoring every text rank file while still feeding the Zig loader directly
- `Encoding.ensure_rank_file()` remains compatible by materializing a canonical `.tiktoken` file only when explicitly requested
- Remaining lower-priority encodings still use the tiktoken-style download/cache path instead of bloating the wheel further

---

## Architecture Diagrams

### Data Flow: encode("hello world")

```
Input: "hello world" (UTF-8 bytes)
          |
          v
[1. Pre-tokenizer (Zig @Vector -- NEON/AVX/WASM SIMD/scalar)]
   - Classify each byte: letter/digit/space/punct
   - Emit chunk boundaries: ["hello", " world"]
   - Zig @Vector compiles to optimal SIMD per target: 16-64 bytes/cycle
          |
          v
[2. For each chunk: BPE merge (O(n) backtracking)]
   - Look up merge pairs in flat array / hash table
   - Apply merges in priority order with backtracking
   - Produce token IDs per chunk
   - "hello" -> [15339]
   - " world" -> [1917]
          |
          v
[3. Concatenate token arrays]
   - [15339, 1917]
          |
          v
Output: [15339, 1917]
```

### Data Flow: decode([15339, 1917])

```
Input: [15339, 1917]
          |
          v
[1. Lookup table decode (NEON/AVX/scalar)]
   - For each token ID, load (byte_ptr, byte_len) from flat table
   - SIMD memcpy to output buffer with prefetch
   - 15339 -> "hello" (5 bytes)
   - 1917 -> " world" (6 bytes)
          |
          v
[2. UTF-8 validation (optional)]
   - Verify output is valid UTF-8
   - Handle errors per `errors` parameter
          |
          v
Output: "hello world"
```

### Memory Layout: Flat Pair-Cache Array

```
+-----------------------------------------------+
| Flat array: 4MB, 64-byte cache-line aligned    |
|                                                |
| Index: hash(token_a, token_b) % ARRAY_SIZE    |
| Value: merged_token_id (u32) or EMPTY (0xFFFF) |
|                                                |
| [slot 0] [slot 1] [slot 2] ... [slot N]       |
| Each slot: 4 bytes (u32)                       |
|                                                |
| Cache behavior:                                |
| - Sequential access pattern during merge loop  |
| - NEON ld1/st1 for vectorized access          |
| - prfm pldl1keep for prefetch                 |
| - 4MB fits in L2 cache (M4 Max has 48MB L2)  |
+-----------------------------------------------+
         |
         | (cache miss for rare pairs)
         v
+------------------------+
| Hash table fallback    |
| Open addressing        |
| For rare merge pairs   |
| ~2MB additional        |
+------------------------+
```

### Backend Selection (compile-time via build.zig + runtime)

```
build.zig (compile-time target selection)
    |
    +-- target == aarch64-macos / aarch64-linux
    |   +-- Compile: src/arch/aarch64.zig + asm/arm64/*.S + src/arch/generic.zig (fallback)
    |   +-- Output: libturbotoken.dylib / libturbotoken.so
    |   +-- Zig @Vector(16, u8) compiles to NEON instructions automatically
    |
    +-- target == x86_64-linux / x86_64-windows
    |   +-- Compile: src/arch/x86_64.zig + asm/x86_64/*.S + src/arch/generic.zig (fallback)
    |   +-- Output: libturbotoken.so / turbotoken.dll
    |   +-- Zig @Vector(32, u8) compiles to AVX2, @Vector(64, u8) to AVX-512
    |   +-- Runtime CPU feature detection via Zig std.Target.x86
    |       +-- AVX-512BW available? -> use avx512 path
    |       +-- AVX2 available? -> use avx2 path
    |       +-- else -> use scalar path (src/arch/generic.zig)
    |
    +-- target == wasm32-freestanding
    |   +-- Compile: src/arch/wasm.zig + src/arch/generic.zig
    |   +-- Output: turbotoken.wasm (no .js glue needed!)
    |   +-- @Vector(16, u8) may compile to WASM SIMD if enabled
    |
    +-- target == riscv64-linux
        +-- Compile: src/arch/riscv.zig + asm/riscv/*.S + src/arch/generic.zig (fallback)
        +-- Output: libturbotoken.so
        +-- Runtime: check RVV support via hwcap

Python (runtime)
    |
    +-- import turbotoken
    +-- _native.py loads libturbotoken.{dylib,so,dll} via cffi
    +-- Zig's export fn provides C ABI symbols
    +-- turbotoken.backend() -> "neon" | "avx2" | "avx512" | "scalar" | "wasm" | "rvv"
```
