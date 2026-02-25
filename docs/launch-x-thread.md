# X/Twitter Launch Draft

## Launch Tweet
Shipping an early version of `turbotoken`:

- `tiktoken`-compatible Python API
- Zig core
- parity checks passing on tracked corpora for `o200k_base`, `cl100k_base`, `p50k_base`, `r50k_base`
- reproducible benches + compat reports in repo

Latest encode(100kb) snapshot on macOS ARM64: ~1.33x vs `tiktoken`.
Roadmap: NEON, Metal, WASM, AVX, CUDA, RVV.

## Thread Outline
1. What problem this targets: tokenization overhead in coding/agent workloads.
2. Current state: early implementation, parity-focused first, acceleration backends still in progress.
3. Compatibility evidence: upstream-adapted tests + `compat-report` output.
4. Performance evidence: Hyperfine artifacts and benchmark scripts.
5. Build and packaging: cross-target wheel pipeline and native bridge status.
6. Ask for feedback: parity edge cases, benchmark workloads, API expectations.
