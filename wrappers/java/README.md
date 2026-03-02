# turbotoken Java Wrapper

Experimental Java/JNI wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/java
mvn test
```

Notes:
- JNI declarations are in `wrappers/java/src/main/java/com/turbotoken/NativeBridge.java`.
- Native JNI source is in `wrappers/jni/turbotoken_jni.c`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
