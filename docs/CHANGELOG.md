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
  - launch-hn.md and launch-x-thread.md -- launch copy drafts grounded in current project status
  - CHANGELOG.md -- this file
- Bun automation scaffolding in `scripts/`
  - Executable benchmark scripts with JSON output and manual fallback when Hyperfine is unavailable
  - `scripts/test-all.ts`, `scripts/build-all.ts`, `scripts/ci-benchmark.ts`, `scripts/generate-fixture.ts`, and `scripts/generate-charts.ts`
  - `scripts/build-wheels.ts` and `scripts/repack-wheel.py` to produce platform-tagged wheels with bundled native libraries
  - `scripts/sync-upstream.ts` to clone/update upstream repos and emit adapted upstream smoke tests
- `scripts/compat-report.ts` to compare token outputs against `tiktoken` and track parity deltas
- `scripts/test-upstream-alias.ts` to run upstream public `tiktoken` tests against a `turbotoken` alias shim
- Script runtime now resolves a concrete Zig executable path via `scripts/_lib.ts` (`zigExecutable`) to avoid environment shim/plugin failures
- Added `upstream/tiktoken` as a real git submodule (`.gitmodules`) for compatibility oracle tracking
- Python CLI coverage for `turbotoken bench` and `turbotoken info`
- Native bridge probe in `python/turbotoken/_native.py` for loading Zig C ABI symbols when a shared library is present
- Native bridge wrappers for rank-based BPE encode/decode C ABI exports (`turbotoken_encode_bpe_from_ranks`, `turbotoken_decode_bpe_from_ranks`) with graceful fallback when symbols are unavailable
- Shared Zig library artifact installed by `zig build` (`libturbotoken`), with exported placeholder C ABI symbols for count/encode/decode byte paths
- Rank-file cache/download support in `python/turbotoken/_rank_files.py` (`~/.cache/turbotoken/*.tiktoken`)
- Optional tiktoken parity smoke tests in `python/tests/test_tiktoken_parity_smoke.py` (auto-skips when `tiktoken` is not installed)
- Deterministic tiktoken parity fuzz tests in `python/tests/test_tiktoken_parity_fuzz.py`
- Adapted upstream public test coverage in `python/tests/upstream/test_tiktoken_adapted_public.py`
- Additional adapted upstream misc/compat coverage in `python/tests/upstream/test_tiktoken_adapted_misc.py`
- Multi-target build steps in `build.zig` for `aarch64-macos`, `aarch64-linux`, `x86_64-linux`, and `wasm32-freestanding`
- 4MB flat pair-cache scaffold implementation in Zig (`src/pair_cache.zig`) with `put/get/clear` tests
- Merge-table-derived pair-cache seeding (`populateFromRankTable`) with coverage for split-derived pair mappings
- `hypothesis` added to Python `dev` dependencies so upstream property-based compatibility tests are reproducible locally

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
- Python `Encoding` now runs real regex+BPE tokenization using downloaded `.tiktoken` mergeable ranks (including `allowed_special`/`disallowed_special`, batch helpers, decode APIs, numpy export, and token-byte lookup)
- `Encoding.count()` now shares the BPE path with `encode()` while avoiding token-list allocation by summing per-piece token counts
- `build.zig` now supports Zig's modern build API shape (`addLibrary` + `root_module`) and local `zig build`/`zig build test` pass on Zig 0.15
- Updated declared Zig toolchain baseline to `>= 0.15.0` in `build.zig.zon` and `AGENTS.md`
- `src/encoder.zig`, `src/decoder.zig`, and `src/exports.zig` moved from `NotImplemented` stubs to executable placeholder byte behavior
- Python package dependencies now include `regex` for Unicode property tokenization patterns used by OpenAI encodings
- Compatibility smoke report now reaches zero mismatches versus `tiktoken` across `o200k_base`, `cl100k_base`, `p50k_base`, and `r50k_base` for the tracked corpus
- `Encoding` now includes additional parity helpers (`decode_tokens_bytes`, `decode_with_offsets`) and expanded model-name mapping behavior closer to `tiktoken` expectations
- Registry now includes `tiktoken`-style encoding aliases (`gpt2`, `p50k_edit`, `o200k_harmony`) and model mappings that resolve to those names
- Python `Encoding` now exposes extra internal-compat members used by upstream tests (`max_token_value`, `_encode_bytes`, `_pat_str`, `_special_tokens`, lazy `_mergeable_ranks`)
- Python `Encoding` constructor now accepts tiktoken-style custom-encoding arguments (`name`, `pat_str`, `mergeable_ranks`, `special_tokens`) used by upstream pickle compatibility tests
- Python BPE path now dispatches large byte pieces to native Zig rank-based encoding when available to avoid quadratic slow paths on repetitive large inputs
- Zig core now includes `.tiktoken` rank parsing (`src/rank_loader.zig`) and rank-aware encode/decode scaffolding (`encodeWithRanks`, `decodeWithRanks`) with unit tests
- Zig rank loader now keeps constant-time reverse rank lookups (`rank -> token bytes`) and validates duplicate ranks during parsing
- Zig rank-aware encoder now uses a backtracking merge queue (linked token nodes + priority queue candidates) with pair-rank memoization instead of quadratic full-scan merging
- Zig encoder now exposes `countWithRanks` on top of shared merge-node internals so scalar count paths can avoid allocating output token slices
- Zig exports now include rank-driven BPE encode/decode helpers (`turbotoken_encode_bpe_from_ranks`, `turbotoken_decode_bpe_from_ranks`) for native integration experiments
- Rank-driven C ABI exports now route through `src/arch/generic.zig` scalar backend wrappers for consistent fallback behavior
- Scalar architecture fallback now has functional rank-aware backend hooks in `src/arch/generic.zig` (`encode`, `decode`, `count`) with unit tests
- ARM64 architecture module now includes a real `@Vector(16, u8)` pretokenizer estimation path, and `src/pretokenizer.zig` dispatches to it on AArch64 targets
- ARM64 assembly stubs were replaced with executable NEON routines for non-ASCII byte counting and u32->u8 decode packing, and are now wired into `build.zig` and AArch64 decode/pretokenizer paths
- ARM64 NEON assembly hot loops now include `prfm pldl1keep` prefetch hints
- Benchmark scripts now consistently use the repo venv Python interpreter when available
- Full benchmark suite now runs with real Hyperfine measurements and regenerated chart summaries (`bun run bench`)
- `build.zig` now skips shared-library installation for `wasm32-freestanding`, fixing wasm cross-target build failures
- README and benchmark docs now include concrete measured results from latest local runs
- `.gitignore` now excludes `dist/` wheel output artifacts from local packaging runs
- Verified macOS ARM64 wheel smoke path via local `pip install` + import/roundtrip/native bridge load checks
- Verified Linux ARM64 and Linux x86_64 wheel smoke paths via Docker (`python:3.11-slim`) with successful install/import/roundtrip/native-availability checks
- Verified upstream public `tiktoken` tests against turbotoken aliasing (`--import-mode=importlib`): `33 passed`

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
