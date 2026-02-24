# turbotoken -- Changelog

> All notable changes to this project.
> Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
> Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

---

## [Unreleased]

### Added
- Project planning and documentation
  - PRD v2 with multi-platform vision (6 backends: NEON, Metal, WASM, AVX, CUDA, RVV)
  - PROGRESS.md -- phase-by-phase task tracker
  - BENCHMARKS.md -- benchmark results and comparison tables
  - COMPETITORS.md -- deep competitive analysis of 10 tokenizer projects
  - RESEARCH.md -- ongoing research log for each backend
  - ARCHITECTURE.md -- technical decisions and architecture records (10 ADRs)
  - WASM-EXPLORATION.md -- Zig (primary) vs MoonBit vs Emscripten comparison
  - UPSTREAM-SYNC.md -- strategy for syncing tiktoken/rs-bpe/GitHub bpe tests
  - CHANGELOG.md -- this file
- Bun automation scaffolding in `scripts/`
  - Executable benchmark scripts with JSON output and manual fallback when Hyperfine is unavailable
  - `scripts/test-all.ts`, `scripts/build-all.ts`, `scripts/ci-benchmark.ts`, `scripts/generate-fixture.ts`, and `scripts/generate-charts.ts`
  - `scripts/sync-upstream.ts` to clone/update upstream repos and emit adapted upstream smoke tests
  - `scripts/compat-report.ts` to compare token outputs against `tiktoken` and track parity deltas
- Added `upstream/tiktoken` as a real git submodule (`.gitmodules`) for compatibility oracle tracking
- Python CLI coverage for `turbotoken bench` and `turbotoken info`
- Native bridge probe in `python/turbotoken/_native.py` for loading Zig C ABI symbols when a shared library is present
- Shared Zig library artifact installed by `zig build` (`libturbotoken`), with exported placeholder C ABI symbols for count/encode/decode byte paths
- Rank-file cache/download support in `python/turbotoken/_rank_files.py` (`~/.cache/turbotoken/*.tiktoken`)
- Multi-target build steps in `build.zig` for `aarch64-macos`, `aarch64-linux`, `x86_64-linux`, and `wasm32-freestanding`
- 4MB flat pair-cache scaffold implementation in Zig (`src/pair_cache.zig`) with `put/get/clear` tests

### Changed
- Core language: C + Assembly -> **Zig + Assembly** (ADR-001)
  - `@Vector` portable SIMD across all targets (NEON, AVX, WASM SIMD, scalar)
  - `comptime` merge table generation at compile time
  - `export fn` C ABI for Python cffi, Node N-API, cgo, Rust FFI
  - Built-in cross-compilation for all platforms
- Build system: CMake -> **build.zig** (ADR-002)
  - Native Zig integration, zero external dependencies
  - Same `build.zig` produces native binaries + WASM
- WASM strategy: MoonBit primary -> **Zig unified** (ADR-006)
  - Same `src/*.zig` compiles to `wasm32-freestanding`
  - Zero runtime overhead (no libc, no GC)
  - WASM SIMD via `@Vector(16, u8)` on wasm32 target
  - MoonBit and Emscripten retained as comparison builds only
- WASM-EXPLORATION.md updated: Zig primary, MoonBit/Emscripten comparison only
- `package.json` scripts now run real test/bench/build helpers instead of TODO placeholders
- `js/tests/smoke.test.ts` now uses Bun test assertions instead of side-effect checks
- Python `Encoding` scaffold expanded with broader tiktoken-like methods (`encode_batch`, `decode_bytes`, `decode_batch`, `encode_to_numpy`, `token_byte_values`, `count_batch`)
- `Encoding.count()` now has an allocation-free placeholder path with special-token handling and optional native C ABI fast path
- `build.zig` now supports Zig's modern build API shape (`addLibrary` + `root_module`) and local `zig build`/`zig build test` pass on Zig 0.15
- Updated declared Zig toolchain baseline to `>= 0.15.0` in `build.zig.zon` and `AGENTS.md`
- `src/encoder.zig`, `src/decoder.zig`, and `src/exports.zig` moved from `NotImplemented` stubs to executable placeholder byte behavior

### Research Completed
- BPE algorithm: O(n) backtracking (GitHub bpe crate, rs-bpe)
- ARM64 NEON: byte classification via vtbl/vceq, decode via ld1/st1+prfm
- Apple Metal 4: BlockBPE GPU parallelization approach
- WebAssembly: Zig unified (primary) vs MoonBit vs Emscripten vs Rust vs AssemblyScript
- x86 SIMD: AVX2 vpshufb/vpcmpeqb, AVX-512BW vpermb
- RISC-V: RVV 1.0 vector-length-agnostic approach
- Benchmark methodology: Hyperfine + Bun Shell TypeScript
- **Zig language evaluation**: @Vector SIMD, comptime, C ABI export, WASM unification

---

## Version History

> Entries will be added here as releases are cut.

### [0.1.0] -- TBD (Phase 1 Launch)
- Initial release
- ARM64 NEON backend
- Scalar Zig fallback
- Python package (pip install turbotoken)
- Drop-in tiktoken compatibility
- CLI tool (count, encode, decode, bench, info)
- Hyperfine benchmark suite

### [0.2.0] -- TBD (Phase 2)
- Apple Metal GPU backend
- encode_gpu() / count_gpu() methods
- Metal batch encoding benchmarks

### [0.3.0] -- TBD (Phase 3)
- WebAssembly build (Zig unified, same codebase)
- npm package (turbotoken)
- Browser compatibility

### [0.4.0] -- TBD (Phase 4)
- x86_64 AVX2/AVX-512 backend
- Runtime CPU feature detection
- Intel/AMD benchmarks

### [0.5.0] -- TBD (Phase 5)
- NVIDIA CUDA backend
- GPU batch encoding for datacenter

### [0.6.0] -- TBD (Phase 6)
- RISC-V Vector Extension (RVV 1.0) backend
