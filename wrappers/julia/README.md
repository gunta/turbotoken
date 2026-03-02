# turbotoken Julia Wrapper

Experimental Julia wrapper package.

## Local Dev

```bash
zig build
cd wrappers/julia
julia --project=. -e 'using Pkg; Pkg.test()'
```

Notes:
- Package entrypoint is `wrappers/julia/src/TurboToken.jl`.
- Native loading strategy is still being finalized.
