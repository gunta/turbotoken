# turbotoken Flutter Wrapper

Experimental Flutter plugin for turbotoken using FFI.

## Local Dev

```bash
zig build
cd wrappers/flutter
flutter pub get
flutter test
```

Notes:
- Plugin sources are under `wrappers/flutter/lib/src`.
- Platform glue is in `wrappers/flutter/android` and `wrappers/flutter/ios`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
