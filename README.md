# turbotoken

The fastest BPE tokenizer on every platform.

`turbotoken` is a drop-in replacement for `tiktoken` with a Zig core, architecture-specific
SIMD backends, and a compatibility-focused Python API.

## Status

Project scaffold initialized. Core implementation is in progress.

## Planned Backends

- ARM64 NEON
- Apple Metal
- WebAssembly
- x86_64 AVX2/AVX-512
- NVIDIA CUDA
- RISC-V Vector

## Repository Layout

See [PRD.md](./PRD.md) and [ARCHITECTURE.md](./ARCHITECTURE.md) for details.
