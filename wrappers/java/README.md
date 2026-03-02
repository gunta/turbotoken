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
