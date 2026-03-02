# Monorepo Layout

This repository is organized as a language-wrapper monorepo around a shared Zig core.

## Top-Level Structure

- `src/`, `asm/`, `gpu/`, `include/`: core native implementation and acceleration paths
- `wrappers/`: all language-specific wrapper packages
- `scripts/`: automation for build, benchmark, and release checks
- `docs/`: architecture, progress, benchmark, and release docs

## Wrapper Model

Each wrapper package should:
- keep heavy logic in Zig/native layers
- stay thin at the language boundary
- provide its own package metadata and local `README.md`
- be listed in `wrappers/release-matrix.json`

## Release Governance

The release matrix is the source of truth for publish readiness:
- `wrappers/release-matrix.json`

Run checks:

```bash
bun run release:check
bun run release:dry-run
```

Artifacts:
- `dist/release/release-readiness-*.json`
- `dist/release/release-readiness-*.md`
