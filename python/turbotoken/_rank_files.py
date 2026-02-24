from __future__ import annotations

import base64
import hashlib
import os
import tempfile
from pathlib import Path
from urllib.request import urlopen

from ._registry import get_encoding_spec


DEFAULT_CACHE_DIR = Path(os.environ.get("TURBOTOKEN_CACHE_DIR", Path.home() / ".cache" / "turbotoken"))


def cache_dir(path: Path | None = None) -> Path:
    out = path or DEFAULT_CACHE_DIR
    out.mkdir(parents=True, exist_ok=True)
    return out


def rank_file_path(name: str, *, dir_path: Path | None = None) -> Path:
    spec = get_encoding_spec(name)
    return cache_dir(dir_path) / f"{spec.name}.tiktoken"


def _download_bytes(url: str, *, timeout: float = 30.0) -> bytes:
    with urlopen(url, timeout=timeout) as response:  # noqa: S310
        return response.read()


def ensure_rank_file(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> Path:
    target = rank_file_path(name, dir_path=dir_path)
    if target.exists() and not force:
        return target

    payload = _download_bytes(get_encoding_spec(name).rank_file_url, timeout=timeout)
    with tempfile.NamedTemporaryFile("wb", dir=target.parent, delete=False) as tmp:
        tmp.write(payload)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp_path = Path(tmp.name)

    tmp_path.replace(target)
    return target


def read_rank_file(name: str, *, dir_path: Path | None = None) -> bytes:
    return ensure_rank_file(name, dir_path=dir_path).read_bytes()


def parse_rank_file_bytes(payload: bytes) -> dict[bytes, int]:
    ranks: dict[bytes, int] = {}
    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        token_b64, rank_text = line.split(b" ", 1)
        token_bytes = base64.b64decode(token_b64)
        ranks[token_bytes] = int(rank_text)

    return ranks


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()
