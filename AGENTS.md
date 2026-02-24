# AGENTS.md

Guidance for coding agents working in this repository.

## 1. Project Intent

`turbotoken` aims to be a `tiktoken`-compatible tokenizer with a Zig core and platform-specific acceleration paths.

Current state is **scaffold/early implementation**. Do not present this repository as production-ready yet.

## 2. Non-Negotiable Architecture Decisions

These are settled unless explicitly changed by maintainers in docs/ADRs:

- Core implementation language: **Zig** (`src/`) with optional hand-written assembly (`asm/`) for hot paths.
- Build system: **`build.zig`** (not CMake/Meson).
- Python bridge direction: Zig C ABI exports (`export fn`) consumed from Python layer.
- WASM direction: Zig unified build (`wasm32-freestanding`) from the same core codebase.
- Scripts and orchestration: **Bun + TypeScript** (`scripts/*.ts`).
- API target: behavioral compatibility with `tiktoken`.

Reference: `docs/ARCHITECTURE.md`.

## 3. Current Reality (Important)

The repo already contains source files, but core tokenization is still placeholder-level:

- `src/encoder.zig` and `src/decoder.zig` implement UTF-8 byte placeholder behavior, not BPE.
- `src/exports.zig` now exports working placeholder C ABI functions (`count`/`encode`/`decode` byte path).
- Python and JS wrappers still use UTF-8 byte placeholder behavior rather than true BPE logic.
- Scripts in `scripts/` are wired and runnable, but benchmark outputs are scaffold-stage unless true BPE backend is active.

Agents must keep this status explicit in docs, PRs, and benchmark claims.

## 4. Repository Map

- `src/`: Zig tokenizer core.
- `asm/`: architecture-specific assembly stubs/implementations.
- `gpu/`: Metal and CUDA experiments.
- `python/`: Python package and tests.
- `js/`: JS/TS wrapper and smoke tests.
- `scripts/`: Bun TypeScript automation/benchmark/sync scripts.
- `docs/`: PRD, architecture decisions, progress, and benchmark notes.

## 5. Local Setup

Expected tools:

- Zig `>= 0.15.0` (see `build.zig.zon`)
- Bun `>= 1.x`
- Python `>= 3.10`

Typical setup:

```bash
bun install
python3 -m pip install -e ".[dev]"
```

## 6. Build and Test Commands

Primary commands:

```bash
zig build
zig build test
python3 -m pytest -q
bun run test
bun run bench
bun run sync:upstream
```

Notes:

- `bun run test` and several `scripts/*.ts` commands are currently scaffolds and may only print TODO output.
- If Zig is routed via an environment shim, ensure a real Zig binary is available before reporting build failures.

## 7. Engineering Rules for Agents

- Keep changes scoped and minimal; avoid broad refactors unless requested.
- Preserve placeholder markers until replacing them with real, tested behavior.
- Do not add synthetic benchmark claims. Only publish measured numbers with reproducible commands.
- Match existing style per language (Zig, Python, TypeScript) and keep public APIs stable where possible.
- Prefer adding/adjusting tests with functional changes.
- Update docs when behavior, commands, or architecture assumptions change.

## 8. Definition of Done for Code Changes

For a change to be considered complete, agents should:

1. Implement code with clear intent and minimal surface area.
2. Run the most relevant local checks for touched areas.
3. Report exactly what was run and what could not be run.
4. Update docs/tests when needed to keep repo state truthful.

## 9. Priority Order (When Unsure)

1. Correctness and API compatibility.
2. Reproducible tests and benchmarks.
3. Performance optimization.
4. New platform/backend expansion.
