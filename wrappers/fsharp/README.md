# turbotoken F# Wrapper

Experimental F# wrapper over the turbotoken native library.

## Local Dev

```bash
zig build
dotnet build wrappers/fsharp/TurboToken.FSharp.fsproj
```

Notes:
- The package currently mirrors the C# surface with F# idioms.
- Test coverage is still in progress.
