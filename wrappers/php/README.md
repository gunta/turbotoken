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
