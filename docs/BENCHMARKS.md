# turbotoken -- Benchmark Tracker

> All benchmark results, methodology, and comparison data.
> Every number in this file comes from Hyperfine or documented tooling.
> No hand-waving. No "approximately". Measured or marked as TARGET.

---

## Methodology

### Tools
- **Hyperfine** v1.19+ -- CLI benchmark with statistical analysis
- **Bun Shell TypeScript** -- all benchmark orchestration scripts
- **Python `timeit`** -- in-process micro-benchmarks (supplement to Hyperfine)
- **`/usr/bin/time -l`** (macOS) / `/usr/bin/time -v` (Linux) -- peak RSS memory
- **`wc -c`** -- binary/wheel size comparison

### Principles
1. **Core local benchmarks are reproducible** via `bun run scripts/bench-all.ts` (`bun run bench` / `bun run bench:queue`)
   - Local runs now use a machine lock (`bench/.locks/runtime-local-machine`) so only one local benchmark job can run at a time.
   - `bun run bench:queue` / `bun run bench` default to a fast profile (`TURBOTOKEN_BENCH_SPEED=fast`) for shorter iteration cycles.
   - Use `bun run bench:queue:full` (or `bun run bench:full`) for full-fidelity runs.
   - Queue runner emits `bench/results/bench-queue-*.json` with per-step timing + exit codes.
   - latest measured queue runtime:
     - full baseline: `850.638s` (`bench/results/bench-queue-1772351213303.json`)
     - fast profile: `209.795s` (`bench/results/bench-queue-1772361524545.json`)
     - reduction: `~75.34%` (`~4.05x` faster)
   - CUDA rows are opt-in via `bun run bench:cuda`
   - Paid Modal CUDA runs are opt-in via `bun run bench:modal:cuda`
2. **Hyperfine run count is profile-aware**
   - full profile defaults: minimum 10 iterations with 3 warmup runs
   - fast profile defaults: scaled down via `TURBOTOKEN_BENCH_HYPERFINE_RUN_SCALE=0.25` (or `TURBOTOKEN_BENCH_FAST=1`)
3. **Shell overhead correction** enabled (Hyperfine's `--shell=none` for fast commands)
4. **Same input data** for all competitors (fixtures in `bench/fixtures/`)
5. **Same machine** for any comparison table (noted in header)
6. **JSON export** for every run (`bench/results/*.json`)
7. **Charts auto-generated** from JSON via `bun run scripts/generate-charts.ts`
8. **Canonical scorecard** consolidated from latest artifacts via `bun run bench:scorecard` (`bench/results/bench-scorecard-*.json`, `bench/charts/scorecard.md`)
9. **GPU direct-route headline profile** uses `normal-text`; `low-entropy` remains stress/safety reporting only.
10. **Lock visibility tools**:
   - `bun run bench:lock:status` to inspect current local lock owner.
   - `bun run bench:lock:wait` to block until the local lock is released.
   - `TURBOTOKEN_BENCH_LOCK_DISABLE=1` for explicit lock bypass on non-local isolated hosts.

### CI Governance
- `scripts/ci-benchmark.ts` is the benchmark gate runner used by CI (`bun run bench:ci`).
- CUDA is intentionally **off by default** in governance paths; enable only on demand with explicit CUDA scripts (`bench:cuda`, `bench:modal:cuda`).
- Artifact speed-profile selection is explicit:
  - `--artifact-speed=full|fast|any` (or `TURBOTOKEN_CI_ARTIFACT_SPEED`) controls which benchmark artifacts are eligible for gate evaluation.
  - Default is `full`, so untagged/fast artifacts are ignored unless explicitly requested.
  - Benchmark artifacts now stamp `speedProfile` so fast/full governance separation is reproducible.
  - Fast artifact mode keeps local smoke governance practical by relaxing only two GPU checks:
    - direct throughput floor uses a 0.95 multiplier
    - long-lane direct A/B row requirement is disabled
    Full-profile CI gates remain strict.
- Hard gate thresholds live in `bench/ci-gates.json` and currently cover:
  - startup cold (`hello` first encode)
  - encode/count 1MB latency
  - encode/count 1MB throughput (MiB/s)
  - training latency (native 100KB fixture)
  - training latency + throughput for native 1MB fixture
  - training competitor governance (100KB `rustbpe`/`minbpe` row presence and native-vs-competitor ratio ceilings on profiled CPU runners)
  - peak RSS for 1MB encode and native 1MB training
  - GPU memory envelope (`bench-gpu-memory`) when GPU rows are required on the runner
  - Metal direct 1MB parity (`metal-bpe-direct-encode-1mb.matches_native == true`) on profiled Metal runners
  - Metal direct-route A/B safety (`bench-gpu-bpe-direct`) for low-entropy/normal-text short lanes and 1MB long lanes (with route policy checks), using median-of-3 latest artifacts
  - Metal overlap quality (`bench-gpu-overlap`) using median-of-3 latest artifacts (`overlap_vs_no_overlap` floor on profiled Metal runners)
- Relative regression gates are also enabled in `bench/ci-gates.json` (`relative.enabled=true`) so CI enforces bounded drift against baselines for the same metric set (latency, throughput, RSS, GPU memory).
- Runner-specific profiles are now supported via `scripts/ci-benchmark.ts --profile=...`:
  - `linux-x86_64-cpu` for Ubuntu CPU gate runners
  - `macos-arm64-metal` for macOS Metal gate runners
  This keeps hard/relative gates host-aware instead of sharing one global baseline across dissimilar runners.
- Workflow runner/toolchain policy for benchmark CI:
  - CPU gates: `ubuntu-24.04`
  - Metal gates: `macos-14` (Apple Silicon)
  - Python: `3.14` (`check-latest: true`)
  - Zig: `0.15.2`
  - Bun install: `bun install --frozen-lockfile`
  - CI gate jobs explicitly set `TURBOTOKEN_BENCH_SPEED=full` and `TURBOTOKEN_CI_ARTIFACT_SPEED=full` so uploaded artifacts are full-profile by construction.
  - CPU benchmark job installs `rustbpe` and clones `minbpe` to `/tmp/minbpe` so training competitor governance rows stay populated.
  - CI uploads both `bench/results/*.json` and `bench/results/*.meta.json` artifacts for downstream selection/debug visibility.
  - Metal gate run env: `TURBOTOKEN_GPU_CROSSOVER_QUICK=1`, `TURBOTOKEN_GPU_MEMORY_RUNS=1`, `TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES=262144`
- Baseline refresh tooling:
  - `bun run bench:ci:refresh-baselines` refreshes profile relative baselines from the latest successful per-profile CI benchmark artifacts.
  - `--speed=full|fast|any` (or `TURBOTOKEN_CI_ARTIFACT_SPEED`) selects which artifact speed profile is allowed during refresh.
  - host guard is enabled by default (profile host must match artifact host); use `--allow-host-mismatch` only for explicit local experimentation.
  - benchmark workflow also runs a non-mutating refresh dry-run job and uploads the summary artifact for operator review.
- Local governance commands:
  - CPU gates (Linux profile): `bun run scripts/ci-benchmark.ts --mode=cpu --profile=linux-x86_64-cpu`
  - CPU gates against fast artifacts: `bun run scripts/ci-benchmark.ts --mode=cpu --profile=linux-x86_64-cpu --artifact-speed=fast`
  - Metal gates (quick profile on free runner envelope): `TURBOTOKEN_GPU_CROSSOVER_QUICK=1 TURBOTOKEN_GPU_MEMORY_RUNS=1 TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES=262144 bun run scripts/ci-benchmark.ts --mode=gpu --profile=macos-arm64-metal`
  - Metal gates against fast artifacts: `TURBOTOKEN_GPU_CROSSOVER_QUICK=1 TURBOTOKEN_GPU_MEMORY_RUNS=1 TURBOTOKEN_GPU_MEMORY_ROUTE_BYTES=262144 bun run scripts/ci-benchmark.ts --mode=gpu --profile=macos-arm64-metal --artifact-speed=fast`
  - Direct-route A/B profile matrix: `bun run scripts/bench-gpu-bpe-direct.ts`
  - Single crossover profile run: `TURBOTOKEN_GPU_CROSSOVER_BPE_TEXT_KIND=normal-text bun run scripts/bench-gpu-crossover.ts`
  - fast competitors mode keeps mandatory `python-encode-1mb-turbotoken` / `python-count-1mb-turbotoken` rows so CI 1MB gates remain measurable.
- Packaging smoke checks are now CI-wired:
  - wheels workflow installs the host wheel into an isolated venv and verifies import + native bridge load.
  - wasm workflow packs npm tarball, installs it into a temp project, and validates installed WASM roundtrip.

### Test Machine

| Property | Value |
|----------|-------|
| Machine | MacBook Pro (2024) |
| Chip | Apple M4 Max |
| CPU Cores | 16 (12P + 4E) |
| GPU Cores | 40 |
| RAM | 128GB Unified |
| OS | macOS Sequoia 15.x |
| Python | 3.14.x |
| Node.js | 22.x LTS |
| Bun | 1.x |

Local benchmark host details (from `sysctl` / `uname`):
- model identifier: `Mac16,5`
- kernel / arch: `Darwin 25.3.0` / `arm64` (`AArch64`)
- ISA features detected: NEON/AdvSIMD, FP16, DotProd, BF16, I8MM, SHA3/AES/PMULL, LSE/LSE2, SME/SME2 (current hot path uses AdvSIMD/NEON instructions)

> Additional machines will be added as we benchmark on Graviton, x86, RISC-V, etc.

---

## Latest Update (2026-03-02, WASM Phase 3 completion pass)

Recent artifacts:
- `dist/npm/optimize-wasm-1772455008637.json`
- `dist/npm/verify-npm-package-1772455008778.json`
- `dist/npm/smoke-npm-install-1772454999165.json`
- `bench/results/bench-wasm-comparisons-1772455001727.json`
- `bench/results/bench-browser-competitors-1772455163556.json`
- `bench/results/bench-wasm-1772455201579.json`

What changed:
- npm-minimal WASM (`zig-out/bin/turbotoken-npm.wasm`) is now optimized with `wasm-opt -Oz` and hard-gated at `<150KB`.
- npm auto-load path now validates in verify + smoke install flow, and package dry-run publish passes with prerelease tag (`npm publish --dry-run --tag dev`).
- browser competitor benchmark is now reproducible via:
  - page: `bench/browser/wasm-competitors.html`
  - runner: `bun run bench:browser:competitors`
- binary size comparison automation is now wired for Zig vs MoonBit vs Emscripten via `bun run bench:wasm:comparisons`.

Measured outcomes:
- optimized npm WASM size: `1170 bytes` (`1552 -> 1170` after wasm-opt).
- comparison sizes (`bench-wasm-comparisons-1772455001727.json`):
  - Zig full wasm: `1,642,265 bytes` (`794,657` bytes gz)
  - Zig npm wasm: `1,170 bytes` (`689` bytes gz)
  - MoonBit wasm-gc: `59 bytes` (`66` bytes gz; current MoonBit project is an intentionally minimal/no-op comparison target)
  - Emscripten wasm: `7,182 bytes` (`3,227` bytes gz)
- browser competitor rows (`bench-browser-competitors-1772455163556.json`):
  - turbotoken startup `8.5 ms`, encode 1MiB `106.47 ms` (`9.39 MiB/s`)
  - gpt-tokenizer startup `613.2 ms`, encode 1MiB `11.7 ms` (`85.47 MiB/s`)
  - js-tiktoken startup `1414.2 ms`, encode 1MiB `151.8 ms` (`6.59 MiB/s`)
  - wasm-tokenizer import failed from `esm.sh/wasm-tokenizer@latest` in this run
- browser parity/throughput rows in canonical WASM suite (`bench-wasm-1772455201579.json`):
  - startup first encode `1.03 ms`
  - UTF-8 encode 1MiB `3333.33 MiB/s`
  - BPE encode 1MiB `3.17 MiB/s`

---

## Latest Update (2026-03-02, direct-lane safety fix + medium-lane floor tuning)

Recent artifacts:
- `bench/results/bench-gpu-crossover-1772452891350.json`
- `bench/results/bench-gpu-crossover-1772452991129.json`
- `bench/results/bench-gpu-bpe-direct-1772453132082.json`
- `bench/results/bench-gpu-overlap-1772453446855.json`

What changed:
- `python/turbotoken/_gpu.py`
  - lowered default direct-route minimum to `262_144` bytes (`TURBOTOKEN_METAL_BPE_DIRECT_MIN_BYTES`) to allow medium normal-text lanes to engage direct GPU when eligible.
  - extended low-entropy guard to the multi-range Metal-many direct branch, not only the single-piece direct branch.
  - overlap adaptive selector now cold-starts with serial sampling and alternates until both overlap/serial baselines exist.
  - overlap candidate gate now includes minimum average piece size (`TURBOTOKEN_GPU_OVERLAP_MIN_AVG_PIECE_BYTES`, default `2048`).
- `python/turbotoken/core.py`
  - force-all non-strict mode now has a piece-count CPU fallback guard (`TURBOTOKEN_METAL_FORCE_ALL_CPU_FALLBACK_MAX_RANGES`, default `128`) to avoid catastrophic many-piece dispatch paths.

Measured outcomes:
- 256KB normal-text (`fixture-alpha`) forced-metal row recovered from pathological behavior:
  - before safety fix: `1313.12 ms` (`0.190 MiB/s`) from `bench-gpu-crossover-1772452891350.json`
  - after safety fix: `5.07 ms` (`49.36 MiB/s`) from `bench-gpu-crossover-1772452991129.json`
- Direct A/B (`bench-gpu-bpe-direct-1772453132082.json`):
  - `normalText` (262,144 bytes): enabled vs disabled throughput `1.035x` (slight improvement), parity true.
  - `normalTextLong` (1MB): enabled vs disabled throughput `1.776x`, enabled route uses direct, parity true.
  - low-entropy profiles remain on non-direct safety routes by default (direct not selected; parity true).
- Overlap quality check (`bench-gpu-overlap-1772453446855.json`, 0.25MiB x batch 4): `overlap_vs_no_overlap = 0.989x` (still near break-even/negative on this workload).

---

## Latest Update (2026-03-02, median-of-3 GPU gates + training 1MB governance + browser parity checks)

Recent artifacts:
- `bench/results/bench-training-python-20260302-112550.json`
- `bench/results/bench-ram-1772450936168.json`
- `bench/results/bench-wasm-1772450810515.json`
- `bench/results/bench-gpu-memory-1772451219726.json`
- `bench/results/bench-gpu-bpe-direct-1772451241564.json`
- `bench/results/bench-gpu-overlap-1772451519356.json`
- `bench/results/ci-benchmark-cpu-default-1772450940780-93514.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772451527480-4898.json`

What changed:
- `scripts/ci-benchmark.ts`
  - GPU direct A/B gates now evaluate a median-of-3 window from latest `bench-gpu-bpe-direct` artifacts.
  - GPU overlap gates now evaluate a median-of-3 window from latest `bench-gpu-overlap` artifacts.
  - Added CPU governance metrics for native training on 1MB fixture:
    - max latency gate
    - min throughput gate (MiB/s)
    - peak RSS gate (from RAM artifact training row)
- `bench/ci-gates.json`
  - version bumped to `5`.
  - added defaults/profile thresholds for `training1mbNative*`, `peakRssTrain1mbNative*`, and overlap gate knobs (`requireGpuOverlapRows`, `overlapVsNoOverlapMinRatio`).
- `scripts/bench-training.ts`
  - full profile now includes native `english-1mb` training row by default.
  - optional `english-10mb` row can be enabled with `TURBOTOKEN_TRAIN_INCLUDE_10MB=1`.
- `scripts/bench-ram.ts`
  - added `python-ram-turbotoken-train-1mb-native-v*` row (with reduced per-row run count for cost control).
- `scripts/bench-wasm.ts`
  - browser harness now performs strict parity assertions before timing:
    - UTF-8 identity + roundtrip checks on sample payloads
    - BPE deterministic + roundtrip checks when rank payload is available

Measured outcomes:
- training native:
  - `python-train-english-100kb-turbotoken-native-v320`: `45.68 ms`
  - `python-train-english-1mb-turbotoken-native-v320`: `56.70 ms` (`17.64 MiB/s` in CI summary)
- training RSS:
  - `python-ram-turbotoken-train-1mb-native-v320`: `18.68 MB` median peak RSS
- browser WASM rows (with parity checks enabled):
  - startup: `1.84 ms`
  - UTF-8 encode 1MB: `3125.00 MiB/s`
  - BPE encode 1MB: `3.35 MiB/s`
- governance:
  - CPU gate run passes with new 1MB training metrics (`ci-benchmark-cpu-default-1772450940780-93514.json`)
  - Metal GPU profile gate run passes with median-of-3 direct A/B + overlap checks (`ci-benchmark-gpu-macos-arm64-metal-1772451527480-4898.json`)
    - overlap median ratio (`overlap_vs_no_overlap`): `0.9983x`

---

## Latest Update (2026-03-02, short-lane path tuning + browser WASM rows live)

Recent artifacts:
- `bench/results/bench-gpu-memory-1772448957208.json`
- `bench/results/bench-gpu-bpe-direct-1772448966603.json`
- `bench/results/bench-gpu-overlap-1772449004842.json`
- `bench/results/bench-wasm-1772448715771.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772449012735-3306.json`

What changed:
- Short-lane Metal path tuning:
  - `python/turbotoken/_gpu.py`
    - cached direct/full route settings parsing (env -> parsed config) to reduce per-call overhead in hot loops.
    - `encode_bpe_chunked_stitched_metal_many` now hoists direct/full thresholds out of per-piece loops.
    - rank-table initialization for full-piece/direct checks is now lazy (only when a piece is eligible), avoiding unnecessary setup work for exact/native-only batches.
  - `python/turbotoken/core.py`
    - added ASCII fast path for UTF-8 byte-length checks (`_utf8_len_fast`) in GPU route logic.
- Direct A/B benchmark stability:
  - `scripts/bench-gpu-crossover.ts` quick profile now uses higher BPE loop counts (`min=8`, `max=32`, base `4 MiB`) to reduce short-lane timing noise.
- Browser WASM harness:
  - `scripts/bench-wasm.ts` browser evaluator bug fixed (`warmup`/`runs` payload scoping), and Playwright/Chromium runs now produce real browser rows.

Measured outcomes:
- Direct 1MB parity lane (`bench-gpu-memory-1772448957208.json`):
  - GPU median: `17.78 ms` (`56.26 MiB/s`)
  - CPU median: `20.52 ms`
  - parity: `matches_native=true`
  - max device allocated: `52.45 MiB`
- Direct A/B short lanes (`bench-gpu-bpe-direct-1772448966603.json`, 262,144 bytes):
  - `normal-text`: disabled `0.708 ms` vs enabled `0.763 ms` (`0.928x` throughput ratio, `+7.76%` slowdown), parity true.
  - `low-entropy`: disabled `0.493 ms` vs enabled `0.502 ms` (`0.983x` throughput ratio, `+1.73%` slowdown), parity true.
- Direct A/B long lane (`normalTextLong`, 1MB):
  - disabled `120.60 ms` vs enabled `58.67 ms` (`2.06x` throughput ratio), enabled route uses direct, parity true.
- Overlap (`bench-gpu-overlap-1772449004842.json`, `normal-text`, `0.25 MiB`, batch `4`, 3 runs/row):
  - no-overlap: `867.90 ms`
  - overlap: `892.28 ms`
  - overlap/no-overlap ratio: `0.973x`
- Browser WASM rows (`bench-wasm-1772448715771.json`):
  - `browser-wasm-startup-first-encode-hello`: `2.02 ms`
  - `browser-wasm-encode-utf8-bytes-1mb`: `3125.00 MiB/s`
  - `browser-wasm-encode-bpe-o200k-1mb`: `3.078 MiB/s`

Governance:
- GPU profile gates still pass after this pass (`ci-benchmark-gpu-macos-arm64-metal-1772449012735-3306.json`).

---

## Latest Update (2026-03-02, refreshed full GPU governance + baseline refresh)

Recent artifacts:
- `bench/results/bench-gpu-memory-1772447237318.json`
- `bench/results/bench-gpu-bpe-direct-1772447245871.json`
- `bench/results/bench-gpu-overlap-1772447400710.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772447287127-10348.json`
- `bench/results/ci-gates-refresh-1772447300873.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772447417005-15553.json`

What changed:
- Ran a fresh full-speed GPU governance sweep (`scripts/ci-benchmark.ts --mode=gpu --profile=macos-arm64-metal`) and revalidated with artifact-only gate checks after baseline refresh.
- Refreshed relative GPU baselines from the latest successful profile artifact:
  - `directBpeEncodeMiBPerSec`: `52.970086 -> 56.924252`
- `scripts/bench-gpu-overlap.ts` now forces overlap benchmark runs to bypass the runtime minimum-total-bytes gate only when overlap mode is enabled, so low-size overlap benches do not silently benchmark a non-overlap route.

Measured outcomes:
- `metal-bpe-direct-encode-1mb` (`bench-gpu-memory-1772447237318.json`):
  - GPU median: `17.57 ms` (`56.92 MiB/s`)
  - CPU median: `20.00 ms` (`50.01 MiB/s`)
  - parity: `matches_native=true`
  - max device allocated: `52.45 MiB`
- Direct A/B long lane (`bench-gpu-bpe-direct-1772447245871.json`, `normalTextLong`, 1MB):
  - disabled: `151.50 ms` (`6.60 MiB/s`)
  - enabled: `57.56 ms` (`17.37 MiB/s`)
  - throughput ratio: `2.63x`
  - enabled route used direct: `true`
  - parity: true in both states
- Overlap (`bench-gpu-overlap-1772447400710.json`, `normal-text`, `0.25 MiB`, batch `4`, 3 runs/row):
  - no-overlap: `885.86 ms` (`1.129 MiB/s`)
  - overlap: `878.13 ms` (`1.139 MiB/s`)
  - overlap/no-overlap ratio: `1.009x`

Governance:
- Full GPU profile gates pass on the refreshed artifacts (`ci-benchmark-gpu-macos-arm64-metal-1772447287127-10348.json`).
- Gate-only recheck also passes after baseline refresh (`ci-benchmark-gpu-macos-arm64-metal-1772447417005-15553.json`).

---

## Latest Update (2026-03-02, long-lane direct governance)

Recent artifacts:
- `bench/results/bench-gpu-bpe-direct-1772444208380.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772444437508-23104.json`

What changed:
- `scripts/ci-benchmark.ts`
  - added parsing + gate evaluation for long-lane direct A/B rows (`lowEntropyLong`, `normalTextLong`) from `bench-gpu-bpe-direct` artifacts.
  - added long-lane route policy checks (enabled direct-route required/disabled per gate config).
- `bench/ci-gates.json`
  - extended `directAbSafety` with long-lane thresholds and route expectations.
  - profiled Metal runner now requires long rows and enforces:
    - `requireLowEntropyLongNoDirectRoute=true`
    - `requireNormalTextLongDirectRoute=true`
    - parity remains required for all direct A/B lanes.

Measured outcomes (from `bench-gpu-bpe-direct-1772444208380.json`):
- `normalTextLong` (1MB): direct enabled `62.62 ms` vs disabled `108.52 ms` (`1.73x` throughput ratio), parity true, enabled route used direct.
- `lowEntropyLong` (1MB): enabled stays non-direct route under safety guard, parity true.

Governance:
- GPU profile gates pass with long-lane checks enabled (`ci-benchmark-gpu-macos-arm64-metal-1772444437508-23104.json`).

---

## Latest Update (2026-03-02, WASM SIMD + Metal merge/overlap tuning)

Recent artifacts:
- `bench/results/bench-wasm-1772445390871.json`
- `bench/results/bench-gpu-bpe-direct-1772445416722.json`
- `bench/results/bench-gpu-overlap-1772446520930.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772446353101-59281.json`

What changed:
- WASM path:
  - `src/arch/wasm.zig`: SIMD byte encode/decode loops now use vector widen/truncate + block copies (removes per-lane writes in hot loops).
  - `js/src/wasm-loader.ts`: rank payload is now cached in WASM memory across BPE calls (no per-call rank re-copy), and UTF-8/BPE encode paths use one-shot output buffers.
  - `js/src/encoding.ts`: when WASM bridge is loaded, non-BPE byte-path `encode/decode/count` now uses bridge APIs (thinner JS wrapper path, less JS-side processing).
- Metal merge loop:
  - `gpu/metal/metal_bridge.m`: default large-input direct BPE batch size changed to `24` rounds/submit (from `16`) to reduce submit overhead while keeping convergence stable.
- Overlap benchmark:
  - `scripts/bench-gpu-overlap.ts` now supports `normal-text` and `low-entropy` workload modes and sub-1MiB sizing (`TURBOTOKEN_GPU_OVERLAP_TEXT_MIB` accepts fractions).
  - overlap benchmark now forces strict all-piece mode to avoid silent CPU fallback in force-all scenarios.

Measured outcomes:
- WASM (`bench-wasm-1772445390871.json`):
  - `wasm-encode-utf8-bytes-1mb`: `~23.60 MiB/s`
  - `wasm-encode-bpe-o200k-1mb`: `~2.40 MiB/s`
  - `node-wasm-encode-bpe-o200k-1mb`: `~2.08 MiB/s`
- Metal direct A/B long lane (`bench-gpu-bpe-direct-1772445416722.json`):
  - `normalTextLong` enabled: `57.54 ms`, `17.38 MiB/s`, `96 rounds / 4 submits`, parity true.
  - throughput ratio vs disabled: `1.93x` (`-48.10%` latency).
- Overlap (`bench-gpu-overlap-1772446520930.json`, `normal-text`, `0.25 MiB`, batch `4`, 3 runs/row):
  - `gpu-metal-cpu-overlap` vs `gpu-metal-no-overlap`: `~1.004x` (`~0.38%` uplift in this run).

Governance:
- Metal GPU CI profile continues passing with the updated direct-lane behavior (`ci-benchmark-gpu-macos-arm64-metal-1772446353101-59281.json`).

---

## Latest Update (2026-03-02, governance + parity gates)

Recent artifacts:
- GPU governance:
  - `bench/results/bench-gpu-memory-1772381615970.json`
  - `bench/results/bench-gpu-crossover-1772381619318.json`
  - `bench/results/bench-gpu-bpe-direct-1772381625356.json`
  - `bench/results/bench-gpu-overlap-1772381674893.json`
  - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772381683528-47089.json`
- CPU governance:
  - `bench/results/bench-startup-cold-20260301-160606.json`
  - `bench/results/bench-competitors-python-encode-20260301-160732.json`
  - `bench/results/bench-competitors-python-count-20260301-161149.json`
  - `bench/results/bench-training-python-20260301-164154.json`
  - `bench/results/bench-ram-1772381595388.json`
  - `bench/results/ci-benchmark-cpu-linux-x86_64-cpu-1772383338921-50436.json`

Measured outcomes:
- GPU direct 1MB parity gate is now populated and passing:
  - `metal-bpe-direct-encode-1mb`: `~60.66 MiB/s`, `matches_native=true`, `max_device_allocated_mib=48.45`.
- GPU governance profile (`macos-arm64-metal`) passes with the new hard parity requirement enabled:
  - `bestBpeDirectMiBPerSec=60.66`, `direct1mbMatchesNative=true`.
- CPU governance profile (`linux-x86_64-cpu`) passes with new training competitor checks enabled:
  - native training: `44.72 ms`
  - `rustbpe`: `74.12 ms`
  - `minbpe`: `794.90 ms`
  - native-vs-rustbpe ratio: `0.603` (gate cap: `1.25`)
- Metal hard floor is now stricter for profiled runners: `minBpeDirectEncodeMiBPerSec=40` with direct parity still required.

---

## Latest Update (2026-03-02, Metal auto-route regression fix)

Recent artifacts:
- `bench/results/bench-gpu-crossover-1772427763887.json`
- `bench/results/bench-gpu-bpe-direct-1772427787190.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772427994134-37216.json`
- `bench/results/bench-scorecard-1772428019154.json`

What changed in code:
- `python/turbotoken/core.py`
  - `encode_gpu(device="auto", strict_verify=False)` now early-exits to the regular CPU encode path when whole-text autoroute is native.
  - GPU range-batch fallback now keeps native range batching (chunked by range-count limit) instead of dropping to per-piece Python BPE.
- `python/turbotoken/_gpu.py`
  - route-threshold resolution is now in-memory cached by env/profile tuple to avoid repeated route-cache file reads in per-piece loops.

Measured outcomes (quick profile, `normal-text`, 262,144 bytes):
- crossover (`bench-gpu-crossover-1772427763887.json`):
  - CPU baseline: `0.668 ms` (`~374.27 MiB/s`)
  - auto route: `0.755 ms` (`~331.24 MiB/s`)
  - forced Metal route: `2408.36 ms` (`~0.104 MiB/s`)
  - parity: `auto_matches_baseline=true`, `metal_matches_baseline=true`
- direct A/B matrix (`bench-gpu-bpe-direct-1772427787190.json`):
  - `normal-text` headline:
    - direct disabled: `2397.51 ms` (`~0.104 MiB/s`)
    - direct enabled: `2338.47 ms` (`~0.107 MiB/s`)
    - slowdown: `-2.46%`, parity true in both states
  - `low-entropy` stress profile:
    - slowdown: `+18.46%`, throughput ratio: `0.844x`, parity true in both states

Governance:
- GPU gates continue to pass after the routing fix (`failures: []` in `ci-benchmark-gpu-macos-arm64-metal-1772427994134-37216.json`).

---

## Latest Update (2026-03-02, tiny-piece force-route guard + batching)

Recent artifacts:
- `bench/results/bench-gpu-bpe-direct-1772432813845.json`
- `bench/results/bench-gpu-crossover-1772432841004.json`
- `bench/results/bench-gpu-memory-1772432853486.json`
- `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772432870280-96001.json`
- `bench/results/bench-scorecard-1772432887151.json`

What changed in code:
- `python/turbotoken/_gpu.py`
  - added full-piece GPU lower bound (`TURBOTOKEN_METAL_BPE_FULL_MIN_BYTES`, default `4096`) so tiny regex pieces avoid per-piece GPU dispatch overhead.
  - single-chunk exact pieces in Metal-many path are now batched through native range encode instead of per-piece native calls.
  - Metal bridge wrappers now use one-shot output buffers for `encode_utf8_bytes` and `encode_bpe_from_bytes` (no probe call).
- `python/turbotoken/core.py`
  - added force-all safety guard for sub-direct-size texts:
    - when `TURBOTOKEN_METAL_FORCE_ALL_PIECES=1` and text is below direct route minimum, route falls back to regular CPU encode unless `TURBOTOKEN_METAL_FORCE_ALL_PIECES_STRICT=1`.

Measured outcomes:
- direct A/B matrix (`bench-gpu-bpe-direct-1772432813845.json`, 262,144 bytes):
  - `normal-text`:
    - direct disabled: `0.667 ms` (`~374.74 MiB/s`)
    - direct enabled: `0.710 ms` (`~352.01 MiB/s`)
    - parity true in both states
  - `low-entropy`:
    - direct disabled: `0.476 ms` (`~525.24 MiB/s`)
    - direct enabled: `0.500 ms` (`~499.91 MiB/s`)
    - parity true in both states
- crossover quick (`bench-gpu-crossover-1772432841004.json`, `normal-text` 262,144 bytes):
  - CPU: `0.704 ms`
  - auto: `0.699 ms`
  - forced metal: `0.772 ms`
  - parity true (`auto_matches_baseline=true`, `metal_matches_baseline=true`)

Governance:
- GPU gates still pass after this pass (`ci-benchmark-gpu-macos-arm64-metal-1772432870280-96001.json`).

---

## Latest Update (2026-03-01, macOS ARM64)

Recent artifacts:
- profile-matrix guarded quick run:
  - `bench/results/bench-gpu-bpe-direct-1772344263726.json`
- guarded default run:
  - `bench/results/bench-gpu-bpe-direct-1772337431441.json`
  - `bench/results/bench-gpu-crossover-1772337432831.json`
  - `bench/results/bench-gpu-crossover-1772337436147.json`
  - `bench/results/bench-gpu-memory-1772337434324.json`
  - `bench/results/bench-gpu-memory-1772337438047.json`
- raw direct stress run (guard explicitly disabled):
  - `bench/results/bench-gpu-bpe-direct-1772337512879.json`
- `bench/results/bench-wasm-1772280409724.json`
- `bench/results/bench-scorecard-1772280469323.json`

Metal direct-route A/B (quick profile):
- profile-matrix run (`bench-gpu-bpe-direct-1772344263726.json`):
  - low-entropy:
    - direct disabled: `126.74 ms` (`~1.97 MiB/s`)
    - direct enabled: `126.21 ms` (`~1.98 MiB/s`)
    - slowdown: `~-0.42%`, throughput ratio: `~1.004x`, route remained `stitched` in both rows.
  - normal-text:
    - direct disabled: `3693.69 ms` (`~0.068 MiB/s`)
    - direct enabled: `3596.20 ms` (`~0.070 MiB/s`)
    - slowdown: `~-2.64%`, throughput ratio: `~1.027x`, baseline parity stayed true.
    - GPU-only route row: disabled `~142.60 MiB/s`, enabled `~521.56 MiB/s` (`~3.66x`).
  - note: normal-text direct profile now uses an alphabetic stream derived from the English fixture to keep a realistic character distribution while avoiding fragmented tiny-piece routing in forced-metal A/B runs.

Decision:
- root cause of the extreme slowdown is direct-kernel round complexity on low-entropy inputs (very high `bpe_rounds`) plus host round-submission overhead.
- mitigations applied:
  - direct path remains opt-in (`TURBOTOKEN_METAL_BPE_DIRECT_ENABLE`, default off)
  - low-entropy guard enabled by default (`TURBOTOKEN_METAL_BPE_DIRECT_LOW_ENTROPY_GUARD=1`)
  - Metal BPE default round batching increased (`TURBOTOKEN_METAL_BPE_ROUNDS_PER_SUBMIT` default `8`, was `1`)
- CI now enforces direct A/B safety gates via `bench/ci-gates.json` + `scripts/ci-benchmark.ts` for both text profiles (with CUDA still off by default).

Latest direct-route tuning pass (find+min fused + adaptive round batching):
- artifacts:
  - `bench/results/bench-gpu-memory-1772363356661.json` (pre-pass reference)
  - `bench/results/bench-gpu-memory-1772367624313.json` (post-pass)
  - `bench/results/bench-gpu-bpe-direct-1772363279739.json` (pre-pass reference)
  - `bench/results/bench-gpu-bpe-direct-1772367628817.json` (post-pass)
- measured deltas:
  - direct kernel memory row (`metal-bpe-direct-encode-1mb`): `~32.21 -> ~40.77 MiB/s` (`~26.6%` uplift in this run)
  - normal-text direct A/B enabled row (`bench-gpu-bpe-direct`): `~0.09252 -> ~0.09485 MiB/s` (`~2.5%` uplift in this run)
  - normal-text route-level median GPU throughput (enabled): `~551.07 -> ~641.85 MiB/s`
- parity/governance:
  - strict full-profile GPU governance check passed after this pass:
    - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772367702055-96954.json`

Latest direct-route stability pass (active-compaction guard + on-GPU counter reset):
- artifacts:
  - `bench/results/bench-gpu-crossover-1772368569131.json` (default compaction off)
  - `bench/results/bench-gpu-crossover-1772368584996.json` (forced compaction on, experimental)
  - `bench/results/bench-gpu-bpe-direct-1772368616934.json`
  - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772368666492-45051.json`
- measured outcome:
  - normal-text direct A/B parity restored in both toggle states (`matchesBaseline=true` for disabled/enabled).
  - normal-text A/B timing is near-neutral in this run:
    - disabled: `2499.19 ms`
    - enabled: `2513.09 ms`
    - slowdown: `~0.56%` (`throughputRatio ~0.994x`)
  - low-entropy safety profile remains parity-correct with expected guard-driven behavior:
    - slowdown: `~10.85%` (`throughputRatio ~0.902x`)
  - forced active-compaction mode remained experimental in that run; forced-on parity drift was observed there (`metal_matches_baseline=false`).
  - rounds-per-submit sweep supports the current adaptive default (`32` for medium inputs, `16` for large):
    - 262KB normal-text (`bench-gpu-crossover`, quick): `8 -> 4276.99 ms`, `16 -> 3018.98 ms`, `32 -> 2477.65 ms`, `64 -> 2625.46 ms` (all parity true; `32` best on this size).
    - 1MB direct row (`bench-gpu-memory`): `16 -> 23.99 ms` (`41.69 MiB/s`) vs `32 -> 27.74 ms` (`36.05 MiB/s`) in this run (`16` better on large size).
- governance:
  - strict full-profile GPU governance check passed:
    - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772368951153-62341.json`

Latest active-compaction prefix+stride pass (parity-safe + adaptive default):
- artifacts:
  - compaction off baseline (quick crossover): `bench/results/bench-gpu-crossover-1772376217672.json`
  - compaction stride sweep (forced on, quick crossover):
    - `bench/results/bench-gpu-crossover-1772376135995.json` (stride 1)
    - `bench/results/bench-gpu-crossover-1772376155260.json` (stride 2)
    - `bench/results/bench-gpu-crossover-1772376173089.json` (stride 4)
    - `bench/results/bench-gpu-crossover-1772376190626.json` (stride 8)
  - direct 1MB explicit off/on memory rows:
    - `bench/results/bench-gpu-memory-1772376313905.json` (compaction off)
    - `bench/results/bench-gpu-memory-1772376326853.json` (compaction on + stride 4)
  - latest GPU governance pass:
    - `bench/results/bench-gpu-bpe-direct-1772376545989.json`
    - `bench/results/bench-gpu-memory-1772376523625.json`
    - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772376597296-28059.json`
- measured outcome:
  - forced compaction parity drift is fixed (`metal_matches_baseline=true` across forced-on quick crossover rows in this pass).
  - compaction stride tuning at 262KB normal-text (forced on):
    - stride 1: `3108.79 ms`
    - stride 2: `2897.99 ms`
    - stride 4: `2749.02 ms` (best forced-on stride in this run)
    - stride 8: `2805.62 ms`
    - compaction-off baseline on same profile: `2590.13 ms` (still faster at 262KB).
  - direct 1MB row improved strongly with compaction:
    - off: `23.87 ms` (`41.90 MiB/s`)
    - on (stride 4): `16.09 ms` (`62.16 MiB/s`)
    - uplift: `~48.4%` throughput in this run.
  - default behavior is now adaptive:
    - compaction off for smaller direct pieces (e.g., 262KB)
    - compaction on for larger direct pieces (>=512KB)
  - latest governed GPU memory artifact reflects this uplift:
    - `bestBpeDirectMiBPerSec: 61.21` with gates passing.

Latest specialized no-branch kernel pass (full vs active pipelines):
- artifacts:
  - quick crossover off/on:
    - `bench/results/bench-gpu-crossover-1772377009841.json` (compaction off)
    - `bench/results/bench-gpu-crossover-1772377026006.json` (compaction on + stride 4)
  - 1MB direct memory off/on:
    - `bench/results/bench-gpu-memory-1772377057702.json` (compaction off)
    - `bench/results/bench-gpu-memory-1772377071513.json` (compaction on + stride 4)
  - governed pass:
    - `bench/results/bench-gpu-bpe-direct-1772377092299.json`
    - `bench/results/ci-benchmark-gpu-macos-arm64-metal-1772377142876-55625.json`
- measured outcome:
  - specialized full-grid path improved the 262KB quick row:
    - compaction-off quick crossover: `2396.04 ms` (`0.1043 MiB/s`, parity true)
  - large direct row keeps strong compaction win:
    - off: `25.63 ms` (`39.02 MiB/s`)
    - on (stride 4): `16.17 ms` (`61.85 MiB/s`)
  - governance remains green with the new kernels (`failures: []`).

WASM scorecard rows:
- latest scorecard now includes runtime-split rows:
  - `wasmRows=15`
  - `wasmNodeRows=6`
  - `wasmBrowserRows=2` (explicit not-run placeholders when browser harness is unavailable locally)

---

## Latest Measured Snapshot (2026-02-27, macOS ARM64)

This is the latest refreshed scorecard snapshot (`bun run bench:scorecard`) built from latest measured artifacts:

- `bench/results/bench-startup-cold-20260227-162101.json`
- `bench/results/bench-startup-warm-20260227-162132.json`
- `bench/results/bench-comparison-20260227-162050.json`
- `bench/results/bench-competitors-python-encode-20260227-162558.json`
- `bench/results/bench-competitors-python-decode-20260227-162719.json`
- `bench/results/bench-competitors-python-count-20260227-162811.json`
- `bench/results/bench-training-python-20260227-145645.json`
- `bench/results/bench-ram-1772204354545.json`
- `bench/results/bench-gpu-memory-1772204436247.json`
- `bench/results/bench-scorecard-1772209744278.json`

Note:
- This snapshot mixes freshly rerun startup/comparison/competitor artifacts with the latest already-available training/RAM/GPU-memory artifacts.

| Workload | Mean |
|---|---:|
| startup cold (import + first encode) | 65.2 ms |
| startup warm | 63.6 ms |
| count 100KB | 44.6 ms |
| encode 100KB | 43.6 ms |
| decode 128K tokens | 74.3 ms |
| encode 1MB | 74.2 ms |
| count 1MB | 72.6 ms |

Comparison (`bench-comparison-20260227-162050.json`):
- turbotoken encode 100KB: 44.9 ms
- tiktoken encode 100KB: 216.5 ms
- turbotoken ran ~4.82x faster on this workload in this run.

---

## Latest Pair-Cache Hash A/B (2026-02-27, macOS ARM64)

Direct hash strategy comparison from:
- `bench/results/bench-pair-cache-hash-20260227-145710.json`
- run command: `bun run scripts/bench-pair-cache-hash.ts`
- env switch used per row: `TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`

| Operation | `rapidhash` mean | `crc32` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 148.1 ms | 162.6 ms | rapidhash ~8.9% faster in this run |
| native encode BPE 100KB | 158.7 ms | 159.3 ms | rapidhash ~0.4% faster in this run |

Decision for now:
- default remains `crc32` on AArch64+CRC and `rapidhash` on other targets.
- keep both explicit overrides for A/B checks (`TURBOTOKEN_PAIR_CACHE_HASH=rapidhash|crc32`).
- this 100KB pass favors `rapidhash`; larger-file A/B still favors the current default policy.

---

## Latest Encoder Queue A/B (2026-02-27, macOS ARM64)

Direct queue strategy comparison from:
- `bench/results/bench-encoder-queue-20260227-145729.json`
- run command: `bun run scripts/bench-encoder-queue.ts`
- env switch used per row: `TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket`

| Operation | `hybrid` mean | `full-bucket` mean | Relative |
|---|---:|---:|---:|
| native count BPE 100KB | 146.4 ms | 142.6 ms | full-bucket ~2.6% faster |
| native encode BPE 100KB | 162.0 ms | 152.8 ms | full-bucket ~5.7% faster |

Decision for now:
- switched default queue mode to `full-bucket` (env var unset) in `src/encoder.zig`.
- keep explicit override controls (`TURBOTOKEN_ENCODER_QUEUE=hybrid|full-bucket`).
- latest full-pass scalar fallback (`bench/results/bench-scalar-fallback-20260227-200639.json`) remains substantially improved vs pre-switch baseline (`bench/results/bench-scalar-fallback-20260227-131921.json`):
  - native count 100KB: `177.1 ms -> 92.9 ms` (~47.5% faster)
  - native encode 100KB: `223.1 ms -> 94.0 ms` (~57.9% faster)

---

## Latest ASCII Boundary Classifier (2026-02-27, macOS ARM64)

Experimental boundary-classification benchmark from:
- `bench/results/bench-boundary-classifier-20260227-145815.json`
- run command: `bun run scripts/bench-boundary-classifier.ts`

| Operation | Auto mean | Scalar mean | Relative (Auto vs Scalar) |
|---|---:|---:|---:|
| boundary-class english-1mb | 283.2 ms | 775.6 ms | auto ~2.74x faster |
| boundary-class unicode-1mb | 301.5 ms | 802.4 ms | auto ~2.66x faster |

Note:
- This is an additive pretokenizer primitive (`count_ascii_class_boundaries`), not a replacement of the core BPE path.
- In this run, `auto` and explicit NEON are near parity.

---

## Latest Native Byte-Path Comparison (2026-02-27, macOS ARM64)

Direct ARM64 byte-kernel comparison from:
- `bench/results/bench-native-byte-path-20260227-145853.json`
- `bench/results/bench-native-byte-path-20260227-145853.meta.json`

Benchmark setup:
- Fixture: `bench/fixtures/english-1mb.txt` (+ generated `english-1mb.u32le.bin` for decode)
- In-process iterations per Hyperfine sample: 128 calls
- Commands compare C ABI NEON path (`turbotoken_encode/decode_utf8_bytes`) vs explicit scalar exports (`turbotoken_encode/decode_utf8_bytes_scalar`)

| Operation | NEON mean | Scalar mean | Speedup |
|---|---:|---:|---:|
| encode UTF-8 bytes (1MB x 128) | 81.0 ms | 109.9 ms | 1.36x |
| decode UTF-8 bytes (1MB x 128) | 80.5 ms | 116.7 ms | 1.45x |

Approx throughput from the same means:
- encode NEON: ~1579.5 MiB/s vs scalar ~1164.2 MiB/s
- decode NEON: ~1589.4 MiB/s vs scalar ~1096.9 MiB/s

---

## Latest Native Pretokenizer Comparison (2026-02-27, macOS ARM64)

Direct non-ASCII byte-count kernel comparison from:
- baseline mode:
  - `bench/results/bench-native-pretokenizer-20260227-145747.json`
  - `bench/results/bench-native-pretokenizer-20260227-145747.meta.json`

Benchmark setup:
- Fixtures:
  - `bench/fixtures/english-1mb.txt` (`mixed-ascii`)
  - `bench/fixtures/unicode-1mb.txt` (`non-ascii-heavy`)
- In-process iterations per Hyperfine sample: 256 calls
- Commands compare scalar vs explicit NEON vs explicit DotProd kernel and `auto` runtime kernel selection (plus explicit SME when built with `-Dexperimental-sme=true` on SME-capable hardware)
- Runtime auto-selection note: SME is excluded from auto unless `TURBOTOKEN_EXPERIMENTAL_SME_AUTO` is set.
- Current build note: explicit SME kernel was unavailable in this run, so SME rows were skipped.

| Operation | Mean | Relative |
|---|---:|---:|
| count non-ascii unicode-1mb NEON | 97.0 ms | baseline |
| count non-ascii english-1mb NEON | 97.3 ms | 1.00x slower |
| count non-ascii english-1mb auto | 99.1 ms | 1.02x slower |
| count non-ascii unicode-1mb auto | 100.0 ms | 1.03x slower |
| count non-ascii english-1mb DotProd | 110.4 ms | 1.14x slower |
| count non-ascii unicode-1mb DotProd | 111.4 ms | 1.15x slower |
| count non-ascii unicode-1mb scalar | 169.3 ms | 1.75x slower |
| count non-ascii english-1mb scalar | 171.4 ms | 1.77x slower |

SME tuning note:
- The latest SME pass (4x streaming-vector unroll + prefetch in `asm/arm64/sme_pretokenizer.S`) improved micro-kernel throughput, but end-to-end Hyperfine means still vary across runs; treat very small deltas as noise unless repeated.

Runtime dispatch probe (same build):
- `turbotoken_arm64_feature_mask() = 4095` (`NEON/FP16/DotProd/BF16/I8MM/AES+PMULL/SHA3/LSE/LSE2/SME/SME2`)
- `turbotoken_count_non_ascii_kernel_id() = 1` (`NEON` selected by auto-tune)

---

## Latest Metal Byte-Path Comparison (2026-02-27, macOS ARM64)

Experimental Metal backend benchmark from:
- `bench/results/bench-gpu-20260227-150010.json`
- `bench/results/bench-gpu-20260227-150010.meta.json`

Benchmark setup:
- Encode fixture: `bench/fixtures/english-1mb.txt`
- Count fixture: `bench/fixtures/english-1kb.txt` batched to `4096` segments
- In-process iterations per Hyperfine sample:
  - encode path: `128`
  - batch count path: `512`

| Operation | Mean | Relative |
|---|---:|---:|
| Metal encode UTF-8 bytes (1MB x 128) | 193.8 ms | baseline (metal encode) |
| Native NEON encode UTF-8 bytes (1MB x 128) | 73.8 ms | 2.63x faster than metal encode |
| Hybrid NEON+Metal encode UTF-8 bytes (1MB x 128) | 170.6 ms | 1.14x faster than metal encode |
| Metal count non-zero batch (4096 x 1KB, x512 loops) | 261.0 ms | baseline (metal batch count) |
| Python CPU count non-zero batch (4096 x 1KB, x512 loops) | 748.7 ms | 2.87x slower than metal batch count |

Notes:
- This measures experimental Metal kernels and routing only.
- Full-piece GPU BPE merge path is currently capped to small inputs by default (`TURBOTOKEN_METAL_BPE_FULL_MAX_BYTES=16384`) and larger pieces fall back to chunk/native-verified paths.
- Throughput equivalents from the same run:
  - encode: native NEON ~1734.1 MiB/s, metal ~660.5 MiB/s, hybrid ~750.3 MiB/s
  - batch count (aggregate): metal ~7845.9 MiB/s vs Python CPU ~2735.5 MiB/s
- Current conclusion on parallel CPU+GPU split for byte-path: this native-bridge hybrid beats pure metal in this run, but remains much slower than pure NEON on this machine/workload.
- Additional first-pass GPU optimization trials on 2026-02-25 (wide-load encode variants plus BPE loop dispatch/min-rank changes) regressed crossover means and were rolled back as-is:
  - `bench/results/bench-gpu-20260225-182512.json`
  - `bench/results/bench-gpu-crossover-1772043937345.json`
  - `bench/results/bench-gpu-20260225-182816.json`
  - `bench/results/bench-gpu-crossover-1772044096004.json`

---

## Latest Metal Crossover Matrix (2026-02-27, macOS ARM64)

Matrix benchmark from:
- standard: `bench/results/bench-gpu-crossover-1772204438191.json`
- run command: `bun run scripts/bench-gpu-crossover.ts`
- default: `TURBOTOKEN_BENCH_LONG=0` (long mode disabled)
- optional long-run row (adds `10,485,760` bytes/chars): `TURBOTOKEN_BENCH_LONG=1 bun run scripts/bench-gpu-crossover.ts` (not run in this pass)

Outputs include:
- size/batch crossover rows for Metal vs native/Python baselines
- auto-route backend decisions
- per-run low-level profile counters (CPU ns + GPU ns + dispatch geometry)
- persisted auto-route thresholds in `~/.cache/turbotoken/metal/autoroute-v1.json`
  - cache payload schema version: `5`
- long-mode metadata (`long_mode.enabled`, `bench_sizes`) for reproducible optional heavy runs

Current calibration summary on this machine:
- encode auto-route threshold: effectively "never Metal" for byte encode (`2^60` bytes sentinel)
- count auto-route threshold: effectively "never Metal" for current non-zero count benchmark (`2^60` bytes sentinel)
- bpe auto-route threshold: `1,048,576` bytes (auto-route can pick Metal for long-piece BPE at/above this size in current calibration payload)
- practical implication: current byte/count auto-route still stays on native/Python at these gates; BPE now has calibrated rows and an explicit threshold, but remains experimental and workload-sensitive.

Added BPE crossover rows (`o200k_base`, long `"a"*N` inputs):

| Input Size | CPU encode | `encode_gpu(device="auto", strict_verify=False)` | `encode_gpu(device="metal", strict_verify=False)` | Correctness |
|---|---:|---:|---:|---|
| 65,536 chars | 0.124 ms | 1.153 ms | 29.9 ms | auto matches baseline, metal matches baseline |
| 262,144 chars | 0.479 ms | 4.065 ms | 107.0 ms | auto matches baseline, metal matches baseline |
| 1,048,576 chars | 1.930 ms | 105.0 ms | 167.2 ms | auto matches baseline, metal matches baseline |

---

## Latest CPU+GPU Overlap Matrix (2026-03-01, macOS ARM64)

- artifact: `bench/results/bench-gpu-overlap-1772339930654.json`
- command: `bun run scripts/bench-gpu-overlap.ts`
- workload:
  - synthetic single-piece `o200k_base` text (`"a"` repeated, default `TURBOTOKEN_GPU_OVERLAP_TEXT_MIB=1`)
  - batch mode (`TURBOTOKEN_GPU_OVERLAP_BATCH`, default `4`)
  - stitched route chunk size (`TURBOTOKEN_GPU_OVERLAP_CHUNK_BYTES`, default `1024`)

What this measures:
- CPU-only baseline: `encode_batch(...)`
- Metal non-overlap: `encode_gpu(device=\"metal\", strict_verify=False)` with overlap pipeline disabled
- Metal overlap: same call with CPU pretokenize overlap enabled (`TURBOTOKEN_GPU_OVERLAP_ENABLE=1`)

Note:
- This path is intentionally scoped to **large-text crossover** behavior; small/medium pieces remain routed to CPU/native by default.
- Latest run still shows CPU-only ahead on this machine/workload (`~531.5 MiB/s` CPU vs `~3.44 MiB/s` Metal non-overlap vs `~3.56 MiB/s` overlap), but overlap improved Metal stitched throughput by ~`3.5%` (`overlap_vs_no_overlap ≈ 1.035`) for this stress path.
- GPU rows now include max memory telemetry sampled from `_gpu.profile_last()` (`max_memory_active_bytes`, `max_memory_working_set_bytes`, `max_memory_device_allocated_bytes`, `max_memory_device_recommended_working_set_bytes`).

---

## Baseline Measurements (Competitors)

> Measured on our M4 Max. These are the numbers to beat.
> Status: `PARTIAL` -- Python competitor rows plus selected Bun JS (`gpt-tokenizer`) rows, startup, and memory are measured; broader JS/WASM matrix is still pending.

Artifacts for this pass:
- `bench/results/bench-competitors-python-encode-20260227-170426.json`
- `bench/results/bench-competitors-python-decode-20260227-170602.json`
- `bench/results/bench-competitors-python-count-20260227-170704.json`
- commands:
  - `bun run scripts/bench-competitors.ts`
Training baseline artifacts:
- `bench/results/bench-training-python-20260227-145645.json` (english-100kb, vocab=320)
- command: `bun run bench:training`
Startup + memory artifacts:
- `bench/results/bench-startup-cold-20260227-170257.json`
- `bench/results/bench-startup-warm-20260227-170333.json`
- `bench/results/bench-ram-1772212098947.json`
WASM + binary artifacts:
- `bench/results/bench-wasm-1772204362471.json`
- `bench/results/bench-binary-size-1772204354576.json`
Wheel build artifact:
- `dist/wheels/build-wheels-1772103454490.json`

### Python Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | 1MB | 1MB Throughput (MiB/s) | Source |
|-----------|-----|------|-------|-----|------------------------|--------|
| tiktoken (latest) | 215.9 ms | 220.6 ms | 226.2 ms | 277.7 ms | 3.60 | `pip install tiktoken` |
| rs-bpe | 74.4 ms | 71.6 ms | 77.1 ms | 93.0 ms | 10.75 | `pip install rs-bpe` |
| TokenDagger (`tokendagger`) | 499.7 ms | 507.4 ms | 493.8 ms | 493.6 ms | 2.03 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| gpt-tokenizer (Bun) | 164.8 ms | 169.1 ms | 170.4 ms | 185.7 ms | 5.38 | `bun add --dev gpt-tokenizer` |
| HuggingFace tokenizers | PENDING | PENDING | PENDING | PENDING | PENDING | `tokenizers` package installed, but no stable built-in `o200k_base` entry-point |
| turbotoken (default CPU path) | 68.0 ms | 44.1 ms | 45.9 ms | 76.5 ms | 13.08 | local editable package (`python/`) |
| turbotoken (Metal GPU route) | 98.2 ms | 100.3 ms | 123.6 ms | 182.0 ms | 5.50 | `Encoding.encode_gpu(device="metal", strict_verify=False)` |

### Python Tokenizers (decode, o200k_base)

| Competitor | 1K tok | 10K tok | 128K tok | Source |
|-----------|--------|---------|----------|--------|
| tiktoken | 213.5 ms | 225.9 ms | 222.7 ms | `tiktoken.get_encoding("o200k_base").decode(...)` |
| rs-bpe | 82.2 ms | 85.0 ms | 84.2 ms | `openai.o200k_base().decode(...)` |
| TokenDagger (`tokendagger`) | 493.5 ms | 497.3 ms | 511.0 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| gpt-tokenizer (Bun) | 175.4 ms | 173.9 ms | 179.1 ms | `decode(tokens)` |
| turbotoken (default CPU path) | 66.1 ms | 69.9 ms | 77.9 ms | `turbotoken.get_encoding("o200k_base").decode(...)` |

### Python Tokenizers (count-only, o200k_base)

| Competitor | 1KB | 100KB | 1MB | 1MB Throughput (MiB/s) | Source |
|-----------|-----|-------|----------------|------------------------|--------|
| tiktoken (via `len(encode())`) | 213.9 ms | 221.4 ms | 280.5 ms | 3.56 | `len(encode())` |
| rs-bpe `count()` | 71.3 ms | 73.9 ms | 87.0 ms | 11.50 | `openai.o200k_base().count(...)` |
| TokenDagger (`tokendagger`, via `len(encode())`) | 486.9 ms | 490.4 ms | 499.3 ms | 2.00 | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| gpt-tokenizer (Bun, `countTokens`) | 169.2 ms | 175.9 ms | 182.6 ms | 5.48 | `countTokens(text)` |
| turbotoken `count()` | 67.1 ms | 45.0 ms | 71.0 ms | 14.09 | No-alloc fast path |

### Experimental CL100K Native-Full Toggle (count-only, 1MB ASCII)

Artifact:
- `bench/results/bench-cl100k-native-full-toggle-20260228-035411.json`
- `bench/results/bench-cl100k-native-full-toggle-20260228-050607.json`

| Command | Mean |
|---|---:|
| `turbotoken` (`TURBOTOKEN_NATIVE_CL100K_FULL_DISABLE=1`) | `68.5 ms` |
| `turbotoken` (`TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE=1`) | `93.5 ms` |
| `tiktoken` (`cl100k_base`, `len(encode())`) | `181.9 ms` |

Decision:
- keep `TURBOTOKEN_NATIVE_CL100K_FULL_ENABLE=1` path opt-in only for now (still slower in cold-process benchmark mode).

### Experimental O200K Native-Full Toggle (count-only, 1MB ASCII)

Artifact:
- `bench/results/bench-o200k-native-full-toggle-20260228-035541.json`
- `bench/results/bench-o200k-native-full-toggle-20260228-050621.json`

| Command | Mean |
|---|---:|
| `turbotoken` (`TURBOTOKEN_NATIVE_O200K_FULL_DISABLE=1`) | `68.0 ms` |
| `turbotoken` (`TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1`) | `94.3 ms` |
| `tiktoken` (`o200k_base`, `len(encode())`) | `261.6 ms` |

Decision:
- keep `TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1` path opt-in only for now (forced full route remains slower than default CPU route in cold-process benchmark mode).

### Experimental Native-Direct Training Toggle (1MB, vocab size 320)

Artifact:
- `bench/results/bench-training-direct-toggle-20260228-050720.json`

| Command | Mean |
|---|---:|
| `turbotoken` native direct (`TURBOTOKEN_TRAINING_BACKEND=native`, `TURBOTOKEN_NATIVE_TRAINING_FORCE=1`, `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1`) | `68.5 ms` |
| `turbotoken` python backend (`TURBOTOKEN_TRAINING_BACKEND=python`) | `69.9 ms` |

Threading A/B artifact:
- `bench/results/bench-training-native-threads-20260228-050832.json` (`TURBOTOKEN_NATIVE_TRAIN_THREADS=1` vs `8`; near parity in this cold-process setup).

### Python BPE Training (regex+BPE trainer, vocab size 320)

| Corpus | turbotoken (Python backend) | turbotoken (Zig native backend prototype) | rustbpe | minbpe |
|---|---:|---:|---:|---:|
| english-100kb | 55.9 ms (1.75 MiB/s) | 44.7 ms (2.18 MiB/s) | 74.1 ms (1.32 MiB/s) | 794.9 ms (0.12 MiB/s) |

Notes:
- `turbotoken` training API is now available via `train_mergeable_ranks_from_iterator(...)` and `train_encoding_from_iterator(...)`.
- backend routing:
  - default: `TURBOTOKEN_TRAINING_BACKEND=auto` (currently prefers Python path for throughput in this environment)
  - force native prototype: `TURBOTOKEN_TRAINING_BACKEND=native`
  - force Python fallback: `TURBOTOKEN_TRAINING_BACKEND=python`
- native-experimental toggles:
  - `TURBOTOKEN_TRAIN_NATIVE_PRETOKENIZE=1` enables native ASCII O200K range splitting before chunk counting
  - `TURBOTOKEN_TRAIN_NATIVE_DIRECT_ASCII=1` enables direct native ASCII O200K `text -> train` path for single-text list inputs
  - `TURBOTOKEN_NATIVE_TRAIN_THREADS=<n>` overrides native trainer shard worker count (default auto)
  - when `TURBOTOKEN_TRAINING_BACKEND=native` and these env vars are unset, both now default to enabled; set them to `0/false/no` to explicitly disable.
  - latest direct-path artifacts:
    - `bench/results/bench-training-python-20260301-164154.json` (100kb)
- native benchmark row (`python-train-...-turbotoken-native-v320`) currently uses a thin direct C-ABI call (`turbotoken_train_bpe_ascii_o200k`) via Python `ctypes` to measure core native trainer throughput with minimal wrapper overhead.
- `minbpe` was benchmarked from local source checkout (`/tmp/minbpe`) because it is not published on PyPI.
- In this pass, both turbotoken rows lead `rustbpe` on the measured 100KB fixture; native core row leads by a clear margin.

### JavaScript/WASM Tokenizers (encode, o200k_base)

| Competitor | 1KB | 10KB | 100KB | Runtime | WASM Size | Source |
|-----------|-----|------|-------|---------|-----------|--------|
| tiktoken (npm, WASM) | PENDING | PENDING | PENDING | Node.js | PENDING | `npm install tiktoken` |
| gpt-tokenizer | 164.8 ms | 169.1 ms | 170.4 ms | Bun | N/A (pure JS) | `bun add --dev gpt-tokenizer` |
| wasm-tokenizer | PENDING | PENDING | PENDING | Node.js | PENDING | `npm install wasm-tokenizer` |
| turbotoken (Zig WASM, Bun host) | PENDING | PENDING | 115.7 ms | Bun | 1,642,265 B (`zig-out/bin/turbotoken.wasm`) | `bun run scripts/bench-wasm.ts` (`wasm-encode-bpe-o200k-100kb`) |
| turbotoken (Zig WASM, Node host) | PENDING | PENDING | 176.4 ms | Node.js | 1,642,265 B (`zig-out/bin/turbotoken.wasm`) | `bun run scripts/bench-wasm.ts` (`node-wasm-encode-bpe-o200k-100kb`) |
| turbotoken (N-API native) | PENDING | PENDING | PENDING | Node.js | N/A | Phase 3 |

WASM artifact reference:
- `bench/results/bench-wasm-1772421489508.json`

### Startup Latency (time to first encode of "hello")

| Competitor | Cold Start | Warm Start | Notes |
|-----------|-----------|-----------|-------|
| tiktoken (Python) | 208.6 ms | 211.8 ms | Rust extension load + merge table |
| rs-bpe (Python) | 68.7 ms | 65.6 ms | `openai.o200k_base().encode("hello")` |
| turbotoken (Python) | 69.7 ms | 66.4 ms | local editable package (`python/`) |
| TokenDagger (`tokendagger`) | 489.7 ms | 485.3 ms | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| gpt-tokenizer (Bun) | 158.4 ms | 159.2 ms | `encode("hello")` via Bun ESM import |
| tiktoken (npm) | PENDING | PENDING | WASM instantiation |
| turbotoken (npm WASM) | PENDING | PENDING | Zig WASM instantiation |
| turbotoken CLI | 95.4 ms | 97.3 ms | `python -m turbotoken.cli encode hello --encoding o200k_base` |

Notes:
- cold artifact: `bench/results/bench-startup-cold-20260227-170257.json`
- warm artifact: `bench/results/bench-startup-warm-20260227-170333.json`
- warm mode here means same command measured after Hyperfine warmup (`--warmup 10`), not a long-lived daemon process.

### Chat Helper APIs (encode/count/token-limit)

Artifact:
- `bench/results/bench-chat-helpers-20260227-174446.json`
- command: `bun run scripts/bench-chat.ts`

| Helper operation | turbotoken (Python) | gpt-tokenizer (Bun, gpt-4o module) |
|---|---:|---:|
| chat encode | 72.8 ms | 160.5 ms |
| chat count | 70.8 ms | 156.4 ms |
| chat is-within-token-limit | 101.9 ms | 153.8 ms |

Notes:
- Fixture: `bench/fixtures/chat-sample.json`
- Helpers are template-driven with wrapper-level APIs:
  - Python: `Encoding.encode_chat(...)`, `count_chat(...)`, `is_chat_within_token_limit(...)`
  - JS: `Encoding.encodeChat(...)`, `countChat(...)`, `isChatWithinTokenLimit(...)`
- `template="turbotoken_v1"` is the project-native default framing.
- This benchmark runs turbotoken with `template="im_tokens"` for compatibility-style comparison against `gpt-tokenizer`.
- `o200k_harmony` is an encoding alias in the registry; it is separate from chat template framing.

### Memory Usage (Peak RSS during o200k_base encode of 1MB)

| Competitor | Peak RSS | Delta over baseline | Notes |
|-----------|----------|-------------------|-------|
| Python baseline (empty) | 14.48 MB | -- | `python3 -c "pass"` |
| tiktoken | 114.80 MB | +100.31 MB | `tiktoken.get_encoding("o200k_base").encode(text)` |
| rs-bpe | 90.58 MB | +76.09 MB | `openai.o200k_base().encode(text)` |
| TokenDagger (`tokendagger`) | 242.39 MB | +227.91 MB | rebuilt from cleaned sdist via `bun run deps:token-dagger` |
| gpt-tokenizer (Bun) | 190.97 MB | +176.48 MB | `encode(text)` |
| turbotoken | 30.53 MB | +16.05 MB | `turbotoken.get_encoding("o200k_base").encode(text)` |
| turbotoken CLI | 39.80 MB | +25.31 MB | `python -m turbotoken.cli encode - --encoding o200k_base` |

Notes:
- artifact: `bench/results/bench-ram-1772212098947.json`
- each row is median peak RSS across 5 runs (`TURBOTOKEN_RAM_RUNS=5` default)

### Binary / Package Size

| Artifact | tiktoken | turbotoken | Notes |
|----------|----------|-----------|-------|
| Python wheel (macOS ARM64) | 993,978 B | 1,331,143 B | tiktoken from `pip download --no-deps tiktoken`; turbotoken from `dist/wheels/turbotoken-0.1.0.dev0-py3-none-macosx_11_0_arm64.whl` |
| Python wheel (Linux x86_64) | 1,183,308 B | 3,234,620 B | tiktoken from `pip download --no-deps --only-binary=:all: --platform manylinux2014_x86_64 --python-version 312 --implementation cp --abi cp312 tiktoken`; turbotoken from `dist/wheels/turbotoken-0.1.0.dev0-py3-none-manylinux_2_17_x86_64.whl` (fixed in `dist/wheels/build-wheels-1772103454490.json`) |
| npm package (WASM) | 5,593,287 B (`package/tiktoken_bg.wasm`) | PENDING | extracted from `npm pack tiktoken@1.0.22`; target: <200KB WASM |
| npm package (total) | 23,587,949 B (unpacked) | PENDING | `npm view tiktoken dist.unpackedSize`; turbotoken npm package pending |
| CLI binary (macOS ARM64) | N/A | PENDING | |

---

## Benchmark Dimensions Checklist

Track which benchmarks have been run. Each cell = `PENDING` | `DONE` | `N/A`.

### By Input Size

| Size | tiktoken | rs-bpe | TokenDagger | HF tokenizers | turbotoken scalar | turbotoken NEON | turbotoken Metal | turbotoken WASM |
|------|----------|--------|-------------|---------------|-------------------|-----------------|------------------|-----------------|
| 1KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 10KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 100KB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 1MB | DONE | DONE | DONE | PENDING | DONE | PENDING | DONE | PENDING |
| 10MB | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING | PENDING |

### By Input Type

| Type | tiktoken | turbotoken NEON | Notes |
|------|----------|-----------------|-------|
| English prose | PENDING | PENDING | Wikipedia article |
| Python code | PENDING | PENDING | Real source file |
| JavaScript code | PENDING | PENDING | Real source file |
| Rust code | PENDING | PENDING | Real source file |
| CJK text | PENDING | PENDING | Japanese + Chinese mixed |
| Emoji-heavy | PENDING | PENDING | Slack/Discord messages |
| Random bytes | PENDING | PENDING | Adversarial / worst case |
| Repeated chars | PENDING | PENDING | `"a" * 1_000_000` |

### By Concurrency (batch encode, 1K strings of 1KB each)

| Threads | tiktoken | turbotoken CPU | turbotoken Metal GPU |
|---------|----------|---------------|---------------------|
| 1 | PENDING | PENDING | N/A |
| 2 | PENDING | PENDING | N/A |
| 4 | PENDING | PENDING | N/A |
| 8 | PENDING | PENDING | N/A |
| 16 | PENDING | PENDING | N/A |
| GPU | N/A | N/A | PENDING |

### By Encoding

| Encoding | tiktoken encode 100KB | tiktoken MiB/s | turbotoken encode 100KB | turbotoken MiB/s | Speedup |
|----------|----------------------|----------------|------------------------|------------------|---------|
| o200k_base | 200.6 ms | 0.49 | 39.5 ms | 2.47 | 5.08x |
| cl100k_base | 133.1 ms | 0.73 | 40.6 ms | 2.41 | 3.28x |
| p50k_base | 103.8 ms | 0.94 | 55.8 ms | 1.75 | 1.86x |
| r50k_base | 104.9 ms | 0.93 | 56.8 ms | 1.72 | 1.85x |

Encoding matrix artifact:
- `bench/results/bench-encoding-matrix-1772093253.json`

---

## Benchmark Results History

> Append new results here as they're generated. Each entry includes date, git SHA, and machine.

### [Template -- copy for each benchmark run]

```
Date: YYYY-MM-DD
Git SHA: xxxxxxx
Machine: Apple M4 Max / 128GB
Backend: neon | scalar | metal | wasm | avx2 | cuda
Script: scripts/bench-encode.ts

[Paste Hyperfine markdown table output here]

Notes:
- Any relevant observations
```

---

## Performance Targets vs Actuals

| Operation | Target | Actual | Met? | Date | Git SHA |
|-----------|--------|--------|------|------|---------|
| encode 1KB (NEON) | <0.025ms | -- | -- | -- | -- |
| encode 100KB (NEON) | <2.5ms | -- | -- | -- | -- |
| encode 673K tok (NEON) | <46ms | -- | -- | -- | -- |
| decode 1K tok (NEON) | <0.0005ms | -- | -- | -- | -- |
| decode 128K tok (NEON) | <0.06ms | -- | -- | -- | -- |
| count 673K tok (NEON) | <35ms | -- | -- | -- | -- |
| batch 1K strings CPU (NEON) | <25ms | -- | -- | -- | -- |
| batch 1K strings Metal GPU | <5ms | -- | -- | -- | -- |
| binary size wheel | <500KB | -- | -- | -- | -- |
| WASM binary size | <200KB | -- | -- | -- | -- |
| startup to first encode | <5ms | -- | -- | -- | -- |
| peak RAM o200k_base | <12MB | -- | -- | -- | -- |

---

## Cross-Platform Results

> Filled as we test on different hardware.

### macOS ARM64 (M4 Max) -- Primary

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | 215.9 ms | 43.4 ms | 4.98x | 2026-02-27 |
| decode 128K tok | 222.7 ms | 77.9 ms | 2.86x | 2026-02-27 |

### Linux ARM64 (Graviton3)

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | PENDING | PENDING | PENDING | -- |
| decode 128K tok | PENDING | PENDING | PENDING | -- |

### Linux x86_64 (AVX2)

| Operation | tiktoken | turbotoken | Speedup | Date |
|-----------|----------|-----------|---------|------|
| encode 100KB | PENDING | PENDING | PENDING | -- |
| decode 128K tok | PENDING | PENDING | PENDING | -- |

### WASM (Chrome V8 / Node.js)

| Operation | tiktoken.js | gpt-tokenizer | wasm-tokenizer | turbotoken WASM | Date |
|-----------|------------|---------------|----------------|-----------------|------|
| encode 100KB | PENDING | PENDING | PENDING | PENDING | -- |

### NVIDIA GPU (Modal B200, CUDA 13.1.1)

Latest measured remote CUDA run (Modal) from:

- `bench/results/bench-modal-cuda-1772191604329.json`
- command: `bun run bench:modal:cuda --runs 5`
- detected GPU: `NVIDIA B200` (`nvidia-smi`)

CUDA workload rows embedded in the artifact:

| Operation | Workload | Median | Throughput | Median backend peak alloc | Date |
|-----------|----------|-------:|-----------:|--------------------------:|------|
| `cuda-cupy-encode-u8-to-u32-1mb` | 1 MiB encode cast | 0.827 ms | 1208.7 MiB/s | 10 MiB | 2026-02-27 |
| `cuda-cupy-count-nonzero-batch-4096x1kb` | 4 MiB aggregate count | 0.674 ms | 5934.6 MiB/s | 9 MiB | 2026-02-27 |

From the same Modal run summary:
- startup cold winner: `python-startup-rs-bpe` (84.28 ms)
- startup warm winner: `python-startup-rs-bpe` (55.32 ms)
- encode winner: `python-encode-10kb-turbotoken` (36.71 ms)
- decode winner: `python-decode-1000-tok-rs-bpe` (79.42 ms)
- count winner: `python-count-100kb-turbotoken` (40.69 ms)
- training winner: `python-train-english-100kb-turbotoken-py-fallback-v320` (47.96 ms)

Notes:
- This CUDA table currently reflects CUDA memory/throughput microbench rows (`scripts/bench-gpu-memory-cuda.ts`), not full GPU BPE kernel throughput (Phase 5 work remains TODO).
- First-sample CUDA initialization outliers are present in raw samples; medians above are reported for stable comparison.

### NVIDIA GPU (RTX 4090 dedicated host)

| Operation | Batch Size | turbotoken CUDA | Per-string | Date |
|-----------|-----------|-----------------|------------|------|
| encode batch | 1K | PENDING | PENDING | -- |
| encode batch | 10K | PENDING | PENDING | -- |
