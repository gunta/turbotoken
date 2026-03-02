# turbotoken Clojure Wrapper

Experimental Clojure wrapper over the shared turbotoken native core.

## Local Dev

```bash
zig build
cd wrappers/clojure
lein test
```

Notes:
- This package currently depends on the Java wrapper sources in `wrappers/java`.
- Native loading behavior is still evolving.
