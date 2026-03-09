"""Native bridge utilities for loading Zig C ABI exports via ctypes/cffi."""

from __future__ import annotations

import ctypes
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

try:
    _PY_BYTES_AS_STRING = ctypes.pythonapi.PyBytes_AsString
    _PY_BYTES_AS_STRING.argtypes = [ctypes.py_object]
    _PY_BYTES_AS_STRING.restype = ctypes.c_void_p
except AttributeError:  # pragma: no cover - platform/runtime specific
    _PY_BYTES_AS_STRING = None

try:
    _PY_UNICODE_AS_UTF8_AND_SIZE = ctypes.pythonapi.PyUnicode_AsUTF8AndSize
    _PY_UNICODE_AS_UTF8_AND_SIZE.argtypes = [ctypes.py_object, ctypes.POINTER(ctypes.c_ssize_t)]
    _PY_UNICODE_AS_UTF8_AND_SIZE.restype = ctypes.c_void_p
except AttributeError:  # pragma: no cover - platform/runtime specific
    _PY_UNICODE_AS_UTF8_AND_SIZE = None


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


def _unpack_u32(ffi: Any, out: Any, written: int) -> list[int]:
    if written <= 0:
        return []
    try:
        return list(ffi.unpack(out, written))
    except AttributeError:
        return [int(out[idx]) for idx in range(written)]


def _fast_encode_output_capacity(input_len: int) -> int:
    if input_len <= 0:
        return 0
    if input_len <= 4096:
        return input_len
    return min(input_len, max(4096, (input_len + 3) // 4))


def _configure_fast_ctypes(lib: Any) -> None:
    void_p = ctypes.c_void_p
    size_t = ctypes.c_size_t
    long_t = ctypes.c_long
    u32_p = ctypes.POINTER(ctypes.c_uint32)
    u8_p = ctypes.POINTER(ctypes.c_ubyte)

    lib.turbotoken_version.argtypes = []
    lib.turbotoken_version.restype = ctypes.c_char_p
    lib.turbotoken_clear_rank_table_cache.argtypes = []
    lib.turbotoken_clear_rank_table_cache.restype = None

    lib.turbotoken_pretokenize_ascii_letter_space_ranges.argtypes = [void_p, size_t, u32_p, u32_p, size_t]
    lib.turbotoken_pretokenize_ascii_letter_space_ranges.restype = long_t
    lib.turbotoken_pretokenize_ascii_o200k_ranges.argtypes = [void_p, size_t, u32_p, u32_p, size_t]
    lib.turbotoken_pretokenize_ascii_o200k_ranges.restype = long_t

    lib.turbotoken_count_bpe_from_ranks.argtypes = [void_p, size_t, void_p, size_t]
    lib.turbotoken_count_bpe_from_ranks.restype = long_t
    lib.turbotoken_encode_bpe_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, size_t]
    lib.turbotoken_encode_bpe_from_ranks.restype = long_t
    lib.turbotoken_is_within_token_limit_bpe_from_ranks.argtypes = [void_p, size_t, void_p, size_t, size_t]
    lib.turbotoken_is_within_token_limit_bpe_from_ranks.restype = long_t
    lib.turbotoken_encode_bpe_batch_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, size_t, u32_p, size_t, u32_p, size_t]
    lib.turbotoken_encode_bpe_batch_from_ranks.restype = long_t
    lib.turbotoken_encode_bpe_ranges_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, u32_p, size_t, u32_p, size_t, u32_p, size_t]
    lib.turbotoken_encode_bpe_ranges_from_ranks.restype = long_t
    lib.turbotoken_count_bpe_ranges_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, u32_p, size_t]
    lib.turbotoken_count_bpe_ranges_from_ranks.restype = long_t

    lib.turbotoken_count_bpe_ascii_letter_space_from_ranks.argtypes = [void_p, size_t, void_p, size_t]
    lib.turbotoken_count_bpe_ascii_letter_space_from_ranks.restype = long_t
    lib.turbotoken_encode_bpe_ascii_letter_space_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, size_t]
    lib.turbotoken_encode_bpe_ascii_letter_space_from_ranks.restype = long_t

    lib.turbotoken_count_bpe_ascii_o200k_from_ranks.argtypes = [void_p, size_t, void_p, size_t]
    lib.turbotoken_count_bpe_ascii_o200k_from_ranks.restype = long_t
    lib.turbotoken_encode_bpe_ascii_o200k_from_ranks.argtypes = [void_p, size_t, void_p, size_t, u32_p, size_t]
    lib.turbotoken_encode_bpe_ascii_o200k_from_ranks.restype = long_t

    lib.turbotoken_decode_bpe_from_ranks.argtypes = [void_p, size_t, u32_p, size_t, u8_p, size_t]
    lib.turbotoken_decode_bpe_from_ranks.restype = long_t


@dataclass(slots=True)
class NativeBridge:
    _lib: Any | None = None
    _ffi: Any | None = None
    _error: str | None = None
    _rank_payload_ref: bytes | None = None
    _rank_payload_buf: Any | None = None
    _fast_lib: Any | None = None
    _fast_error: str | None = None
    _fast_rank_payload_ref: bytes | None = None
    _fast_rank_payload_buf: Any | None = None
    _rank_session_payload_ref: bytes | None = None
    _rank_session_cache: "NativeRankSession | None" = None

    def _load_fast_lib(self) -> Any | None:
        if self._fast_lib is not None:
            return self._fast_lib
        if self._fast_error is not None:
            return None

        last_error: str | None = None
        for path in _candidate_library_paths():
            if not path.exists():
                continue
            try:
                lib = ctypes.CDLL(str(path))
                _configure_fast_ctypes(lib)
                self._fast_lib = lib
                return lib
            except OSError as exc:
                last_error = f"failed to load {path}: {exc}"
                break

        self._fast_error = last_error or "native library not found"
        return None

    def _fast_rank_payload_ptr(self, rank_payload: bytes) -> Any | None:
        if self._load_fast_lib() is None:
            return None
        if self._fast_rank_payload_ref is not rank_payload or self._fast_rank_payload_buf is None:
            self._fast_rank_payload_ref = rank_payload
            self._fast_rank_payload_buf = self._fast_bytes_view(rank_payload)
        return self._fast_rank_payload_buf

    @staticmethod
    def _fast_bytes_view(data: bytes) -> Any:
        if _PY_BYTES_AS_STRING is not None:
            try:
                ptr = _PY_BYTES_AS_STRING(data)
            except (TypeError, ValueError):
                ptr = None
            if ptr is not None:
                return ctypes.c_void_p(ptr)
        return ctypes.create_string_buffer(data)

    @staticmethod
    def _fast_ascii_text_view(text: str) -> tuple[Any, int] | None:
        if _PY_UNICODE_AS_UTF8_AND_SIZE is None or not text.isascii():
            return None
        size = ctypes.c_ssize_t()
        try:
            ptr = _PY_UNICODE_AS_UTF8_AND_SIZE(text, ctypes.byref(size))
        except (TypeError, ValueError):
            return None
        if ptr is None or size.value < 0:
            return None
        return (ctypes.c_void_p(ptr), int(size.value))

    def _fast_pretokenize_ranges(self, symbol: str, data: bytes) -> list[tuple[int, int]] | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None

        in_buf = self._fast_bytes_view(data)
        try:
            needed = int(getattr(lib, symbol)(in_buf, len(data), None, None, 0))
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        starts = (ctypes.c_uint32 * needed)()
        ends = (ctypes.c_uint32 * needed)()
        try:
            written = int(getattr(lib, symbol)(in_buf, len(data), starts, ends, needed))
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [(int(starts[idx]), int(ends[idx])) for idx in range(written)]

    def _fast_count_from_ranks(self, symbol: str, rank_payload: bytes, data: bytes) -> int | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._fast_bytes_view(data)
        try:
            result = int(getattr(lib, symbol)(rank_buf, len(rank_payload), in_buf, len(data)))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def _fast_count_from_ranks_text(self, symbol: str, rank_payload: bytes, text: str) -> int | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        view = self._fast_ascii_text_view(text)
        if view is None:
            return None

        in_buf, text_len = view
        try:
            result = int(getattr(lib, symbol)(rank_buf, len(rank_payload), in_buf, text_len))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def _fast_encode_from_ranks(self, symbol: str, rank_payload: bytes, data: bytes) -> list[int] | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        if not data:
            return []

        in_buf = self._fast_bytes_view(data)
        input_len = len(data)
        initial_cap = _fast_encode_output_capacity(input_len)
        for out_cap in (initial_cap, input_len) if initial_cap < input_len else (input_len,):
            out = (ctypes.c_uint32 * out_cap)()
            try:
                written = int(getattr(lib, symbol)(rank_buf, len(rank_payload), in_buf, input_len, out, out_cap))
            except (AttributeError, OverflowError, TypeError):
                return None
            if written >= 0:
                return out[:written]
        return None

    def _fast_encode_from_ranks_text(self, symbol: str, rank_payload: bytes, text: str) -> list[int] | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        view = self._fast_ascii_text_view(text)
        if view is None:
            return None

        in_buf, text_len = view
        if text_len == 0:
            return []

        initial_cap = _fast_encode_output_capacity(text_len)
        for out_cap in (initial_cap, text_len) if initial_cap < text_len else (text_len,):
            out = (ctypes.c_uint32 * out_cap)()
            try:
                written = int(getattr(lib, symbol)(rank_buf, len(rank_payload), in_buf, text_len, out, out_cap))
            except (AttributeError, OverflowError, TypeError):
                return None
            if written >= 0:
                return out[:written]
        return None

    def _fast_is_within_limit_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        token_limit: int,
    ) -> int | bool | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        if token_limit < 0:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._fast_bytes_view(data)
        try:
            result = int(
                lib.turbotoken_is_within_token_limit_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    token_limit,
                )
            )
        except (AttributeError, TypeError):
            return None
        if result == -2:
            return False
        if result < 0:
            return None
        return result

    def _fast_encode_batch_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        offsets: list[int],
    ) -> tuple[list[int], list[int]] | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(offsets) == 0 or len(data) > 0xFFFFFFFF:
            return None
        if offsets[0] != 0 or offsets[-1] != len(data):
            return None
        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(data) or value > 0xFFFFFFFF:
                return None
            prev = value

        in_buf = self._fast_bytes_view(data)
        offsets_buf = (ctypes.c_uint32 * len(offsets))(*offsets)
        token_offsets = (ctypes.c_uint32 * len(offsets))()
        out_cap = max(1, len(data))
        out = (ctypes.c_uint32 * out_cap)()
        try:
            written = int(
                lib.turbotoken_encode_bpe_batch_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    offsets_buf,
                    len(offsets),
                    out,
                    len(data),
                    token_offsets,
                    len(offsets),
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            [int(out[idx]) for idx in range(written)],
            [int(token_offsets[idx]) for idx in range(len(offsets))],
        )

    def _fast_encode_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> tuple[list[int], list[int]] | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None or len(data) > 0xFFFFFFFF:
            return None

        starts: list[int] = []
        ends: list[int] = []
        upper_bound = 0
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)
            upper_bound += end - start
            if upper_bound > 0x7FFFFFFF_FFFFFFFF:
                return None

        in_buf = self._fast_bytes_view(data)
        starts_buf = (ctypes.c_uint32 * len(starts))(*starts)
        ends_buf = (ctypes.c_uint32 * len(ends))(*ends)
        token_offsets = (ctypes.c_uint32 * (len(ranges) + 1))()
        out_cap = max(1, upper_bound)
        out = (ctypes.c_uint32 * out_cap)()
        try:
            written = int(
                lib.turbotoken_encode_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                    out,
                    upper_bound,
                    token_offsets,
                    len(ranges) + 1,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            [int(out[idx]) for idx in range(written)],
            [int(token_offsets[idx]) for idx in range(len(ranges) + 1)],
        )

    def _fast_count_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> int | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None or len(data) > 0xFFFFFFFF:
            return None

        starts: list[int] = []
        ends: list[int] = []
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)

        in_buf = self._fast_bytes_view(data)
        starts_buf = (ctypes.c_uint32 * len(starts))(*starts)
        ends_buf = (ctypes.c_uint32 * len(ends))(*ends)
        try:
            result = int(
                lib.turbotoken_count_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def _fast_decode_from_ranks(self, rank_payload: bytes, tokens: list[int]) -> bytes | None:
        lib = self._load_fast_lib()
        if lib is None:
            return None
        rank_buf = self._fast_rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        token_buf = (ctypes.c_uint32 * len(tokens))(*tokens)
        try:
            needed = int(
                lib.turbotoken_decode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    token_buf,
                    len(tokens),
                    None,
                    0,
                )
            )
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = (ctypes.c_ubyte * needed)()
        try:
            written = int(
                lib.turbotoken_decode_bpe_from_ranks(
                    rank_buf,
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
        return bytes(out[:written])

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
            long turbotoken_pretokenize_ascii_letter_space_ranges(
                const char *text,
                size_t text_len,
                uint32_t *out_starts,
                uint32_t *out_ends,
                size_t out_cap
            );
            long turbotoken_pretokenize_ascii_o200k_ranges(
                const char *text,
                size_t text_len,
                uint32_t *out_starts,
                uint32_t *out_ends,
                size_t out_cap
            );
            unsigned long long turbotoken_arm64_feature_mask(void);
            unsigned int turbotoken_count_non_ascii_kernel_id(void);
            long turbotoken_count_non_ascii_utf8(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_scalar(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_neon(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_dotprod(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_non_ascii_utf8_sme(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8_scalar(
                const char *text,
                size_t text_len
            );
            long turbotoken_count_ascii_class_boundaries_utf8_neon(
                const char *text,
                size_t text_len
            );
            long turbotoken_encode_utf8_bytes(
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_encode_utf8_bytes_scalar(
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_decode_utf8_bytes(
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            long turbotoken_decode_utf8_bytes_scalar(
                const uint32_t *tokens,
                size_t token_len,
                unsigned char *out_bytes,
                size_t out_cap
            );
            void turbotoken_clear_rank_table_cache(void);
            long turbotoken_encode_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_train_bpe_from_chunk_counts(
                const char *chunks,
                size_t chunks_len,
                const uint32_t *chunk_offsets,
                size_t chunk_offsets_len,
                const uint32_t *chunk_counts,
                size_t chunk_counts_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_train_bpe_ascii_o200k(
                const char *text,
                size_t text_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_train_bpe_ascii_o200k_multi(
                const char *texts,
                size_t texts_len,
                const uint32_t *text_offsets,
                size_t text_offsets_len,
                uint32_t vocab_size,
                uint32_t min_frequency,
                uint32_t *out_merges,
                size_t out_cap
            );
            long turbotoken_encode_bpe_batch_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                const uint32_t *offsets,
                size_t offsets_len,
                uint32_t *out_tokens,
                size_t out_cap,
                uint32_t *out_token_offsets,
                size_t out_token_offsets_len
            );
            long turbotoken_encode_bpe_ranges_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                const uint32_t *range_starts,
                const uint32_t *range_ends,
                size_t ranges_len,
                uint32_t *out_tokens,
                size_t out_cap,
                uint32_t *out_token_offsets,
                size_t out_token_offsets_len
            );
            long turbotoken_count_bpe_ranges_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                const uint32_t *range_starts,
                const uint32_t *range_ends,
                size_t ranges_len
            );
            long turbotoken_bpe_ranges_token_layout_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                size_t input_len,
                const uint32_t *range_starts,
                const uint32_t *range_ends,
                size_t ranges_len,
                const uint32_t *tokens,
                size_t token_len,
                const uint32_t *token_offsets,
                size_t token_offsets_len,
                uint32_t source_chunk_base,
                uint32_t chunk_bytes,
                uint32_t num_chunks,
                uint32_t *out_token_starts,
                uint32_t *out_source_chunks,
                size_t out_cap
            );
            long turbotoken_filter_tokens_by_keep_flags(
                const uint32_t *tokens,
                const uint32_t *keep_flags,
                size_t token_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_encode_bpe_chunked_stitched_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                size_t chunk_bytes,
                size_t overlap_bytes,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_count_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len
            );
            long turbotoken_is_within_token_limit_bpe_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                size_t token_limit
            );
            long turbotoken_encode_bpe_file_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *file_path,
                size_t file_path_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_count_bpe_file_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *file_path,
                size_t file_path_len
            );
            long turbotoken_is_within_token_limit_bpe_file_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *file_path,
                size_t file_path_len,
                size_t token_limit
            );
            long turbotoken_count_bpe_ascii_letter_space_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len
            );
            long turbotoken_encode_bpe_ascii_letter_space_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len,
                uint32_t *out_tokens,
                size_t out_cap
            );
            long turbotoken_count_bpe_ascii_o200k_from_ranks(
                const char *rank_bytes,
                size_t rank_len,
                const char *text,
                size_t text_len
            );
            long turbotoken_encode_bpe_ascii_o200k_from_ranks(
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
        return self._load_fast_lib() is not None or self._load_cffi_available()

    @property
    def error(self) -> str | None:
        if self.available:
            return None
        return self._fast_error or self._error

    def _load_cffi_available(self) -> bool:
        self.load()
        return self._lib is not None

    def version(self) -> str | None:
        fast = self._load_fast_lib()
        if fast is not None:
            raw = fast.turbotoken_version()
            return raw.decode("utf-8") if raw is not None else None

        self.load()
        if self._lib is None or self._ffi is None:
            return None

        raw = self._lib.turbotoken_version()
        if raw == self._ffi.NULL:
            return None
        return self._ffi.string(raw).decode("utf-8")

    def _rank_payload_ptr(self, rank_payload: bytes) -> Any | None:
        self.load()
        if self._ffi is None:
            return None
        if self._rank_payload_ref is not rank_payload or self._rank_payload_buf is None:
            self._rank_payload_ref = rank_payload
            self._rank_payload_buf = self._ffi.from_buffer("const char[]", rank_payload)
        return self._rank_payload_buf

    @staticmethod
    def _path_to_bytes(path: Any) -> bytes | None:
        try:
            raw = os.fsencode(path)
        except (TypeError, ValueError):
            return None
        if not raw or b"\x00" in raw:
            return None
        return raw

    def rank_session(self, rank_payload: bytes) -> "NativeRankSession | None":
        if not self.available:
            return None
        if (
            self._rank_session_cache is not None
            and self._rank_session_payload_ref is rank_payload
        ):
            return self._rank_session_cache
        if self._fast_rank_payload_ptr(rank_payload) is None and self._rank_payload_ptr(rank_payload) is None:
            return None
        session = NativeRankSession(_bridge=self, _rank_payload=rank_payload)
        self._rank_session_payload_ref = rank_payload
        self._rank_session_cache = session
        return session

    def clear_rank_table_cache(self) -> bool:
        fast = self._load_fast_lib()
        if fast is not None:
            try:
                fast.turbotoken_clear_rank_table_cache()
            except (AttributeError, TypeError):
                return False
            return True

        self.load()
        if self._lib is None:
            return False
        try:
            self._lib.turbotoken_clear_rank_table_cache()
        except (AttributeError, TypeError):
            return False
        return True

    def count_bytes(self, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        result = int(self._lib.turbotoken_count(data, len(data)))
        if result < 0:
            return None
        return result

    def pretokenize_ascii_letter_space_ranges(
        self,
        data: bytes,
    ) -> list[tuple[int, int]] | None:
        fast = self._fast_pretokenize_ranges("turbotoken_pretokenize_ascii_letter_space_ranges", data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_pretokenize_ascii_letter_space_ranges(
                    data,
                    len(data),
                    self._ffi.NULL,
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

        starts = self._ffi.new("uint32_t[]", needed)
        ends = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_pretokenize_ascii_letter_space_ranges(
                    data,
                    len(data),
                    starts,
                    ends,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [(int(starts[idx]), int(ends[idx])) for idx in range(written)]

    def pretokenize_ascii_o200k_ranges(
        self,
        data: bytes,
    ) -> list[tuple[int, int]] | None:
        fast = self._fast_pretokenize_ranges("turbotoken_pretokenize_ascii_o200k_ranges", data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_pretokenize_ascii_o200k_ranges(
                    data,
                    len(data),
                    self._ffi.NULL,
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

        starts = self._ffi.new("uint32_t[]", needed)
        ends = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_pretokenize_ascii_o200k_ranges(
                    data,
                    len(data),
                    starts,
                    ends,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return [(int(starts[idx]), int(ends[idx])) for idx in range(written)]

    def arm64_feature_mask(self) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            return int(self._lib.turbotoken_arm64_feature_mask())
        except (AttributeError, TypeError):
            return None

    def count_non_ascii_kernel_id(self) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            return int(self._lib.turbotoken_count_non_ascii_kernel_id())
        except (AttributeError, TypeError):
            return None

    def _count_non_ascii(self, symbol: str, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            fn = getattr(self._lib, symbol)
            result = int(fn(data, len(data)))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_non_ascii_utf8(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8", data)

    def count_non_ascii_utf8_scalar(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_scalar", data)

    def count_non_ascii_utf8_neon(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_neon", data)

    def count_non_ascii_utf8_dotprod(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_dotprod", data)

    def count_non_ascii_utf8_sme(self, data: bytes) -> int | None:
        return self._count_non_ascii("turbotoken_count_non_ascii_utf8_sme", data)

    def _count_ascii_boundaries(self, symbol: str, data: bytes) -> int | None:
        self.load()
        if self._lib is None:
            return None

        try:
            fn = getattr(self._lib, symbol)
            result = int(fn(data, len(data)))
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_ascii_class_boundaries_utf8(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8", data)

    def count_ascii_class_boundaries_utf8_scalar(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8_scalar", data)

    def count_ascii_class_boundaries_utf8_neon(self, data: bytes) -> int | None:
        return self._count_ascii_boundaries("turbotoken_count_ascii_class_boundaries_utf8_neon", data)

    def encode_utf8_bytes(self, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(self._lib.turbotoken_encode_utf8_bytes(data, len(data), self._ffi.NULL, 0))
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(self._lib.turbotoken_encode_utf8_bytes(data, len(data), out, needed))
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def decode_utf8_bytes(self, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(self._lib.turbotoken_decode_utf8_bytes(token_buf, len(tokens), self._ffi.NULL, 0))
        except (AttributeError, TypeError):
            return None
        if needed < 0:
            return None
        if needed == 0:
            return b""

        out = self._ffi.new("unsigned char[]", needed)
        try:
            written = int(
                self._lib.turbotoken_decode_utf8_bytes(
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

    def encode_utf8_bytes_scalar(self, data: bytes) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        try:
            needed = int(
                self._lib.turbotoken_encode_utf8_bytes_scalar(data, len(data), self._ffi.NULL, 0)
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
                self._lib.turbotoken_encode_utf8_bytes_scalar(data, len(data), out, needed)
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def decode_utf8_bytes_scalar(self, tokens: list[int]) -> bytes | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(
                self._lib.turbotoken_decode_utf8_bytes_scalar(
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
                self._lib.turbotoken_decode_utf8_bytes_scalar(
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

    def encode_bpe_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        fast = self._fast_encode_from_ranks("turbotoken_encode_bpe_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if not data:
            return []

        try:
            # BPE output token count is bounded by input byte length.
            out = self._ffi.new("uint32_t[]", len(data))
            written = int(
                self._lib.turbotoken_encode_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                    out,
                    len(data),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def train_bpe_from_chunk_counts(
        self,
        chunks: bytes,
        offsets: list[int],
        counts: list[int],
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None
        if len(offsets) == 0 or len(counts) + 1 != len(offsets):
            return None
        if offsets[0] != 0 or offsets[-1] != len(chunks):
            return None

        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(chunks) or value > 0xFFFFFFFF:
                return None
            prev = value
        for count in counts:
            if count < 0 or count > 0xFFFFFFFF:
                return None

        chunk_buf = self._ffi.from_buffer("const char[]", chunks)
        offsets_buf = self._ffi.new("uint32_t[]", offsets)
        counts_buf = self._ffi.new("uint32_t[]", counts)

        max_merges = max(0, vocab_size - 256)
        if max_merges == 0:
            return []

        flat_len = max_merges * 3
        try:
            out = self._ffi.new("uint32_t[]", flat_len)
            written = int(
                self._lib.turbotoken_train_bpe_from_chunk_counts(
                    chunk_buf,
                    len(chunks),
                    offsets_buf,
                    len(offsets),
                    counts_buf,
                    len(counts),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def train_bpe_ascii_o200k(
        self,
        text: bytes,
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None

        in_buf = self._ffi.from_buffer("const char[]", text)
        max_merges = max(0, vocab_size - 256)
        if max_merges == 0:
            return []

        flat_len = max_merges * 3
        try:
            out = self._ffi.new("uint32_t[]", flat_len)
            written = int(
                self._lib.turbotoken_train_bpe_ascii_o200k(
                    in_buf,
                    len(text),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def train_bpe_ascii_o200k_multi(
        self,
        texts: bytes,
        offsets: list[int],
        *,
        vocab_size: int,
        min_frequency: int,
    ) -> list[tuple[int, int, int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if vocab_size < 256 or min_frequency < 1:
            return None
        if len(offsets) == 0 or offsets[0] != 0 or offsets[-1] != len(texts):
            return None

        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(texts) or value > 0xFFFFFFFF:
                return None
            prev = value

        in_buf = self._ffi.from_buffer("const char[]", texts)
        max_merges = max(0, vocab_size - 256)
        if max_merges == 0:
            return []

        flat_len = max_merges * 3
        try:
            offsets_buf = self._ffi.new("uint32_t[]", offsets)
            out = self._ffi.new("uint32_t[]", flat_len)
            written = int(
                self._lib.turbotoken_train_bpe_ascii_o200k_multi(
                    in_buf,
                    len(texts),
                    offsets_buf,
                    len(offsets),
                    vocab_size,
                    min_frequency,
                    out,
                    flat_len,
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None

        merges: list[tuple[int, int, int]] = []
        for idx in range(written):
            base = idx * 3
            merges.append((int(out[base]), int(out[base + 1]), int(out[base + 2])))
        return merges

    def encode_bpe_batch_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        offsets: list[int],
    ) -> tuple[list[int], list[int]] | None:
        fast = self._fast_encode_batch_from_ranks(rank_payload, data, offsets)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(offsets) == 0:
            return None
        if len(data) > 0xFFFFFFFF:
            return None
        if offsets[0] != 0 or offsets[-1] != len(data):
            return None
        prev = 0
        for value in offsets:
            if value < prev or value < 0 or value > len(data) or value > 0xFFFFFFFF:
                return None
            prev = value

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            offsets_buf = self._ffi.new("uint32_t[]", offsets)
            token_offsets = self._ffi.new("uint32_t[]", len(offsets))
            # BPE output token count is bounded by input bytes, so one pass is enough.
            out = self._ffi.new("uint32_t[]", max(1, len(data)))
        except (OverflowError, TypeError):
            return None
        try:
            written = int(
                self._lib.turbotoken_encode_bpe_batch_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    offsets_buf,
                    len(offsets),
                    out,
                    len(data),
                    token_offsets,
                    len(offsets),
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None

        return (
            _unpack_u32(self._ffi, out, written),
            _unpack_u32(self._ffi, token_offsets, len(offsets)),
        )

    def encode_bpe_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> tuple[list[int], list[int]] | None:
        fast = self._fast_encode_ranges_from_ranks(rank_payload, data, ranges)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(data) > 0xFFFFFFFF:
            return None
        starts: list[int] = []
        ends: list[int] = []
        upper_bound = 0
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)
            upper_bound += end - start
            if upper_bound > 0x7FFFFFFF_FFFFFFFF:
                return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            token_offsets = self._ffi.new("uint32_t[]", len(ranges) + 1)
            out = self._ffi.new("uint32_t[]", max(1, upper_bound))
        except (OverflowError, TypeError):
            return None

        try:
            written = int(
                self._lib.turbotoken_encode_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                    out,
                    upper_bound,
                    token_offsets,
                    len(ranges) + 1,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            _unpack_u32(self._ffi, out, written),
            _unpack_u32(self._ffi, token_offsets, len(ranges) + 1),
        )

    def count_bpe_ranges_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> int | None:
        fast = self._fast_count_ranges_from_ranks(rank_payload, data, ranges)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if len(data) > 0xFFFFFFFF:
            return None
        starts: list[int] = []
        ends: list[int] = []
        for start, end in ranges:
            if start < 0 or end < start or end > len(data) or end > 0xFFFFFFFF:
                return None
            starts.append(start)
            ends.append(end)

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            result = int(
                self._lib.turbotoken_count_bpe_ranges_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    starts_buf,
                    ends_buf,
                    len(ranges),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def encode_bpe_chunked_stitched_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        *,
        chunk_bytes: int,
        overlap_bytes: int,
    ) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        if chunk_bytes <= 0 or overlap_bytes <= 0:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            out = self._ffi.new("uint32_t[]", max(1, len(data)))
            written = int(
                self._lib.turbotoken_encode_bpe_chunked_stitched_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    chunk_bytes,
                    overlap_bytes,
                    out,
                    len(data),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def bpe_ranges_token_layout_from_ranks(
        self,
        rank_payload: bytes,
        *,
        input_len: int,
        starts: list[int],
        ends: list[int],
        tokens: list[int],
        token_offsets: list[int],
        source_chunk_base: int,
        chunk_bytes: int,
        num_chunks: int,
    ) -> tuple[list[int], list[int]] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if input_len < 0 or input_len > 0xFFFFFFFF:
            return None
        if chunk_bytes <= 0 or chunk_bytes > 0xFFFFFFFF:
            return None
        if num_chunks <= 0 or num_chunks > 0xFFFFFFFF:
            return None
        if source_chunk_base < 0 or source_chunk_base > 0xFFFFFFFF:
            return None
        if len(starts) != len(ends):
            return None
        if len(token_offsets) != len(starts) + 1:
            return None
        if len(tokens) > 0xFFFFFFFF:
            return None

        for start, end in zip(starts, ends):
            if start < 0 or end < start or end > input_len or end > 0xFFFFFFFF:
                return None

        prev = 0
        for value in token_offsets:
            if value < prev or value < 0 or value > len(tokens) or value > 0xFFFFFFFF:
                return None
            prev = value

        try:
            starts_buf = self._ffi.new("uint32_t[]", starts)
            ends_buf = self._ffi.new("uint32_t[]", ends)
            tokens_buf = self._ffi.new("uint32_t[]", tokens)
            offsets_buf = self._ffi.new("uint32_t[]", token_offsets)
            out_starts = self._ffi.new("uint32_t[]", max(1, len(tokens)))
            out_chunks = self._ffi.new("uint32_t[]", max(1, len(tokens)))
        except (OverflowError, TypeError):
            return None

        try:
            written = int(
                self._lib.turbotoken_bpe_ranges_token_layout_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    input_len,
                    starts_buf,
                    ends_buf,
                    len(starts),
                    tokens_buf,
                    len(tokens),
                    offsets_buf,
                    len(token_offsets),
                    source_chunk_base,
                    chunk_bytes,
                    num_chunks,
                    out_starts,
                    out_chunks,
                    len(tokens),
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return (
            _unpack_u32(self._ffi, out_starts, written),
            _unpack_u32(self._ffi, out_chunks, written),
        )

    def filter_tokens_by_keep_flags(
        self,
        tokens: list[int],
        keep_flags: list[int],
    ) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if len(tokens) != len(keep_flags):
            return None
        if len(tokens) > 0xFFFFFFFF:
            return None
        if len(tokens) == 0:
            return []

        try:
            token_buf = self._ffi.new("uint32_t[]", tokens)
            flag_buf = self._ffi.new("uint32_t[]", keep_flags)
        except (OverflowError, TypeError):
            return None

        try:
            needed = int(
                self._lib.turbotoken_filter_tokens_by_keep_flags(
                    token_buf,
                    flag_buf,
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
            return []

        out = self._ffi.new("uint32_t[]", needed)
        try:
            written = int(
                self._lib.turbotoken_filter_tokens_by_keep_flags(
                    token_buf,
                    flag_buf,
                    len(tokens),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def count_bpe_from_ranks(self, rank_payload: bytes, data: bytes) -> int | None:
        fast = self._fast_count_from_ranks("turbotoken_count_bpe_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        try:
            result = int(
                self._lib.turbotoken_count_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def is_within_token_limit_bpe_from_ranks(
        self,
        rank_payload: bytes,
        data: bytes,
        token_limit: int,
    ) -> int | bool | None:
        fast = self._fast_is_within_limit_from_ranks(rank_payload, data, token_limit)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None:
            return None
        if token_limit < 0:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        try:
            result = int(
                self._lib.turbotoken_is_within_token_limit_bpe_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    data,
                    len(data),
                    token_limit,
                )
            )
        except (AttributeError, TypeError):
            return None
        if result == -2:
            return False
        if result < 0:
            return None
        return result

    def encode_bpe_file_from_ranks(self, rank_payload: bytes, path: Any) -> list[int] | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        path_bytes = self._path_to_bytes(path)
        if path_bytes is None:
            return None

        path_buf = self._ffi.from_buffer("const char[]", path_bytes)
        try:
            needed = int(
                self._lib.turbotoken_encode_bpe_file_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    path_buf,
                    len(path_bytes),
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
                self._lib.turbotoken_encode_bpe_file_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    path_buf,
                    len(path_bytes),
                    out,
                    needed,
                )
            )
        except (AttributeError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def count_bpe_file_from_ranks(self, rank_payload: bytes, path: Any) -> int | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        path_bytes = self._path_to_bytes(path)
        if path_bytes is None:
            return None

        path_buf = self._ffi.from_buffer("const char[]", path_bytes)
        try:
            result = int(
                self._lib.turbotoken_count_bpe_file_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    path_buf,
                    len(path_bytes),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def is_within_token_limit_bpe_file_from_ranks(
        self,
        rank_payload: bytes,
        path: Any,
        token_limit: int,
    ) -> int | bool | None:
        self.load()
        if self._lib is None or self._ffi is None:
            return None
        if token_limit < 0:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None
        path_bytes = self._path_to_bytes(path)
        if path_bytes is None:
            return None

        path_buf = self._ffi.from_buffer("const char[]", path_bytes)
        try:
            result = int(
                self._lib.turbotoken_is_within_token_limit_bpe_file_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    path_buf,
                    len(path_bytes),
                    token_limit,
                )
            )
        except (AttributeError, TypeError):
            return None
        if result == -2:
            return False
        if result < 0:
            return None
        return result

    def count_bpe_ascii_letter_space_from_ranks(self, rank_payload: bytes, data: bytes) -> int | None:
        fast = self._fast_count_from_ranks("turbotoken_count_bpe_ascii_letter_space_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            result = int(
                self._lib.turbotoken_count_bpe_ascii_letter_space_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def encode_bpe_ascii_letter_space_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        fast = self._fast_encode_from_ranks("turbotoken_encode_bpe_ascii_letter_space_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if not data:
            return []

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            # BPE output token count is bounded by input byte length.
            out = self._ffi.new("uint32_t[]", len(data))
            written = int(
                self._lib.turbotoken_encode_bpe_ascii_letter_space_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    out,
                    len(data),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def count_bpe_ascii_o200k_from_ranks(self, rank_payload: bytes, data: bytes) -> int | None:
        fast = self._fast_count_from_ranks("turbotoken_count_bpe_ascii_o200k_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            result = int(
                self._lib.turbotoken_count_bpe_ascii_o200k_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                )
            )
        except (AttributeError, TypeError):
            return None
        if result < 0:
            return None
        return result

    def count_bpe_ascii_o200k_text_from_ranks(self, rank_payload: bytes, text: str) -> int | None:
        fast = self._fast_count_from_ranks_text("turbotoken_count_bpe_ascii_o200k_from_ranks", rank_payload, text)
        if fast is not None:
            return fast
        return self.count_bpe_ascii_o200k_from_ranks(rank_payload, text.encode("ascii"))

    def encode_bpe_ascii_o200k_from_ranks(self, rank_payload: bytes, data: bytes) -> list[int] | None:
        fast = self._fast_encode_from_ranks("turbotoken_encode_bpe_ascii_o200k_from_ranks", rank_payload, data)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        if not data:
            return []

        in_buf = self._ffi.from_buffer("const char[]", data)
        try:
            # BPE output token count is bounded by input byte length.
            out = self._ffi.new("uint32_t[]", len(data))
            written = int(
                self._lib.turbotoken_encode_bpe_ascii_o200k_from_ranks(
                    rank_buf,
                    len(rank_payload),
                    in_buf,
                    len(data),
                    out,
                    len(data),
                )
            )
        except (AttributeError, OverflowError, TypeError):
            return None
        if written < 0:
            return None
        return _unpack_u32(self._ffi, out, written)

    def encode_bpe_ascii_o200k_text_from_ranks(self, rank_payload: bytes, text: str) -> list[int] | None:
        fast = self._fast_encode_from_ranks_text("turbotoken_encode_bpe_ascii_o200k_from_ranks", rank_payload, text)
        if fast is not None:
            return fast
        return self.encode_bpe_ascii_o200k_from_ranks(rank_payload, text.encode("ascii"))

    def decode_bpe_from_ranks(self, rank_payload: bytes, tokens: list[int]) -> bytes | None:
        fast = self._fast_decode_from_ranks(rank_payload, tokens)
        if fast is not None:
            return fast

        self.load()
        if self._lib is None or self._ffi is None:
            return None
        rank_buf = self._rank_payload_ptr(rank_payload)
        if rank_buf is None:
            return None

        token_buf = self._ffi.new("uint32_t[]", tokens)
        try:
            needed = int(
                self._lib.turbotoken_decode_bpe_from_ranks(
                    rank_buf,
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
                    rank_buf,
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


@dataclass(slots=True)
class NativeRankSession:
    _bridge: NativeBridge
    _rank_payload: bytes

    def encode_bpe(self, data: bytes) -> list[int] | None:
        return self._bridge.encode_bpe_from_ranks(self._rank_payload, data)

    def count_bpe(self, data: bytes) -> int | None:
        return self._bridge.count_bpe_from_ranks(self._rank_payload, data)

    def is_within_token_limit_bpe(self, data: bytes, token_limit: int) -> int | bool | None:
        return self._bridge.is_within_token_limit_bpe_from_ranks(
            self._rank_payload,
            data,
            token_limit,
        )

    def encode_bpe_file(self, path: Any) -> list[int] | None:
        return self._bridge.encode_bpe_file_from_ranks(self._rank_payload, path)

    def count_bpe_file(self, path: Any) -> int | None:
        return self._bridge.count_bpe_file_from_ranks(self._rank_payload, path)

    def is_within_token_limit_bpe_file(self, path: Any, token_limit: int) -> int | bool | None:
        return self._bridge.is_within_token_limit_bpe_file_from_ranks(
            self._rank_payload,
            path,
            token_limit,
        )

    def encode_bpe_ranges(
        self,
        data: bytes,
        ranges: list[tuple[int, int]],
    ) -> tuple[list[int], list[int]] | None:
        return self._bridge.encode_bpe_ranges_from_ranks(self._rank_payload, data, ranges)

    def count_bpe_ranges(self, data: bytes, ranges: list[tuple[int, int]]) -> int | None:
        return self._bridge.count_bpe_ranges_from_ranks(self._rank_payload, data, ranges)

    def encode_bpe_chunked_stitched(
        self,
        data: bytes,
        *,
        chunk_bytes: int,
        overlap_bytes: int,
    ) -> list[int] | None:
        return self._bridge.encode_bpe_chunked_stitched_from_ranks(
            self._rank_payload,
            data,
            chunk_bytes=chunk_bytes,
            overlap_bytes=overlap_bytes,
        )

    def encode_bpe_ascii_o200k(self, data: bytes) -> list[int] | None:
        return self._bridge.encode_bpe_ascii_o200k_from_ranks(self._rank_payload, data)

    def encode_bpe_ascii_o200k_text(self, text: str) -> list[int] | None:
        return self._bridge.encode_bpe_ascii_o200k_text_from_ranks(self._rank_payload, text)

    def count_bpe_ascii_o200k(self, data: bytes) -> int | None:
        return self._bridge.count_bpe_ascii_o200k_from_ranks(self._rank_payload, data)

    def count_bpe_ascii_o200k_text(self, text: str) -> int | None:
        return self._bridge.count_bpe_ascii_o200k_text_from_ranks(self._rank_payload, text)

    def encode_bpe_ascii_letter_space(self, data: bytes) -> list[int] | None:
        return self._bridge.encode_bpe_ascii_letter_space_from_ranks(self._rank_payload, data)

    def count_bpe_ascii_letter_space(self, data: bytes) -> int | None:
        return self._bridge.count_bpe_ascii_letter_space_from_ranks(self._rank_payload, data)

    def decode_bpe(self, tokens: list[int]) -> bytes | None:
        return self._bridge.decode_bpe_from_ranks(self._rank_payload, tokens)
