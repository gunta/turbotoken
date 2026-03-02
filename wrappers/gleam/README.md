# turbotoken Gleam Wrapper

Experimental Gleam wrapper that targets Erlang and calls turbotoken native bindings.

## Local Dev

```bash
zig build
cd wrappers/gleam
gleam test
```

Notes:
- Erlang FFI module is `wrappers/gleam/src/turbotoken_ffi.erl`.
- Native bridge support code is shared with `wrappers/nif`.
