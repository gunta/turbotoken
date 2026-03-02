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
