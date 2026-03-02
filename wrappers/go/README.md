# turbotoken Go Wrapper

Experimental Go wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/go
go test ./...
```

Notes:
- Module path: `github.com/turbotoken/turbotoken-go`.
- Wrapper aims to keep cgo/FFI overhead minimal.
