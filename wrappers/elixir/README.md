# turbotoken Elixir Wrapper

Experimental Elixir package using a native extension to call turbotoken.

## Local Dev

```bash
zig build
cd wrappers/elixir
mix deps.get
mix test
```

Notes:
- Native source is in `wrappers/elixir/c_src` with shared support in `wrappers/nif`.
- Build is orchestrated by `elixir_make`.
