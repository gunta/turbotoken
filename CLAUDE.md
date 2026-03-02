# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

turbotoken is a **drop-in replacement for tiktoken** — the fastest BPE tokenizer on every platform. It uses **Zig + hand-written assembly** as its core, with platform-specific backends: ARM64 NEON, Apple Metal GPU, Zig WASM (unified), AVX2/AVX-512, NVIDIA CUDA, and RISC-V Vector.

**Current status:** Active development. Phase 1 (ARM64 NEON + Python) is ~95% complete with 6.75x speedup over tiktoken measured. Phase 2 (Metal GPU) has production-grade shaders. Phase 3 (WASM) is functional. Phase 4 (AVX) has dispatch skeleton. ~15,000 lines of working Zig/Python/JS/ASM code.

## Architecture Decisions (Critical)

These are settled decisions — do not revisit or suggest alternatives:

- **Core language:** Zig + hand-written `.S` assembly per target ISA (not C, not Rust)
- **Build system:** `build.zig` (not CMake, not Meson)
- **Python FFI:** cffi via Zig `export fn` C ABI (not pybind11, not ctypes)
- **WASM strategy:** Zig unified — same `src/*.zig` compiles to `wasm32-freestanding` (MoonBit/Emscripten are comparison-only)
- **BPE algorithm:** O(n) backtracking (from GitHub `bpe` crate / rs-bpe), not tiktoken's O(n²) greedy
- **SIMD:** Zig `@Vector` for portable SIMD + hand-written `.S` for absolute peak-perf hot loops
- **Merge tables:** `comptime`-generated flat pair-cache array (4MB, cache-aligned)
- **Scripts:** All in Bun Shell TypeScript (`scripts/*.ts`)
- **Benchmarks:** Hyperfine for everything, JSON export, minimum 10 iterations + 3 warmup

Full rationale in ADR-001 through ADR-010 in `docs/ARCHITECTURE.md`.

## Build Commands

```bash
# Build native (current platform)
zig build

# Build for specific target
zig build -Dtarget=aarch64-macos
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-linux
zig build -Dtarget=wasm32-freestanding

# Run Zig tests
zig build test

# Python tests (byte-perfect vs tiktoken)
cd python && pytest tests/

# All benchmarks
bun run scripts/bench-all.ts

# Build all targets
bun run scripts/build-all.ts

# Sync upstream test suites
bun run scripts/sync-upstream.ts
```

## Repository Structure

```
docs/                    # All project documentation (see Documentation Map)
src/                     # Zig core (platform-agnostic)
  encoder.zig            # O(n) backtracking BPE
  decoder.zig            # Flat lookup table decode
  pretokenizer.zig       # @Vector portable SIMD
  pair_cache.zig         # comptime-generated merge cache
  exports.zig            # C ABI exports for FFI
  arch/                  # Architecture-specific SIMD
    aarch64.zig          # NEON via @Vector(16, u8)
    x86_64.zig           # AVX via @Vector(32/64, u8)
    wasm.zig             # WASM SIMD via @Vector(16, u8)
    generic.zig          # Scalar fallback
asm/                     # Hand-written assembly (.S)
  arm64/                 # NEON hot loops
  x86_64/                # AVX hot loops
  riscv/                 # RVV hot loops
gpu/metal/               # Apple Metal compute shaders
gpu/cuda/                # NVIDIA CUDA kernels
wrappers/python/turbotoken/       # Python package (cffi bridge)
wrappers/js/             # npm package (WASM loader)
scripts/                 # Bun Shell TypeScript (all tooling)
bench/                   # Benchmark fixtures and results
upstream/                # Git submodules (tiktoken, rs-bpe, github-bpe)
```

## Key Technical Patterns

- **`@Vector(N, u8)`** is the portable SIMD primitive: compiles to NEON on ARM64, SSE/AVX on x86, WASM SIMD on wasm32, scalar elsewhere
- **`comptime`** generates merge tables and hash functions at compile time — zero runtime init cost
- **`export fn`** exports C ABI symbols callable from Python cffi, Node N-API, cgo, Rust FFI
- **Hand-written `.S`** is only for the hottest 5% of code paths where Zig's codegen leaves performance on the table
- **Byte-perfect compatibility** with tiktoken is non-negotiable — all encodings must produce identical output

## Documentation Map

All documentation lives in `docs/`.

| File | Purpose |
|------|---------|
| `docs/PRD.md` | Master product spec, API design, phase plan, marketing |
| `docs/ARCHITECTURE.md` | ADRs, backend selection logic, data flow diagrams |
| `docs/PROGRESS.md` | Phase-by-phase task tracker with status |
| `docs/RESEARCH.md` | Research log per backend (algorithms, SIMD, WASM) |
| `docs/BENCHMARKS.md` | All benchmark results, methodology, comparison tables |
| `docs/COMPETITORS.md` | Deep analysis of 10 competing tokenizers |
| `docs/CHANGELOG.md` | Keep-a-changelog format |
| `docs/WASM-EXPLORATION.md` | Zig vs MoonBit vs Emscripten WASM comparison |
| `docs/UPSTREAM-SYNC.md` | Strategy for syncing tiktoken/rs-bpe tests |

## Phase Order

NEON (Phase 1) → Metal (Phase 2) → Zig WASM (Phase 3) → AVX (Phase 4) → CUDA (Phase 5) → RVV (Phase 6) → Language bindings (Phase 7+)

Primary dev target: **Apple M4 Max** (12P+4E cores, 40 GPU cores, 128GB unified, 48MB L2).

## Performance Targets vs Measured (2026-03-02)

| Metric | Target | Measured | Status |
|--------|--------|----------|--------|
| encode 100KB | <2.5ms (8x tiktoken) | 41ms (6.75x tiktoken) | Gap — 6.75x achieved, not 8x |
| decode 128K tokens | <0.06ms | not benchmarked end-to-end | Pending |
| count 673K tokens | <35ms | not benchmarked at this size | Pending |
| WASM binary | <200KB | not optimized yet | Phase 3 TODO |
| Python wheel | <500KB | wheels built, size TBD | Phase 1 launch |
| Startup cold | <5ms | 67.5ms | Gap — 13x off target |
| Peak RAM (o200k_base) | <12MB | 31.5 MB (1MB encode) | Gap — ~2.6x off target |
| Training 100KB | — | 45.7ms (beats rustbpe/minbpe) | Win |
| GPU long-lane 1MB | — | 1.72x throughput boost | Win |

**Key win:** 6.75x faster than tiktoken on 100KB encode. 3.3x faster startup. Training beats all competitors.
