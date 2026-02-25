"""Native bridge utilities for loading Zig C ABI exports via cffi."""

from __future__ import annotations

import os
import platform
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

try:
    from cffi import FFI
except ModuleNotFoundError:  # pragma: no cover - handled at runtime in bridge state
    FFI = None  # type: ignore[assignment]


def _shared_library_names() -> list[str]:
    if os.name == "nt":
        return ["turbotoken.dll"]
    if platform.system() == "Darwin":
        return ["libturbotoken.dylib", "turbotoken.dylib"]
    return ["libturbotoken.so"]


def _candidate_library_paths() -> list[Path]:
    package_dir = Path(__file__).resolve().parent
    repo_root = package_dir.parents[2]

    candidates: list[Path] = []

    env_path = os.environ.get("TURBOTOKEN_NATIVE_LIB")
    if env_path:
        candidates.append(Path(env_path).expanduser())

    search_dirs = [
        package_dir,
        package_dir / ".libs",
        repo_root / "zig-out" / "lib",
        Path.cwd() / "zig-out" / "lib",
    ]
    for directory in search_dirs:
        for lib_name in _shared_library_names():
            candidates.append(directory / lib_name)

    deduped: list[Path] = []
    seen: set[str] = set()
    for candidate in candidates:
        key = str(candidate)
        if key in seen:
            continue
        seen.add(key)
        deduped.append(candidate)
    return deduped


@dataclass(slots=True)
class NativeBridge:
    _lib: Any | None = None
    _ffi: Any | None = None
    _error: str | None = None

    def load(self) -> None:
        if self._lib is not None or self._error is not None:
            return

        if FFI is None:
            self._error = "cffi is not installed"
            return

        ffi = FFI()
        ffi.cdef(
            """
            const char *turbotoken_version(void);
            long turbotoken_count(const char *text, size_t text_len);
            long turbotoken_encode_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_decode_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            """
        )

        for path in _candidate_library_paths():
            if not path.exists():
                continue
            try:
                self._lib = ffi.dlopen(str(path))
                self._ffi = ffi
                return
            except OSError as exc:
                self._error = f"failed to load {path}: {exc}"
                return

        self._error = "native library not found"

    @property
    def available(self) -> bool:
        self.load()
        return self._lib is not None

    @property
    def error(self) -> str | None:
        self.load()
        return self._error

    def version(self) -> str | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        raw = self._lib.turbotoken_version()
        if raw == self._ffi.NULL:
            return None
        return self._ffi.string(raw).decode("utf-8")

    def count_bytes(self, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        result = int(self._lib.turbotoken_count(data, len(data)))
        if result < 0:
            return None
        return result

    def encode_bpe_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_encode_bpe_from_ranks(
                    rank_payload,
                    len(rank_payload),
                    data,
                    len(data),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_encode_bpe_from_ranks(
                    rank_payload,
                    len(rank_payload),
                    data,
                    len(data),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [int(out[idx]) for idx in range(written)]

    def decode_bpe_from_ranks(self, rank_payload: bytes, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(
                self._lib.turbotoken_decode_bpe_from_ranks(
                    rank_payload,
                    len(rank_payload),
                    token_buf,
                    len(tokens),
                    self._ffi.NULL,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = self._ffi.new("unsigned char[]", needed)
        try:
            written = int(
                self._lib.turbotoken_decode_bpe_from_ranks(
                    rank_payload,
                    len(rank_payload),
                    token_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return bytes(self._ffi.buffer(out, written))


@lru_cache(maxsize=1)
def get_native_bridge() -> NativeBridge:
    return NativeBridge()
