# turbotoken Groovy Wrapper

Experimental Groovy wrapper layered over the Java binding.

## Local Dev

```bash
zig build
cd wrappers/java
mvn -q -DskipTests package
cd ../groovy
gradle test
```

Notes:
- Depends on Java artifact output from `wrappers/java`.
- Publishes as `turbotoken-groovy`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
