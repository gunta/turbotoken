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
- `scripts/bench-native-byte-path.ts` to benchmark native C ABI UTF-8 byte encode/decode paths independently of scalar BPE
- `scripts/bench-native-pretokenizer.ts` to benchmark native non-ASCII counting kernels (auto/scalar/NEON/DotProd, plus optional SME when built with `-Dexperimental-sme=true`)
- `scripts/bench-pair-cache-hash.ts` to compare scalar BPE throughput across pair-cache hash strategies (`rapidhash`, ARM64 `crc32`) under identical commands
- `scripts/bench-encoder-queue.ts` to compare scalar BPE queue strategies (`hybrid` vs `full-bucket`) under `TURBOTOKEN_ENCODER_QUEUE`
- `scripts/bench-boundary-classifier.ts` to benchmark native ASCII boundary-classification counters (`auto`/`scalar`/`neon`)
- `scripts/bench-gpu-crossover.ts` now includes long-piece BPE crossover rows (`encode_gpu(auto)` vs forced `encode_gpu(metal)`) with baseline correctness checks, plus optional `TURBOTOKEN_BENCH_LONG=1` mode that appends a `10,485,760` bytes/chars row for periodic heavy comparison runs
- `scripts/generate-pair-cache-seeds.ts` plus generated seed artifact `src/generated/pair_cache_seeds.zig` for merge-table-driven pair-cache warmup
- Script runtime now resolves a concrete Zig executable path via `scripts/_lib.ts` (`zigExecutable`) to avoid environment shim/plugin failures
- Added `upstream/tiktoken` as a real git submodule (`.gitmodules`) for compatibility oracle tracking
- Python CLI coverage for `turbotoken bench` and `turbotoken info`
- Native bridge probe in `python/turbotoken/_native.py` for loading Zig C ABI symbols when a shared library is present
- Native bridge wrappers for rank-based BPE encode/decode C ABI exports (`turbotoken_encode_bpe_from_ranks`, `turbotoken_decode_bpe_from_ranks`) with graceful fallback when symbols are unavailable
- Native bridge wrappers for rank-based BPE batch/range/chunk-stitch C ABI exports (`turbotoken_encode_bpe_batch_from_ranks`, `turbotoken_encode_bpe_ranges_from_ranks`, `turbotoken_encode_bpe_chunked_stitched_from_ranks`)
- Native bridge wrappers for Metal stitch owner-mask C ABI export (`turbotoken_metal_chunk_owner_flags`) plus stitch profiling counters
- Native bridge wrappers for UTF-8 byte C ABI exports (`turbotoken_encode_utf8_bytes`, `turbotoken_decode_utf8_bytes`)
- Native bridge wrappers for ARM64 feature/kernel introspection and non-ASCII count variants (`auto`/`scalar`/`neon`/`dotprod`)
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
- Rank-driven C ABI exports now include `turbotoken_count_bpe_from_ranks`, and rank-table loading in exports reuses a cached parsed table across repeated calls when the input rank payload pointer/length are unchanged
- Rank-driven C ABI exports now also include multi-segment helpers for chunk workflows (`turbotoken_encode_bpe_batch_from_ranks`, `turbotoken_encode_bpe_ranges_from_ranks`) plus experimental native chunk-owner stitching (`turbotoken_encode_bpe_chunked_stitched_from_ranks`)
- Rank loader now keeps a dense rank-to-token index for faster `tokenForRank` lookups on the merge hot path, while preserving existing map-backed behavior
- Encoder pair-rank lookup now uses a stack buffer for short merged-token probes to reduce scratch-buffer overhead in the scalar path
- Scalar architecture fallback now has functional rank-aware backend hooks in `src/arch/generic.zig` (`encode`, `decode`, `count`) with unit tests
- ARM64 architecture module now includes a real `@Vector(16, u8)` pretokenizer estimation path, and `src/pretokenizer.zig` dispatches to it on AArch64 targets
- ARM64 assembly stubs were replaced with executable NEON routines for non-ASCII byte counting, u32->u8 decode packing, and u8->u32 widening encode, wired into `build.zig` and AArch64 encode/decode/pretokenizer paths
- ARM64 NEON assembly hot loops now include load/store prefetch hints (`prfm pldl1keep` + `prfm pstl1keep`), non-ASCII counting now uses reduced horizontal reductions per 64-byte chunk, and decode/encode stay unrolled to 64-byte blocks before 16-byte/tail fallback
- ARM64 decode fused validate+pack assembly path (`turbotoken_arm64_validate_and_decode_u32_to_u8`) now includes a 64-byte unrolled fast loop and uses vector-max accumulation for low-overhead validity checks before one final compare
- ARM64 encode 64-byte loop now batches source loads (`ld1` of four vectors) before widening/storing, reducing load overhead in the widening hot path
- ARM64 pretokenizer now has a DotProd kernel (`turbotoken_arm64_count_non_ascii_dotprod`) and runtime auto-selection between NEON and DotProd via one-time microbenchmark gating
- C ABI now exports ARM64 feature mask and selected pretokenizer kernel id (`turbotoken_arm64_feature_mask`, `turbotoken_count_non_ascii_kernel_id`) plus explicit non-ASCII counters (`auto`, `scalar`, `neon`, `dotprod`)
- Added an experimental ARM64 SME non-ASCII counter kernel (`turbotoken_arm64_count_non_ascii_sme`) behind build flag `zig build -Dexperimental-sme=true`, with C ABI export (`turbotoken_count_non_ascii_utf8_sme`); auto-selection now requires explicit runtime opt-in via `TURBOTOKEN_EXPERIMENTAL_SME_AUTO`
- Experimental SME counter hot loop now uses 4x streaming-vector unroll + prefetch for lower loop/control overhead on large buffers
- Native pretokenizer benchmark now includes a non-ASCII-heavy `unicode-1mb` fixture row in addition to `english-1mb`
- Native pretokenizer benchmark now supports separate run modes/artifacts for baseline vs SME auto opt-in (`bench:native-pretokenizer` and `bench:native-pretokenizer:sme-auto`)
- Current M4 Max tuning data selects NEON (kernel id `1`) over DotProd for non-ASCII counting (`bench/results/bench-native-pretokenizer-20260225-134405.json`)
- `Encoding.encode_gpu()` routing now distinguishes exact and experimental paths: `device="auto"` keeps exact CPU/native rank-BPE behavior, while `device="metal"` enables experimental chunked stitch kernels
- Experimental chunked stitch path now prefers a Metal owner-mask kernel stage when requested, then falls back to native/Python stitch implementations when unavailable
- Metal auto-route calibration cache now uses schema v3 with BPE crossover rows and `bpe_use_metal_min_piece_bytes` threshold gating; v3 bump forces recalibration after `metal-byte-path-v3` kernel changes
- Experimental chunked stitch path now applies boundary-repair/exactness guards and per-shape compatibility caching so `encode_gpu(device="metal", strict_verify=False)` preserves baseline token output on calibrated long-piece rows
- Metal byte-path bridge/kernels now run as `metal-byte-path-v3`: encode widened to `256` bytes/thread with unrolled `uint4` stores, count switched to SIMD-group reduction + unrolled accumulation, host dispatch uses dedicated encode threadgroup sizing and adaptive count lanes, and autoroute cache schema moved to `v3` to force recalibration after kernel changes
- Metal byte-path bridge/kernels now run as `metal-byte-path-v4`: encode widened to `512` bytes/thread with unrolled `uchar4 -> uint4` stores, count hot loop widened to 8x unroll with single-simdgroup fast path, host launch heuristics tuned again (including lower mid-size count lanes), and autoroute cache schema moved to `v4` for recalibration
- UTF-8 byte C ABI now also exports explicit scalar-only variants (`turbotoken_encode_utf8_bytes_scalar`, `turbotoken_decode_utf8_bytes_scalar`) to allow apples-to-apples NEON-vs-scalar benchmarking
- Native byte-path benchmark now includes direct NEON-vs-scalar comparison (latest artifact: `bench/results/bench-native-byte-path-20260225-134436.json`)
- Native pretokenizer benchmark now measures auto/scalar/NEON/DotProd paths with kernel-selection visibility (`bench/results/bench-native-pretokenizer-20260225-134405.json`)
- `docs/PROGRESS.md` now tracks rolled-back optimization trials with benchmark artifact references to avoid re-running known regressions blindly
- Recorded and rolled back an ARM64 `aes/pmull` pair-cache hash experiment after no stable scalar-BPE win across reruns (`bench/results/bench-scalar-fallback-20260225-132701.json`, `bench/results/bench-scalar-fallback-20260225-132746.json`)
- Pair-cache slot hashing now defaults to `rapidhash` (`src/hash.zig`), while retaining opt-in ARM64 `crc32` mode via `TURBOTOKEN_PAIR_CACHE_HASH=crc32` for direct A/B checks (`bench/results/bench-pair-cache-hash-20260225-182315.json`)
- Rank-BPE encoder queue now supports an experimental `full-bucket` mode (`TURBOTOKEN_ENCODER_QUEUE=full-bucket`) while keeping `hybrid` as default after mixed A/B results (`bench/results/bench-encoder-queue-20260225-181051.json`)
- Added native ASCII boundary-classification exports/wrappers (`turbotoken_count_ascii_class_boundaries_utf8` + scalar/neon variants) and benchmark coverage (`bench/results/bench-boundary-classifier-20260225-181856.json`)
- Recorded and rolled back first-pass GPU optimization trials for wide-load encode variants and BPE loop dispatch/min-rank changes after crossover regressions (`bench/results/bench-gpu-20260225-182512.json`, `bench/results/bench-gpu-crossover-1772043937345.json`, `bench/results/bench-gpu-20260225-182816.json`, `bench/results/bench-gpu-crossover-1772044096004.json`)
- Launch bundle milestone is now explicitly marked postponed in planning docs (`LAUNCH: PyPI + GitHub + HN + Twitter`)
- Benchmark scripts now consistently use the repo venv Python interpreter when available
- Full benchmark suite now runs with real Hyperfine measurements and regenerated chart summaries (`bun run bench`)
- `build.zig` now skips shared-library installation for `wasm32-freestanding`, fixing wasm cross-target build failures
- README and benchmark docs now include concrete measured results from latest local runs
- `.gitignore` now excludes `dist/` wheel output artifacts from local packaging runs
- Verified macOS ARM64 wheel smoke path via local `pip install` + import/roundtrip/native bridge load checks
- Verified Linux ARM64 and Linux x86_64 wheel smoke paths via Docker (`python:3.11-slim`) with successful install/import/roundtrip/native-availability checks
- Verified upstream public `tiktoken` tests against turbotoken aliasing (`--import-mode=importlib`): `32 passed, 1 deselected` (default deselection for known disallowed-special roundtrip hypothesis case)

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
