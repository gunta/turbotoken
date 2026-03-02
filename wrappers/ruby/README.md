# turbotoken Ruby Wrapper

Experimental Ruby gem wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/ruby
bundle install
bundle exec rspec
```

Notes:
- Gem spec: `wrappers/ruby/turbotoken.gemspec`.
- Native calls are routed via Ruby FFI.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
