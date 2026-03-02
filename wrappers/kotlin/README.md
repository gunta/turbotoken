# turbotoken Kotlin Wrapper

Experimental Kotlin/JVM wrapper over turbotoken JNI.

## Local Dev

```bash
zig build
cd wrappers/kotlin
./gradlew test
```

Notes:
- Kotlin wrapper currently shares Java JNI definitions and classes.
- Java sources are referenced from `wrappers/java`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
