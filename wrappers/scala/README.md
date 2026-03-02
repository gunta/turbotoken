# turbotoken Scala Wrapper

Experimental Scala wrapper layered on the Java package.

## Local Dev

```bash
zig build
cd wrappers/scala
sbt test
```

Notes:
- Current build references Java wrapper artifacts from `wrappers/java`.
- Scala 2.13 and 3.x cross versions are configured.
