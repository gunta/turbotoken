# Publishing Guide

This repo supports multiple package ecosystems from a single monorepo.

Primary release inventory:
- `wrappers/release-matrix.json`

Primary automation:
- `bun run release:check`
- `bun run release:dry-run`
- `bun run release:check:ga`
- `bun run release:dry-run:ga`
- `bun run release:smoke:ga -- --package-id=<id>`

Support tiers are defined per package in `wrappers/release-matrix.json`:
- `ga`: must pass per-package dry-run in CI with `--fail-on-skipped` and ecosystem-specific toolchain setup.
- `beta`: included in metadata checks and optional dry-run sweeps.
- `experimental`: scaffolded publish targets, no GA guarantees.

## Global Flow

1. Run package/readme/metadata checks.
2. Run dry-run packaging where toolchains are installed.
3. Resolve failing rows from `dist/release/release-readiness-*.md`.
4. Tag and publish packages by ecosystem.

GA CI dry-run jobs run one package per matrix entry:

```bash
bun run scripts/release-readiness.ts --dry-run --tier=ga --package-id=<id> --fail-on-skipped
```

GA CI smoke jobs also run one package per matrix entry:

```bash
bun run scripts/ga-wrapper-smoke.ts --package-id=<id>
```

## Common Commands

### JS/TS (npm)

```bash
npm pack --silent
npm publish --access public
```

### React Native (npm)

```bash
cd wrappers/react-native
npm pack --silent
npm publish --access public
```

### Python (PyPI)

```bash
python3 -m build --wheel --sdist
python3 -m twine upload dist/*
```

### Rust (crates.io)

```bash
cd wrappers/rust
cargo package --allow-dirty --no-verify
cargo publish
```

### Java/Kotlin/Groovy/Scala (Maven ecosystem)

```bash
cd wrappers/java && mvn -q -DskipTests package
cd wrappers/kotlin && gradle -q assemble
cd wrappers/groovy && gradle -q assemble
cd wrappers/scala && sbt -no-colors package
```

### .NET (NuGet)

```bash
cd wrappers/csharp && dotnet pack TurboToken.csproj -c Release
cd wrappers/fsharp && dotnet pack TurboToken.FSharp.fsproj -c Release
```

### Ruby (RubyGems)

```bash
cd wrappers/ruby
gem build turbotoken.gemspec
gem push turbotoken-<version>.gem
```

### PHP (Packagist)

```bash
cd wrappers/php
composer validate --strict
# publish via git tag and Packagist update
```

### Elixir / Gleam (Hex)

```bash
cd wrappers/elixir && mix hex.build
cd wrappers/gleam && gleam test
```

### Deno (JSR)

```bash
cd wrappers/deno
deno check mod.ts
jsr publish
```

### Lua (LuaRocks)

```bash
cd wrappers/lua
luarocks pack turbotoken-dev-1.rockspec
```

### Flutter (pub.dev)

```bash
cd wrappers/flutter
flutter pub publish --dry-run
```

## Notes

- Not every developer machine has every package-manager toolchain installed; `release:dry-run` reports `SKIPPED` when a command is unavailable.
- `release:dry-run:ga` fails on `SKIPPED` to keep GA lanes strict in CI.
- JNI/NIF directories are support layers and not standalone publish targets.
