# turbotoken C# Wrapper

Experimental .NET/C# wrapper over the shared turbotoken native library.

## Local Dev

```bash
zig build
dotnet test wrappers/csharp/Tests/TurboToken.Tests.csproj
```

Notes:
- Package project: `wrappers/csharp/TurboToken.csproj`.
- Tests currently focus on API shape and smoke behavior.
