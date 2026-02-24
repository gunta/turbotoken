# turbotoken -- Progress Tracker

> Master progress document. Updated as work happens.
> Each phase has a checklist, status, blockers, and links to relevant commits/PRs.

---

## Status Summary

| Phase | Name | Status | Progress | Target | Actual |
|-------|------|--------|----------|--------|--------|
| 1 | ARM64 NEON + Python | `IN PROGRESS` | 8/19 | Weeks 1-3 | -- |
| 2 | Apple Metal GPU | `NOT STARTED` | 0/5 | Weeks 4-5 | -- |
| 3 | Zig WebAssembly (unified) | `IN PROGRESS` | 1/10 | Weeks 6-7 | -- |
| 4 | x86_64 AVX2/AVX-512 | `NOT STARTED` | 0/5 | Weeks 8-9 | -- |
| 5 | NVIDIA CUDA | `NOT STARTED` | 0/4 | Weeks 10-11 | -- |
| 6 | RISC-V Vector (RVV) | `NOT STARTED` | 0/4 | Weeks 12-13 | -- |
| 7+ | Language Bindings | `NOT STARTED` | 0/5 | Weeks 14+ | -- |

**Legend:** `NOT STARTED` | `IN PROGRESS` | `BLOCKED` | `DONE`

---

## Phase 1: ARM64 NEON + Python Package (Weeks 1-3)

> Primary dev target: Apple M4 Max. Optimize for what we have in hand.

### Week 1: Core Zig + ARM64 Assembly

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 1.1 | Scaffold project structure (`src/`, `src/arch/`, `asm/arm64/`, `python/`, `bench/`, `scripts/`, `build.zig`) | `DONE` | Scaffold committed with working directory layout |
| 1.2 | Implement flat pair-cache array (4MB, cache-aligned, `comptime`-generated) | `IN PROGRESS` | Added 4MB flat hash-array cache implementation + Zig tests in `src/pair_cache.zig`; merge-table `comptime` generation still pending |
| 1.3 | Implement O(n) backtracking BPE encoder in Zig | `TODO` | Reference: GitHub `bpe` crate + rs-bpe |
| 1.4 | Write NEON pre-tokenizer: Zig `@Vector(16, u8)` + hand-written ARM64 `.S` | `TODO` | `src/arch/aarch64.zig` + `asm/arm64/neon_pretokenizer.S` |
| 1.5 | Write NEON decoder (`ld1`/`st1` + `prfm` prefetch) in ARM64 assembly | `TODO` | `asm/arm64/neon_decoder.S` |
| 1.6 | Scalar Zig fallback (no SIMD `@Vector`) | `TODO` | `src/arch/generic.zig` -- still beats tiktoken via O(n) algo |
| 1.7 | Set up Hyperfine benchmark scripts (Bun Shell TS) | `DONE` | `scripts/bench-*.ts` now run benchmarks with JSON output + manual fallback |
| 1.8 | Clone tiktoken upstream as git submodule | `DONE` | Added `upstream/tiktoken` git submodule and updated `scripts/sync-upstream.ts` to manage it via `git submodule update --remote` |
| 1.9 | `build.zig` with multi-target support | `DONE` | Added cross-target build steps for macOS/Linux ARM64, Linux x86_64, wasm32-freestanding |

### Week 2: Python Wrapper + Compatibility

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 1.10 | cffi bridge from Zig (via `export fn` C ABI) to Python | `DONE` | cffi bridge is wired and loads native symbols from `zig-out/lib/libturbotoken.*` after `zig build` (`turbotoken_version`, `turbotoken_count`) |
| 1.11 | Implement full `Encoding` class (tiktoken API parity) | `IN PROGRESS` | `python/turbotoken/core.py` now includes broad API surface (batch/special-token/decode-bytes/numpy hooks), but still placeholder byte-token behavior |
| 1.12 | Load merge tables from `.tiktoken` rank file URLs | `DONE` | Added `python/turbotoken/_rank_files.py` with URL download, cache in `~/.cache/turbotoken/`, and rank-file parsing |
| 1.13 | Implement `count()` fast path (no allocation) | `DONE` | `count()` now runs allocation-free placeholder counting with special-token handling and native C ABI probe fallback |
| 1.14 | Sync and adapt tiktoken's test suite | `IN PROGRESS` | `scripts/sync-upstream.ts` now syncs upstream and emits adapted smoke test in `python/tests/upstream/` |
| 1.15 | Byte-perfect comparison tests vs tiktoken | `IN PROGRESS` | Added `scripts/compat-report.ts`; latest run records mismatch baseline across all 4 encodings while placeholder backend remains active |

### Week 3: Packaging + Benchmarks + Launch

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 1.16 | Build wheels via Zig cross-compilation (`macosx_11_0_arm64`, `manylinux_2_17_aarch64`, x86_64 scalar, win_amd64 scalar) | `TODO` | Zig cross-compile |
| 1.17 | Run full Hyperfine benchmark suite, generate charts | `IN PROGRESS` | `scripts/bench-all.ts` + `scripts/generate-charts.ts` now run; Hyperfine binary still missing in local env |
| 1.18 | Write README + benchmark page + architecture doc | `TODO` | |
| 1.19 | CLI tool (`turbotoken count/bench/info/encode/decode`) | `DONE` | Added `bench` + `info` subcommands; `count`/`encode`/`decode` already wired |

**Launch Checklist:**
- [ ] `pip install turbotoken` works on macOS ARM64
- [ ] `pip install turbotoken` works on Linux ARM64
- [ ] `pip install turbotoken` works on Linux x86_64 (scalar fallback)
- [ ] `import turbotoken as tiktoken` passes all tiktoken tests
- [ ] Benchmark charts generated and committed
- [ ] README complete with benchmark table
- [ ] HN post drafted
- [ ] Tweet/X thread drafted
- [ ] PyPI published

---

## Phase 2: Apple Metal GPU Backend (Weeks 4-5)

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 2.1 | Metal 4 compute shader for batch pre-tokenization | `TODO` | `gpu/metal/batch_encode.metal` |
| 2.2 | Metal compute shader for batch BPE merge (BlockBPE-style) | `TODO` | Independent chunks |
| 2.3 | `encode_gpu()` / `count_gpu()` Python methods | `TODO` | |
| 2.4 | Hyperfine benchmarks: Metal vs NEON CPU vs tiktoken | `TODO` | |
| 2.5 | Blog post: Metal GPU tokenization | `TODO` | `docs/metal-gpu.md` |

---

## Phase 3: Zig WebAssembly -- Unified Build (Weeks 6-7)

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 3.1 | Add `wasm32-freestanding` target to `build.zig` | `DONE` | Added explicit wasm32-freestanding cross-target build step |
| 3.2 | WASM-specific optimizations in `src/arch/wasm.zig` | `TODO` | Scalar + WASM SIMD |
| 3.3 | Explore WASM SIMD via Zig `@Vector(16, u8)` on wasm32 | `TODO` | 128-bit SIMD in browser |
| 3.4 | Target: <150KB WASM binary (ReleaseSmall + wasm-opt) | `TODO` | Zero runtime overhead |
| 3.5 | JS/TS wrapper: `js/wasm-loader.ts` with ES module export | `TODO` | |
| 3.6 | npm package: `turbotoken` with WASM auto-loaded | `TODO` | `package.json` |
| 3.7 | Browser benchmark page | `TODO` | vs tiktoken.js, gpt-tokenizer, wasm-tokenizer |
| 3.8 | MoonBit WASM comparison build (for docs only) | `TODO` | Document in `WASM-EXPLORATION.md` |
| 3.9 | Binary size + perf comparison (all WASM approaches) | `TODO` | Zig vs MoonBit vs Emscripten |
| 3.10 | Blog post: Zig WASM unified build deep dive | `TODO` | `docs/zig-wasm.md` |

---

## Phase 4: x86_64 AVX2/AVX-512 (Weeks 8-9)

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 4.1 | AVX2 pre-tokenizer via Zig `@Vector(32, u8)` + hand-written `.S` | `TODO` | `src/arch/x86_64.zig` + `asm/x86_64/*.S` |
| 4.2 | AVX-512BW pre-tokenizer (`vpermb`, 64 bytes/cycle) | `TODO` | Where available |
| 4.3 | AVX2 decoder (`vmovdqu` + streaming stores) | `TODO` | |
| 4.4 | Runtime CPU feature detection (AVX-512 -> AVX2 -> SSE4.2 -> scalar) | `TODO` | |
| 4.5 | Hyperfine benchmarks on Intel Xeon + AMD Ryzen | `TODO` | |

---

## Phase 5: NVIDIA CUDA Backend (Weeks 10-11)

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 5.1 | CUDA BlockBPE kernel (sm_80+) | `TODO` | `gpu/cuda/batch_encode.cu` |
| 5.2 | Shared memory merge table for coalesced access | `TODO` | |
| 5.3 | Benchmarks on RTX 4090 / A100 | `TODO` | |
| 5.4 | Blog post: GPU tokenization at scale | `TODO` | |

---

## Phase 6: RISC-V Vector Extension (Weeks 12-13)

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 6.1 | RVV 1.0 pre-tokenizer (vector-length-agnostic) | `TODO` | `asm/riscv/rvv_pretokenizer.S` |
| 6.2 | RVV decoder (scalable vector load/store) | `TODO` | |
| 6.3 | Test on QEMU RVV emulation | `TODO` | |
| 6.4 | Hyperfine benchmarks (baseline on emulation) | `TODO` | |

---

## Phase 7+: Language Bindings

| # | Task | Status | Notes / Commit |
|---|------|--------|----------------|
| 7.1 | Rust crate (`turbotoken`) -- thin FFI wrapper | `TODO` | |
| 7.2 | Go module (`turbotoken-go`) -- cgo wrapper | `TODO` | |
| 7.3 | Swift package -- direct Metal integration | `TODO` | iOS/macOS apps |
| 7.4 | C# / .NET P/Invoke wrapper | `TODO` | Unity/game dev |
| 7.5 | turbodiff / turbogrep planning | `TODO` | Next turbo-tools |

---

## Blockers Log

| Date | Blocker | Phase | Resolution | Resolved? |
|------|---------|-------|------------|-----------|
| 2026-02-24 | Local Zig 0.15.1 is not compatible with current 0.13-style build API (`addStaticLibrary`) | 1 | Migrated build config to support modern `addLibrary`/`root_module` flow and updated `build.zig.zon`; `zig build` + `zig build test` now pass locally. | Yes |
| -- | -- | -- | -- | -- |

---

## Key Decisions Log

| Date | Decision | Alternatives Considered | Rationale |
|------|----------|------------------------|-----------|
| 2026-02-24 | MIT license | Apache 2.0 | tiktoken is MIT, minimize friction |
| 2026-02-24 | **Zig + Assembly** as core language | C + Assembly, Rust | `@Vector` portable SIMD, `comptime` tables, WASM unification, C ABI export |
| 2026-02-24 | **`build.zig`** build system | CMake, Meson | Native Zig, built-in cross-compilation, zero external deps |
| 2026-02-24 | cffi Python bridge (via Zig C ABI export) | ctypes, pybind11 | No compile dependency, lighter |
| 2026-02-24 | Download merge tables on first use | Vendor in wheel | Same as tiktoken, avoids bloat |
| 2026-02-24 | Bun Shell TypeScript for all scripts | Bash, Python, Makefile | Cross-platform, type-safe, maintainable |
| 2026-02-24 | Hyperfine for all benchmarks | Python timeit only | Statistical rigor, JSON export, reproducible |
| 2026-02-24 | **Zig WASM unified** (same codebase) | MoonBit, Emscripten, Rust | One codebase, zero runtime, smallest binary |
| 2026-02-24 | M4 Max as primary dev target | Cloud-first | Optimize for what we have |
| 2026-02-24 | Phase order: NEON > Metal > WASM > AVX > CUDA > RVV | Various | Hardware at hand first, then expanding reach |

---

## Weekly Notes

### Week 0 (2026-02-24) -- Planning
- PRD v2 completed with multi-platform vision
- Created progress tracking documents
- Defined 6-phase roadmap: NEON -> Metal -> WASM -> AVX -> CUDA -> RVV
- Identified key competitors: rs-bpe, TokenDagger, GitHub bpe, wasm-tokenizer, gpt-tokenizer
- Research completed on MoonBit WASM, Hyperfine, Bun Shell, BlockBPE, Metal 4
- **KEY DECISION: Switched from C + Assembly to Zig + Assembly**
  - Zig `@Vector` for portable SIMD across all targets
  - Zig `comptime` for merge table generation at compile time
  - Zig `wasm32-freestanding` for unified WASM build (replaces MoonBit as primary)
  - Zig `export fn` for C ABI (cffi still works, same FFI story)
  - `build.zig` replaces CMake as build system
  - Hand-written `.S` assembly retained for absolute peak-performance hot loops

### Week 1 (2026-02-24) -- Scaffold Implementation Started
- Replaced all `scripts/*.ts` TODO stubs with executable Bun scripts for benchmark, build, test, fixture generation, chart generation, and upstream sync.
- Added multi-target build steps in `build.zig` (`aarch64-macos`, `aarch64-linux`, `x86_64-linux`, `wasm32-freestanding`).
- Expanded Python CLI with `bench` and `info`, and added native bridge probing plus upstream sync smoke tests.
- Added cffi-based native bridge loading and rank-file cache/download plumbing for all planned encoding names.
- Expanded Python compatibility scaffold with additional `Encoding` methods and test coverage (29 passing tests in local venv).
- Replaced `src/pair_cache.zig` placeholder with a real 4MB flat cache structure (put/get/clear tests), while keeping merge-table generation work explicitly pending.
- Added `scripts/compat-report.ts` to generate reproducible mismatch reports versus `tiktoken` and capture parity progress over time.
