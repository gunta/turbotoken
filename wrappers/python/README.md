# turbotoken Python Wrapper

Python package for turbotoken with native bridge integration.

## Local Dev

```bash
zig build
python3 -m pip install -e ".[dev]"
python3 -m pytest -q wrappers/python/tests
```

## Usage

```python
from turbotoken import get_encoding

enc = get_encoding("o200k_base")
ids = enc.encode("hello world")
text = enc.decode(ids)
```

Notes:
- Package source: `wrappers/python/turbotoken`.
- Tests: `wrappers/python/tests`.
- Large ASCII `o200k_*` full/range native bridges remain opt-in for now; use `TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1` or `TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE=1` to force them when benchmarking.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
