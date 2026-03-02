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
