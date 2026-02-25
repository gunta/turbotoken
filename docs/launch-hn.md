# HN Launch Draft

## Title
Show HN: turbotoken -- tiktoken-compatible tokenizer with a Zig core (early implementation)

## Post
I have been building `turbotoken`, a tokenizer project targeting `tiktoken` API compatibility with a Zig core.

Current state:
- Early implementation (not production-ready yet)
- Python API parity work for `o200k_base`, `cl100k_base`, `p50k_base`, `r50k_base`
- Compatibility corpus currently reports 0 mismatches vs `tiktoken` on tracked cases
- Cross-target wheel build pipeline for macOS ARM64, Linux ARM64, Linux x86_64, and win_amd64

Recent benchmark snapshot in this repo (Hyperfine, macOS ARM64):
- `turbotoken-encode-100kb`: 147.1 ms
- `tiktoken-encode-100kb`: 195.0 ms
- About `1.33x` speedup on that workload

Roadmap is documented publicly (NEON/Metal/WASM/AVX/CUDA/RVV), but most acceleration backends are still in progress.

Repository includes reproducible scripts for tests and benchmarks:
- `bun run test`
- `bun run bench`
- `bun run compat:report`

Feedback on API compatibility gaps and benchmark methodology would be very helpful.
