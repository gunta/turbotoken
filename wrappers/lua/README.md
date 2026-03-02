# turbotoken Lua Wrapper

Experimental Lua wrapper (LuaJIT FFI / cffi-lua style) for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/lua
busted spec
```

Notes:
- Rockspec: `wrappers/lua/turbotoken-dev-1.rockspec`.
- Modules are under `wrappers/lua/src/turbotoken`.
