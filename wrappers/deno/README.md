# turbotoken Deno Wrapper

Experimental Deno wrapper with FFI bindings to the turbotoken native core.

## Local Dev

```bash
zig build
deno test wrappers/deno/tests
```

Notes:
- Main module entrypoint: `wrappers/deno/mod.ts`.
- Native library discovery is expected to use local build artifacts.
