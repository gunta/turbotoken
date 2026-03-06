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
- `o200k_base`, `o200k_harmony`, and `cl100k_base` now ship embedded native rank payloads, so those encodings stay offline by default and only materialize `.tiktoken` cache files when callers explicitly ask for them.
- The remaining encodings still fall back to downloaded `.tiktoken` rank files on first use.
- Large ASCII `o200k_*` full/range native bridges now auto-route on Linux `x86_64` for sufficiently large ASCII inputs; use `TURBOTOKEN_NATIVE_O200K_FULL_ENABLE=1` or `TURBOTOKEN_NATIVE_RANGE_BATCH_ENABLE=1` to force them when benchmarking.

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
