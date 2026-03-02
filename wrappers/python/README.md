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
