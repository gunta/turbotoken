# Wrapper Monorepo

All language bindings live under `wrappers/` and are intended to stay thin wrappers over the Zig core (`src/`, `asm/`, `gpu/`).

Release metadata and dry-run commands are tracked in:
- `wrappers/release-matrix.json`

Run release readiness checks from repo root:

```bash
bun run release:check
bun run release:dry-run
bun run release:check:ga
bun run release:dry-run:ga
bun run release:smoke:ga -- --package-id=<ga-id>
```

`release:dry-run:ga` enables `--fail-on-skipped`, so GA wrappers fail if the dry-run command cannot execute.
`release:smoke:ga` runs package-level GA smoke checks (encode/decode roundtrip where runtime is available).

Support tier is tracked per package row in `wrappers/release-matrix.json`:
- `ga`: CI-gated, fail-on-skipped dry-runs with per-ecosystem toolchain setup.
- `beta`: tracked in release checks, not GA-gated yet.
- `experimental`: publish scaffolding present, no GA guarantees.

## Publishable Packages

| Wrapper | Ecosystem | Package | Tier | Manifest |
|---|---|---|---|---|
| JS/TS | npm | `turbotoken` | `ga` | `package.json` |
| React Native | npm | `react-native-turbotoken` | `ga` | `wrappers/react-native/package.json` |
| Python | PyPI | `turbotoken` | `ga` | `pyproject.toml` |
| Rust | crates.io | `turbotoken` | `ga` | `wrappers/rust/Cargo.toml` |
| Go | Go proxy | `github.com/turbotoken/turbotoken-go` | `ga` | `wrappers/go/go.mod` |
| Ruby | RubyGems | `turbotoken` | `experimental` | `wrappers/ruby/turbotoken.gemspec` |
| PHP | Packagist | `turbotoken/turbotoken` | `experimental` | `wrappers/php/composer.json` |
| Java | Maven Central / Maven | `com.turbotoken:turbotoken` | `experimental` | `wrappers/java/pom.xml` |
| Kotlin | Maven | `com.turbotoken:turbotoken-kotlin` | `experimental` | `wrappers/kotlin/build.gradle.kts` |
| Groovy | Maven | `com.turbotoken:turbotoken-groovy` | `experimental` | `wrappers/groovy/build.gradle` |
| Clojure | Clojars | `com.turbotoken/turbotoken-clj` | `experimental` | `wrappers/clojure/project.clj` |
| C# | NuGet | `TurboToken` | `experimental` | `wrappers/csharp/TurboToken.csproj` |
| F# | NuGet | `TurboToken.FSharp` | `experimental` | `wrappers/fsharp/TurboToken.FSharp.fsproj` |
| Elixir | Hex | `turbotoken` | `experimental` | `wrappers/elixir/mix.exs` |
| Gleam | Hex (via Gleam) | `turbotoken` | `experimental` | `wrappers/gleam/gleam.toml` |
| Julia | General registry | `TurboToken` | `experimental` | `wrappers/julia/Project.toml` |
| R | CRAN | `turbotoken` | `experimental` | `wrappers/r/DESCRIPTION` |
| Scala | Maven | `com.turbotoken:turbotoken-scala` | `experimental` | `wrappers/scala/build.sbt` |
| Swift | SwiftPM index | `TurboToken` | `experimental` | `wrappers/swift/Package.swift` |
| Lua | LuaRocks | `turbotoken` | `experimental` | `wrappers/lua/turbotoken-dev-1.rockspec` |
| Deno | JSR | `@turbotoken/turbotoken` | `ga` | `wrappers/deno/deno.json` |
| Flutter | pub.dev | `turbotoken` | `experimental` | `wrappers/flutter/pubspec.yaml` |

## Support-Only Wrapper Infrastructure

These directories provide bridge sources but are not standalone publish targets:
- `wrappers/jni`
- `wrappers/nif`

## Per-Package Docs

Every wrapper directory contains its own `README.md` with:
- what the package is
- current status/scope
- local development commands
- package-manager context
