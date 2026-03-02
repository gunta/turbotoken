# turbotoken React Native Wrapper

Experimental React Native package for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/react-native
npm install
npm run typescript
```

Notes:
- JS/TS source is in `wrappers/react-native/src`.
- Native modules live in `wrappers/react-native/android` and `wrappers/react-native/ios`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
