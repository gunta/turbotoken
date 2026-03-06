from __future__ import annotations

import base64
import os
import struct
from pathlib import Path

from ._registry import get_encoding_spec


_DEFAULT_CACHE_DIR: Path | None = None


def _pickle_module():
    import pickle

    return pickle


def _default_cache_dir() -> Path:
    global _DEFAULT_CACHE_DIR
    if _DEFAULT_CACHE_DIR is not None:
        return _DEFAULT_CACHE_DIR
    env_dir = os.environ.get("TURBOTOKEN_CACHE_DIR")
    if env_dir:
        _DEFAULT_CACHE_DIR = Path(env_dir)
    else:
        _DEFAULT_CACHE_DIR = Path.home() / ".cache" / "turbotoken"
    return _DEFAULT_CACHE_DIR


def cache_dir(path: Path | None = None) -> Path:
    out = path or _default_cache_dir()
    out.mkdir(parents=True, exist_ok=True)
    return out


def rank_file_path(name: str, *, dir_path: Path | None = None) -> Path:
    spec = get_encoding_spec(name)
    return cache_dir(dir_path) / f"{spec.name}.tiktoken"


def _download_bytes(url: str, *, timeout: float = 30.0) -> bytes:
    from urllib.request import urlopen

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
    import tempfile

    with tempfile.NamedTemporaryFile("wb", dir=target.parent, delete=False) as tmp:
        tmp.write(payload)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp_path = Path(tmp.name)

    tmp_path.replace(target)
    return target


def read_rank_file(name: str, *, dir_path: Path | None = None) -> bytes:
    return ensure_rank_file(name, dir_path=dir_path).read_bytes()


_RANK_CACHE_VERSION = 1
_DECODER_CACHE_VERSION = 1
_PIECE_CACHE_VERSION = 1
_NATIVE_PAYLOAD_MAGIC = b"TTKRBIN1"
_NATIVE_PAYLOAD_VERSION = 1
_NATIVE_PAYLOAD_FLAGS = 0
_NATIVE_PAYLOAD_MISSING = 0xFFFFFFFF
_NATIVE_PAYLOAD_HEADER = struct.Struct("<8sIIQQII")


def _rank_pickle_path(rank_path: Path) -> Path:
    return rank_path.with_suffix(f"{rank_path.suffix}.pickle")


def _decoder_pickle_path(rank_path: Path) -> Path:
    return rank_path.with_suffix(f"{rank_path.suffix}.decoder.pickle")


def _piece_pickle_path(rank_path: Path) -> Path:
    return rank_path.with_suffix(f"{rank_path.suffix}.pieces.pickle")


def _native_payload_path(rank_path: Path) -> Path:
    return rank_path.with_suffix(f"{rank_path.suffix}.native.bin")


def _native_payload_header_matches(payload: bytes, *, rank_size: int, rank_mtime_ns: int) -> bool:
    if len(payload) < _NATIVE_PAYLOAD_HEADER.size:
        return False
    magic, version, flags, source_size, source_mtime_ns, _entry_count, _max_rank_plus_one = _NATIVE_PAYLOAD_HEADER.unpack(
        payload[: _NATIVE_PAYLOAD_HEADER.size]
    )
    return (
        magic == _NATIVE_PAYLOAD_MAGIC
        and version == _NATIVE_PAYLOAD_VERSION
        and flags == _NATIVE_PAYLOAD_FLAGS
        and source_size == rank_size
        and source_mtime_ns == rank_mtime_ns
    )


def _compile_native_rank_payload(payload: bytes, *, rank_size: int, rank_mtime_ns: int) -> bytes:
    entries: list[tuple[int, bytes]] = []
    max_rank = -1
    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        parts = line.split()
        if len(parts) != 2:
            raise ValueError("invalid rank line")
        token_b64, rank_text = parts
        rank = int(rank_text)
        if rank < 0 or rank > 0xFFFFFFFF:
            raise ValueError("rank out of range")
        token_bytes = base64.b64decode(token_b64)
        entries.append((rank, token_bytes))
        if rank > max_rank:
            max_rank = rank

    max_rank_plus_one = max_rank + 1 if max_rank >= 0 else 0
    dense: list[bytes | None] = [None] * max_rank_plus_one
    for rank, token_bytes in entries:
        if dense[rank] is not None:
            raise ValueError("duplicate rank")
        dense[rank] = token_bytes

    out = bytearray()
    out.extend(
        _NATIVE_PAYLOAD_HEADER.pack(
            _NATIVE_PAYLOAD_MAGIC,
            _NATIVE_PAYLOAD_VERSION,
            _NATIVE_PAYLOAD_FLAGS,
            rank_size,
            rank_mtime_ns,
            len(entries),
            max_rank_plus_one,
        )
    )
    for token_bytes in dense:
        if token_bytes is None:
            out.extend(struct.pack("<I", _NATIVE_PAYLOAD_MISSING))
            continue
        out.extend(struct.pack("<I", len(token_bytes)))
        out.extend(token_bytes)
    return bytes(out)


def read_rank_file_native_payload(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> bytes:
    rank_path = ensure_rank_file(name, dir_path=dir_path, timeout=timeout, force=force)
    stat = rank_path.stat()
    native_path = _native_payload_path(rank_path)

    if not force and native_path.exists():
        try:
            payload = native_path.read_bytes()
            if _native_payload_header_matches(payload, rank_size=stat.st_size, rank_mtime_ns=stat.st_mtime_ns):
                return payload
        except Exception:
            pass

    rank_payload = rank_path.read_bytes()
    try:
        native_payload = _compile_native_rank_payload(
            rank_payload,
            rank_size=stat.st_size,
            rank_mtime_ns=stat.st_mtime_ns,
        )
    except Exception:
        return rank_payload

    try:
        import tempfile

        with tempfile.NamedTemporaryFile("wb", dir=native_path.parent, delete=False) as tmp:
            tmp.write(native_payload)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        tmp_path.replace(native_path)
    except Exception:
        pass

    return native_payload


def load_rank_payload_and_ranks(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> tuple[bytes, dict[bytes, int]]:
    payload, ranks = _load_rank_payload_and_ranks_impl(
        name,
        dir_path=dir_path,
        timeout=timeout,
        force=force,
        include_payload=True,
    )
    assert payload is not None
    return payload, ranks


def load_ranks_only(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> dict[bytes, int]:
    _, ranks = _load_rank_payload_and_ranks_impl(
        name,
        dir_path=dir_path,
        timeout=timeout,
        force=force,
        include_payload=False,
    )
    return ranks


def load_decoder_only(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> dict[int, bytes]:
    pickle_mod = _pickle_module()
    rank_path = ensure_rank_file(name, dir_path=dir_path, timeout=timeout, force=force)
    stat = rank_path.stat()
    rank_size = stat.st_size
    rank_mtime_ns = stat.st_mtime_ns
    decoder_path = _decoder_pickle_path(rank_path)

    if not force and decoder_path.exists():
        try:
            with decoder_path.open("rb") as handle:
                cached = pickle_mod.load(handle)
            if (
                isinstance(cached, dict)
                and cached.get("version") == _DECODER_CACHE_VERSION
                and cached.get("size") == rank_size
                and cached.get("mtime_ns") == rank_mtime_ns
                and isinstance(cached.get("decoder"), dict)
            ):
                return cached["decoder"]
        except Exception:
            pass

    ranks = load_ranks_only(name, dir_path=dir_path, timeout=timeout, force=force)
    decoder = {token_id: token_bytes for token_bytes, token_id in ranks.items()}

    try:
        import tempfile

        with tempfile.NamedTemporaryFile("wb", dir=decoder_path.parent, delete=False) as tmp:
            pickle_mod.dump(
                {
                    "version": _DECODER_CACHE_VERSION,
                    "size": rank_size,
                    "mtime_ns": rank_mtime_ns,
                    "decoder": decoder,
                },
                tmp,
                protocol=pickle_mod.HIGHEST_PROTOCOL,
            )
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        tmp_path.replace(decoder_path)
    except Exception:
        pass

    return decoder


def load_piece_bpe_cache(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> dict[bytes, tuple[int, ...]]:
    pickle_mod = _pickle_module()
    rank_path = ensure_rank_file(name, dir_path=dir_path, timeout=timeout, force=force)
    stat = rank_path.stat()
    rank_size = stat.st_size
    rank_mtime_ns = stat.st_mtime_ns
    piece_path = _piece_pickle_path(rank_path)

    if not force and piece_path.exists():
        try:
            with piece_path.open("rb") as handle:
                cached = pickle_mod.load(handle)
            if (
                isinstance(cached, dict)
                and cached.get("version") == _PIECE_CACHE_VERSION
                and cached.get("size") == rank_size
                and cached.get("mtime_ns") == rank_mtime_ns
                and isinstance(cached.get("pieces"), dict)
            ):
                pieces = cached["pieces"]
                if all(
                    isinstance(key, bytes)
                    and isinstance(value, tuple)
                    and all(isinstance(token, int) for token in value)
                    for key, value in pieces.items()
                ):
                    return pieces
        except Exception:
            pass

    return {}


def save_piece_bpe_cache(
    name: str,
    pieces: dict[bytes, tuple[int, ...]],
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
) -> None:
    pickle_mod = _pickle_module()
    rank_path = ensure_rank_file(name, dir_path=dir_path, timeout=timeout, force=force)
    stat = rank_path.stat()
    piece_path = _piece_pickle_path(rank_path)

    try:
        import tempfile

        with tempfile.NamedTemporaryFile("wb", dir=piece_path.parent, delete=False) as tmp:
            pickle_mod.dump(
                {
                    "version": _PIECE_CACHE_VERSION,
                    "size": stat.st_size,
                    "mtime_ns": stat.st_mtime_ns,
                    "pieces": pieces,
                },
                tmp,
                protocol=pickle_mod.HIGHEST_PROTOCOL,
            )
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        tmp_path.replace(piece_path)
    except Exception:
        pass


def _load_rank_payload_and_ranks_impl(
    name: str,
    *,
    dir_path: Path | None = None,
    timeout: float = 30.0,
    force: bool = False,
    include_payload: bool,
) -> tuple[bytes | None, dict[bytes, int]]:
    pickle_mod = _pickle_module()
    rank_path = ensure_rank_file(name, dir_path=dir_path, timeout=timeout, force=force)
    payload = rank_path.read_bytes() if include_payload else None

    stat = rank_path.stat()
    rank_size = stat.st_size
    rank_mtime_ns = stat.st_mtime_ns
    pickle_path = _rank_pickle_path(rank_path)

    if not force and pickle_path.exists():
        try:
            with pickle_path.open("rb") as handle:
                cached = pickle_mod.load(handle)
            if (
                isinstance(cached, dict)
                and cached.get("version") == _RANK_CACHE_VERSION
                and cached.get("size") == rank_size
                and cached.get("mtime_ns") == rank_mtime_ns
                and isinstance(cached.get("ranks"), dict)
            ):
                return payload, cached["ranks"]
        except Exception:
            pass

    payload_for_parse = payload if payload is not None else rank_path.read_bytes()
    ranks = parse_rank_file_bytes(payload_for_parse)
    try:
        import tempfile

        with tempfile.NamedTemporaryFile("wb", dir=pickle_path.parent, delete=False) as tmp:
            pickle_mod.dump(
                {
                    "version": _RANK_CACHE_VERSION,
                    "size": rank_size,
                    "mtime_ns": rank_mtime_ns,
                    "ranks": ranks,
                },
                tmp,
                protocol=pickle_mod.HIGHEST_PROTOCOL,
            )
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        tmp_path.replace(pickle_path)
    except Exception:
        pass

    return payload, ranks


def parse_rank_file_bytes(payload: bytes) -> dict[bytes, int]:
    if payload.startswith(_NATIVE_PAYLOAD_MAGIC):
        return _parse_native_rank_file_bytes(payload)

    ranks: dict[bytes, int] = {}
    for raw_line in payload.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        token_b64, rank_text = line.split(b" ", 1)
        token_bytes = base64.b64decode(token_b64)
        ranks[token_bytes] = int(rank_text)

    return ranks


def _parse_native_rank_file_bytes(payload: bytes) -> dict[bytes, int]:
    if len(payload) < _NATIVE_PAYLOAD_HEADER.size:
        raise ValueError("invalid native rank payload header")
    magic, version, flags, _source_size, _source_mtime_ns, entry_count, max_rank_plus_one = _NATIVE_PAYLOAD_HEADER.unpack(
        payload[: _NATIVE_PAYLOAD_HEADER.size]
    )
    if (
        magic != _NATIVE_PAYLOAD_MAGIC
        or version != _NATIVE_PAYLOAD_VERSION
        or flags != _NATIVE_PAYLOAD_FLAGS
    ):
        raise ValueError("unsupported native rank payload format")

    cursor = _NATIVE_PAYLOAD_HEADER.size
    ranks: dict[bytes, int] = {}
    for rank in range(max_rank_plus_one):
        if cursor + 4 > len(payload):
            raise ValueError("truncated native rank payload")
        (token_len,) = struct.unpack_from("<I", payload, cursor)
        cursor += 4
        if token_len == _NATIVE_PAYLOAD_MISSING:
            continue
        end = cursor + token_len
        if end > len(payload):
            raise ValueError("truncated native rank payload token bytes")
        token_bytes = payload[cursor:end]
        cursor = end
        ranks[token_bytes] = rank

    if len(ranks) != entry_count:
        raise ValueError("native rank payload entry count mismatch")
    return ranks


def file_sha256(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()
