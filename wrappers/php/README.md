# turbotoken PHP Wrapper

Experimental PHP wrapper package using `ext-ffi`.

## Local Dev

```bash
zig build
cd wrappers/php
composer install
phpunit -c phpunit.xml
```

Notes:
- Namespace: `TurboToken\\`.
- Composer package metadata is in `wrappers/php/composer.json`.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
