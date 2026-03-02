# turbotoken JNI Support

Shared JNI C bridge sources used by JVM wrappers.

## Scope

This is not a standalone package. It provides native glue consumed by:
- `wrappers/java`
- `wrappers/kotlin`

Primary file:
- `wrappers/jni/turbotoken_jni.c`
