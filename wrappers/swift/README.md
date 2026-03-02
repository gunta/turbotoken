# turbotoken Swift Wrapper

Experimental Swift Package Manager wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/swift
swift test
```

Notes:
- SwiftPM package manifest: `wrappers/swift/Package.swift`.
- System module bridge: `wrappers/swift/Sources/CTurboToken`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
