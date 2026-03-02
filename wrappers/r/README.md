# turbotoken R Wrapper

Experimental R package wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/r
R CMD check .
```

Notes:
- Package metadata: `wrappers/r/DESCRIPTION`.
- Native sources are in `wrappers/r/src`.
